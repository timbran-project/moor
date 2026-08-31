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

use std::backtrace::Backtrace;

use moor_common::tasks::{
    EventLogPurgeResult, EventLogStats, Exception, ListenerInfo, SessionError,
};
use rand::RngExt;

use crate::tasks::{
    TaskDescription,
    task_scheduler_client::{ActiveTaskDescriptions, TaskLimitDisposition, TaskLimitInfo},
};

use super::*;

static HANDLE_TASK_TIMEOUT_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("handle_task_timeout"));

impl Scheduler {
    pub fn handle_task_success(
        &self,
        task_id: TaskId,
        value: Var,
        mutations_made: bool,
        timestamp: u64,
    ) {
        // Extract session under lock, then commit outside.
        let session = {
            let mut lc = self.lifecycle.lock();

            if mutations_made {
                lc.last_mutation_timestamp = Some(timestamp);
            }

            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for success");
                return;
            };
            task.terminal_result = Some(Ok(TaskNotification::Result(value)));
            task.phase = RunningTaskPhase::Completing;
            task.session.clone()
        };

        // Session commit (potential I/O) outside the lock.
        if let Err(error) = session.commit() {
            error!(
                task_id,
                boundary = "task completion",
                ?error,
                "Session commit failed after world-state commit; output may be lost"
            );
            let mut lc = self.lifecycle.lock();
            lc.discard_pending_sends(task_id);
            if let Some(task) = lc.task_q.active.get_mut(&task_id) {
                task.terminal_result = Some(Err(TaskAbortedError));
            }
            return lc.task_q.send_reserved_task_result(task_id);
        }

        let mut lc = self.lifecycle.lock();
        lc.flush_pending_sends(task_id);
        lc.task_q.remove_message_queue(task_id);
        lc.task_q.send_reserved_task_result(task_id)
    }

    pub fn handle_task_conflict_retry(
        &self,
        task_id: TaskId,
        mut task: Box<Task>,
        boundary: &'static str,
        conflict_info: Option<ConflictInfo>,
    ) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskConflictRetry);

        let mut lc = self.lifecycle.lock();

        lc.discard_pending_sends(task_id);

        // Make sure the old thread is dead.
        task.kill_switch.store(true, Ordering::SeqCst);

        if lc.state != SchedulerState::Running {
            debug!(task_id, "Discarding transaction retry during shutdown");
            lc.task_q.remove_message_queue(task_id);
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }

        // Remove from active tasks to get session/result_sender
        let Some(old_tc) = lc.task_q.active.remove(&task_id) else {
            error!(
                task_id,
                "Task not found for retry suspension, ignoring -- consistency issue!"
            );
            return;
        };

        // If the number of retries has been exceeded, abort immediately
        let max_retries = self.server_options.load().max_task_retries;
        if task.retries >= max_retries {
            let task_origin = task.conflict_task_origin();
            let conflict = conflict_info
                .as_ref()
                .map(ToString::to_string)
                .unwrap_or_else(|| "details unavailable".to_string());
            error!(
                task_id,
                retries = task.retries,
                max_retries,
                task = %task_origin,
                boundary,
                %conflict,
                "Task retry limit exhausted; aborting task"
            );
            lc.task_q
                .send_task_result_direct(task_id, old_tc.result_sender, Err(TaskAbortedError));
            return;
        }
        task.retries += 1;

        // Calculate backoff time: 10-50ms base, exponentially backed off
        let mut rng = rand::rng();
        let base_delay_ms = rng.random_range(10u64..=50u64);
        // Exponential backoff: base * 2^(retries-1)
        // Cap shift at 10 to prevent excessive delays (max multiplier 1024x)
        let shift = (task.retries as u32).saturating_sub(1).min(10);
        let delay_ms = base_delay_ms << shift;
        let wake_time = Deadline::from_now(Duration::from_millis(delay_ms)).instant();

        trace!(
            task_id,
            retries = task.retries,
            delay_ms,
            "Suspending task for retry backoff"
        );

        // Add to suspension queue with retry wake condition
        lc.task_q.suspended.add_task(
            WakeCondition::Retry(wake_time),
            task,
            old_tc.session,
            old_tc.result_sender,
        );
    }

    pub fn handle_task_verb_not_found(&self, task_id: TaskId, who: Var, what: Symbol) {
        let mut lc = self.lifecycle.lock();
        lc.task_q.send_task_result(
            task_id,
            Err(SchedulerError::TaskAbortedVerbNotFound(who, what)),
        );
    }

    pub fn handle_task_command_error(&self, task_id: TaskId, error: CommandError) {
        let mut lc = self.lifecycle.lock();
        // This is a common occurrence, so we don't want to log it at warn level.
        lc.task_q
            .send_task_result(task_id, Err(CommandExecutionError(error)));
    }

    pub fn handle_task_abort_cancelled(&self, task_id: TaskId) {
        let requested_abort = {
            let mut lc = self.lifecycle.lock();
            lc.task_q.active.get_mut(&task_id).and_then(|task| {
                task.abort_error
                    .take()
                    .map(|error| (error, task.session.clone()))
            })
        };
        if let Some((error, session)) = requested_abort {
            if let Err(session_error) = session.rollback() {
                warn!(
                    task_id,
                    ?session_error,
                    "Could not roll back cancelled task session"
                );
            }
            let mut lc = self.lifecycle.lock();
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
            return lc.task_q.send_task_result(task_id, Err(error));
        }

        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskAbortCancelled);

        // Extract session and player under lock. Shutdown cancellation does not publish an
        // "Aborted" message or commit buffered output; the shutdown notice has already been sent.
        let (session, shutting_down) = {
            let mut lc = self.lifecycle.lock();
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
            let shutting_down = lc.state != SchedulerState::Running;

            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                if lc.state == SchedulerState::Running {
                    warn!(task_id, "Task not found for abort");
                } else {
                    debug!(task_id, "Cancelled task already detached during shutdown");
                }
                return;
            };
            let session = task.session.clone();
            if shutting_down {
                debug!(task_id, "Task cancelled during shutdown");
                (session, true)
            } else {
                warn!(task_id, "Task cancelled");
                let player = task.player;
                if let Err(send_error) = session.send_system_msg(player, "Aborted.") {
                    warn!("Could not send abort message to player: {send_error:?}");
                }
                (session, false)
            }
        };

        if shutting_down {
            if let Err(e) = session.rollback() {
                debug!(task_id, error = ?e, "Could not rollback cancelled session during shutdown");
            }
            let mut lc = self.lifecycle.lock();
            if lc.task_q.active.contains_key(&task_id) {
                lc.task_q
                    .send_task_result(task_id, Err(TaskAbortedCancelled));
            }
            return;
        }

        // Session commit (potential I/O) outside the lock.
        if session.commit().is_err() {
            warn!("Could not commit aborted session; aborting task");
            let mut lc = self.lifecycle.lock();
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        lc.task_q
            .send_task_result(task_id, Err(TaskAbortedCancelled));
    }

    pub fn handle_task_transaction_renewal_failed(&self, task_id: TaskId) {
        let session = {
            let lc = self.lifecycle.lock();
            let Some(task) = lc.task_q.active.get(&task_id) else {
                warn!(task_id, "Task not found after transaction renewal failure");
                return;
            };
            task.session.clone()
        };

        let session_result = session.commit();

        let mut lc = self.lifecycle.lock();
        lc.flush_pending_sends(task_id);
        lc.task_q.remove_message_queue(task_id);

        let result = match session_result {
            Ok(()) => Err(SchedulerError::CouldNotStartTask),
            Err(error) => {
                error!(
                    task_id,
                    boundary = "transaction renewal",
                    ?error,
                    "Session commit failed after world-state commit; output may be lost"
                );
                Err(TaskAbortedError)
            }
        };
        lc.task_q.send_task_result(task_id, result);
    }

    pub fn handle_task_abort_panicked(
        &self,
        task_id: TaskId,
        panic_msg: String,
        _backtrace: Backtrace,
    ) {
        warn!(?task_id, ?panic_msg, "Task thread panicked");

        let mut lc = self.lifecycle.lock();

        lc.discard_pending_sends(task_id);
        lc.task_q.remove_message_queue(task_id);

        // Task already dead, can't access session. Just send error result directly.
        lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
    }

    pub(crate) fn handle_task_abort_limits_reached(
        &self,
        task_id: TaskId,
        limit_info: TaskLimitInfo,
    ) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskAbortLimits);
        let TaskLimitInfo {
            reason: limit_reason,
            disposition,
            this,
            verb_name: verb,
            line_number,
            stack,
            backtrace,
        } = limit_info;

        // Extract task and session under lock.
        let (mut task, session, player) = {
            let mut lc = self.lifecycle.lock();
            let Some(task) = lc.task_q.active.remove(&task_id) else {
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
                warn!(task_id, "Task not found for abort");
                return;
            };
            match disposition {
                TaskLimitDisposition::Commit {
                    mutations_made,
                    timestamp,
                } => {
                    if mutations_made {
                        lc.last_mutation_timestamp = Some(timestamp);
                    }
                    lc.flush_pending_sends(task_id);
                }
                TaskLimitDisposition::Rollback => lc.discard_pending_sends(task_id),
            }
            lc.task_q.remove_message_queue(task_id);
            let session = task.session.clone();
            let player = task.player;
            (task, session, player)
        };

        // Send the abort notification and finalize the session outside the lock.
        let abort_reason_text = match limit_reason {
            AbortLimitReason::Ticks(t) => {
                warn!(?task_id, ticks = t, "Task aborted, ticks exceeded");
                format!(
                    "Abort: Task exceeded ticks limit of {t} @ {}:{verb}:{line_number}",
                    to_literal(&this)
                )
            }
            AbortLimitReason::Time(t) => {
                warn!(?task_id, time = ?t, "Task aborted, time exceeded");
                format!("Abort: Task exceeded time limit of {t:?}")
            }
            AbortLimitReason::OutputEvents(events) => {
                warn!(
                    ?task_id,
                    events, "Task aborted, captured event count exceeded"
                );
                format!("Abort: Task exceeded captured output limit of {events} events")
            }
            AbortLimitReason::OutputBytes(bytes) => {
                warn!(?task_id, bytes, "Task aborted, captured output exceeded");
                format!("Abort: Task exceeded captured output limit of {bytes} bytes")
            }
        };

        if let Err(e) = session.send_system_msg(player, &abort_reason_text) {
            warn!("Could not send abort message to player: {e:?}");
        }

        let handler_session = session.clone().fork();
        let session_result = match disposition {
            TaskLimitDisposition::Commit { .. } => session.commit(),
            TaskLimitDisposition::Rollback => session.rollback(),
        };
        if let Err(error) = session_result {
            let action = match disposition {
                TaskLimitDisposition::Commit { .. } => "commit",
                TaskLimitDisposition::Rollback => "rollback",
            };
            error!(
                task_id,
                boundary = "task limit",
                action,
                ?error,
                "Session finalization failed after task limit"
            );
        }

        // Re-acquire lock for handler task submission.
        let mut lc = self.lifecycle.lock();

        // Attempt to invoke the handler verb as a separate task.
        let resource_str = match limit_reason {
            AbortLimitReason::Ticks(_) => "ticks",
            AbortLimitReason::Time(_) => "seconds",
            AbortLimitReason::OutputEvents(_) => "output events",
            AbortLimitReason::OutputBytes(_) => "output bytes",
        };

        let handler_args = List::from_iter(vec![
            v_str(resource_str),
            List::from_iter(stack).into(),
            List::from_iter(backtrace).into(),
        ]);

        let handler_task_start = TaskStart::StartVerb {
            player,
            vloc: v_obj(SYSTEM_OBJECT),
            verb: *HANDLE_TASK_TIMEOUT_SYM,
            args: handler_args,
            argstr: v_empty_str(),
        };

        let handler_task_id = lc.next_task_id;
        lc.next_task_id += 1;

        debug!(
            "Spawning handler task {} for timeout on task {}",
            handler_task_id, task_id
        );

        let handler_session = handler_session.unwrap_or_else(|error| {
            warn!(
                task_id,
                ?error,
                "Could not fork session for task-limit handler"
            );
            session.clone()
        });
        let handler_result = self.submit_task(
            &mut lc,
            handler_task_id,
            &player,
            &player,
            handler_task_start,
            None,
            handler_session,
        );

        match handler_result {
            Ok(_) => {
                debug!("Handler task {} started successfully", handler_task_id);
            }
            Err(e) => {
                warn!("Failed to start handler task: {:?}", e);
            }
        }

        // Report the original task as aborted (handler outcome doesn't affect this)
        lc.task_q.suspended.enqueue_dependents_for(task_id);
        lc.task_q.send_task_result_direct(
            task_id,
            task.result_sender.take(),
            Err(TaskAbortedLimit(limit_reason)),
        );
    }

    pub fn handle_task_exception(&self, task_id: TaskId, exception: Box<Exception>) {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::TaskException);

        // Extract session under lock, send traceback event.
        let session = {
            let lc = self.lifecycle.lock();
            let Some(task) = lc.task_q.active.get(&task_id) else {
                warn!(task_id, "Task not found for abort");
                return;
            };
            let session = task.session.clone();
            if let Err(send_error) = session.send_event(
                task.player,
                Box::new(NarrativeEvent {
                    event_id: Uuid::now_v7(),
                    timestamp: SystemTime::now(),
                    author: v_obj(task.player),
                    event: Event::Traceback(exception.as_ref().clone()),
                }),
            ) {
                warn!("Could not send traceback to player: {:?}", send_error);
            }
            session
        };

        // Session commit (potential I/O) outside the lock.
        let _ = session.commit();

        let mut lc = self.lifecycle.lock();
        lc.flush_pending_sends(task_id);
        lc.task_q.remove_message_queue(task_id);
        lc.task_q.send_task_result(
            task_id,
            Err(TaskAbortedException(exception.as_ref().clone())),
        );
    }

    pub fn handle_task_request_fork(&self, task_id: TaskId, fork_request: Box<Fork>) -> TaskId {
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::ForkTask);

        let mut lc = self.lifecycle.lock();

        // Task has requested a fork. Dispatch it and reply with the new task id.
        let new_session = {
            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for fork request");
                // Return a sentinel; caller should handle missing task.
                return 0;
            };
            task.session.clone()
        };

        // Fork the session.
        let forked_session = new_session.fork().unwrap();

        let suspended = fork_request.delay.is_some();
        let player = fork_request.player;
        let delay = fork_request.delay;
        let progr = fork_request.progr;

        let task_start = TaskStart::StartFork {
            fork_request,
            suspended,
        };
        let new_task_id = lc.next_task_id;
        lc.next_task_id += 1;
        if let Err(e) = self.submit_task(
            &mut lc,
            new_task_id,
            &player,
            &progr,
            task_start,
            delay,
            forked_session,
        ) {
            error!(?e, "Could not fork task");
        }

        new_task_id
    }

    pub fn handle_task_suspend(
        &self,
        task_id: TaskId,
        wake_condition: TaskSuspend,
        task: Box<Task>,
    ) {
        // Keep the task visible while committing the session. The final move from
        // active to suspended is performed under one lifecycle lock acquisition.
        let session = {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Discarding suspension request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
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
            lc.discard_pending_sends(task_id);
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        if lc.state != SchedulerState::Running {
            debug!(task_id, "Cancelling suspension completed during shutdown");
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
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

    pub fn handle_task_request_input(
        &self,
        task_id: TaskId,
        task: Box<Task>,
        input_player: Obj,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) {
        let input_request_id = Uuid::new_v4();

        // Keep the task visible while committing output and registering the input
        // request. The active-to-suspended move remains atomic under the lock.
        let session = {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Discarding input request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
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
            lc.discard_pending_sends(task_id);
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running {
                debug!(task_id, "Cancelling input request during shutdown");
                lc.discard_pending_sends(task_id);
                lc.task_q.remove_message_queue(task_id);
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
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        }

        let mut lc = self.lifecycle.lock();
        if lc.state != SchedulerState::Running {
            debug!(
                task_id,
                "Cancelling registered input request during shutdown"
            );
            lc.discard_pending_sends(task_id);
            lc.task_q.remove_message_queue(task_id);
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

    pub fn handle_request_tasks(&self, _task_id: TaskId) -> Vec<TaskDescription> {
        let lc = self.lifecycle.lock();
        lc.task_q.suspended.tasks()
        // TODO: add non-queued tasks.
    }

    #[inline]
    pub fn handle_task_exists(&self, check_task_id: TaskId) -> bool {
        self.live_tasks.contains(check_task_id)
    }

    pub fn handle_kill_task(
        &self,
        _task_id: TaskId,
        victim_task_id: TaskId,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        lc.task_q.kill_task(victim_task_id, sender_authority)
    }

    /// Cancel a task the server started on its own behalf, with no permission check.
    /// Returns false if the task was already gone.
    pub fn handle_abort_task(&self, victim_task_id: TaskId) -> AbortTaskOutcome {
        let mut lc = self.lifecycle.lock();
        lc.task_q.abort_task(victim_task_id)
    }

    pub fn handle_resume_task(
        &self,
        task_id: TaskId,
        queued_task_id: TaskId,
        sender_authority: TaskPermissions,
        return_value: Var,
    ) -> Var {
        let mut lc = self.lifecycle.lock();
        lc.task_q.resume_task(
            task_id,
            queued_task_id,
            sender_authority,
            return_value,
            self,
            self.database.as_ref(),
            self.builtin_registry.clone(),
            self.config.clone(),
        )
    }

    pub fn handle_boot_player(&self, task_id: TaskId, player: Obj) {
        let mut lc = self.lifecycle.lock();
        // Task is asking to boot a player.
        lc.task_q.disconnect_task(task_id, &player);
    }

    pub fn handle_notify(
        &self,
        task_id: TaskId,
        player: Obj,
        event: Box<NarrativeEvent>,
        size_bytes: Option<usize>,
    ) {
        let mut lc = self.lifecycle.lock();
        // Task is asking to notify a player of an event.
        let Some(task) = lc.task_q.active.get_mut(&task_id) else {
            warn!(task_id, "Task not found for notify request");
            return;
        };
        let send_result = match size_bytes {
            Some(size_bytes) => task.session.send_event_with_size(player, event, size_bytes),
            None => task.session.send_event(player, event),
        };
        let Err(error) = send_result else {
            return;
        };
        warn!(?error, "Could not notify player; cancelling task");
        let scheduler_error = match error {
            SessionError::OutputEventLimitExceeded(limit) => {
                TaskAbortedLimit(AbortLimitReason::OutputEvents(limit))
            }
            SessionError::OutputByteLimitExceeded(limit) => {
                TaskAbortedLimit(AbortLimitReason::OutputBytes(limit))
            }
            _ => TaskAbortedError,
        };
        task.abort_error = Some(scheduler_error);
        task.kill_switch.store(true, Ordering::SeqCst);
    }

    pub fn handle_log_event(&self, task_id: TaskId, player: Obj, event: Box<NarrativeEvent>) {
        let mut lc = self.lifecycle.lock();
        // Task is asking to log an event without broadcasting.
        let Some(task) = lc.task_q.active.get_mut(&task_id) else {
            warn!(task_id, "Task not found for log_event request");
            return;
        };
        let Ok(()) = task.session.log_event(player, event) else {
            warn!("Could not log event; aborting task");
            return lc.task_q.send_task_result(task_id, Err(TaskAbortedError));
        };
    }

    pub fn handle_get_listeners(&self) -> Vec<ListenerInfo> {
        self.system_control
            .listeners()
            .expect("Could not get listeners")
    }

    pub fn handle_listen(
        &self,
        task_id: TaskId,
        handler_object: Obj,
        host_type: String,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Option<Error> {
        let lc = self.lifecycle.lock();
        let Some(_task) = lc.task_q.active.get(&task_id) else {
            warn!(task_id, "Task not found for listen request");
            return Some(E_INVARG.msg("Task not found"));
        };
        drop(lc);

        self.system_control
            .listen(handler_object, &host_type, port, options)
            .err()
    }

    pub fn handle_unlisten(&self, task_id: TaskId, host_type: String, port: u16) -> Option<Error> {
        let lc = self.lifecycle.lock();
        let Some(_task) = lc.task_q.active.get(&task_id) else {
            warn!(task_id, "Task not found for unlisten request");
            return Some(E_INVARG.msg("Task not found"));
        };
        drop(lc);

        match self.system_control.unlisten(port, &host_type) {
            Ok(_) => None,
            Err(_) => Some(E_PERM.msg("Permission denied on unlisten")),
        }
    }

    pub fn handle_refresh_server_options(&self) {
        self.reload_server_options();
    }

    pub fn handle_shutdown(&self, msg: Option<String>) {
        info!("Shutting down scheduler. Reason: {msg:?}");
        let scheduler = self.clone();
        if let Err(e) = std::thread::Builder::new()
            .name("moor-scheduler-shutdown".to_string())
            .spawn(move || {
                if let Err(e) = scheduler.stop(msg) {
                    error!(error = ?e, "Could not shutdown scheduler cleanly");
                }
            })
        {
            error!(error = ?e, "Could not start scheduler shutdown thread");
        }
    }

    pub fn handle_force_input(
        &self,
        task_id: TaskId,
        who: Obj,
        line: String,
    ) -> Result<TaskId, Error> {
        let mut lc = self.lifecycle.lock();

        let new_session = {
            let Some(task) = lc.task_q.active.get_mut(&task_id) else {
                warn!(task_id, "Task not found for force input request");
                return Err(E_INVIND.msg("Task not found"));
            };
            task.session.clone().fork().unwrap()
        };
        let task_start = TaskStart::StartCommandVerb {
            handler_object: SYSTEM_OBJECT,
            player: who,
            command: line,
        };

        let new_task_id = lc.next_task_id;
        lc.next_task_id += 1;
        let result = self.submit_task(
            &mut lc,
            new_task_id,
            &who,
            &who,
            task_start,
            None,
            new_session,
        );
        match result {
            Err(e) => {
                error!(?e, "Could not start task thread");
                Err(E_INVIND.with_msg(|| format!("Could not start thread for force_input: {e:?}")))
            }
            Ok(th) => Ok(th.0),
        }
    }

    pub fn handle_active_tasks(&self, _task_id: TaskId) -> Result<ActiveTaskDescriptions, Error> {
        let lc = self.lifecycle.lock();
        let mut results = vec![];
        for (task_id, tc) in lc.task_q.active.iter() {
            results.push((*task_id, tc.player, tc.task_start.clone()));
        }
        Ok(results)
    }

    pub fn handle_task_telemetry(&self, task_id: Option<TaskId>) -> Vec<TaskTelemetry> {
        let sources: Vec<_> = {
            let lc = self.lifecycle.lock();
            lc.task_q
                .active
                .iter()
                .filter(|(active_task_id, _)| {
                    task_id.is_none_or(|task_id| task_id == **active_task_id)
                })
                .map(|(task_id, task)| TaskTelemetrySource {
                    task_id: *task_id,
                    player: task.player,
                    dispatched_at: task.dispatched_at,
                    baseline: task.run_baseline.get().cloned(),
                })
                .collect()
        };

        // Procfs reads can fault or block. Keep them outside the scheduler lifecycle lock.
        let samples: Vec<_> = sources.iter().map(TaskTelemetrySource::sample).collect();

        let lc = self.lifecycle.lock();
        sources
            .into_iter()
            .zip(samples)
            .filter_map(|(source, sample)| {
                let active = lc.task_q.active.get(&source.task_id)?;
                if active.run_baseline.get() != source.baseline.as_ref() {
                    return None;
                }
                Some(sample)
            })
            .collect()
    }

    pub fn handle_checkpoint_from_task(&self, _task_id: TaskId) -> Result<(), SchedulerError> {
        self.checkpoint()
    }

    pub fn handle_task_send(
        &self,
        task_id: TaskId,
        target_task_id: TaskId,
        value: Var,
        sender_authority: TaskPermissions,
    ) -> Var {
        let mut lc = self.lifecycle.lock();

        if let Err(error) = lc
            .task_q
            .require_task_send_authority(target_task_id, sender_authority)
        {
            return match error {
                E_INVARG => v_error(
                    E_INVARG
                        .with_msg(|| format!("Task ({target_task_id}) not found for task_send")),
                ),
                E_PERM => v_error(E_PERM.with_msg(|| {
                    format!("Permission denied for task_send to task ({target_task_id})")
                })),
                _ => v_err(error),
            };
        }

        // Check mailbox size limit (committed queue + pending sends
        // from this task to same target)
        let committed_len = lc.task_q.mailbox_len(target_task_id);
        let pending_len = lc.pending_task_sends.get(&task_id).map_or(0, |sends| {
            sends
                .iter()
                .filter(|(tid, _)| *tid == target_task_id)
                .count()
        });
        if committed_len + pending_len >= self.server_options.load().max_task_mailbox {
            return v_error(E_QUOTA.with_msg(|| {
                format!(
                    "Task mailbox full ({} messages) for task ({target_task_id})",
                    committed_len + pending_len
                )
            }));
        }

        // Buffer the message for delivery at commit time
        lc.pending_task_sends
            .entry(task_id)
            .or_default()
            .push((target_task_id, value));

        v_int(0)
    }

    pub fn handle_task_recv(&self, task_id: TaskId) -> Vec<Var> {
        let mut lc = self.lifecycle.lock();
        // Drain all messages from the calling task's queue
        let (messages, total_wait_nanos, message_count) =
            lc.task_q.drain_messages_with_wait_nanos(task_id);
        if message_count > 0 {
            let perfc = sched_counters();
            perfc.timers.record_elapsed(
                SchedulerOp::TaskMessageDeliveryToRecvLatency,
                Duration::from_nanos(total_wait_nanos as u64),
            );
        }
        messages
    }

    pub fn handle_force_gc(&self) {
        info!("Forcing garbage collection via gc_collect() builtin");
        if !self.config.features.anonymous_objects {
            warn!("GC force requested but anonymous objects are disabled, ignoring request");
        } else {
            {
                let mut lc = self.lifecycle.lock();
                lc.gc_force_collect = true;
            }
            self.wake_timer_thread();
        }
    }

    pub fn handle_rotate_enrollment_token(&self) -> Result<String, Error> {
        self.system_control.rotate_enrollment_token()
    }

    pub fn handle_player_event_log_stats(
        &self,
        player: Obj,
        since: Option<SystemTime>,
        until: Option<SystemTime>,
    ) -> Result<EventLogStats, Error> {
        self.system_control
            .player_event_log_stats(player, since, until)
    }

    pub fn handle_purge_player_event_log(
        &self,
        player: Obj,
        before: Option<SystemTime>,
        drop_pubkey: bool,
    ) -> Result<EventLogPurgeResult, Error> {
        self.system_control
            .purge_player_event_log(player, before, drop_pubkey)
    }

    pub fn handle_request_new_transaction(
        &self,
        task_id: TaskId,
    ) -> Result<Box<dyn WorldState>, SchedulerError> {
        let mut lc = self.lifecycle.lock();
        lc.flush_pending_sends(task_id);
        drop(lc);

        self.database
            .new_world_state()
            .map_err(|_| SchedulerError::CouldNotStartTask)
    }

    pub fn handle_dump_object_from_task(
        &self,
        obj: Obj,
        use_constants: bool,
    ) -> Result<Vec<Var>, Error> {
        self.handle_dump_object(obj, use_constants)
    }

    pub fn handle_switch_player_from_task(
        &self,
        task_id: TaskId,
        source: Option<Obj>,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), Error> {
        let mut lc = self.lifecycle.lock();

        // Get the current task to access its session
        let Some(task) = lc.task_q.active.get_mut(&task_id) else {
            return Err(E_INVARG.with_msg(|| "Task not found for switch_player".to_string()));
        };

        let current_connection = task
            .session
            .connection_details(None)
            .map_err(|e| {
                E_INVARG.with_msg(|| {
                    format!("Failed to get connection details for current session: {e:?}")
                })
            })?
            .first()
            .ok_or_else(|| {
                E_INVARG.with_msg(|| "No connection found for current session".to_string())
            })?
            .connection_obj;

        // A player can own several connections. If the task names its own player, retain the
        // connection that initiated the task instead of selecting an arbitrary connection.
        let connection_obj = if source.is_none() || source == Some(task.player) {
            current_connection
        } else {
            let connection_details = task.session.connection_details(source).map_err(|e| {
                E_INVARG.with_msg(|| {
                    format!("Failed to get connection details for switch source: {e:?}")
                })
            })?;
            let [connection] = connection_details.as_slice() else {
                if connection_details.is_empty() {
                    return Err(E_INVARG
                        .with_msg(|| "No connection found for switch_player source".to_string()));
                }
                return Err(E_INVARG.with_msg(|| {
                    "switch_player source has multiple connections; pass a connection object"
                        .to_string()
                }));
            };
            connection.connection_obj
        };

        drop(lc);

        self.system_control
            .switch_player(connection_obj, new_player, silent, preserve_history)?;

        // The registry is the durable commit point. Update scheduler metadata only after it
        // succeeds so a rejected switch leaves the running task associated with its old player.
        let mut lc = self.lifecycle.lock();
        if connection_obj == current_connection
            && let Some(task) = lc.task_q.active.get_mut(&task_id)
        {
            task.player = new_player;
            task.session
                .switch_player_identity(new_player, preserve_history);
        }

        Ok(())
    }
}
