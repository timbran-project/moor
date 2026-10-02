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

//! Bounded daemon-owned retention for host or browser acknowledged delivery.

use moor_runtime_api::{
    RpcMessageError,
    api::{
        ClientEvent, ClientEventMessage, EventStreamOperation, EventStreamRequest, EventStreamState,
    },
    api_codec::{decode_client_event_message_ref, encode_client_event_bytes},
};
use moor_schema::rpc::ClientEventRef;
use planus::ReadAsRoot;
use std::{
    collections::{HashMap, VecDeque},
    fmt,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use uuid::Uuid;

const MAX_EVENTS_PER_CLIENT: usize = 8_192;
const MAX_BYTES_PER_CLIENT: usize = 16 * 1024 * 1024;
const MAX_TOTAL_BYTES: usize = 256 * 1024 * 1024;
const STREAM_RETENTION: Duration = Duration::from_secs(300);
const MAX_BATCH_BYTES: usize = 1024 * 1024;
pub(crate) const MAX_REPLAY_EVENTS: usize = 512;

#[derive(Debug)]
pub(crate) enum ClientEventBufferError {
    BacklogExceeded {
        client_id: Uuid,
        events: usize,
        bytes: usize,
    },
    InvalidAcknowledgement {
        client_id: Uuid,
        acknowledged: u64,
        latest: u64,
    },
    ReplayUnavailable {
        client_id: Uuid,
        requested: u64,
        available_from: u64,
    },
    BrowserOwned,
    Encoding(String),
}
impl fmt::Display for ClientEventBufferError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::BacklogExceeded {
                client_id,
                events,
                bytes,
            } => write!(
                f,
                "client {client_id} backlog exceeded its limit ({events} events, {bytes} bytes)"
            ),
            Self::InvalidAcknowledgement {
                client_id,
                acknowledged,
                latest,
            } => write!(
                f,
                "client {client_id} acknowledged {acknowledged}, latest is {latest}"
            ),
            Self::ReplayUnavailable {
                client_id,
                requested,
                available_from,
            } => write!(
                f,
                "client {client_id} requested {requested}, replay starts at {available_from}"
            ),
            Self::BrowserOwned => f.write_str("delivery is acknowledged by the browser"),
            Self::Encoding(error) => f.write_str(error),
        }
    }
}
impl std::error::Error for ClientEventBufferError {}

struct BufferedEvent {
    sequence: u64,
    bytes: Arc<[u8]>,
    created: Instant,
}

struct ClientBuffer {
    stream_id: Uuid,
    browser_owned: bool,
    next_sequence: u64,
    acknowledged: u64,
    available_after: u64,
    bytes: usize,
    events: VecDeque<BufferedEvent>,
}
impl Default for ClientBuffer {
    fn default() -> Self {
        Self {
            stream_id: Uuid::new_v4(),
            browser_owned: false,
            next_sequence: 1,
            acknowledged: 0,
            available_after: 0,
            bytes: 0,
            events: VecDeque::new(),
        }
    }
}
impl ClientBuffer {
    fn remove_front(&mut self) -> usize {
        let event = self.events.pop_front().unwrap();
        self.available_after = event.sequence;
        self.bytes -= event.bytes.len();
        event.bytes.len()
    }
    fn expire(&mut self, now: Instant) -> usize {
        let mut removed = 0;
        while self.browser_owned
            && self
                .events
                .front()
                .is_some_and(|e| now.duration_since(e.created) >= STREAM_RETENTION)
        {
            removed += self.remove_front();
        }
        removed
    }
    fn acknowledge(&mut self, sequence: u64) -> usize {
        self.acknowledged = self.acknowledged.max(sequence);
        let mut removed = 0;
        while self
            .events
            .front()
            .is_some_and(|e| e.sequence <= self.acknowledged)
        {
            removed += self.remove_front();
        }
        removed
    }
    fn metadata(&self, payloads: Vec<Arc<[u8]>>) -> EventStreamState {
        EventStreamState {
            stream_id: self.stream_id,
            acknowledged_sequence: self.acknowledged,
            available_after: self.available_after,
            latest_sequence: self.next_sequence - 1,
            payloads,
        }
    }
}
struct BufferState {
    clients: HashMap<Uuid, ClientBuffer>,
    total_bytes: usize,
}

/// Stores one encoded payload per delivery. Browser-owned streams publish watermarks only.
pub(crate) struct ClientEventBuffer {
    state: Mutex<BufferState>,
    max_events_per_client: usize,
    max_bytes_per_client: usize,
    max_total_bytes: usize,
}
impl ClientEventBuffer {
    pub(crate) fn new() -> Self {
        Self::with_limits(MAX_EVENTS_PER_CLIENT, MAX_BYTES_PER_CLIENT, MAX_TOTAL_BYTES)
    }
    fn with_limits(
        max_events_per_client: usize,
        max_bytes_per_client: usize,
        max_total_bytes: usize,
    ) -> Self {
        Self {
            state: Mutex::new(BufferState {
                clients: HashMap::new(),
                total_bytes: 0,
            }),
            max_events_per_client,
            max_bytes_per_client,
            max_total_bytes,
        }
    }

    pub(crate) fn push(
        &self,
        client_id: Uuid,
        event: ClientEvent,
    ) -> Result<(ClientEventMessage, Vec<u8>), ClientEventBufferError> {
        let mut state = self.state.lock().unwrap();
        let expired = state
            .clients
            .get_mut(&client_id)
            .map_or(0, |c| c.expire(Instant::now()));
        state.total_bytes -= expired;
        let client = state.clients.entry(client_id).or_default();
        let sequence = client.next_sequence;
        let browser_owned = client.browser_owned;
        let message = ClientEventMessage { sequence, event };
        let encoded = encode_client_event_bytes(&message)
            .map_err(|e| ClientEventBufferError::Encoding(e.to_string()))?;
        let bytes = encoded.len();
        let next_events = client.events.len() + 1;
        let next_client_bytes = client.bytes + bytes;
        if next_events > self.max_events_per_client
            || next_client_bytes > self.max_bytes_per_client
            || state.total_bytes + bytes > self.max_total_bytes
        {
            return Err(ClientEventBufferError::BacklogExceeded {
                client_id,
                events: next_events,
                bytes: next_client_bytes,
            });
        }
        let client = state.clients.get_mut(&client_id).unwrap();
        client.next_sequence = sequence
            .checked_add(1)
            .ok_or_else(|| ClientEventBufferError::Encoding("event sequence exhausted".into()))?;
        client.bytes = next_client_bytes;
        client.events.push_back(BufferedEvent {
            sequence,
            bytes: Arc::from(encoded.as_slice()),
            created: Instant::now(),
        });
        state.total_bytes += bytes;
        if browser_owned {
            let notification = ClientEventMessage {
                sequence,
                event: ClientEvent::EventsAvailable,
            };
            let encoded = encode_client_event_bytes(&notification)
                .map_err(|e| ClientEventBufferError::Encoding(e.to_string()))?;
            return Ok((notification, encoded));
        }
        Ok((message, encoded))
    }

    /// Host delivery and browser delivery have separate acknowledgement authorities.
    pub(crate) fn replay(
        &self,
        client_id: Uuid,
        after_sequence: u64,
        limit: usize,
    ) -> Result<(Vec<ClientEventMessage>, u64), ClientEventBufferError> {
        let mut state = self.state.lock().unwrap();
        let Some(client) = state.clients.get_mut(&client_id) else {
            return Ok((Vec::new(), 0));
        };
        if client.browser_owned {
            return Err(ClientEventBufferError::BrowserOwned);
        }
        let latest = client.next_sequence - 1;
        if after_sequence > latest {
            return Err(ClientEventBufferError::InvalidAcknowledgement {
                client_id,
                acknowledged: after_sequence,
                latest,
            });
        }
        if after_sequence != 0 && after_sequence < client.available_after {
            return Err(ClientEventBufferError::ReplayUnavailable {
                client_id,
                requested: after_sequence + 1,
                available_from: client.available_after + 1,
            });
        }
        let removed = client.acknowledge(after_sequence);
        let events = client
            .events
            .iter()
            .take(limit.clamp(1, MAX_REPLAY_EVENTS))
            .map(|e| {
                let event = ClientEventRef::read_as_root(&e.bytes)
                    .map_err(|e| ClientEventBufferError::Encoding(e.to_string()))?;
                decode_client_event_message_ref(event)
                    .map_err(|e| ClientEventBufferError::Encoding(e.to_string()))
            })
            .collect::<Result<Vec<_>, _>>();
        state.total_bytes -= removed;
        Ok((events?, latest))
    }

    pub(crate) fn stream(
        &self,
        client_id: Uuid,
        request: EventStreamRequest,
    ) -> Result<EventStreamState, RpcMessageError> {
        let mut state = self.state.lock().unwrap();
        if request.operation == EventStreamOperation::Open {
            let client = state.clients.entry(client_id).or_default();
            client.browser_owned = true;
        }
        let Some(client) = state.clients.get_mut(&client_id) else {
            return Err(RpcMessageError::EventStreamExpired);
        };
        if !client.browser_owned
            || (request.operation != EventStreamOperation::Open
                && request.stream_id != Some(client.stream_id))
        {
            return Err(RpcMessageError::EventStreamExpired);
        }
        let removed = client.expire(Instant::now());
        state.total_bytes -= removed;
        let client = state.clients.get_mut(&client_id).unwrap();
        if matches!(
            request.operation,
            EventStreamOperation::Read | EventStreamOperation::Acknowledge
        ) && request.sequence >= client.next_sequence
        {
            return Err(RpcMessageError::InvalidRequest(
                "sequence exceeds the stream watermark".into(),
            ));
        }
        match request.operation {
            EventStreamOperation::Read => {
                if request.sequence < client.available_after {
                    return Err(RpcMessageError::EventStreamExpired);
                }
                let mut bytes = 0;
                let payloads = client
                    .events
                    .iter()
                    .filter(|e| e.sequence > request.sequence)
                    .take(request.limit.clamp(1, MAX_REPLAY_EVENTS))
                    .take_while(|e| {
                        let include = bytes == 0 || bytes + e.bytes.len() <= MAX_BATCH_BYTES;
                        if include {
                            bytes += e.bytes.len();
                        }
                        include
                    })
                    .map(|e| e.bytes.clone())
                    .collect();
                Ok(client.metadata(payloads))
            }
            EventStreamOperation::Acknowledge => {
                // Once unacknowledged data expires, an ACK cannot erase that gap.
                if client.available_after > client.acknowledged {
                    return Err(RpcMessageError::EventStreamExpired);
                }
                let removed = client.acknowledge(request.sequence);
                let result = client.metadata(Vec::new());
                state.total_bytes -= removed;
                Ok(result)
            }
            _ => Ok(client.metadata(Vec::new())),
        }
    }

    /// Expire idle payloads too, without requiring a subsequent read or publish.
    pub(crate) fn expire(&self) {
        let mut state = self.state.lock().unwrap();
        let now = Instant::now();
        let removed: usize = state.clients.values_mut().map(|c| c.expire(now)).sum();
        state.total_bytes -= removed;
    }
    pub(crate) fn remove_client(&self, client_id: Uuid) {
        let mut state = self.state.lock().unwrap();
        if let Some(client) = state.clients.remove(&client_id) {
            state.total_bytes -= client.bytes;
        }
    }
}

#[cfg(test)]
mod tests {
    use moor_runtime_api::api::ClientEvent;
    use uuid::Uuid;

    use super::{ClientEventBuffer, ClientEventBufferError};

    use super::*;

    fn request(
        operation: EventStreamOperation,
        stream_id: Option<Uuid>,
        sequence: u64,
    ) -> EventStreamRequest {
        EventStreamRequest {
            operation,
            stream_id,
            sequence,
            limit: 128,
        }
    }

    #[test]
    fn browser_reads_are_retryable_and_only_cumulative_ack_reclaims_payloads() {
        let buffer = ClientEventBuffer::new();
        let client = Uuid::new_v4();
        let stream = buffer
            .stream(client, request(EventStreamOperation::Open, None, 0))
            .unwrap()
            .stream_id;
        for _ in 0..3 {
            let (published, _) = buffer.push(client, ClientEvent::Disconnect).unwrap();
            assert!(matches!(published.event, ClientEvent::EventsAvailable));
        }
        let first = buffer
            .stream(client, request(EventStreamOperation::Read, Some(stream), 0))
            .unwrap();
        let retry = buffer
            .stream(client, request(EventStreamOperation::Read, Some(stream), 0))
            .unwrap();
        assert_eq!(first.payloads, retry.payloads);
        assert_eq!(first.payloads.len(), 3);
        assert_eq!(first.acknowledged_sequence, 0);
        assert!(matches!(
            buffer.replay(client, 3, 128),
            Err(ClientEventBufferError::BrowserOwned)
        ));
        buffer
            .stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(stream), 2),
            )
            .unwrap();
        // Requests through separate hosts can arrive out of order; ACKs must never move backwards.
        let duplicate = buffer
            .stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(stream), 1),
            )
            .unwrap();
        assert_eq!(duplicate.acknowledged_sequence, 2);
        let remaining = buffer
            .stream(client, request(EventStreamOperation::Read, Some(stream), 2))
            .unwrap();
        assert_eq!(remaining.payloads.len(), 1);
        assert_eq!(remaining.payloads[0], first.payloads[2]);
        assert_eq!(
            buffer.state.lock().unwrap().total_bytes,
            remaining.payloads[0].len()
        );
        assert!(matches!(
            buffer.stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(stream), 4)
            ),
            Err(RpcMessageError::InvalidRequest(_))
        ));
        buffer
            .stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(stream), 3),
            )
            .unwrap();
        assert_eq!(buffer.state.lock().unwrap().total_bytes, 0);
    }

    #[test]
    fn stream_generations_fence_late_acknowledgements() {
        let buffer = ClientEventBuffer::new();
        let client = Uuid::new_v4();
        let old = buffer
            .stream(client, request(EventStreamOperation::Open, None, 0))
            .unwrap()
            .stream_id;
        buffer.remove_client(client);
        let new = buffer
            .stream(client, request(EventStreamOperation::Open, None, 0))
            .unwrap()
            .stream_id;
        assert_ne!(old, new);
        buffer.push(client, ClientEvent::Disconnect).unwrap();
        assert!(matches!(
            buffer.stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(old), 1)
            ),
            Err(RpcMessageError::EventStreamExpired)
        ));
        assert_eq!(
            buffer
                .stream(client, request(EventStreamOperation::Read, Some(new), 0))
                .unwrap()
                .payloads
                .len(),
            1
        );
    }

    #[test]
    fn expiry_reclaims_idle_bytes_and_reports_gap_even_when_the_queue_is_empty() {
        let buffer = ClientEventBuffer::new();
        let client = Uuid::new_v4();
        let stream = buffer
            .stream(client, request(EventStreamOperation::Open, None, 0))
            .unwrap()
            .stream_id;
        buffer.push(client, ClientEvent::Disconnect).unwrap();
        buffer
            .state
            .lock()
            .unwrap()
            .clients
            .get_mut(&client)
            .unwrap()
            .events
            .front_mut()
            .unwrap()
            .created -= STREAM_RETENTION;
        buffer.expire();
        assert_eq!(buffer.state.lock().unwrap().total_bytes, 0);
        let status = buffer
            .stream(
                client,
                request(EventStreamOperation::Status, Some(stream), 0),
            )
            .unwrap();
        assert_eq!(status.available_after, 1);
        assert_eq!(status.acknowledged_sequence, 0);
        for operation in [
            EventStreamOperation::Read,
            EventStreamOperation::Acknowledge,
        ] {
            assert!(matches!(
                buffer.stream(client, request(operation, Some(stream), 0)),
                Err(RpcMessageError::EventStreamExpired)
            ));
        }
        assert!(matches!(
            buffer.stream(
                client,
                request(EventStreamOperation::Acknowledge, Some(stream), 1)
            ),
            Err(RpcMessageError::EventStreamExpired)
        ));
    }

    #[test]
    fn payload_bytes_have_per_client_and_global_bounds() {
        let buffer = ClientEventBuffer::with_limits(100, 256, 300);
        let first = Uuid::new_v4();
        let second = Uuid::new_v4();
        let event = || ClientEvent::SystemMessage {
            player: moor_var::Obj::mk_id(1),
            message: "x".repeat(100),
        };
        buffer.push(first, event()).unwrap();
        assert!(matches!(
            buffer.push(first, event()),
            Err(ClientEventBufferError::BacklogExceeded { .. })
        ));
        assert!(matches!(
            buffer.push(second, event()),
            Err(ClientEventBufferError::BacklogExceeded { .. })
        ));
        buffer.remove_client(first);
        buffer.push(second, event()).unwrap();
    }

    #[test]
    fn replay_acknowledges_and_returns_following_events() {
        let buffer = ClientEventBuffer::with_limits(8, 1_000_000, 1_000_000);
        let client_id = Uuid::new_v4();
        let (first, _) = buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        let (second, _) = buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        assert_eq!(first.sequence, 1);
        assert_eq!(second.sequence, 2);

        let (events, latest) = buffer.replay(client_id, 1, 8).unwrap();
        assert_eq!(latest, 2);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].sequence, 2);

        let (events, latest) = buffer.replay(client_id, 2, 8).unwrap();
        assert_eq!(latest, 2);
        assert!(events.is_empty());
    }

    #[test]
    fn rejects_an_unacknowledged_backlog_over_the_event_limit() {
        let buffer = ClientEventBuffer::with_limits(2, 1_000_000, 1_000_000);
        let client_id = Uuid::new_v4();
        buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        let error = buffer.push(client_id, ClientEvent::Disconnect).unwrap_err();
        assert!(matches!(
            error,
            ClientEventBufferError::BacklogExceeded { events: 3, .. }
        ));
    }

    #[test]
    fn initial_replay_starts_at_the_retained_boundary() {
        let buffer = ClientEventBuffer::with_limits(8, 1_000_000, 1_000_000);
        let client_id = Uuid::new_v4();
        buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        buffer.push(client_id, ClientEvent::Disconnect).unwrap();
        buffer.replay(client_id, 2, 8).unwrap();
        let (third, _) = buffer.push(client_id, ClientEvent::Disconnect).unwrap();

        let (events, latest) = buffer.replay(client_id, 0, 8).unwrap();
        assert_eq!(latest, 3);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].sequence, third.sequence);
    }
}
