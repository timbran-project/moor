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

//! Bounded retention for client events awaiting host acknowledgement.

use std::{
    collections::{HashMap, VecDeque},
    fmt,
    sync::Mutex,
};

use moor_runtime_api::{
    api::{ClientEvent, ClientEventMessage},
    api_codec::encode_client_event_bytes,
};
use uuid::Uuid;

const MAX_EVENTS_PER_CLIENT: usize = 8_192;
const MAX_BYTES_PER_CLIENT: usize = 16 * 1024 * 1024;
const MAX_TOTAL_BYTES: usize = 256 * 1024 * 1024;
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
                "client {client_id} event backlog exceeded its limit ({events} events, {bytes} bytes)"
            ),
            Self::InvalidAcknowledgement {
                client_id,
                acknowledged,
                latest,
            } => write!(
                f,
                "client {client_id} acknowledged sequence {acknowledged}, but latest is {latest}"
            ),
            Self::ReplayUnavailable {
                client_id,
                requested,
                available_from,
            } => write!(
                f,
                "client {client_id} requested sequence {requested}, but replay starts at {available_from}"
            ),
            Self::Encoding(error) => write!(f, "could not encode client event: {error}"),
        }
    }
}

impl std::error::Error for ClientEventBufferError {}

#[derive(Clone)]
struct BufferedEvent {
    message: ClientEventMessage,
    encoded_len: usize,
}

struct ClientBuffer {
    next_sequence: u64,
    bytes: usize,
    events: VecDeque<BufferedEvent>,
}

impl Default for ClientBuffer {
    fn default() -> Self {
        Self {
            next_sequence: 1,
            bytes: 0,
            events: VecDeque::new(),
        }
    }
}

struct BufferState {
    clients: HashMap<Uuid, ClientBuffer>,
    total_bytes: usize,
}

/// Retains each per-client event until the host confirms a sequence after it.
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
        let sequence = state
            .clients
            .get(&client_id)
            .map_or(1, |client| client.next_sequence);
        let message = ClientEventMessage { sequence, event };
        let encoded = encode_client_event_bytes(&message)
            .map_err(|error| ClientEventBufferError::Encoding(error.to_string()))?;
        let encoded_len = encoded.len();

        let next_total_bytes = state.total_bytes.saturating_add(encoded_len);
        let client = state.clients.entry(client_id).or_default();
        let next_events = client.events.len() + 1;
        let next_client_bytes = client.bytes.saturating_add(encoded_len);
        if next_events > self.max_events_per_client
            || next_client_bytes > self.max_bytes_per_client
            || next_total_bytes > self.max_total_bytes
        {
            return Err(ClientEventBufferError::BacklogExceeded {
                client_id,
                events: next_events,
                bytes: next_client_bytes,
            });
        }

        client.next_sequence = client.next_sequence.saturating_add(1);
        client.bytes = next_client_bytes;
        client.events.push_back(BufferedEvent {
            message: message.clone(),
            encoded_len,
        });
        state.total_bytes = next_total_bytes;
        Ok((message, encoded))
    }

    pub(crate) fn replay(
        &self,
        client_id: Uuid,
        after_sequence: u64,
        limit: usize,
    ) -> Result<(Vec<ClientEventMessage>, u64), ClientEventBufferError> {
        let mut state = self.state.lock().unwrap();
        let (events, latest_sequence, acknowledged_bytes) = {
            let Some(client) = state.clients.get_mut(&client_id) else {
                return Ok((Vec::new(), 0));
            };
            let latest_sequence = client.next_sequence.saturating_sub(1);
            if after_sequence > latest_sequence {
                return Err(ClientEventBufferError::InvalidAcknowledgement {
                    client_id,
                    acknowledged: after_sequence,
                    latest: latest_sequence,
                });
            }

            let mut acknowledged_bytes = 0;
            while client
                .events
                .front()
                .is_some_and(|event| event.message.sequence <= after_sequence)
            {
                let event = client.events.pop_front().unwrap();
                acknowledged_bytes += event.encoded_len;
            }
            client.bytes = client.bytes.saturating_sub(acknowledged_bytes);

            if after_sequence != 0
                && let Some(first) = client.events.front()
                && first.message.sequence > after_sequence.saturating_add(1)
            {
                return Err(ClientEventBufferError::ReplayUnavailable {
                    client_id,
                    requested: after_sequence.saturating_add(1),
                    available_from: first.message.sequence,
                });
            }

            let limit = limit.clamp(1, MAX_REPLAY_EVENTS);
            let events = client
                .events
                .iter()
                .take(limit)
                .map(|event| event.message.clone())
                .collect();
            (events, latest_sequence, acknowledged_bytes)
        };
        state.total_bytes = state.total_bytes.saturating_sub(acknowledged_bytes);
        Ok((events, latest_sequence))
    }

    pub(crate) fn remove_client(&self, client_id: Uuid) {
        let mut state = self.state.lock().unwrap();
        if let Some(client) = state.clients.remove(&client_id) {
            state.total_bytes = state.total_bytes.saturating_sub(client.bytes);
        }
    }
}

#[cfg(test)]
mod tests {
    use moor_runtime_api::api::ClientEvent;
    use uuid::Uuid;

    use super::{ClientEventBuffer, ClientEventBufferError};

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
