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

//! Initial command, verb, fork, eval, and batch execution setup.
//!
//! `setup_task_start` resolves `TaskStart` using the worker's transaction context. Commands first
//! try `do_command`; a false result returns here through `setup_start_parse_command` for ordinary
//! command lookup. `dispatch` owns that return path and subsequent VM responses.

use super::{Task, TaskState, transaction::CommitFailure};
use crate::{
    config::Config,
    task_context::{
        current_session, rollback_current_transaction, with_current_transaction,
        with_current_transaction_mut,
    },
    tasks::{SchedulerOp, TaskStart, sched_counters, task_scheduler_client::TaskSchedulerClient},
};
use moor_common::{
    matching::{
        CommandParser, ComplexObjectNameMatcher, DefaultParseCommand, ParseCommandError,
        ParsedCommand, WsMatchEnv,
    },
    model::{
        CommitResult, DispatchFlagsSource, ObjFlag, ResolvedVerb, TaskPermissions, VerbDispatch,
        VerbLookup, WorldState, WorldStateError, command_verb_argspec,
    },
    tasks::{CommandError, CommandError::PermissionDenied},
    util::{BitEnum, parse_into_words},
};
use moor_var::{
    List, NOTHING, Obj, SYSTEM_OBJECT, Symbol, Var, Variant, program::ProgramType, v_empty_str,
    v_int, v_obj, v_str,
};
use moor_vm::Frame;
use std::sync::LazyLock;
use tracing::{error, warn};

static HUH_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("huh"));
pub(super) static HANDLE_UNCAUGHT_ERROR_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("handle_uncaught_error"));
static DO_COMMAND_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("do_command"));

impl Task {
    /// Set the task up to start executing, based on the task start configuration.
    pub(crate) fn setup_task_start(&mut self, tsc: &TaskSchedulerClient, config: &Config) -> bool {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::SetupTask);
        self.refresh_authority_principal_flags();
        match self.state.task_start() {
            // We've been asked to start a command.
            // We need to set up the VM and then execute it.
            TaskStart::StartCommandVerb {
                handler_object,
                player,
                command,
            } => {
                let (handler_object, player, command) = (*handler_object, *player, command.clone());
                if let Err(e) = with_current_transaction_mut(|world_state| {
                    self.start_command(&handler_object, &player, command.as_str(), world_state)
                }) {
                    tsc.command_error(e);
                };
            }
            TaskStart::StartVerb {
                player,
                vloc,
                verb,
                args,
                argstr,
            } => {
                let verb_name = *verb;
                let this = vloc.clone();
                let player = *player;
                let args_val = args.clone();
                let argstr_val = argstr.clone();
                let caller = v_obj(player);
                if !self.setup_call_verb(tsc, this, player, verb_name, args_val, caller, argstr_val)
                {
                    return false;
                }
            }
            TaskStart::StartScheduled {
                player,
                vloc,
                verb,
                args,
                ..
            } => {
                let verb_name = *verb;
                let player = *player;
                let args_val = args.clone();
                let argstr_val = v_str("");
                // The schedule's creator is the caller: `caller` and `caller_perms()` report the
                // authority principal captured at creation, never the target or `player`, so
                // `caller == this` and `caller_perms()` checks inside the verb see who arranged
                // the call.
                let principal = self.authority_principal;
                let caller = v_obj(principal);

                // vloc is an ObjectRef here (schedule entries are stored durably, so they can't
                // hold a live Var), so it needs resolving against the current transaction first,
                // same as a $do_command-style invocation would.
                let resolved = with_current_transaction_mut(|world_state| {
                    crate::tasks::world_state_executor::match_object_ref(
                        &player,
                        &player,
                        vloc,
                        world_state,
                    )
                });
                let this = match resolved {
                    Ok(obj) => v_obj(obj),
                    Err(e) => {
                        error!(task_id = ?self.task_id, vloc = ?vloc, verb = ?verb_name,
                               "Could not resolve scheduled task object reference: {:?}", e);
                        return false;
                    }
                };

                if !self.setup_call_verb(tsc, this, player, verb_name, args_val, caller, argstr_val)
                {
                    return false;
                }
                self.vm_host.vm_exec_state_mut().root_caller_perms = principal;
            }
            TaskStart::StartFork {
                fork_request,
                suspended: _,
            } => {
                let mut prepared_fork = (**fork_request).clone();
                if let Frame::Moo(ref mut frame) = prepared_fork.activation.frame {
                    frame.materialize_program_for_handoff();
                }
                // When setup_task_start is called, the task is being woken/started, so we always
                // pass suspended=false to ensure vm_host.running is set to true
                self.vm_host.start_fork(self.task_id, &prepared_fork, false);
            }
            TaskStart::StartEval {
                player,
                program,
                initial_env,
            } => {
                self.vm_host.start_eval(
                    self.task_id,
                    player,
                    program.clone(),
                    initial_env.as_deref(),
                );
            }
            TaskStart::StartDoCommand { .. } => {
                panic!("StartDoCommand invocation should not happen on initial setup_task_start");
            }
            TaskStart::StartBatchWorldState {
                actions,
                rollback,
                result_sink,
                ..
            } => {
                let actions = actions.clone();
                let rollback = *rollback;
                let result_sink = result_sink.clone();

                // Execute the batch directly against the task's transaction.
                let batch_result = with_current_transaction_mut(|world_state| {
                    crate::tasks::world_state_executor::execute_world_state_actions(
                        world_state,
                        config,
                        actions,
                    )
                });

                // Store the result in the shared sink for the caller to retrieve.
                *result_sink.lock().unwrap() = Some(batch_result.clone());

                // Handle commit/rollback and notify the scheduler.
                match batch_result {
                    Ok(_) => {
                        if rollback {
                            let Some(claim) = self.control.claim_terminal() else {
                                self.rollback_cancelled_transaction();
                                tsc.abort_cancelled();
                                return false;
                            };
                            let _ = rollback_current_transaction();
                            claim.rolled_back();
                        } else {
                            let session = current_session();
                            let commit_result =
                                match self.commit_terminal_transaction(session.as_ref()) {
                                    Ok(result) => result,
                                    Err(CommitFailure::Cancelled) => {
                                        tsc.abort_cancelled();
                                        return false;
                                    }
                                    Err(CommitFailure::Rejected(error)) => {
                                        tsc.commit_rejected(self.commit_rejection(error));
                                        return false;
                                    }
                                };
                            match commit_result {
                                CommitResult::Success { .. } => {}
                                CommitResult::ConflictRetry { conflict_info } => {
                                    let msg = match conflict_info {
                                        Some(info) => format!("Transaction conflict: {info}"),
                                        None => "Transaction conflict".to_string(),
                                    };
                                    *result_sink.lock().unwrap() = Some(Err(
                                        moor_common::tasks::SchedulerError::CommandExecutionError(
                                            CommandError::DatabaseError(
                                                moor_common::model::WorldStateError::DatabaseError(
                                                    msg,
                                                ),
                                            ),
                                        ),
                                    ));
                                    tsc.command_error(CommandError::DatabaseError(
                                        moor_common::model::WorldStateError::DatabaseError(
                                            "Transaction conflict".to_string(),
                                        ),
                                    ));
                                    return false;
                                }
                            }
                        }
                        tsc.success(v_int(0), !rollback, 0);
                        return false; // No VM loop needed
                    }
                    Err(ref e) => {
                        tsc.command_error(CommandError::DatabaseError(
                            moor_common::model::WorldStateError::DatabaseError(e.to_string()),
                        ));
                        return false;
                    }
                }
            }
            TaskStart::StartExceptionHandler { player, args, .. } => {
                // Start $handle_uncaught_error on the system object with the exception args
                // Find and set up the handler verb
                match with_current_transaction(|world_state| {
                    world_state.dispatch_verb(
                        &self.task_permissions(),
                        VerbDispatch::new(
                            VerbLookup::method(&SYSTEM_OBJECT, *HANDLE_UNCAUGHT_ERROR_SYM),
                            DispatchFlagsSource::Permissions,
                        ),
                    )
                }) {
                    Ok(None) => {
                        warn!("handle_uncaught_error verb not found during setup");
                        return false;
                    }
                    Err(e) => {
                        error!(task_id = ?self.task_id, "Error resolving handle_uncaught_error: {e:?}");
                        return false;
                    }
                    Ok(Some(verb_result)) => {
                        self.vm_host.start_call_method_verb(
                            self.task_id,
                            verb_result.verbdef,
                            *HANDLE_UNCAUGHT_ERROR_SYM,
                            v_obj(SYSTEM_OBJECT),
                            *player,
                            args.clone(),
                            v_obj(*player),
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
                                        "Error resolving exception-handler program: {e:?}"
                                    );
                                    return false;
                                }
                            },
                        );
                    }
                }
            }
        };
        true
    }

    /// Shared body of `StartVerb`/`StartScheduled` setup: resolve `verb` on `this` and hand it
    /// to the VM host to start executing. Returns false (meaning: setup failed, task is done)
    /// on any lookup failure, having already told the scheduler via `tsc`.
    #[allow(clippy::too_many_arguments)]
    fn setup_call_verb(
        &mut self,
        tsc: &TaskSchedulerClient,
        this: Var,
        player: Obj,
        verb_name: Symbol,
        args_val: List,
        caller: Var,
        argstr_val: Var,
    ) -> bool {
        // Find the callable verb ...
        // Obj or flyweight?
        let object_location = match &this.variant() {
            Variant::Flyweight(f) => *f.delegate(),
            Variant::Obj(o) => *o,
            _ => {
                tsc.verb_not_found(this, verb_name);
                return false;
            }
        };
        match with_current_transaction(|world_state| {
            world_state.dispatch_verb(
                &self.task_permissions(),
                VerbDispatch::new(
                    VerbLookup::method(&object_location, verb_name),
                    DispatchFlagsSource::Permissions,
                ),
            )
        }) {
            Ok(None) => {
                tsc.verb_not_found(this, verb_name);
                false
            }
            Err(WorldStateError::VerbNotFound(_, _)) => {
                panic!("dispatch_verb() should return Ok(None), not VerbNotFound");
            }
            Err(e) => {
                error!(task_id = ?self.task_id, this = ?this,
                       verb = ?verb_name,
                       "World state error while resolving verb: {:?}", e);
                panic!("Could not resolve verb: {e:?}");
            }
            Ok(Some(verb_result)) => {
                // Dispatch has already authorized the call on `x`; fetching the program to run
                // it is execution, not a source read, so it must not also demand `r`.
                let program = match with_current_transaction(|ws| {
                    ws.retrieve_verb_for_execution(
                        &self.task_permissions(),
                        &object_location,
                        &verb_result.program_key.verb_definer,
                        verb_result.program_key.verb_uuid,
                    )
                }) {
                    Ok((program, _)) => program,
                    Err(e) => {
                        error!(
                            task_id = ?self.task_id,
                            "Error resolving startup verb program: {e:?}"
                        );
                        return false;
                    }
                };
                self.vm_host.start_call_method_verb(
                    self.task_id,
                    verb_result.verbdef,
                    verb_name,
                    this,
                    player,
                    args_val,
                    caller,
                    argstr_val,
                    verb_result.permissions_flags,
                    program,
                );
                true
            }
        }
    }

    fn start_command(
        &mut self,
        handler_object: &Obj,
        player: &Obj,
        command: &str,
        world_state: &mut dyn WorldState,
    ) -> Result<(), CommandError> {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::StartCommand);

        // Command execution is a multi-phase process:
        //   1. Lookup $do_command. If we have the verb, execute it.
        //   2. If it returns a boolean `true`, we're done, let scheduler know, otherwise:
        //   3. Call parse_command, looking for a verb to execute in the environment.
        //     a. If something, call that verb.
        //     b. If nothing, look for :huh. If we have it, execute it.
        //   4. On completion, let the scheduler know.

        // All of this should occur in the same task id, and in the same transaction, and
        //  forms a multi-part process with continuation back from the VM along the whole
        //  chain, which complicates things significantly.

        // First check to see if we have a $do_command at all, if yes, we're actually starting
        // that verb with the command as an argument. If that then fails (non-true return code)
        // we'll end up in the start_parse_command phase.
        let do_command = world_state.dispatch_verb(
            &self.task_permissions(),
            VerbDispatch::new(
                VerbLookup::method(&SYSTEM_OBJECT, *DO_COMMAND_SYM),
                DispatchFlagsSource::Permissions,
            ),
        );

        match do_command {
            Ok(None) => {
                self.setup_start_parse_command(player, command, world_state)?;
            }
            Ok(Some(verb_result)) => {
                let arguments = parse_into_words(command);
                let args = List::from_iter(arguments.iter().map(|s| v_str(s)));
                self.vm_host.start_call_method_verb(
                    self.task_id,
                    verb_result.verbdef,
                    *DO_COMMAND_SYM,
                    v_obj(*handler_object),
                    *player,
                    args,
                    v_obj(*handler_object),
                    v_str(command),
                    verb_result.permissions_flags,
                    world_state
                        .retrieve_verb(
                            &self.task_permissions(),
                            &verb_result.program_key.verb_definer,
                            verb_result.program_key.verb_uuid,
                        )
                        .map_err(CommandError::DatabaseError)?
                        .0,
                );
                self.state = TaskState::Prepared(TaskStart::StartDoCommand {
                    handler_object: *handler_object,
                    player: *player,
                    command: command.to_string(),
                });
            }
            Err(WorldStateError::VerbNotFound(_, _)) => {
                panic!("dispatch_verb() should return Ok(None), not VerbNotFound");
            }
            Err(e) => {
                panic!("Unable to start task due to error: {e:?}");
            }
        }
        Ok(())
    }

    pub(super) fn setup_start_parse_command(
        &mut self,
        player: &Obj,
        command: &str,
        world_state: &mut dyn WorldState,
    ) -> Result<(), CommandError> {
        let (player_location, parsed_command) = {
            let perfc = sched_counters();
            let _t = perfc.timers.start(SchedulerOp::ParseCommand);
            let task_permissions = self.task_permissions();

            // We need the player's location, and we'll just die if we can't get it.
            let player_location = match world_state.location_of(&task_permissions, player) {
                Ok(loc) => loc,
                Err(WorldStateError::VerbPermissionDenied)
                | Err(WorldStateError::ObjectPermissionDenied)
                | Err(WorldStateError::PropertyPermissionDenied) => {
                    return Err(PermissionDenied);
                }
                Err(wse) => {
                    return Err(CommandError::DatabaseError(wse));
                }
            };

            // Parse the command in the current environment.
            let me = WsMatchEnv::with_permissions(world_state, task_permissions);
            let matcher = ComplexObjectNameMatcher {
                env: me,
                player: *player,
                fuzzy_threshold: 0.5,
            };
            let command_parser = DefaultParseCommand::new();
            let parsed_command = match command_parser.parse_command(command, &matcher) {
                Ok(pc) => pc,
                Err(ParseCommandError::PermissionDenied) => {
                    return Err(PermissionDenied);
                }
                Err(_) => {
                    return Err(CommandError::CouldNotParseCommand);
                }
            };

            (player_location, parsed_command)
        };

        // Look for the verb...
        let parse_results = find_verb_for_command(
            &self.task_permissions(),
            player,
            &player_location,
            &parsed_command,
            world_state,
        )?;
        let ((program, verbdef, permissions_flags), target) = match parse_results {
            // If we have a successful match, that's what we'll call into
            Some((verb_info, target)) => (verb_info, target),
            // Otherwise, we want to try to call :huh, if it exists.
            None => {
                if player_location == NOTHING {
                    return Err(CommandError::NoCommandMatch);
                }
                // Try to find :huh. If it exists, we'll dispatch to that, instead.
                // If we don't find it, that's the end of the line.
                let Ok(Some(verb_result)) = world_state.dispatch_verb(
                    &self.task_permissions(),
                    VerbDispatch::new(
                        VerbLookup::method(&player_location, *HUH_SYM),
                        DispatchFlagsSource::VerbOwner,
                    ),
                ) else {
                    return Err(CommandError::NoCommandMatch);
                };
                (
                    (
                        world_state
                            .retrieve_verb(
                                &self.task_permissions(),
                                &verb_result.program_key.verb_definer,
                                verb_result.program_key.verb_uuid,
                            )
                            .map_err(CommandError::DatabaseError)?
                            .0,
                        verb_result.verbdef,
                        verb_result.permissions_flags,
                    ),
                    player_location,
                )
            }
        };
        self.vm_host.start_call_command_verb(
            self.task_id,
            verbdef,
            parsed_command.verb,
            v_obj(target),
            *player,
            v_obj(*player),
            parsed_command,
            permissions_flags,
            program,
        );
        Ok(())
    }
}

#[allow(clippy::type_complexity)]
fn find_verb_for_command(
    permissions: &TaskPermissions,
    player: &Obj,
    player_location: &Obj,
    pc: &ParsedCommand,
    ws: &mut dyn WorldState,
) -> Result<Option<((ProgramType, ResolvedVerb, BitEnum<ObjFlag>), Obj)>, CommandError> {
    let perfc = sched_counters();
    let _t = perfc.timers.start(SchedulerOp::FindVerbForCommand);
    let targets_to_search = vec![
        *player,
        *player_location,
        pc.dobj.unwrap_or(NOTHING),
        pc.iobj.unwrap_or(NOTHING),
    ];
    let dobj = pc.dobj.unwrap_or(NOTHING);
    let iobj = pc.iobj.unwrap_or(NOTHING);
    for target in targets_to_search {
        let argspec = command_verb_argspec(&target, &dobj, pc.prep, &iobj);
        let match_result = ws.dispatch_verb(
            permissions,
            VerbDispatch::new(
                VerbLookup::command(&target, pc.verb, argspec),
                DispatchFlagsSource::VerbOwner,
            ),
        );
        let match_result = match match_result {
            Ok(m) => m,
            Err(WorldStateError::VerbPermissionDenied) => return Err(PermissionDenied),
            Err(WorldStateError::ObjectPermissionDenied) => {
                return Err(PermissionDenied);
            }
            Err(WorldStateError::PropertyPermissionDenied) => {
                return Err(PermissionDenied);
            }
            Err(wse) => return Err(CommandError::DatabaseError(wse)),
        };
        if let Some(verb_result) = match_result {
            // Lookup authorizes command invocation independently of the verb's public flags.
            let code_permissions =
                TaskPermissions::new(verb_result.verbdef.owner(), verb_result.permissions_flags);
            return Ok(Some((
                (
                    ws.retrieve_verb(
                        &code_permissions,
                        &verb_result.program_key.verb_definer,
                        verb_result.program_key.verb_uuid,
                    )
                    .map_err(CommandError::DatabaseError)?
                    .0,
                    verb_result.verbdef,
                    verb_result.permissions_flags,
                ),
                target,
            )));
        }
    }
    Ok(None)
}
