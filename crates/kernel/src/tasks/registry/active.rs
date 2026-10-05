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

//! Active task metadata and lock-free membership. The lifecycle mutex protects metadata.

use crate::tasks::{
    TaskNotification, TaskStart, task_control::TaskControl, task_telemetry::TaskRunBaseline,
};
use ahash::AHasher;
use flume::Sender;
use moor_common::{
    tasks::{SchedulerError, Session, TaskId},
    util::Instant,
};
use moor_var::{Obj, Var};
use papaya::HashMap as PapayaHashMap;
use std::{
    hash::BuildHasherDefault,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
};

struct LiveTasks {
    entries: PapayaHashMap<TaskId, u64, BuildHasherDefault<AHasher>>,
    next_generation: AtomicU64,
}

/// Lock-free membership index for tasks accepted by the scheduler.
#[derive(Clone)]
pub(crate) struct LiveTaskRegistry {
    tasks: Arc<LiveTasks>,
}

/// Exclusive ownership of a logical task's membership across attempts and wakeups.
/// Dropping an older registration cannot remove a replacement with the same task ID.
#[must_use]
pub(crate) struct LiveTaskRegistration {
    tasks: Arc<LiveTasks>,
    task_id: TaskId,
    generation: u64,
}

impl LiveTaskRegistration {
    pub(crate) fn task_id(&self) -> TaskId {
        self.task_id
    }
}

impl Drop for LiveTaskRegistration {
    fn drop(&mut self) {
        let _ = self
            .tasks
            .entries
            .pin()
            .remove_if(&self.task_id, |_, generation| {
                *generation == self.generation
            });
    }
}

impl LiveTaskRegistry {
    pub(super) fn new() -> Self {
        Self {
            tasks: Arc::new(LiveTasks {
                entries: PapayaHashMap::with_hasher(BuildHasherDefault::default()),
                next_generation: AtomicU64::new(0),
            }),
        }
    }

    #[inline]
    pub(crate) fn contains(&self, task_id: TaskId) -> bool {
        self.tasks.entries.pin().contains_key(&task_id)
    }

    pub(crate) fn register(&self, task_id: TaskId) -> LiveTaskRegistration {
        let generation = self
            .tasks
            .next_generation
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
            .expect("Live task registration generation exhausted");
        self.tasks.entries.pin().insert(task_id, generation);
        LiveTaskRegistration {
            tasks: self.tasks.clone(),
            task_id,
            generation,
        }
    }
}

/// Identity of one worker dispatch. Wakeup and conflict retry create a new control object.
/// Clones identify the same attempt; they do not own its completion or live registration.
#[derive(Clone)]
pub(crate) struct TaskAttempt {
    task_id: TaskId,
    control: Arc<TaskControl>,
}

impl TaskAttempt {
    pub(crate) fn new(task_id: TaskId, control: Arc<TaskControl>) -> Self {
        Self { task_id, control }
    }

    pub(crate) fn task_id(&self) -> TaskId {
        self.task_id
    }

    pub(super) fn matches(&self, task: &RunningTask) -> bool {
        Arc::ptr_eq(&self.control, &task.control)
    }
}

/// Scheduler-side phase for a task which still occupies the active-task slot.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum RunningTaskPhase {
    /// The VM may still be executing.
    Running,
    /// The VM has yielded and its session is finalizing before terminal result delivery.
    Completing(Result<Var, SchedulerError>),
    /// The VM has yielded and its session is committing before suspension.
    Suspending,
    /// The VM has yielded and its input request is being registered.
    RequestingInput,
}

/// Scheduler-side per-task record protected by the scheduler lifecycle lock.
/// The actual `Task` is owned by the task thread until it is suspended or completed.
/// (When suspended it is moved into a `SuspendedTask` in the `.suspended` list)
pub(crate) struct RunningTask {
    pub(crate) registration: LiveTaskRegistration,
    /// Unpublished messages and schedule operations owned by this active attempt.
    pub(crate) effects: crate::tasks::scheduler::effects::PendingTaskEffects,
    /// Current lifecycle phase while the task occupies the active slot.
    pub(crate) phase: RunningTaskPhase,
    /// For which player this task is running on behalf of.
    pub(crate) player: Obj,
    /// What triggered this task to start.
    pub(crate) task_start: TaskStart,
    /// When this task was submitted to the task-pool queue.
    pub(crate) dispatched_at: Instant,
    /// Immutable operating-system counters captured by the worker on entry.
    pub(crate) run_baseline: Arc<OnceLock<TaskRunBaseline>>,
    /// Arbitration between cancellation and transaction commit.
    pub(crate) control: Arc<TaskControl>,
    /// The connection-session for this task.
    pub(crate) session: Arc<dyn Session>,
    /// An error requested by a scheduler-side operation. The worker observes cancellation,
    /// rolls back, and reports this error instead of a generic cancellation.
    pub(crate) abort_error: Option<SchedulerError>,
    /// A mailbox to deliver the result of the task to a waiting party with a subscription, if any.
    pub(crate) result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
}
