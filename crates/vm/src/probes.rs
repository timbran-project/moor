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

//! USDT probe points for `tools/mootop`.
//!
//! Each probe tells a tracer what is running on the current thread. With no tracer attached a
//! probe costs one load and one branch, and its arguments are never evaluated.
//!
//! The frame probes take `task, kind, a, b, c, name_ptr, name_len`. `kind` is one of the
//! `FRAME_*` values below:
//!
//! - verb (1): `a` is the definer object, `b` and `c` are the verb UUID's high and low halves
//! - lambda (2): the identity of the verb that defines it; the name is the lambda's
//! - builtin (3): `a` is the builtin ID
//! - eval (4): no identity
//! - native (5): a verb implemented by a native library; identity as for a verb
//! - none (0): the stack is empty
//!
//! `name_ptr` and `name_len` give the name as UTF-8, valid for the duration of the probe. The book
//! page "Watching a Server with mootop" lists every probe; keep it in step with changes here.

use moor_common::tasks::TaskId;
use moor_var::NOTHING;

use crate::{Activation, Frame, PcType};

const FRAME_NONE: u64 = 0;
const FRAME_VERB: u64 = 1;
const FRAME_LAMBDA: u64 = 2;
const FRAME_BUILTIN: u64 = 3;
const FRAME_EVAL: u64 = 4;
const FRAME_NATIVE: u64 = 5;

struct FrameIdentity<'a> {
    kind: u64,
    a: u64,
    b: u64,
    c: u64,
    name: &'a str,
}

impl<'a> FrameIdentity<'a> {
    const NONE: Self = Self {
        kind: FRAME_NONE,
        a: 0,
        b: 0,
        c: 0,
        name: "",
    };

    #[cold]
    fn of(activation: Option<&'a Activation>) -> Self {
        let Some(activation) = activation else {
            return Self::NONE;
        };
        let name = activation.verb_name.as_str();
        let kind = match &activation.frame {
            Frame::Bf(bf) => {
                return Self {
                    kind: FRAME_BUILTIN,
                    a: bf.bf_id.0 as u64,
                    b: 0,
                    c: 0,
                    name,
                };
            }
            Frame::Moo(_) if activation.verbdef.location() == NOTHING => {
                return Self {
                    kind: FRAME_EVAL,
                    name,
                    ..Self::NONE
                };
            }
            Frame::Moo(frame) if matches!(frame.pc_type, PcType::Lambda(_)) => FRAME_LAMBDA,
            Frame::Moo(_) => FRAME_VERB,
            Frame::Native(_) => FRAME_NATIVE,
        };
        let (b, c) = activation.verbdef.uuid().as_u64_pair();
        Self {
            kind,
            a: activation.verbdef.location().as_u64(),
            b,
            c,
            name,
        }
    }
}

// `probe_lazy!` evaluates its arguments in order, and only while a tracer is attached. The first
// argument fills in the identity that the rest read.
macro_rules! frame_probe {
    ($name:ident, $task_id:expr, $activation:expr) => {{
        let f: FrameIdentity;
        probe::probe_lazy!(
            moor,
            $name,
            $task_id,
            {
                f = FrameIdentity::of($activation);
                f.kind
            },
            f.a,
            f.b,
            f.c,
            f.name.as_ptr(),
            f.name.len()
        );
    }};
}

/// `moor:frame_enter`: `activation` was pushed and is now running on this thread.
#[inline(always)]
pub fn probe_frame_enter(task_id: TaskId, activation: &Activation) {
    frame_probe!(frame_enter, task_id, Some(activation));
}

/// `moor:frame_top`: the top of the stack changed without a push (after a pop, or when a task
/// resumes on this thread). `top` is the new top, or `None` if the stack is empty.
#[inline(always)]
pub fn probe_frame_top(task_id: TaskId, top: Option<&Activation>) {
    frame_probe!(frame_top, task_id, top);
}

/// `moor:task_off`: the task stopped running on this thread.
#[inline(always)]
pub fn probe_task_off(task_id: TaskId) {
    probe::probe_lazy!(moor, task_off, task_id);
}
