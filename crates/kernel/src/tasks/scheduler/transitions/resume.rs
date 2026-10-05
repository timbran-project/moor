// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Wake selection and resumption for timers, input, explicit requests, and worker responses.
//!
//! These methods acquire the lifecycle lock and transfer registered continuations into dispatch.
//! Timer selection queues generation-tagged signals while continuations remain registered.
//! Each signal is consumed under a fresh lifecycle lock after shutdown and GC admission checks.
//! `TaskLifecycle::wake_suspended_task` borrows the locked state and calls shared dispatch
//! preparation. It retains direct responses in suspension while sweep blocks admission. The
//! registered continuation owns the return value or error until dispatch or explicit cancellation.
//! Failed dispatch resolves terminal bookkeeping in the registry.

#[cfg(feature = "trace_events")]
use crate::trace_task_resume;
use crate::{
    config::Config,
    tasks::{
        SchedulerOp, TaskStart,
        registry::{RegisteredSuspendedTask, SuspendedTask, TaskAttempt, TaskQ, WakeCondition},
        sched_counters,
        scheduler::{
            ResumeAction, Scheduler,
            lifecycle::{SchedulerState, TaskLifecycle},
        },
        workers::WorkerResponse,
    },
    vm::builtins::BuiltinRegistry,
};
use moor_common::{
    model::TaskPermissions,
    tasks::{SchedulerError, SchedulerError::InputRequestNotFound, TaskId, WorkerError},
    util::Instant,
};
#[cfg(feature = "trace_events")]
use moor_compiler::to_literal;
use moor_db::Database;
use moor_var::{
    E_EXEC, E_INVARG, E_INVIND, E_PERM, E_QUOTA, E_TYPE, Error, List, Obj, SYSTEM_OBJECT, Var,
    v_bool_int, v_err, v_int,
};
use std::sync::Arc;
use tracing::{error, warn};
use uuid::Uuid;

impl Scheduler {
    pub(crate) fn submit_task_input_inner(
        &self,
        connection: Obj,
        player: Obj,
        input_request_id: Uuid,
        input: Var,
    ) -> Result<(), SchedulerError> {
        let mut lc = self.lifecycle.lock();

        // Validate that the given input request is valid, and if so, resume the task, sending it
        // the given input, clearing the input request out.

        // Find the task that requested this input, if any
        let Some(sr) =
            lc.task_q
                .suspended
                .pull_task_for_input(input_request_id, &connection, &player)
        else {
            warn!(?input_request_id, "Input request not found");
            return Err(InputRequestNotFound(input_request_id.as_u128()));
        };

        // Wake and bake.
        lc.wake_suspended_task(
            sr,
            ResumeAction::Return(input),
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        )
    }

    /// Select expired timers, retaining their continuations in the suspension registry.
    /// The common wake queue checks admission and registration generation at dispatch.
    pub(in crate::tasks::scheduler) fn collect_and_wake_expired_tasks(&self) {
        self.lifecycle
            .lock()
            .task_q
            .suspended
            .enqueue_expired_wakes(Instant::now());
        self.drain_immediate_wakes();
    }

    /// Consume wake signals one at a time. The continuation remains visible to GC and shutdown
    /// until admission succeeds under the same lifecycle lock as dispatch preparation.
    pub(crate) fn drain_immediate_wakes(&self) {
        loop {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running || lc.gc_phase.blocks_admission() {
                return;
            }
            let Some((task_id, signaled_at)) = lc.task_q.suspended.pop_immediate_wake() else {
                return;
            };
            let mut sr =
                lc.task_q.suspended.remove_task(task_id).expect(
                    "wake selection retained the current suspension under the lifecycle lock",
                );
            let perfc = sched_counters();
            TaskQ::record_latency(
                &perfc.timers,
                SchedulerOp::TaskWakeSignalToDispatchStartLatency,
                signaled_at.instant(),
            );

            let resume_action = sr.pending_resume.take().unwrap_or_else(|| {
                ResumeAction::Return(match &sr.wake_condition {
                    WakeCondition::Immediate(value) => value.clone().unwrap_or_else(|| v_int(0)),
                    WakeCondition::TaskMessage(_) => {
                        List::from_iter(lc.task_q.drain_messages(task_id)).into()
                    }
                    WakeCondition::Checkpoint(_) => v_bool_int(true),
                    _ => v_int(0),
                })
            });

            #[cfg(feature = "trace_events")]
            {
                let (wake_condition, wake_reason) = match &sr.wake_condition {
                    WakeCondition::Time(_) => ("Time", "Timer expired"),
                    WakeCondition::Input(_) => ("Input", "Input request fulfilled"),
                    WakeCondition::Task(_) => ("Task", "Dependency task completed"),
                    WakeCondition::Immediate(_) => ("Immediate", "Immediate wake"),
                    WakeCondition::Worker(_) => ("Worker", "Worker response received"),
                    WakeCondition::GCComplete => ("GCComplete", "Garbage collection completed"),
                    WakeCondition::Never => ("Never", "Manual wake"),
                    WakeCondition::Retry(_) => ("Retry", "Transaction retry backoff"),
                    WakeCondition::TaskMessage(_) => ("TaskMessage", "Message received or timeout"),
                    WakeCondition::Checkpoint(_) => ("Checkpoint", "Checkpoint completed"),
                    WakeCondition::StorageCompaction(_) => {
                        ("StorageCompaction", "Storage compaction completed")
                    }
                };
                trace_task_resume!(
                    task_id,
                    wake_condition,
                    wake_reason,
                    match &resume_action {
                        ResumeAction::Return(value) => to_literal(value),
                        ResumeAction::Raise(error) => error.to_string(),
                    },
                    sr.task.vm_host.max_ticks,
                    sr.task.vm_host.tick_count()
                );
            }

            if matches!(sr.wake_condition, WakeCondition::Retry(_)) {
                lc.wake_retry_suspended_task(
                    sr,
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                );
                continue;
            }
            if let Err(error) = lc.wake_suspended_task(
                sr,
                resume_action,
                self,
                self.database.as_ref(),
                self.builtin_registry.clone(),
                self.config.clone(),
            ) {
                error!(?task_id, ?error, "Error resuming task");
            }
        }
    }

    /// Handles a response from a worker task and resumes the suspended task.
    ///
    /// Converts worker responses (errors or successful responses) into appropriate
    /// resume actions, finds the suspended task associated with the request ID,
    /// and wakes it with the result. Handles error mapping from WorkerError to
    /// MOO error types and records trace events when enabled.
    ///
    /// # Arguments
    /// * `worker_response` - The response from a worker task containing either
    ///   an error or a successful result value
    ///
    /// # Notes
    /// If the suspended task is not found (e.g., was killed or expired), a warning
    /// is logged and the response is discarded.
    pub(crate) fn handle_worker_response(&self, worker_response: WorkerResponse) {
        let (request_id, resume_action) = match worker_response {
            WorkerResponse::Error { request_id, error } => {
                let err_msg = error.to_string();
                let err = match error {
                    WorkerError::PermissionDenied(_) => E_PERM.msg(err_msg),
                    WorkerError::NoWorkerAvailable(_) => E_TYPE.msg(err_msg),
                    WorkerError::InvalidRequest(_) => E_INVARG.msg(err_msg),
                    WorkerError::InternalError(_) => E_EXEC.msg(err_msg),
                    WorkerError::RequestTimedOut(_) => E_QUOTA.msg(err_msg),
                    WorkerError::RequestError(_) => E_INVARG.msg(err_msg),
                    WorkerError::WorkerDetached(_) => E_EXEC.msg(err_msg),
                };
                (request_id, ResumeAction::Raise(err))
            }
            WorkerResponse::Response {
                request_id,
                response,
            } => (request_id, ResumeAction::Return(response)),
        };

        let mut lc = self.lifecycle.lock();

        // Find the suspended task for this request.
        let task = lc.task_q.suspended.pull_task_for_worker(request_id);

        // Find the task that requested this input, if any
        let Some(sr) = task else {
            warn!(?request_id, "Task for worker request not found; expired?");
            return;
        };

        #[cfg(feature = "trace_events")]
        {
            let task_id = sr.task.task_id;
            let max_ticks = sr.task.vm_host.max_ticks;
            let tick_count = sr.task.vm_host.tick_count();

            let (return_value_str, wake_reason) = match &resume_action {
                ResumeAction::Return(v) => (to_literal(v), "Worker response"),
                ResumeAction::Raise(e) => (e.to_string(), "Worker error"),
            };

            trace_task_resume!(
                task_id,
                "Worker",
                wake_reason,
                return_value_str,
                max_ticks,
                tick_count
            );
        }

        if let Err(e) = lc.wake_suspended_task(
            sr,
            resume_action,
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        ) {
            error!("Failure to resume task after worker response: {:?}", e);
        }
    }

    pub fn handle_resume_task(
        &self,
        task_id: TaskId,
        queued_task_id: TaskId,
        sender_authority: TaskPermissions,
        return_value: Var,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        lc.resume_task(
            task_id,
            queued_task_id,
            sender_authority,
            return_value,
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        )
    }

    pub(crate) fn handle_resume_task_for_attempt(
        &self,
        attempt: &TaskAttempt,
        queued_task_id: TaskId,
        sender_authority: TaskPermissions,
        return_value: Var,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_attempt(attempt) {
            return v_err(E_INVARG);
        }
        let task_id = attempt.task_id();
        lc.resume_task(
            task_id,
            queued_task_id,
            sender_authority,
            return_value,
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        )
    }

    pub fn handle_force_input(
        &self,
        task_id: TaskId,
        who: Obj,
        line: String,
    ) -> Result<TaskId, Error> {
        let Some(attempt) = self.capture_task_attempt(task_id) else {
            return Err(E_INVIND.msg("Task not found"));
        };
        self.handle_force_input_for_attempt(&attempt, who, line)
    }

    pub(crate) fn handle_force_input_for_attempt(
        &self,
        attempt: &TaskAttempt,
        who: Obj,
        line: String,
    ) -> Result<TaskId, Error> {
        let task_id = attempt.task_id();
        let mut lc = self.lifecycle.lock();

        let new_session = {
            let Some(task) = lc.task_q.running_attempt_mut(attempt) else {
                warn!(task_id, "Task not found for force input request");
                return Err(E_INVIND.msg("Task not found"));
            };
            task.session.clone().fork().unwrap()
        };
        let task_start = TaskStart::StartCommandVerb {
            handler_object: SYSTEM_OBJECT,
            player: who,
            command: line,
        };

        let new_task_id = lc.next_task_id;
        lc.next_task_id += 1;
        let result = self.submit_task(
            &mut lc,
            new_task_id,
            &who,
            &who,
            task_start,
            None,
            new_session,
        );
        match result {
            Err(e) => {
                error!(?e, "Could not start task thread");
                Err(E_INVIND.with_msg(|| format!("Could not start thread for force_input: {e:?}")))
            }
            Ok(th) => Ok(th.0),
        }
    }
}

impl TaskLifecycle {
    /// Settle a continuation that was accepted for dispatch but cannot start during shutdown.
    pub(in crate::tasks::scheduler) fn cancel_undispatched_task(
        &mut self,
        task: RegisteredSuspendedTask,
    ) {
        let task_id = task.task.task_id;
        task.task.control.request_cancel();
        self.task_q.remove_message_queue(task_id);
        self.task_q.suspended.enqueue_dependents_for(task_id);
        self.task_q.send_task_result_direct(
            task.registration,
            task.record.result_sender,
            Err(SchedulerError::TaskAbortedCancelled),
        );
    }

    pub(in crate::tasks::scheduler) fn cancel_pending_resumes(
        &mut self,
        shutdown_message: &Option<String>,
    ) {
        for id in self.task_q.suspended.pending_resume_ids() {
            let task = self
                .task_q
                .suspended
                .remove_task(id)
                .expect("pending resume is registered");
            let _ = task.session.notify_shutdown(shutdown_message.clone());
            self.cancel_undispatched_task(task);
        }
    }

    /// Accept a response under the lifecycle lock. During sweep, retain it without starting a
    /// transaction or waiting on GC. Shutdown settles it; open admission dispatches immediately.
    #[inline]
    pub(crate) fn wake_suspended_task(
        &mut self,
        suspended_task: RegisteredSuspendedTask,
        resume_action: ResumeAction,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) -> Result<(), SchedulerError> {
        if self.state != SchedulerState::Running {
            self.cancel_undispatched_task(suspended_task);
            return Err(SchedulerError::SchedulerNotResponding);
        }
        if self.gc_phase.blocks_admission() {
            self.task_q
                .suspended
                .defer_resume(suspended_task, resume_action);
            return Ok(());
        }
        let RegisteredSuspendedTask {
            record,
            registration,
            pending_resume: _,
        } = suspended_task;
        let SuspendedTask {
            task,
            session,
            result_sender,
            ..
        } = record;
        self.dispatch_task(
            task,
            resume_action,
            session,
            result_sender,
            scheduler,
            database,
            builtin_registry,
            config,
            registration,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn resume_task(
        &mut self,
        requesting_task_id: TaskId,
        queued_task_id: TaskId,
        sender_authority: TaskPermissions,
        return_value: Var,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) -> Var {
        if requesting_task_id == queued_task_id {
            error!(
                task = requesting_task_id,
                "Task requested to resume itself. Ignoring"
            );
            return v_err(E_INVARG);
        }

        if let Err(error) = self
            .task_q
            .require_resume_authority(queued_task_id, sender_authority)
        {
            return v_err(error);
        }

        // A response already accepted during sweep cannot be replaced by another resume call.
        if self.task_q.suspended.has_pending_resume(queued_task_id) {
            return v_err(E_INVARG);
        }
        let sr = self.task_q.suspended.remove_task(queued_task_id).unwrap();

        if self
            .wake_suspended_task(
                sr,
                ResumeAction::Return(return_value),
                scheduler,
                database,
                builtin_registry,
                config,
            )
            .is_err()
        {
            error!(task = queued_task_id, "Could not resume task");
            return v_err(E_INVARG);
        }
        v_bool_int(false)
    }
}

#[cfg(test)]
mod tests;
