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

//! Recovery for per-client event streams delivered over lossy transports.

use std::{collections::VecDeque, sync::Arc, time::Duration};

use async_trait::async_trait;
use tracing::warn;
use uuid::Uuid;

use crate::{
    ClientToken, RpcError,
    api::{ClientEventMessage, ClientEventSubscription, ClientReply, ClientRequest, RuntimeClient},
};

const EVENT_REPLAY_LIMIT: usize = 512;
const EVENT_ACK_BATCH: usize = 64;
const EVENT_REPLAY_INTERVAL: Duration = Duration::from_secs(5);

/// Adds ordered replay and acknowledgement to a live client-event subscription.
pub struct RecoveringClientEventSubscription {
    client_id: Uuid,
    live: Box<dyn ClientEventSubscription>,
    rpc: Arc<dyn RuntimeClient>,
    client_token: ClientToken,
    pending: VecDeque<ClientEventMessage>,
    last_delivered: u64,
    delivered_since_ack: usize,
    initialized: bool,
}

impl RecoveringClientEventSubscription {
    pub fn new(
        client_id: Uuid,
        live: Box<dyn ClientEventSubscription>,
        rpc: Arc<dyn RuntimeClient>,
        client_token: ClientToken,
    ) -> Self {
        Self {
            client_id,
            live,
            rpc,
            client_token,
            pending: VecDeque::new(),
            last_delivered: 0,
            delivered_since_ack: 0,
            initialized: false,
        }
    }

    async fn synchronize(&mut self) -> Result<(), RpcError> {
        let reply = self
            .rpc
            .client_call(
                self.client_id,
                ClientRequest::ReplayClientEvents {
                    client_token: self.client_token.clone(),
                    after_sequence: self.last_delivered,
                    limit: EVENT_REPLAY_LIMIT,
                },
            )
            .await?;
        let ClientReply::ClientEvents {
            events,
            latest_sequence,
        } = reply
        else {
            return Err(RpcError::UnexpectedReply(
                "Expected client event replay".to_string(),
            ));
        };

        if !self.initialized {
            self.last_delivered = events
                .first()
                .map_or(latest_sequence, |event| event.sequence.saturating_sub(1));
        }

        let mut expected = self.last_delivered.saturating_add(1);
        for event in events {
            if event.sequence != expected {
                return Err(RpcError::CouldNotReceive(format!(
                    "Client event replay is not contiguous: expected {expected}, received {}",
                    event.sequence
                )));
            }
            expected = expected.saturating_add(1);
            self.pending.push_back(event);
        }
        if self.pending.is_empty() && latest_sequence > self.last_delivered {
            return Err(RpcError::CouldNotReceive(format!(
                "Client event replay ended at {}, but daemon latest is {latest_sequence}",
                self.last_delivered
            )));
        }

        self.delivered_since_ack = 0;
        self.initialized = true;
        Ok(())
    }

    fn deliver(&mut self, message: ClientEventMessage) -> Result<ClientEventMessage, RpcError> {
        let expected = self.last_delivered.saturating_add(1);
        if message.sequence != expected {
            return Err(RpcError::CouldNotReceive(format!(
                "Client event sequence gap: expected {expected}, received {}",
                message.sequence
            )));
        }
        self.last_delivered = message.sequence;
        self.delivered_since_ack += 1;
        Ok(message)
    }
}

#[async_trait]
impl ClientEventSubscription for RecoveringClientEventSubscription {
    async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError> {
        loop {
            if let Some(message) = self.pending.pop_front() {
                return self.deliver(message);
            }

            if !self.initialized || self.delivered_since_ack >= EVENT_ACK_BATCH {
                self.synchronize().await?;
                if !self.pending.is_empty() {
                    continue;
                }
            }

            let live =
                match tokio::time::timeout(EVENT_REPLAY_INTERVAL, self.live.recv_client_event())
                    .await
                {
                    Ok(Ok(message)) => message,
                    Ok(Err(RpcError::Recoverable(_))) | Err(_) => {
                        self.synchronize().await?;
                        continue;
                    }
                    Ok(Err(error)) => return Err(error),
                };

            if live.sequence <= self.last_delivered {
                continue;
            }
            if live.sequence == self.last_delivered.saturating_add(1) {
                return self.deliver(live);
            }

            warn!(
                client_id = ?self.client_id,
                expected_sequence = self.last_delivered.saturating_add(1),
                received_sequence = live.sequence,
                "Recovering dropped client events"
            );
            self.synchronize().await?;
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        collections::VecDeque,
        sync::{Arc, Mutex},
    };

    use async_trait::async_trait;
    use tokio::sync::mpsc;
    use uuid::Uuid;

    use crate::{
        ClientToken, RpcError,
        api::{
            ClientEvent, ClientEventMessage, ClientEventSubscription, ClientReply, ClientRequest,
            HostReply, HostRequest, RuntimeClient,
        },
    };

    use super::RecoveringClientEventSubscription;

    struct TestRuntime {
        replies: Mutex<VecDeque<ClientReply>>,
        acknowledged: Mutex<Vec<u64>>,
    }

    #[async_trait]
    impl RuntimeClient for TestRuntime {
        async fn client_call(
            &self,
            _client_id: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, RpcError> {
            let ClientRequest::ReplayClientEvents { after_sequence, .. } = request else {
                panic!("unexpected client request")
            };
            self.acknowledged.lock().unwrap().push(after_sequence);
            self.replies
                .lock()
                .unwrap()
                .pop_front()
                .ok_or_else(|| RpcError::UnexpectedReply("missing test reply".to_string()))
        }

        async fn host_call(
            &self,
            _host_id: Uuid,
            _request: HostRequest,
        ) -> Result<HostReply, RpcError> {
            Err(RpcError::UnexpectedReply(
                "unexpected host request".to_string(),
            ))
        }
    }

    struct TestLiveSubscription {
        receiver: mpsc::UnboundedReceiver<Result<ClientEventMessage, RpcError>>,
    }

    #[async_trait]
    impl ClientEventSubscription for TestLiveSubscription {
        async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError> {
            self.receiver.recv().await.unwrap_or_else(|| {
                Err(RpcError::CouldNotReceive(
                    "test subscription closed".to_string(),
                ))
            })
        }
    }

    fn message(sequence: u64) -> ClientEventMessage {
        ClientEventMessage {
            sequence,
            event: ClientEvent::Disconnect,
        }
    }

    fn subscription(
        runtime: Arc<TestRuntime>,
        live_events: Vec<Result<ClientEventMessage, RpcError>>,
    ) -> RecoveringClientEventSubscription {
        let (sender, receiver) = mpsc::unbounded_channel();
        for event in live_events {
            sender.send(event).unwrap();
        }
        RecoveringClientEventSubscription::new(
            Uuid::new_v4(),
            Box::new(TestLiveSubscription { receiver }),
            runtime,
            ClientToken("test".to_string()),
        )
    }

    #[tokio::test]
    async fn initial_replay_resumes_at_retained_sequence() {
        let runtime = Arc::new(TestRuntime {
            replies: Mutex::new(VecDeque::from([ClientReply::ClientEvents {
                events: vec![message(3)],
                latest_sequence: 3,
            }])),
            acknowledged: Mutex::new(Vec::new()),
        });
        let mut subscription = subscription(runtime.clone(), vec![]);

        let event = subscription.recv_client_event().await.unwrap();
        assert_eq!(event.sequence, 3);
        assert_eq!(*runtime.acknowledged.lock().unwrap(), vec![0]);
    }

    #[tokio::test]
    async fn live_gap_is_replayed_in_order() {
        let runtime = Arc::new(TestRuntime {
            replies: Mutex::new(VecDeque::from([
                ClientReply::ClientEvents {
                    events: vec![],
                    latest_sequence: 0,
                },
                ClientReply::ClientEvents {
                    events: vec![message(1), message(2)],
                    latest_sequence: 2,
                },
            ])),
            acknowledged: Mutex::new(Vec::new()),
        });
        let mut subscription = subscription(runtime.clone(), vec![Ok(message(2))]);

        assert_eq!(subscription.recv_client_event().await.unwrap().sequence, 1);
        assert_eq!(subscription.recv_client_event().await.unwrap().sequence, 2);
        assert_eq!(*runtime.acknowledged.lock().unwrap(), vec![0, 0]);
    }
}
