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

//! In-process event bus for single-process deployments.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use async_trait::async_trait;
use moor_common::tasks::{Event, NarrativeEvent};
use moor_kernel::SchedulerClient;
use moor_runtime_api::{
    RpcError,
    api::{
        BroadcastEvent, BroadcastEventMessage, ClientBroadcastSubscription, ClientEvent,
        ClientEventMessage, ClientEventSubscription, HostBroadcastEvent, HostEventSubscription,
    },
};
use moor_var::Obj;
use tokio::sync::broadcast;
use uuid::Uuid;

use moor_daemon::{MessageHandler, Transport};

const EVENT_CHANNEL_CAPACITY: usize = 1024;

/// Shared in-process event bus used by the daemon and local hosts.
pub struct LocalEventBus {
    client_events: Mutex<HashMap<Uuid, broadcast::Sender<ClientEventMessage>>>,
    client_broadcasts: broadcast::Sender<BroadcastEventMessage>,
    host_events: broadcast::Sender<HostBroadcastEvent>,
}

impl LocalEventBus {
    pub fn new() -> Self {
        let (client_broadcasts, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        let (host_events, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
        Self {
            client_events: Mutex::new(HashMap::new()),
            client_broadcasts,
            host_events,
        }
    }

    pub fn subscribe_client_events(&self, client_id: Uuid) -> LocalClientEventSubscription {
        let mut client_events = self.client_events.lock().unwrap();
        let sender = client_events
            .entry(client_id)
            .or_insert_with(|| {
                let (sender, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
                sender
            })
            .clone();
        LocalClientEventSubscription {
            receiver: sender.subscribe(),
        }
    }

    pub fn subscribe_client_broadcasts(&self) -> LocalClientBroadcastSubscription {
        LocalClientBroadcastSubscription {
            receiver: self.client_broadcasts.subscribe(),
        }
    }

    pub fn subscribe_host_events(&self) -> LocalHostEventSubscription {
        LocalHostEventSubscription {
            receiver: self.host_events.subscribe(),
        }
    }

    fn client_sender(&self, client_id: Uuid) -> broadcast::Sender<ClientEventMessage> {
        let mut client_events = self.client_events.lock().unwrap();
        client_events
            .entry(client_id)
            .or_insert_with(|| {
                let (sender, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
                sender
            })
            .clone()
    }
}

impl Default for LocalEventBus {
    fn default() -> Self {
        Self::new()
    }
}

impl Transport for LocalEventBus {
    fn start_request_loop(
        &self,
        _rpc_endpoint: String,
        _scheduler_client: SchedulerClient,
        _message_handler: Arc<dyn MessageHandler>,
    ) -> eyre::Result<()> {
        Ok(())
    }

    fn publish_narrative_events(
        &self,
        events: &[(Obj, Box<NarrativeEvent>)],
        connections: &dyn moor_daemon::connections::ConnectionRegistry,
    ) -> Result<(), eyre::Error> {
        for (player, event) in events {
            let client_ids = connections.client_ids_for(*player)?;

            let client_event = match &event.event {
                Event::SetConnectionOption {
                    connection,
                    option,
                    value,
                } => {
                    if let Some(&client_id) = client_ids.first() {
                        connections.set_client_attribute(
                            client_id,
                            *option,
                            Some(value.clone()),
                        )?;
                    }
                    ClientEvent::SetConnectionOption {
                        connection_obj: *connection,
                        option_name: *option,
                        value: value.clone(),
                    }
                }
                _ => ClientEvent::Narrative {
                    player: *player,
                    event: event.as_ref().clone(),
                },
            };

            let message = ClientEventMessage {
                event: client_event,
            };
            for client_id in client_ids {
                let sender = self.client_sender(client_id);
                let _ = sender.send(message.clone());
            }
        }
        Ok(())
    }

    fn broadcast_host_event(&self, event: HostBroadcastEvent) -> Result<(), eyre::Error> {
        let _ = self.host_events.send(event);
        Ok(())
    }

    fn publish_client_event(&self, client_id: Uuid, event: ClientEvent) -> Result<(), eyre::Error> {
        let message = ClientEventMessage { event };
        let sender = self.client_sender(client_id);
        let _ = sender.send(message);
        Ok(())
    }

    fn broadcast_client_event(&self, event: BroadcastEvent) -> Result<(), eyre::Error> {
        let event = BroadcastEventMessage { event };
        let _ = self.client_broadcasts.send(event);
        Ok(())
    }
}

pub struct LocalClientEventSubscription {
    receiver: broadcast::Receiver<ClientEventMessage>,
}

#[async_trait]
impl ClientEventSubscription for LocalClientEventSubscription {
    async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError> {
        recv_broadcast(&mut self.receiver).await
    }
}

pub struct LocalClientBroadcastSubscription {
    receiver: broadcast::Receiver<BroadcastEventMessage>,
}

#[async_trait]
impl ClientBroadcastSubscription for LocalClientBroadcastSubscription {
    async fn recv_client_broadcast(&mut self) -> Result<BroadcastEventMessage, RpcError> {
        recv_broadcast(&mut self.receiver).await
    }
}

pub struct LocalHostEventSubscription {
    receiver: broadcast::Receiver<HostBroadcastEvent>,
}

#[async_trait]
impl HostEventSubscription for LocalHostEventSubscription {
    async fn recv_host_event(&mut self) -> Result<HostBroadcastEvent, RpcError> {
        recv_broadcast(&mut self.receiver).await
    }
}

async fn recv_broadcast<T: Clone>(receiver: &mut broadcast::Receiver<T>) -> Result<T, RpcError> {
    receiver.recv().await.map_err(|e| match e {
        broadcast::error::RecvError::Closed => {
            RpcError::CouldNotReceive("local event bus closed".to_string())
        }
        broadcast::error::RecvError::Lagged(count) => RpcError::Recoverable(format!(
            "local event subscription lagged by {count} messages"
        )),
    })
}

#[cfg(test)]
mod tests {
    use moor_runtime_api::api::{
        BroadcastEvent, ClientBroadcastSubscription, ClientEvent, ClientEventSubscription,
        HostBroadcastEvent, HostEventSubscription,
    };
    use uuid::Uuid;

    use super::LocalEventBus;
    use moor_daemon::Transport;

    #[tokio::test]
    async fn delivers_client_event_to_client_subscription() {
        let bus = LocalEventBus::new();
        let client_id = Uuid::new_v4();
        let mut sub = bus.subscribe_client_events(client_id);

        bus.publish_client_event(client_id, ClientEvent::Disconnect)
            .unwrap();

        let event = sub.recv_client_event().await.unwrap();
        assert!(matches!(event.event, ClientEvent::Disconnect));
    }

    #[tokio::test]
    async fn delivers_broadcast_and_host_events() {
        let bus = LocalEventBus::new();
        let mut client_sub = bus.subscribe_client_broadcasts();
        let mut host_sub = bus.subscribe_host_events();

        bus.broadcast_client_event(BroadcastEvent::PingPong)
            .unwrap();
        bus.broadcast_host_event(HostBroadcastEvent::PingPong)
            .unwrap();

        let client_event = client_sub.recv_client_broadcast().await.unwrap();
        assert!(matches!(client_event.event, BroadcastEvent::PingPong));

        let host_event = host_sub.recv_host_event().await.unwrap();
        assert!(matches!(host_event, HostBroadcastEvent::PingPong));
    }
}
