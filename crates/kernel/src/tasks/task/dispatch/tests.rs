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

use super::*;
use crate::{
    config::Config,
    task_context::TaskGuard,
    tasks::{
        NoopTasksDb, TaskNotification,
        registry::{RunningTask, RunningTaskPhase},
        scheduler::Scheduler,
        task_control::TaskControl,
    },
};
use moor_common::{
    model::{ObjFlag, ObjectKind, TaskPermissions, VerbArgsSpec, VerbFlag, WorldStateSource},
    tasks::{CommandError, NoopClientSession, NoopSystemControl, SchedulerError, TaskId},
    util::{BitEnum, Instant},
};
use moor_compiler::{CompileOptions, compile};
use moor_db::{DatabaseConfig, TxDB};
use moor_var::{E_DIV, NOTHING, Symbol, program::ProgramType};
use std::sync::{Arc, OnceLock};

const TASK_ID: TaskId = 71;

struct DispatchTest {
    _guard: TaskGuard,
    scheduler: Scheduler,
    task: Box<Task>,
    client: TaskSchedulerClient,
    session: Arc<dyn Session>,
    results: flume::Receiver<(TaskId, Result<TaskNotification, SchedulerError>)>,
}

fn dispatch_test(unreadable_handler: bool) -> DispatchTest {
    let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
    let permissions = TaskPermissions::new(SYSTEM_OBJECT, ObjFlag::all_flags());
    let mut world = db.new_world_state().unwrap();
    world
        .create_object(
            &permissions,
            &NOTHING,
            &SYSTEM_OBJECT,
            ObjFlag::all_flags(),
            ObjectKind::NextObjid,
        )
        .unwrap();
    let player = if unreadable_handler {
        let player = world
            .create_object(
                &permissions,
                &NOTHING,
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        world
            .add_verb(
                &permissions,
                &SYSTEM_OBJECT,
                vec![Symbol::mk("handle_uncaught_error")],
                &SYSTEM_OBJECT,
                BitEnum::new_with(VerbFlag::Exec),
                VerbArgsSpec::this_none_this(),
                ProgramType::MooR(compile("return 0;", CompileOptions::default()).unwrap()),
            )
            .unwrap();
        player
    } else {
        SYSTEM_OBJECT
    };
    world.commit().unwrap();

    let scheduler = Scheduler::new(
        semver::Version::new(0, 0, 0),
        Box::new(db),
        Box::new(NoopTasksDb {}),
        Arc::new(Config::default()),
        Arc::new(NoopSystemControl::default()),
        None,
        None,
    );
    let control = Arc::new(TaskControl::new());
    let task_start = TaskStart::StartEval {
        player,
        program: Default::default(),
        initial_env: None,
    };
    let mut task = Task::new(
        TASK_ID,
        player,
        player,
        task_start.clone(),
        scheduler.server_options.load().as_ref(),
        control.clone(),
    );
    let session: Arc<dyn Session> = Arc::new(NoopClientSession::new());
    let (sender, results) = flume::unbounded();
    {
        let mut lc = scheduler.lifecycle.lock();
        let registration = lc.task_q.register_task(TASK_ID);
        lc.task_q.insert_active(
            TASK_ID,
            RunningTask {
                registration,
                effects: Default::default(),
                phase: RunningTaskPhase::Running,
                player,
                task_start,
                dispatched_at: Instant::now(),
                run_baseline: Arc::new(OnceLock::new()),
                abort_error: None,
                control,
                session: session.clone(),
                result_sender: Some(sender),
            },
        );
    }
    let client = TaskSchedulerClient::new(TASK_ID, scheduler.clone());
    let guard = TaskGuard::new(
        scheduler.database.new_world_state().unwrap(),
        client.clone(),
        TASK_ID,
        player,
        session.clone(),
    );
    task.refresh_authority_principal_flags();
    DispatchTest {
        _guard: guard,
        scheduler,
        task,
        client,
        session,
        results,
    }
}

fn assert_command_failure(
    scheduler: &Scheduler,
    results: &flume::Receiver<(TaskId, Result<TaskNotification, SchedulerError>)>,
) -> CommandError {
    let (_, result) = results
        .try_recv()
        .expect("dispatch error must settle the task");
    let Err(SchedulerError::CommandExecutionError(error)) = result else {
        panic!("expected command error, got {result:?}");
    };
    assert!(!scheduler.handle_task_exists(TASK_ID));
    assert!(
        !scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .contains_key(&TASK_ID)
    );
    assert!(results.try_recv().is_err(), "completion must occur once");
    error
}

#[test]
fn failed_command_fallback_does_not_return_continuation() {
    let mut test = dispatch_test(false);
    test.task.state = TaskState::Prepared(TaskStart::StartDoCommand {
        handler_object: SYSTEM_OBJECT,
        player: SYSTEM_OBJECT,
        command: "missing-command".to_string(),
    });
    let next = test
        .task
        .dispatch_success(v_int(0), &test.client, test.session.as_ref());
    assert!(
        next.is_none(),
        "a completed command error cannot continue execution"
    );
    assert!(matches!(
        assert_command_failure(&test.scheduler, &test.results),
        CommandError::NoCommandMatch
    ));
}

#[test]
fn missing_pending_exception_settles_the_task() {
    let mut test = dispatch_test(false);
    test.task.handling_uncaught_error = true;
    test.task.pending_exception = None;
    assert!(
        test.task
            .dispatch_success(v_int(0), &test.client, test.session.as_ref())
            .is_none()
    );
    assert!(matches!(
        test.results.try_recv().unwrap().1,
        Err(SchedulerError::TaskAbortedCancelled)
    ));
    assert!(!test.scheduler.handle_task_exists(TASK_ID));
    assert!(
        !test
            .scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .contains_key(&TASK_ID)
    );
    assert!(test.results.try_recv().is_err());
}

#[test]
fn unreadable_exception_handler_settles_the_task() {
    let test = dispatch_test(true);
    let exception = Box::new(Exception {
        error: E_DIV.into(),
        stack: vec![],
        backtrace: vec![],
    });
    assert!(
        test.task
            .dispatch_exception(exception, &test.client, test.session.as_ref())
            .is_none()
    );
    assert!(matches!(
        assert_command_failure(&test.scheduler, &test.results),
        CommandError::DatabaseError(WorldStateError::VerbPermissionDenied)
    ));
}
