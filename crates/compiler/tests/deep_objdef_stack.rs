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

use moor_compiler::{CompileOptions, ObjDefParseError, ObjFileContext, compile_object_definitions};
use std::process::Command;

const CHILD_ENV: &str = "MOOR_DEEP_OBJDEF_STACK_CHILD";
const ESCAPED_STRING_CHILD_ENV: &str = "MOOR_ESCAPED_STRING_CHILD";
const MAP_DEPTH: usize = 256;
const ESCAPE_COUNT: usize = 4_096;
const TASK_STACK_BYTES: usize = 2 * 1024 * 1024;

fn nested_map_objdef(depth: usize) -> String {
    let mut literal = String::with_capacity(depth * 8 + 6);
    for _ in 0..depth {
        literal.push_str("[0 -> ");
    }
    literal.push_str("\"leaf\"");
    for _ in 0..depth {
        literal.push(']');
    }

    format!(
        "object #340\n\
         name: \"Nested map\"\n\
         parent: #-1\n\
         owner: #0\n\
         location: #-1\n\
         readable: true\n\
         property history (owner: #0, flags: \"r\") = {literal};\n\
         endobject\n"
    )
}

fn escaped_string_objdef(escape_count: usize) -> String {
    let value = "\\n".repeat(escape_count);
    format!(
        r#"object #340
 name: "Deep literal regression"
 parent: #1
 owner: #0
 location: #0
 readable: true
 writeable: false
 property history (owner: #0, flags: "r") = "{value}";
endobject"#,
    )
}

#[test]
#[ignore = "diagnostic for native stack exhaustion in the objdef parser"]
fn deeply_nested_map_objdef_does_not_abort() {
    if std::env::var_os(CHILD_ENV).is_some() {
        let source = nested_map_objdef(MAP_DEPTH);
        let mut context = ObjFileContext::new();
        let error =
            match compile_object_definitions(&source, &CompileOptions::default(), &mut context) {
                Ok(_) => panic!("nested map objdef should be rejected before parsing"),
                Err(error) => error,
            };
        assert!(matches!(
            error,
            ObjDefParseError::LiteralNestingTooDeep { max_depth: 64 }
        ));
        return;
    }

    let output = Command::new(std::env::current_exe().expect("test executable should exist"))
        .args([
            "--exact",
            "deeply_nested_map_objdef_does_not_abort",
            "--ignored",
            "--nocapture",
        ])
        .env(CHILD_ENV, "1")
        .env("RUST_MIN_STACK", TASK_STACK_BYTES.to_string())
        .output()
        .expect("child parser process should start");

    assert!(
        output.status.success(),
        "objdef parser child failed with {}\nstdout:\n{}\nstderr:\n{}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );
}

#[test]
#[ignore = "diagnostic for native stack exhaustion in the objdef string grammar"]
fn escaped_string_objdef_does_not_abort() {
    if std::env::var_os(ESCAPED_STRING_CHILD_ENV).is_some() {
        let source = escaped_string_objdef(ESCAPE_COUNT);
        let mut context = ObjFileContext::new();
        compile_object_definitions(&source, &CompileOptions::default(), &mut context)
            .expect("objdef with escaped string should compile");
        return;
    }

    let output = Command::new(std::env::current_exe().expect("test executable should exist"))
        .arg("--exact")
        .arg("escaped_string_objdef_does_not_abort")
        .arg("--ignored")
        .arg("--nocapture")
        .env(ESCAPED_STRING_CHILD_ENV, "1")
        .env("RUST_MIN_STACK", TASK_STACK_BYTES.to_string())
        .output()
        .expect("child test process should start");

    assert!(
        output.status.success(),
        "objdef parser child failed with {status}\nchild stdout:\n{stdout}\nchild stderr:\n{stderr}",
        status = output.status,
        stdout = String::from_utf8_lossy(&output.stdout),
        stderr = String::from_utf8_lossy(&output.stderr),
    );
}
