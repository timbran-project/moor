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

use std::{sync::Arc, time::SystemTime};

use crate::{
    task_context::with_current_session,
    tasks::{
        SchedulerOp, TaskDescription, sched_counters, task::Task, task_telemetry::TaskTelemetry,
    },
    vm::{Fork, TaskSuspend},
};
use moor_common::{
    model::{ConflictInfo, TaskPermissions, WorldState},
    tasks::{
        AbortLimitReason, CommandError, EventLogPurgeResult, EventLogStats, Exception,
        ListenerInfo, NarrativeEvent, SchedulerError, TaskId,
    },
};
use moor_var::{E_INVARG, E_INVIND, Error, List, Obj, Symbol, Var, v_err};

use crate::tasks::{scheduler::Scheduler, task_control::TaskControl, task_q::TaskAttempt};

pub use moor_common::tasks::WorkerInfo;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum TaskLimitDisposition {
    Commit {
        mutations_made: bool,
        timestamp: u64,
    },
    Rollback,
}

/// Information needed to finalize a task that reached a tick or time limit.
pub(crate) struct TaskLimitInfo {
    pub(crate) reason: AbortLimitReason,
    pub(crate) disposition: TaskLimitDisposition,
    pub(crate) this: Var,
    pub(crate) verb_name: Symbol,
    pub(crate) line_number: usize,
    pub(crate) stack: Vec<Var>,
    pub(crate) backtrace: Vec<Var>,
}

/// A handle for talking to the scheduler from within a task.
/// Direct calls retain the worker dispatch identity across transaction callbacks.
#[derive(Clone)]
pub struct TaskSchedulerClient {
    task_id: TaskId,
    attempt: Option<TaskAttempt>,
    scheduler: Scheduler,
}

impl TaskSchedulerClient {
    /// Bind callbacks to the active attempt at construction. A client without an active attempt
    /// can still make independent queries, but cannot complete a task registered later.
    pub fn new(task_id: TaskId, scheduler: Scheduler) -> Self {
        let attempt = scheduler.capture_task_attempt(task_id);
        Self {
            task_id,
            attempt,
            scheduler,
        }
    }

    /// Dispatch already holds the lifecycle lock; use the worker's control without another lock.
    pub(crate) fn for_attempt(
        task_id: TaskId,
        scheduler: Scheduler,
        control: Arc<TaskControl>,
    ) -> Self {
        Self {
            task_id,
            attempt: Some(TaskAttempt::new(task_id, control)),
            scheduler,
        }
    }

    pub fn success(&self, var: Var, mutations: bool, timestamp: u64) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_success_for_attempt(attempt, var, mutations, timestamp);
        }
    }

    pub fn conflict_retry(
        &self,
        task: Box<Task>,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) {
        self.scheduler
            .handle_task_conflict_retry(self.task_id, task, boundary, conflict_info);
    }

    pub fn command_error(&self, error: CommandError) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_command_error_for_attempt(attempt, error);
        }
    }

    pub fn verb_not_found(&self, what: Var, verb: Symbol) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_verb_not_found_for_attempt(attempt, what, verb);
        }
    }

    pub fn exception(&self, exception: Box<Exception>) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_exception_for_attempt(attempt, exception);
        }
    }

    pub fn commit_rejected(&self, exception: Box<Exception>) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_commit_rejected_for_attempt(attempt, exception);
        }
    }

    pub fn request_fork(&self, fork: Box<Fork>) -> TaskId {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskRequestForkLatency);
        self.attempt.as_ref().map_or(0, |attempt| {
            self.scheduler
                .handle_task_request_fork_for_attempt(attempt, fork)
        })
    }

    pub fn abort_cancelled(&self) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_abort_cancelled_for_attempt(attempt);
        }
    }

    pub fn abort_transaction_renewal_failed(&self) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_transaction_renewal_failed_for_attempt(attempt);
        }
    }

    pub(crate) fn abort_limits_reached(&self, limit_info: TaskLimitInfo) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_abort_limits_reached_for_attempt(attempt, limit_info);
        }
    }

    pub(crate) fn abort_panicked(&self, message: String, backtrace: std::backtrace::Backtrace) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_task_abort_panicked_for_attempt(attempt, message, backtrace);
        }
    }

    pub(crate) fn rollback_on_task_limit(&self) -> bool {
        self.scheduler.rollback_on_task_limit()
    }

    /// Hand off a task after its database boundary. The owned task carries the commit proof.
    pub fn suspend(&self, resume_condition: TaskSuspend, task: Box<Task>) {
        self.scheduler
            .handle_task_suspend(self.task_id, resume_condition, task);
    }

    /// Hand off an input request after the task's database boundary.
    pub fn request_input(
        &self,
        task: Box<Task>,
        input_player: Obj,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) {
        self.scheduler
            .handle_task_request_input(self.task_id, task, input_player, metadata);
    }

    pub fn task_list(&self) -> Vec<TaskDescription> {
        self.scheduler.handle_request_tasks(self.task_id)
    }

    #[inline]
    pub fn task_exists(&self, task_id: TaskId) -> bool {
        self.scheduler.handle_task_exists(task_id)
    }

    pub fn kill_task(&self, victim_task_id: TaskId, sender_authority: TaskPermissions) -> Var {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskKillTaskLatency);
        let Some(attempt) = &self.attempt else {
            return v_err(E_INVARG);
        };
        self.scheduler
            .handle_kill_task_for_attempt(attempt, victim_task_id, sender_authority)
    }

    pub fn resume_task(
        &self,
        queued_task_id: TaskId,
        sender_authority: TaskPermissions,
        return_value: Var,
    ) -> Var {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskResumeTaskLatency);
        let Some(attempt) = &self.attempt else {
            return v_err(E_INVARG);
        };
        self.scheduler.handle_resume_task_for_attempt(
            attempt,
            queued_task_id,
            sender_authority,
            return_value,
        )
    }

    pub fn boot_player(&self, player: Obj) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_boot_player_for_attempt(attempt, player);
        }
    }

    pub fn checkpoint(&self) -> Result<(), SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskCheckpointLatency);
        self.scheduler.handle_checkpoint_from_task(self.task_id)
    }

    pub fn notify(&self, player: Obj, event: Box<NarrativeEvent>) {
        let result = with_current_session(|session| session.send_event(player, event));
        if let Err(error) = result
            && let Some(attempt) = &self.attempt
        {
            self.scheduler
                .handle_notify_error_for_attempt(attempt, error);
        }
    }

    pub fn log_event(&self, player: Obj, event: Box<NarrativeEvent>) {
        if let Some(attempt) = &self.attempt {
            self.scheduler
                .handle_log_event_for_attempt(attempt, player, event);
        }
    }

    pub fn listen(
        &self,
        handler_object: Obj,
        host_type: String,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Option<Error> {
        let Some(attempt) = &self.attempt else {
            return Some(E_INVARG.msg("Task not found"));
        };
        self.scheduler
            .handle_listen_for_attempt(attempt, handler_object, host_type, port, options)
    }

    pub fn listeners(&self) -> Vec<ListenerInfo> {
        self.scheduler.handle_get_listeners()
    }

    pub fn unlisten(&self, host_type: String, port: u16) -> Option<Error> {
        let Some(attempt) = &self.attempt else {
            return Some(E_INVARG.msg("Task not found"));
        };
        self.scheduler
            .handle_unlisten_for_attempt(attempt, host_type, port)
    }

    pub fn refresh_server_options(&self) {
        self.scheduler.handle_refresh_server_options();
    }

    pub fn shutdown(&self, msg: Option<String>) {
        self.scheduler.handle_shutdown(msg);
    }

    pub fn rotate_enrollment_token(&self) -> Result<String, Error> {
        self.scheduler.handle_rotate_enrollment_token()
    }

    pub fn player_event_log_stats(
        &self,
        player: Obj,
        since: Option<SystemTime>,
        until: Option<SystemTime>,
    ) -> Result<EventLogStats, Error> {
        self.scheduler
            .handle_player_event_log_stats(player, since, until)
    }

    pub fn purge_player_event_log(
        &self,
        player: Obj,
        before: Option<SystemTime>,
        drop_pubkey: bool,
    ) -> Result<EventLogPurgeResult, Error> {
        self.scheduler
            .handle_purge_player_event_log(player, before, drop_pubkey)
    }

    pub fn force_input(&self, who: Obj, line: String) -> Result<TaskId, Error> {
        let Some(attempt) = &self.attempt else {
            return Err(E_INVIND.msg("Task not found"));
        };
        self.scheduler
            .handle_force_input_for_attempt(attempt, who, line)
    }

    pub fn active_tasks(&self) -> Result<ActiveTaskDescriptions, Error> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskActiveTasksLatency);
        self.scheduler.handle_active_tasks(self.task_id)
    }

    pub fn task_telemetry(&self, task_id: Option<TaskId>) -> Vec<TaskTelemetry> {
        self.scheduler.handle_task_telemetry(task_id)
    }

    pub fn switch_player(
        &self,
        source: Option<Obj>,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), Error> {
        let Some(attempt) = &self.attempt else {
            return Err(E_INVARG.msg("Task not found for switch_player"));
        };
        self.scheduler.handle_switch_player_for_attempt(
            attempt,
            source,
            new_player,
            silent,
            preserve_history,
        )
    }

    pub fn dump_object(&self, obj: Obj, use_constants: bool) -> Result<Vec<Var>, Error> {
        self.scheduler
            .handle_dump_object_from_task(obj, use_constants)
    }

    pub fn workers_info(&self) -> Vec<WorkerInfo> {
        self.scheduler
            .system_control
            .workers_info()
            .unwrap_or_default()
    }

    pub fn begin_new_transaction(&self) -> Result<Box<dyn WorldState>, SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskBeginTransactionLatency);
        self.scheduler
            .handle_request_new_transaction_for_attempt(self.attempt.as_ref())
    }

    pub fn task_send(
        &self,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        let Some(attempt) = &self.attempt else {
            return v_err(E_INVARG);
        };
        self.scheduler.handle_task_send_for_attempt(
            attempt,
            target_task_id,
            value,
            sender_authority,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn schedule_create(
        &self,
        kind: crate::tasks::schedule_q::PendingKind,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: crate::tasks::schedule_q::ScheduleOptions,
    ) -> Result<crate::tasks::schedule_q::ScheduleId, crate::tasks::schedule_q::ScheduleError> {
        self.scheduler.handle_schedule_create_for_attempt(
            self.attempt.as_ref(),
            kind,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
        )
    }

    pub fn schedule_stop(
        &self,
        schedule_id: crate::tasks::schedule_q::ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<bool, moor_var::Error> {
        self.attempt.as_ref().map_or(Ok(false), |attempt| {
            self.scheduler
                .handle_schedule_stop_for_attempt(attempt, schedule_id, authority)
        })
    }

    pub fn schedule_valid(&self, schedule_id: crate::tasks::schedule_q::ScheduleId) -> bool {
        self.scheduler
            .handle_schedule_valid_for_attempt(self.attempt.as_ref(), schedule_id)
    }

    pub fn schedule_info(
        &self,
        schedule_id: crate::tasks::schedule_q::ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<Var, moor_var::Error> {
        self.scheduler.handle_schedule_info(schedule_id, authority)
    }

    pub fn schedules(&self, owner: Option<Obj>, authority: &TaskPermissions) -> Vec<i64> {
        self.scheduler.handle_schedules(owner, authority)
    }

    pub fn schedules_for(&self, target: Obj) -> Vec<i64> {
        self.scheduler.handle_schedules_for(target)
    }

    pub fn task_recv(&self) -> Vec<Var> {
        self.attempt.as_ref().map_or_else(Vec::new, |attempt| {
            self.scheduler.handle_task_recv_for_attempt(attempt)
        })
    }

    pub fn force_gc(&self) {
        self.scheduler.handle_force_gc();
    }
}

pub type ActiveTaskDescriptions = Vec<(TaskId, Obj, TaskStart)>;

// TaskStart re-exported for the type alias above
use crate::tasks::TaskStart;
