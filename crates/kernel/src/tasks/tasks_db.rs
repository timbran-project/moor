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

use crate::tasks::schedule_q::{ScheduleEntry, ScheduleId};
use crate::tasks::task_q::SuspendedTask;
use moor_common::tasks::TaskId;

#[derive(Debug, thiserror::Error)]
pub enum TasksDbError {
    #[error("Could not load tasks")]
    CouldNotLoadTasks,
    #[error("Could not save task")]
    CouldNotSaveTask,
    #[error("Could not delete task")]
    CouldNotDeleteTask,
    #[error("Task not found: {0}")]
    TaskNotFound(TaskId),
    #[error("Could not load schedules")]
    CouldNotLoadSchedules,
    #[error("Could not save schedule")]
    CouldNotSaveSchedule,
    #[error("Could not delete schedule")]
    CouldNotDeleteSchedule,
}

pub trait TasksDb: Send {
    fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError>;
    fn save_task(&self, task: &SuspendedTask) -> Result<(), TasksDbError>;
    fn delete_task(&self, task_id: TaskId) -> Result<(), TasksDbError>;
    fn delete_all_tasks(&self) -> Result<(), TasksDbError>;

    /// Native schedules (`ScheduleQ` entries with `persist` set). Stored
    /// separately from suspended tasks: a schedule has no VM state, only a
    /// deadline and a verb to call. Defaults are no-ops so test doubles that
    /// only care about tasks need not implement them.
    fn load_schedules(&self) -> Result<Vec<ScheduleEntry>, TasksDbError> {
        Ok(vec![])
    }
    fn save_schedule(&self, _entry: &ScheduleEntry) -> Result<(), TasksDbError> {
        Ok(())
    }
    fn delete_schedule(&self, _schedule_id: ScheduleId) -> Result<(), TasksDbError> {
        Ok(())
    }
    fn delete_all_schedules(&self) -> Result<(), TasksDbError> {
        Ok(())
    }

    /// Trigger database compaction to reclaim space and reduce journal size.
    /// Should be called periodically (e.g., every few minutes).
    fn compact(&self);
}

pub struct NoopTasksDb {}

impl TasksDb for NoopTasksDb {
    fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError> {
        Ok(vec![])
    }

    fn save_task(&self, _task: &SuspendedTask) -> Result<(), TasksDbError> {
        Ok(())
    }

    fn delete_task(&self, _task_id: TaskId) -> Result<(), TasksDbError> {
        Ok(())
    }

    fn delete_all_tasks(&self) -> Result<(), TasksDbError> {
        Ok(())
    }

    fn compact(&self) {
        // No-op for in-memory implementation
    }
}
