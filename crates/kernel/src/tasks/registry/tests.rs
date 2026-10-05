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

//! Permission, cancellation, and live-registration contracts.

use super::*;
use crate::tasks::{
    AbortTaskOutcome, DEFAULT_DB_COMMIT_QUEUE_TIMEOUT, DEFAULT_DB_COMMIT_QUEUE_WARN,
    DEFAULT_MAX_TASK_MAILBOX, DEFAULT_MAX_TASK_RETRIES, NoopTasksDb, ServerOptions, TaskStart,
    registry::{RunningTask, SuspensionQ, WakeCondition},
    task::Task,
    task_control::TaskControl,
};
use moor_common::{
    model::ObjFlag,
    tasks::{NoopClientSession, Session},
    util::{BitEnum, Instant},
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

fn add_suspended_task(task_q: &mut TaskQ, task_id: TaskId, player: Obj, authority_principal: Obj) {
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
        task_q.require_task_send_authority(10, authority(3, BitEnum::new_with(ObjFlag::Wizard))),
        Ok(())
    );
    assert_eq!(
        task_q.require_task_send_authority(99, authority(2, BitEnum::new())),
        Err(E_INVARG)
    );
}
