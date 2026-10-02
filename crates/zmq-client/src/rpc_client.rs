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

use moor_common::config::MAX_CAPTURE_DEADLINE_MS;
use moor_runtime_api::{RpcError, uuid_fb};
use moor_schema::rpc as moor_rpc;
use planus::Builder;
use r0z_async::{
    AsZmqSocket, Multipart,
    request_reply::{RequestReply, RequestReplyState},
};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use tracing::debug;
use uuid::Uuid;

const DEFAULT_SOCK_CONNECT_TIMEOUT_MS: i32 = 5000;
const DEFAULT_SOCK_RECEIVE_TIMEOUT_MS: i32 = 5000;

/// How much longer than a request's own deadline a socket waits for the reply. The daemon only
/// answers a captured invocation once the task finishes or its deadline expires, so the socket has
/// to outlive that deadline or the caller gives up on a reply that is about to arrive. The daemon
/// may also spend a scheduler request timeout cancelling a task that overran, which lands inside
/// the same wait, so the margin is generous enough to cover that too.
const RECEIVE_TIMEOUT_MARGIN_MS: i32 = 15000;

/// Configuration for the RPC client
#[derive(Debug, Clone)]
pub struct RpcConfig {
    pub max_pool_size: usize,
    pub connect_timeout_ms: i32,
    pub receive_timeout_ms: i32,
}

impl Default for RpcConfig {
    fn default() -> Self {
        Self {
            max_pool_size: 10,
            connect_timeout_ms: DEFAULT_SOCK_CONNECT_TIMEOUT_MS,
            receive_timeout_ms: DEFAULT_SOCK_RECEIVE_TIMEOUT_MS,
        }
    }
}

/// CURVE encryption keys for secure connections
#[derive(Debug, Clone)]
pub struct CurveKeys {
    pub client_secret: String,
    pub client_public: String,
    pub server_public: String,
}

/// RPC client with connection pooling and cancellation safety
pub struct RpcClient {
    zmq_context: Arc<r0z_async::Context>,
    rpc_addr: String,
    curve_keys: Option<CurveKeys>,
    config: RpcConfig,
    connection_pool: Mutex<VecDeque<RequestReply>>,
}

impl Clone for RpcClient {
    fn clone(&self) -> Self {
        Self {
            zmq_context: self.zmq_context.clone(),
            rpc_addr: self.rpc_addr.clone(),
            curve_keys: self.curve_keys.clone(),
            config: self.config.clone(),
            connection_pool: Mutex::new(VecDeque::new()), // New pool for clone
        }
    }
}

/// Socket guard that ensures socket cleanup regardless of cancellation
struct SocketGuard<'a> {
    client: &'a RpcClient,
    socket: Option<RequestReply>,
    /// Whether the socket belongs to the pool. A socket built for one long deadline is discarded
    /// afterwards rather than handed to an unrelated caller that expects the shorter default.
    pooled: bool,
}

impl<'a> SocketGuard<'a> {
    /// Create a new socket guard, acquiring a socket from the pool
    async fn new(client: &'a RpcClient) -> Result<Self, RpcError> {
        let socket = client.acquire_socket().await?;
        Ok(Self {
            client,
            socket: Some(socket),
            pooled: true,
        })
    }

    /// Create a socket guard over a socket built for a single call with its own receive timeout.
    async fn dedicated(client: &'a RpcClient, receive_timeout_ms: i32) -> Result<Self, RpcError> {
        let socket = client
            .create_socket_with_timeout(receive_timeout_ms)
            .await?;
        Ok(Self {
            client,
            socket: Some(socket),
            pooled: false,
        })
    }

    fn socket_mut(&mut self) -> &mut RequestReply {
        self.socket.as_mut().expect("RPC guard owns its socket")
    }
}

impl Drop for SocketGuard<'_> {
    fn drop(&mut self) {
        let Some(socket) = self.socket.take() else {
            return;
        };
        if self.pooled && socket.state() == RequestReplyState::SendReady {
            self.client.return_socket(socket);
        }
    }
}

impl RpcClient {
    /// Create a new managed RPC client
    pub fn new(
        zmq_context: Arc<r0z_async::Context>,
        rpc_addr: String,
        curve_keys: Option<CurveKeys>,
        config: RpcConfig,
    ) -> Self {
        Self {
            zmq_context,
            rpc_addr,
            curve_keys,
            config,
            connection_pool: Mutex::new(VecDeque::new()),
        }
    }

    /// Create a new managed RPC client with default configuration
    pub fn new_with_defaults(
        zmq_context: Arc<r0z_async::Context>,
        rpc_addr: String,
        curve_keys: Option<CurveKeys>,
    ) -> Self {
        Self::new(zmq_context, rpc_addr, curve_keys, RpcConfig::default())
    }

    /// Make a client RPC call with cancellation safety and connection pooling
    pub async fn make_client_rpc_call(
        &self,
        client_id: Uuid,
        rpc_msg: moor_rpc::HostClientToDaemonMessage,
    ) -> Result<Vec<u8>, RpcError> {
        // Use a guard pattern to ensure socket cleanup regardless of cancellation
        let mut socket_guard = match required_receive_timeout_ms(&rpc_msg) {
            Some(timeout_ms) if timeout_ms > self.config.receive_timeout_ms => {
                SocketGuard::dedicated(self, timeout_ms).await?
            }
            _ => SocketGuard::new(self).await?,
        };
        Self::perform_rpc_call(socket_guard.socket_mut(), client_id, rpc_msg).await
    }

    /// Make a host RPC call with cancellation safety and connection pooling
    pub async fn make_host_rpc_call(
        &self,
        host_id: Uuid,
        rpc_message: moor_rpc::HostToDaemonMessage,
    ) -> Result<Vec<u8>, RpcError> {
        // Use a guard pattern to ensure socket cleanup regardless of cancellation
        let mut socket_guard = SocketGuard::new(self).await?;
        Self::perform_host_rpc_call(socket_guard.socket_mut(), host_id, rpc_message).await
    }

    /// Acquire a socket from the pool or create a new one
    async fn acquire_socket(&self) -> Result<RequestReply, RpcError> {
        let socket = self.connection_pool.lock().unwrap().pop_front();
        if let Some(socket) = socket {
            debug!("Reusing socket from pool");
            return Ok(socket);
        }
        self.create_socket().await
    }

    /// Return a socket to the pool, discarding if pool is full
    fn return_socket(&self, socket: RequestReply) {
        let mut pool = self.connection_pool.lock().unwrap();

        if pool.len() < self.config.max_pool_size {
            pool.push_back(socket);
        } else {
            drop(socket);
        }
    }

    /// Create a new socket with proper configuration
    async fn create_socket(&self) -> Result<RequestReply, RpcError> {
        self.create_socket_with_timeout(self.config.receive_timeout_ms)
            .await
    }

    /// Create a new socket that waits `receive_timeout_ms` for its reply.
    async fn create_socket_with_timeout(
        &self,
        receive_timeout_ms: i32,
    ) -> Result<RequestReply, RpcError> {
        let mut socket_builder = r0z_async::request(&self.zmq_context)
            .set_rcvtimeo(receive_timeout_ms)
            .set_sndtimeo(self.config.connect_timeout_ms)
            // Fail immediately if no connection instead of queuing messages indefinitely
            .set_immediate(true)
            // Don't linger on close - drop queued messages immediately
            .set_linger(0);

        // Configure CURVE encryption if keys provided
        if let Some(curve_keys) = &self.curve_keys {
            socket_builder = super::configure_curve_client(
                socket_builder,
                &curve_keys.client_secret,
                &curve_keys.client_public,
                &curve_keys.server_public,
            )
            .map_err(|e| RpcError::Fatal(format!("Failed to configure CURVE: {}", e)))?;
        }

        socket_builder
            .connect(&self.rpc_addr)
            .map_err(|e| RpcError::Fatal(format!("Failed to connect to RPC server: {}", e)))
    }

    /// Perform an RPC call with guaranteed socket cleanup
    async fn perform_rpc_call(
        socket: &mut RequestReply,
        client_id: Uuid,
        rpc_msg: moor_rpc::HostClientToDaemonMessage,
    ) -> Result<Vec<u8>, RpcError> {
        // Serialize the message to FlatBuffer bytes
        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&rpc_msg, None).to_vec();

        // Build the MessageType discriminator
        let client_msg = moor_rpc::HostClientToDaemonMsg {
            client_data: client_id.as_bytes().to_vec(),
            message: Box::new(rpc_msg),
        };
        let message_type = moor_rpc::MessageType {
            message: moor_rpc::MessageTypeUnion::HostClientToDaemonMsg(Box::new(client_msg)),
        };
        let mut discriminator_builder = Builder::new();
        let message_type_bytes = discriminator_builder.finish(&message_type, None).to_vec();

        let message = Multipart::from(vec![message_type_bytes, rpc_msg_payload]);

        let reply = exchange(socket, message).await?;
        Ok(reply[0].to_vec())
    }

    /// Perform a host RPC call with guaranteed socket cleanup
    async fn perform_host_rpc_call(
        socket: &mut RequestReply,
        host_id: Uuid,
        rpc_message: moor_rpc::HostToDaemonMessage,
    ) -> Result<Vec<u8>, RpcError> {
        // Serialize the message to FlatBuffer bytes
        let mut builder = Builder::new();
        let rpc_msg_payload = builder.finish(&rpc_message, None).to_vec();

        // Build the MessageType discriminator
        let host_msg = moor_rpc::HostToDaemonMsg {
            host_id: uuid_fb(host_id),
            message: Box::new(rpc_message),
        };
        let message_type = moor_rpc::MessageType {
            message: moor_rpc::MessageTypeUnion::HostToDaemonMsg(Box::new(host_msg)),
        };
        let mut discriminator_builder = Builder::new();
        let message_type_bytes = discriminator_builder.finish(&message_type, None).to_vec();

        let message = Multipart::from(vec![message_type_bytes, rpc_msg_payload]);

        let reply = exchange(socket, message).await?;
        Ok(reply[0].to_vec())
    }

    /// Get current pool size for monitoring
    pub async fn pool_size(&self) -> usize {
        let pool = self.connection_pool.lock().unwrap();
        pool.len()
    }

    /// Clear the connection pool (useful for cleanup)
    pub async fn clear_pool(&self) {
        let mut pool = self.connection_pool.lock().unwrap();
        pool.clear();
        debug!("Cleared RPC connection pool");
    }
}

/// Complete one exchange while enforcing the configured asynchronous deadlines.
pub(crate) async fn exchange(
    socket: &mut RequestReply,
    message: Multipart,
) -> Result<Multipart, RpcError> {
    let send_timeout = socket
        .get_socket()
        .get_sndtimeo()
        .map_err(|e| RpcError::CouldNotSend(e.to_string()))?;
    let receive_timeout = socket
        .get_socket()
        .get_rcvtimeo()
        .map_err(|e| RpcError::CouldNotReceive(e.to_string()))?;
    socket_operation(send_timeout, socket.send(message))
        .await
        .map_err(RpcError::CouldNotSend)?;
    socket_operation(receive_timeout, socket.recv())
        .await
        .map_err(RpcError::CouldNotReceive)
}

async fn socket_operation<T>(
    timeout_ms: i32,
    operation: impl std::future::Future<Output = r0z_async::Result<T>>,
) -> Result<T, String> {
    if timeout_ms < 0 {
        return operation.await.map_err(|e| e.to_string());
    }
    tokio::time::timeout(
        std::time::Duration::from_millis(timeout_ms as u64),
        operation,
    )
    .await
    .map_err(|_| format!("RPC operation timed out after {timeout_ms}ms"))?
    .map_err(|e| e.to_string())
}

/// The receive timeout a message needs, when it needs more than the configured default.
///
/// Only a captured invocation does: the daemon holds the reply until the task finishes or its
/// deadline expires. A request that asks the daemon to pick the deadline, and the welcome message
/// which always uses the daemon's configured maximum, are sized against the protocol ceiling
/// instead, because the client cannot see what the daemon is configured to.
fn required_receive_timeout_ms(rpc_msg: &moor_rpc::HostClientToDaemonMessage) -> Option<i32> {
    let deadline_ms = match &rpc_msg.message {
        moor_rpc::HostClientToDaemonMessageUnion::Command(command) => {
            capture_deadline_ms(&command.mode)?
        }
        moor_rpc::HostClientToDaemonMessageUnion::InvokeVerb(invoke) => {
            capture_deadline_ms(&invoke.mode)?
        }
        moor_rpc::HostClientToDaemonMessageUnion::Eval(eval) => capture_deadline_ms(&eval.mode)?,
        moor_rpc::HostClientToDaemonMessageUnion::InvokeSystemHandler(handler) => {
            if handler.timeout_ms == 0 {
                MAX_CAPTURE_DEADLINE_MS
            } else {
                handler.timeout_ms
            }
        }
        moor_rpc::HostClientToDaemonMessageUnion::InvokeWelcomeMessage(_) => {
            MAX_CAPTURE_DEADLINE_MS
        }
        _ => return None,
    };
    let deadline_ms = i32::try_from(deadline_ms).unwrap_or(i32::MAX);
    Some(deadline_ms.saturating_add(RECEIVE_TIMEOUT_MARGIN_MS))
}

fn capture_deadline_ms(mode: &moor_rpc::InvocationMode) -> Option<u64> {
    let moor_rpc::InvocationMode::CaptureOutputInvocation(capture) = mode else {
        return None;
    };
    Some(if capture.timeout_ms == 0 {
        MAX_CAPTURE_DEADLINE_MS
    } else {
        capture.timeout_ms
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_runtime_api::{
        AuthToken, ClientToken, mk_command_capture_msg, mk_eval_capture_msg,
        mk_invoke_system_handler_msg, mk_invoke_verb_capture_msg, mk_invoke_verb_msg,
        mk_invoke_welcome_message_msg, mk_list_objects_msg,
    };
    use moor_var::Symbol;
    use std::time::Duration;

    fn auth_token() -> AuthToken {
        AuthToken("auth".to_string())
    }

    #[test]
    fn a_connected_invocation_uses_the_default_receive_timeout() {
        let msg = mk_invoke_verb_msg(
            &ClientToken("client".to_string()),
            &auth_token(),
            &moor_common::model::ObjectRef::Id(moor_var::Obj::mk_id(1)),
            &Symbol::mk("look"),
            vec![],
        )
        .expect("message");
        assert_eq!(required_receive_timeout_ms(&msg), None);
    }

    #[test]
    fn a_captured_invocation_waits_longer_than_its_own_deadline() {
        let msg = mk_invoke_verb_capture_msg(
            &auth_token(),
            &moor_common::model::ObjectRef::Id(moor_var::Obj::mk_id(1)),
            &Symbol::mk("look"),
            vec![],
            Some(Duration::from_secs(120)),
        )
        .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(
            timeout_ms > 120_000,
            "receive timeout {timeout_ms}ms must exceed the 120000ms deadline"
        );
    }

    #[test]
    fn a_captured_command_waits_longer_than_its_own_deadline() {
        let msg = mk_command_capture_msg(
            &auth_token(),
            &moor_var::SYSTEM_OBJECT,
            "look".to_string(),
            Some(Duration::from_secs(120)),
        )
        .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(
            timeout_ms > 120_000,
            "receive timeout {timeout_ms}ms must exceed the 120000ms deadline"
        );
    }

    #[test]
    fn a_captured_eval_waits_longer_than_its_own_deadline() {
        let msg = mk_eval_capture_msg(
            &auth_token(),
            "return 1;".to_string(),
            Some(Duration::from_secs(120)),
        )
        .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(timeout_ms > 120_000);
    }

    #[test]
    fn a_system_handler_waits_for_the_longest_daemon_deadline() {
        let msg = mk_invoke_system_handler_msg(&Uuid::new_v4(), "http", vec![], None, None)
            .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(timeout_ms > MAX_CAPTURE_DEADLINE_MS as i32);
    }

    #[test]
    fn a_system_handler_waits_longer_than_its_own_deadline() {
        let msg = mk_invoke_system_handler_msg(
            &Uuid::new_v4(),
            "http",
            vec![],
            None,
            Some(Duration::from_secs(30)),
        )
        .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(timeout_ms > 30_000);
        assert!(timeout_ms < MAX_CAPTURE_DEADLINE_MS as i32);
    }

    #[test]
    fn the_welcome_message_waits_for_the_longest_deadline_a_daemon_may_use() {
        let msg = mk_invoke_welcome_message_msg();
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(timeout_ms > MAX_CAPTURE_DEADLINE_MS as i32);
    }

    #[test]
    fn a_capture_that_defers_to_the_daemon_waits_for_the_protocol_maximum() {
        let msg = mk_invoke_verb_capture_msg(
            &auth_token(),
            &moor_common::model::ObjectRef::Id(moor_var::Obj::mk_id(1)),
            &Symbol::mk("look"),
            vec![],
            None,
        )
        .expect("message");
        let timeout_ms = required_receive_timeout_ms(&msg).expect("a timeout");
        assert!(
            timeout_ms > MAX_CAPTURE_DEADLINE_MS as i32,
            "receive timeout {timeout_ms}ms must exceed the protocol maximum"
        );
    }

    #[test]
    fn an_ordinary_request_needs_no_special_timeout() {
        assert_eq!(
            required_receive_timeout_ms(&mk_list_objects_msg(&auth_token())),
            None
        );
    }

    fn socket_fixture(config: RpcConfig) -> (RpcClient, RequestReply) {
        let context = Arc::new(r0z::Context::new());
        let endpoint = format!("inproc://rpc-test-{}", Uuid::new_v4());
        let server = r0z_async::reply(&context).bind(&endpoint).unwrap();
        (RpcClient::new(context, endpoint, None, config), server)
    }

    #[tokio::test]
    async fn completed_calls_reuse_the_original_pool() {
        let (client, mut server) = socket_fixture(RpcConfig::default());
        let peer = async {
            for _ in 0..2 {
                assert_eq!(server.recv().await.unwrap().len(), 2);
                server.send(vec!["reply"].into()).await.unwrap();
            }
        };
        let calls = async {
            for _ in 0..2 {
                let reply = client
                    .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                    .await
                    .unwrap();
                assert_eq!(reply, b"reply");
                assert_eq!(client.pool_size().await, 1);
            }
            client.clear_pool().await;
            assert_eq!(client.pool_size().await, 0);
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(peer, calls);
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn receive_timeout_discards_socket_and_next_call_reconnects() {
        let (mut client, mut server) = socket_fixture(RpcConfig {
            receive_timeout_ms: 20,
            ..RpcConfig::default()
        });
        let (timed_out, wait_for_timeout) = tokio::sync::oneshot::channel();
        let peer = async {
            server.recv().await.unwrap();
            wait_for_timeout.await.unwrap();
            server.send(vec!["late reply"].into()).await.unwrap();
            server.recv().await.unwrap();
            server.send(vec!["fresh reply"].into()).await.unwrap();
        };
        let calls = async {
            let error = client
                .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                .await
                .unwrap_err();
            assert!(matches!(error, RpcError::CouldNotReceive(_)));
            assert_eq!(client.pool_size().await, 0);
            timed_out.send(()).unwrap();
            client.config.receive_timeout_ms = 1000;
            let reply = client
                .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                .await
                .unwrap();
            assert_eq!(reply, b"fresh reply");
            assert_eq!(client.pool_size().await, 1);
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(peer, calls);
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn cancelled_receive_does_not_return_socket_to_pool() {
        let (client, mut server) = socket_fixture(RpcConfig::default());
        {
            let call =
                client.make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()));
            tokio::pin!(call);
            tokio::select! {
                result = &mut call => panic!("call completed before reply: {result:?}"),
                request = server.recv() => { request.unwrap(); }
            }
        }
        assert_eq!(client.pool_size().await, 0);
        server.send(vec!["late reply"].into()).await.unwrap();
    }

    #[tokio::test]
    async fn send_timeout_discards_pending_socket() {
        let context = Arc::new(r0z::Context::new());
        // Hold the port without completing a ZeroMQ handshake, so send must wait.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let client = RpcClient::new(
            context,
            format!("tcp://{}", listener.local_addr().unwrap()),
            None,
            RpcConfig {
                connect_timeout_ms: 20,
                ..RpcConfig::default()
            },
        );
        let result = tokio::time::timeout(
            Duration::from_secs(2),
            client.make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token())),
        )
        .await
        .unwrap();
        assert!(matches!(result, Err(RpcError::CouldNotSend(_))));
        assert_eq!(client.pool_size().await, 0);
    }

    #[tokio::test]
    async fn unused_socket_is_reusable_but_dedicated_socket_is_not_pooled() {
        let (client, _server) = socket_fixture(RpcConfig::default());
        drop(SocketGuard::new(&client).await.unwrap());
        assert_eq!(client.pool_size().await, 1);
        let dedicated = SocketGuard::dedicated(&client, 120_000).await.unwrap();
        assert_eq!(
            dedicated
                .socket
                .as_ref()
                .unwrap()
                .get_socket()
                .get_rcvtimeo()
                .unwrap(),
            120_000
        );
        drop(dedicated);
        assert_eq!(client.pool_size().await, 1);
    }
}
