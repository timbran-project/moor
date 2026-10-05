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

//! Terminal completion retains its result in active metadata during session I/O.
//! Only one completion owner can reserve a running dispatch. The worker panic handler performs
//! registry cleanup if session finalization unwinds; this owner never locks or publishes in Drop.

use super::super::lifecycle::TaskLifecycle;
use crate::tasks::registry::{RunningTask, RunningTaskPhase, TaskDispatch};
use moor_common::tasks::{SchedulerError, Session, TaskId};
use moor_var::Var;
use std::sync::Arc;

use crate::tasks::{
    SchedulerOp, TaskStart, sched_counters,
    scheduler::Scheduler,
    task_scheduler_client::{TaskLimitDisposition, TaskLimitInfo},
};
use moor_common::tasks::{
    AbortLimitReason, CommandError, Event, Exception, NarrativeEvent,
    SchedulerError::{
        CommandExecutionError, TaskAbortedError, TaskAbortedException, TaskAbortedLimit,
    },
};
use moor_compiler::to_literal;
use moor_var::{List, SYSTEM_OBJECT, Symbol, v_empty_str, v_obj, v_str};
use std::{sync::LazyLock, time::SystemTime};
use tracing::{debug, error, warn};
use uuid::Uuid;

#[must_use]
pub(in crate::tasks::scheduler) struct TaskCompletion {
    dispatch: TaskDispatch,
    pub(in crate::tasks::scheduler) session: Arc<dyn Session>,
}

impl TaskCompletion {
    pub(in crate::tasks::scheduler) fn reserve(
        task_id: TaskId,
        task: &mut RunningTask,
        result: Result<Var, SchedulerError>,
    ) -> Option<Self> {
        if task.phase != RunningTaskPhase::Running {
            return None;
        }
        task.phase = RunningTaskPhase::Completing(result);
        Some(Self {
            dispatch: TaskDispatch::new(task_id, task.control.clone()),
            session: task.session.clone(),
        })
    }

    pub(in crate::tasks::scheduler) fn is_current(&self, lc: &TaskLifecycle) -> bool {
        lc.task_q.is_current_dispatch(&self.dispatch)
            && lc
                .task_q
                .active
                .get(&self.dispatch.task_id())
                .is_some_and(|task| matches!(task.phase, RunningTaskPhase::Completing(_)))
    }

    /// Session failure can replace the reserved outcome without exposing its storage to callers.
    pub(in crate::tasks::scheduler) fn finish_with_result(
        self,
        lc: &mut TaskLifecycle,
        result: Result<Var, SchedulerError>,
    ) {
        if self.is_current(lc) {
            lc.task_q
                .active
                .get_mut(&self.dispatch.task_id())
                .expect("checked current completion")
                .phase = RunningTaskPhase::Completing(result);
            self.finish(lc);
        }
    }

    pub(in crate::tasks::scheduler) fn finish(self, lc: &mut TaskLifecycle) {
        if self.is_current(lc) {
            lc.task_q.send_reserved_task_result(self.dispatch.task_id());
        }
    }
}

static HANDLE_TASK_TIMEOUT_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("handle_task_timeout"));

impl Scheduler {
    pub(crate) fn handle_task_success_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        value: Var,
        mutations_made: bool,
        timestamp: u64,
    ) {
        let task_id = dispatch.task_id();
        // Extract session under lock, then commit outside.
        let completion = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_dispatch(dispatch) {
                return;
            }

            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for success");
                return;
            };
            let Some(completion) = TaskCompletion::reserve(task_id, task, Ok(value)) else {
                return;
            };
            if mutations_made {
                lc.last_mutation_timestamp = Some(timestamp);
            }
            completion
        };

        // Session commit (potential I/O) outside the lock.
        if let Err(error) = completion.session.commit() {
            error!(
                task_id,
                boundary = "task completion",
                ?error,
                "Session commit failed after world-state commit; output may be lost"
            );
            let mut lc = self.lifecycle.lock();
            if !completion.is_current(&lc) {
                return;
            }
            lc.discard_task_effects(task_id);
            completion.finish_with_result(&mut lc, Err(TaskAbortedError));
            return lc.settle_schedule_firings();
        }

        let mut lc = self.lifecycle.lock();
        if !completion.is_current(&lc) {
            return;
        }
        lc.publish_task_effects(task_id);
        lc.task_q.remove_message_queue(task_id);
        completion.finish(&mut lc);
        lc.settle_schedule_firings();
    }

    pub(crate) fn handle_task_verb_not_found_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        who: Var,
        what: Symbol,
    ) {
        let task_id = dispatch.task_id();
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_current_dispatch(dispatch) {
            return;
        }
        let task = lc
            .task_q
            .active
            .get_mut(&task_id)
            .expect("checked current attempt");
        if let Some(completion) = TaskCompletion::reserve(
            task_id,
            task,
            Err(SchedulerError::TaskAbortedVerbNotFound(who, what)),
        ) {
            completion.finish(&mut lc);
        }
    }

    pub(crate) fn handle_task_command_error_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        error: CommandError,
    ) {
        let task_id = dispatch.task_id();
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_current_dispatch(dispatch) {
            return;
        }
        // This is a common occurrence, so we don't want to log it at warn level.
        let task = lc
            .task_q
            .active
            .get_mut(&task_id)
            .expect("checked current attempt");
        if let Some(completion) =
            TaskCompletion::reserve(task_id, task, Err(CommandExecutionError(error)))
        {
            completion.finish(&mut lc);
        }
    }

    pub(crate) fn handle_task_transaction_renewal_failed_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
    ) {
        let task_id = dispatch.task_id();
        let completion = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_dispatch(dispatch) {
                return;
            }
            let task = lc
                .task_q
                .active
                .get_mut(&task_id)
                .expect("checked current attempt");
            let Some(completion) =
                TaskCompletion::reserve(task_id, task, Err(SchedulerError::CouldNotStartTask))
            else {
                return;
            };
            completion
        };

        let session_result = completion.session.commit();
        let mut lc = self.lifecycle.lock();
        if !completion.is_current(&lc) {
            return;
        }
        // The database commit already succeeded. Preserve publication even if session commit fails.
        lc.publish_task_effects(task_id);
        lc.task_q.remove_message_queue(task_id);
        match session_result {
            Ok(()) => completion.finish(&mut lc),
            Err(error) => {
                error!(
                    task_id,
                    boundary = "transaction renewal",
                    ?error,
                    "Session commit failed after world-state commit; output may be lost"
                );
                completion.finish_with_result(&mut lc, Err(TaskAbortedError));
            }
        }
    }

    pub(crate) fn handle_task_abort_limits_reached_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        limit_info: TaskLimitInfo,
    ) {
        let task_id = dispatch.task_id();
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskAbortLimits);
        let TaskLimitInfo {
            reason: limit_reason,
            disposition,
            this,
            verb_name: verb,
            line_number,
            stack,
            backtrace,
        } = limit_info;

        // Reserve the terminal result before finalizing the session. A deadline which arrives
        // during finalization must wait for this result instead of observing a missing task.
        let (completion, player) = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_dispatch(dispatch) {
                return;
            }
            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                lc.discard_task_effects(task_id);
                lc.task_q.remove_message_queue(task_id);
                warn!(task_id, "Task not found for abort");
                return;
            };
            let Some(completion) =
                TaskCompletion::reserve(task_id, task, Err(TaskAbortedLimit(limit_reason)))
            else {
                return;
            };
            let player = task.player;

            match disposition {
                TaskLimitDisposition::Commit {
                    mutations_made,
                    timestamp,
                } => {
                    if mutations_made {
                        lc.last_mutation_timestamp = Some(timestamp);
                    }
                    lc.publish_task_effects(task_id);
                }
                TaskLimitDisposition::Rollback => lc.discard_task_effects(task_id),
            }
            lc.task_q.remove_message_queue(task_id);
            (completion, player)
        };

        let session = completion.session.clone();

        // Send the abort notification and finalize the session outside the lock.
        let abort_reason_text = match limit_reason {
            AbortLimitReason::Ticks(t) => {
                warn!(?task_id, ticks = t, "Task aborted, ticks exceeded");
                format!(
                    "Abort: Task exceeded ticks limit of {t} @ {}:{verb}:{line_number}",
                    to_literal(&this)
                )
            }
            AbortLimitReason::Time(t) => {
                warn!(?task_id, time = ?t, "Task aborted, time exceeded");
                format!("Abort: Task exceeded time limit of {t:?}")
            }
            AbortLimitReason::OutputEvents(events) => {
                warn!(
                    ?task_id,
                    events, "Task aborted, captured event count exceeded"
                );
                format!("Abort: Task exceeded captured output limit of {events} events")
            }
            AbortLimitReason::OutputBytes(bytes) => {
                warn!(?task_id, bytes, "Task aborted, captured output exceeded");
                format!("Abort: Task exceeded captured output limit of {bytes} bytes")
            }
        };

        if let Err(e) = session.send_system_msg(player, &abort_reason_text) {
            warn!("Could not send abort message to player: {e:?}");
        }

        let handler_session = session.clone().fork();
        let session_result = match disposition {
            TaskLimitDisposition::Commit { .. } => session.commit(),
            TaskLimitDisposition::Rollback => session.rollback(),
        };
        if let Err(error) = session_result {
            let action = match disposition {
                TaskLimitDisposition::Commit { .. } => "commit",
                TaskLimitDisposition::Rollback => "rollback",
            };
            error!(
                task_id,
                boundary = "task limit",
                action,
                ?error,
                "Session finalization failed after task limit"
            );
        }

        // Re-acquire lock for handler task submission.
        let mut lc = self.lifecycle.lock();
        if !completion.is_current(&lc) {
            return;
        }

        // Attempt to invoke the handler verb as a separate task.
        let resource_str = match limit_reason {
            AbortLimitReason::Ticks(_) => "ticks",
            AbortLimitReason::Time(_) => "seconds",
            AbortLimitReason::OutputEvents(_) => "output events",
            AbortLimitReason::OutputBytes(_) => "output bytes",
        };

        let handler_args = List::from_iter(vec![
            v_str(resource_str),
            List::from_iter(stack).into(),
            List::from_iter(backtrace).into(),
        ]);

        let handler_task_start = TaskStart::StartVerb {
            player,
            vloc: v_obj(SYSTEM_OBJECT),
            verb: *HANDLE_TASK_TIMEOUT_SYM,
            args: handler_args,
            argstr: v_empty_str(),
        };

        let handler_task_id = lc.next_task_id;
        lc.next_task_id += 1;

        debug!(
            "Spawning handler task {} for timeout on task {}",
            handler_task_id, task_id
        );

        let handler_session = handler_session.unwrap_or_else(|error| {
            warn!(
                task_id,
                ?error,
                "Could not fork session for task-limit handler"
            );
            session.clone()
        });
        let handler_result = self.submit_task(
            &mut lc,
            handler_task_id,
            &player,
            &player,
            handler_task_start,
            None,
            handler_session,
        );

        match handler_result {
            Ok(_) => {
                debug!("Handler task {} started successfully", handler_task_id);
            }
            Err(e) => {
                warn!("Failed to start handler task: {:?}", e);
            }
        }

        // Report the original task as aborted (handler outcome doesn't affect this).
        completion.finish(&mut lc);
    }

    pub(crate) fn handle_task_exception_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        exception: Box<Exception>,
    ) {
        let task_id = dispatch.task_id();
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskException);
        let completion = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_dispatch(dispatch) {
                return;
            }
            let task = lc
                .task_q
                .active
                .get_mut(&task_id)
                .expect("checked current attempt");
            let Some(completion) = TaskCompletion::reserve(
                task_id,
                task,
                Err(TaskAbortedException(exception.as_ref().clone())),
            ) else {
                return;
            };
            if let Err(send_error) = completion.session.send_event(
                task.player,
                Box::new(NarrativeEvent {
                    event_id: Uuid::now_v7(),
                    timestamp: SystemTime::now(),
                    author: v_obj(task.player),
                    event: Event::Traceback(exception.as_ref().clone()),
                }),
            ) {
                warn!("Could not send traceback to player: {:?}", send_error);
            }
            completion
        };

        // Exception policy publishes after the session commit attempt, including session failure.
        let _ = completion.session.commit();
        let mut lc = self.lifecycle.lock();
        if !completion.is_current(&lc) {
            return;
        }
        lc.publish_task_effects(task_id);
        lc.task_q.remove_message_queue(task_id);
        completion.finish(&mut lc);
        lc.settle_schedule_firings();
    }

    pub(crate) fn handle_task_commit_rejected_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        exception: Box<Exception>,
    ) {
        let task_id = dispatch.task_id();
        let completion = {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_current_dispatch(dispatch) {
                return;
            }
            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found after database commit rejection");
                return;
            };
            let Some(completion) = TaskCompletion::reserve(
                task_id,
                task,
                Err(TaskAbortedException(exception.as_ref().clone())),
            ) else {
                return;
            };
            lc.discard_task_effects(task_id);
            lc.task_q.remove_message_queue(task_id);
            completion
        };

        if let Err(error) = completion.session.rollback() {
            warn!(
                task_id,
                ?error,
                "Could not roll back session after database commit rejection"
            );
        }

        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_current_dispatch(dispatch) {
            return;
        }
        completion.finish(&mut lc);
    }
}

#[cfg(test)]
mod tests;
