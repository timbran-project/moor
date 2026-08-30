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
use uuid::Uuid;

use moor_common::tasks::{ConnectionDetails, NarrativeEvent, Session, SessionError};
use moor_runtime_api::api::ClientEvent;
use moor_var::{Obj, Symbol, Var};

use crate::{
    connections::ConnectionStateSource, event_log::EventLogOps,
    rpc::session_event_buffer::SessionEventBuffer,
};

/// A "session" that runs over the RPC system.
pub struct RpcSession {
    client_id: Uuid,
    connection: Obj,
    /// Buffered events and the shared event-log commit rules.
    events: SessionEventBuffer,
    connection_state: Arc<dyn ConnectionStateSource>,
    send: Sender<SessionActions>,
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
            events: SessionEventBuffer::new(event_log, active_player, history_player),
            connection_state,
            send: sender,
        }
    }
}

impl Session for RpcSession {
    fn switch_player_identity(&self, new_player: Obj, preserve_history: bool) {
        self.events
            .switch_player_identity(new_player, preserve_history);
    }

    fn commit(&self) -> Result<(), SessionError> {
        // Writes both buffers to the event log and hands back the deliverable events.
        let events = self.events.commit();

        // Only publish regular events to connected clients (not log_only_events)
        self.send
            .send(SessionActions::PublishNarrativeEvents(events))
            .map_err(|e| SessionError::CommitError(e.to_string()))?;
        Ok(())
    }

    fn rollback(&self) -> Result<(), SessionError> {
        self.events.rollback();
        Ok(())
    }

    fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        let identity = self.events.identity();
        Ok(Arc::new(Self::new(
            self.client_id,
            self.connection,
            identity.active_player,
            identity.history_player,
            self.events.event_log(),
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
        self.events.push_event(player, event);
        Ok(())
    }

    fn log_event(&self, player: Obj, event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.events.push_log_only_event(player, event);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{connections::ConnectionRegistryFactory, testing::MockEventLog};
    use moor_var::{v_obj, v_str};

    /// An age/X25519 recipient key; the event log encrypts every event it stores.
    const TEST_PUBKEY: &str = "age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj";

    fn event(msg: &str) -> Box<NarrativeEvent> {
        Box::new(NarrativeEvent::notify(
            v_obj(Obj::mk_id(1)),
            v_str(msg),
            None,
            false,
            false,
            None,
        ))
    }

    struct Harness {
        session: Arc<RpcSession>,
        log: Arc<MockEventLog>,
        actions: flume::Receiver<SessionActions>,
        player: Obj,
    }

    fn harness() -> Harness {
        let log = Arc::new(MockEventLog::new());
        let player = Obj::mk_id(2);
        log.set_pubkey(player, TEST_PUBKEY.to_string());
        let (tx, actions) = flume::unbounded();
        let connections = ConnectionRegistryFactory::in_memory_only().unwrap();
        let session = Arc::new(RpcSession::new(
            Uuid::new_v4(),
            player,
            player,
            player,
            log.clone(),
            connections,
            tx,
        ));
        Harness {
            session,
            log,
            actions,
            player,
        }
    }

    fn published(actions: &flume::Receiver<SessionActions>) -> Vec<(Obj, Box<NarrativeEvent>)> {
        match actions.try_recv() {
            Ok(SessionActions::PublishNarrativeEvents(events)) => events,
            Ok(_) => panic!("expected narrative events"),
            Err(e) => panic!("no session action published: {e}"),
        }
    }

    #[test]
    fn commit_logs_both_buffers_and_publishes_only_send_events() {
        let h = harness();

        h.session.send_event(h.player, event("broadcast")).unwrap();
        h.session.log_event(h.player, event("log-only")).unwrap();
        h.session.commit().unwrap();

        // Both events reach the event log; only the send_event is published.
        assert_eq!(h.log.narrative_event_count(), 2);
        assert_eq!(published(&h.actions).len(), 1);
    }

    #[test]
    fn rollback_discards_buffered_events() {
        let h = harness();

        h.session.send_event(h.player, event("doomed")).unwrap();
        h.session.log_event(h.player, event("doomed too")).unwrap();
        h.session.rollback().unwrap();
        h.session.commit().unwrap();

        assert_eq!(h.log.narrative_event_count(), 0);
        assert!(published(&h.actions).is_empty());
    }

    #[test]
    fn events_without_a_pubkey_are_not_logged_but_are_still_published() {
        let h = harness();
        let other = Obj::mk_id(7);

        h.session.send_event(other, event("no pubkey")).unwrap();
        h.session.commit().unwrap();

        assert_eq!(h.log.narrative_event_count(), 0);
        assert_eq!(published(&h.actions).len(), 1);
    }

    #[test]
    fn switching_player_without_preserving_history_moves_the_log_owner() {
        let h = harness();
        let new_player = Obj::mk_id(9);
        h.log.set_pubkey(new_player, TEST_PUBKEY.to_string());

        h.session.switch_player_identity(new_player, false);
        h.session
            .send_event(new_player, event("after switch"))
            .unwrap();
        h.session.commit().unwrap();

        assert_eq!(h.log.event_count_for_player(new_player), 1);
        assert_eq!(h.log.event_count_for_player(h.player), 0);
    }

    #[test]
    fn switching_player_preserving_history_keeps_the_old_log_owner() {
        let h = harness();
        let new_player = Obj::mk_id(9);
        h.log.set_pubkey(new_player, TEST_PUBKEY.to_string());

        h.session.switch_player_identity(new_player, true);
        h.session
            .send_event(new_player, event("after switch"))
            .unwrap();
        h.session.commit().unwrap();

        assert_eq!(h.log.event_count_for_player(h.player), 1);
        assert_eq!(h.log.event_count_for_player(new_player), 0);
    }

    #[test]
    fn fork_inherits_identity_and_logs_independently() {
        let h = harness();

        let forked = h.session.clone().fork().unwrap();
        forked.send_event(h.player, event("from fork")).unwrap();
        forked.commit().unwrap();

        assert_eq!(h.log.event_count_for_player(h.player), 1);
        // The parent's own buffer is untouched by the fork's commit.
        h.session.commit().unwrap();
        assert_eq!(h.log.event_count_for_player(h.player), 1);
    }
}
