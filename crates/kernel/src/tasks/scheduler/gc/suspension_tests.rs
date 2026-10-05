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
use crate::vm::TaskSuspend;
use std::{collections::HashSet, sync::Barrier};

use crate::tasks::scheduler::test_support::*;

#[test]
fn gc_sweep_waits_for_suspension_transition() {
    let scheduler = scheduler();
    let threads = scheduler
        .start(Arc::new(NoopSessionFactory))
        .expect("scheduler should start");
    let task_id = 45;
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

    let (gc_done_send, gc_done_recv) = flume::bounded(1);
    let gc_scheduler = scheduler.clone();
    let gc = std::thread::spawn(move || {
        let result = {
            let cycle = gc::GcCycle::begin(&gc_scheduler).unwrap();
            assert!(cycle.marking());
            let timestamp = gc_scheduler.lifecycle.lock().last_mutation_timestamp;
            cycle.sweep(HashSet::new(), timestamp)
        };
        gc_done_send.send(result).ok();
    });

    let wait_started = std::time::Instant::now();
    while !scheduler.lifecycle.lock().gc_phase.blocks_admission() {
        assert!(
            wait_started.elapsed() < Duration::from_secs(1),
            "GC sweep did not enter its waiting phase"
        );
        std::thread::yield_now();
    }
    assert!(
        gc_done_recv
            .recv_timeout(Duration::from_millis(25))
            .is_err(),
        "GC sweep completed while a suspension transition was active"
    );

    release_commit.wait();
    callback.join().expect("suspend callback should complete");
    gc_done_recv
        .recv_timeout(Duration::from_secs(1))
        .expect("GC sweep should complete after suspension")
        .expect("GC sweep should succeed");
    gc.join().expect("GC sweep thread should stop");

    scheduler.stop(None).expect("scheduler should stop");
    threads
        .join()
        .expect("all scheduler-owned threads should stop");
}

#[test]
fn shutdown_cancels_gc_sweep_waiting_on_suspension() {
    let scheduler = scheduler();
    let threads = scheduler
        .start(Arc::new(NoopSessionFactory))
        .expect("scheduler should start");
    let task_id = 46;
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

    let gc_scheduler = scheduler.clone();
    let gc = std::thread::spawn(move || {
        let cycle = gc::GcCycle::begin(&gc_scheduler).unwrap();
        assert!(cycle.marking());
        let timestamp = gc_scheduler.lifecycle.lock().last_mutation_timestamp;
        cycle.sweep(HashSet::new(), timestamp)
    });
    let wait_started = std::time::Instant::now();
    while !scheduler.lifecycle.lock().gc_phase.blocks_admission() {
        assert!(
            wait_started.elapsed() < Duration::from_secs(1),
            "GC sweep did not enter its waiting phase"
        );
        std::thread::yield_now();
    }

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
    gc.join()
        .expect("GC sweep thread should stop")
        .expect("cancelled GC sweep should exit cleanly");
    assert!(!scheduler.lifecycle.lock().gc_phase.blocks_admission());
    assert!(!scheduler.handle_task_exists(task_id));

    threads
        .join()
        .expect("all scheduler-owned threads should stop");
}
