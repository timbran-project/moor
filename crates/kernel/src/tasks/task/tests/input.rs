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
