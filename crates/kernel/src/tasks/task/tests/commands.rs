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
