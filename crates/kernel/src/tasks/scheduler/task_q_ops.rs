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
        sender_authority: Authority,
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
        sender_authority: Authority,
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
        sender_authority: Authority,
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
        self.wake_task_thread(
            task,
            resume_action,
            session,
            result_sender,
            scheduler,
            database,
            builtin_registry,
            config,
        )
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
        perms: &Obj,
        task_start: TaskStart,
        delay_start: Option<Duration>,
        session: Arc<dyn Session>,
        server_options: &ServerOptions,
        gc_in_progress: bool,
    ) -> TaskSubmission {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::StartTask);
        let (sender, receiver) = flume::unbounded();

        let kill_switch = Arc::new(AtomicBool::new(false));
        let task = Task::new(
            task_id,
            *player,
            *perms,
            task_start.clone(),
            server_options,
            kill_switch.clone(),
        );

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
        let player = task.perms;

        // Brand new kill switch for the resumed task.
        let kill_switch = Arc::new(AtomicBool::new(false));
        task.kill_switch = kill_switch.clone();
        let task_control = RunningTask {
            player,
            kill_switch,
            session: session.clone(),
            result_sender,
            task_start: task.state.task_start().clone(),
        };

        self.active.insert(task_id, task_control);

        let scheduler_clone = scheduler.clone();
        let task_scheduler_client = TaskSchedulerClient::new(task_id, scheduler.clone());

        // Check if this is a brand new task or a resuming task
        let is_created = matches!(task.state, crate::tasks::task::TaskState::Pending(_));

        let wake_to_dispatch_started_at = Instant::now();
        let dispatch_started_at = Instant::now();
        self.thread_pool.spawn(move || {
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
            warn!(task_id, "Task not found for notification, ignoring");
            return;
        };
        self.suspended.enqueue_dependents_for(task_id);
        let result_sender = task_control.result_sender.take();
        Self::send_task_result_direct(task_id, result_sender, result);
    }

    /// Send task result directly with an explicit result_sender (for tasks not in active queue)
    pub(super) fn send_task_result_direct(
        task_id: TaskId,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        result: Result<Var, SchedulerError>,
    ) {
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

        // Fork the session for the new attempt
        let new_session = session.fork().unwrap();

        // Brand new kill switch for the retried task
        let kill_switch = Arc::new(AtomicBool::new(false));
        task.kill_switch = kill_switch.clone();

        let task_control = RunningTask {
            player: task.player,
            kill_switch,
            session: new_session.clone(),
            result_sender,
            task_start: task.state.task_start().clone(),
        };

        self.active.insert(task_id, task_control);

        let scheduler_clone = scheduler.clone();

        let world_state = match database.new_world_state() {
            Ok(ws) => ws,
            Err(e) => {
                panic!("Could not start transaction for retry wake task due to DB error: {e:?}");
            }
        };
        let task_scheduler_client = TaskSchedulerClient::new(task_id, scheduler.clone());
        let player = task.player;
        let wake_to_dispatch_started_at = Instant::now();
        let dispatch_started_at = Instant::now();
        self.thread_pool.spawn(move || {
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

                info!(
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

    pub(super) fn kill_task(&mut self, victim_task_id: TaskId, sender_authority: Authority) -> Var {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = match self.authority_may_kill_task(victim_task_id, sender_authority) {
            Ok(is_suspended) => is_suspended,
            Err(error) => return v_err(error),
        };

        if is_suspended {
            if self
                .suspended
                .remove_task_terminal(victim_task_id)
                .is_none()
            {
                error!(
                    task = victim_task_id,
                    "Task not found in suspended list for kill request"
                );
            }
            return v_bool_int(false);
        }

        let victim_task = match self.active.remove(&victim_task_id) {
            Some(victim_task) => victim_task,
            None => {
                return v_err(E_INVARG);
            }
        };
        self.suspended.enqueue_dependents_for(victim_task_id);
        victim_task.kill_switch.store(true, Ordering::SeqCst);
        v_bool_int(false)
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) fn resume_task(
        &mut self,
        requesting_task_id: TaskId,
        queued_task_id: TaskId,
        sender_authority: Authority,
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
            tc.kill_switch.store(true, Ordering::SeqCst);
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
        }
    }

    fn authority(principal: i32, flags: BitEnum<ObjFlag>) -> Authority {
        Authority::new(Obj::mk_id(principal), flags)
    }

    fn task_q() -> TaskQ {
        TaskQ::new(SuspensionQ::new(Box::new(NoopTasksDb {})))
    }

    fn session() -> Arc<dyn Session> {
        Arc::new(NoopClientSession::new())
    }

    fn task(task_id: TaskId, player: Obj, perms: Obj) -> Box<Task> {
        Task::new(
            task_id,
            player,
            perms,
            TaskStart::StartEval {
                player,
                program: Default::default(),
                initial_env: None,
            },
            &test_server_options(),
            Arc::new(AtomicBool::new(false)),
        )
    }

    fn add_suspended_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj, perms: Obj) {
        task_q.suspended.add_task(
            WakeCondition::Never,
            task(task_id, player, perms),
            session(),
            None,
        );
    }

    fn add_input_suspended_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj, perms: Obj) {
        task_q.suspended.add_task(
            WakeCondition::Input(Uuid::new_v4()),
            task(task_id, player, perms),
            session(),
            None,
        );
    }

    fn add_active_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj) {
        task_q.active.insert(
            task_id,
            RunningTask {
                player,
                task_start: TaskStart::StartEval {
                    player,
                    program: Default::default(),
                    initial_env: None,
                },
                kill_switch: Arc::new(AtomicBool::new(false)),
                session: session(),
                result_sender: None,
            },
        );
    }

    #[test]
    fn kill_authority_matches_suspended_task_permissions_or_wizard() {
        let mut task_q = task_q();
        let player = Obj::mk_id(2);
        let perms = Obj::mk_id(3);
        add_suspended_task(&mut task_q, 10, player, perms);

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
    fn resume_authority_filters_input_tasks_for_non_wizards() {
        let mut task_q = task_q();
        let player = Obj::mk_id(2);
        let perms = Obj::mk_id(3);
        add_input_suspended_task(&mut task_q, 10, player, perms);

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
