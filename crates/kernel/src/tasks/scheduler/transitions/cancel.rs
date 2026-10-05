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

//! Cancellation and abort policy for active and suspended tasks.

use super::complete::TaskCompletion;
use crate::tasks::task_q::{RunningTaskPhase, TaskAttempt};
use crate::tasks::{
    AbortTaskOutcome, SchedulerOp, sched_counters,
    scheduler::{Scheduler, lifecycle::SchedulerState},
};
use moor_common::{
    model::TaskPermissions,
    tasks::{
        SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
        TaskId,
    },
};
use moor_var::{E_INVARG, Var, v_err};
use std::backtrace::Backtrace;
use tracing::{debug, warn};

impl Scheduler {
    pub(crate) fn handle_task_abort_cancelled_for_attempt(&self, attempt: &TaskAttempt) {
        let task_id = attempt.task_id();
        let requested_abort = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_attempt(attempt) {
                return;
            }
            let task = lc
                .task_q
                .active
                .get_mut(&task_id)
                .expect("checked current attempt");
            if task.phase != RunningTaskPhase::Running {
                return;
            }
            task.abort_error
                .take()
                .and_then(|error| TaskCompletion::reserve(task_id, task, Err(error)))
        };
        if let Some(completion) = requested_abort {
            if let Err(session_error) = completion.session.rollback() {
                warn!(
                    task_id,
                    ?session_error,
                    "Could not roll back cancelled task session"
                );
            }
            let mut lc = self.lifecycle.lock();
            if !completion.is_current(&lc) {
                return;
            }
            lc.discard_task_effects(task_id);
            lc.task_q.remove_message_queue(task_id);
            return completion.finish(&mut lc);
        }

        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskAbortCancelled);
        let (completion, shutting_down) = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_attempt(attempt) {
                return;
            }
            let shutting_down = lc.state != SchedulerState::Running;
            let task = lc
                .task_q
                .active
                .get_mut(&task_id)
                .expect("checked current attempt");
            let Some(completion) =
                TaskCompletion::reserve(task_id, task, Err(TaskAbortedCancelled))
            else {
                return;
            };
            let player = task.player;
            lc.discard_task_effects(task_id);
            lc.task_q.remove_message_queue(task_id);
            if shutting_down {
                debug!(task_id, "Task cancelled during shutdown");
            } else {
                warn!(task_id, "Task cancelled");
                if let Err(send_error) = completion.session.send_system_msg(player, "Aborted.") {
                    warn!("Could not send abort message to player: {send_error:?}");
                }
            }
            (completion, shutting_down)
        };

        // Shutdown rolls back buffered output. Ordinary cancellation preserves its commit policy.
        if shutting_down {
            if let Err(error) = completion.session.rollback() {
                debug!(
                    task_id,
                    ?error,
                    "Could not rollback cancelled session during shutdown"
                );
            }
            return completion.finish(&mut self.lifecycle.lock());
        }
        if completion.session.commit().is_err() {
            warn!("Could not commit aborted session; aborting task");
            return completion
                .finish_with_result(&mut self.lifecycle.lock(), Err(TaskAbortedError));
        }
        completion.finish(&mut self.lifecycle.lock());
    }

    pub(crate) fn handle_task_abort_panicked_for_attempt(
        &self,
        attempt: &TaskAttempt,
        panic_msg: String,
        _backtrace: Backtrace,
    ) {
        let task_id = attempt.task_id();
        warn!(?task_id, ?panic_msg, "Task thread panicked");

        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_current_attempt(attempt) {
            return;
        }

        lc.discard_task_effects(task_id);
        lc.task_q.remove_message_queue(task_id);

        // Task already dead, can't access session. Just send error result directly.
        lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
    }

    pub fn handle_kill_task(
        &self,
        _task_id: TaskId,
        victim_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        lc.task_q.kill_task(victim_task_id, sender_authority)
    }

    pub(crate) fn handle_kill_task_for_attempt(
        &self,
        attempt: &TaskAttempt,
        victim_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_attempt(attempt) {
            return v_err(E_INVARG);
        }
        lc.task_q.kill_task(victim_task_id, sender_authority)
    }

    /// Cancel a task the server started on its own behalf, with no permission check.
    /// Returns false if the task was already gone.
    pub fn handle_abort_task(&self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let mut lc = self.lifecycle.lock();
        lc.task_q.abort_task(victim_task_id)
    }
}
