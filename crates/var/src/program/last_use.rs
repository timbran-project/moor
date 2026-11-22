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

//! Finds the last read of a variable before it is overwritten.
//!
//! `x[i] = v` and `x = {@x, v}` push `x`, build a new value from it, and store that back in `x`.
//! While the variable still holds the old value, the copy on the stack is shared and the edit has
//! to copy the whole collection. Turning that push into one that takes the value out of the
//! variable leaves the stack with the only reference, so the edit happens in place.
//!
//! A push is converted only when the store that follows is certain to run and nothing can look at
//! the variable in between:
//!
//! - every instruction from the push to the store runs in a straight line, and neither reads nor
//!   writes a variable by name;
//! - neither is inside a `try` or a catch expression, where a handler in the same frame could
//!   run after an error and find the variable empty.
//!
//! An error outside those constructs unwinds the frame, so nothing is left to see the variable.
//! A jump that lands between the two is harmless: that path reaches the store without having
//! taken anything.
//!
//! # Storage
//!
//! `PushClear` and `PushClearScope0Local` are execution-only: a stored program never contains
//! them. The encoder writes each as the push it replaced, and this pass runs again whenever a
//! program is decoded. So the pass has to give the same result on a freshly compiled program and
//! on one read back from storage, which holds because it looks only at the instructions and
//! running it twice changes nothing. [`mark_program`] is the single entry point for both.
//!
//! The pass does not change the number or order of instructions, so a program counter saved in a
//! suspended task means the same thing before and after. A task suspended between a `PushClear`
//! and its store has the value on its stack and the variable unset; the store puts it back when
//! the task resumes, on any server version.

use crate::program::{
    names::{GlobalName, Name},
    opcode::Op,
};
use strum::EnumCount;

/// A variable slot: scope depth and offset. Scope ids are not needed, since a conversion never
/// spans the start or end of a scope.
type Slot = (u8, u16);

fn slot(name: &Name) -> Option<Slot> {
    // The frame supplies defaults for unset globals, and the VM reads some of them itself.
    if name.1 == 0 && usize::from(name.0) < GlobalName::COUNT {
        return None;
    }
    Some((name.1, name.0))
}

/// True for instructions that work only on the value stack and fall through to the next one.
fn is_stack_only(op: &Op) -> bool {
    matches!(
        op,
        Op::Add
            | Op::BitAnd
            | Op::BitOr
            | Op::BitXor
            | Op::BitShl
            | Op::BitShr
            | Op::BitLShr
            | Op::BitNot
            | Op::Div
            | Op::Eq
            | Op::Exp
            | Op::Ge
            | Op::Gt
            | Op::Le
            | Op::Lt
            | Op::Mod
            | Op::Mul
            | Op::Ne
            | Op::Not
            | Op::Sub
            | Op::UnaryMinus
            | Op::In
            | Op::Imm(..)
            | Op::ImmBigInt(..)
            | Op::ImmFloat(..)
            | Op::ImmEmptyList
            | Op::ImmInt(..)
            | Op::ImmType(..)
            | Op::ImmNone
            | Op::ImmObjid(..)
            | Op::ImmSymbol(..)
            | Op::ImmErr(..)
            | Op::MakeError(..)
            | Op::MakeSingletonList
            | Op::MakeMap
            | Op::MapInsert
            | Op::MakeFlyweight(..)
            | Op::ListAddTail
            | Op::ListAppend
            | Op::CheckListForSplice
            | Op::Pop
            | Op::Dup
            | Op::Swap
            | Op::PushTemp
            | Op::PutTemp
            | Op::PutTempPop
            | Op::Ref
            | Op::PushRef
            | Op::RangeRef
            | Op::IndexSet
            | Op::IndexSetAt(..)
            | Op::RangeSet
            | Op::RangeSetAt(..)
            | Op::Length(..)
            | Op::GetProp
            | Op::PushGetProp
            | Op::PutProp
            | Op::CallVerb
            | Op::FuncCall { .. }
            | Op::CallLambda
            | Op::Pass
    )
}

/// For each instruction, whether a handler in this vector is active while it runs.
/// Returns `None` if the handler instructions do not nest as expected.
fn guarded(ops: &[Op]) -> Option<Vec<bool>> {
    let mut depth = 0usize;
    let mut guarded = Vec::with_capacity(ops.len());
    for op in ops {
        match op {
            Op::EndCatch(..) | Op::EndExcept(..) | Op::EndFinally => {
                depth = depth.checked_sub(1)?;
                guarded.push(true);
            }
            Op::TryCatch { .. } | Op::TryExcept { .. } | Op::TryFinally { .. } => {
                depth += 1;
                guarded.push(true);
            }
            _ => guarded.push(depth > 0),
        }
    }
    (depth == 0).then_some(guarded)
}

/// Apply [`mark_last_uses`] to every instruction vector of a program. Called when a program is
/// compiled and when it is decoded from storage.
pub fn mark_program(main_vector: &mut [Op], fork_vectors: &mut [(usize, Vec<Op>)]) {
    mark_last_uses(main_vector);
    for (_, fork_vector) in fork_vectors {
        mark_last_uses(fork_vector);
    }
}

/// Rewrite the last push of a variable before it is overwritten into a push that takes the value.
/// Running this on a vector that was already rewritten changes nothing.
pub fn mark_last_uses(ops: &mut [Op]) {
    let Some(guarded) = guarded(ops) else {
        return;
    };

    // Slots whose next access, reading forwards, is a store.
    let mut overwritten: Vec<Slot> = Vec::new();
    for i in (0..ops.len()).rev() {
        let op = &mut ops[i];
        let (read, taken) = match op {
            Op::Put(name) | Op::PutPop(name) => {
                if let Some(slot) = slot(name)
                    && !overwritten.contains(&slot)
                {
                    overwritten.push(slot);
                }
                continue;
            }
            Op::PutScope0Local(offset) | Op::PutPopScope0Local(offset) => {
                if !overwritten.contains(&(0, *offset)) {
                    overwritten.push((0, *offset));
                }
                continue;
            }
            Op::Push(name) => (slot(name), Op::PushClear(*name)),
            Op::PushScope0Local(offset) => (Some((0, *offset)), Op::PushClearScope0Local(*offset)),
            Op::PushClear(name) => (slot(name), Op::PushClear(*name)),
            Op::PushClearScope0Local(offset) => {
                (Some((0, *offset)), Op::PushClearScope0Local(*offset))
            }
            op if is_stack_only(op) => continue,
            _ => {
                overwritten.clear();
                continue;
            }
        };
        let Some(read) = read else {
            continue;
        };
        if let Some(found) = overwritten.iter().position(|slot| *slot == read) {
            overwritten.swap_remove(found);
            if !guarded[i] {
                *op = taken;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::program::labels::{Label, Offset};

    const X: Name = Name(20, 0, 0);
    const Y: Name = Name(21, 0, 0);

    fn marked(mut ops: Vec<Op>) -> Vec<Op> {
        mark_last_uses(&mut ops);
        let mut again = ops.clone();
        mark_last_uses(&mut again);
        assert_eq!(again, ops, "a second pass must change nothing");
        ops
    }

    #[test]
    fn the_last_push_before_a_store_takes_the_value() {
        // x = {@x, length(x)}
        let ops = marked(vec![
            Op::Push(X),
            Op::CheckListForSplice,
            Op::Push(X),
            Op::Length(Offset(0)),
            Op::ListAddTail,
            Op::PutPop(X),
        ]);
        assert_eq!(ops[0], Op::Push(X));
        assert_eq!(ops[2], Op::PushClear(X));
    }

    #[test]
    fn scope_zero_locals_are_converted() {
        let ops = marked(vec![
            Op::PushScope0Local(20),
            Op::ImmInt(1),
            Op::ImmInt(2),
            Op::Dup,
            Op::IndexSetAt(Offset(1)),
            Op::Swap,
            Op::PutPopScope0Local(20),
            Op::Pop,
        ]);
        assert_eq!(ops[0], Op::PushClearScope0Local(20));
    }

    #[test]
    fn a_push_with_no_store_after_it_is_left_alone() {
        let ops = marked(vec![Op::Push(X), Op::PutPop(Y), Op::Push(X), Op::Pop]);
        assert_eq!(ops[0], Op::Push(X));
        assert_eq!(ops[2], Op::Push(X));
    }

    #[test]
    fn an_instruction_that_names_a_variable_blocks_it() {
        let ops = marked(vec![Op::Push(X), Op::Capture(X), Op::PutPop(X)]);
        assert_eq!(ops[0], Op::Push(X));
    }

    #[test]
    fn a_branch_between_push_and_store_blocks_it() {
        let ops = marked(vec![
            Op::Push(X),
            Op::Jump { label: Label(0) },
            Op::PutPop(X),
        ]);
        assert_eq!(ops[0], Op::Push(X));
    }

    #[test]
    fn nothing_is_taken_while_a_handler_is_active() {
        let ops = marked(vec![
            Op::TryFinally {
                end_label: Label(0),
                environment_width: 0,
            },
            Op::Push(X),
            Op::ImmInt(1),
            Op::ListAddTail,
            Op::PutPop(X),
            Op::EndFinally,
            Op::Push(X),
            Op::ImmInt(1),
            Op::ListAddTail,
            Op::PutPop(X),
        ]);
        assert_eq!(ops[1], Op::Push(X));
        assert_eq!(ops[6], Op::PushClear(X));
    }

    #[test]
    fn globals_are_never_taken() {
        let player = Name(GlobalName::player as u16, 0, 0);
        let ops = marked(vec![Op::Push(player), Op::PutPop(player)]);
        assert_eq!(ops[0], Op::Push(player));
    }
}
