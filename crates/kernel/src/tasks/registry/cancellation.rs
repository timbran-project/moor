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

//! Cancellation bookkeeping for active and suspended registrations.
//!
//! Callers hold the lifecycle lock. `kill_task` checks authority before `cancel_task` changes
//! membership. `abort_task` is the server-owned entry point. A reserved completion or in-flight
//! commit retains active membership so its owner can finish cleanup and result delivery.

use super::{RunningTaskPhase, TaskQ};
use crate::tasks::{AbortTaskOutcome, SchedulerOp, sched_counters, task_control::CancelResult};
use moor_common::{model::TaskPermissions, tasks::TaskId};
use moor_var::{E_INVARG, Var, v_bool_int, v_err};
use tracing::error;

impl TaskQ {
    /// Take a task out of the queues and stop it running. Returns false if the task was not
    /// found. This does no permission check, so anything reachable from the world must check
    /// authority first.
    fn cancel_task(&mut self, victim_task_id: TaskId, is_suspended: bool) -> bool {
        if is_suspended {
            return self
                .suspended
                .remove_task_terminal(victim_task_id)
                .is_some();
        }

        let Some(task) = self.active.get(&victim_task_id) else {
            return false;
        };
        if matches!(task.phase, RunningTaskPhase::Completing(_))
            || task.control.request_cancel() != CancelResult::Cancelled
        {
            return true;
        }

        self.active.remove(&victim_task_id);
        self.suspended.enqueue_dependents_for(victim_task_id);
        true
    }

    pub(crate) fn kill_task(
        &mut self,
        victim_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Var {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = match self.authority_may_kill_task(victim_task_id, sender_authority) {
            Ok(is_suspended) => is_suspended,
            Err(error) => return v_err(error),
        };

        if !self.cancel_task(victim_task_id, is_suspended) {
            if !is_suspended {
                return v_err(E_INVARG);
            }
            error!(
                task = victim_task_id,
                "Task not found in suspended list for kill request"
            );
        }
        v_bool_int(false)
    }

    /// Cancel a task the server itself started, with no permission check. Used when whatever
    /// was waiting for the task's result has given up on it.
    pub(crate) fn abort_task(&mut self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::KillTask);

        let is_suspended = self.suspended.get(victim_task_id).is_some();
        if is_suspended {
            return if self.cancel_task(victim_task_id, true) {
                AbortTaskOutcome::Cancelled
            } else {
                AbortTaskOutcome::NotFound
            };
        }

        let Some(task) = self.active.get(&victim_task_id) else {
            return AbortTaskOutcome::NotFound;
        };

        // A completion owner can be finalizing a cancellation or a failed renewal even when
        // the atomic control is no longer in a terminal database commit state.
        if matches!(task.phase, RunningTaskPhase::Completing(_)) {
            return AbortTaskOutcome::Completing;
        }
        match task.control.request_cancel() {
            CancelResult::Completing => AbortTaskOutcome::Completing,
            CancelResult::AfterBoundary => AbortTaskOutcome::Cancelled,
            CancelResult::Cancelled => {
                self.active.remove(&victim_task_id);
                self.suspended.enqueue_dependents_for(victim_task_id);
                AbortTaskOutcome::Cancelled
            }
        }
    }
}
