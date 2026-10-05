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
    start::HANDLE_UNCAUGHT_ERROR_SYM,
    transaction::{Renewal, YieldCommit},
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
    vm::{TaskSuspend, VMHostResponse, builtins::BuiltinRegistry},
};
#[cfg(feature = "trace_events")]
use moor_common::tasks::AbortLimitReason;
use moor_common::{
    model::{CommitResult, DispatchFlagsSource, VerbDispatch, VerbLookup, WorldStateError},
    tasks::Session,
};
use moor_var::{List, SYSTEM_OBJECT, v_empty_str, v_err, v_int, v_obj, v_str, v_string};
use tracing::{error, warn};

impl Task {
    /// Call out to the vm_host and ask it to execute the next instructions, and it will return
    /// back telling us next steps.
    /// Results of VM execution are looked at, and if they involve a scheduler action, we will
    /// send a message back to the scheduler to handle it.
    /// If the scheduler action is some kind of suspension, we move ourselves into the message
    /// itself.
    /// If we are to be consumed (because ownership transferred back to the scheduler), we will
    /// return None, otherwise we will return ourselves.
    pub(super) fn vm_dispatch(
        mut self: Box<Self>,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
        builtin_registry: &BuiltinRegistry,
        config: &FeaturesConfig,
    ) -> Option<Box<Self>> {
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
            self.cancel_before_commit(task_scheduler_client);
            return None;
        }

        // Having done that, what should we now do?
        match vm_exec_result {
            VMHostResponse::DispatchFork(fork_request) => {
                // Commit current transaction, dispatch fork, then resume in a new transaction.
                let task_id_var = fork_request.task_id;
                let fork_request = fork_request;

                let renewal = self.renew_transaction(task_scheduler_client, session, || {
                    let new_world_state =
                        task_scheduler_client.begin_new_transaction().map_err(|e| {
                            WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                        })?;
                    let task_id = task_scheduler_client.request_fork(fork_request);
                    Ok((new_world_state, task_id))
                });
                match renewal {
                    Renewal::Cancelled => None,
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
                        Some(self)
                    }
                    Renewal::Conflict(conflict_info) => {
                        self.log_conflict_retry("fork dispatch", conflict_info.as_ref());
                        session.rollback().unwrap();
                        task_scheduler_client.conflict_retry(self, "fork dispatch", conflict_info);
                        None
                    }
                    Renewal::CommitFailed(e) => {
                        error!("Failed to commit before fork dispatch: {e:?}");
                        self.reject_commit(task_scheduler_client, e);
                        None
                    }
                    Renewal::BeginFailed(e) => {
                        error!("Failed to begin transaction after fork commit: {e:?}");
                        task_scheduler_client.abort_transaction_renewal_failed();
                        None
                    }
                }
            }
            VMHostResponse::Suspend(delay) => {
                self.dispatch_suspend(*delay, task_scheduler_client, session)
            }
            VMHostResponse::SuspendNeedInput(input_request) => {
                // VMHost is now suspended for input, and we'll be waiting for a ResumeReceiveInput

                // Attempt commit... See comments/notes on Suspend above.
                let commit_result =
                    self.commit_yield_transaction(task_scheduler_client, session)?;

                let boundary = match commit_result {
                    YieldCommit::Committed(boundary) => boundary,
                    YieldCommit::Conflict(conflict_info) => {
                        self.log_conflict_retry("input suspend", conflict_info.as_ref());
                        session.rollback().unwrap();
                        task_scheduler_client.conflict_retry(self, "input suspend", conflict_info);
                        return None;
                    }
                };

                self.refresh_retry_state();
                self.vm_host.stop();

                trace_task_suspend!(self.task_id, "Waiting for input");

                // Consume us, passing back to the scheduler that we're waiting for input.
                task_scheduler_client.request_input(
                    self,
                    input_request.player,
                    input_request.metadata,
                    boundary,
                );
                None
            }
            VMHostResponse::ContinueOk => Some(self),

            VMHostResponse::CompleteSuccess(result) => {
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
                            task_scheduler_client.command_error(e);
                        }
                        return Some(self);
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
                            return None; // Can't restore exception, abort task
                        };

                        // Restore the original exception and handle it normally
                        let commit_result =
                            self.commit_terminal_transaction(task_scheduler_client, session)?;

                        let CommitResult::Success { .. } = commit_result else {
                            let conflict_info = match commit_result {
                                CommitResult::ConflictRetry { conflict_info } => conflict_info,
                                CommitResult::Success { .. } => unreachable!(),
                            };
                            self.log_conflict_retry("exception handling", conflict_info.as_ref());
                            session.rollback().unwrap();
                            task_scheduler_client.conflict_retry(
                                self,
                                "exception handling",
                                conflict_info,
                            );
                            return None;
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

                        task_scheduler_client.exception(Box::new(original_exception));
                        return None;
                    }

                    // Handler returned true, clear pending exception and continue with success
                    self.pending_exception = None;
                }

                let commit_result =
                    self.commit_terminal_transaction(task_scheduler_client, session)?;

                let (mutations_made, timestamp) = match commit_result {
                    CommitResult::Success {
                        mutations_made,
                        timestamp,
                    } => (mutations_made, timestamp),
                    CommitResult::ConflictRetry { conflict_info } => {
                        self.log_conflict_retry("task completion", conflict_info.as_ref());
                        session.rollback().unwrap();

                        // Backoff is handled by the scheduler via suspension-based retry
                        task_scheduler_client.conflict_retry(
                            self,
                            "task completion",
                            conflict_info,
                        );
                        return None;
                    }
                };

                self.vm_host.stop();

                trace_task_complete!(self.task_id, &format!("{result:?}"));

                task_scheduler_client.success(result, mutations_made, timestamp);
                None
            }
            VMHostResponse::CompleteAbort => {
                error!(task_id = self.task_id, "Task aborted");

                if !self.rollback_terminal_transaction(task_scheduler_client) {
                    return None;
                }

                self.vm_host.stop();

                trace_task_abort!(self.task_id, "Task aborted");

                task_scheduler_client.abort_cancelled();
                None
            }
            VMHostResponse::CompleteException(exception) => {
                // Check if we're already handling an uncaught error (prevent infinite recursion)
                if self.handling_uncaught_error {
                    // We're in the handler and it threw an exception.
                    // Fall through to normal exception reporting below.
                } else if let TaskState::Prepared(TaskStart::StartExceptionHandler { .. })
                | TaskState::Pending(TaskStart::StartExceptionHandler { .. }) =
                    &self.state
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

                        let args =
                            List::from_iter(vec![code, msg, value, stack.into(), traceback.into()]);

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
                                    return None;
                                }
                            },
                        );

                        // Continue execution - the handler will now run
                        return Some(self);
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
                let commit_result =
                    self.commit_terminal_transaction(task_scheduler_client, session)?;

                if let CommitResult::ConflictRetry { conflict_info } = commit_result {
                    self.log_conflict_retry("exception reporting", conflict_info.as_ref());
                    session.rollback().unwrap();
                    task_scheduler_client.conflict_retry(
                        self,
                        "exception reporting",
                        conflict_info,
                    );
                    return None;
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

                task_scheduler_client.exception(exception);
                None
            }
            VMHostResponse::CompleteRollback(commit_session) => {
                if !self.rollback_terminal_transaction(task_scheduler_client) {
                    return None;
                }

                // And then decide if we are going to rollback th session as well.
                if !commit_session {
                    session.rollback().expect("Could not rollback session");
                } else {
                    session.commit().expect("Could not commit session");
                }
                self.vm_host.stop();
                task_scheduler_client.abort_cancelled();
                None
            }

            VMHostResponse::AbortLimit(reason) => {
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
                        AbortLimitReason::Ticks(ticks) => {
                            ("Ticks".to_string(), format!("{}", ticks))
                        }
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
                    if !self.rollback_terminal_transaction(task_scheduler_client) {
                        return None;
                    }
                    TaskLimitDisposition::Rollback
                } else {
                    match self.commit_terminal_transaction(task_scheduler_client, session)? {
                        CommitResult::Success {
                            mutations_made,
                            timestamp,
                        } => TaskLimitDisposition::Commit {
                            mutations_made,
                            timestamp,
                        },
                        CommitResult::ConflictRetry { conflict_info } => {
                            self.log_conflict_retry("task limit", conflict_info.as_ref());
                            session.rollback().unwrap();
                            task_scheduler_client.conflict_retry(self, "task limit", conflict_info);
                            return None;
                        }
                    }
                };

                // The scheduler finalizes task effects and invokes $handle_task_timeout separately.
                self.vm_host.stop();
                task_scheduler_client.abort_limits_reached(TaskLimitInfo {
                    reason,
                    disposition,
                    this,
                    verb_name,
                    line_number,
                    stack: stack_list,
                    backtrace: backtrace_list,
                });
                None
            }
            VMHostResponse::RollbackRetry => {
                warn!(task_id = self.task_id, "Task rollback requested, retrying");

                self.vm_host.stop();
                rollback_current_transaction().expect("Could not rollback world state");

                session.rollback().unwrap();
                task_scheduler_client.conflict_retry(self, "explicit rollback", None);
                None
            }
        }
    }

    pub(super) fn dispatch_suspend(
        mut self: Box<Self>,
        delay: TaskSuspend,
        task_scheduler_client: &TaskSchedulerClient,
        session: &dyn Session,
    ) -> Option<Box<Self>> {
        // Fast path for RecvMessages(None): commit, drain messages, resume immediately
        if matches!(&delay, TaskSuspend::RecvMessages(None)) {
            let perfc = sched_counters();
            let _t = perfc
                .timers
                .start(SchedulerOp::TaskRecvImmediateResumeLatency);
            let renewal = self.renew_transaction(task_scheduler_client, session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            });
            match renewal {
                Renewal::Cancelled => return None,
                Renewal::Continued(()) => {
                    let messages = task_scheduler_client.task_recv();
                    let resume_value = List::from_iter(messages).into();
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return Some(self);
                }
                Renewal::Conflict(conflict_info) => {
                    self.log_conflict_retry("task_recv immediate resume", conflict_info.as_ref());
                    session.rollback().unwrap();
                    task_scheduler_client.conflict_retry(
                        self,
                        "task_recv immediate resume",
                        conflict_info,
                    );
                    return None;
                }
                Renewal::CommitFailed(e) => {
                    error!("Failed to commit before task_recv: {e:?}");
                    self.reject_commit(task_scheduler_client, e);
                    return None;
                }
                Renewal::BeginFailed(e) => {
                    error!("Failed to begin new transaction for task_recv: {e:?}");
                    task_scheduler_client.abort_transaction_renewal_failed();
                    return None;
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
            let renewal = self.renew_transaction(task_scheduler_client, session, || {
                let new_world_state =
                    task_scheduler_client.begin_new_transaction().map_err(|e| {
                        WorldStateError::DatabaseError(format!("Scheduler error: {e:?}"))
                    })?;
                Ok((new_world_state, ()))
            });
            match renewal {
                Renewal::Cancelled => return None,
                Renewal::Continued(()) => {
                    // Resume first (which resets start_time), then snapshot
                    // so retry_state has fresh timing if we need to restore
                    self.vm_host.resume_execution(resume_value);
                    self.refresh_retry_state();
                    return Some(self);
                }
                Renewal::Conflict(conflict_info) => {
                    self.log_conflict_retry("immediate resume", conflict_info.as_ref());
                    session.rollback().unwrap();
                    task_scheduler_client.conflict_retry(self, "immediate resume", conflict_info);
                    return None;
                }
                Renewal::CommitFailed(e) => {
                    error!("Failed to commit before immediate resume: {e:?}");
                    self.reject_commit(task_scheduler_client, e);
                    return None;
                }
                Renewal::BeginFailed(e) => {
                    error!("Failed to begin new transaction for immediate resume: {e:?}");
                    task_scheduler_client.abort_transaction_renewal_failed();
                    return None;
                }
            }
        }

        // VMHost is now suspended for execution, and we'll be waiting for a Resume
        let commit_result = self.commit_yield_transaction(task_scheduler_client, session)?;

        let boundary = match commit_result {
            YieldCommit::Committed(boundary) => boundary,
            YieldCommit::Conflict(conflict_info) => {
                self.log_conflict_retry("suspend", conflict_info.as_ref());
                session.rollback().unwrap();
                task_scheduler_client.conflict_retry(self, "suspend", conflict_info);
                return None;
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
        task_scheduler_client.suspend(delay.clone(), self, boundary);
        None
    }
}
