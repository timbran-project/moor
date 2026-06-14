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

use std::fmt::Write as _;

use moor_common::tasks::Exception;
use moor_compiler::{BUILTINS, Label, Offset, Op, to_literal};
use moor_var::{
    Error, NOTHING, Sequence, Var, v_arc_str, v_bool, v_err, v_int, v_list, v_none, v_obj, v_str,
    v_string,
};

use crate::exec_state::ExecState;
use crate::moo_execute::ExecutionResult;
use crate::{Activation, CatchType, Frame, MooStackFrame, ScopeKind, ScopeType};

#[derive(Clone, Eq, PartialEq, Debug)]
pub enum FinallyReason {
    Fallthrough,
    Raise(Box<Exception>),
    Return(Var),
    Abort,
    Exit { stack: Offset, label: Label },
}

enum ActivationUnwind {
    Handled,
    PopActivation,
}

impl ExecState {
    /// Compose a list of the current stack frames, from the current frame down to the root frame.
    pub fn make_stack_list(activations: &[Activation]) -> Vec<Var> {
        Self::make_stack_list_from(activations, 0)
    }

    /// Compose a list of the current stack frames, from the current frame down to
    /// `start_activation` inclusive.
    pub fn make_stack_list_from(activations: &[Activation], start_activation: usize) -> Vec<Var> {
        let Some(activations) = activations.get(start_activation..) else {
            return Vec::new();
        };

        let mut stack_list = Vec::with_capacity(activations.len());
        for a in activations.iter().rev() {
            let line_no = match a.frame.find_line_no() {
                None => v_none(),
                Some(l) => v_int(l as i64),
            };
            match &a.frame {
                Frame::Moo(_) => stack_list.push(v_list(&[
                    a.this.clone(),
                    v_str(&a.verb_name.as_string()),
                    v_obj(a.permissions()),
                    v_obj(a.verb_definer()),
                    v_obj(a.player),
                    line_no,
                ])),
                Frame::Bf(bf_frame) => {
                    let bf_name = BUILTINS.name_of(bf_frame.bf_id).unwrap();
                    stack_list.push(v_list(&[
                        a.this.clone(),
                        v_arc_str(bf_name.as_arc_str()),
                        v_obj(a.permissions()),
                        v_obj(NOTHING),
                        v_obj(a.player),
                        v_int(0),
                    ]));
                }
            }
        }
        stack_list
    }

    /// Compose a backtrace list of strings for an error, starting from the current stack frame.
    pub fn make_backtrace(activations: &[Activation], error: &Error) -> Vec<Var> {
        let mut backtrace_list = Vec::with_capacity(activations.len() + 1);
        for (i, a) in activations.iter().rev().enumerate() {
            let mut piece = String::new();
            if i != 0 {
                piece.push_str("... called from ");
            }
            match &a.frame {
                Frame::Moo(_) => {
                    let _ = write!(&mut piece, "{}:{}", a.verb_definer(), a.verb_name);
                }
                Frame::Bf(bf_frame) => {
                    let bf_name = BUILTINS.name_of(bf_frame.bf_id).unwrap();
                    let _ = write!(&mut piece, "builtin {bf_name}");
                }
            }
            if v_obj(a.verb_definer()) != a.this {
                let _ = write!(&mut piece, " (this == {})", to_literal(&a.this));
            }
            if let Some(line_num) = a.frame.find_line_no() {
                let _ = write!(&mut piece, " (line {line_num})");
            }
            if i == 0 {
                let _ = write!(&mut piece, ": {} ({})", error.err_type(), error.message());
            }
            backtrace_list.push(v_str(&piece))
        }
        backtrace_list.push(v_str("(End of traceback)"));
        backtrace_list
    }

    /// Compose a formatted backtrace from a structured stack list.
    pub fn make_backtrace_from_stack(stack: &[Var], error: &Error) -> Vec<Var> {
        let mut backtrace_list = Vec::with_capacity(stack.len() + 1);
        for (i, frame) in stack.iter().enumerate() {
            let Some(mut piece) = Self::stack_frame_backtrace_piece(frame) else {
                let mut piece = String::new();
                if i != 0 {
                    piece.push_str("... called from ");
                }
                let _ = write!(&mut piece, "{}", to_literal(frame));
                backtrace_list.push(v_str(&piece));
                continue;
            };
            if i != 0 {
                let mut prefixed = String::with_capacity("... called from ".len() + piece.len());
                prefixed.push_str("... called from ");
                prefixed.push_str(&piece);
                piece = prefixed;
            }
            if i == 0 {
                let _ = write!(&mut piece, ": {} ({})", error.err_type(), error.message());
            }
            backtrace_list.push(v_str(&piece));
        }
        backtrace_list.push(v_str("(End of traceback)"));
        backtrace_list
    }

    pub fn materialize_exception_backtrace(exception: &mut Exception) {
        if !exception.backtrace.is_empty() {
            return;
        }
        exception.backtrace = Self::make_backtrace_from_stack(&exception.stack, &exception.error);
    }

    fn stack_frame_backtrace_piece(frame: &Var) -> Option<String> {
        let frame = frame.as_list()?;
        if frame.len() < 6 {
            return None;
        }

        let this = frame.index(0).ok()?;
        let verb_name = frame.index(1).ok()?;
        let verb_name = verb_name.as_string()?;
        let verb_definer = frame.index(3).ok()?.as_object()?;
        let line_num = frame.index(5).ok()?.as_integer();

        if verb_definer == NOTHING {
            let mut piece = String::new();
            let _ = write!(&mut piece, "builtin {verb_name}");
            return Some(piece);
        }

        let mut piece = String::new();
        let _ = write!(&mut piece, "{verb_definer}:{verb_name}");
        if this.as_object() != Some(verb_definer) {
            let _ = write!(&mut piece, " (this == {})", to_literal(&this));
        }
        if let Some(line_num) = line_num {
            let _ = write!(&mut piece, " (line {line_num})");
        }
        Some(piece)
    }

    /// Explicitly raise an error.
    /// Finds the catch handler for the given error if there is one, and unwinds the stack to it.
    /// If there is no handler, creates an 'Uncaught' reason with backtrace, and unwinds with that.
    pub fn throw_error(&mut self, error: Error) -> ExecutionResult {
        if self.catch_error_in_current_activation(&error) {
            return ExecutionResult::More;
        }

        let stack_start = self.handler_activation_index(&error).unwrap_or(0);
        let stack = Self::make_stack_list_from(&self.stack, stack_start);
        let exception = Box::new(Exception {
            error,
            stack,
            backtrace: Vec::new(),
        });
        self.unwind_stack(FinallyReason::Raise(exception))
    }

    fn catch_matches(catch: &CatchType, error: &Error) -> bool {
        match catch {
            CatchType::Any => true,
            CatchType::Errors(errs) => errs.contains(error),
        }
    }

    fn catch_value(error: &Error, stack: &[Var]) -> Var {
        let value = error.value().cloned().unwrap_or(v_int(0));
        v_list(&[
            v_err(error.err_type()),
            v_string(error.message()),
            value,
            v_list(stack),
        ])
    }

    fn activation_has_catch_for_error(activation: &Activation, error: &Error) -> bool {
        let Frame::Moo(frame) = &activation.frame else {
            return false;
        };

        for scope in frame.scope_stack.iter().rev() {
            if let Some(catches) = frame.try_catches_for_scope(scope)
                && catches
                    .iter()
                    .any(|catch| Self::catch_matches(&catch.0, error))
            {
                return true;
            }
        }

        false
    }

    fn handler_activation_index(&self, error: &Error) -> Option<usize> {
        self.stack
            .iter()
            .enumerate()
            .rev()
            .find_map(|(idx, activation)| {
                Self::activation_has_catch_for_error(activation, error).then_some(idx)
            })
    }

    fn top_moo_activation_catch_label(&self, error: &Error) -> Option<(usize, Label)> {
        let (activation_idx, activation) = self
            .stack
            .iter()
            .enumerate()
            .rev()
            .find(|(_, activation)| matches!(activation.frame, Frame::Moo(_)))?;
        let Frame::Moo(frame) = &activation.frame else {
            return None;
        };

        for scope in frame.scope_stack.iter().rev() {
            match scope.kind {
                ScopeKind::TryFinally => return None,
                ScopeKind::TryCatch => {
                    let catches = frame
                        .try_catches_for_scope(scope)
                        .expect("try/catch scope without payload");
                    for catch in catches {
                        let found = Self::catch_matches(&catch.0, error);
                        if found {
                            return Some((activation_idx, catch.1));
                        }
                    }
                }
                _ => {}
            }
        }
        None
    }

    fn catch_discards_value(&self, activation_idx: usize, catch_label: Label) -> bool {
        let Some(activation) = self.stack.get(activation_idx) else {
            return false;
        };
        let Frame::Moo(frame) = &activation.frame else {
            return false;
        };

        let handler_pc = frame.label_position(catch_label);
        matches!(frame.opcodes().get(handler_pc as usize), Some(Op::Pop))
    }

    fn catch_error_in_current_activation(&mut self, error: &Error) -> bool {
        let Some((activation_idx, catch_label)) = self.top_moo_activation_catch_label(error) else {
            return false;
        };

        let catch_discards_value = self.catch_discards_value(activation_idx, catch_label);
        if !catch_discards_value && activation_idx + 1 != self.stack.len() {
            return false;
        }

        let stack = if catch_discards_value {
            None
        } else {
            let stack_start = activation_idx;
            Some(Self::make_stack_list_from(&self.stack, stack_start))
        };

        self.stack.truncate(activation_idx + 1);
        let Some(activation) = self.stack.last_mut() else {
            return false;
        };
        let Frame::Moo(frame) = &mut activation.frame else {
            return false;
        };

        while let Some(scope) = frame.pop_scope() {
            let ScopeType::TryCatch(catches) = scope else {
                continue;
            };
            for catch in catches {
                let found = Self::catch_matches(&catch.0, error);
                if found && catch.1 == catch_label {
                    frame.jump(&catch_label);
                    if catch_discards_value {
                        frame.pc += 1;
                    } else {
                        let stack = stack.as_ref().expect("catch stack value not built");
                        frame.push(Self::catch_value(error, stack));
                    }
                    return true;
                }
            }
        }

        false
    }

    fn unwind_activation(activation: &mut Activation, why: &FinallyReason) -> ActivationUnwind {
        match &mut activation.frame {
            Frame::Moo(frame) => Self::unwind_moo_frame(frame, why),
            Frame::Bf(_) => ActivationUnwind::PopActivation,
        }
    }

    fn unwind_moo_frame(frame: &mut MooStackFrame, why: &FinallyReason) -> ActivationUnwind {
        if let FinallyReason::Exit { label, .. } = why {
            frame.jump(label);
            return ActivationUnwind::Handled;
        }

        while let Some(scope) = frame.pop_scope() {
            match scope {
                ScopeType::TryFinally(finally_label) => {
                    frame.jump(&finally_label);
                    frame.push_finally_reason(why.clone());
                    return ActivationUnwind::Handled;
                }
                ScopeType::TryCatch(catches) => {
                    if let FinallyReason::Raise(exception) = why
                        && let Some((_, catch_label)) = catches
                            .iter()
                            .find(|(catch, _)| Self::catch_matches(catch, &exception.error))
                    {
                        frame.jump(catch_label);
                        frame.push(Self::catch_value(&exception.error, &exception.stack));
                        return ActivationUnwind::Handled;
                    }
                }
                _ => {}
            }
        }

        ActivationUnwind::PopActivation
    }

    fn finish_unwind(why: FinallyReason) -> ExecutionResult {
        match why {
            FinallyReason::Return(r) => ExecutionResult::Complete(r),
            FinallyReason::Fallthrough => ExecutionResult::Complete(v_bool(false)),
            _ => ExecutionResult::Exception(why),
        }
    }

    /// Unwind the activation stack until a frame handles `why` or the task completes.
    pub fn unwind_stack(&mut self, why: FinallyReason) -> ExecutionResult {
        while let Some(activation) = self.stack.last_mut() {
            if matches!(
                Self::unwind_activation(activation, &why),
                ActivationUnwind::Handled
            ) {
                return ExecutionResult::More;
            }

            self.stack.pop();
            if self.stack.is_empty() {
                break;
            }

            if let FinallyReason::Return(value) = &why {
                self.set_return_value(value.clone());
                return ExecutionResult::More;
            }
        }

        Self::finish_unwind(why)
    }
}
