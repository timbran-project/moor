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

//! Lock-free arbitration between task cancellation and transaction commit.

use std::sync::atomic::{AtomicU8, Ordering};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
enum TaskState {
    Running = 0,
    Cancelled = 1,
    BoundaryCommit = 2,
    CancelAfterBoundaryCommit = 3,
    TerminalCommit = 4,
    CancelAfterTerminalCommit = 5,
    Finalizing = 6,
}

impl TaskState {
    fn from_u8(value: u8) -> Self {
        match value {
            0 => Self::Running,
            1 => Self::Cancelled,
            2 => Self::BoundaryCommit,
            3 => Self::CancelAfterBoundaryCommit,
            4 => Self::TerminalCommit,
            5 => Self::CancelAfterTerminalCommit,
            6 => Self::Finalizing,
            _ => unreachable!("invalid task control state {value}"),
        }
    }
}

/// Result of an external cancellation request.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CancelResult {
    /// Cancellation won before a commit started. The scheduler may detach the task.
    Cancelled,
    /// A non-terminal transaction is committing. The worker will stop after that boundary.
    AfterBoundary,
    /// A terminal commit won. The caller must wait for its result to finish publication.
    Completing,
}

/// Shared state used by the scheduler and one task worker.
///
/// A task must claim a commit before it calls into the database. Cancellation and commit then
/// have one atomic ordering: cancellation either prevents the commit, stops the task after a
/// non-terminal boundary, or observes that terminal completion already won.
#[derive(Debug)]
pub struct TaskControl {
    state: AtomicU8,
}

impl Default for TaskControl {
    fn default() -> Self {
        Self::new()
    }
}

impl TaskControl {
    pub fn new() -> Self {
        Self {
            state: AtomicU8::new(TaskState::Running as u8),
        }
    }

    #[inline]
    pub(crate) fn is_cancelled(&self) -> bool {
        matches!(
            self.load(),
            TaskState::Cancelled
                | TaskState::CancelAfterBoundaryCommit
                | TaskState::CancelAfterTerminalCommit
        )
    }

    pub(crate) fn request_cancel(&self) -> CancelResult {
        loop {
            let state = self.load();
            let (next, result) = match state {
                TaskState::Running => (TaskState::Cancelled, CancelResult::Cancelled),
                TaskState::Cancelled => return CancelResult::Cancelled,
                TaskState::BoundaryCommit => (
                    TaskState::CancelAfterBoundaryCommit,
                    CancelResult::AfterBoundary,
                ),
                TaskState::CancelAfterBoundaryCommit => return CancelResult::AfterBoundary,
                TaskState::TerminalCommit => (
                    TaskState::CancelAfterTerminalCommit,
                    CancelResult::Completing,
                ),
                TaskState::CancelAfterTerminalCommit | TaskState::Finalizing => {
                    return CancelResult::Completing;
                }
            };

            if self.transition(state, next) {
                return result;
            }
        }
    }

    pub(crate) fn begin_boundary_commit(&self) -> bool {
        self.begin_commit(TaskState::BoundaryCommit)
    }

    pub(crate) fn finish_boundary_commit(&self) -> bool {
        loop {
            let state = self.load();
            let next = match state {
                TaskState::BoundaryCommit => TaskState::Running,
                TaskState::CancelAfterBoundaryCommit => TaskState::Cancelled,
                _ => return false,
            };
            if self.transition(state, next) {
                return next == TaskState::Running && !self.is_cancelled();
            }
        }
    }

    pub(crate) fn begin_terminal_commit(&self) -> bool {
        self.begin_commit(TaskState::TerminalCommit)
    }

    /// Finish a terminal commit attempt.
    ///
    /// A successful database commit always wins. A conflict or commit failure releases the claim;
    /// a cancellation which arrived during that failed attempt then wins instead of allowing a
    /// retry.
    pub(crate) fn finish_terminal_commit(&self, committed: bool) -> bool {
        loop {
            let state = self.load();
            let next = match (state, committed) {
                (TaskState::TerminalCommit, true)
                | (TaskState::CancelAfterTerminalCommit, true) => TaskState::Finalizing,
                (TaskState::TerminalCommit, false) => TaskState::Running,
                (TaskState::CancelAfterTerminalCommit, false) => TaskState::Cancelled,
                _ => return false,
            };
            if self.transition(state, next) {
                return next != TaskState::Cancelled && !self.is_cancelled();
            }
        }
    }

    fn begin_commit(&self, commit_state: TaskState) -> bool {
        self.state
            .compare_exchange(
                TaskState::Running as u8,
                commit_state as u8,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok()
    }

    #[inline]
    fn load(&self) -> TaskState {
        TaskState::from_u8(self.state.load(Ordering::Acquire))
    }

    #[inline]
    fn transition(&self, from: TaskState, to: TaskState) -> bool {
        self.state
            .compare_exchange_weak(from as u8, to as u8, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancellation_wins_before_commit() {
        let control = TaskControl::new();
        assert_eq!(control.request_cancel(), CancelResult::Cancelled);
        assert!(!control.begin_boundary_commit());
        assert!(!control.begin_terminal_commit());
    }

    #[test]
    fn cancellation_stops_after_boundary_commit() {
        let control = TaskControl::new();
        assert!(control.begin_boundary_commit());
        assert_eq!(control.request_cancel(), CancelResult::AfterBoundary);
        assert!(!control.finish_boundary_commit());
        assert!(control.is_cancelled());
    }

    #[test]
    fn successful_terminal_commit_wins_cancellation_race() {
        let control = TaskControl::new();
        assert!(control.begin_terminal_commit());
        assert_eq!(control.request_cancel(), CancelResult::Completing);
        assert!(control.finish_terminal_commit(true));
        assert_eq!(control.request_cancel(), CancelResult::Completing);
    }

    #[test]
    fn cancellation_wins_when_terminal_commit_conflicts() {
        let control = TaskControl::new();
        assert!(control.begin_terminal_commit());
        assert_eq!(control.request_cancel(), CancelResult::Completing);
        assert!(!control.finish_terminal_commit(false));
        assert!(control.is_cancelled());
    }
}
