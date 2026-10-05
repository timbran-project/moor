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
