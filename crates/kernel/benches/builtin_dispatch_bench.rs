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

//! Builtin dispatch floor benchmarks.

use micromeasure::{
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, Throughput, benchmark_main,
    black_box,
};
use moor_common::{
    model::{
        CommitResult, DispatchFlagsSource, ObjFlag, ObjectKind, TaskPermissions, VerbArgsSpec,
        VerbDispatch, VerbFlag, VerbLookup, WorldState, WorldStateSource,
    },
    tasks::{AbortLimitReason, NoopClientSession, Session},
    util::BitEnum,
};
use moor_compiler::{BuiltinId, CompileOptions, compile, offset_for_builtin};
use moor_db::{DatabaseConfig, TxDB};
use moor_kernel::{
    config::FeaturesConfig,
    tasks::TaskProgramCache,
    testing::vm_test_utils::{
        benchmark_builtin_call_function, benchmark_builtin_direct_function, setup_task_context,
    },
    vm::{VMHostResponse, builtins::BuiltinRegistry, vm_host::VmHost},
};
use moor_var::{List, NOTHING, SYSTEM_OBJECT, Symbol, v_empty_str, v_int, v_obj};
use std::{sync::Arc, time::Duration};

const FULL_MOO_TICKS: usize = 20_000_000;
const DIRECT_BUILTIN_CALLS: usize = 2_000_000;

fn system_permissions() -> TaskPermissions {
    TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
}

fn create_db() -> TxDB {
    let (ws_source, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
    let mut tx = ws_source.new_world_state().unwrap();
    let _sysobj = tx
        .create_object(
            &system_permissions(),
            &NOTHING,
            &SYSTEM_OBJECT,
            ObjFlag::all_flags(),
            ObjectKind::NextObjid,
        )
        .unwrap();
    assert!(matches!(tx.commit(), Ok(CommitResult::Success { .. })));
    ws_source
}

fn prepare_call_verb(
    world_state: &mut dyn WorldState,
    verb_name: &str,
    args: List,
    max_ticks: usize,
) -> VmHost {
    let mut vm_host = VmHost::new(0, 20, max_ticks, Duration::from_secs(1000));

    let verb_name = Symbol::mk(verb_name);
    let verb_result = world_state
        .dispatch_verb(
            &system_permissions(),
            VerbDispatch::new(
                VerbLookup::method(&SYSTEM_OBJECT, verb_name),
                DispatchFlagsSource::Permissions,
            ),
        )
        .unwrap();
    let Some(verb_result) = verb_result else {
        panic!("could not resolve benchmark verb");
    };
    let (program, _) = world_state
        .retrieve_verb(
            &system_permissions(),
            &verb_result.program_key.verb_definer,
            verb_result.program_key.verb_uuid,
        )
        .unwrap();
    let permissions_flags = BitEnum::new_with(ObjFlag::Wizard) | ObjFlag::Programmer;
    vm_host.start_call_method_verb(
        0,
        verb_result.verbdef,
        verb_name,
        v_obj(SYSTEM_OBJECT),
        SYSTEM_OBJECT,
        args,
        v_obj(SYSTEM_OBJECT),
        v_empty_str(),
        permissions_flags,
        program,
    );
    vm_host
}

fn prepare_vm_execution(
    ws_source: &dyn WorldStateSource,
    program: &str,
    max_ticks: usize,
) -> VmHost {
    let program = compile(program, CompileOptions::default()).unwrap();
    let mut tx = ws_source.new_world_state().unwrap();
    tx.add_verb(
        &system_permissions(),
        &SYSTEM_OBJECT,
        vec![Symbol::mk("test")],
        &SYSTEM_OBJECT,
        VerbFlag::rxd(),
        VerbArgsSpec::this_none_this(),
        moor_var::program::ProgramType::MooR(program),
    )
    .unwrap();
    let vm_host = prepare_call_verb(tx.as_mut(), "test", List::mk_list(&[]), max_ticks);
    assert!(matches!(tx.commit(), Ok(CommitResult::Success { .. })));
    vm_host
}

fn execute_until_ticks(
    session: Arc<dyn Session>,
    vm_host: &mut VmHost,
    builtins: &BuiltinRegistry,
    features: &FeaturesConfig,
) -> usize {
    vm_host.reset_ticks();
    vm_host.reset_time();

    let mut program_cache = TaskProgramCache::default();

    loop {
        match vm_host.exec_interpreter(0, session.as_ref(), builtins, features, &mut program_cache)
        {
            VMHostResponse::ContinueOk => continue,
            VMHostResponse::AbortLimit(AbortLimitReason::Ticks(t)) => return t,
            _ => panic!("unexpected VM response"),
        }
    }
}

struct BuiltinDispatchContext {
    db: TxDB,
    vm_host: VmHost,
    builtins: BuiltinRegistry,
    session: Arc<dyn Session>,
    features: FeaturesConfig,
    builtin: BuiltinId,
    args: List,
}

impl BuiltinDispatchContext {
    fn with_program(program: &str, max_ticks: usize) -> Self {
        let db = create_db();
        let vm_host = prepare_vm_execution(&db, program, max_ticks);
        let builtins = BuiltinRegistry::new();
        let session = Arc::new(NoopClientSession::new());
        let features = FeaturesConfig::default();
        let builtin = BuiltinId(offset_for_builtin("typeof") as u16);
        let args = List::mk_list(&[v_int(1)]);

        Self {
            db,
            vm_host,
            builtins,
            session,
            features,
            builtin,
            args,
        }
    }
}

impl BenchContext for BuiltinDispatchContext {
    fn prepare(_num_chunks: usize) -> Self {
        Self::with_program("while (1) 1; endwhile", FULL_MOO_TICKS)
    }

    fn chunk_size() -> Option<usize> {
        Some(1)
    }
}

fn builtin_full_moo_typeof(
    ctx: &mut BuiltinDispatchContext,
    _chunk_size: usize,
    _chunk_num: usize,
) {
    let tx = ctx.db.new_world_state().unwrap();
    let _tx_guard = setup_task_context(tx);
    let ticks = execute_until_ticks(
        ctx.session.clone(),
        &mut ctx.vm_host,
        &ctx.builtins,
        &ctx.features,
    );
    black_box(ticks);
}

fn builtin_current_call_function_typeof(
    ctx: &mut BuiltinDispatchContext,
    _chunk_size: usize,
    _chunk_num: usize,
) {
    let tx = ctx.db.new_world_state().unwrap();
    let _tx_guard = setup_task_context(tx);
    let calls = benchmark_builtin_call_function(
        &mut ctx.vm_host,
        &ctx.builtins,
        &ctx.features,
        ctx.session.as_ref(),
        ctx.builtin,
        &ctx.args,
        DIRECT_BUILTIN_CALLS,
    );
    black_box(calls);
}

fn builtin_direct_function_typeof(
    ctx: &mut BuiltinDispatchContext,
    _chunk_size: usize,
    _chunk_num: usize,
) {
    let tx = ctx.db.new_world_state().unwrap();
    let _tx_guard = setup_task_context(tx);
    let calls = benchmark_builtin_direct_function(
        &mut ctx.vm_host,
        &ctx.builtins,
        &ctx.features,
        ctx.builtin,
        &ctx.args,
        DIRECT_BUILTIN_CALLS,
    );
    black_box(calls);
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some("all, full_moo, current_call, direct_function, or typeof".to_string()),
        runtime: BenchmarkRuntimeOptions {
            warm_up_duration: Duration::from_millis(250),
            benchmark_duration: Duration::from_secs(1),
            min_samples: 8,
            max_samples: 24,
        },
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        runner.group::<BuiltinDispatchContext>("builtin_dispatch", |g| {
            g.throughput(Throughput::per_operation(FULL_MOO_TICKS as u64, "opcodes"))
                .factory(&|| {
                    BuiltinDispatchContext::with_program(
                        "while (1) typeof(1); endwhile",
                        FULL_MOO_TICKS,
                    )
                })
                .bench("builtin_full_moo_typeof", builtin_full_moo_typeof);

            g.throughput(Throughput::per_operation(
                DIRECT_BUILTIN_CALLS as u64,
                "builtin_calls",
            ))
            .factory(&|| {
                BuiltinDispatchContext::with_program("while (1) 1; endwhile", FULL_MOO_TICKS)
            })
            .bench(
                "builtin_current_call_function_typeof",
                builtin_current_call_function_typeof,
            );

            g.throughput(Throughput::per_operation(
                DIRECT_BUILTIN_CALLS as u64,
                "builtin_calls",
            ))
            .factory(&|| {
                BuiltinDispatchContext::with_program("while (1) 1; endwhile", FULL_MOO_TICKS)
            })
            .bench(
                "builtin_direct_function_typeof",
                builtin_direct_function_typeof,
            );
        });
    }
);
