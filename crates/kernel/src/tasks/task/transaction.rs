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

use super::Task;
use crate::{
    task_context::{
        TransactionRenewalError, commit_current_transaction, rollback_current_transaction,
        with_new_transaction,
    },
    tasks::{task_control::CommittedBoundary, task_scheduler_client::TaskSchedulerClient},
};
use moor_common::{
    model::{CommitResult, ConflictInfo, WorldState, WorldStateError},
    tasks::Session,
};
use tracing::warn;

pub(super) enum YieldCommit {
    Committed(CommittedBoundary),
    Conflict(Option<ConflictInfo>),
}

impl Task {
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
    ) -> Option<Result<(CommitResult, Option<R>), TransactionRenewalError>> {
        let Some(claim) = self.control.claim_boundary() else {
            self.cancel_before_commit(task_scheduler_client);
            return None;
        };

        let result = with_new_transaction(create_transaction);
        let committed = matches!(
            result,
            Ok((CommitResult::Success { .. }, _)) | Err(TransactionRenewalError::Begin(_))
        );
        let proceed = if committed {
            claim.committed().finish()
        } else {
            claim.failed()
        };
        if proceed {
            return Some(result);
        }

        if !committed && let Err(error) = session.rollback() {
            warn!(
                ?error,
                "Could not roll back session after cancelled transaction renewal"
            );
        }
        self.cancel_before_commit(task_scheduler_client);
        None
    }
}
