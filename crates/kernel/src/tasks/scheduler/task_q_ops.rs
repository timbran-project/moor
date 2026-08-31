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

use super::*;

/// Result of submitting a new task - either already suspended (delayed/GC-blocked)
/// or needs immediate wake by the caller.
pub(super) enum TaskSubmission {
    /// Task is suspended with a delay or waiting for GC - no further action needed
    Suspended(TaskHandle),
    /// Task should start immediately - caller must wake it
    NeedsWake {
        handle: TaskHandle,
        task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
    },
}

impl TaskQ {
    #[inline]
    fn authority_may_kill_task(
        &self,
        task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Result<bool, ErrorCode> {
        if self.suspended.tasks.contains_key(&task_id) {
            if sender_authority.is_wizard()
                || self.suspended.authority_principal_controls_task(
                    task_id,
                    sender_authority.principal(),
                    true,
                )
            {
                return Ok(true);
            }
            return Err(E_PERM);
        }

        let Some(tc) = self.active.get(&task_id) else {
            return Err(E_INVARG);
        };

        if sender_authority.controls(&tc.player) {
            return Ok(false);
        }

        Err(E_PERM)
    }

    #[inline]
    fn require_resume_authority(
        &self,
        task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Result<(), ErrorCode> {
        if self.suspended.authority_principal_controls_task(
            task_id,
            sender_authority.principal(),
            false,
        ) {
            return Ok(());
        }

        if !sender_authority.is_wizard() {
            return Err(E_PERM);
        }

        if !self.suspended.tasks.contains_key(&task_id) {
            error!(task = task_id, "Task not found for resume request");
            return Err(E_INVARG);
        }

        Ok(())
    }

    #[inline]
    pub(super) fn require_task_send_authority(
        &self,
        target_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Result<(), ErrorCode> {
        let Some(owner) = self.task_owner(target_task_id) else {
            return Err(E_INVARG);
        };

        if sender_authority.controls(&owner) {
            return Ok(());
        }

        Err(E_PERM)
    }

    #[inline]
    pub(super) fn record_latency(
        timers: &LabeledSampledTimer<SchedulerOp>,
        op: SchedulerOp,
        started_at: Instant,
    ) {
        timers.record_elapsed(op, started_at.elapsed());
    }

    #[inline]
    pub(super) fn wake_suspended_task(
        &mut self,
        suspended_task: SuspendedTask,
        resume_action: ResumeAction,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) -> Result<(), SchedulerError> {
        let SuspendedTask {
            task,
            session,
            result_sender,
            ..
        } = suspended_task;
        let task_id = task.task_id;
        let result = self.wake_task_thread(
            task,
            resume_action,
            session,
            result_sender,
            scheduler,
            database,
            builtin_registry,
            config,
        );
        if result.is_err() {
            self.live_tasks.remove(task_id);
        }
        result
    }

    #[inline]
    pub(super) fn wake_retry_suspended_task(
        &mut self,
        suspended_task: SuspendedTask,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) {
        let SuspendedTask {
            task,
            session,
            result_sender,
            ..
        } = suspended_task;
        self.wake_retry_task(
            task,
            session,
            result_sender,
            scheduler,
            database,
            builtin_registry,
            config,
        );
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn submit_new_task(
        &mut self,
        task_id: TaskId,
        player: &Obj,
        authority_principal: &Obj,
        task_start: TaskStart,
        delay_start: Option<Duration>,
        session: Arc<dyn Session>,
        server_options: &ServerOptions,
        gc_in_progress: bool,
    ) -> TaskSubmission {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::StartTask);
        let (sender, receiver) = flume::unbounded();

        let control = Arc::new(TaskControl::new());
        let task = Task::new(
            task_id,
            *player,
            *authority_principal,
            task_start.clone(),
            server_options,
            control.clone(),
        );
        self.register_task(task_id);

        let handle = TaskHandle(task_id, receiver);

        // Delayed tasks go into suspension
        if let Some(delay) = delay_start {
            self.suspended.add_task(
                WakeCondition::Time(Deadline::from_now(delay).instant()),
                task,
                session,
                Some(sender),
            );
            return TaskSubmission::Suspended(handle);
        }

        // GC-blocked tasks go into suspension
        if gc_in_progress {
            self.suspended
                .add_task(WakeCondition::GCComplete, task, session, Some(sender));
            return TaskSubmission::Suspended(handle);
        }

        // Immediate start - return task directly, skip suspension queue entirely
        TaskSubmission::NeedsWake {
            handle,
            task,
            session,
            result_sender: Some(sender),
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn wake_task_thread(
        &mut self,
        mut task: Box<Task>,
        resume_action: ResumeAction,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) -> Result<(), SchedulerError> {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::ResumeTask);

        // Start its new transaction...
        let world_state = match database.new_world_state() {
            Ok(ws) => ws,
            Err(e) => {
                error!(error = ?e, "Could not start transaction for task resumption due to DB error");
                return Err(SchedulerError::CouldNotStartTask);
            }
        };

        let task_id = task.task_id;
        let player = task.player();

        let control = Arc::new(TaskControl::new());
        task.control = control.clone();
        let run_baseline = Arc::new(OnceLock::new());
        let task_control = RunningTask {
            phase: RunningTaskPhase::Running,
            player,
            control,
            session: session.clone(),
            result_sender,
            task_start: task.state.task_start().clone(),
            dispatched_at: Instant::now(),
            run_baseline: run_baseline.clone(),
            abort_error: None,
            terminal_result: None,
        };

        self.insert_active(task_id, task_control);

        let scheduler_clone = scheduler.clone();
        let task_scheduler_client = TaskSchedulerClient::new(task_id, scheduler.clone());

        // Check if this is a brand new task or a resuming task
        let is_created = matches!(task.state, crate::tasks::task::TaskState::Pending(_));

        let wake_to_dispatch_started_at = Instant::now();
        let dispatch_started_at = Instant::now();
        self.thread_pool.spawn(move || {
            run_baseline.set(TaskRunBaseline::capture()).ok();
            let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let perfc = sched_counters();
                Self::record_latency(
                    &perfc.timers,
                    SchedulerOp::TaskWakeToDispatchLatency,
                    wake_to_dispatch_started_at,
                );
                Self::record_latency(
                    &perfc.timers,
                    SchedulerOp::TaskThreadHandoffLatency,
                    dispatch_started_at,
                );

                if is_created {
                    Self::record_latency(
                        &perfc.timers,
                        SchedulerOp::TaskSubmitToFirstRunLatency,
                        task.creation_time,
                    );
                }

                // Set up transaction context for this thread
                let _tx_guard = TaskGuard::new(
                    world_state,
                    task_scheduler_client.clone(),
                    task_id,
                    player,
                    session.clone(),
                );

                if is_created {
                    // Brand new task - call setup_task_start and transition to Running
                    let setup_success = task.setup_task_start(&task_scheduler_client, &config);
                    if !setup_success {
                        // Setup failed (e.g., verb not found)
                        return;
                    }

                    // Transition to Running state
                    if let crate::tasks::task::TaskState::Pending(start) = &task.state {
                        task.state = crate::tasks::task::TaskState::Prepared(start.clone());
                    }

                    task.retry_state = task.vm_host.vm_exec_state().clone();
                } else {
                    // Resuming an existing task - handle the resume action
                    task.reclaim_program_cache();
                    match resume_action {
                        ResumeAction::Return(value) => {
                            task.vm_host.resume_execution(value);
                        }
                        ResumeAction::Raise(error) => {
                            task.vm_host.resume_with_error(error);
                        }
                    }
                }

                Task::run_task_loop(
                    task,
                    &task_scheduler_client,
                    session,
                    builtin_registry,
                    config,
                );
            }));

            if let Err(panic_payload) = panic_result {
                // Task thread panicked - extract panic message and log it
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
                    "Task thread panicked"
                );

                // Send panic abort directly to scheduler
                scheduler_clone.handle_task_abort_panicked(task_id, panic_msg, backtrace);
            }
        });

        Ok(())
    }

    pub(super) fn send_task_result(
        &mut self,
        task_id: TaskId,
        result: Result<Var, SchedulerError>,
    ) {
        let Some(mut task_control) = self.active.remove(&task_id) else {
            self.live_tasks.remove(task_id);
            warn!(task_id, "Task not found for notification, ignoring");
            return;
        };
        self.suspended.enqueue_dependents_for(task_id);
        let result_sender = task_control.result_sender.take();
        self.send_task_result_direct(task_id, result_sender, result);
    }

    pub(super) fn send_reserved_task_result(&mut self, task_id: TaskId) {
        let Some(task) = self.active.get_mut(&task_id) else {
            warn!(
                task_id,
                "Task not found for reserved notification, ignoring"
            );
            return;
        };
        let Some(result) = task.terminal_result.take() else {
            warn!(task_id, "Task has no reserved terminal result, ignoring");
            return;
        };
        let result = match result {
            Ok(TaskNotification::Result(value)) => Ok(value),
            Ok(TaskNotification::Suspended) => {
                warn!(task_id, "Suspension cannot be a terminal task result");
                return;
            }
            Err(error) => Err(error),
        };
        self.send_task_result(task_id, result);
    }

    /// Send task result directly with an explicit result_sender (for tasks not in active queue)
    pub(super) fn send_task_result_direct(
        &self,
        task_id: TaskId,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        result: Result<Var, SchedulerError>,
    ) {
        self.live_tasks.remove(task_id);
        let Some(result_sender) = result_sender else {
            warn!(
                task_id,
                "Task not found for (direct) notification, ignoring"
            );
            return;
        };
        let result = result.map(|v| TaskNotification::Result(v.clone()));
        result_sender.send((task_id, result)).ok();
    }

    /// Wake a task that was suspended for retry backoff
    #[allow(clippy::too_many_arguments)]
    pub(super) fn wake_retry_task(
        &mut self,
        mut task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        scheduler: &Scheduler,
        database: &dyn Database,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
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
        let new_session = session.fork_retry().unwrap();

        let control = Arc::new(TaskControl::new());
        task.control = control.clone();
        let run_baseline = Arc::new(OnceLock::new());

        let task_control = RunningTask {
            phase: RunningTaskPhase::Running,
            player: task.player(),
            control,
            session: new_session.clone(),
            result_sender,
            task_start: task.state.task_start().clone(),
            dispatched_at: Instant::now(),
            run_baseline: run_baseline.clone(),
            abort_error: None,
            terminal_result: None,
        };

        self.insert_active(task_id, task_control);

        let scheduler_clone = scheduler.clone();

        let world_state = match database.new_world_state() {
            Ok(ws) => ws,
            Err(e) => {
                panic!("Could not start transaction for retry wake task due to DB error: {e:?}");
            }
        };
        let task_scheduler_client = TaskSchedulerClient::new(task_id, scheduler.clone());
        let player = task.player();
        let wake_to_dispatch_started_at = Instant::now();
        let dispatch_started_at = Instant::now();
        self.thread_pool.spawn(move || {
            run_baseline.set(TaskRunBaseline::capture()).ok();
            let panic_result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let perfc = sched_counters();
                Self::record_latency(
                    &perfc.timers,
                    SchedulerOp::TaskWakeToDispatchLatency,
                    wake_to_dispatch_started_at,
                );
                Self::record_latency(
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

                scheduler_clone.handle_task_abort_panicked(task_id, panic_msg, backtrace);
            }
        });
    }

    /// Take a task out of the queues and stop it running. Returns false if the task was not
    /// found. This does no permission check, so anything reachable from the world must check
    /// authority first.
    fn cancel_task(&mut self, victim_task_id: TaskId, is_suspended: bool) -> bool {
        if is_suspended {
            return self
                .suspended
                .remove_task_terminal(victim_task_id)
                .is_some();
        }

        let Some(task) = self.active.get(&victim_task_id) else {
            return false;
        };
        if task.control.request_cancel() != CancelResult::Cancelled {
            return true;
        }

        self.active.remove(&victim_task_id);
        self.live_tasks.remove(victim_task_id);
        self.suspended.enqueue_dependents_for(victim_task_id);
        true
    }

    pub(super) fn kill_task(
        &mut self,
        victim_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Var {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = match self.authority_may_kill_task(victim_task_id, sender_authority) {
            Ok(is_suspended) => is_suspended,
            Err(error) => return v_err(error),
        };

        if !self.cancel_task(victim_task_id, is_suspended) {
            if !is_suspended {
                return v_err(E_INVARG);
            }
            error!(
                task = victim_task_id,
                "Task not found in suspended list for kill request"
            );
        }
        v_bool_int(false)
    }

    /// Cancel a task the server itself started, with no permission check. Used when whatever
    /// was waiting for the task's result has given up on it.
    pub(super) fn abort_task(&mut self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = self.suspended.tasks.contains_key(&victim_task_id);
        if is_suspended {
            return if self.cancel_task(victim_task_id, true) {
                AbortTaskOutcome::Cancelled
            } else {
                AbortTaskOutcome::NotFound
            };
        }

        let Some(task) = self.active.get(&victim_task_id) else {
            return AbortTaskOutcome::NotFound;
        };

        match task.control.request_cancel() {
            CancelResult::Completing => AbortTaskOutcome::Completing,
            CancelResult::AfterBoundary => AbortTaskOutcome::Cancelled,
            CancelResult::Cancelled => {
                self.active.remove(&victim_task_id);
                self.live_tasks.remove(victim_task_id);
                self.suspended.enqueue_dependents_for(victim_task_id);
                AbortTaskOutcome::Cancelled
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn resume_task(
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

        if let Err(error) = self.require_resume_authority(queued_task_id, sender_authority) {
            return v_err(error);
        }

        let sr = self.suspended.remove_task(queued_task_id).unwrap();

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

    pub(super) fn disconnect_task(&mut self, disconnect_task_id: TaskId, player: &Obj) {
        let Some(task) = self.active.get_mut(&disconnect_task_id) else {
            warn!(task = disconnect_task_id, "Disconnecting task not found");
            return;
        };
        warn!(?player, ?disconnect_task_id, "Disconnecting player");
        if let Err(e) = task.session.disconnect(*player) {
            warn!(?player, ?disconnect_task_id, error = ?e, "Could not disconnect player's session");
            return;
        }

        for (task_id, tc) in self.active.iter() {
            if *task_id == disconnect_task_id {
                continue;
            }
            if tc.player.eq(player) {
                continue;
            }
            warn!(
                ?player,
                task_id, "Aborting task from disconnected player..."
            );
            tc.control.request_cancel();
        }
        self.suspended.prune_foreground_tasks(player);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tasks::{
        DEFAULT_MAX_TASK_MAILBOX, DEFAULT_MAX_TASK_RETRIES, NoopTasksDb, ServerOptions,
    };
    use moor_common::{model::ObjFlag, tasks::NoopClientSession, util::BitEnum};
    use uuid::Uuid;

    fn test_server_options() -> ServerOptions {
        ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            rollback_on_task_limit: false,
        }
    }

    fn authority(principal: i32, flags: BitEnum<ObjFlag>) -> TaskPermissions {
        TaskPermissions::new(Obj::mk_id(principal), flags)
    }

    fn task_q() -> TaskQ {
        TaskQ::new(SuspensionQ::new(Box::new(NoopTasksDb {})))
    }

    fn session() -> Arc<dyn Session> {
        Arc::new(NoopClientSession::new())
    }

    fn task(task_id: TaskId, player: Obj, authority_principal: Obj) -> Box<Task> {
        Task::new(
            task_id,
            player,
            authority_principal,
            TaskStart::StartEval {
                player,
                program: Default::default(),
                initial_env: None,
            },
            &test_server_options(),
            Arc::new(TaskControl::new()),
        )
    }

    fn add_suspended_task(
        task_q: &mut TaskQ,
        task_id: TaskId,
        player: Obj,
        authority_principal: Obj,
    ) {
        task_q.register_task(task_id);
        task_q.suspended.add_task(
            WakeCondition::Never,
            task(task_id, player, authority_principal),
            session(),
            None,
        );
    }

    fn add_input_suspended_task(
        task_q: &mut TaskQ,
        task_id: TaskId,
        player: Obj,
        authority_principal: Obj,
    ) {
        task_q.register_task(task_id);
        task_q.suspended.add_task(
            WakeCondition::Input(Uuid::new_v4()),
            task(task_id, player, authority_principal),
            session(),
            None,
        );
    }

    fn add_active_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj) {
        task_q.register_task(task_id);
        task_q.insert_active(
            task_id,
            RunningTask {
                phase: RunningTaskPhase::Running,
                player,
                task_start: TaskStart::StartEval {
                    player,
                    program: Default::default(),
                    initial_env: None,
                },
                control: Arc::new(TaskControl::new()),
                session: session(),
                result_sender: None,
                dispatched_at: Instant::now(),
                run_baseline: Arc::new(OnceLock::new()),
                abort_error: None,
                terminal_result: None,
            },
        );
    }

    #[test]
    fn kill_authority_matches_suspended_task_permissions_or_wizard() {
        let mut task_q = task_q();
        let player = Obj::mk_id(2);
        let authority_principal = Obj::mk_id(3);
        add_suspended_task(&mut task_q, 10, player, authority_principal);

        assert_eq!(
            task_q.authority_may_kill_task(10, authority(3, BitEnum::new())),
            Ok(true)
        );
        assert_eq!(
            task_q.authority_may_kill_task(10, authority(4, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q.authority_may_kill_task(10, authority(4, BitEnum::new_with(ObjFlag::Wizard))),
            Ok(true)
        );
    }

    #[test]
    fn kill_authority_controls_active_task_player() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));

        assert_eq!(
            task_q.authority_may_kill_task(10, authority(2, BitEnum::new())),
            Ok(false)
        );
        assert_eq!(
            task_q.authority_may_kill_task(10, authority(3, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q.authority_may_kill_task(99, authority(1, BitEnum::new())),
            Err(E_INVARG)
        );
    }

    #[test]
    fn abort_task_kills_an_active_task_without_permission_check() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        let control = task_q.active[&10].control.clone();

        assert!(matches!(task_q.abort_task(10), AbortTaskOutcome::Cancelled));

        assert!(control.is_cancelled());
        assert!(!task_q.live_tasks.contains(10));
        assert!(!task_q.active.contains_key(&10));
    }

    #[test]
    fn abort_task_removes_a_suspended_task() {
        let mut task_q = task_q();
        add_suspended_task(&mut task_q, 10, Obj::mk_id(2), Obj::mk_id(3));

        assert!(matches!(task_q.abort_task(10), AbortTaskOutcome::Cancelled));

        assert!(!task_q.live_tasks.contains(10));
        assert!(!task_q.suspended.tasks.contains_key(&10));
    }

    #[test]
    fn abort_task_reports_an_unknown_task() {
        let mut task_q = task_q();

        assert!(matches!(task_q.abort_task(10), AbortTaskOutcome::NotFound));
    }

    #[test]
    fn abort_task_waits_for_session_finalization() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        let task = task_q.active.get_mut(&10).unwrap();
        task.phase = RunningTaskPhase::Completing;
        task.terminal_result = Some(Ok(TaskNotification::Result(v_int(42))));
        assert!(task.control.begin_terminal_commit());
        assert!(task.control.finish_terminal_commit(true));

        assert!(matches!(
            task_q.abort_task(10),
            AbortTaskOutcome::Completing
        ));
        assert!(task_q.active.contains_key(&10));
        assert!(!task_q.active[&10].control.is_cancelled());
    }

    #[test]
    fn abort_task_leaves_boundary_commit_attached_for_cleanup() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        let control = task_q.active[&10].control.clone();
        assert!(control.begin_boundary_commit());

        assert!(matches!(task_q.abort_task(10), AbortTaskOutcome::Cancelled));
        assert!(task_q.active.contains_key(&10));
        assert!(!control.finish_boundary_commit());
    }

    #[test]
    fn abort_task_waits_for_terminal_database_commit() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        let control = task_q.active[&10].control.clone();
        assert!(control.begin_terminal_commit());

        assert!(matches!(
            task_q.abort_task(10),
            AbortTaskOutcome::Completing
        ));
        assert!(task_q.active.contains_key(&10));
        assert!(control.finish_terminal_commit(true));
    }

    #[test]
    fn live_task_membership_ends_with_active_completion() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        assert!(task_q.live_tasks.contains(10));

        task_q.send_task_result(10, Ok(v_int(0)));

        assert!(!task_q.live_tasks.contains(10));
    }

    #[test]
    fn live_task_membership_survives_suspension_moves() {
        let mut task_q = task_q();
        add_suspended_task(&mut task_q, 10, Obj::mk_id(2), Obj::mk_id(3));
        assert!(task_q.live_tasks.contains(10));

        let suspended = task_q
            .suspended
            .remove_task(10)
            .expect("suspended task should exist");
        assert!(task_q.live_tasks.contains(10));

        task_q.suspended.add_task(
            WakeCondition::Never,
            suspended.task,
            suspended.session,
            suspended.result_sender,
        );
        task_q.suspended.remove_task_terminal(10);
        assert!(!task_q.live_tasks.contains(10));
    }

    #[test]
    fn resume_authority_filters_input_tasks_for_non_wizards() {
        let mut task_q = task_q();
        let player = Obj::mk_id(2);
        let authority_principal = Obj::mk_id(3);
        add_input_suspended_task(&mut task_q, 10, player, authority_principal);

        assert_eq!(
            task_q.require_resume_authority(10, authority(2, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q.require_resume_authority(10, authority(3, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q.require_resume_authority(10, authority(1, BitEnum::new_with(ObjFlag::Wizard))),
            Ok(())
        );
    }

    #[test]
    fn resume_authority_reports_missing_task_for_wizard() {
        let task_q = task_q();

        assert_eq!(
            task_q.require_resume_authority(10, authority(1, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q.require_resume_authority(10, authority(1, BitEnum::new_with(ObjFlag::Wizard))),
            Err(E_INVARG)
        );
    }

    #[test]
    fn task_send_authority_controls_target_task_owner() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));

        assert_eq!(
            task_q.require_task_send_authority(10, authority(2, BitEnum::new())),
            Ok(())
        );
        assert_eq!(
            task_q.require_task_send_authority(10, authority(3, BitEnum::new())),
            Err(E_PERM)
        );
        assert_eq!(
            task_q
                .require_task_send_authority(10, authority(3, BitEnum::new_with(ObjFlag::Wizard))),
            Ok(())
        );
        assert_eq!(
            task_q.require_task_send_authority(99, authority(2, BitEnum::new())),
            Err(E_INVARG)
        );
    }
}
