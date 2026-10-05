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

//! Compatibility entry points for callers that address a task by ID.
//!
//! These calls select the active dispatch at entry, then use the same guarded transitions as
//! workers. TaskSchedulerClient retains its dispatch identity instead of selecting a new dispatch
//! on each callback. Handoffs carrying a Task or CommittedBoundary already carry their identity.

use crate::tasks::scheduler::Scheduler;
use moor_common::tasks::{CommandError, Exception, TaskId};
use moor_var::{Symbol, Var};
use std::backtrace::Backtrace;

impl Scheduler {
    pub fn handle_task_abort_cancelled(&self, task_id: TaskId) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_abort_cancelled_for_dispatch(&dispatch);
    }

    pub fn handle_task_abort_panicked(
        &self,
        task_id: TaskId,
        panic_msg: String,
        _backtrace: Backtrace,
    ) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_abort_panicked_for_dispatch(&dispatch, panic_msg, _backtrace);
    }

    pub fn handle_task_success(
        &self,
        task_id: TaskId,
        value: Var,
        mutations_made: bool,
        timestamp: u64,
    ) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_success_for_dispatch(&dispatch, value, mutations_made, timestamp);
    }

    pub fn handle_task_verb_not_found(&self, task_id: TaskId, who: Var, what: Symbol) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_verb_not_found_for_dispatch(&dispatch, who, what);
    }

    pub fn handle_task_command_error(&self, task_id: TaskId, error: CommandError) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_command_error_for_dispatch(&dispatch, error);
    }

    pub fn handle_task_transaction_renewal_failed(&self, task_id: TaskId) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_transaction_renewal_failed_for_dispatch(&dispatch);
    }

    pub fn handle_task_exception(&self, task_id: TaskId, exception: Box<Exception>) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_exception_for_dispatch(&dispatch, exception);
    }

    pub fn handle_task_commit_rejected(&self, task_id: TaskId, exception: Box<Exception>) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_task_commit_rejected_for_dispatch(&dispatch, exception);
    }
}
