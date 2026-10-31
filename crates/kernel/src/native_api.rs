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

//! The functions the daemon gives native verb libraries, `moor_api` in `moor_native.h`.
//!
//! A `moor_value` holds an integer, float, boolean or object itself, and anything else by a
//! `moor_ref`: a pointer to a `Var` the daemon keeps. Refs made during a call live in its
//! [`NativeCallContext`] and are freed when the step ends; retained refs are boxes the library
//! frees with `release`. Every function here is called across the C boundary, so none may panic.

use moor_common::{
    builtins::BUILTINS,
    model::{
        DispatchFlagsSource, ObjFlag, TaskPermissions, ValSet, VerbDispatch, VerbLookup,
        WorldStateError,
    },
    util::BitEnum,
};
use moor_compiler::{BuiltinId, to_literal};
use moor_native_verb::ffi::{
    MOOR_CONFLICT, MOOR_ERROR, MOOR_NATIVE_ABI, MOOR_OK, MOOR_TYPE_BOOL, MOOR_TYPE_FLOAT,
    MOOR_TYPE_INT, MOOR_TYPE_NONE, MOOR_TYPE_OBJ, moor_api, moor_call, moor_obj, moor_ref,
    moor_status, moor_value, moor_value_as,
};
use moor_var::{
    Associative, E_ARGS, E_INVARG, E_RANGE, E_TYPE, Error, ErrorCode, List, Obj, Symbol, Var,
    VarType, Variant, v_binary, v_bool, v_empty_map, v_error, v_float, v_flyweight, v_int,
    v_list_iter, v_obj, v_str, v_sym,
};
use std::ffi::c_char;

use crate::task_context::{
    has_active_task, with_current_transaction, with_current_transaction_mut,
};

/// How a step ended, when it ended normally.
pub(crate) enum Outcome {
    Return(Var),
    CallVerb {
        target: Var,
        verb: Symbol,
        args: List,
        step: u32,
        state: Option<Var>,
    },
    CallBuiltin {
        builtin: BuiltinId,
        args: List,
        step: u32,
        state: Option<Var>,
    },
}

/// How many refs each block of a call's arena holds.
const REF_BLOCK: usize = 64;

/// The refs made during a step. Each block is allocated at full capacity and never grows, so a
/// ref's address stays put as more are made, and a step that makes many refs allocates once per
/// block rather than once per ref.
#[derive(Default)]
struct Refs {
    blocks: Vec<Vec<Var>>,
}

impl Refs {
    fn push(&mut self, value: Var) -> *mut moor_ref {
        if self
            .blocks
            .last()
            .is_none_or(|block| block.len() == REF_BLOCK)
        {
            self.blocks.push(Vec::with_capacity(REF_BLOCK));
        }
        let block = self.blocks.last_mut().expect("a block was just added");
        block.push(value);
        block.last_mut().expect("a value was just added") as *mut Var as *mut moor_ref
    }
}

/// One step of a native verb: what it was called with, the refs it holds, and how it ended.
pub(crate) struct NativeCallContext {
    refs: Refs,
    this: Var,
    player: Obj,
    caller: Var,
    verb: Symbol,
    args: List,
    permissions: TaskPermissions,
    step: u32,
    state: Option<Var>,
    result: Option<Var>,
    pub(crate) pending_error: Option<Error>,
    pub(crate) conflict: bool,
    pub(crate) outcome: Option<Outcome>,
    /// World and call requests made, charged to the task as ticks.
    pub(crate) requests: usize,
}

impl NativeCallContext {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        this: Var,
        player: Obj,
        caller: Var,
        verb: Symbol,
        args: List,
        permissions: TaskPermissions,
        step: u32,
        state: Option<Var>,
        result: Option<Var>,
    ) -> Self {
        Self {
            refs: Refs::default(),
            this,
            player,
            caller,
            verb,
            args,
            permissions,
            step,
            state,
            result,
            pending_error: None,
            conflict: false,
            outcome: None,
            requests: 0,
        }
    }

    pub(crate) fn as_call(&mut self) -> *mut moor_call {
        self as *mut Self as *mut moor_call
    }

    fn reference(&mut self, value: Var) -> *mut moor_ref {
        self.refs.push(value)
    }

    /// A value in its C form: a scalar held directly, anything else by a new ref.
    fn value(&mut self, value: &Var) -> moor_value {
        let (type_, as_) = match value.variant() {
            Variant::Int(i) => (MOOR_TYPE_INT, moor_value_as { i }),
            Variant::Float(f) => (MOOR_TYPE_FLOAT, moor_value_as { f }),
            Variant::Bool(b) => (MOOR_TYPE_BOOL, moor_value_as { b }),
            Variant::Obj(o) => (MOOR_TYPE_OBJ, moor_value_as { o: o.as_u64() }),
            _ => (
                value.type_code() as i32,
                moor_value_as {
                    ref_: self.reference(value.clone()),
                },
            ),
        };
        moor_value { type_, as_ }
    }

    fn optional_value(&mut self, value: Option<&Var>) -> moor_value {
        value.map_or(moor_value::NONE, |v| self.value(v))
    }

    fn fail(&mut self, error: Error) -> moor_status {
        self.pending_error = Some(error);
        MOOR_ERROR
    }

    fn world_failure(&mut self, error: WorldStateError) -> moor_status {
        match error {
            WorldStateError::RollbackRetry => {
                self.conflict = true;
                MOOR_CONFLICT
            }
            other => self.fail(other.to_error()),
        }
    }

    /// Write a value made here, or fail with why it could not be made.
    fn finish(&mut self, made: Result<Var, Error>, out: *mut moor_value) -> moor_status {
        match made {
            Ok(made) => {
                let made = self.value(&made);
                unsafe { write(out, made) };
                MOOR_OK
            }
            Err(e) => self.fail(e),
        }
    }
}

/// The context of a call. A null or foreign pointer is the library's bug, as in any C API.
unsafe fn context<'a>(call: *mut moor_call) -> &'a mut NativeCallContext {
    // SAFETY: the daemon passes only pointers to live contexts; see `NativeCallContext::as_call`.
    unsafe { &mut *(call as *mut NativeCallContext) }
}

unsafe fn referenced<'a>(r: *mut moor_ref) -> Option<&'a Var> {
    if r.is_null() {
        None
    } else {
        // SAFETY: refs are pointers to values the daemon keeps alive.
        Some(unsafe { &*(r as *const Var) })
    }
}

/// The value a ref holds, or E_INVARG for a null ref.
unsafe fn deref<'a>(r: *mut moor_ref) -> Result<&'a Var, Error> {
    unsafe { referenced(r) }.ok_or_else(|| E_INVARG.msg("A native verb passed a null ref"))
}

/// A value from its C form, or none for MOOR_TYPE_NONE.
unsafe fn from_value(value: &moor_value) -> Result<Option<Var>, Error> {
    // SAFETY: the member read is the one `type_` names.
    unsafe {
        Ok(Some(match value.type_ {
            MOOR_TYPE_NONE => return Ok(None),
            MOOR_TYPE_INT => v_int(value.as_.i),
            MOOR_TYPE_FLOAT => v_float(value.as_.f),
            MOOR_TYPE_BOOL => v_bool(value.as_.b),
            MOOR_TYPE_OBJ => v_obj(object(value.as_.o)?),
            declared => {
                let held = deref(value.as_.ref_)?;
                if held.type_code() as i32 != declared {
                    return Err(E_INVARG
                        .msg("A native verb passed a value whose type is not what it holds"));
                }
                held.clone()
            }
        }))
    }
}

/// A value that must be present.
unsafe fn required(value: &moor_value) -> Result<Var, Error> {
    unsafe { from_value(value) }?.ok_or_else(|| E_INVARG.msg("A native verb passed no value"))
}

unsafe fn text<'a>(ptr: *const c_char, len: usize) -> Option<&'a str> {
    if len == 0 {
        return Some("");
    }
    if ptr.is_null() {
        return None;
    }
    // SAFETY: the library passes `len` readable bytes.
    std::str::from_utf8(unsafe { std::slice::from_raw_parts(ptr.cast::<u8>(), len) }).ok()
}

unsafe fn write<T>(out: *mut T, value: T) {
    if !out.is_null() {
        // SAFETY: the library passes a writable pointer, or null to ignore the result.
        unsafe { out.write(value) };
    }
}

fn type_error(what: &str, found: &Var) -> Error {
    E_TYPE.with_msg(|| format!("Expected {what}, got {}", found.type_code().to_literal()))
}

/// A name given as a symbol or a string.
fn name_of(name: &Var) -> Result<Symbol, Error> {
    match name.variant() {
        Variant::Sym(s) => Ok(s),
        Variant::Str(s) => Ok(Symbol::mk(s.as_str())),
        _ => Err(type_error("a symbol or string", name)),
    }
}

fn object(obj: moor_obj) -> Result<Obj, Error> {
    Obj::try_read(obj).map_err(|_| E_INVARG.msg("Not an object reference"))
}

fn error_code(code: &str) -> ErrorCode {
    ErrorCode::parse_str(code).unwrap_or_else(|| ErrorCode::ErrCustom(Symbol::mk(code)))
}

fn make_error(code: &str, message: Option<&str>, value: Option<Var>) -> Error {
    let message = message.filter(|m| !m.is_empty()).map(str::to_string);
    Error::new(error_code(code), message, value)
}

fn objects(set: impl IntoIterator<Item = Obj>) -> Var {
    v_list_iter(set.into_iter().map(v_obj))
}

/// Run `f` on a call, failing it with whatever error `f` gives.
fn attempt(
    call: *mut moor_call,
    f: impl FnOnce(&mut NativeCallContext) -> Result<(), Error>,
) -> moor_status {
    let call = unsafe { context(call) };
    match f(call) {
        Ok(()) => MOOR_OK,
        Err(e) => call.fail(e),
    }
}

/// Make a value from what a ref holds and write it, as `attempt` does.
fn make(
    call: *mut moor_call,
    out: *mut moor_value,
    f: impl FnOnce(&mut NativeCallContext) -> Result<Var, Error>,
) -> moor_status {
    let call = unsafe { context(call) };
    let made = f(call);
    call.finish(made, out)
}

// --- The call ---

unsafe extern "C" fn this_value(call: *mut moor_call) -> moor_value {
    let call = unsafe { context(call) };
    let this = call.this.clone();
    call.value(&this)
}

unsafe extern "C" fn player(call: *mut moor_call) -> moor_obj {
    unsafe { context(call) }.player.as_u64()
}

unsafe extern "C" fn caller(call: *mut moor_call) -> moor_value {
    let call = unsafe { context(call) };
    let caller = call.caller.clone();
    call.value(&caller)
}

unsafe extern "C" fn verb(call: *mut moor_call) -> *mut moor_ref {
    let call = unsafe { context(call) };
    let verb = Var::mk_symbol(call.verb);
    call.reference(verb)
}

unsafe extern "C" fn args(call: *mut moor_call) -> *mut moor_ref {
    let call = unsafe { context(call) };
    let args = Var::from(call.args.clone());
    call.reference(args)
}

unsafe extern "C" fn arg_count(call: *mut moor_call) -> usize {
    unsafe { context(call) }.args.len()
}

unsafe extern "C" fn arg(call: *mut moor_call, index: usize, out: *mut moor_value) -> moor_status {
    let call = unsafe { context(call) };
    let count = call.args.len();
    if index >= count {
        return call.fail(
            E_ARGS.with_msg(|| format!("Native verb wants argument {index}, but has {count}")),
        );
    }
    let found = call.args[index].clone();
    let found = call.value(&found);
    unsafe { write(out, found) };
    MOOR_OK
}

/// Where `count` values from `start` go, or why they cannot: `short` when the source has fewer.
unsafe fn span<'a, T>(
    out: *mut T,
    start: usize,
    count: usize,
    len: usize,
    short: ErrorCode,
) -> Result<&'a mut [T], Error> {
    if start.checked_add(count).is_none_or(|end| end > len) {
        return Err(
            short.with_msg(|| format!("Wanted {count} items from {start}, but there are {len}"))
        );
    }
    if count == 0 || out.is_null() {
        return Ok(&mut []);
    }
    // SAFETY: the library passes room for `count` values.
    Ok(unsafe { std::slice::from_raw_parts_mut(out, count) })
}

unsafe extern "C" fn args_read(
    call: *mut moor_call,
    start: usize,
    out: *mut moor_value,
    count: usize,
) -> moor_status {
    attempt(call, |call| {
        let args = call.args.clone();
        let out = unsafe { span(out, start, count, args.len(), E_ARGS) }?;
        for (slot, index) in out.iter_mut().zip(start..) {
            *slot = call.value(&args[index]);
        }
        Ok(())
    })
}

unsafe extern "C" fn programmer(call: *mut moor_call) -> moor_obj {
    unsafe { context(call) }.permissions.principal().as_u64()
}

unsafe extern "C" fn step(call: *mut moor_call) -> u32 {
    unsafe { context(call) }.step
}

unsafe extern "C" fn state(call: *mut moor_call) -> moor_value {
    let call = unsafe { context(call) };
    let state = call.state.clone();
    call.optional_value(state.as_ref())
}

unsafe extern "C" fn result(call: *mut moor_call) -> moor_value {
    let call = unsafe { context(call) };
    let result = call.result.clone();
    call.optional_value(result.as_ref())
}

// --- Ending a step ---

unsafe extern "C" fn ret(call: *mut moor_call, value: moor_value) -> moor_status {
    attempt(call, |call| {
        call.outcome = Some(Outcome::Return(unsafe { required(&value) }?));
        Ok(())
    })
}

/// The arguments and resumption of a call out, checked.
fn call_out(
    call: &mut NativeCallContext,
    args: &moor_value,
    step: u32,
    state: &moor_value,
) -> Result<(List, Option<Var>), Error> {
    let args = unsafe { required(args) }?;
    let Some(list) = args.as_list() else {
        return Err(type_error("a list of arguments", &args));
    };
    if step == 0 {
        return Err(E_INVARG.msg("A native verb cannot resume at step 0"));
    }
    call.requests += 1;
    Ok((list.clone(), unsafe { from_value(state) }?))
}

unsafe extern "C" fn call_verb(
    call: *mut moor_call,
    target: moor_value,
    verb: moor_value,
    args: moor_value,
    step: u32,
    state: moor_value,
) -> moor_status {
    attempt(call, |call| {
        let target = unsafe { required(&target) }?;
        let verb = name_of(&unsafe { required(&verb) }?)?;
        let (args, state) = call_out(call, &args, step, &state)?;
        call.outcome = Some(Outcome::CallVerb {
            target,
            verb,
            args,
            step,
            state,
        });
        Ok(())
    })
}

unsafe extern "C" fn call_builtin(
    call: *mut moor_call,
    name: moor_value,
    args: moor_value,
    step: u32,
    state: moor_value,
) -> moor_status {
    attempt(call, |call| {
        let name = name_of(&unsafe { required(&name) }?)?;
        let builtin = BUILTINS
            .find_builtin(name)
            .ok_or_else(|| E_INVARG.with_msg(|| format!("No builtin named {name}")))?;
        let (args, state) = call_out(call, &args, step, &state)?;
        call.outcome = Some(Outcome::CallBuiltin {
            builtin,
            args,
            step,
            state,
        });
        Ok(())
    })
}

// --- Errors ---

unsafe extern "C" fn raise(
    call: *mut moor_call,
    code: *const c_char,
    code_len: usize,
    message: *const c_char,
    message_len: usize,
) -> moor_status {
    let call = unsafe { context(call) };
    let Some(code) = (unsafe { text(code, code_len) }).filter(|c| !c.is_empty()) else {
        return call.fail(E_INVARG.msg("A native verb raised an error without a valid code"));
    };
    let message = unsafe { text(message, message_len) };
    let error = make_error(code, message, None);
    call.fail(error)
}

unsafe extern "C" fn raise_value(call: *mut moor_call, error: moor_value) -> moor_status {
    let call = unsafe { context(call) };
    let error = match unsafe { required(&error) } {
        Ok(error) => error,
        Err(e) => return call.fail(e),
    };
    match error.as_error() {
        Some(raised) => {
            let raised = raised.clone();
            call.fail(raised)
        }
        None => call.fail(type_error("an error", &error)),
    }
}

unsafe extern "C" fn pending_error(call: *mut moor_call) -> moor_value {
    let call = unsafe { context(call) };
    match call.pending_error.clone() {
        Some(error) => call.value(&v_error(error)),
        None => moor_value::NONE,
    }
}

unsafe extern "C" fn clear_error(call: *mut moor_call) {
    unsafe { context(call) }.pending_error = None;
}

// --- Refs ---

unsafe extern "C" fn retain(_call: *mut moor_call, r: *mut moor_ref) -> *mut moor_ref {
    match unsafe { referenced(r) } {
        Some(held) => Box::into_raw(Box::new(held.clone())) as *mut moor_ref,
        None => std::ptr::null_mut(),
    }
}

unsafe extern "C" fn release(r: *mut moor_ref) {
    if !r.is_null() {
        // SAFETY: a retained ref is a box from `retain`, released once.
        drop(unsafe { Box::from_raw(r as *mut Var) });
    }
}

unsafe extern "C" fn local(call: *mut moor_call, r: *mut moor_ref) -> *mut moor_ref {
    let call = unsafe { context(call) };
    match unsafe { referenced(r) } {
        Some(held) => {
            let held = held.clone();
            call.reference(held)
        }
        None => std::ptr::null_mut(),
    }
}

unsafe extern "C" fn ref_type(r: *mut moor_ref) -> i32 {
    unsafe { referenced(r) }.map_or(MOOR_TYPE_NONE, |held| held.type_code() as i32)
}

// --- Reading values ---

unsafe extern "C" fn get_str(
    call: *mut moor_call,
    r: *mut moor_ref,
    ptr: *mut *const c_char,
    len: *mut usize,
) -> moor_status {
    attempt(call, |_| {
        let held = unsafe { deref(r) }?;
        // A string's bytes live as long as the value, and a symbol's as long as the process: the
        // interner keeps every symbol.
        let (start, count) = match held.variant() {
            Variant::Str(s) => (s.as_str().as_ptr(), s.as_str().len()),
            Variant::Sym(s) => (s.as_str().as_ptr(), s.as_str().len()),
            _ => return Err(type_error("a string or symbol", held)),
        };
        unsafe {
            write(ptr, start.cast::<c_char>());
            write(len, count);
        }
        Ok(())
    })
}

unsafe extern "C" fn get_binary(
    call: *mut moor_call,
    r: *mut moor_ref,
    ptr: *mut *const u8,
    len: *mut usize,
) -> moor_status {
    attempt(call, |_| {
        let held = unsafe { deref(r) }?;
        let Variant::Binary(b) = held.variant() else {
            return Err(type_error("a binary", held));
        };
        let bytes = b.as_bytes();
        unsafe {
            write(ptr, bytes.as_ptr());
            write(len, bytes.len());
        }
        Ok(())
    })
}

unsafe extern "C" fn length(
    call: *mut moor_call,
    r: *mut moor_ref,
    out: *mut usize,
) -> moor_status {
    attempt(call, |_| {
        let held = unsafe { deref(r) }?;
        let len = match held.variant() {
            Variant::Flyweight(f) => f.contents().len(),
            Variant::Binary(b) => b.len(),
            _ => held.len()?,
        };
        unsafe { write(out, len) };
        Ok(())
    })
}

/// The list a ref holds.
unsafe fn list_of<'a>(r: *mut moor_ref) -> Result<&'a List, Error> {
    let held = unsafe { deref(r) }?;
    held.as_list().ok_or_else(|| type_error("a list", held))
}

unsafe fn map_of<'a>(r: *mut moor_ref) -> Result<&'a moor_var::Map, Error> {
    let held = unsafe { deref(r) }?;
    held.as_map().ok_or_else(|| type_error("a map", held))
}

unsafe extern "C" fn list_get(
    call: *mut moor_call,
    list: *mut moor_ref,
    index: usize,
    out: *mut moor_value,
) -> moor_status {
    attempt(call, |call| {
        let list = unsafe { list_of(list) }?;
        if index >= list.len() {
            let len = list.len();
            return Err(E_RANGE.with_msg(|| format!("Index {index} beyond a list of {len}")));
        }
        let found = call.value(&list[index]);
        unsafe { write(out, found) };
        Ok(())
    })
}

unsafe extern "C" fn list_read(
    call: *mut moor_call,
    list: *mut moor_ref,
    start: usize,
    out: *mut moor_value,
    count: usize,
) -> moor_status {
    attempt(call, |call| {
        let list = unsafe { list_of(list) }?;
        let out = unsafe { span(out, start, count, list.len(), E_RANGE) }?;
        for (slot, index) in out.iter_mut().zip(start..) {
            *slot = call.value(&list[index]);
        }
        Ok(())
    })
}

/// Read `count` items from `start` of a list into `out`, each converted by `read`.
fn list_scalars<T>(
    call: *mut moor_call,
    list: *mut moor_ref,
    start: usize,
    out: *mut T,
    count: usize,
    what: &str,
    read: impl Fn(&Var) -> Option<T>,
) -> moor_status {
    attempt(call, |_| {
        let list = unsafe { list_of(list) }?;
        let out = unsafe { span(out, start, count, list.len(), E_RANGE) }?;
        for (slot, index) in out.iter_mut().zip(start..) {
            let item = &list[index];
            *slot = read(item).ok_or_else(|| {
                E_TYPE.with_msg(|| {
                    format!(
                        "Expected {what} at {index}, got {}",
                        item.type_code().to_literal()
                    )
                })
            })?;
        }
        Ok(())
    })
}

unsafe extern "C" fn list_ints(
    call: *mut moor_call,
    list: *mut moor_ref,
    start: usize,
    out: *mut i64,
    count: usize,
) -> moor_status {
    list_scalars(call, list, start, out, count, "an integer", Var::as_integer)
}

unsafe extern "C" fn list_floats(
    call: *mut moor_call,
    list: *mut moor_ref,
    start: usize,
    out: *mut f64,
    count: usize,
) -> moor_status {
    list_scalars(call, list, start, out, count, "a number", |v| {
        v.as_float().or_else(|| v.as_integer().map(|i| i as f64))
    })
}

unsafe extern "C" fn map_get(
    call: *mut moor_call,
    map: *mut moor_ref,
    key: moor_value,
    out: *mut moor_value,
) -> moor_status {
    attempt(call, |call| {
        let map = unsafe { map_of(map) }?;
        let key = unsafe { required(&key) }?;
        let found = map.get(&key).ok();
        let found = call.optional_value(found.as_ref());
        unsafe { write(out, found) };
        Ok(())
    })
}

unsafe extern "C" fn map_entry(
    call: *mut moor_call,
    map: *mut moor_ref,
    index: usize,
    key: *mut moor_value,
    value: *mut moor_value,
) -> moor_status {
    attempt(call, |call| {
        let (k, v) = unsafe { map_of(map) }?.index(index)?;
        let (k, v) = (call.value(&k), call.value(&v));
        unsafe {
            write(key, k);
            write(value, v);
        }
        Ok(())
    })
}

unsafe extern "C" fn map_read(
    call: *mut moor_call,
    map: *mut moor_ref,
    start: usize,
    keys: *mut moor_value,
    values: *mut moor_value,
    count: usize,
) -> moor_status {
    attempt(call, |call| {
        let map = unsafe { map_of(map) }?;
        let keys = unsafe { span(keys, start, count, map.len(), E_RANGE) }?;
        let values = unsafe { span(values, start, count, map.len(), E_RANGE) }?;
        for ((key, value), (k, v)) in keys
            .iter_mut()
            .zip(values.iter_mut())
            .zip(map.iter().skip(start))
        {
            *key = call.value(&k);
            *value = call.value(&v);
        }
        Ok(())
    })
}

unsafe extern "C" fn error_parts(
    call: *mut moor_call,
    error: *mut moor_ref,
    code: *mut moor_value,
    message: *mut moor_value,
    value: *mut moor_value,
) -> moor_status {
    attempt(call, |call| {
        let held = unsafe { deref(error) }?;
        let error = held
            .as_error()
            .ok_or_else(|| type_error("an error", held))?;
        let name = call.value(&Var::mk_symbol(error.name()));
        let text = call.value(&v_str(&error.message()));
        let attached = call.optional_value(error.value());
        unsafe {
            write(code, name);
            write(message, text);
            write(value, attached);
        }
        Ok(())
    })
}

unsafe extern "C" fn flyweight_parts(
    call: *mut moor_call,
    flyweight: *mut moor_ref,
    delegate: *mut moor_obj,
    slots: *mut moor_value,
    contents: *mut moor_value,
) -> moor_status {
    attempt(call, |call| {
        let held = unsafe { deref(flyweight) }?;
        let Variant::Flyweight(f) = held.variant() else {
            return Err(type_error("a flyweight", held));
        };
        let mut map = v_empty_map();
        for (name, slot) in f.slots_storage() {
            if let Some(m) = map.as_map() {
                map = m.set(&Var::mk_symbol(*name), slot)?;
            }
        }
        let owner = f.delegate().as_u64();
        let (map, items) = (
            call.value(&map),
            call.value(&Var::from(f.contents().clone())),
        );
        unsafe {
            write(delegate, owner);
            write(slots, map);
            write(contents, items);
        }
        Ok(())
    })
}

unsafe extern "C" fn same(a: moor_value, b: moor_value) -> bool {
    match unsafe { (from_value(&a), from_value(&b)) } {
        (Ok(Some(a)), Ok(Some(b))) => a.is_identical(&b),
        _ => false,
    }
}

unsafe extern "C" fn equal(a: moor_value, b: moor_value) -> bool {
    match unsafe { (from_value(&a), from_value(&b)) } {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

unsafe extern "C" fn compare(
    call: *mut moor_call,
    a: moor_value,
    b: moor_value,
    out: *mut i32,
) -> moor_status {
    attempt(call, |_| {
        let (a, b) = unsafe { (required(&a)?, required(&b)?) };
        let ordering = a.compare(&b)?;
        unsafe { write(out, ordering as i32) };
        Ok(())
    })
}

unsafe extern "C" fn literal(call: *mut moor_call, value: moor_value) -> moor_value {
    let call = unsafe { context(call) };
    match unsafe { from_value(&value) } {
        Ok(Some(value)) => call.value(&v_str(&to_literal(&value))),
        _ => moor_value::NONE,
    }
}

// --- Making values ---

unsafe extern "C" fn new_str(
    call: *mut moor_call,
    ptr: *const c_char,
    len: usize,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        unsafe { text(ptr, len) }
            .map(v_str)
            .ok_or_else(|| E_INVARG.msg("A native verb made a string that is not UTF-8"))
    })
}

unsafe extern "C" fn new_sym(
    call: *mut moor_call,
    ptr: *const c_char,
    len: usize,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        unsafe { text(ptr, len) }
            .map(v_sym)
            .ok_or_else(|| E_INVARG.msg("A native verb made a symbol that is not UTF-8"))
    })
}

unsafe fn slice<'a, T>(items: *const T, count: usize) -> &'a [T] {
    if count == 0 || items.is_null() {
        &[]
    } else {
        // SAFETY: the library passes `count` items.
        unsafe { std::slice::from_raw_parts(items, count) }
    }
}

unsafe extern "C" fn new_binary(call: *mut moor_call, ptr: *const u8, len: usize) -> moor_value {
    let bytes = unsafe { slice(ptr, len) }.to_vec();
    unsafe { context(call) }.value(&v_binary(bytes))
}

unsafe extern "C" fn new_list(
    call: *mut moor_call,
    items: *const moor_value,
    count: usize,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let items: Vec<Var> = unsafe { slice(items, count) }
            .iter()
            .map(|item| unsafe { required(item) })
            .collect::<Result<_, _>>()?;
        Ok(v_list_iter(items))
    })
}

unsafe extern "C" fn new_list_ints(
    call: *mut moor_call,
    items: *const i64,
    count: usize,
) -> moor_value {
    let list = v_list_iter(unsafe { slice(items, count) }.iter().map(|i| v_int(*i)));
    unsafe { context(call) }.value(&list)
}

unsafe extern "C" fn new_list_floats(
    call: *mut moor_call,
    items: *const f64,
    count: usize,
) -> moor_value {
    let list = v_list_iter(unsafe { slice(items, count) }.iter().map(|f| v_float(*f)));
    unsafe { context(call) }.value(&list)
}

unsafe extern "C" fn new_map(
    call: *mut moor_call,
    keys: *const moor_value,
    values: *const moor_value,
    count: usize,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let mut map = v_empty_map();
        for (key, value) in unsafe { slice(keys, count) }
            .iter()
            .zip(unsafe { slice(values, count) })
        {
            let (key, value) = unsafe { (required(key)?, required(value)?) };
            if let Some(m) = map.as_map() {
                map = m.set(&key, &value)?;
            }
        }
        Ok(map)
    })
}

unsafe extern "C" fn new_error(
    call: *mut moor_call,
    code: *const c_char,
    code_len: usize,
    message: *const c_char,
    message_len: usize,
    value: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let code = unsafe { text(code, code_len) }
            .filter(|c| !c.is_empty())
            .ok_or_else(|| E_INVARG.msg("A native verb made an error without a valid code"))?;
        let message = unsafe { text(message, message_len) };
        let attached = unsafe { from_value(&value) }?;
        Ok(v_error(make_error(code, message, attached)))
    })
}

unsafe extern "C" fn new_flyweight(
    call: *mut moor_call,
    delegate: moor_obj,
    slots: moor_value,
    contents: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let delegate = object(delegate)?;
        let mut named = Vec::new();
        if let Some(slots) = unsafe { from_value(&slots) }? {
            let map = slots
                .as_map()
                .ok_or_else(|| type_error("a map of slots", &slots))?;
            for (name, slot) in map.iter() {
                named.push((name_of(&name)?, slot));
            }
        }
        let items = match unsafe { from_value(&contents) }? {
            Some(contents) => contents
                .as_list()
                .cloned()
                .ok_or_else(|| type_error("a list of contents", &contents))?,
            None => List::mk_list(&[]),
        };
        Ok(v_flyweight(delegate, &named, items))
    })
}

unsafe extern "C" fn list_append(
    call: *mut moor_call,
    list: *mut moor_ref,
    item: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let list = unsafe { list_of(list) }?;
        Ok(list.clone().push_owned(&unsafe { required(&item) }?))
    })
}

unsafe extern "C" fn list_set(
    call: *mut moor_call,
    list: *mut moor_ref,
    index: usize,
    item: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let list = unsafe { list_of(list) }?;
        list.clone()
            .index_set_owned(index, &unsafe { required(&item) }?)
    })
}

unsafe extern "C" fn map_set(
    call: *mut moor_call,
    map: *mut moor_ref,
    key: moor_value,
    value: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let map = unsafe { map_of(map) }?;
        map.set(&unsafe { required(&key) }?, &unsafe { required(&value) }?)
    })
}

unsafe extern "C" fn map_remove(
    call: *mut moor_call,
    map: *mut moor_ref,
    key: moor_value,
    out: *mut moor_value,
) -> moor_status {
    make(call, out, |_| {
        let map = unsafe { map_of(map) }?;
        Ok(map.remove_key(&unsafe { required(&key) }?).0)
    })
}

// --- Objects ---

unsafe extern "C" fn obj_from_number(number: i32) -> moor_obj {
    Obj::mk_id(number).as_u64()
}

unsafe extern "C" fn obj_number(obj: moor_obj, out: *mut i32) -> bool {
    match Obj::try_read(obj) {
        Ok(obj) if obj.is_oid() => {
            unsafe { write(out, obj.id().0) };
            true
        }
        _ => false,
    }
}

// --- The world ---

/// Why a world request failed: a MOO error, or a transaction conflict to pass on.
enum WorldFailure {
    Error(Error),
    World(WorldStateError),
}

impl From<Error> for WorldFailure {
    fn from(e: Error) -> Self {
        WorldFailure::Error(e)
    }
}

impl From<WorldStateError> for WorldFailure {
    fn from(e: WorldStateError) -> Self {
        WorldFailure::World(e)
    }
}

/// Run a world request as the verb's programmer, writing what it finds.
fn world<T>(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut T,
    request: impl FnOnce(&mut NativeCallContext, Obj) -> Result<T, WorldFailure>,
) -> moor_status {
    let call = unsafe { context(call) };
    call.requests += 1;
    if !has_active_task() {
        return call.fail(E_INVARG.msg("A native verb run outside a task has no world to read"));
    }
    let found = object(obj)
        .map_err(WorldFailure::Error)
        .and_then(|obj| request(call, obj));
    match found {
        Ok(found) => {
            unsafe { write(out, found) };
            MOOR_OK
        }
        Err(WorldFailure::Error(e)) => call.fail(e),
        Err(WorldFailure::World(e)) => call.world_failure(e),
    }
}

/// As `world`, for requests whose result is a value.
fn world_value(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_value,
    request: impl FnOnce(&NativeCallContext, Obj) -> Result<Var, WorldFailure>,
) -> moor_status {
    world(call, obj, out, |call, obj| {
        let found = request(call, obj)?;
        Ok(call.value(&found))
    })
}

fn named(value: &moor_value) -> Result<Symbol, WorldFailure> {
    Ok(name_of(&unsafe { required(value) }?)?)
}

unsafe extern "C" fn valid(call: *mut moor_call, obj: moor_obj, out: *mut bool) -> moor_status {
    world(call, obj, out, |_, obj| {
        Ok(with_current_transaction(|ws| ws.valid(&obj))?)
    })
}

unsafe extern "C" fn parent(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_obj,
) -> moor_status {
    world(call, obj, out, |call, obj| {
        Ok(with_current_transaction(|ws| ws.parent_of(&call.permissions, &obj))?.as_u64())
    })
}

unsafe extern "C" fn children(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_value,
) -> moor_status {
    world_value(call, obj, out, |call, obj| {
        let set = with_current_transaction(|ws| ws.children_of(&call.permissions, &obj))?;
        Ok(objects(set.iter()))
    })
}

unsafe extern "C" fn ancestors(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_value,
) -> moor_status {
    world_value(call, obj, out, |call, obj| {
        let set = with_current_transaction(|ws| ws.ancestors_of(&call.permissions, &obj, false))?;
        Ok(objects(set.iter()))
    })
}

unsafe extern "C" fn isa(
    call: *mut moor_call,
    obj: moor_obj,
    ancestor: moor_obj,
    out: *mut bool,
) -> moor_status {
    world(call, obj, out, |_, obj| {
        let ancestor = object(ancestor)?;
        Ok(with_current_transaction(|ws| ws.isa(&obj, &ancestor))?)
    })
}

unsafe extern "C" fn location(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_obj,
) -> moor_status {
    world(call, obj, out, |call, obj| {
        Ok(with_current_transaction(|ws| ws.location_of(&call.permissions, &obj))?.as_u64())
    })
}

unsafe extern "C" fn contents(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_value,
) -> moor_status {
    world_value(call, obj, out, |call, obj| {
        let set = with_current_transaction(|ws| ws.contents_of(&call.permissions, &obj))?;
        Ok(objects(set.iter()))
    })
}

unsafe extern "C" fn owner(call: *mut moor_call, obj: moor_obj, out: *mut moor_obj) -> moor_status {
    world(call, obj, out, |_, obj| {
        Ok(with_current_transaction(|ws| ws.owner_of(&obj))?.as_u64())
    })
}

unsafe extern "C" fn name(
    call: *mut moor_call,
    obj: moor_obj,
    out: *mut moor_value,
) -> moor_status {
    world_value(call, obj, out, |call, obj| {
        Ok(v_str(&with_current_transaction(|ws| {
            ws.name_of(&call.permissions, &obj)
        })?))
    })
}

unsafe extern "C" fn flags(call: *mut moor_call, obj: moor_obj, out: *mut u16) -> moor_status {
    world(call, obj, out, |_, obj| {
        let flags: BitEnum<ObjFlag> = with_current_transaction(|ws| ws.flags_of(&obj))?;
        Ok(flags.to_u16())
    })
}

unsafe extern "C" fn property(
    call: *mut moor_call,
    obj: moor_obj,
    name: moor_value,
    out: *mut moor_value,
) -> moor_status {
    world_value(call, obj, out, |call, obj| {
        let name = named(&name)?;
        Ok(with_current_transaction(|ws| {
            ws.retrieve_property(&call.permissions, &obj, name)
        })?)
    })
}

unsafe extern "C" fn set_property(
    call: *mut moor_call,
    obj: moor_obj,
    name: moor_value,
    value: moor_value,
) -> moor_status {
    world(call, obj, std::ptr::null_mut::<()>(), |call, obj| {
        let name = named(&name)?;
        let value = unsafe { required(&value) }?;
        Ok(with_current_transaction_mut(|ws| {
            ws.update_property(&call.permissions, &obj, name, &value)
        })?)
    })
}

unsafe extern "C" fn metadata(
    call: *mut moor_call,
    obj: moor_obj,
    key: moor_value,
    out: *mut moor_value,
) -> moor_status {
    world(call, obj, out, |call, obj| {
        let key = named(&key)?;
        let found =
            with_current_transaction(|ws| ws.get_object_metadata(&call.permissions, &obj, key))?;
        Ok(call.optional_value(found.as_ref()))
    })
}

unsafe extern "C" fn set_metadata(
    call: *mut moor_call,
    obj: moor_obj,
    key: moor_value,
    value: moor_value,
) -> moor_status {
    world(call, obj, std::ptr::null_mut::<()>(), |call, obj| {
        let key = named(&key)?;
        let value = unsafe { required(&value) }?;
        Ok(with_current_transaction_mut(|ws| {
            ws.set_object_metadata(&call.permissions, &obj, key, value)
        })?)
    })
}

unsafe extern "C" fn responds_to(
    call: *mut moor_call,
    obj: moor_obj,
    verb: moor_value,
    out: *mut bool,
) -> moor_status {
    world(call, obj, out, |call, obj| {
        let verb = named(&verb)?;
        let found = with_current_transaction(|ws| {
            ws.dispatch_verb(
                &call.permissions,
                VerbDispatch::new(
                    VerbLookup::method(&obj, verb),
                    DispatchFlagsSource::Permissions,
                ),
            )
        })?;
        Ok(found.is_some())
    })
}

/// The table the daemon passes every library.
pub(crate) static API: moor_api = moor_api {
    abi_version: MOOR_NATIVE_ABI,
    size: size_of::<moor_api>() as u32,
    this_value,
    player,
    caller,
    verb,
    args,
    arg_count,
    arg,
    args_read,
    programmer,
    step,
    state,
    result,
    ret,
    call_verb,
    call_builtin,
    raise,
    raise_value,
    pending_error,
    clear_error,
    retain,
    release,
    local,
    ref_type,
    get_str,
    get_binary,
    length,
    list_get,
    list_read,
    list_ints,
    list_floats,
    map_get,
    map_entry,
    map_read,
    error_parts,
    flyweight_parts,
    same,
    equal,
    compare,
    to_literal: literal,
    new_str,
    new_sym,
    new_binary,
    new_list,
    new_list_ints,
    new_list_floats,
    new_map,
    new_error,
    new_flyweight,
    list_append,
    list_set,
    map_set,
    map_remove,
    obj_from_number,
    obj_number,
    valid,
    parent,
    children,
    ancestors,
    isa,
    location,
    contents,
    owner,
    name,
    flags,
    property,
    set_property,
    metadata,
    set_metadata,
    responds_to,
};

/// Whether a value may be a native verb's result: anything but the clear value.
pub(crate) fn returnable(value: &Var) -> bool {
    value.type_code() != VarType::TYPE_NONE
}
