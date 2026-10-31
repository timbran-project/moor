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

//! Writes saved tasks to the tasks database on a thread of its own, so that serializing and
//! compressing them doesn't hold the scheduler's lock. Saves and deletes go through one queue in
//! the order they were asked for, so a delete can't be overtaken by an earlier save of that task.

use crate::tasks::{TasksDb, convert_task::SavedTask};
use moor_common::tasks::TaskId;
use std::{sync::Arc, thread::JoinHandle};
use tracing::error;

enum WriterMessage {
    Save(Vec<SavedTask>),
    Delete(TaskId),
    /// Answer once everything sent before this has been written.
    Barrier(flume::Sender<()>),
}

pub(super) struct TaskWriter {
    messages: Option<flume::Sender<WriterMessage>>,
    thread: Option<JoinHandle<()>>,
}

impl TaskWriter {
    pub(super) fn new(tasks_db: Arc<dyn TasksDb>) -> Self {
        let (messages, received) = flume::unbounded();
        let thread = std::thread::Builder::new()
            .name("moor-tasks-writer".to_string())
            .spawn(move || write_tasks(tasks_db.as_ref(), received))
            .expect("Unable to start the tasks writer thread");
        Self {
            messages: Some(messages),
            thread: Some(thread),
        }
    }

    pub(super) fn save(&self, tasks: Vec<SavedTask>) {
        self.send(WriterMessage::Save(tasks));
    }

    pub(super) fn delete(&self, task_id: TaskId) {
        self.send(WriterMessage::Delete(task_id));
    }

    /// Wait until everything asked for so far has been written.
    pub(super) fn wait_until_written(&self) {
        let (written, wait) = flume::bounded(1);
        self.send(WriterMessage::Barrier(written));
        if wait.recv().is_err() {
            error!("The tasks writer stopped before finishing its work");
        }
    }

    fn send(&self, message: WriterMessage) {
        let sent = self
            .messages
            .as_ref()
            .map(|messages| messages.send(message));
        if !matches!(sent, Some(Ok(()))) {
            error!("The tasks writer has stopped; a suspended task's record may be out of date");
        }
    }
}

impl Drop for TaskWriter {
    fn drop(&mut self) {
        // Closing the queue lets the thread finish what it was already given, and end.
        self.messages.take();
        if let Some(thread) = self.thread.take()
            && thread.join().is_err()
        {
            error!("The tasks writer thread panicked");
        }
    }
}

fn write_tasks(tasks_db: &dyn TasksDb, received: flume::Receiver<WriterMessage>) {
    for message in received {
        match message {
            WriterMessage::Save(tasks) => {
                for task in &tasks {
                    if let Err(error) = tasks_db.save_task(task) {
                        error!(?error, "Could not save suspended task");
                    }
                }
            }
            // Preserve the best-effort deletion policy, including absent records.
            WriterMessage::Delete(task_id) => {
                let _ = tasks_db.delete_task(task_id);
            }
            WriterMessage::Barrier(written) => {
                let _ = written.send(());
            }
        }
    }
}
