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
    assert_eq!(err, TaskOutcome::aborted(AbortReason::Killed, Kept::Yes));
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
        TaskOutcome {
            kept: Kept::Yes,
            ending: TaskEnding::Aborted(AbortReason::Exception(ex)),
        } => {
            assert_eq!(ex.error.err_type(), E_DIV);
        }
        other => panic!("Expected an uncaught exception, got {other:?}"),
    }
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

/// Run `code` as an eval with symbols and booleans enabled; return its result and the
/// events it committed.
fn eval_capturing(
    code: &str,
) -> (
    Result<Var, TaskOutcome>,
    Vec<moor_common::tasks::NarrativeEvent>,
) {
    let (client, _sched) = setup_scheduler(&[]);
    let session = Arc::new(MockClientSession::new());
    let features = FeaturesConfig {
        symbol_type: true,
        bool_type: true,
        ..Default::default()
    };
    let handle = client
        .submit_eval_task(
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            code.to_string(),
            None,
            session.clone(),
            Arc::new(features),
        )
        .unwrap();
    let result = wait_result(&handle);
    (result, session.committed())
}

fn aborted_with(result: Result<Var, TaskOutcome>) -> moor_var::ErrorCode {
    match result {
        Err(TaskOutcome {
            kept: Kept::Yes,
            ending: TaskEnding::Aborted(AbortReason::Exception(ex)),
        }) => ex.error.err_type(),
        other => panic!("expected an aborted task, got {other:?}"),
    }
}

/// emit_data() sends one event per recipient, flagged ephemeral only when asked.
#[test]
fn test_emit_data_recipients_and_ephemeral_option() {
    let (result, events) = eval_capturing(
        "emit_data({#0, #0}, 'game, 'positions, 1, ['ephemeral -> true]); \
         emit_data(#0, 'state, 'room, 2, ['ephemeral -> false]); \
         emit_data(#0, 'state, 'room, 3); return 1;",
    );
    assert_eq!(result, Ok(v_int(1)));
    let flags: Vec<bool> = events.iter().map(|event| event.is_ephemeral()).collect();
    assert_eq!(flags, vec![true, true, false, false]);
}

/// emit_data() rejects unknown options, non-boolean flags, and non-object recipients.
#[test]
fn test_emit_data_rejects_bad_arguments() {
    use moor_var::{E_INVARG, E_TYPE};
    for (code, error) in [
        ("emit_data(#0, 'a, 'b, 1, ['loud -> true]);", E_INVARG),
        ("emit_data(#0, 'a, 'b, 1, ['ephemeral -> 1]);", E_TYPE),
        ("emit_data({#0, 1}, 'a, 'b, 1);", E_TYPE),
        ("emit_data(\"#0\", 'a, 'b, 1);", E_TYPE),
    ] {
        let (result, events) = eval_capturing(code);
        assert_eq!(aborted_with(result), error, "{code}");
        let emitted = events
            .iter()
            .any(|event| matches!(event.event, moor_common::tasks::Event::Data { .. }));
        assert!(!emitted, "{code} emitted data");
    }
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

/// listen() uses its `kind` option to choose the hosts, and does not pass it on to them;
/// unlisten() takes the kind as its second argument; listeners() reports each kind.
#[test]
fn test_listen_unlisten_and_listeners_name_kinds() {
    let system = Arc::new(MockClientSession::new());
    let (client, _sched) =
        start_scheduler_with_system(Box::new(setup_database(&[])), system.clone());
    let handle = client
        .submit_eval_task(
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            "listen(#0, 7000, [\"kind\" -> \"minecraft\", \"tls\" -> 0]); \
             listen(#0, 7001); unlisten(7000, \"minecraft\"); unlisten(7001); \
             return {`listen(#0, 7002, [\"kind\" -> 5]) ! ANY', listeners()};"
                .to_string(),
            None,
            Arc::new(NoopClientSession::new()),
            Arc::new(FeaturesConfig::default()),
        )
        .unwrap();
    let result = wait_result(&handle).unwrap();
    let error = result
        .index(&v_int(1), moor_var::IndexMode::OneBased)
        .unwrap();
    assert_eq!(
        error.as_error().map(|e| e.err_type()),
        Some(moor_var::E_TYPE)
    );
    let listeners = result
        .index(&v_int(2), moor_var::IndexMode::OneBased)
        .unwrap();
    assert_eq!(
        listeners,
        moor_var::v_list(&[moor_var::v_list(&[
            v_obj(SYSTEM_OBJECT),
            v_int(8888),
            moor_var::v_map(&[]),
            v_str("telnet"),
        ])])
    );
    assert_eq!(
        system.system(),
        vec![
            "listen: minecraft 7000 [\"tls\"]",
            "listen: telnet 7001 []",
            "unlisten: minecraft 7000",
            "unlisten: telnet 7001",
        ]
    );
}
