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

//! Scheduler service startup, loops, and shutdown.
//! Joins and external shutdown operations run without the lifecycle mutex.

use super::{Scheduler, SchedulerClientRequest, SchedulerState};
use crate::tasks::{DEFAULT_COMPACT_INTERVAL_SECONDS, workers::WorkerResponse};
use flume::{Receiver, RecvTimeoutError};
use moor_common::{
    tasks::{SchedulerError, SchedulerError::TaskAbortedCancelled, SessionFactory},
    threading::{set_current_thread_background_priority, spawn_perf},
};
use std::{sync::Arc, time::Duration};
use tracing::{debug, info, warn};

/// Threads owned by a running scheduler.
#[must_use = "scheduler service threads must be joined during shutdown"]
pub struct SchedulerThreads {
    timer: std::thread::JoinHandle<()>,
    worker_response: Option<std::thread::JoinHandle<()>>,
    client_requests: std::thread::JoinHandle<()>,
}

impl SchedulerThreads {
    /// Join all scheduler service threads, returning the first panic after every
    /// handle has been collected.
    pub fn join(self) -> std::thread::Result<()> {
        let mut handles = vec![self.timer, self.client_requests];
        if let Some(worker_response) = self.worker_response {
            handles.push(worker_response);
        }

        let mut first_panic = None;
        for handle in handles {
            if let Err(panic) = handle.join()
                && first_panic.is_none()
            {
                first_panic = Some(panic);
            }
        }

        match first_panic {
            Some(panic) => Err(panic),
            None => Ok(()),
        }
    }
}

impl Scheduler {
    /// Start the scheduler and return ownership of all scheduler service threads.
    pub fn start(
        &self,
        bg_session_factory: Arc<dyn SessionFactory>,
    ) -> Result<SchedulerThreads, SchedulerError> {
        // Rehydrate suspended tasks.
        {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Created {
                return Err(SchedulerError::SchedulerNotResponding);
            }
            if let Some(max_restored_task_id) =
                lc.task_q.suspended.load_tasks(bg_session_factory.clone())
            {
                let next_restored_task_id = max_restored_task_id
                    .checked_add(1)
                    .expect("Restored task ID exhausted the task ID space");
                lc.next_task_id = lc.next_task_id.max(next_restored_task_id);
            }
            lc.load_schedules();
            lc.bg_session_factory = Some(bg_session_factory);
            lc.state = SchedulerState::Running;
        }

        // Start worker response thread if we have a worker receiver.
        let worker_response = if let Some(recv) = self.worker_response_recv.lock().take() {
            let scheduler = self.clone();
            Some(
                spawn_perf("moor-worker-recv", move || {
                    scheduler.worker_response_loop(recv);
                })
                .expect("Could not spawn worker response thread"),
            )
        } else {
            None
        };

        let client_request_recv = self
            .client_request_recv
            .lock()
            .take()
            .ok_or(SchedulerError::CouldNotStartTask)?;
        let scheduler = self.clone();
        let client_requests = spawn_perf("moor-scheduler-requests", move || {
            scheduler.client_request_loop(client_request_recv);
        })
        .expect("Could not spawn scheduler client request thread");

        // Start timer thread.
        let scheduler = self.clone();
        let timer = spawn_perf("moor-timer", move || {
            set_current_thread_background_priority().ok();
            scheduler.timer_loop();
        })
        .expect("Could not spawn timer thread");

        info!("Scheduler started");
        Ok(SchedulerThreads {
            timer,
            worker_response,
            client_requests,
        })
    }

    fn client_request_loop(&self, recv: Receiver<SchedulerClientRequest>) {
        loop {
            match recv.recv_timeout(Duration::from_millis(50)) {
                Ok(request) => request(self),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }

            if self.state() == SchedulerState::Stopped {
                break;
            }
        }
        debug!("Scheduler client request loop exited");
    }

    pub(crate) fn enqueue_client_request(
        &self,
        request: SchedulerClientRequest,
    ) -> Result<(), SchedulerError> {
        let lc = self.lifecycle.lock();
        if lc.state != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        self.client_request_send
            .send(request)
            .map_err(|_| SchedulerError::SchedulerNotResponding)
    }

    /// The timer loop replaces the old run() main loop.
    /// Handles: timer expirations, GC checks, compaction, immediate wakes.
    fn timer_loop(&self) {
        loop {
            {
                let lc = self.lifecycle.lock();
                if lc.state == SchedulerState::Stopped {
                    break;
                }
            }

            // Check GC conditions
            {
                let mut lc = self.lifecycle.lock();
                if lc.state == SchedulerState::Running
                    && self.config.features.anonymous_objects
                    && !lc.gc_collection_in_progress
                    && !lc.gc_mark_in_progress
                    && self.should_run_gc(&lc)
                {
                    self.run_gc_cycle(&mut lc);
                }

                // Periodic tasks DB compaction
                if lc.last_compact_time.elapsed()
                    >= Duration::from_secs(DEFAULT_COMPACT_INTERVAL_SECONDS)
                {
                    debug!("Triggering periodic tasks database compaction");
                    lc.task_q.compact();
                    lc.last_compact_time = std::time::Instant::now();
                }
            }

            // Drain immediate wakes
            self.drain_immediate_wakes();

            // Collect timer-based wakes
            self.collect_and_wake_expired_tasks();

            // Settle finished firings and fire due native schedules
            {
                let mut lc = self.lifecycle.lock();
                lc.settle_schedule_firings();
            }
            self.collect_and_fire_schedules();

            // Sleep until next timer expiry or notification
            let tick_duration = self
                .config
                .runtime
                .scheduler_tick_duration
                .unwrap_or(Duration::from_millis(10));

            let (lock, cvar) = &*self.timer_notify;
            let mut notified = lock.lock();
            *notified = false;
            cvar.wait_for(&mut notified, tick_duration);
        }

        // Write out all the suspended tasks to the database.
        info!("Timer loop done; saving suspended tasks");
        let lc = self.lifecycle.lock();
        lc.task_q.suspended.save_tasks();
        lc.save_schedules();
        info!("Saved.");
    }

    /// Wake the timer thread to recompute its sleep duration.
    pub(crate) fn wake_timer_thread(&self) {
        let (lock, cvar) = &*self.timer_notify;
        let mut notified = lock.lock();
        *notified = true;
        cvar.notify_one();
    }

    /// Dedicated thread for receiving worker responses.
    fn worker_response_loop(&self, recv: Receiver<WorkerResponse>) {
        loop {
            match recv.recv_timeout(Duration::from_millis(50)) {
                Ok(response) => self.handle_worker_response(response),
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => break,
            }

            if self.state() == SchedulerState::Stopped {
                break;
            }
        }
        debug!("Worker response loop exited");
    }

    /// Stop the scheduler run loop.
    pub(crate) fn stop(&self, msg: Option<String>) -> Result<(), SchedulerError> {
        // Stop accepting work, notify sessions, and ask active tasks to cancel. Keep their
        // scheduler records until their callbacks finish so shutdown can wait on real progress.
        {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running {
                return Err(SchedulerError::SchedulerNotResponding);
            }
            lc.state = SchedulerState::Stopping;

            // Notify all live tasks of shutdown.
            for task in lc.task_q.active.values() {
                let _ = task.session.notify_shutdown(msg.clone());
                task.control.request_cancel();
            }
            info!(
                active_tasks = lc.task_q.active.len(),
                "Stopping scheduler tasks"
            );
        }

        let active_maintenance = self.maintenance_coordinator.close();

        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        loop {
            let active_tasks = self.lifecycle.lock().task_q.active.len();
            if active_tasks == 0 {
                break;
            }
            if std::time::Instant::now() >= deadline {
                let mut lc = self.lifecycle.lock();
                let remaining = lc.task_q.active.len();
                let task_ids = lc.task_q.active.keys().copied().collect::<Vec<_>>();
                for task_id in task_ids {
                    lc.discard_task_effects(task_id);
                    lc.task_q.remove_message_queue(task_id);
                    let Some(mut task) = lc.task_q.active.remove(&task_id) else {
                        continue;
                    };
                    lc.task_q.suspended.enqueue_dependents_for(task_id);
                    lc.task_q.send_task_result_direct(
                        task_id,
                        task.result_sender.take(),
                        Err(TaskAbortedCancelled),
                    );
                }
                warn!(
                    remaining,
                    "Timed out waiting for scheduler tasks; detaching them"
                );
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }

        let gc_result = self.join_gc_thread();
        let maintenance_result = active_maintenance.map_or(Ok(()), |ticket| {
            info!(
                generation = ticket.generation(),
                kind = ?ticket.kind(),
                "Waiting for active database maintenance before shutdown"
            );
            ticket.wait()
        });

        // Now ask the rpc server and hosts to shutdown (no lock held).
        self.system_control
            .shutdown(msg)
            .expect("Could not cleanly shutdown system");

        info!("Scheduler tasks stopped");
        {
            let mut lc = self.lifecycle.lock();
            lc.state = SchedulerState::Stopped;
        }
        self.wake_timer_thread();

        gc_result.and(maintenance_result)
    }
}
