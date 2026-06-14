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

use std::{fmt::Debug, sync::LazyLock, time::SystemTime};

use flume::Receiver;
use moor_compiler::{Program, to_literal};
use moor_var::{List, Obj, Symbol, Var};

pub use crate::tasks::tasks_db::{NoopTasksDb, TasksDb, TasksDbError};
use crate::vm::Fork;
use fast_telemetry::{DeriveLabel, ExportMetrics, LabeledSampledTimer};
use moor_common::tasks::{Exception, SchedulerError, TaskId};
use moor_common::util::hot_stride;

/// Shared sink for batch world state task results.
/// Written by the task thread, read by the caller after the task completes.
pub type BatchResultSink = std::sync::Arc<
    std::sync::Mutex<Option<Result<Vec<world_state_action::WorldStateResult>, SchedulerError>>>,
>;

pub mod scheduler;

pub(crate) mod checkpoint;
pub mod convert_task;
pub(crate) mod gc_thread;
pub(crate) mod scheduler_client;
pub(crate) mod task;
pub(crate) mod task_pool;
pub(crate) mod task_program_cache;
pub(crate) mod task_q;
pub mod task_scheduler_client;
mod tasks_db;
pub mod workers;
pub mod world_state_action;
pub(crate) mod world_state_executor;

pub use task_program_cache::TaskProgramCache;

pub const DEFAULT_FG_TICKS: usize = 60_000;
pub const DEFAULT_BG_TICKS: usize = 30_000;
pub const DEFAULT_FG_SECONDS: f64 = 5.0;
pub const DEFAULT_BG_SECONDS: f64 = 3.0;
pub const DEFAULT_MAX_STACK_DEPTH: usize = 50;
pub const DEFAULT_GC_INTERVAL_SECONDS: u64 = 30;
pub const DEFAULT_MAX_TASK_RETRIES: u8 = 10;
pub const DEFAULT_MAX_TASK_MAILBOX: usize = 1000;
/// Interval for tasks DB compaction (independent of GC)
pub const DEFAULT_COMPACT_INTERVAL_SECONDS: u64 = 300;

static SCHED_COUNTERS: LazyLock<SchedulerPerfCounters> = LazyLock::new(SchedulerPerfCounters::new);

thread_local! {
    static SCHED_COUNTERS_TLS: &'static SchedulerPerfCounters = &SCHED_COUNTERS;
}

pub fn sched_counters() -> &'static SchedulerPerfCounters {
    SCHED_COUNTERS_TLS.with(|c| *c)
}

/// Just a handle to a task, with a receiver for the result.
pub struct TaskHandle(
    TaskId,
    Receiver<(TaskId, Result<TaskNotification, SchedulerError>)>,
);

// Results from a task which are either a value or a notification that the underlying task handle
// was replaced at the whim of the scheduler.
pub enum TaskNotification {
    /// Task is completed, and here are its results.
    Result(Var),
    /// Task has transitioned into a suspended/background state.
    Suspended,
}

impl Debug for TaskHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TaskHandle")
            .field("task_id", &self.0)
            .finish()
    }
}

impl TaskHandle {
    pub fn task_id(&self) -> TaskId {
        self.0
    }

    /// Dissolve the handle into a receiver for the result.
    pub fn into_receiver(self) -> Receiver<(TaskId, Result<TaskNotification, SchedulerError>)> {
        self.1
    }

    pub fn receiver(&self) -> &Receiver<(TaskId, Result<TaskNotification, SchedulerError>)> {
        &self.1
    }

    /// Create a new TaskHandle (for testing/mocking purposes)
    pub fn new_mock(
        task_id: TaskId,
        receiver: Receiver<(TaskId, Result<TaskNotification, SchedulerError>)>,
    ) -> Self {
        Self(task_id, receiver)
    }
}

/// External interface description of a task, for purpose of e.g. the queued_tasks() builtin.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct TaskDescription {
    pub task_id: TaskId,
    pub start_time: Option<SystemTime>,
    /// Authority principal for the task. MOO-facing task builtins expose this as the programmer.
    pub permissions: Obj,
    pub verb_name: Symbol,
    pub verb_definer: Obj,
    pub line_number: usize,
    pub this: Var,
}

/// The set of options that can be configured for the server via core $server_options.
/// bf_load_server_options refreshes the server options from the database.
#[derive(Debug, Clone)]
pub struct ServerOptions {
    /// The number of seconds allotted to background tasks.
    pub bg_seconds: f64,
    /// The number of ticks allotted to background tasks.
    pub bg_ticks: usize,
    /// The number of seconds allotted to foreground tasks.
    pub fg_seconds: f64,
    /// The number of ticks allotted to foreground tasks.
    pub fg_ticks: usize,
    /// The maximum number of levels of nested verb calls.
    pub max_stack_depth: usize,
    /// The interval in seconds for automatic database checkpoints.
    pub dump_interval: Option<u64>,
    /// The interval in seconds for automatic garbage collection.
    pub gc_interval: Option<u64>,
    /// Maximum number of times a task can be retried on transaction conflict before aborting.
    pub max_task_retries: u8,
    /// Maximum number of messages allowed in a task's mailbox (for task_send/task_recv).
    pub max_task_mailbox: usize,
}

impl ServerOptions {
    pub fn max_vm_values(&self, is_background: bool) -> (f64, usize, usize) {
        if is_background {
            (self.bg_seconds, self.bg_ticks, self.max_stack_depth)
        } else {
            (self.fg_seconds, self.fg_ticks, self.max_stack_depth)
        }
    }
}

#[derive(Copy, Clone, Debug, DeriveLabel)]
#[label_name = "op"]
pub enum SchedulerOp {
    ResumeTask,
    StartTask,
    RetryTask,
    KillTask,
    SetupTask,
    StartCommand,
    ParseCommand,
    FindVerbForCommand,
    TaskConflictRetry,
    TaskAbortCancelled,
    TaskAbortLimits,
    ForkTask,
    TaskException,
    HandleSchedulerMsg,
    HandleTaskMsg,
    GcMarkPhase,
    GcSweepPhase,
    SubmitCommandTaskLatency,
    SubmitVerbTaskLatency,
    SubmitEvalTaskLatency,
    SubmitOobTaskLatency,
    SubmitSystemHandlerTaskLatency,
    CheckpointLatency,
    LoadObjectLatency,
    ReloadObjectLatency,
    TaskRequestForkLatency,
    TaskKillTaskLatency,
    TaskResumeTaskLatency,
    TaskCheckpointLatency,
    TaskActiveTasksLatency,
    TaskBeginTransactionLatency,
    TaskRecvImmediateResumeLatency,
    TaskMessageDeliveryToRecvLatency,
    TaskWakeSignalToDispatchStartLatency,
    TaskWakeToDispatchLatency,
    TaskThreadHandoffLatency,
    TaskSubmitToFirstRunLatency,
}

const SCHED_SHARD_COUNT: usize = 16;

#[derive(ExportMetrics)]
#[metric_prefix = "sched"]
pub struct SchedulerPerfCounters {
    #[help = "Scheduler operation latency"]
    pub timers: LabeledSampledTimer<SchedulerOp>,
}

impl Default for SchedulerPerfCounters {
    fn default() -> Self {
        Self::new()
    }
}

impl SchedulerPerfCounters {
    pub fn new() -> Self {
        Self {
            timers: LabeledSampledTimer::with_latency_buckets(SCHED_SHARD_COUNT, hot_stride()),
        }
    }
}

#[derive(Debug, Clone)]
pub enum TaskStart {
    /// The scheduler is telling the task to parse a command and execute whatever verbs are
    /// associated with it.
    StartCommandVerb {
        /// The object that will handle the command, usually #0 (the system object), but can
        /// be a connection handler passed from `listen()`.
        handler_object: Obj,
        player: Obj,
        command: String,
    },
    /// The task start has been turned into an invocation to $do_command, which is a verb on the
    /// system object that is called when a player types a command. If it returns true, all is
    /// well and we just return. If it returns false, we intercept and turn it back into a
    /// StartCommandVerb and dispatch it as an old school parsed command.
    StartDoCommand {
        /// The object that will handle the command, usually #0 (the system object), but can
        /// be a connection handler passed from `listen()`.
        handler_object: Obj,
        player: Obj,
        command: String,
    },
    /// The scheduler is telling the task to run a (method) verb.
    StartVerb {
        player: Obj,
        vloc: Var,
        verb: Symbol,
        args: List,
        argstr: Var,
    },
    /// The scheduler is telling the task to run a task that was forked from another task.
    /// ForkRequest contains the information on the fork vector and other information needed to
    /// set up execution.
    StartFork {
        fork_request: Box<Fork>,
        // If we're starting in a suspended state. If this is true, an explicit Resume from the
        // scheduler will be required to start the task.
        suspended: bool,
    },
    /// The scheduler is telling the task to evaluate a specific (MOO) program.
    StartEval {
        player: Obj,
        program: Program,
        /// Optional initial variable bindings to inject into the eval's environment.
        initial_env: Option<Vec<(Symbol, Var)>>,
    },
    /// The task is executing $handle_uncaught_error to handle an exception.
    /// The original exception is stored so if the handler returns false, we can re-raise it.
    StartExceptionHandler {
        player: Obj,
        args: List,
        original_exception: Box<Exception>,
    },
    /// Execute a batch of world state actions within a single transaction.
    /// This is the high-performance path for bulk reads/writes that doesn't go through the VM.
    /// Results are written to `result_sink` before the task reports success.
    StartBatchWorldState {
        player: Obj,
        perms: Obj,
        actions: Vec<world_state_action::WorldStateAction>,
        rollback: bool,
        result_sink: BatchResultSink,
    },
}

impl TaskStart {
    pub fn is_background(&self) -> bool {
        matches!(self, TaskStart::StartFork { .. })
    }

    pub fn diagnostic(&self) -> String {
        match self {
            TaskStart::StartCommandVerb {
                player, command, ..
            } => {
                format!("CommandVerb(player: {player}, command: {command:?})")
            }
            TaskStart::StartDoCommand {
                player, command, ..
            } => {
                format!("DoCommand(player: {player}, command: {command:?})")
            }
            TaskStart::StartVerb {
                player, verb, vloc, ..
            } => {
                format!(
                    "Verb(player: {}, verb: {}, vloc: {})",
                    player,
                    verb,
                    to_literal(vloc)
                )
            }
            TaskStart::StartFork {
                suspended,
                fork_request,
            } => {
                format!(
                    "Fork(suspended: {}) for verb: {}:{} (defined on {}) @ line {:?}, parent task {}",
                    suspended,
                    to_literal(&fork_request.activation.this),
                    fork_request.activation.verb_name,
                    fork_request.activation.verb_definer(),
                    fork_request.activation.frame.find_line_no(),
                    fork_request.parent_task_id,
                )
            }
            TaskStart::StartEval { player, .. } => {
                format!("Eval(player: {player})")
            }
            TaskStart::StartExceptionHandler { player, .. } => {
                format!("ExceptionHandler(player: {player})")
            }
            TaskStart::StartBatchWorldState {
                player, actions, ..
            } => {
                format!(
                    "BatchWorldState(player: {player}, actions: {})",
                    actions.len()
                )
            }
        }
    }
}
