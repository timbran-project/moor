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
use crate::tasks::{
    scheduler::tests::{insert_active_task, scheduler},
    task_scheduler_client::TaskSchedulerClient,
};
use moor_common::tasks::MockClientSession;
use moor_var::{SYSTEM_OBJECT, v_int};

fn handoff(scheduler: &Scheduler, task: Box<Task>, input: bool, client: bool) {
    if client {
        let client = TaskSchedulerClient::new(task.task_id, scheduler.clone());
        if input {
            client.request_input(task, SYSTEM_OBJECT, None);
        } else {
            client.suspend(TaskSuspend::Never, task);
        }
    } else if input {
        scheduler.handle_task_request_input(task.task_id, task, SYSTEM_OBJECT, None);
    } else {
        scheduler.handle_task_suspend(task.task_id, TaskSuspend::Never, task);
    }
}

#[test]
fn unproven_public_handoffs_cannot_suspend_or_publish_effects() {
    for input in [false, true] {
        for client in [false, true] {
            let scheduler = scheduler();
            scheduler.lifecycle.lock().state = SchedulerState::Running;
            let session = Arc::new(MockClientSession::new());
            let task = insert_active_task(&scheduler, 41, session.clone());
            // The control state alone cannot replace ownership of the committed boundary.
            let boundary = task.control.claim_boundary().unwrap().committed();
            let (send, recv) = flume::unbounded();
            {
                let mut lc = scheduler.lifecycle.lock();
                let active = lc.task_q.active.get_mut(&41).unwrap();
                active.result_sender = Some(send);
                active.effects.send(42, v_int(99));
            }
            handoff(&scheduler, task, input, client);
            assert_eq!(session.input_requests().len(), usize::from(input));
            let mut lc = scheduler.lifecycle.lock();
            assert!(!lc.task_q.active.contains_key(&41));
            assert!(lc.task_q.suspended.get(41).is_none());
            assert!(!scheduler.handle_task_exists(41));
            assert!(lc.task_q.drain_messages(42).is_empty());
            assert!(matches!(
                recv.try_recv(),
                Ok((41, Err(TaskAbortedCancelled)))
            ));
            drop(boundary);
        }
    }
}

#[test]
fn public_handoffs_transfer_the_owned_boundary() {
    for input in [false, true] {
        for client in [false, true] {
            let scheduler = scheduler();
            scheduler.lifecycle.lock().state = SchedulerState::Running;
            let session = Arc::new(MockClientSession::new());
            let task = insert_active_task(&scheduler, 41, session.clone());
            let control = task.control.clone();
            let boundary = control.claim_boundary().unwrap().committed();
            scheduler
                .lifecycle
                .lock()
                .task_q
                .active
                .get_mut(&41)
                .unwrap()
                .effects
                .send(42, v_int(99));
            handoff(
                &scheduler,
                task.with_committed_boundary(boundary),
                input,
                client,
            );
            assert_eq!(session.input_requests().len(), usize::from(input));
            let mut lc = scheduler.lifecycle.lock();
            assert!(!lc.task_q.active.contains_key(&41));
            assert!(lc.task_q.suspended.get(41).is_some());
            assert!(scheduler.handle_task_exists(41));
            assert_eq!(lc.task_q.drain_messages(42), vec![v_int(99)]);
            assert!(!control.is_cancelled());
            // The proof is consumed before storage. A later drop cannot cancel this dispatch.
            let suspended = lc.task_q.suspended.remove_task(41).unwrap();
            drop(suspended);
            assert!(!control.is_cancelled());
        }
    }
}

#[test]
fn stale_public_handoff_retains_the_replacement() {
    for input in [false, true] {
        let scheduler = scheduler();
        scheduler.lifecycle.lock().state = SchedulerState::Running;
        let stale = insert_active_task(&scheduler, 41, Arc::new(MockClientSession::new()));
        let stale_control = stale.control.clone();
        let boundary = stale_control.claim_boundary().unwrap().committed();
        let replacement = insert_active_task(&scheduler, 41, Arc::new(MockClientSession::new()));
        let (send, recv) = flume::unbounded();
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get_mut(&41)
            .unwrap()
            .result_sender = Some(send);
        handoff(
            &scheduler,
            stale.with_committed_boundary(boundary),
            input,
            false,
        );
        let lc = scheduler.lifecycle.lock();
        assert!(Arc::ptr_eq(
            &lc.task_q.active[&41].control,
            &replacement.control
        ));
        assert_eq!(lc.task_q.active[&41].phase, RunningTaskPhase::Running);
        assert!(lc.task_q.suspended.get(41).is_none());
        assert!(scheduler.handle_task_exists(41));
        assert!(recv.try_recv().is_err());
        assert!(!replacement.control.is_cancelled());
        assert!(stale_control.is_cancelled());
    }
}

#[test]
fn abandoned_handoff_cancels_its_owned_boundary() {
    let scheduler = scheduler();
    let task = insert_active_task(&scheduler, 41, Arc::new(MockClientSession::new()));
    let control = task.control.clone();
    let boundary = control.claim_boundary().unwrap().committed();
    drop(task.with_committed_boundary(boundary));
    assert!(control.is_cancelled());
    // Drop resolves arbitration only. Explicit scheduler cleanup still owns the registry.
    assert!(scheduler.handle_task_exists(41));
}
