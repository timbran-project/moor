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

//! Conflict retry replaces an attempt under the lifecycle lock.

use crate::tasks::{
    SchedulerOp, sched_counters,
    scheduler::{Scheduler, lifecycle::SchedulerState},
    task::Task,
    task_q::WakeCondition,
};
use moor_common::{
    model::ConflictInfo,
    tasks::{
        SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
        TaskId,
    },
    util::Deadline,
};
use rand::RngExt;
use std::time::Duration;
use tracing::{debug, error, trace};

impl Scheduler {
    pub fn handle_task_conflict_retry(
        &self,
        task_id: TaskId,
        mut task: Box<Task>,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskConflictRetry);

        let mut lc = self.lifecycle.lock();

        lc.discard_task_effects(task_id);

        // Make sure the old thread is dead.
        task.control.request_cancel();

        if lc.state != SchedulerState::Running {
            debug!(task_id, "Discarding transaction retry during shutdown");
            lc.task_q.remove_message_queue(task_id);
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }

        // Remove from active tasks to get session/result_sender
        let Some(old_tc) = lc.task_q.active.remove(&task_id) else {
            error!(
                task_id,
                "Task not found for retry suspension, ignoring -- consistency issue!"
            );
            return;
        };

        // If the number of retries has been exceeded, abort immediately
        let max_retries = self.server_options.load().max_task_retries;
        if task.retries >= max_retries {
            let task_origin = task.conflict_task_origin();
            let conflict = conflict_info
                .as_ref()
                .map(ToString::to_string)
                .unwrap_or_else(|| "details unavailable".to_string());
            error!(
                task_id,
                retries = task.retries,
                max_retries,
                task = %task_origin,
                boundary,
                %conflict,
                "Task retry limit exhausted; aborting task"
            );
            lc.task_q
                .send_task_result_direct(task_id, old_tc.result_sender, Err(TaskAbortedError));
            return;
        }
        task.retries += 1;

        // Calculate backoff time: 10-50ms base, exponentially backed off
        let mut rng = rand::rng();
        let base_delay_ms = rng.random_range(10u64..=50u64);
        // Exponential backoff: base * 2^(retries-1)
        // Cap shift at 10 to prevent excessive delays (max multiplier 1024x)
        let shift = (task.retries as u32).saturating_sub(1).min(10);
        let delay_ms = base_delay_ms << shift;
        let wake_time = Deadline::from_now(Duration::from_millis(delay_ms)).instant();

        trace!(
            task_id,
            retries = task.retries,
            delay_ms,
            "Suspending task for retry backoff"
        );

        // Add to suspension queue with retry wake condition
        lc.task_q.suspended.add_task(
            WakeCondition::Retry(wake_time),
            task,
            old_tc.session,
            old_tc.result_sender,
        );
    }
}
