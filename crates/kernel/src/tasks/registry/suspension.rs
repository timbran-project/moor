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

//! Suspended tasks and wake indexes, mutated under the scheduler lifecycle lock.

use super::active::{LiveTaskRegistration, LiveTaskRegistry};
use crate::tasks::{
    TaskDescription, TaskNotification, TaskStart, TasksDb,
    task::{Task, TaskState},
};
use ahash::AHasher;
use flume::Sender;
use hierarchical_hash_wheel_timer::wheels::{
    Skip, TimerEntryWithDelay,
    quad_wheel::{PruneDecision, QuadWheelWithOverflow},
};
use moor_common::{
    tasks::{SchedulerError, Session, TaskId},
    util::{Deadline, Instant, Timestamp},
};
use moor_var::{Obj, Var};
use std::{
    collections::{HashMap, VecDeque},
    hash::BuildHasherDefault,
    sync::Arc,
    time::{Duration, SystemTime},
};
use tracing::{error, warn};
use uuid::Uuid;

/// Timer entry for the hash wheel timer
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct TimerEntry {
    pub(super) task_id: TaskId,
    delay: Duration,
    /// Monotonic generation stamp assigned when the entry is created.
    /// Compared against the current `SuspendedTask::timer_generation` to
    /// detect stale entries left behind by earlier suspensions of the same task.
    pub(super) generation: u64,
}

impl TimerEntryWithDelay for TimerEntry {
    fn delay(&self) -> Duration {
        self.delay
    }
}
/// State a suspended task sits in inside the `suspended` side of the task queue.
/// When tasks are not running they are moved into these.
pub struct SuspendedTask {
    /// Timestamp when this task entered the suspended queue.
    pub enqueued_at: Timestamp,
    pub wake_condition: WakeCondition,
    pub task: Box<Task>,
    pub session: Arc<dyn Session>,
    pub result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
    /// Generation stamp matching the `TimerEntry` that belongs to this suspension.
    /// Stale timer entries from prior suspensions will carry a different value.
    pub timer_generation: u64,
}

/// A persisted continuation paired with its runtime membership owner.
/// The record format stays independent of registration lifetime.
pub(crate) struct RegisteredSuspendedTask {
    pub(crate) record: SuspendedTask,
    pub(crate) registration: LiveTaskRegistration,
}

impl std::ops::Deref for RegisteredSuspendedTask {
    type Target = SuspendedTask;
    fn deref(&self) -> &Self::Target {
        &self.record
    }
}

impl SuspendedTask {
    fn new(
        wake_condition: WakeCondition,
        task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
    ) -> Self {
        Self {
            enqueued_at: Timestamp::now(),
            wake_condition,
            task,
            session,
            result_sender,
            timer_generation: 0,
        }
    }
}

/// Possible conditions in which a suspended task can wake from suspension.
#[derive(Debug)]
pub enum WakeCondition {
    /// This task will never wake up on its own, and must be manually woken with `bf_resume`
    Never,
    /// This task will wake up when the given time is reached.
    Time(Instant),
    /// This task will wake up when the given input request is fulfilled.
    Input(Uuid),
    /// This task will wake up when the given task is completed.
    Task(TaskId),
    /// Wake immediately with optional return value. Some(val) for tasks that performed a commit(),
    /// None for brand new tasks that haven't executed yet.
    Immediate(Option<Var>),
    /// Wake when a worker responds to this request id
    Worker(Uuid),
    /// Wake when garbage collection completes
    GCComplete,
    /// Wake for retry after transaction conflict - includes backoff time
    Retry(Instant),
    /// Wake when a task message is delivered, or at deadline (whichever first)
    TaskMessage(Instant),
    /// Wake when this process's checkpoint generation completes.
    Checkpoint(u64),
    /// Wake when this process's storage-compaction generation completes.
    StorageCompaction(u64),
}

#[repr(u8)]
pub enum WakeConditionType {
    Never = 0,
    Time = 1,
    Input = 2,
    Task = 3,
    Immediate = 4,
    Worker = 5,
    GCComplete = 6,
    Retry = 7,
    TaskMessage = 8,
    Checkpoint = 9,
    StorageCompaction = 10,
}

impl WakeCondition {
    pub fn condition_type(&self) -> WakeConditionType {
        match self {
            WakeCondition::Never => WakeConditionType::Never,
            WakeCondition::Time(_) => WakeConditionType::Time,
            WakeCondition::Input(_) => WakeConditionType::Input,
            WakeCondition::Task(_) => WakeConditionType::Task,
            WakeCondition::Immediate(_) => WakeConditionType::Immediate,
            WakeCondition::Worker(_) => WakeConditionType::Worker,
            WakeCondition::GCComplete => WakeConditionType::GCComplete,
            WakeCondition::Retry(_) => WakeConditionType::Retry,
            WakeCondition::TaskMessage(_) => WakeConditionType::TaskMessage,
            WakeCondition::Checkpoint(_) => WakeConditionType::Checkpoint,
            WakeCondition::StorageCompaction(_) => WakeConditionType::StorageCompaction,
        }
    }
}

/// Ties the local storage for suspended tasks in with a reference to the tasks DB, to allow for
/// keeping them in sync.
pub struct SuspensionQ {
    /// All suspended tasks - the master storage
    tasks: HashMap<TaskId, RegisteredSuspendedTask, BuildHasherDefault<AHasher>>,

    /// Time-based tasks use a hash wheel timer (O(1) amortized)
    timer_wheel: QuadWheelWithOverflow<TimerEntry>,

    /// Last time we advanced the timer wheel (for tracking elapsed time)
    last_timer_advance: Option<Instant>,

    /// Queue for tasks that should wake immediately (O(1) push/pop)
    immediate_wake_queue: VecDeque<(TaskId, Timestamp)>,

    /// Tasks waiting for other tasks to complete (O(1) lookup by dependency)
    task_dependencies: HashMap<TaskId, Vec<TaskId>, BuildHasherDefault<AHasher>>,

    /// Tasks waiting for input by request ID, with the requested player connection.
    input_requests: HashMap<uuid::Uuid, (TaskId, Obj), BuildHasherDefault<AHasher>>,

    /// Tasks waiting for worker responses by request ID (O(1) lookup)
    worker_requests: HashMap<uuid::Uuid, TaskId, BuildHasherDefault<AHasher>>,

    /// Tasks waiting for GC completion
    gc_waiting_tasks: Vec<TaskId>,

    /// Tasks waiting for retry after transaction conflict
    retry_tasks: Vec<TaskId>,

    /// Tasks waiting for inter-task messages (via task_recv with timeout)
    pub(super) message_waiting_tasks: Vec<TaskId>,

    /// Monotonic counter for timer entry generation stamps.
    next_generation: u64,

    tasks_database: Box<dyn TasksDb>,
    pub(super) live_tasks: LiveTaskRegistry,
}

impl SuspensionQ {
    pub fn new(tasks_database: Box<dyn TasksDb>) -> Self {
        Self {
            tasks: Default::default(),
            // Create timer wheel with pruner that keeps all entries
            timer_wheel: QuadWheelWithOverflow::new(|_| PruneDecision::Keep),
            last_timer_advance: Some(Instant::now()),
            immediate_wake_queue: VecDeque::new(),
            task_dependencies: HashMap::default(),
            input_requests: HashMap::default(),
            worker_requests: HashMap::default(),
            gc_waiting_tasks: Vec::new(),
            retry_tasks: Vec::new(),
            message_waiting_tasks: Vec::new(),
            next_generation: 0,
            tasks_database,
            live_tasks: LiveTaskRegistry::new(),
        }
    }

    /// Borrow the persisted record without exposing registration or index mutation.
    pub(crate) fn get(&self, task_id: TaskId) -> Option<&SuspendedTask> {
        self.tasks.get(&task_id).map(|task| &task.record)
    }

    pub(crate) fn records(&self) -> impl Iterator<Item = &SuspendedTask> {
        self.tasks.values().map(|task| &task.record)
    }

    pub(super) fn is_empty(&self) -> bool {
        self.tasks.is_empty()
    }

    /// Check if a suspended task exists and return its controlling principal.
    pub(crate) fn task_owner(&self, task_id: TaskId) -> Option<Obj> {
        self.tasks
            .get(&task_id)
            .map(|st| st.task.authority_principal())
    }

    /// Queue a task for immediate wake.
    #[inline]
    pub(crate) fn enqueue_immediate_wake(&mut self, task_id: TaskId) {
        self.immediate_wake_queue
            .push_back((task_id, Timestamp::now()));
    }

    /// Pop the next task queued for immediate wake.
    #[inline]
    pub(crate) fn pop_immediate_wake(&mut self) -> Option<(TaskId, Timestamp)> {
        self.immediate_wake_queue.pop_front()
    }

    /// Queue all tasks waiting on `dependency_task_id` for immediate wake.
    pub(crate) fn enqueue_dependents_for(&mut self, dependency_task_id: TaskId) {
        let Some(dependents) = self.task_dependencies.remove(&dependency_task_id) else {
            return;
        };
        for task_id in dependents {
            self.enqueue_immediate_wake(task_id);
        }
    }

    /// Queue all tasks waiting for GC completion for immediate wake.
    pub(crate) fn enqueue_gc_waiting_tasks(&mut self) {
        let waiting_tasks = std::mem::take(&mut self.gc_waiting_tasks);
        for task_id in waiting_tasks {
            self.enqueue_immediate_wake(task_id);
        }
    }

    /// Advance the timer wheel based on elapsed time and return expired entries.
    pub(super) fn advance_timer_wheel(&mut self) -> Option<Vec<TimerEntry>> {
        let now = Instant::now();
        let last_advance = self.last_timer_advance.unwrap_or(now);

        if now <= last_advance {
            return None;
        }

        let elapsed_millis = now.duration_since(last_advance).as_millis() as u32;
        let mut millis_remaining = elapsed_millis;

        let mut expired_entries = None;

        while millis_remaining > 0 {
            match self.timer_wheel.can_skip() {
                Skip::Empty => {
                    // Wheel is empty - no timers, nothing to tick
                    self.timer_wheel.skip(millis_remaining);
                    break;
                }
                Skip::Millis(skippable) => {
                    let to_skip = skippable.min(millis_remaining);
                    self.timer_wheel.skip(to_skip);
                    millis_remaining -= to_skip;
                }
                Skip::None => {
                    // Next tick has expiring timers, must tick
                    expired_entries
                        .get_or_insert_with(Vec::new)
                        .extend(self.timer_wheel.tick());
                    millis_remaining -= 1;
                }
            }
        }

        self.last_timer_advance = Some(last_advance + Duration::from_millis(elapsed_millis as u64));

        expired_entries
    }

    /// Add a task to the set of suspended tasks.
    pub(crate) fn add_task(
        &mut self,
        wake_condition: WakeCondition,
        task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        registration: LiveTaskRegistration,
    ) {
        let input_player = task.player();
        self.insert_task(
            SuspendedTask::new(wake_condition, task, session, result_sender),
            input_player,
            registration,
        );
    }

    /// Register input against the requested player before exposing the suspended task.
    pub(crate) fn add_input_task(
        &mut self,
        input_request_id: Uuid,
        input_player: Obj,
        task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
        registration: LiveTaskRegistration,
    ) {
        self.insert_task(
            SuspendedTask::new(
                WakeCondition::Input(input_request_id),
                task,
                session,
                result_sender,
            ),
            input_player,
            registration,
        );
    }

    /// Install a restored continuation without rewriting its persisted record.
    /// Restore and ordinary suspension share the same wake-index registration.
    pub(super) fn register_restored_task(&mut self, mut task: SuspendedTask) {
        let task_id = task.task.task_id;
        let input_player = task.task.player();
        self.register_wake(&mut task, input_player);

        let registration = self.live_tasks.register(task_id);
        self.tasks.insert(
            task_id,
            RegisteredSuspendedTask {
                record: task,
                registration,
            },
        );
    }

    fn insert_task(
        &mut self,
        mut task: SuspendedTask,
        input_player: Obj,
        registration: LiveTaskRegistration,
    ) {
        assert_eq!(task.task.task_id, registration.task_id());
        let should_persist = self.register_wake(&mut task, input_player);
        if should_persist {
            self.persist_task(&task);
        }
        self.tasks.insert(
            task.task.task_id,
            RegisteredSuspendedTask {
                record: task,
                registration,
            },
        );
    }

    /// Register exactly the indexes implied by the wake condition. Returns persistence policy
    /// for a new suspension; restoration uses the indexes without rewriting each loaded record.
    fn register_wake(&mut self, task: &mut SuspendedTask, input_player: Obj) -> bool {
        let task_id = task.task.task_id;
        self.next_generation += 1;
        let generation = self.next_generation;
        task.timer_generation = generation;
        match &task.wake_condition {
            WakeCondition::Time(deadline) => self.register_timer(task_id, generation, *deadline),
            WakeCondition::Immediate(_) => {
                self.enqueue_immediate_wake(task_id);
                false
            }
            WakeCondition::Task(dependency) => {
                self.task_dependencies
                    .entry(*dependency)
                    .or_default()
                    .push(task_id);
                true
            }
            WakeCondition::Input(request) => {
                self.input_requests
                    .insert(*request, (task_id, input_player));
                false
            }
            WakeCondition::Worker(request) => {
                self.worker_requests.insert(*request, task_id);
                true
            }
            WakeCondition::Never => true,
            WakeCondition::GCComplete => {
                self.gc_waiting_tasks.push(task_id);
                true
            }
            WakeCondition::Retry(deadline) => {
                self.retry_tasks.push(task_id);
                self.register_timer(task_id, generation, *deadline);
                false
            }
            WakeCondition::TaskMessage(deadline) => {
                self.message_waiting_tasks.push(task_id);
                self.register_timer(task_id, generation, *deadline);
                true
            }
            WakeCondition::Checkpoint(_) | WakeCondition::StorageCompaction(_) => false,
        }
    }

    /// Expired or unrepresentable deadlines use the immediate queue. Only successfully
    /// armed ordinary timers are persisted when first suspended.
    fn register_timer(&mut self, task_id: TaskId, generation: u64, deadline: Instant) -> bool {
        let inserted = Deadline::at(deadline)
            .remaining_at(Instant::now())
            .is_some_and(|delay| {
                let entry = TimerEntry {
                    task_id,
                    generation,
                    delay,
                };
                self.timer_wheel.insert_with_delay(entry, delay).is_ok()
            });
        if !inserted {
            self.enqueue_immediate_wake(task_id);
        }
        inserted
    }

    /// Remove one registration. Timer and immediate entries can remain stale until dispatch.
    fn unregister_wake(&mut self, task_id: TaskId, wake_condition: &WakeCondition) {
        match wake_condition {
            WakeCondition::Time(_)
            | WakeCondition::Immediate(_)
            | WakeCondition::Never
            | WakeCondition::Checkpoint(_)
            | WakeCondition::StorageCompaction(_) => {}
            WakeCondition::Task(dependency_task_id) => {
                // Remove from task dependencies
                if let Some(dependents) = self.task_dependencies.get_mut(dependency_task_id) {
                    dependents.retain(|&id| id != task_id);
                    if dependents.is_empty() {
                        self.task_dependencies.remove(dependency_task_id);
                    }
                }
            }
            WakeCondition::Input(input_request_id) => {
                self.input_requests.remove(input_request_id);
            }
            WakeCondition::Worker(worker_request_id) => {
                self.worker_requests.remove(worker_request_id);
            }
            WakeCondition::GCComplete => {
                self.gc_waiting_tasks.retain(|&id| id != task_id);
            }
            WakeCondition::Retry(_) => {
                self.retry_tasks.retain(|&id| id != task_id);
            }
            WakeCondition::TaskMessage(_) => {
                self.message_waiting_tasks.retain(|&id| id != task_id);
            }
        }
    }

    /// Remove a task from suspension, retaining live membership for a wakeup transfer.
    pub(crate) fn remove_task(&mut self, task_id: TaskId) -> Option<RegisteredSuspendedTask> {
        let task = self.tasks.remove(&task_id)?;
        self.unregister_wake(task_id, &task.wake_condition);
        self.delete_persisted_task(task_id);
        Some(task)
    }

    /// Remove a task permanently from suspension and wake tasks depending on it.
    pub(crate) fn remove_task_terminal(&mut self, task_id: TaskId) -> Option<SuspendedTask> {
        let RegisteredSuspendedTask {
            record,
            registration,
        } = self.remove_task(task_id)?;
        drop(registration);
        self.enqueue_dependents_for(task_id);
        Some(record)
    }

    /// The backing store, shared with the native schedule queue.
    pub(crate) fn tasks_db(&self) -> &dyn TasksDb {
        self.tasks_database.as_ref()
    }

    /// Pull a task waiting for input from the responding connection or player.
    /// Uses O(1) lookup instead of O(n) linear scan.
    pub(crate) fn pull_task_for_input(
        &mut self,
        input_request_id: Uuid,
        connection: &Obj,
        player: &Obj,
    ) -> Option<RegisteredSuspendedTask> {
        // O(1) lookup by input request ID
        let &(task_id, input_player) = self.input_requests.get(&input_request_id)?;

        // Input must come from the connection selected by read().
        if input_player.ne(connection) && input_player.ne(player) {
            warn!(
                ?task_id,
                ?input_request_id,
                ?connection,
                ?player,
                ?input_player,
                "Task input request received for wrong player"
            );
            return None;
        }

        // Remove and return the task
        self.remove_task(task_id)
    }

    /// Pull a task from the suspended list that is waiting for a worker response.
    /// Uses O(1) lookup instead of O(n) linear scan.
    pub(crate) fn pull_task_for_worker(
        &mut self,
        worker_request_id: Uuid,
    ) -> Option<RegisteredSuspendedTask> {
        // O(1) lookup by worker request ID
        let &task_id = self.worker_requests.get(&worker_request_id)?;

        // Remove and return the task
        self.remove_task(task_id)
    }

    /// Get a nice friendly list of all tasks in suspension state.
    pub(crate) fn tasks(&self) -> Vec<TaskDescription> {
        let mut tasks = Vec::new();

        // Suspended tasks.
        for sr in self.tasks.values() {
            let start_time = match sr.wake_condition {
                WakeCondition::Time(t) => {
                    let distance_from_now = Deadline::at(t).remaining().unwrap_or(Duration::ZERO);
                    Some(SystemTime::now() + distance_from_now)
                }
                WakeCondition::Task(task_id) => {
                    if self.tasks.contains_key(&task_id) {
                        Some(SystemTime::now() + Duration::from_secs(1000000000))
                    } else {
                        None
                    }
                }
                _ => None,
            };
            // For tasks in Created state (not yet started), we need to extract info from TaskStart
            // because the vm_host stack is still empty (setup_task_start hasn't been called yet)
            let (verb_name, verb_definer, line_number, this) = match &sr.task.state {
                TaskState::Pending(task_start) => {
                    // Extract info from the TaskStart since vm_host isn't initialized yet
                    match task_start {
                        TaskStart::StartFork { fork_request, .. } => {
                            let activation = &fork_request.activation;
                            (
                                activation.verb_name,
                                activation.verb_definer(),
                                activation.frame.find_line_no().unwrap_or(0),
                                activation.this.clone(),
                            )
                        }
                        _ => {
                            // For other task types in Created state, we can't get this info yet
                            // Use placeholder values
                            (
                                moor_var::Symbol::mk(""),
                                moor_var::NOTHING,
                                0,
                                moor_var::v_none(),
                            )
                        }
                    }
                }
                TaskState::Prepared(_) => {
                    // Prefer the top non-builtin frame so builtins like suspend() don't mask
                    // the calling verb in queued_tasks().
                    let activation = sr
                        .task
                        .vm_host
                        .vm_exec_state()
                        .stack
                        .iter()
                        .rev()
                        .find(|a| !a.is_builtin_frame());
                    if let Some(activation) = activation {
                        let line_number = activation.frame.find_line_no().unwrap_or(0);
                        (
                            activation.verb_name,
                            activation.verb_definer(),
                            line_number,
                            activation.this.clone(),
                        )
                    } else {
                        // For prepared tasks, vm_host stack MUST be non-empty
                        let Some(((verb_name, verb_definer), (line_number, this))) = sr
                            .task
                            .vm_host
                            .verb_name()
                            .zip(sr.task.vm_host.verb_definer())
                            .zip(sr.task.vm_host.line_number().zip(sr.task.vm_host.this()))
                        else {
                            error!(
                                task_id = sr.task.task_id,
                                "Prepared task has empty activation stack - skipping"
                            );
                            continue;
                        };
                        (verb_name, verb_definer, line_number, this)
                    }
                }
            };

            tasks.push(TaskDescription {
                task_id: sr.task.task_id,
                start_time,
                authority_principal: sr.task.authority_principal(),
                verb_name,
                verb_definer,
                line_number,
                this,
            });
        }
        tasks
    }

    /// Check whether an authority principal controls a suspended task.
    ///
    /// LambdaMOO's suspended-task rule is dual:
    /// - Input-waiting tasks are controlled by the task player.
    /// - Computational tasks are controlled by the task authority principal.
    ///
    /// Resume filters input-waiting tasks, while kill permits them, so callers must choose whether
    /// input waits participate in the check.
    pub(crate) fn authority_principal_controls_task(
        &self,
        task_id: TaskId,
        authority_principal: Obj,
        include_input_waiting: bool,
    ) -> bool {
        let Some(sr) = self.tasks.get(&task_id) else {
            return false;
        };

        if !include_input_waiting && matches!(sr.wake_condition, WakeCondition::Input(_)) {
            return false;
        }

        let controlling_principal = if matches!(sr.wake_condition, WakeCondition::Input(_)) {
            sr.task.player()
        } else {
            sr.task.authority_principal()
        };

        authority_principal == controlling_principal
    }

    /// Remove all non-background tasks for the given player.
    pub(crate) fn prune_foreground_tasks(&mut self, player: &Obj) {
        let to_remove = self
            .tasks
            .iter()
            .filter_map(|(task_id, sr)| {
                (!sr.task.state.is_background() && sr.task.player().eq(player)).then_some(*task_id)
            })
            .collect::<Vec<_>>();
        for task_id in to_remove {
            self.remove_task_terminal(task_id);
        }
    }

    /// Trigger database compaction to reclaim space and reduce journal size.
    pub(crate) fn compact(&self) {
        self.tasks_database.compact();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tasks::{
        DEFAULT_DB_COMMIT_QUEUE_TIMEOUT, DEFAULT_DB_COMMIT_QUEUE_WARN, DEFAULT_MAX_TASK_MAILBOX,
        DEFAULT_MAX_TASK_RETRIES, NoopTasksDb, ServerOptions, TaskStart, task_control::TaskControl,
    };
    use moor_common::tasks::NoopClientSession;
    use moor_var::SYSTEM_OBJECT;

    fn test_server_options() -> ServerOptions {
        ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        }
    }

    fn mock_task(task_id: TaskId) -> Box<Task> {
        mock_task_with_identity(task_id, SYSTEM_OBJECT, SYSTEM_OBJECT)
    }

    fn mock_task_with_identity(
        task_id: TaskId,
        player: Obj,
        authority_principal: Obj,
    ) -> Box<Task> {
        Task::new(
            task_id,
            player,
            authority_principal,
            TaskStart::StartEval {
                player,
                program: Default::default(),
                initial_env: None,
            },
            &test_server_options(),
            Arc::new(TaskControl::new()),
        )
    }

    fn mock_session() -> Arc<dyn Session> {
        Arc::new(NoopClientSession::new())
    }

    #[test]
    fn restored_waiters_respond_to_completion_events() {
        use crate::tasks::TasksDbError;
        use moor_common::tasks::{SessionError, SessionFactory};
        use parking_lot::Mutex;

        struct RestoreDb(Mutex<Vec<SuspendedTask>>);
        impl TasksDb for RestoreDb {
            fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError> {
                Ok(std::mem::take(&mut *self.0.lock()))
            }
            fn save_task(&self, _: &SuspendedTask) -> Result<(), TasksDbError> {
                panic!("restoration must not rewrite each loaded task")
            }
            fn delete_task(&self, _: TaskId) -> Result<(), TasksDbError> {
                Ok(())
            }
            fn delete_all_tasks(&self) -> Result<(), TasksDbError> {
                Ok(())
            }
            fn compact(&self) {}
        }
        struct Factory;
        impl SessionFactory for Factory {
            fn mk_background_session(
                self: Arc<Self>,
                _: &Obj,
            ) -> Result<Arc<dyn Session>, SessionError> {
                Ok(mock_session())
            }
        }
        let worker = Uuid::new_v4();
        let input = Uuid::new_v4();
        let tasks = [
            WakeCondition::GCComplete,
            WakeCondition::Task(99),
            WakeCondition::Worker(worker),
            WakeCondition::Input(input),
        ]
        .into_iter()
        .enumerate()
        .map(|(id, condition)| {
            SuspendedTask::new(condition, mock_task(id + 1), mock_session(), None)
        })
        .collect();
        let mut queue = SuspensionQ::new(Box::new(RestoreDb(Mutex::new(tasks))));
        assert_eq!(queue.load_tasks(Arc::new(Factory)), Some(4));

        queue.enqueue_gc_waiting_tasks();
        queue.enqueue_dependents_for(99);
        assert_eq!(queue.pop_immediate_wake().unwrap().0, 1);
        assert_eq!(queue.pop_immediate_wake().unwrap().0, 2);
        assert!(queue.pop_immediate_wake().is_none());
        assert_eq!(queue.pull_task_for_worker(worker).unwrap().task.task_id, 3);
        assert!(queue.pull_task_for_worker(worker).is_none());
        assert_eq!(
            queue
                .pull_task_for_input(input, &SYSTEM_OBJECT, &SYSTEM_OBJECT)
                .unwrap()
                .task
                .task_id,
            4
        );
        assert!(
            queue
                .pull_task_for_input(input, &SYSTEM_OBJECT, &SYSTEM_OBJECT)
                .is_none()
        );
    }

    #[test]
    fn gc_completion_wakes_registered_waiters_only_once() {
        let mut queue = SuspensionQ::new(Box::new(NoopTasksDb {}));
        for id in [1, 2] {
            queue.add_task(
                WakeCondition::GCComplete,
                mock_task(id),
                mock_session(),
                None,
                queue.live_tasks.register(id),
            );
        }
        queue.remove_task_terminal(2).unwrap();
        queue.enqueue_gc_waiting_tasks();
        assert_eq!(queue.pop_immediate_wake().unwrap().0, 1);
        assert!(queue.pop_immediate_wake().is_none());
        queue.enqueue_gc_waiting_tasks();
        assert!(queue.pop_immediate_wake().is_none());
    }

    #[test]
    fn live_task_registry_supports_concurrent_reads() {
        let registry = LiveTaskRegistry::new();
        let registration = registry.register(42);

        std::thread::scope(|scope| {
            for _ in 0..8 {
                let registry = registry.clone();
                scope.spawn(move || {
                    for _ in 0..10_000 {
                        assert!(registry.contains(42));
                    }
                });
            }
        });

        drop(registration);
        assert!(!registry.contains(42));
    }

    #[test]
    fn input_request_is_bound_to_requested_player_not_task_authority() {
        let task_id = 42;
        let task_player = Obj::mk_id(2);
        let authority_principal = Obj::mk_id(3);
        let input_player = Obj::mk_id(4);
        let wrong_player = Obj::mk_id(5);
        let input_request_id = Uuid::new_v4();
        let mut sq = SuspensionQ::new(Box::new(NoopTasksDb {}));

        sq.add_input_task(
            input_request_id,
            input_player,
            mock_task_with_identity(task_id, task_player, authority_principal),
            mock_session(),
            None,
            sq.live_tasks.register(task_id),
        );

        assert!(
            sq.pull_task_for_input(input_request_id, &wrong_player, &wrong_player)
                .is_none(),
            "input from another player must not consume the request"
        );
        let suspended = sq
            .pull_task_for_input(input_request_id, &input_player, &input_player)
            .expect("the requested player should fulfill the input request");
        assert_eq!(suspended.task.task_id, task_id);
    }

    /// Verify that stale timer entries from prior suspensions of the same task
    /// are filtered out and do not cause spurious wakes.
    ///
    /// Scenario: a task calls `task_recv(0.05)` which inserts a 50ms timer.
    /// A message arrives early, waking the task via `enqueue_immediate_wake`.
    /// The task re-suspends with a new `task_recv(0.05)`, inserting a second
    /// timer entry. The old entry still sits in the wheel. When it fires, the
    /// generation mismatch should cause it to be discarded.
    #[test]
    fn stale_timer_entry_filtered_by_generation() {
        let task_id: TaskId = 42;
        let mut sq = SuspensionQ::new(Box::new(NoopTasksDb {}));

        // First suspension: task_recv with 50ms timeout.
        let deadline1 = Deadline::from_now(Duration::from_millis(50)).instant();
        sq.add_task(
            WakeCondition::TaskMessage(deadline1),
            mock_task(task_id),
            mock_session(),
            None,
            sq.live_tasks.register(task_id),
        );
        let gen1 = sq.tasks.get(&task_id).unwrap().timer_generation;

        // Simulate early wake from message delivery: remove the task from
        // the suspended map (the timer entry remains in the wheel).
        let removed = sq.remove_task(task_id);
        assert!(removed.is_some());

        // Re-suspend the same task with a new 100ms timeout.
        // This gets a fresh generation, while the stale 50ms entry lingers.
        let deadline2 = Deadline::from_now(Duration::from_millis(100)).instant();
        sq.add_task(
            WakeCondition::TaskMessage(deadline2),
            mock_task(task_id),
            mock_session(),
            None,
            sq.live_tasks.register(task_id),
        );
        let gen2 = sq.tasks.get(&task_id).unwrap().timer_generation;
        assert_ne!(
            gen1, gen2,
            "second suspension must have a different generation"
        );

        // Sleep past the first timer's deadline (50ms) but not the second (100ms).
        std::thread::sleep(Duration::from_millis(60));

        // Advance the timer wheel — the stale 50ms entry should fire.
        let expired = sq.advance_timer_wheel();
        // There may be expired entries, but after filtering by generation,
        // none should match the current task.
        if let Some(entries) = &expired {
            let matching: Vec<_> = entries
                .iter()
                .filter(|e| {
                    sq.tasks
                        .get(&e.task_id)
                        .is_some_and(|st| st.timer_generation == e.generation)
                })
                .collect();
            assert!(
                matching.is_empty(),
                "stale timer entry should not match current generation"
            );
        }

        // Now sleep past the second timer's deadline.
        std::thread::sleep(Duration::from_millis(50));

        // Advance again — the valid 100ms entry should fire.
        let expired2 = sq.advance_timer_wheel();
        assert!(expired2.is_some(), "second timer entry should have expired");
        let entries2 = expired2.unwrap();
        let matching2: Vec<_> = entries2
            .iter()
            .filter(|e| {
                sq.tasks
                    .get(&e.task_id)
                    .is_some_and(|st| st.timer_generation == e.generation)
            })
            .collect();
        assert_eq!(
            matching2.len(),
            1,
            "exactly one valid timer entry should match"
        );
        assert_eq!(matching2[0].task_id, task_id);
        assert_eq!(matching2[0].generation, gen2);
    }
}
