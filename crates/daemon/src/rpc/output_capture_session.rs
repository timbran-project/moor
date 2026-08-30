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

use std::sync::{Arc, Mutex};
use uuid::Uuid;

use moor_common::tasks::{ConnectionDetails, NarrativeEvent, Session, SessionError};
use moor_var::{List, Obj, Symbol, Var};

use crate::{event_log::EventLogOps, rpc::session_event_buffer::SessionEventBuffer};

/// A session that captures a task's committed narrative output in memory instead of delivering it
/// to a connected client.
///
/// Used for captured-output verb invocations, which have no client connection. Events are buffered
/// per transaction exactly as they are for `RpcSession`: on commit they are written to the event
/// log and moved into the capture buffer, and on rollback they are discarded.
///
/// Forked tasks get their own non-capturing session, so their output does not appear in the
/// parent's captured result, but their committed events still reach the event log.
pub struct OutputCaptureSession {
    client_id: Uuid,
    player: Obj,
    /// Buffered events and the shared event-log commit rules.
    events: SessionEventBuffer,
    /// Whether this session accumulates committed events for the caller. Forks do not.
    capturing: bool,
    /// Committed narrative events, in commit order.
    captured_events: Mutex<Vec<(Obj, Box<NarrativeEvent>)>>,
}

impl OutputCaptureSession {
    /// A capturing session for the root task of a captured invocation.
    pub fn new(client_id: Uuid, player: Obj, event_log: Arc<dyn EventLogOps>) -> Self {
        Self::with_capture(client_id, player, event_log, true)
    }

    fn with_capture(
        client_id: Uuid,
        player: Obj,
        event_log: Arc<dyn EventLogOps>,
        capturing: bool,
    ) -> Self {
        Self {
            client_id,
            player,
            events: SessionEventBuffer::new(event_log, player, player),
            capturing,
            captured_events: Mutex::new(Vec::new()),
        }
    }

    /// Take the events this session committed so far.
    pub fn take_captured_events(&self) -> Vec<(Obj, Box<NarrativeEvent>)> {
        let mut events = self.captured_events.lock().unwrap();
        events.drain(..).collect()
    }
}

impl Session for OutputCaptureSession {
    fn commit(&self) -> Result<(), SessionError> {
        // Writes both buffers to the event log and hands back the deliverable events. There is no
        // connected client, so "delivery" means moving them into the capture buffer.
        let events = self.events.commit();
        if self.capturing {
            self.captured_events.lock().unwrap().extend(events);
        }
        Ok(())
    }

    fn rollback(&self) -> Result<(), SessionError> {
        // Events buffered by the rolled-back transaction are dropped: they are neither logged nor
        // captured. Events from earlier committed transactions of the same task are kept.
        self.events.rollback();
        Ok(())
    }

    fn fork(self: Arc<Self>) -> Result<Arc<dyn Session>, SessionError> {
        // A fork is an independent task and may outlive the captured response, so it gets a
        // non-capturing session. Its committed events still reach the event log.
        Ok(Arc::new(Self::with_capture(
            self.client_id,
            self.player,
            self.events.event_log(),
            false,
        )))
    }

    fn request_input(
        &self,
        _player: Obj,
        _input_request_id: Uuid,
        _metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), SessionError> {
        // Captured mode has no input channel, so an input request fails the task.
        Err(SessionError::CommitError(
            "Input requests not supported for output capture sessions".to_string(),
        ))
    }

    fn send_event(&self, player: Obj, event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        self.events.push_event(player, event);
        Ok(())
    }

    fn log_event(&self, player: Obj, event: Box<NarrativeEvent>) -> Result<(), SessionError> {
        // Log-only events go to the event log on commit, but never into the captured response.
        self.events.push_log_only_event(player, event);
        Ok(())
    }

    fn send_system_msg(&self, _player: Obj, _msg: &str) -> Result<(), SessionError> {
        // No connected destination; discard.
        Ok(())
    }

    fn notify_shutdown(&self, _msg: Option<String>) -> Result<(), SessionError> {
        // No connected destination; discard.
        Ok(())
    }

    fn connection_name(&self, _player: Obj) -> Result<String, SessionError> {
        Ok("output-capture-session".to_string())
    }

    fn disconnect(&self, _player: Obj) -> Result<(), SessionError> {
        Ok(())
    }

    fn connected_players(&self, _include_all: bool) -> Result<Vec<Obj>, SessionError> {
        Ok(vec![])
    }

    fn connected_seconds(&self, _player: Obj) -> Result<f64, SessionError> {
        Ok(0.0)
    }

    fn idle_seconds(&self, _player: Obj) -> Result<f64, SessionError> {
        Ok(0.0)
    }

    fn connections(&self, _player: Option<Obj>) -> Result<Vec<Obj>, SessionError> {
        Ok(vec![])
    }

    fn connection_details(
        &self,
        _player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        Ok(vec![])
    }

    fn connection_attributes(&self, _obj: Obj) -> Result<Var, SessionError> {
        Ok(Var::from(List::mk_list(&[])))
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
    use crate::testing::MockEventLog;
    use moor_common::tasks::NarrativeEvent;
    use moor_var::{v_obj, v_str};

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

    fn session(log: Arc<MockEventLog>) -> Arc<OutputCaptureSession> {
        let player = Obj::mk_id(2);
        log.set_pubkey(player, test_pubkey());
        Arc::new(OutputCaptureSession::new(Uuid::new_v4(), player, log))
    }

    /// An age/X25519 recipient key; the event log encrypts every event it stores.
    fn test_pubkey() -> String {
        "age1zvkyg2lqzraa2lnjvqej32nkuu0ues2s82hzrye869xeexvn73equnujwj".to_string()
    }

    #[test]
    fn captures_only_committed_send_events() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log.clone());
        let player = Obj::mk_id(2);

        session.send_event(player, event("kept")).unwrap();
        session.log_event(player, event("log-only")).unwrap();
        session.commit().unwrap();

        let captured = session.take_captured_events();
        assert_eq!(captured.len(), 1);
        // Both events were written to the event log; only the send_event was captured.
        assert_eq!(log.narrative_event_count(), 2);
    }

    #[test]
    fn uncommitted_events_are_not_captured() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log.clone());

        session.send_event(Obj::mk_id(2), event("pending")).unwrap();

        assert!(session.take_captured_events().is_empty());
        assert_eq!(log.narrative_event_count(), 0);
    }

    #[test]
    fn rollback_drops_buffered_events() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log.clone());
        let player = Obj::mk_id(2);

        session.send_event(player, event("doomed")).unwrap();
        session.rollback().unwrap();
        session.commit().unwrap();

        assert!(session.take_captured_events().is_empty());
        assert_eq!(log.narrative_event_count(), 0);
    }

    #[test]
    fn fork_output_is_logged_but_not_captured() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log.clone());
        let player = Obj::mk_id(2);

        let forked = session.clone().fork().unwrap();
        forked.send_event(player, event("from fork")).unwrap();
        forked.commit().unwrap();

        assert!(session.take_captured_events().is_empty());
        assert_eq!(log.narrative_event_count(), 1);
    }

    #[test]
    fn input_requests_fail() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log);

        assert!(
            session
                .request_input(Obj::mk_id(2), Uuid::new_v4(), None)
                .is_err()
        );
    }

    #[test]
    fn system_messages_are_discarded() {
        let log = Arc::new(MockEventLog::new());
        let session = session(log.clone());

        session.send_system_msg(Obj::mk_id(2), "hello").unwrap();
        session.notify_shutdown(None).unwrap();
        session.commit().unwrap();

        assert!(session.take_captured_events().is_empty());
        assert_eq!(log.narrative_event_count(), 0);
    }
}
