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

//! The C header and the Rust definitions in `ffi` must agree: compile, against the header,
//! static assertions of every size, field offset and constant as Rust sees them.

use moor_native_verb::ffi::{self, moor_api, moor_function, moor_library, moor_value};
use std::{fmt::Write, mem::offset_of, path::PathBuf, process::Command};

macro_rules! offsets {
    ($ty:ident: $($field:ident),* $(,)?) => {
        vec![$((stringify!($ty), stringify!($field), offset_of!($ty, $field))),*]
    };
}

#[test]
fn the_header_matches_the_rust_definitions() {
    let mut fields = offsets!(moor_api:
        abi_version, size, this_value, player, caller, verb, args, arg_count, arg, args_read,
        programmer, step, state, result, ret, call_verb, call_builtin, raise, raise_value,
        pending_error, clear_error, retain, release, local, ref_type, get_str, get_binary, length,
        list_get, list_read, list_ints, list_floats, map_get, map_entry, map_read, error_parts,
        flyweight_parts, same, equal, compare, to_literal, new_str, new_sym, new_binary,
        new_list, new_list_ints, new_list_floats, new_map, new_error, new_flyweight,
        list_append, list_set, map_set, map_remove, obj_from_number, obj_number, valid, parent,
        children, ancestors, isa, location, contents, owner, name, flags, property,
        set_property, metadata, set_metadata, responds_to,
    );
    fields.extend(offsets!(moor_function: name, call));
    fields.extend(
        offsets!(moor_value: type_, as_)
            .into_iter()
            .map(|(ty, field, offset)| {
                // The C fields are `type` and `as`, keywords in Rust.
                (ty, field.trim_end_matches('_'), offset)
            }),
    );
    fields.extend(offsets!(moor_library: abi_version, name, version, functions, function_count));

    let mut source = String::from("#include <stddef.h>\n#include \"moor_native.h\"\n");
    for (ty, size) in [
        ("moor_api", size_of::<moor_api>()),
        ("moor_function", size_of::<moor_function>()),
        ("moor_library", size_of::<moor_library>()),
        ("moor_obj", size_of::<ffi::moor_obj>()),
        ("moor_value", size_of::<ffi::moor_value>()),
        ("moor_status", size_of::<ffi::moor_status>()),
    ] {
        writeln!(
            source,
            "_Static_assert(sizeof({ty}) == {size}, \"size of {ty}\");"
        )
        .unwrap();
    }
    for (ty, field, offset) in fields {
        writeln!(
            source,
            "_Static_assert(offsetof({ty}, {field}) == {offset}, \"{ty}.{field}\");"
        )
        .unwrap();
    }
    for (name, value) in [
        ("MOOR_NATIVE_ABI", i64::from(ffi::MOOR_NATIVE_ABI)),
        ("MOOR_OK", i64::from(ffi::MOOR_OK)),
        ("MOOR_ERROR", i64::from(ffi::MOOR_ERROR)),
        ("MOOR_CONFLICT", i64::from(ffi::MOOR_CONFLICT)),
        ("MOOR_TYPE_INT", i64::from(ffi::MOOR_TYPE_INT)),
        ("MOOR_TYPE_OBJ", i64::from(ffi::MOOR_TYPE_OBJ)),
        ("MOOR_TYPE_STR", i64::from(ffi::MOOR_TYPE_STR)),
        ("MOOR_TYPE_ERR", i64::from(ffi::MOOR_TYPE_ERR)),
        ("MOOR_TYPE_LIST", i64::from(ffi::MOOR_TYPE_LIST)),
        ("MOOR_TYPE_NONE", i64::from(ffi::MOOR_TYPE_NONE)),
        ("MOOR_TYPE_FLOAT", i64::from(ffi::MOOR_TYPE_FLOAT)),
        ("MOOR_TYPE_MAP", i64::from(ffi::MOOR_TYPE_MAP)),
        ("MOOR_TYPE_BOOL", i64::from(ffi::MOOR_TYPE_BOOL)),
        ("MOOR_TYPE_FLYWEIGHT", i64::from(ffi::MOOR_TYPE_FLYWEIGHT)),
        ("MOOR_TYPE_SYMBOL", i64::from(ffi::MOOR_TYPE_SYMBOL)),
        ("MOOR_TYPE_BINARY", i64::from(ffi::MOOR_TYPE_BINARY)),
        ("MOOR_TYPE_LAMBDA", i64::from(ffi::MOOR_TYPE_LAMBDA)),
        ("MOOR_FLAG_USER", i64::from(ffi::MOOR_FLAG_USER)),
        ("MOOR_FLAG_PROGRAMMER", i64::from(ffi::MOOR_FLAG_PROGRAMMER)),
        ("MOOR_FLAG_WIZARD", i64::from(ffi::MOOR_FLAG_WIZARD)),
        ("MOOR_FLAG_READ", i64::from(ffi::MOOR_FLAG_READ)),
        ("MOOR_FLAG_WRITE", i64::from(ffi::MOOR_FLAG_WRITE)),
        ("MOOR_FLAG_FERTILE", i64::from(ffi::MOOR_FLAG_FERTILE)),
    ] {
        writeln!(source, "_Static_assert({name} == {value}, \"{name}\");").unwrap();
    }

    let crate_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let out = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let check = out.join("moor_native_check.c");
    std::fs::write(&check, source).unwrap();
    let compiler = std::env::var("CC").unwrap_or_else(|_| "cc".to_string());
    for file in [check, crate_dir.join("tests/c/sum.c")] {
        let output = Command::new(&compiler)
            .args([
                "-std=c11",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-fsyntax-only",
                "-I",
            ])
            .arg(crate_dir.join("include"))
            .arg(&file)
            .output()
            .unwrap_or_else(|e| panic!("Unable to run the C compiler {compiler}: {e}"));
        assert!(
            output.status.success(),
            "{} does not compile against the header:\n{}",
            file.display(),
            String::from_utf8_lossy(&output.stderr)
        );
    }
}
