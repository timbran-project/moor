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

use crate::tasks::{scheduler::lifecycle::TaskLifecycle, task_control::CommittedBoundary};
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
use moor_common::tasks::{Session, SessionError};
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
use std::sync::Arc;
use tracing::{debug, error, warn};
use uuid::Uuid;

/// Owns the task and its committed boundary while session I/O runs without the lock.
/// On unwind, boundary Drop stops continuation. The worker's panic handler performs
/// registry cleanup and result delivery after its stack (and all lock guards) unwinds.
#[must_use]
struct SuspensionTransition {
    task: Box<Task>,
    session: Arc<dyn Session>,
    boundary: CommittedBoundary,
    phase: RunningTaskPhase,
}

impl SuspensionTransition {
    fn prepare(
        lc: &mut TaskLifecycle,
        task: Box<Task>,
        boundary: CommittedBoundary,
        phase: RunningTaskPhase,
    ) -> Option<Self> {
        let task_id = task.task_id;
        let active = lc.task_q.active.get_mut(&task_id)?;
        if !boundary.belongs_to(&active.control) || !boundary.belongs_to(&task.control) {
            warn!(task_id, "Ignoring a boundary from a replaced task attempt");
            return None;
        }
        if active.phase != RunningTaskPhase::Running {
            warn!(task_id, phase = ?active.phase, "Task already transitioning");
            return None;
        }
        active.phase = phase;
        let transition = Self {
            task,
            session: active.session.clone(),
            boundary,
            phase,
        };
        transition.check_running(lc).then_some(transition)
    }

    fn is_current(&self, lc: &TaskLifecycle) -> bool {
        lc.task_q
            .active
            .get(&self.task.task_id)
            .is_some_and(|active| {
                self.boundary.belongs_to(&active.control) && active.phase == self.phase
            })
    }

    /// Check after each lock reacquisition, before changing any shared state.
    fn check_running(&self, lc: &mut TaskLifecycle) -> bool {
        if !self.is_current(lc) {
            debug!(
                task_id = self.task.task_id,
                "Task attempt changed during suspension"
            );
            return false;
        }
        if lc.state == SchedulerState::Running {
            return true;
        }
        let task_id = self.task.task_id;
        self.task.control.request_cancel();
        lc.discard_pending_sends(task_id);
        lc.task_q.remove_message_queue(task_id);
        lc.task_q
            .send_task_result(task_id, Err(TaskAbortedCancelled));
        false
    }

    fn session_failed(self, lc: &mut TaskLifecycle, error: SessionError) {
        let task_id = self.task.task_id;
        error!(
            task_id,
            ?error,
            "Session commit failed after world-state commit; output may be lost"
        );
        if self.is_current(lc) {
            lc.discard_pending_sends(task_id);
            lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }
    }

    fn input_failed(self, lc: &mut TaskLifecycle) {
        // Keep input delivery policy separate from session-commit failure policy.
        if self.is_current(lc) {
            lc.task_q
                .send_task_result(self.task.task_id, Err(TaskAbortedError));
        }
    }

    fn finish(self, lc: &mut TaskLifecycle) -> Option<Box<Task>> {
        if !self.check_running(lc) {
            return None;
        }
        let task_id = self.task.task_id;
        if !self.boundary.finish() {
            lc.task_q.remove_message_queue(task_id);
            lc.task_q
                .send_task_result(task_id, Err(TaskAbortedCancelled));
            return None;
        }
        lc.flush_pending_sends(task_id);
        Some(self.task)
    }
}

impl Scheduler {
    pub(crate) fn handle_task_suspend(
        &self,
        task_id: TaskId,
        wake_condition: TaskSuspend,
        task: Box<Task>,
        boundary: CommittedBoundary,
    ) {
        assert_eq!(task_id, task.task_id);
        let Some(transition) = SuspensionTransition::prepare(
            &mut self.lifecycle.lock(),
            task,
            boundary,
            RunningTaskPhase::Suspending,
        ) else {
            return;
        };

        if let Err(error) = transition.session.commit() {
            transition.session_failed(&mut self.lifecycle.lock(), error);
            return;
        }

        let mut lc = self.lifecycle.lock();
        let Some(task) = transition.finish(&mut lc) else {
            return;
        };
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
        assert_eq!(task_id, task.task_id);
        let input_request_id = Uuid::new_v4();
        let Some(transition) = SuspensionTransition::prepare(
            &mut self.lifecycle.lock(),
            task,
            boundary,
            RunningTaskPhase::RequestingInput,
        ) else {
            return;
        };

        if let Err(error) = transition.session.commit() {
            transition.session_failed(&mut self.lifecycle.lock(), error);
            return;
        }
        if !transition.check_running(&mut self.lifecycle.lock()) {
            return;
        }
        if transition
            .session
            .request_input(input_player, input_request_id, metadata)
            .is_err()
        {
            warn!(
                task_id,
                "Could not request input from session; aborting task"
            );
            transition.input_failed(&mut self.lifecycle.lock());
            return;
        }

        let mut lc = self.lifecycle.lock();
        let Some(task) = transition.finish(&mut lc) else {
            return;
        };
        let active = lc
            .task_q
            .active
            .remove(&task_id)
            .expect("transitioning task disappeared while lifecycle lock was held");
        lc.task_q.suspended.add_input_task(
            input_request_id,
            input_player,
            task,
            active.session,
            active.result_sender,
        );
    }
}
