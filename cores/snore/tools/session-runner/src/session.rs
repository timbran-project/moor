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

//! Test sessions with transaction-local output and one scenario-wide delivery/presence hub.
//! Presence is explicit; connection handles, attributes, and elapsed time are not simulated.

use moor_common::tasks::{ConnectionDetails, NarrativeEvent, Session, SessionError};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var};
use std::{
    collections::HashSet,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

pub type InputRequest = (Obj, Uuid, Option<Vec<(Symbol, Var)>>);

#[derive(Default)]
pub struct SessionHub {
    delivered: Mutex<Vec<(Obj, NarrativeEvent)>>,
    input: Mutex<Vec<InputRequest>>,
    connected: Mutex<HashSet<Obj>>,
    system: Mutex<Vec<String>>,
}

impl SessionHub {
    pub fn set_connected(&self, player: Obj, connected: bool) {
        let mut players = self.connected.lock().unwrap();
        if connected {
            players.insert(player);
        } else {
            players.remove(&player);
        }
    }
    pub fn take_input_requests(&self) -> Vec<InputRequest> {
        std::mem::take(&mut *self.input.lock().unwrap())
    }
    pub fn take_committed_events(&self) -> Vec<(Obj, NarrativeEvent)> {
        std::mem::take(&mut *self.delivered.lock().unwrap())
    }
}

pub struct TestSession {
    pending: Mutex<Vec<(Obj, NarrativeEvent)>>,
    hub: Arc<SessionHub>,
}

impl TestSession {
    pub fn new(hub: Arc<SessionHub>) -> Self {
        Self {
            pending: Mutex::default(),
            hub,
        }
    }
}

impl Session for TestSession {
    fn commit(&self) -> Result<(), SessionError> {
        let pending = std::mem::take(&mut *self.pending.lock().unwrap());
        self.hub.delivered.lock().unwrap().extend(pending);
        Ok(())
    }

    fn rollback(&self) -> Result<(), SessionError> {
        self.pending.lock().unwrap().clear();
        Ok(())
    }

    fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        Ok(Arc::new(TestSession::new(self.hub.clone())))
    }

    fn fork_retry(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        Ok(self)
    }

    fn request_input(
        &self,
        player: Obj,
        input_request_id: Uuid,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), SessionError> {
        self.hub
            .input
            .lock()
            .unwrap()
            .push((player, input_request_id, metadata));
        Ok(())
    }

    fn send_event(&self, player: Obj, msg: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.pending.lock().unwrap().push((player, *msg));
        Ok(())
    }

    fn log_event(&self, _player: Obj, _event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        // Mock session doesn't persist to event log, so this is a no-op
        Ok(())
    }

    fn send_system_msg(&self, player: Obj, msg: &str) -> Result<(), SessionError> {
        self.hub
            .system
            .lock()
            .unwrap()
            .push(format!("{player}: {msg}"));
        Ok(())
    }

    fn notify_shutdown(&self, msg: Option<String>) -> Result<(), SessionError> {
        let mut system = self.hub.system.lock().unwrap();
        if let Some(msg) = msg {
            system.push(format!("shutdown: {msg}"));
        } else {
            system.push(String::from("shutdown"));
        }
        Ok(())
    }

    fn connection_name(&self, player: Obj) -> Result<String, SessionError> {
        Ok(format!("player-{player}"))
    }

    fn disconnect(&self, player: Obj) -> Result<(), SessionError> {
        self.hub.set_connected(player, false);
        Ok(())
    }

    fn connected_players(&self, _include_all: bool) -> Result<Vec<Obj>, SessionError> {
        let mut players: Vec<_> = self.hub.connected.lock().unwrap().iter().copied().collect();
        players.sort();
        Ok(players)
    }

    fn connected_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        self.hub
            .connected
            .lock()
            .unwrap()
            .contains(&player)
            .then_some(0.0)
            .ok_or(SessionError::NoConnectionForPlayer(player))
    }

    fn idle_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        self.connected_seconds(player)
    }

    fn connections(&self, _player: Option<Obj>) -> Result<Vec<Obj>, SessionError> {
        Err(SessionError::NoConnectionForPlayer(SYSTEM_OBJECT))
    }

    fn connection_details(
        &self,
        _player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        Err(SessionError::NoConnectionForPlayer(SYSTEM_OBJECT))
    }

    fn connection_attributes(&self, _obj: Obj) -> Result<Var, SessionError> {
        use moor_var::v_list;
        Ok(v_list(&[]))
    }

    fn set_connection_attribute(
        &self,
        _connection_obj: Obj,
        _key: Symbol,
        _value: Var,
    ) -> Result<(), SessionError> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_common::tasks::Event;
    use moor_var::{v_obj, v_str};

    fn event(text: &str) -> Box<NarrativeEvent> {
        Box::new(NarrativeEvent::notify(
            v_obj(SYSTEM_OBJECT),
            v_str(text),
            None,
            false,
            false,
            None,
        ))
    }
    fn delivered(hub: &SessionHub) -> Vec<(Obj, String)> {
        hub.take_committed_events()
            .into_iter()
            .map(|(recipient, event)| {
                let Event::Notify { value, .. } = event.event else {
                    panic!("not a notification")
                };
                (recipient, value.as_string().unwrap().to_string())
            })
            .collect()
    }

    #[test]
    fn transaction_buffers_and_shared_delivery_preserve_payloads() {
        let hub = Arc::new(SessionHub::default());
        let parent = Arc::new(TestSession::new(hub.clone()));
        let child = parent.clone().fork().unwrap();
        let a = Obj::mk_id(1);
        let b = Obj::mk_id(2);
        parent.send_event(a, event("parent pending")).unwrap();
        child.send_event(b, event("discard child")).unwrap();
        child.rollback().unwrap();
        assert!(delivered(&hub).is_empty());
        parent.commit().unwrap();
        assert_eq!(delivered(&hub), vec![(a, "parent pending".into())]);
        parent.send_event(a, event("discard parent")).unwrap();
        child.send_event(b, event("child committed")).unwrap();
        child.commit().unwrap();
        parent.rollback().unwrap();
        assert_eq!(delivered(&hub), vec![(b, "child committed".into())]);
        assert!(delivered(&hub).is_empty());
        parent.send_event(a, event("first")).unwrap();
        parent.commit().unwrap();
        child.commit().unwrap();
        parent.send_event(b, event("second")).unwrap();
        parent.commit().unwrap();
        assert_eq!(
            delivered(&hub),
            vec![(a, "first".into()), (b, "second".into())]
        );
        parent.send_event(a, event("retry discarded")).unwrap();
        parent.rollback().unwrap();
        let retry = parent.fork_retry().unwrap();
        retry.send_event(b, event("retry committed")).unwrap();
        retry.commit().unwrap();
        assert_eq!(delivered(&hub), vec![(b, "retry committed".into())]);
    }

    #[test]
    fn presence_and_disconnect_are_shared_across_sessions_and_forks() {
        let hub = Arc::new(SessionHub::default());
        let parent = Arc::new(TestSession::new(hub.clone()));
        let sibling = TestSession::new(hub.clone());
        let child = parent.clone().fork().unwrap();
        let player = Obj::mk_id(12);
        assert!(parent.connected_players(false).unwrap().is_empty());
        assert!(
            matches!(parent.connected_seconds(player), Err(SessionError::NoConnectionForPlayer(p)) if p == player)
        );
        assert!(parent.idle_seconds(player).is_err());
        hub.set_connected(player, true);
        assert_eq!(child.connected_players(false).unwrap(), vec![player]);
        assert_eq!(sibling.connected_seconds(player).unwrap(), 0.0);
        child.disconnect(player).unwrap();
        assert!(parent.connected_players(false).unwrap().is_empty());
        assert!(sibling.idle_seconds(player).is_err());
        hub.set_connected(player, true);
        assert_eq!(parent.connected_players(false).unwrap(), vec![player]);
    }

    #[test]
    fn input_requests_keep_metadata_and_drain_once() {
        let hub = Arc::new(SessionHub::default());
        let parent = Arc::new(TestSession::new(hub.clone()));
        let child = parent.fork().unwrap();
        let player = Obj::mk_id(7);
        let id = Uuid::nil();
        let metadata = Some(vec![(Symbol::mk("prompt"), v_str("Subject:"))]);
        child.request_input(player, id, metadata.clone()).unwrap();
        assert_eq!(hub.take_input_requests(), vec![(player, id, metadata)]);
        assert!(hub.take_input_requests().is_empty());
    }
}
