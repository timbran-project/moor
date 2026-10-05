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

//! VM response routing, continuation, and scheduler handoffs.
//!
//! `vm_dispatch` runs the interpreter, refreshes authority, and selects the response policy.
//! `dispatch_suspend` handles immediate renewal and suspension. Transaction helpers arbitrate
//! commits; scheduler transitions own session finalization and registry changes after handoff.

use super::{
    Task, TaskState,
    outcome::{ExecutionOutcome, SuspensionKind, TerminalCompletion},
    start::HANDLE_UNCAUGHT_ERROR_SYM,
    transaction::{CommitFailure, Renewal, TerminalRollback, YieldCommit},
};
#[cfg(feature = "trace_events")]
use crate::trace_abort_limit_reached;
use crate::{
    config::FeaturesConfig,
    task_context::{
        rollback_current_transaction, with_current_transaction, with_current_transaction_mut,
    },
    tasks::{
        SchedulerOp, TaskStart, sched_counters,
        task_scheduler_client::{TaskLimitDisposition, TaskLimitInfo, TaskSchedulerClient},
    },
    trace_task_abort, trace_task_complete, trace_task_suspend, trace_task_suspend_with_delay,
    vm::{Fork, TaskInputRequest, TaskSuspend, VMHostResponse, builtins::BuiltinRegistry},
};
use moor_common::{
    model::{CommitResult, DispatchFlagsSource, VerbDispatch, VerbLookup, WorldStateError},
    tasks::{AbortLimitReason, CommandError, Exception, Session},
};
use moor_var::{List, SYSTEM_OBJECT, Var, v_empty_str, v_err, v_int, v_obj, v_str, v_string};
use tracing::{error, warn};

impl Task {
    /// Execute the VM, refresh its authority and telemetry, then select the operation policy.
    /// The worker loop consumes the returned decision and owns every scheduler handoff.
    pub(super) fn vm_dispatch(
        mut self: Box<Self>,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
        builtin_registry: &BuiltinRegistry,
        config: &FeaturesConfig,
    ) -> ExecutionOutcome {
        // Call the VM using transaction context
        let vm_exec_result = self.vm_host.exec_interpreter(
            self.task_id,
            session,
            builtin_registry,
            config,
            &mut self.program_cache,
        );
        self.sync_authority_from_vm();
        self.vm_host.set_program_cache_sizes(
            self.program_cache.total_slot_count(),
            self.program_cache.live_slot_count(),
            self.program_cache.key_count(),
        );

        if self.control.is_cancelled() {
            return self.cancelled_outcome();
        }

        // Having done that, what should we now do?
        match vm_exec_result {
            VMHostResponse::DispatchFork(fork_request) => {
                self.dispatch_fork(fork_request, task_scheduler_client, session)
            }
            VMHostResponse::Suspend(delay) => {
                self.dispatch_suspend(*delay, task_scheduler_client, session)
            }
            VMHostResponse::SuspendNeedInput(input_request) => {
                self.dispatch_input(*input_request, session)
            }
            VMHostResponse::ContinueOk => ExecutionOutcome::Continue(self),

            VMHostResponse::CompleteSuccess(result) => self.dispatch_success(result, session),
            VMHostResponse::CompleteAbort => self.dispatch_abort(),
            VMHostResponse::CompleteException(exception) => {
                self.dispatch_exception(exception, session)
            }
            VMHostResponse::CompleteRollback(commit_session) => {
                self.dispatch_rollback(commit_session, session)
            }

            VMHostResponse::AbortLimit(reason) => {
                self.dispatch_limit(reason, task_scheduler_client, session)
            }
            VMHostResponse::RollbackRetry => self.dispatch_retry(session),
        }
    }

    fn dispatch_fork(
        mut self: Box<Self>,
        fork_request: Box<Fork>,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        // Commit current transaction, dispatch fork, then resume in a new transaction.
        let task_id_var = fork_request.task_id;
        let fork_request = fork_request;

        let renewal = self.renew_transaction(session, || {
            let new_world_state = task_scheduler_client
                .begin_new_transaction()
                .map_err(|e| WorldStateError::DatabaseError(format!("Scheduler error: {e:?}")))?;
            let task_id = task_scheduler_client.request_fork(fork_request);
            Ok((new_world_state, task_id))
        });
        match renewal {
            Renewal::Cancelled => self.terminal_outcome(TerminalCompletion::Cancelled),
            Renewal::Continued(task_id) => {
                if let Some(task_id_var) = task_id_var {
                    self.vm_host
                        .set_variable(&task_id_var, v_int(task_id as i64));
                }
                // Mirror the other successful-commit paths (task_recv, immediate
                // resume, suspend): snapshot state for retry *after* mutating the
                // VM with this boundary's result (the task id variable, if any),
                // and reset `retries` since a fork dispatch that commits is a
                // successful transaction boundary like any other.
                self.refresh_retry_state();
                ExecutionOutcome::Continue(self)
            }
            Renewal::Conflict(conflict_info) => {
                self.conflict_outcome(session, "fork dispatch", conflict_info)
            }
            Renewal::CommitFailed(e) => {
                error!("Failed to commit before fork dispatch: {e:?}");
                self.commit_failure_outcome(CommitFailure::Rejected(e))
            }
            Renewal::BeginFailed(e) => {
                error!("Failed to begin transaction after fork commit: {e:?}");
                self.terminal_outcome(TerminalCompletion::RenewalFailed)
            }
        }
    }

    fn dispatch_input(
        mut self: Box<Self>,
        input_request: TaskInputRequest,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        // VMHost is now suspended for input, and we'll be waiting for a ResumeReceiveInput

        // Attempt commit... See comments/notes on Suspend above.
        let commit_result = match self.commit_yield_transaction(session) {
            Ok(result) => result,
            Err(failure) => return self.commit_failure_outcome(failure),
        };

        let boundary = match commit_result {
            YieldCommit::Committed(boundary) => boundary,
            YieldCommit::Conflict(conflict_info) => {
                return self.conflict_outcome(session, "input suspend", conflict_info);
            }
        };

        self.refresh_retry_state();
        self.vm_host.stop();

        trace_task_suspend!(self.task_id, "Waiting for input");

        // Transfer the committed boundary with the task when the loop consumes this request.
        self.suspension_outcome(SuspensionKind::Input(input_request), boundary)
    }

    fn dispatch_success(
        mut self: Box<Self>,
        result: Var,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        // Special case: in case of return from $do_command @ top-level, we need to look at the results:
        //      non-true value? => parse_command and restart (in same transaction)
        //      true value? => commit and return success.
        if let TaskStart::StartDoCommand {
            handler_object,
            player,
            command,
        } = self.state.task_start()
        {
            let (player, command) = (*player, command.clone());
            if !result.is_true() {
                // Intercept and rewrite us back to StartVerbCommand and do old school parse.
                self.state = TaskState::Prepared(TaskStart::StartCommandVerb {
                    handler_object: *handler_object,
                    player,
                    command: command.clone(),
                });

                if let Err(e) = with_current_transaction_mut(|world_state| {
                    self.setup_start_parse_command(&player, &command, world_state)
                }) {
                    return self.terminal_outcome(TerminalCompletion::CommandError(e));
                }
                return ExecutionOutcome::Continue(self);
            }
        }

        // Special case: if we're returning from $handle_uncaught_error, check the result
        if self.handling_uncaught_error {
            self.handling_uncaught_error = false;

            // If handler returned false, proceed with normal exception handling
            if !result.is_true() {
                let Some(original_exception) = self.pending_exception.take() else {
                    warn!(
                        task_id = self.task_id,
                        "handle_uncaught_error returned false, but original exception lost"
                    );
                    return self.cancelled_outcome();
                };

                // Restore the original exception and handle it normally
                let commit_result = match self.commit_terminal_transaction(session) {
                    Ok(result) => result,
                    Err(failure) => return self.commit_failure_outcome(failure),
                };

                let CommitResult::Success { .. } = commit_result else {
                    let conflict_info = match commit_result {
                        CommitResult::ConflictRetry { conflict_info } => conflict_info,
                        CommitResult::Success { .. } => unreachable!(),
                    };
                    return self.conflict_outcome(session, "exception handling", conflict_info);
                };

                // Debug level - this is normal when handle_uncaught_error doesn't exist or returns false
                // The exception itself is already being handled and reported to the client
                tracing::debug!(
                    task_id = self.task_id,
                    ?original_exception,
                    "Task exception (handle_uncaught_error returned false)"
                );
                self.vm_host.stop();

                trace_task_abort!(
                    self.task_id,
                    &format!("Exception: {}", original_exception.error.err_type())
                );

                return self
                    .terminal_outcome(TerminalCompletion::Exception(Box::new(original_exception)));
            }

            // Handler returned true, clear pending exception and continue with success
            self.pending_exception = None;
        }

        let commit_result = match self.commit_terminal_transaction(session) {
            Ok(result) => result,
            Err(failure) => return self.commit_failure_outcome(failure),
        };

        let (mutations_made, timestamp) = match commit_result {
            CommitResult::Success {
                mutations_made,
                timestamp,
            } => (mutations_made, timestamp),
            CommitResult::ConflictRetry { conflict_info } => {
                return self.conflict_outcome(session, "task completion", conflict_info);
            }
        };

        self.vm_host.stop();

        trace_task_complete!(self.task_id, &format!("{result:?}"));

        self.terminal_outcome(TerminalCompletion::Success {
            value: result,
            mutations_made,
            timestamp,
        })
    }

    fn dispatch_abort(mut self: Box<Self>) -> ExecutionOutcome {
        error!(task_id = self.task_id, "Task aborted");

        if matches!(
            self.rollback_terminal_transaction(),
            TerminalRollback::Cancelled
        ) {
            return self.terminal_outcome(TerminalCompletion::Cancelled);
        }

        self.vm_host.stop();

        trace_task_abort!(self.task_id, "Task aborted");

        self.terminal_outcome(TerminalCompletion::Cancelled)
    }

    fn dispatch_exception(
        mut self: Box<Self>,
        exception: Box<Exception>,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        // Check if we're already handling an uncaught error (prevent infinite recursion)
        if self.handling_uncaught_error {
            // We're in the handler and it threw an exception.
            // Fall through to normal exception reporting below.
        } else if let TaskState::Prepared(TaskStart::StartExceptionHandler { .. })
        | TaskState::Pending(TaskStart::StartExceptionHandler { .. }) = &self.state
        {
            // Current task IS the exception handler and it threw.
            // Fall through to normal exception reporting.
        } else {
            // Try to find and invoke $handle_uncaught_error on #0 (SYSTEM_OBJECT)
            let verb_lookup = with_current_transaction(|world_state| {
                world_state.dispatch_verb(
                    &self.task_permissions(),
                    VerbDispatch::new(
                        VerbLookup::method(&SYSTEM_OBJECT, *HANDLE_UNCAUGHT_ERROR_SYM),
                        DispatchFlagsSource::Permissions,
                    ),
                )
            });

            if let Ok(Some(verb_result)) = verb_lookup {
                // Handler exists - prepare to invoke it
                // Prepare arguments: {code, msg, value, stack, traceback}
                let code = v_err(exception.error.err_type());
                let msg = match exception.error.msg() {
                    Some(m) => v_string(m.to_string()),
                    None => v_str(""),
                };
                let value = exception.error.value().cloned().unwrap_or(v_int(0));
                let stack = List::from_iter(exception.stack.clone());
                let traceback = List::from_iter(exception.backtrace.clone());

                let args = List::from_iter(vec![code, msg, value, stack.into(), traceback.into()]);

                // Store the original exception and mark that we're handling uncaught error
                self.pending_exception = Some((*exception).clone());
                self.handling_uncaught_error = true;

                // Set up the handler as a method call on SYSTEM_OBJECT
                self.vm_host.start_call_method_verb(
                    self.task_id,
                    verb_result.verbdef,
                    *HANDLE_UNCAUGHT_ERROR_SYM,
                    v_obj(SYSTEM_OBJECT),
                    self.player,
                    args,
                    v_obj(self.player),
                    v_empty_str(),
                    verb_result.permissions_flags,
                    match with_current_transaction(|ws| {
                        ws.retrieve_verb(
                            &self.task_permissions(),
                            &verb_result.program_key.verb_definer,
                            verb_result.program_key.verb_uuid,
                        )
                    }) {
                        Ok((program, _)) => program,
                        Err(e) => {
                            error!(
                                task_id = ?self.task_id,
                                "Error resolving handler program: {e:?}"
                            );
                            return self.terminal_outcome(TerminalCompletion::CommandError(
                                CommandError::DatabaseError(e),
                            ));
                        }
                    },
                );

                // Continue execution - the handler will now run
                return ExecutionOutcome::Continue(self);
            }

            // No handler exists or error looking it up
            if let Err(e) = verb_lookup {
                error!(task_id = ?self.task_id, "Error looking up handle_uncaught_error: {:?}", e);
                // Proceed with normal exception reporting
            }
        }

        // Normal exception reporting (either no handler found, or handler itself threw)
        // Commands that end in exceptions are still expected to be committed, to
        // conform with MOO's expectations.
        let commit_result = match self.commit_terminal_transaction(session) {
            Ok(result) => result,
            Err(failure) => return self.commit_failure_outcome(failure),
        };

        if let CommitResult::ConflictRetry { conflict_info } = commit_result {
            return self.conflict_outcome(session, "exception reporting", conflict_info);
        }

        // Format the backtrace for logging
        let backtrace_str: String = exception
            .backtrace
            .iter()
            .filter_map(|v| v.as_string())
            .map(|s| format!("        {}", s))
            .collect::<Vec<_>>()
            .join("\n");

        error!(
            task_id = self.task_id,
            player_id = self.player.to_literal(),
            authority_principal = self.authority_principal.to_literal(),
            error = %exception.error,
            "Task exception:\n{}",
            backtrace_str
        );
        self.vm_host.stop();

        trace_task_abort!(
            self.task_id,
            &format!("Exception: {}", exception.error.err_type())
        );

        self.terminal_outcome(TerminalCompletion::Exception(exception))
    }

    fn dispatch_rollback(
        mut self: Box<Self>,
        commit_session: bool,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        if matches!(
            self.rollback_terminal_transaction(),
            TerminalRollback::Cancelled
        ) {
            return self.terminal_outcome(TerminalCompletion::Cancelled);
        }

        // Preserve the requested session disposition after world-state rollback.
        if !commit_session {
            session.rollback().expect("Could not rollback session");
        } else {
            session.commit().expect("Could not commit session");
        }
        self.vm_host.stop();
        self.terminal_outcome(TerminalCompletion::Cancelled)
    }

    fn dispatch_limit(
        mut self: Box<Self>,
        reason: AbortLimitReason,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        warn!(task_id = self.task_id, "Task abort limit reached");

        // Inside a running task, stack should never be empty - if it is, that's a critical bug
        let this = self
            .vm_host
            .this()
            .expect("Task has empty activation stack during abort - critical bug");
        let verb_name = self
            .vm_host
            .verb_name()
            .expect("Task has empty activation stack during abort - critical bug");
        let line_number = self
            .vm_host
            .line_number()
            .expect("Task has empty activation stack during abort - critical bug");

        // Emit trace event for abort limit
        #[cfg(feature = "trace_events")]
        {
            let (limit_type, limit_value) = match &reason {
                AbortLimitReason::Ticks(ticks) => ("Ticks".to_string(), format!("{}", ticks)),
                AbortLimitReason::Time(duration) => (
                    "Time".to_string(),
                    format!("{:.3}s", duration.as_secs_f64()),
                ),
                AbortLimitReason::OutputEvents(events) => {
                    ("OutputEvents".to_string(), events.to_string())
                }
                AbortLimitReason::OutputBytes(bytes) => {
                    ("OutputBytes".to_string(), bytes.to_string())
                }
            };

            trace_abort_limit_reached!(
                self.task_id,
                &limit_type,
                limit_value,
                self.vm_host.max_ticks,
                self.vm_host.tick_count(),
                verb_name,
                this.clone(),
                line_number
            );
        }

        // Collect traceback information for the handler
        let (stack_list, backtrace_list) = self.vm_host.get_traceback();
        let disposition = if task_scheduler_client.rollback_on_task_limit() {
            if matches!(
                self.rollback_terminal_transaction(),
                TerminalRollback::Cancelled
            ) {
                return self.terminal_outcome(TerminalCompletion::Cancelled);
            }
            TaskLimitDisposition::Rollback
        } else {
            match self.commit_terminal_transaction(session) {
                Ok(CommitResult::Success {
                    mutations_made,
                    timestamp,
                }) => TaskLimitDisposition::Commit {
                    mutations_made,
                    timestamp,
                },
                Ok(CommitResult::ConflictRetry { conflict_info }) => {
                    return self.conflict_outcome(session, "task limit", conflict_info);
                }
                Err(failure) => return self.commit_failure_outcome(failure),
            }
        };

        // The scheduler finalizes task effects and invokes $handle_task_timeout separately.
        self.vm_host.stop();
        self.terminal_outcome(TerminalCompletion::Limit(TaskLimitInfo {
            reason,
            disposition,
            this,
            verb_name,
            line_number,
            stack: stack_list,
            backtrace: backtrace_list,
        }))
    }

    fn dispatch_retry(mut self: Box<Self>, session: &dyn Session) -> ExecutionOutcome {
        warn!(task_id = self.task_id, "Task rollback requested, retrying");

        self.vm_host.stop();
        rollback_current_transaction().expect("Could not rollback world state");

        session.rollback().unwrap();
        self.retry_outcome("explicit rollback", None)
    }

    pub(super) fn dispatch_suspend(
        mut self: Box<Self>,
        delay: TaskSuspend,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> ExecutionOutcome {
        // Fast path for RecvMessages(None): commit, drain messages, resume immediately
        if matches!(&delay, TaskSuspend::RecvMessages(None)) {
            let perfc = sched_counters();
            let _t = perfc
                .timers
                .start(SchedulerOp::TaskRecvImmediateResumeLatency);
            let renewal = self.renew_transaction(session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            });
            match renewal {
                Renewal::Cancelled => return self.terminal_outcome(TerminalCompletion::Cancelled),
                Renewal::Continued(()) => {
                    let messages = task_scheduler_client.task_recv();
                    let resume_value = List::from_iter(messages).into();
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return ExecutionOutcome::Continue(self);
                }
                Renewal::Conflict(conflict_info) => {
                    return self.conflict_outcome(
                        session,
                        "task_recv immediate resume",
                        conflict_info,
                    );
                }
                Renewal::CommitFailed(e) => {
                    error!("Failed to commit before task_recv: {e:?}");
                    return self.commit_failure_outcome(CommitFailure::Rejected(e));
                }
                Renewal::BeginFailed(e) => {
                    error!("Failed to begin new transaction for task_recv: {e:?}");
                    return self.terminal_outcome(TerminalCompletion::RenewalFailed);
                }
            }
        }

        // Check for immediate wake conditions to avoid scheduler round-trip
        let (is_immediate, resume_value) = match &delay {
            TaskSuspend::Commit(val) => (true, val.clone()),
            TaskSuspend::Timed(d) if d.is_zero() => (true, v_int(0)),
            _ => (false, v_int(0)),
        };

        if is_immediate {
            // Fast path: get new transaction and continue immediately
            let renewal = self.renew_transaction(session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            });
            match renewal {
                Renewal::Cancelled => return self.terminal_outcome(TerminalCompletion::Cancelled),
                Renewal::Continued(()) => {
                    // Resume first (which resets start_time), then snapshot
                    // so retry_state has fresh timing if we need to restore
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return ExecutionOutcome::Continue(self);
                }
                Renewal::Conflict(conflict_info) => {
                    return self.conflict_outcome(session, "immediate resume", conflict_info);
                }
                Renewal::CommitFailed(e) => {
                    error!("Failed to commit before immediate resume: {e:?}");
                    return self.commit_failure_outcome(CommitFailure::Rejected(e));
                }
                Renewal::BeginFailed(e) => {
                    error!("Failed to begin new transaction for immediate resume: {e:?}");
                    return self.terminal_outcome(TerminalCompletion::RenewalFailed);
                }
            }
        }

        // VMHost is now suspended for execution, and we'll be waiting for a Resume
        let commit_result = match self.commit_yield_transaction(session) {
            Ok(result) => result,
            Err(failure) => return self.commit_failure_outcome(failure),
        };

        let boundary = match commit_result {
            YieldCommit::Committed(boundary) => boundary,
            YieldCommit::Conflict(conflict_info) => {
                return self.conflict_outcome(session, "suspend", conflict_info);
            }
        };

        self.refresh_retry_state();
        self.vm_host.stop();

        trace_task_suspend_with_delay!(self.task_id, &delay);

        // Let the scheduler know about our suspension, which can be of the form:
        //      * Indefinite, wake-able only with Resume
        //      * Scheduled, a duration is given, and we'll wake up after that duration
        // In both cases we'll rely on the scheduler to wake us up in its processing loop
        // rather than sleep here, which would make this thread unresponsive to other
        // messages.
        self.suspension_outcome(SuspensionKind::Wait(delay), boundary)
    }
}

#[cfg(test)]
mod tests;
