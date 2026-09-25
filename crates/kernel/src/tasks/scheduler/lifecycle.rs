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

//! TaskLifecycle: all mutable state that must be consistent during task state transitions.
//! Protected by a single Mutex in the Scheduler handle.

use std::collections::HashMap;
use std::sync::Arc;

use moor_common::tasks::{SessionFactory, TaskId};
use moor_var::Var;

use crate::tasks::schedule_q::{ScheduleId, ScheduleQ};
use crate::tasks::task_q::TaskQ;

/// A schedule mutation a task has asked for but not yet committed. Flushed to
/// the `ScheduleQ` when the task commits, discarded on rollback or conflict
/// retry, so `schedule_at()` behaves like a world-state write rather than
/// like `fork`.
#[derive(Debug)]
pub(crate) enum PendingScheduleOp {
    Create(Box<crate::tasks::schedule_q::PendingCreate>),
    Stop(ScheduleId),
}

/// Lifecycle state for the scheduler and its service threads.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SchedulerState {
    /// Constructed, but task rehydration and service threads have not started.
    Created,
    /// Accepting requests and dispatching tasks.
    Running,
    /// Rejecting new work while shutdown is in progress.
    Stopping,
    /// Shutdown has completed. A stopped scheduler cannot be restarted.
    Stopped,
}

/// All mutable state that must be consistent during task state transitions.
/// Protected by a single Mutex in the Scheduler handle.
pub(crate) struct TaskLifecycle {
    /// The internal task queue holding active and suspended tasks.
    pub(crate) task_q: TaskQ,

    /// Buffered inter-task messages awaiting commit. Keyed by sending task_id.
    /// Delivered to target queues when the sending task commits; discarded on abort/conflict.
    pub(crate) pending_task_sends: HashMap<TaskId, Vec<(TaskId, Var)>>,

    /// Task ID counter.
    pub(crate) next_task_id: usize,

    /// Anonymous object garbage collection flag.
    pub(crate) gc_collection_in_progress: bool,
    /// Flag indicating concurrent GC mark phase is in progress.
    pub(crate) gc_mark_in_progress: bool,
    /// Flag indicating GC sweep phase is in progress (blocks new tasks).
    pub(crate) gc_sweep_in_progress: bool,
    /// Flag to force GC on next opportunity (set by gc_collect() builtin).
    pub(crate) gc_force_collect: bool,
    /// Counter tracking the number of GC cycles completed.
    pub(crate) gc_cycle_count: u64,
    /// Time of last GC cycle (for interval-based collection).
    pub(crate) gc_last_cycle_time: std::time::Instant,

    /// Transaction timestamp (monotonically incrementing) of the last mutating task/transaction.
    pub(crate) last_mutation_timestamp: Option<u64>,

    /// Current scheduler lifecycle state.
    pub(crate) state: SchedulerState,

    /// Time of last tasks DB compaction (independent of GC).
    pub(crate) last_compact_time: std::time::Instant,

    /// Native scheduled tasks: records of intent, fired from the timer loop.
    pub(crate) schedule_q: ScheduleQ,

    /// Schedule creations/stops buffered per task until that task commits.
    pub(crate) pending_schedule_ops: HashMap<TaskId, Vec<PendingScheduleOp>>,

    /// Factory for the sessions scheduled firings run under; set at `start()`.
    pub(crate) bg_session_factory: Option<Arc<dyn SessionFactory>>,
}

impl TaskLifecycle {
    /// Apply the schedule mutations a task buffered, now that it has committed.
    pub(crate) fn flush_pending_schedule_ops(&mut self, task_id: TaskId) {
        if let Some(ops) = self.pending_schedule_ops.remove(&task_id) {
            let now = std::time::SystemTime::now();
            for op in ops {
                match op {
                    PendingScheduleOp::Create(create) => self.schedule_q.add_pending(*create, now),
                    PendingScheduleOp::Stop(id) => {
                        self.schedule_q.stop(id);
                    }
                }
            }
        }
    }

    /// Drop a task's buffered schedule mutations (rollback / conflict retry).
    pub(crate) fn discard_pending_schedule_ops(&mut self, task_id: TaskId) {
        self.pending_schedule_ops.remove(&task_id);
    }

    /// Settle native-schedule firings against the terminal results delivered
    /// since the last call: re-arm or retire each schedule whose task just
    /// ended. Conflict retries never produce a terminal result, so they never
    /// reach here (the retry is the same firing). Cheap when nothing is
    /// scheduled; called from the terminal callbacks and the timer loop.
    pub(crate) fn settle_schedule_firings(&mut self) {
        if self.task_q.settled_results.is_empty() {
            return;
        }
        let results = std::mem::take(&mut self.task_q.settled_results);
        let now = std::time::SystemTime::now();
        for (task_id, result) in results {
            let Some(schedule_id) = self.schedule_q.schedule_for_task(task_id) else {
                continue;
            };
            let outcome = match result {
                Ok(v) => crate::tasks::schedule_q::Outcome::Success(v),
                Err(moor_common::tasks::SchedulerError::TaskAbortedException(e)) => {
                    crate::tasks::schedule_q::Outcome::Fault(moor_var::v_error(e.error))
                }
                Err(e) => {
                    crate::tasks::schedule_q::Outcome::Fault(moor_var::v_str(&format!("{e:?}")))
                }
            };
            self.schedule_q.complete(schedule_id, outcome, now);
        }
    }

    /// Deliver all buffered messages from the given task to their target queues.
    /// Called when a task commits (success, suspend, input request, exception, new transaction).
    pub(crate) fn flush_pending_sends(&mut self, task_id: TaskId) {
        self.flush_pending_schedule_ops(task_id);
        if let Some(sends) = self.pending_task_sends.remove(&task_id) {
            for (target_task_id, value) in sends {
                self.task_q.deliver_message(target_task_id, value);
            }
        }
    }

    /// Discard all buffered messages from the given task without delivering.
    /// Called when task finalization rolls back its effects.
    pub(crate) fn discard_pending_sends(&mut self, task_id: TaskId) {
        self.discard_pending_schedule_ops(task_id);
        self.pending_task_sends.remove(&task_id);
    }
}
