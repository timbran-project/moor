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
//! Uses a lock-free CAS loop for write commits: multiple workers can check
//! conflicts and build candidate snapshots in parallel. Only the final atomic
//! publish (via `ArcSwap::rcu`) serializes.
//!
//! On CAS failure, we first attempt a cheap rebase: if the winner only modified
//! different relations than us, we can re-slot our prepared indexes onto the
//! winner's snapshot and CAS again without re-checking or re-preparing. Only if
//! both we and the winner touched the same relation do we fall back to a full
//! re-check cycle.

use super::{Caches, MoorDB, WorkingSets, WorldStateSnapshot};
use crate::api::world_state::db_counters;
use crate::engine::relation_defs::RebaseCheck;
use moor_common::model::{CommitResult, ConflictInfo, ConflictTarget, WorldStateTimerOp};
use moor_common::util::Instant;
use moor_var::{NOTHING, Obj, Symbol};
use std::time::Duration;
use tracing::{error, trace, warn};

/// Maximum number of rebase attempts after the initial CAS before giving up.
const MAX_REBASE_ATTEMPTS: u32 = 16;

fn property_name_at_snapshot(
    root: &WorldStateSnapshot,
    object: Obj,
    uuid: uuid::Uuid,
) -> Option<Symbol> {
    let mut current = object;
    for _ in 0..256 {
        if let Some(entry) = root.object_propdefs.index_lookup(&current)
            && let Some(propdef) = entry.value.find_ref(&uuid)
        {
            return Some(propdef.name());
        }

        let parent = root.object_parent.index_lookup(&current)?.value;
        if parent == NOTHING || parent == current {
            return None;
        }
        current = parent;
    }
    None
}

fn enrich_conflict_info(
    root: &WorldStateSnapshot,
    mut conflict_info: ConflictInfo,
) -> ConflictInfo {
    if let Some(ConflictTarget::Property { object, uuid, name }) = &mut conflict_info.target
        && name.is_none()
    {
        *name = property_name_at_snapshot(root, *object, *uuid);
    }
    conflict_info
}

impl MoorDB {
    /// Publish read-only cache updates for the transaction snapshot version.
    pub(crate) fn commit_read_only(&self, snapshot_version: u64, combined_caches: Caches) {
        self.snapshot_planes
            .publish_read_only_cache(snapshot_version, combined_caches);
    }

    /// Persist a successfully published snapshot to the durable store.
    fn persist_commit(
        &self,
        persist_ops: &super::RelationPersistOps,
        publication_version: u64,
        tx_timestamp: crate::tx::Timestamp,
    ) {
        let mut batch = match self.relations.persist_ops_to_batch(
            persist_ops,
            publication_version,
            tx_timestamp,
        ) {
            Ok(batch) => batch,
            Err(error) => {
                Self::report_persistence_failure(&format!(
                    "failed to encode transaction {publication_version}: {error}"
                ));
                return;
            }
        };

        self.sequences[15].store(
            self.monotonic.load(std::sync::atomic::Ordering::Relaxed) as i64,
            std::sync::atomic::Ordering::Relaxed,
        );
        for (i, seq) in self.sequences.iter().enumerate() {
            batch.insert_encoded(
                self.sequences_partition.clone(),
                i.to_le_bytes().to_vec(),
                seq.load(std::sync::atomic::Ordering::Relaxed)
                    .to_le_bytes()
                    .to_vec(),
            );
        }

        if let Err(error) = self.batch_writer.write(batch) {
            Self::report_persistence_failure(&format!(
                "failed to enqueue transaction {publication_version}: {error}"
            ));
        }
    }

    fn report_persistence_failure(detail: &str) {
        error!("FATAL: {detail}");
        #[cfg(not(test))]
        moor_common::util::signal_fatal_db_error("transaction persistence", detail);
    }

    /// Execute the write-commit path for a transaction via CAS loop.
    pub(crate) fn commit_writes(
        &self,
        ws: Box<WorkingSets>,
        _enqueued_at: Instant,
    ) -> CommitResult {
        let counters = db_counters();
        let _process_timer = counters
            .timers_hot
            .start(WorldStateTimerOp::CommitProcessPhase);

        let num_tuples = ws.total_tuples();
        if num_tuples > 10_000 {
            warn!("Potential large batch @ commit... {num_tuples} total tuples in working set");
        }

        let tx_timestamp = ws.tx.ts;
        let snapshot_version = ws.tx.snapshot_version;
        let has_mutations = ws.has_mutations;
        let tx_bloom = ws.tx_bloom.clone();
        let (mut relation_ws, verb_cache, prop_cache, ancestry_cache) =
            ws.extract_relation_working_sets();

        // Read-only fast path
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

        let start_time = Instant::now();

        // Phase 1: Check conflicts and prepare indexes against current snapshot
        let current_root = self.snapshot_planes.load_root();
        let mut checkers = self.relations.begin_check_all(&current_root);

        // Skip conflict check if:
        // - No commits since our snapshot (existing fast path), OR
        // - The snapshot's cumulative bloom filter covers all commits since
        //   our snapshot, and our keys don't intersect it
        let skip_conflict_check = snapshot_version == current_root.version
            || (snapshot_version >= current_root.bloom_since_version
                && current_root
                    .commit_bloom
                    .as_ref()
                    .is_some_and(|snap_bloom| !tx_bloom.might_intersect(snap_bloom)));

        if !skip_conflict_check {
            let _t = counters
                .timers_hot
                .start(WorldStateTimerOp::CommitCheckPhase);
            if let Err(conflict_info) = checkers.check_all(&mut relation_ws) {
                let conflict_info = enrich_conflict_info(&current_root, conflict_info);
                trace!("Transaction conflict during commit: {conflict_info}");
                return CommitResult::ConflictRetry {
                    conflict_info: Some(conflict_info),
                };
            }
        }

        if start_time.elapsed() > Duration::from_secs(5) {
            warn!(
                "Long running commit; check phase took {}s for {num_tuples} tuples",
                start_time.elapsed().as_secs_f32()
            );
        }

        let _t = counters
            .timers_hot
            .start(WorldStateTimerOp::CommitApplyPhase);
        let (persist_ops, bloom) = checkers.prepare_apply_all(&relation_ws);
        let combined_caches = Caches {
            verb_resolution_cache: verb_cache.fork(),
            prop_resolution_cache: prop_cache.fork(),
            ancestry_cache: ancestry_cache.fork(),
        };
        let next_root =
            checkers.build_snapshot(&current_root, tx_timestamp, combined_caches, bloom.clone());
        drop(_t);

        // Phase 2: Try to publish
        let publication_version = next_root.version;
        if self
            .snapshot_planes
            .try_publish_write_root(current_root.version, next_root)
        {
            self.persist_commit(&persist_ops, publication_version, tx_timestamp);
            return CommitResult::Success {
                mutations_made: true,
                timestamp: tx_timestamp.0,
            };
        }

        // Phase 3: CAS failed — try to rebase onto the winner's snapshot.
        // Bloom misses prove disjointness cheaply. Bloom hits are checked
        // exactly against the snapshot for which our operations were prepared.
        let mut checked_root = current_root;
        for _rebase in 0..MAX_REBASE_ATTEMPTS {
            let winner = self.snapshot_planes.load_root();

            let rebase_check = checkers.rebase_check(&relation_ws, &checked_root, &winner);
            if let RebaseCheck::ActualOverlap(conflict_info) = rebase_check {
                let conflict_info = enrich_conflict_info(&winner, conflict_info);
                trace!(
                    checked_version = checked_root.version,
                    winner_version = winner.version,
                    %conflict_info,
                    "Transaction found an exact key overlap after CAS loss"
                );
                return CommitResult::ConflictRetry {
                    conflict_info: Some(conflict_info),
                };
            }

            let combined_caches = Caches {
                verb_resolution_cache: verb_cache.fork(),
                prop_resolution_cache: prop_cache.fork(),
                ancestry_cache: ancestry_cache.fork(),
            };
            let rebased = checkers.build_rebased_snapshot(
                &relation_ws,
                &winner,
                tx_timestamp,
                combined_caches,
                &bloom,
            );

            // Rebase succeeded — no key overlap. Try CAS again.
            let publication_version = rebased.version;
            if self
                .snapshot_planes
                .try_publish_write_root(winner.version, rebased)
            {
                self.persist_commit(&persist_ops, publication_version, tx_timestamp);
                return CommitResult::Success {
                    mutations_made: true,
                    timestamp: tx_timestamp.0,
                };
            }

            // Another writer won. The prepared operations have now been proven
            // safe through this winner, so compare only the next interval.
            checked_root = winner;
        }

        CommitResult::ConflictRetry {
            conflict_info: None,
        }
    }
}
