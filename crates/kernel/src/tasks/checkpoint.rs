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
    path::{Path, PathBuf},
    sync::Arc,
    time::{SystemTime, UNIX_EPOCH},
};

use moor_common::tasks::SchedulerError;
use moor_db::Database;
use moor_objdef::{collect_object_definitions, dump_object_definitions};
use parking_lot::{Condvar, Mutex};
use tracing::{error, info};

use crate::config::Config;

type CompletionCallback = Box<dyn FnOnce(u64, Result<(), SchedulerError>) + Send + 'static>;

struct CheckpointCompletion {
    outcome: Mutex<Option<Result<(), SchedulerError>>>,
    completed: Condvar,
}

/// A generation-specific handle for observing checkpoint completion.
#[derive(Clone)]
pub(crate) struct CheckpointTicket {
    generation: u64,
    completion: Arc<CheckpointCompletion>,
}

impl CheckpointTicket {
    #[inline]
    pub(crate) fn generation(&self) -> u64 {
        self.generation
    }

    /// Wait until the checkpoint has either published its final file or failed.
    pub(crate) fn wait(&self) -> Result<(), SchedulerError> {
        let mut outcome = self.completion.outcome.lock();
        loop {
            if let Some(outcome) = outcome.as_ref() {
                return outcome.clone();
            }
            self.completion.completed.wait(&mut outcome);
        }
    }
}

struct ActiveCheckpoint {
    ticket: CheckpointTicket,
}

struct CoordinatorState {
    accepting: bool,
    next_generation: u64,
    active: Option<ActiveCheckpoint>,
}

struct CheckpointCoordinatorInner {
    state: Mutex<CoordinatorState>,
}

/// Owns checkpoint admission and generation-scoped completion state.
#[derive(Clone)]
pub(crate) struct CheckpointCoordinator {
    inner: Arc<CheckpointCoordinatorInner>,
}

impl CheckpointCoordinator {
    pub(crate) fn new() -> Self {
        Self {
            inner: Arc::new(CheckpointCoordinatorInner {
                state: Mutex::new(CoordinatorState {
                    accepting: true,
                    next_generation: 0,
                    active: None,
                }),
            }),
        }
    }

    fn admit(&self) -> Result<CheckpointTicket, SchedulerError> {
        let mut state = self.inner.state.lock();
        if !state.accepting {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        if state.active.is_some() {
            return Err(SchedulerError::CheckpointInProgress);
        }

        state.next_generation = state
            .next_generation
            .checked_add(1)
            .expect("Checkpoint generation space exhausted");
        let ticket = CheckpointTicket {
            generation: state.next_generation,
            completion: Arc::new(CheckpointCompletion {
                outcome: Mutex::new(None),
                completed: Condvar::new(),
            }),
        };
        state.active = Some(ActiveCheckpoint {
            ticket: ticket.clone(),
        });
        Ok(ticket)
    }

    fn complete(&self, ticket: &CheckpointTicket, outcome: Result<(), SchedulerError>) {
        let mut ticket_outcome = ticket.completion.outcome.lock();
        if ticket_outcome.is_some() {
            return;
        }
        *ticket_outcome = Some(outcome);

        let mut state = self.inner.state.lock();
        if state
            .active
            .as_ref()
            .is_some_and(|active| active.ticket.generation == ticket.generation)
        {
            state.active = None;
        }
        drop(state);
        ticket.completion.completed.notify_all();
    }

    /// Prevent new checkpoints and return the active ticket, if one exists.
    pub(crate) fn close(&self) -> Option<CheckpointTicket> {
        let mut state = self.inner.state.lock();
        state.accepting = false;
        state.active.as_ref().map(|active| active.ticket.clone())
    }
}

/// An admitted checkpoint which has not yet been handed to the database.
///
/// Separating admission from launch lets a blocking MOO task enter the suspended
/// queue before an unusually fast snapshot callback can complete.
pub(crate) struct CheckpointJob {
    coordinator: CheckpointCoordinator,
    ticket: CheckpointTicket,
    checkpoint_path: PathBuf,
    launched: bool,
}

impl CheckpointJob {
    #[inline]
    pub(crate) fn generation(&self) -> u64 {
        self.ticket.generation()
    }

    /// Start the snapshot and export. Completion is delivered exactly once.
    pub(crate) fn launch(
        mut self,
        database: &dyn Database,
        callback: CompletionCallback,
    ) -> Result<CheckpointTicket, SchedulerError> {
        let ticket = self.ticket.clone();
        let callback = Arc::new(Mutex::new(Some(callback)));
        let callback_for_snapshot = callback.clone();
        let coordinator = self.coordinator.clone();
        let coordinator_on_error = self.coordinator.clone();
        let ticket_for_snapshot = ticket.clone();
        let ticket_on_error = ticket.clone();
        let checkpoint_path = self.checkpoint_path.clone();

        self.launched = true;
        let output_dir = checkpoint_path
            .parent()
            .expect("Checkpoint path should have an output directory");
        if let Err(e) = fs::create_dir_all(output_dir) {
            error!(?e, "Could not create checkpoint output directory");
            let outcome = Err(SchedulerError::CouldNotStartTask);
            finish_checkpoint(
                &coordinator_on_error,
                &ticket_on_error,
                outcome.clone(),
                &callback,
            );
            return outcome.map(|()| ticket);
        }

        let result = database.create_snapshot_async(Box::new(move |snapshot_result| {
            let outcome = match snapshot_result {
                Ok(loader_client) => perform_export(loader_client.as_ref(), &checkpoint_path),
                Err(e) => {
                    error!(?e, "Could not create snapshot for checkpoint");
                    Err(SchedulerError::CouldNotStartTask)
                }
            };

            finish_checkpoint(
                &coordinator,
                &ticket_for_snapshot,
                outcome,
                &callback_for_snapshot,
            );
            Ok(())
        }));

        if let Err(e) = result {
            error!(?e, "Could not start checkpoint snapshot");
            let outcome = Err(SchedulerError::CouldNotStartTask);
            finish_checkpoint(
                &coordinator_on_error,
                &ticket_on_error,
                outcome.clone(),
                &callback,
            );
            return outcome.map(|()| ticket);
        }

        Ok(ticket)
    }
}

impl Drop for CheckpointJob {
    fn drop(&mut self) {
        if self.launched {
            return;
        }
        self.coordinator
            .complete(&self.ticket, Err(SchedulerError::CouldNotStartTask));
    }
}

fn finish_checkpoint(
    coordinator: &CheckpointCoordinator,
    ticket: &CheckpointTicket,
    outcome: Result<(), SchedulerError>,
    callback: &Mutex<Option<CompletionCallback>>,
) {
    coordinator.complete(ticket, outcome.clone());
    if let Some(callback) = callback.lock().take() {
        callback(ticket.generation(), outcome);
    }
}

/// Reserve a checkpoint generation and its output path.
pub(crate) fn prepare_checkpoint(
    config: &Config,
    coordinator: &CheckpointCoordinator,
) -> Result<CheckpointJob, SchedulerError> {
    let ticket = coordinator.admit()?;

    let Some(output_dir) = config.import_export.output_path.clone() else {
        error!("Cannot checkpoint as output directory not configured");
        coordinator.complete(&ticket, Err(SchedulerError::CouldNotStartTask));
        return Err(SchedulerError::CouldNotStartTask);
    };

    let checkpoint_path = output_dir.join(format!(
        "checkpoint-{}.in-progress",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("Time went backwards")
            .as_secs()
    ));

    Ok(CheckpointJob {
        coordinator: coordinator.clone(),
        ticket,
        checkpoint_path,
        launched: false,
    })
}

fn perform_export(
    loader_client: &dyn moor_common::model::loader::SnapshotInterface,
    checkpoint_path: &Path,
) -> Result<(), SchedulerError> {
    info!("Collecting objects for checkpoint...");
    let objects = collect_object_definitions(loader_client).map_err(|e| {
        error!(?e, "Failed to collect objects for checkpoint");
        SchedulerError::CouldNotStartTask
    })?;
    info!("Dumping objects to {checkpoint_path:?}");
    dump_object_definitions(&objects, checkpoint_path).map_err(|e| {
        error!(error = %e, "Failed to dump objects");
        SchedulerError::CouldNotStartTask
    })?;
    let final_path = checkpoint_path.with_extension("moo");
    fs::rename(checkpoint_path, &final_path).map_err(|e| {
        error!(?e, "Could not rename checkpoint to final path");
        SchedulerError::CouldNotStartTask
    })?;
    info!(?final_path, "Checkpoint written.");

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn duplicate_admission_reports_checkpoint_in_progress() {
        let coordinator = CheckpointCoordinator::new();
        let ticket = coordinator.admit().unwrap();

        assert!(matches!(
            coordinator.admit(),
            Err(SchedulerError::CheckpointInProgress)
        ));

        coordinator.complete(&ticket, Ok(()));
        assert!(coordinator.admit().is_ok());
    }

    #[test]
    fn ticket_preserves_its_generation_outcome() {
        let coordinator = CheckpointCoordinator::new();
        let ticket = coordinator.admit().unwrap();
        coordinator.complete(&ticket, Err(SchedulerError::CouldNotStartTask));

        assert_eq!(ticket.wait(), Err(SchedulerError::CouldNotStartTask));
    }

    #[test]
    fn closing_coordinator_rejects_new_work_and_exposes_active_ticket() {
        let coordinator = CheckpointCoordinator::new();
        let ticket = coordinator.admit().unwrap();
        let active = coordinator.close().unwrap();

        assert_eq!(active.generation(), ticket.generation());
        assert!(matches!(
            coordinator.admit(),
            Err(SchedulerError::SchedulerNotResponding)
        ));
    }
}
