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
    scheduler::{
        Scheduler,
        test_support::{insert_active_task, scheduler},
    },
    task_scheduler_client::TaskSchedulerClient,
};
use moor_common::{
    model::{
        TaskPermissions, WorldState, WorldStateError, WorldStateSource,
        loader::{LoaderInterface, SnapshotInterface},
    },
    tasks::{NoopClientSession, SchedulerError, TaskId},
};
use moor_db::{Database, GCInterface, SnapshotCallback};
use moor_var::{E_INVARG, SYSTEM_OBJECT, v_err, v_int};
use std::sync::Arc;

const SOURCE: TaskId = 301;
const TARGET: TaskId = 302;

fn replace_dispatch(scheduler: &Scheduler) -> TaskSchedulerClient {
    insert_active_task(scheduler, SOURCE, Arc::new(NoopClientSession::new()));
    let old = TaskSchedulerClient::new(SOURCE, scheduler.clone());
    insert_active_task(scheduler, SOURCE, Arc::new(NoopClientSession::new()));
    insert_active_task(scheduler, TARGET, Arc::new(NoopClientSession::new()));
    {
        let mut lc = scheduler.lifecycle.lock();
        lc.task_q
            .active
            .get_mut(&SOURCE)
            .unwrap()
            .effects
            .send(TARGET, v_int(17));
        lc.task_q.deliver_message(SOURCE, v_int(42));
    }
    old
}

fn assert_replacement_untouched(scheduler: &Scheduler) {
    let mut lc = scheduler.lifecycle.lock();
    assert_eq!(lc.task_q.active[&SOURCE].effects.messages_for(TARGET), 1);
    assert_eq!(lc.task_q.drain_messages(SOURCE), vec![v_int(42)]);
    assert!(lc.task_q.drain_messages(TARGET).is_empty());
    assert!(lc.task_q.active[&SOURCE].abort_error.is_none());
    assert!(!lc.task_q.active[&SOURCE].control.is_cancelled());
}

#[test]
fn stale_send_cannot_buffer_a_message_in_replacement() {
    let scheduler = scheduler();
    let old = replace_dispatch(&scheduler);
    assert_eq!(
        old.task_send(
            TARGET,
            v_int(99),
            TaskPermissions::new(SYSTEM_OBJECT, Default::default())
        ),
        v_err(E_INVARG)
    );
    assert_replacement_untouched(&scheduler);
}

#[test]
fn stale_receive_cannot_drain_replacement_mailbox() {
    let scheduler = scheduler();
    let old = replace_dispatch(&scheduler);
    assert!(old.task_recv().is_empty());
    assert_replacement_untouched(&scheduler);
}

#[test]
fn stale_renewal_cannot_publish_replacement_effects() {
    let scheduler = scheduler();
    let old = replace_dispatch(&scheduler);
    assert!(matches!(
        old.begin_new_transaction(),
        Err(SchedulerError::CouldNotStartTask)
    ));
    assert_replacement_untouched(&scheduler);
}

#[test]
fn unbound_client_does_not_acquire_a_later_registration() {
    let scheduler = scheduler();
    let unbound = TaskSchedulerClient::new(SOURCE, scheduler.clone());
    replace_dispatch(&scheduler);
    // Standalone VM callers can still open transactions without owning scheduler effects.
    unbound.begin_new_transaction().unwrap().rollback().unwrap();
    assert!(unbound.task_recv().is_empty());
    assert_eq!(
        unbound.task_send(
            TARGET,
            v_int(99),
            TaskPermissions::new(SYSTEM_OBJECT, Default::default())
        ),
        v_err(E_INVARG)
    );
    assert_replacement_untouched(&scheduler);
}

#[test]
fn inline_renewal_publishes_each_buffer_once() {
    let scheduler = scheduler();
    replace_dispatch(&scheduler);
    let current = TaskSchedulerClient::new(SOURCE, scheduler.clone());
    let target = TaskSchedulerClient::new(TARGET, scheduler.clone());
    assert_eq!(current.task_recv(), vec![v_int(42)]);
    // The public task-ID adapter selects the current registration at entry.
    scheduler
        .handle_request_new_transaction(SOURCE)
        .unwrap()
        .rollback()
        .unwrap();
    assert_eq!(target.task_recv(), vec![v_int(17)]);
    assert_eq!(
        current.task_send(
            TARGET,
            v_int(99),
            TaskPermissions::new(SYSTEM_OBJECT, Default::default())
        ),
        v_int(0)
    );
    assert!(target.task_recv().is_empty());
    current.begin_new_transaction().unwrap().rollback().unwrap();
    assert_eq!(target.task_recv(), vec![v_int(99)]);
    current.begin_new_transaction().unwrap().rollback().unwrap();
    assert!(target.task_recv().is_empty());
}

struct GatedDatabase {
    inner: Arc<dyn Database>,
    opened: flume::Sender<()>,
    release: flume::Receiver<()>,
}

impl WorldStateSource for GatedDatabase {
    fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
        let transaction = self.inner.new_world_state()?;
        self.opened.send(()).unwrap();
        self.release.recv().unwrap();
        Ok(transaction)
    }

    fn checkpoint(&self) -> Result<(), WorldStateError> {
        unreachable!("renewal does not checkpoint")
    }
}

impl Database for GatedDatabase {
    fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
        unreachable!("renewal does not load objects")
    }

    fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
        unreachable!("renewal does not create snapshots")
    }

    fn create_snapshot_async(&self, _: SnapshotCallback) -> Result<(), WorldStateError> {
        unreachable!("renewal does not create snapshots")
    }

    fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
        unreachable!("renewal does not collect garbage")
    }
}

#[test]
fn renewal_rechecks_dispatch_after_opening_world_state() {
    let mut scheduler = scheduler();
    replace_dispatch(&scheduler);
    let (opened_send, opened_recv) = flume::bounded(1);
    let (release_send, release_recv) = flume::bounded(1);
    scheduler.database = Arc::new(GatedDatabase {
        inner: scheduler.database.clone(),
        opened: opened_send,
        release: release_recv,
    });
    let client = TaskSchedulerClient::new(SOURCE, scheduler.clone());
    let worker = std::thread::spawn(move || client.begin_new_transaction());
    opened_recv
        .recv_timeout(std::time::Duration::from_secs(5))
        .unwrap();
    insert_active_task(&scheduler, SOURCE, Arc::new(NoopClientSession::new()));
    {
        let mut lc = scheduler.lifecycle.lock();
        lc.task_q
            .active
            .get_mut(&SOURCE)
            .unwrap()
            .effects
            .send(TARGET, v_int(99));
    }
    release_send.send(()).unwrap();
    let result = worker.join().unwrap();
    assert!(matches!(result, Err(SchedulerError::CouldNotStartTask)));
    let mut lc = scheduler.lifecycle.lock();
    // The old boundary published before replacement; the new buffer stays private.
    assert_eq!(lc.task_q.drain_messages(TARGET), vec![v_int(17)]);
    assert_eq!(lc.task_q.active[&SOURCE].effects.messages_for(TARGET), 1);
}

#[test]
fn completing_dispatch_rejects_new_message_and_renewal_requests() {
    let scheduler = scheduler();
    replace_dispatch(&scheduler);
    let current = TaskSchedulerClient::new(SOURCE, scheduler.clone());
    scheduler
        .lifecycle
        .lock()
        .task_q
        .active
        .get_mut(&SOURCE)
        .unwrap()
        .phase = crate::tasks::registry::RunningTaskPhase::Completing(Ok(v_int(0)));
    assert_eq!(
        current.task_send(
            TARGET,
            v_int(99),
            TaskPermissions::new(SYSTEM_OBJECT, Default::default())
        ),
        v_err(E_INVARG)
    );
    assert!(current.task_recv().is_empty());
    assert!(matches!(
        current.begin_new_transaction(),
        Err(SchedulerError::CouldNotStartTask)
    ));
    assert_replacement_untouched(&scheduler);
}
