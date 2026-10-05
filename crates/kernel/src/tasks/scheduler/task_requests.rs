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

//! Scheduler queries, host operations, and object import/export requests.
//!
//! Task queries acquire the lifecycle lock to inspect active metadata. Object operations use
//! database interfaces directly; each retains its existing transaction and permission policy.
//! Worker requests carry dispatch identity into each borrow of active metadata. Public task-ID
//! entry points select the current registration. Session calls retain their existing lock scopes.
//! Host listener and player-switch I/O run outside the lock. A successful host action remains
//! committed if the caller disappears; player-switch completion rechecks its dispatch before it
//! updates task or session metadata.

use crate::{
    tasks::{
        SchedulerOp, TaskDescription, TaskStart,
        registry::TaskDispatch,
        sched_counters,
        scheduler::{Scheduler, lifecycle::TaskLifecycle},
        task_scheduler_client::ActiveTaskDescriptions,
        task_telemetry::{TaskTelemetry, TaskTelemetrySource},
    },
    vm::Fork,
};
use moor_common::{
    model::{TaskPermissions, WorldState},
    tasks::{
        AbortLimitReason, EventLogPurgeResult, EventLogStats, ListenerInfo, NarrativeEvent,
        SchedulerError,
        SchedulerError::{TaskAbortedError, TaskAbortedLimit},
        SessionError, TaskId,
    },
};
use moor_objdef::{collect_index_names, collect_object, dump_object};
use moor_var::{E_INVARG, E_PERM, E_QUOTA, Error, Obj, Symbol, Var, v_err, v_error, v_int};
use std::{
    collections::HashMap,
    time::{Duration, SystemTime},
};
use tracing::{debug, error, info, warn};

impl Scheduler {
    /// Dumps an object's definition to a list of strings for export.
    ///
    /// Creates a database snapshot to avoid blocking ongoing operations, collects
    /// the object definition, and optionally builds index names from import_export_id
    /// metadata when `use_constants` is true.
    ///
    /// # Arguments
    /// * `obj` - The object to dump
    /// * `use_constants` - If true, builds index names from all object definitions
    ///
    /// # Returns
    /// A vector of string Vars representing the object's definition, or an error
    pub(crate) fn handle_dump_object(
        &self,
        obj: Obj,
        use_constants: bool,
    ) -> Result<Vec<Var>, Error> {
        // Create a snapshot to avoid blocking ongoing operations
        let snapshot = self.database.create_snapshot().map_err(|e| {
            E_INVARG.with_msg(|| format!("Failed to create database snapshot: {e:?}"))
        })?;

        // Collect the object definition
        let (_, _, _, object_def) = collect_object(snapshot.as_ref(), &obj)
            .map_err(|e| E_INVARG.with_msg(|| format!("Failed to collect object {obj}: {e:?}")))?;

        // Build index_names from import_export_id metadata if requested
        let index_names = if use_constants {
            collect_index_names(snapshot.as_ref()).map_err(|e| {
                E_INVARG.with_msg(|| format!("Failed to collect object constants: {e:?}"))
            })?
        } else {
            HashMap::new()
        };

        let lines = dump_object(&index_names, &object_def)
            .map_err(|e| E_INVARG.with_msg(|| format!("Failed to dump object {obj}: {e:?}")))?;

        Ok(lines)
    }

    /// Loads an object definition into the database.
    ///
    /// Creates a new world state, initializes an object definition loader,
    /// and loads a single object from the provided definition string.
    /// Commits the transaction if the loader result indicates success.
    ///
    /// # Arguments
    /// * `object_definition` - The object definition string to load
    /// * `options` - Loader options controlling the load behavior
    /// * `_return_conflicts` - Whether to return conflict information (unused)
    ///
    /// # Returns
    /// The loader results containing loaded object information, or a SchedulerError
    pub(crate) fn handle_load_object(
        &self,
        object_definition: String,
        options: moor_objdef::ObjDefLoaderOptions,
        _return_conflicts: bool,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        use moor_objdef::ObjectDefinitionLoader;

        // Create a new world state for loading
        let world_state = self
            .database
            .new_world_state()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        let mut loader = Box::new(world_state)
            .as_loader_interface()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        let mut object_loader = ObjectDefinitionLoader::new(loader.as_mut());

        // Load the object with the provided options
        let compile_options = self.config.features.compile_options();

        let result = object_loader
            .load_single_object(&object_definition, compile_options, options)
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        // Commit the transaction if the result says we should
        if result.commit {
            loader
                .commit()
                .map_err(|_| SchedulerError::CouldNotStartTask)?;
        }

        Ok(result)
    }

    /// Reloads an object definition, updating an existing object in the database.
    ///
    /// Creates a new world state, initializes an object definition loader,
    /// and reloads a single object from the provided definition string.
    /// Unlike load, this always commits the transaction (no dry-run mode).
    ///
    /// # Arguments
    /// * `object_definition` - The object definition string to reload
    /// * `constants` - Optional constants to use during reload
    /// * `target_obj` - Optional target object to reload into
    ///
    /// # Returns
    /// The loader results containing reloaded object information, or a SchedulerError
    pub(crate) fn handle_reload_object(
        &self,
        object_definition: String,
        constants: Option<moor_objdef::Constants>,
        target_obj: Option<Obj>,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        use moor_objdef::ObjectDefinitionLoader;

        // Create a new world state for reloading
        let world_state = self
            .database
            .new_world_state()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        let mut loader = Box::new(world_state)
            .as_loader_interface()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        let mut object_loader = ObjectDefinitionLoader::new(loader.as_mut());

        // Reload the object with the provided constants and target
        let result = object_loader
            .reload_single_object(&object_definition, constants, target_obj)
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        // Always commit for reload operations (they don't have dry-run mode)
        loader
            .commit()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        Ok(result)
    }

    pub fn handle_task_request_fork(&self, task_id: TaskId, fork_request: Box<Fork>) -> TaskId {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return 0;
        };
        self.handle_task_request_fork_for_dispatch(&dispatch, fork_request)
    }

    pub(crate) fn handle_task_request_fork_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        fork_request: Box<Fork>,
    ) -> TaskId {
        let task_id = dispatch.task_id();
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::ForkTask);

        let mut lc = self.lifecycle.lock();

        // Task has requested a fork. Dispatch it and reply with the new task id.
        let new_session = {
            let Some(task) = lc.task_q.running_dispatch_mut(dispatch) else {
                warn!(task_id, "Task not found for fork request");
                // Return a sentinel; caller should handle missing task.
                return 0;
            };
            task.session.clone()
        };

        // Fork the session.
        let forked_session = new_session.fork().unwrap();

        let suspended = fork_request.delay.is_some();
        let player = fork_request.player;
        let delay = fork_request.delay;
        let progr = fork_request.progr;

        let task_start = TaskStart::StartFork {
            fork_request,
            suspended,
        };
        let new_task_id = lc.next_task_id;
        lc.next_task_id += 1;
        if let Err(e) = self.submit_task(
            &mut lc,
            new_task_id,
            &player,
            &progr,
            task_start,
            delay,
            forked_session,
        ) {
            error!(?e, "Could not fork task");
        }

        new_task_id
    }

    pub fn handle_request_tasks(&self, _task_id: TaskId) -> Vec<TaskDescription> {
        let lc = self.lifecycle.lock();
        lc.task_q.suspended.tasks()
        // TODO: add non-queued tasks.
    }

    #[inline]
    pub fn handle_task_exists(&self, check_task_id: TaskId) -> bool {
        self.live_tasks.contains(check_task_id)
    }

    pub fn handle_boot_player(&self, task_id: TaskId, player: Obj) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_boot_player_for_dispatch(&dispatch, player)
    }

    pub(crate) fn handle_boot_player_for_dispatch(&self, dispatch: &TaskDispatch, player: Obj) {
        let task_id = dispatch.task_id();
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_dispatch(dispatch) {
            return;
        }
        // Task is asking to boot a player.
        lc.task_q.disconnect_task(task_id, &player);
    }

    pub fn handle_notify_error(&self, task_id: TaskId, error: SessionError) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_notify_error_for_dispatch(&dispatch, error)
    }

    pub(crate) fn handle_notify_error_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        error: SessionError,
    ) {
        let task_id = dispatch.task_id();
        let mut lc = self.lifecycle.lock();
        let Some(task) = lc.task_q.running_dispatch_mut(dispatch) else {
            debug!(
                task_id,
                ?error,
                "Ignoring session error from cancelled task"
            );
            return;
        };
        warn!(?error, "Could not notify player; cancelling task");
        let scheduler_error = match error {
            SessionError::OutputEventLimitExceeded(limit) => {
                TaskAbortedLimit(AbortLimitReason::OutputEvents(limit))
            }
            SessionError::OutputByteLimitExceeded(limit) => {
                TaskAbortedLimit(AbortLimitReason::OutputBytes(limit))
            }
            _ => TaskAbortedError,
        };
        task.abort_error = Some(scheduler_error);
        task.control.request_cancel();
    }

    pub fn handle_log_event(&self, task_id: TaskId, player: Obj, event: Box<NarrativeEvent>) {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return;
        };
        self.handle_log_event_for_dispatch(&dispatch, player, event)
    }

    pub(crate) fn handle_log_event_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        player: Obj,
        event: Box<NarrativeEvent>,
    ) {
        let task_id = dispatch.task_id();
        let mut lc = self.lifecycle.lock();
        // Task is asking to log an event without broadcasting.
        let Some(task) = lc.task_q.running_dispatch_mut(dispatch) else {
            warn!(task_id, "Task not found for log_event request");
            return;
        };
        let Ok(()) = task.session.log_event(player, event) else {
            warn!("Could not log event; aborting task");
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        };
    }

    pub fn handle_get_listeners(&self) -> Vec<ListenerInfo> {
        self.system_control
            .listeners()
            .expect("Could not get listeners")
    }

    pub fn handle_listen(
        &self,
        task_id: TaskId,
        handler_object: Obj,
        host_type: String,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Option<Error> {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return Some(E_INVARG.msg("Task not found"));
        };
        self.handle_listen_for_dispatch(&dispatch, handler_object, host_type, port, options)
    }

    pub(crate) fn handle_listen_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        handler_object: Obj,
        host_type: String,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Option<Error> {
        let task_id = dispatch.task_id();
        let lc = self.lifecycle.lock();
        let Some(_task) = lc.task_q.running_dispatch(dispatch) else {
            warn!(task_id, "Task not found for listen request");
            return Some(E_INVARG.msg("Task not found"));
        };
        drop(lc);

        self.system_control
            .listen(handler_object, &host_type, port, options)
            .err()
    }

    pub fn handle_unlisten(&self, task_id: TaskId, host_type: String, port: u16) -> Option<Error> {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return Some(E_INVARG.msg("Task not found"));
        };
        self.handle_unlisten_for_dispatch(&dispatch, host_type, port)
    }

    pub(crate) fn handle_unlisten_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        host_type: String,
        port: u16,
    ) -> Option<Error> {
        let task_id = dispatch.task_id();
        let lc = self.lifecycle.lock();
        let Some(_task) = lc.task_q.running_dispatch(dispatch) else {
            warn!(task_id, "Task not found for unlisten request");
            return Some(E_INVARG.msg("Task not found"));
        };
        drop(lc);

        match self.system_control.unlisten(port, &host_type) {
            Ok(_) => None,
            Err(_) => Some(E_PERM.msg("Permission denied on unlisten")),
        }
    }

    pub fn handle_refresh_server_options(&self) {
        self.reload_server_options();
    }

    pub fn handle_shutdown(&self, msg: Option<String>) {
        info!("Shutting down scheduler. Reason: {msg:?}");
        let scheduler = self.clone();
        if let Err(e) = std::thread::Builder::new()
            .name("moor-scheduler-shutdown".to_string())
            .spawn(move || {
                if let Err(e) = scheduler.stop(msg) {
                    error!(error = ?e, "Could not shutdown scheduler cleanly");
                }
            })
        {
            error!(error = ?e, "Could not start scheduler shutdown thread");
        }
    }

    pub fn handle_active_tasks(&self, _task_id: TaskId) -> Result<ActiveTaskDescriptions, Error> {
        let lc = self.lifecycle.lock();
        let mut results = vec![];
        for (task_id, tc) in lc.task_q.active.iter() {
            results.push((*task_id, tc.player, tc.task_start.clone()));
        }
        Ok(results)
    }

    pub fn handle_task_telemetry(&self, task_id: Option<TaskId>) -> Vec<TaskTelemetry> {
        let sources: Vec<_> = {
            let lc = self.lifecycle.lock();
            lc.task_q
                .active
                .iter()
                .filter(|(active_task_id, _)| {
                    task_id.is_none_or(|task_id| task_id == **active_task_id)
                })
                .map(|(task_id, task)| TaskTelemetrySource {
                    task_id: *task_id,
                    player: task.player,
                    dispatched_at: task.dispatched_at,
                    baseline: task.run_baseline.get().cloned(),
                })
                .collect()
        };

        // Procfs reads can fault or block. Keep them outside the scheduler lifecycle lock.
        let samples: Vec<_> = sources.iter().map(TaskTelemetrySource::sample).collect();

        let lc = self.lifecycle.lock();
        sources
            .into_iter()
            .zip(samples)
            .filter_map(|(source, sample)| {
                let active = lc.task_q.active.get(&source.task_id)?;
                if active.run_baseline.get() != source.baseline.as_ref() {
                    return None;
                }
                Some(sample)
            })
            .collect()
    }

    pub fn handle_checkpoint_from_task(&self, _task_id: TaskId) -> Result<(), SchedulerError> {
        self.checkpoint()
    }

    pub fn handle_task_send(
        &self,
        task_id: TaskId,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        self.buffer_task_message(&mut lc, task_id, target_task_id, value, sender_authority)
    }

    pub(crate) fn handle_task_send_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_dispatch(dispatch) {
            return v_err(E_INVARG);
        }
        self.buffer_task_message(
            &mut lc,
            dispatch.task_id(),
            target_task_id,
            value,
            sender_authority,
        )
    }

    // The caller holds the lifecycle lock through identity validation and buffer mutation.
    fn buffer_task_message(
        &self,
        lc: &mut TaskLifecycle,
        task_id: TaskId,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        if let Err(error) = lc
            .task_q
            .require_task_send_authority(target_task_id, sender_authority)
        {
            return match error {
                E_INVARG => v_error(
                    E_INVARG
                        .with_msg(|| format!("Task ({target_task_id}) not found for task_send")),
                ),
                E_PERM => v_error(E_PERM.with_msg(|| {
                    format!("Permission denied for task_send to task ({target_task_id})")
                })),
                _ => v_err(error),
            };
        }

        // Check mailbox size limit (committed queue + pending sends
        // from this task to same target)
        let committed_len = lc.task_q.mailbox_len(target_task_id);
        let pending_len = lc
            .task_q
            .active
            .get(&task_id)
            .map_or(0, |task| task.effects.messages_for(target_task_id));
        if committed_len + pending_len >= self.server_options.load().max_task_mailbox {
            return v_error(E_QUOTA.with_msg(|| {
                format!(
                    "Task mailbox full ({} messages) for task ({target_task_id})",
                    committed_len + pending_len
                )
            }));
        }

        // Buffer the message for delivery at commit time
        if let Some(task) = lc.task_q.active.get_mut(&task_id) {
            task.effects.send(target_task_id, value);
        }

        v_int(0)
    }

    pub fn handle_task_recv(&self, task_id: TaskId) -> Vec<Var> {
        Self::drain_task_messages(&mut self.lifecycle.lock(), task_id)
    }

    pub(crate) fn handle_task_recv_for_dispatch(&self, dispatch: &TaskDispatch) -> Vec<Var> {
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_dispatch(dispatch) {
            return vec![];
        }
        Self::drain_task_messages(&mut lc, dispatch.task_id())
    }

    fn drain_task_messages(lc: &mut TaskLifecycle, task_id: TaskId) -> Vec<Var> {
        // Drain all messages from the calling task's queue
        let (messages, total_wait_nanos, message_count) =
            lc.task_q.drain_messages_with_wait_nanos(task_id);
        if message_count > 0 {
            let perfc = sched_counters();
            perfc.timers.record_elapsed(
                SchedulerOp::TaskMessageDeliveryToRecvLatency,
                Duration::from_nanos(total_wait_nanos as u64),
            );
        }
        messages
    }

    pub fn handle_force_gc(&self) {
        info!("Forcing garbage collection via gc_collect() builtin");
        if !self.config.features.anonymous_objects {
            warn!("GC force requested but anonymous objects are disabled, ignoring request");
        } else {
            {
                let mut lc = self.lifecycle.lock();
                lc.gc_force_collect = true;
            }
            self.wake_timer_thread();
        }
    }

    pub fn handle_rotate_enrollment_token(&self) -> Result<String, Error> {
        self.system_control.rotate_enrollment_token()
    }

    pub fn handle_player_event_log_stats(
        &self,
        player: Obj,
        since: Option<SystemTime>,
        until: Option<SystemTime>,
    ) -> Result<EventLogStats, Error> {
        self.system_control
            .player_event_log_stats(player, since, until)
    }

    pub fn handle_purge_player_event_log(
        &self,
        player: Obj,
        before: Option<SystemTime>,
        drop_pubkey: bool,
    ) -> Result<EventLogPurgeResult, Error> {
        self.system_control
            .purge_player_event_log(player, before, drop_pubkey)
    }

    pub fn handle_request_new_transaction(
        &self,
        task_id: TaskId,
    ) -> Result<Box<dyn WorldState>, SchedulerError> {
        let dispatch = self.capture_task_dispatch(task_id);
        self.handle_request_new_transaction_for_dispatch(dispatch.as_ref())
    }

    /// Publish one dispatch's effects and open its next transaction.
    /// Unregistered VM clients can open world state, but have no effects to publish.
    pub(crate) fn handle_request_new_transaction_for_dispatch(
        &self,
        dispatch: Option<&TaskDispatch>,
    ) -> Result<Box<dyn WorldState>, SchedulerError> {
        if let Some(dispatch) = dispatch {
            let mut lc = self.lifecycle.lock();
            if !lc.task_q.is_running_dispatch(dispatch) {
                return Err(SchedulerError::CouldNotStartTask);
            }
            lc.publish_task_effects(dispatch.task_id());
        }

        let transaction = self
            .database
            .new_world_state()
            .map_err(|_| SchedulerError::CouldNotStartTask)?;

        // Opening world state runs without the lifecycle lock. Revalidate before returning it.
        let stale = dispatch
            .is_some_and(|dispatch| !self.lifecycle.lock().task_q.is_running_dispatch(dispatch));
        if stale {
            if let Err(error) = transaction.rollback() {
                warn!(
                    ?error,
                    "Could not roll back transaction opened for a replaced task"
                );
            }
            return Err(SchedulerError::CouldNotStartTask);
        }
        Ok(transaction)
    }

    pub fn handle_dump_object_from_task(
        &self,
        obj: Obj,
        use_constants: bool,
    ) -> Result<Vec<Var>, Error> {
        self.handle_dump_object(obj, use_constants)
    }

    pub fn handle_switch_player_from_task(
        &self,
        task_id: TaskId,
        source: Option<Obj>,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), Error> {
        let Some(dispatch) = self.capture_task_dispatch(task_id) else {
            return Err(E_INVARG.msg("Task not found for switch_player"));
        };
        self.handle_switch_player_for_dispatch(
            &dispatch,
            source,
            new_player,
            silent,
            preserve_history,
        )
    }

    pub(crate) fn handle_switch_player_for_dispatch(
        &self,
        dispatch: &TaskDispatch,
        source: Option<Obj>,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), Error> {
        let mut lc = self.lifecycle.lock();

        // Get the current task to access its session
        let Some(task) = lc.task_q.running_dispatch_mut(dispatch) else {
            return Err(E_INVARG.with_msg(|| "Task not found for switch_player".to_string()));
        };

        let current_connection = task
            .session
            .connection_details(None)
            .map_err(|e| {
                E_INVARG.with_msg(|| {
                    format!("Failed to get connection details for current session: {e:?}")
                })
            })?
            .first()
            .ok_or_else(|| {
                E_INVARG.with_msg(|| "No connection found for current session".to_string())
            })?
            .connection_obj;

        // A player can own several connections. If the task names its own player, retain the
        // connection that initiated the task instead of selecting an arbitrary connection.
        let connection_obj = if source.is_none() || source == Some(task.player) {
            current_connection
        } else {
            let connection_details = task.session.connection_details(source).map_err(|e| {
                E_INVARG.with_msg(|| {
                    format!("Failed to get connection details for switch source: {e:?}")
                })
            })?;
            let [connection] = connection_details.as_slice() else {
                if connection_details.is_empty() {
                    return Err(E_INVARG
                        .with_msg(|| "No connection found for switch_player source".to_string()));
                }
                return Err(E_INVARG.with_msg(|| {
                    "switch_player source has multiple connections; pass a connection object"
                        .to_string()
                }));
            };
            connection.connection_obj
        };

        drop(lc);

        self.system_control
            .switch_player(connection_obj, new_player, silent, preserve_history)?;

        // The registry is the durable commit point. Update scheduler metadata only after it
        // succeeds so a rejected switch leaves the running task associated with its old player.
        let mut lc = self.lifecycle.lock();
        if connection_obj == current_connection
            && let Some(task) = lc.task_q.running_dispatch_mut(dispatch)
        {
            task.player = new_player;
            task.session
                .switch_player_identity(new_player, preserve_history);
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod session_tests;
