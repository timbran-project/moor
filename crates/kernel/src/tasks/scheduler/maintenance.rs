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

//! Checkpoint and compaction integration: preparation, launch, and waiter completion.
//!
//! Jobs retain their maintenance ownership outside the lifecycle lock. Completion acquires that
//! lock and checks the wait generation before removing a continuation. Shutdown completion sends
//! a terminal cancellation instead of dispatching more work. The job implementations remain in
//! the checkpoint and storage_compaction modules.

use crate::tasks::{
    checkpoint::{CheckpointJob, CheckpointTicket, prepare_checkpoint},
    registry::WakeCondition,
    scheduler::{ResumeAction, Scheduler, SchedulerState},
    storage_compaction::{
        StorageCompactionJob, compaction_failure_to_var, compaction_results_to_var,
        prepare_storage_compaction,
    },
};
use moor_common::tasks::{SchedulerError, SchedulerError::TaskAbortedCancelled, TaskId};
use moor_db::DatabaseRelation;
use moor_var::v_bool_int;
use tracing::{debug, error};

impl Scheduler {
    pub(crate) fn handle_checkpoint_task_completion(
        &self,
        task_id: TaskId,
        generation: u64,
        outcome: Result<(), SchedulerError>,
    ) {
        let mut lc = self.lifecycle.lock();
        let waiting_for_generation = lc.task_q.suspended.get(task_id).is_some_and(
            |task| matches!(task.wake_condition, WakeCondition::Checkpoint(g) if g == generation),
        );
        if !waiting_for_generation {
            debug!(task_id, generation, "Checkpoint waiter no longer suspended");
            return;
        }

        let Some(suspended) = lc.task_q.suspended.remove_task(task_id) else {
            return;
        };
        if lc.state != SchedulerState::Running {
            lc.task_q.suspended.enqueue_dependents_for(task_id);
            lc.task_q.send_task_result_direct(
                suspended.registration,
                suspended.record.result_sender,
                Err(TaskAbortedCancelled),
            );
            return;
        }

        let succeeded = outcome.is_ok();
        if let Err(error) = outcome {
            error!(?error, task_id, generation, "Blocking checkpoint failed");
        }
        if let Err(error) = lc.wake_suspended_task(
            suspended,
            ResumeAction::Return(v_bool_int(succeeded)),
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        ) {
            error!(
                ?error,
                task_id, generation, "Could not resume checkpoint waiter"
            );
        }
    }

    pub(crate) fn handle_storage_compaction_task_completion(
        &self,
        task_id: TaskId,
        generation: u64,
        relations: &[DatabaseRelation],
        outcome: Result<Vec<moor_db::RelationCompactionResult>, SchedulerError>,
    ) {
        let mut lc = self.lifecycle.lock();
        let waiting_for_generation = lc.task_q.suspended.get(task_id).is_some_and(|task| {
            matches!(task.wake_condition, WakeCondition::StorageCompaction(g) if g == generation)
        });
        if !waiting_for_generation {
            debug!(
                task_id,
                generation, "Storage compaction waiter no longer suspended"
            );
            return;
        }

        let Some(suspended) = lc.task_q.suspended.remove_task(task_id) else {
            return;
        };
        if lc.state != SchedulerState::Running {
            lc.task_q.suspended.enqueue_dependents_for(task_id);
            lc.task_q.send_task_result_direct(
                suspended.registration,
                suspended.record.result_sender,
                Err(TaskAbortedCancelled),
            );
            return;
        }

        let return_value = match outcome {
            Ok(results) => compaction_results_to_var(&results),
            Err(error) => {
                error!(?error, task_id, generation, "Storage compaction failed");
                compaction_failure_to_var(relations, &error)
            }
        };
        if let Err(error) = lc.wake_suspended_task(
            suspended,
            ResumeAction::Return(return_value),
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        ) {
            error!(
                ?error,
                task_id, generation, "Could not resume storage compaction waiter"
            );
        }
    }

    pub(crate) fn prepare_checkpoint_job(&self) -> Result<CheckpointJob, SchedulerError> {
        prepare_checkpoint(self.config.as_ref(), &self.maintenance_coordinator)
    }

    pub(crate) fn prepare_storage_compaction_job(
        &self,
        relations: Vec<DatabaseRelation>,
    ) -> Result<StorageCompactionJob, SchedulerError> {
        prepare_storage_compaction(&self.maintenance_coordinator, relations)
    }

    pub(crate) fn launch_checkpoint_job(
        &self,
        job: CheckpointJob,
        waiting_task: Option<TaskId>,
    ) -> Result<CheckpointTicket, SchedulerError> {
        let callback_scheduler = self.clone();
        job.launch(
            self.database.as_ref(),
            Box::new(move |generation, outcome| {
                let Some(task_id) = waiting_task else {
                    if let Err(error) = outcome {
                        error!(?error, generation, "Checkpoint export failed");
                    }
                    return;
                };
                callback_scheduler.handle_checkpoint_task_completion(task_id, generation, outcome);
            }),
        )
    }

    pub(crate) fn launch_storage_compaction_job(
        &self,
        job: StorageCompactionJob,
        waiting_task: TaskId,
    ) -> Result<(), SchedulerError> {
        let callback_scheduler = self.clone();
        let relations = job.relations().to_vec();
        job.launch(
            self.database.clone(),
            Box::new(move |generation, outcome| {
                callback_scheduler.handle_storage_compaction_task_completion(
                    waiting_task,
                    generation,
                    &relations,
                    outcome,
                );
            }),
        )
        .map(|_| ())
    }

    /// Admit and launch a checkpoint without waiting for its export to finish.
    pub(crate) fn begin_checkpoint(&self) -> Result<CheckpointTicket, SchedulerError> {
        if self.state() != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        let job = self.prepare_checkpoint_job()?;
        self.launch_checkpoint_job(job, None)
    }

    pub(crate) fn checkpoint(&self) -> Result<(), SchedulerError> {
        self.begin_checkpoint().map(|_| ())
    }
}
