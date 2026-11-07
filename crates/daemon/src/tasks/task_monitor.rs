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

//! Task completion monitoring and lifecycle management

use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use uuid::Uuid;

use crate::rpc::{DeferredCalls, SessionActions};
use flume::Sender;
use moor_common::tasks::{TaskEnding, TaskId};
use moor_kernel::tasks::TaskHandle;
use moor_runtime_api::api::ClientEvent;

/// Who is told about a monitored task.
#[derive(Clone)]
enum TaskOwner {
    /// A connected client, through published events.
    Client(Uuid),
    /// A captured call waiting for this task.
    Deferred(Arc<DeferredCalls>),
}

/// Monitors task completions and handles their lifecycle
pub struct TaskMonitor {
    task_handles: papaya::HashMap<TaskId, (TaskOwner, TaskHandle)>,
    mailbox_sender: Sender<SessionActions>,
    wake_signal: (Sender<()>, flume::Receiver<()>),
}

impl TaskMonitor {
    pub fn new(mailbox_sender: Sender<SessionActions>) -> Arc<Self> {
        let wake_signal = flume::unbounded();
        let monitor = Self {
            task_handles: papaya::HashMap::new(),
            mailbox_sender,
            wake_signal,
        };

        Arc::new(monitor)
    }

    pub fn add_task(
        &self,
        task_id: TaskId,
        client_id: Uuid,
        task_handle: TaskHandle,
    ) -> Result<(), String> {
        self.insert_task(task_id, TaskOwner::Client(client_id), task_handle)
    }

    /// Monitor a task on behalf of a captured call, which was added to `deferred` first.
    pub(crate) fn add_deferred_task(
        &self,
        task_id: TaskId,
        task_handle: TaskHandle,
        deferred: Arc<DeferredCalls>,
    ) -> Result<(), String> {
        self.insert_task(task_id, TaskOwner::Deferred(deferred), task_handle)
    }

    fn insert_task(
        &self,
        task_id: TaskId,
        owner: TaskOwner,
        task_handle: TaskHandle,
    ) -> Result<(), String> {
        // Insert the task handle into the map
        let guard = self.task_handles.guard();
        if self
            .task_handles
            .insert(task_id, (owner, task_handle), &guard)
            .is_some()
        {
            Err(format!("Task ID {task_id} already exists"))
        } else {
            // Signal the waiting thread that a new task was added
            let _ = self.wake_signal.0.try_send(());
            Ok(())
        }
    }

    /// Block indefinitely waiting for task completions until kill switch is activated
    pub fn wait_for_completions(&self, kill_switch: Arc<AtomicBool>) {
        loop {
            if kill_switch.load(Ordering::Relaxed) {
                return;
            }

            // Collect all the receives into one select
            let task_count = self.task_handles.len();
            let mut receives = Vec::with_capacity(task_count);
            let mut task_client_ids = Vec::with_capacity(task_count);

            {
                let guard = self.task_handles.guard();
                for (task_id, (owner, task_handle)) in self.task_handles.iter(&guard) {
                    receives.push(task_handle.receiver().clone());
                    task_client_ids.push((*task_id, owner.clone()));
                }
            }

            // Wait on the new-task signal as well as every task, so a task added now is noticed
            // without waiting for another task to finish or for the timeout.
            let selector = flume::Selector::new().recv(&self.wake_signal.1, |_| None);

            // Add all task receivers to the selector with their index as the mapped value
            let selector = receives
                .iter()
                .enumerate()
                .fold(selector, |sel, (index, recv)| {
                    sel.recv(recv, move |result| Some((index, result)))
                });

            match selector.wait_timeout(Duration::from_millis(1000)) {
                Ok(Some((index, result))) => {
                    self.process_task_completion(index, result, &task_client_ids);
                }
                Ok(None) => {
                    // New tasks were added. One rebuild covers them all.
                    while self.wake_signal.1.try_recv().is_ok() {}
                }
                Err(_) => {
                    // Timeout, check kill switch and continue
                }
            }
        }
    }

    fn process_task_completion(
        &self,
        index: usize,
        result: Result<moor_kernel::tasks::TaskResult, flume::RecvError>,
        task_client_ids: &[(TaskId, TaskOwner)],
    ) {
        let task_id = task_client_ids[index].0;
        let guard = self.task_handles.guard();
        let client_id = match &task_client_ids[index].1 {
            TaskOwner::Client(client_id) => *client_id,
            TaskOwner::Deferred(deferred) => {
                match result {
                    Ok((task_id, outcome)) => {
                        let suspended = outcome.ending == TaskEnding::Suspended;
                        deferred.task_result(task_id, outcome);
                        if !suspended {
                            self.task_handles.remove(&task_id, &guard);
                        }
                    }
                    Err(_) => {
                        deferred.result_channel_closed(task_id);
                        self.task_handles.remove(&task_id, &guard);
                    }
                }
                return;
            }
        };
        match result {
            Ok((task_id, outcome)) => {
                // A suspended task is still running, so its handle stays until it ends.
                let ended = outcome.ending != TaskEnding::Suspended;
                let client_event = ClientEvent::TaskOutcome {
                    task_id: task_id as u64,
                    outcome,
                };
                if let Err(e) = self
                    .mailbox_sender
                    .send(SessionActions::PublishTaskCompletion(
                        client_id,
                        client_event,
                    ))
                {
                    tracing::error!(error = ?e, client_id = ?client_id, "Failed to send task outcome for publishing");
                }
                if ended {
                    self.task_handles.remove(&task_id, &guard);
                }
            }
            Err(_e) => {
                self.task_handles.remove(&task_id, &guard);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_common::tasks::TaskOutcome;
    use moor_var::v_int;
    use std::time::Instant;

    #[test]
    fn a_new_task_is_noticed_while_other_tasks_are_waiting() {
        let (mailbox_sender, mailbox) = flume::unbounded();
        let monitor = TaskMonitor::new(mailbox_sender);
        let kill_switch = Arc::new(AtomicBool::new(false));

        let (_waiting_send, waiting_receive) = flume::unbounded();
        monitor
            .add_task(1, Uuid::new_v4(), TaskHandle::new_mock(1, waiting_receive))
            .unwrap();

        let thread = std::thread::spawn({
            let monitor = monitor.clone();
            let kill_switch = kill_switch.clone();
            move || monitor.wait_for_completions(kill_switch)
        });
        // Let the monitor settle into waiting on the first task alone.
        std::thread::sleep(Duration::from_millis(100));

        let (finished_send, finished_receive) = flume::unbounded();
        finished_send
            .send((2, TaskOutcome::completed(v_int(1))))
            .unwrap();
        let added = Instant::now();
        monitor
            .add_task(2, Uuid::new_v4(), TaskHandle::new_mock(2, finished_receive))
            .unwrap();

        let published = mailbox.recv_timeout(Duration::from_secs(5));
        let elapsed = added.elapsed();
        kill_switch.store(true, Ordering::Relaxed);
        monitor.wake_signal.0.send(()).unwrap();
        thread.join().unwrap();

        assert!(matches!(
            published,
            Ok(SessionActions::PublishTaskCompletion(
                _,
                ClientEvent::TaskOutcome { task_id: 2, outcome }
            )) if outcome == TaskOutcome::completed(v_int(1))
        ));
        assert!(
            elapsed < Duration::from_millis(500),
            "new task's result took {elapsed:?} to be noticed"
        );
    }
}
