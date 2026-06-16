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

use crate::{
    VmHost,
    config::FeaturesConfig,
    moo_frame::{CatchType, ForRangeScope, MooStackFrame, PcType, ScopeType},
    scatter_assign::scatter_assign,
    vm_unwind::FinallyReason,
};
use moor_common::model::TaskPermissions;
use moor_common::{
    matching::ParsedCommand,
    model::{
        DispatchFlagsSource, ObjFlag, ResolvedVerb, VerbDispatch, VerbLookup, VerbProgramKey,
        WorldStateError,
    },
    tasks::TaskId,
    util::BitEnum,
};
use moor_compiler::{BuiltinId, Label, Offset, Op, Program, to_literal};
use moor_var::{
    E_ARGS, E_DIV, E_INVARG, E_INVIND, E_PERM, E_RANGE, E_TYPE, E_VARNF, E_VERBNF, Error,
    IndexMode, List, Obj, SYSTEM_OBJECT, Sequence, Symbol, TypeClass, Var, VarType, Variant,
    program::names::{GlobalName, Name},
    v_arc_str, v_bool, v_bool_int, v_empty_list, v_empty_map, v_empty_str, v_err, v_error, v_float,
    v_flyweight, v_int, v_list, v_map, v_none, v_obj, v_sym,
};
use std::{sync::LazyLock, time::Duration};

/// The set of parameters for a scheduler-requested *resolved* verb method dispatch.
#[derive(Debug, Clone, PartialEq)]
pub struct VerbExecutionRequest {
    /// Principal used for permission-sensitive program lookup and cache resolution.
    ///
    /// This is not necessarily the authority principal of the activation that will be pushed. For
    /// normal verb-owner dispatch, the activation runs as `resolved_verb.owner()` while lookup and
    /// program materialization still use this principal.
    lookup_principal: Obj,
    /// Cached flags for the activation authority selected by dispatch.
    ///
    /// `Activation::for_call` pairs these flags with `resolved_verb.owner()`.
    activation_authority_flags: BitEnum<ObjFlag>,
    /// The resolved verb.
    pub resolved_verb: ResolvedVerb,
    /// Verb name
    pub verb_name: Symbol,
    /// This object
    pub this: Var,
    /// Player
    pub player: Obj,
    /// Arguments
    pub args: List,
    /// Caller
    pub caller: Var,
    /// Argument string
    pub argstr: Var,
    /// Stable key for the dispatched verb program.
    pub program_key: VerbProgramKey,
}

impl VerbExecutionRequest {
    #[allow(clippy::too_many_arguments)]
    #[inline]
    pub fn new(
        lookup_principal: Obj,
        activation_authority_flags: BitEnum<ObjFlag>,
        resolved_verb: ResolvedVerb,
        verb_name: Symbol,
        this: Var,
        player: Obj,
        args: List,
        caller: Var,
        argstr: Var,
        program_key: VerbProgramKey,
    ) -> Self {
        Self {
            lookup_principal,
            activation_authority_flags,
            resolved_verb,
            verb_name,
            this,
            player,
            args,
            caller,
            argstr,
            program_key,
        }
    }

    /// Principal used to resolve or materialize the target verb program.
    #[inline]
    pub fn lookup_principal(&self) -> Obj {
        self.lookup_principal
    }

    /// Cached flags paired with the resolved verb owner for the new activation.
    #[inline]
    pub fn activation_authority_flags(&self) -> BitEnum<ObjFlag> {
        self.activation_authority_flags
    }
}

/// The set of parameters for a command verb dispatch with full command environment.
#[derive(Debug, Clone, PartialEq)]
pub struct CommandVerbExecutionRequest {
    /// Principal used for permission-sensitive program lookup and cache resolution.
    ///
    /// This is not necessarily the authority principal of the activation that will be pushed. For
    /// normal verb-owner dispatch, the activation runs as `resolved_verb.owner()` while lookup and
    /// program materialization still use this principal.
    lookup_principal: Obj,
    /// Cached flags for the activation authority selected by dispatch.
    ///
    /// `Activation::for_call` pairs these flags with `resolved_verb.owner()`.
    activation_authority_flags: BitEnum<ObjFlag>,
    /// The resolved verb.
    pub resolved_verb: ResolvedVerb,
    /// Verb name
    pub verb_name: Symbol,
    /// This object
    pub this: Var,
    /// Player
    pub player: Obj,
    /// Caller
    pub caller: Var,
    /// The parsed command with dobj, iobj, prep, etc.
    pub command: ParsedCommand,
    /// Stable key for the dispatched verb program.
    pub program_key: VerbProgramKey,
}

impl CommandVerbExecutionRequest {
    #[allow(clippy::too_many_arguments)]
    #[inline]
    pub fn new(
        lookup_principal: Obj,
        activation_authority_flags: BitEnum<ObjFlag>,
        resolved_verb: ResolvedVerb,
        verb_name: Symbol,
        this: Var,
        player: Obj,
        caller: Var,
        command: ParsedCommand,
        program_key: VerbProgramKey,
    ) -> Self {
        Self {
            lookup_principal,
            activation_authority_flags,
            resolved_verb,
            verb_name,
            this,
            player,
            caller,
            command,
            program_key,
        }
    }

    /// Principal used to resolve or materialize the target verb program.
    #[inline]
    pub fn lookup_principal(&self) -> Obj {
        self.lookup_principal
    }

    /// Cached flags paired with the resolved verb owner for the new activation.
    #[inline]
    pub fn activation_authority_flags(&self) -> BitEnum<ObjFlag> {
        self.activation_authority_flags
    }
}

#[cfg(test)]
mod execution_request_tests {
    use super::*;
    use moor_common::model::{PrepSpec, VerbArgsSpec, VerbFlag};
    use uuid::Uuid;

    fn resolved_verb(owner: Obj) -> ResolvedVerb {
        ResolvedVerb::new(
            Uuid::nil(),
            Obj::mk_id(2),
            owner,
            BitEnum::new_with(VerbFlag::Read),
            VerbArgsSpec::this_none_this(),
        )
    }

    #[test]
    fn verb_execution_request_separates_lookup_principal_from_activation_flags() {
        let lookup_principal = Obj::mk_id(10);
        let activation_flags = BitEnum::new_with(ObjFlag::Programmer);
        let request = VerbExecutionRequest::new(
            lookup_principal,
            activation_flags,
            resolved_verb(Obj::mk_id(20)),
            Symbol::mk("test"),
            v_obj(Obj::mk_id(2)),
            Obj::mk_id(3),
            List::mk_list(&[]),
            v_obj(Obj::mk_id(4)),
            v_empty_str(),
            VerbProgramKey {
                verb_definer: Obj::mk_id(2),
                verb_uuid: Uuid::nil(),
            },
        );

        assert_eq!(request.lookup_principal(), lookup_principal);
        assert_eq!(request.activation_authority_flags(), activation_flags);
        assert_eq!(request.resolved_verb.owner(), Obj::mk_id(20));
    }

    #[test]
    fn command_execution_request_separates_lookup_principal_from_activation_flags() {
        let lookup_principal = Obj::mk_id(11);
        let activation_flags = BitEnum::new_with(ObjFlag::Wizard);
        let command = ParsedCommand {
            verb: Symbol::mk("look"),
            argstr: "look".to_string(),
            args: vec![],
            dobjstr: None,
            dobj: None,
            ambiguous_dobj: None,
            prepstr: None,
            prep: PrepSpec::None,
            iobjstr: None,
            iobj: None,
            ambiguous_iobj: None,
        };
        let request = CommandVerbExecutionRequest::new(
            lookup_principal,
            activation_flags,
            resolved_verb(Obj::mk_id(21)),
            Symbol::mk("look"),
            v_obj(Obj::mk_id(2)),
            Obj::mk_id(3),
            v_obj(Obj::mk_id(3)),
            command,
            VerbProgramKey {
                verb_definer: Obj::mk_id(2),
                verb_uuid: Uuid::nil(),
            },
        );

        assert_eq!(request.lookup_principal(), lookup_principal);
        assert_eq!(request.activation_authority_flags(), activation_flags);
        assert_eq!(request.resolved_verb.owner(), Obj::mk_id(21));
    }
}

/// Activation data needed by opcodes that prepare host-level execution requests.
#[derive(Debug, Clone)]
pub struct FrameExecutionContext<'a> {
    /// Task permissions of the activation currently executing this frame.
    authority: TaskPermissions,
    activation_player: Obj,
    this: &'a Var,
    verb_name: Symbol,
    verb_definer: Obj,
}

impl<'a> FrameExecutionContext<'a> {
    #[inline]
    #[must_use]
    pub fn new(
        authority: TaskPermissions,
        activation_player: Obj,
        this: &'a Var,
        verb_name: Symbol,
        verb_definer: Obj,
    ) -> Self {
        Self {
            authority,
            activation_player,
            this,
            verb_name,
            verb_definer,
        }
    }

    fn player_for_frame(&self, frame: &MooStackFrame) -> Obj {
        frame
            .get_gvar(GlobalName::player)
            .and_then(|v| v.as_object())
            .filter(|fp| fp != &self.activation_player)
            .map_or(self.activation_player, |fp| {
                if self.authority.is_wizard() {
                    fp
                } else {
                    self.activation_player
                }
            })
    }
}

/// Flavours of task suspension.
#[derive(Debug, Clone, PartialEq)]
pub enum TaskSuspend {
    /// Suspend forever.
    Never,
    /// Suspend for a given duration.
    Timed(Duration),
    /// Suspend until another task completes (or never exists)
    WaitTask(TaskId),
    /// Commit and resume immediately with the given return value.
    Commit(Var),
    /// Ask the scheduler to ask a worker to do some work, suspend us, and then resume us when
    /// the work is done.
    WorkerRequest(Symbol, Vec<Var>, Option<Duration>),
    /// Commit and receive inter-task messages. None = immediate (fast path),
    /// Some(duration) = wait up to duration for messages if queue is empty.
    RecvMessages(Option<Duration>),
}

/// The set of parameters for a VM-requested fork.
#[derive(Debug, Clone)]
pub struct Fork {
    /// The player. This is in the activation as well, but it's nicer to have it up here and
    /// explicit
    pub player: Obj,
    /// Authority principal for the forked task.
    pub progr: Obj,
    /// The task ID of the task that forked us
    pub parent_task_id: usize,
    /// The time to delay before starting the forked task, if any.
    pub delay: Option<Duration>,
    /// A copy of the activation record from the task that forked us.
    pub activation: crate::Activation,
    /// The unique fork vector offset into the fork vector for the executing binary held in the
    /// activation record.  This is copied into the main vector and execution proceeds from there,
    /// instead.
    pub fork_vector_offset: Offset,
    /// The (optional) variable label where the task ID of the new task should be stored, in both
    /// the parent activation and the new task's activation.
    pub task_id: Option<Name>,
}

/// Possible outcomes from VM execution inner loop, which are used to determine what to do next.
#[derive(Debug, Clone)]
pub enum ExecutionResult {
    /// All is well. The task should let the VM continue executing.
    More,
    /// Execution of this stack frame is complete with a return value.
    Complete(Var),
    /// An error occurred during execution, that we might need to push to the stack and
    /// potentially resume or unwind, depending on the context.
    PushError(Error),
    /// An error occurred during execution, that should definitely be treated as a proper "raise"
    /// and unwind event unless there's a catch handler in place
    RaiseError(Error),
    /// An explicit stack unwind (for a reason other than a return.)
    Unwind(FinallyReason),
    /// Explicit return, unwind stack
    Return(Var),
    /// An exception was raised during execution.
    Exception(FinallyReason),
    /// Perform the verb dispatch, building the stack frame and executing it.
    DispatchVerb(Box<VerbExecutionRequest>),
    /// Perform command verb dispatch with full command environment (dobj, iobj, prep, etc).
    DispatchCommandVerb(Box<CommandVerbExecutionRequest>),
    /// Request `eval` execution, which is a kind of special activation creation where we've already
    /// been given the program to execute instead of having to look it up.
    DispatchEval {
        /// Authority principal for the eval.
        authority_principal: Obj,
        /// The player who is performing the eval.
        player: Obj,
        /// The program to execute.
        program: Program,
        /// Optional initial variable bindings to inject into the eval's environment.
        initial_env: Option<Vec<(Symbol, Var)>>,
    },
    /// Request dispatch of a builtin function with the given arguments.
    DispatchBuiltin { builtin: BuiltinId, arguments: List },
    /// Request dispatch of a lambda function with the given arguments.
    DispatchLambda {
        lambda: moor_var::Lambda,
        arguments: List,
    },
    /// Request start of a new task as a fork, at a given offset into the fork vector of the
    /// current program. If the duration is None, the task should be started immediately, otherwise
    /// it should be scheduled to start after the given delay.
    /// If a Name is provided, the task ID of the new task should be stored in the variable with
    /// that in the parent activation.
    TaskStartFork(Option<Duration>, Option<Name>, Offset),
    /// Request that this task be suspended for a duration of time.
    /// This leads to the task performing a commit, being suspended for a delay, and then being
    /// resumed under a new transaction.
    /// If the duration is None, then the task is suspended indefinitely, until it is killed or
    /// resumed using `resume()` or `kill_task()`.
    TaskSuspend(TaskSuspend),
    /// Request input from the client, with optional metadata for UI hints.
    TaskNeedInput(Option<Vec<(Symbol, Var)>>),
    /// Rollback the current transaction and restart the task in a new transaction.
    /// This can happen when a conflict occurs during execution, independent of a commit.
    TaskRollbackRestart,
    /// Just rollback and die. Kills all task DB mutations. Output (Session) is optionally committed.
    TaskRollback(bool),
}

static DELEGATE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("delegate"));
static SLOTS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("slots"));
static LIST_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("list_proto"));
static MAP_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("map_proto"));
static STRING_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("str_proto"));
static INTEGER_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("int_proto"));
static FLOAT_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("float_proto"));
static ERROR_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("err_proto"));
static BOOL_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("bool_proto"));
static SYM_PROTO_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("sym_proto"));

/// Build a captured environment from a list of captured variables
/// This recreates the environment structure needed by lambda execution
fn build_captured_environment(
    captured_vars: &[(Name, Var)],
    lambda_program: &Program,
) -> Vec<Vec<Var>> {
    if captured_vars.is_empty() {
        return vec![];
    }

    // Organize variables by scope depth using a Vec (scope depths are sequential from 0)
    let max_scope_depth = captured_vars
        .iter()
        .map(|(name, _)| name.1 as usize)
        .max()
        .unwrap_or(0);

    let mut scope_vars: Vec<Vec<(u16, Var)>> = vec![Vec::new(); max_scope_depth + 1];

    for &(name, ref value) in captured_vars {
        let scope_depth = name.1 as usize;
        let var_offset = name.0;
        scope_vars[scope_depth].push((var_offset, value.clone()));
    }

    // Build environment with proper scope structure
    let mut captured_env = Vec::new();

    for (scope_idx, vars_in_scope) in scope_vars.iter().enumerate() {
        // For scope 0 (global), use global width. For others, use a reasonable default.
        let expected_var_count = if scope_idx == 0 {
            lambda_program.var_names().global_width()
        } else {
            // For non-global scopes, start with a minimum size and expand as needed
            16
        };
        let mut scope_env = vec![v_none(); expected_var_count];

        if !vars_in_scope.is_empty() {
            // Find the maximum offset to ensure we have enough space
            let max_offset = vars_in_scope
                .iter()
                .map(|(offset, _)| *offset as usize)
                .max()
                .unwrap_or(0);
            if max_offset >= scope_env.len() {
                scope_env.resize(max_offset + 1, v_none());
            }

            for &(var_offset, ref value) in vars_in_scope {
                scope_env[var_offset as usize] = value.clone();
            }
        }

        captured_env.push(scope_env);
    }

    captured_env
}

#[cold]
#[inline(never)]
fn push_error_cold(error: Error) -> ExecutionResult {
    ExecutionResult::PushError(error)
}

#[cold]
#[inline(never)]
fn invalid_property_name_error(propname: &Var) -> Error {
    E_TYPE.with_msg(|| format!("Invalid property name: {}", to_literal(propname)))
}

#[cold]
#[inline(never)]
fn invalid_property_access_error(value: &Var) -> Error {
    E_TYPE.with_msg(|| format!("Invalid value for property access: {}", to_literal(value)))
}

#[cold]
#[inline(never)]
fn invalid_verb_target_error(value: &Var) -> Error {
    E_TYPE.with_msg(|| format!("Invalid target for verb dispatch: {}", to_literal(value)))
}

#[cold]
#[inline(never)]
fn invalid_verb_name_error(verb: &Var) -> Error {
    E_TYPE.with_msg(|| format!("Invalid verb name: {}", to_literal(verb)))
}

#[cold]
#[inline(never)]
fn invalid_list_append_error() -> Error {
    E_TYPE.msg("invalid value in list append")
}

#[cold]
#[inline(never)]
fn division_by_zero_error() -> Error {
    E_DIV.msg("division by zero")
}

#[cold]
#[inline(never)]
fn invalid_error_message_error() -> Error {
    E_TYPE.msg("invalid value for error message")
}

#[cold]
#[inline(never)]
fn invalid_list_splice_error() -> Error {
    E_TYPE.msg("invalid value in list splice")
}

macro_rules! binary_bool_op {
    ( $f:ident, $op:tt, $bi:expr ) => {
        let rhs = $f.pop();
        let bres: bool = *$f.peek_top() $op rhs;
        *$f.peek_top_mut() = if $bi {
            Var::mk_bool(bres)
        } else {
            v_bool_int(bres)
        };
    };
}

macro_rules! binary_var_op {
    ( $f:ident, $op:tt ) => {
        let rhs = $f.pop();
        let result = $f.peek_top().$op(&rhs);
        match result {
            Ok(result) => {
                *$f.peek_top_mut() = result;
            }
            Err(err_code) => {
                $f.pop();
                return push_error_cold(err_code);
            }
        }
    };
}

fn stack_index(len: usize, depth: usize, pc: u16) -> usize {
    len.checked_sub(depth + 1)
        .unwrap_or_else(|| panic!("stack underflow @ PC: {pc}"))
}

fn remove_stack_indices(stack: &mut Vec<Var>, indices: &mut [usize]) {
    indices.sort_unstable_by(|a, b| b.cmp(a));
    for idx in indices.iter().copied() {
        stack.remove(idx);
    }
}

fn prepare_verb_dispatch<H: VmHost>(
    host: &mut H,
    context: &FrameExecutionContext<'_>,
    frame: &MooStackFrame,
    type_dispatch: bool,
    target: Var,
    verb: Symbol,
    args: List,
) -> Result<ExecutionResult, Error> {
    if let Some(o) = target.as_object() {
        return Ok(prepare_call_verb(
            host, context, frame, o, target, verb, args,
        ));
    }

    if let Some(f) = target.as_flyweight() {
        return Ok(prepare_call_verb(
            host,
            context,
            frame,
            *f.delegate(),
            target,
            verb,
            args,
        ));
    }

    if !type_dispatch {
        return Err(E_TYPE
            .with_msg(|| format!("Invalid target {:?} for verb dispatch", target.type_code())));
    }

    let sysprop_sym = if target.is_int() {
        *INTEGER_PROTO_SYM
    } else if target.is_string() {
        *STRING_PROTO_SYM
    } else if target.is_float() {
        *FLOAT_PROTO_SYM
    } else if target.is_list() {
        *LIST_PROTO_SYM
    } else {
        match target.variant() {
            Variant::Map(_) => *MAP_PROTO_SYM,
            Variant::Err(_) => *ERROR_PROTO_SYM,
            Variant::Sym(_) => *SYM_PROTO_SYM,
            Variant::Bool(_) => *BOOL_PROTO_SYM,
            _ => {
                return Err(E_TYPE.with_msg(|| {
                    format!(
                        "Invalid target for verb dispatch: {}",
                        target.type_code().to_literal()
                    )
                }));
            }
        }
    };
    let prop_val = host
        .retrieve_property(&context.authority, &SYSTEM_OBJECT, sysprop_sym)
        .map_err(|e| e.to_error())?;
    let Some(prop_val) = prop_val.as_object() else {
        return Err(E_TYPE.with_msg(|| {
            format!(
                "Invalid target for verb dispatch: {}",
                prop_val.type_code().to_literal()
            )
        }));
    };
    let arguments = args
        .insert(0, &target)
        .expect("Failed to insert object for dispatch");
    let Some(arguments) = arguments.as_list() else {
        return Err(E_TYPE.with_msg(|| {
            format!(
                "Invalid arguments for verb dispatch: {}",
                arguments.type_code().to_literal()
            )
        }));
    };
    Ok(prepare_call_verb(
        host,
        context,
        frame,
        prop_val,
        v_obj(prop_val),
        verb,
        arguments.clone(),
    ))
}

fn prepare_pass_verb<H: VmHost>(
    host: &mut H,
    context: &FrameExecutionContext<'_>,
    args: List,
) -> ExecutionResult {
    let parent = match host.parent_of(&context.authority, &context.verb_definer) {
        Ok(p) => p,
        Err(WorldStateError::RollbackRetry) => {
            return ExecutionResult::TaskRollbackRestart;
        }
        Err(e) => return ExecutionResult::RaiseError(e.to_error()),
    };

    if !host.valid(&parent).unwrap_or_default() {
        return ExecutionResult::PushError(E_INVIND.msg("Invalid object for pass() verb dispatch"));
    }

    let verb_result = host.dispatch_verb(
        &context.authority,
        VerbDispatch::new(
            VerbLookup::method(&parent, context.verb_name),
            DispatchFlagsSource::Permissions,
        ),
    );

    let (program_key, resolved_verb, permissions_flags) = match verb_result {
        Ok(Some(vi)) => (vi.program_key, vi.verbdef, vi.permissions_flags),
        Ok(None) => {
            return ExecutionResult::PushError(E_VERBNF.msg("Verb not found for pass() dispatch"));
        }
        Err(WorldStateError::RollbackRetry) => {
            return ExecutionResult::TaskRollbackRestart;
        }
        Err(e) => return ExecutionResult::RaiseError(e.to_error()),
    };

    ExecutionResult::DispatchVerb(Box::new(VerbExecutionRequest::new(
        context.authority.principal(),
        permissions_flags,
        resolved_verb,
        context.verb_name,
        (*context.this).clone(),
        context.activation_player,
        args,
        (*context.this).clone(),
        v_empty_str(),
        program_key,
    )))
}

fn prepare_call_verb<H: VmHost>(
    host: &mut H,
    context: &FrameExecutionContext<'_>,
    frame: &MooStackFrame,
    location: Obj,
    this: Var,
    verb_name: Symbol,
    args: List,
) -> ExecutionResult {
    let player = context.player_for_frame(frame);

    if !host.valid(&location).unwrap_or_default() {
        return ExecutionResult::PushError(
            E_INVIND.with_msg(|| format!("Invalid object ({location}) for verb dispatch")),
        );
    }

    let verb_result = host.dispatch_verb(
        &context.authority,
        VerbDispatch::new(
            VerbLookup::method(&location, verb_name),
            DispatchFlagsSource::VerbOwner,
        ),
    );

    let (program_key, resolved_verb, permissions_flags) = match verb_result {
        Ok(Some(vi)) => (vi.program_key, vi.verbdef, vi.permissions_flags),
        Ok(None) => {
            return ExecutionResult::PushError(E_VERBNF.with_msg(|| {
                format!(
                    "Verb {}:{} not found",
                    to_literal(&v_obj(location)),
                    verb_name,
                )
            }));
        }
        Err(WorldStateError::ObjectPermissionDenied | WorldStateError::VerbPermissionDenied) => {
            return ExecutionResult::PushError(E_PERM.into());
        }
        Err(WorldStateError::RollbackRetry) => {
            return ExecutionResult::TaskRollbackRestart;
        }
        Err(WorldStateError::VerbNotFound(_, _)) => {
            panic!("dispatch_verb() should return Ok(None), not VerbNotFound");
        }
        Err(e) => {
            panic!("Unexpected error from dispatch_verb: {e:?}")
        }
    };

    ExecutionResult::DispatchVerb(Box::new(VerbExecutionRequest::new(
        context.authority.principal(),
        permissions_flags,
        resolved_verb,
        verb_name,
        this,
        player,
        args,
        (*context.this).clone(),
        v_empty_str(),
        program_key,
    )))
}

/// Main VM opcode execution for MOO stack frames. The actual meat of the MOO virtual machine.
pub fn moo_frame_execute<H: VmHost>(
    host: &mut H,
    tick_slice: usize,
    tick_count: &mut usize,
    context: &FrameExecutionContext,
    f: &mut MooStackFrame,
    features_config: &FeaturesConfig,
) -> ExecutionResult {
    // Unprogrammed verbs have empty opcodes - return 0/false to caller (LambdaMOO compat).
    if f.opcodes().is_empty() {
        let ret_val = if features_config.use_boolean_returns {
            v_bool(false)
        } else {
            v_int(0)
        };
        return ExecutionResult::Return(ret_val);
    }

    // The per-execution slice count. This is used to limit the amount of work we do in a single
    // execution slice for this task.
    // We should not execute more than `tick_slice` in a single VM instruction fetch/execute
    // run. This is to allow us to be responsive to the task scheduler.
    // Note this is not the same as the total amount of ticks aportioned to the task -- that's
    // `max_ticks` on the task itself.
    // For clarity, to avoid regressions again:
    // `tick_count` tracks total task execution across slices.
    // `tick_slice` is only the maximum work for this call into the interpreter.
    // `max_ticks` on the task is the total limit which is checked above us, outside this loop.
    //
    // Opcode stream is selected once for this execute call. This relies on pc_type staying
    // stable while a frame is running in this function.
    let program_ptr = f.program_ref() as *const Program;
    // SAFETY: pointer is resolved from either the frame-owned program or a tx-local program slot.
    // The pointer remains valid for this execute call.
    let program = unsafe { &*program_ptr };
    let pc_type = f.pc_type;
    let opcodes: &[Op] = match pc_type {
        PcType::Main => program.main_vector(),
        PcType::ForkVector(fork_vector) => program.fork_vector(fork_vector),
        PcType::Lambda(lambda_offset) => program.lambda_program(lambda_offset).main_vector(),
    };
    let opcodes_ptr = opcodes.as_ptr();
    let opcodes_len = opcodes.len();
    let tick_slice_end = (*tick_count).saturating_add(tick_slice);
    let permissions = context.authority.clone();
    while *tick_count < tick_slice_end {
        *tick_count += 1;

        // Otherwise, start poppin' opcodes.
        // We panic here if we run out of opcodes, as that means there's a bug in either the
        // compiler or in opcode execution, and we'd dearly like to know about it, not hide it.
        debug_assert_eq!(f.pc_type, pc_type, "pc_type changed mid-frame execution");
        let pc = f.pc;
        f.pc += 1;
        debug_assert!(
            (pc as usize) < opcodes_len,
            "PC out of range for opcode stream"
        );
        // SAFETY: `opcodes_ptr` comes from the frame program selected above and remains valid for
        // this execution call because we do not mutate/replace it here. `pc` is bounds-checked.
        let op = unsafe { &*opcodes_ptr.add(pc as usize) };

        match op {
            Op::If(label, environment_width) => {
                f.push_scope(ScopeType::If, *environment_width, label);
                let cond = f.pop();
                if !cond.is_true() {
                    f.jump(label);
                }
            }
            Op::Eif(label, environment_width) => {
                f.push_scope(ScopeType::Eif, *environment_width, label);
                let cond = f.pop();
                if !cond.is_true() {
                    f.jump(label);
                }
            }
            Op::While {
                jump_label: label,
                environment_width,
            } => {
                f.push_scope(ScopeType::While, *environment_width, label);
                let cond = f.pop();
                if !cond.is_true() {
                    f.jump(label);
                }
            }
            Op::IfQues(label) => {
                let label = *label;
                let cond = f.pop();
                if !cond.is_true() {
                    f.jump(&label);
                }
            }
            Op::Jump { label } => {
                let label = *label;
                f.jump(&label);
            }
            Op::WhileId {
                id,
                end_label,
                environment_width,
            } => {
                f.push_scope(ScopeType::While, *environment_width, end_label);
                let v = f.pop();
                let is_true = v.is_true();
                f.set_variable(id, v);
                if !is_true {
                    f.jump(end_label);
                }
            }
            Op::BeginForSequence { operand } => {
                let operand_offset = *operand;
                let operand = program.for_sequence_operand(operand_offset).clone();

                // Pop sequence from stack
                let sequence = f.pop();

                // Validate sequence - strings are not iterable in MOO
                if sequence.type_code() == VarType::TYPE_STR {
                    return ExecutionResult::RaiseError(
                        E_TYPE.msg("strings are not iterable; convert to list first"),
                    );
                }
                if !sequence.is_sequence() && !sequence.is_associative() {
                    return ExecutionResult::RaiseError(E_TYPE.with_msg(|| {
                        format!(
                            "for-loop requires list or map (was {})",
                            sequence.type_code().to_literal()
                        )
                    }));
                }

                let Ok(list_len) = sequence.len() else {
                    return ExecutionResult::RaiseError(
                        E_TYPE.msg("invalid sequence length in for loop"),
                    );
                };

                // If sequence is empty, jump to end immediately
                if list_len == 0 {
                    f.jump(&operand.end_label);
                    continue;
                }

                // Create ForSequence scope with initial state
                f.push_for_sequence_scope(
                    sequence,
                    operand.value_bind,
                    operand.key_bind,
                    &operand.end_label,
                    operand.environment_width,
                );
            }
            Op::IterateForSequence => {
                // Get ForSequence scope or error early
                let Some(scope) = f.get_for_sequence_scope_mut() else {
                    return ExecutionResult::RaiseError(
                        E_ARGS.msg("IterateForSequence without ForSequence scope"),
                    );
                };
                let value_bind = scope.value_bind;
                let key_bind = scope.key_bind;
                let is_associative = scope.sequence.is_associative();

                // Bounds check using cached length (avoids dereferencing on loop end)
                let len = scope.sequence.len().expect("already validated as sequence");
                if scope.current_index >= len {
                    let end_lbl = scope.end_label;
                    f.jump(&end_lbl);
                    continue;
                }

                // Get next element - maps need special key iteration, sequences use direct indexing.
                if is_associative {
                    let TypeClass::Associative(a) = scope.sequence.type_class() else {
                        unreachable!()
                    };
                    let next = match &scope.current_key {
                        Some(current_key) => a.next_after(current_key, false),
                        None => a.first(),
                    };
                    let (key, value) = match next {
                        Ok(k_v) => k_v,
                        Err(e) => return ExecutionResult::RaiseError(e),
                    };

                    // Increment index for next iteration.
                    scope.current_index += 1;

                    if let Some(key_bind) = key_bind {
                        scope.current_key = Some(key.clone());
                        f.set_variable(&value_bind, value);
                        f.set_variable(&key_bind, key);
                    } else {
                        scope.current_key = Some(key);
                        f.set_variable(&value_bind, value);
                    }
                } else {
                    let TypeClass::Sequence(s) = scope.sequence.type_class() else {
                        unreachable!()
                    };
                    let value = match s.index(scope.current_index) {
                        Ok(v) => v,
                        Err(e) => return ExecutionResult::RaiseError(e),
                    };

                    // Increment index for next iteration.
                    scope.current_index += 1;
                    let key_var =
                        key_bind.map(|key_bind| (key_bind, v_int(scope.current_index as i64)));

                    f.set_variable(&value_bind, value);
                    if let Some((key_bind, key_value)) = key_var {
                        f.set_variable(&key_bind, key_value);
                    }
                }
            }
            Op::BeginForRange { operand } => {
                let operand_offset = *operand;
                let operand = program.for_range_operand(operand_offset).clone();

                // Pop end_value and start_value from stack (stack: [from, to])
                let end_val = f.pop();
                let start_val = f.pop();

                // Validate range values are integers, floats, or objects
                if !start_val.same_numeric_type(&end_val) {
                    return ExecutionResult::RaiseError(E_TYPE.msg(
                        "for-range requires matching types (both INT, both FLOAT, or both OBJ)",
                    ));
                }

                // For object ranges, only numeric OIDs can be iterated (not UUIDs or anonymous)
                if let (Some(start_obj), Some(end_obj)) =
                    (start_val.as_object(), end_val.as_object())
                    && (!start_obj.is_oid() || !end_obj.is_oid())
                {
                    return ExecutionResult::RaiseError(
                        E_TYPE.msg("for-range requires numeric object IDs, not UUIDs"),
                    );
                }

                let scope_type = if let (Some(start), Some(end)) =
                    (start_val.as_integer(), end_val.as_integer())
                {
                    if start > end {
                        f.jump(&operand.end_label);
                        continue;
                    }
                    ScopeType::ForRangeInt {
                        current: start,
                        end,
                        loop_variable: operand.loop_variable,
                        end_label: operand.end_label,
                    }
                } else if let (Some(start), Some(end)) = (start_val.as_float(), end_val.as_float())
                {
                    if start.total_cmp(&end).is_gt() {
                        f.jump(&operand.end_label);
                        continue;
                    }
                    ScopeType::ForRangeFloat {
                        current_bits: start.to_bits(),
                        end_bits: end.to_bits(),
                        loop_variable: operand.loop_variable,
                        end_label: operand.end_label,
                    }
                } else if let (Some(start), Some(end)) =
                    (start_val.as_object(), end_val.as_object())
                {
                    let start = start.id().0;
                    let end = end.id().0;
                    if start > end {
                        f.jump(&operand.end_label);
                        continue;
                    }
                    ScopeType::ForRangeObj {
                        current: start,
                        end,
                        loop_variable: operand.loop_variable,
                        end_label: operand.end_label,
                    }
                } else {
                    return ExecutionResult::RaiseError(
                        E_TYPE.msg("invalid type in for-range iteration"),
                    );
                };

                f.push_for_range_scope(scope_type, &operand.end_label, operand.environment_width);
            }
            Op::IterateForRange => {
                enum RangeAction {
                    Jump(Label),
                    Bind(Name, Var),
                }

                let Some(scope) = f.get_for_range_scope_mut() else {
                    return ExecutionResult::RaiseError(
                        E_INVARG.msg("IterateForRange without ForRange scope"),
                    );
                };
                let action = match scope {
                    ForRangeScope::Int {
                        current,
                        end,
                        loop_variable,
                        end_label,
                    } => {
                        if *current > *end {
                            RangeAction::Jump(*end_label)
                        } else {
                            let value = *current;
                            if value == i64::MAX {
                                if *end > i64::MIN {
                                    *end -= 1;
                                }
                            } else {
                                *current += 1;
                            }
                            RangeAction::Bind(*loop_variable, v_int(value))
                        }
                    }
                    ForRangeScope::Float {
                        current_bits,
                        end_bits,
                        loop_variable,
                        end_label,
                    } => {
                        let current = f64::from_bits(*current_bits);
                        let end = f64::from_bits(*end_bits);
                        if current.total_cmp(&end).is_gt() {
                            RangeAction::Jump(*end_label)
                        } else {
                            *current_bits = (current + 1.0).to_bits();
                            RangeAction::Bind(*loop_variable, v_float(current))
                        }
                    }
                    ForRangeScope::Obj {
                        current,
                        end,
                        loop_variable,
                        end_label,
                    } => {
                        if *current > *end {
                            RangeAction::Jump(*end_label)
                        } else {
                            let value = *current;
                            if value == i32::MAX {
                                if *end > i32::MIN {
                                    *end -= 1;
                                }
                            } else {
                                *current += 1;
                            }
                            RangeAction::Bind(*loop_variable, v_obj(Obj::mk_id(value)))
                        }
                    }
                };

                match action {
                    RangeAction::Jump(end_label) => {
                        f.jump(&end_label);
                        continue;
                    }
                    RangeAction::Bind(loop_var, current_val) => {
                        f.set_variable(&loop_var, current_val);
                    }
                }
            }
            Op::Pop => {
                f.pop();
            }
            Op::Dup => {
                let v = f.peek_top().clone();
                f.push(v);
            }
            Op::Swap => {
                let len = f.valstack.len();
                if len < 2 {
                    panic!("stack underflow @ PC: {}", f.pc);
                }
                f.valstack.swap(len - 1, len - 2);
            }
            Op::ImmNone => {
                f.push(v_none());
            }
            Op::ImmBigInt(val) => {
                f.push(v_int(*val));
            }
            Op::ImmFloat(val) => {
                f.push(v_float(*val));
            }
            Op::ImmInt(val) => {
                f.push(v_int(*val as i64));
            }
            Op::ImmObjid(val) => {
                f.push(v_obj(*val));
            }
            Op::ImmSymbol(val) => {
                f.push(v_sym(*val));
            }
            Op::ImmErr(val) => {
                f.push(v_err(*val));
            }
            Op::Imm(slot) => {
                // it's questionable whether this optimization actually will be of much use
                // on a modern CPU as it could cause branch prediction misses. We should
                // benchmark this. its purpose is to avoid pointless stack ops for literals
                // that are never used (e.g. comments).
                // what might be better is an "optimization pass" that removes these prior to
                // execution, but then we'd have to cache them, etc. etc.
                match f.lookahead_ref() {
                    Some(Op::Pop) => {
                        // skip
                        f.skip();
                        continue;
                    }
                    _ => {
                        let value = program.find_literal(slot).expect("literal not found");
                        f.push(value.clone());
                    }
                }
            }
            Op::ImmType(vt) => {
                let value = *vt as u8;
                f.push(v_int(value as i64));
            }
            Op::ImmEmptyList => f.push(v_empty_list()),
            Op::ListAddTail => {
                let tail = f.pop();
                let list = std::mem::replace(f.peek_top_mut(), v_none());
                if !list.is_sequence() || list.type_code() == VarType::TYPE_STR {
                    f.pop();
                    return push_error_cold(invalid_list_append_error());
                }
                // TODO: quota check SVO_MAX_LIST_CONCAT -> E_QUOTA in list add and append
                let result = list.push_owned(&tail);
                match result {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::ListAppend => {
                let tail = f.pop();
                let list = std::mem::replace(f.peek_top_mut(), v_none());

                // Don't allow strings here.
                if list.type_code() == VarType::TYPE_STR {
                    f.pop();
                    return push_error_cold(invalid_list_append_error());
                }

                if !tail.is_sequence() || !list.is_sequence() {
                    f.pop();
                    return push_error_cold(invalid_list_append_error());
                }
                let new_list = list.append_owned(&tail);
                match new_list {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::IndexSet => {
                let (rhs, index) = (f.pop(), f.pop());
                let lhs = std::mem::replace(f.peek_top_mut(), v_none());
                let result = lhs.set_owned_vars(index, rhs, IndexMode::OneBased);
                match result {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::IndexSetAt(offset) => {
                let offset = offset.0 as usize;
                let len = f.valstack.len();
                let rhs_idx = stack_index(len, offset, f.pc);
                let index_idx = stack_index(len, offset + 1, f.pc);
                let base_idx = stack_index(len, offset + 2, f.pc);

                let rhs = std::mem::replace(&mut f.valstack[rhs_idx], v_none());
                let index = std::mem::replace(&mut f.valstack[index_idx], v_none());
                let base = std::mem::replace(&mut f.valstack[base_idx], v_none());

                let result = base.set_owned_vars(index, rhs, IndexMode::OneBased);
                match result {
                    Ok(v) => {
                        f.valstack[base_idx] = v;
                        let mut to_remove = [rhs_idx, index_idx];
                        remove_stack_indices(&mut f.valstack, &mut to_remove);
                    }
                    Err(e) => {
                        let mut to_remove = vec![rhs_idx, index_idx, base_idx];
                        if offset > 0 {
                            to_remove.push(len - 1);
                        }
                        remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                        return push_error_cold(e);
                    }
                }
            }
            Op::MakeError(offset) => {
                let code = *program.error_operand(*offset);

                // Expect an argument on stack (otherwise we would have used ImmErr)
                let err_msg = f.pop();
                let Some(err_msg) = err_msg.as_string() else {
                    return push_error_cold(invalid_error_message_error());
                };
                f.push(v_error(code.msg(err_msg)));
            }
            Op::MakeSingletonList => {
                let v = f.peek_top();
                f.poke(0, v_list(std::slice::from_ref(v)));
            }
            Op::MakeMap => {
                f.push(v_empty_map());
            }
            Op::MapInsert => {
                let (value, key) = (f.pop(), f.pop());
                let map = std::mem::replace(f.peek_top_mut(), v_none());
                let result = map.set_owned_vars(key, value, IndexMode::OneBased);
                match result {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::MakeFlyweight(num_slots) => {
                let num_slots = *num_slots;
                // Stack should be: contents, slots, delegate
                let contents = f.pop();
                // Contents must be a list
                let Some(contents) = contents.as_list() else {
                    return ExecutionResult::PushError(
                        E_TYPE.msg("invalid value for flyweight contents, must be list"),
                    );
                };
                let mut slots = Vec::with_capacity(num_slots);
                for _ in 0..num_slots {
                    let (k, v) = (f.pop(), f.pop());
                    let Ok(sym) = k.as_symbol() else {
                        return ExecutionResult::PushError(
                            E_TYPE.msg("invalid value for flyweight slot, must be a valid symbol"),
                        );
                    };
                    slots.push((sym, v));
                }
                let delegate = f.pop();
                let Some(delegate) = delegate.as_object() else {
                    return ExecutionResult::PushError(
                        E_TYPE.msg("invalid value for flyweight delegate, must be object"),
                    );
                };
                // Slots should be v_str -> value, num_slots times

                let flyweight = v_flyweight(delegate, &slots, contents.clone());
                f.push(flyweight);
            }
            Op::PutTemp => {
                f.temp = f.peek_top().clone();
            }
            Op::PutTempPop => {
                f.temp = f.pop();
            }
            Op::PushTemp => {
                let tmp = std::mem::replace(&mut f.temp, v_none());
                f.push(tmp);
            }
            Op::Eq => {
                binary_bool_op!(f, ==, features_config.use_boolean_returns);
            }
            Op::Ne => {
                binary_bool_op!(f, !=, features_config.use_boolean_returns);
            }
            Op::Gt => {
                binary_bool_op!(f, >, features_config.use_boolean_returns);
            }
            Op::Lt => {
                binary_bool_op!(f, <, features_config.use_boolean_returns);
            }
            Op::Ge => {
                binary_bool_op!(f, >=, features_config.use_boolean_returns);
            }
            Op::Le => {
                binary_bool_op!(f, <=, features_config.use_boolean_returns);
            }
            Op::In => {
                let (lhs, rhs) = (f.pop(), f.peek_top());
                let r = lhs.index_in(rhs, false, IndexMode::OneBased);
                match r {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        f.pop();
                        return ExecutionResult::PushError(e);
                    }
                }
            }
            Op::Mul => {
                binary_var_op!(f, mul);
            }
            Op::Sub => {
                binary_var_op!(f, sub);
            }
            Op::Div => {
                // Explicit division by zero check to raise E_DIV.
                // Note that LambdaMOO consider 1/0.0 to be E_DIV, but Rust permits it, creating
                // `inf`.
                let (divisor, _) = f.peek2();
                if divisor.is_zero() {
                    return push_error_cold(division_by_zero_error());
                };
                binary_var_op!(f, div);
            }
            Op::Add => {
                binary_var_op!(f, add);
            }
            Op::Exp => {
                binary_var_op!(f, pow);
            }
            Op::Mod => {
                let (divisor, _) = f.peek2();
                if divisor.is_zero() {
                    return push_error_cold(division_by_zero_error());
                };
                binary_var_op!(f, modulus);
            }
            Op::And(label) => {
                let label = *label;
                let v = f.peek_top().is_true();
                if !v {
                    f.jump(&label)
                } else {
                    f.pop();
                }
            }
            Op::Or(label) => {
                let label = *label;
                let v = f.peek_top().is_true();
                if v {
                    f.jump(&label);
                } else {
                    f.pop();
                }
            }
            Op::BitAnd => {
                binary_var_op!(f, bitand);
            }
            Op::BitOr => {
                binary_var_op!(f, bitor);
            }
            Op::BitXor => {
                binary_var_op!(f, bitxor);
            }
            Op::BitShl => {
                binary_var_op!(f, bitshl);
            }
            Op::BitShr => {
                binary_var_op!(f, bitshr);
            }
            Op::BitLShr => {
                binary_var_op!(f, bitlshr);
            }
            Op::BitNot => {
                let v = f.peek_top();
                match v.bitnot() {
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                    Ok(result) => {
                        f.poke(0, result);
                    }
                }
            }
            Op::Not => {
                let v = !f.peek_top().is_true();
                let b = if features_config.use_boolean_returns {
                    Var::mk_bool(v)
                } else {
                    v_bool_int(v)
                };
                f.poke(0, b);
            }
            Op::UnaryMinus => {
                let v = f.peek_top();
                match v.negative() {
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                    Ok(v) => f.poke(0, v),
                }
            }
            Op::Push(ident) => {
                let Some(v) = f.get_env(ident) else {
                    if let Some(var_name) = program.var_names().ident_for_name(ident) {
                        return ExecutionResult::PushError(
                            E_VARNF.with_msg(|| format!("Variable `{var_name}` not found")),
                        );
                    } else {
                        return ExecutionResult::PushError(E_VARNF.msg("Variable not found"));
                    }
                };
                f.push(v.clone());
            }
            Op::PushScope0Local(offset) => {
                let Some(v) = f.environment.get_scope0(*offset as usize) else {
                    if let Some(var_name) = program.var_names().ident_for_scope0_offset(*offset) {
                        return ExecutionResult::PushError(
                            E_VARNF.with_msg(|| format!("Variable `{var_name}` not found")),
                        );
                    }
                    return ExecutionResult::PushError(E_VARNF.msg("Variable not found"));
                };
                f.push(v.clone());
            }
            Op::Put(ident) => {
                let ident = *ident;
                let v = f.peek_top();
                f.set_variable(&ident, v.clone());
            }
            Op::PutScope0Local(offset) => {
                let v = f.peek_top();
                f.environment.set_scope0(*offset as usize, v.clone());
            }
            Op::PutPop(ident) => {
                let ident = *ident;
                let v = f.pop();
                f.set_variable(&ident, v);
            }
            Op::PutPopScope0Local(offset) => {
                let v = f.pop();
                f.environment.set_scope0(*offset as usize, v);
            }
            Op::PushRef => {
                let (key_or_index, value) = f.peek2();
                let result = value.get(key_or_index, IndexMode::OneBased);
                match result {
                    Ok(v) => f.push(v),
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::Ref => {
                let (key_or_index, value) = (f.pop(), f.peek_top());

                let result = value.get(&key_or_index, IndexMode::OneBased);
                match result {
                    Ok(v) => f.poke(0, v),
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                }
            }
            Op::RangeRef => {
                let (to, from, base) = (f.pop(), f.pop(), f.peek_top());
                let result = base.range(&from, &to, IndexMode::OneBased);
                if let Err(e) = result {
                    f.pop();
                    return push_error_cold(e);
                }
                f.poke(0, result.unwrap());
            }
            Op::RangeSet => {
                let (value, to, from) = (f.pop(), f.pop(), f.pop());
                let base = std::mem::replace(f.peek_top_mut(), v_none());
                let result = base.range_set_owned(&from, &to, &value, IndexMode::OneBased);
                if let Err(e) = result {
                    f.pop();
                    return push_error_cold(e);
                }
                f.poke(0, result.unwrap());
            }
            Op::RangeSetAt(offset) => {
                let offset = offset.0 as usize;
                let len = f.valstack.len();
                let rhs_idx = stack_index(len, offset, f.pc);
                let to_idx = stack_index(len, offset + 1, f.pc);
                let from_idx = stack_index(len, offset + 2, f.pc);
                let base_idx = stack_index(len, offset + 3, f.pc);

                let rhs = std::mem::replace(&mut f.valstack[rhs_idx], v_none());
                let to = std::mem::replace(&mut f.valstack[to_idx], v_none());
                let from = std::mem::replace(&mut f.valstack[from_idx], v_none());
                let base = std::mem::replace(&mut f.valstack[base_idx], v_none());

                let result = base.range_set_owned(&from, &to, &rhs, IndexMode::OneBased);
                match result {
                    Ok(v) => {
                        f.valstack[base_idx] = v;
                        let mut to_remove = [rhs_idx, to_idx, from_idx];
                        remove_stack_indices(&mut f.valstack, &mut to_remove);
                    }
                    Err(e) => {
                        let mut to_remove = vec![rhs_idx, to_idx, from_idx, base_idx];
                        if offset > 0 {
                            to_remove.push(len - 1);
                        }
                        remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                        return push_error_cold(e);
                    }
                }
            }
            Op::Length(offset) => {
                let v = f.peek_abs(offset.0 as usize);
                match v.len() {
                    Ok(l) => f.push(v_int(l as i64)),
                    Err(e) => return push_error_cold(e),
                }
            }
            Op::GetProp => {
                let propname = f.pop();
                let obj = std::mem::replace(f.peek_top_mut(), v_none());

                let Ok(propname) = propname.as_symbol() else {
                    return push_error_cold(invalid_property_name_error(&propname));
                };

                let value = get_property(host, &permissions, &obj, propname, features_config);
                match value {
                    Ok(v) => {
                        f.poke(0, v);
                    }
                    Err(e) => {
                        return push_error_cold(e);
                    }
                }
            }
            Op::PushGetProp => {
                let (propname, obj) = f.peek2();

                let Ok(propname) = propname.as_symbol() else {
                    return push_error_cold(invalid_property_name_error(propname));
                };

                let value = get_property(host, &permissions, obj, propname, features_config);
                match value {
                    Ok(v) => {
                        f.push(v);
                    }
                    Err(e) => {
                        return push_error_cold(e);
                    }
                }
            }
            Op::PutProp => {
                let (rhs, propname, obj) = (f.pop(), f.pop(), f.peek_top());

                let Some(obj) = obj.as_object() else {
                    return push_error_cold(invalid_property_access_error(obj));
                };
                let Ok(propname) = propname.as_symbol() else {
                    return push_error_cold(invalid_property_name_error(&propname));
                };
                let update_result = host.update_property(&permissions, &obj, propname, &rhs);

                match update_result {
                    Ok(()) => {
                        f.poke(0, rhs);
                    }
                    Err(e) => {
                        return push_error_cold(e.to_error());
                    }
                }
            }
            Op::PutPropAt {
                offset,
                jump_if_object,
            } => {
                let jump_if_object = *jump_if_object;
                let offset = offset.0 as usize;
                let len = f.valstack.len();
                let rhs_idx = stack_index(len, offset, f.pc);
                let prop_idx = stack_index(len, offset + 1, f.pc);
                let base_idx = stack_index(len, offset + 2, f.pc);

                let rhs = std::mem::replace(&mut f.valstack[rhs_idx], v_none());
                let propname = std::mem::replace(&mut f.valstack[prop_idx], v_none());
                let base = std::mem::replace(&mut f.valstack[base_idx], v_none());
                let should_jump = base.as_object().is_some();

                let Ok(propname) = propname.as_symbol() else {
                    let mut to_remove = vec![rhs_idx, prop_idx, base_idx];
                    if offset > 0 {
                        to_remove.push(len - 1);
                    }
                    remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                    return push_error_cold(invalid_property_name_error(&propname));
                };

                let update_result = if let Some(obj) = base.as_object() {
                    host.update_property(&permissions, &obj, propname, &rhs)
                        .map(|()| base)
                        .map_err(|e| e.to_error())
                } else if let Some(flyweight) = base.as_flyweight() {
                    if propname == *DELEGATE_SYM || propname == *SLOTS_SYM {
                        let mut to_remove = vec![rhs_idx, prop_idx, base_idx];
                        if offset > 0 {
                            to_remove.push(len - 1);
                        }
                        remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                        return push_error_cold(
                            E_TYPE.with_msg(|| format!("Invalid property name: {propname}")),
                        );
                    }
                    let updated = flyweight.add_slot(propname, rhs);
                    Ok(Var::from_flyweight(updated))
                } else {
                    Err(invalid_property_access_error(&base))
                };

                match update_result {
                    Ok(updated_base) => {
                        f.valstack[base_idx] = updated_base;
                        let mut to_remove = vec![rhs_idx, prop_idx];
                        remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                        if should_jump {
                            f.jump(&jump_if_object);
                        }
                    }
                    Err(e) => {
                        let mut to_remove = vec![rhs_idx, prop_idx, base_idx];
                        if offset > 0 {
                            to_remove.push(len - 1);
                        }
                        remove_stack_indices(&mut f.valstack, to_remove.as_mut_slice());
                        return push_error_cold(e);
                    }
                }
            }
            Op::Fork { id, fv_offset } => {
                let (id, fv_offset) = (*id, *fv_offset);
                // Delay time should be on stack
                let time = f.pop();

                let time = if let Some(i) = time.as_integer() {
                    i as f64
                } else if let Some(f) = time.as_float() {
                    f
                } else {
                    return ExecutionResult::PushError(
                        E_TYPE.msg("invalid value for delay time in fork"),
                    );
                };

                if time < 0.0 {
                    return ExecutionResult::PushError(
                        E_INVARG.msg("invalid value for delay time in fork"),
                    );
                }
                let delay = (time != 0.0).then(|| Duration::from_secs_f64(time));

                return ExecutionResult::TaskStartFork(delay, id, fv_offset);
            }
            Op::Pass => {
                let args = f.pop();
                let Some(args) = args.as_list() else {
                    return push_error_cold(invalid_verb_target_error(&args));
                };
                return prepare_pass_verb(host, context, args.clone());
            }
            Op::CallVerb => {
                let (args, verb, obj) = (f.pop(), f.pop(), f.pop());
                let Some(l) = args.as_list() else {
                    return push_error_cold(invalid_verb_target_error(&args));
                };
                let Ok(verb) = verb.as_symbol() else {
                    return push_error_cold(invalid_verb_name_error(&verb));
                };
                return prepare_verb_dispatch(
                    host,
                    context,
                    f,
                    features_config.type_dispatch,
                    obj,
                    verb,
                    l.clone(),
                )
                .unwrap_or_else(ExecutionResult::PushError);
            }
            Op::Return => {
                let ret_val = f.pop();
                return ExecutionResult::Return(ret_val);
            }
            Op::Return0 => {
                return ExecutionResult::Return(v_int(0));
            }
            Op::Done => {
                return ExecutionResult::Return(v_bool(false));
            }
            Op::FuncCall { id } => {
                let builtin = *id;
                // Pop arguments, should be a list.
                let args = f.pop();
                let Some(args) = args.as_list() else {
                    return ExecutionResult::PushError(
                        E_ARGS.msg("invalid value for function call"),
                    );
                };
                return ExecutionResult::DispatchBuiltin {
                    builtin,
                    arguments: args.iter().collect(),
                };
            }
            Op::PushCatchLabel(label) => {
                let label = *label;
                // Get the error codes, which is either a list of error codes or Any.
                let error_codes = f.pop();

                // The scope above us has to be a TryCatch, and we need to push into that scope
                // the code list that we're going to execute.
                if let Some(error_codes) = error_codes.as_list() {
                    let error_codes = error_codes.iter().map(|v| {
                        let Some(e) = v.as_error() else {
                            panic!("Error codes list contains non-error code");
                        };
                        e.clone()
                    });
                    f.push_catch(CatchType::Errors(error_codes.into_iter().collect()), label);
                } else if error_codes.as_integer() == Some(0) {
                    f.push_catch(CatchType::Any, label);
                } else {
                    panic!("Invalid error codes list");
                }
            }
            Op::TryFinally {
                end_label,
                environment_width,
            } => {
                f.push_scope(
                    ScopeType::TryFinally(*end_label),
                    *environment_width,
                    end_label,
                );
            }
            Op::TryCatch { end_label, .. } => {
                let end_label = *end_label;
                let catches = f.take_catch_stack();
                f.push_non_var_scope(ScopeType::TryCatch(catches), &end_label);
            }
            Op::TryExcept {
                environment_width,
                end_label,
                ..
            } => {
                let catches = f.take_catch_stack();
                f.push_scope(ScopeType::TryCatch(catches), *environment_width, end_label);
            }
            Op::EndExcept(label) => {
                let label = *label;
                let handler = f.pop_scope().expect("Missing handler for try/catch/except");
                let ScopeType::TryCatch(..) = handler else {
                    panic!("Handler is not a catch handler",);
                };
                f.jump(&label);
            }
            Op::EndCatch(label) => {
                let label = *label;

                let stack_top = f.pop();
                let handler = f.pop_scope().expect("Missing handler for try/catch/except");
                let ScopeType::TryCatch(_) = handler else {
                    panic!("Handler is not a catch handler",);
                };
                f.jump(&label);
                f.push(stack_top);
            }
            Op::EndFinally => {
                // Execution of the block completed successfully, so we can just continue with
                // fall-through into the FinallyContinue block
                // Pop the scope that was pushed by TryFinally
                let scope = f.pop_scope().expect("Missing scope for try/finally");
                if !matches!(scope, ScopeType::TryFinally(_)) {
                    panic!("EndFinally without TryFinally scope");
                }
                f.push_finally_reason(FinallyReason::Fallthrough);
            }
            //
            Op::FinallyContinue => {
                let why = f.pop_finally_reason().expect("Missing finally reason");
                match why {
                    FinallyReason::Fallthrough => continue,
                    FinallyReason::Abort => {
                        panic!("Unexpected FINALLY_ABORT in FinallyContinue")
                    }
                    FinallyReason::Raise(_)
                    | FinallyReason::Return(_)
                    | FinallyReason::Exit { .. } => {
                        return ExecutionResult::Unwind(why);
                    }
                }
            }
            Op::BeginScope {
                num_bindings,
                end_label,
            } => {
                f.push_scope(ScopeType::Block, *num_bindings, end_label);
            }
            Op::EndScope { .. } => {
                let Some(..) = f.pop_scope() else {
                    panic!(
                        "EndScope without a scope @ {} ({})",
                        f.pc,
                        f.find_line_no(f.pc).unwrap_or(0)
                    );
                };
            }
            Op::ExitId(label) => {
                let label = *label;
                f.jump(&label);
                continue;
            }
            Op::Exit { stack, label } => {
                return ExecutionResult::Unwind(FinallyReason::Exit {
                    stack: *stack,
                    label: *label,
                });
            }
            Op::Scatter(sa) => {
                // Get the scatter table and the values to assign
                let sa = *sa;
                let table = program.scatter_table(sa);
                let rhs_values = {
                    let rhs = f.peek_top();
                    let Some(rhs_values) = rhs.as_list() else {
                        let scatter_err = E_TYPE
                            .with_msg(|| format!("Invalid value for scatter: {}", to_literal(rhs)));
                        f.pop();
                        return push_error_cold(scatter_err);
                    };
                    rhs_values.iter_ref().cloned().collect::<Vec<_>>()
                };

                // Use the shared scatter assignment logic
                let result = scatter_assign(table, rhs_values.iter(), |name, value| {
                    f.set_variable(name, value);
                });

                match result.result {
                    Err(e) => {
                        f.pop();
                        return push_error_cold(e);
                    }
                    Ok(()) => {
                        // Jump to appropriate location based on whether defaults are needed
                        let jump_label = result.first_default_label.unwrap_or(table.done);
                        f.jump(&jump_label);
                    }
                }
            }
            Op::CheckListForSplice => {
                if !f.peek_top().is_sequence() {
                    f.pop();
                    return push_error_cold(invalid_list_splice_error());
                }
            }

            // Execution of the comprehension is:
            //
            //  Op::BeginComprehension (enter scope)
            //      pushes empty list & scope to stack
            //  set variable to start of index
            //  push end of index to stack
            //  begin loop (set label X)
            //      Op:ComprehendRange:
            //        pop end of range index from stack
            //        get index from var
            //        if index > end of range, jmp to end label (Y)
            //        push index
            //      execute producer expr
            //      Op::ContinueRange
            //          pop result
            //          pop list from stack
            //          append result to list, push back
            //          push end of range index to stack
            //          push cur index to stack
            //      jmp X
            //  end loop / scope
            //  (set label Y)
            Op::BeginComprehension(_, end_label, _) => {
                let end_label = *end_label;
                f.push(v_empty_list());
                f.push_scope(ScopeType::Comprehension, 1, &end_label);
            }
            Op::ComprehendRange(offset) => {
                let offset = *offset;
                let range_comprehension = program.range_comprehension(offset);
                let end_of_range_register = range_comprehension.end_of_range_register;
                let position_register = range_comprehension.position;
                let end_label = range_comprehension.end_label;
                let end_of_range = f.get_env(&end_of_range_register).unwrap();
                let position = f
                    .get_env(&position_register)
                    .expect("Bad range position variable in range comprehension");
                if !position.le(end_of_range) {
                    f.jump(&end_label);
                }
            }
            Op::ComprehendList(offset) => {
                let offset = *offset;
                let list_comprehension = program.list_comprehension(offset);
                let list_register = list_comprehension.list_register;
                let position_register = list_comprehension.position_register;
                let item_variable = list_comprehension.item_variable;
                let end_label = list_comprehension.end_label;
                let list = f.get_env(&list_register).unwrap();
                let position = f.get_env(&position_register).unwrap();
                let Some(position) = position.as_integer() else {
                    return push_error_cold(E_TYPE.msg("invalid value in list comprehension"));
                };
                if position > list.len().unwrap() as i64 {
                    f.jump(&end_label);
                } else {
                    let Ok(item) = list.index(&v_int(position), IndexMode::OneBased) else {
                        return push_error_cold(E_RANGE.msg("invalid index in list comprehension"));
                    };
                    f.set_variable(&item_variable, item);
                }
            }
            Op::FilterComprehension(label) => {
                let label = *label;
                let cond = f.pop();
                if !cond.is_true() {
                    f.jump(&label);
                }
            }
            Op::ContinueComprehension(id) => {
                let id = *id;
                let result = f.pop();
                let list = f.pop();
                let position = f
                    .get_env(&id)
                    .expect("Bad range position variable in range comprehension");
                let Ok(new_position) = position.add(&v_int(1)) else {
                    return push_error_cold(E_TYPE.msg("invalid value in list comprehension"));
                };
                let Ok(new_list) = list.push_owned(&result) else {
                    return push_error_cold(E_TYPE.msg("invalid value in list comprehension"));
                };
                f.set_variable(&id, new_position);
                f.push(new_list);
            }
            Op::Capture(var_name) => {
                let var_name = *var_name;
                // Capture a variable from the current environment for lambda closure
                if let Some(value) = f.get_env(&var_name) {
                    f.push_capture(var_name, value.clone());
                } else {
                    // Variable not found - capture None/v_none
                    f.push_capture(var_name, v_none());
                }
            }
            Op::MakeLambda {
                scatter_offset,
                program_offset,
                self_var,
                num_captured,
            } => {
                let (scatter_offset, program_offset, self_var, num_captured) =
                    (*scatter_offset, *program_offset, *self_var, *num_captured);
                // Retrieve the scatter specification for lambda parameters
                let scatter_spec = program.scatter_table(scatter_offset).clone();

                // Retrieve the pre-compiled Program for the lambda body
                let lambda_program = program.lambda_program(program_offset).clone();

                // Build captured environment from the capture stack
                let captured_env = if num_captured == 0 {
                    vec![]
                } else {
                    // Take the last num_captured items from the capture stack
                    let stack_len = f.capture_stack_len();
                    if stack_len < num_captured as usize {
                        return push_error_cold(
                            E_ARGS.msg("insufficient captured variables on stack"),
                        );
                    }

                    // Extract captured variables and convert to environment format
                    let captured_vars = f.drain_captures_from(stack_len - num_captured as usize);

                    build_captured_environment(&captured_vars, &lambda_program)
                };

                // Create the lambda value with self-reference information
                // Self-reference will be handled during lambda activation
                let lambda_var =
                    Var::mk_lambda(scatter_spec, lambda_program, captured_env, self_var);

                // Push lambda value onto the stack
                f.push(lambda_var);
            }
            Op::CallLambda => {
                // Pop arguments list and lambda value from stack
                let args_list = f.pop();
                let lambda_var = f.pop();

                // Verify we have a lambda value
                let Some(lambda) = lambda_var.as_lambda() else {
                    return ExecutionResult::PushError(E_TYPE.msg("expected lambda value"));
                };

                // Convert args list to List type for dispatch
                let Some(args) = args_list.as_list() else {
                    return ExecutionResult::PushError(E_ARGS.msg("expected argument list"));
                };
                let args = args.clone();

                // Request lambda dispatch - this will create a new activation
                return ExecutionResult::DispatchLambda {
                    lambda: lambda.clone(),
                    arguments: args,
                };
            }
        }
    }
    // We don't usually get here because most execution paths return before we hit the end of
    // the loop. But if we do, we need to return More so the scheduler knows to keep feeding
    // us.
    ExecutionResult::More
}

#[allow(clippy::too_many_arguments)]
fn get_property<H: VmHost>(
    host: &mut H,
    permissions: &TaskPermissions,
    obj: &Var,
    propname: Symbol,
    features_config: &FeaturesConfig,
) -> Result<Var, Error> {
    // Fast path: Obj is by far the most common case for property access
    if let Some(obj_ref) = obj.as_object() {
        return host
            .retrieve_property(permissions, &obj_ref, propname)
            .map_err(|e| e.to_error());
    }

    // Flyweight case
    if let Some(flyweight) = obj.as_flyweight() {
        // If propname is `delegate`, return the delegate object.
        // If the propname is `slots`, return the slots list.
        // Otherwise, return the value from the slots list.
        let value = if propname == *DELEGATE_SYM {
            v_obj(*flyweight.delegate())
        } else if propname == *SLOTS_SYM {
            let slots: Vec<_> = flyweight
                .slots_storage()
                .iter()
                .map(|(k, v)| {
                    (
                        if features_config.use_symbols_in_builtins {
                            v_sym(*k)
                        } else {
                            v_arc_str(k.as_arc_str())
                        },
                        v.clone(),
                    )
                })
                .collect();
            v_map(&slots)
        } else if let Some(result) = flyweight.get_slot(&propname) {
            result.clone()
        } else {
            // Now check the delegate
            let delegate = flyweight.delegate();
            let result = host.retrieve_property(permissions, delegate, propname);
            match result {
                Ok(v) => v,
                Err(e) => return Err(e.to_error()),
            }
        };
        return Ok(value);
    }

    // Invalid target for property access
    Err(E_INVIND.with_msg(|| format!("Invalid value for property access: {}", to_literal(obj))))
}
