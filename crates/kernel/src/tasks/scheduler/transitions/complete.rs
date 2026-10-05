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

//! Terminal completion retains its result in active metadata during session I/O.
//! This owner identifies the attempt that can consume the reserved result.

use super::super::lifecycle::TaskLifecycle;
use crate::tasks::{
    task_control::TaskControl,
    task_q::{RunningTask, RunningTaskPhase},
};
use moor_common::tasks::{SchedulerError, Session, TaskId};
use moor_var::Var;
use std::sync::Arc;

#[must_use]
pub(in crate::tasks::scheduler) struct TaskCompletion {
    task_id: TaskId,
    control: Arc<TaskControl>,
    pub(in crate::tasks::scheduler) session: Arc<dyn Session>,
}

impl TaskCompletion {
    pub(in crate::tasks::scheduler) fn reserve(
        task_id: TaskId,
        task: &mut RunningTask,
        result: Result<Var, SchedulerError>,
    ) -> Self {
        task.phase = RunningTaskPhase::Completing(result);
        Self {
            task_id,
            control: task.control.clone(),
            session: task.session.clone(),
        }
    }

    pub(in crate::tasks::scheduler) fn is_current(&self, lc: &TaskLifecycle) -> bool {
        lc.task_q.active.get(&self.task_id).is_some_and(|task| {
            Arc::ptr_eq(&task.control, &self.control)
                && matches!(task.phase, RunningTaskPhase::Completing(_))
        })
    }

    pub(in crate::tasks::scheduler) fn finish(self, lc: &mut TaskLifecycle) {
        if self.is_current(lc) {
            lc.task_q.send_reserved_task_result(self.task_id);
        }
    }
}
