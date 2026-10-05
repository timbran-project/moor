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

//! Native schedule requests and task firing policy.

use crate::tasks::scheduler::Scheduler;
use moor_common::{model::TaskPermissions, tasks::TaskId};
use moor_var::{E_INVARG, E_PERM, List, Obj, Symbol, Var};
use std::time::SystemTime;

impl Scheduler {
    /// Buffer a schedule creation for `task_id`; applied when it commits.
    /// Returns the eagerly allocated schedule id.
    #[allow(clippy::too_many_arguments)]
    pub fn handle_schedule_create(
        &self,
        task_id: TaskId,
        kind: crate::tasks::schedule_q::PendingKind,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: crate::tasks::schedule_q::ScheduleOptions,
    ) -> Result<crate::tasks::schedule_q::ScheduleId, crate::tasks::schedule_q::ScheduleError> {
        use crate::tasks::schedule_q::{PendingCreate, PendingKind};
        let mut lc = self.lifecycle.lock();
        match kind {
            PendingKind::At(when) => lc.schedule_q.validate_at(when, &options)?,
            PendingKind::Every(interval) => {
                lc.schedule_q
                    .validate_every(interval, &options, SystemTime::now())?
            }
        }
        let id = lc.reserve_schedule_id();
        if let Some(task) = lc.task_q.active.get_mut(&task_id) {
            task.effects.create_schedule(PendingCreate {
                id,
                kind,
                target,
                verb,
                args,
                authority_principal,
                owner,
                options,
            });
        }
        Ok(id)
    }

    /// Buffer a schedule stop for `task_id`; applied when it commits. Returns
    /// whether the id currently refers to a live schedule (or one this task
    /// created and has not yet committed). Never raises: a stale id is an
    /// ordinary race, not an error.
    pub fn handle_schedule_stop(
        &self,
        task_id: TaskId,
        schedule_id: crate::tasks::schedule_q::ScheduleId,
        authority: &TaskPermissions,
    ) -> Result<bool, moor_var::Error> {
        let mut lc = self.lifecycle.lock();
        if lc
            .task_q
            .active
            .get_mut(&task_id)
            .is_some_and(|task| task.effects.cancel_created_schedule(schedule_id))
        {
            return Ok(true);
        }
        let Some(entry) = lc.schedule_q.info(schedule_id) else {
            return Ok(false);
        };
        let authorized = authority.is_wizard() || authority.principal() == entry.owner;
        // A retired id is stale: `false`, never an error. Its owner (or a
        // wizard) stopping it releases the retained diagnostics on commit.
        let live = entry.is_live();
        if !live && !authorized {
            return Ok(false);
        }
        if !authorized {
            return Err(E_PERM.msg("schedule_stop: not the owner of this schedule"));
        }
        if let Some(task) = lc.task_q.active.get_mut(&task_id) {
            task.effects.stop_schedule(schedule_id);
        }
        Ok(live)
    }

    pub fn handle_schedule_valid(
        &self,
        task_id: TaskId,
        schedule_id: crate::tasks::schedule_q::ScheduleId,
    ) -> bool {
        let lc = self.lifecycle.lock();
        if lc.schedule_q.is_valid(schedule_id) {
            return true;
        }
        lc.task_q
            .active
            .get(&task_id)
            .is_some_and(|task| task.effects.contains_schedule(schedule_id))
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
