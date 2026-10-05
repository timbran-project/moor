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

use crate::{
    task_context::{TaskGuard, rollback_current_transaction},
    tasks::{
        registry::RunningTaskPhase,
        scheduler::test_support::{insert_active_task, scheduler},
        task_scheduler_client::TaskSchedulerClient,
    },
    vm::Fork,
};
use moor_common::tasks::{
    ConnectionDetails, EventLogPurgeResult, EventLogStats, ListenerInfo, NarrativeEvent, Session,
    SessionError, SystemControl, TaskId, WorkerInfo,
};
use moor_var::{
    Error, Obj, SYSTEM_OBJECT, Symbol, Var, program::labels::Offset, v_int, v_obj, v_str,
};
use parking_lot::Mutex;
use std::{
    sync::Arc,
    time::{Duration, SystemTime},
};
use uuid::Uuid;

const TASK: TaskId = 321;

#[derive(Default)]
struct RecordingSession {
    calls: Mutex<Vec<&'static str>>,
    identities: Mutex<Vec<Obj>>,
}

impl Session for RecordingSession {
    fn switch_player_identity(&self, new_player: Obj, _preserve_history: bool) {
        self.identities.lock().push(new_player);
    }

    fn commit(&self) -> Result<(), SessionError> {
        Ok(())
    }
    fn rollback(&self) -> Result<(), SessionError> {
        Ok(())
    }

    fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        self.calls.lock().push("fork");
        Ok(self.clone())
    }

    fn request_input(
        &self,
        player: Obj,
        _input_request_id: Uuid,
        _metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), SessionError> {
        panic!("RecordingSession::request_input called for player {player}")
    }

    fn send_event(&self, _player: Obj, _msg: Box<NarrativeEvent>) -> Result<(), SessionError> {
        Err(SessionError::OutputEventLimitExceeded(1))
    }

    fn log_event(&self, _player: Obj, _event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.calls.lock().push("log");
        Ok(())
    }

    fn send_system_msg(&self, _player: Obj, _msg: &str) -> Result<(), SessionError> {
        Ok(())
    }

    fn notify_shutdown(&self, _msg: Option<String>) -> Result<(), SessionError> {
        Ok(())
    }

    fn connection_name(&self, player: Obj) -> Result<String, SessionError> {
        Ok(format!("player-{player}"))
    }
    fn disconnect(&self, _player: Obj) -> Result<(), SessionError> {
        self.calls.lock().push("disconnect");
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
        Err(SessionError::NoConnectionForPlayer(SYSTEM_OBJECT))
    }

    fn connection_details(
        &self,
        _player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        self.calls.lock().push("connection_details");
        Ok(vec![ConnectionDetails {
            connection_obj: Obj::mk_id(-11),
            peer_addr: String::new(),
            idle_seconds: 0.0,
            acceptable_content_types: vec![],
        }])
    }

    fn connection_attributes(&self, _obj: Obj) -> Result<Var, SessionError> {
        use moor_var::v_list;
        Ok(v_list(&[]))
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

#[derive(Default)]
struct RecordingSystemControl {
    calls: Mutex<Vec<&'static str>>,
    switch_gate: Option<(flume::Sender<()>, flume::Receiver<()>)>,
}

impl SystemControl for RecordingSystemControl {
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
        self.calls.lock().push("listen");
        Ok(())
    }

    fn unlisten(&self, _port: u16, _host_type: &str) -> Result<(), Error> {
        self.calls.lock().push("unlisten");
        Ok(())
    }

    fn listeners(&self) -> Result<Vec<ListenerInfo>, Error> {
        Ok(vec![])
    }

    fn switch_player(
        &self,
        _connection_obj: Obj,
        _new_player: Obj,
        _silent: bool,
        _preserve_history: bool,
    ) -> Result<(), Error> {
        self.calls.lock().push("switch_player");
        if let Some((entered, release)) = &self.switch_gate {
            entered.send(()).unwrap();
            release.recv().unwrap();
        }
        Ok(())
    }

    fn rotate_enrollment_token(&self) -> Result<String, Error> {
        Ok(String::new())
    }

    fn player_event_log_stats(
        &self,
        _player: Obj,
        _since: Option<SystemTime>,
        _until: Option<SystemTime>,
    ) -> Result<EventLogStats, Error> {
        Ok(EventLogStats::default())
    }

    fn purge_player_event_log(
        &self,
        _player: Obj,
        _before: Option<SystemTime>,
        _drop_pubkey: bool,
    ) -> Result<EventLogPurgeResult, Error> {
        Ok(EventLogPurgeResult::default())
    }

    fn workers_info(&self) -> Result<Vec<WorkerInfo>, Error> {
        Ok(vec![])
    }
}

fn event() -> Box<NarrativeEvent> {
    Box::new(NarrativeEvent::notify(
        v_obj(SYSTEM_OBJECT),
        v_str("event"),
        None,
        false,
        false,
        None,
    ))
}

fn fork() -> Box<Fork> {
    Box::new(Fork {
        player: SYSTEM_OBJECT,
        progr: SYSTEM_OBJECT,
        parent_task_id: TASK,
        delay: Some(Duration::from_secs(60)),
        activation: moor_vm::Activation::for_eval(
            SYSTEM_OBJECT,
            Default::default(),
            &SYSTEM_OBJECT,
            Default::default(),
            None,
        ),
        fork_vector_offset: Offset(0),
        task_id: None,
    })
}

fn stale_operations() -> [fn(&TaskSchedulerClient); 7] {
    [
        |client| client.log_event(SYSTEM_OBJECT, event()),
        |client| client.boot_player(SYSTEM_OBJECT),
        |client| assert!(client.force_input(SYSTEM_OBJECT, "look".into()).is_err()),
        |client| assert_eq!(client.request_fork(fork()), 0),
        |client| {
            assert!(
                client
                    .listen(SYSTEM_OBJECT, "tcp".into(), 8888, vec![])
                    .is_some()
            )
        },
        |client| assert!(client.unlisten("tcp".into(), 8888).is_some()),
        |client| {
            assert!(
                client
                    .switch_player(None, Obj::mk_id(99), false, false)
                    .is_err()
            )
        },
    ]
}

#[test]
fn stale_session_requests_cannot_use_replacement_sessions_or_hosts() {
    for bound in [true, false] {
        for operation in stale_operations() {
            let mut scheduler = scheduler();
            let system = Arc::new(RecordingSystemControl::default());
            scheduler.system_control = system.clone();
            if bound {
                insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
            }
            let old = TaskSchedulerClient::new(TASK, scheduler.clone());
            let replacement = Arc::new(RecordingSession::default());
            insert_active_task(&scheduler, TASK, replacement.clone());
            let next_id = scheduler.lifecycle.lock().next_task_id;
            operation(&old);
            assert!(replacement.calls.lock().is_empty());
            assert!(replacement.identities.lock().is_empty());
            assert!(system.calls.lock().is_empty());
            assert_eq!(scheduler.lifecycle.lock().next_task_id, next_id);
        }
    }
}

#[test]
fn finalizing_dispatch_cannot_start_new_session_operations() {
    for phase in [
        RunningTaskPhase::Completing(Ok(v_int(0))),
        RunningTaskPhase::Suspending,
        RunningTaskPhase::RequestingInput,
    ] {
        let mut scheduler = scheduler();
        let system = Arc::new(RecordingSystemControl::default());
        scheduler.system_control = system.clone();
        let session = Arc::new(RecordingSession::default());
        insert_active_task(&scheduler, TASK, session.clone());
        let client = TaskSchedulerClient::new(TASK, scheduler.clone());
        scheduler
            .lifecycle
            .lock()
            .task_q
            .active
            .get_mut(&TASK)
            .unwrap()
            .phase = phase;
        for operation in stale_operations() {
            operation(&client);
        }
        assert!(session.calls.lock().is_empty());
        assert!(system.calls.lock().is_empty());
    }
}

#[test]
fn notification_error_cannot_cancel_a_replacement_dispatch() {
    let scheduler = scheduler();
    let session = Arc::new(RecordingSession::default());
    insert_active_task(&scheduler, TASK, session.clone());
    let client = TaskSchedulerClient::new(TASK, scheduler.clone());
    let replacement = insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let guard = TaskGuard::new(
        scheduler.database.new_world_state().unwrap(),
        client.clone(),
        TASK,
        SYSTEM_OBJECT,
        session,
    );
    client.notify(SYSTEM_OBJECT, event());
    rollback_current_transaction().unwrap();
    drop(guard);
    let lc = scheduler.lifecycle.lock();
    assert!(lc.task_q.active[&TASK].abort_error.is_none());
    assert!(!replacement.control.is_cancelled());
}

#[test]
fn player_switch_rechecks_dispatch_after_host_io() {
    let mut scheduler = scheduler();
    let (entered_send, entered_recv) = flume::bounded(1);
    let (release_send, release_recv) = flume::bounded(1);
    scheduler.system_control = Arc::new(RecordingSystemControl {
        switch_gate: Some((entered_send, release_recv)),
        ..Default::default()
    });
    insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let client = TaskSchedulerClient::new(TASK, scheduler.clone());
    let worker =
        std::thread::spawn(move || client.switch_player(None, Obj::mk_id(99), false, false));
    entered_recv.recv_timeout(Duration::from_secs(5)).unwrap();
    let replacement = Arc::new(RecordingSession::default());
    insert_active_task(&scheduler, TASK, replacement.clone());
    release_send.send(()).unwrap();
    // Host success remains success, but it cannot rewrite the replacement's metadata or session.
    assert!(worker.join().unwrap().is_ok());
    assert_eq!(
        scheduler.lifecycle.lock().task_q.active[&TASK].player,
        SYSTEM_OBJECT
    );
    assert!(replacement.identities.lock().is_empty());
}

#[test]
fn current_player_switch_updates_its_session_after_host_success() {
    let mut scheduler = scheduler();
    let system = Arc::new(RecordingSystemControl::default());
    scheduler.system_control = system.clone();
    let session = Arc::new(RecordingSession::default());
    insert_active_task(&scheduler, TASK, session.clone());
    let client = TaskSchedulerClient::new(TASK, scheduler.clone());
    let new_player = Obj::mk_id(99);
    client.switch_player(None, new_player, false, true).unwrap();
    assert_eq!(
        scheduler.lifecycle.lock().task_q.active[&TASK].player,
        new_player
    );
    assert_eq!(*session.identities.lock(), vec![new_player]);
    assert_eq!(*system.calls.lock(), vec!["switch_player"]);
}

#[test]
fn stale_kill_cannot_cancel_replacement_dispatch() {
    let scheduler = scheduler();
    insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let old = TaskSchedulerClient::new(TASK, scheduler.clone());
    let replacement = insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let result = old.kill_task(
        TASK,
        moor_common::model::TaskPermissions::new(SYSTEM_OBJECT, Default::default()),
    );
    assert_eq!(result, moor_var::v_err(moor_var::E_INVARG));
    assert!(!replacement.control.is_cancelled());
    assert!(scheduler.lifecycle.lock().task_q.active.contains_key(&TASK));
}

#[test]
fn stale_resume_cannot_consume_another_tasks_continuation() {
    let scheduler = scheduler();
    insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let old = TaskSchedulerClient::new(TASK, scheduler.clone());
    insert_active_task(&scheduler, TASK, Arc::new(RecordingSession::default()));
    let target = TASK + 1;
    let suspended = crate::tasks::scheduler::test_support::suspended_task(target);
    {
        let mut lc = scheduler.lifecycle.lock();
        let registration = lc.task_q.register_task(target);
        lc.task_q.suspended.add_task(
            suspended.wake_condition,
            suspended.task,
            suspended.session,
            None,
            registration,
        );
    }
    let result = old.resume_task(
        target,
        moor_common::model::TaskPermissions::new(SYSTEM_OBJECT, Default::default()),
        v_int(7),
    );
    assert_eq!(result, moor_var::v_err(moor_var::E_INVARG));
    assert!(
        scheduler
            .lifecycle
            .lock()
            .task_q
            .suspended
            .get(target)
            .is_some()
    );
}
