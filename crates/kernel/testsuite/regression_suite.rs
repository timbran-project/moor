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

use crate::common::{compile_verbs, create_db};
use moor_common::model::{CommitResult, TaskPermissions, VerbAttrs};
use moor_common::tasks::NoopClientSession;
use moor_common::util::BitEnum;
use moor_compiler::{CompileOptions, compile};
use moor_db::Database;
use moor_kernel::{testing::vm_test_utils, vm::builtins::BuiltinRegistry};
use moor_var::{List, Obj, SYSTEM_OBJECT, Symbol, program::ProgramType};
use std::sync::Arc;

mod common;

fn call_redefined(db: &dyn Database) -> vm_test_utils::ExecResult {
    vm_test_utils::call_verb(
        db.new_world_state().unwrap(),
        Arc::new(NoopClientSession::new()),
        BuiltinRegistry::new(),
        "redefinition_fixture",
        List::mk_list(&[]),
    )
}

#[test]
fn test_verb_redefinition_uses_updated_program() {
    let db = create_db();
    let original = compile("return 42;", CompileOptions::default()).unwrap();
    compile_verbs(db.as_ref(), &[("redefinition_fixture", &original)]);
    assert_eq!(call_redefined(db.as_ref()), Ok(42.into()));

    let mut tx = db.new_world_state().unwrap();
    let permissions = TaskPermissions::new(Obj::mk_id(3), BitEnum::new());
    let name = Symbol::mk("redefinition_fixture");
    let replacement = compile("return 200;", CompileOptions::default()).unwrap();
    tx.update_verb(
        &permissions,
        &SYSTEM_OBJECT,
        name,
        VerbAttrs {
            definer: None,
            owner: None,
            names: None,
            flags: None,
            args_spec: None,
            program: Some(ProgramType::MooR(replacement)),
        },
    )
    .unwrap();
    assert!(matches!(tx.commit(), Ok(CommitResult::Success { .. })));
    assert_eq!(call_redefined(db.as_ref()), Ok(200.into()));
}
