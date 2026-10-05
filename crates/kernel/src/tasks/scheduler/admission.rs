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

//! New-task construction, scheduler admission, and initial dispatch.
//!
//! Submission entry points allocate IDs under the lifecycle lock. `submit_task` receives that
//! borrowed state, checks scheduler and GC admission, and registers or dispatches the task.
//! Input delivery resumes an existing task in `transitions::resume` instead.

use super::{ResumeAction, Scheduler, SchedulerState, lifecycle::TaskLifecycle};
use crate::{
    tasks::{
        SchedulerOp, ServerOptions, TaskHandle, TaskNotification, TaskStart,
        registry::{LiveTaskRegistration, WakeCondition},
        sched_counters,
        task::Task,
        task_control::TaskControl,
        world_state_action::WorldStateAction,
        world_state_executor::match_object_ref,
    },
    trace_task_create_command, trace_task_create_eval, trace_task_create_verb,
};
use flume::Sender;
use moor_common::{
    model::ObjectRef,
    tasks::{CommandError, SchedulerError, SchedulerError::CommandExecutionError, Session, TaskId},
    util::Deadline,
};
use moor_var::{List, NOTHING, Obj, SYSTEM_OBJECT, Symbol, Var, v_empty_str, v_int, v_obj};
use std::{sync::Arc, time::Duration};
use tracing::{debug, warn};

/// Result of submitting a new task - either already suspended (delayed/GC-blocked)
/// or needs immediate wake by the caller.
enum TaskSubmission {
    /// Task is suspended with a delay or waiting for GC - no further action needed
    Suspended(TaskHandle),
    /// Task should start immediately - caller must wake it
    NeedsWake {
        registration: LiveTaskRegistration,
        handle: TaskHandle,
        task: Box<Task>,
        session: Arc<dyn Session>,
        result_sender: Option<Sender<(TaskId, Result<TaskNotification, SchedulerError>)>>,
    },
}

impl Scheduler {
    /// Submit a new task and wake it immediately if needed.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn submit_task(
        &self,
        lc: &mut TaskLifecycle,
        task_id: TaskId,
        player: &Obj,
        authority_principal: &Obj,
        task_start: TaskStart,
        delay_start: Option<Duration>,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        if lc.state != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }

        let gc_in_progress = self.config.features.anonymous_objects
            && (lc.gc_phase.blocks_admission() || lc.gc_force_collect);

        let so = self.server_options.load();
        match lc.submit_new_task(
            task_id,
            player,
            authority_principal,
            task_start,
            delay_start,
            session,
            &so,
            gc_in_progress,
        ) {
            TaskSubmission::Suspended(handle) => Ok(handle),
            TaskSubmission::NeedsWake {
                registration,
                handle,
                task,
                session,
                result_sender,
            } => {
                lc.dispatch_task(
                    task,
                    ResumeAction::Return(v_int(0)),
                    session,
                    result_sender,
                    self,
                    self.database.as_ref(),
                    self.builtin_registry.clone(),
                    self.config.clone(),
                    registration,
                )?;
                Ok(handle)
            }
        }
    }

    pub(crate) fn submit_command_task_inner(
        &self,
        handler_object: Obj,
        player: Obj,
        command: String,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;

        trace_task_create_command!(task_id, &player, &command, &handler_object);

        let task_start = TaskStart::StartCommandVerb {
            handler_object,
            player,
            command: command.to_string(),
        };

        self.submit_task(
            &mut lc, task_id, &player, &player, task_start, None, session,
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn submit_verb_task_inner(
        &self,
        player: Obj,
        vloc: ObjectRef,
        verb: Symbol,
        args: List,
        argstr: Var,
        authority_principal: Obj,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        // We need to translate Vloc and any of the arguments into valid references
        // before we can start the task.
        // If they're all just plain object references, we can just use them as-is, without
        // starting a transaction. Otherwise, we need to start a transaction to resolve them.
        let need_tx_oref = !matches!(vloc, ObjectRef::Id(_));
        let vloc = if need_tx_oref {
            let mut tx = self.database.new_world_state().unwrap();
            let Ok(vloc) = match_object_ref(&player, &authority_principal, &vloc, tx.as_mut())
            else {
                warn!(
                    player = %player,
                    authority_principal = %authority_principal,
                    object_ref = %vloc,
                    verb = %verb,
                    "Could not resolve invoke-verb object reference"
                );
                return Err(CommandExecutionError(CommandError::NoObjectMatch));
            };
            v_obj(vloc)
        } else {
            match vloc {
                ObjectRef::Id(id) => v_obj(id),
                _ => panic!("Unexpected object reference in vloc"),
            }
        };

        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;

        trace_task_create_verb!(task_id, &player, &verb.as_string(), &vloc);

        let task_start = TaskStart::StartVerb {
            player,
            vloc,
            verb,
            args,
            argstr,
        };

        self.submit_task(
            &mut lc,
            task_id,
            &player,
            &authority_principal,
            task_start,
            None,
            session,
        )
    }

    /// Start `handler_object:verb` for a connection-level hook (`do_out_of_band_command`,
    /// `do_client_data`). The handler is a plain object id, so no transaction is needed to
    /// resolve it.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn submit_handler_task_inner(
        &self,
        handler_object: Obj,
        verb: Symbol,
        player: Obj,
        authority_principal: Obj,
        args: List,
        argstr: Var,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;

        let task_start = TaskStart::StartVerb {
            player,
            vloc: v_obj(handler_object),
            verb,
            args,
            argstr,
        };

        self.submit_task(
            &mut lc,
            task_id,
            &player,
            &authority_principal,
            task_start,
            None,
            session,
        )
    }

    pub(crate) fn submit_eval_task_inner(
        &self,
        player: Obj,
        authority_principal: Obj,
        program: moor_compiler::Program,
        initial_env: Option<Vec<(Symbol, Var)>>,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;

        trace_task_create_eval!(task_id, &player);

        let task_start = TaskStart::StartEval {
            player,
            program,
            initial_env,
        };

        self.submit_task(
            &mut lc,
            task_id,
            &player,
            &authority_principal,
            task_start,
            None,
            session,
        )
    }

    pub(crate) fn submit_system_handler_task_inner(
        &self,
        player: Obj,
        handler_type: String,
        args: Vec<Var>,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        // If no provided (auth'd) player, we use #0 itself
        let player = if player == NOTHING {
            SYSTEM_OBJECT
        } else {
            player
        };
        debug!(
            "Processing system handler task: handler_type={}, player={}, args_count={}",
            handler_type,
            player,
            args.len()
        );

        // Construct specific verb name: invoke_<handler_type>_handler
        let verb_name = format!("invoke_{handler_type}_handler");
        let invoke_handler_sym = Symbol::mk(&verb_name);

        // Prepare arguments: [args...] (handler_type is now encoded in the verb name)
        let handler_args = args;

        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;
        debug!("Created system handler task with id={}", task_id);

        let task_start = TaskStart::StartVerb {
            player,
            vloc: v_obj(SYSTEM_OBJECT),
            verb: invoke_handler_sym,
            args: List::mk_list(&handler_args),
            argstr: v_empty_str(),
        };

        let result = self.submit_task(
            &mut lc, task_id, &player, &player, // Use the same player as permissions object
            task_start, None, session,
        );
        debug!("System handler task submission result: {:?}", result);
        result
    }

    pub(crate) fn submit_batch_world_state_task_inner(
        &self,
        player: Obj,
        authority_principal: Obj,
        actions: Vec<WorldStateAction>,
        rollback: bool,
        result_sink: crate::tasks::BatchResultSink,
        session: Arc<dyn Session>,
    ) -> Result<TaskHandle, SchedulerError> {
        let mut lc = self.lifecycle.lock();
        let task_id = lc.next_task_id;
        lc.next_task_id += 1;

        let task_start = TaskStart::StartBatchWorldState {
            player,
            authority_principal,
            actions,
            rollback,
            result_sink,
        };

        self.submit_task(
            &mut lc,
            task_id,
            &player,
            &authority_principal,
            task_start,
            None,
            session,
        )
    }
}

impl TaskLifecycle {
    #[allow(clippy::too_many_arguments)]
    fn submit_new_task(
        &mut self,
        task_id: TaskId,
        player: &Obj,
        authority_principal: &Obj,
        task_start: TaskStart,
        delay_start: Option<Duration>,
        session: Arc<dyn Session>,
        server_options: &ServerOptions,
        gc_in_progress: bool,
    ) -> TaskSubmission {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::StartTask);
        let (sender, receiver) = flume::unbounded();

        let control = Arc::new(TaskControl::new());
        let task = Task::new(
            task_id,
            *player,
            *authority_principal,
            task_start.clone(),
            server_options,
            control.clone(),
        );
        let registration = self.task_q.register_task(task_id);

        let handle = TaskHandle(task_id, receiver);

        // Delayed tasks go into suspension
        if let Some(delay) = delay_start {
            self.task_q.suspended.add_task(
                WakeCondition::Time(Deadline::from_now(delay).instant()),
                task,
                session,
                Some(sender),
                registration,
            );
            return TaskSubmission::Suspended(handle);
        }

        // GC-blocked tasks go into suspension
        if gc_in_progress {
            self.task_q.suspended.add_task(
                WakeCondition::GCComplete,
                task,
                session,
                Some(sender),
                registration,
            );
            return TaskSubmission::Suspended(handle);
        }

        // Immediate start - return task directly, skip suspension queue entirely
        TaskSubmission::NeedsWake {
            registration,
            handle,
            task,
            session,
            result_sender: Some(sender),
        }
    }
}
