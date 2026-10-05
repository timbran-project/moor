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
