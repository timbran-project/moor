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

//! ZMQ transport layer for RPC, separated from business logic

use eyre::Context;
use planus::ReadAsRoot;
use r0z::Socket;
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};
use tracing::{error, info, warn};
use uuid::Uuid;

use super::message_handler::{DaemonReplySink, MessageHandler};
use crate::runtime::{RunOnWorker, WorkerJob};
use crate::{ReadySignal, signal_ready};
use moor_common::threading::spawn_efficient;
use moor_kernel::SchedulerClient;
use moor_rpc::{HostToDaemonMessageRef, MessageTypeRef};
use moor_runtime_api::{
    CLIENT_BROADCAST_TOPIC, HOST_BROADCAST_TOPIC, RpcMessageError,
    api::{BroadcastEvent, ClientEventMessage, HostBroadcastEvent},
    api_codec::{encode_broadcast_event_bytes, encode_host_broadcast_event_bytes},
    scheduler_error_to_flatbuffer_struct,
};
use moor_schema::rpc as moor_rpc;
/// Where workers send replies for the router to deliver.
const RPC_REPLIES_ENDPOINT: &str = "inproc://rpc-replies";
/// Requests that can wait for a free worker. Past this, a request is dropped and its host times out.
const MAX_QUEUED_REQUESTS: usize = 8192;
/// Pongs that can wait for the control thread. A round from every session can arrive at once.
const MAX_QUEUED_CONTROL_REQUESTS: usize = 16384;

/// The frames of a ZeroMQ message.
type Frames = Vec<Vec<u8>>;

/// Where a request's reply goes. It can be used from any thread.
#[derive(Clone)]
struct ReplyRoute {
    transport: u8,
    envelope: Frames,
    replies: Arc<Mutex<Socket>>,
    run_on_worker: RunOnWorker,
}

impl ReplyRoute {
    fn send(self, reply: Vec<u8>) {
        let mut frames = Vec::with_capacity(self.envelope.len() + 2);
        frames.push(vec![self.transport]);
        frames.extend(self.envelope);
        frames.push(reply);
        if let Err(e) = self.replies.lock().unwrap().send_multipart(frames, 0) {
            warn!(error = ?e, "Unable to queue RPC reply");
        }
    }
}

/// One request waiting for a thread, with what the router needs to deliver its reply.
struct RpcRequest {
    /// Index of the client socket the request arrived on.
    transport: u8,
    /// The routing frames, through the empty delimiter, returned unchanged with the reply.
    envelope: Vec<Vec<u8>>,
    /// The frames after the envelope.
    request: Vec<Vec<u8>>,
}

/// Work for an RPC worker.
enum RpcJob {
    Request(RpcRequest),
    /// The later part of a request that replies later, which can block on the scheduler.
    Run(WorkerJob),
}

/// Split a `ROUTER` message into its routing envelope, through the empty delimiter, and its body.
fn split_envelope(mut frames: Frames) -> Option<(Frames, Frames)> {
    let delimiter = frames.iter().position(Vec::is_empty)?;
    let request = frames.split_off(delimiter + 1);
    Some((frames, request))
}

/// Whether a request is a pong. Anything malformed is not, and gets its error from a worker.
fn request_is_pong(request: &[Vec<u8>]) -> bool {
    let [discriminator, body] = request else {
        return false;
    };
    let Ok(Ok(message_type)) =
        MessageTypeRef::read_as_root(discriminator).map(|message| message.message())
    else {
        return false;
    };
    match message_type {
        moor_rpc::MessageTypeUnionRef::HostToDaemonMsg(_) => matches!(
            HostToDaemonMessageRef::read_as_root(body).and_then(|message| message.message()),
            Ok(moor_rpc::HostToDaemonMessageUnionRef::HostPong(_))
        ),
        moor_rpc::MessageTypeUnionRef::HostClientToDaemonMsg(_) => matches!(
            moor_rpc::HostClientToDaemonMessageRef::read_as_root(body)
                .and_then(|message| message.message()),
            Ok(moor_rpc::HostClientToDaemonMessageUnionRef::ClientPong(_))
        ),
    }
}

/// Trait for the transport layer that handles communication between hosts and the daemon
pub trait Transport: Send + Sync {
    /// Start the request processing loop
    fn start_request_loop(
        &self,
        rpc_endpoint: String,
        scheduler_client: SchedulerClient,
        message_handler: Arc<dyn MessageHandler>,
    ) -> eyre::Result<()>;
    /// Broadcast events to hosts
    fn broadcast_host_event(&self, event: HostBroadcastEvent) -> Result<(), eyre::Error>;
    /// Publish event to specific client
    fn publish_client_event(
        &self,
        client_id: Uuid,
        event: ClientEventMessage,
        encoded: Vec<u8>,
    ) -> Result<(), eyre::Error>;
    /// Broadcast events to all clients
    fn broadcast_client_event(&self, event: BroadcastEvent) -> Result<(), eyre::Error>;
}

/// ZMQ + bincoded structs transport layer that handles socket management and message routing
pub struct RpcTransport {
    zmq_context: r0z::Context,
    kill_switch: Arc<AtomicBool>,
    /// IPC PUB socket for local connections (no CURVE) - binds all IPC endpoints
    events_publish_ipc: Option<Arc<Mutex<Socket>>>,
    /// TCP PUB socket for remote connections (with CURVE) - binds all TCP endpoints
    events_publish_tcp: Option<Arc<Mutex<Socket>>>,
    curve_secret_key: Option<String>, // Z85-encoded CURVE secret key for server mode
    /// IPC endpoints for RPC (no CURVE)
    ipc_rpc_endpoints: Vec<String>,
    /// TCP endpoints for RPC (with CURVE)
    tcp_rpc_endpoints: Vec<String>,
    ready_signal: Option<ReadySignal>,
}

impl RpcTransport {
    /// Parse comma-separated endpoints and group by type (IPC vs TCP)
    fn parse_endpoints(endpoints_str: &str) -> (Vec<String>, Vec<String>) {
        let mut ipc_endpoints = Vec::new();
        let mut tcp_endpoints = Vec::new();

        for endpoint in endpoints_str.split(',') {
            let endpoint = endpoint.trim();
            if endpoint.is_empty() {
                continue;
            }
            if endpoint.starts_with("tcp://") {
                tcp_endpoints.push(endpoint.to_string());
            } else {
                // IPC or other local transports
                ipc_endpoints.push(endpoint.to_string());
            }
        }

        (ipc_endpoints, tcp_endpoints)
    }

    pub fn new(
        zmq_context: r0z::Context,
        kill_switch: Arc<AtomicBool>,
        events_endpoints: &str,
        rpc_endpoints: &str,
        curve_secret_key: Option<String>,
        ready_signal: Option<ReadySignal>,
    ) -> Result<Self, eyre::Error> {
        // Parse endpoints into IPC and TCP groups
        let (ipc_events_endpoints, tcp_events_endpoints) = Self::parse_endpoints(events_endpoints);
        let (ipc_rpc_endpoints, tcp_rpc_endpoints) = Self::parse_endpoints(rpc_endpoints);

        // Create IPC PUB socket if we have any IPC endpoints
        let events_publish_ipc = if !ipc_events_endpoints.is_empty() {
            let ipc_publish = zmq_context
                .socket(r0z::SocketType::PUB)
                .context("Unable to create IPC PUB socket")?;

            for endpoint in &ipc_events_endpoints {
                ipc_publish
                    .bind(endpoint)
                    .with_context(|| format!("Unable to bind IPC PUB socket @ {endpoint}"))?;
                info!("IPC events endpoint bound at {}", endpoint);
            }

            Some(Arc::new(Mutex::new(ipc_publish)))
        } else {
            None
        };

        // Create TCP PUB socket with CURVE if we have any TCP endpoints
        let events_publish_tcp = if !tcp_events_endpoints.is_empty() {
            let tcp_publish = zmq_context
                .socket(r0z::SocketType::PUB)
                .context("Unable to create TCP PUB socket")?;

            // Configure CURVE encryption
            if let Some(ref secret_key) = curve_secret_key {
                tcp_publish
                    .set_zap_domain("moor")
                    .context("Failed to set ZAP domain on TCP PUB socket")?;
                tcp_publish
                    .set_curve_server(true)
                    .context("Failed to enable CURVE server on TCP PUB socket")?;
                let secret_key_bytes =
                    r0z::z85_decode(secret_key).context("Failed to decode Z85 secret key")?;
                tcp_publish
                    .set_curve_secretkey(&secret_key_bytes)
                    .context("Failed to set CURVE secret key on TCP PUB socket")?;
                info!("CURVE encryption enabled on TCP events publisher with ZAP authentication");
            }

            for endpoint in &tcp_events_endpoints {
                tcp_publish
                    .bind(endpoint)
                    .with_context(|| format!("Unable to bind TCP PUB socket @ {endpoint}"))?;
                info!("TCP events endpoint bound at {}", endpoint);
            }

            Some(Arc::new(Mutex::new(tcp_publish)))
        } else {
            None
        };

        Ok(Self {
            zmq_context,
            kill_switch,
            events_publish_ipc,
            events_publish_tcp,
            curve_secret_key,
            ipc_rpc_endpoints,
            tcp_rpc_endpoints,
            ready_signal,
        })
    }

    /// Run queued requests on one thread, sending each reply back through the router.
    fn rpc_worker_loop(
        replies: Arc<Mutex<Socket>>,
        kill_switch: Arc<AtomicBool>,
        scheduler_client: SchedulerClient,
        message_handler: Arc<dyn MessageHandler>,
        jobs: flume::Receiver<RpcJob>,
        run_on_worker: RunOnWorker,
    ) -> eyre::Result<()> {
        while !kill_switch.load(Ordering::Relaxed) {
            let job = match jobs.recv_timeout(Duration::from_secs(1)) {
                Ok(RpcJob::Request(job)) => job,
                Ok(RpcJob::Run(job)) => {
                    job();
                    continue;
                }
                Err(flume::RecvTimeoutError::Timeout) => continue,
                Err(flume::RecvTimeoutError::Disconnected) => return Ok(()),
            };
            let route = ReplyRoute {
                transport: job.transport,
                envelope: job.envelope,
                replies: replies.clone(),
                run_on_worker: run_on_worker.clone(),
            };
            match Self::process_request(
                job.request,
                Some(route.clone()),
                &scheduler_client,
                message_handler.as_ref(),
            ) {
                Ok(Some(reply)) => route.send(reply),
                Ok(None) => {}
                Err(e) => error!(error = ?e, "Error processing request"),
            }
        }
        Ok(())
    }

    /// Own the client-facing sockets: queue each request for a free thread, and send back replies.
    /// This never runs a handler, so a slow request cannot delay other requests or their replies.
    fn run_router(
        &self,
        clients: Vec<Socket>,
        replies: Socket,
        control_jobs: flume::Sender<RpcJob>,
        worker_jobs: flume::Sender<RpcJob>,
    ) -> eyre::Result<()> {
        while !self.kill_switch.load(Ordering::Relaxed) {
            let mut items: Vec<_> = clients
                .iter()
                .map(|client| client.as_poll_item(r0z::POLLIN))
                .collect();
            items.push(replies.as_poll_item(r0z::POLLIN));
            r0z::poll(&mut items, 1000).with_context(|| "Error polling RPC sockets")?;
            let readable: Vec<bool> = items.iter().map(|item| item.is_readable()).collect();
            drop(items);

            for (transport, client) in clients.iter().enumerate() {
                if readable[transport] {
                    while let Ok(frames) = client.recv_multipart(r0z::DONTWAIT) {
                        Self::queue_request(transport as u8, frames, &control_jobs, &worker_jobs);
                    }
                }
            }
            if readable[clients.len()] {
                while let Ok(mut frames) = replies.recv_multipart(r0z::DONTWAIT) {
                    let transport = frames.remove(0)[0] as usize;
                    if let Err(e) = clients[transport].send_multipart(frames, 0) {
                        warn!(error = ?e, "Unable to send RPC reply");
                    }
                }
            }
        }
        info!("Kill switch activated, exiting");
        Ok(())
    }

    fn queue_request(
        transport: u8,
        frames: Vec<Vec<u8>>,
        control_jobs: &flume::Sender<RpcJob>,
        worker_jobs: &flume::Sender<RpcJob>,
    ) {
        let Some((envelope, request)) = split_envelope(frames) else {
            warn!("Dropping an RPC request with no routing envelope");
            return;
        };
        let is_pong = request_is_pong(&request);
        let queue = if is_pong { control_jobs } else { worker_jobs };
        let job = RpcJob::Request(RpcRequest {
            transport,
            envelope,
            request,
        });
        // A host that gets no reply times out, as it does when any request is lost.
        if queue.try_send(job).is_err() {
            warn!(is_pong, "RPC queue is full; dropping a request");
        }
    }

    fn rpc_direct_inproc_loop(
        &self,
        scheduler_client: SchedulerClient,
        message_handler: Arc<dyn MessageHandler>,
    ) -> eyre::Result<()> {
        let rpc_socket = self.zmq_context.socket(r0z::REP)?;
        for endpoint in &self.ipc_rpc_endpoints {
            rpc_socket.bind(endpoint)?;
            info!("Inproc RPC endpoint bound at {}", endpoint);
        }

        signal_ready(&self.ready_signal);

        loop {
            if self.kill_switch.load(Ordering::Relaxed) {
                return Ok(());
            }

            let poll_result = rpc_socket
                .poll(r0z::POLLIN, 1000)
                .with_context(|| "Error polling ZMQ socket. Bailing out.")?;
            if poll_result == 0 {
                continue;
            }

            match rpc_socket.recv_multipart(0) {
                Err(_) => {
                    info!("ZMQ socket closed, exiting");
                    return Ok(());
                }
                Ok(request) => {
                    match Self::process_request(
                        request,
                        None,
                        &scheduler_client,
                        message_handler.as_ref(),
                    ) {
                        Ok(Some(reply)) => rpc_socket.send_multipart(vec![reply], 0)?,
                        Ok(None) => {}
                        Err(e) => error!(error = ?e, "Error processing request"),
                    }
                }
            }
        }
    }

    /// Process a single request message
    fn process_request(
        request: Vec<Vec<u8>>,
        route: Option<ReplyRoute>,
        scheduler_client: &SchedulerClient,
        message_handler: &dyn MessageHandler,
    ) -> eyre::Result<Option<Vec<u8>>> {
        // Components are: [discriminator, request_body]
        // discriminator is a MessageType FlatBuffer that tells us what's in request_body
        if request.len() != 2 {
            return Self::invalid_request_reply("Incorrect message length").map(Some);
        }

        let (discriminator, request_body) = (&request[0], &request[1]);

        // Decode the MessageType discriminator
        let message_type_ref = match MessageTypeRef::read_as_root(discriminator) {
            Ok(msg) => msg,
            Err(_) => {
                return Self::invalid_request_reply("Could not decode message type").map(Some);
            }
        };

        use moor_rpc::MessageTypeUnionRef;
        match message_type_ref
            .message()
            .map_err(|_| eyre::eyre!("Missing message union"))?
        {
            MessageTypeUnionRef::HostToDaemonMsg(host_msg) => {
                // Extract host_id from discriminator
                let host_id_ref = match host_msg.host_id() {
                    Ok(id) => id,
                    Err(_) => {
                        return Self::invalid_request_reply("Missing host_id").map(Some);
                    }
                };
                let host_id_data = match host_id_ref.data() {
                    Ok(data) => data,
                    Err(_) => {
                        return Self::invalid_request_reply("Invalid host_id").map(Some);
                    }
                };
                let Ok(host_id) = Uuid::from_slice(host_id_data) else {
                    return Self::invalid_request_reply("Bad host_id").map(Some);
                };

                // Decode the actual HostToDaemonMessage from request_body
                let Ok(host_message_fb) = HostToDaemonMessageRef::read_as_root(request_body) else {
                    return Self::invalid_request_reply("Could not decode host message").map(Some);
                };

                // Process
                let response = message_handler.handle_host_message(host_id, host_message_fb);
                match Self::pack_host_response(response) {
                    Ok(response) => {
                        return Ok(Some(response));
                    }
                    Err(e) => {
                        error!(error = ?e, "Failed to encode host response");
                    }
                }
            }
            MessageTypeUnionRef::HostClientToDaemonMsg(client_msg) => {
                // Extract client_id from discriminator
                let Ok(client_data) = client_msg.client_data() else {
                    return Self::invalid_request_reply("Missing client data").map(Some);
                };
                let Ok(client_id) = Uuid::from_slice(client_data) else {
                    return Self::invalid_request_reply("Bad client id").map(Some);
                };

                // Decode the actual HostClientToDaemonMessage from request_body
                let Ok(request_fb) =
                    moor_rpc::HostClientToDaemonMessageRef::read_as_root(request_body)
                else {
                    return Self::invalid_request_reply("Could not decode request body").map(Some);
                };

                // Process the request
                // With a route, a request that waits for a task can reply later and free this
                // thread. The direct inproc path has a REP socket, which must reply now.
                let response = match route {
                    Some(route) => {
                        let run_on_worker = route.run_on_worker.clone();
                        let sink: DaemonReplySink =
                            Box::new(move |response| match Self::pack_client_response(response) {
                                Ok(reply) => route.send(reply),
                                Err(e) => error!(error = ?e, "Failed to encode client response"),
                            });
                        let response = message_handler.handle_client_message_deferred(
                            scheduler_client.clone(),
                            client_id,
                            request_fb,
                            sink,
                            run_on_worker,
                        );
                        let Some(response) = response else {
                            return Ok(None);
                        };
                        response
                    }
                    None => message_handler.handle_client_message(
                        scheduler_client.clone(),
                        client_id,
                        request_fb,
                    ),
                };
                match Self::pack_client_response(response) {
                    Ok(response) => {
                        return Ok(Some(response));
                    }
                    Err(e) => {
                        error!(error = ?e, "Failed to encode client response");
                    }
                }
            }
        }

        Ok(None)
    }

    fn invalid_request_reply(reason: &str) -> eyre::Result<Vec<u8>> {
        warn!("Invalid request received, replying with error: {reason}");
        Self::pack_client_response(Err(RpcMessageError::InvalidRequest(reason.to_string())))
    }

    fn pack_client_response(
        result: Result<moor_rpc::DaemonToClientReply, RpcMessageError>,
    ) -> Result<Vec<u8>, eyre::Error> {
        match result {
            Ok(reply) => {
                let mut builder = planus::Builder::new();
                let reply_result = moor_rpc::ReplyResult {
                    result: moor_rpc::ReplyResultUnion::ClientSuccess(Box::new(
                        moor_rpc::ClientSuccess {
                            reply: Box::new(reply),
                        },
                    )),
                };
                let finished = builder.finish(&reply_result, None);
                Ok(finished.to_vec())
            }
            Err(e) => {
                let mut builder = planus::Builder::new();

                // Convert RpcMessageError to FlatBuffer format
                let (error_code, message, scheduler_error) = match &e {
                    RpcMessageError::AlreadyConnected => (
                        moor_rpc::RpcMessageErrorCode::AlreadyConnected,
                        Some("Already connected".to_string()),
                        None,
                    ),
                    RpcMessageError::InvalidRequest(msg) => (
                        moor_rpc::RpcMessageErrorCode::InvalidRequest,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::NoConnection => (
                        moor_rpc::RpcMessageErrorCode::NoConnection,
                        Some("No connection for client".to_string()),
                        None,
                    ),
                    RpcMessageError::ErrorCouldNotRetrieveSysProp(msg) => (
                        moor_rpc::RpcMessageErrorCode::ErrorCouldNotRetrieveSysProp,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::LoginTaskFailed(msg) => (
                        moor_rpc::RpcMessageErrorCode::LoginTaskFailed,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::CreateSessionFailed => (
                        moor_rpc::RpcMessageErrorCode::CreateSessionFailed,
                        Some("Could not create session".to_string()),
                        None,
                    ),
                    RpcMessageError::PermissionDenied => (
                        moor_rpc::RpcMessageErrorCode::PermissionDenied,
                        Some("Permission denied".to_string()),
                        None,
                    ),
                    RpcMessageError::TaskError(scheduler_error) => {
                        let scheduler_error_fb =
                            scheduler_error_to_flatbuffer_struct(scheduler_error)
                                .ok()
                                .map(Box::new);
                        (
                            moor_rpc::RpcMessageErrorCode::TaskError,
                            None,
                            scheduler_error_fb,
                        )
                    }
                    RpcMessageError::EntityRetrievalError(msg) => (
                        moor_rpc::RpcMessageErrorCode::EntityRetrievalError,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::EventStreamExpired => (
                        moor_rpc::RpcMessageErrorCode::EventStreamExpired,
                        None,
                        None,
                    ),
                    RpcMessageError::ServerBusy => {
                        (moor_rpc::RpcMessageErrorCode::ServerBusy, None, None)
                    }
                    RpcMessageError::InternalError(msg) => (
                        moor_rpc::RpcMessageErrorCode::InternalError,
                        Some(msg.clone()),
                        None,
                    ),
                };

                let error_fb = moor_rpc::RpcMessageError {
                    error_code,
                    message,
                    scheduler_error,
                };
                let reply_result = moor_rpc::ReplyResult {
                    result: moor_rpc::ReplyResultUnion::Failure(Box::new(moor_rpc::Failure {
                        error: Box::new(error_fb),
                    })),
                };
                let finished = builder.finish(&reply_result, None);
                Ok(finished.to_vec())
            }
        }
    }

    fn pack_host_response(
        result: Result<moor_rpc::DaemonToHostReply, RpcMessageError>,
    ) -> Result<Vec<u8>, eyre::Error> {
        match result {
            Ok(reply) => {
                let mut builder = planus::Builder::new();
                let reply_result = moor_rpc::ReplyResult {
                    result: moor_rpc::ReplyResultUnion::HostSuccess(Box::new(
                        moor_rpc::HostSuccess {
                            reply: Box::new(reply),
                        },
                    )),
                };
                let finished = builder.finish(&reply_result, None);
                Ok(finished.to_vec())
            }
            Err(e) => {
                let mut builder = planus::Builder::new();

                // Convert RpcMessageError to FlatBuffer format
                let (error_code, message, scheduler_error) = match &e {
                    RpcMessageError::AlreadyConnected => (
                        moor_rpc::RpcMessageErrorCode::AlreadyConnected,
                        Some("Already connected".to_string()),
                        None,
                    ),
                    RpcMessageError::InvalidRequest(msg) => (
                        moor_rpc::RpcMessageErrorCode::InvalidRequest,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::NoConnection => (
                        moor_rpc::RpcMessageErrorCode::NoConnection,
                        Some("No connection for client".to_string()),
                        None,
                    ),
                    RpcMessageError::ErrorCouldNotRetrieveSysProp(msg) => (
                        moor_rpc::RpcMessageErrorCode::ErrorCouldNotRetrieveSysProp,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::LoginTaskFailed(msg) => (
                        moor_rpc::RpcMessageErrorCode::LoginTaskFailed,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::CreateSessionFailed => (
                        moor_rpc::RpcMessageErrorCode::CreateSessionFailed,
                        Some("Could not create session".to_string()),
                        None,
                    ),
                    RpcMessageError::PermissionDenied => (
                        moor_rpc::RpcMessageErrorCode::PermissionDenied,
                        Some("Permission denied".to_string()),
                        None,
                    ),
                    RpcMessageError::TaskError(scheduler_error) => {
                        let scheduler_error_fb =
                            scheduler_error_to_flatbuffer_struct(scheduler_error)
                                .ok()
                                .map(Box::new);
                        (
                            moor_rpc::RpcMessageErrorCode::TaskError,
                            None,
                            scheduler_error_fb,
                        )
                    }
                    RpcMessageError::EntityRetrievalError(msg) => (
                        moor_rpc::RpcMessageErrorCode::EntityRetrievalError,
                        Some(msg.clone()),
                        None,
                    ),
                    RpcMessageError::EventStreamExpired => (
                        moor_rpc::RpcMessageErrorCode::EventStreamExpired,
                        None,
                        None,
                    ),
                    RpcMessageError::ServerBusy => {
                        (moor_rpc::RpcMessageErrorCode::ServerBusy, None, None)
                    }
                    RpcMessageError::InternalError(msg) => (
                        moor_rpc::RpcMessageErrorCode::InternalError,
                        Some(msg.clone()),
                        None,
                    ),
                };

                let error_fb = moor_rpc::RpcMessageError {
                    error_code,
                    message,
                    scheduler_error,
                };
                let reply_result = moor_rpc::ReplyResult {
                    result: moor_rpc::ReplyResultUnion::Failure(Box::new(moor_rpc::Failure {
                        error: Box::new(error_fb),
                    })),
                };
                let finished = builder.finish(&reply_result, None);
                Ok(finished.to_vec())
            }
        }
    }
}

impl Transport for RpcTransport {
    /// Start the request processing loop
    fn start_request_loop(
        &self,
        _rpc_endpoint: String, // Ignored - we use ipc_rpc_endpoints and tcp_rpc_endpoints
        scheduler_client: SchedulerClient,
        message_handler: Arc<dyn MessageHandler>,
    ) -> eyre::Result<()> {
        let num_io_threads = self.zmq_context.get_io_threads()?;
        let has_ipc = !self.ipc_rpc_endpoints.is_empty();
        let has_tcp = !self.tcp_rpc_endpoints.is_empty();

        info!(
            "Starting RPC server with {} IO threads, IPC endpoints: {:?}, TCP endpoints: {:?}",
            num_io_threads, self.ipc_rpc_endpoints, self.tcp_rpc_endpoints
        );

        let inproc_only = !has_tcp
            && has_ipc
            && self
                .ipc_rpc_endpoints
                .iter()
                .all(|endpoint| endpoint.starts_with("inproc://"));
        if inproc_only {
            info!("Using direct inproc RPC server path");
            return self.rpc_direct_inproc_loop(scheduler_client, message_handler);
        }

        let mut clients = Vec::with_capacity(2);

        // Bind all IPC endpoints to one socket (no CURVE)
        if has_ipc {
            let ipc_clients = self.zmq_context.socket(r0z::ROUTER)?;
            for endpoint in &self.ipc_rpc_endpoints {
                ipc_clients.bind(endpoint)?;
                info!("IPC RPC endpoint bound at {}", endpoint);
            }
            clients.push(ipc_clients);
        }

        // Bind all TCP endpoints to one socket, with CURVE encryption if configured
        if has_tcp {
            let tcp_clients = self.zmq_context.socket(r0z::ROUTER)?;
            if let Some(ref secret_key) = self.curve_secret_key {
                tcp_clients
                    .set_zap_domain("moor")
                    .context("Failed to set ZAP domain on TCP ROUTER socket")?;
                tcp_clients
                    .set_curve_server(true)
                    .context("Failed to enable CURVE server on TCP ROUTER socket")?;
                let secret_key_bytes =
                    r0z::z85_decode(secret_key).context("Failed to decode Z85 secret key")?;
                tcp_clients
                    .set_curve_secretkey(&secret_key_bytes)
                    .context("Failed to set CURVE secret key on TCP ROUTER socket")?;
                info!("CURVE encryption enabled on TCP RPC server with ZAP authentication");
            }
            for endpoint in &self.tcp_rpc_endpoints {
                tcp_clients.bind(endpoint)?;
                info!("TCP RPC endpoint bound at {}", endpoint);
            }
            clients.push(tcp_clients);
        }

        let replies = self.zmq_context.socket(r0z::PULL)?;
        replies.bind(RPC_REPLIES_ENDPOINT)?;

        // Replies can come from workers and from whichever thread finishes a waiting call.
        let reply_sender = self.zmq_context.socket(r0z::PUSH)?;
        reply_sender.connect(RPC_REPLIES_ENDPOINT)?;
        let reply_sender = Arc::new(Mutex::new(reply_sender));

        let (control_jobs, control_receive) = flume::bounded(MAX_QUEUED_CONTROL_REQUESTS);
        let (worker_jobs, worker_receive) = flume::bounded(MAX_QUEUED_REQUESTS);

        // Keep the existing worker count until measurements justify changing it.
        let num_proxies = (has_ipc as i32) + (has_tcp as i32);
        let num_workers = (num_io_threads - num_proxies).max(1);

        // A job that finds the queue full runs here instead: it finishes a request already started,
        // so it cannot be dropped, and this keeps its caller from waiting on the queue.
        let run_on_worker: RunOnWorker = {
            let worker_jobs = worker_jobs.clone();
            Arc::new(move |job| {
                if let Err(flume::TrySendError::Full(RpcJob::Run(job))) =
                    worker_jobs.try_send(RpcJob::Run(job))
                {
                    job();
                }
            })
        };

        let spawn_worker = |name: String, jobs: flume::Receiver<RpcJob>| {
            let handler = message_handler.clone();
            let sched_client = scheduler_client.clone();
            let kill_switch = self.kill_switch.clone();
            let replies = reply_sender.clone();
            let run_on_worker = run_on_worker.clone();
            spawn_efficient(name, move || {
                if let Err(e) = Self::rpc_worker_loop(
                    replies,
                    kill_switch,
                    sched_client,
                    handler,
                    jobs,
                    run_on_worker,
                ) {
                    error!(error = ?e, "RPC worker loop failed");
                }
            })
        };
        spawn_worker("moor-rpc-control".to_string(), control_receive)?;
        for i in 0..num_workers {
            spawn_worker(format!("moor-rpc-srv{i}"), worker_receive.clone())?;
        }

        signal_ready(&self.ready_signal);

        self.run_router(clients, replies, control_jobs, worker_jobs)
    }
    /// Broadcast events to hosts
    fn broadcast_host_event(&self, event: HostBroadcastEvent) -> Result<(), eyre::Error> {
        let event_bytes = encode_host_broadcast_event_bytes(&event)
            .map_err(|e| eyre::eyre!("Failed to encode host event: {e}"))?;
        let payload = vec![HOST_BROADCAST_TOPIC.to_vec(), event_bytes];

        // Send to IPC socket if available
        if let Some(ref ipc_pub) = self.events_publish_ipc {
            let ipc_pub = ipc_pub.lock().unwrap();
            ipc_pub.send_multipart(payload.clone(), 0).map_err(|e| {
                error!(error = ?e, "Unable to send host broadcast event to IPC");
                eyre::eyre!("Delivery error (IPC)")
            })?;
        }

        // Send to TCP socket if available
        if let Some(ref tcp_pub) = self.events_publish_tcp {
            let tcp_pub = tcp_pub.lock().unwrap();
            tcp_pub.send_multipart(payload, 0).map_err(|e| {
                error!(error = ?e, "Unable to send host broadcast event to TCP");
                eyre::eyre!("Delivery error (TCP)")
            })?;
        }

        Ok(())
    }
    /// Publish event to specific client
    fn publish_client_event(
        &self,
        client_id: Uuid,
        _event: ClientEventMessage,
        encoded: Vec<u8>,
    ) -> Result<(), eyre::Error> {
        let payload = vec![client_id.as_bytes().to_vec(), encoded];

        // Send to IPC socket if available
        if let Some(ref ipc_pub) = self.events_publish_ipc {
            let ipc_pub = ipc_pub.lock().unwrap();
            ipc_pub.send_multipart(payload.clone(), 0).map_err(|e| {
                error!(error = ?e, "Unable to send client event to IPC");
                eyre::eyre!("Delivery error (IPC)")
            })?;
        }

        // Send to TCP socket if available
        if let Some(ref tcp_pub) = self.events_publish_tcp {
            let tcp_pub = tcp_pub.lock().unwrap();
            tcp_pub.send_multipart(payload, 0).map_err(|e| {
                error!(error = ?e, "Unable to send client event to TCP");
                eyre::eyre!("Delivery error (TCP)")
            })?;
        }

        Ok(())
    }
    /// Broadcast events to all clients
    fn broadcast_client_event(&self, event: BroadcastEvent) -> Result<(), eyre::Error> {
        let event_bytes = encode_broadcast_event_bytes(&event);
        let payload = vec![CLIENT_BROADCAST_TOPIC.to_vec(), event_bytes];

        // Send to IPC socket if available
        if let Some(ref ipc_pub) = self.events_publish_ipc {
            let ipc_pub = ipc_pub.lock().unwrap();
            ipc_pub.send_multipart(payload.clone(), 0).map_err(|e| {
                error!(error = ?e, "Unable to send client broadcast event to IPC");
                eyre::eyre!("Delivery error (IPC)")
            })?;
        }

        // Send to TCP socket if available
        if let Some(ref tcp_pub) = self.events_publish_tcp {
            let tcp_pub = tcp_pub.lock().unwrap();
            tcp_pub.send_multipart(payload, 0).map_err(|e| {
                error!(error = ?e, "Unable to send client broadcast event to TCP");
                eyre::eyre!("Delivery error (TCP)")
            })?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod router_tests {
    use super::*;

    #[test]
    fn the_envelope_runs_through_the_empty_delimiter() {
        let frames = vec![b"id".to_vec(), vec![], b"a".to_vec(), b"b".to_vec()];
        let (envelope, request) = split_envelope(frames).unwrap();
        assert_eq!(envelope, vec![b"id".to_vec(), vec![]]);
        assert_eq!(request, vec![b"a".to_vec(), b"b".to_vec()]);
    }

    #[test]
    fn a_message_with_no_delimiter_has_no_envelope() {
        assert!(split_envelope(vec![b"id".to_vec(), b"a".to_vec()]).is_none());
    }

    #[test]
    fn malformed_requests_are_not_pongs() {
        assert!(!request_is_pong(&[]));
        assert!(!request_is_pong(&[b"junk".to_vec(), b"junk".to_vec()]));
    }
}
