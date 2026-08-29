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
    fs,
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Instant, SystemTime, UNIX_EPOCH},
};

use moor_common::tasks::SchedulerError;
use moor_db::{CompactionDecision, Database};
use moor_objdef::{ScanCounts, collect_object_definitions_with_counts, dump_object_definitions};
use tracing::{debug, error, info, warn};

use crate::config::Config;

/// Name of the file written into a completed checkpoint directory describing the export.
pub const CHECKPOINT_MANIFEST_FILE: &str = "manifest.json";

enum CheckpointCompletion {
    FireAndForget,
    Blocking(std::sync::mpsc::Sender<Result<(), SchedulerError>>),
}

/// Determine whether the checkpoint should block until the export has completed.
pub enum CheckpointMode {
    NonBlocking,
    Blocking,
}

fn epoch_secs(at: SystemTime) -> u64 {
    at.duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default()
}

/// Kick off a checkpoint operation, optionally waiting for completion.
pub fn start_checkpoint(
    database: &dyn Database,
    config: &Config,
    _version: &semver::Version,
    checkpoint_flag: Arc<AtomicBool>,
    mode: CheckpointMode,
) -> Result<(), SchedulerError> {
    if checkpoint_flag
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        // Distinct from success: the caller asked for an export and is not getting one. Returning
        // Ok(()) here made `dump_database()` answer 1 for work it had discarded, which is how a
        // stale export came to look like a fresh one.
        warn!("Checkpoint already in progress, skipping duplicate request");
        return Err(SchedulerError::CheckpointInProgress);
    }

    let Some(output_dir) = config.import_export.output_path.clone() else {
        checkpoint_flag.store(false, Ordering::SeqCst);
        error!("Cannot checkpoint as output directory not configured");
        return Err(SchedulerError::CouldNotStartTask);
    };

    if let Err(e) = fs::create_dir_all(&output_dir) {
        checkpoint_flag.store(false, Ordering::SeqCst);
        error!(?e, "Could not create checkpoint output directory");
        return Err(SchedulerError::CouldNotStartTask);
    }

    let snapshot_time = SystemTime::now();
    let checkpoint_path = output_dir.join(format!(
        "checkpoint-{}.in-progress",
        epoch_secs(snapshot_time)
    ));

    let (completion_handler, completion_receiver) = match mode {
        CheckpointMode::NonBlocking => (CheckpointCompletion::FireAndForget, None),
        CheckpointMode::Blocking => {
            let (tx, rx) = std::sync::mpsc::channel();
            (CheckpointCompletion::Blocking(tx), Some(rx))
        }
    };

    let checkpoint_flag_on_error = checkpoint_flag.clone();
    let auto_compaction = config
        .database
        .as_ref()
        .map(|db| db.auto_compaction.clone())
        .unwrap_or_default();
    let compaction_target = database.compaction_handle();
    let result = database.create_snapshot_async(Box::new(move |snapshot_result| {
        let outcome = match snapshot_result {
            Ok(loader_client) => {
                let exported =
                    perform_export(loader_client.as_ref(), &checkpoint_path, snapshot_time);

                // Drop the snapshot before considering compaction. Not because compaction would
                // otherwise be futile — it would not be — but because the two are both full passes
                // over the database and there is no reason to overlap them.
                drop(loader_client);

                if let Ok(counts) = &exported {
                    maybe_auto_compact(compaction_target.as_deref(), &auto_compaction, counts);
                }
                exported.map(|_| ())
            }
            Err(e) => {
                error!(?e, "Could not create snapshot for checkpoint");
                Err(SchedulerError::CouldNotStartTask)
            }
        };

        // Released only now, so a checkpoint cannot start while compaction is still running.
        checkpoint_flag.store(false, Ordering::SeqCst);

        match completion_handler {
            CheckpointCompletion::FireAndForget => {
                if let Err(e) = &outcome {
                    error!(?e, "Checkpoint export failed");
                }
            }
            CheckpointCompletion::Blocking(ref sender) => {
                if sender.send(outcome).is_err() {
                    error!("Failed to send checkpoint completion result");
                }
            }
        }

        Ok(())
    }));

    if result.is_err() {
        checkpoint_flag_on_error.store(false, Ordering::SeqCst);
        return Err(SchedulerError::CouldNotStartTask);
    }

    if let Some(receiver) = completion_receiver {
        receiver.recv().unwrap_or_else(|_| {
            error!("Failed to receive checkpoint completion result");
            Err(SchedulerError::CouldNotStartTask)
        })
    } else {
        Ok(())
    }
}

/// Render the manifest recorded alongside an export.
///
/// The directory name carries the snapshot instant while its mtime carries the completion instant,
/// and the two can be many minutes apart, so anything reading by mtime sees the export as newer
/// than its contents. This states both unambiguously, along with what the scan saw.
fn manifest_json(
    snapshot_time: SystemTime,
    completed_time: SystemTime,
    scan_duration_ms: u128,
    write_duration_ms: u128,
    counts: &ScanCounts,
) -> String {
    let snapshot_epoch = epoch_secs(snapshot_time);
    let completed_epoch = epoch_secs(completed_time);
    format!(
        concat!(
            "{{\n",
            "  \"snapshot_epoch\": {},\n",
            "  \"completed_epoch\": {},\n",
            "  \"scan_duration_ms\": {},\n",
            "  \"write_duration_ms\": {},\n",
            "  \"objects\": {},\n",
            "  \"verbs\": {},\n",
            "  \"properties\": {},\n",
            "  \"property_overrides\": {},\n",
            "  \"live_property_bytes\": {},\n",
            "  \"live_property_rows\": {}\n",
            "}}\n"
        ),
        snapshot_epoch,
        completed_epoch,
        scan_duration_ms,
        write_duration_ms,
        counts.objects,
        counts.verbs,
        counts.properties,
        counts.property_overrides,
        // `null` when the snapshot did not measure it, so the fields are always present.
        counts
            .live_property_bytes
            .map_or_else(|| "null".to_string(), |b| b.to_string()),
        counts
            .live_property_rows
            .map_or_else(|| "null".to_string(), |r| r.to_string()),
    )
}

/// Consider reclaiming dead space now that the checkpoint's snapshot has been released.
///
/// The checkpoint has just counted every live property row, so this is the one moment when a
/// live-data figure is available to compare against what the engine actually stores — dead space is
/// otherwise invisible, since fjall's cheap counters are per-row tombstone counts and the case that
/// prompted this hid 94.8 MB behind two tombstones. Nothing here runs unless the ratio says the
/// rewrite is worth it, because `major_compact` rewrites every table and blocks.
fn maybe_auto_compact(
    compactor: Option<&dyn moor_db::StorageCompactor>,
    config: &moor_db::AutoCompactionConfig,
    counts: &ScanCounts,
) {
    let Some(compactor) = compactor else {
        return;
    };
    let Some(live_rows) = counts.live_property_rows else {
        // The snapshot did not count live rows, so there is no ratio to test. Staying quiet
        // rather than compacting blind.
        return;
    };

    let stored_rows = compactor.stored_property_rows();
    let decision = config.decide(live_rows, stored_rows);
    match decision {
        CompactionDecision::Compact { amplification_pct } => {
            info!(
                live_rows,
                stored_rows,
                amplification_pct,
                disk_bytes = compactor.disk_bytes(),
                "Post-checkpoint compaction: reclaiming superseded data"
            );
            let results = compactor.major_compact();
            let reclaimed: u64 = results.iter().map(|r| r.bytes_reclaimed()).sum();
            let failures = results.iter().filter(|r| r.error.is_some()).count();
            if failures > 0 {
                warn!(
                    failures,
                    reclaimed, "Post-checkpoint compaction finished with errors"
                );
            } else {
                info!(reclaimed, "Post-checkpoint compaction complete");
            }
        }
        // Logged so that "why is my database still huge" has an answer in the log.
        other => debug!(
            live_rows,
            stored_rows,
            ?other,
            "Not compacting after checkpoint"
        ),
    }
}

fn perform_export(
    loader_client: &dyn moor_common::model::loader::SnapshotInterface,
    checkpoint_path: &Path,
    snapshot_time: SystemTime,
) -> Result<ScanCounts, SchedulerError> {
    info!("Collecting objects for checkpoint...");
    let scan_started = Instant::now();
    let (objects, counts) = collect_object_definitions_with_counts(loader_client).map_err(|e| {
        error!(?e, "Failed to collect objects for checkpoint");
        SchedulerError::CouldNotStartTask
    })?;
    let scan_duration = scan_started.elapsed();

    info!("Dumping objects to {checkpoint_path:?}");
    let write_started = Instant::now();
    dump_object_definitions(&objects, checkpoint_path).map_err(|e| {
        error!(error = %e, "Failed to dump objects");
        SchedulerError::CouldNotStartTask
    })?;
    let write_duration = write_started.elapsed();

    // Write the manifest before the rename, so a completed `.moo` directory always has one.
    let manifest = manifest_json(
        snapshot_time,
        SystemTime::now(),
        scan_duration.as_millis(),
        write_duration.as_millis(),
        &counts,
    );
    if let Err(e) = fs::write(checkpoint_path.join(CHECKPOINT_MANIFEST_FILE), manifest) {
        // A missing manifest does not invalidate the export, so do not fail the checkpoint for it.
        warn!(?e, "Could not write checkpoint manifest");
    }

    let final_path = checkpoint_path.with_extension("moo");
    fs::rename(checkpoint_path, &final_path).map_err(|e| {
        error!(?e, "Could not rename checkpoint to final path");
        SchedulerError::CouldNotStartTask
    })?;
    info!(
        ?final_path,
        scan = ?scan_duration,
        write = ?write_duration,
        "Checkpoint written."
    );

    Ok(counts)
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_common::model::{
        WorldState, WorldStateError, WorldStateSource,
        loader::{LoaderInterface, SnapshotInterface},
    };
    use moor_db::{Database, GCInterface, SnapshotCallback};
    use std::time::Duration;

    /// A Database that never produces a snapshot, so `start_checkpoint` gets as far as claiming
    /// the flag and no further. Enough to test the concurrency guard without a real world state.
    struct NoSnapshotDatabase;

    impl WorldStateSource for NoSnapshotDatabase {
        fn new_world_state(&self) -> Result<Box<dyn WorldState>, WorldStateError> {
            unimplemented!("not needed for checkpoint guard tests")
        }
        fn checkpoint(&self) -> Result<(), WorldStateError> {
            Ok(())
        }
    }

    impl Database for NoSnapshotDatabase {
        fn loader_client(&self) -> Result<Box<dyn LoaderInterface>, WorldStateError> {
            unimplemented!("not needed for checkpoint guard tests")
        }
        fn create_snapshot(&self) -> Result<Box<dyn SnapshotInterface>, WorldStateError> {
            Err(WorldStateError::DatabaseError("no snapshot".to_string()))
        }
        fn create_snapshot_async(
            &self,
            _callback: SnapshotCallback,
        ) -> Result<(), WorldStateError> {
            // Never invoke the callback: the checkpoint stays "in flight" and holds the flag,
            // which is exactly the state a duplicate request has to be told about.
            Ok(())
        }
        fn gc_interface(&self) -> Result<Box<dyn GCInterface>, WorldStateError> {
            unimplemented!("not needed for checkpoint guard tests")
        }
    }

    fn config_with_output(dir: &Path) -> Config {
        let mut config = Config::default();
        config.import_export.output_path = Some(dir.to_path_buf());
        config
    }

    /// The regression this whole finding turns on: a checkpoint requested while one is running
    /// must report a distinct outcome, not `Ok(())`. Returning success there is what made
    /// `dump_database()` answer 1 for work it had thrown away.
    #[test]
    fn duplicate_checkpoint_is_refused_rather_than_reported_as_success() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = NoSnapshotDatabase;
        let config = config_with_output(tmpdir.path());
        let version = semver::Version::new(0, 1, 0);
        let flag = Arc::new(AtomicBool::new(false));

        // First request claims the flag and leaves the export "in flight".
        let first = start_checkpoint(
            &db,
            &config,
            &version,
            flag.clone(),
            CheckpointMode::NonBlocking,
        );
        assert!(first.is_ok(), "first checkpoint should start: {first:?}");
        assert!(flag.load(Ordering::SeqCst), "flag should be held");

        // Second request must say so, in both modes — the early return happens before the
        // blocking channel is built, so `dump_database(1)` must not silently return success.
        for mode in [CheckpointMode::NonBlocking, CheckpointMode::Blocking] {
            let duplicate = start_checkpoint(&db, &config, &version, flag.clone(), mode);
            assert_eq!(
                duplicate,
                Err(SchedulerError::CheckpointInProgress),
                "a duplicate checkpoint request must be distinguishable from success"
            );
        }

        // And once the flag clears, a checkpoint can start again.
        flag.store(false, Ordering::SeqCst);
        let after = start_checkpoint(
            &db,
            &config,
            &version,
            flag.clone(),
            CheckpointMode::NonBlocking,
        );
        assert!(after.is_ok(), "checkpoint should start again: {after:?}");
    }

    /// A missing output directory is a real error, and must stay distinct from the skip.
    #[test]
    fn unconfigured_output_is_not_reported_as_in_progress() {
        let db = NoSnapshotDatabase;
        let config = Config::default(); // no output_path
        let version = semver::Version::new(0, 1, 0);
        let flag = Arc::new(AtomicBool::new(false));

        let result = start_checkpoint(
            &db,
            &config,
            &version,
            flag.clone(),
            CheckpointMode::NonBlocking,
        );

        assert_eq!(result, Err(SchedulerError::CouldNotStartTask));
        assert!(
            !flag.load(Ordering::SeqCst),
            "the flag must be released when the checkpoint cannot start"
        );
    }

    /// Records what was asked of it, so the decision can be observed without a real database.
    struct SpyCompactor {
        stored_rows: u64,
        compactions: std::sync::atomic::AtomicUsize,
    }

    impl SpyCompactor {
        fn new(stored_rows: u64) -> Self {
            Self {
                stored_rows,
                compactions: std::sync::atomic::AtomicUsize::new(0),
            }
        }
        fn count(&self) -> usize {
            self.compactions.load(Ordering::SeqCst)
        }
    }

    impl moor_db::StorageCompactor for SpyCompactor {
        fn disk_bytes(&self) -> u64 {
            // Only logged, never used in the decision.
            783 * 1024 * 1024
        }
        fn stored_property_rows(&self) -> u64 {
            self.stored_rows
        }
        fn major_compact(&self) -> Vec<moor_db::RelationCompactionResult> {
            self.compactions.fetch_add(1, Ordering::SeqCst);
            vec![moor_db::RelationCompactionResult {
                relation: "object_propvalues",
                bytes_before: 783 * 1024 * 1024,
                bytes_after: 783 * 1024 * 1024 / 4,
                error: None,
            }]
        }
    }

    fn counts_with_live_rows(live: Option<u64>) -> ScanCounts {
        ScanCounts {
            objects: 7747,
            verbs: 6835,
            properties: 7283,
            property_overrides: 39833,
            live_property_bytes: Some(136_314_880),
            live_property_rows: live,
        }
    }

    /// The situation the investigation found: most of the stored rows are superseded versions.
    #[test]
    fn auto_compaction_runs_when_dead_space_dominates() {
        let compactor = SpyCompactor::new(566_000);
        let config = moor_db::AutoCompactionConfig::default();

        maybe_auto_compact(
            Some(&compactor),
            &config,
            &counts_with_live_rows(Some(94_000)),
        );

        assert_eq!(
            compactor.count(),
            1,
            "6x amplification on a large database should compact"
        );
    }

    /// A healthy database must not be rewritten on every checkpoint — that would be worse than the
    /// problem being solved.
    #[test]
    fn auto_compaction_leaves_a_healthy_database_alone() {
        let compactor = SpyCompactor::new(500_000);
        let config = moor_db::AutoCompactionConfig::default();

        maybe_auto_compact(
            Some(&compactor),
            &config,
            &counts_with_live_rows(Some(400_000)),
        );

        assert_eq!(
            compactor.count(),
            0,
            "1.25x amplification is normal for an LSM tree and must not trigger a rewrite"
        );
    }

    #[test]
    fn auto_compaction_respects_the_disable_switch() {
        let compactor = SpyCompactor::new(10_000_000);
        let config = moor_db::AutoCompactionConfig {
            after_checkpoint: false,
            ..Default::default()
        };

        maybe_auto_compact(
            Some(&compactor),
            &config,
            &counts_with_live_rows(Some(1_000)),
        );

        assert_eq!(compactor.count(), 0, "disabled config must not compact");
    }

    /// A small database must not be rewritten, however bad its ratio looks — a fresh server would
    /// otherwise compact on every checkpoint.
    #[test]
    fn auto_compaction_leaves_a_small_database_alone() {
        let compactor = SpyCompactor::new(8_000);
        let config = moor_db::AutoCompactionConfig::default();

        maybe_auto_compact(
            Some(&compactor),
            &config,
            &counts_with_live_rows(Some(1_000)),
        );

        assert_eq!(
            compactor.count(),
            0,
            "8x amplification on a trivially small database is not worth a rewrite"
        );
    }

    /// Without a live measurement there is no ratio, and compacting blind on every checkpoint is
    /// exactly the behaviour this design set out to avoid.
    #[test]
    fn auto_compaction_does_nothing_without_a_live_measurement() {
        let compactor = SpyCompactor::new(566_000);
        let config = moor_db::AutoCompactionConfig::default();

        maybe_auto_compact(Some(&compactor), &config, &counts_with_live_rows(None));

        assert_eq!(
            compactor.count(),
            0,
            "an unmeasured scan must not trigger a blind full-database rewrite"
        );
    }

    #[test]
    fn manifest_records_both_instants_and_counts() {
        let snapshot = UNIX_EPOCH + Duration::from_secs(1_787_984_276);
        let completed = snapshot + Duration::from_secs(722);
        let counts = counts_with_live_rows(Some(94_216));

        let manifest = manifest_json(snapshot, completed, 713_000, 9_600, &counts);

        assert!(manifest.contains("\"snapshot_epoch\": 1787984276"));
        assert!(manifest.contains("\"completed_epoch\": 1787984998"));
        assert!(manifest.contains("\"scan_duration_ms\": 713000"));
        assert!(manifest.contains("\"write_duration_ms\": 9600"));
        assert!(manifest.contains("\"objects\": 7747"));
        assert!(manifest.contains("\"property_overrides\": 39833"));
        assert!(manifest.contains("\"live_property_bytes\": 136314880"));
        assert!(manifest.contains("\"live_property_rows\": 94216"));

        // Must be parseable as JSON by anything reading the export.
        let parsed: serde_json::Value = serde_json::from_str(&manifest).expect("valid JSON");
        assert_eq!(parsed["snapshot_epoch"], 1_787_984_276u64);
        assert_eq!(parsed["completed_epoch"], 1_787_984_998u64);
        assert_eq!(parsed["verbs"], 6835);
    }
}
