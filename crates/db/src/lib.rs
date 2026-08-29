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

#![recursion_limit = "256"]

use moor_common::model::loader::{LoaderInterface, SnapshotInterface};
use moor_common::model::{WorldState, WorldStateError, WorldStateSource};
use moor_common::threading::spawn_efficient;
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

mod api;
mod cache;
mod config;
mod engine;
mod model;
mod provider;
mod tx;

use crate::engine::MoorDB;

pub use api::world_state::DbWorldState;
pub use api::{
    gc::{GCError, GCInterface},
    world_state::db_counters,
};
pub use cache::stats::CacheStats;
pub use cache::{ANCESTRY_CACHE_STATS, PROP_CACHE_STATS, VERB_CACHE_STATS};
pub use cache::{
    ancestry_cache::AncestryCache, prop_cache::PropResolutionCache, verb_cache::VerbResolutionCache,
};
pub use config::{AutoCompactionConfig, CompactionDecision, DatabaseConfig, TableConfig};
pub use model::{
    AnonymousObjectMetadata, BytesHolder, EntityMetadataKey, ObjAndUUIDHolder, StringHolder,
    SystemTimeHolder, UUIDHolder,
};
pub use provider::Provider;
pub use tx::{
    AcceptIdentical, CheckRelation, ConflictResolver, Error, FailOnConflict, PotentialConflict,
    ProposedOp, Relation, RelationCodomain, RelationCodomainHashable, RelationDomain,
    RelationIndex, RelationTransaction, SmartMergeResolver, Timestamp, Tx, WorkingSet,
};

pub type SnapshotCallback = Box<
    dyn FnOnce(Result<Box<dyn SnapshotInterface>, WorldStateError>) -> Result<(), WorldStateError>
        + Send,
>;

/// Outcome of major-compacting one relation's keyspace.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RelationCompactionResult {
    /// The relation name, as declared in `define_relations!`.
    pub relation: &'static str,
    pub bytes_before: u64,
    pub bytes_after: u64,
    /// Set if this relation's compaction failed; the others were still attempted.
    pub error: Option<String>,
}

impl RelationCompactionResult {
    /// Bytes reclaimed, saturating — compaction can briefly grow a keyspace.
    pub fn bytes_reclaimed(&self) -> u64 {
        self.bytes_before.saturating_sub(self.bytes_after)
    }
}

/// Point-in-time storage-engine maintenance counters.
///
/// These values are observational and may change immediately after being read.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct StorageMaintenanceStats {
    pub write_buffer_bytes: u64,
    pub outstanding_flushes: usize,
    pub active_compactions: usize,
    pub compactions_completed: usize,
    pub compaction_time: Duration,
    pub journal_count: usize,
    pub journal_bytes: u64,
    pub disk_bytes: u64,
}

impl StorageMaintenanceStats {
    /// Whether storage work is currently queued or executing.
    #[must_use]
    pub fn is_active(self) -> bool {
        self.outstanding_flushes != 0 || self.active_compactions != 0
    }
}

// Re-export sequence constants for use in VM
pub use engine::SEQUENCE_MAX_OBJECT;

#[derive(Debug, thiserror::Error)]
pub enum DatabaseOpenError {
    #[error("failed to create temporary database directory: {source}")]
    TempDir { source: std::io::Error },

    #[error("failed to migrate database at {path:?}: {detail}")]
    Migration { path: PathBuf, detail: String },

    #[error("failed to open database at {path:?}: {detail}")]
    Open { path: PathBuf, detail: String },

    #[error("failed to open keyspace {keyspace:?} in database at {path:?}: {detail}")]
    Keyspace {
        path: PathBuf,
        keyspace: &'static str,
        detail: String,
    },

    #[error("failed to read sequence {index} from database at {path:?}: {detail}")]
    ReadSequence {
        path: PathBuf,
        index: usize,
        detail: String,
    },

    #[error(
        "failed to decode sequence {index} from database at {path:?}: expected 8 bytes, got {len}"
    )]
    DecodeSequence {
        path: PathBuf,
        index: usize,
        len: usize,
    },

    #[error("failed to mark fresh database version at {path:?}: {detail}")]
    MarkVersion { path: PathBuf, detail: String },

    #[error("invalid tuple value format in database at {path:?}: {detail}")]
    TupleValueFormat { path: PathBuf, detail: String },

    #[error("failed to seed relation {relation:?} from database at {path:?}: {detail}")]
    SeedRelation {
        path: PathBuf,
        relation: &'static str,
        detail: String,
    },

    #[error("transaction timestamp space is exhausted in database at {path:?}")]
    TransactionTimestampExhausted { path: PathBuf },
}

pub trait Database: Send + Sync + WorldStateSource {
    fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError>;
    fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError>;
    fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError>;
    fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError>;

    /// Return storage maintenance counters when supported by the engine.
    fn storage_maintenance_stats(&self) -> Option<StorageMaintenanceStats> {
        None
    }

    /// Major-compact all storage, blocking until done, when supported by the engine.
    ///
    /// Reclaims superseded versions and tombstoned rows that background compaction has not got to.
    /// Expensive: it rewrites every table, and blocks the caller throughout. `None` means the
    /// engine has no such operation.
    ///
    /// It is *not* required that no snapshot be open. fjall's GC floor comes from the oldest
    /// retained snapshot minus one, so data superseded before that snapshot was taken is still
    /// reclaimable, and the snapshot goes on reading its own versions correctly
    /// (`fjall_gc_watermark_probe` asserts both). Callers still serialize this against checkpoints,
    /// because doing both at once means two full passes over the database at the same time.
    fn major_compact(&self) -> Option<Vec<RelationCompactionResult>> {
        None
    }

    /// Physical bytes the storage engine currently occupies, when it can report them.
    ///
    /// Reported for observability. Note this is post-compression and includes write-ahead
    /// journals, so it is not comparable with a logical live-bytes figure.
    fn disk_bytes(&self) -> Option<u64> {
        None
    }

    /// Rows the engine has stored for property data, superseded versions included.
    ///
    /// Compared against the live row count from a checkpoint scan to estimate version
    /// amplification; see [`DatabaseConfig::auto_compaction`].
    fn stored_property_rows(&self) -> Option<u64> {
        None
    }

    /// An owned handle for compacting this storage from another thread.
    ///
    /// A checkpoint runs its export on a spawned thread and wants to compact once the snapshot is
    /// released, which outlives any borrow of the database. `None` when the engine cannot compact.
    fn compaction_handle(&self) -> Option<Arc<dyn StorageCompactor>> {
        None
    }
}

/// The subset of [`Database`] a background maintenance step needs, as a sendable handle.
pub trait StorageCompactor: Send + Sync {
    /// Physical bytes currently occupied, for logging.
    fn disk_bytes(&self) -> u64;
    /// Stored property rows, superseded versions included. The amplification signal.
    fn stored_property_rows(&self) -> u64;
    /// Major-compact everything, blocking until done.
    fn major_compact(&self) -> Vec<RelationCompactionResult>;
}

#[derive(Clone)]
pub struct TxDB {
    storage: Arc<MoorDB>,
}

impl TxDB {
    pub fn try_open(
        path: Option<&Path>,
        database_config: DatabaseConfig,
    ) -> Result<(Self, bool), DatabaseOpenError> {
        let (storage, fresh) = MoorDB::try_open(path, database_config)?;
        Ok((Self { storage }, fresh))
    }

    /// Mark all relations as fully loaded from their backing providers.
    /// Call this after bulk import operations to enable optimized reads.
    pub fn mark_all_fully_loaded(&self) {
        self.storage.mark_all_fully_loaded();
    }

    /// Wait until the current published state has been committed into Fjall.
    ///
    /// This does not request an fsync or wait for LSM maintenance.
    pub fn wait_for_persistence(&self) -> Result<(), WorldStateError> {
        self.storage
            .wait_for_persistence()
            .map_err(WorldStateError::DatabaseError)
    }
}

impl WorldStateSource for TxDB {
    fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
        let tx = self.storage.start_transaction();
        let tx = api::world_state::DbWorldState { tx };
        Ok(Box::new(tx))
    }

    fn checkpoint(&self) -> Result<(), WorldStateError> {
        // TODO: noop for now... but this should probably do a sync of sequences to disk and make
        //   sure all data is durable.
        Ok(())
    }
}

impl Database for TxDB {
    fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
        let tx = self.storage.start_transaction();
        let tx = api::world_state::DbWorldState { tx };
        Ok(Box::new(tx))
    }

    fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
        self.storage
            .create_snapshot()
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))
    }

    fn create_snapshot_async(&self, callback: SnapshotCallback) -> Result<(), WorldStateError> {
        let storage = self.storage.clone();
        spawn_efficient("moor-snapshot", move || {
            let snapshot_result = storage
                .create_snapshot()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()));

            if let Err(e) = callback(snapshot_result) {
                tracing::error!("Snapshot callback failed: {}", e);
            }
        })
        .map_err(|e| {
            WorldStateError::DatabaseError(format!("Failed to spawn snapshot thread: {e}"))
        })?;
        Ok(())
    }

    fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
        let tx = self.storage.start_transaction();
        let tx = api::world_state::DbWorldState { tx };
        Ok(Box::new(tx))
    }

    fn storage_maintenance_stats(&self) -> Option<StorageMaintenanceStats> {
        Some(self.storage.storage_maintenance_stats())
    }

    fn major_compact(&self) -> Option<Vec<RelationCompactionResult>> {
        Some(self.storage.major_compact_all())
    }

    fn disk_bytes(&self) -> Option<u64> {
        Some(self.storage.usage_bytes() as u64)
    }

    fn stored_property_rows(&self) -> Option<u64> {
        Some(self.storage.stored_property_rows())
    }

    fn compaction_handle(&self) -> Option<Arc<dyn StorageCompactor>> {
        Some(Arc::new(MoorDBCompactor {
            storage: self.storage.clone(),
        }))
    }
}

struct MoorDBCompactor {
    storage: Arc<MoorDB>,
}

impl StorageCompactor for MoorDBCompactor {
    fn disk_bytes(&self) -> u64 {
        self.storage.usage_bytes() as u64
    }

    fn stored_property_rows(&self) -> u64 {
        self.storage.stored_property_rows()
    }

    fn major_compact(&self) -> Vec<RelationCompactionResult> {
        self.storage.major_compact_all()
    }
}
