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

use std::sync::Arc;

use flume::Sender;
use std::sync::Mutex;
use uuid::Uuid;

use moor_common::tasks::{ConnectionDetails, NarrativeEvent, Session, SessionError};
use moor_runtime_api::api::ClientEvent;
use moor_var::{Obj, Symbol, Var};

use crate::{
    connections::ConnectionStateSource,
    event_log::{EventLogOps, logged_narrative_event_to_flatbuffer},
};

/// A "session" that runs over the RPC system.
pub struct RpcSession {
    client_id: Uuid,
    connection: Obj,
    identity: Mutex<SessionIdentity>,
    /// Shared event log for persistent storage across all sessions
    event_log: Arc<dyn EventLogOps>,
    connection_state: Arc<dyn ConnectionStateSource>,
    /// Transaction-local buffer for events pending commit (both logged and broadcast)
    transaction_buffer: Mutex<Vec<(Obj, Box<NarrativeEvent>)>>,
    /// Transaction-local buffer for log-only events (logged but not broadcast)
    log_only_buffer: Mutex<Vec<(Obj, Box<NarrativeEvent>)>>,
    send: Sender<SessionActions>,
}

#[derive(Clone, Copy)]
struct SessionIdentity {
    active_player: Obj,
    history_player: Obj,
}

pub enum SessionActions {
    PublishNarrativeEvents(Vec<(Obj, Box<NarrativeEvent>)>),
    RequestClientInput {
        client_id: Uuid,
        connection: Obj,
        request_id: Uuid,
        metadata: Option<Vec<(Symbol, Var)>>,
    },
    SendSystemMessage {
        client_id: Uuid,
        connection: Obj,
        system_message: String,
    },
    Disconnect(Uuid, Obj),
    SetClientAttribute(Uuid, Obj, Symbol, Var),
    PublishTaskCompletion(Uuid, ClientEvent),
}

impl RpcSession {
    pub fn new(
        client_id: Uuid,
        connection: Obj,
        active_player: Obj,
        history_player: Obj,
        event_log: Arc<dyn EventLogOps>,
        connection_state: Arc<dyn ConnectionStateSource>,
        sender: Sender<SessionActions>,
    ) -> Self {
        Self {
            client_id,
            connection,
            identity: Mutex::new(SessionIdentity {
                active_player,
                history_player,
            }),
            event_log,
            connection_state,
            transaction_buffer: Mutex::new(Vec::new()),
            log_only_buffer: Mutex::new(Vec::new()),
            send: sender,
        }
    }
}

impl Session for RpcSession {
    fn switch_player_identity(&self, new_player: Obj, preserve_history: bool) {
        let mut identity = self.identity.lock().unwrap();
        identity.active_player = new_player;
        if !preserve_history {
            identity.history_player = new_player;
        }
    }

    fn commit(&self) -> Result<(), SessionError> {
        let events: Vec<_> = {
            let mut transaction_buffer = self.transaction_buffer.lock().unwrap();
            transaction_buffer.drain(..).collect()
        };
        let log_only_events: Vec<_> = {
            let mut log_only_buffer = self.log_only_buffer.lock().unwrap();
            log_only_buffer.drain(..).collect()
        };

        let identity = *self.identity.lock().unwrap();

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

        // Only publish regular events to connected clients (not log_only_events)
        self.send
            .send(SessionActions::PublishNarrativeEvents(events))
            .map_err(|e| SessionError::CommitError(e.to_string()))?;
        Ok(())
    }

    fn rollback(&self) -> Result<(), SessionError> {
        self.transaction_buffer.lock().unwrap().clear();
        self.log_only_buffer.lock().unwrap().clear();
        Ok(())
    }

    fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        let identity = *self.identity.lock().unwrap();
        Ok(Arc::new(Self::new(
            self.client_id,
            self.connection,
            identity.active_player,
            identity.history_player,
            self.event_log.clone(),
            self.connection_state.clone(),
            self.send.clone(),
        )))
    }

    fn request_input(
        &self,
        player: Obj,
        input_request_id: Uuid,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), SessionError> {
        self.send
            .send(SessionActions::RequestClientInput {
                client_id: self.client_id,
                connection: player,
                request_id: input_request_id,
                metadata,
            })
            .map_err(|e| SessionError::CommitError(e.to_string()))?;
        Ok(())
    }

    fn send_event(&self, player: Obj, event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.transaction_buffer
            .lock()
            .unwrap()
            .push((player, event));
        Ok(())
    }

    fn log_event(&self, player: Obj, event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.log_only_buffer.lock().unwrap().push((player, event));
        Ok(())
    }

    fn send_system_msg(&self, player: Obj, msg: &str) -> Result<(), SessionError> {
        self.send
            .send(SessionActions::SendSystemMessage {
                client_id: self.client_id,
                connection: player,
                system_message: msg.to_string(),
            })
            .map_err(|e| SessionError::CommitError(e.to_string()))?;
        Ok(())
    }

    fn notify_shutdown(&self, msg: Option<String>) -> Result<(), SessionError> {
        let shutdown_msg = match msg {
            Some(msg) => format!("** Server is shutting down: {msg} **"),
            None => "** Server is shutting down ** ".to_string(),
        };
        self.send
            .send(SessionActions::SendSystemMessage {
                client_id: self.client_id,
                connection: self.connection,
                system_message: shutdown_msg,
            })
            .map_err(|e| SessionError::CommitError(e.to_string()))
    }

    fn connection_name(&self, player: Obj) -> Result<String, SessionError> {
        self.connection_state.connection_name(player)
    }

    fn disconnect(&self, player: Obj) -> Result<(), SessionError> {
        self.send
            .send(SessionActions::Disconnect(self.client_id, player))
            .map_err(|_e| SessionError::DeliveryError)?;
        Ok(())
    }

    fn connected_players(&self, include_all: bool) -> Result<Vec<Obj>, SessionError> {
        Ok(self.connection_state.connected_players(include_all))
    }

    fn connected_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        self.connection_state.connected_seconds(player)
    }

    fn idle_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        self.connection_state.idle_seconds(player)
    }

    fn connections(&self, player: Option<Obj>) -> Result<Vec<Obj>, SessionError> {
        self.connection_state
            .connections_for(self.client_id, player)
    }

    fn connection_details(
        &self,
        player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        self.connection_state
            .connection_details(self.client_id, player)
    }

    fn connection_attributes(&self, obj: Obj) -> Result<Var, SessionError> {
        self.connection_state.connection_attributes(obj)
    }

    fn set_connection_attribute(
        &self,
        connection_obj: Obj,
        key: Symbol,
        value: Var,
    ) -> Result<(), SessionError> {
        self.send
            .send(SessionActions::SetClientAttribute(
                self.client_id,
                connection_obj,
                key,
                value,
            ))
            .map_err(|_e| SessionError::DeliveryError)?;
        Ok(())
    }
}
