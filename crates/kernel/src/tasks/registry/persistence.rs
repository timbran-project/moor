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
//! Accepted responses awaiting dispatch are runtime work. Shutdown cancels them, and save excludes
//! them because the persisted record does not contain their pending return value or raised error.
//!
//! A suspended task isn't saved when it suspends. Many tasks wake within moments, such as one
//! looping on its mailbox, and for those a save would be wasted. So a suspension is noted, and
//! `save_due_tasks` copies out those that are still suspended once they have waited long enough,
//! for `TaskWriter` to write off the lifecycle lock. A task that wakes first costs no write and
//! no delete. A crash can therefore lose a task that suspended within the last
//! `MESSAGE_OR_TIMER_SAVE_DELAY` plus `SAVE_PASS_INTERVAL`, along with the writes still queued.
//! A clean shutdown saves everything.
//!
//! This module preserves the existing error policy. Load and session-construction errors panic
//! during startup. Save and bulk-deletion errors are logged and do not reverse in-memory changes.
//! Individual deletion errors are ignored. A deletion failure can therefore leave a stale record
//! for restart; changing that policy requires a separate recovery design. No persistence starts
//! in a destructor, though the writer finishes what it was already given.

use super::suspension::{SuspensionQ, WakeCondition};
use crate::tasks::convert_task::SavedTask;
use moor_common::{
    tasks::{SessionFactory, TaskId},
    util::Instant,
};
use std::{sync::Arc, time::Duration};
use tracing::{error, info};

/// How often to look for suspended tasks that are due to be saved.
pub(super) const SAVE_PASS_INTERVAL: Duration = Duration::from_millis(250);

/// How long a task must wait on its mailbox or a timer before it is saved. Tasks doing these
/// often wake soon, and many do so again and again. This needs to outlast the gaps in such loops:
/// in a load test of mailbox loops, saves went from about 1 a second at 500 ms to about 190 a
/// second at 250 ms.
pub(super) const MESSAGE_OR_TIMER_SAVE_DELAY: Duration = Duration::from_secs(1);

/// The most tasks to copy out in one pass, to keep the time holding the lifecycle lock short. Any
/// more wait for the next pass.
const MAX_SAVES_PER_PASS: usize = 256;

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

    /// Hand the writer those suspended tasks whose time to be saved has come.
    pub(crate) fn save_due_tasks(&mut self, now: Instant) {
        if now < self.next_save_pass {
            return;
        }
        self.next_save_pass = now + SAVE_PASS_INTERVAL;
        let due: Vec<TaskId> = self
            .unsaved
            .iter()
            .filter(|(_, due)| **due <= now)
            .map(|(task_id, _)| *task_id)
            .take(MAX_SAVES_PER_PASS)
            .collect();
        let mut tasks = Vec::with_capacity(due.len());
        for task_id in due {
            self.unsaved.remove(&task_id);
            // Accepted responses have left their persisted wait, and have nothing to save.
            let Some(task) = self.tasks.get(&task_id) else {
                continue;
            };
            if task.pending_resume.is_some() {
                continue;
            }
            match SavedTask::of(&task.record) {
                Ok(saved) => {
                    tasks.push(saved);
                    self.saved.insert(task_id);
                }
                Err(error) => error!(?error, task_id, "Could not save suspended task"),
            }
        }
        if !tasks.is_empty() {
            self.writer.save(tasks);
        }
    }

    /// Synchronize the suspended tasks with the tasks database. Called on shutdown.
    pub(crate) fn save_tasks(&self) {
        let mut tasks = vec![];
        for st in self.persistable_records() {
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
            match SavedTask::of(st) {
                Ok(saved) => tasks.push(saved),
                Err(error) => error!(?error, "Could not save suspended task"),
            }
        }
        self.writer.save(tasks);
        self.writer.wait_until_written();
    }

    /// Forget a task's record, if it has one.
    pub(super) fn delete_persisted_task(&mut self, task_id: TaskId) {
        self.unsaved.remove(&task_id);
        if self.saved.remove(&task_id) {
            self.writer.delete(task_id);
        }
    }
}
