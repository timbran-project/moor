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

//! Pending effects belong to the active transaction attempt. Removing that attempt
//! drops unpublished effects. Publication consumes them before a new attempt starts.

use super::lifecycle::TaskLifecycle;
use crate::tasks::schedule_q::{PendingCreate, ScheduleId};
use moor_common::tasks::TaskId;
use moor_var::Var;

/// A schedule mutation a task has asked for but not yet committed. Flushed to
/// the `ScheduleQ` when the task commits, discarded on rollback or conflict
/// retry, so `schedule_at()` behaves like a world-state write rather than
/// like `fork`.
#[derive(Debug)]
enum PendingScheduleOp {
    Create(Box<crate::tasks::schedule_q::PendingCreate>),
    Stop(ScheduleId),
}

#[derive(Default)]
pub(crate) struct PendingTaskEffects {
    messages: Vec<(TaskId, Var)>,
    schedules: Vec<PendingScheduleOp>,
}

impl PendingTaskEffects {
    pub(crate) fn send(&mut self, target: TaskId, value: Var) {
        self.messages.push((target, value));
    }

    pub(crate) fn messages_for(&self, target: TaskId) -> usize {
        self.messages.iter().filter(|(id, _)| *id == target).count()
    }

    pub(crate) fn create_schedule(&mut self, create: PendingCreate) {
        self.schedules
            .push(PendingScheduleOp::Create(Box::new(create)));
    }

    pub(crate) fn contains_schedule(&self, id: ScheduleId) -> bool {
        self.schedules
            .iter()
            .any(|op| matches!(op, PendingScheduleOp::Create(c) if c.id == id))
    }

    pub(crate) fn cancel_created_schedule(&mut self, id: ScheduleId) -> bool {
        let created = self.contains_schedule(id);
        self.schedules
            .retain(|op| !matches!(op, PendingScheduleOp::Create(c) if c.id == id));
        created
    }

    pub(crate) fn stop_schedule(&mut self, id: ScheduleId) {
        self.schedules.push(PendingScheduleOp::Stop(id));
    }

    fn publish(self, lifecycle: &mut TaskLifecycle) {
        // Schedules become visible before messages, preserving boundary ordering.
        let now = std::time::SystemTime::now();
        for op in self.schedules {
            match op {
                PendingScheduleOp::Create(create) => {
                    let id = create.id;
                    lifecycle.schedule_q.add_pending(*create, now);
                    lifecycle.persist_schedule(id);
                }
                PendingScheduleOp::Stop(id) => {
                    lifecycle.schedule_q.stop(id);
                    lifecycle.persist_schedule(id);
                }
            }
        }
        for (target, value) in self.messages {
            lifecycle.task_q.deliver_message(target, value);
        }
    }
}

impl TaskLifecycle {
    pub(crate) fn publish_task_effects(&mut self, task_id: TaskId) {
        if let Some(task) = self.task_q.active.get_mut(&task_id) {
            let effects = std::mem::take(&mut task.effects);
            effects.publish(self);
        }
    }

    pub(crate) fn discard_task_effects(&mut self, task_id: TaskId) {
        if let Some(task) = self.task_q.active.get_mut(&task_id) {
            task.effects = PendingTaskEffects::default();
        }
    }
}
