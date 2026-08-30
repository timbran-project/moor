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

//! Transaction-local narrative event buffering and event-log commit logic shared by every
//! daemon-side [`moor_common::tasks::Session`] implementation.
//!
//! A session buffers the events a task produces until the task's transaction commits. On commit
//! the buffered events are written to the event log; the subset that is also deliverable is
//! handed back to the caller so that it can broadcast it (`RpcSession`) or capture it
//! (`OutputCaptureSession`). On rollback the buffers are discarded and nothing is logged.

use std::sync::{Arc, Mutex};

use moor_common::tasks::NarrativeEvent;
use moor_var::Obj;

use crate::event_log::{EventLogOps, logged_narrative_event_to_flatbuffer};

/// Which player a session's events are logged under.
///
/// `active_player` is the player the session currently speaks for. `history_player` is the
/// identity whose event log receives events addressed to the active player; the two differ when
/// a player switch preserves the previous history owner.
#[derive(Clone, Copy)]
pub struct SessionIdentity {
    pub active_player: Obj,
    pub history_player: Obj,
}

/// Buffered narrative events for one session, plus the shared event-log commit rules.
pub struct SessionEventBuffer {
    /// Shared event log for persistent storage across all sessions
    event_log: Arc<dyn EventLogOps>,
    identity: Mutex<SessionIdentity>,
    /// Transaction-local buffer for events pending commit (both logged and delivered)
    transaction_buffer: Mutex<Vec<(Obj, Box<NarrativeEvent>)>>,
    /// Transaction-local buffer for log-only events (logged but not delivered)
    log_only_buffer: Mutex<Vec<(Obj, Box<NarrativeEvent>)>>,
}

impl SessionEventBuffer {
    pub fn new(event_log: Arc<dyn EventLogOps>, active_player: Obj, history_player: Obj) -> Self {
        Self {
            event_log,
            identity: Mutex::new(SessionIdentity {
                active_player,
                history_player,
            }),
            transaction_buffer: Mutex::new(Vec::new()),
            log_only_buffer: Mutex::new(Vec::new()),
        }
    }

    /// The event log this buffer writes to, for handing to a forked session.
    pub fn event_log(&self) -> Arc<dyn EventLogOps> {
        self.event_log.clone()
    }

    /// Current identity of the session.
    pub fn identity(&self) -> SessionIdentity {
        *self.identity.lock().unwrap()
    }

    /// Point the session at a new active player, optionally keeping the old history owner.
    pub fn switch_player_identity(&self, new_player: Obj, preserve_history: bool) {
        let mut identity = self.identity.lock().unwrap();
        identity.active_player = new_player;
        if !preserve_history {
            identity.history_player = new_player;
        }
    }

    /// Buffer an event that is both logged and delivered on commit.
    pub fn push_event(&self, player: Obj, event: Box<NarrativeEvent>) {
        self.transaction_buffer
            .lock()
            .unwrap()
            .push((player, event));
    }

    /// Buffer an event that is logged but never delivered.
    pub fn push_log_only_event(&self, player: Obj, event: Box<NarrativeEvent>) {
        self.log_only_buffer.lock().unwrap().push((player, event));
    }

    /// Commit the buffered events: write every buffered event to the event log and return the
    /// deliverable ones, in order. Both buffers are emptied.
    pub fn commit(&self) -> Vec<(Obj, Box<NarrativeEvent>)> {
        let events: Vec<_> = self.transaction_buffer.lock().unwrap().drain(..).collect();
        let log_only_events: Vec<_> = self.log_only_buffer.lock().unwrap().drain(..).collect();

        let identity = self.identity();

        // Log events from both buffers to the event log. Only events addressed to the active
        // player follow the session's selected history owner; events for other players do not.
        for (player, event) in events.iter().chain(log_only_events.iter()) {
            let history_player = if *player == identity.active_player {
                identity.history_player
            } else {
                *player
            };
            let Some(pubkey) = self.event_log.get_pubkey(history_player) else {
                continue;
            };

            // Convert to FlatBuffer LoggedNarrativeEvent (always encrypted)
            if let Ok((logged_event, presentation_action)) =
                logged_narrative_event_to_flatbuffer(history_player, event.clone(), pubkey)
            {
                self.event_log.append(logged_event, presentation_action);
            }
        }

        events
    }

    /// Discard every buffered event without logging any of it.
    pub fn rollback(&self) {
        self.transaction_buffer.lock().unwrap().clear();
        self.log_only_buffer.lock().unwrap().clear();
    }
}
