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

//! Per-client session event loop and realtime transport coordination.

mod outbox;
mod websocket;

#[cfg(test)]
mod tests;

use axum::extract::ws::{Message, WebSocket};
use futures_util::{Sink, Stream, StreamExt};
use moor_runtime_api::{
    AuthToken, ClientToken,
    api::{
        ClientEvent, ClientEventSubscription, ClientReply, ClientRequest, InvocationMode,
        RuntimeClient,
    },
    api_codec::encode_client_event_bytes,
    session_pong::PongTask,
};
use moor_schema::{convert::var_from_flatbuffer_ref, rpc as moor_rpc, var as moor_var_schema};
use moor_var::{Obj, Var, v_str};
use planus::ReadAsRoot;
use std::{
    collections::VecDeque,
    net::SocketAddr,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::{select, sync::watch};
use tracing::{debug, error, info, trace, warn};
use uuid::Uuid;

use self::outbox::Outbox;
use self::websocket::{ReadEvent, read_websocket_event};
use crate::host::actions::{action_request, is_action_frame};
use crate::host::client_data::{self, WireFormat};
use crate::webrtc::{
    self, ChannelMessages, WebRtc, WebRtcPeer,
    signaling::{SignalingMessage, encode_signaling_message, parse_signaling_message},
};
use moor_common::util::TokenBucket;

const WEBSOCKET_PING_INTERVAL: Duration = Duration::from_secs(30);

// Application-level heartbeat to detect zombie WebSocket connections.
// Unlike WebSocket ping/pong (handled by browser at protocol level), this requires
// JavaScript to process and respond, proving the client is actually alive.
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(30);
const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(15);
const HEARTBEAT_REQUEST: u8 = 0x02;

/// How long a command waits for the previous task's completion before running anyway.
const TASK_TIMEOUT: Duration = Duration::from_secs(10);

/// Commands held while a task runs or a prompt is open. When either bound is reached,
/// the session stops reading the WebSocket until commands drain.
const MAX_DEFERRED_COMMANDS: usize = 64;
const MAX_DEFERRED_BYTES: usize = 1024 * 1024;

/// The payload size of a WebSocket message.
fn message_len(message: &Message) -> usize {
    match message {
        Message::Text(text) => text.len(),
        Message::Binary(data) => data.len(),
        _ => 0,
    }
}

pub struct ClientSession {
    pub(crate) player: Obj,
    pub(crate) peer_addr: SocketAddr,
    /// Answers the daemon's pings, and reports when the daemon has dropped this connection.
    pub(crate) pong_task: PongTask,
    pub(crate) narrative_sub: Box<dyn ClientEventSubscription>,
    pub(crate) client_id: Uuid,
    pub(crate) client_token: ClientToken,
    pub(crate) auth_token: AuthToken,
    pub(crate) daemon_client: Arc<dyn RuntimeClient>,
    pub(crate) handler_object: Obj,
    pub(crate) pending_task: Option<PendingTask>,
    pub(crate) close_code: Option<u16>,
    pub(crate) is_logout: bool,
    /// The host's WebRTC service, when enabled.
    pub(crate) webrtc: Option<Arc<WebRtc>>,
    /// This client's data channel connection, once it has made an offer.
    pub(crate) webrtc_peer: Option<WebRtcPeer>,
    /// Limits client data from the WebSocket and the data channel together.
    pub(crate) client_data_limiter: TokenBucket,
    /// Whether the core was last told this connection has an open data channel.
    pub(crate) realtime_reported: bool,
    /// Whether JSON booleans from the client become BOOL values, as the server's
    /// use_boolean_returns says, rather than 1 and 0.
    pub(crate) use_boolean_returns: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub struct PendingTask {
    pub(crate) task_id: usize,
    pub(crate) start_time: tokio::time::Instant,
}

impl ClientSession {
    /// Build a CredentialsUpdatedEvent as serialized FlatBuffer bytes.
    fn build_credentials_event(&self) -> Result<Vec<u8>, moor_runtime_api::RpcMessageError> {
        let event = moor_runtime_api::api::ClientEventMessage {
            sequence: 0,
            event: ClientEvent::CredentialsUpdated {
                client_id: self.client_id,
                client_token: self.client_token.clone(),
            },
        };
        encode_client_event_bytes(&event)
    }

    pub async fn handle(&mut self, connect_type: moor_rpc::ConnectType, stream: WebSocket) {
        info!("New connection from {}, {}", self.peer_addr, self.player);
        let (ws_sender, ws_receiver) = stream.split();
        self.run(connect_type, ws_sender, ws_receiver).await;
    }

    /// Serve the client over a WebSocket's two halves until it closes, then detach.
    async fn run<W, R>(
        &mut self,
        connect_type: moor_rpc::ConnectType,
        ws_sender: W,
        mut ws_receiver: R,
    ) where
        W: Sink<Message, Error = axum::Error> + Unpin + Send + 'static,
        R: Stream<Item = Result<Message, axum::Error>> + Unpin,
    {
        // Send credentials at the start of every connection.
        // This ensures the client always has the correct credentials, even after
        // reattach fails and a new connection is created.
        let credentials_bytes = match self.build_credentials_event() {
            Ok(bytes) => bytes,
            Err(e) => {
                error!("Failed to encode credentials update: {}", e);
                return;
            }
        };
        let outbox = Outbox::start(ws_sender);
        if !outbox.send(Message::Binary(credentials_bytes.into())).await {
            error!("Failed to send credentials update");
            return;
        }
        debug!(client_id = ?self.client_id, "Sent credentials update to client");

        // Connection message is now sent via SystemMessageEvent from the daemon
        match connect_type {
            moor_rpc::ConnectType::Connected => {
                debug!("Player {} connected", self.player);
            }
            moor_rpc::ConnectType::Reconnected => {
                debug!("Player {} reconnected", self.player);
            }
            moor_rpc::ConnectType::Created => {
                debug!("Player {} created", self.player);
            }
            moor_rpc::ConnectType::NoConnect => {
                error!("NoConnect reached WebSocket handler unexpectedly");
                return;
            }
        };

        debug!(client_id = ?self.client_id, "Entering command dispatch loop");

        let mut expecting_input = VecDeque::new();
        // Commands wait here while a task runs or a prompt is open; the socket is still
        // read, so client data, signaling, heartbeats and close frames are not held up.
        let mut deferred_actions: VecDeque<Message> = VecDeque::new();
        let mut deferred_bytes = 0;
        let mut ping_interval = tokio::time::interval(WEBSOCKET_PING_INTERVAL);
        let mut heartbeat_interval = tokio::time::interval(HEARTBEAT_INTERVAL);
        let mut pending_heartbeat: Option<Instant> = None;
        // Held outside `self` so the select below can wait on them beside the other branches.
        let mut channel_messages: Option<ChannelMessages> = None;
        let mut channel_open: Option<watch::Receiver<bool>> = None;
        loop {
            if expecting_input.is_empty()
                && self.pending_task.is_none()
                && let Some(action) = deferred_actions.pop_front()
            {
                deferred_bytes -= message_len(&action);
                self.process_command_line(action).await;
            }
            // Check for heartbeat timeout - if we sent a heartbeat and haven't received
            // a response within HEARTBEAT_TIMEOUT, the websocket connection is likely zombie.
            if let Some(sent_time) = pending_heartbeat
                && sent_time.elapsed() > HEARTBEAT_TIMEOUT
            {
                warn!(
                    "Heartbeat timeout after {:?} - websocket not responding, closing connection",
                    sent_time.elapsed()
                );
                break;
            }

            let task_deadline = self
                .pending_task
                .as_ref()
                .filter(|_| expecting_input.is_empty())
                .map(|task| task.start_time + TASK_TIMEOUT);
            let can_defer = deferred_actions.len() < MAX_DEFERRED_COMMANDS
                && deferred_bytes < MAX_DEFERRED_BYTES;

            select! {
                line = read_websocket_event(
                    &mut ws_receiver,
                    !expecting_input.is_empty(),
                ), if can_defer => {
                    match line {
                        ReadEvent::Command(line) => {
                            // Keep commands behind the running task, and separate from read()
                            // replies, including prompt races.
                            if expecting_input.is_empty() && self.pending_task.is_none() {
                                self.process_command_line(line).await;
                            } else {
                                deferred_bytes += message_len(&line);
                                deferred_actions.push_back(line);
                            }
                        }
                        ReadEvent::InputReply(line) =>{
                            self.process_requested_input_line(line, &mut expecting_input).await;
                        }
                        ReadEvent::ConnectionClose { close_code, is_logout } => {
                            self.close_code = close_code;
                            self.is_logout = is_logout;
                            info!("Connection closed with code: {:?}, is_logout: {}", close_code, is_logout);
                            break;
                        }
                        ReadEvent::Ping(payload) => {
                            trace!("Responding to client ping with pong");
                            if !outbox.send(Message::Pong(payload.into())).await {
                                break;
                            }
                        }
                        ReadEvent::HeartbeatResponse => {
                            trace!("Heartbeat response received, client JS is alive");
                            pending_heartbeat = None;
                        }
                        ReadEvent::WebRtcSignaling(data) => {
                            if !self.handle_webrtc_signaling(&data, &outbox, &mut channel_messages, &mut channel_open).await {
                                break;
                            }
                        }
                        ReadEvent::ClientData(body) => {
                            self.submit_client_data(WireFormat::of_frame_body(&body), &body).await;
                        }
                    }
                }
                _ = async {
                    match task_deadline {
                        Some(deadline) => tokio::time::sleep_until(deadline).await,
                        None => std::future::pending().await,
                    }
                } => {
                    if let Some(task) = self.pending_task.take() {
                        error!(
                            "Task {} stuck without response for more than {TASK_TIMEOUT:?}",
                            task.task_id
                        );
                    }
                }
                _ = heartbeat_interval.tick() => {
                    // Send application-level heartbeat request
                    // Client must respond with HEARTBEAT_RESPONSE to prove JS is processing
                    trace!("Sending heartbeat request");
                    if !outbox.send(Message::Binary(vec![HEARTBEAT_REQUEST].into())).await {
                        break;
                    }
                    pending_heartbeat = Some(Instant::now());
                }
                _ = ping_interval.tick() => {
                    trace!("Sending WebSocket ping");
                    if !outbox.send(Message::Ping(vec![].into())).await {
                        break;
                    }
                }
                Some(message) = async {
                    match channel_messages.as_mut() {
                        Some(messages) => messages.recv().await,
                        None => std::future::pending().await,
                    }
                } => {
                    let format = self.webrtc_peer.as_ref().map(WebRtcPeer::format).unwrap_or_default();
                    self.submit_client_data(format, &message).await;
                }
                changed = async {
                    match channel_open.as_mut() {
                        Some(open) => open.changed().await,
                        None => std::future::pending().await,
                    }
                } => {
                    match changed {
                        Ok(()) => {
                            let open = channel_open.as_ref().is_some_and(|open| *open.borrow());
                            self.report_realtime(open).await;
                        }
                        // The peer has gone; a new offer will bring a new watcher.
                        Err(_) => channel_open = None,
                    }
                }
                _ = self.pong_task.connection_gone() => {
                    info!(client_id = %self.client_id, "Daemon no longer has this connection");
                    break;
                }
                Ok(event_msg) = self.narrative_sub.recv_client_event() => {
                    match &event_msg.event {
                        ClientEvent::RequestInput { request_id, .. } => {
                            expecting_input.push_back(*request_id);
                        }
                        ClientEvent::TaskSuccess { .. } |
                        ClientEvent::TaskError { .. } |
                        ClientEvent::TaskSuspended { .. } => {
                            // Clear the pending task so we can process the next command
                            self.pending_task = None;
                        }
                        ClientEvent::PlayerSwitched {
                            new_player,
                            new_auth_token,
                            ..
                        } => {
                            info!(
                                old_player = ?self.player,
                                ?new_player,
                                client_id = ?self.client_id,
                                "Updating web session player"
                            );
                            self.player = *new_player;
                            self.auth_token.clone_from(new_auth_token);
                        }
                        _ => {}
                    }

                    let event_bytes = match encode_client_event_bytes(&event_msg) {
                        Ok(bytes) => bytes,
                        Err(e) => {
                            error!("Failed to encode client event for websocket: {}", e);
                            break;
                        }
                    };
                    if !self.forward_event(&event_msg.event, event_bytes, &outbox).await {
                        break;
                    }
                }
            }
        }

        // Leave the WebRTC endpoint if this client joined it.
        self.webrtc_peer = None;

        // Detach transport
        // Use the is_logout flag from the close reason to determine if session should be destroyed
        // If close reason was "LOGOUT", destroy session. Otherwise, keep alive for reconnection.
        debug!(
            "Detaching connection: close_code={:?}, is_logout={}, disconnected={}",
            self.close_code, self.is_logout, self.is_logout
        );
        self.daemon_client
            .client_call(
                self.client_id,
                ClientRequest::Detach {
                    client_token: self.client_token.clone(),
                    disconnected: self.is_logout,
                },
            )
            .await
            .map_err(|e| warn!("Unable to send detach event to RPC server: {}", e))
            .ok();
    }

    async fn process_command_line(&mut self, line: Message) {
        let request = if let Message::Binary(ref bytes) = line
            && is_action_frame(bytes)
        {
            match action_request(
                &bytes[1..],
                self.handler_object,
                self.auth_token.clone(),
                self.client_token.clone(),
                self.use_boolean_returns,
            ) {
                Ok(request) => request,
                Err(error) => {
                    warn!(%error, "Invalid structured action");
                    return;
                }
            }
        } else {
            let line = match line.into_text() {
                Ok(line) => line,
                Err(e) => {
                    warn!("Received non-text command message: {}", e);
                    return;
                }
            };
            ClientRequest::Command {
                auth_token: self.auth_token.clone(),
                handler_object: self.handler_object,
                command: line.trim().to_string(),
                mode: InvocationMode::Connected {
                    client_token: self.client_token.clone(),
                },
            }
        };

        let reply = self
            .daemon_client
            .client_call(self.client_id, request)
            .await;
        let reply = match reply {
            Ok(reply) => reply,
            Err(e) => {
                warn!("Unable to send command to RPC server: {}", e);
                return;
            }
        };

        match reply {
            ClientReply::TaskSubmitted { task_id } => {
                self.set_pending_task(task_id as usize);
            }
            ClientReply::InputThanks => {
                warn!("Received input thanks unprovoked, out of order")
            }
            _ => {
                error!("Unexpected daemon to client reply");
            }
        }
    }

    async fn process_requested_input_line(
        &mut self,
        message: Message,
        expecting_input: &mut VecDeque<Uuid>,
    ) {
        let Some(cmd) = var_from_input_message(message) else {
            return;
        };

        let Some(input_request_id) = expecting_input.front() else {
            warn!("Attempt to send reply to input request without an input request");
            return;
        };

        let reply = self
            .daemon_client
            .client_call(
                self.client_id,
                ClientRequest::RequestedInput {
                    client_token: self.client_token.clone(),
                    auth_token: self.auth_token.clone(),
                    request_id: *input_request_id,
                    input: cmd,
                },
            )
            .await;
        let reply = match reply {
            Ok(reply) => reply,
            Err(e) => {
                warn!("Unable to send input to RPC server: {}", e);
                return;
            }
        };

        match reply {
            ClientReply::TaskSubmitted { task_id } => {
                self.set_pending_task(task_id as usize);
                warn!("Got TaskSubmitted when expecting input-thanks")
            }
            ClientReply::InputThanks => {
                expecting_input.pop_front();
            }
            _ => {
                error!("Unexpected daemon to client reply");
            }
        }
    }

    /// Handle a WebRTC signaling frame. Returns false if the WebSocket has failed.
    async fn handle_webrtc_signaling(
        &mut self,
        data: &[u8],
        outbox: &Outbox,
        channel_messages: &mut Option<ChannelMessages>,
        channel_open: &mut Option<watch::Receiver<bool>>,
    ) -> bool {
        let Some(webrtc) = self.webrtc.clone() else {
            debug!("WebRTC signaling received but WebRTC is disabled");
            return true;
        };
        let Some(msg) = parse_signaling_message(data) else {
            warn!("Failed to parse WebRTC signaling message");
            return true;
        };
        match msg {
            SignalingMessage::Offer { sdp } => {
                // A new offer replaces any earlier connection.
                self.webrtc_peer = None;
                *channel_messages = None;
                *channel_open = None;
                self.report_realtime(false).await;
                let (peer, answer_sdp, messages) = match webrtc.answer(&sdp).await {
                    Ok(answered) => answered,
                    Err(e) => {
                        warn!("Failed to answer WebRTC offer: {e}");
                        return true;
                    }
                };
                *channel_open = Some(peer.watch_open());
                self.webrtc_peer = Some(peer);
                *channel_messages = Some(messages);
                let answer =
                    encode_signaling_message(&SignalingMessage::Answer { sdp: answer_sdp });
                outbox.send(Message::Binary(answer.into())).await
            }
            SignalingMessage::IceCandidate { candidate } => {
                if let Some(peer) = &self.webrtc_peer
                    && let Err(e) = peer.add_ice_candidate(&candidate).await
                {
                    warn!("Failed to add ICE candidate: {e}");
                }
                true
            }
            SignalingMessage::Answer { .. } => {
                warn!("Received unexpected SDP answer from client");
                true
            }
        }
    }

    /// Tell the core whether this connection has an open data channel.
    async fn report_realtime(&mut self, open: bool) {
        if open == self.realtime_reported {
            return;
        }
        self.realtime_reported = open;
        let requests = client_data::realtime_report(
            open,
            self.handler_object,
            &self.auth_token,
            &self.client_token,
        );
        for request in requests {
            if let Err(e) = self
                .daemon_client
                .client_call(self.client_id, request)
                .await
            {
                warn!("Unable to report the data channel to the RPC server: {e}");
            }
        }
    }

    /// Deliver a client data message to `do_client_data`, if the rate allows.
    async fn submit_client_data(&mut self, format: WireFormat, body: &[u8]) {
        if !self.client_data_limiter.allow(Instant::now()) {
            trace!("Client data over the rate limit; dropped");
            return;
        }
        let (kind, payload) = match client_data::decode(format, body, self.use_boolean_returns) {
            Ok(message) => message,
            Err(error) => {
                warn!(%error, "Invalid client data");
                return;
            }
        };
        let request = client_data::request(
            kind,
            payload,
            self.handler_object,
            self.auth_token.clone(),
            self.client_token.clone(),
        );
        if let Err(e) = self
            .daemon_client
            .client_call(self.client_id, request)
            .await
        {
            warn!("Unable to send client data to RPC server: {e}");
        }
    }

    /// The data channel message for an ephemeral event, when the channel is open, encoded
    /// in the channel's format. FlatBuffers channels carry the WebSocket bytes.
    fn channel_message(&self, event: &ClientEvent, websocket_bytes: &[u8]) -> Option<Vec<u8>> {
        let peer = self.webrtc_peer.as_ref().filter(|peer| peer.is_open())?;
        match (peer.format(), event) {
            (WireFormat::FlatBuffers, _) => Some(websocket_bytes.to_vec()),
            (WireFormat::Json, ClientEvent::Narrative { event, .. }) => {
                client_data::event_json(event)
            }
            (WireFormat::Json, _) => None,
        }
    }

    /// Send an event to the client. Ephemeral events take the data channel when it is open
    /// and accepts them, and otherwise the WebSocket's latest-wins queue; everything else is
    /// queued on the WebSocket in order. Returns false once the WebSocket has failed.
    async fn forward_event(
        &mut self,
        event: &ClientEvent,
        bytes: Vec<u8>,
        outbox: &Outbox,
    ) -> bool {
        let Some(key) = webrtc::channel_key(event) else {
            return outbox.send(Message::Binary(bytes.into())).await;
        };
        if let Some(message) = self.channel_message(event, &bytes)
            && let Some(peer) = &self.webrtc_peer
        {
            match peer.send(key, &message) {
                Ok(()) => return true,
                Err(e) => debug!("Data channel send failed, falling back to WS: {e}"),
            }
        }
        outbox.send_latest(key, bytes)
    }

    fn set_pending_task(&mut self, task_id: usize) -> bool {
        self.pending_task = Some(PendingTask {
            task_id,
            start_time: tokio::time::Instant::now(),
        });
        true
    }
}

fn var_from_input_message(message: Message) -> Option<Var> {
    match message {
        Message::Text(text) => Some(v_str(&text)),
        Message::Binary(bytes) => var_from_binary_input(&bytes),
        _ => {
            warn!("Received unsupported message type for input");
            None
        }
    }
}

fn var_from_binary_input(bytes: &[u8]) -> Option<Var> {
    let var_ref = match moor_var_schema::VarRef::read_as_root(bytes) {
        Ok(var_ref) => var_ref,
        Err(e) => {
            warn!("Invalid FlatBuffer in binary input: {}", e);
            return None;
        }
    };

    match var_from_flatbuffer_ref(var_ref) {
        Ok(var) => Some(var),
        Err(e) => {
            warn!("Failed to decode Var from FlatBuffer: {}", e);
            None
        }
    }
}
