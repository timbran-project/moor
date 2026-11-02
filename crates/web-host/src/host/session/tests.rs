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

//! Session loop tests over an in-memory socket and runtime.

use std::{
    net::SocketAddr,
    pin::Pin,
    sync::{Arc, Mutex},
    time::Duration,
};

use async_trait::async_trait;
use axum::extract::ws::Message;
use futures_util::{Sink, Stream};
use moor_common::util::TokenBucket;
use moor_runtime_api::session_pong::{PongIdentity, PongTask};
use moor_runtime_api::{
    AuthToken, ClientToken, RpcError,
    api::{
        BroadcastEventMessage, ClientBroadcastSubscription, ClientEvent, ClientEventMessage,
        ClientEventSubscription, ClientReply, ClientRequest, HostReply, HostRequest, RuntimeClient,
    },
};
use moor_schema::rpc as moor_rpc;
use moor_var::{Obj, v_int};
use tokio::sync::mpsc;
use uuid::Uuid;

use super::websocket::HEARTBEAT_RESPONSE;
use super::{ClientSession, HEARTBEAT_TIMEOUT, MAX_DEFERRED_COMMANDS, TASK_TIMEOUT};

/// Records requests in order, and submits a new task for each command.
struct Runtime {
    requests: mpsc::UnboundedSender<ClientRequest>,
    next_task: Mutex<u64>,
    /// How long the daemon takes to answer the first command, as when it is lagging.
    first_command_delay: Duration,
}

#[async_trait]
impl RuntimeClient for Runtime {
    async fn client_call(&self, _: Uuid, request: ClientRequest) -> Result<ClientReply, RpcError> {
        if matches!(request, ClientRequest::Command { .. }) && *self.next_task.lock().unwrap() == 0
        {
            tokio::time::sleep(self.first_command_delay).await;
        }
        let reply = match &request {
            ClientRequest::Command { .. } => {
                let mut next = self.next_task.lock().unwrap();
                *next += 1;
                ClientReply::TaskSubmitted { task_id: *next }
            }
            _ => ClientReply::ClientAttributeSet,
        };
        let _ = self.requests.send(request);
        Ok(reply)
    }

    async fn host_call(&self, _: Uuid, _: HostRequest) -> Result<HostReply, RpcError> {
        panic!("unexpected host request")
    }
}

struct Events(mpsc::UnboundedReceiver<ClientEventMessage>);

#[async_trait]
impl ClientEventSubscription for Events {
    async fn recv_client_event(&mut self) -> Result<ClientEventMessage, RpcError> {
        match self.0.recv().await {
            Some(event) => Ok(event),
            None => std::future::pending().await,
        }
    }
}

struct NoBroadcasts;

#[async_trait]
impl ClientBroadcastSubscription for NoBroadcasts {
    async fn recv_client_broadcast(&mut self) -> Result<BroadcastEventMessage, RpcError> {
        std::future::pending().await
    }
}

/// A running session and the test's ends of its socket and runtime.
struct Harness {
    client: mpsc::UnboundedSender<Message>,
    requests: mpsc::UnboundedReceiver<ClientRequest>,
    events: mpsc::UnboundedSender<ClientEventMessage>,
    sequence: u64,
    session: tokio::task::JoinHandle<()>,
    /// What the session sent to the client.
    sent: mpsc::UnboundedReceiver<Message>,
}

impl Harness {
    fn start() -> Self {
        Self::start_with_command_delay(Duration::ZERO)
    }

    fn start_with_command_delay(first_command_delay: Duration) -> Self {
        let (requests_tx, requests) = mpsc::unbounded_channel();
        let (events, events_rx) = mpsc::unbounded_channel();
        let (client, client_rx) = mpsc::unbounded_channel();
        let (sent_tx, sent) = mpsc::unbounded_channel();
        let client_id = Uuid::new_v4();
        let daemon_client: Arc<dyn RuntimeClient> = Arc::new(Runtime {
            requests: requests_tx,
            next_task: Mutex::new(0),
            first_command_delay,
        });
        let mut session = ClientSession {
            player: Obj::mk_id(1),
            peer_addr: SocketAddr::from(([127, 0, 0, 1], 1)),
            pong_task: PongTask::spawn(
                Box::new(NoBroadcasts),
                daemon_client.clone(),
                PongIdentity {
                    client_id,
                    client_token: ClientToken("client".into()),
                    player: Obj::mk_id(1),
                    socket_addr: "127.0.0.1:1".into(),
                },
            ),
            narrative_sub: Box::new(Events(events_rx)),
            client_id,
            client_token: ClientToken("client".into()),
            auth_token: AuthToken("auth".into()),
            daemon_client,
            handler_object: Obj::mk_id(0),
            pending_task: None,
            close_code: None,
            is_logout: false,
            webrtc: None,
            webrtc_peer: None,
            client_data_limiter: TokenBucket::new(0, std::time::Instant::now()),
            realtime_reported: false,
            use_boolean_returns: true,
        };
        let session = tokio::spawn(async move {
            session
                .run(
                    moor_rpc::ConnectType::Connected,
                    sink(sent_tx),
                    stream(client_rx),
                )
                .await;
        });
        Self {
            client,
            requests,
            events,
            sequence: 0,
            session,
            sent,
        }
    }

    fn send(&self, message: Message) {
        self.client.send(message).unwrap();
    }

    async fn next_request(&mut self) -> ClientRequest {
        tokio::time::timeout(Duration::from_secs(60), self.requests.recv())
            .await
            .expect("no request reached the runtime")
            .unwrap()
    }

    fn no_request(&mut self) {
        assert!(
            self.requests.try_recv().is_err(),
            "an unexpected request reached the runtime"
        );
    }

    fn complete(&mut self, task_id: u64) {
        self.sequence += 1;
        self.events
            .send(ClientEventMessage {
                sequence: self.sequence,
                event: ClientEvent::TaskSuccess {
                    task_id,
                    result: v_int(0),
                },
            })
            .unwrap();
    }

    /// The next binary message sent to the client, skipping control messages.
    async fn next_sent(&mut self) -> Vec<u8> {
        loop {
            let message = tokio::time::timeout(Duration::from_secs(60), self.sent.recv())
                .await
                .expect("nothing was sent to the client")
                .unwrap();
            if let Message::Binary(data) = message
                && data.len() > 1
            {
                return data.to_vec();
            }
        }
    }

    async fn close(mut self) {
        self.send(Message::Close(None));
        assert!(matches!(
            self.next_request().await,
            ClientRequest::Detach { .. }
        ));
        self.session.await.unwrap();
    }
}

fn sink(
    sent: mpsc::UnboundedSender<Message>,
) -> Pin<Box<dyn Sink<Message, Error = axum::Error> + Send>> {
    Box::pin(futures_util::sink::unfold(
        sent,
        |sent, message| async move {
            sent.send(message).map_err(axum::Error::new)?;
            Ok(sent)
        },
    ))
}

fn stream(
    client: mpsc::UnboundedReceiver<Message>,
) -> Pin<Box<dyn Stream<Item = Result<Message, axum::Error>> + Send>> {
    Box::pin(futures_util::stream::unfold(
        client,
        |mut client| async move { client.recv().await.map(|message| (Ok(message), client)) },
    ))
}

fn command(request: &ClientRequest) -> Option<&str> {
    match request {
        ClientRequest::Command { command, .. } => Some(command),
        _ => None,
    }
}

fn client_data_frame() -> Message {
    Message::Binary(b"\x05{\"kind\":\"move\",\"payload\":1}".to_vec().into())
}

/// Let the session handle everything it has been sent.
async fn settle() {
    for _ in 0..100 {
        tokio::task::yield_now().await;
    }
}

#[tokio::test]
async fn client_data_is_not_held_behind_a_running_task() {
    let mut harness = Harness::start();
    harness.send(Message::Text("look".into()));
    assert_eq!(command(&harness.next_request().await), Some("look"));

    harness.send(Message::Text("east".into()));
    harness.send(client_data_frame());
    let request = harness.next_request().await;
    assert!(
        matches!(&request, ClientRequest::ClientData { kind, .. } if kind == "move"),
        "the next command ran before the task finished, or client data waited: {request:?}"
    );

    harness.complete(1);
    assert_eq!(command(&harness.next_request().await), Some("east"));
    harness.close().await;
}

#[tokio::test(start_paused = true)]
async fn a_slow_command_does_not_stop_heartbeats() {
    let delay = HEARTBEAT_TIMEOUT + Duration::from_secs(1);
    let mut harness = Harness::start_with_command_delay(delay);
    // The heartbeat request goes out as soon as the session starts.
    settle().await;
    harness.send(Message::Text("look".into()));
    settle().await;
    harness.send(Message::Binary(vec![HEARTBEAT_RESPONSE].into()));

    assert_eq!(command(&harness.next_request().await), Some("look"));

    // The session is still up, and still taking commands in order.
    harness.complete(1);
    harness.send(Message::Text("east".into()));
    assert_eq!(command(&harness.next_request().await), Some("east"));
    harness.close().await;
}

#[tokio::test(start_paused = true)]
async fn client_data_does_not_overtake_a_slow_command() {
    let mut harness = Harness::start_with_command_delay(Duration::from_secs(3));
    harness.send(Message::Text("look".into()));
    harness.send(client_data_frame());

    assert_eq!(command(&harness.next_request().await), Some("look"));
    assert!(matches!(
        harness.next_request().await,
        ClientRequest::ClientData { .. }
    ));
    harness.close().await;
}

#[tokio::test(start_paused = true)]
async fn a_second_command_waits_for_a_slow_first_one() {
    let mut harness = Harness::start_with_command_delay(Duration::from_secs(3));
    harness.send(Message::Text("look".into()));
    harness.send(Message::Text("east".into()));

    assert_eq!(command(&harness.next_request().await), Some("look"));
    settle().await;
    harness.no_request();

    harness.complete(1);
    assert_eq!(command(&harness.next_request().await), Some("east"));
    harness.close().await;
}

#[tokio::test(start_paused = true)]
async fn a_stuck_task_releases_waiting_commands() {
    let mut harness = Harness::start();
    harness.send(Message::Text("look".into()));
    assert_eq!(command(&harness.next_request().await), Some("look"));
    harness.send(Message::Text("east".into()));
    settle().await;
    harness.no_request();

    // The paused clock advances to the deadline once the session is idle.
    let started = tokio::time::Instant::now();
    assert_eq!(command(&harness.next_request().await), Some("east"));
    assert!(started.elapsed() >= TASK_TIMEOUT - Duration::from_millis(100));
    harness.close().await;
}

#[tokio::test]
async fn a_full_command_queue_stops_reading_the_socket() {
    let mut harness = Harness::start();
    harness.send(Message::Text("look".into()));
    assert_eq!(command(&harness.next_request().await), Some("look"));
    for n in 0..MAX_DEFERRED_COMMANDS {
        harness.send(Message::Text(format!("wait {n}").into()));
    }
    harness.send(client_data_frame());
    settle().await;
    harness.no_request();

    // The finished task lets one command run, which makes room to read the frame.
    harness.complete(1);
    assert_eq!(command(&harness.next_request().await), Some("wait 0"));
    assert!(matches!(
        harness.next_request().await,
        ClientRequest::ClientData { .. }
    ));
    harness.close().await;
}

#[tokio::test]
async fn ephemeral_events_reach_the_websocket() {
    use moor_common::tasks::NarrativeEvent;
    use moor_runtime_api::api_codec::encode_client_event_bytes;
    use moor_var::Symbol;
    let mut harness = Harness::start();
    // The credentials update comes first.
    harness.next_sent().await;
    let message = ClientEventMessage::unsequenced(ClientEvent::Narrative {
        player: Obj::mk_id(1),
        event: NarrativeEvent::data(
            v_int(0),
            Symbol::mk("game"),
            Symbol::mk("position"),
            v_int(3),
            true,
        ),
    });
    let expected = encode_client_event_bytes(&message).unwrap();
    harness.events.send(message).unwrap();
    assert_eq!(harness.next_sent().await, expected);
    harness.close().await;
}
