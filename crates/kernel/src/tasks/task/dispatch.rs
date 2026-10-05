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

//! VM suspension outcomes and immediate transaction renewal.
//! Task workers own execution here and transfer suspended tasks to the scheduler.

use super::Task;
use crate::{
    task_context::TransactionRenewalError,
    tasks::{SchedulerOp, sched_counters, task_scheduler_client::TaskSchedulerClient},
    trace_task_suspend_with_delay,
    vm::TaskSuspend,
};
use moor_common::{
    model::{CommitResult, WorldStateError},
    tasks::Session,
};
use moor_var::{List, v_int};
use tracing::error;

impl Task {
    pub(super) fn dispatch_suspend(
        mut self: Box<Self>,
        delay: TaskSuspend,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> Option<Box<Self>> {
        // Fast path for RecvMessages(None): commit, drain messages, resume immediately
        if matches!(&delay, TaskSuspend::RecvMessages(None)) {
            let perfc = sched_counters();
            let _t = perfc
                .timers
                .start(SchedulerOp::TaskRecvImmediateResumeLatency);
            let renewal = self.renew_transaction(task_scheduler_client, session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            })?;
            match renewal {
                Ok((CommitResult::Success { .. }, _)) => {
                    let messages = task_scheduler_client.task_recv();
                    let resume_value = List::from_iter(messages).into();
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return Some(self);
                }
                Ok((CommitResult::ConflictRetry { conflict_info }, _)) => {
                    self.log_conflict_retry("task_recv immediate resume", conflict_info.as_ref());
                    session.rollback().unwrap();
                    task_scheduler_client.conflict_retry(
                        self,
                        "task_recv immediate resume",
                        conflict_info,
                    );
                    return None;
                }
                Err(TransactionRenewalError::Commit(e)) => {
                    error!("Failed to commit before task_recv: {e:?}");
                    self.reject_commit(task_scheduler_client, e);
                    return None;
                }
                Err(TransactionRenewalError::Begin(e)) => {
                    error!("Failed to begin new transaction for task_recv: {e:?}");
                    task_scheduler_client.abort_transaction_renewal_failed();
                    return None;
                }
            }
        }

        // Check for immediate wake conditions to avoid scheduler round-trip
        let (is_immediate, resume_value) = match &delay {
            TaskSuspend::Commit(val) => (true, val.clone()),
            TaskSuspend::Timed(d) if d.is_zero() => (true, v_int(0)),
            _ => (false, v_int(0)),
        };

        if is_immediate {
            // Fast path: get new transaction and continue immediately
            let renewal = self.renew_transaction(task_scheduler_client, session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            })?;
            match renewal {
                Ok((CommitResult::Success { .. }, _)) => {
                    // Resume first (which resets start_time), then snapshot
                    // so retry_state has fresh timing if we need to restore
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return Some(self);
                }
                Ok((CommitResult::ConflictRetry { conflict_info }, _)) => {
                    self.log_conflict_retry("immediate resume", conflict_info.as_ref());
                    session.rollback().unwrap();
                    task_scheduler_client.conflict_retry(self, "immediate resume", conflict_info);
                    return None;
                }
                Err(TransactionRenewalError::Commit(e)) => {
                    error!("Failed to commit before immediate resume: {e:?}");
                    self.reject_commit(task_scheduler_client, e);
                    return None;
                }
                Err(TransactionRenewalError::Begin(e)) => {
                    error!("Failed to begin new transaction for immediate resume: {e:?}");
                    task_scheduler_client.abort_transaction_renewal_failed();
                    return None;
                }
            }
        }

        // VMHost is now suspended for execution, and we'll be waiting for a Resume
        let commit_result = self.commit_yield_transaction(task_scheduler_client, session)?;

        if let CommitResult::ConflictRetry { conflict_info } = commit_result {
            self.log_conflict_retry("suspend", conflict_info.as_ref());
            session.rollback().unwrap();
            task_scheduler_client.conflict_retry(self, "suspend", conflict_info);
            return None;
        }

        self.refresh_retry_state();
        self.vm_host.stop();

        trace_task_suspend_with_delay!(self.task_id, &delay);

        // Let the scheduler know about our suspension, which can be of the form:
        //      * Indefinite, wake-able only with Resume
        //      * Scheduled, a duration is given, and we'll wake up after that duration
        // In both cases we'll rely on the scheduler to wake us up in its processing loop
        // rather than sleep here, which would make this thread unresponsive to other
        // messages.
        task_scheduler_client.suspend(delay.clone(), self);
        None
    }
}
