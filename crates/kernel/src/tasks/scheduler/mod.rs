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

pub(crate) mod lifecycle;
mod scheduler_config;
mod scheduler_gc;
mod scheduler_ops;
mod scheduler_submit;
mod scheduler_task_callbacks;
mod task_q_ops;

use arc_swap::ArcSwap;
use fast_telemetry::LabeledSampledTimer;

use crate::{
    task_context::TaskGuard,
    tasks::checkpoint::{CheckpointMode, start_checkpoint},
};
use flume::{Receiver, RecvTimeoutError, Sender};
use moor_common::util::{Deadline, Instant};
use parking_lot::{Condvar, Mutex};
use std::{
    sync::{
        Arc, LazyLock, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, SystemTime},
};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use moor_common::model::{CommitResult, TaskPermissions, WorldState};
use moor_compiler::to_literal;
use moor_db::Database;

use crate::{
    config::Config,
    tasks::{
        DEFAULT_BG_SECONDS, DEFAULT_BG_TICKS, DEFAULT_COMPACT_INTERVAL_SECONDS, DEFAULT_FG_SECONDS,
        DEFAULT_FG_TICKS, DEFAULT_GC_INTERVAL_SECONDS, DEFAULT_MAX_STACK_DEPTH,
        DEFAULT_MAX_TASK_MAILBOX, DEFAULT_MAX_TASK_RETRIES, SchedulerOp, ServerOptions, TaskHandle,
        TaskNotification, TaskStart,
        gc_thread::spawn_gc_mark_phase,
        sched_counters,
        task::Task,
        task_q::{
            LiveTaskRegistry, RunningTask, RunningTaskPhase, SuspendedTask, SuspensionQ, TaskQ,
            WakeCondition,
        },
        task_scheduler_client::TaskSchedulerClient,
        task_telemetry::{TaskRunBaseline, TaskTelemetry, TaskTelemetrySource},
        tasks_db::TasksDb,
        workers::{WorkerRequest, WorkerResponse},
        world_state_action::{WorldStateAction, WorldStateResponse},
        world_state_executor::{WorldStateActionExecutor, match_object_ref},
    },
    trace_task_create_command, trace_task_create_eval, trace_task_create_verb,
    vm::{Fork, TaskSuspend, builtins::BuiltinRegistry},
};

#[cfg(feature = "trace_events")]
use crate::trace_task_resume;

use moor_common::{
    tasks::{
        AbortLimitReason, CommandError, Event, NarrativeEvent, SchedulerError,
        SchedulerError::{
            CommandExecutionError, InputRequestNotFound, TaskAbortedCancelled, TaskAbortedError,
            TaskAbortedException, TaskAbortedLimit,
        },
        Session, SessionFactory, SystemControl, TaskId, WorkerError,
    },
    threading::{
        TaskPoolAffinityConfig, set_current_thread_background_priority,
        set_task_pool_affinity_config, spawn_perf,
    },
};
use moor_objdef::{collect_object, collect_object_definitions, dump_object, extract_index_names};
use moor_var::{
    E_EXEC, E_INVARG, E_INVIND, E_PERM, E_QUOTA, E_TYPE, Error, ErrorCode, List, NOTHING, Obj,
    SYSTEM_OBJECT, Symbol, Var, v_bool_int, v_empty_str, v_err, v_error, v_int, v_obj, v_str,
};
use std::collections::HashMap;

use self::lifecycle::TaskLifecycle;

pub use self::lifecycle::SchedulerState;

pub(crate) type SchedulerClientRequest = Box<dyn FnOnce(&Scheduler) + Send + 'static>;

/// Threads owned by a running scheduler.
#[must_use = "scheduler service threads must be joined during shutdown"]
pub struct SchedulerThreads {
    timer: std::thread::JoinHandle<()>,
    worker_response: Option<std::thread::JoinHandle<()>>,
    client_requests: std::thread::JoinHandle<()>,
}

impl SchedulerThreads {
    /// Join all scheduler service threads, returning the first panic after every
    /// handle has been collected.
    pub fn join(self) -> std::thread::Result<()> {
        let mut handles = vec![self.timer, self.client_requests];
        if let Some(worker_response) = self.worker_response {
            handles.push(worker_response);
        }

        let mut first_panic = None;
        for handle in handles {
            if let Err(panic) = handle.join()
                && first_panic.is_none()
            {
                first_panic = Some(panic);
            }
        }

        match first_panic {
            Some(panic) => Err(panic),
            None => Ok(()),
        }
    }
}

/// Action to take when resuming a suspended task
#[derive(Debug, Clone)]
pub enum ResumeAction {
    /// Resume with a return value (normal case)
    Return(Var),
    /// Resume and immediately raise an error
    Raise(Error),
}

/// Responsible for the dispatching, control, and accounting of tasks in the system.
/// Cheaply cloneable handle — replaces both SchedulerClient and TaskSchedulerClient.
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

    /// Server version.
    pub(crate) version: semver::Version,

    /// Tracks whether a checkpoint operation is currently in progress.
    pub(crate) checkpoint_in_progress: Arc<AtomicBool>,

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
        version: semver::Version,
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
        };
        let builtin_registry = BuiltinRegistry::new();

        let database: Arc<dyn Database> = Arc::from(database);

        let server_options = Arc::new(ArcSwap::from_pointee(default_server_options));
        let (client_request_send, client_request_recv) = flume::unbounded();

        let lifecycle = TaskLifecycle {
            task_q,
            pending_task_sends: HashMap::new(),
            next_task_id: 0,
            gc_collection_in_progress: false,
            gc_mark_in_progress: false,
            gc_sweep_in_progress: false,
            gc_force_collect: false,
            gc_cycle_count: 0,
            gc_last_cycle_time: std::time::Instant::now(),
            last_mutation_timestamp: None,
            state: SchedulerState::Created,
            last_compact_time: std::time::Instant::now(),
        };

        let s = Self {
            lifecycle: Arc::new(Mutex::new(lifecycle)),
            live_tasks,
            database,
            config,
            server_options,
            builtin_registry,
            system_control,
            version,
            checkpoint_in_progress: Arc::new(AtomicBool::new(false)),
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

    /// Start the scheduler and return ownership of all scheduler service threads.
    pub fn start(
        &self,
        bg_session_factory: Arc<dyn SessionFactory>,
    ) -> Result<SchedulerThreads, SchedulerError> {
        // Rehydrate suspended tasks.
        {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Created {
                return Err(SchedulerError::SchedulerNotResponding);
            }
            if let Some(max_restored_task_id) = lc.task_q.suspended.load_tasks(bg_session_factory) {
                let next_restored_task_id = max_restored_task_id
                    .checked_add(1)
                    .expect("Restored task ID exhausted the task ID space");
                lc.next_task_id = lc.next_task_id.max(next_restored_task_id);
            }
            lc.state = SchedulerState::Running;
        }

        // Start worker response thread if we have a worker receiver.
        let worker_response = if let Some(recv) = self.worker_response_recv.lock().take() {
            let scheduler = self.clone();
            Some(
                spawn_perf("moor-worker-recv", move || {
                    scheduler.worker_response_loop(recv);
                })
                .expect("Could not spawn worker response thread"),
            )
        } else {
            None
        };

        let client_request_recv = self
            .client_request_recv
            .lock()
            .take()
            .ok_or(SchedulerError::CouldNotStartTask)?;
        let scheduler = self.clone();
        let client_requests = spawn_perf("moor-scheduler-requests", move || {
            scheduler.client_request_loop(client_request_recv);
        })
        .expect("Could not spawn scheduler client request thread");

        // Start timer thread.
        let scheduler = self.clone();
        let timer = spawn_perf("moor-timer", move || {
            set_current_thread_background_priority().ok();
            scheduler.timer_loop();
        })
        .expect("Could not spawn timer thread");

        info!("Scheduler started");
        Ok(SchedulerThreads {
            timer,
            worker_response,
            client_requests,
        })
    }

    fn client_request_loop(&self, recv: Receiver<SchedulerClientRequest>) {
        loop {
            match recv.recv_timeout(Duration::from_millis(50)) {
                Ok(request) => request(self),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }

            if self.state() == SchedulerState::Stopped {
                break;
            }
        }
        debug!("Scheduler client request loop exited");
    }

    pub(crate) fn enqueue_client_request(
        &self,
        request: SchedulerClientRequest,
    ) -> Result<(), SchedulerError> {
        let lc = self.lifecycle.lock();
        if lc.state != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        self.client_request_send
            .send(request)
            .map_err(|_| SchedulerError::SchedulerNotResponding)
    }

    /// The timer loop replaces the old run() main loop.
    /// Handles: timer expirations, GC checks, compaction, immediate wakes.
    fn timer_loop(&self) {
        loop {
            {
                let lc = self.lifecycle.lock();
                if lc.state == SchedulerState::Stopped {
                    break;
                }
            }

            // Check GC conditions
            {
                let mut lc = self.lifecycle.lock();
                if lc.state == SchedulerState::Running
                    && self.config.features.anonymous_objects
                    && !lc.gc_collection_in_progress
                    && !lc.gc_mark_in_progress
                    && self.should_run_gc(&lc)
                {
                    self.run_gc_cycle(&mut lc);
                }

                // Periodic tasks DB compaction
                if lc.last_compact_time.elapsed()
                    >= Duration::from_secs(DEFAULT_COMPACT_INTERVAL_SECONDS)
                {
                    debug!("Triggering periodic tasks database compaction");
                    lc.task_q.compact();
                    lc.last_compact_time = std::time::Instant::now();
                }
            }

            // Drain immediate wakes
            self.drain_immediate_wakes();

            // Collect timer-based wakes
            self.collect_and_wake_expired_tasks();

            // Sleep until next timer expiry or notification
            let tick_duration = self
                .config
                .runtime
                .scheduler_tick_duration
                .unwrap_or(Duration::from_millis(10));

            let (lock, cvar) = &*self.timer_notify;
            let mut notified = lock.lock();
            *notified = false;
            cvar.wait_for(&mut notified, tick_duration);
        }

        // Write out all the suspended tasks to the database.
        info!("Timer loop done; saving suspended tasks");
        let lc = self.lifecycle.lock();
        lc.task_q.suspended.save_tasks();
        info!("Saved.");
    }

    /// Wake the timer thread to recompute its sleep duration.
    pub(crate) fn wake_timer_thread(&self) {
        let (lock, cvar) = &*self.timer_notify;
        let mut notified = lock.lock();
        *notified = true;
        cvar.notify_one();
    }

    /// Dedicated thread for receiving worker responses.
    fn worker_response_loop(&self, recv: Receiver<WorkerResponse>) {
        loop {
            match recv.recv_timeout(Duration::from_millis(50)) {
                Ok(response) => self.handle_worker_response(response),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }

            if self.state() == SchedulerState::Stopped {
                break;
            }
        }
        debug!("Worker response loop exited");
    }

    /// Collect expired timer tasks and wake them.
    /// Collection happens under one lock acquisition; each wake re-acquires
    /// briefly so other operations aren't blocked for the entire batch.
    fn collect_and_wake_expired_tasks(&self) {
        // Collect expired tasks under lock, then release.
        let to_wake = {
            let mut lc = self.lifecycle.lock();
            match lc.task_q.collect_wake_tasks() {
                Some(tasks) => tasks,
                None => return,
            }
        };

        // Wake each task individually, re-acquiring the lock per task.
        for sr in to_wake {
            let task_id = sr.task.task_id;
            let is_retry = matches!(sr.wake_condition, WakeCondition::Retry(_));

            #[cfg(feature = "trace_events")]
            {
                let max_ticks = sr.task.vm_host.max_ticks;
                let tick_count = sr.task.vm_host.tick_count();

                let (wake_condition, wake_reason) = match &sr.wake_condition {
                    WakeCondition::Time(_) => ("Time", "Timer expired"),
                    WakeCondition::Input(_) => ("Input", "Input request fulfilled"),
                    WakeCondition::Task(_) => ("Task", "Dependency task completed"),
                    WakeCondition::Immediate(_) => ("Immediate", "Immediate wake"),
                    WakeCondition::Worker(_) => ("Worker", "Worker response received"),
                    WakeCondition::GCComplete => ("GCComplete", "Garbage collection completed"),
                    WakeCondition::Never => ("Never", "Manual wake"),
                    WakeCondition::Retry(_) => ("Retry", "Transaction retry backoff"),
                    WakeCondition::TaskMessage(_) => ("TaskMessage", "Message received or timeout"),
                };

                trace_task_resume!(
                    task_id,
                    wake_condition,
                    wake_reason,
                    to_literal(&v_int(0)),
                    max_ticks,
                    tick_count
                );
            }

            let mut lc = self.lifecycle.lock();
            if is_retry {
                lc.task_q.wake_retry_suspended_task(
                    sr,
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                );
            } else {
                let resume_value = match &sr.wake_condition {
                    WakeCondition::TaskMessage(_) => {
                        let messages = lc.task_q.drain_messages(task_id);
                        List::from_iter(messages).into()
                    }
                    WakeCondition::Immediate(val) => val.clone().unwrap_or_else(|| v_int(0)),
                    _ => v_int(0),
                };
                if let Err(e) = lc.task_q.wake_suspended_task(
                    sr,
                    ResumeAction::Return(resume_value),
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                ) {
                    error!(?task_id, ?e, "Error resuming task");
                }
            }
        }
    }

    /// Submit a new task and wake it immediately if needed.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn submit_task(
        &self,
        lc: &mut TaskLifecycle,
        task_id: TaskId,
        player: &Obj,
        authority_principal: &Obj,
        task_start: TaskStart,
        delay_start: Option<Duration>,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        if lc.state != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }

        let gc_in_progress = self.config.features.anonymous_objects
            && (lc.gc_sweep_in_progress || lc.gc_force_collect);

        let so = self.server_options.load();
        match lc.task_q.submit_new_task(
            task_id,
            player,
            authority_principal,
            task_start,
            delay_start,
            session,
            &so,
            gc_in_progress,
        ) {
            task_q_ops::TaskSubmission::Suspended(handle) => Ok(handle),
            task_q_ops::TaskSubmission::NeedsWake {
                handle,
                task,
                session,
                result_sender,
            } => {
                if let Err(error) = lc.task_q.wake_task_thread(
                    task,
                    ResumeAction::Return(v_int(0)),
                    session,
                    result_sender,
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                ) {
                    lc.task_q.live_tasks.remove(task_id);
                    return Err(error);
                }
                Ok(handle)
            }
        }
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
mod tests {
    use super::*;
    use crate::tasks::TasksDbError;
    use moor_common::tasks::{
        ConnectionDetails, NoopClientSession, NoopSystemControl, SessionError, SessionFactory,
    };
    use moor_common::util::Timestamp;
    use moor_db::{DatabaseConfig, TxDB};
    use std::collections::HashSet;
    use std::sync::Barrier;

    struct NoopSessionFactory;

    impl SessionFactory for NoopSessionFactory {
        fn mk_background_session(
            self: Arc<Self>,
            _player: &Obj,
        ) -> Result<Arc<dyn Session>, SessionError> {
            Ok(Arc::new(NoopClientSession::new()))
        }
    }

    struct LoadedTasksDb(Mutex<Option<Vec<SuspendedTask>>>);

    impl TasksDb for LoadedTasksDb {
        fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError> {
            Ok(self.0.lock().take().unwrap())
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

        fn compact(&self) {}
    }

    struct BlockingCommitSession {
        commit_entered: Arc<Barrier>,
        release_commit: Arc<Barrier>,
        connection_obj: Option<Obj>,
        source_connections: Option<Vec<Obj>>,
    }

    impl Session for BlockingCommitSession {
        fn commit(&self) -> Result<(), SessionError> {
            self.commit_entered.wait();
            self.release_commit.wait();
            Ok(())
        }

        fn rollback(&self) -> Result<(), SessionError> {
            Ok(())
        }

        fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
            Ok(self)
        }

        fn request_input(
            &self,
            _player: Obj,
            _input_request_id: Uuid,
            _metadata: Option<Vec<(Symbol, Var)>>,
        ) -> Result<(), SessionError> {
            Ok(())
        }

        fn send_event(
            &self,
            _player: Obj,
            _event: Box<NarrativeEvent>,
        ) -> Result<(), SessionError> {
            Ok(())
        }

        fn log_event(&self, _player: Obj, _event: Box<NarrativeEvent>) -> Result<(), SessionError> {
            Ok(())
        }

        fn send_system_msg(&self, _player: Obj, _msg: &str) -> Result<(), SessionError> {
            Ok(())
        }

        fn notify_shutdown(&self, _msg: Option<String>) -> Result<(), SessionError> {
            Ok(())
        }

        fn connection_name(&self, _player: Obj) -> Result<String, SessionError> {
            Ok(String::new())
        }

        fn disconnect(&self, _player: Obj) -> Result<(), SessionError> {
            Ok(())
        }

        fn connected_players(&self, _include_all: bool) -> Result<Vec<Obj>, SessionError> {
            Ok(vec![])
        }

        fn connected_seconds(&self, _player: Obj) -> Result<f64, SessionError> {
            Ok(0.0)
        }

        fn idle_seconds(&self, _player: Obj) -> Result<f64, SessionError> {
            Ok(0.0)
        }

        fn connections(&self, _player: Option<Obj>) -> Result<Vec<Obj>, SessionError> {
            Ok(vec![])
        }

        fn connection_details(
            &self,
            player: Option<Obj>,
        ) -> Result<Vec<ConnectionDetails>, SessionError> {
            let connection_objs = match (player, &self.source_connections) {
                (Some(_), Some(source_connections)) => source_connections.clone(),
                _ => self.connection_obj.into_iter().collect(),
            };
            Ok(connection_objs
                .into_iter()
                .map(|connection_obj| ConnectionDetails {
                    connection_obj,
                    peer_addr: String::new(),
                    idle_seconds: 0.0,
                    acceptable_content_types: vec![],
                })
                .collect())
        }

        fn connection_attributes(&self, _obj: Obj) -> Result<Var, SessionError> {
            Ok(moor_var::v_list(&[]))
        }

        fn set_connection_attribute(
            &self,
            _connection_obj: Obj,
            _key: Symbol,
            _value: Var,
        ) -> Result<(), SessionError> {
            Ok(())
        }
    }

    fn scheduler_with_system_control(system_control: Arc<dyn SystemControl>) -> Scheduler {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(crate::tasks::NoopTasksDb {}),
            Arc::new(Config::default()),
            system_control,
            None,
            None,
        )
    }

    fn scheduler() -> Scheduler {
        scheduler_with_system_control(Arc::new(NoopSystemControl::default()))
    }

    struct FailingSwitchSystemControl;

    impl SystemControl for FailingSwitchSystemControl {
        fn shutdown(&self, _msg: Option<String>) -> Result<(), Error> {
            Ok(())
        }

        fn listen(
            &self,
            _handler_object: Obj,
            _host_type: &str,
            _port: u16,
            _options: Vec<(Symbol, Var)>,
        ) -> Result<(), Error> {
            Ok(())
        }

        fn unlisten(&self, _port: u16, _host_type: &str) -> Result<(), Error> {
            Ok(())
        }

        fn listeners(&self) -> Result<Vec<moor_common::tasks::ListenerInfo>, Error> {
            Ok(vec![])
        }

        fn switch_player(
            &self,
            _connection_obj: Obj,
            _new_player: Obj,
            _silent: bool,
            _preserve_history: bool,
        ) -> Result<(), Error> {
            Err(E_INVARG.with_msg(|| "Injected player switch failure".to_string()))
        }

        fn rotate_enrollment_token(&self) -> Result<String, Error> {
            Ok(String::new())
        }

        fn player_event_log_stats(
            &self,
            _player: Obj,
            _since: Option<SystemTime>,
            _until: Option<SystemTime>,
        ) -> Result<moor_common::tasks::EventLogStats, Error> {
            Ok(moor_common::tasks::EventLogStats::default())
        }

        fn purge_player_event_log(
            &self,
            _player: Obj,
            _before: Option<SystemTime>,
            _drop_pubkey: bool,
        ) -> Result<moor_common::tasks::EventLogPurgeResult, Error> {
            Ok(moor_common::tasks::EventLogPurgeResult::default())
        }

        fn workers_info(&self) -> Result<Vec<moor_common::tasks::WorkerInfo>, Error> {
            Ok(vec![])
        }
    }

    fn suspended_task(task_id: TaskId) -> SuspendedTask {
        let server_options = ServerOptions {
            bg_seconds: 0.0,
            bg_ticks: 0,
            fg_seconds: 0.0,
            fg_ticks: 0,
            max_stack_depth: 0,
            dump_interval: None,
            gc_interval: None,
            max_task_retries: DEFAULT_MAX_TASK_RETRIES,
            max_task_mailbox: DEFAULT_MAX_TASK_MAILBOX,
        };
        SuspendedTask {
            enqueued_at: Timestamp::now(),
            wake_condition: WakeCondition::Never,
            task: Task::new(
                task_id,
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                TaskStart::StartEval {
                    player: SYSTEM_OBJECT,
                    program: Default::default(),
                    initial_env: None,
                },
                &server_options,
                Arc::new(AtomicBool::new(false)),
            ),
            session: Arc::new(NoopClientSession::new()),
            result_sender: None,
            timer_generation: 0,
        }
    }

    #[test]
    fn restored_task_ids_advance_allocator() {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let tasks = vec![suspended_task(4), suspended_task(81)];
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(LoadedTasksDb(Mutex::new(Some(tasks)))),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );

        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        {
            let lifecycle = scheduler.lifecycle.lock();
            assert_eq!(lifecycle.next_task_id, 82);
            assert!(lifecycle.task_q.suspended.tasks.contains_key(&4));
            assert!(lifecycle.task_q.suspended.tasks.contains_key(&81));
        }
        assert!(scheduler.handle_task_exists(4));
        assert!(scheduler.handle_task_exists(81));

        scheduler.stop(None).expect("scheduler should stop");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    fn insert_active_task(
        scheduler: &Scheduler,
        task_id: TaskId,
        session: Arc<dyn Session>,
    ) -> Box<Task> {
        let task_start = TaskStart::StartEval {
            player: SYSTEM_OBJECT,
            program: Default::default(),
            initial_env: None,
        };
        let kill_switch = Arc::new(AtomicBool::new(false));
        let task = Task::new(
            task_id,
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            task_start.clone(),
            scheduler.server_options.load().as_ref(),
            kill_switch.clone(),
        );

        let mut lifecycle = scheduler.lifecycle.lock();
        lifecycle.task_q.register_task(task_id);
        lifecycle.task_q.insert_active(
            task_id,
            RunningTask {
                phase: RunningTaskPhase::Running,
                player: SYSTEM_OBJECT,
                task_start,
                dispatched_at: Instant::now(),
                run_baseline: Arc::new(OnceLock::new()),
                kill_switch,
                session,
                result_sender: None,
            },
        );
        drop(lifecycle);
        task
    }

    #[test]
    fn task_existence_does_not_wait_for_lifecycle_lock() {
        let scheduler = scheduler();
        let task_id = 45;
        insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));

        let lifecycle = scheduler.lifecycle.lock();
        let lookup_scheduler = scheduler.clone();
        let (result_send, result_recv) = flume::bounded(1);
        let lookup = std::thread::spawn(move || {
            result_send
                .send(lookup_scheduler.handle_task_exists(task_id))
                .unwrap();
        });

        assert_eq!(
            result_recv.recv_timeout(Duration::from_millis(100)),
            Ok(true),
            "task membership lookup must not acquire the lifecycle lock"
        );
        drop(lifecycle);
        lookup.join().expect("task lookup should complete");
    }

    #[test]
    fn terminal_task_result_removes_live_membership() {
        let scheduler = scheduler();
        let task_id = 46;
        insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        assert!(scheduler.handle_task_exists(task_id));

        scheduler
            .lifecycle
            .lock()
            .task_q
            .send_task_result(task_id, Ok(v_int(0)));

        assert!(!scheduler.handle_task_exists(task_id));
    }

    #[test]
    fn failed_player_switch_preserves_scheduler_player() {
        let scheduler = scheduler_with_system_control(Arc::new(FailingSwitchSystemControl));
        let task_id = 47;
        let session = Arc::new(BlockingCommitSession {
            commit_entered: Arc::new(Barrier::new(1)),
            release_commit: Arc::new(Barrier::new(1)),
            connection_obj: Some(Obj::mk_id(-1)),
            source_connections: None,
        });
        let _task = insert_active_task(&scheduler, task_id, session);

        assert!(
            scheduler
                .handle_switch_player_from_task(task_id, None, Obj::mk_id(100), false, false)
                .is_err()
        );
        assert_eq!(
            scheduler.lifecycle.lock().task_q.active[&task_id].player,
            SYSTEM_OBJECT
        );
    }

    #[test]
    fn current_player_switch_uses_task_connection() {
        let scheduler = scheduler();
        let task_id = 48;
        let current_connection = Obj::mk_id(-1);
        let session = Arc::new(BlockingCommitSession {
            commit_entered: Arc::new(Barrier::new(1)),
            release_commit: Arc::new(Barrier::new(1)),
            connection_obj: Some(current_connection),
            source_connections: Some(vec![Obj::mk_id(-2), current_connection]),
        });
        let _task = insert_active_task(&scheduler, task_id, session);
        let new_player = Obj::mk_id(100);

        scheduler
            .handle_switch_player_from_task(task_id, Some(SYSTEM_OBJECT), new_player, false, true)
            .unwrap();

        assert_eq!(
            scheduler.lifecycle.lock().task_q.active[&task_id].player,
            new_player
        );
    }

    #[test]
    fn switch_rejects_ambiguous_other_player_source() {
        let scheduler = scheduler();
        let task_id = 49;
        let session = Arc::new(BlockingCommitSession {
            commit_entered: Arc::new(Barrier::new(1)),
            release_commit: Arc::new(Barrier::new(1)),
            connection_obj: Some(Obj::mk_id(-1)),
            source_connections: Some(vec![Obj::mk_id(-2), Obj::mk_id(-3)]),
        });
        let _task = insert_active_task(&scheduler, task_id, session);

        let error = scheduler
            .handle_switch_player_from_task(
                task_id,
                Some(Obj::mk_id(7)),
                Obj::mk_id(100),
                false,
                false,
            )
            .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("source has multiple connections")
        );
        assert_eq!(
            scheduler.lifecycle.lock().task_q.active[&task_id].player,
            SYSTEM_OBJECT
        );
    }

    #[test]
    fn lifecycle_rejects_work_before_start_and_after_stop() {
        let scheduler = scheduler();
        let client = scheduler.client().unwrap();
        let session = Arc::new(NoopClientSession::new());

        assert_eq!(scheduler.state(), SchedulerState::Created);
        assert_eq!(
            client.check_status(),
            Err(SchedulerError::SchedulerNotResponding)
        );
        assert!(matches!(
            client.submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look", session.clone()),
            Err(SchedulerError::SchedulerNotResponding)
        ));
        assert!(matches!(
            client.submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "not valid moo code".to_string(),
                None,
                session.clone(),
                Arc::new(crate::config::FeaturesConfig::default()),
            ),
            Err(SchedulerError::SchedulerNotResponding)
        ));

        let timer = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start once");
        assert_eq!(scheduler.state(), SchedulerState::Running);
        assert_eq!(client.check_status(), Ok(()));
        assert!(matches!(
            scheduler.start(Arc::new(NoopSessionFactory)),
            Err(SchedulerError::SchedulerNotResponding)
        ));

        scheduler.stop(None).expect("scheduler should stop once");
        timer.join().expect("timer thread should stop");

        assert_eq!(scheduler.state(), SchedulerState::Stopped);
        assert_eq!(
            client.check_status(),
            Err(SchedulerError::SchedulerNotResponding)
        );
        assert!(matches!(
            client.submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look", session),
            Err(SchedulerError::SchedulerNotResponding)
        ));
        assert!(matches!(
            client.submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "not valid moo code".to_string(),
                None,
                Arc::new(NoopClientSession::new()),
                Arc::new(crate::config::FeaturesConfig::default()),
            ),
            Err(SchedulerError::SchedulerNotResponding)
        ));
        assert_eq!(
            scheduler.stop(None),
            Err(SchedulerError::SchedulerNotResponding)
        );
    }

    #[test]
    fn suspending_task_remains_visible_until_atomic_queue_move() {
        let scheduler = scheduler();
        let timer = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        let task_id = 42;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
        });
        let task = insert_active_task(&scheduler, task_id, session);

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task);
        });

        commit_entered.wait();
        assert!(
            scheduler.handle_task_exists(task_id),
            "task must remain addressable while its session commit is in progress"
        );
        assert_eq!(
            scheduler
                .lifecycle
                .lock()
                .task_q
                .active
                .get(&task_id)
                .map(|task| task.phase),
            Some(RunningTaskPhase::Suspending)
        );

        release_commit.wait();
        callback.join().expect("suspend callback should complete");

        let lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        assert!(lc.task_q.suspended.tasks.contains_key(&task_id));
        drop(lc);

        scheduler.stop(None).expect("scheduler should stop");
        timer.join().expect("timer thread should stop");
    }

    #[test]
    fn input_task_remains_visible_until_atomic_queue_move() {
        let scheduler = scheduler();
        let timer = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        let task_id = 43;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
        });
        let task = insert_active_task(&scheduler, task_id, session);

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_request_input(task_id, task, SYSTEM_OBJECT, None);
        });

        commit_entered.wait();
        assert!(
            scheduler.handle_task_exists(task_id),
            "task must remain addressable while its input request is in progress"
        );
        assert_eq!(
            scheduler
                .lifecycle
                .lock()
                .task_q
                .active
                .get(&task_id)
                .map(|task| task.phase),
            Some(RunningTaskPhase::RequestingInput)
        );

        release_commit.wait();
        callback
            .join()
            .expect("input request callback should complete");

        let lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        assert!(lc.task_q.suspended.tasks.contains_key(&task_id));
        drop(lc);

        scheduler.stop(None).expect("scheduler should stop");
        timer.join().expect("timer thread should stop");
    }

    #[test]
    fn shutdown_joins_worker_response_thread_with_live_sender() {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let (_worker_send, worker_recv) = flume::unbounded();
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(crate::tasks::NoopTasksDb {}),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            Some(worker_recv),
        );
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");

        scheduler.stop(None).expect("scheduler should stop");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn shutdown_does_not_resurrect_suspending_task() {
        let scheduler = scheduler();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        let task_id = 44;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
        });
        let task = insert_active_task(&scheduler, task_id, session);

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task);
        });

        commit_entered.wait();
        let (stop_done_send, stop_done_recv) = flume::bounded(1);
        let stop_scheduler = scheduler.clone();
        let stop = std::thread::spawn(move || {
            let result = stop_scheduler.stop(None);
            stop_done_send.send(result).ok();
        });
        let wait_started = std::time::Instant::now();
        while scheduler.state() != SchedulerState::Stopping {
            assert!(
                wait_started.elapsed() < Duration::from_secs(1),
                "scheduler did not enter stopping state"
            );
            std::thread::yield_now();
        }
        assert!(
            stop_done_recv
                .recv_timeout(Duration::from_millis(25))
                .is_err(),
            "scheduler stopped before the in-flight callback finished"
        );

        release_commit.wait();
        callback.join().expect("suspend callback should exit");
        stop_done_recv
            .recv_timeout(Duration::from_secs(1))
            .expect("scheduler shutdown should finish after the callback")
            .expect("scheduler should stop");
        stop.join().expect("shutdown thread should stop");
        assert_eq!(scheduler.state(), SchedulerState::Stopped);

        let lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        assert!(!lc.task_q.suspended.tasks.contains_key(&task_id));
        drop(lc);

        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn gc_sweep_waits_for_suspension_transition() {
        let scheduler = scheduler();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        let task_id = 45;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
        });
        let task = insert_active_task(&scheduler, task_id, session);

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task);
        });
        commit_entered.wait();

        let (gc_done_send, gc_done_recv) = flume::bounded(1);
        let gc_scheduler = scheduler.clone();
        let gc = std::thread::spawn(move || {
            let result = gc_scheduler.run_blocking_sweep_phase(HashSet::new());
            gc_done_send.send(result).ok();
        });

        let wait_started = std::time::Instant::now();
        while !scheduler.lifecycle.lock().gc_sweep_in_progress {
            assert!(
                wait_started.elapsed() < Duration::from_secs(1),
                "GC sweep did not enter its waiting phase"
            );
            std::thread::yield_now();
        }
        assert!(
            gc_done_recv
                .recv_timeout(Duration::from_millis(25))
                .is_err(),
            "GC sweep completed while a suspension transition was active"
        );

        release_commit.wait();
        callback.join().expect("suspend callback should complete");
        gc_done_recv
            .recv_timeout(Duration::from_secs(1))
            .expect("GC sweep should complete after suspension")
            .expect("GC sweep should succeed");
        gc.join().expect("GC sweep thread should stop");

        scheduler.stop(None).expect("scheduler should stop");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn shutdown_cancels_gc_sweep_waiting_on_suspension() {
        let scheduler = scheduler();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        let task_id = 46;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
        });
        let task = insert_active_task(&scheduler, task_id, session);

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task);
        });
        commit_entered.wait();

        let gc_scheduler = scheduler.clone();
        let gc = std::thread::spawn(move || gc_scheduler.run_blocking_sweep_phase(HashSet::new()));
        let wait_started = std::time::Instant::now();
        while !scheduler.lifecycle.lock().gc_sweep_in_progress {
            assert!(
                wait_started.elapsed() < Duration::from_secs(1),
                "GC sweep did not enter its waiting phase"
            );
            std::thread::yield_now();
        }

        let (stop_done_send, stop_done_recv) = flume::bounded(1);
        let stop_scheduler = scheduler.clone();
        let stop = std::thread::spawn(move || {
            let result = stop_scheduler.stop(None);
            stop_done_send.send(result).ok();
        });
        let wait_started = std::time::Instant::now();
        while scheduler.state() != SchedulerState::Stopping {
            assert!(
                wait_started.elapsed() < Duration::from_secs(1),
                "scheduler did not enter stopping state"
            );
            std::thread::yield_now();
        }
        assert!(
            stop_done_recv
                .recv_timeout(Duration::from_millis(25))
                .is_err(),
            "scheduler stopped before the in-flight callback finished"
        );

        release_commit.wait();
        callback.join().expect("suspend callback should exit");
        stop_done_recv
            .recv_timeout(Duration::from_secs(1))
            .expect("scheduler shutdown should finish after the callback")
            .expect("scheduler should stop");
        stop.join().expect("shutdown thread should stop");
        gc.join()
            .expect("GC sweep thread should stop")
            .expect("cancelled GC sweep should exit cleanly");
        assert!(!scheduler.lifecycle.lock().gc_sweep_in_progress);
        assert!(!scheduler.handle_task_exists(task_id));

        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn shutdown_joins_in_flight_gc_cycle() {
        let scheduler = scheduler();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");

        {
            let mut lc = scheduler.lifecycle.lock();
            scheduler.run_gc_cycle(&mut lc);
            assert!(lc.gc_collection_in_progress);
            assert!(lc.gc_mark_in_progress);
        }

        scheduler.stop(None).expect("scheduler should stop");
        assert!(scheduler.gc_thread.lock().is_none());
        let lc = scheduler.lifecycle.lock();
        assert!(!lc.gc_collection_in_progress);
        assert!(!lc.gc_mark_in_progress);
        drop(lc);

        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }
}
