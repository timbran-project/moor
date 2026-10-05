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

//! Registry permission queries, cancellation, and terminal bookkeeping under exclusive access.
//! Scheduler admission and transitions own transaction, session, and dispatch preparation.

use crate::tasks::{
    AbortTaskOutcome, SchedulerOp, TaskNotification,
    registry::{LiveTaskRegistration, RunningTaskPhase, TaskQ},
    sched_counters,
    task_control::CancelResult,
};
use fast_telemetry::LabeledSampledTimer;
use flume::Sender;
use moor_common::{
    model::TaskPermissions,
    tasks::{SchedulerError, TaskId},
    util::Instant,
};
use moor_var::{E_INVARG, E_PERM, ErrorCode, Obj, Var, v_bool_int, v_err};
use tracing::{error, warn};

impl TaskQ {
    #[inline]
    fn authority_may_kill_task(
        &self,
        task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Result<bool, ErrorCode> {
        if self.suspended.get(task_id).is_some() {
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
    pub(in crate::tasks) fn require_resume_authority(
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

        if self.suspended.get(task_id).is_none() {
            error!(task = task_id, "Task not found for resume request");
            return Err(E_INVARG);
        }

        Ok(())
    }

    #[inline]
    pub(crate) fn require_task_send_authority(
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
    pub(crate) fn record_latency(
        timers: &LabeledSampledTimer<SchedulerOp>,
        op: SchedulerOp,
        started_at: Instant,
    ) {
        timers.record_elapsed(op, started_at.elapsed());
    }

    pub(crate) fn send_task_result(
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
        self.send_task_result_direct(task_control.registration, result_sender, result);
    }

    pub(crate) fn send_reserved_task_result(&mut self, task_id: TaskId) {
        let Some(task) = self.active.get_mut(&task_id) else {
            warn!(
                task_id,
                "Task not found for reserved notification, ignoring"
            );
            return;
        };
        if !matches!(task.phase, RunningTaskPhase::Completing(_)) {
            warn!(task_id, "Task has no reserved terminal result, ignoring");
            return;
        }
        let task = self.active.remove(&task_id).expect("checked active entry");
        let RunningTaskPhase::Completing(result) = task.phase else {
            unreachable!("checked completion phase under exclusive access");
        };
        self.suspended.enqueue_dependents_for(task_id);
        self.send_task_result_direct(task.registration, task.result_sender, result);
    }

    /// Send task result directly with an explicit result_sender (for tasks not in active queue)
    pub(crate) fn send_task_result_direct(
        &mut self,
        registration: LiveTaskRegistration,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        result: Result<Var, SchedulerError>,
    ) {
        let task_id = registration.task_id();
        drop(registration);
        self.settled_results.push((task_id, result.clone()));
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

    /// Finish a wakeup that failed before worker dispatch. The caller holds the lifecycle lock,
    /// and the continuation has already left suspension. No transaction ran in this attempt.
    pub(in crate::tasks) fn finish_failed_wakeup(
        &mut self,
        registration: LiveTaskRegistration,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
    ) {
        let task_id = registration.task_id();
        self.remove_message_queue(task_id);
        self.suspended.enqueue_dependents_for(task_id);
        self.send_task_result_direct(
            registration,
            result_sender,
            Err(SchedulerError::CouldNotStartTask),
        );
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
        if matches!(task.phase, RunningTaskPhase::Completing(_))
            || task.control.request_cancel() != CancelResult::Cancelled
        {
            return true;
        }

        self.active.remove(&victim_task_id);
        self.suspended.enqueue_dependents_for(victim_task_id);
        true
    }

    pub(crate) fn kill_task(
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
    pub(crate) fn abort_task(&mut self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = self.suspended.get(victim_task_id).is_some();
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

        // A completion owner can be finalizing a cancellation or a failed renewal even when
        // the atomic control is no longer in a terminal database commit state.
        if matches!(task.phase, RunningTaskPhase::Completing(_)) {
            return AbortTaskOutcome::Completing;
        }
        match task.control.request_cancel() {
            CancelResult::Completing => AbortTaskOutcome::Completing,
            CancelResult::AfterBoundary => AbortTaskOutcome::Cancelled,
            CancelResult::Cancelled => {
                self.active.remove(&victim_task_id);
                self.suspended.enqueue_dependents_for(victim_task_id);
                AbortTaskOutcome::Cancelled
            }
        }
    }

    pub(crate) fn disconnect_task(&mut self, disconnect_task_id: TaskId, player: &Obj) {
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
        DEFAULT_DB_COMMIT_QUEUE_TIMEOUT, DEFAULT_DB_COMMIT_QUEUE_WARN, DEFAULT_MAX_TASK_MAILBOX,
        DEFAULT_MAX_TASK_RETRIES, NoopTasksDb, ServerOptions, TaskStart,
        registry::{RunningTask, SuspensionQ, WakeCondition},
        task::Task,
        task_control::TaskControl,
    };
    use moor_common::{
        model::ObjFlag,
        tasks::{NoopClientSession, Session},
        util::BitEnum,
    };
    use moor_var::v_int;
    use std::sync::{Arc, OnceLock};
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
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
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
        let registration = task_q.register_task(task_id);
        task_q.suspended.add_task(
            WakeCondition::Never,
            task(task_id, player, authority_principal),
            session(),
            None,
            registration,
        );
    }

    fn add_input_suspended_task(
        task_q: &mut TaskQ,
        task_id: TaskId,
        player: Obj,
        authority_principal: Obj,
    ) {
        let registration = task_q.register_task(task_id);
        task_q.suspended.add_task(
            WakeCondition::Input(Uuid::new_v4()),
            task(task_id, player, authority_principal),
            session(),
            None,
            registration,
        );
    }

    fn add_active_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj) {
        let registration = task_q.register_task(task_id);
        task_q.insert_active(
            task_id,
            RunningTask {
                registration,
                effects: Default::default(),
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
        assert!(task_q.suspended.get(10).is_none());
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
        task.phase = RunningTaskPhase::Completing(Ok(v_int(42)));
        assert!(task.control.claim_terminal().unwrap().committed());

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
        let claim = control.claim_boundary().unwrap();

        assert!(matches!(task_q.abort_task(10), AbortTaskOutcome::Cancelled));
        assert!(task_q.active.contains_key(&10));
        assert!(!claim.committed().finish());
    }

    #[test]
    fn abort_task_waits_for_terminal_database_commit() {
        let mut task_q = task_q();
        add_active_task(&mut task_q, 10, Obj::mk_id(2));
        let control = task_q.active[&10].control.clone();
        let claim = control.claim_terminal().unwrap();

        assert!(matches!(
            task_q.abort_task(10),
            AbortTaskOutcome::Completing
        ));
        assert!(task_q.active.contains_key(&10));
        assert!(claim.committed());
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
            suspended.record.task,
            suspended.record.session,
            suspended.record.result_sender,
            suspended.registration,
        );
        task_q.suspended.remove_task_terminal(10);
        assert!(!task_q.live_tasks.contains(10));
    }

    #[test]
    fn abandoned_wakeup_releases_live_membership() {
        let mut task_q = task_q();
        add_suspended_task(&mut task_q, 10, Obj::mk_id(2), Obj::mk_id(3));
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _wakeup = task_q.suspended.remove_task(10).unwrap();
            assert!(task_q.live_tasks.contains(10));
            panic!("injected failure during wakeup transfer");
        }));
        assert!(result.is_err());
        assert!(!task_q.live_tasks.contains(10));
    }

    #[test]
    fn abandoned_old_wakeup_preserves_replacement_membership() {
        let mut task_q = task_q();
        add_suspended_task(&mut task_q, 10, Obj::mk_id(2), Obj::mk_id(3));
        let old_wakeup = task_q.suspended.remove_task(10).unwrap();
        add_active_task(&mut task_q, 10, Obj::mk_id(4));
        drop(old_wakeup);
        assert!(task_q.live_tasks.contains(10));
        task_q.send_task_result(10, Ok(v_int(0)));
        assert!(!task_q.live_tasks.contains(10));
    }

    #[test]
    fn dropping_registry_releases_active_and_suspended_membership() {
        let mut task_q = task_q();
        add_suspended_task(&mut task_q, 10, Obj::mk_id(2), Obj::mk_id(3));
        add_active_task(&mut task_q, 11, Obj::mk_id(4));
        let live_tasks = task_q.live_tasks.clone();
        drop(task_q);
        assert!(!live_tasks.contains(10));
        assert!(!live_tasks.contains(11));
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
