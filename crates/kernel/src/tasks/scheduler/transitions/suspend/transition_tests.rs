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

use crate::tasks::scheduler::*;
use crate::{
    tasks::{
        AbortTaskOutcome, TaskNotification,
        registry::{RunningTaskPhase, WakeCondition},
    },
    vm::TaskSuspend,
};
use moor_common::tasks::{
    NoopClientSession,
    SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
};
use moor_var::{SYSTEM_OBJECT, v_int};
use std::sync::Barrier;

use crate::tasks::scheduler::test_support::*;

#[test]
fn suspending_task_remains_visible_until_atomic_queue_move() {
    let scheduler = scheduler();
    let timer = scheduler
        .start(Arc::new(NoopSessionFactory))
        .expect("scheduler should start");
    let task_id = 42;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let session = Arc::new(BlockingCommitSession {
        commit_entered: commit_entered.clone(),
        release_commit: release_commit.clone(),
        connection_obj: None,
        source_connections: None,
        fail_commit: false,
    });
    let task = insert_active_task(&scheduler, task_id, session);
    let boundary = task.control.claim_boundary().unwrap().committed();

    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_suspend(
            task_id,
            TaskSuspend::Never,
            task.with_committed_boundary(boundary),
        );
    });

    commit_entered.wait();
    assert!(
        scheduler.handle_task_exists(task_id),
        "task must remain addressable while its session commit is in progress"
    );
    assert_eq!(
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get(&task_id)
            .map(|task| task.phase.clone()),
        Some(RunningTaskPhase::Suspending)
    );

    release_commit.wait();
    callback.join().expect("suspend callback should complete");

    let lc = scheduler.lifecycle.lock();
    assert!(!lc.task_q.active.contains_key(&task_id));
    assert!(lc.task_q.suspended.get(task_id).is_some());
    drop(lc);

    scheduler.stop(None).expect("scheduler should stop");
    timer.join().expect("timer thread should stop");
}

#[test]
fn timed_suspension_publishes_effects_after_session_commit() {
    check_timed_suspension_effects(false, false);
}

#[test]
fn timed_suspension_session_failure_does_not_publish_effects() {
    check_timed_suspension_effects(true, false);
}

#[test]
fn timed_suspension_cancellation_does_not_publish_effects() {
    check_timed_suspension_effects(false, true);
}

fn check_timed_suspension_effects(fail_commit: bool, cancel: bool) {
    let scheduler = scheduler();
    // No service loops: the test controls every transition and deadline.
    scheduler.lifecycle.lock().state = SchedulerState::Running;
    let task_id = 242;
    let target_id = 243;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let session = Arc::new(BlockingCommitSession {
        commit_entered: commit_entered.clone(),
        release_commit: release_commit.clone(),
        connection_obj: None,
        source_connections: None,
        fail_commit,
    });
    let task = insert_active_task(&scheduler, task_id, session);
    let control = task.control.clone();
    let boundary = control.claim_boundary().unwrap().committed();
    let (send, recv) = flume::unbounded();
    {
        let mut lc = scheduler.lifecycle.lock();
        lc.task_q.active.get_mut(&task_id).unwrap().result_sender = Some(send);
        lc.task_q
            .active
            .get_mut(&task_id)
            .unwrap()
            .effects
            .send(target_id, v_int(17));
    }
    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_suspend(
            task_id,
            TaskSuspend::Timed(Duration::from_secs(60)),
            task.with_committed_boundary(boundary),
        );
    });
    commit_entered.wait();
    {
        let mut lc = scheduler.lifecycle.lock();
        assert!(lc.task_q.drain_messages(target_id).is_empty());
        assert!(lc.task_q.active.contains_key(&task_id));
        assert!(recv.try_recv().is_err());
        if cancel {
            assert!(matches!(
                lc.task_q.abort_task(task_id),
                AbortTaskOutcome::Cancelled
            ));
            assert!(lc.task_q.active.contains_key(&task_id));
        }
    }
    release_commit.wait();
    callback.join().unwrap();
    let mut lc = scheduler.lifecycle.lock();
    assert!(!lc.task_q.active.contains_key(&task_id));
    let (_, result) = recv.recv().unwrap();
    if fail_commit || cancel {
        assert!(lc.task_q.drain_messages(target_id).is_empty());
        assert!(lc.task_q.suspended.get(task_id).is_none());
        assert!(!scheduler.handle_task_exists(task_id));
        assert!(
            matches!(result, Err(TaskAbortedError)) && fail_commit
                || matches!(result, Err(TaskAbortedCancelled)) && cancel
        );
    } else {
        assert_eq!(lc.task_q.drain_messages(target_id), vec![v_int(17)]);
        assert!(matches!(result, Ok(TaskNotification::Suspended)));
        let suspended = lc.task_q.suspended.get(task_id).unwrap();
        assert!(matches!(suspended.wake_condition, WakeCondition::Time(_)));
        assert!(scheduler.handle_task_exists(task_id));
    }
}

#[test]
fn stale_suspension_completion_leaves_replacement_attempt_active() {
    let scheduler = scheduler();
    scheduler.lifecycle.lock().state = SchedulerState::Running;
    let task_id = 244;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let task = insert_active_task(
        &scheduler,
        task_id,
        Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
            fail_commit: false,
        }),
    );
    let boundary = task.control.claim_boundary().unwrap().committed();
    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_suspend(
            task_id,
            TaskSuspend::Never,
            task.with_committed_boundary(boundary),
        );
    });
    commit_entered.wait();
    let replacement = insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
    release_commit.wait();
    callback.join().unwrap();
    let lc = scheduler.lifecycle.lock();
    let active = lc.task_q.active.get(&task_id).unwrap();
    assert!(Arc::ptr_eq(&active.control, &replacement.control));
    assert_eq!(active.phase, RunningTaskPhase::Running);
    assert!(!replacement.control.is_cancelled());
    assert!(lc.task_q.suspended.get(task_id).is_none());
}

#[test]
fn input_task_remains_visible_until_atomic_queue_move() {
    let scheduler = scheduler();
    let timer = scheduler
        .start(Arc::new(NoopSessionFactory))
        .expect("scheduler should start");
    let task_id = 43;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let session = Arc::new(BlockingCommitSession {
        commit_entered: commit_entered.clone(),
        release_commit: release_commit.clone(),
        connection_obj: None,
        source_connections: None,
        fail_commit: false,
    });
    let task = insert_active_task(&scheduler, task_id, session);
    let boundary = task.control.claim_boundary().unwrap().committed();

    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_request_input(
            task_id,
            task.with_committed_boundary(boundary),
            SYSTEM_OBJECT,
            None,
        );
    });

    commit_entered.wait();
    assert!(
        scheduler.handle_task_exists(task_id),
        "task must remain addressable while its input request is in progress"
    );
    assert_eq!(
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get(&task_id)
            .map(|task| task.phase.clone()),
        Some(RunningTaskPhase::RequestingInput)
    );

    release_commit.wait();
    callback
        .join()
        .expect("input request callback should complete");

    let lc = scheduler.lifecycle.lock();
    assert!(!lc.task_q.active.contains_key(&task_id));
    assert!(lc.task_q.suspended.get(task_id).is_some());
    drop(lc);

    scheduler.stop(None).expect("scheduler should stop");
    timer.join().expect("timer thread should stop");
}

#[test]
fn shutdown_does_not_resurrect_suspending_task() {
    let scheduler = scheduler();
    let threads = scheduler
        .start(Arc::new(NoopSessionFactory))
        .expect("scheduler should start");
    let task_id = 44;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let session = Arc::new(BlockingCommitSession {
        commit_entered: commit_entered.clone(),
        release_commit: release_commit.clone(),
        connection_obj: None,
        source_connections: None,
        fail_commit: false,
    });
    let task = insert_active_task(&scheduler, task_id, session);
    let boundary = task.control.claim_boundary().unwrap().committed();

    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_suspend(
            task_id,
            TaskSuspend::Never,
            task.with_committed_boundary(boundary),
        );
    });

    commit_entered.wait();
    let (stop_done_send, stop_done_recv) = flume::bounded(1);
    let stop_scheduler = scheduler.clone();
    let stop = std::thread::spawn(move || {
        let result = stop_scheduler.stop(None);
        stop_done_send.send(result).ok();
    });
    let wait_started = std::time::Instant::now();
    while scheduler.state() != SchedulerState::Stopping {
        assert!(
            wait_started.elapsed() < Duration::from_secs(1),
            "scheduler did not enter stopping state"
        );
        std::thread::yield_now();
    }
    assert!(
        stop_done_recv
            .recv_timeout(Duration::from_millis(25))
            .is_err(),
        "scheduler stopped before the in-flight callback finished"
    );

    release_commit.wait();
    callback.join().expect("suspend callback should exit");
    stop_done_recv
        .recv_timeout(Duration::from_secs(1))
        .expect("scheduler shutdown should finish after the callback")
        .expect("scheduler should stop");
    stop.join().expect("shutdown thread should stop");
    assert_eq!(scheduler.state(), SchedulerState::Stopped);

    let lc = scheduler.lifecycle.lock();
    assert!(!lc.task_q.active.contains_key(&task_id));
    assert!(lc.task_q.suspended.get(task_id).is_none());
    drop(lc);

    threads
        .join()
        .expect("all scheduler-owned threads should stop");
}
