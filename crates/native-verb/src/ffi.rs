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

//! The C interface, as `include/moor_native.h` defines it. The two must agree field for field;
//! a test compiles the header against these definitions.

#![allow(non_camel_case_types)]

use std::ffi::c_char;

pub const MOOR_NATIVE_ABI: u32 = 1;

pub type moor_status = i32;
pub const MOOR_OK: moor_status = 0;
pub const MOOR_ERROR: moor_status = 1;
pub const MOOR_CONFLICT: moor_status = 2;

pub const MOOR_TYPE_INT: i32 = 0;
pub const MOOR_TYPE_OBJ: i32 = 1;
pub const MOOR_TYPE_STR: i32 = 2;
pub const MOOR_TYPE_ERR: i32 = 3;
pub const MOOR_TYPE_LIST: i32 = 4;
pub const MOOR_TYPE_NONE: i32 = 6;
pub const MOOR_TYPE_FLOAT: i32 = 9;
pub const MOOR_TYPE_MAP: i32 = 10;
pub const MOOR_TYPE_BOOL: i32 = 14;
pub const MOOR_TYPE_FLYWEIGHT: i32 = 15;
pub const MOOR_TYPE_SYMBOL: i32 = 16;
pub const MOOR_TYPE_BINARY: i32 = 17;
pub const MOOR_TYPE_LAMBDA: i32 = 18;

pub const MOOR_FLAG_USER: u16 = 1 << 0;
pub const MOOR_FLAG_PROGRAMMER: u16 = 1 << 1;
pub const MOOR_FLAG_WIZARD: u16 = 1 << 2;
pub const MOOR_FLAG_READ: u16 = 1 << 4;
pub const MOOR_FLAG_WRITE: u16 = 1 << 5;
pub const MOOR_FLAG_FERTILE: u16 = 1 << 7;

pub type moor_obj = u64;

/// A value the daemon holds. Only ever behind a pointer.
#[repr(C)]
pub struct moor_ref {
    _private: [u8; 0],
}

/// A call in progress. Only ever behind a pointer.
#[repr(C)]
pub struct moor_call {
    _private: [u8; 0],
}

/// A MOO value: a scalar in `as_`, or a ref to anything else.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct moor_value {
    pub type_: i32,
    pub as_: moor_value_as,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union moor_value_as {
    pub i: i64,
    pub f: f64,
    pub b: bool,
    pub o: moor_obj,
    pub ref_: *mut moor_ref,
}

impl moor_value {
    pub const NONE: moor_value = moor_value {
        type_: MOOR_TYPE_NONE,
        as_: moor_value_as { i: 0 },
    };
}

type Call = *mut moor_call;
type Ref = *mut moor_ref;
type Value = moor_value;

#[repr(C)]
pub struct moor_api {
    pub abi_version: u32,
    pub size: u32,

    // The call.
    pub this_value: unsafe extern "C" fn(call: Call) -> Value,
    pub player: unsafe extern "C" fn(call: Call) -> moor_obj,
    pub caller: unsafe extern "C" fn(call: Call) -> Value,
    pub verb: unsafe extern "C" fn(call: Call) -> Ref,
    pub args: unsafe extern "C" fn(call: Call) -> Ref,
    pub arg_count: unsafe extern "C" fn(call: Call) -> usize,
    pub arg: unsafe extern "C" fn(call: Call, index: usize, out: *mut Value) -> moor_status,
    pub args_read: unsafe extern "C" fn(
        call: Call,
        start: usize,
        out: *mut Value,
        count: usize,
    ) -> moor_status,
    pub programmer: unsafe extern "C" fn(call: Call) -> moor_obj,
    pub step: unsafe extern "C" fn(call: Call) -> u32,
    pub state: unsafe extern "C" fn(call: Call) -> Value,
    pub result: unsafe extern "C" fn(call: Call) -> Value,

    // Ending a step.
    pub ret: unsafe extern "C" fn(call: Call, value: Value) -> moor_status,
    pub call_verb: unsafe extern "C" fn(
        call: Call,
        target: Value,
        verb: Value,
        args: Value,
        step: u32,
        state: Value,
    ) -> moor_status,
    pub call_builtin: unsafe extern "C" fn(
        call: Call,
        name: Value,
        args: Value,
        step: u32,
        state: Value,
    ) -> moor_status,

    // Errors.
    pub raise: unsafe extern "C" fn(
        call: Call,
        code: *const c_char,
        code_len: usize,
        message: *const c_char,
        message_len: usize,
    ) -> moor_status,
    pub raise_value: unsafe extern "C" fn(call: Call, error: Value) -> moor_status,
    pub pending_error: unsafe extern "C" fn(call: Call) -> Value,
    pub clear_error: unsafe extern "C" fn(call: Call),

    // Refs.
    pub retain: unsafe extern "C" fn(call: Call, r: Ref) -> Ref,
    pub release: unsafe extern "C" fn(r: Ref),
    pub local: unsafe extern "C" fn(call: Call, r: Ref) -> Ref,
    pub ref_type: unsafe extern "C" fn(r: Ref) -> i32,

    // Reading values.
    pub get_str: unsafe extern "C" fn(
        call: Call,
        r: Ref,
        ptr: *mut *const c_char,
        len: *mut usize,
    ) -> moor_status,
    pub get_binary: unsafe extern "C" fn(
        call: Call,
        r: Ref,
        ptr: *mut *const u8,
        len: *mut usize,
    ) -> moor_status,
    pub length: unsafe extern "C" fn(call: Call, r: Ref, out: *mut usize) -> moor_status,
    pub list_get:
        unsafe extern "C" fn(call: Call, list: Ref, index: usize, out: *mut Value) -> moor_status,
    pub list_read: unsafe extern "C" fn(
        call: Call,
        list: Ref,
        start: usize,
        out: *mut Value,
        count: usize,
    ) -> moor_status,
    pub list_ints: unsafe extern "C" fn(
        call: Call,
        list: Ref,
        start: usize,
        out: *mut i64,
        count: usize,
    ) -> moor_status,
    pub list_floats: unsafe extern "C" fn(
        call: Call,
        list: Ref,
        start: usize,
        out: *mut f64,
        count: usize,
    ) -> moor_status,
    pub map_get:
        unsafe extern "C" fn(call: Call, map: Ref, key: Value, out: *mut Value) -> moor_status,
    pub map_entry: unsafe extern "C" fn(
        call: Call,
        map: Ref,
        index: usize,
        key: *mut Value,
        value: *mut Value,
    ) -> moor_status,
    pub map_read: unsafe extern "C" fn(
        call: Call,
        map: Ref,
        start: usize,
        keys: *mut Value,
        values: *mut Value,
        count: usize,
    ) -> moor_status,
    pub error_parts: unsafe extern "C" fn(
        call: Call,
        error: Ref,
        code: *mut Value,
        message: *mut Value,
        value: *mut Value,
    ) -> moor_status,
    pub flyweight_parts: unsafe extern "C" fn(
        call: Call,
        flyweight: Ref,
        delegate: *mut moor_obj,
        slots: *mut Value,
        contents: *mut Value,
    ) -> moor_status,
    pub same: unsafe extern "C" fn(a: Value, b: Value) -> bool,
    pub equal: unsafe extern "C" fn(a: Value, b: Value) -> bool,
    pub compare: unsafe extern "C" fn(call: Call, a: Value, b: Value, out: *mut i32) -> moor_status,
    pub to_literal: unsafe extern "C" fn(call: Call, value: Value) -> Value,

    // Making values.
    pub new_str: unsafe extern "C" fn(
        call: Call,
        ptr: *const c_char,
        len: usize,
        out: *mut Value,
    ) -> moor_status,
    pub new_sym: unsafe extern "C" fn(
        call: Call,
        ptr: *const c_char,
        len: usize,
        out: *mut Value,
    ) -> moor_status,
    pub new_binary: unsafe extern "C" fn(call: Call, ptr: *const u8, len: usize) -> Value,
    pub new_list: unsafe extern "C" fn(
        call: Call,
        items: *const Value,
        count: usize,
        out: *mut Value,
    ) -> moor_status,
    pub new_list_ints: unsafe extern "C" fn(call: Call, items: *const i64, count: usize) -> Value,
    pub new_list_floats: unsafe extern "C" fn(call: Call, items: *const f64, count: usize) -> Value,
    pub new_map: unsafe extern "C" fn(
        call: Call,
        keys: *const Value,
        values: *const Value,
        count: usize,
        out: *mut Value,
    ) -> moor_status,
    pub new_error: unsafe extern "C" fn(
        call: Call,
        code: *const c_char,
        code_len: usize,
        message: *const c_char,
        message_len: usize,
        value: Value,
        out: *mut Value,
    ) -> moor_status,
    pub new_flyweight: unsafe extern "C" fn(
        call: Call,
        delegate: moor_obj,
        slots: Value,
        contents: Value,
        out: *mut Value,
    ) -> moor_status,
    pub list_append:
        unsafe extern "C" fn(call: Call, list: Ref, item: Value, out: *mut Value) -> moor_status,
    pub list_set: unsafe extern "C" fn(
        call: Call,
        list: Ref,
        index: usize,
        item: Value,
        out: *mut Value,
    ) -> moor_status,
    pub map_set: unsafe extern "C" fn(
        call: Call,
        map: Ref,
        key: Value,
        value: Value,
        out: *mut Value,
    ) -> moor_status,
    pub map_remove:
        unsafe extern "C" fn(call: Call, map: Ref, key: Value, out: *mut Value) -> moor_status,

    // Objects.
    pub obj_from_number: unsafe extern "C" fn(number: i32) -> moor_obj,
    pub obj_number: unsafe extern "C" fn(obj: moor_obj, out: *mut i32) -> bool,

    // The world.
    pub valid: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut bool) -> moor_status,
    pub parent: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut moor_obj) -> moor_status,
    pub children: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut Value) -> moor_status,
    pub ancestors: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut Value) -> moor_status,
    pub isa: unsafe extern "C" fn(
        call: Call,
        obj: moor_obj,
        ancestor: moor_obj,
        out: *mut bool,
    ) -> moor_status,
    pub location:
        unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut moor_obj) -> moor_status,
    pub contents: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut Value) -> moor_status,
    pub owner: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut moor_obj) -> moor_status,
    pub name: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut Value) -> moor_status,
    pub flags: unsafe extern "C" fn(call: Call, obj: moor_obj, out: *mut u16) -> moor_status,
    pub property: unsafe extern "C" fn(
        call: Call,
        obj: moor_obj,
        name: Value,
        out: *mut Value,
    ) -> moor_status,
    pub set_property:
        unsafe extern "C" fn(call: Call, obj: moor_obj, name: Value, value: Value) -> moor_status,
    pub metadata:
        unsafe extern "C" fn(call: Call, obj: moor_obj, key: Value, out: *mut Value) -> moor_status,
    pub set_metadata:
        unsafe extern "C" fn(call: Call, obj: moor_obj, key: Value, value: Value) -> moor_status,
    pub responds_to:
        unsafe extern "C" fn(call: Call, obj: moor_obj, verb: Value, out: *mut bool) -> moor_status,
}

pub type moor_native_fn = unsafe extern "C" fn(call: Call) -> moor_status;

#[repr(C)]
pub struct moor_function {
    pub name: *const c_char,
    pub call: moor_native_fn,
}

#[repr(C)]
pub struct moor_library {
    pub abi_version: u32,
    pub name: *const c_char,
    pub version: *const c_char,
    pub functions: *const moor_function,
    pub function_count: usize,
}

// A descriptor is immutable static data.
unsafe impl Sync for moor_library {}
unsafe impl Sync for moor_function {}

/// The function every library exports as `moor_native_library`.
pub type moor_entry_fn = unsafe extern "C" fn(api: *const moor_api) -> *const moor_library;

/// The name of that function.
pub const ENTRY_SYMBOL: &str = "moor_native_library";
