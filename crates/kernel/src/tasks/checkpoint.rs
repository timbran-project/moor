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
use moor_db::Database;
use moor_objdef::{ScanCounts, collect_object_definitions_with_counts, dump_object_definitions};
use tracing::{error, info, warn};

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
    let result = database.create_snapshot_async(Box::new(move |snapshot_result| {
        let outcome = match snapshot_result {
            Ok(loader_client) => {
                perform_export(loader_client.as_ref(), &checkpoint_path, snapshot_time)
            }
            Err(e) => {
                error!(?e, "Could not create snapshot for checkpoint");
                Err(SchedulerError::CouldNotStartTask)
            }
        };

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
            "  \"property_overrides\": {}\n",
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
    )
}

fn perform_export(
    loader_client: &dyn moor_common::model::loader::SnapshotInterface,
    checkpoint_path: &Path,
    snapshot_time: SystemTime,
) -> Result<(), SchedulerError> {
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

    Ok(())
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

    #[test]
    fn manifest_records_both_instants_and_counts() {
        let snapshot = UNIX_EPOCH + Duration::from_secs(1_787_984_276);
        let completed = snapshot + Duration::from_secs(722);
        let counts = ScanCounts {
            objects: 7747,
            verbs: 6835,
            properties: 7283,
            property_overrides: 39833,
        };

        let manifest = manifest_json(snapshot, completed, 713_000, 9_600, &counts);

        assert!(manifest.contains("\"snapshot_epoch\": 1787984276"));
        assert!(manifest.contains("\"completed_epoch\": 1787984998"));
        assert!(manifest.contains("\"scan_duration_ms\": 713000"));
        assert!(manifest.contains("\"write_duration_ms\": 9600"));
        assert!(manifest.contains("\"objects\": 7747"));
        assert!(manifest.contains("\"property_overrides\": 39833"));

        // Must be parseable as JSON by anything reading the export.
        let parsed: serde_json::Value = serde_json::from_str(&manifest).expect("valid JSON");
        assert_eq!(parsed["snapshot_epoch"], 1_787_984_276u64);
        assert_eq!(parsed["completed_epoch"], 1_787_984_998u64);
        assert_eq!(parsed["verbs"], 6835);
    }
}
