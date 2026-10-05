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
use moor_common::tasks::NoopClientSession;

use crate::tasks::scheduler::test_support::*;

#[test]
fn stale_retry_keeps_replacement_attempt_running() {
    let scheduler = scheduler();
    let task_id = 251;
    let old_task = insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
    let replacement = insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
    scheduler.lifecycle.lock().state = SchedulerState::Running;
    scheduler.handle_task_conflict_retry(task_id, old_task, "test", None);
    let lc = scheduler.lifecycle.lock();
    let active = lc
        .task_q
        .active
        .get(&task_id)
        .expect("replacement must not enter retry");
    assert!(Arc::ptr_eq(&active.control, &replacement.control));
    assert!(!replacement.control.is_cancelled());
    assert!(lc.task_q.suspended.get(task_id).is_none());
}
