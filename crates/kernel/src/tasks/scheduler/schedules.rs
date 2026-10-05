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

//! Native schedules from request admission through firing, persistence, and settlement.
//!
//! Scheduler methods acquire the lifecycle lock. TaskLifecycle methods borrow already locked
//! state. Expiry collection releases the lock, so firing rechecks the expiry generation before
//! creating a session or task. ScheduleQ retains timing policy and the separate firing records.
//! Session creation and target validation retain their existing lock scopes.

use crate::tasks::{
    TaskStart,
    registry::TaskAttempt,
    schedule_q::{
        Outcome, PendingCreate, PendingKind, RetireReason, ScheduleEntry, ScheduleError,
        ScheduleExpiry, ScheduleId, ScheduleOptions,
    },
    scheduler::{Scheduler, SchedulerState, lifecycle::TaskLifecycle},
};
use moor_common::{model::TaskPermissions, tasks::TaskId};
use moor_var::{E_INVARG, E_PERM, List, Obj, Symbol, Var, v_float, v_str};
use std::{collections::HashMap, time::SystemTime};
use tracing::warn;

impl Scheduler {
    /// Fire every native schedule whose deadline has passed. Expired entries
    /// are collected under one lock acquisition; each firing is then
    /// submitted as an ordinary background task with
    /// `TaskStart::StartScheduled`, and the schedule is marked running so the
    /// completion callbacks can find it again.
    pub(super) fn collect_and_fire_schedules(&self) {
        let now_sys = SystemTime::now();
        let now = std::time::Instant::now();
        let to_fire: Vec<(ScheduleExpiry, ScheduleEntry)> = {
            let mut lc = self.lifecycle.lock();
            if lc.state != SchedulerState::Running {
                return;
            }
            let ids = lc.schedule_q.expired(now, now_sys);
            ids.into_iter()
                .filter_map(|id| Some((lc.schedule_q.expiry(id)?, lc.schedule_q.info(id)?.clone())))
                .collect()
        };
        self.fire_collected_schedules(to_fire, now_sys);
    }

    pub(super) fn fire_collected_schedules(
        &self,
        to_fire: Vec<(ScheduleExpiry, ScheduleEntry)>,
        now_sys: SystemTime,
    ) {
        for (expiry, entry) in to_fire {
            let mut lc = self.lifecycle.lock();
            // Completion may have replaced the arm while the lock was released.
            if !lc.schedule_q.is_current_expiry(expiry) {
                continue;
            }
            let id = expiry.id;
            let Some(factory) = lc.bg_session_factory.clone() else {
                warn!(schedule_id = id, "No session factory; cannot fire schedule");
                continue;
            };
            let player = entry.options.player.unwrap_or(entry.target);
            let session = match factory.mk_background_session(&player) {
                Ok(s) => s,
                Err(e) => {
                    warn!(schedule_id = id, error = ?e, "Could not make session for schedule firing");
                    continue;
                }
            };

            // Revalidate the target and the verb before spending a task on it.
            // A recycled target or a vanished verb retires the schedule.
            if !self.schedule_target_is_valid(&entry) {
                lc.schedule_q
                    .retire(id, RetireReason::InvalidTarget, now_sys);
                lc.persist_schedule(id);
                continue;
            }

            let mut args: Var = entry.args.clone().into();
            if let Some(state) = &entry.options.state {
                args = args.push(state).unwrap_or(args);
            }
            let task_id = lc.next_task_id;
            lc.next_task_id += 1;
            let elapsed = lc.schedule_q.mark_fired(id, task_id, now_sys);
            lc.persist_schedule(id);
            if entry.options.pass_elapsed {
                let secs = elapsed.map(|d| d.as_secs_f64()).unwrap_or(0.0);
                args = args.push(&v_float(secs)).unwrap_or(args);
            }
            let args = match args.variant() {
                moor_var::Variant::List(l) => l.clone(),
                _ => entry.args.clone(),
            };
            let task_start = TaskStart::StartScheduled {
                schedule_id: id,
                player,
                vloc: moor_common::model::ObjectRef::Id(entry.target),
                verb: entry.verb,
                args,
            };
            if let Err(e) = self.submit_task(
                &mut lc,
                task_id,
                &player,
                &entry.authority_principal,
                task_start,
                None,
                session,
            ) {
                warn!(schedule_id = id, error = ?e, "Could not submit schedule firing");
                lc.schedule_q.complete(
                    id,
                    task_id,
                    Outcome::Fault(v_str(&format!("{e:?}"))),
                    SystemTime::now(),
                );
                lc.persist_schedule(id);
            }
        }
    }

    /// Whether a schedule's target still exists and its verb is still callable by the
    /// schedule's authority principal, by the same rule a method call uses.
    fn schedule_target_is_valid(&self, entry: &ScheduleEntry) -> bool {
        let Ok(tx) = self.database.new_world_state() else {
            return true; // cannot check; let the firing find out
        };
        let valid = tx.valid(&entry.target).unwrap_or(false);
        if !valid {
            let _ = tx.rollback();
            return false;
        }
        let perms = moor_common::model::TaskPermissions::new(
            entry.authority_principal,
            tx.flags_of(&entry.authority_principal).unwrap_or_default(),
        );
        let found = matches!(
            tx.dispatch_verb(
                &perms,
                moor_common::model::VerbDispatch::new(
                    moor_common::model::VerbLookup::method(&entry.target, entry.verb),
                    moor_common::model::DispatchFlagsSource::Permissions,
                ),
            ),
            Ok(Some(_))
        );
        let _ = tx.rollback();
        found
    }

    /// Buffer a schedule creation for the current registration; applied when it commits.
    /// Returns the eagerly allocated schedule id even if the task no longer exists.
    #[allow(clippy::too_many_arguments)]
    pub fn handle_schedule_create(
        &self,
        task_id: TaskId,
        kind: PendingKind,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
    ) -> Result<ScheduleId, ScheduleError> {
        let mut lc = self.lifecycle.lock();
        let create = lc.reserve_schedule_create(
            kind,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
        )?;
        let id = create.id;
        if let Some(task) = lc.task_q.active.get_mut(&task_id) {
            task.effects.create_schedule(create);
        }
        Ok(id)
    }

    #[allow(clippy::too_many_arguments)]
    pub(crate) fn handle_schedule_create_for_attempt(
        &self,
        attempt: Option<&TaskAttempt>,
        kind: PendingKind,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
    ) -> Result<ScheduleId, ScheduleError> {
        let mut lc = self.lifecycle.lock();
        // Preserve validation and eager ID reservation for an absent caller. Dropping the
        // unpublished request cannot attach it to a replacement under the same task ID.
        let create = lc.reserve_schedule_create(
            kind,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
        )?;
        let id = create.id;
        if let Some(attempt) = attempt
            && lc.task_q.is_running_attempt(attempt)
        {
            lc.task_q
                .active
                .get_mut(&attempt.task_id())
                .unwrap()
                .effects
                .create_schedule(create);
        }
        Ok(id)
    }

    /// Buffer a schedule stop for the current registration; applied when it commits.
    /// A stale schedule ID returns false. Stopping another owner's live schedule returns E_PERM.
    pub fn handle_schedule_stop(
        &self,
        task_id: TaskId,
        schedule_id: ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<bool, moor_var::Error> {
        self.lifecycle
            .lock()
            .buffer_schedule_stop(task_id, schedule_id, authority)
    }

    pub(crate) fn handle_schedule_stop_for_attempt(
        &self,
        attempt: &TaskAttempt,
        schedule_id: ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<bool, moor_var::Error> {
        let mut lc = self.lifecycle.lock();
        if !lc.task_q.is_running_attempt(attempt) {
            return Ok(false);
        }
        lc.buffer_schedule_stop(attempt.task_id(), schedule_id, authority)
    }

    pub fn handle_schedule_valid(&self, task_id: TaskId, schedule_id: ScheduleId) -> bool {
        self.lifecycle
            .lock()
            .schedule_visible_to(Some(task_id), schedule_id)
    }

    pub(crate) fn handle_schedule_valid_for_attempt(
        &self,
        attempt: Option<&TaskAttempt>,
        schedule_id: ScheduleId,
    ) -> bool {
        let lc = self.lifecycle.lock();
        let task_id = attempt
            .filter(|attempt| lc.task_q.is_running_attempt(attempt))
            .map(TaskAttempt::task_id);
        lc.schedule_visible_to(task_id, schedule_id)
    }

    pub fn handle_schedule_info(
        &self,
        schedule_id: crate::tasks::schedule_q::ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<Var, moor_var::Error> {
        let lc = self.lifecycle.lock();
        let Some(entry) = lc.schedule_q.info(schedule_id) else {
            return Err(E_INVARG.msg("schedule_info: no such schedule"));
        };
        if !authority.is_wizard() && authority.principal() != entry.owner {
            return Err(E_PERM.msg("schedule_info: not the owner of this schedule"));
        }
        Ok(entry.to_info_map())
    }

    /// Ids visible to the caller: all for a wizard, own for anyone else;
    /// optionally filtered to one owner.
    pub fn handle_schedules(&self, owner: Option<Obj>, authority: &TaskPermissions) -> Vec<i64> {
        let lc = self.lifecycle.lock();
        let ids = match owner {
            Some(o) => lc.schedule_q.for_owner(&o),
            None if authority.is_wizard() => lc.schedule_q.all_ids(),
            None => lc.schedule_q.for_owner(&authority.principal()),
        };
        ids.into_iter()
            .filter(|id| {
                lc.schedule_q.info(*id).is_some_and(|e| {
                    e.is_live() && (authority.is_wizard() || e.owner == authority.principal())
                })
            })
            .map(|id| id as i64)
            .collect()
    }

    /// Live schedule ids targeting `target`. Anyone may ask: recycle and
    /// unregister paths need it regardless of who created the schedule.
    pub fn handle_schedules_for(&self, target: Obj) -> Vec<i64> {
        let lc = self.lifecycle.lock();
        lc.schedule_q
            .for_target(&target)
            .into_iter()
            .filter(|id| lc.schedule_q.is_valid(*id))
            .map(|id| id as i64)
            .collect()
    }
}

impl TaskLifecycle {
    /// Validate a creation and reserve its durable ID before buffering it in a task attempt.
    #[allow(clippy::too_many_arguments)]
    fn reserve_schedule_create(
        &mut self,
        kind: PendingKind,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
    ) -> Result<PendingCreate, ScheduleError> {
        match kind {
            PendingKind::At(when) => self.schedule_q.validate_at(when, &options)?,
            PendingKind::Every(interval) => {
                self.schedule_q
                    .validate_every(interval, &options, SystemTime::now())?
            }
        }
        Ok(PendingCreate {
            id: self.reserve_schedule_id(),
            kind,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
        })
    }

    fn buffer_schedule_stop(
        &mut self,
        task_id: TaskId,
        schedule_id: ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<bool, moor_var::Error> {
        if self
            .task_q
            .active
            .get_mut(&task_id)
            .is_some_and(|task| task.effects.cancel_created_schedule(schedule_id))
        {
            return Ok(true);
        }
        let Some(entry) = self.schedule_q.info(schedule_id) else {
            return Ok(false);
        };
        let authorized = authority.is_wizard() || authority.principal() == entry.owner;
        // A retired id is stale: false, never an error. An authorized caller can still
        // release its retained diagnostics at commit.
        let live = entry.is_live();
        if !live && !authorized {
            return Ok(false);
        }
        if !authorized {
            return Err(E_PERM.msg("schedule_stop: not the owner of this schedule"));
        }
        if let Some(task) = self.task_q.active.get_mut(&task_id) {
            task.effects.stop_schedule(schedule_id);
        }
        Ok(live)
    }

    fn schedule_visible_to(&self, task_id: Option<TaskId>, schedule_id: ScheduleId) -> bool {
        self.schedule_q.is_valid(schedule_id)
            || task_id
                .and_then(|task_id| self.task_q.active.get(&task_id))
                .is_some_and(|task| task.effects.contains_schedule(schedule_id))
    }

    /// Write a live persistent schedule, or delete a stopped, retired, or non-persistent entry.
    /// Storage errors are logged and do not reverse the in-memory schedule change.
    pub(crate) fn persist_schedule(&mut self, id: ScheduleId) {
        let db = self.task_q.suspended.tasks_db();
        match self.schedule_q.info(id) {
            Some(e) if e.is_live() && e.options.persist => {
                if let Err(err) = db.save_schedule(e) {
                    tracing::error!(schedule_id = id, ?err, "Could not save schedule");
                }
            }
            _ => {
                if let Err(err) = db.delete_schedule(id) {
                    tracing::error!(schedule_id = id, ?err, "Could not delete schedule");
                }
            }
        }
    }

    /// Allocate an ID and attempt to persist the high-water mark before returning it to MOO code.
    /// Storage errors are logged; the in-memory reservation still succeeds.
    pub(crate) fn reserve_schedule_id(&mut self) -> ScheduleId {
        let id = self.schedule_q.reserve_id();
        let next_id = self.schedule_q.next_id();
        if let Err(err) = self
            .task_q
            .suspended
            .tasks_db()
            .save_next_schedule_id(next_id)
        {
            tracing::error!(next_id, ?err, "Could not save schedule id high-water mark");
        }
        id
    }

    /// Restore persisted schedules at startup. Must run after the suspended
    /// tasks are restored: a restored `StartScheduled` task is a firing still
    /// in progress, and is re-linked to its schedule here so that the
    /// schedule is not fired a second time for the same deadline and the
    /// task's result settles it. Schedules with no restored firing go through
    /// their catchup policy inside `ScheduleQ::load`.
    ///
    /// A restored firing whose schedule was not restored (stopped, retired,
    /// or `persist: 0`) runs to completion and its result is ignored, the
    /// same as a firing whose schedule is stopped while it runs.
    /// The id counter resumes at the larger of the persisted high-water
    /// mark and one past the highest surviving id.
    pub(crate) fn load_schedules(&mut self) {
        match self.task_q.suspended.tasks_db().load_next_schedule_id() {
            Ok(Some(next_id)) => self.schedule_q.restore_next_id(next_id),
            Ok(None) => {}
            Err(err) => {
                tracing::error!(?err, "Could not load schedule id high-water mark");
            }
        }
        let entries = match self.task_q.suspended.tasks_db().load_schedules() {
            Ok(v) => v,
            Err(err) => {
                tracing::error!(?err, "Could not load schedules from tasks database");
                return;
            }
        };
        let mut firings = self.restored_schedule_firings();
        let now = std::time::SystemTime::now();
        let count = entries.len();
        for e in entries {
            let id = e.id;
            let tasks = firings.remove(&id).unwrap_or_default();
            self.schedule_q.load(e, &tasks, now);
            // Loading can retire an entry whose cadence has run out of range;
            // drop it from the store so it is not loaded again.
            if !self.schedule_q.is_valid(id) {
                self.persist_schedule(id);
            }
        }
        for (schedule_id, tasks) in firings {
            tracing::info!(
                schedule_id,
                ?tasks,
                "Restored scheduled firing has no schedule; it will run unlinked"
            );
        }
        if count > 0 {
            tracing::info!(count, "Loaded native schedules from tasks database");
        }
    }

    /// Restored suspended tasks that are schedule firings, by schedule id.
    fn restored_schedule_firings(&self) -> HashMap<ScheduleId, Vec<TaskId>> {
        let mut firings: HashMap<ScheduleId, Vec<TaskId>> = HashMap::new();
        for st in self.task_q.suspended.records() {
            if let TaskStart::StartScheduled { schedule_id, .. } = st.task.state.task_start() {
                firings
                    .entry(*schedule_id)
                    .or_default()
                    .push(st.task.task_id);
            }
        }
        firings
    }

    /// Save every live persistent schedule. Called at shutdown as a
    /// belt-and-braces pass over the write-through store.
    pub(crate) fn save_schedules(&self) {
        let db = self.task_q.suspended.tasks_db();
        for e in self.schedule_q.persistable() {
            if let Err(err) = db.save_schedule(e) {
                tracing::error!(schedule_id = e.id, ?err, "Could not save schedule");
            }
        }
    }

    /// Settle native-schedule firings against the terminal results delivered
    /// since the last call: re-arm or retire each schedule whose task just
    /// ended. Conflict retries never produce a terminal result, so they never
    /// reach here (the retry is the same firing). Cheap when nothing is
    /// scheduled; called from the terminal callbacks and the timer loop.
    pub(crate) fn settle_schedule_firings(&mut self) {
        if self.task_q.settled_results.is_empty() {
            return;
        }
        let results = std::mem::take(&mut self.task_q.settled_results);
        let now = std::time::SystemTime::now();
        for (task_id, result) in results {
            let Some(schedule_id) = self.schedule_q.schedule_for_task(task_id) else {
                continue;
            };
            let outcome = match result {
                Ok(v) => crate::tasks::schedule_q::Outcome::Success(v),
                Err(moor_common::tasks::SchedulerError::TaskAbortedException(e)) => {
                    crate::tasks::schedule_q::Outcome::Fault(moor_var::v_error(e.error))
                }
                Err(e) => {
                    crate::tasks::schedule_q::Outcome::Fault(moor_var::v_str(&format!("{e:?}")))
                }
            };
            self.schedule_q.complete(schedule_id, task_id, outcome, now);
            self.persist_schedule(schedule_id);
        }
    }
}

#[cfg(test)]
mod tests;
