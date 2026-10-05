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

//! Suspension and input transitions retain active membership during session I/O.
//! The lifecycle mutex protects the final move into suspended storage.

use crate::tasks::task_control::CommittedBoundary;
use crate::{
    tasks::{
        TaskNotification,
        scheduler::{Scheduler, SchedulerState},
        storage_compaction::compaction_failure_to_var,
        task::Task,
        task_q::{RunningTaskPhase, WakeCondition},
        workers::WorkerRequest,
    },
    vm::TaskSuspend,
};
use moor_common::{
    tasks::{
        SchedulerError,
        SchedulerError::{TaskAbortedCancelled, TaskAbortedError},
        TaskId,
    },
    util::Deadline,
};
use moor_db::DatabaseRelation;
use moor_var::{List, Obj, Symbol, Var, v_bool_int};
use tracing::{debug, error, warn};
use uuid::Uuid;

impl Scheduler {
    pub(crate) fn handle_task_suspend(
        &self,
        task_id: TaskId,
        wake_condition: TaskSuspend,
        task: Box<Task>,
        boundary: CommittedBoundary,
    ) {
        // Keep the task visible while committing the session. The final move from
        // active to suspended is performed under one lifecycle lock acquisition.
        let session = {
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Discarding suspension request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
                if let Some(task) = lc.task_q.active.get(&task_id) {
                    task.control.request_cancel();
                }
                if lc.task_q.active.contains_key(&task_id) {
                    lc.task_q
                        .send_task_result(task_id, Err(TaskAbortedCancelled));
                }
                return;
            }
            let Some(tc) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for suspend request");
                return;
            };
            if !boundary.belongs_to(&tc.control) {
                warn!(task_id, "Ignoring a boundary from a replaced task attempt");
                return;
            }
            if tc.phase != RunningTaskPhase::Running {
                warn!(task_id, phase = ?tc.phase, "Task already transitioning");
                return;
            }
            tc.phase = RunningTaskPhase::Suspending;
            tc.session.clone()
        };

        // Session commit (potential I/O) outside the lock.
        if let Err(error) = session.commit() {
            error!(
                task_id,
                boundary = "suspend",
                ?error,
                "Session commit failed after world-state commit; output may be lost"
            );
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            lc.discard_pending_sends(task_id);
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        if !lc
            .task_q
            .active
            .get(&task_id)
            .is_some_and(|active| boundary.belongs_to(&active.control))
        {
            debug!(
                task_id,
                "Ignoring a boundary from a missing or replaced task attempt"
            );
            return;
        }
        if lc.state != SchedulerState::Running {
            debug!(task_id, "Cancelling suspension completed during shutdown");
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
            if let Some(task) = lc.task_q.active.get(&task_id) {
                task.control.request_cancel();
            }
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }
        let Some(tc) = lc.task_q.active.get(&task_id) else {
            debug!(task_id, "Task removed while suspension was committing");
            return;
        };
        if tc.phase != RunningTaskPhase::Suspending {
            warn!(task_id, phase = ?tc.phase, "Task suspension phase changed unexpectedly");
            return;
        }
        if !boundary.finish() {
            lc.task_q.remove_message_queue(task_id);
            return lc
                .task_q
                .send_task_result(task_id, Err(TaskAbortedCancelled));
        }
        lc.flush_pending_sends(task_id);

        // And insert into the suspended list.
        let mut checkpoint_job = None;
        let mut storage_compaction_job = None;
        let wake_condition = match wake_condition {
            TaskSuspend::Never => WakeCondition::Never,
            TaskSuspend::Timed(t) => WakeCondition::Time(Deadline::from_now(t).instant()),
            TaskSuspend::WaitTask(task_id) => WakeCondition::Task(task_id),
            TaskSuspend::Commit(return_value) => WakeCondition::Immediate(Some(return_value)),
            TaskSuspend::WorkerRequest(worker_type, args, timeout) => {
                let worker_request_id = Uuid::new_v4();
                // Send request to the worker process.
                // If no workers are configured, abort the task.
                let Some(workers_sender) = self.worker_request_send.as_ref() else {
                    warn!("No workers configured for scheduler; aborting task");
                    return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
                };

                if let Err(e) = workers_sender.send(WorkerRequest::Request {
                    request_id: worker_request_id,
                    request_type: worker_type,
                    authority_principal: task.authority_principal(),
                    request: args,
                    timeout,
                }) {
                    error!(?e, "Could not send worker request; aborting task");
                    return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
                }

                WakeCondition::Worker(worker_request_id)
            }
            TaskSuspend::RecvMessages(Some(duration)) => {
                // Check if there are already messages in the queue after commit
                let messages = lc.task_q.drain_messages(task_id);
                if !messages.is_empty() {
                    // Messages available — wake immediately with them
                    WakeCondition::Immediate(Some(List::from_iter(messages).into()))
                } else {
                    // No messages — suspend with deadline, wake on message
                    // arrival or timeout
                    WakeCondition::TaskMessage(Deadline::from_now(duration).instant())
                }
            }
            TaskSuspend::RecvMessages(None) => {
                // Immediate fast path — drain queue and wake immediately
                let messages = lc.task_q.drain_messages(task_id);
                WakeCondition::Immediate(Some(List::from_iter(messages).into()))
            }
            TaskSuspend::Checkpoint => match self.prepare_checkpoint_job() {
                Ok(job) => {
                    let generation = job.generation();
                    checkpoint_job = Some(job);
                    WakeCondition::Checkpoint(generation)
                }
                Err(error) => {
                    error!(?error, task_id, "Could not start blocking checkpoint");
                    WakeCondition::Immediate(Some(v_bool_int(false)))
                }
            },
            TaskSuspend::StorageCompaction(relation_names) => {
                let relations = relation_names
                    .iter()
                    .filter_map(|name| DatabaseRelation::named(name.as_str()))
                    .collect::<Vec<_>>();
                if relations.len() != relation_names.len() {
                    error!(
                        task_id,
                        "Storage compaction contained an invalid relation name"
                    );
                    WakeCondition::Immediate(Some(compaction_failure_to_var(
                        &relations,
                        &SchedulerError::CouldNotStartTask,
                    )))
                } else {
                    match self.prepare_storage_compaction_job(relations.clone()) {
                        Ok(job) => {
                            let generation = job.generation();
                            storage_compaction_job = Some(job);
                            WakeCondition::StorageCompaction(generation)
                        }
                        Err(error) => {
                            error!(?error, task_id, "Could not start storage compaction");
                            WakeCondition::Immediate(Some(compaction_failure_to_var(
                                &relations, &error,
                            )))
                        }
                    }
                }
            }
        };

        if !matches!(wake_condition, WakeCondition::Immediate(_))
            && let Some(sender) = lc
                .task_q
                .active
                .get(&task_id)
                .and_then(|tc| tc.result_sender.as_ref())
        {
            let _ = sender.send((task_id, Ok(TaskNotification::Suspended)));
        }

        let needs_timer_wake = matches!(
            wake_condition,
            WakeCondition::Time(_) | WakeCondition::Retry(_) | WakeCondition::TaskMessage(_)
        );

        let tc = lc
            .task_q
            .active
            .remove(&task_id)
            .expect("transitioning task disappeared while lifecycle lock was held");
        lc.task_q
            .suspended
            .add_task(wake_condition, task, tc.session, tc.result_sender);

        drop(lc);
        if let Some(job) = checkpoint_job {
            let _ = self.launch_checkpoint_job(job, Some(task_id));
        }
        if let Some(job) = storage_compaction_job {
            let _ = self.launch_storage_compaction_job(job, task_id);
        }

        // Wake the timer thread so it can recompute its sleep duration for the
        // newly-inserted deadline.
        if needs_timer_wake {
            self.wake_timer_thread();
        }
    }

    pub(crate) fn handle_task_request_input(
        &self,
        task_id: TaskId,
        task: Box<Task>,
        input_player: Obj,
        metadata: Option<Vec<(Symbol, Var)>>,
        boundary: CommittedBoundary,
    ) {
        let input_request_id = Uuid::new_v4();

        // Keep the task visible while committing output and registering the input
        // request. The active-to-suspended move remains atomic under the lock.
        let session = {
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Discarding input request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
                if let Some(task) = lc.task_q.active.get(&task_id) {
                    task.control.request_cancel();
                }
                if lc.task_q.active.contains_key(&task_id) {
                    lc.task_q
                        .send_task_result(task_id, Err(TaskAbortedCancelled));
                }
                return;
            }
            let Some(tc) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for input request");
                return;
            };
            if !boundary.belongs_to(&tc.control) {
                warn!(task_id, "Ignoring a boundary from a replaced task attempt");
                return;
            }
            if tc.phase != RunningTaskPhase::Running {
                warn!(task_id, phase = ?tc.phase, "Task already transitioning");
                return;
            }
            tc.phase = RunningTaskPhase::RequestingInput;
            tc.session.clone()
        };

        // Session commit (potential I/O) outside the lock — flushes output
        // up to the prompt point.
        if let Err(error) = session.commit() {
            error!(
                task_id,
                boundary = "input suspend",
                ?error,
                "Session commit failed after world-state commit; output may be lost"
            );
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            lc.discard_pending_sends(task_id);
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        {
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Cancelling input request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
                if let Some(task) = lc.task_q.active.get(&task_id) {
                    task.control.request_cancel();
                }
                if lc.task_q.active.contains_key(&task_id) {
                    lc.task_q
                        .send_task_result(task_id, Err(TaskAbortedCancelled));
                }
                return;
            }
        }

        if session
            .request_input(input_player, input_request_id, metadata)
            .is_err()
        {
            warn!("Could not request input from session; aborting task");
            let mut lc = self.lifecycle.lock();
            if !lc
                .task_q
                .active
                .get(&task_id)
                .is_some_and(|active| boundary.belongs_to(&active.control))
            {
                debug!(
                    task_id,
                    "Ignoring a boundary from a missing or replaced task attempt"
                );
                return;
            }
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        if !lc
            .task_q
            .active
            .get(&task_id)
            .is_some_and(|active| boundary.belongs_to(&active.control))
        {
            debug!(
                task_id,
                "Ignoring a boundary from a missing or replaced task attempt"
            );
            return;
        }
        if lc.state != SchedulerState::Running {
            debug!(
                task_id,
                "Cancelling registered input request during shutdown"
            );
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
            if let Some(task) = lc.task_q.active.get(&task_id) {
                task.control.request_cancel();
            }
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }
        let Some(tc) = lc.task_q.active.get(&task_id) else {
            debug!(task_id, "Task removed while input request was registering");
            return;
        };
        if tc.phase != RunningTaskPhase::RequestingInput {
            warn!(task_id, phase = ?tc.phase, "Task input phase changed unexpectedly");
            return;
        }
        if !boundary.finish() {
            lc.task_q.remove_message_queue(task_id);
            return lc
                .task_q
                .send_task_result(task_id, Err(TaskAbortedCancelled));
        }
        lc.flush_pending_sends(task_id);
        let tc = lc
            .task_q
            .active
            .remove(&task_id)
            .expect("transitioning task disappeared while lifecycle lock was held");
        lc.task_q.suspended.add_input_task(
            input_request_id,
            input_player,
            task,
            tc.session,
            tc.result_sender,
        );
    }
}
