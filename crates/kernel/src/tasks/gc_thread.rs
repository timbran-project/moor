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

//! Concurrent GC mark phase thread spawned by scheduler

use std::{collections::HashSet, io, thread, time::Instant};

use moor_var::Obj;
use tracing::{debug, error, info};

use crate::tasks::{SchedulerOp, sched_counters, scheduler::gc::GcCycle};
use moor_common::{tasks::SchedulerError, tasks::SchedulerError::GarbageCollectionFailed};

/// Spawn a mark worker which owns cycle cleanup, including during unwinding.
pub(crate) fn spawn_gc_mark_phase(
    gc_tx: Box<dyn moor_db::GCInterface>,
    cycle: GcCycle,
    vm_refs: HashSet<Obj>,
    mutation_timestamp: Option<u64>,
) -> io::Result<thread::JoinHandle<()>> {
    thread::Builder::new()
        .name("moor-gc".into())
        .spawn(move || {
            match run_gc_mark_phase(gc_tx, vm_refs) {
                Ok(unreachable) => {
                    if let Err(error) = cycle.finish_mark(unreachable, mutation_timestamp) {
                        error!(?error, "GC sweep failed");
                    }
                }
                Err(error) => error!(?error, "GC mark phase failed"),
            }
            // A failed mark drops the cycle here. A panic drops it while unwinding.
        })
}

/// Run the mark phase in a background thread
fn run_gc_mark_phase(
    mut gc: Box<dyn moor_db::GCInterface>,
    vm_refs: HashSet<Obj>,
) -> Result<HashSet<Obj>, SchedulerError> {
    let start_time = Instant::now();
    let perfc = sched_counters();
    let _t = perfc.timers.start(SchedulerOp::GcMarkPhase);

    // Get all anonymous objects
    let all_anon_objects = gc
        .get_anonymous_objects()
        .map_err(|e| GarbageCollectionFailed(format!("Failed to get anonymous objects: {e}")))?;

    // Get all DB references to anonymous objects
    let db_refs = gc
        .scan_anonymous_object_references()
        .map_err(|e| GarbageCollectionFailed(format!("Failed to scan DB references: {e}")))?;

    // Build lookup map for transitive closure
    let db_refs_map: std::collections::HashMap<Obj, HashSet<Obj>> = db_refs.into_iter().collect();

    // Start with VM refs (filter to anonymous only)
    let mut reachable_objects: HashSet<Obj> = vm_refs
        .into_iter()
        .filter(|obj| obj.is_anonymous())
        .collect();

    // Add refs from regular (non-anonymous) objects - these are roots
    for (obj, refs) in &db_refs_map {
        if !obj.is_anonymous() {
            reachable_objects.extend(refs.iter().copied());
        }
    }

    // Transitive closure: follow refs from reachable anonymous objects to find more
    let mut worklist: Vec<Obj> = reachable_objects
        .iter()
        .filter(|o| o.is_anonymous())
        .copied()
        .collect();

    while let Some(obj) = worklist.pop() {
        if let Some(refs) = db_refs_map.get(&obj) {
            for r in refs {
                if r.is_anonymous() && reachable_objects.insert(*r) {
                    worklist.push(*r);
                }
            }
        }
    }

    // Find unreachable objects
    let unreachable_objects: HashSet<Obj> = all_anon_objects
        .difference(&reachable_objects)
        .copied()
        .collect();

    let mark_duration = start_time.elapsed();
    if unreachable_objects.is_empty() {
        debug!(
            "GC mark: no unreachable objects identified in {:.2}ms",
            mark_duration.as_millis()
        );
    } else {
        info!(
            "GC mark: {} unreachable objects identified in {:.2}ms",
            unreachable_objects.len(),
            mark_duration.as_millis()
        );
    }
    Ok(unreachable_objects)
}
