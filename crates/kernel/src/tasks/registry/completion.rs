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

//! Terminal registry bookkeeping under the caller's lifecycle lock.
//!
//! `send_task_result` removes an active record. `send_reserved_task_result` consumes a result
//! reserved by scheduler completion. Both reach `send_task_result_direct`, which releases live
//! membership, records schedule settlement, and delivers the result. `finish_failed_wakeup`
//! resolves a continuation whose dispatch preparation failed before a worker could own it.

use super::{LiveTaskRegistration, RunningTaskPhase, TaskQ};
use crate::tasks::TaskNotification;
use flume::Sender;
use moor_common::tasks::{SchedulerError, TaskId};
use moor_var::Var;
use tracing::warn;

impl TaskQ {
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
}
