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

//! Conflict retry replaces a dispatch under the lifecycle lock.
//! The callback registers backoff. `TaskLifecycle::wake_retry_suspended_task` consumes that
//! continuation, restores its snapshot, and prepares the retry session before worker dispatch.

use crate::{
    config::Config,
    task_context::TaskGuard,
    tasks::{
        SchedulerOp, TaskNotification,
        registry::{
            LiveTaskRegistration, RegisteredSuspendedTask, RunningTask, RunningTaskPhase,
            SuspendedTask, TaskDispatch, TaskQ, WakeCondition,
        },
        sched_counters,
        scheduler::{
            Scheduler,
            lifecycle::{SchedulerState, TaskLifecycle},
        },
        task::Task,
        task_control::TaskControl,
        task_scheduler_client::TaskSchedulerClient,
        task_telemetry::TaskRunBaseline,
    },
    vm::builtins::BuiltinRegistry,
};
use flume::Sender;
use moor_common::{
    model::ConflictInfo,
    tasks::{
        SchedulerError,
        SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
        Session, TaskId,
    },
    util::{Deadline, Instant},
};
use moor_db::Database;
use rand::RngExt;
use std::{
    sync::{Arc, OnceLock},
    time::Duration,
};
use tracing::{debug, error, trace};

impl Scheduler {
    pub fn handle_task_conflict_retry(
        &self,
        task_id: TaskId,
        mut task: Box<Task>,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskConflictRetry);

        assert_eq!(task_id, task.task_id);
        let dispatch = TaskDispatch::new(task_id, task.control.clone());
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_current_dispatch(&dispatch)
            || lc.task_q.active[&task_id].phase != RunningTaskPhase::Running
        {
            return;
        }

        lc.discard_task_effects(task_id);

        // Make sure the old thread is dead.
        task.control.request_cancel();

        if lc.state != SchedulerState::Running {
            debug!(task_id, "Discarding transaction retry during shutdown");
            lc.task_q.remove_message_queue(task_id);
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }

        // Remove from active tasks to get session/result_sender
        let Some(old_tc) = lc.task_q.active.remove(&task_id) else {
            error!(
                task_id,
                "Task not found for retry suspension, ignoring -- consistency issue!"
            );
            return;
        };

        // If the number of retries has been exceeded, abort immediately
        let max_retries = self.server_options.load().max_task_retries;
        if task.retries >= max_retries {
            let task_origin = task.conflict_task_origin();
            let conflict = conflict_info
                .as_ref()
                .map(ToString::to_string)
                .unwrap_or_else(|| "details unavailable".to_string());
            error!(
                task_id,
                retries = task.retries,
                max_retries,
                task = %task_origin,
                boundary,
                %conflict,
                "Task retry limit exhausted; aborting task"
            );
            lc.task_q.send_task_result_direct(
                old_tc.registration,
                old_tc.result_sender,
                Err(TaskAbortedError),
            );
            return;
        }
        task.retries += 1;

        // Calculate backoff time: 10-50ms base, exponentially backed off
        let mut rng = rand::rng();
        let base_delay_ms = rng.random_range(10u64..=50u64);
        // Exponential backoff: base * 2^(retries-1)
        // Cap shift at 10 to prevent excessive delays (max multiplier 1024x)
        let shift = (task.retries as u32).saturating_sub(1).min(10);
        let delay_ms = base_delay_ms << shift;
        let wake_time = Deadline::from_now(Duration::from_millis(delay_ms)).instant();

        trace!(
            task_id,
            retries = task.retries,
            delay_ms,
            "Suspending task for retry backoff"
        );

        // Add to suspension queue with retry wake condition
        lc.task_q.suspended.add_task(
            WakeCondition::Retry(wake_time),
            task,
            old_tc.session,
            old_tc.result_sender,
            old_tc.registration,
        );
    }
}

impl TaskLifecycle {
    #[inline]
    pub(crate) fn wake_retry_suspended_task(
        &mut self,
        suspended_task: RegisteredSuspendedTask,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) {
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
        self.dispatch_retry_task(
            task,
            session,
            result_sender,
            scheduler,
            database,
            builtin_registry,
            config,
            registration,
        );
    }

    /// Wake a task that was suspended for retry backoff
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn dispatch_retry_task(
        &mut self,
        mut task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
        registration: LiveTaskRegistration,
    ) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::RetryTask);

        let task_id = task.task_id;

        // Restore the VM state from its last snapshot
        task.vm_host.restore_state(&task.retry_state);
        task.reclaim_program_cache();
        task.vm_host.reset_time();

        // Fork the session for the new attempt. This is the same task running again, not a new
        // one, so use `fork_retry`: a session accumulating output for a caller has to keep that
        // accumulator across the retry.
        let new_session = match session.fork_retry() {
            Ok(session) => session,
            Err(error) => {
                error!(task_id, ?error, "Could not create session for retry wakeup");
                self.task_q
                    .finish_failed_wakeup(registration, result_sender);
                return;
            }
        };

        // Complete fallible preparation before installing an active dispatch. No worker exists
        // yet to report these errors or remove a partially constructed active record.
        let world_state = match database.new_world_state() {
            Ok(ws) => ws,
            Err(error) => {
                error!(
                    task_id,
                    ?error,
                    "Could not start transaction for retry wakeup"
                );
                self.task_q
                    .finish_failed_wakeup(registration, result_sender);
                return;
            }
        };

        let control = Arc::new(TaskControl::new());
        task.control = control.clone();
        let run_baseline = Arc::new(OnceLock::new());

        let task_control = RunningTask {
            registration,
            effects: Default::default(),
            phase: RunningTaskPhase::Running,
            player: task.player(),
            control,
            session: new_session.clone(),
            result_sender,
            task_start: task.state.task_start().clone(),
            dispatched_at: Instant::now(),
            run_baseline: run_baseline.clone(),
            abort_error: None,
        };

        self.task_q.insert_active(task_id, task_control);

        let task_scheduler_client =
            TaskSchedulerClient::for_dispatch(task_id, scheduler.clone(), task.control.clone());
        let player = task.player();
        let wake_to_dispatch_started_at = Instant::now();
        let dispatch_started_at = Instant::now();
        self.task_q.thread_pool.spawn(move || {
            run_baseline.set(TaskRunBaseline::capture()).ok();
            let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let perfc = sched_counters();
                TaskQ::record_latency(
                    &perfc.timers,
                    SchedulerOp::TaskWakeToDispatchLatency,
                    wake_to_dispatch_started_at,
                );
                TaskQ::record_latency(
                    &perfc.timers,
                    SchedulerOp::TaskThreadHandoffLatency,
                    dispatch_started_at,
                );

                let _tx_guard = TaskGuard::new(
                    world_state,
                    task_scheduler_client.clone(),
                    task_id,
                    player,
                    new_session.clone(),
                );

                trace!(
                    ?task_id,
                    retries = task.retries,
                    "Waking retry task from suspension"
                );
                Task::run_task_loop(
                    task,
                    &task_scheduler_client,
                    new_session,
                    builtin_registry,
                    config,
                );
            }));

            if let Err(panic_payload) = panic_result {
                let panic_msg = if let Some(s) = panic_payload.downcast_ref::<&str>() {
                    s.to_string()
                } else if let Some(s) = panic_payload.downcast_ref::<String>() {
                    s.clone()
                } else {
                    "Task panicked with unknown payload".to_string()
                };

                let backtrace = std::backtrace::Backtrace::capture();
                error!(
                    task_id,
                    ?player,
                    panic_msg,
                    ?backtrace,
                    "Retry task thread panicked"
                );

                task_scheduler_client.abort_panicked(panic_msg, backtrace);
            }
        });
    }
}
