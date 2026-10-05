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
//! Owned commit states bind validation, candidate construction, and publication.
//! A failed publication must pass rebase validation before it can be retried.

use super::{Caches, MoorDB, WorkingSets};
use crate::api::world_state::db_counters;
use moor_common::model::{CommitResult, WorldStateError, WorldStateTimerOp};
use moor_common::util::Instant;
use tracing::warn;

mod state;
pub(super) use state::RootPublication;
use state::{PrepareError, PreparedCommit};

/// Maximum number of rebase attempts after the initial CAS before giving up.
const MAX_REBASE_ATTEMPTS: u32 = 16;

impl MoorDB {
    /// Publish read-only cache updates for the transaction snapshot version.
    pub(crate) fn commit_read_only(&self, snapshot_version: u64, combined_caches: Caches) {
        self.snapshot_planes
            .publish_read_only_cache(snapshot_version, combined_caches);
    }

    pub(crate) fn commit_writes(
        &self,
        ws: Box<WorkingSets>,
        _enqueued_at: Instant,
    ) -> Result<CommitResult, WorldStateError> {
        let _process_timer = db_counters()
            .timers_hot
            .start(WorldStateTimerOp::CommitProcessPhase);
        let num_tuples = ws.total_tuples();
        if num_tuples > 10_000 {
            warn!("Potential large batch @ commit... {num_tuples} total tuples in working set");
        }

        if !ws.has_mutations {
            let tx = ws.tx;
            let (_, verb_resolution_cache, prop_resolution_cache, ancestry_cache) =
                ws.extract_relation_working_sets();
            self.commit_read_only(
                tx.snapshot_version,
                Caches {
                    verb_resolution_cache,
                    prop_resolution_cache,
                    ancestry_cache,
                },
            );
            return Ok(CommitResult::Success {
                mutations_made: false,
                timestamp: tx.ts.0,
            });
        }

        let mut prepared = match PreparedCommit::prepare(self, ws) {
            Ok(prepared) => prepared,
            Err(PrepareError::Conflict(info)) => {
                return Ok(CommitResult::ConflictRetry {
                    conflict_info: Some(info),
                });
            }
            Err(PrepareError::Database(error)) => return Err(error),
        };
        for attempt in 0..=MAX_REBASE_ATTEMPTS {
            let retry = match prepared.try_publish() {
                Ok(published) => return Ok(published.enqueue_persistence()),
                Err(retry) => retry,
            };
            if attempt == MAX_REBASE_ATTEMPTS {
                break;
            }
            prepared = match retry.rebase() {
                Ok(prepared) => prepared,
                Err(info) => {
                    return Ok(CommitResult::ConflictRetry {
                        conflict_info: Some(info),
                    });
                }
            };
        }
        Ok(CommitResult::ConflictRetry {
            conflict_info: None,
        })
    }
}
