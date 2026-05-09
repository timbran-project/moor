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

use crate::environment::Environment;

/// Stable handle to a program residing in a task-local program cache.
/// The pointer is valid for the duration of the owning task's transaction.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ProgramSlot {
    pub program_ptr: usize,
    pub global_width: usize,
    pub main_max_stack: usize,
    pub main_max_scope_depth: usize,
}
use crate::vm_unwind::FinallyReason;
use moor_compiler::{Label, Op, Program};
use moor_var::{
    Error, Var,
    VarType::TYPE_NONE,
    program::{
        labels::Offset,
        names::{GlobalName, Name},
    },
    v_empty_str, v_none, v_nothing,
};
use std::cmp::max;
use std::sync::LazyLock;
use strum::EnumCount;

/// The MOO stack-frame specific portions of the activation:
///   the value stack, local variables, program, program counter, handler stack, etc.
#[derive(Debug, Clone, PartialEq)]
pub struct MooStackFrame {
    /// The program of the verb that is currently being executed.
    pub program: Option<Program>,
    pub program_ptr: Option<usize>,
    /// The program counter.
    pub pc: usize,
    /// Where is the PC pointing to?
    pub pc_type: PcType,
    /// The values of the variables currently in scope, by their offset.
    pub environment: Environment,
    /// The value stack.
    pub valstack: Vec<Var>,
    /// A stack of active scopes. Used for catch and finally blocks and in the future for lexical
    /// scoping as well.
    pub scope_stack: Vec<Scope>,
    /// Scratch space for PushTemp and PutTemp opcodes.
    pub temp: Var,
    /// Scratch space for constructing the catch handlers for a forthcoming try scope.
    pub catch_stack: Vec<(CatchType, Label)>,
    /// Scratch space for holding finally-reasons to be popped off the stack when a finally block
    /// is ended.
    pub finally_stack: Vec<FinallyReason>,
    /// Stack for captured variables during lambda creation
    pub capture_stack: Vec<(Name, Var)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PcType {
    Main,
    ForkVector(Offset),
    Lambda(Offset),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CatchType {
    Any,
    Errors(Vec<Error>),
}

/// The kinds of block scopes that can be entered and exited, which far now are just catch and
/// finally blocks.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScopeType {
    /// A scope that attempts to execute a block of code, and then executes the block of code at
    /// "Label" regardless of whether the block of code succeeded or failed.
    /// Note that `return` and `exit` are not considered failures.
    TryFinally(Label),
    TryCatch(Vec<(CatchType, Label)>),
    If,
    Eif,
    While,
    For,
    /// For-sequence iteration state stored in scope instead of on stack
    /// For sequences: current_index tracks position, current_key is None
    /// For maps: current_key tracks the current key for efficient iteration
    ForSequence {
        sequence: Var,
        current_index: usize,
        current_key: Option<Var>,
        value_bind: Name,
        key_bind: Option<Name>,
        end_label: Label,
    },
    /// Integer for-range iteration state stored in scope instead of on stack.
    ForRangeInt {
        current: i64,
        end: i64,
        loop_variable: Name,
        end_label: Label,
    },
    /// Floating point for-range iteration state stored in scope instead of on stack.
    ForRangeFloat {
        current_bits: u64,
        end_bits: u64,
        loop_variable: Name,
        end_label: Label,
    },
    /// Numeric object for-range iteration state stored in scope instead of on stack.
    ForRangeObj {
        current: i32,
        end: i32,
        loop_variable: Name,
        end_label: Label,
    },
    Block,
    Comprehension,
}

/// A scope is a record of the current size of the valstack when it was created, and are
/// enter and exit scopes.
/// On entry, the current size of the valstack is stored in `valstack_pos`.
/// On exit, the valstack is eaten back to that size.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Scope {
    pub scope_type: ScopeType,
    pub valstack_pos: usize,
    pub start_pos: usize,
    pub end_pos: usize,
    /// True if this scope has a variable environment.
    pub environment: bool,
}

static PARSE_EMPTY_STR: LazyLock<Var> = LazyLock::new(v_empty_str);
static PARSE_NOTHING: LazyLock<Var> = LazyLock::new(v_nothing);

impl MooStackFrame {
    #[inline]
    fn valstack_for_max_depth(max_depth: usize) -> Vec<Var> {
        Vec::with_capacity(max_depth)
    }

    #[inline]
    fn main_valstack_for_program(program: &Program) -> Vec<Var> {
        Self::valstack_for_max_depth(program.main_max_stack())
    }

    #[inline]
    fn scope_stack_for_max_depth(max_depth: usize) -> Vec<Scope> {
        Vec::with_capacity(max_depth)
    }

    #[inline]
    fn main_scope_stack_for_program(program: &Program) -> Vec<Scope> {
        Self::scope_stack_for_max_depth(program.main_max_scope_depth())
    }

    #[inline]
    fn debug_assert_resolvable_program(&self) {
        debug_assert!(
            self.program.is_some() || self.program_ptr.is_some(),
            "MooStackFrame missing both materialized program and program_ptr"
        );
    }

    /// Create a new MOO stack frame with default environment.
    #[allow(dead_code)]
    pub fn new(program: Program) -> Self {
        let width = max(program.var_names().global_width(), GlobalName::COUNT);
        let valstack = Self::main_valstack_for_program(&program);
        let scope_stack = Self::main_scope_stack_for_program(&program);
        Self {
            program: Some(program),
            program_ptr: None,
            environment: Environment::with_initial_scope(width),
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Vec::new(),
            finally_stack: Vec::new(),
            capture_stack: Vec::new(),
        }
    }

    /// Create frame with all globals pre-populated (for top-level verb calls).
    #[inline]
    pub fn new_with_all_globals(
        program: Program,
        player: Var,
        this: Var,
        caller: Var,
        verb: Var,
        args: Var,
        argstr: Var,
    ) -> Self {
        let width = max(program.var_names().global_width(), GlobalName::COUNT);
        let valstack = Self::main_valstack_for_program(&program);
        let scope_stack = Self::main_scope_stack_for_program(&program);
        Self {
            program: Some(program),
            program_ptr: None,
            environment: Environment::with_call_globals(
                player, this, caller, verb, args, argstr, width,
            ),
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Vec::new(),
            finally_stack: Vec::new(),
            capture_stack: Vec::new(),
        }
    }

    /// Create frame with core globals and parsing globals copied from source (for nested calls).
    #[inline]
    pub fn new_with_globals_from_source(
        program: Program,
        player: Var,
        this: Var,
        caller: Var,
        verb: Var,
        args: Var,
        source_frame: &MooStackFrame,
    ) -> Self {
        let width = max(program.var_names().global_width(), GlobalName::COUNT);
        let valstack = Self::main_valstack_for_program(&program);
        let scope_stack = Self::main_scope_stack_for_program(&program);
        Self {
            program: Some(program),
            program_ptr: None,
            environment: Environment::with_call_globals_copy_parsing(
                player,
                this,
                caller,
                verb,
                args,
                &source_frame.environment,
                width,
            ),
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Vec::new(),
            finally_stack: Vec::new(),
            capture_stack: Vec::new(),
        }
    }

    /// Create a new frame with a pre-built environment (for lambdas).
    /// Uses v_none() as sentinel for uninitialized slots.
    pub fn with_environment(program: Program, environment: Vec<Vec<Var>>) -> Self {
        // Ensure global scope exists with proper width for global variables
        let global_width = max(program.var_names().global_width(), GlobalName::COUNT);
        let valstack = Self::main_valstack_for_program(&program);
        let scope_stack = Self::main_scope_stack_for_program(&program);
        let env = if environment.is_empty() {
            // No captured environment - just create global scope
            Environment::with_initial_scope(global_width)
        } else {
            let mut env = Environment::new();
            // Merge captured environment, ensuring scope 0 has enough room for globals
            for (scope_idx, scope) in environment.into_iter().enumerate() {
                let width = if scope_idx == 0 {
                    max(scope.len(), global_width)
                } else {
                    scope.len()
                };
                env.push_scope(width);
                for (i, var) in scope.into_iter().enumerate() {
                    if !var.is_none() {
                        env.set(env.len() - 1, i, var);
                    }
                }
            }
            env
        };

        Self {
            program: Some(program),
            program_ptr: None,
            environment: env,
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Default::default(),
            finally_stack: Default::default(),
            capture_stack: Default::default(),
        }
    }

    #[inline]
    fn resolved_program_ptr(&self) -> *const Program {
        if let Some(program) = &self.program {
            return program as *const Program;
        }
        self.program_ptr
            .map(|ptr| ptr as *const Program)
            .expect("MooStackFrame missing both program and program_ptr")
    }

    #[inline]
    fn resolved_program(&self) -> &Program {
        // SAFETY: pointer comes either from self-owned Program or task-owned program cache.
        // It is used only for immediate, read-only access.
        unsafe { &*self.resolved_program_ptr() }
    }

    #[inline]
    fn try_resolved_program(&self) -> Option<&Program> {
        if let Some(program) = &self.program {
            return Some(program);
        }
        let ptr = self.program_ptr? as *const Program;
        // SAFETY: pointer refers to the task-owned program cache or frame-owned program.
        Some(unsafe { &*ptr })
    }

    pub fn program_ref(&self) -> &Program {
        self.debug_assert_resolvable_program();
        self.resolved_program()
    }

    pub fn materialize_program_from_slot(&mut self) {
        self.debug_assert_resolvable_program();
        if self.program.is_some() {
            self.program_ptr = None;
            return;
        }
        let Some(ptr) = self.program_ptr else {
            return;
        };
        // SAFETY: program_ptr points to a stable allocation in task-owned program cache.
        self.program = Some(unsafe { (&*(ptr as *const Program)).clone() });
        self.program_ptr = None;
    }

    pub fn materialize_program_for_handoff(&mut self) {
        self.debug_assert_resolvable_program();
        if self.program.is_none() {
            self.program = Some(self.program_ref().clone());
        }
        self.program_ptr = None;
    }

    pub fn new_with_all_globals_from_slot(
        program_slot: ProgramSlot,
        player: Var,
        this: Var,
        caller: Var,
        verb: Var,
        args: Var,
        argstr: Var,
    ) -> Self {
        let width = max(program_slot.global_width, GlobalName::COUNT);
        let valstack = Self::valstack_for_max_depth(program_slot.main_max_stack);
        let scope_stack = Self::scope_stack_for_max_depth(program_slot.main_max_scope_depth);
        Self {
            program: None,
            program_ptr: Some(program_slot.program_ptr),
            environment: Environment::with_call_globals(
                player, this, caller, verb, args, argstr, width,
            ),
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Vec::new(),
            finally_stack: Vec::new(),
            capture_stack: Vec::new(),
        }
    }

    pub fn new_with_globals_from_source_slot(
        program_slot: ProgramSlot,
        player: Var,
        this: Var,
        caller: Var,
        verb: Var,
        args: Var,
        source_frame: &MooStackFrame,
    ) -> Self {
        let width = max(program_slot.global_width, GlobalName::COUNT);
        let valstack = Self::valstack_for_max_depth(program_slot.main_max_stack);
        let scope_stack = Self::scope_stack_for_max_depth(program_slot.main_max_scope_depth);
        Self {
            program: None,
            program_ptr: Some(program_slot.program_ptr),
            environment: Environment::with_call_globals_copy_parsing(
                player,
                this,
                caller,
                verb,
                args,
                &source_frame.environment,
                width,
            ),
            pc: 0,
            pc_type: PcType::Main,
            temp: v_none(),
            valstack,
            scope_stack,
            catch_stack: Vec::new(),
            finally_stack: Vec::new(),
            capture_stack: Vec::new(),
        }
    }

    pub fn opcodes(&self) -> &[Op] {
        let program = self.resolved_program();
        match self.pc_type {
            PcType::Main => program.main_vector(),
            PcType::ForkVector(fork_vector) => program.fork_vector(fork_vector),
            PcType::Lambda(lambda_offset) => program.lambda_program(lambda_offset).main_vector(),
        }
    }

    pub fn find_line_no(&self, pc: usize) -> Option<usize> {
        let program = self.try_resolved_program()?;
        match self.pc_type {
            PcType::Main => Some(program.line_num_for_position(pc, 0)),
            PcType::ForkVector(fv) => Some(program.fork_line_num_for_position(fv, pc)),
            PcType::Lambda(lambda_offset) => {
                let lambda_program = program.lambda_program(lambda_offset);
                Some(lambda_program.line_num_for_position(pc, 0))
            }
        }
    }

    pub fn set_gvar(&mut self, gname: GlobalName, value: Var) {
        let pos = gname as usize;
        self.environment.set_scope0(pos, value);
    }

    pub fn get_gvar(&self, gname: GlobalName) -> Option<&Var> {
        if let Some(v) = self.environment.get_scope0(gname as usize) {
            return Some(v);
        }

        match gname {
            GlobalName::dobj | GlobalName::iobj => Some(&PARSE_NOTHING),
            GlobalName::argstr
            | GlobalName::dobjstr
            | GlobalName::prepstr
            | GlobalName::iobjstr => Some(&PARSE_EMPTY_STR),
            _ => None,
        }
    }

    #[inline(always)]
    pub fn set_variable(&mut self, id: &Name, v: Var) {
        // This is a "trust us we know what we're doing" use of the explicit offset without check
        // into the names list like we did before. If the compiler produces garbage, it gets what
        // it deserves.
        debug_assert_ne!(v.type_code(), TYPE_NONE, "Setting variable to TYPE_NONE");
        let offset = id.0 as usize;
        if id.1 == 0 {
            self.environment.set_scope0(offset, v);
            return;
        }

        self.environment.set(id.1 as usize, offset, v);
    }

    /// Return the value of a local variable.
    #[inline(always)]
    pub fn get_env(&self, id: &Name) -> Option<&Var> {
        let scope_idx = id.1 as usize;
        let var_idx = id.0 as usize;

        if scope_idx == 0 {
            if let Some(v) = self.environment.get_scope0(var_idx) {
                return Some(v);
            }
        } else {
            return self.environment.get(scope_idx, var_idx);
        }

        match GlobalName::from_repr(var_idx) {
            Some(GlobalName::dobj) | Some(GlobalName::iobj) => Some(&PARSE_NOTHING),
            Some(GlobalName::argstr)
            | Some(GlobalName::dobjstr)
            | Some(GlobalName::prepstr)
            | Some(GlobalName::iobjstr) => Some(&PARSE_EMPTY_STR),
            _ => None,
        }
    }

    pub fn switch_to_fork_vector(&mut self, fork_vector: Offset) {
        let max_stack = self.program_ref().fork_vector_max_stack(fork_vector);
        let max_scope_depth = self.program_ref().fork_vector_max_scope_depth(fork_vector);
        self.pc_type = PcType::ForkVector(fork_vector);
        self.pc = 0;
        self.valstack.reserve(max_stack);
        self.scope_stack.reserve(max_scope_depth);
    }

    pub fn lookahead_ref(&self) -> Option<&Op> {
        let program = self.resolved_program();
        match self.pc_type {
            PcType::Main => program.main_vector().get(self.pc),
            PcType::ForkVector(fork_vector) => program.fork_vector(fork_vector).get(self.pc),
            PcType::Lambda(lambda_offset) => program
                .lambda_program(lambda_offset)
                .main_vector()
                .get(self.pc),
        }
    }

    pub fn skip(&mut self) {
        self.pc += 1;
    }

    #[inline(always)]
    pub fn pop(&mut self) -> Var {
        self.valstack
            .pop()
            .unwrap_or_else(|| panic!("stack underflow @ PC: {}", self.pc))
    }

    #[inline(always)]
    pub fn push(&mut self, v: Var) {
        self.valstack.push(v)
    }

    #[inline(always)]
    pub fn peek_top(&self) -> &Var {
        self.valstack.last().expect("stack underflow")
    }

    #[inline(always)]
    pub fn peek_top_mut(&mut self) -> &mut Var {
        self.valstack.last_mut().expect("stack underflow")
    }

    pub fn peek_abs(&self, amt: usize) -> &Var {
        &self.valstack[amt]
    }

    pub fn peek2(&self) -> (&Var, &Var) {
        let l = self.valstack.len();
        let (a, b) = (&self.valstack[l - 1], &self.valstack[l - 2]);
        (a, b)
    }

    #[inline(always)]
    pub fn poke(&mut self, amt: usize, v: Var) {
        let l = self.valstack.len();
        self.valstack[l - amt - 1] = v;
    }

    pub fn label_position(&self, label_id: Label) -> usize {
        self.resolved_program().jump_label(label_id).position.0 as usize
    }

    pub fn jump(&mut self, label_id: &Label) {
        let position = self.label_position(*label_id);

        self.pc = position;
        // Pop all scopes that the jump target is outside of
        while let Some(scope) = self.scope_stack.last() {
            // If jump target is within the scope range, keep the scope
            if self.pc >= scope.start_pos && self.pc < scope.end_pos {
                break;
            }

            // Jump target is outside scope range - pop it
            self.pop_scope();
        }
    }

    /// Enter a new lexical scope and/or try/catch handling block.
    pub fn push_scope(&mut self, scope: ScopeType, scope_width: u16, end_label: &Label) {
        let end_pos = self.resolved_program().jump_label(*end_label).position.0 as usize;
        let start_pos = self.pc;
        self.scope_stack.push(Scope {
            scope_type: scope,
            valstack_pos: self.valstack.len(),
            start_pos,
            end_pos,
            environment: true,
        });
        self.environment.push_scope(scope_width as usize);
    }

    /// Enter a scope which does not restrict stack of environment size, purely for catch expressions
    /// The scope is just used for unwinding to the catch handler purposes.
    pub fn push_non_var_scope(&mut self, scope: ScopeType, end_label: &Label) {
        let end_pos = self.resolved_program().jump_label(*end_label).position.0 as usize;
        let start_pos = self.pc;
        self.scope_stack.push(Scope {
            scope_type: scope,
            valstack_pos: self.valstack.len(),
            start_pos,
            end_pos,
            environment: false,
        });
    }

    pub fn pop_scope(&mut self) -> Option<Scope> {
        let scope = self.scope_stack.pop()?;
        if scope.environment {
            self.environment.pop_scope();
        }
        self.valstack.truncate(scope.valstack_pos);
        Some(scope)
    }

    /// Enter a ForSequence scope that holds iteration state
    pub fn push_for_sequence_scope(
        &mut self,
        sequence: Var,
        value_bind: Name,
        key_bind: Option<Name>,
        end_label: &Label,
        environment_width: u16,
    ) {
        let end_pos = self.resolved_program().jump_label(*end_label).position.0 as usize;
        let start_pos = self.pc;
        let scope_type = ScopeType::ForSequence {
            sequence,
            current_index: 0,
            current_key: None,
            value_bind,
            key_bind,
            end_label: *end_label,
        };
        self.scope_stack.push(Scope {
            scope_type,
            valstack_pos: self.valstack.len(),
            start_pos,
            end_pos,
            environment: true,
        });
        self.environment.push_scope(environment_width as usize);
    }

    /// Get the current ForSequence scope for iteration
    pub fn get_for_sequence_scope_mut(&mut self) -> Option<&mut ScopeType> {
        for scope in self.scope_stack.iter_mut().rev() {
            if matches!(scope.scope_type, ScopeType::ForSequence { .. }) {
                return Some(&mut scope.scope_type);
            }
        }
        None
    }

    /// Enter a ForRange scope that holds iteration state
    pub fn push_for_range_scope(
        &mut self,
        scope_type: ScopeType,
        end_label: &Label,
        environment_width: u16,
    ) {
        debug_assert!(matches!(
            scope_type,
            ScopeType::ForRangeInt { .. }
                | ScopeType::ForRangeFloat { .. }
                | ScopeType::ForRangeObj { .. }
        ));
        let end_pos = self.resolved_program().jump_label(*end_label).position.0 as usize;
        let start_pos = self.pc;
        self.scope_stack.push(Scope {
            scope_type,
            valstack_pos: self.valstack.len(),
            start_pos,
            end_pos,
            environment: true,
        });
        self.environment.push_scope(environment_width as usize);
    }

    /// Get the current ForRange scope for iteration
    pub fn get_for_range_scope_mut(&mut self) -> Option<&mut ScopeType> {
        for scope in self.scope_stack.iter_mut().rev() {
            if matches!(
                scope.scope_type,
                ScopeType::ForRangeInt { .. }
                    | ScopeType::ForRangeFloat { .. }
                    | ScopeType::ForRangeObj { .. }
            ) {
                return Some(&mut scope.scope_type);
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_compiler::{CompileOptions, compile};
    use moor_var::{Obj, v_empty_list, v_empty_str, v_none, v_obj};

    fn call_frame(program: Program) -> MooStackFrame {
        MooStackFrame::new_with_all_globals(
            program,
            v_obj(Obj::mk_id(1)),
            v_none(),
            v_none(),
            v_none(),
            v_empty_list(),
            v_empty_str(),
        )
    }

    #[test]
    fn call_frame_presizes_valstack_from_program_depth() {
        let program = compile("1 + 2;", CompileOptions::default()).unwrap();
        let expected = program.main_max_stack();
        let frame = call_frame(program);

        assert!(expected > 0);
        assert!(frame.valstack.capacity() >= expected);
    }

    #[test]
    fn cached_slot_frame_presizes_valstack_from_program_slot() {
        let program = compile("1 + 2;", CompileOptions::default()).unwrap();
        let expected = program.main_max_stack();
        let slot = ProgramSlot {
            program_ptr: &program as *const Program as usize,
            global_width: program.var_names().global_width(),
            main_max_stack: expected,
            main_max_scope_depth: program.main_max_scope_depth(),
        };

        let frame = MooStackFrame::new_with_all_globals_from_slot(
            slot,
            v_obj(Obj::mk_id(1)),
            v_none(),
            v_none(),
            v_none(),
            v_empty_list(),
            v_empty_str(),
        );

        assert!(expected > 0);
        assert!(frame.valstack.capacity() >= expected);
    }

    #[test]
    fn fork_switch_reserves_valstack_for_fork_depth() {
        let program = compile(
            r#"
            fork (0)
                {1, 2, 3, 4};
            endfork
            "#,
            CompileOptions::default(),
        )
        .unwrap();
        let fork_offset = Offset(0);
        let fork_depth = program.fork_vector_max_stack(fork_offset);
        let mut frame = call_frame(program);

        assert!(fork_depth > frame.valstack.capacity());
        frame.switch_to_fork_vector(fork_offset);
        assert!(frame.valstack.capacity() >= fork_depth);
    }

    #[test]
    fn call_frame_presizes_scope_stack_from_program_depth() {
        let program = compile(
            r#"
            if (1)
                while (0)
                    1;
                endwhile
            endif
            "#,
            CompileOptions::default(),
        )
        .unwrap();
        let expected = program.main_max_scope_depth();
        let frame = call_frame(program);

        assert!(expected >= 2);
        assert!(frame.scope_stack.capacity() >= expected);
    }

    #[test]
    fn fork_switch_reserves_scope_stack_for_fork_depth() {
        let program = compile(
            r#"
            fork (0)
                if (1)
                    while (0)
                        1;
                    endwhile
                endif
            endfork
            "#,
            CompileOptions::default(),
        )
        .unwrap();
        let fork_offset = Offset(0);
        let fork_depth = program.fork_vector_max_scope_depth(fork_offset);
        let mut frame = call_frame(program);

        assert!(fork_depth > frame.scope_stack.capacity());
        frame.switch_to_fork_vector(fork_offset);
        assert!(frame.scope_stack.capacity() >= fork_depth);
    }
}
