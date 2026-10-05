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

use std::sync::Arc;

use moor_common::tasks::SessionFactory;

use crate::tasks::schedule_q::ScheduleQ;
use crate::tasks::task_q::TaskQ;

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

    /// Task ID counter.
    pub(crate) next_task_id: usize,

    /// Current collection phase and the identity of its owner.
    pub(crate) gc_phase: super::gc::GcPhase,
    /// Flag to force GC on next opportunity (set by gc_collect() builtin).
    pub(crate) gc_force_collect: bool,
    /// Number of GC cycles started, including failed cycles.
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

    /// Factory for the sessions scheduled firings run under; set at `start()`.
    pub(crate) bg_session_factory: Option<Arc<dyn SessionFactory>>,
}
