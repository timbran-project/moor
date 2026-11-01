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

//! Native verbs called from MOO code and run as a task's first verb, through a library linked
//! into the test binary. Linking skips only `dlopen`; the descriptor, the function table and
//! the calls are the same.

#[cfg(test)]
mod tests {
    use std::{
        path::Path,
        sync::{Arc, Mutex},
    };

    use moor_common::{
        model::{
            ObjFlag, ObjectKind, PropFlag, TaskPermissions, VerbArgsSpec, VerbFlag,
            WorldStateSource,
        },
        tasks::{AbortLimitReason, NoopClientSession},
        util::BitEnum,
    };
    use moor_compiler::{CompileOptions, compile};
    use moor_db::{DatabaseConfig, TxDB};
    use moor_native_verb::{Call, Done, Obj as NativeObj, Result, Retained, Value};
    use moor_var::{
        E_RANGE, List, NOTHING, SYSTEM_OBJECT, Symbol, Var,
        program::{NativeProgram, ProgramType},
        v_bool, v_float, v_int, v_list, v_list_iter, v_obj, v_str,
    };

    use crate::{
        native_verbs::NativeVerbs,
        testing::vm_test_utils::{call_verb, call_verb_within_limits},
        vm::builtins::BuiltinRegistry,
    };

    fn sum(call: &Call) -> Result<Done> {
        let mut total = 0;
        for arg in call.arg_values()? {
            total += arg
                .as_int()
                .ok_or_else(|| call.raise("E_RANGE", "sum adds integers"))?;
        }
        Ok(call.ret(total))
    }

    /// Read a list of integers and a mixed list in bulk, and build lists the same ways.
    fn bulk(call: &Call) -> Result<Done> {
        let numbers = call.arg(0)?.list(call)?;
        let mixed = call.arg(1)?.list(call)?;
        let entries = call.arg(2)?.map(call)?.entries()?;
        let flipped: Vec<Value> = entries.iter().map(|(k, v)| call.list(&[*v, *k])).collect();
        let doubled: Vec<i64> = numbers.ints()?.iter().map(|n| n * 2).collect();
        let mut middle = [0; 2];
        numbers.read_ints(1, &mut middle)?;
        let halves: Vec<f64> = numbers.floats()?.iter().map(|n| n / 2.0).collect();
        let items = mixed.items()?;
        let kinds: Vec<Value> = items
            .iter()
            .map(|item| {
                call.str(match item {
                    Value::Int(_) => "int",
                    Value::Float(_) => "float",
                    Value::Bool(_) => "bool",
                    Value::Obj(_) => "obj",
                    Value::Ref(_) => "ref",
                })
            })
            .collect();
        let refused = match mixed.ints() {
            Ok(_) => call.str("accepted"),
            Err(_) => {
                let error = call.pending_error().expect("a pending error");
                let code = error.reference(call)?.error_parts()?.0;
                call.clear_error();
                code
            }
        };
        Ok(call.ret(call.list(&[
            call.list_ints(&doubled),
            call.list_ints(&middle),
            call.list_floats(&halves),
            call.list(&items),
            call.list(&kinds),
            refused,
            call.list(&flipped),
        ])))
    }

    fn describe(call: &Call) -> Result<Done> {
        Ok(call.ret(call.list(&[call.this(), call.verb().into(), call.args().into()])))
    }

    /// Call `this:double(n)`, then return what it gave with the `n` carried across.
    fn twice(call: &Call) -> Result<Done> {
        match call.step() {
            0 => {
                let n = call.arg(0)?;
                let args = call.list(&[n]);
                call.call_verb(call.this(), call.sym("double"), args, 1, Some(n))
            }
            1 => {
                let carried = call.state().expect("the state carried to step 1");
                let result = call.result().expect("the result of double");
                Ok(call.ret(call.list(&[carried, result])))
            }
            other => Err(call.raise("E_INVARG", &format!("no step {other}"))),
        }
    }

    /// Call `length()` on the argument list, through the builtin.
    fn count(call: &Call) -> Result<Done> {
        match call.step() {
            0 => {
                let args = call.list(&[call.args().into()]);
                call.call_builtin(call.sym("length"), args, 1, None)
            }
            _ => Ok(call.ret(call.result().expect("length's result"))),
        }
    }

    /// Call `this:(name)()` and give back whatever it returned, error values included.
    fn relay(call: &Call) -> Result<Done> {
        match call.step() {
            0 => {
                let verb = call.arg(0)?;
                call.call_verb(call.this(), verb, call.list(&[]), 1, None)
            }
            _ => Ok(call.ret(call.result().expect("the relayed result"))),
        }
    }

    /// Count #0.counter up by one, and report #0's name, parent and validity and a metadata
    /// round trip.
    fn world(call: &Call) -> Result<Done> {
        let system = NativeObj::number(0);
        let counter = call.sym("counter");
        let next = call.property(system, counter)?.int(call)? + 1;
        call.set_property(system, counter, next.into())?;
        let key = call.sym("native_mark");
        call.set_metadata(system, key, call.str("marked"))?;
        let mark = call.metadata(system, key)?.expect("the metadata just set");
        Ok(call.ret(call.list(&[
            next.into(),
            call.parent(system)?.into(),
            call.valid(system)?.into(),
            call.valid(NativeObj::number(9999))?.into(),
            mark,
            call.responds_to(system, call.sym("native_world"))?.into(),
        ])))
    }

    static KEPT: Mutex<Option<Retained>> = Mutex::new(None);

    /// Whether the argument is the very value passed last time.
    fn unchanged(call: &Call) -> Result<Done> {
        let arg = call.arg(0)?.list(call)?;
        let mut kept = KEPT.lock().unwrap();
        let same = kept.as_ref().is_some_and(|k| k.get(call).same(arg));
        *kept = Some(arg.retain());
        Ok(call.ret(same))
    }

    /// Retain the argument, take a ref to it from the retained handle, drop the handle, and
    /// return what the ref holds: a ref from a retained handle lasts the call.
    fn outlive(call: &Call) -> Result<Done> {
        let retained = call.arg(0)?.list(call)?.retain();
        let kept = retained.get(call);
        drop(retained);
        Ok(call.ret(kept.append(call.str("kept"))?))
    }

    /// Read a missing property, and fail with that error.
    fn missing(call: &Call) -> Result<Done> {
        let found = call.property(NativeObj::number(0), call.sym("no_such_property"))?;
        Ok(call.ret(found))
    }

    /// Make twelve world requests, then return.
    fn busy(call: &Call) -> Result<Done> {
        for _ in 0..12 {
            call.valid(NativeObj::number(0))?;
        }
        Ok(call.ret(42))
    }

    /// Make twelve world requests, then ask to suspend.
    fn busy_then_suspend(call: &Call) -> Result<Done> {
        if call.step() == 0 {
            for _ in 0..12 {
                call.valid(NativeObj::number(0))?;
            }
            return call.call_builtin(call.sym("suspend"), call.list(&[0.into()]), 1, None);
        }
        Ok(call.ret(42))
    }

    fn slow(call: &Call) -> Result<Done> {
        std::thread::sleep(std::time::Duration::from_millis(50));
        Ok(call.ret(42))
    }

    /// Suspend, then call `this:(name)()` and give back what it returned.
    fn suspend_then_relay(call: &Call) -> Result<Done> {
        match call.step() {
            0 => call.call_builtin(call.sym("suspend"), call.list(&[0.into()]), 1, None),
            1 => {
                let verb = call.arg(0)?;
                call.call_verb(call.this(), verb, call.list(&[]), 2, None)
            }
            _ => Ok(call.ret(call.result().expect("the relayed result"))),
        }
    }

    static CONFLICTS_LEFT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

    /// Call `this:double(20)`, then count #0.counter up, and report a conflict while
    /// CONFLICTS_LEFT is above zero, counting it down.
    fn conflicted(call: &Call) -> Result<Done> {
        use std::sync::atomic::Ordering;
        if call.step() == 0 {
            let args = call.list(&[20.into()]);
            return call.call_verb(call.this(), call.sym("double"), args, 1, None);
        }
        let system = NativeObj::number(0);
        let counter = call.sym("counter");
        let next = call.property(system, counter)?.int(call)? + 1;
        call.set_property(system, counter, next.into())?;
        if CONFLICTS_LEFT
            .try_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            .is_ok()
        {
            return Err(moor_native_verb::Stop::Conflict);
        }
        Ok(call.ret(call.list(&[call.result().expect("double's result"), next.into()])))
    }

    fn explode(_call: &Call) -> Result<Done> {
        panic!("boom")
    }

    moor_native_verb::native_verb_library! {
        name: "test_natives",
        version: "1.0",
        functions: {
            "sum" => sum,
            "bulk" => bulk,
            "describe" => describe,
            "twice" => twice,
            "count" => count,
            "relay" => relay,
            "world" => world,
            "unchanged" => unchanged,
            "outlive" => outlive,
            "busy" => busy,
            "conflicted" => conflicted,
            "busy_then_suspend" => busy_then_suspend,
            "slow" => slow,
            "suspend_then_relay" => suspend_then_relay,
            "missing" => missing,
            "explode" => explode,
        },
    }

    fn native_verbs() -> BuiltinRegistry {
        let mut native_verbs = NativeVerbs::default();
        // SAFETY: the linked library's descriptor is static.
        unsafe { native_verbs.add_linked(moor_native_library, Path::new("linked")) }.unwrap();
        BuiltinRegistry::with_native_verbs(Arc::new(native_verbs))
    }

    fn native(function: &str) -> ProgramType {
        ProgramType::Native(NativeProgram {
            library: Symbol::mk("test_natives"),
            function: Symbol::mk(function),
        })
    }

    fn moo(code: &str) -> ProgramType {
        ProgramType::MooR(compile(code, CompileOptions::default()).unwrap())
    }

    fn world_with(verbs: Vec<(&str, ProgramType)>) -> TxDB {
        let permissions = TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new());
        let (state, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let mut tx = state.new_world_state().unwrap();
        let sysobj = tx
            .create_object(
                &permissions,
                &NOTHING,
                &SYSTEM_OBJECT,
                ObjFlag::all_flags(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        tx.define_property(
            &permissions,
            &sysobj,
            &sysobj,
            Symbol::mk("counter"),
            &sysobj,
            BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
            Some(v_int(41)),
        )
        .unwrap();
        tx.define_property(
            &permissions,
            &sysobj,
            &sysobj,
            Symbol::mk("table"),
            &sysobj,
            BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
            Some(v_list_iter((1..=100).map(v_int))),
        )
        .unwrap();
        for (name, program) in verbs {
            tx.add_verb(
                &permissions,
                &sysobj,
                vec![Symbol::mk(name)],
                &sysobj,
                VerbFlag::rxd(),
                VerbArgsSpec::this_none_this(),
                program,
            )
            .unwrap();
        }
        tx.commit().unwrap();
        state
    }

    fn run(
        db: &TxDB,
        verb: &str,
        args: &[Var],
    ) -> std::result::Result<Var, moor_common::tasks::Exception> {
        call_verb(
            db.new_world_state().unwrap(),
            Arc::new(NoopClientSession::new()),
            native_verbs(),
            verb,
            List::mk_list(args),
        )
    }

    #[test]
    fn moo_code_calls_native_verbs() {
        let db = world_with(vec![
            ("native_sum", native("sum")),
            ("native_describe", native("describe")),
            (
                "test",
                moo("return {#0:native_sum(1, 2, 3), #0:native_describe(\"x\")};"),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_int(6),
                v_list(&[
                    v_obj(SYSTEM_OBJECT),
                    Var::mk_symbol(Symbol::mk("native_describe")),
                    v_list(&[v_str("x")])
                ]),
            ]))
        );
    }

    #[test]
    fn native_errors_raise_in_the_caller() {
        let db = world_with(vec![
            ("native_sum", native("sum")),
            ("native_explode", native("explode")),
            (
                "test",
                moo(
                    "try #0:native_sum(\"x\"); except e (E_RANGE) a = e[2]; endtry \
                     try #0:native_explode(); except e (E_INVARG) b = e[2]; endtry \
                     return {a, b};",
                ),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_str("sum adds integers"),
                v_str("Native verb panicked: boom")
            ]))
        );
    }

    /// The host for testing libraries runs them through the same table, outside any task.
    #[test]
    fn libraries_run_outside_a_task() {
        let mut native_verbs = NativeVerbs::default();
        // SAFETY: the linked library's descriptor is static.
        unsafe { native_verbs.add_linked(moor_native_library, Path::new("linked")) }.unwrap();
        let call = |function: &str, args: &[Var]| {
            native_verbs.call(
                "test_natives",
                function,
                v_obj(NOTHING),
                NOTHING,
                List::mk_list(args),
            )
        };
        assert_eq!(call("sum", &[v_int(2), v_int(3)]), Ok(v_int(5)));
        assert_eq!(call("sum", &[v_str("x")]).unwrap_err().err_type(), E_RANGE);
        // There is no world, and nothing to call out to, without a task.
        for (function, args) in [("world", vec![]), ("twice", vec![v_int(1)])] {
            let error = call(function, &args).unwrap_err();
            assert_eq!(
                error.err_type(),
                moor_var::E_INVARG,
                "{function}: {error:?}"
            );
        }
    }

    /// How a run of a task ended.
    enum Ran {
        Done(Var),
        Limit(AbortLimitReason),
        /// The task asked to be retried, and its transaction was rolled back.
        Retry,
    }

    /// Run a verb on #0 with the given limits, resuming it whenever it suspends.
    fn run_limited(
        db: &TxDB,
        verb: &str,
        max_ticks: usize,
        max_time: std::time::Duration,
    ) -> std::result::Result<Var, AbortLimitReason> {
        match run_once(db, verb, max_ticks, max_time) {
            Ran::Done(value) => Ok(value),
            Ran::Limit(reason) => Err(reason),
            Ran::Retry => panic!("{verb} asked to be retried"),
        }
    }

    /// Run a verb on #0 once in a transaction of its own, committed if it completes and rolled
    /// back if it asks to be retried, as the scheduler does.
    fn run_once(db: &TxDB, verb: &str, max_ticks: usize, max_time: std::time::Duration) -> Ran {
        use crate::{
            tasks::task_program_cache::TaskProgramCache,
            testing::vm_test_utils::setup_task_context,
            vm::{VMHostResponse, vm_host::VmHost},
        };
        use moor_common::model::{DispatchFlagsSource, VerbDispatch, VerbLookup};
        let permissions = TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new());
        let tx = db.new_world_state().unwrap();
        let found = tx
            .dispatch_verb(
                &permissions,
                VerbDispatch::new(
                    VerbLookup::method(&SYSTEM_OBJECT, Symbol::mk(verb)),
                    DispatchFlagsSource::Permissions,
                ),
            )
            .unwrap()
            .unwrap();
        let program = tx
            .retrieve_verb(&permissions, &SYSTEM_OBJECT, found.program_key.verb_uuid)
            .unwrap()
            .0;
        let _guard = setup_task_context(tx);
        let mut host = VmHost::new(0, 20, max_ticks, max_time);
        host.start_call_method_verb(
            0,
            found.verbdef,
            Symbol::mk(verb),
            v_obj(SYSTEM_OBJECT),
            SYSTEM_OBJECT,
            List::mk_list(&[]),
            v_obj(NOTHING),
            moor_var::v_empty_str(),
            ObjFlag::all_flags(),
            program,
        );
        let (session, builtins) = (NoopClientSession::new(), native_verbs());
        let config = crate::config::FeaturesConfig::default();
        let mut cache = TaskProgramCache::default();
        loop {
            match host.exec_interpreter(0, &session, &builtins, &config, &mut cache) {
                VMHostResponse::ContinueOk => continue,
                VMHostResponse::Suspend(_) => host.resume_execution(v_int(0)),
                VMHostResponse::CompleteSuccess(value) => {
                    crate::task_context::commit_current_transaction().unwrap();
                    return Ran::Done(value);
                }
                VMHostResponse::AbortLimit(reason) => return Ran::Limit(reason),
                VMHostResponse::RollbackRetry => {
                    crate::task_context::rollback_current_transaction().unwrap();
                    return Ran::Retry;
                }
                _ => panic!("the task ended some other way"),
            }
        }
    }

    #[test]
    fn native_steps_keep_to_the_tick_and_time_limits() {
        let db = world_with(vec![
            ("native_busy", native("busy")),
            ("native_busy_suspend", native("busy_then_suspend")),
            ("native_slow", native("slow")),
        ]);
        let second = std::time::Duration::from_secs(1);
        // Twelve requests are twelve ticks: past a limit of ten, whether the step ends by
        // returning or by suspending.
        for verb in ["native_busy", "native_busy_suspend"] {
            assert!(
                matches!(
                    run_limited(&db, verb, 10, second),
                    Err(AbortLimitReason::Ticks(_))
                ),
                "{verb}"
            );
            assert_eq!(run_limited(&db, verb, 100, second), Ok(v_int(42)), "{verb}");
        }
        let brief = std::time::Duration::from_millis(10);
        assert!(matches!(
            run_limited(&db, "native_slow", 90_000, brief),
            Err(AbortLimitReason::Time(_))
        ));
        assert_eq!(
            run_limited(&db, "native_slow", 90_000, second),
            Ok(v_int(42))
        );
    }

    /// A conflict in a native step, after it has called out and changed the world, retries the
    /// whole task: its changes are undone, and the retry starts the native verb afresh.
    #[test]
    fn conflicts_in_native_steps_retry_the_task_from_its_start() {
        let db = world_with(vec![
            ("native_conflicted", native("conflicted")),
            ("double", moo("return args[1] * 2;")),
        ]);
        let limits = (90_000, std::time::Duration::from_secs(5));
        CONFLICTS_LEFT.store(1, std::sync::atomic::Ordering::SeqCst);
        assert!(matches!(
            run_once(&db, "native_conflicted", limits.0, limits.1),
            Ran::Retry
        ));
        // The counter, 41 at first, was counted up once by the run that stuck.
        assert!(matches!(
            run_once(&db, "native_conflicted", limits.0, limits.1),
            Ran::Done(value) if value == v_list(&[v_int(40), v_int(42)])
        ));
    }

    #[test]
    fn native_verbs_hand_on_the_command_context() {
        let db = world_with(vec![
            ("native_relay", native("relay")),
            ("native_suspend_relay", native("suspend_then_relay")),
            (
                "read_globals",
                moo("return {argstr, dobj, dobjstr, prepstr, iobj, iobjstr};"),
            ),
            (
                "test",
                moo(
                    "argstr = \"apple with knife\"; dobj = #17; dobjstr = \"apple\"; \
                     prepstr = \"with\"; iobj = #18; iobjstr = \"knife\"; \
                     return {#0:native_relay(\"read_globals\"), \
                     #0:native_suspend_relay(\"read_globals\")};",
                ),
            ),
        ]);
        let context = v_list(&[
            v_str("apple with knife"),
            v_obj(moor_var::Obj::mk_id(17)),
            v_str("apple"),
            v_str("with"),
            v_obj(moor_var::Obj::mk_id(18)),
            v_str("knife"),
        ]);
        assert_eq!(
            run_limited(&db, "test", 90_000, std::time::Duration::from_secs(5)),
            Ok(v_list(&[context.clone(), context]))
        );
    }

    #[test]
    fn refs_from_retained_values_last_the_call() {
        let db = world_with(vec![
            ("native_outlive", native("outlive")),
            ("test", moo("return #0:native_outlive({1, \"two\"});")),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[v_int(1), v_str("two"), v_str("kept")]))
        );
    }

    #[test]
    fn values_are_read_and_made_in_bulk() {
        let db = world_with(vec![
            ("native_bulk", native("bulk")),
            (
                "test",
                moo(
                    "return #0:native_bulk({2, 4, 6, 8}, {1, 2.5, #0, \"s\", {3}}, [\"a\" -> 1, \"b\" -> 2]);",
                ),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_list(&[v_int(4), v_int(8), v_int(12), v_int(16)]),
                v_list(&[v_int(4), v_int(6)]),
                v_list(&[v_float(1.0), v_float(2.0), v_float(3.0), v_float(4.0)]),
                v_list(&[
                    v_int(1),
                    v_float(2.5),
                    v_obj(SYSTEM_OBJECT),
                    v_str("s"),
                    v_list(&[v_int(3)])
                ]),
                v_list(&[
                    v_str("int"),
                    v_str("float"),
                    v_str("obj"),
                    v_str("ref"),
                    v_str("ref")
                ]),
                Var::mk_symbol(Symbol::mk("E_TYPE")),
                v_list(&[
                    v_list(&[v_int(1), v_str("a")]),
                    v_list(&[v_int(2), v_str("b")])
                ]),
            ]))
        );
    }

    #[test]
    fn native_verbs_call_verbs_and_resume() {
        let db = world_with(vec![
            ("native_twice", native("twice")),
            ("double", moo("return args[1] * 2;")),
            ("test", moo("return #0:native_twice(21);")),
        ]);
        assert_eq!(run(&db, "test", &[]), Ok(v_list(&[v_int(21), v_int(42)])));
        // The same, as a task's first verb.
        assert_eq!(
            run(&db, "native_twice", &[v_int(5)]),
            Ok(v_list(&[v_int(5), v_int(10)]))
        );
    }

    #[test]
    fn native_verbs_call_builtins() {
        let db = world_with(vec![
            ("native_count", native("count")),
            ("test", moo("return #0:native_count(1, 2, 3);")),
        ]);
        assert_eq!(run(&db, "test", &[]), Ok(v_int(3)));
    }

    #[test]
    fn called_verbs_see_a_native_caller() {
        let db = world_with(vec![
            ("native_relay", native("relay")),
            (
                "who",
                moo("return {caller, callers()[1][2], caller_perms()};"),
            ),
            ("test", moo("return #0:native_relay(\"who\");")),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_obj(SYSTEM_OBJECT),
                v_str("native_relay"),
                v_obj(SYSTEM_OBJECT)
            ]))
        );
    }

    #[test]
    fn errors_in_called_verbs_pass_through_native_verbs() {
        let db = world_with(vec![
            ("native_relay", native("relay")),
            ("fails", moo("raise(E_INVARG, \"from below\");")),
            (
                "test",
                moo(
                    "return {`#0:native_relay(\"fails\") ! E_INVARG => \"caught\"', \
                     `#0:native_relay(\"absent\") ! E_VERBNF => \"no verb\"'};",
                ),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[v_str("caught"), v_str("no verb")]))
        );
    }

    #[test]
    fn native_verbs_read_and_change_the_world() {
        let db = world_with(vec![
            ("native_world", native("world")),
            ("native_missing", native("missing")),
            (
                "test",
                moo("return {#0:native_world(), #0.counter, \
                     `#0:native_missing() ! E_PROPNF => \"no property\"'};"),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_list(&[
                    v_int(42),
                    v_obj(NOTHING),
                    v_bool(true),
                    v_bool(false),
                    v_str("marked"),
                    v_bool(true),
                ]),
                v_int(42),
                v_str("no property"),
            ]))
        );
    }

    #[test]
    fn retained_values_tell_an_unchanged_property_from_a_new_one() {
        let db = world_with(vec![
            ("native_unchanged", native("unchanged")),
            (
                "test",
                moo("a = #0:native_unchanged(#0.table); \
                     b = #0:native_unchanged(#0.table); \
                     #0.table = {@#0.table, 3}; \
                     c = #0:native_unchanged(#0.table); \
                     copy = {}; for i in [1..101] copy = {@copy, i}; endfor \
                     d = #0:native_unchanged(copy); \
                     e = #0:native_unchanged({1, 2}); \
                     f = #0:native_unchanged({1, 2}); \
                     return {a, b, c, d, e, f};"),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_bool(false),
                v_bool(true),
                v_bool(false),
                // An equal list made separately shares nothing.
                v_bool(false),
                v_bool(false),
                // Small lists of the same items are the same value.
                v_bool(true),
            ]))
        );
    }

    /// A library written in C against `moor_native.h`, built here and loaded as the daemon loads
    /// any library.
    #[test]
    fn c_libraries_load_and_run() {
        let native_verb = Path::new(env!("CARGO_MANIFEST_DIR")).join("../native-verb");
        let out = std::env::temp_dir().join(format!("moor-native-c-{}", std::process::id()));
        std::fs::create_dir_all(&out).unwrap();
        let library = out.join("libc_example.so");
        let compiler = std::env::var("CC").unwrap_or_else(|_| "cc".to_string());
        let built = std::process::Command::new(&compiler)
            .args(["-std=c11", "-shared", "-fPIC", "-I"])
            .arg(native_verb.join("include"))
            .arg(native_verb.join("tests/c/sum.c"))
            .arg("-o")
            .arg(&library)
            .output()
            .unwrap_or_else(|e| panic!("Unable to run the C compiler {compiler}: {e}"));
        assert!(
            built.status.success(),
            "{}",
            String::from_utf8_lossy(&built.stderr)
        );
        let native_verbs = NativeVerbs::load(std::slice::from_ref(&library)).unwrap();
        std::fs::remove_dir_all(&out).ok();
        let db = world_with(vec![
            (
                "c_sum",
                ProgramType::Native(NativeProgram {
                    library: Symbol::mk("c_example"),
                    function: Symbol::mk("sum"),
                }),
            ),
            (
                "test",
                moo("return {#0:c_sum(1, 2, 3), `#0:c_sum(\"x\") ! E_TYPE => \"not a number\"'};"),
            ),
        ]);
        let outcome = call_verb(
            db.new_world_state().unwrap(),
            Arc::new(NoopClientSession::new()),
            BuiltinRegistry::with_native_verbs(Arc::new(native_verbs)),
            "test",
            List::mk_list(&[]),
        );
        assert_eq!(outcome, Ok(v_list(&[v_int(6), v_str("not a number")])));
    }

    #[test]
    fn loops_of_native_calls_keep_to_the_tick_limit() {
        let looping = |callee: &str| {
            moo(&format!(
                "for i in [1..100000] x = #0:{callee}(1, 2, 39); endfor return x;"
            ))
        };
        let db = world_with(vec![
            ("native_sum", native("sum")),
            ("moo_sum", moo("return 42;")),
            ("native_loop", looping("native_sum")),
            ("moo_loop", looping("moo_sum")),
        ]);
        for verb in ["moo_loop", "native_loop"] {
            let outcome = call_verb_within_limits(
                db.new_world_state().unwrap(),
                Arc::new(NoopClientSession::new()),
                native_verbs(),
                verb,
                List::mk_list(&[]),
            );
            assert!(
                matches!(outcome, Err(AbortLimitReason::Ticks(_))),
                "{verb} should exhaust its ticks, got {outcome:?}"
            );
        }
    }

    #[test]
    fn a_task_may_start_with_a_native_verb() {
        let db = world_with(vec![("native_sum", native("sum"))]);
        assert_eq!(run(&db, "native_sum", &[v_int(4), v_int(5)]), Ok(v_int(9)));
        let error = run(&db, "native_sum", &[v_str("x")]).unwrap_err();
        assert_eq!(error.error.err_type(), E_RANGE);
    }

    #[test]
    fn unloaded_libraries_and_functions_raise_verbnf() {
        let db = world_with(vec![
            (
                "missing",
                ProgramType::Native(NativeProgram {
                    library: Symbol::mk("elsewhere"),
                    function: Symbol::mk("sum"),
                }),
            ),
            ("unknown", native("multiply")),
            (
                "test",
                moo(
                    "return {`#0:missing() ! E_VERBNF => \"no library\"', `#0:unknown() ! E_VERBNF => \"no function\"'};",
                ),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[v_str("no library"), v_str("no function")]))
        );
    }

    #[test]
    fn wizards_bind_verbs_to_loaded_functions() {
        let db = world_with(vec![
            ("adder", moo("return 0;")),
            (
                "test",
                moo(
                    "set_verb_native(#0, \"adder\", \"test_natives\", \"sum\"); \
                     return {#0:adder(2, 3), verb_native(#0, \"adder\"), \
                     `set_verb_native(#0, \"adder\", \"test_natives\", \"nothing\") ! E_INVARG => \"refused\"', \
                     `verb_code(#0, \"adder\") ! E_INVARG => \"native\"', \
                     native_libraries()[1][1..2]};",
                ),
            ),
        ]);
        assert_eq!(
            run(&db, "test", &[]),
            Ok(v_list(&[
                v_int(5),
                v_list(&[v_str("test_natives"), v_str("sum")]),
                v_str("refused"),
                v_str("native"),
                v_list(&[v_str("test_natives"), v_str("1.0")]),
            ]))
        );
    }
}
