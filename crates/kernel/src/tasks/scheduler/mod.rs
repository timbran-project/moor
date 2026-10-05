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

//! Scheduler handle and shared lifecycle state.
//!
//! External clients enqueue requests through `SchedulerClient`; task workers call directly
//! through `TaskSchedulerClient`. Both reach the same lifecycle state and transition methods.
//! New tasks enter through `admission`, while wakeups enter through `transitions::resume`.
//! `services` owns threads and shutdown. Domain modules own GC, schedules, and maintenance.
//!
//! Start at `Scheduler::new` for construction or `Scheduler::start` for service startup.
//! `submit_task` checks admission and calls `TaskLifecycle::dispatch_task`. Returning workers
//! enter `handle_task_suspend`, `handle_task_conflict_retry`, or a terminal transition in
//! `transitions::complete`. These operations show session and registry changes in execution order.
//! `TaskLifecycle` stores the state shared by these modules; it does not own a separate lock.

mod admission;
mod config;
mod dispatch;
pub(crate) mod effects;
pub(crate) mod gc;
pub(crate) mod lifecycle;
mod maintenance;
mod requests;
mod schedules;
mod services;
mod task_requests;
mod transitions;

pub use self::lifecycle::SchedulerState;
use self::lifecycle::TaskLifecycle;
use crate::{
    config::Config,
    tasks::{
        DEFAULT_BG_SECONDS, DEFAULT_BG_TICKS, DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
        DEFAULT_DB_COMMIT_QUEUE_WARN, DEFAULT_FG_SECONDS, DEFAULT_FG_TICKS,
        DEFAULT_MAX_STACK_DEPTH, DEFAULT_MAX_TASK_MAILBOX, DEFAULT_MAX_TASK_RETRIES, ServerOptions,
        maintenance::MaintenanceCoordinator,
        registry::{LiveTaskRegistry, SuspensionQ, TaskQ},
        schedule_q::ScheduleQ,
        tasks_db::TasksDb,
        workers::{WorkerRequest, WorkerResponse},
    },
    vm::builtins::BuiltinRegistry,
};
use arc_swap::ArcSwap;
use flume::{Receiver, Sender};
use moor_common::{
    tasks::{SchedulerError, SystemControl},
    threading::{TaskPoolAffinityConfig, set_task_pool_affinity_config},
};
use moor_db::Database;
use moor_var::{Error, Var};
use parking_lot::{Condvar, Mutex};
pub use services::SchedulerThreads;
use std::{sync::Arc, time::Duration};

pub(crate) type SchedulerClientRequest = Box<dyn FnOnce(&Scheduler) + Send + 'static>;

/// Action to take when resuming a suspended task
#[derive(Debug, Clone)]
pub enum ResumeAction {
    /// Resume with a return value (normal case)
    Return(Var),
    /// Resume and immediately raise an error
    Raise(Error),
}

/// Responsible for the dispatching, control, and accounting of tasks in the system.
/// Shared handle used by external request clients and direct task-worker callbacks.
#[derive(Clone)]
pub struct Scheduler {
    /// All mutable lifecycle state, protected by a single Mutex.
    pub(crate) lifecycle: Arc<Mutex<TaskLifecycle>>,

    /// Lock-free task membership for queries that do not need lifecycle state.
    pub(crate) live_tasks: LiveTaskRegistry,

    /// Database access (thread-safe, lock-free reads).
    pub(crate) database: Arc<dyn Database>,

    /// Runtime configuration.
    pub(crate) config: Arc<Config>,

    /// Host/connection management.
    pub(crate) system_control: Arc<dyn SystemControl>,

    /// Server options (lock-free reads via ArcSwap, updated from database).
    pub(crate) server_options: Arc<ArcSwap<ServerOptions>>,

    /// Builtin function registry.
    pub(crate) builtin_registry: BuiltinRegistry,

    /// Owns mutually exclusive database maintenance across all request paths.
    pub(crate) maintenance_coordinator: MaintenanceCoordinator,

    /// Current GC mark/callback thread, retained for shutdown and cycle-to-cycle joining.
    pub(crate) gc_thread: Arc<Mutex<Option<std::thread::JoinHandle<()>>>>,

    /// Channel for sending requests TO workers.
    pub(crate) worker_request_send: Option<Sender<WorkerRequest>>,

    /// Worker response receiver — taken once when starting the worker response thread.
    worker_response_recv: Arc<Mutex<Option<Receiver<WorkerResponse>>>>,

    /// Queue for bounded requests from external scheduler clients.
    client_request_send: Sender<SchedulerClientRequest>,

    /// Client request receiver — taken once when starting its service thread.
    client_request_recv: Arc<Mutex<Option<Receiver<SchedulerClientRequest>>>>,

    /// Condvar to wake the timer thread when a new earlier timer is inserted.
    timer_notify: Arc<(Mutex<bool>, Condvar)>,
}

impl Scheduler {
    pub fn new(
        _version: semver::Version,
        database: Box<dyn Database>,
        tasks_database: Box<dyn TasksDb>,
        config: Arc<Config>,
        system_control: Arc<dyn SystemControl>,
        worker_request_send: Option<Sender<WorkerRequest>>,
        worker_request_recv: Option<Receiver<WorkerResponse>>,
    ) -> Self {
        let mut affinity_config = TaskPoolAffinityConfig::default();
        if let Some(pinning_mode) = config.runtime.task_pool_pinning {
            affinity_config.pinning_mode = pinning_mode;
        }
        affinity_config.service_perf_cores = config.runtime.service_perf_cores;
        set_task_pool_affinity_config(affinity_config);

        let mut timing_policy = moor_common::util::perf_timing_policy();
        if let Some(enabled) = config.runtime.perf_timing_enabled {
            timing_policy.enabled = enabled;
        }
        if let Some(shift) = config.runtime.perf_timing_hot_path_shift {
            timing_policy.hot_path_shift = shift;
        }
        moor_common::util::set_perf_timing_policy(timing_policy);

        let suspension_q = SuspensionQ::new(tasks_database);
        let task_q = TaskQ::new(suspension_q);
        let live_tasks = task_q.live_tasks.clone();
        let default_server_options = ServerOptions {
            bg_seconds: DEFAULT_BG_SECONDS,
            bg_ticks: DEFAULT_BG_TICKS,
            fg_seconds: DEFAULT_FG_SECONDS,
            fg_ticks: DEFAULT_FG_TICKS,
            max_stack_depth: DEFAULT_MAX_STACK_DEPTH,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
        };
        let builtin_registry = BuiltinRegistry::new();

        let database: Arc<dyn Database> = Arc::from(database);

        let server_options = Arc::new(ArcSwap::from_pointee(default_server_options));
        let (client_request_send, client_request_recv) = flume::unbounded();

        let lifecycle = TaskLifecycle {
            task_q,
            // Reserve zero for the no-task sentinel.
            next_task_id: 1,
            gc_phase: gc::GcPhase::Idle,
            gc_force_collect: false,
            gc_cycle_count: 0,
            gc_last_cycle_time: std::time::Instant::now(),
            last_mutation_timestamp: None,
            state: SchedulerState::Created,
            last_compact_time: std::time::Instant::now(),
            schedule_q: ScheduleQ::new(
                config
                    .runtime
                    .scheduler_tick_duration
                    .unwrap_or(Duration::from_millis(10)),
            ),
            bg_session_factory: None,
        };

        let s = Self {
            lifecycle: Arc::new(Mutex::new(lifecycle)),
            live_tasks,
            database,
            config,
            server_options,
            builtin_registry,
            system_control,
            maintenance_coordinator: MaintenanceCoordinator::new(),
            gc_thread: Arc::new(Mutex::new(None)),
            worker_request_send,
            worker_response_recv: Arc::new(Mutex::new(worker_request_recv)),
            client_request_send,
            client_request_recv: Arc::new(Mutex::new(Some(client_request_recv))),
            timer_notify: Arc::new((Mutex::new(false), Condvar::new())),
        };

        s.reload_server_options();
        s
    }

    /// Legacy compatibility: returns a SchedulerClient wrapping this Scheduler.
    pub fn client(
        &self,
    ) -> Result<crate::tasks::scheduler_client::SchedulerClient, SchedulerError> {
        Ok(crate::tasks::scheduler_client::SchedulerClient::new(
            self.clone(),
        ))
    }

    /// Return the current scheduler lifecycle state.
    pub fn state(&self) -> SchedulerState {
        self.lifecycle.lock().state
    }
}

#[cfg(test)]
mod test_support;
