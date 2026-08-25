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

use std::time::SystemTime;

use crate::{
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
use moor_var::{Error, Obj, Symbol, Var};

use crate::tasks::scheduler::Scheduler;

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
/// Wraps a Scheduler + TaskId; all methods are direct calls.
#[derive(Clone)]
pub struct TaskSchedulerClient {
    task_id: TaskId,
    scheduler: Scheduler,
}

impl TaskSchedulerClient {
    pub fn new(task_id: TaskId, scheduler: Scheduler) -> Self {
        Self { task_id, scheduler }
    }

    pub fn success(&self, var: Var, mutations: bool, timestamp: u64) {
        self.scheduler
            .handle_task_success(self.task_id, var, mutations, timestamp);
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
        self.scheduler
            .handle_task_command_error(self.task_id, error);
    }

    pub fn verb_not_found(&self, what: Var, verb: Symbol) {
        self.scheduler
            .handle_task_verb_not_found(self.task_id, what, verb);
    }

    pub fn exception(&self, exception: Box<Exception>) {
        self.scheduler
            .handle_task_exception(self.task_id, exception);
    }

    pub fn request_fork(&self, fork: Box<Fork>) -> TaskId {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskRequestForkLatency);
        self.scheduler.handle_task_request_fork(self.task_id, fork)
    }

    pub fn abort_cancelled(&self) {
        self.scheduler.handle_task_abort_cancelled(self.task_id);
    }

    pub fn abort_transaction_renewal_failed(&self) {
        self.scheduler
            .handle_task_transaction_renewal_failed(self.task_id);
    }

    pub(crate) fn abort_limits_reached(&self, limit_info: TaskLimitInfo) {
        self.scheduler
            .handle_task_abort_limits_reached(self.task_id, limit_info);
    }

    pub(crate) fn rollback_on_task_limit(&self) -> bool {
        self.scheduler.rollback_on_task_limit()
    }

    pub fn suspend(&self, resume_condition: TaskSuspend, task: Box<Task>) {
        self.scheduler
            .handle_task_suspend(self.task_id, resume_condition, task);
    }

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
        self.scheduler
            .handle_kill_task(self.task_id, victim_task_id, sender_authority)
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
        self.scheduler.handle_resume_task(
            self.task_id,
            queued_task_id,
            sender_authority,
            return_value,
        )
    }

    pub fn boot_player(&self, player: Obj) {
        self.scheduler.handle_boot_player(self.task_id, player);
    }

    pub fn checkpoint(&self) {
        let _ = self
            .scheduler
            .handle_checkpoint_from_task(self.task_id, false);
    }

    pub fn checkpoint_with_blocking(&self, blocking: bool) -> Result<(), SchedulerError> {
        let _timer = sched_counters()
            .timers
            .start(SchedulerOp::TaskCheckpointLatency);
        self.scheduler
            .handle_checkpoint_from_task(self.task_id, blocking)
    }

    pub fn notify(&self, player: Obj, event: Box<NarrativeEvent>) {
        self.scheduler.handle_notify(self.task_id, player, event);
    }

    pub fn log_event(&self, player: Obj, event: Box<NarrativeEvent>) {
        self.scheduler.handle_log_event(self.task_id, player, event);
    }

    pub fn listen(
        &self,
        handler_object: Obj,
        host_type: String,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Option<Error> {
        self.scheduler
            .handle_listen(self.task_id, handler_object, host_type, port, options)
    }

    pub fn listeners(&self) -> Vec<ListenerInfo> {
        self.scheduler.handle_get_listeners()
    }

    pub fn unlisten(&self, host_type: String, port: u16) -> Option<Error> {
        self.scheduler
            .handle_unlisten(self.task_id, host_type, port)
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
        self.scheduler.handle_force_input(self.task_id, who, line)
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
        self.scheduler.handle_switch_player_from_task(
            self.task_id,
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
        self.scheduler.handle_request_new_transaction(self.task_id)
    }

    pub fn task_send(
        &self,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        self.scheduler
            .handle_task_send(self.task_id, target_task_id, value, sender_authority)
    }

    pub fn task_recv(&self) -> Vec<Var> {
        self.scheduler.handle_task_recv(self.task_id)
    }

    pub fn force_gc(&self) {
        self.scheduler.handle_force_gc();
    }
}

pub type ActiveTaskDescriptions = Vec<(TaskId, Obj, TaskStart)>;

// TaskStart re-exported for the type alias above
use crate::tasks::TaskStart;
