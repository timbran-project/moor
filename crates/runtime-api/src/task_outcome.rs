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

//! FlatBuffer conversion for task outcomes.

use crate::{
    errors::{
        abort_limit_from_ref, abort_limit_to_flatbuffer_struct, command_error_from_ref,
        command_error_to_flatbuffer_struct, exception_to_flatbuffer_struct,
    },
    helpers::symbol_fb,
};
use moor_common::tasks::{AbortReason, Kept, TaskEnding, TaskOutcome};
use moor_schema::{
    convert::{exception_from_ref, symbol_from_ref, var_from_ref, var_to_flatbuffer},
    fb_read, rpc,
};
use moor_var::EncodingError;
use std::time::Duration;

/// Convert TaskOutcome to FlatBuffer struct
pub fn task_outcome_to_flatbuffer_struct(
    outcome: &TaskOutcome,
) -> Result<rpc::TaskOutcome, EncodingError> {
    let kept = match outcome.kept {
        Kept::Yes => rpc::Kept::Yes,
        Kept::No => rpc::Kept::No,
        Kept::Unknown => rpc::Kept::Unknown,
    };
    let ending = match &outcome.ending {
        TaskEnding::Completed(result) => {
            rpc::TaskEnding::TaskCompleted(Box::new(rpc::TaskCompleted {
                result: Box::new(var_to_flatbuffer(result).map_err(|e| {
                    EncodingError::CouldNotEncode(format!("Failed to encode task result: {e}"))
                })?),
            }))
        }
        TaskEnding::Suspended => rpc::TaskEnding::TaskSuspended(Box::new(rpc::TaskSuspended {})),
        TaskEnding::Aborted(reason) => rpc::TaskEnding::TaskAborted(Box::new(rpc::TaskAborted {
            reason: abort_reason_to_flatbuffer(reason)?,
        })),
        TaskEnding::ResultLost => rpc::TaskEnding::TaskResultLost(Box::new(rpc::TaskResultLost {})),
    };
    Ok(rpc::TaskOutcome { kept, ending })
}

fn abort_reason_to_flatbuffer(reason: &AbortReason) -> Result<rpc::AbortReason, EncodingError> {
    Ok(match reason {
        AbortReason::Limit(limit) => rpc::AbortReason::AbortedLimit(Box::new(rpc::AbortedLimit {
            limit: Box::new(abort_limit_to_flatbuffer_struct(limit)),
        })),
        AbortReason::Exception(exception) => {
            rpc::AbortReason::AbortedException(Box::new(rpc::AbortedException {
                exception: Box::new(exception_to_flatbuffer_struct(exception)?),
            }))
        }
        AbortReason::VerbNotFound(object, verb) => {
            rpc::AbortReason::AbortedVerbNotFound(Box::new(rpc::AbortedVerbNotFound {
                where_: Box::new(var_to_flatbuffer(object).map_err(|e| {
                    EncodingError::CouldNotEncode(format!("Failed to encode verbnf `where`: {e}"))
                })?),
                what: symbol_fb(verb),
            }))
        }
        AbortReason::CommandFailed(error) => {
            rpc::AbortReason::AbortedCommandFailed(Box::new(rpc::AbortedCommandFailed {
                error: Box::new(command_error_to_flatbuffer_struct(error)?),
            }))
        }
        AbortReason::Cancelled => {
            rpc::AbortReason::AbortedCancelled(Box::new(rpc::AbortedCancelled {}))
        }
        AbortReason::Killed => rpc::AbortReason::AbortedKilled(Box::new(rpc::AbortedKilled {})),
        AbortReason::RolledBack => {
            rpc::AbortReason::AbortedRolledBack(Box::new(rpc::AbortedRolledBack {}))
        }
        AbortReason::ConflictRetriesExhausted => rpc::AbortReason::AbortedConflictRetriesExhausted(
            Box::new(rpc::AbortedConflictRetriesExhausted {}),
        ),
        AbortReason::Deadline(deadline) => {
            rpc::AbortReason::AbortedDeadline(Box::new(rpc::AbortedDeadline {
                deadline_nanos: deadline.as_nanos() as u64,
            }))
        }
        AbortReason::Internal(message) => {
            rpc::AbortReason::AbortedInternal(Box::new(rpc::AbortedInternal {
                message: message.clone(),
            }))
        }
    })
}

/// Convert from FlatBuffer TaskOutcomeRef to TaskOutcome
pub fn task_outcome_from_ref(outcome: rpc::TaskOutcomeRef<'_>) -> Result<TaskOutcome, String> {
    let kept = match fb_read!(outcome, kept) {
        rpc::Kept::Yes => Kept::Yes,
        rpc::Kept::No => Kept::No,
        rpc::Kept::Unknown => Kept::Unknown,
    };
    let ending = match fb_read!(outcome, ending) {
        rpc::TaskEndingRef::TaskCompleted(completed) => TaskEnding::Completed(
            var_from_ref(fb_read!(completed, result))
                .map_err(|e| format!("Failed to decode task result: {e}"))?,
        ),
        rpc::TaskEndingRef::TaskSuspended(_) => TaskEnding::Suspended,
        rpc::TaskEndingRef::TaskAborted(aborted) => {
            TaskEnding::Aborted(abort_reason_from_ref(fb_read!(aborted, reason))?)
        }
        rpc::TaskEndingRef::TaskResultLost(_) => TaskEnding::ResultLost,
    };
    Ok(TaskOutcome { kept, ending })
}

fn abort_reason_from_ref(reason: rpc::AbortReasonRef<'_>) -> Result<AbortReason, String> {
    Ok(match reason {
        rpc::AbortReasonRef::AbortedLimit(limit) => {
            AbortReason::Limit(abort_limit_from_ref(fb_read!(limit, limit))?)
        }
        rpc::AbortReasonRef::AbortedException(aborted) => {
            AbortReason::Exception(exception_from_ref(fb_read!(aborted, exception))?)
        }
        rpc::AbortReasonRef::AbortedVerbNotFound(verbnf) => AbortReason::VerbNotFound(
            var_from_ref(fb_read!(verbnf, where_))
                .map_err(|e| format!("Failed to decode verb `where`: {e}"))?,
            symbol_from_ref(fb_read!(verbnf, what))
                .map_err(|e| format!("Failed to decode verb `what`: {e}"))?,
        ),
        rpc::AbortReasonRef::AbortedCommandFailed(failed) => {
            AbortReason::CommandFailed(command_error_from_ref(fb_read!(failed, error))?)
        }
        rpc::AbortReasonRef::AbortedCancelled(_) => AbortReason::Cancelled,
        rpc::AbortReasonRef::AbortedKilled(_) => AbortReason::Killed,
        rpc::AbortReasonRef::AbortedRolledBack(_) => AbortReason::RolledBack,
        rpc::AbortReasonRef::AbortedConflictRetriesExhausted(_) => {
            AbortReason::ConflictRetriesExhausted
        }
        rpc::AbortReasonRef::AbortedDeadline(deadline) => {
            AbortReason::Deadline(Duration::from_nanos(fb_read!(deadline, deadline_nanos)))
        }
        rpc::AbortReasonRef::AbortedInternal(internal) => {
            AbortReason::Internal(fb_read!(internal, message).to_string())
        }
    })
}
