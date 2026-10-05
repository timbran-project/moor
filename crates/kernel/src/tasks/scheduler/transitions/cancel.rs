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
use moor_var::Var;
use std::backtrace::Backtrace;
use tracing::{debug, warn};

impl Scheduler {
    pub fn handle_task_abort_cancelled(&self, task_id: TaskId) {
        let requested_abort = {
            let mut lc = self.lifecycle.lock();
            lc.task_q.active.get_mut(&task_id).and_then(|task| {
                task.abort_error
                    .take()
                    .map(|error| (error, task.session.clone()))
            })
        };
        if let Some((error, session)) = requested_abort {
            if let Err(session_error) = session.rollback() {
                warn!(
                    task_id,
                    ?session_error,
                    "Could not roll back cancelled task session"
                );
            }
            let mut lc = self.lifecycle.lock();
            lc.discard_task_effects(task_id);
            lc.task_q.remove_message_queue(task_id);
            return lc.task_q.send_task_result(task_id, Err(error));
        }

        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskAbortCancelled);

        // Extract session and player under lock. Shutdown cancellation does not publish an
        // "Aborted" message or commit buffered output; the shutdown notice has already been sent.
        let (session, shutting_down) = {
            let mut lc = self.lifecycle.lock();
            lc.discard_task_effects(task_id);
            lc.task_q.remove_message_queue(task_id);
            let shutting_down = lc.state != SchedulerState::Running;

            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                if lc.state == SchedulerState::Running {
                    warn!(task_id, "Task not found for abort");
                } else {
                    debug!(task_id, "Cancelled task already detached during shutdown");
                }
                return;
            };
            let session = task.session.clone();
            if shutting_down {
                debug!(task_id, "Task cancelled during shutdown");
                (session, true)
            } else {
                warn!(task_id, "Task cancelled");
                let player = task.player;
                if let Err(send_error) = session.send_system_msg(player, "Aborted.") {
                    warn!("Could not send abort message to player: {send_error:?}");
                }
                (session, false)
            }
        };

        if shutting_down {
            if let Err(e) = session.rollback() {
                debug!(task_id, error = ?e, "Could not rollback cancelled session during shutdown");
            }
            let mut lc = self.lifecycle.lock();
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }

        // Session commit (potential I/O) outside the lock.
        if session.commit().is_err() {
            warn!("Could not commit aborted session; aborting task");
            let mut lc = self.lifecycle.lock();
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        lc.task_q
            .send_task_result(task_id, Err(TaskAbortedCancelled));
    }

    pub fn handle_task_abort_panicked(
        &self,
        task_id: TaskId,
        panic_msg: String,
        _backtrace: Backtrace,
    ) {
        warn!(?task_id, ?panic_msg, "Task thread panicked");

        let mut lc = self.lifecycle.lock();

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

    /// Cancel a task the server started on its own behalf, with no permission check.
    /// Returns false if the task was already gone.
    pub fn handle_abort_task(&self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let mut lc = self.lifecycle.lock();
        lc.task_q.abort_task(victim_task_id)
    }
}
