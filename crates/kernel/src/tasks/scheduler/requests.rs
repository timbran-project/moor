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

//! External request adapters for scheduler status, shutdown, and object operations.
//!
//! The client service executes queued closures that call these methods. Each adapter delegates
//! to the owning domain. Direct world-state batches use the existing executor and wait for its
//! result outside the lifecycle lock; task-based batches enter through `admission`.

use super::{Scheduler, SchedulerState};
use crate::tasks::{
    world_state_action::{WorldStateAction, WorldStateResponse},
    world_state_executor::WorldStateActionExecutor,
};
use moor_common::{
    tasks::{CommandError, SchedulerError, SchedulerError::CommandExecutionError},
    threading::spawn_perf,
};
use moor_var::Obj;

impl Scheduler {
    pub(crate) fn handle_shutdown_request(&self, msg: String) -> Result<(), SchedulerError> {
        self.stop(Some(msg))
    }

    pub(crate) fn handle_check_status(&self) -> Result<(), SchedulerError> {
        if self.lifecycle.lock().state != SchedulerState::Running {
            return Err(SchedulerError::SchedulerNotResponding);
        }
        Ok(())
    }

    pub(crate) fn handle_load_object_request(
        &self,
        object_definition: String,
        options: moor_objdef::ObjDefLoaderOptions,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        self.handle_load_object(object_definition, options)
    }

    pub(crate) fn handle_reload_object_request(
        &self,
        object_definition: String,
        constants: Option<moor_objdef::Constants>,
        target_obj: Option<Obj>,
    ) -> Result<moor_objdef::ObjDefLoaderResults, SchedulerError> {
        self.handle_reload_object(object_definition, constants, target_obj)
    }

    pub(crate) fn execute_world_state_actions_inner(
        &self,
        actions: Vec<crate::tasks::world_state_action::WorldStateRequest>,
        rollback: bool,
    ) -> Result<Vec<WorldStateResponse>, SchedulerError> {
        // Create transaction in caller's context
        let tx = self
            .database
            .new_world_state()
            .map_err(|e| CommandExecutionError(CommandError::DatabaseError(e)))?;

        // Extract just the actions from the requests
        let action_vec: Vec<WorldStateAction> =
            actions.iter().map(|req| req.action.clone()).collect();
        let config = self.config.clone();

        // Use a channel to get the result back from the spawned thread
        let (tx_send, rx_recv) = std::sync::mpsc::channel();

        // Spawn thread to execute actions, moving transaction into the thread
        spawn_perf("ws-actions", move || {
            let executor = WorldStateActionExecutor::new(tx, config);

            match executor.execute_batch(action_vec, rollback) {
                Ok(results) => {
                    // Build responses with the original request IDs
                    let responses: Vec<WorldStateResponse> = actions
                        .into_iter()
                        .zip(results)
                        .map(|(request, result)| WorldStateResponse::Success {
                            id: request.id,
                            result,
                        })
                        .collect();

                    let _ = tx_send.send(Ok(responses));
                }
                Err(error) => {
                    let _ = tx_send.send(Err(error));
                }
            }
        })
        .expect("Could not spawn WorldStateAction execution thread");

        rx_recv
            .recv()
            .map_err(|_| SchedulerError::CouldNotStartTask)?
    }
}
