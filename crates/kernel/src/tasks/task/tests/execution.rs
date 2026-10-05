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
    assert!(matches!(err, SchedulerError::TaskAbortedCancelled));
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
