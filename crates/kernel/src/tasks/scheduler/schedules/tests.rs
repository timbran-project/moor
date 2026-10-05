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

use crate::tasks::{
    schedule_q::{PendingKind, ScheduleError, ScheduleId, ScheduleKind, ScheduleOptions},
    scheduler::{
        Scheduler,
        test_support::{insert_active_task, scheduler},
    },
    task_scheduler_client::TaskSchedulerClient,
};
use moor_common::{
    model::TaskPermissions,
    tasks::{NoopClientSession, TaskId},
};
use moor_var::{List, SYSTEM_OBJECT, Symbol};
use std::{sync::Arc, time::Duration};

const TASK: TaskId = 311;
const INTERVAL: Duration = Duration::from_secs(60);

fn create(client: &TaskSchedulerClient, interval: Duration) -> Result<ScheduleId, ScheduleError> {
    client.schedule_create(
        PendingKind::Every(interval),
        SYSTEM_OBJECT,
        Symbol::mk("tick"),
        List::mk_list(&[]),
        SYSTEM_OBJECT,
        SYSTEM_OBJECT,
        ScheduleOptions::for_kind(&ScheduleKind::Every { interval }),
    )
}

fn clients(scheduler: &Scheduler) -> (TaskSchedulerClient, TaskSchedulerClient) {
    insert_active_task(scheduler, TASK, Arc::new(NoopClientSession::new()));
    let old = TaskSchedulerClient::new(TASK, scheduler.clone());
    insert_active_task(scheduler, TASK, Arc::new(NoopClientSession::new()));
    (old, TaskSchedulerClient::new(TASK, scheduler.clone()))
}

#[test]
fn stale_creation_reserves_an_id_without_changing_replacement_effects() {
    let scheduler = scheduler();
    let (old, current) = clients(&scheduler);
    let first = create(&current, INTERVAL).unwrap();
    let abandoned = create(&old, INTERVAL).unwrap();
    let last = create(&current, INTERVAL).unwrap();
    assert_eq!(abandoned, first + 1);
    assert_eq!(last, abandoned + 1);
    assert_eq!(
        create(&old, Duration::ZERO),
        Err(ScheduleError::InvalidInterval)
    );
    assert!(!current.schedule_valid(abandoned));
    current.begin_new_transaction().unwrap().rollback().unwrap();
    let lc = scheduler.lifecycle.lock();
    assert!(lc.schedule_q.is_valid(first));
    assert!(lc.schedule_q.is_valid(last));
    assert!(!lc.schedule_q.is_valid(abandoned));
}

#[test]
fn stale_query_cannot_see_replacement_pending_schedules() {
    let scheduler = scheduler();
    let (old, current) = clients(&scheduler);
    let id = create(&current, INTERVAL).unwrap();
    assert!(current.schedule_valid(id));
    assert!(!old.schedule_valid(id));
    current.begin_new_transaction().unwrap().rollback().unwrap();
    assert!(old.schedule_valid(id)); // Committed schedules are global query state.
}

#[test]
fn stale_stop_cannot_cancel_replacement_pending_creation() {
    let scheduler = scheduler();
    let (old, current) = clients(&scheduler);
    let id = create(&current, INTERVAL).unwrap();
    let authority = TaskPermissions::new(SYSTEM_OBJECT, Default::default());
    assert!(!old.schedule_stop(id, &authority).unwrap());
    assert!(current.schedule_valid(id));
    assert!(current.schedule_stop(id, &authority).unwrap());
    assert!(!current.schedule_valid(id));
}

#[test]
fn stale_stop_cannot_buffer_a_stop_for_a_committed_schedule() {
    let scheduler = scheduler();
    let (old, current) = clients(&scheduler);
    let id = create(&current, INTERVAL).unwrap();
    current.begin_new_transaction().unwrap().rollback().unwrap();
    let authority = TaskPermissions::new(SYSTEM_OBJECT, Default::default());
    assert!(!old.schedule_stop(id, &authority).unwrap());
    current.begin_new_transaction().unwrap().rollback().unwrap();
    assert!(current.schedule_valid(id));
    assert!(current.schedule_stop(id, &authority).unwrap());
    current.begin_new_transaction().unwrap().rollback().unwrap();
    assert!(!current.schedule_valid(id));
}

#[test]
fn unbound_schedule_client_does_not_acquire_a_later_registration() {
    let scheduler = scheduler();
    let unbound = TaskSchedulerClient::new(TASK, scheduler.clone());
    let (_, current) = clients(&scheduler);
    let id = create(&current, INTERVAL).unwrap();
    let abandoned = create(&unbound, INTERVAL).unwrap();
    assert!(!unbound.schedule_valid(id));
    assert!(!current.schedule_valid(abandoned));
    let authority = TaskPermissions::new(SYSTEM_OBJECT, Default::default());
    assert!(!unbound.schedule_stop(id, &authority).unwrap());
    assert!(current.schedule_valid(id));
}

#[test]
fn finalizing_dispatch_cannot_change_pending_schedules() {
    use crate::tasks::registry::RunningTaskPhase;
    use moor_var::v_int;

    for phase in [
        RunningTaskPhase::Completing(Ok(v_int(0))),
        RunningTaskPhase::Suspending,
        RunningTaskPhase::RequestingInput,
    ] {
        let scheduler = scheduler();
        let (_, current) = clients(&scheduler);
        let id = create(&current, INTERVAL).unwrap();
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get_mut(&TASK)
            .unwrap()
            .phase = phase;
        let abandoned = create(&current, INTERVAL).unwrap();
        let authority = TaskPermissions::new(SYSTEM_OBJECT, Default::default());
        assert!(!current.schedule_stop(id, &authority).unwrap());
        assert!(!current.schedule_valid(id));
        let lc = scheduler.lifecycle.lock();
        let effects = &lc.task_q.active[&TASK].effects;
        assert!(effects.contains_schedule(id));
        assert!(!effects.contains_schedule(abandoned));
    }
}
