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

//! How a task ended, as reported to whoever started it.
//!
//! An outcome has two parts. The ending says how the task stopped, in LambdaMOO's terms: it
//! completed, it suspended, or it aborted. `kept` says whether its last transaction committed,
//! which MOO semantics leave independent of the ending: a task that ends in an uncaught error or
//! runs out of ticks keeps its changes, while one cancelled by another task does not. Changes
//! committed earlier, when the task suspended, forked or read input, stand either way.

use crate::tasks::{AbortLimitReason, CommandError, Exception};
use moor_var::{Symbol, Var};
use std::{fmt::Display, time::Duration};

/// Whether a task's last transaction committed.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Kept {
    Yes,
    No,
    /// Whoever reports the outcome cannot tell, such as when a task's result was lost.
    Unknown,
}

/// How a task stopped.
#[derive(Clone, Debug, PartialEq)]
pub enum TaskEnding {
    /// The task returned this value.
    Completed(Var),
    /// The task suspended or is waiting for input, and continues in the background.
    Suspended,
    /// The task stopped before returning.
    Aborted(AbortReason),
    /// The task ended, but its result did not reach whoever is reporting the outcome.
    ResultLost,
}

/// Why a task stopped before returning.
#[derive(Clone, Debug, PartialEq)]
pub enum AbortReason {
    /// The task hit a tick, time or captured-output limit.
    Limit(AbortLimitReason),
    /// The task raised an error nothing caught.
    Exception(Exception),
    /// A verb call found no verb.
    VerbNotFound(Var, Symbol),
    /// A command task matched no command.
    CommandFailed(CommandError),
    /// Another task, or the server, cancelled the task.
    Cancelled,
    /// The task killed itself with `kill_task(task_id())`.
    Killed,
    /// The task called `rollback()`.
    RolledBack,
    /// The task's commit conflicted on every attempt the server allows.
    ConflictRetriesExhausted,
    /// The call that started the task passed its deadline, and the task was cancelled.
    Deadline(Duration),
    /// The server could not finish the task.
    Internal(String),
}

/// How a task ended, and whether its last transaction committed.
#[derive(Clone, Debug, PartialEq)]
pub struct TaskOutcome {
    pub kept: Kept,
    pub ending: TaskEnding,
}

impl TaskOutcome {
    /// The task returned `value` and committed.
    pub fn completed(value: Var) -> Self {
        Self {
            kept: Kept::Yes,
            ending: TaskEnding::Completed(value),
        }
    }

    /// The task committed its work so far and continues in the background.
    pub fn suspended() -> Self {
        Self {
            kept: Kept::Yes,
            ending: TaskEnding::Suspended,
        }
    }

    pub fn aborted(reason: AbortReason, kept: Kept) -> Self {
        Self {
            kept,
            ending: TaskEnding::Aborted(reason),
        }
    }

    /// The task's result was lost; `kept` says what is known about its last transaction.
    pub fn result_lost(kept: Kept) -> Self {
        Self {
            kept,
            ending: TaskEnding::ResultLost,
        }
    }

    /// The returned value, if the task completed.
    pub fn completed_value(&self) -> Option<&Var> {
        match &self.ending {
            TaskEnding::Completed(value) => Some(value),
            _ => None,
        }
    }
}

impl Display for AbortReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            AbortReason::Limit(AbortLimitReason::Ticks(_)) => f.write_str("Task ran out of ticks"),
            AbortReason::Limit(AbortLimitReason::Time(_)) => f.write_str("Task ran out of seconds"),
            AbortReason::Limit(AbortLimitReason::OutputEvents(_)) => {
                f.write_str("Task produced too many captured output events")
            }
            AbortReason::Limit(AbortLimitReason::OutputBytes(_)) => {
                f.write_str("Task produced too much captured output")
            }
            AbortReason::Exception(exception) => write!(f, "Task exception: {exception}"),
            AbortReason::VerbNotFound(object, verb) => {
                write!(f, "Verb not found: {object:?}:{verb}")
            }
            AbortReason::CommandFailed(error) => write!(f, "{error}"),
            AbortReason::Cancelled => f.write_str("Task cancelled"),
            AbortReason::Killed => f.write_str("Task killed itself"),
            AbortReason::RolledBack => f.write_str("Task rolled back"),
            AbortReason::ConflictRetriesExhausted => {
                f.write_str("Task could not commit after repeated conflicts")
            }
            AbortReason::Deadline(deadline) => {
                write!(f, "Task passed its call deadline of {deadline:?}")
            }
            AbortReason::Internal(message) => write!(f, "Task failed: {message}"),
        }
    }
}
