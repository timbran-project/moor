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

//! Task membership and mailbox storage. Registry methods borrow state and never acquire the lifecycle mutex.

use crate::{tasks::task_pool::TaskThreadPool, vm::extract_anonymous_refs_from_vm_exec_state};
use ahash::AHasher;
use moor_common::{
    tasks::{SchedulerError, TaskId},
    util::Timestamp,
};
use moor_var::{Obj, Var};
use std::{
    collections::{HashMap, VecDeque},
    hash::BuildHasherDefault,
};

mod active;
mod operations;
mod persistence;
mod suspension;

pub(crate) use active::{LiveTaskRegistration, LiveTaskRegistry, RunningTask, RunningTaskPhase};
pub(crate) use operations::TaskSubmission;
pub(crate) use suspension::RegisteredSuspendedTask;
pub use suspension::{SuspendedTask, SuspensionQ, WakeCondition};

/// Task membership and shared mailboxes under the lifecycle mutex.
pub struct TaskQ {
    /// Information about the active, running tasks. The actual `Task` is owned by the task thread
    /// and this is just an information, and control record for communicating with it.
    pub(crate) active: HashMap<TaskId, RunningTask, BuildHasherDefault<AHasher>>,
    /// Tasks in various types of suspension:
    ///     Forked background tasks that will execute someday
    ///     Suspended foreground tasks that are either indefinitely suspended or will execute someday
    ///     Suspended tasks waiting for input from the player or a task id to complete
    pub(crate) suspended: SuspensionQ,
    /// Thread pool for task execution
    pub(crate) thread_pool: TaskThreadPool,
    /// Inter-task message queues. Keyed by receiving task_id, shared across active and suspended.
    /// Each message stores enqueue timestamp for mailbox-wait latency accounting.
    pub(crate) task_message_queues:
        HashMap<TaskId, VecDeque<(Timestamp, Var)>, BuildHasherDefault<AHasher>>,
    /// Task membership shared with lock-free scheduler readers.
    pub(crate) live_tasks: LiveTaskRegistry,
    /// Terminal results delivered since the last drain, for the scheduler to
    /// settle native-schedule firings against. Every terminal path funnels
    /// through `send_task_result_direct`, so recording there catches them all.
    pub(crate) settled_results: Vec<(TaskId, Result<Var, SchedulerError>)>,
}

impl TaskQ {
    pub fn new(suspended: SuspensionQ) -> Self {
        let live_tasks = suspended.live_tasks.clone();
        let thread_pool = TaskThreadPool::configured().expect("Failed to create task thread pool");

        Self {
            active: Default::default(),
            suspended,
            thread_pool,
            task_message_queues: HashMap::default(),
            live_tasks,
            settled_results: Vec::new(),
        }
    }

    #[inline]
    pub(crate) fn insert_active(&mut self, task_id: TaskId, task: RunningTask) {
        assert_eq!(task_id, task.registration.task_id());
        self.active.insert(task_id, task);
    }

    #[inline]
    pub(crate) fn register_task(&self, task_id: TaskId) -> LiveTaskRegistration {
        self.live_tasks.register(task_id)
    }

    /// Check if a task exists and return its controlling principal.
    /// Checks both active and suspended tasks atomically.
    pub(crate) fn task_owner(&self, task_id: TaskId) -> Option<Obj> {
        // Check active tasks first
        if let Some(running) = self.active.get(&task_id) {
            return Some(running.player);
        }

        // Check suspended tasks
        self.suspended.task_owner(task_id)
    }

    /// Collect tasks that need to be woken up by timer, pull them from our suspended list, and
    /// return them. Other wake paths are event-driven through the immediate wake queue.
    pub(crate) fn collect_wake_tasks(&mut self) -> Option<Vec<RegisteredSuspendedTask>> {
        let mut to_wake: Option<Vec<TaskId>> = None;

        // 1. Advance timer wheel based on elapsed time and collect expired timers
        // (Always advance the timer wheel to maintain accurate timing, even when no tasks are suspended)
        if let Some(expired_timers) = self.suspended.advance_timer_wheel() {
            to_wake.get_or_insert_with(Vec::new).extend(
                expired_timers
                    .into_iter()
                    .filter(|e| {
                        // Ignore stale timer entries from prior suspensions of the same task.
                        self.suspended
                            .get(e.task_id)
                            .is_some_and(|st| st.timer_generation == e.generation)
                    })
                    .map(|e| e.task_id),
            );
        }

        if self.suspended.is_empty() {
            return None;
        }
        let to_wake = to_wake?;
        let tasks: Vec<_> = to_wake
            .into_iter()
            .filter_map(|task_id| self.suspended.remove_task(task_id))
            .collect();

        if tasks.is_empty() { None } else { Some(tasks) }
    }

    /// Collect anonymous object references from all suspended tasks
    pub(crate) fn collect_anonymous_object_references(&self) -> std::collections::HashSet<Obj> {
        let mut refs = std::collections::HashSet::new();

        // Scan all suspended tasks
        for suspended_task in self.suspended.records() {
            // Scan the current VM state
            let current_vm_state = suspended_task.task.vm_host.vm_exec_state();
            extract_anonymous_refs_from_vm_exec_state(current_vm_state, &mut refs);

            // Scan the retry state
            extract_anonymous_refs_from_vm_exec_state(&suspended_task.task.retry_state, &mut refs);
        }

        refs
    }

    /// Deliver a message to a task's incoming queue. If the target task is suspended
    /// waiting for messages (WakeCondition::TaskMessage), trigger an immediate wake.
    pub(crate) fn deliver_message(&mut self, target_task_id: TaskId, value: Var) {
        self.task_message_queues
            .entry(target_task_id)
            .or_default()
            .push_back((Timestamp::now(), value));

        // If the target is suspended and waiting for messages, wake it immediately
        if self
            .suspended
            .message_waiting_tasks
            .contains(&target_task_id)
        {
            self.suspended.enqueue_immediate_wake(target_task_id);
        }
    }

    /// Drain all messages from a task's queue, returning them.
    pub(crate) fn drain_messages(&mut self, task_id: TaskId) -> Vec<Var> {
        let (messages, _, _) = self.drain_messages_with_wait_nanos(task_id);
        messages
    }

    /// Drain all messages from a task's queue and include aggregate wait-time accounting.
    /// Returns `(messages, total_wait_nanos, message_count)`.
    pub(crate) fn drain_messages_with_wait_nanos(
        &mut self,
        task_id: TaskId,
    ) -> (Vec<Var>, u128, usize) {
        let now = Timestamp::now();
        self.task_message_queues
            .remove(&task_id)
            .map(|q| {
                let mut total_wait_nanos = 0u128;
                let mut messages = Vec::with_capacity(q.len());
                let message_count = q.len();
                for (enqueued_at, value) in q {
                    total_wait_nanos += now.duration_since(enqueued_at).as_nanos();
                    messages.push(value);
                }
                (messages, total_wait_nanos, message_count)
            })
            .unwrap_or((Vec::new(), 0, 0))
    }

    /// Return the current number of messages in a task's mailbox.
    pub(crate) fn mailbox_len(&self, task_id: TaskId) -> usize {
        self.task_message_queues
            .get(&task_id)
            .map_or(0, |q| q.len())
    }

    /// Remove a task's message queue (e.g., when task is killed/completed).
    pub(crate) fn remove_message_queue(&mut self, task_id: TaskId) {
        self.task_message_queues.remove(&task_id);
    }

    /// Trigger database compaction to reclaim space and reduce journal size.
    pub fn compact(&self) {
        self.suspended.compact();
    }
}
