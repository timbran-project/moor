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

//! Admission and completion tracking for mutually exclusive database maintenance.

use std::sync::Arc;

use moor_common::tasks::SchedulerError;
use parking_lot::{Condvar, Mutex};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum MaintenanceKind {
    Checkpoint,
    StorageCompaction,
}

struct MaintenanceCompletion {
    outcome: Mutex<Option<Result<(), SchedulerError>>>,
    completed: Condvar,
}

/// A generation-specific handle for observing maintenance completion.
#[derive(Clone)]
pub(crate) struct MaintenanceTicket {
    generation: u64,
    kind: MaintenanceKind,
    completion: Arc<MaintenanceCompletion>,
}

impl MaintenanceTicket {
    #[inline]
    pub(crate) fn generation(&self) -> u64 {
        self.generation
    }

    #[inline]
    pub(crate) fn kind(&self) -> MaintenanceKind {
        self.kind
    }

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

struct CoordinatorState {
    accepting: bool,
    next_generation: u64,
    active: Option<MaintenanceTicket>,
}

struct MaintenanceCoordinatorInner {
    state: Mutex<CoordinatorState>,
}

/// Serializes maintenance which must not overlap Fjall snapshot pinning or table rewrites.
#[derive(Clone)]
pub(crate) struct MaintenanceCoordinator {
    inner: Arc<MaintenanceCoordinatorInner>,
}

impl MaintenanceCoordinator {
    pub(crate) fn new() -> Self {
        Self {
            inner: Arc::new(MaintenanceCoordinatorInner {
                state: Mutex::new(CoordinatorState {
                    accepting: true,
                    next_generation: 0,
                    active: None,
                }),
            }),
        }
    }

    pub(crate) fn admit(&self, kind: MaintenanceKind) -> Result<MaintenanceTicket, SchedulerError> {
        let mut state = self.inner.state.lock();
        if !state.accepting {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        if let Some(active) = state.active.as_ref() {
            return Err(match active.kind {
                MaintenanceKind::Checkpoint => SchedulerError::CheckpointInProgress,
                MaintenanceKind::StorageCompaction => SchedulerError::StorageMaintenanceInProgress,
            });
        }

        state.next_generation = state
            .next_generation
            .checked_add(1)
            .expect("Maintenance generation space exhausted");
        let ticket = MaintenanceTicket {
            generation: state.next_generation,
            kind,
            completion: Arc::new(MaintenanceCompletion {
                outcome: Mutex::new(None),
                completed: Condvar::new(),
            }),
        };
        state.active = Some(ticket.clone());
        Ok(ticket)
    }

    pub(crate) fn complete(&self, ticket: &MaintenanceTicket, outcome: Result<(), SchedulerError>) {
        let mut ticket_outcome = ticket.completion.outcome.lock();
        if ticket_outcome.is_some() {
            return;
        }
        *ticket_outcome = Some(outcome);

        let mut state = self.inner.state.lock();
        if state.active.as_ref().is_some_and(|active| {
            active.generation == ticket.generation && active.kind == ticket.kind
        }) {
            state.active = None;
        }
        drop(state);
        ticket.completion.completed.notify_all();
    }

    /// Prevent new maintenance and return the active ticket, if one exists.
    pub(crate) fn close(&self) -> Option<MaintenanceTicket> {
        let mut state = self.inner.state.lock();
        state.accepting = false;
        state.active.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checkpoint_and_compaction_report_the_active_maintenance_kind() {
        let coordinator = MaintenanceCoordinator::new();
        let checkpoint = coordinator.admit(MaintenanceKind::Checkpoint).unwrap();
        assert_eq!(
            coordinator.admit(MaintenanceKind::StorageCompaction).err(),
            Some(SchedulerError::CheckpointInProgress)
        );
        coordinator.complete(&checkpoint, Ok(()));

        let compaction = coordinator
            .admit(MaintenanceKind::StorageCompaction)
            .unwrap();
        assert_eq!(
            coordinator.admit(MaintenanceKind::Checkpoint).err(),
            Some(SchedulerError::StorageMaintenanceInProgress)
        );
        assert_eq!(
            coordinator.admit(MaintenanceKind::StorageCompaction).err(),
            Some(SchedulerError::StorageMaintenanceInProgress)
        );
        coordinator.complete(&compaction, Ok(()));
    }

    #[test]
    fn ticket_preserves_its_generation_outcome() {
        let coordinator = MaintenanceCoordinator::new();
        let ticket = coordinator.admit(MaintenanceKind::Checkpoint).unwrap();
        coordinator.complete(&ticket, Err(SchedulerError::CouldNotStartTask));

        assert_eq!(ticket.wait(), Err(SchedulerError::CouldNotStartTask));
    }

    #[test]
    fn closing_coordinator_rejects_new_work_and_exposes_active_ticket() {
        let coordinator = MaintenanceCoordinator::new();
        let ticket = coordinator.admit(MaintenanceKind::Checkpoint).unwrap();
        let active = coordinator.close().unwrap();

        assert_eq!(active.generation(), ticket.generation());
        assert_eq!(active.kind(), MaintenanceKind::Checkpoint);
        assert!(matches!(
            coordinator.admit(MaintenanceKind::StorageCompaction),
            Err(SchedulerError::SchedulerNotResponding)
        ));
    }
}
