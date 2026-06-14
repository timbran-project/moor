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

use std::{
    cell::Cell,
    sync::{Arc, LazyLock},
    time::Instant,
};
use thiserror::Error;

use crate::vm::builtins::bf_connection::register_bf_connection;
use crate::vm::builtins::bf_obj_load::register_bf_obj_load;
use crate::vm::builtins::bf_task::register_bf_task;
use crate::{
    config::FeaturesConfig,
    task_context::with_current_transaction,
    vm::{
        builtins::{
            bf_cryptography::register_bf_cryptography,
            bf_documents::register_bf_documents,
            bf_flyweights::register_bf_flyweights,
            bf_list_sets::register_bf_list_sets,
            bf_maps::register_bf_maps,
            bf_num::register_bf_num,
            bf_objects::register_bf_objects,
            bf_properties::register_bf_properties,
            bf_server::{bf_noop, register_bf_server},
            bf_spatial::register_bf_spatial,
            bf_strings::register_bf_strings,
            bf_values::register_bf_values,
            bf_verbs::register_bf_verbs,
        },
        vm_host::ExecutionResult,
    },
};
use fast_telemetry::{Counter, Histogram, MetricKind, MetricLabel, MetricLabels, MetricMeta};
use moor_common::model::WorldStateError;
use moor_common::util::hot_stride;
use moor_compiler::{BUILTINS, BuiltinId, DiagnosticRenderOptions, DiagnosticVerbosity};
use moor_var::{
    E_INVARG, E_PERM, E_TYPE, Error, ErrorCode, List, Map, Obj, Sequence, Symbol, Var, Variant,
    v_bool_int, v_map,
};
use moor_vm::{Authority, BuiltinFrame, ExecState, Frame};

mod bf_cryptography;
mod bf_documents;
mod bf_flyweights;
mod bf_list_sets;
mod bf_maps;
mod bf_num;
mod bf_obj_load;
mod bf_objects;
mod bf_properties;
pub mod bf_server;
mod bf_strings;
mod bf_values;
mod bf_verbs;
mod docs;

mod bf_connection;
mod bf_spatial;
mod bf_task;
#[cfg(test)]
#[path = "test_function_help.rs"]
mod test_function_help;
mod unix_crypt_compat;
// See ADDING-BUILTINS.md in this directory for safe builtin additions.

static BF_COUNTERS: LazyLock<BfCounters> = LazyLock::new(BfCounters::new);

thread_local! {
    static BF_COUNTERS_TLS: &'static BfCounters = &BF_COUNTERS;
}

pub struct BfTimer {
    calls: Option<Counter>,
    samples: Option<Histogram>,
    stride_mask: u64,
}

pub struct BfTimerGuard<'a> {
    samples: Option<&'a Histogram>,
    start: Option<Instant>,
}

pub struct BfCounters {
    timers: Vec<BfTimer>,
}

impl Default for BfCounters {
    fn default() -> Self {
        Self::new()
    }
}

impl BfCounters {
    pub fn new() -> Self {
        let mut timers = Vec::with_capacity(BUILTINS.number_of());
        let stride_mask = hot_stride().max(1).next_power_of_two() - 1;
        for index in 0..BUILTINS.number_of() {
            let id = BuiltinId(index as u16);
            let desc = BUILTINS.description_for(id).expect("Builtin not found");
            let (calls, samples) = if desc.exposed {
                (
                    Some(Counter::new(16)),
                    Some(Histogram::new(BF_SAMPLE_BOUNDS_NANOS, 16)),
                )
            } else {
                (None, None)
            };
            timers.push(BfTimer {
                calls,
                samples,
                stride_mask,
            });
        }
        Self { timers }
    }

    pub fn timer_for(&self, id: BuiltinId) -> &BfTimer {
        &self.timers[id.0 as usize]
    }

    pub fn visit_metrics<V: fast_telemetry::MetricVisitor + ?Sized>(&self, visitor: &mut V) {
        let call_meta = MetricMeta {
            name: "bf_calls",
            help: "Builtin function calls",
            kind: MetricKind::Counter,
            unit: None,
        };
        let sample_meta = MetricMeta {
            name: "bf_samples",
            help: "Builtin function sampled latency in nanoseconds",
            kind: MetricKind::Histogram,
            unit: Some("ns"),
        };

        for (index, timer) in self.timers.iter().enumerate() {
            let Some(calls) = timer.calls.as_ref() else {
                continue;
            };
            let id = BuiltinId(index as u16);
            let desc = BUILTINS.description_for(id).expect("Builtin not found");
            let labels = MetricLabels::one(MetricLabel {
                name: "op",
                value: desc.name.as_str(),
            });
            visitor.counter(call_meta, labels, calls.sum() as i64);
            if let Some(samples) = timer.samples.as_ref() {
                visitor.histogram(sample_meta, labels, samples);
            }
        }
    }
}

pub fn bf_perf_counters() -> &'static BfCounters {
    BF_COUNTERS_TLS.with(|c| *c)
}

const BF_SAMPLE_BOUNDS_NANOS: &[u64] = &[
    10_000,         // 10µs
    50_000,         // 50µs
    100_000,        // 100µs
    500_000,        // 500µs
    1_000_000,      // 1ms
    5_000_000,      // 5ms
    10_000_000,     // 10ms
    50_000_000,     // 50ms
    100_000_000,    // 100ms
    500_000_000,    // 500ms
    1_000_000_000,  // 1s
    5_000_000_000,  // 5s
    10_000_000_000, // 10s
];

impl BfTimer {
    #[inline]
    pub fn start(&self) -> BfTimerGuard<'_> {
        let Some(calls) = self.calls.as_ref() else {
            return BfTimerGuard {
                samples: None,
                start: None,
            };
        };
        calls.inc();
        let start = should_sample_bf_timer(self.stride_mask).then(Instant::now);
        BfTimerGuard {
            samples: self.samples.as_ref(),
            start,
        }
    }
}

impl Drop for BfTimerGuard<'_> {
    #[inline]
    fn drop(&mut self) {
        let Some(start) = self.start.take() else {
            return;
        };
        if let Some(samples) = self.samples {
            samples.record(start.elapsed().as_nanos().min(u64::MAX as u128) as u64);
        }
    }
}

thread_local! {
    static BF_TIMER_SAMPLE_TICK: Cell<u64> = const { Cell::new(0) };
}

#[inline]
fn should_sample_bf_timer(stride_mask: u64) -> bool {
    BF_TIMER_SAMPLE_TICK.with(|tick| {
        let next = tick.get().wrapping_add(1);
        tick.set(next);
        next & stride_mask == 0
    })
}

/// The bundle of builtins are stored here, and passed around globally.
#[derive(Clone)]
pub struct BuiltinRegistry {
    // The set of built-in functions, indexed by their Name offset in the variable stack.
    pub(crate) builtins: Arc<[BuiltinFunction]>,
}

impl Default for BuiltinRegistry {
    fn default() -> Self {
        Self::new()
    }
}

impl BuiltinRegistry {
    pub fn new() -> Self {
        let mut builtins: Vec<BuiltinFunction> = Vec::with_capacity(BUILTINS.number_of());
        for _ in 0..BUILTINS.number_of() {
            builtins.push(bf_noop)
        }
        register_bf_server(&mut builtins);
        register_bf_connection(&mut builtins);
        register_bf_task(&mut builtins);
        register_bf_num(&mut builtins);
        register_bf_values(&mut builtins);
        register_bf_strings(&mut builtins);
        register_bf_list_sets(&mut builtins);
        register_bf_maps(&mut builtins);
        register_bf_objects(&mut builtins);
        register_bf_obj_load(&mut builtins);
        register_bf_verbs(&mut builtins);
        register_bf_properties(&mut builtins);
        register_bf_flyweights(&mut builtins);
        register_bf_documents(&mut builtins);
        register_bf_cryptography(&mut builtins);
        register_bf_spatial(&mut builtins);

        BuiltinRegistry {
            builtins: Arc::from(builtins),
        }
    }

    pub(crate) fn builtin_for(&self, id: &BuiltinId) -> &BuiltinFunction {
        &self.builtins[id.0 as usize]
    }
}

/// The arguments and other state passed to a built-in function.
/// WorldState, TaskSchedulerClient, and Session are now accessed via the global task context.
pub(crate) struct BfCallState<'a> {
    /// The name of the invoked function.
    pub(crate) name: Symbol,
    /// Arguments passed to the function.
    pub(crate) args: &'a List,
    /// The current execution state of this task in this VM, including the stack
    /// so that BFs can inspect and manipulate it.
    pub(crate) exec_state: &'a mut ExecState,
    /// Config
    pub(crate) config: &'a FeaturesConfig,
}

impl BfCallState<'_> {
    pub fn caller_perms(&self) -> Obj {
        self.exec_state.caller_perms()
    }
    pub fn task_authority_principal(&self) -> Obj {
        self.exec_state.task_authority_principal()
    }

    pub fn player(&self) -> Obj {
        self.exec_state.top().player()
    }

    pub fn task_authority(&self) -> Result<Authority, WorldStateError> {
        let who = self.task_authority_principal();
        // Always do a live lookup here - object flags can change mid-execution
        // (e.g., player.programmer = 0) and builtins need to see current state
        let flags = with_current_transaction(|ws| ws.flags_of(&who))?;
        Ok(Authority::new(who, flags))
    }

    pub fn require_wizard(&self) -> Result<(), BfErr> {
        self.task_authority()
            .map_err(world_state_bf_err)?
            .require_wizard()
            .map_err(world_state_bf_err)
    }

    pub fn require_wizard_msg(&self, message: &'static str) -> Result<(), BfErr> {
        self.task_authority()
            .map_err(world_state_bf_err)?
            .require_wizard()
            .map_err(|_| BfErr::ErrValue(E_PERM.msg(message)))
    }

    pub fn require_programmer(&self) -> Result<(), BfErr> {
        self.task_authority()
            .map_err(world_state_bf_err)?
            .require_programmer()
            .map_err(world_state_bf_err)
    }

    pub fn require_controls(&self, owner: &Obj) -> Result<(), BfErr> {
        self.task_authority()
            .map_err(world_state_bf_err)?
            .require_controls(owner)
            .map_err(world_state_bf_err)
    }

    pub fn require_controls_msg(&self, owner: &Obj, message: &'static str) -> Result<(), BfErr> {
        self.task_authority()
            .map_err(world_state_bf_err)?
            .require_controls(owner)
            .map_err(|_| BfErr::ErrValue(E_PERM.msg(message)))
    }

    pub fn bf_frame(&self) -> &BuiltinFrame {
        let Frame::Bf(frame) = &self.exec_state.top().frame else {
            panic!("Expected a BF frame at the top of the stack");
        };

        frame
    }

    pub fn bf_frame_mut(&mut self) -> &mut BuiltinFrame {
        let Frame::Bf(frame) = &mut self.exec_state.top_mut().frame else {
            panic!("Expected a BF frame at the top of the stack");
        };

        frame
    }

    /// Construct a boolean value from a truthy value but convert to mooR boolean only if that
    /// feature is enabled.
    pub fn v_bool(&self, truthy: bool) -> Var {
        if !self.config.use_boolean_returns {
            v_bool_int(truthy)
        } else {
            Var::mk_bool(truthy)
        }
    }

    /// Convert a map or alist (list of {key, value} pairs) to a Map.
    /// Returns an error if the value is neither a map nor a valid alist.
    pub fn map_or_alist_to_map(&self, value: &Var) -> Result<Map, BfErr> {
        match value.variant() {
            Variant::Map(m) => Ok(m.clone()),
            Variant::List(l) => {
                let mut pairs = Vec::new();
                for item in l.iter() {
                    let Some(pair_list) = item.as_list() else {
                        return Err(BfErr::ErrValue(
                            E_TYPE.msg("Alist must be a list of {key, value} pairs"),
                        ));
                    };
                    if pair_list.len() != 2 {
                        return Err(BfErr::ErrValue(
                            E_TYPE.msg("Alist pairs must have exactly 2 elements"),
                        ));
                    }
                    let key = pair_list.index(0).map_err(BfErr::ErrValue)?;
                    let val = pair_list.index(1).map_err(BfErr::ErrValue)?;
                    pairs.push((key, val));
                }
                Ok(v_map(&pairs).as_map().unwrap().clone())
            }
            _ => Err(BfErr::ErrValue(
                E_TYPE.msg("Expected map or alist (list of {key, value} pairs)"),
            )),
        }
    }
}

pub(crate) type BuiltinFunction = fn(&mut BfCallState<'_>) -> Result<BfRet, BfErr>;

/// Return possibilities from a built-in function.
pub(crate) enum BfRet {
    /// Successful return with no relevant value.
    /// This will just get turned into v_int(0), but I want to call it out as a distinct path.
    /// We used to return v_none here, until TYPE_NONE became E_VARNF.
    RetNil,
    /// Successful return, with a value to be pushed to the value stack.
    Ret(Var),
    /// BF wants to return control back to the VM, with specific instructions to things like
    /// `suspend` or dispatch to a verb call or execute eval.
    VmInstr(ExecutionResult),
}

#[derive(Debug, Clone, PartialEq, Error)]
pub(crate) enum BfErr {
    #[error("Error in built-in function: {0}")]
    ErrValue(Error),
    #[error("Error in built-in function: {0}")]
    Code(ErrorCode),
    #[error("Raised error: {0:?}")]
    Raise(Error),
    #[error("Transaction rollback-retry")]
    Rollback,
}

pub(crate) fn world_state_bf_err(err: WorldStateError) -> BfErr {
    match err {
        WorldStateError::RollbackRetry => BfErr::Rollback,
        _ => BfErr::ErrValue(err.into()),
    }
}
pub(crate) enum DiagnosticOutput {
    Formatted(DiagnosticRenderOptions),
    Structured,
}

pub(crate) fn parse_diagnostic_options(
    verbosity: Option<i64>,
    output_mode: Option<i64>,
) -> Result<DiagnosticOutput, BfErr> {
    let verbosity_level = verbosity.unwrap_or(0);

    // Verbosity 3 means return structured data instead of formatted strings
    if verbosity_level == 3 {
        return Ok(DiagnosticOutput::Structured);
    }

    let verbosity = match verbosity_level {
        0 => DiagnosticVerbosity::Summary,
        1 => DiagnosticVerbosity::SourceContext,
        2 => DiagnosticVerbosity::Detailed,
        _ => {
            return Err(BfErr::Code(E_INVARG));
        }
    };

    let (use_graphics, use_color) = match output_mode {
        Some(0) => (false, false),
        Some(1) => (true, false),
        Some(2) => (true, true),
        Some(_) => {
            return Err(BfErr::Code(E_INVARG));
        }
        None => (false, false),
    };

    Ok(DiagnosticOutput::Formatted(DiagnosticRenderOptions {
        verbosity,
        use_graphics,
        use_color,
    }))
}
