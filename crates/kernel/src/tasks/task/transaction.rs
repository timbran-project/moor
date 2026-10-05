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

//! Transaction boundary arbitration for task workers.
//! A successful yield transfers an owned boundary to scheduler finalization.
//! This module also owns retry snapshots and conflict diagnostics. Callers inject boundary results
//! into the VM before `refresh_retry_state`, so a retry restores the state after that boundary.

use super::Task;
use crate::{
    task_context::{
        RenewedTransaction, TransactionRenewalError, commit_current_transaction, has_active_task,
        renew_current_transaction, rollback_current_transaction,
    },
    tasks::{
        TaskStart, task_control::CommittedBoundary, task_scheduler_client::TaskSchedulerClient,
    },
};
use moor_common::{
    model::{CommitResult, ConflictInfo, ConflictTarget, WorldState, WorldStateError},
    tasks::{CommandError, Exception, Session},
};
use moor_compiler::to_literal;
use moor_var::E_EXEC;
use tracing::warn;

pub(super) enum YieldCommit {
    Committed(CommittedBoundary),
    Conflict(Option<ConflictInfo>),
}

pub(super) enum Renewal<R> {
    Continued(R),
    Conflict(Option<ConflictInfo>),
    CommitFailed(WorldStateError),
    BeginFailed(WorldStateError),
    Cancelled,
}

impl Task {
    pub(super) fn cancel_before_commit(&self, task_scheduler_client: &TaskSchedulerClient) {
        if has_active_task() {
            rollback_current_transaction()
                .expect("Could not rollback transaction after cancellation won");
        }
        task_scheduler_client.abort_cancelled();
    }

    pub(super) fn reject_commit(
        &self,
        task_scheduler_client: &TaskSchedulerClient,
        error: WorldStateError,
    ) {
        if let TaskStart::StartBatchWorldState { result_sink, .. } = self.state.task_start() {
            *result_sink.lock().unwrap() = Some(Err(
                moor_common::tasks::SchedulerError::CommandExecutionError(
                    CommandError::DatabaseError(error.clone()),
                ),
            ));
        }
        let error = match error {
            error @ WorldStateError::DatabaseOverloaded(_) => error.to_error(),
            error => E_EXEC.with_msg(|| format!("Database commit failed: {error}")),
        };
        let (stack, backtrace) = self.vm_host.get_traceback();
        task_scheduler_client.commit_rejected(Box::new(Exception {
            error,
            stack,
            backtrace,
        }));
    }

    #[inline]
    pub(super) fn refresh_retry_state(&mut self) {
        let snapshot = self.vm_host.snapshot_state();
        self.vm_host.restore_state(&snapshot);
        self.retry_state = snapshot;
        // `retries` counts conflict retries consecutive since the last successful
        // transaction boundary, not lifetime retries against this task. Crossing a
        // successful boundary here (this is only ever called after a commit succeeded)
        // means whatever conflicts happened before this point are resolved and done;
        // they must not count against a later, unrelated conflict later in this same
        // long-lived task's life. This bounds backoff growth and `max_task_retries` to
        // one piece of work, rather than letting a heartbeat-shaped task accumulate
        // retries across its entire lifetime and spuriously hit the abort threshold.
        self.retries = 0;
    }

    pub(crate) fn conflict_task_origin(&self) -> String {
        match self.state.task_start() {
            TaskStart::StartCommandVerb {
                player, command, ..
            } => format!("command {command:?} by {player}"),
            TaskStart::StartDoCommand {
                player, command, ..
            } => format!("do_command {command:?} by {player}"),
            TaskStart::StartVerb { vloc, verb, .. } => {
                format!("verb {}:{verb}", to_literal(vloc))
            }
            TaskStart::StartScheduled {
                schedule_id,
                vloc,
                verb,
                ..
            } => {
                format!("scheduled {schedule_id} verb {vloc}:{verb}")
            }
            TaskStart::StartFork { fork_request, .. } => format!(
                "fork {}:{} (parent {})",
                to_literal(&fork_request.activation.this),
                fork_request.activation.verb_name,
                fork_request.parent_task_id
            ),
            TaskStart::StartEval { player, .. } => format!("eval by {player}"),
            TaskStart::StartExceptionHandler { player, .. } => {
                format!("exception handler for {player}")
            }
            TaskStart::StartBatchWorldState {
                player, actions, ..
            } => format!("batch of {} actions for {player}", actions.len()),
        }
    }

    pub(super) fn log_conflict_retry(
        &self,
        boundary: &'static str,
        conflict_info: Option<&ConflictInfo>,
    ) {
        if !tracing::enabled!(tracing::Level::DEBUG) {
            return;
        }

        let task = self.conflict_task_origin();
        let Some(conflict_info) = conflict_info else {
            tracing::debug!(
                task_id = self.task_id,
                retry = self.retries,
                %task,
                boundary,
                "Transaction conflict without key details; retrying task"
            );
            return;
        };

        let relation = conflict_info.relation_name;
        let conflict_type = conflict_info.conflict_type;
        match &conflict_info.target {
            Some(ConflictTarget::Property {
                object,
                uuid,
                name: Some(name),
            }) => {
                let property = format!("{object}.{}", name.as_string());
                tracing::debug!(
                    task_id = self.task_id,
                    retry = self.retries,
                    %task,
                    boundary,
                    type = %conflict_type,
                    %relation,
                    %uuid,
                    "Transaction conflict on {property}; retrying task"
                );
            }
            Some(ConflictTarget::Object(object)) => {
                tracing::debug!(
                    task_id = self.task_id,
                    retry = self.retries,
                    %task,
                    boundary,
                    type = %conflict_type,
                    %relation,
                    "Transaction conflict on {object}; retrying task"
                );
            }
            _ => {
                let key = &conflict_info.domain_key;
                tracing::debug!(
                    task_id = self.task_id,
                    retry = self.retries,
                    %task,
                    boundary,
                    type = %conflict_type,
                    %relation,
                    "Transaction conflict on {key}; retrying task"
                );
            }
        }
    }

    #[inline]
    /// Commit before handing task ownership to a scheduler callback.
    ///
    /// The callback releases the boundary claim after it commits the session. Until then,
    /// cancellation leaves the active-task record in place for deterministic cleanup.
    pub(super) fn commit_yield_transaction(
        &self,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> Option<YieldCommit> {
        let Some(claim) = self.control.claim_boundary() else {
            self.cancel_before_commit(task_scheduler_client);
            return None;
        };

        let result = commit_current_transaction();
        if matches!(&result, Ok(CommitResult::Success { .. })) {
            return Some(YieldCommit::Committed(claim.committed()));
        }

        if claim.failed() {
            return match result {
                Ok(CommitResult::ConflictRetry { conflict_info }) => {
                    Some(YieldCommit::Conflict(conflict_info))
                }
                Ok(CommitResult::Success { .. }) => unreachable!("success transferred the claim"),
                Err(error) => {
                    self.reject_commit(task_scheduler_client, error);
                    None
                }
            };
        }

        if let Err(error) = session.rollback() {
            warn!(
                ?error,
                "Could not roll back session after cancelled yield commit"
            );
        }
        self.cancel_before_commit(task_scheduler_client);
        None
    }

    pub(super) fn commit_terminal_transaction(
        &self,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> Option<CommitResult> {
        let Some(claim) = self.control.claim_terminal() else {
            self.cancel_before_commit(task_scheduler_client);
            return None;
        };

        let result = commit_current_transaction();
        let committed = matches!(result, Ok(CommitResult::Success { .. }));
        let proceed = if committed {
            claim.committed()
        } else {
            claim.failed()
        };
        if proceed {
            return match result {
                Ok(result) => Some(result),
                Err(error) => {
                    self.reject_commit(task_scheduler_client, error);
                    None
                }
            };
        }

        if let Err(error) = session.rollback() {
            warn!(
                ?error,
                "Could not roll back session after cancelled terminal commit"
            );
        }
        self.cancel_before_commit(task_scheduler_client);
        None
    }

    pub(super) fn rollback_terminal_transaction(
        &self,
        task_scheduler_client: &TaskSchedulerClient,
    ) -> bool {
        let Some(claim) = self.control.claim_terminal() else {
            self.cancel_before_commit(task_scheduler_client);
            return false;
        };
        rollback_current_transaction().expect("Could not rollback terminal task transaction");
        claim.rolled_back()
    }

    pub(super) fn renew_transaction<R>(
        &self,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
        create_transaction: impl FnOnce() -> Result<(Box<dyn WorldState>, R), WorldStateError>,
    ) -> Renewal<R> {
        let Some(claim) = self.control.claim_boundary() else {
            self.cancel_before_commit(task_scheduler_client);
            return Renewal::Cancelled;
        };

        let result = renew_current_transaction(create_transaction);
        let committed = matches!(
            result,
            Ok(RenewedTransaction::Continued { .. }) | Err(TransactionRenewalError::Begin(_))
        );
        let proceed = if committed {
            claim.committed().finish()
        } else {
            claim.failed()
        };
        if proceed {
            return match result {
                Ok(RenewedTransaction::Continued { value, .. }) => Renewal::Continued(value),
                Ok(RenewedTransaction::Conflict(info)) => Renewal::Conflict(info),
                Err(TransactionRenewalError::Commit(error)) => Renewal::CommitFailed(error),
                Err(TransactionRenewalError::Begin(error)) => Renewal::BeginFailed(error),
            };
        }

        if !committed && let Err(error) = session.rollback() {
            warn!(
                ?error,
                "Could not roll back session after cancelled transaction renewal"
            );
        }
        self.cancel_before_commit(task_scheduler_client);
        Renewal::Cancelled
    }
}
