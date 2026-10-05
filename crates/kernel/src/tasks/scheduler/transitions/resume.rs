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

//! Explicit resumption and input-driven wakeup of suspended tasks.

use crate::tasks::{TaskStart, scheduler::Scheduler};
use moor_common::{model::TaskPermissions, tasks::TaskId};
use moor_var::{E_INVIND, Error, Obj, SYSTEM_OBJECT, Var};
use tracing::{error, warn};

impl Scheduler {
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
}

#[cfg(test)]
mod tests;
