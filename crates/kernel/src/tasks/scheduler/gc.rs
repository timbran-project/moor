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

//! GC cycle ownership, admission, mark completion, and sweep orchestration.
//! A cycle owner crosses the worker boundary and releases waiters on every exit.

use super::{Scheduler, SchedulerState, lifecycle::TaskLifecycle};
use crate::tasks::{
    DEFAULT_GC_INTERVAL_SECONDS, SchedulerOp, gc_thread::spawn_gc_mark_phase, sched_counters,
};
use moor_common::{model::CommitResult, tasks::SchedulerError};
use moor_db::GCInterface;
use moor_var::Obj;
use std::{collections::HashSet, thread::JoinHandle, time::Duration};
use tracing::{debug, error, info, warn};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) enum GcPhase {
    #[default]
    Idle,
    Preparing(u64),
    Marking(u64),
    Sweeping(u64),
}

impl GcPhase {
    fn cycle(self) -> Option<u64> {
        match self {
            Self::Idle => None,
            Self::Preparing(id) | Self::Marking(id) | Self::Sweeping(id) => Some(id),
        }
    }

    pub(crate) fn is_active(self) -> bool {
        self.cycle().is_some()
    }

    pub(crate) fn blocks_admission(self) -> bool {
        matches!(self, Self::Sweeping(_))
    }
}

/// Owns one collection cycle, including admission blocking during sweep.
/// Drop runs after local lifecycle lock guards unwind. It never commits GC work.
#[must_use]
pub(crate) struct GcCycle {
    scheduler: Scheduler,
    id: u64,
}

struct MarkInput {
    transaction: Box<dyn GCInterface>,
    roots: HashSet<Obj>,
    mutation_timestamp: Option<u64>,
}

impl GcCycle {
    pub(super) fn begin(scheduler: &Scheduler) -> Option<Self> {
        let mut lc = scheduler.lifecycle.lock();
        if lc.state != SchedulerState::Running || lc.gc_phase.is_active() {
            return None;
        }
        lc.gc_force_collect = false;
        lc.gc_cycle_count += 1;
        let id = lc.gc_cycle_count;
        lc.gc_phase = GcPhase::Preparing(id);
        Some(Self {
            scheduler: scheduler.clone(),
            id,
        })
    }

    fn prepare_mark(&self) -> Result<Option<MarkInput>, SchedulerError> {
        let (roots, mutation_timestamp) = {
            let mut lc = self.scheduler.lifecycle.lock();
            if lc.state != SchedulerState::Running || lc.gc_phase != GcPhase::Preparing(self.id) {
                return Ok(None);
            }
            let mut roots = lc.task_q.collect_anonymous_object_references();
            lc.schedule_q.purge_retired(std::time::SystemTime::now());
            lc.schedule_q
                .collect_anonymous_object_references(&mut roots);
            (roots, lc.last_mutation_timestamp)
        };
        let transaction = self
            .scheduler
            .database
            .gc_interface()
            .map_err(|error| gc_error("Failed to create GC interface", error))?;
        Ok(Some(MarkInput {
            transaction,
            roots,
            mutation_timestamp,
        }))
    }

    pub(super) fn marking(&self) -> bool {
        let mut lc = self.scheduler.lifecycle.lock();
        if lc.state != SchedulerState::Running || lc.gc_phase != GcPhase::Preparing(self.id) {
            return false;
        }
        lc.gc_phase = GcPhase::Marking(self.id);
        true
    }

    pub(crate) fn finish_mark(
        self,
        unreachable: HashSet<Obj>,
        mutation_timestamp: Option<u64>,
    ) -> Result<(), SchedulerError> {
        debug!(
            cycle = self.id,
            unreachable = unreachable.len(),
            "GC mark phase completed"
        );
        if unreachable.is_empty() {
            return Ok(());
        }
        self.sweep(unreachable, mutation_timestamp)
    }

    /// Admission and mark validation change together under the lifecycle lock.
    /// This consuming operation retains the cycle owner through waits and database I/O.
    pub(super) fn sweep(
        self,
        unreachable: HashSet<Obj>,
        mutation_timestamp: Option<u64>,
    ) -> Result<(), SchedulerError> {
        {
            let mut lc = self.scheduler.lifecycle.lock();
            if lc.state != SchedulerState::Running || lc.gc_phase != GcPhase::Marking(self.id) {
                return Ok(());
            }
            if lc.last_mutation_timestamp != mutation_timestamp {
                info!(
                    cycle = self.id,
                    "GC mark invalidated by a world-state mutation"
                );
                return Ok(());
            }
            lc.gc_phase = GcPhase::Sweeping(self.id);
        }
        loop {
            {
                let lc = self.scheduler.lifecycle.lock();
                if lc.state != SchedulerState::Running || lc.gc_phase != GcPhase::Sweeping(self.id)
                {
                    return Ok(());
                }
                if lc.last_mutation_timestamp != mutation_timestamp {
                    info!(
                        cycle = self.id,
                        "GC sweep invalidated while waiting for active tasks"
                    );
                    return Ok(());
                }
                if lc.task_q.active.is_empty() {
                    break;
                }
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        self.scheduler.run_gc_sweep_phase(unreachable)
    }
}

impl Drop for GcCycle {
    fn drop(&mut self) {
        let mut lc = self.scheduler.lifecycle.lock();
        if lc.gc_phase.cycle() == Some(self.id) {
            lc.gc_phase = GcPhase::Idle;
            lc.task_q.suspended.enqueue_gc_waiting_tasks();
        }
    }
}

fn gc_error(context: &str, error: impl std::fmt::Debug) -> SchedulerError {
    SchedulerError::GarbageCollectionFailed(format!("{context}: {error:?}"))
}

impl Scheduler {
    pub(super) fn join_gc_thread(&self) -> Result<(), SchedulerError> {
        let Some(thread) = self.gc_thread.lock().take() else {
            return Ok(());
        };
        if thread.thread().id() == std::thread::current().id() {
            return Err(gc_error(
                "Cannot join current GC thread",
                thread.thread().id(),
            ));
        }
        thread
            .join()
            .map_err(|_| gc_error("GC worker panicked", "shutdown"))
    }

    /// Reserve a cycle before preparing roots. Joins and retries never hold the lifecycle lock.
    pub(super) fn run_gc_cycle(&self) {
        // Serialize handle publication with shutdown. The GC worker never takes this mutex.
        let mut thread_slot = self.gc_thread.lock();
        let Some(cycle) = GcCycle::begin(self) else {
            return;
        };
        let result = self.launch_gc(cycle, &mut thread_slot);
        // Preserve the interval measured from cycle startup, including a failed start.
        self.lifecycle.lock().gc_last_cycle_time = std::time::Instant::now();
        if let Err(error) = result {
            error!(?error, "GC cycle could not start");
        }
    }

    fn launch_gc(
        &self,
        cycle: GcCycle,
        thread_slot: &mut Option<JoinHandle<()>>,
    ) -> Result<(), SchedulerError> {
        if let Some(previous) = thread_slot.take() {
            previous
                .join()
                .map_err(|_| gc_error("Previous GC worker panicked", "cycle startup"))?;
        }
        for attempt in 1..=3 {
            match cycle.prepare_mark() {
                Ok(Some(input)) => {
                    if !cycle.marking() {
                        return Ok(());
                    }
                    *thread_slot = Some(
                        spawn_gc_mark_phase(
                            input.transaction,
                            cycle,
                            input.roots,
                            input.mutation_timestamp,
                        )
                        .map_err(|error| gc_error("Could not spawn GC worker", error))?,
                    );
                    return Ok(());
                }
                Ok(None) => return Ok(()),
                Err(error)
                    if error.to_string().contains("GC transaction conflict") && attempt < 3 =>
                {
                    warn!(attempt, ?error, "Retrying GC preparation after conflict");
                    std::thread::sleep(Duration::from_millis(attempt * 10));
                }
                Err(error) => return Err(error),
            }
        }
        unreachable!("the final attempt returns its result")
    }

    pub(super) fn should_run_gc(&self, lc: &TaskLifecycle) -> bool {
        // Force GC if requested via gc_collect() builtin
        if lc.gc_force_collect {
            return true;
        }

        // Run automatic GC based on conditions
        self.should_run_automatic_gc(lc)
    }

    fn should_run_automatic_gc(&self, lc: &TaskLifecycle) -> bool {
        let gc_interval = if let Some(config_interval) = self.config.runtime.gc_interval {
            config_interval
        } else if let Some(db_secs) = self.server_options.load().gc_interval {
            Duration::from_secs(db_secs)
        } else {
            Duration::from_secs(DEFAULT_GC_INTERVAL_SECONDS)
        };

        let time_since_last_gc = lc.gc_last_cycle_time.elapsed();

        if time_since_last_gc >= gc_interval {
            debug!(
                "Triggering automatic GC after {} seconds of inactivity (interval: {} seconds)",
                time_since_last_gc.as_secs(),
                gc_interval.as_secs()
            );
            return true;
        }

        // In the future, this could also check:
        // - Number of anonymous objects created since last GC
        // - Memory pressure
        // - Task activity levels
        false
    }

    /// Collect unreachable anonymous objects in a new transaction.
    fn run_gc_sweep_phase(
        &self,
        unreachable_objects: std::collections::HashSet<Obj>,
    ) -> Result<(), SchedulerError> {
        let start_time = std::time::Instant::now();
        let perfc = sched_counters();
        let _t = perfc.timers.start(SchedulerOp::GcSweepPhase);
        // Get a new GC interface for the sweep phase transaction
        let mut gc = self
            .database
            .gc_interface()
            .map_err(|e| gc_error("Failed to create GC interface for sweep phase", e))?;

        // Collect unreachable objects
        let collected = if !unreachable_objects.is_empty() {
            gc.collect_unreachable_anonymous_objects(&unreachable_objects)
                .map_err(|e| gc_error("Failed to collect unreachable objects", e))?
        } else {
            0
        };

        // Only log the collection if we actually collected some objects or if it took an unusual amount of time.
        let sweep_duration = start_time.elapsed();
        if collected != 0 || sweep_duration > Duration::from_secs(5) {
            if sweep_duration > Duration::from_secs(5) {
                warn!(
                    "GC sweep: {} objects collected in *{:.2}ms*",
                    collected,
                    sweep_duration.as_secs_f64() * 1000.0
                );
            } else {
                info!(
                    "GC sweep: {} objects collected in {:.2}ms",
                    collected,
                    sweep_duration.as_secs_f64() * 1000.0
                );
            }
        }

        // Commit the sweep phase transaction
        match gc.commit() {
            Ok(CommitResult::Success { .. }) => Ok(()),
            Ok(CommitResult::ConflictRetry { .. }) => {
                // Transaction conflict - our optimism wasn't justified
                warn!("GC sweep transaction conflict - retry needed");
                Err(SchedulerError::GarbageCollectionFailed(
                    "GC transaction conflict - retry needed".to_string(),
                ))
            }
            Err(e) => {
                error!("Failed to commit GC sweep transaction: {:?}", e);
                Err(gc_error("GC commit failed", e))
            }
        }
    }

    pub(crate) fn handle_get_gc_stats(
        &self,
    ) -> Result<crate::tasks::scheduler_client::GCStats, SchedulerError> {
        let lc = self.lifecycle.lock();
        Ok(crate::tasks::scheduler_client::GCStats {
            cycle_count: lc.gc_cycle_count,
        })
    }

    pub(crate) fn handle_request_gc(&self) -> Result<(), SchedulerError> {
        debug!("Direct GC request received via scheduler client");

        let mut lc = self.lifecycle.lock();

        // Check if anonymous objects are enabled first
        if !self.config.features.anonymous_objects {
            warn!("GC requested but anonymous objects are disabled, ignoring request");
            Ok(())
        } else if lc.gc_phase.is_active() {
            info!("GC already in progress, request acknowledged but no additional cycle started");
            Ok(())
        } else if lc.task_q.active.is_empty() {
            // Can run GC immediately since no active tasks
            drop(lc);
            self.run_gc_cycle();
            Ok(())
        } else {
            // Set flag for GC to run when tasks complete
            lc.gc_force_collect = true;
            debug!("GC requested but tasks are active, will run when tasks complete");
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::tests::{scheduler, suspended_task};
    use super::*;
    use crate::tasks::task_q::WakeCondition;
    use moor_common::model::{ObjAttrs, ObjFlag, ObjectKind, WorldStateError};
    use moor_db::GCError;
    use moor_var::NOTHING;

    enum MarkOutcome {
        Empty,
        Error,
        Panic,
    }

    struct ControlledMark {
        entered: flume::Sender<()>,
        release: flume::Receiver<()>,
        outcome: MarkOutcome,
    }

    impl GCInterface for ControlledMark {
        fn get_anonymous_objects(&self) -> Result<HashSet<Obj>, WorldStateError> {
            self.entered.send(()).unwrap();
            self.release.recv().unwrap();
            match self.outcome {
                MarkOutcome::Empty => Ok(HashSet::new()),
                MarkOutcome::Error => {
                    Err(WorldStateError::DatabaseError("injected mark error".into()))
                }
                MarkOutcome::Panic => panic!("injected mark panic"),
            }
        }
        fn scan_anonymous_object_references(
            &mut self,
        ) -> Result<Vec<(Obj, HashSet<Obj>)>, WorldStateError> {
            Ok(Vec::new())
        }
        fn collect_unreachable_anonymous_objects(
            &mut self,
            _: &HashSet<Obj>,
        ) -> Result<usize, WorldStateError> {
            unreachable!("mark interface cannot sweep")
        }
        fn commit(self: Box<Self>) -> Result<CommitResult, GCError> {
            unreachable!("mark is read only")
        }
        fn rollback(self: Box<Self>) -> Result<(), GCError> {
            unreachable!("mark is read only")
        }
    }

    fn waiting_scheduler() -> Scheduler {
        let scheduler = scheduler();
        let waiting = suspended_task(81);
        {
            let mut lc = scheduler.lifecycle.lock();
            lc.state = SchedulerState::Running;
            let registration = lc.task_q.register_task(waiting.task.task_id);
            lc.task_q.suspended.add_task(
                WakeCondition::GCComplete,
                waiting.task,
                waiting.session,
                None,
                registration,
            );
        }
        scheduler
    }

    fn assert_waiter_released_once(scheduler: &Scheduler) {
        let mut lc = scheduler.lifecycle.lock();
        assert_eq!(lc.gc_phase, GcPhase::Idle);
        assert_eq!(lc.task_q.suspended.pop_immediate_wake().unwrap().0, 81);
        assert!(lc.task_q.suspended.pop_immediate_wake().is_none());
    }

    #[test]
    fn mark_error_and_panic_release_gc_waiters() {
        for outcome in [MarkOutcome::Error, MarkOutcome::Panic] {
            let scheduler = waiting_scheduler();
            let cycle = GcCycle::begin(&scheduler).unwrap();
            assert!(cycle.marking());
            let (entered, started) = flume::bounded(1);
            let (release, resume) = flume::bounded(1);
            let panics = matches!(outcome, MarkOutcome::Panic);
            let worker = spawn_gc_mark_phase(
                Box::new(ControlledMark {
                    entered,
                    release: resume,
                    outcome,
                }),
                cycle,
                HashSet::new(),
                None,
            )
            .unwrap();
            started.recv_timeout(Duration::from_secs(5)).unwrap();
            assert!(matches!(
                scheduler.lifecycle.lock().gc_phase,
                GcPhase::Marking(_)
            ));
            release.send(()).unwrap();
            assert_eq!(worker.join().is_err(), panics);
            assert_waiter_released_once(&scheduler);
        }
    }

    #[test]
    fn abandoned_preparation_releases_gc_waiters() {
        let scheduler = waiting_scheduler();
        let cycle = GcCycle::begin(&scheduler).unwrap();
        assert!(GcCycle::begin(&scheduler).is_none());
        drop(cycle);
        assert_waiter_released_once(&scheduler);
    }

    #[test]
    fn previous_worker_can_finish_while_next_cycle_starts() {
        let scheduler = waiting_scheduler();
        let (release, resume) = flume::bounded(1);
        let previous = scheduler.clone();
        *scheduler.gc_thread.lock() = Some(std::thread::spawn(move || {
            resume.recv().unwrap();
            // A join under this mutex would prevent the previous worker from exiting.
            let _lc = previous.lifecycle.lock();
        }));
        let next = scheduler.clone();
        let (finished, completion) = flume::bounded(1);
        let launch = std::thread::spawn(move || {
            next.run_gc_cycle();
            finished.send(()).unwrap();
        });
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        loop {
            if let Some(lc) = scheduler.lifecycle.try_lock()
                && matches!(lc.gc_phase, GcPhase::Preparing(_))
            {
                break;
            }
            assert!(std::time::Instant::now() < deadline);
            std::thread::yield_now();
        }
        release.send(()).unwrap();
        completion.recv_timeout(Duration::from_secs(5)).unwrap();
        launch.join().unwrap();
        scheduler.join_gc_thread().unwrap();
        assert_waiter_released_once(&scheduler);
    }

    #[test]
    fn stale_mark_cannot_release_a_replacement_cycle() {
        let scheduler = waiting_scheduler();
        let stale = GcCycle::begin(&scheduler).unwrap();
        assert!(stale.marking());
        let replacement = {
            let mut lc = scheduler.lifecycle.lock();
            lc.gc_cycle_count += 1;
            let id = lc.gc_cycle_count;
            lc.gc_phase = GcPhase::Marking(id);
            GcCycle {
                scheduler: scheduler.clone(),
                id,
            }
        };
        stale
            .finish_mark(HashSet::from([Obj::mk_anonymous_generated()]), None)
            .unwrap();
        {
            let mut lc = scheduler.lifecycle.lock();
            assert_eq!(lc.gc_phase, GcPhase::Marking(replacement.id));
            assert!(lc.task_q.suspended.pop_immediate_wake().is_none());
        }
        drop(replacement);
        assert_waiter_released_once(&scheduler);
    }

    #[test]
    fn invalidated_mark_preserves_unreachable_objects() {
        let scheduler = waiting_scheduler();
        let mut loader = scheduler.database.loader_client().unwrap();
        let owner = Obj::mk_id(2);
        loader
            .create_object(
                ObjectKind::Objid(owner),
                &ObjAttrs::new(owner, NOTHING, NOTHING, ObjFlag::all_flags(), "Wizard"),
            )
            .unwrap();
        let anonymous = loader
            .create_object(
                ObjectKind::Anonymous,
                &ObjAttrs::new(owner, NOTHING, NOTHING, ObjFlag::all_flags(), "Anonymous"),
            )
            .unwrap();
        loader.commit().unwrap();

        let cycle = GcCycle::begin(&scheduler).unwrap();
        assert!(cycle.marking());
        scheduler.lifecycle.lock().last_mutation_timestamp = Some(12);
        cycle.finish_mark(HashSet::from([anonymous]), None).unwrap();
        assert!(
            scheduler
                .database
                .gc_interface()
                .unwrap()
                .get_anonymous_objects()
                .unwrap()
                .contains(&anonymous)
        );
        assert_waiter_released_once(&scheduler);
    }

    #[test]
    fn shutdown_joins_in_flight_gc_cycle() {
        let scheduler = waiting_scheduler();
        let cycle = GcCycle::begin(&scheduler).unwrap();
        assert!(cycle.marking());
        let (entered, started) = flume::bounded(1);
        let (release, resume) = flume::bounded(1);
        let worker = spawn_gc_mark_phase(
            Box::new(ControlledMark {
                entered,
                release: resume,
                outcome: MarkOutcome::Empty,
            }),
            cycle,
            HashSet::new(),
            None,
        )
        .unwrap();
        *scheduler.gc_thread.lock() = Some(worker);
        started.recv_timeout(Duration::from_secs(5)).unwrap();

        let shutdown = scheduler.clone();
        let (completed, done) = flume::bounded(1);
        let stop = std::thread::spawn(move || completed.send(shutdown.stop(None)).unwrap());
        let deadline = std::time::Instant::now() + Duration::from_secs(5);
        while scheduler.state() != SchedulerState::Stopping {
            assert!(std::time::Instant::now() < deadline);
            std::thread::yield_now();
        }
        assert!(done.try_recv().is_err());
        release.send(()).unwrap();
        done.recv_timeout(Duration::from_secs(5)).unwrap().unwrap();
        stop.join().unwrap();
        assert_eq!(scheduler.state(), SchedulerState::Stopped);
        assert!(scheduler.gc_thread.lock().is_none());
        assert_waiter_released_once(&scheduler);
    }
}
