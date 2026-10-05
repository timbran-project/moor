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

//! Task transitions coordinate registry changes under the lifecycle lock.
//! Session I/O runs outside that lock while active metadata remains visible.

mod cancel;
mod compat;
pub(super) mod complete;
mod resume;
mod retry;
mod suspend;

use crate::tasks::{scheduler::Scheduler, task_q::TaskAttempt};
use moor_common::tasks::TaskId;

impl Scheduler {
    /// Compatibility entry points address the active attempt at call time. Worker clients retain
    /// the identity captured during dispatch and pass it directly to the transition instead.
    pub(crate) fn capture_task_attempt(&self, task_id: TaskId) -> Option<TaskAttempt> {
        self.lifecycle.lock().task_q.attempt(task_id)
    }
}
