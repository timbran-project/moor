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

use crate::tasks::scheduler::*;
use moor_var::{E_INVARG, Obj, SYSTEM_OBJECT, Symbol};
use std::sync::Barrier;
use std::time::SystemTime;

use crate::tasks::scheduler::test_support::*;

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
        .handle_switch_player_from_task(task_id, Some(Obj::mk_id(7)), Obj::mk_id(100), false, false)
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
