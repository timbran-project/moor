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
use crate::tasks::{AbortTaskOutcome, TaskNotification, registry::RunningTaskPhase};
use moor_common::tasks::{
    CommandError, NarrativeEvent, NoopClientSession,
    SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
    Session,
};
use moor_var::{E_QUOTA, List, SYSTEM_OBJECT, Symbol, v_int, v_obj, v_str};
use std::sync::Barrier;

use crate::tasks::scheduler::test_support::*;

#[test]
fn task_existence_does_not_wait_for_lifecycle_lock() {
    let scheduler = scheduler();
    let task_id = 45;
    insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));

    let lifecycle = scheduler.lifecycle.lock();
    let lookup_scheduler = scheduler.clone();
    let (result_send, result_recv) = flume::bounded(1);
    let lookup = std::thread::spawn(move || {
        result_send
            .send(lookup_scheduler.handle_task_exists(task_id))
            .unwrap();
    });

    assert_eq!(
        result_recv.recv_timeout(Duration::from_millis(100)),
        Ok(true),
        "task membership lookup must not acquire the lifecycle lock"
    );
    drop(lifecycle);
    lookup.join().expect("task lookup should complete");
}

#[test]
fn terminal_task_result_removes_live_membership() {
    let scheduler = scheduler();
    let task_id = 46;
    insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
    assert!(scheduler.handle_task_exists(task_id));

    scheduler
        .lifecycle
        .lock()
        .task_q
        .send_task_result(task_id, Ok(v_int(0)));

    assert!(!scheduler.handle_task_exists(task_id));
}

#[test]
fn rejected_commit_rolls_back_session_effects() {
    let scheduler = scheduler();
    let task_id = 147;
    let session = Arc::new(moor_common::tasks::MockClientSession::new());
    session
        .send_event(
            SYSTEM_OBJECT,
            Box::new(NarrativeEvent::notify(
                v_obj(SYSTEM_OBJECT),
                v_str("must be discarded"),
                None,
                false,
                false,
                None,
            )),
        )
        .unwrap();
    insert_active_task(&scheduler, task_id, session.clone());

    scheduler.handle_task_commit_rejected(
        task_id,
        Box::new(moor_common::tasks::Exception {
            error: E_QUOTA.with_msg(|| "database writer overloaded".to_string()),
            stack: Vec::new(),
            backtrace: Vec::new(),
        }),
    );

    assert!(session.received().is_empty());
    assert!(session.committed().is_empty());
    assert!(!scheduler.handle_task_exists(task_id));
}

#[test]
fn removed_attempt_cannot_publish_effects_through_replacement() {
    use crate::tasks::schedule_q::{PendingKind, ScheduleKind, ScheduleOptions};
    let scheduler = scheduler();
    let task_id = 245;
    let target_id = 246;
    let session = Arc::new(NoopClientSession::new());
    insert_active_task(&scheduler, task_id, session.clone());
    let interval = Duration::from_secs(60);
    let schedule_id = scheduler
        .handle_schedule_create(
            task_id,
            PendingKind::Every(interval),
            SYSTEM_OBJECT,
            Symbol::mk("tick"),
            List::mk_list(&[]),
            SYSTEM_OBJECT,
            SYSTEM_OBJECT,
            ScheduleOptions::for_kind(&ScheduleKind::Every { interval }),
        )
        .unwrap();
    assert!(scheduler.handle_schedule_valid(task_id, schedule_id));
    {
        let mut lc = scheduler.lifecycle.lock();
        lc.task_q
            .active
            .get_mut(&task_id)
            .unwrap()
            .effects
            .send(target_id, v_int(17));
        assert!(matches!(
            lc.task_q.abort_task(task_id),
            AbortTaskOutcome::Cancelled
        ));
    }
    insert_active_task(&scheduler, task_id, session);
    assert!(!scheduler.handle_schedule_valid(task_id, schedule_id));
    let mut lc = scheduler.lifecycle.lock();
    lc.publish_task_effects(task_id);
    assert!(lc.task_q.drain_messages(target_id).is_empty());
    assert!(!lc.schedule_q.is_valid(schedule_id));
}

#[test]
fn stale_worker_client_cannot_complete_replacement_attempt() {
    use crate::tasks::task_scheduler_client::TaskSchedulerClient;
    use moor_common::tasks::Exception;

    fn exception() -> Box<Exception> {
        Box::new(Exception {
            error: E_QUOTA.msg("old attempt"),
            stack: vec![],
            backtrace: vec![],
        })
    }
    let callbacks: [fn(&TaskSchedulerClient); 9] = [
        |client| client.success(v_int(1), true, 99),
        |client| client.command_error(CommandError::NoCommandMatch),
        |client| client.verb_not_found(v_int(0), Symbol::mk("old")),
        |client| client.exception(exception()),
        |client| client.commit_rejected(exception()),
        |client| client.abort_transaction_renewal_failed(),
        |client| client.abort_cancelled(),
        |client| client.abort_panicked("old panic".into(), std::backtrace::Backtrace::disabled()),
        |client| {
            client.abort_limits_reached(crate::tasks::task_scheduler_client::TaskLimitInfo {
                reason: moor_common::tasks::AbortLimitReason::Ticks(1),
                disposition: crate::tasks::task_scheduler_client::TaskLimitDisposition::Commit {
                    mutations_made: true,
                    timestamp: 99,
                },
                this: v_int(0),
                verb_name: Symbol::mk("old"),
                line_number: 0,
                stack: vec![],
                backtrace: vec![],
            })
        },
    ];
    for callback in callbacks {
        let scheduler = scheduler();
        let task_id = 249;
        let target_id = 250;
        insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        let old_client = TaskSchedulerClient::new(task_id, scheduler.clone());
        let replacement =
            insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
        let (send, recv) = flume::unbounded();
        {
            let mut lc = scheduler.lifecycle.lock();
            lc.state = SchedulerState::Running;
            lc.task_q.deliver_message(task_id, v_int(42));
            let active = lc.task_q.active.get_mut(&task_id).unwrap();
            active.result_sender = Some(send);
            active.effects.send(target_id, v_int(17));
            active.abort_error = Some(SchedulerError::CouldNotStartTask);
        }

        callback(&old_client);

        let mut lc = scheduler.lifecycle.lock();
        let active = lc
            .task_q
            .active
            .get(&task_id)
            .expect("replacement must remain active");
        assert!(Arc::ptr_eq(&active.control, &replacement.control));
        assert_eq!(active.phase, RunningTaskPhase::Running);
        assert_eq!(active.effects.messages_for(target_id), 1);
        assert_eq!(active.abort_error, Some(SchedulerError::CouldNotStartTask));
        assert_eq!(lc.task_q.mailbox_len(task_id), 1);
        assert!(lc.task_q.drain_messages(target_id).is_empty());
        assert!(lc.task_q.settled_results.is_empty());
        assert!(lc.last_mutation_timestamp.is_none());
        assert!(matches!(recv.try_recv(), Err(flume::TryRecvError::Empty)));
    }
}

#[test]
fn session_finalization_cannot_settle_a_replacement_attempt() {
    use crate::tasks::task_scheduler_client::TaskSchedulerClient;
    let callbacks: [fn(&TaskSchedulerClient); 3] = [
        |client| {
            client.exception(Box::new(moor_common::tasks::Exception {
                error: E_QUOTA.msg("old exception"),
                stack: vec![],
                backtrace: vec![],
            }))
        },
        |client| client.abort_transaction_renewal_failed(),
        |client| client.abort_cancelled(),
    ];
    for callback in callbacks {
        for fail_commit in [false, true] {
            let scheduler = scheduler();
            let task_id = 252;
            let target_id = 253;
            let commit_entered = Arc::new(Barrier::new(2));
            let release_commit = Arc::new(Barrier::new(2));
            insert_active_task(
                &scheduler,
                task_id,
                Arc::new(BlockingCommitSession {
                    commit_entered: commit_entered.clone(),
                    release_commit: release_commit.clone(),
                    connection_obj: None,
                    source_connections: None,
                    fail_commit,
                }),
            );
            scheduler.lifecycle.lock().state = SchedulerState::Running;
            let old_client = TaskSchedulerClient::new(task_id, scheduler.clone());
            let worker = std::thread::spawn(move || callback(&old_client));
            commit_entered.wait();
            let reserved = {
                let lc = scheduler.lifecycle.lock();
                matches!(
                    lc.task_q.active.get(&task_id).unwrap().phase,
                    RunningTaskPhase::Completing(_)
                )
            };
            let abort_outcome = scheduler.handle_abort_task(task_id);
            let replacement =
                insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
            let (send, recv) = flume::unbounded();
            {
                let mut lc = scheduler.lifecycle.lock();
                lc.task_q.deliver_message(task_id, v_int(42));
                let active = lc.task_q.active.get_mut(&task_id).unwrap();
                active.result_sender = Some(send);
                active.effects.send(target_id, v_int(17));
            }
            release_commit.wait();
            worker.join().unwrap();
            assert!(
                reserved,
                "session finalization must reserve its terminal result"
            );
            assert!(matches!(abort_outcome, AbortTaskOutcome::Completing));
            let mut lc = scheduler.lifecycle.lock();
            let active = lc
                .task_q
                .active
                .get(&task_id)
                .expect("replacement must remain active");
            assert!(Arc::ptr_eq(&active.control, &replacement.control));
            assert_eq!(active.phase, RunningTaskPhase::Running);
            assert_eq!(active.effects.messages_for(target_id), 1);
            assert_eq!(lc.task_q.mailbox_len(task_id), 1);
            assert!(lc.task_q.drain_messages(target_id).is_empty());
            assert!(lc.task_q.settled_results.is_empty());
            assert!(matches!(recv.try_recv(), Err(flume::TryRecvError::Empty)));
        }
    }
}

#[test]
fn finalization_preserves_effect_and_error_policies() {
    use crate::tasks::task_scheduler_client::TaskSchedulerClient;
    use moor_common::tasks::SchedulerError::{CouldNotStartTask, TaskAbortedException};
    for kind in ["exception", "renewal", "cancellation"] {
        for fail_commit in [false, true] {
            let scheduler = scheduler();
            let task_id = 254;
            let target_id = 255;
            let commit_entered = Arc::new(Barrier::new(2));
            let release_commit = Arc::new(Barrier::new(2));
            insert_active_task(
                &scheduler,
                task_id,
                Arc::new(BlockingCommitSession {
                    commit_entered: commit_entered.clone(),
                    release_commit: release_commit.clone(),
                    connection_obj: None,
                    source_connections: None,
                    fail_commit,
                }),
            );
            let (send, recv) = flume::unbounded();
            {
                let mut lc = scheduler.lifecycle.lock();
                lc.state = SchedulerState::Running;
                lc.task_q.deliver_message(task_id, v_int(42));
                let active = lc.task_q.active.get_mut(&task_id).unwrap();
                active.result_sender = Some(send);
                active.effects.send(target_id, v_int(17));
            }
            let client = TaskSchedulerClient::new(task_id, scheduler.clone());
            let worker = std::thread::spawn(move || match kind {
                "exception" => client.exception(Box::new(moor_common::tasks::Exception {
                    error: E_QUOTA.msg("failure"),
                    stack: vec![],
                    backtrace: vec![],
                })),
                "renewal" => client.abort_transaction_renewal_failed(),
                "cancellation" => client.abort_cancelled(),
                _ => unreachable!(),
            });
            commit_entered.wait();
            let unpublished = scheduler.lifecycle.lock().task_q.mailbox_len(target_id) == 0;
            release_commit.wait();
            worker.join().unwrap();
            assert!(unpublished);
            let mut lc = scheduler.lifecycle.lock();
            let messages = lc.task_q.drain_messages(target_id);
            if kind == "cancellation" {
                assert!(messages.is_empty());
            } else {
                assert_eq!(messages, vec![v_int(17)]);
            }
            assert!(!scheduler.handle_task_exists(task_id));
            assert_eq!(lc.task_q.mailbox_len(task_id), 0);
            let (id, result) = recv.try_recv().unwrap();
            assert_eq!(id, task_id);
            assert!(matches!(
                (kind, fail_commit, result),
                ("exception", _, Err(TaskAbortedException(_)))
                    | ("renewal", false, Err(CouldNotStartTask))
                    | ("cancellation", false, Err(TaskAbortedCancelled))
                    | ("renewal" | "cancellation", true, Err(TaskAbortedError))
            ));
            assert!(matches!(
                recv.try_recv(),
                Err(flume::TryRecvError::Disconnected)
            ));
        }
    }
}

#[test]
fn reserved_completion_rejects_duplicate_callbacks() {
    use crate::tasks::task_scheduler_client::TaskSchedulerClient;
    let scheduler = scheduler();
    let task_id = 256;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    insert_active_task(
        &scheduler,
        task_id,
        Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
            fail_commit: false,
        }),
    );
    let (send, recv) = flume::unbounded();
    scheduler
        .lifecycle
        .lock()
        .task_q
        .active
        .get_mut(&task_id)
        .unwrap()
        .result_sender = Some(send);
    let client = TaskSchedulerClient::new(task_id, scheduler.clone());
    let worker_client = client.clone();
    let worker = std::thread::spawn(move || worker_client.success(v_int(17), false, 0));
    commit_entered.wait();
    client.command_error(CommandError::NoCommandMatch);
    client.verb_not_found(v_int(0), Symbol::mk("duplicate"));
    client.success(v_int(99), true, 99);
    client.abort_cancelled();
    client.abort_transaction_renewal_failed();
    let still_pending = matches!(recv.try_recv(), Err(flume::TryRecvError::Empty));
    release_commit.wait();
    worker.join().unwrap();
    assert!(still_pending);
    assert!(
        matches!(recv.try_recv(), Ok((256, Ok(TaskNotification::Result(value)))) if value == v_int(17))
    );
    assert!(scheduler.lifecycle.lock().last_mutation_timestamp.is_none());
    assert!(matches!(
        recv.try_recv(),
        Err(flume::TryRecvError::Disconnected)
    ));
}

#[test]
fn stale_terminal_completion_preserves_replacement_result_and_effects() {
    let scheduler = scheduler();
    let task_id = 247;
    let target_id = 248;
    let commit_entered = Arc::new(Barrier::new(2));
    let release_commit = Arc::new(Barrier::new(2));
    let task = insert_active_task(
        &scheduler,
        task_id,
        Arc::new(BlockingCommitSession {
            commit_entered: commit_entered.clone(),
            release_commit: release_commit.clone(),
            connection_obj: None,
            source_connections: None,
            fail_commit: false,
        }),
    );
    assert!(task.control.claim_terminal().unwrap().committed());
    let callback_scheduler = scheduler.clone();
    let callback = std::thread::spawn(move || {
        callback_scheduler.handle_task_success(task_id, v_int(1), false, 0);
    });
    commit_entered.wait();
    let replacement = insert_active_task(&scheduler, task_id, Arc::new(NoopClientSession::new()));
    let (send, recv) = flume::unbounded();
    {
        let mut lc = scheduler.lifecycle.lock();
        let active = lc.task_q.active.get_mut(&task_id).unwrap();
        active.result_sender = Some(send);
        active.effects.send(target_id, v_int(17));
    }
    release_commit.wait();
    callback.join().unwrap();
    let mut lc = scheduler.lifecycle.lock();
    let active = lc.task_q.active.get(&task_id).unwrap();
    assert!(Arc::ptr_eq(&active.control, &replacement.control));
    assert_eq!(active.phase, RunningTaskPhase::Running);
    assert_eq!(active.effects.messages_for(target_id), 1);
    assert!(lc.task_q.drain_messages(target_id).is_empty());
    assert!(recv.try_recv().is_err());
}
