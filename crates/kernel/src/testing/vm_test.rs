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

//! Low-level VM tests using raw opcodes.
//! These tests exercise the bytecode interpreter directly without going through the compiler.

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use triomphe::Arc as TArc;

    use moor_common::{
        model::{
            ObjFlag, ObjectKind, PropFlag, TaskPermissions, VerbArgsSpec, VerbFlag,
            WorldStateSource,
        },
        util::BitEnum,
    };
    use moor_var::{List, Symbol, Var, v_bool, v_int, v_list, v_objid, v_str};

    use moor_var::{NOTHING, SYSTEM_OBJECT, *};

    use crate::{testing::vm_test_utils::call_verb, vm::builtins::BuiltinRegistry};
    use moor_common::tasks::NoopClientSession;
    use moor_compiler::{Names, Op, Op::*, Program};
    use moor_db::{DatabaseConfig, TxDB};
    use moor_var::program::{ProgramType, program::PrgInner};

    fn system_permissions() -> TaskPermissions {
        TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
    }

    fn mk_program(main_vector: Vec<Op>, literals: Vec<Var>, var_names: Names) -> Program {
        Program(TArc::new(PrgInner {
            literal_catches: Default::default(),
            lambda_entry_scope_count: 0,
            literals,
            jump_labels: vec![],
            var_names,
            scatter_tables: vec![],
            for_sequence_operands: vec![],
            for_range_operands: vec![],
            range_comprehensions: vec![],
            list_comprehensions: vec![],
            error_operands: vec![],
            lambda_programs: vec![],
            main_vector,
            main_max_stack: 0,
            main_max_scope_depth: 0,
            fork_vectors: vec![],
            fork_max_stacks: vec![],
            fork_max_scope_depths: vec![],
            line_number_spans: vec![],
            fork_line_number_spans: vec![],
            source_declarations: None,
        }))
    }

    #[test]
    fn static_catch_preserves_each_tick_slice_boundary() {
        use crate::vm::kernel_host::KernelHost;
        use moor_vm::{
            ExecutionResult, FeaturesConfig, FrameExecutionContext, MooStackFrame,
            moo_frame_execute,
        };
        let this = v_obj(SYSTEM_OBJECT);
        let context = FrameExecutionContext::new(
            system_permissions(),
            SYSTEM_OBJECT,
            &this,
            Symbol::mk("test"),
            SYSTEM_OBJECT,
        );
        let features = FeaturesConfig::default();
        // `scope_tick` is the tick of the instruction that opens the guard, after its setup.
        for (source, scope_tick, total_ticks) in [
            ("return `123 ! E_DIV, E_PERM => 0';", 6, 9),
            ("return `123 ! ANY => 0';", 3, 6),
        ] {
            let program = moor_compiler::compile(source, Default::default()).unwrap();
            for slice in 1..=scope_tick {
                let mut frame = MooStackFrame::new(program.clone());
                let mut ticks = 0;
                assert!(matches!(
                    moo_frame_execute(
                        &mut KernelHost,
                        slice,
                        &mut ticks,
                        &context,
                        &mut frame,
                        &features
                    ),
                    ExecutionResult::More
                ));
                assert_eq!((ticks, usize::from(frame.pc)), (slice, slice));
                if slice == scope_tick {
                    assert!(frame.scratch.is_none());
                    assert!(frame.scope_payloads.is_empty());
                }
                assert!(matches!(
                    moo_frame_execute(&mut KernelHost, 20, &mut ticks, &context, &mut frame, &features),
                    ExecutionResult::Return(v) if v == v_int(123)
                ));
                assert_eq!(ticks, total_ticks);
            }
        }
    }

    fn test_db_with_verbs(verbs: &[(&str, &Program)]) -> TxDB {
        let (state, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let mut tx = state.new_world_state().unwrap();
        let sysobj = tx
            .create_object(
                &system_permissions(),
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("name"),
            &v_str("system"),
        )
        .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("programmer"),
            &v_int(1),
        )
        .unwrap();
        tx.update_property(
            &system_permissions(),
            &sysobj,
            Symbol::mk("wizard"),
            &v_int(1),
        )
        .unwrap();

        tx.define_property(
            &system_permissions(),
            &sysobj,
            &sysobj,
            Symbol::mk("test"),
            &SYSTEM_OBJECT,
            PropFlag::all_flags(),
            Some(v_int(1)),
        )
        .unwrap();

        for (verb_name, program) in verbs {
            tx.add_verb(
                &system_permissions(),
                &sysobj.clone(),
                vec![Symbol::mk(verb_name)],
                &sysobj.clone(),
                VerbFlag::rxd(),
                VerbArgsSpec::this_none_this(),
                ProgramType::MooR((*program).clone()),
            )
            .unwrap();
        }
        tx.commit().unwrap();
        state
    }

    fn test_db_with_verb(verb_name: &str, program: &Program) -> TxDB {
        test_db_with_verbs(&[(verb_name, program)])
    }

    #[test]
    fn declaration_metadata_survives_storage_source_and_execution() {
        use moor_compiler::{CompileOptions, compile, program_to_tree, unparse};
        use moor_schema::convert_program::{program_to_stored, stored_to_program};

        let cases = [
            (
                "let value = (value = 1); value = value + 1; return value;",
                2,
            ),
            (
                "let value = 1; begin const value = 2; value; end return value;",
                1,
            ),
            (
                "const {first, ?second = 2, @rest} = {3}; return first + second;",
                5,
            ),
            ("let value; value = 4; return value;", 4),
            (
                "const captured = 7; fn get() const {local} = {captured}; return local; endfn return get();",
                7,
            ),
        ];
        for (source, expected) in cases {
            let program = compile(source, CompileOptions::default()).unwrap();
            let restored = stored_to_program(&program_to_stored(&program).unwrap()).unwrap();
            assert_eq!(restored, program);
            let text = unparse(&program_to_tree(&restored).unwrap(), false, true)
                .unwrap()
                .join("\n");
            let recompiled = compile(&text, CompileOptions::default()).unwrap();
            assert_eq!(program.main_vector(), recompiled.main_vector());
            for program in [&restored, &recompiled] {
                let db = test_db_with_verb("test", program);
                let result = call_verb(
                    db.new_world_state().unwrap(),
                    Arc::new(NoopClientSession::new()),
                    BuiltinRegistry::new(),
                    "test",
                    List::mk_list(&[]),
                );
                assert_eq!(result, Ok(v_int(expected)), "{source}");
            }
        }
    }

    #[test]
    fn test_simple_vm_execute() {
        let program = mk_program(
            vec![Imm(0.into()), Pop, Done],
            vec![1.into()],
            Names::new(64),
        );
        let state_source = test_db_with_verb("test", &program);
        let state = state_source.new_world_state().unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );
        assert_eq!(result, Ok(v_bool(false)));
    }

    #[test]
    fn test_string_value_simple_indexing() {
        let state_source = test_db_with_verb(
            "test",
            &mk_program(
                vec![Imm(0.into()), Imm(1.into()), Ref, Return, Done],
                vec![v_str("hello"), 2.into()],
                Names::new(64),
            ),
        );
        let state = state_source.new_world_state().unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );

        assert_eq!(result, Ok(v_str("e")));
    }

    #[test]
    fn test_string_value_range_indexing() {
        let state = test_db_with_verb(
            "test",
            &mk_program(
                vec![
                    Imm(0.into()),
                    Imm(1.into()),
                    Imm(2.into()),
                    RangeRef,
                    Return,
                    Done,
                ],
                vec![v_str("hello"), 2.into(), 4.into()],
                Names::new(64),
            ),
        )
        .new_world_state()
        .unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );

        assert_eq!(result, Ok(v_str("ell")));
    }

    #[test]
    fn test_list_value_simple_indexing() {
        let state = test_db_with_verb(
            "test",
            &mk_program(
                vec![Imm(0.into()), Imm(1.into()), Ref, Return, Done],
                vec![v_list(&[111.into(), 222.into(), 333.into()]), 2.into()],
                Names::new(64),
            ),
        )
        .new_world_state()
        .unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );

        assert_eq!(result, Ok(v_int(222)));
    }

    #[test]
    fn test_list_value_range_indexing() {
        let state = test_db_with_verb(
            "test",
            &mk_program(
                vec![
                    Imm(0.into()),
                    Imm(1.into()),
                    Imm(2.into()),
                    RangeRef,
                    Return,
                    Done,
                ],
                vec![
                    v_list(&[111.into(), 222.into(), 333.into()]),
                    2.into(),
                    3.into(),
                ],
                Names::new(64),
            ),
        )
        .new_world_state()
        .unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );
        assert_eq!(result, Ok(v_list(&[222.into(), 333.into()])));
    }

    #[test]
    fn test_property_retrieval() {
        let mut state = test_db_with_verb(
            "test",
            &mk_program(
                vec![Imm(0.into()), Imm(1.into()), GetProp, Return, Done],
                vec![v_objid(0), v_str("test_prop")],
                Names::new(64),
            ),
        )
        .new_world_state()
        .unwrap();
        {
            state
                .define_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    Symbol::mk("test_prop"),
                    &SYSTEM_OBJECT,
                    BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
                    Some(v_int(666)),
                )
                .unwrap();
        }
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test",
            List::mk_list(&[]),
        );
        assert_eq!(result, Ok(v_int(666)));
    }

    #[test]
    fn test_call_verb() {
        // Prepare two, chained, test verbs in our environment, with simple operations.

        // The first merely returns the value "666" immediately.
        let return_verb_binary = mk_program(
            vec![Imm(0.into()), Return, Done],
            vec![v_int(666)],
            Names::new(64),
        );

        // The second actually calls the first verb, and returns the result.
        let call_verb_binary = mk_program(
            vec![
                Imm(0.into()), /* obj */
                Imm(1.into()), /* verb */
                Imm(2.into()), /* args */
                CallVerb,
                Return,
                Done,
            ],
            vec![v_objid(0), v_str("test_return_verb"), v_empty_list()],
            Names::new(64),
        );
        let state = test_db_with_verbs(&[
            ("test_return_verb", &return_verb_binary),
            ("test_call_verb", &call_verb_binary),
        ])
        .new_world_state()
        .unwrap();
        let session = Arc::new(NoopClientSession::new());
        let result = call_verb(
            state,
            session,
            BuiltinRegistry::new(),
            "test_call_verb",
            List::mk_list(&[]),
        );

        assert_eq!(result, Ok(v_int(666)));
    }

    #[test]
    fn guard_without_default_yields_code_of_error_from_called_verb() {
        let compile = |source| moor_compiler::compile(source, Default::default()).unwrap();
        let callee = compile("return 1 / 0;");
        let caller = compile(
            r#"
            a = `#0:callee() ! E_DIV';
            b = `raise(E_PERM, "message", 5) ! ANY';
            c = `#0:callee() ! E_DIV => 7';
            return {a, b, c, `8 ! ANY'};
            "#,
        );
        let state = test_db_with_verbs(&[("callee", &callee), ("caller", &caller)])
            .new_world_state()
            .unwrap();
        let result = call_verb(
            state,
            Arc::new(NoopClientSession::new()),
            BuiltinRegistry::new(),
            "caller",
            List::mk_list(&[]),
        );
        assert_eq!(
            result,
            Ok(v_list(&[v_err(E_DIV), v_err(E_PERM), v_int(7), v_int(8)]))
        );
    }
}
