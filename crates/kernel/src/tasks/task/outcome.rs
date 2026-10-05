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

//! Owned decisions returned by VM operation handlers.
//!
//! The worker loop consumes each request once using its dispatch-bound scheduler client.
//! Terminal requests retain the executable task through the callback for panic diagnostics.
//! Dropping a request never publishes effects or acquires the lifecycle lock. A suspension's
//! committed boundary retains its existing cancellation-on-abandonment contract.

use super::{Task, transaction::CommitFailure};
use crate::{
    tasks::{
        TaskStart,
        task_control::CommittedBoundary,
        task_scheduler_client::{TaskLimitInfo, TaskSchedulerClient},
    },
    vm::{TaskInputRequest, TaskSuspend},
};
use moor_common::{
    model::{ConflictInfo, WorldStateError},
    tasks::{CommandError, Exception, SchedulerError, Session},
};
use moor_var::{E_EXEC, Var};

#[must_use]
pub(super) enum ExecutionOutcome {
    Continue(Box<Task>),
    Retry(RetryRequest),
    Suspend(SuspensionRequest),
    Finish(TerminalRequest),
}

#[must_use]
pub(super) struct RetryRequest {
    task: Box<Task>,
    boundary: &'static str,
    conflict_info: Option<ConflictInfo>,
}

impl RetryRequest {
    pub(super) fn handoff(self, client: &TaskSchedulerClient) {
        client.conflict_retry(self.task, self.boundary, self.conflict_info);
    }
}

pub(super) enum SuspensionKind {
    Wait(TaskSuspend),
    Input(TaskInputRequest),
}

#[must_use]
pub(super) struct SuspensionRequest {
    task: Box<Task>,
    boundary: CommittedBoundary,
    kind: SuspensionKind,
}

impl SuspensionRequest {
    pub(super) fn handoff(self, client: &TaskSchedulerClient) {
        let task = self.task.with_committed_boundary(self.boundary);
        match self.kind {
            SuspensionKind::Wait(delay) => client.suspend(delay, task),
            SuspensionKind::Input(input) => {
                client.request_input(task, input.player, input.metadata);
            }
        }
    }
}

/// These outcomes deliberately retain different session and effect policies in the scheduler.
pub(super) enum TerminalCompletion {
    Success {
        value: Var,
        mutations_made: bool,
        timestamp: u64,
    },
    Exception(Box<Exception>),
    CommitRejected(Box<Exception>),
    CommandError(CommandError),
    Cancelled,
    RenewalFailed,
    Limit(TaskLimitInfo),
}

#[must_use]
pub(super) struct TerminalRequest {
    task: Box<Task>,
    completion: TerminalCompletion,
}

impl TerminalRequest {
    pub(super) fn finish(self, client: &TaskSchedulerClient) {
        match self.completion {
            TerminalCompletion::Success {
                value,
                mutations_made,
                timestamp,
            } => {
                client.success(value, mutations_made, timestamp);
            }
            TerminalCompletion::Exception(exception) => client.exception(exception),
            TerminalCompletion::CommitRejected(exception) => client.commit_rejected(exception),
            TerminalCompletion::CommandError(error) => client.command_error(error),
            TerminalCompletion::Cancelled => client.abort_cancelled(),
            TerminalCompletion::RenewalFailed => client.abort_transaction_renewal_failed(),
            TerminalCompletion::Limit(info) => client.abort_limits_reached(info),
        }
        // Keep the task alive until the callback returns, including any session I/O.
        drop(self.task);
    }
}

impl Task {
    pub(super) fn terminal_outcome(
        self: Box<Self>,
        completion: TerminalCompletion,
    ) -> ExecutionOutcome {
        ExecutionOutcome::Finish(TerminalRequest {
            task: self,
            completion,
        })
    }

    pub(super) fn cancelled_outcome(self: Box<Self>) -> ExecutionOutcome {
        self.rollback_cancelled_transaction();
        self.terminal_outcome(TerminalCompletion::Cancelled)
    }

    pub(super) fn commit_failure_outcome(
        self: Box<Self>,
        failure: CommitFailure,
    ) -> ExecutionOutcome {
        let completion = match failure {
            CommitFailure::Cancelled => TerminalCompletion::Cancelled,
            CommitFailure::Rejected(error) => {
                TerminalCompletion::CommitRejected(self.commit_rejection(error))
            }
        };
        self.terminal_outcome(completion)
    }

    pub(super) fn conflict_outcome(
        self: Box<Self>,
        session: &dyn Session,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) -> ExecutionOutcome {
        self.log_conflict_retry(boundary, conflict_info.as_ref());
        session.rollback().unwrap();
        self.retry_outcome(boundary, conflict_info)
    }

    pub(super) fn retry_outcome(
        self: Box<Self>,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) -> ExecutionOutcome {
        ExecutionOutcome::Retry(RetryRequest {
            task: self,
            boundary,
            conflict_info,
        })
    }

    pub(super) fn suspension_outcome(
        self: Box<Self>,
        kind: SuspensionKind,
        boundary: CommittedBoundary,
    ) -> ExecutionOutcome {
        ExecutionOutcome::Suspend(SuspensionRequest {
            task: self,
            kind,
            boundary,
        })
    }

    /// Capture rejection details before handing ownership to terminal completion.
    /// Batch startup also uses this policy without entering the VM execution loop.
    pub(super) fn commit_rejection(&self, error: WorldStateError) -> Box<Exception> {
        if let TaskStart::StartBatchWorldState { result_sink, .. } = self.state.task_start() {
            *result_sink.lock().unwrap() = Some(Err(SchedulerError::CommandExecutionError(
                CommandError::DatabaseError(error.clone()),
            )));
        }
        let error = match error {
            error @ WorldStateError::DatabaseOverloaded(_) => error.to_error(),
            error => E_EXEC.with_msg(|| format!("Database commit failed: {error}")),
        };
        let (stack, backtrace) = self.vm_host.get_traceback();
        Box::new(Exception {
            error,
            stack,
            backtrace,
        })
    }
}
