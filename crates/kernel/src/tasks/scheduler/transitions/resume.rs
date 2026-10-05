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
//! Failed dispatch resolves terminal bookkeeping in the registry.

use crate::tasks::{
    SchedulerOp, TaskStart, sched_counters,
    scheduler::{ResumeAction, Scheduler, lifecycle::SchedulerState},
    task_q::{TaskAttempt, TaskQ, WakeCondition},
    workers::WorkerResponse,
};
#[cfg(feature = "trace_events")]
use crate::trace_task_resume;
use moor_common::{
    model::TaskPermissions,
    tasks::{SchedulerError, SchedulerError::InputRequestNotFound, TaskId, WorkerError},
    util::Instant,
};
#[cfg(feature = "trace_events")]
use moor_compiler::to_literal;
use moor_var::{
    E_EXEC, E_INVARG, E_INVIND, E_PERM, E_QUOTA, E_TYPE, Error, List, Obj, SYSTEM_OBJECT, Var,
    v_bool_int, v_err, v_int,
};
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
        lc.task_q.wake_suspended_task(
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
            let sr =
                lc.task_q.suspended.remove_task(task_id).expect(
                    "wake selection retained the current suspension under the lifecycle lock",
                );
            let perfc = sched_counters();
            TaskQ::record_latency(
                &perfc.timers,
                SchedulerOp::TaskWakeSignalToDispatchStartLatency,
                signaled_at.instant(),
            );

            let return_value = match &sr.wake_condition {
                WakeCondition::Immediate(value) => value.clone().unwrap_or_else(|| v_int(0)),
                WakeCondition::TaskMessage(_) => {
                    List::from_iter(lc.task_q.drain_messages(task_id)).into()
                }
                WakeCondition::Checkpoint(_) => v_bool_int(true),
                _ => v_int(0),
            };

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
                    to_literal(&return_value),
                    sr.task.vm_host.max_ticks,
                    sr.task.vm_host.tick_count()
                );
            }

            if matches!(sr.wake_condition, WakeCondition::Retry(_)) {
                lc.task_q.wake_retry_suspended_task(
                    sr,
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                );
                continue;
            }
            if let Err(error) = lc.task_q.wake_suspended_task(
                sr,
                ResumeAction::Return(return_value),
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

        if let Err(e) = lc.task_q.wake_suspended_task(
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
        lc.task_q.resume_task(
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
        lc.task_q.resume_task(
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

#[cfg(test)]
mod tests;
