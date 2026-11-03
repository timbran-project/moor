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

//! The runtime's perf metrics: a full walk for export, and the flattened views the counter builtins
//! return.

use fast_telemetry::MetricVisitor;
use moor_common::util::{MetricEntriesVisitor, MetricEntry};
use moor_db::{ANCESTRY_CACHE_STATS, PROP_CACHE_STATS, VERB_CACHE_STATS, db_counters};

use crate::{
    tasks::{sched_counters, task_program_cache::PROGRAM_CACHE_GLOBAL_STATS},
    vm::builtins::bf_perf_counters,
};

/// Visit every runtime metric: database, scheduler and builtin timings and counts, and the
/// resolution and program caches.
pub fn visit_all_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    db_counters().visit_metrics(visitor);
    sched_counters().visit_metrics(visitor);
    bf_perf_counters().visit_metrics(visitor);
    PROP_CACHE_STATS.visit_metrics("property", visitor);
    VERB_CACHE_STATS.visit_metrics("verb", visitor);
    ANCESTRY_CACHE_STATS.visit_metrics("ancestry", visitor);
    PROGRAM_CACHE_GLOBAL_STATS.visit_metrics(visitor);
}

/// World-state (database) operation counters and timings.
pub fn db_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new();
    db_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}

/// Scheduler operation counters and timings.
pub fn sched_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new();
    sched_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}

/// Builtin function call counts and timings.
pub fn bf_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new();
    bf_perf_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}
