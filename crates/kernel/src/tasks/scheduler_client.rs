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

use std::{sync::Arc, time::Duration};

use moor_common::model::{ObjectRef, PropDef, PropPerms, VerbDef, VerbDefs};
use moor_common::tasks::{SchedulerError, SchedulerError::CompilationError, Session};
use moor_compiler::compile;
use moor_var::{List, Obj, Symbol, Var};

use crate::tasks::scheduler::{Scheduler, SchedulerState};
use crate::tasks::world_state_action::{
    WorldStateAction, WorldStateRequest, WorldStateResponse, WorldStateResult,
};
use crate::{
    config::FeaturesConfig,
    tasks::{SchedulerOp, TaskHandle, sched_counters},
};

const DEFAULT_REQUEST_TIMEOUT: Duration = Duration::from_secs(5);
const GC_REQUEST_TIMEOUT: Duration = Duration::from_secs(10);
const LONG_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Garbage collection statistics
#[derive(Debug, Clone)]
pub struct GCStats {
    /// Total number of GC cycles completed
    pub cycle_count: u64,
}

/// A handle for talking to the scheduler from the outside world.
/// This is not meant to be used by running tasks, but by the rpc daemon, tests, etc.
/// Handles requests for task submission, shutdown, etc.
#[derive(Clone)]
pub struct SchedulerClient {
    scheduler: Scheduler,
}

impl SchedulerClient {
    pub fn new(scheduler: Scheduler) -> Self {
        Self { scheduler }
    }

    fn request_with_timeout<T>(
        &self,
        timeout: Duration,
        request: impl FnOnce(&Scheduler) -> Result<T, SchedulerError> + Send + 'static,
    ) -> Result<T, SchedulerError>
    where
        T: Send + 'static,
    {
        let (reply_send, reply_recv) = flume::bounded(1);
        self.scheduler
            .enqueue_client_request(Box::new(move |scheduler| {
                let result = request(scheduler);
                reply_send.send(result).ok();
            }))?;

        reply_recv
            .recv_timeout(timeout)
            .map_err(|_| SchedulerError::SchedulerNotResponding)?
    }

    fn ensure_running(&self) -> Result<(), SchedulerError> {
        if self.scheduler.state() != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        Ok(())
    }

    /// Submit a command to the scheduler for execution.
    pub fn submit_command_task(
        &self,
        handler_object: &Obj,
        player: &Obj,
        command: &str,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::SubmitCommandTaskLatency);

        let handler_object = *handler_object;
        let player = *player;
        let command = command.to_string();
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_command_task_inner(handler_object, player, command, session)
        })
    }

    /// Submit a verb task to the scheduler for execution.
    /// (This path is really only used for the invocations from the serving processes like login,
    /// user_connected, or the do_command invocation which precedes an internal parser attempt.)
    // Yes yes I know it's a lot of arguments, but wrapper object here is redundant.
    #[allow(clippy::too_many_arguments)]
    pub fn submit_verb_task(
        &self,
        player: &Obj,
        vloc: &ObjectRef,
        verb: Symbol,
        args: List,
        argstr: Var,
        authority_principal: &Obj,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::SubmitVerbTaskLatency);

        let player = *player;
        let vloc = vloc.clone();
        let authority_principal = *authority_principal;
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_verb_task_inner(
                player,
                vloc,
                verb,
                args,
                argstr,
                authority_principal,
                session,
            )
        })
    }

    /// Receive input that the suspended task requested from the authenticated connection.
    /// The request is identified by the `input_request_id`, and given the input and resumed under
    /// a new transaction.
    pub fn submit_requested_input(
        &self,
        connection: &Obj,
        player: &Obj,
        input_request_id: uuid::Uuid,
        input: Var,
    ) -> Result<(), SchedulerError> {
        let connection = *connection;
        let player = *player;
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_task_input_inner(connection, player, input_request_id, input)
        })
    }

    pub fn submit_out_of_band_task(
        &self,
        handler_object: &Obj,
        player: &Obj,
        command: List,
        argstr: Var,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::SubmitOobTaskLatency);

        let handler_object = *handler_object;
        let player = *player;
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_oob_task_inner(handler_object, player, command, argstr, session)
        })
    }

    /// Submit an eval task to the scheduler for execution.
    pub fn submit_eval_task(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        code: String,
        initial_env: Option<Vec<(Symbol, Var)>>,
        sessions: Arc<dyn Session>,
        config: Arc<FeaturesConfig>,
    ) -> Result<TaskHandle, SchedulerError> {
        self.ensure_running()?;

        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::SubmitEvalTaskLatency);

        // Compile the text into a verb.
        let program = match compile(code.as_str(), config.compile_options()) {
            Ok(b) => b,
            Err(e) => return Err(CompilationError(e)),
        };

        let player = *player;
        let authority_principal = *authority_principal;
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_eval_task_inner(
                player,
                authority_principal,
                program,
                initial_env,
                sessions,
            )
        })
    }

    pub fn submit_shutdown(&self, msg: &str) -> Result<(), SchedulerError> {
        let msg = msg.to_string();
        self.request_with_timeout(LONG_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.handle_shutdown_request(msg)
        })
    }

    pub fn submit_verb_program(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        verb_name: Symbol,
        code: Vec<String>,
    ) -> Result<(Obj, Symbol), SchedulerError> {
        let action = WorldStateAction::ProgramVerb {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            verb_name,
            code,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::VerbProgrammed { object, verb },
                ..
            }) => Ok((object, verb)),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn request_system_property(
        &self,
        player: &Obj,
        obj: &ObjectRef,
        property: Symbol,
    ) -> Result<Var, SchedulerError> {
        let action = WorldStateAction::RequestSystemProperty {
            player: *player,
            obj: obj.clone(),
            property,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::SystemProperty(value),
                ..
            }) => Ok(value),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn request_checkpoint(&self) -> Result<(), SchedulerError> {
        self.request_checkpoint_with_blocking(false)
    }

    /// Request a checkpoint and wait for the textdump generation to complete.
    ///
    /// This method blocks until the final textdump file has been published.
    pub fn request_checkpoint_blocking(&self) -> Result<(), SchedulerError> {
        self.request_checkpoint_with_blocking(true)
    }

    /// Request a checkpoint with optional blocking behavior.
    ///
    /// If `blocking` is true, waits for the textdump generation to complete.
    /// If false, returns immediately after initiating the checkpoint.
    pub fn request_checkpoint_with_blocking(&self, blocking: bool) -> Result<(), SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::CheckpointLatency);

        self.ensure_running()?;
        let ticket = self.scheduler.begin_checkpoint()?;
        if blocking { ticket.wait() } else { Ok(()) }
    }

    /// Check if the scheduler is alive and responding (lightweight operation)
    pub fn check_status(&self) -> Result<(), SchedulerError> {
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, Scheduler::handle_check_status)
    }

    /// Get garbage collection statistics from the scheduler
    pub fn get_gc_stats(&self) -> Result<GCStats, SchedulerError> {
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, Scheduler::handle_get_gc_stats)
    }

    /// Request a garbage collection cycle from the scheduler
    pub fn request_gc(&self) -> Result<(), SchedulerError> {
        self.request_with_timeout(GC_REQUEST_TIMEOUT, Scheduler::handle_request_gc)
    }

    pub fn request_verbs(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        inherited: bool,
    ) -> Result<VerbDefs, SchedulerError> {
        let action = WorldStateAction::RequestVerbs {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            inherited,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::Verbs(verbs),
                ..
            }) => Ok(verbs),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn request_verb(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        verb: Symbol,
    ) -> Result<(VerbDef, Vec<String>), SchedulerError> {
        let action = WorldStateAction::RequestVerbCode {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            verb,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::VerbCode(verbdef, code),
                ..
            }) => Ok((verbdef, code)),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn request_properties(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        inherited: bool,
    ) -> Result<Vec<(PropDef, PropPerms)>, SchedulerError> {
        let action = WorldStateAction::RequestProperties {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            inherited,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::Properties(props),
                ..
            }) => Ok(props),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn request_property(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        property: Symbol,
    ) -> Result<(PropDef, PropPerms, Var), SchedulerError> {
        let action = WorldStateAction::RequestProperty {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            property,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::Property(info, perms, value),
                ..
            }) => Ok((info, perms, value)),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    pub fn resolve_object(&self, player: Obj, obj: ObjectRef) -> Result<Var, SchedulerError> {
        let action = WorldStateAction::ResolveObject { player, obj };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::ResolvedObject(value),
                ..
            }) => Ok(value),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    /// Execute a batch of WorldStateActions.
    pub fn execute_world_state_actions(
        &self,
        actions: Vec<WorldStateRequest>,
        rollback: bool,
    ) -> Result<Vec<WorldStateResponse>, SchedulerError> {
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.execute_world_state_actions_inner(actions, rollback)
        })
    }

    /// Submit a batch of WorldStateActions as a tracked task.
    /// Returns a `TaskHandle` and a shared sink where the batch results will be
    /// deposited before the task reports success.
    /// Unlike `execute_world_state_actions`, this creates a proper task visible
    /// to `queued_tasks()` and subject to task limits.
    pub fn submit_batch_world_state_task(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        actions: Vec<WorldStateAction>,
        rollback: bool,
        session: Arc<dyn Session>,
    ) -> Result<(TaskHandle, crate::tasks::BatchResultSink), SchedulerError> {
        let result_sink: crate::tasks::BatchResultSink = Arc::new(std::sync::Mutex::new(None));
        let task_result_sink = result_sink.clone();
        let player = *player;
        let authority_principal = *authority_principal;

        let handle = self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_batch_world_state_task_inner(
                player,
                authority_principal,
                actions,
                rollback,
                task_result_sink,
                session,
            )
        })?;

        Ok((handle, result_sink))
    }

    /// Load an object from objdef text.
    pub fn load_object(
        &self,
        object_definition: String,
        options: moor_objdef::ObjDefLoaderOptions,
        return_conflicts: bool,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::LoadObjectLatency);

        self.request_with_timeout(LONG_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.handle_load_object_request(object_definition, options, return_conflicts)
        })
    }

    /// Submit a system handler task with proper permissions lookup.
    /// This method looks up the #0.invoke_handler_perms property and uses that user
    /// as the permissions object for the verb invocation.
    pub fn submit_system_handler_task(
        &self,
        player: &Obj,
        handler_type: String,
        args: Vec<Var>,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::SubmitSystemHandlerTaskLatency);

        let player = *player;
        self.request_with_timeout(DEFAULT_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.submit_system_handler_task_inner(player, handler_type, args, session)
        })
    }

    /// Reload an existing object from objdef text, completely replacing its contents.
    pub fn reload_object(
        &self,
        object_definition: String,
        constants: Option<moor_objdef::Constants>,
        target_obj: Option<Obj>,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::ReloadObjectLatency);

        self.request_with_timeout(LONG_REQUEST_TIMEOUT, move |scheduler| {
            scheduler.handle_reload_object_request(object_definition, constants, target_obj)
        })
    }

    /// Get all objects in the database (for tab completion)
    pub fn request_all_objects(&self, player: Obj) -> Result<Vec<Obj>, SchedulerError> {
        let action = WorldStateAction::RequestAllObjects { player };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::AllObjects(objects),
                ..
            }) => Ok(objects),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    /// List all objects with metadata (for object browser)
    pub fn list_objects(
        &self,
        player: &Obj,
    ) -> Result<Vec<(Obj, moor_common::model::ObjAttrs, usize, usize)>, SchedulerError> {
        let action = WorldStateAction::ListObjects { player: *player };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::ObjectsList(objects),
                ..
            }) => Ok(objects),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    /// Get flags for a specific object
    pub fn get_object_flags(&self, obj: &Obj) -> Result<u16, SchedulerError> {
        let action = WorldStateAction::GetObjectFlags { obj: *obj };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::ObjectFlags(flags),
                ..
            }) => Ok(flags),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }

    /// Update a property value
    pub fn update_property(
        &self,
        player: &Obj,
        authority_principal: &Obj,
        obj: &ObjectRef,
        property: Symbol,
        value: Var,
    ) -> Result<(), SchedulerError> {
        let action = WorldStateAction::UpdateProperty {
            player: *player,
            authority_principal: *authority_principal,
            obj: obj.clone(),
            property,
            value,
        };
        let request = WorldStateRequest::new(action);
        let responses = self.execute_world_state_actions(vec![request], false)?;

        match responses.into_iter().next() {
            Some(WorldStateResponse::Success {
                result: WorldStateResult::PropertyUpdated,
                ..
            }) => Ok(()),
            Some(WorldStateResponse::Error { error, .. }) => Err(error),
            _ => Err(SchedulerError::SchedulerNotResponding),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        config::{Config, FeaturesConfig},
        tasks::{NoopTasksDb, TaskHandle, TaskNotification, scheduler::Scheduler},
    };
    use moor_common::{
        model::{
            ObjFlag, ObjectKind, TaskPermissions, WorldState, WorldStateError, WorldStateSource,
            loader::{LoaderInterface, SnapshotInterface},
        },
        tasks::{NoopClientSession, NoopSystemControl, SessionError, SessionFactory},
        util::BitEnum,
    };
    use moor_db::{Database, DatabaseConfig, GCInterface, SnapshotCallback, TxDB};
    use moor_var::{NOTHING, SYSTEM_OBJECT, v_int};
    use std::sync::{Mutex as StdMutex, mpsc};

    struct GatedSnapshotDatabase {
        inner: TxDB,
        started: mpsc::Sender<()>,
        release: Arc<StdMutex<mpsc::Receiver<()>>>,
    }

    impl WorldStateSource for GatedSnapshotDatabase {
        fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
            self.inner.new_world_state()
        }

        fn checkpoint(&self) -> Result<(), WorldStateError> {
            self.inner.checkpoint()
        }
    }

    impl Database for GatedSnapshotDatabase {
        fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
            self.inner.loader_client()
        }

        fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
            self.inner.create_snapshot()
        }

        fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError> {
            let snapshot = self.inner.create_snapshot()?;
            let started = self.started.clone();
            let release = self.release.clone();
            std::thread::spawn(move || {
                started.send(()).unwrap();
                release.lock().unwrap().recv().unwrap();
                callback(Ok(snapshot)).unwrap();
            });
            Ok(())
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
        ) -> Result<Arc<dyn Session>, SessionError> {
            Ok(Arc::new(NoopClientSession::new()))
        }
    }

    fn gated_scheduler() -> (
        SchedulerClient,
        crate::tasks::scheduler::SchedulerThreads,
        mpsc::Receiver<()>,
        mpsc::Sender<()>,
        tempfile::TempDir,
    ) {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let mut world_state = database.new_world_state().unwrap();
        let permissions = TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new());
        let system_object = world_state
            .create_object(
                &permissions,
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        assert_eq!(system_object, SYSTEM_OBJECT);
        world_state.commit().unwrap();
        let (started_send, started_recv) = mpsc::channel();
        let (release_send, release_recv) = mpsc::channel();
        let database = GatedSnapshotDatabase {
            inner: database,
            started: started_send,
            release: Arc::new(StdMutex::new(release_recv)),
        };
        let output = tempfile::tempdir().unwrap();
        let mut config = Config::default();
        config.import_export.output_path = Some(output.path().to_path_buf());
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(NoopTasksDb {}),
            Arc::new(config),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );
        let client = scheduler.client().unwrap();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");
        (client, threads, started_recv, release_send, output)
    }

    fn wait_for_task(handle: &TaskHandle) -> Result<Var, SchedulerError> {
        loop {
            match handle
                .receiver()
                .recv_timeout(Duration::from_secs(2))
                .expect("task result timed out")
            {
                (_, Ok(TaskNotification::Result(value))) => return Ok(value),
                (_, Ok(TaskNotification::Suspended)) => {}
                (_, Err(error)) => return Err(error),
            }
        }
    }

    #[test]
    fn bounded_request_reports_scheduler_timeout() {
        let (database, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let scheduler = Scheduler::new(
            semver::Version::new(0, 0, 0),
            Box::new(database),
            Box::new(NoopTasksDb {}),
            Arc::new(Config::default()),
            Arc::new(NoopSystemControl::default()),
            None,
            None,
        );
        let client = scheduler.client().unwrap();
        let threads = scheduler
            .start(Arc::new(NoopSessionFactory))
            .expect("scheduler should start");

        let result = client.request_with_timeout(Duration::from_millis(20), |_scheduler| {
            std::thread::sleep(Duration::from_millis(200));
            Ok(())
        });
        assert_eq!(result, Err(SchedulerError::SchedulerNotResponding));

        client
            .submit_shutdown("timeout test complete")
            .expect("scheduler should process shutdown after the delayed request");
        threads
            .join()
            .expect("all scheduler-owned threads should stop");
    }

    #[test]
    fn blocking_checkpoint_does_not_block_scheduler_requests() {
        let (client, threads, started, release, _output) = gated_scheduler();
        let blocking_client = client.clone();
        let checkpoint = std::thread::spawn(move || blocking_client.request_checkpoint_blocking());

        started.recv_timeout(Duration::from_secs(1)).unwrap();
        assert_eq!(client.check_status(), Ok(()));
        assert_eq!(
            client.request_checkpoint(),
            Err(SchedulerError::CheckpointInProgress)
        );

        release.send(()).unwrap();
        assert_eq!(checkpoint.join().unwrap(), Ok(()));
        client.submit_shutdown("checkpoint test complete").unwrap();
        threads.join().unwrap();
    }

    #[test]
    fn shutdown_waits_for_active_checkpoint() {
        let (client, threads, started, release, _output) = gated_scheduler();
        client.request_checkpoint().unwrap();
        started.recv_timeout(Duration::from_secs(1)).unwrap();

        let shutdown_client = client.clone();
        let (shutdown_done_send, shutdown_done_recv) = mpsc::channel();
        let shutdown = std::thread::spawn(move || {
            let result = shutdown_client.submit_shutdown("checkpoint shutdown test");
            shutdown_done_send.send(()).unwrap();
            result
        });
        assert!(
            shutdown_done_recv
                .recv_timeout(Duration::from_millis(50))
                .is_err()
        );

        release.send(()).unwrap();
        assert_eq!(shutdown.join().unwrap(), Ok(()));
        threads.join().unwrap();
    }

    #[test]
    fn blocking_dump_suspends_its_moo_task() {
        let (client, threads, started, release, _output) = gated_scheduler();
        let checkpoint_task = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "return dump_database(1);".to_string(),
                None,
                Arc::new(NoopClientSession::new()),
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        started.recv_timeout(Duration::from_secs(1)).unwrap();

        let other_task = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "return 42;".to_string(),
                None,
                Arc::new(NoopClientSession::new()),
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        assert_eq!(wait_for_task(&other_task), Ok(v_int(42)));

        release.send(()).unwrap();
        assert!(wait_for_task(&checkpoint_task).unwrap().is_true());
        client
            .submit_shutdown("blocking dump test complete")
            .unwrap();
        threads.join().unwrap();
    }

    #[test]
    fn blocking_dump_returns_false_when_checkpoint_is_busy() {
        let (client, threads, started, release, _output) = gated_scheduler();
        client.request_checkpoint().unwrap();
        started.recv_timeout(Duration::from_secs(1)).unwrap();

        let duplicate = client
            .submit_eval_task(
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                "return dump_database(1);".to_string(),
                None,
                Arc::new(NoopClientSession::new()),
                Arc::new(FeaturesConfig::default()),
            )
            .unwrap();
        assert!(!wait_for_task(&duplicate).unwrap().is_true());

        release.send(()).unwrap();
        client
            .submit_shutdown("duplicate dump test complete")
            .unwrap();
        threads.join().unwrap();
    }
}
