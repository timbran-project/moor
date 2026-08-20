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

//! Write and read-only commit execution pipeline for `MoorDB`.
//!
//! This module implements the serialized write commit path, including conflict
//! checking, relation apply, root publication, and async durability handoff.

use super::{Caches, MoorDB, WorkingSets};
use crate::api::world_state::db_counters;
use moor_common::model::CommitResult;
use moor_common::util::{Instant, PerfIntensity, PerfTimerGuard};
use std::time::Duration;
use tracing::warn;

impl MoorDB {
    /// Publish read-only cache updates for the transaction snapshot version.
    pub(crate) fn commit_read_only(&self, snapshot_version: u64, combined_caches: Caches) {
        self.snapshot_planes
            .publish_read_only_cache(snapshot_version, combined_caches);
    }

    /// Execute the serialized write-commit path for a transaction.
    pub(crate) fn commit_writes(&self, ws: Box<WorkingSets>, enqueued_at: Instant) -> CommitResult {
        let counters = db_counters();
        let lock_wait_timer = PerfTimerGuard::from_start_with_intensity(
            &counters.commit_lock_wait_phase,
            enqueued_at,
            PerfIntensity::MediumPath,
        );
        let _commit_guard = self.commit_apply_lock.lock();
        drop(lock_wait_timer);

        let _process_timer = PerfTimerGuard::new(&counters.commit_process_phase);
        self.process_commit_writes(ws, counters)
    }

    /// Perform conflict check, apply, publication, and durability scheduling.
    fn process_commit_writes(
        &self,
        ws: Box<WorkingSets>,
        counters: &moor_common::model::WorldStatePerf,
    ) -> CommitResult {
        let _t = PerfTimerGuard::new(&counters.commit_check_phase);
        let start_time = Instant::now();

        let current_root = self.snapshot_planes.load_root();
        let mut checkers = self.relations.begin_check_all(&current_root);

        let num_tuples = ws.total_tuples();
        if num_tuples > 10_000 {
            warn!(
                "Potential large batch @ commit... Checking {num_tuples} total tuples from the working set..."
            );
        }

        let tx_timestamp = ws.tx.ts;
        let snapshot_version = ws.tx.snapshot_version;
        let has_mutations = ws.has_mutations;
        let (mut relation_ws, verb_cache, prop_cache, ancestry_cache) =
            ws.extract_relation_working_sets();

        let skip_conflict_check = snapshot_version == current_root.version;
        if !skip_conflict_check && let Err(conflict_info) = checkers.check_all(&mut relation_ws) {
            warn!("Transaction conflict during commit: {}", conflict_info);
            return CommitResult::ConflictRetry {
                conflict_info: Some(conflict_info),
            };
        }
        drop(_t);

        if !has_mutations {
            self.commit_read_only(
                snapshot_version,
                Caches {
                    verb_resolution_cache: verb_cache,
                    prop_resolution_cache: prop_cache,
                    ancestry_cache,
                },
            );
            return CommitResult::Success {
                mutations_made: false,
                timestamp: tx_timestamp.0,
            };
        }

        if start_time.elapsed() > Duration::from_secs(5) {
            warn!(
                "Long running commit; check phase took {}s for {num_tuples} tuples",
                start_time.elapsed().as_secs_f32()
            );
        }

        let _t = PerfTimerGuard::new(&counters.commit_apply_phase);
        let publication_version = current_root.version + 1;
        self.batch_collector
            .start_commit(publication_version, tx_timestamp, num_tuples + 16);

        let checkers = match checkers.apply_all(relation_ws) {
            Ok(checkers) => checkers,
            Err(()) => {
                self.batch_collector.abort_commit();
                warn!("Transaction conflict during apply phase (no detailed info available)");
                return CommitResult::ConflictRetry {
                    conflict_info: None,
                };
            }
        };

        self.sequences[15].store(
            self.monotonic.load(std::sync::atomic::Ordering::Relaxed) as i64,
            std::sync::atomic::Ordering::Relaxed,
        );
        let mut batch = self.batch_collector.finish_commit();
        for (i, sequence) in self.sequences.iter().enumerate() {
            batch.insert_encoded(
                self.sequences_partition.clone(),
                i.to_le_bytes().to_vec(),
                sequence
                    .load(std::sync::atomic::Ordering::Relaxed)
                    .to_le_bytes()
                    .to_vec(),
            );
        }

        let batch_op_count = batch.operations.len();
        let batch_write_start = Instant::now();
        self.batch_writer.write(batch);
        let batch_write_elapsed = batch_write_start.elapsed();

        let next_root = checkers.commit_all(&current_root, verb_cache, prop_cache, ancestry_cache);
        debug_assert_eq!(next_root.version, publication_version);
        self.snapshot_planes.publish_write_root(next_root);

        self.batch_writer.send_barrier(publication_version);
        self.last_write_version
            .store(publication_version, std::sync::atomic::Ordering::Release);

        if batch_write_elapsed > Duration::from_secs(1) {
            warn!(
                "Slow batch_write: {} ops blocked for {:.2}s (version {}, ts {})",
                batch_op_count,
                batch_write_elapsed.as_secs_f32(),
                publication_version,
                tx_timestamp.0
            );
        }

        drop(_t);
        CommitResult::Success {
            mutations_made: true,
            timestamp: tx_timestamp.0,
        }
    }
}
