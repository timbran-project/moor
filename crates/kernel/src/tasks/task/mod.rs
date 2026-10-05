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

//! Executable task state and the worker execution loop.
//!
//! A task owns its VM, retry snapshot, authority, and program cache. The worker supplies its
//! transaction and session through task context. The scheduler retains active metadata separately.
//!
//! Startup resolves commands and verbs in `start`. The loop calls `Task::vm_dispatch` in `dispatch`
//! for each VM response. `transaction` owns commit arbitration and retry snapshots. The loop
//! consumes decisions from `outcome` to transfer execution or finalize it through the scheduler.
//! Cache lifetime remains tied to this executable task and its retry snapshot.

mod dispatch;
mod outcome;
mod start;
mod transaction;

use outcome::ExecutionOutcome;

use crate::{
    config::Config,
    task_context::with_current_transaction,
    tasks::{
        ServerOptions, TaskStart, task_control::TaskControl, task_program_cache::TaskProgramCache,
        task_scheduler_client::TaskSchedulerClient,
    },
    trace_task_start,
    vm::{builtins::BuiltinRegistry, vm_host::VmHost},
};
#[cfg(feature = "trace_events")]
use crate::{
    trace_task_create_command, trace_task_create_eval, trace_task_create_exception_handler,
    trace_task_create_fork, trace_task_create_verb,
};
use ahash::AHasher;
use moor_common::{
    model::{ObjFlag, TaskPermissions},
    tasks::{Exception, Session, TaskId},
    util::{BitEnum, Instant},
};
use moor_compiler::to_literal;
#[cfg(feature = "trace_events")]
use moor_var::v_str;
use moor_var::{Error, ErrorCode, Obj};
use moor_vm::{ExecState, Frame};
use std::{collections::HashSet, sync::Arc, time::Duration};
use tracing::error;

/// Tracks the lifecycle state of a task
#[derive(Debug, Clone)]
pub enum TaskState {
    /// Task pending execution, their host and activation frames are not yet set up, and is not
    /// prepared for execution yet.
    Pending(TaskStart),
    /// Task has had its state set up and ready to go.
    Prepared(TaskStart),
}

impl TaskState {
    pub fn task_start(&self) -> &TaskStart {
        match self {
            TaskState::Pending(start) => start,
            TaskState::Prepared(start) => start,
        }
    }

    pub fn is_background(&self) -> bool {
        self.task_start().is_background()
    }
}

#[derive(Debug)]
pub struct Task {
    /// My unique task id.
    pub task_id: TaskId,
    /// When I was first instantiated (not necessarily) started
    pub creation_time: Instant,
    /// What I was asked to do and current lifecycle state.
    pub(crate) state: TaskState,
    /// The player on behalf of whom this task is running. Who owns this task.
    player: Obj,
    /// The object on behalf of which task permissions are evaluated.
    authority_principal: Obj,
    /// Cached flags for the authority principal.
    authority_principal_flags: BitEnum<ObjFlag>,
    /// The actual VM host which is managing the execution of this task.
    pub(crate) vm_host: VmHost,
    /// Arbitration between cancellation and transaction commit.
    pub(crate) control: Arc<TaskControl>,
    /// The number of retries this process has undergone.
    pub(crate) retries: u8,
    /// A copy of the VM state at the time the task was created or last committed/suspended.
    /// For restoring on retry.
    pub(crate) retry_state: ExecState,
    /// True if we're currently handling an uncaught error to prevent infinite recursion.
    pub(crate) handling_uncaught_error: bool,
    /// The original exception when calling handle_uncaught_error, in case it returns false.
    pub(crate) pending_exception: Option<Exception>,
    /// Transaction-lifetime verb program cache for this task.
    pub(crate) program_cache: TaskProgramCache,
}

impl Task {
    // Yes yes I know it's a lot of arguments, but wrapper object here is redundant.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        task_id: TaskId,
        player: Obj,
        authority_principal: Obj,
        task_start: TaskStart,
        server_options: &ServerOptions,
        control: Arc<TaskControl>,
    ) -> Box<Self> {
        let is_background = task_start.is_background();
        let state = TaskState::Pending(task_start.clone());

        // Find out max ticks, etc. for this task. These are either pulled from server constants in
        // the DB or from default constants.
        let (max_seconds, max_ticks, max_stack_depth) = server_options.max_vm_values(is_background);

        let vm_host = VmHost::new(
            task_id,
            max_stack_depth,
            max_ticks,
            Duration::from_secs_f64(max_seconds),
        );

        let retry_state = vm_host.snapshot_state();

        // Emit task creation trace event based on task start type
        #[cfg(feature = "trace_events")]
        {
            match &task_start {
                TaskStart::StartCommandVerb {
                    command,
                    handler_object,
                    ..
                } => {
                    trace_task_create_command!(task_id, &player, command, handler_object);
                }
                TaskStart::StartDoCommand {
                    command,
                    handler_object,
                    ..
                } => {
                    trace_task_create_command!(task_id, &player, command, handler_object);
                }
                TaskStart::StartVerb { verb, vloc, .. } => {
                    trace_task_create_verb!(task_id, &player, &verb.as_string(), vloc);
                }
                TaskStart::StartScheduled { verb, .. } => {
                    trace_task_create_verb!(
                        task_id,
                        &player,
                        &verb.as_string(),
                        &v_str("scheduled")
                    );
                }
                TaskStart::StartFork { .. } => {
                    trace_task_create_fork!(task_id, &player);
                }
                TaskStart::StartEval { .. } => {
                    trace_task_create_eval!(task_id, &player);
                }
                TaskStart::StartExceptionHandler { .. } => {
                    trace_task_create_exception_handler!(task_id, &player);
                }
                TaskStart::StartBatchWorldState { .. } => {
                    // No specific trace event for batch world state tasks yet
                }
            }
        }

        let creation_time = Instant::now();
        Box::new(Self {
            task_id,
            creation_time,
            player,
            state,
            vm_host,
            authority_principal,
            authority_principal_flags: BitEnum::new(),
            control,
            retries: 0,
            retry_state,
            handling_uncaught_error: false,
            pending_exception: None,
            program_cache: TaskProgramCache::default(),
        })
    }

    #[inline]
    pub(crate) fn player(&self) -> Obj {
        self.player
    }

    #[inline]
    pub(crate) fn authority_principal(&self) -> Obj {
        self.authority_principal
    }

    #[inline]
    fn task_permissions(&self) -> TaskPermissions {
        TaskPermissions::new(self.authority_principal, self.authority_principal_flags)
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn from_restored(
        task_id: TaskId,
        creation_time: Instant,
        player: Obj,
        state: TaskState,
        vm_host: VmHost,
        authority_principal: Obj,
        authority_principal_flags: BitEnum<ObjFlag>,
        control: Arc<TaskControl>,
        retries: u8,
        retry_state: ExecState,
        handling_uncaught_error: bool,
        pending_exception: Option<Exception>,
        program_cache: TaskProgramCache,
    ) -> Self {
        Self {
            task_id,
            creation_time,
            player,
            state,
            vm_host,
            authority_principal,
            authority_principal_flags,
            control,
            retries,
            retry_state,
            handling_uncaught_error,
            pending_exception,
            program_cache,
        }
    }

    pub fn run_task_loop(
        mut task: Box<Task>,
        task_scheduler_client: &TaskSchedulerClient,
        session: Arc<dyn Session>,
        builtin_registry: BuiltinRegistry,
        config: Arc<Config>,
    ) {
        // Transaction context is already set up by the caller

        trace_task_start!(task.task_id);

        while task.vm_host.is_running() {
            let outcome = if task.control.is_cancelled() {
                task.cancelled_outcome()
            } else {
                task.vm_dispatch(
                    task_scheduler_client,
                    session.as_ref(),
                    &builtin_registry,
                    config.features.as_ref(),
                )
            };
            match outcome {
                ExecutionOutcome::Continue(continuation) => task = continuation,
                ExecutionOutcome::Retry(request) => {
                    request.handoff(task_scheduler_client);
                    break;
                }
                ExecutionOutcome::Suspend(request) => {
                    request.handoff(task_scheduler_client);
                    break;
                }
                ExecutionOutcome::Finish(request) => {
                    request.finish(task_scheduler_client);
                    break;
                }
            }
        }

        // Transaction is automatically cleaned up by _tx_guard drop
    }

    fn sync_authority_from_vm(&mut self) {
        let authority_principal = self.vm_host.vm_exec_state().task_authority_principal();
        if !authority_principal.is_nothing() {
            self.authority_principal = authority_principal;
            self.refresh_authority_principal_flags();
        }
    }

    fn refresh_authority_principal_flags(&mut self) {
        self.authority_principal_flags =
            with_current_transaction(|ws| ws.flags_of(&self.authority_principal))
                .unwrap_or_default();
    }

    fn collect_live_program_ptrs_from_state(
        state: &ExecState,
        live_ptrs: &mut HashSet<usize, std::hash::BuildHasherDefault<AHasher>>,
    ) {
        for activation in &state.stack {
            let Frame::Moo(frame) = &activation.frame else {
                continue;
            };
            if let Some(ptr) = frame.cached_program_ptr() {
                live_ptrs.insert(ptr.addr());
            }
        }
    }

    pub(crate) fn reclaim_program_cache(&mut self) {
        let mut live_ptrs =
            HashSet::with_hasher(std::hash::BuildHasherDefault::<AHasher>::default());

        Self::collect_live_program_ptrs_from_state(self.vm_host.vm_exec_state(), &mut live_ptrs);
        Self::collect_live_program_ptrs_from_state(&self.retry_state, &mut live_ptrs);

        if let TaskStart::StartFork { fork_request, .. } = self.state.task_start()
            && let Frame::Moo(frame) = &fork_request.activation.frame
            && let Some(ptr) = frame.cached_program_ptr()
        {
            live_ptrs.insert(ptr.addr());
        }

        let reclaimed = self.program_cache.reclaim_unreferenced(&live_ptrs);
        if reclaimed > 0 {
            let reclaimed_i = reclaimed as i64;
            self.vm_host
                .vm_exec_state_mut()
                .program_cache_stats
                .reclaimed += reclaimed_i;
            self.retry_state.program_cache_stats.reclaimed += reclaimed_i;
        }

        let total_slots = self.program_cache.total_slot_count();
        let live_slots = self.program_cache.live_slot_count();
        let key_count = self.program_cache.key_count();
        self.vm_host
            .set_program_cache_sizes(total_slots, live_slots, key_count);
        self.retry_state.program_cache_total_slots = total_slots;
        self.retry_state.program_cache_live_slots = live_slots;
        self.retry_state.program_cache_key_count = key_count;
    }
}

impl Drop for Task {
    fn drop(&mut self) {
        if !std::thread::panicking() {
            return;
        }

        let task_start = self.state.task_start().diagnostic();
        let vm_state = self.vm_host.vm_exec_state();
        let Some(activation) = vm_state.try_top() else {
            error!(
                task_id = self.task_id,
                player = %self.player,
                task_start = %task_start,
                "Task panicked with empty activation stack"
            );
            return;
        };

        let stack = ExecState::make_stack_list(&vm_state.stack);
        let panic_error = Error::new(ErrorCode::E_MAXREC, Some("Task panicked".to_string()), None);
        let backtrace = ExecState::make_backtrace(&vm_state.stack, &panic_error);
        let stack_literals = stack.iter().map(to_literal).collect::<Vec<_>>();
        let backtrace_lines = backtrace
            .iter()
            .map(|entry| {
                entry
                    .as_string()
                    .map(str::to_string)
                    .unwrap_or_else(|| to_literal(entry))
            })
            .collect::<Vec<_>>();
        let args = activation
            .args()
            .iter()
            .map(|arg| to_literal(&arg))
            .collect::<Vec<_>>();
        let this_literal = to_literal(&activation.this);
        let line_number = activation.frame.find_line_no();
        let definer = activation.verb_definer();

        error!(
            task_id = self.task_id,
            player = %self.player,
            task_start = %task_start,
            this = %this_literal,
            verb = %activation.verb_name,
            definer = %definer,
            line_number = ?line_number,
            args = ?args,
            stack = ?stack_literals,
            backtrace = ?backtrace_lines,
            "Task panicked at top activation"
        );
    }
}

// Tests use the real Scheduler with TxDB — tasks are submitted via SchedulerClient
// and results are observed through TaskHandle receivers.
#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    };
    use std::time::{Duration, Instant};

    use moor_common::{
        model::{
            ArgSpec, CommitResult, ObjFlag, ObjectKind, ObjectRef, PrepSpec, PropFlag,
            VerbArgsSpec, VerbFlag, WorldState, WorldStateError, WorldStateSource,
            loader::{LoaderInterface, SnapshotInterface},
        },
        tasks::{
            CommandError, MockClientSession, NoopClientSession, NoopSystemControl, SchedulerError,
            SessionError, SessionFactory,
        },
        util::BitEnum,
    };
    use moor_compiler::{CompileOptions, Program, compile};
    use moor_db::{Database, DatabaseConfig, GCInterface, SnapshotCallback, TxDB};
    use moor_var::{
        E_DIV, List, NOTHING, Obj, SYSTEM_OBJECT, Symbol, Var, program::ProgramType, v_empty_str,
        v_int, v_obj, v_str,
    };

    use crate::{
        config::{Config, FeaturesConfig},
        tasks::{
            NoopTasksDb, TaskHandle, TaskNotification,
            scheduler::{Scheduler, SchedulerThreads},
            scheduler_client::SchedulerClient,
        },
    };

    struct TestVerb {
        name: Symbol,
        program: Program,
        argspec: VerbArgsSpec,
    }

    struct FailingDatabase {
        inner: TxDB,
        successful_world_states_before_failure: Arc<AtomicUsize>,
    }

    impl WorldStateSource for FailingDatabase {
        fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
            let remaining = self
                .successful_world_states_before_failure
                .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |remaining| {
                    Some(match remaining {
                        usize::MAX | 0 => usize::MAX,
                        _ => remaining - 1,
                    })
                })
                .unwrap();

            if remaining == 0 {
                return Err(WorldStateError::DatabaseError(
                    "injected new world state failure".to_string(),
                ));
            }

            self.inner.new_world_state()
        }

        fn checkpoint(&self) -> Result<(), WorldStateError> {
            self.inner.checkpoint()
        }
    }

    impl Database for FailingDatabase {
        fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
            self.inner.loader_client()
        }

        fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
            self.inner.create_snapshot()
        }

        fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError> {
            self.inner.create_snapshot_async(callback)
        }

        fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
            self.inner.gc_interface()
        }
    }

    struct GatedConflictDatabase {
        inner: TxDB,
        gate_next_world_state: Arc<AtomicBool>,
        started: flume::Sender<()>,
        release: flume::Receiver<()>,
    }

    impl WorldStateSource for GatedConflictDatabase {
        fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
            let world_state = self.inner.new_world_state()?;
            if self.gate_next_world_state.swap(false, Ordering::SeqCst) {
                self.started.send(()).unwrap();
                self.release.recv().unwrap();
            }
            Ok(world_state)
        }

        fn checkpoint(&self) -> Result<(), WorldStateError> {
            self.inner.checkpoint()
        }
    }

    impl Database for GatedConflictDatabase {
        fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
            self.inner.loader_client()
        }

        fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
            self.inner.create_snapshot()
        }

        fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError> {
            self.inner.create_snapshot_async(callback)
        }

        fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
            self.inner.gc_interface()
        }
    }

    struct NoopSessionFactory;
    impl SessionFactory for NoopSessionFactory {
        fn mk_background_session(
            self: Arc<Self>,
            _player: &Obj,
        ) -> Result<Arc<dyn moor_common::tasks::Session>, SessionError> {
            Ok(Arc::new(NoopClientSession::new()))
        }
    }

    struct RunningScheduler {
        client: SchedulerClient,
        threads: Option<SchedulerThreads>,
    }

    impl Drop for RunningScheduler {
        fn drop(&mut self) {
            let _ = self.client.submit_shutdown("Task test complete");
            if let Some(threads) = self.threads.take() {
                let _ = threads.join();
            }
        }
    }

    fn system_permissions() -> moor_common::model::TaskPermissions {
        moor_common::model::TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
    }

    /// Create a TxDB, populate it with a system object (wizard/programmer),
    /// optionally add verbs, and commit.
    fn setup_database(verbs: &[TestVerb]) -> TxDB {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let mut tx = db.new_world_state().unwrap();

        let sysobj = tx
            .create_object(
                &system_permissions(),
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("name"),
            &v_str("system"),
        )
        .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("programmer"),
            &v_int(1),
        )
        .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("wizard"),
            &v_int(1),
        )
        .unwrap();

        for TestVerb {
            name,
            program,
            argspec,
        } in verbs
        {
            tx.add_verb(
                &system_permissions(),
                &SYSTEM_OBJECT,
                vec![*name],
                &SYSTEM_OBJECT,
                BitEnum::new_with(VerbFlag::Exec),
                *argspec,
                ProgramType::MooR(program.clone()),
            )
            .unwrap();
        }
        tx.commit().unwrap();

        db
    }

    fn start_scheduler(database: Box<dyn Database>) -> (SchedulerClient, RunningScheduler) {
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            database,
            Box::new(NoopTasksDb {}),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("Failed to start scheduler");
        let client = scheduler.client().unwrap();
        let running_scheduler = RunningScheduler {
            client: client.clone(),
            threads: Some(threads),
        };
        (client, running_scheduler)
    }

    fn setup_scheduler(verbs: &[TestVerb]) -> (SchedulerClient, RunningScheduler) {
        start_scheduler(Box::new(setup_database(verbs)))
    }

    fn setup_task_limit_scheduler(
        rollback_on_task_limit: Option<bool>,
    ) -> (SchedulerClient, RunningScheduler, TxDB) {
        let database = setup_database(&[]);
        let mut tx = database.new_world_state().unwrap();
        let server_options = tx
            .create_object(
                &system_permissions(),
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();

        tx.define_property(
            &system_permissions(),
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            Symbol::mk("server_options"),
            &SYSTEM_OBJECT,
            PropFlag::all_flags(),
            Some(v_obj(server_options)),
        )
        .unwrap();
        tx.define_property(
            &system_permissions(),
            &server_options,
            &server_options,
            Symbol::mk("fg_ticks"),
            &SYSTEM_OBJECT,
            PropFlag::all_flags(),
            Some(v_int(200)),
        )
        .unwrap();
        if let Some(rollback_on_task_limit) = rollback_on_task_limit {
            tx.define_property(
                &system_permissions(),
                &server_options,
                &server_options,
                Symbol::mk("rollback_on_task_limit"),
                &SYSTEM_OBJECT,
                PropFlag::all_flags(),
                Some(v_int(rollback_on_task_limit as i64)),
            )
            .unwrap();
        }
        tx.define_property(
            &system_permissions(),
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            Symbol::mk("limit_test_value"),
            &SYSTEM_OBJECT,
            PropFlag::all_flags(),
            Some(v_int(0)),
        )
        .unwrap();
        tx.define_property(
            &system_permissions(),
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            Symbol::mk("limit_test_messages"),
            &SYSTEM_OBJECT,
            PropFlag::all_flags(),
            Some(v_int(0)),
        )
        .unwrap();
        tx.commit().unwrap();

        let database_probe = database.clone();
        let (client, scheduler) = start_scheduler(Box::new(database));
        (client, scheduler, database_probe)
    }

    fn limit_test_property(database: &TxDB, name: &str) -> Var {
        let tx = database.new_world_state().unwrap();
        let value = tx
            .retrieve_property(&system_permissions(), &SYSTEM_OBJECT, Symbol::mk(name))
            .unwrap();
        tx.rollback().unwrap();
        value
    }

    fn wait_for_limit_test_messages(database: &TxDB) -> Var {
        for _ in 0..100 {
            let value = limit_test_property(database, "limit_test_messages");
            if value != v_int(0) {
                return value;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        panic!("Timed out waiting for task-limit message receiver");
    }

    fn setup_failing_scheduler(
        verbs: &[TestVerb],
    ) -> (SchedulerClient, RunningScheduler, Arc<AtomicUsize>) {
        let successful_world_states_before_failure = Arc::new(AtomicUsize::new(usize::MAX));
        let database = FailingDatabase {
            inner: setup_database(verbs),
            successful_world_states_before_failure: successful_world_states_before_failure.clone(),
        };
        let (client, scheduler) = start_scheduler(Box::new(database));
        (client, scheduler, successful_world_states_before_failure)
    }

    /// Wait for a task result, handling suspended notifications.
    fn wait_result(handle: &TaskHandle) -> Result<moor_var::Var, SchedulerError> {
        loop {
            match handle
                .receiver()
                .recv_timeout(Duration::from_secs(5))
                .expect("Task result timed out")
            {
                (_, Ok(TaskNotification::Result(v))) => return Ok(v),
                (_, Ok(TaskNotification::Suspended)) => continue,
                (_, Err(e)) => return Err(e),
            }
        }
    }

    /// Test that we can start a task and run it to completion.
    #[test]
    fn test_simple_run_return() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "return 1 + 1;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(2));
    }

    #[test]
    fn captured_output_survives_conflict_retry() {
        let verb = Symbol::mk("capture_retry");
        let database = setup_database(&[TestVerb {
            name: verb,
            program: compile(
                "name = this.name; notify(player, \"successful attempt\"); this.name = name; return 42;",
                CompileOptions::default(),
            )
            .unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        }]);
        let database_probe = database.clone();
        let gate_next_world_state = Arc::new(AtomicBool::new(false));
        let (started_send, started_recv) = flume::bounded(1);
        let (release_send, release_recv) = flume::bounded(1);
        let (client, _scheduler) = start_scheduler(Box::new(GatedConflictDatabase {
            inner: database,
            gate_next_world_state: gate_next_world_state.clone(),
            started: started_send,
            release: release_recv,
        }));

        gate_next_world_state.store(true, Ordering::SeqCst);
        let session = Arc::new(MockClientSession::new());
        let submit_client = client.clone();
        let submit_session = session.clone();
        let submit = std::thread::spawn(move || {
            submit_client.submit_verb_task(
                &SYSTEM_OBJECT,
                &ObjectRef::Id(SYSTEM_OBJECT),
                verb,
                List::mk_list(&[]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                submit_session,
            )
        });

        started_recv
            .recv_timeout(Duration::from_secs(1))
            .expect("task transaction should reach the conflict gate");
        let mut competing = database_probe.new_world_state().unwrap();
        competing
            .update_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("name"),
                &v_str("concurrent writer"),
            )
            .unwrap();
        assert!(matches!(
            competing.commit().unwrap(),
            CommitResult::Success { .. }
        ));
        release_send.send(()).unwrap();

        let handle = submit.join().unwrap().unwrap();
        assert_eq!(wait_result(&handle), Ok(v_int(42)));
        let committed = session.committed();
        assert_eq!(committed.len(), 1);
        let moor_common::tasks::Event::Notify { value, .. } = committed[0].event() else {
            panic!("expected a notify event");
        };
        assert_eq!(value, v_str("successful attempt"));
    }

    /// A database that counts `new_world_state()` calls, so a test can wait
    /// for a specific transaction (identified by ordinal) to open without
    /// blocking it.
    /// A database whose `new_world_state()` parks on a gate exactly once,
    /// after the world state's snapshot has been taken, so a competing write
    /// landed while parked is guaranteed to be invisible to it (and so
    /// guaranteed to conflict when the parked transaction later commits a
    /// write of its own). This is `GatedConflictDatabase` generalised to
    /// gate an arbitrary sequence of opens, not just the first.
    struct SequencedGateDatabase {
        inner: TxDB,
        /// Remaining gate arm-counts, one entry consumed per `new_world_state`
        /// call while the queue is non-empty. `0` means "don't park"; `1+`
        /// means "park, then decrement" -- kept simple as a shared counter of
        /// *how many future opens should park*, driven externally by storing
        /// `1` before a release and `0` otherwise via `armed`.
        armed: Arc<AtomicBool>,
        started: flume::Sender<()>,
        release: flume::Receiver<()>,
    }

    impl WorldStateSource for SequencedGateDatabase {
        fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
            let world_state = self.inner.new_world_state()?;
            if self.armed.swap(false, Ordering::SeqCst) {
                self.started.send(()).unwrap();
                self.release.recv().unwrap();
            }
            Ok(world_state)
        }

        fn checkpoint(&self) -> Result<(), WorldStateError> {
            self.inner.checkpoint()
        }
    }

    impl Database for SequencedGateDatabase {
        fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
            self.inner.loader_client()
        }
        fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
            self.inner.create_snapshot()
        }
        fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError> {
            self.inner.create_snapshot_async(callback)
        }
        fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
            self.inner.gc_interface()
        }
    }

    /// Drive a task through `conflicts_per_boundary.len()` `commit()`
    /// boundaries, injecting `conflicts_per_boundary[i]` write-write
    /// conflicts on `name` before the i-th boundary's write is allowed to
    /// succeed.
    ///
    /// Every transaction the task opens is parked, snapshot already taken,
    /// exactly like `captured_output_survives_conflict_retry`'s single gate,
    /// but re-armed before every release so a whole schedule of conflicts
    /// can be driven deterministically: while a transaction is parked, its
    /// snapshot cannot see a write landed after that point, so releasing it
    /// straight into a commit is guaranteed to conflict against a write the
    /// driver lands first.
    ///
    /// Returns the task's result and, per injected conflict, the wall time
    /// from releasing the conflicted attempt to the retry's transaction
    /// reaching the gate (the scheduler's backoff delay plus scheduling
    /// slack).
    fn run_with_conflict_schedule(
        conflicts_per_boundary: &[u32],
    ) -> (Result<Var, SchedulerError>, Vec<Duration>) {
        let verb = Symbol::mk("conflict_schedule");
        let mut program = String::new();
        for _ in conflicts_per_boundary {
            // `name` is a special built-in property (object metadata) with
            // its own storage, not the ordinary `object_propvalues` relation
            // the conflict detector tracks -- writing it never conflicts
            // with anything. Use a real user-defined property instead.
            program.push_str("v = this.conflict_counter; this.conflict_counter = v; commit(); ");
        }
        program.push_str("return 7;");
        let database = setup_database(&[TestVerb {
            name: verb,
            program: compile(&program, CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        }]);
        {
            let mut tx = database.new_world_state().unwrap();
            tx.define_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                Symbol::mk("conflict_counter"),
                &SYSTEM_OBJECT,
                PropFlag::all_flags(),
                Some(v_int(0)),
            )
            .unwrap();
            tx.commit().unwrap();
        }
        let database_probe = database.clone();
        let armed = Arc::new(AtomicBool::new(false));
        let (started_send, started_recv) = flume::bounded(1);
        let (release_send, release_recv) = flume::bounded(1);
        let (client, _scheduler) = start_scheduler(Box::new(SequencedGateDatabase {
            inner: database,
            armed: armed.clone(),
            started: started_send,
            release: release_recv,
        }));

        armed.store(true, Ordering::SeqCst);
        let session = Arc::new(NoopClientSession::new());
        let submit_client = client.clone();
        let submit = std::thread::spawn(move || {
            submit_client.submit_verb_task(
                &SYSTEM_OBJECT,
                &ObjectRef::Id(SYSTEM_OBJECT),
                verb,
                List::mk_list(&[]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                session,
            )
        });

        let mut retry_durations = Vec::new();
        // Invariant at the top of each loop body below: the task has a
        // transaction open and parked at the gate, snapshot already taken.
        started_recv
            .recv_timeout(Duration::from_secs(5))
            .expect("task's first transaction should reach the gate");
        for (i, &conflicts) in conflicts_per_boundary.iter().enumerate() {
            for c in 0..conflicts {
                // Land a competing write invisible to the parked snapshot.
                let mut competing = database_probe.new_world_state().unwrap();
                competing
                    .update_property(
                        &system_permissions(),
                        &SYSTEM_OBJECT,
                        Symbol::mk("conflict_counter"),
                        &v_int(1000 + (i as i64) * 100 + c as i64),
                    )
                    .unwrap();
                assert!(matches!(
                    competing.commit().unwrap(),
                    CommitResult::Success { .. }
                ));
                // Arm the gate for the retry's transaction, then release
                // this parked one into its (now-conflicting) commit.
                armed.store(true, Ordering::SeqCst);
                let released_at = std::time::Instant::now();
                release_send.send(()).unwrap();
                started_recv
                    .recv_timeout(Duration::from_secs(10))
                    .unwrap_or_else(|_| {
                        panic!("boundary {i} conflict {c}: retry never reached the gate")
                    });
                retry_durations.push(released_at.elapsed());
            }
            // Arm the gate for the next boundary's transaction (unless this
            // was the last boundary), then release this attempt, which
            // commits successfully.
            let is_last_boundary = i + 1 == conflicts_per_boundary.len();
            if !is_last_boundary {
                armed.store(true, Ordering::SeqCst);
            }
            release_send.send(()).unwrap();
            if !is_last_boundary {
                started_recv
                    .recv_timeout(Duration::from_secs(5))
                    .unwrap_or_else(|_| {
                        panic!("boundary {i}: next boundary never reached the gate")
                    });
            }
        }

        let handle = submit.join().unwrap().unwrap();
        (wait_result(&handle), retry_durations)
    }

    /// A successful transaction boundary resets the consecutive-retry
    /// counter. Three conflicts before the first boundary push `retries` to
    /// 3; after that boundary succeeds, one conflict before the second
    /// boundary must be retry #1 (backoff shift 0: 10-50ms), not retry #4
    /// (shift 3: 80-400ms).
    #[test]
    fn retries_reset_after_successful_boundary() {
        let (result, retries) = run_with_conflict_schedule(&[3, 1]);
        assert_eq!(result, Ok(v_int(7)));
        assert_eq!(retries.len(), 4, "expected 4 injected conflicts total");
        // First conflict on the second boundary (overall retry #4): shift 0.
        // Without the counter reset this would be retry #4, shift 3
        // (>= 80ms base backoff alone, before scheduling slack).
        assert!(
            retries[3] < Duration::from_millis(70),
            "retry after a successful boundary should use shift 0 (10-50ms base, \
             no shift), got {:?}; without the counter reset this would be \
             shift 3 (>= 80ms)",
            retries[3]
        );
    }

    /// One conflict per boundary, across more boundaries than
    /// `max_task_retries` (10 by default), never aborts: the limit bounds
    /// consecutive retries against one piece of work, not lifetime retries
    /// of a long-lived task. Before the fix in `refresh_retry_state`, this
    /// task would abort with `TaskAbortedError` on its 10th lifetime
    /// conflict even though no boundary ever saw more than one.
    #[test]
    fn one_retry_per_boundary_never_aborts() {
        let boundaries = 12;
        let schedule = vec![1u32; boundaries];
        let (result, retries) = run_with_conflict_schedule(&schedule);
        assert_eq!(
            result,
            Ok(v_int(7)),
            "task should complete despite 12 lifetime conflicts (> max_task_retries \
             of 10), since only one conflict ever occurs per boundary"
        );
        assert_eq!(retries.len(), boundaries);
    }

    /// Killing the current task aborts it instead of completing successfully.
    #[test]
    fn test_kill_current_task() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "kill_task(task_id()); return 1;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let err = wait_result(&handle).unwrap_err();
        assert!(matches!(err, SchedulerError::TaskAbortedCancelled));
    }

    /// A schedule created in a task that then rolls back must never exist:
    /// creation is buffered until commit, exactly like `task_send`.
    #[test]
    fn schedule_creation_is_discarded_on_rollback() {
        let (client, scheduler) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "add_verb(#0, {#0, \"rxd\", \"sched_probe\"}, {\"this\", \"none\", \"this\"}); \
                 set_verb_code(#0, \"sched_probe\", {\"return 0;\"}); commit(); \
                 id = schedule_at(#0, \"sched_probe\", time() + 3600); rollback(); return id;"
                    .to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        // rollback() ends the task without a normal result.
        let _ = wait_result(&handle);
        let lc = scheduler.client.scheduler_for_test().lifecycle.lock();
        assert!(
            lc.schedule_q.all_ids().is_empty(),
            "rolled-back schedule_at must not leave an entry: {:?}",
            lc.schedule_q.all_ids()
        );
        assert!(lc.task_q.active.is_empty());
    }

    /// Trigger a MOO VM exception
    #[test]
    fn test_simple_run_exception() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "return 1 / 0;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let err = wait_result(&handle).unwrap_err();
        match err {
            SchedulerError::TaskAbortedException(ex) => {
                assert_eq!(ex.error.err_type(), E_DIV);
            }
            other => panic!("Expected TaskAbortedException, got {other:?}"),
        }
    }

    #[test]
    fn task_limit_commits_world_state_and_output_by_default() {
        let (client, _sched, database) = setup_task_limit_scheduler(None);
        let session = Arc::new(MockClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                r#"
                    fork receiver (0.05)
                        #0.limit_test_messages = task_recv();
                    endfork
                    task_send(receiver, 42);
                    #0.limit_test_value = 1;
                    notify(#0, "before task limit");
                    while (1)
                    endwhile
                "#
                .to_string(),
                None,
                session.clone(),
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();

        let error = wait_result(&handle).unwrap_err();
        assert!(matches!(error, SchedulerError::TaskAbortedLimit(_)));
        assert_eq!(limit_test_property(&database, "limit_test_value"), v_int(1));
        assert_eq!(
            wait_for_limit_test_messages(&database),
            List::from_iter([v_int(42)]).into()
        );
        assert_eq!(session.committed().len(), 1);
        assert_eq!(session.system().len(), 1);
    }

    #[test]
    fn task_limit_can_roll_back_world_state_and_output() {
        let (client, _sched, database) = setup_task_limit_scheduler(Some(true));
        let session = Arc::new(MockClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                r#"
                    fork receiver (0.05)
                        #0.limit_test_messages = task_recv();
                    endfork
                    task_send(receiver, 42);
                    #0.limit_test_value = 1;
                    notify(#0, "before task limit");
                    while (1)
                    endwhile
                "#
                .to_string(),
                None,
                session.clone(),
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();

        let error = wait_result(&handle).unwrap_err();
        assert!(matches!(error, SchedulerError::TaskAbortedLimit(_)));
        assert_eq!(limit_test_property(&database, "limit_test_value"), v_int(0));
        assert_eq!(
            wait_for_limit_test_messages(&database),
            List::from_iter([]).into()
        );
        assert!(session.committed().is_empty());
        assert_eq!(session.system().len(), 1);
    }

    /// notify() dispatches to the scheduler (no crash, returns successfully)
    #[test]
    fn test_notify_invocation() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                r#"notify(#0, "12345"); return 123;"#.to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(123));
    }

    /// Trigger a task-suspend-resume via suspend(0) (commit-and-continue)
    #[test]
    fn test_simple_run_suspend() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "suspend(0); return 123;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(123));
    }

    #[test]
    fn read_uses_task_player_when_authority_differs() {
        let verb = Symbol::mk("read_helper");
        let (client, _sched) = setup_scheduler(&[TestVerb {
            name: verb,
            program: compile("return read();", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        }]);
        let player = Obj::mk_id(4);
        let session = Arc::new(MockClientSession::new());
        let handle = client
            .submit_verb_task(
                &player,
                &ObjectRef::Id(SYSTEM_OBJECT),
                verb,
                List::mk_list(&[]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                session.clone(),
            )
            .unwrap();

        let deadline = Instant::now() + Duration::from_secs(5);
        let input_request_id = loop {
            if let Some((input_player, input_request_id, _)) =
                session.input_requests().into_iter().next()
            {
                assert_eq!(input_player, player);
                break input_request_id;
            }
            if let Ok((_, result)) = handle.receiver().try_recv() {
                match result {
                    Ok(TaskNotification::Suspended) => {}
                    Ok(TaskNotification::Result(value)) => {
                        panic!("read task returned before requesting input: {value:?}")
                    }
                    Err(error) => panic!("read task aborted before requesting input: {error:?}"),
                }
            }
            assert!(Instant::now() < deadline, "input request timed out");
            std::thread::yield_now();
        };

        client
            .submit_requested_input(&player, &player, input_request_id, v_str("hello"))
            .unwrap();
        assert_eq!(wait_result(&handle).unwrap(), v_str("hello"));
    }

    #[test]
    fn read_can_target_another_player_with_wizard_authority() {
        let verb = Symbol::mk("read_other_helper");
        let (client, _sched) = setup_scheduler(&[TestVerb {
            name: verb,
            program: compile("return read(#0);", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        }]);
        let task_player = Obj::mk_id(4);
        let input_player = SYSTEM_OBJECT;
        let session = Arc::new(MockClientSession::new());
        let handle = client
            .submit_verb_task(
                &task_player,
                &ObjectRef::Id(SYSTEM_OBJECT),
                verb,
                List::mk_list(&[]),
                v_empty_str(),
                &SYSTEM_OBJECT,
                session.clone(),
            )
            .unwrap();

        let deadline = Instant::now() + Duration::from_secs(5);
        let input_request_id = loop {
            if let Some((requested_player, input_request_id, _)) =
                session.input_requests().into_iter().next()
            {
                assert_eq!(requested_player, input_player);
                break input_request_id;
            }
            if let Ok((_, result)) = handle.receiver().try_recv() {
                match result {
                    Ok(TaskNotification::Suspended) => {}
                    Ok(TaskNotification::Result(value)) => {
                        panic!("read task returned before requesting input: {value:?}")
                    }
                    Err(error) => panic!("read task aborted before requesting input: {error:?}"),
                }
            }
            assert!(Instant::now() < deadline, "input request timed out");
            std::thread::yield_now();
        };

        client
            .submit_requested_input(
                &input_player,
                &input_player,
                input_request_id,
                v_str("remote"),
            )
            .unwrap();
        assert_eq!(wait_result(&handle).unwrap(), v_str("remote"));
    }

    #[test]
    fn test_suspend_zero_transaction_renewal_failure_aborts_cleanly() {
        let (client, _sched, successful_world_states_before_failure) = setup_failing_scheduler(&[]);

        // Allow the initial task transaction, then fail the replacement requested by suspend(0).
        successful_world_states_before_failure.store(1, Ordering::SeqCst);

        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "suspend(0); return 123;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();

        let error = wait_result(&handle).unwrap_err();
        assert_eq!(error, SchedulerError::CouldNotStartTask);
    }

    /// Trigger a task-fork — fork spawns a child, parent returns its own value
    #[test]
    fn test_simple_run_fork() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "fork (0) endfork return 123;".to_string(),
                None,
                session,
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(123));
    }

    /// Verifies path through the command parser, and no match on verb
    #[test]
    fn test_command_no_match() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look here", session)
            .unwrap();
        let err = wait_result(&handle).unwrap_err();
        assert!(
            matches!(
                err,
                SchedulerError::CommandExecutionError(CommandError::NoCommandMatch)
            ),
            "Expected NoCommandMatch, got {err:?}"
        );
    }

    /// Install a simple verb that will match and execute, without $do_command.
    #[test]
    fn test_command_match() {
        let look_this = TestVerb {
            name: Symbol::mk("look"),
            program: compile("return 1;", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec {
                dobj: ArgSpec::This,
                prep: PrepSpec::None,
                iobj: ArgSpec::None,
            },
        };
        let (client, _sched) = setup_scheduler(&[look_this]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look #0", session)
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(1));
    }

    /// Install "do_command" that returns true — command was handled.
    #[test]
    fn test_command_do_command() {
        let do_command_verb = TestVerb {
            name: Symbol::mk("do_command"),
            program: compile("return 1;", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        };
        let (client, _sched) = setup_scheduler(&[do_command_verb]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look here", session)
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(1));
    }

    /// Install "do_command" that returns false — falls through to verb dispatch, no match.
    #[test]
    fn test_command_do_command_false_no_match() {
        let do_command_verb = TestVerb {
            name: Symbol::mk("do_command"),
            program: compile("return 0;", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        };
        let (client, _sched) = setup_scheduler(&[do_command_verb]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look here", session)
            .unwrap();
        let err = wait_result(&handle).unwrap_err();
        assert!(
            matches!(
                err,
                SchedulerError::CommandExecutionError(CommandError::NoCommandMatch)
            ),
            "Expected NoCommandMatch, got {err:?}"
        );
    }

    /// Install "do_command" that returns false + a matching verb — falls through and matches.
    #[test]
    fn test_command_do_command_false_match() {
        let do_command_verb = TestVerb {
            name: Symbol::mk("do_command"),
            program: compile("return 0;", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec::this_none_this(),
        };
        let look_this = TestVerb {
            name: Symbol::mk("look"),
            program: compile("return 1;", CompileOptions::default()).unwrap(),
            argspec: VerbArgsSpec {
                dobj: ArgSpec::This,
                prep: PrepSpec::None,
                iobj: ArgSpec::None,
            },
        };
        let (client, _sched) = setup_scheduler(&[do_command_verb, look_this]);
        let session = Arc::new(NoopClientSession::new());
        let handle = client
            .submit_command_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, "look #0", session)
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(1));
    }

    // =========================================================================
    // Batch World State Task Tests
    // =========================================================================

    #[test]
    fn test_batch_world_state_empty() {
        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let (handle, result_sink) = client
            .submit_batch_world_state_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, vec![], false, session)
            .unwrap();
        let result = wait_result(&handle).unwrap();
        assert_eq!(result, v_int(0));

        let sink = result_sink.lock().unwrap();
        let results = sink.as_ref().unwrap().as_ref().unwrap();
        assert!(results.is_empty());
    }

    #[test]
    fn test_batch_world_state_read_property() {
        use crate::tasks::world_state_action::{WorldStateAction, WorldStateResult};
        use moor_common::model::ObjectRef;

        let actions = vec![WorldStateAction::RequestSystemProperty {
            player: SYSTEM_OBJECT,
            obj: ObjectRef::Id(SYSTEM_OBJECT),
            property: Symbol::mk("name"),
        }];

        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let (handle, result_sink) = client
            .submit_batch_world_state_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, actions, false, session)
            .unwrap();
        wait_result(&handle).unwrap();

        let sink = result_sink.lock().unwrap();
        let results = sink.as_ref().unwrap().as_ref().unwrap();
        assert_eq!(results.len(), 1);
        match &results[0] {
            WorldStateResult::SystemProperty(v) => assert_eq!(*v, v_str("system")),
            other => panic!("Expected SystemProperty, got {other:?}"),
        }
    }

    #[test]
    fn test_batch_world_state_rollback() {
        use crate::tasks::world_state_action::{WorldStateAction, WorldStateResult};
        use moor_common::model::ObjectRef;

        let actions = vec![
            WorldStateAction::UpdateProperty {
                player: SYSTEM_OBJECT,
                authority_principal: SYSTEM_OBJECT,
                obj: ObjectRef::Id(SYSTEM_OBJECT),
                property: Symbol::mk("name"),
                value: v_str("modified"),
            },
            WorldStateAction::RequestSystemProperty {
                player: SYSTEM_OBJECT,
                obj: ObjectRef::Id(SYSTEM_OBJECT),
                property: Symbol::mk("name"),
            },
        ];

        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let (handle, result_sink) = client
            .submit_batch_world_state_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, actions, true, session)
            .unwrap();
        wait_result(&handle).unwrap();

        let sink = result_sink.lock().unwrap();
        let results = sink.as_ref().unwrap().as_ref().unwrap();
        assert_eq!(results.len(), 2);
        match &results[0] {
            WorldStateResult::PropertyUpdated => {}
            other => panic!("Expected PropertyUpdated, got {other:?}"),
        }
        match &results[1] {
            WorldStateResult::SystemProperty(v) => assert_eq!(*v, v_str("modified")),
            other => panic!("Expected SystemProperty, got {other:?}"),
        }
        drop(sink);

        let actions = vec![WorldStateAction::RequestSystemProperty {
            player: SYSTEM_OBJECT,
            obj: ObjectRef::Id(SYSTEM_OBJECT),
            property: Symbol::mk("name"),
        }];
        let (handle, result_sink) = client
            .submit_batch_world_state_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                actions,
                false,
                Arc::new(NoopClientSession::new()),
            )
            .unwrap();
        wait_result(&handle).unwrap();
        let sink = result_sink.lock().unwrap();
        let results = sink.as_ref().unwrap().as_ref().unwrap();
        assert!(matches!(
            results.as_slice(),
            [WorldStateResult::SystemProperty(value)] if *value == v_str("system")
        ));
    }

    #[test]
    fn test_batch_world_state_multiple_reads() {
        use crate::tasks::world_state_action::{WorldStateAction, WorldStateResult};
        use moor_common::model::ObjectRef;

        let actions = vec![
            WorldStateAction::RequestSystemProperty {
                player: SYSTEM_OBJECT,
                obj: ObjectRef::Id(SYSTEM_OBJECT),
                property: Symbol::mk("name"),
            },
            WorldStateAction::GetObjectFlags { obj: SYSTEM_OBJECT },
            WorldStateAction::RequestAllObjects {
                player: SYSTEM_OBJECT,
            },
            WorldStateAction::ResolveObject {
                player: SYSTEM_OBJECT,
                obj: ObjectRef::Id(SYSTEM_OBJECT),
            },
        ];

        let (client, _sched) = setup_scheduler(&[]);
        let session = Arc::new(NoopClientSession::new());
        let (handle, result_sink) = client
            .submit_batch_world_state_task(&SYSTEM_OBJECT, &SYSTEM_OBJECT, actions, false, session)
            .unwrap();
        wait_result(&handle).unwrap();

        let sink = result_sink.lock().unwrap();
        let results = sink.as_ref().unwrap().as_ref().unwrap();
        assert_eq!(results.len(), 4);

        assert!(matches!(&results[0], WorldStateResult::SystemProperty(_)));
        assert!(matches!(&results[1], WorldStateResult::ObjectFlags(_)));
        assert!(matches!(&results[2], WorldStateResult::AllObjects(_)));
        assert!(matches!(&results[3], WorldStateResult::ResolvedObject(_)));
    }
}
