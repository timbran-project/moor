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

mod admission;
mod config;
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
        schedule_q::ScheduleQ,
        task_q::{LiveTaskRegistry, SuspensionQ, TaskQ},
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
mod tests {
    use super::*;
    use crate::{
        tasks::{
            AbortTaskOutcome, TaskNotification, TaskStart, TasksDbError,
            schedule_q::{Outcome, RetireReason, ScheduleEntry, ScheduleId},
            task::Task,
            task_control::TaskControl,
            task_q::{RunningTask, RunningTaskPhase, SuspendedTask, WakeCondition},
        },
        vm::TaskSuspend,
    };
    use moor_common::{
        model::{ObjFlag, ObjectKind, PropFlag, TaskPermissions, WorldStateSource},
        tasks::{
            CommandError, ConnectionDetails, NarrativeEvent, NoopClientSession, NoopSystemControl,
            SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
            Session, SessionError, SessionFactory, TaskId,
        },
        util::{BitEnum, Instant, Timestamp},
    };
    use moor_db::{DatabaseConfig, TxDB};
    use moor_var::{
        E_INVARG, E_QUOTA, List, NOTHING, Obj, SYSTEM_OBJECT, Symbol, v_float, v_int, v_obj, v_str,
    };
    use std::time::SystemTime;
    use std::{
        collections::HashSet,
        sync::{Barrier, OnceLock},
    };
    use uuid::Uuid;

    pub(super) struct NoopSessionFactory;

    impl SessionFactory for NoopSessionFactory {
        fn mk_background_session(
            self: Arc<Self>,
            _player: &Obj,
        ) -> Result<Arc<dyn Session>, SessionError> {
            Ok(Arc::new(NoopClientSession::new()))
        }
    }

    struct LoadedTasksDb(Mutex<Option<Vec<SuspendedTask>>>);

    #[test]
    fn adaptive_return_invalidates_collected_expiry() {
        use crate::tasks::schedule_q::{OverlapPolicy, ScheduleKind, ScheduleOptions};

        struct UnexpectedSessionFactory;
        impl SessionFactory for UnexpectedSessionFactory {
            fn mk_background_session(
                self: Arc<Self>,
                _player: &Obj,
            ) -> Result<Arc<dyn Session>, SessionError> {
                panic!("a replaced expiry must not start a session");
            }
        }

        let scheduler = scheduler_with_system_control(Arc::new(NoopSystemControl::default()));
        let t0 = SystemTime::now();
        let i0 = std::time::Instant::now();
        let interval = Duration::from_secs(1);
        let (id, to_fire) = {
            let mut lc = scheduler.lifecycle.lock();
            lc.state = SchedulerState::Running;
            lc.bg_session_factory = Some(Arc::new(UnexpectedSessionFactory));
            let mut opts = ScheduleOptions::for_kind(&ScheduleKind::Every { interval });
            opts.adaptive = true;
            opts.overlap = OverlapPolicy::Concurrent;
            let q = &mut lc.schedule_q;
            q.expired(i0, t0);
            let id = q
                .add_every(
                    interval,
                    SYSTEM_OBJECT,
                    Symbol::mk("tick"),
                    List::mk_list(&[]),
                    SYSTEM_OBJECT,
                    SYSTEM_OBJECT,
                    opts,
                    t0,
                )
                .unwrap();
            assert_eq!(q.expired(i0 + interval, t0 + interval), vec![id]);
            q.mark_fired(id, 1, t0 + interval);
            let due = q.expired(i0 + interval * 2, t0 + interval * 2);
            assert_eq!(due, vec![id]);
            let to_fire = due
                .into_iter()
                .map(|id| (q.expiry(id).unwrap(), q.info(id).unwrap().clone()))
                .collect();
            (id, to_fire)
        };
        // A worker finishes while the timer has released the collection lock.
        scheduler.lifecycle.lock().schedule_q.complete(
            id,
            1,
            Outcome::Success(v_int(60)),
            t0 + interval * 2,
        );
        scheduler.fire_collected_schedules(to_fire, t0 + interval * 2);
        let lc = scheduler.lifecycle.lock();
        let entry = lc.schedule_q.info(id).unwrap();
        assert!(entry.running.is_empty());
        assert_eq!(entry.next_run, Some(t0 + Duration::from_secs(61)));
    }

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
        fail_commit: bool,
    }

    impl Session for BlockingCommitSession {
        fn commit(&self) -> Result<(), SessionError> {
            self.commit_entered.wait();
            self.release_commit.wait();
            if self.fail_commit {
                return Err(SessionError::CommitError("test session failure".into()));
            }
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

    pub(super) fn scheduler() -> Scheduler {
        scheduler_with_system_control(Arc::new(NoopSystemControl::default()))
    }

    #[test]
    fn commit_queue_policy_loads_from_server_options() {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let mut tx = database.new_world_state().unwrap();
        let system = tx
            .create_object(
                &TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new()),
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        assert_eq!(system, SYSTEM_OBJECT);
        let server_options = tx
            .create_object(
                &TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new()),
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        for (object, name, value) in [
            (SYSTEM_OBJECT, "server_options", v_obj(server_options)),
            (
                server_options,
                "db_commit_queue_warn_seconds",
                v_float(0.25),
            ),
            (
                server_options,
                "db_commit_queue_timeout_seconds",
                v_float(1.5),
            ),
        ] {
            tx.define_property(
                &TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new()),
                &object,
                &object,
                Symbol::mk(name),
                &SYSTEM_OBJECT,
                PropFlag::all_flags(),
                Some(value),
            )
            .unwrap();
        }
        tx.commit().unwrap();

        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(crate::tasks::NoopTasksDb {}),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );
        let options = scheduler.server_options.load();
        assert_eq!(options.db_commit_queue_warn, Duration::from_millis(250));
        assert_eq!(options.db_commit_queue_timeout, Duration::from_millis(1500));
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

    pub(super) fn suspended_task(task_id: TaskId) -> SuspendedTask {
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
            db_commit_queue_warn: DEFAULT_DB_COMMIT_QUEUE_WARN,
            db_commit_queue_timeout: DEFAULT_DB_COMMIT_QUEUE_TIMEOUT,
            rollback_on_task_limit: false,
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
                Arc::new(TaskControl::new()),
            ),
            session: Arc::new(NoopClientSession::new()),
            result_sender: None,
            timer_generation: 0,
        }
    }

    #[test]
    fn fresh_task_ids_exclude_zero_sentinel() {
        let scheduler = scheduler();
        let threads = scheduler.start(Arc::new(NoopSessionFactory)).unwrap();
        let handle = scheduler
            .submit_command_task_inner(
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                "look".to_string(),
                Arc::new(NoopClientSession::new()),
            )
            .unwrap();
        assert_ne!(handle.task_id(), 0);
        assert!(!scheduler.handle_task_exists(0));
        scheduler.stop(None).unwrap();
        threads.join().unwrap();
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
            assert!(lifecycle.task_q.suspended.get(4).is_some());
            assert!(lifecycle.task_q.suspended.get(81).is_some());
        }
        assert!(scheduler.handle_task_exists(4));
        assert!(scheduler.handle_task_exists(81));

        scheduler.stop(None).expect("scheduler should stop");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    /// Tasks DB double holding only a schedule id high-water mark.
    struct ScheduleIdTasksDb(Mutex<Option<ScheduleId>>);

    impl TasksDb for ScheduleIdTasksDb {
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

        fn load_next_schedule_id(&self) -> Result<Option<ScheduleId>, TasksDbError> {
            Ok(*self.0.lock())
        }

        fn save_next_schedule_id(&self, next_id: ScheduleId) -> Result<(), TasksDbError> {
            *self.0.lock() = Some(next_id);
            Ok(())
        }

        fn compact(&self) {}
    }

    #[test]
    fn restored_schedule_id_mark_advances_allocator() {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(ScheduleIdTasksDb(Mutex::new(Some(42)))),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );

        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        {
            let mut lifecycle = scheduler.lifecycle.lock();
            // No schedule records survived, yet allocation continues from
            // the persisted mark, and the new mark is written back.
            assert!(lifecycle.schedule_q.all_ids().is_empty());
            assert_eq!(lifecycle.reserve_schedule_id(), 42);
            let saved = lifecycle
                .task_q
                .suspended
                .tasks_db()
                .load_next_schedule_id()
                .unwrap();
            assert_eq!(saved, Some(43));
        }

        scheduler.stop(None).expect("scheduler should stop");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    /// A tasks database holding one restored suspended task and the
    /// persisted schedules.
    struct RestoredScheduleDb {
        tasks: Mutex<Option<Vec<SuspendedTask>>>,
        schedules: Vec<ScheduleEntry>,
    }

    impl TasksDb for RestoredScheduleDb {
        fn load_tasks(&self) -> Result<Vec<SuspendedTask>, TasksDbError> {
            Ok(self.tasks.lock().take().unwrap())
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

        fn load_schedules(&self) -> Result<Vec<ScheduleEntry>, TasksDbError> {
            Ok(self.schedules.clone())
        }

        fn compact(&self) {}
    }

    /// A one-shot that fired as task 12 and called `suspend()` before the
    /// restart: its persisted deadline is overdue.
    fn restored_firing_scheduler(schedule_id: ScheduleId, task_id: TaskId) -> Scheduler {
        use crate::tasks::schedule_q::{ScheduleKind, ScheduleOptions};
        let now = SystemTime::now();
        let fired_at = now - Duration::from_secs(60);
        let mut entry = ScheduleEntry::from_persisted(
            schedule_id,
            SYSTEM_OBJECT,
            Symbol::mk("tick"),
            List::mk_list(&[]),
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            ScheduleKind::At,
            ScheduleOptions::for_kind(&ScheduleKind::At),
            fired_at,
            Some(fired_at),
            Some(fired_at),
            Some(fired_at),
            0,
            0,
            0,
            0,
            0,
            false,
        );
        entry.running.push(crate::tasks::schedule_q::RunningFiring {
            task: task_id,
            deadline: fired_at,
            started_at: fired_at,
        });
        let mut task = suspended_task(task_id);
        task.task = Task::new(
            task_id,
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            TaskStart::StartScheduled {
                schedule_id,
                player: SYSTEM_OBJECT,
                vloc: moor_common::model::ObjectRef::Id(SYSTEM_OBJECT),
                verb: Symbol::mk("tick"),
                args: List::mk_list(&[]),
            },
            &ServerOptions {
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
            },
            Arc::new(TaskControl::new()),
        );
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(RestoredScheduleDb {
                tasks: Mutex::new(Some(vec![task])),
                schedules: vec![entry],
            }),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        )
    }

    #[test]
    fn restored_firing_is_relinked_to_its_schedule() {
        let schedule_id: ScheduleId = 3;
        let task_id: TaskId = 12;
        let scheduler = restored_firing_scheduler(schedule_id, task_id);
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        // Give the timer loop several ticks in which it could fire the
        // overdue deadline a second time.
        std::thread::sleep(Duration::from_millis(100));
        {
            let mut lc = scheduler.lifecycle.lock();
            assert_eq!(lc.schedule_q.schedule_for_task(task_id), Some(schedule_id));
            let entry = lc.schedule_q.info(schedule_id).unwrap();
            assert_eq!(
                entry.running.iter().map(|r| r.task).collect::<Vec<_>>(),
                vec![task_id]
            );
            assert!(entry.retired.is_none(), "{:?}", entry.retired);
            assert!(lc.schedule_q.is_valid(schedule_id));
            assert_eq!(lc.next_task_id, task_id + 1, "no second firing was started");

            // The restored task's result settles the one-shot.
            lc.task_q.settled_results.push((task_id, Ok(v_str("done"))));
            lc.settle_schedule_firings();
            let entry = lc.schedule_q.info(schedule_id).unwrap();
            assert_eq!(entry.retired, Some(RetireReason::OneShotDone));
            assert_eq!(entry.run_count, 1);
            assert!(entry.running.is_empty());
            assert_eq!(lc.schedule_q.schedule_for_task(task_id), None);
        }
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
        let control = Arc::new(TaskControl::new());
        let task = Task::new(
            task_id,
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            task_start.clone(),
            scheduler.server_options.load().as_ref(),
            control.clone(),
        );

        let mut lifecycle = scheduler.lifecycle.lock();
        let registration = lifecycle.task_q.register_task(task_id);
        lifecycle.task_q.insert_active(
            task_id,
            RunningTask {
                registration,
                effects: Default::default(),
                phase: RunningTaskPhase::Running,
                player: SYSTEM_OBJECT,
                task_start,
                dispatched_at: Instant::now(),
                run_baseline: Arc::new(OnceLock::new()),
                abort_error: None,
                control,
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
    fn rejected_commit_rolls_back_session_effects() {
        let scheduler = scheduler();
        let task_id = 147;
        let session = Arc::new(moor_common::tasks::MockClientSession::new());
        session
            .send_event(
                SYSTEM_OBJECT,
                Box::new(NarrativeEvent::notify(
                    v_obj(SYSTEM_OBJECT),
                    v_str("must be discarded"),
                    None,
                    false,
                    false,
                    None,
                )),
            )
            .unwrap();
        insert_active_task(&scheduler, task_id, session.clone());

        scheduler.handle_task_commit_rejected(
            task_id,
            Box::new(moor_common::tasks::Exception {
                error: E_QUOTA.with_msg(|| "database writer overloaded".to_string()),
                stack: Vec::new(),
                backtrace: Vec::new(),
            }),
        );

        assert!(session.received().is_empty());
        assert!(session.committed().is_empty());
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
            fail_commit: false,
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
            fail_commit: false,
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
            fail_commit: false,
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
            fail_commit: false,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let boundary = task.control.claim_boundary().unwrap().committed();

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task, boundary);
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
                .map(|task| task.phase.clone()),
            Some(RunningTaskPhase::Suspending)
        );

        release_commit.wait();
        callback.join().expect("suspend callback should complete");

        let lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        assert!(lc.task_q.suspended.get(task_id).is_some());
        drop(lc);

        scheduler.stop(None).expect("scheduler should stop");
        timer.join().expect("timer thread should stop");
    }

    #[test]
    fn timed_suspension_publishes_effects_after_session_commit() {
        check_timed_suspension_effects(false, false);
    }

    #[test]
    fn timed_suspension_session_failure_does_not_publish_effects() {
        check_timed_suspension_effects(true, false);
    }

    #[test]
    fn timed_suspension_cancellation_does_not_publish_effects() {
        check_timed_suspension_effects(false, true);
    }

    fn check_timed_suspension_effects(fail_commit: bool, cancel: bool) {
        let scheduler = scheduler();
        // No service loops: the test controls every transition and deadline.
        scheduler.lifecycle.lock().state = SchedulerState::Running;
        let task_id = 242;
        let target_id = 243;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let session = Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
            fail_commit,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let control = task.control.clone();
        let boundary = control.claim_boundary().unwrap().committed();
        let (send, recv) = flume::unbounded();
        {
            let mut lc = scheduler.lifecycle.lock();
            lc.task_q.active.get_mut(&task_id).unwrap().result_sender = Some(send);
            lc.task_q
                .active
                .get_mut(&task_id)
                .unwrap()
                .effects
                .send(target_id, v_int(17));
        }
        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(
                task_id,
                TaskSuspend::Timed(Duration::from_secs(60)),
                task,
                boundary,
            );
        });
        commit_entered.wait();
        {
            let mut lc = scheduler.lifecycle.lock();
            assert!(lc.task_q.drain_messages(target_id).is_empty());
            assert!(lc.task_q.active.contains_key(&task_id));
            assert!(recv.try_recv().is_err());
            if cancel {
                assert!(matches!(
                    lc.task_q.abort_task(task_id),
                    AbortTaskOutcome::Cancelled
                ));
                assert!(lc.task_q.active.contains_key(&task_id));
            }
        }
        release_commit.wait();
        callback.join().unwrap();
        let mut lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        let (_, result) = recv.recv().unwrap();
        if fail_commit || cancel {
            assert!(lc.task_q.drain_messages(target_id).is_empty());
            assert!(lc.task_q.suspended.get(task_id).is_none());
            assert!(!scheduler.handle_task_exists(task_id));
            assert!(
                matches!(result, Err(TaskAbortedError)) && fail_commit
                    || matches!(result, Err(TaskAbortedCancelled)) && cancel
            );
        } else {
            assert_eq!(lc.task_q.drain_messages(target_id), vec![v_int(17)]);
            assert!(matches!(result, Ok(TaskNotification::Suspended)));
            let suspended = lc.task_q.suspended.get(task_id).unwrap();
            assert!(matches!(suspended.wake_condition, WakeCondition::Time(_)));
            assert!(scheduler.handle_task_exists(task_id));
        }
    }

    #[test]
    fn stale_suspension_completion_leaves_replacement_attempt_active() {
        let scheduler = scheduler();
        scheduler.lifecycle.lock().state = SchedulerState::Running;
        let task_id = 244;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let task = insert_active_task(
            &scheduler,
            task_id,
            Arc::new(BlockingCommitSession {
                commit_entered: commit_entered.clone(),
                release_commit: release_commit.clone(),
                connection_obj: None,
                source_connections: None,
                fail_commit: false,
            }),
        );
        let boundary = task.control.claim_boundary().unwrap().committed();
        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task, boundary);
        });
        commit_entered.wait();
        let replacement =
            insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        release_commit.wait();
        callback.join().unwrap();
        let lc = scheduler.lifecycle.lock();
        let active = lc.task_q.active.get(&task_id).unwrap();
        assert!(Arc::ptr_eq(&active.control, &replacement.control));
        assert_eq!(active.phase, RunningTaskPhase::Running);
        assert!(!replacement.control.is_cancelled());
        assert!(lc.task_q.suspended.get(task_id).is_none());
    }

    #[test]
    fn removed_attempt_cannot_publish_effects_through_replacement() {
        use crate::tasks::schedule_q::{PendingKind, ScheduleKind, ScheduleOptions};
        let scheduler = scheduler();
        let task_id = 245;
        let target_id = 246;
        let session = Arc::new(NoopClientSession::new());
        insert_active_task(&scheduler, task_id, session.clone());
        let interval = Duration::from_secs(60);
        let schedule_id = scheduler
            .handle_schedule_create(
                task_id,
                PendingKind::Every(interval),
                SYSTEM_OBJECT,
                Symbol::mk("tick"),
                List::mk_list(&[]),
                SYSTEM_OBJECT,
                SYSTEM_OBJECT,
                ScheduleOptions::for_kind(&ScheduleKind::Every { interval }),
            )
            .unwrap();
        assert!(scheduler.handle_schedule_valid(task_id, schedule_id));
        {
            let mut lc = scheduler.lifecycle.lock();
            lc.task_q
                .active
                .get_mut(&task_id)
                .unwrap()
                .effects
                .send(target_id, v_int(17));
            assert!(matches!(
                lc.task_q.abort_task(task_id),
                AbortTaskOutcome::Cancelled
            ));
        }
        insert_active_task(&scheduler, task_id, session);
        assert!(!scheduler.handle_schedule_valid(task_id, schedule_id));
        let mut lc = scheduler.lifecycle.lock();
        lc.publish_task_effects(task_id);
        assert!(lc.task_q.drain_messages(target_id).is_empty());
        assert!(!lc.schedule_q.is_valid(schedule_id));
    }

    #[test]
    fn stale_worker_client_cannot_complete_replacement_attempt() {
        use crate::tasks::task_scheduler_client::TaskSchedulerClient;
        use moor_common::tasks::Exception;

        fn exception() -> Box<Exception> {
            Box::new(Exception {
                error: E_QUOTA.msg("old attempt"),
                stack: vec![],
                backtrace: vec![],
            })
        }
        let callbacks: [fn(&TaskSchedulerClient); 9] = [
            |client| client.success(v_int(1), true, 99),
            |client| client.command_error(CommandError::NoCommandMatch),
            |client| client.verb_not_found(v_int(0), Symbol::mk("old")),
            |client| client.exception(exception()),
            |client| client.commit_rejected(exception()),
            |client| client.abort_transaction_renewal_failed(),
            |client| client.abort_cancelled(),
            |client| {
                client.abort_panicked("old panic".into(), std::backtrace::Backtrace::disabled())
            },
            |client| {
                client.abort_limits_reached(crate::tasks::task_scheduler_client::TaskLimitInfo {
                    reason: moor_common::tasks::AbortLimitReason::Ticks(1),
                    disposition:
                        crate::tasks::task_scheduler_client::TaskLimitDisposition::Commit {
                            mutations_made: true,
                            timestamp: 99,
                        },
                    this: v_int(0),
                    verb_name: Symbol::mk("old"),
                    line_number: 0,
                    stack: vec![],
                    backtrace: vec![],
                })
            },
        ];
        for callback in callbacks {
            let scheduler = scheduler();
            let task_id = 249;
            let target_id = 250;
            insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
            let old_client = TaskSchedulerClient::new(task_id, scheduler.clone());
            let replacement =
                insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
            let (send, recv) = flume::unbounded();
            {
                let mut lc = scheduler.lifecycle.lock();
                lc.state = SchedulerState::Running;
                lc.task_q.deliver_message(task_id, v_int(42));
                let active = lc.task_q.active.get_mut(&task_id).unwrap();
                active.result_sender = Some(send);
                active.effects.send(target_id, v_int(17));
                active.abort_error = Some(SchedulerError::CouldNotStartTask);
            }

            callback(&old_client);

            let mut lc = scheduler.lifecycle.lock();
            let active = lc
                .task_q
                .active
                .get(&task_id)
                .expect("replacement must remain active");
            assert!(Arc::ptr_eq(&active.control, &replacement.control));
            assert_eq!(active.phase, RunningTaskPhase::Running);
            assert_eq!(active.effects.messages_for(target_id), 1);
            assert_eq!(active.abort_error, Some(SchedulerError::CouldNotStartTask));
            assert_eq!(lc.task_q.mailbox_len(task_id), 1);
            assert!(lc.task_q.drain_messages(target_id).is_empty());
            assert!(lc.task_q.settled_results.is_empty());
            assert!(lc.last_mutation_timestamp.is_none());
            assert!(matches!(recv.try_recv(), Err(flume::TryRecvError::Empty)));
        }
    }

    #[test]
    fn stale_retry_keeps_replacement_attempt_running() {
        let scheduler = scheduler();
        let task_id = 251;
        let old_task = insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        let replacement =
            insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        scheduler.lifecycle.lock().state = SchedulerState::Running;
        scheduler.handle_task_conflict_retry(task_id, old_task, "test", None);
        let lc = scheduler.lifecycle.lock();
        let active = lc
            .task_q
            .active
            .get(&task_id)
            .expect("replacement must not enter retry");
        assert!(Arc::ptr_eq(&active.control, &replacement.control));
        assert!(!replacement.control.is_cancelled());
        assert!(lc.task_q.suspended.get(task_id).is_none());
    }

    #[test]
    fn session_finalization_cannot_settle_a_replacement_attempt() {
        use crate::tasks::task_scheduler_client::TaskSchedulerClient;
        let callbacks: [fn(&TaskSchedulerClient); 3] = [
            |client| {
                client.exception(Box::new(moor_common::tasks::Exception {
                    error: E_QUOTA.msg("old exception"),
                    stack: vec![],
                    backtrace: vec![],
                }))
            },
            |client| client.abort_transaction_renewal_failed(),
            |client| client.abort_cancelled(),
        ];
        for callback in callbacks {
            for fail_commit in [false, true] {
                let scheduler = scheduler();
                let task_id = 252;
                let target_id = 253;
                let commit_entered = Arc::new(Barrier::new(2));
                let release_commit = Arc::new(Barrier::new(2));
                insert_active_task(
                    &scheduler,
                    task_id,
                    Arc::new(BlockingCommitSession {
                        commit_entered: commit_entered.clone(),
                        release_commit: release_commit.clone(),
                        connection_obj: None,
                        source_connections: None,
                        fail_commit,
                    }),
                );
                scheduler.lifecycle.lock().state = SchedulerState::Running;
                let old_client = TaskSchedulerClient::new(task_id, scheduler.clone());
                let worker = std::thread::spawn(move || callback(&old_client));
                commit_entered.wait();
                let reserved = {
                    let lc = scheduler.lifecycle.lock();
                    matches!(
                        lc.task_q.active.get(&task_id).unwrap().phase,
                        RunningTaskPhase::Completing(_)
                    )
                };
                let abort_outcome = scheduler.handle_abort_task(task_id);
                let replacement =
                    insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
                let (send, recv) = flume::unbounded();
                {
                    let mut lc = scheduler.lifecycle.lock();
                    lc.task_q.deliver_message(task_id, v_int(42));
                    let active = lc.task_q.active.get_mut(&task_id).unwrap();
                    active.result_sender = Some(send);
                    active.effects.send(target_id, v_int(17));
                }
                release_commit.wait();
                worker.join().unwrap();
                assert!(
                    reserved,
                    "session finalization must reserve its terminal result"
                );
                assert!(matches!(abort_outcome, AbortTaskOutcome::Completing));
                let mut lc = scheduler.lifecycle.lock();
                let active = lc
                    .task_q
                    .active
                    .get(&task_id)
                    .expect("replacement must remain active");
                assert!(Arc::ptr_eq(&active.control, &replacement.control));
                assert_eq!(active.phase, RunningTaskPhase::Running);
                assert_eq!(active.effects.messages_for(target_id), 1);
                assert_eq!(lc.task_q.mailbox_len(task_id), 1);
                assert!(lc.task_q.drain_messages(target_id).is_empty());
                assert!(lc.task_q.settled_results.is_empty());
                assert!(matches!(recv.try_recv(), Err(flume::TryRecvError::Empty)));
            }
        }
    }

    #[test]
    fn finalization_preserves_effect_and_error_policies() {
        use crate::tasks::task_scheduler_client::TaskSchedulerClient;
        use moor_common::tasks::SchedulerError::{CouldNotStartTask, TaskAbortedException};
        for kind in ["exception", "renewal", "cancellation"] {
            for fail_commit in [false, true] {
                let scheduler = scheduler();
                let task_id = 254;
                let target_id = 255;
                let commit_entered = Arc::new(Barrier::new(2));
                let release_commit = Arc::new(Barrier::new(2));
                insert_active_task(
                    &scheduler,
                    task_id,
                    Arc::new(BlockingCommitSession {
                        commit_entered: commit_entered.clone(),
                        release_commit: release_commit.clone(),
                        connection_obj: None,
                        source_connections: None,
                        fail_commit,
                    }),
                );
                let (send, recv) = flume::unbounded();
                {
                    let mut lc = scheduler.lifecycle.lock();
                    lc.state = SchedulerState::Running;
                    lc.task_q.deliver_message(task_id, v_int(42));
                    let active = lc.task_q.active.get_mut(&task_id).unwrap();
                    active.result_sender = Some(send);
                    active.effects.send(target_id, v_int(17));
                }
                let client = TaskSchedulerClient::new(task_id, scheduler.clone());
                let worker = std::thread::spawn(move || match kind {
                    "exception" => client.exception(Box::new(moor_common::tasks::Exception {
                        error: E_QUOTA.msg("failure"),
                        stack: vec![],
                        backtrace: vec![],
                    })),
                    "renewal" => client.abort_transaction_renewal_failed(),
                    "cancellation" => client.abort_cancelled(),
                    _ => unreachable!(),
                });
                commit_entered.wait();
                let unpublished = scheduler.lifecycle.lock().task_q.mailbox_len(target_id) == 0;
                release_commit.wait();
                worker.join().unwrap();
                assert!(unpublished);
                let mut lc = scheduler.lifecycle.lock();
                let messages = lc.task_q.drain_messages(target_id);
                if kind == "cancellation" {
                    assert!(messages.is_empty());
                } else {
                    assert_eq!(messages, vec![v_int(17)]);
                }
                assert!(!scheduler.handle_task_exists(task_id));
                assert_eq!(lc.task_q.mailbox_len(task_id), 0);
                let (id, result) = recv.try_recv().unwrap();
                assert_eq!(id, task_id);
                assert!(matches!(
                    (kind, fail_commit, result),
                    ("exception", _, Err(TaskAbortedException(_)))
                        | ("renewal", false, Err(CouldNotStartTask))
                        | ("cancellation", false, Err(TaskAbortedCancelled))
                        | ("renewal" | "cancellation", true, Err(TaskAbortedError))
                ));
                assert!(matches!(
                    recv.try_recv(),
                    Err(flume::TryRecvError::Disconnected)
                ));
            }
        }
    }

    #[test]
    fn reserved_completion_rejects_duplicate_callbacks() {
        use crate::tasks::task_scheduler_client::TaskSchedulerClient;
        let scheduler = scheduler();
        let task_id = 256;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        insert_active_task(
            &scheduler,
            task_id,
            Arc::new(BlockingCommitSession {
                commit_entered: commit_entered.clone(),
                release_commit: release_commit.clone(),
                connection_obj: None,
                source_connections: None,
                fail_commit: false,
            }),
        );
        let (send, recv) = flume::unbounded();
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get_mut(&task_id)
            .unwrap()
            .result_sender = Some(send);
        let client = TaskSchedulerClient::new(task_id, scheduler.clone());
        let worker_client = client.clone();
        let worker = std::thread::spawn(move || worker_client.success(v_int(17), false, 0));
        commit_entered.wait();
        client.command_error(CommandError::NoCommandMatch);
        client.verb_not_found(v_int(0), Symbol::mk("duplicate"));
        client.success(v_int(99), true, 99);
        client.abort_cancelled();
        client.abort_transaction_renewal_failed();
        let still_pending = matches!(recv.try_recv(), Err(flume::TryRecvError::Empty));
        release_commit.wait();
        worker.join().unwrap();
        assert!(still_pending);
        assert!(
            matches!(recv.try_recv(), Ok((256, Ok(TaskNotification::Result(value)))) if value == v_int(17))
        );
        assert!(scheduler.lifecycle.lock().last_mutation_timestamp.is_none());
        assert!(matches!(
            recv.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn stale_terminal_completion_preserves_replacement_result_and_effects() {
        let scheduler = scheduler();
        let task_id = 247;
        let target_id = 248;
        let commit_entered = Arc::new(Barrier::new(2));
        let release_commit = Arc::new(Barrier::new(2));
        let task = insert_active_task(
            &scheduler,
            task_id,
            Arc::new(BlockingCommitSession {
                commit_entered: commit_entered.clone(),
                release_commit: release_commit.clone(),
                connection_obj: None,
                source_connections: None,
                fail_commit: false,
            }),
        );
        assert!(task.control.claim_terminal().unwrap().committed());
        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_success(task_id, v_int(1), false, 0);
        });
        commit_entered.wait();
        let replacement =
            insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        let (send, recv) = flume::unbounded();
        {
            let mut lc = scheduler.lifecycle.lock();
            let active = lc.task_q.active.get_mut(&task_id).unwrap();
            active.result_sender = Some(send);
            active.effects.send(target_id, v_int(17));
        }
        release_commit.wait();
        callback.join().unwrap();
        let mut lc = scheduler.lifecycle.lock();
        let active = lc.task_q.active.get(&task_id).unwrap();
        assert!(Arc::ptr_eq(&active.control, &replacement.control));
        assert_eq!(active.phase, RunningTaskPhase::Running);
        assert_eq!(active.effects.messages_for(target_id), 1);
        assert!(lc.task_q.drain_messages(target_id).is_empty());
        assert!(recv.try_recv().is_err());
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
            fail_commit: false,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let boundary = task.control.claim_boundary().unwrap().committed();

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_request_input(
                task_id,
                task,
                SYSTEM_OBJECT,
                None,
                boundary,
            );
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
                .map(|task| task.phase.clone()),
            Some(RunningTaskPhase::RequestingInput)
        );

        release_commit.wait();
        callback
            .join()
            .expect("input request callback should complete");

        let lc = scheduler.lifecycle.lock();
        assert!(!lc.task_q.active.contains_key(&task_id));
        assert!(lc.task_q.suspended.get(task_id).is_some());
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
            fail_commit: false,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let boundary = task.control.claim_boundary().unwrap().committed();

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task, boundary);
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
        assert!(lc.task_q.suspended.get(task_id).is_none());
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
            fail_commit: false,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let boundary = task.control.claim_boundary().unwrap().committed();

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task, boundary);
        });
        commit_entered.wait();

        let (gc_done_send, gc_done_recv) = flume::bounded(1);
        let gc_scheduler = scheduler.clone();
        let gc = std::thread::spawn(move || {
            let result = {
                let cycle = gc::GcCycle::begin(&gc_scheduler).unwrap();
                assert!(cycle.marking());
                let timestamp = gc_scheduler.lifecycle.lock().last_mutation_timestamp;
                cycle.sweep(HashSet::new(), timestamp)
            };
            gc_done_send.send(result).ok();
        });

        let wait_started = std::time::Instant::now();
        while !scheduler.lifecycle.lock().gc_phase.blocks_admission() {
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
            fail_commit: false,
        });
        let task = insert_active_task(&scheduler, task_id, session);
        let boundary = task.control.claim_boundary().unwrap().committed();

        let callback_scheduler = scheduler.clone();
        let callback = std::thread::spawn(move || {
            callback_scheduler.handle_task_suspend(task_id, TaskSuspend::Never, task, boundary);
        });
        commit_entered.wait();

        let gc_scheduler = scheduler.clone();
        let gc = std::thread::spawn(move || {
            let cycle = gc::GcCycle::begin(&gc_scheduler).unwrap();
            assert!(cycle.marking());
            let timestamp = gc_scheduler.lifecycle.lock().last_mutation_timestamp;
            cycle.sweep(HashSet::new(), timestamp)
        });
        let wait_started = std::time::Instant::now();
        while !scheduler.lifecycle.lock().gc_phase.blocks_admission() {
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
        assert!(!scheduler.lifecycle.lock().gc_phase.blocks_admission());
        assert!(!scheduler.handle_task_exists(task_id));

        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn shutdown_collects_gc_worker_handle() {
        let scheduler = scheduler();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");

        scheduler.run_gc_cycle();
        assert!(scheduler.gc_thread.lock().is_some());

        scheduler.stop(None).expect("scheduler should stop");
        assert!(scheduler.gc_thread.lock().is_none());
        let lc = scheduler.lifecycle.lock();
        assert_eq!(lc.gc_phase, gc::GcPhase::Idle);
        drop(lc);

        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }
}
