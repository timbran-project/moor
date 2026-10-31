// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Lesser General Public License as published by the Free Software Foundation,
// version 3 or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
// details.
//
// You should have received a copy of the GNU Lesser General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Native verb libraries in Rust.
//!
//! A native verb library is a shared library an administrator lists in the daemon's
//! configuration. The interface is C, defined in `include/moor_native.h` and mirrored in
//! [`ffi`]: a library need not be built with the same compiler or crates as the daemon. This
//! crate wraps that interface for Rust; declare a library with [`native_verb_library!`].
//!
//! A [`Value`] is any MOO value. Integers, floats, booleans and objects are held in it directly;
//! anything else stays in the daemon and the value holds a [`Ref`] to it, through which it is
//! read. Lists of numbers can be read and made in one call, with [`Ref::ints`] and
//! [`Call::list_ints`] and their float forms.
//!
//! A verb is a function `fn(&Call) -> Result<Done>`. It ends each step with [`Call::ret`],
//! [`Call::call_verb`] or [`Call::call_builtin`], each of which gives the [`Done`] the function
//! returns. A verb that calls out is called again at the step it named, with the value it chose
//! to carry as [`Call::state`] and the callee's result as [`Call::result`].
//!
//! When a daemon function fails, its error is left pending in the daemon and the wrapper returns
//! [`Stop::Error`]; returning that from the verb raises the error, so `?` passes errors on as
//! MOO would. [`Stop::Conflict`] means the transaction conflicted and the task will be retried;
//! it must be returned as it is.

pub mod ffi;

use ffi::{
    MOOR_CONFLICT, MOOR_ERROR, MOOR_OK, moor_api, moor_call, moor_ref, moor_status, moor_value,
    moor_value_as,
};
use std::{
    ffi::c_char,
    marker::PhantomData,
    panic::{AssertUnwindSafe, catch_unwind},
    ptr::{self, NonNull},
    sync::OnceLock,
};

static API: OnceLock<&'static moor_api> = OnceLock::new();

/// Keep the daemon's function table. Called by the entry function [`native_verb_library!`]
/// writes; returns false if the table is from another version of the interface.
///
/// # Safety
///
/// `api` must be the table the daemon passes, valid for the rest of the process.
#[doc(hidden)]
pub unsafe fn install(api: *const moor_api) -> bool {
    // SAFETY: the caller's guarantee.
    let Some(api) = (unsafe { api.as_ref() }) else {
        return false;
    };
    if api.abi_version != ffi::MOOR_NATIVE_ABI || (api.size as usize) < size_of::<moor_api>() {
        return false;
    }
    let _ = API.set(api);
    true
}

fn api() -> &'static moor_api {
    API.get()
        .expect("native verb called before the daemon passed its function table")
}

/// Why a step stopped before ending normally.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stop {
    /// An error is pending in the daemon; returning this raises it.
    Error,
    /// The transaction conflicted; returning this retries the task.
    Conflict,
}

pub type Result<T> = std::result::Result<T, Stop>;

fn check(status: moor_status) -> Result<()> {
    match status {
        MOOR_OK => Ok(()),
        MOOR_CONFLICT => Err(Stop::Conflict),
        _ => Err(Stop::Error),
    }
}

/// Proof that a step chose how to end.
#[must_use]
pub struct Done(());

/// An object reference.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Obj(pub ffi::moor_obj);

impl Obj {
    /// The numbered object `#number`.
    pub fn number(number: i32) -> Self {
        // SAFETY: a pure function of its argument.
        Obj(unsafe { (api().obj_from_number)(number) })
    }

    /// This object's number, if it is a numbered object.
    pub fn as_number(self) -> Option<i32> {
        let mut out = 0;
        // SAFETY: `out` is writable.
        unsafe { (api().obj_number)(self.0, &mut out) }.then_some(out)
    }
}

/// A value's type.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    Int,
    Obj,
    Str,
    Err,
    List,
    Float,
    Map,
    Bool,
    Flyweight,
    Symbol,
    Binary,
    Lambda,
    Other(i32),
}

impl Type {
    fn from_code(code: i32) -> Self {
        match code {
            ffi::MOOR_TYPE_INT => Type::Int,
            ffi::MOOR_TYPE_OBJ => Type::Obj,
            ffi::MOOR_TYPE_STR => Type::Str,
            ffi::MOOR_TYPE_ERR => Type::Err,
            ffi::MOOR_TYPE_LIST => Type::List,
            ffi::MOOR_TYPE_FLOAT => Type::Float,
            ffi::MOOR_TYPE_MAP => Type::Map,
            ffi::MOOR_TYPE_BOOL => Type::Bool,
            ffi::MOOR_TYPE_FLYWEIGHT => Type::Flyweight,
            ffi::MOOR_TYPE_SYMBOL => Type::Symbol,
            ffi::MOOR_TYPE_BINARY => Type::Binary,
            ffi::MOOR_TYPE_LAMBDA => Type::Lambda,
            other => Type::Other(other),
        }
    }
}

/// A MOO value: a scalar held directly, or a [`Ref`] to a value the daemon holds.
#[derive(Clone, Copy, Debug)]
pub enum Value<'c> {
    Int(i64),
    Float(f64),
    Bool(bool),
    Obj(Obj),
    Ref(Ref<'c>),
}

/// A value the daemon holds: a string, symbol, list, map, error, flyweight, binary or lambda,
/// valid for the step it came from.
#[derive(Clone, Copy)]
pub struct Ref<'c> {
    raw: NonNull<moor_ref>,
    call: *mut moor_call,
    _call: PhantomData<&'c moor_call>,
}

impl std::fmt::Debug for Ref<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let literal = self.call().literal(Value::Ref(*self));
        match literal.as_ref().map(|r| r.as_str()) {
            Some(Ok(text)) => f.write_str(text),
            _ => f.write_str("<ref>"),
        }
    }
}

impl From<i64> for Value<'_> {
    fn from(i: i64) -> Self {
        Value::Int(i)
    }
}

impl From<f64> for Value<'_> {
    fn from(f: f64) -> Self {
        Value::Float(f)
    }
}

impl From<bool> for Value<'_> {
    fn from(b: bool) -> Self {
        Value::Bool(b)
    }
}

impl From<Obj> for Value<'_> {
    fn from(o: Obj) -> Self {
        Value::Obj(o)
    }
}

impl<'c> From<Ref<'c>> for Value<'c> {
    fn from(r: Ref<'c>) -> Self {
        Value::Ref(r)
    }
}

impl<'c> Value<'c> {
    pub fn type_of(&self) -> Type {
        Type::from_code(self.type_code())
    }

    fn type_code(&self) -> i32 {
        match self {
            Value::Int(_) => ffi::MOOR_TYPE_INT,
            Value::Float(_) => ffi::MOOR_TYPE_FLOAT,
            Value::Bool(_) => ffi::MOOR_TYPE_BOOL,
            Value::Obj(_) => ffi::MOOR_TYPE_OBJ,
            Value::Ref(r) => r.type_code(),
        }
    }

    pub fn as_int(&self) -> Option<i64> {
        match self {
            Value::Int(i) => Some(*i),
            _ => None,
        }
    }

    pub fn as_float(&self) -> Option<f64> {
        match self {
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }

    /// An integer or float, as a float.
    pub fn as_number(&self) -> Option<f64> {
        match self {
            Value::Int(i) => Some(*i as f64),
            Value::Float(f) => Some(*f),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_obj(&self) -> Option<Obj> {
        match self {
            Value::Obj(o) => Some(*o),
            _ => None,
        }
    }

    pub fn as_ref(&self) -> Option<Ref<'c>> {
        match self {
            Value::Ref(r) => Some(*r),
            _ => None,
        }
    }

    /// The integer, or `E_TYPE` pending on `call`.
    pub fn int(&self, call: &Call<'c>) -> Result<i64> {
        self.as_int().ok_or_else(|| call.wrong_type("an integer"))
    }

    /// The integer or float, as a float, or `E_TYPE` pending on `call`.
    pub fn number(&self, call: &Call<'c>) -> Result<f64> {
        self.as_number().ok_or_else(|| call.wrong_type("a number"))
    }

    pub fn bool(&self, call: &Call<'c>) -> Result<bool> {
        self.as_bool().ok_or_else(|| call.wrong_type("a boolean"))
    }

    pub fn obj(&self, call: &Call<'c>) -> Result<Obj> {
        self.as_obj().ok_or_else(|| call.wrong_type("an object"))
    }

    /// The ref of a value that is not a scalar, or `E_TYPE` pending on `call`.
    pub fn reference(&self, call: &Call<'c>) -> Result<Ref<'c>> {
        self.as_ref()
            .ok_or_else(|| call.wrong_type("a string, list, map or other value"))
    }

    /// A list's ref, or `E_TYPE` pending on `call`.
    pub fn list(&self, call: &Call<'c>) -> Result<Ref<'c>> {
        self.as_ref()
            .filter(|r| r.type_of() == Type::List)
            .ok_or_else(|| call.wrong_type("a list"))
    }

    /// A map's ref, or `E_TYPE` pending on `call`.
    pub fn map(&self, call: &Call<'c>) -> Result<Ref<'c>> {
        self.as_ref()
            .filter(|r| r.type_of() == Type::Map)
            .ok_or_else(|| call.wrong_type("a map"))
    }

    /// A string's or symbol's text, or `E_TYPE` pending on `call`.
    pub fn str(&self, call: &Call<'c>) -> Result<&'c str> {
        match self.as_ref() {
            Some(r) => r.as_str(),
            None => Err(call.wrong_type("a string")),
        }
    }

    /// Whether `other` is the very same value: an equal scalar, or a ref to the same storage.
    /// True for a property read twice while it is unchanged, which makes it a cheap test of
    /// whether something computed from a value still holds.
    pub fn same(&self, other: Value<'_>) -> bool {
        // SAFETY: both values are valid during their calls.
        unsafe { (api().same)(raw(self), raw(&other)) }
    }

    /// MOO's `==`.
    pub fn equal(&self, other: Value<'_>) -> bool {
        // SAFETY: as for `same`.
        unsafe { (api().equal)(raw(self), raw(&other)) }
    }
}

/// The C form of a value.
fn raw(value: &Value<'_>) -> moor_value {
    let (type_, as_) = match *value {
        Value::Int(i) => (ffi::MOOR_TYPE_INT, moor_value_as { i }),
        Value::Float(f) => (ffi::MOOR_TYPE_FLOAT, moor_value_as { f }),
        Value::Bool(b) => (ffi::MOOR_TYPE_BOOL, moor_value_as { b }),
        Value::Obj(o) => (ffi::MOOR_TYPE_OBJ, moor_value_as { o: o.0 }),
        Value::Ref(r) => (
            r.type_code(),
            moor_value_as {
                ref_: r.raw.as_ptr(),
            },
        ),
    };
    moor_value { type_, as_ }
}

fn raw_optional(value: Option<Value<'_>>) -> moor_value {
    value.as_ref().map_or(moor_value::NONE, raw)
}

fn none_values(count: usize) -> Vec<moor_value> {
    vec![moor_value::NONE; count]
}

/// A ref kept beyond the step it came from, for any later call. Dropping it lets the daemon
/// free the value.
pub struct Retained {
    raw: NonNull<moor_ref>,
}

// A retained ref is a reference to an immutable value the daemon shares between threads.
unsafe impl Send for Retained {}
unsafe impl Sync for Retained {}

impl Drop for Retained {
    fn drop(&mut self) {
        // SAFETY: the ref came from `retain` and is released once.
        unsafe { (api().release)(self.raw.as_ptr()) }
    }
}

impl Retained {
    /// A ref to the value for use during `call`, made in the call: it stays valid for the rest
    /// of the call whether or not this is dropped.
    pub fn get<'c>(&self, call: &Call<'c>) -> Ref<'c> {
        // SAFETY: the retained ref is live while `self` is, and `call` is the call in progress.
        call.must_ref(unsafe { (api().local)(call.raw, self.raw.as_ptr()) })
    }
}

/// A native verb call in progress.
pub struct Call<'c> {
    raw: *mut moor_call,
    _call: PhantomData<&'c mut moor_call>,
}

impl<'c> Call<'c> {
    fn wrap_ref(&self, raw: NonNull<moor_ref>) -> Ref<'c> {
        Ref {
            raw,
            call: self.raw,
            _call: PhantomData,
        }
    }

    /// A ref the daemon always gives.
    fn must_ref(&self, raw: *mut moor_ref) -> Ref<'c> {
        self.wrap_ref(NonNull::new(raw).expect("the daemon gave no ref where it always gives one"))
    }

    /// A value from its C form; none for MOOR_TYPE_NONE.
    fn wrap(&self, raw: &moor_value) -> Option<Value<'c>> {
        // SAFETY: the daemon fills the member `type_` names.
        unsafe {
            Some(match raw.type_ {
                ffi::MOOR_TYPE_NONE => return None,
                ffi::MOOR_TYPE_INT => Value::Int(raw.as_.i),
                ffi::MOOR_TYPE_FLOAT => Value::Float(raw.as_.f),
                ffi::MOOR_TYPE_BOOL => Value::Bool(raw.as_.b),
                ffi::MOOR_TYPE_OBJ => Value::Obj(Obj(raw.as_.o)),
                _ => Value::Ref(self.wrap_ref(NonNull::new(raw.as_.ref_)?)),
            })
        }
    }

    /// A value the daemon always gives.
    fn must(&self, raw: &moor_value) -> Value<'c> {
        self.wrap(raw)
            .expect("the daemon gave no value where it always gives one")
    }

    /// Run `f`, which writes a value through its pointer, and wrap what it wrote.
    fn out(&self, f: impl FnOnce(*mut moor_value) -> moor_status) -> Result<Value<'c>> {
        let mut out = moor_value::NONE;
        check(f(&mut out))?;
        Ok(self.must(&out))
    }

    fn out_optional(
        &self,
        f: impl FnOnce(*mut moor_value) -> moor_status,
    ) -> Result<Option<Value<'c>>> {
        let mut out = moor_value::NONE;
        check(f(&mut out))?;
        Ok(self.wrap(&out))
    }

    fn wrong_type(&self, expected: &str) -> Stop {
        self.raise("E_TYPE", &format!("Expected {expected}"))
    }

    // --- The call ---

    pub fn this(&self) -> Value<'c> {
        // SAFETY: `raw` is the call in progress, here and below.
        self.must(&unsafe { (api().this_value)(self.raw) })
    }

    pub fn player(&self) -> Obj {
        Obj(unsafe { (api().player)(self.raw) })
    }

    pub fn caller(&self) -> Value<'c> {
        self.must(&unsafe { (api().caller)(self.raw) })
    }

    /// The verb's name, a symbol.
    pub fn verb(&self) -> Ref<'c> {
        self.must_ref(unsafe { (api().verb)(self.raw) })
    }

    /// The arguments, a list.
    pub fn args(&self) -> Ref<'c> {
        self.must_ref(unsafe { (api().args)(self.raw) })
    }

    pub fn arg_count(&self) -> usize {
        unsafe { (api().arg_count)(self.raw) }
    }

    /// The argument at `index`, from 0; `E_ARGS` if there is none.
    pub fn arg(&self, index: usize) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().arg)(self.raw, index, out) })
    }

    /// All the arguments, read in one call.
    pub fn arg_values(&self) -> Result<Vec<Value<'c>>> {
        let count = self.arg_count();
        let mut raw = none_values(count);
        check(unsafe { (api().args_read)(self.raw, 0, raw.as_mut_ptr(), count) })?;
        Ok(raw.iter().map(|v| self.must(v)).collect())
    }

    /// Whose permissions the verb runs with: its owner.
    pub fn programmer(&self) -> Obj {
        Obj(unsafe { (api().programmer)(self.raw) })
    }

    /// The step being run: 0 at first, then the one named when calling out.
    pub fn step(&self) -> u32 {
        unsafe { (api().step)(self.raw) }
    }

    /// The value carried to this step, if any.
    pub fn state(&self) -> Option<Value<'c>> {
        self.wrap(&unsafe { (api().state)(self.raw) })
    }

    /// The result of the verb or builtin called, when resuming.
    pub fn result(&self) -> Option<Value<'c>> {
        self.wrap(&unsafe { (api().result)(self.raw) })
    }

    // --- Ending a step ---

    /// Return `value` from the verb.
    pub fn ret(&self, value: impl Into<Value<'c>>) -> Done {
        // Only the absent value is refused, and a `Value` is never absent.
        unsafe { (api().ret)(self.raw, raw(&value.into())) };
        Done(())
    }

    /// Call `verb` on `target`, resuming at `step` (not 0) with `state`.
    pub fn call_verb(
        &self,
        target: Value<'c>,
        verb: Value<'c>,
        args: Value<'c>,
        step: u32,
        state: Option<Value<'c>>,
    ) -> Result<Done> {
        check(unsafe {
            (api().call_verb)(
                self.raw,
                raw(&target),
                raw(&verb),
                raw(&args),
                step,
                raw_optional(state),
            )
        })?;
        Ok(Done(()))
    }

    /// Call the builtin `name`, resuming at `step` (not 0) with `state`.
    pub fn call_builtin(
        &self,
        name: Value<'c>,
        args: Value<'c>,
        step: u32,
        state: Option<Value<'c>>,
    ) -> Result<Done> {
        check(unsafe {
            (api().call_builtin)(self.raw, raw(&name), raw(&args), step, raw_optional(state))
        })?;
        Ok(Done(()))
    }

    // --- Errors ---

    /// Leave an error pending, with `code` such as `"E_INVARG"`, and give the [`Stop`] to
    /// return: `return Err(call.raise("E_RANGE", "too far"))`.
    pub fn raise(&self, code: &str, message: &str) -> Stop {
        unsafe {
            (api().raise)(
                self.raw,
                code.as_ptr() as *const c_char,
                code.len(),
                message.as_ptr() as *const c_char,
                message.len(),
            )
        };
        Stop::Error
    }

    /// Leave the error value `error` pending.
    pub fn raise_value(&self, error: Value<'c>) -> Stop {
        unsafe { (api().raise_value)(self.raw, raw(&error)) };
        Stop::Error
    }

    /// The pending error, if any.
    pub fn pending_error(&self) -> Option<Value<'c>> {
        self.wrap(&unsafe { (api().pending_error)(self.raw) })
    }

    /// Drop the pending error, to carry on after a failure.
    pub fn clear_error(&self) {
        unsafe { (api().clear_error)(self.raw) }
    }

    // --- Comparing and showing values ---

    /// MOO's ordering.
    pub fn compare(&self, a: Value<'c>, b: Value<'c>) -> Result<std::cmp::Ordering> {
        let mut out = 0;
        check(unsafe { (api().compare)(self.raw, raw(&a), raw(&b), &mut out) })?;
        Ok(out.cmp(&0))
    }

    /// MOO's `toliteral()`, a string's ref.
    pub fn literal(&self, value: Value<'c>) -> Option<Ref<'c>> {
        self.wrap(&unsafe { (api().to_literal)(self.raw, raw(&value)) })
            .and_then(|v| v.as_ref())
    }

    // --- Making values ---

    pub fn str(&self, value: &str) -> Value<'c> {
        // A &str is UTF-8, so this cannot fail.
        self.out(|out| unsafe {
            (api().new_str)(self.raw, value.as_ptr() as *const c_char, value.len(), out)
        })
        .expect("the daemon refused a UTF-8 string")
    }

    pub fn sym(&self, value: &str) -> Value<'c> {
        self.out(|out| unsafe {
            (api().new_sym)(self.raw, value.as_ptr() as *const c_char, value.len(), out)
        })
        .expect("the daemon refused a UTF-8 symbol")
    }

    pub fn binary(&self, value: &[u8]) -> Value<'c> {
        self.must(&unsafe { (api().new_binary)(self.raw, value.as_ptr(), value.len()) })
    }

    pub fn list(&self, items: &[Value<'c>]) -> Value<'c> {
        let raw: Vec<moor_value> = items.iter().map(raw).collect();
        // Values made by this wrapper are well formed, so this cannot fail.
        self.out(|out| unsafe { (api().new_list)(self.raw, raw.as_ptr(), raw.len(), out) })
            .expect("the daemon refused well-formed values")
    }

    /// A list of `items`, made as they come.
    pub fn list_from(&self, items: impl IntoIterator<Item = Value<'c>>) -> Value<'c> {
        let items: Vec<Value<'c>> = items.into_iter().collect();
        self.list(&items)
    }

    pub fn list_ints(&self, items: &[i64]) -> Value<'c> {
        self.must(&unsafe { (api().new_list_ints)(self.raw, items.as_ptr(), items.len()) })
    }

    pub fn list_floats(&self, items: &[f64]) -> Value<'c> {
        self.must(&unsafe { (api().new_list_floats)(self.raw, items.as_ptr(), items.len()) })
    }

    pub fn map(&self, entries: &[(Value<'c>, Value<'c>)]) -> Result<Value<'c>> {
        let keys: Vec<moor_value> = entries.iter().map(|(k, _)| raw(k)).collect();
        let values: Vec<moor_value> = entries.iter().map(|(_, v)| raw(v)).collect();
        self.out(|out| unsafe {
            (api().new_map)(self.raw, keys.as_ptr(), values.as_ptr(), keys.len(), out)
        })
    }

    /// An error value, with `code` such as `"E_INVARG"`.
    pub fn error(&self, code: &str, message: &str, value: Option<Value<'c>>) -> Result<Value<'c>> {
        self.out(|out| unsafe {
            (api().new_error)(
                self.raw,
                code.as_ptr() as *const c_char,
                code.len(),
                message.as_ptr() as *const c_char,
                message.len(),
                raw_optional(value),
                out,
            )
        })
    }

    /// A flyweight with `delegate`, `slots` (a map of names to values) and `contents`.
    pub fn flyweight(
        &self,
        delegate: Obj,
        slots: Option<Value<'c>>,
        contents: Option<Value<'c>>,
    ) -> Result<Value<'c>> {
        self.out(|out| unsafe {
            (api().new_flyweight)(
                self.raw,
                delegate.0,
                raw_optional(slots),
                raw_optional(contents),
                out,
            )
        })
    }

    // --- The world, as the verb's programmer ---

    pub fn valid(&self, obj: Obj) -> Result<bool> {
        let mut out = false;
        check(unsafe { (api().valid)(self.raw, obj.0, &mut out) })?;
        Ok(out)
    }

    pub fn parent(&self, obj: Obj) -> Result<Obj> {
        let mut out = 0;
        check(unsafe { (api().parent)(self.raw, obj.0, &mut out) })?;
        Ok(Obj(out))
    }

    pub fn children(&self, obj: Obj) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().children)(self.raw, obj.0, out) })
    }

    pub fn ancestors(&self, obj: Obj) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().ancestors)(self.raw, obj.0, out) })
    }

    pub fn isa(&self, obj: Obj, ancestor: Obj) -> Result<bool> {
        let mut out = false;
        check(unsafe { (api().isa)(self.raw, obj.0, ancestor.0, &mut out) })?;
        Ok(out)
    }

    pub fn location(&self, obj: Obj) -> Result<Obj> {
        let mut out = 0;
        check(unsafe { (api().location)(self.raw, obj.0, &mut out) })?;
        Ok(Obj(out))
    }

    pub fn contents(&self, obj: Obj) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().contents)(self.raw, obj.0, out) })
    }

    pub fn owner(&self, obj: Obj) -> Result<Obj> {
        let mut out = 0;
        check(unsafe { (api().owner)(self.raw, obj.0, &mut out) })?;
        Ok(Obj(out))
    }

    pub fn name(&self, obj: Obj) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().name)(self.raw, obj.0, out) })
    }

    /// The object's flags, as `ffi::MOOR_FLAG_*` bits.
    pub fn flags(&self, obj: Obj) -> Result<u16> {
        let mut out = 0;
        check(unsafe { (api().flags)(self.raw, obj.0, &mut out) })?;
        Ok(out)
    }

    /// A property, named by a symbol or string.
    pub fn property(&self, obj: Obj, name: Value<'c>) -> Result<Value<'c>> {
        self.out(|out| unsafe { (api().property)(self.raw, obj.0, raw(&name), out) })
    }

    pub fn set_property(&self, obj: Obj, name: Value<'c>, value: Value<'c>) -> Result<()> {
        check(unsafe { (api().set_property)(self.raw, obj.0, raw(&name), raw(&value)) })
    }

    /// Object metadata, keyed by a symbol or string.
    pub fn metadata(&self, obj: Obj, key: Value<'c>) -> Result<Option<Value<'c>>> {
        self.out_optional(|out| unsafe { (api().metadata)(self.raw, obj.0, raw(&key), out) })
    }

    pub fn set_metadata(&self, obj: Obj, key: Value<'c>, value: Value<'c>) -> Result<()> {
        check(unsafe { (api().set_metadata)(self.raw, obj.0, raw(&key), raw(&value)) })
    }

    /// Whether `verb` can be called on `obj`.
    pub fn responds_to(&self, obj: Obj, verb: Value<'c>) -> Result<bool> {
        let mut out = false;
        check(unsafe { (api().responds_to)(self.raw, obj.0, raw(&verb), &mut out) })?;
        Ok(out)
    }
}

impl<'c> Ref<'c> {
    fn call(&self) -> Call<'c> {
        Call {
            raw: self.call,
            _call: PhantomData,
        }
    }

    fn ptr(&self) -> *mut moor_ref {
        self.raw.as_ptr()
    }

    fn type_code(&self) -> i32 {
        // SAFETY: the ref is valid during its call, here and below.
        unsafe { (api().ref_type)(self.ptr()) }
    }

    pub fn type_of(&self) -> Type {
        Type::from_code(self.type_code())
    }

    /// A string's or symbol's text, borrowed from the daemon.
    pub fn as_str(&self) -> Result<&'c str> {
        let mut ptr = ptr::null();
        let mut len = 0;
        check(unsafe { (api().get_str)(self.call, self.ptr(), &mut ptr, &mut len) })?;
        if len == 0 {
            return Ok("");
        }
        // SAFETY: the daemon's strings are UTF-8, and live as long as the ref.
        Ok(unsafe {
            std::str::from_utf8_unchecked(std::slice::from_raw_parts(ptr.cast::<u8>(), len))
        })
    }

    /// A binary's bytes, borrowed from the daemon.
    pub fn as_bytes(&self) -> Result<&'c [u8]> {
        let mut ptr = ptr::null();
        let mut len = 0;
        check(unsafe { (api().get_binary)(self.call, self.ptr(), &mut ptr, &mut len) })?;
        if len == 0 {
            return Ok(&[]);
        }
        // SAFETY: the bytes live as long as the ref.
        Ok(unsafe { std::slice::from_raw_parts(ptr, len) })
    }

    /// As MOO's `length()`.
    pub fn len(&self) -> Result<usize> {
        let mut out = 0;
        check(unsafe { (api().length)(self.call, self.ptr(), &mut out) })?;
        Ok(out)
    }

    pub fn is_empty(&self) -> Result<bool> {
        Ok(self.len()? == 0)
    }

    /// The list item at `index`, from 0.
    pub fn get(&self, index: usize) -> Result<Value<'c>> {
        self.call()
            .out(|out| unsafe { (api().list_get)(self.call, self.ptr(), index, out) })
    }

    /// A list's items, read in one call.
    pub fn items(&self) -> Result<Vec<Value<'c>>> {
        let len = self.len()?;
        self.read(0, len)
    }

    /// `count` items of a list from `start`, from 0, read in one call.
    pub fn read(&self, start: usize, count: usize) -> Result<Vec<Value<'c>>> {
        let mut raw = none_values(count);
        check(unsafe { (api().list_read)(self.call, self.ptr(), start, raw.as_mut_ptr(), count) })?;
        let call = self.call();
        Ok(raw.iter().map(|v| call.must(v)).collect())
    }

    /// A list that must be all integers.
    pub fn ints(&self) -> Result<Vec<i64>> {
        let mut out = vec![0; self.len()?];
        self.read_ints(0, &mut out)?;
        Ok(out)
    }

    /// Integers from `start` into `out`.
    pub fn read_ints(&self, start: usize, out: &mut [i64]) -> Result<()> {
        check(unsafe {
            (api().list_ints)(self.call, self.ptr(), start, out.as_mut_ptr(), out.len())
        })
    }

    /// A list that must be all numbers, as floats.
    pub fn floats(&self) -> Result<Vec<f64>> {
        let mut out = vec![0.0; self.len()?];
        self.read_floats(0, &mut out)?;
        Ok(out)
    }

    /// Numbers from `start` into `out`, as floats.
    pub fn read_floats(&self, start: usize, out: &mut [f64]) -> Result<()> {
        check(unsafe {
            (api().list_floats)(self.call, self.ptr(), start, out.as_mut_ptr(), out.len())
        })
    }

    /// The map value at `key`, if any.
    pub fn map_get(&self, key: Value<'c>) -> Result<Option<Value<'c>>> {
        self.call()
            .out_optional(|out| unsafe { (api().map_get)(self.call, self.ptr(), raw(&key), out) })
    }

    /// The map entry at `index`, from 0.
    pub fn entry(&self, index: usize) -> Result<(Value<'c>, Value<'c>)> {
        let (mut key, mut value) = (moor_value::NONE, moor_value::NONE);
        check(unsafe { (api().map_entry)(self.call, self.ptr(), index, &mut key, &mut value) })?;
        let call = self.call();
        Ok((call.must(&key), call.must(&value)))
    }

    /// A map's entries, in order, read in one call.
    pub fn entries(&self) -> Result<Vec<(Value<'c>, Value<'c>)>> {
        let count = self.len()?;
        let (mut keys, mut values) = (none_values(count), none_values(count));
        check(unsafe {
            (api().map_read)(
                self.call,
                self.ptr(),
                0,
                keys.as_mut_ptr(),
                values.as_mut_ptr(),
                count,
            )
        })?;
        let call = self.call();
        Ok(keys
            .iter()
            .zip(&values)
            .map(|(k, v)| (call.must(k), call.must(v)))
            .collect())
    }

    /// An error's code (a symbol), message and value.
    pub fn error_parts(&self) -> Result<(Value<'c>, Value<'c>, Option<Value<'c>>)> {
        let (mut code, mut message, mut value) =
            (moor_value::NONE, moor_value::NONE, moor_value::NONE);
        check(unsafe {
            (api().error_parts)(self.call, self.ptr(), &mut code, &mut message, &mut value)
        })?;
        let call = self.call();
        Ok((call.must(&code), call.must(&message), call.wrap(&value)))
    }

    /// A flyweight's delegate, slots (a map) and contents (a list).
    pub fn flyweight_parts(&self) -> Result<(Obj, Value<'c>, Value<'c>)> {
        let (mut delegate, mut slots, mut contents) = (0, moor_value::NONE, moor_value::NONE);
        check(unsafe {
            (api().flyweight_parts)(
                self.call,
                self.ptr(),
                &mut delegate,
                &mut slots,
                &mut contents,
            )
        })?;
        let call = self.call();
        Ok((Obj(delegate), call.must(&slots), call.must(&contents)))
    }

    /// A list with `item` added at the end.
    pub fn append(&self, item: Value<'c>) -> Result<Value<'c>> {
        self.call()
            .out(|out| unsafe { (api().list_append)(self.call, self.ptr(), raw(&item), out) })
    }

    /// A list with the item at `index`, from 0, replaced.
    pub fn with_item(&self, index: usize, item: Value<'c>) -> Result<Value<'c>> {
        self.call()
            .out(|out| unsafe { (api().list_set)(self.call, self.ptr(), index, raw(&item), out) })
    }

    /// A map with `key` set to `value`.
    pub fn with_entry(&self, key: Value<'c>, value: Value<'c>) -> Result<Value<'c>> {
        self.call().out(|out| unsafe {
            (api().map_set)(self.call, self.ptr(), raw(&key), raw(&value), out)
        })
    }

    /// A map without `key`.
    pub fn without_key(&self, key: Value<'c>) -> Result<Value<'c>> {
        self.call()
            .out(|out| unsafe { (api().map_remove)(self.call, self.ptr(), raw(&key), out) })
    }

    /// Whether `other` is a ref to the same storage. See [`Value::same`].
    pub fn same(&self, other: Ref<'_>) -> bool {
        Value::Ref(*self).same(Value::Ref(other))
    }

    /// Keep this value beyond the step, for later calls.
    pub fn retain(&self) -> Retained {
        let raw = unsafe { (api().retain)(self.call, self.ptr()) };
        Retained {
            raw: NonNull::new(raw).expect("the daemon refused to retain a value"),
        }
    }
}

/// Run a native verb written in Rust. A panic raises `E_INVARG` rather than unwinding into the
/// daemon.
///
/// # Safety
///
/// `call` must be the call the daemon passed.
#[doc(hidden)]
pub unsafe fn run(
    call: *mut moor_call,
    verb: for<'c> fn(&Call<'c>) -> Result<Done>,
) -> moor_status {
    let call = Call {
        raw: call,
        _call: PhantomData,
    };
    match catch_unwind(AssertUnwindSafe(|| verb(&call))) {
        Ok(Ok(Done(()))) => MOOR_OK,
        Ok(Err(Stop::Error)) => MOOR_ERROR,
        Ok(Err(Stop::Conflict)) => MOOR_CONFLICT,
        Err(panic) => {
            let message = panic
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| panic.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "unknown cause".to_string());
            let _ = call.raise("E_INVARG", &format!("Native verb panicked: {message}"));
            MOOR_ERROR
        }
    }
}

/// Declare a native verb library: its name, its version, and its functions, each a Rust
/// function `fn(&Call) -> Result<Done>` under the name verbs use for it.
///
/// ```ignore
/// fn column(call: &Call) -> Result<Done> { ... }
///
/// moor_native_verb::native_verb_library! {
///     name: "terrain",
///     version: "0.1.0",
///     functions: { "column" => column },
/// }
/// ```
#[macro_export]
macro_rules! native_verb_library {
    (
        name: $name:literal,
        version: $version:literal,
        functions: { $($function:literal => $implementation:ident),* $(,)? } $(,)?
    ) => {
        #[doc(hidden)]
        mod __moor_native_verb_shims {
            $(
                pub unsafe extern "C" fn $implementation(
                    call: *mut $crate::ffi::moor_call,
                ) -> $crate::ffi::moor_status {
                    // SAFETY: the daemon passes the call in progress.
                    unsafe { $crate::run(call, super::$implementation) }
                }
            )*
        }

        #[doc(hidden)]
        static __MOOR_NATIVE_VERB_FUNCTIONS: &[$crate::ffi::moor_function] = &[
            $(
                $crate::ffi::moor_function {
                    name: concat!($function, "\0").as_ptr() as *const ::std::ffi::c_char,
                    call: __moor_native_verb_shims::$implementation,
                },
            )*
        ];

        #[doc(hidden)]
        static __MOOR_NATIVE_VERB_LIBRARY: $crate::ffi::moor_library = $crate::ffi::moor_library {
            abi_version: $crate::ffi::MOOR_NATIVE_ABI,
            name: concat!($name, "\0").as_ptr() as *const ::std::ffi::c_char,
            version: concat!($version, "\0").as_ptr() as *const ::std::ffi::c_char,
            functions: __MOOR_NATIVE_VERB_FUNCTIONS.as_ptr(),
            function_count: __MOOR_NATIVE_VERB_FUNCTIONS.len(),
        };

        /// The library's descriptor, for the mooR daemon.
        ///
        /// # Safety
        ///
        /// `api` must be the daemon's function table.
        #[unsafe(no_mangle)]
        pub unsafe extern "C" fn moor_native_library(
            api: *const $crate::ffi::moor_api,
        ) -> *const $crate::ffi::moor_library {
            // SAFETY: the daemon passes its table, valid for the life of the process.
            if unsafe { $crate::install(api) } {
                &__MOOR_NATIVE_VERB_LIBRARY
            } else {
                ::std::ptr::null()
            }
        }
    };
}
