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

//! Task persistence and restoration under the scheduler lifecycle lock.
//!
//! Registration stays in `suspension`: loading creates sessions, then installs each record through
//! its registration operation. Shutdown saves registered records without changing their membership.
//!
//! This module preserves the existing error policy. Load and session-construction errors panic
//! during startup. Save and bulk-deletion errors are logged and do not reverse in-memory changes.
//! Individual deletion errors are ignored. A deletion failure can therefore leave a stale record
//! for restart; changing that policy requires a separate recovery design. No persistence runs in
//! a destructor.

use super::suspension::{SuspendedTask, SuspensionQ, WakeCondition};
use moor_common::tasks::{SessionFactory, TaskId};
use std::sync::Arc;
use tracing::{error, info};

impl SuspensionQ {
    /// Load all tasks from the tasks database. Called on startup to reconstitute the task list
    /// from the database.
    pub(crate) fn load_tasks(
        &mut self,
        bg_session_factory: Arc<dyn SessionFactory>,
    ) -> Option<TaskId> {
        // Retain every persisted task, including old tasks and disconnected players,
        // matching LambdaMOO restoration behavior.
        let tasks = self
            .tasks_db()
            .load_tasks()
            .expect("Unable to reconstitute tasks from tasks database");
        let num_tasks = tasks.len();
        let max_task_id = tasks.iter().map(|task| task.task.task_id).max();
        for mut task in tasks {
            task.session = bg_session_factory
                .clone()
                .mk_background_session(&task.task.player())
                .expect("Unable to create new background session for suspended task");

            self.register_restored_task(task);
        }
        // Now delete them from the database.
        if let Err(e) = self.tasks_db().delete_all_tasks() {
            error!(?e, "Could not delete suspended tasks from tasks database");
        }
        info!(?num_tasks, "Loaded suspended tasks from tasks database");
        max_task_id
    }

    /// Synchronize the suspended tasks with the tasks database. Called on shutdown.
    pub(crate) fn save_tasks(&self) {
        for st in self.records() {
            // Skip retry tasks - they're transient and their transaction context
            // would be invalid after restart anyway
            if matches!(
                st.wake_condition,
                WakeCondition::Retry(_)
                    | WakeCondition::Checkpoint(_)
                    | WakeCondition::StorageCompaction(_)
            ) {
                continue;
            }
            self.persist_task(st);
        }
    }

    /// Best-effort save. A storage error does not undo suspension registration.
    pub(super) fn persist_task(&self, task: &SuspendedTask) {
        if let Err(error) = self.tasks_db().save_task(task) {
            error!(?error, "Could not save suspended task");
        }
    }

    /// Preserve the current best-effort deletion policy, including absent records.
    pub(super) fn delete_persisted_task(&self, task_id: TaskId) {
        let _ = self.tasks_db().delete_task(task_id);
    }
}
