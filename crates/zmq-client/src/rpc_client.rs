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
use std::time::Duration;
use tokio::sync::{Semaphore, SemaphorePermit};
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
#[derive(Debug, Clone, clap_derive::Args, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct RpcConfig {
    /// Maximum idle ordinary-client sockets. Control sockets have a separate reservation.
    #[arg(long = "rpc-max-idle-sockets", default_value_t = 10)]
    pub max_pool_size: usize,
    /// Maximum sockets, including idle sockets, owned by this client and its clones.
    #[arg(long = "rpc-max-sockets", default_value_t = 64)]
    pub max_sockets: usize,
    /// Part of max_sockets reserved for host control and session pongs.
    #[arg(long = "rpc-control-sockets", default_value_t = 4)]
    pub control_reserved_sockets: usize,
    /// Maximum queued ordinary-client calls. Zero disables queueing.
    #[arg(long = "rpc-max-waiters", default_value_t = 128)]
    pub max_waiters: usize,
    /// Maximum queued control calls, independent of ordinary-client traffic.
    #[arg(long = "rpc-control-max-waiters", default_value_t = 256)]
    pub control_max_waiters: usize,
    /// Maximum time spent waiting for a socket slot.
    #[arg(long = "rpc-acquire-timeout-ms", default_value_t = 5000)]
    pub acquire_timeout_ms: u64,
    #[arg(long = "rpc-send-timeout-ms", default_value_t = DEFAULT_SOCK_CONNECT_TIMEOUT_MS, allow_negative_numbers = true)]
    pub send_timeout_ms: i32,
    #[arg(long = "rpc-receive-timeout-ms", default_value_t = DEFAULT_SOCK_RECEIVE_TIMEOUT_MS, allow_negative_numbers = true)]
    pub receive_timeout_ms: i32,
}

impl Default for RpcConfig {
    fn default() -> Self {
        Self {
            max_pool_size: 10,
            max_sockets: 64,
            control_reserved_sockets: 4,
            max_waiters: 128,
            control_max_waiters: 256,
            acquire_timeout_ms: 5000,
            send_timeout_ms: DEFAULT_SOCK_CONNECT_TIMEOUT_MS,
            receive_timeout_ms: DEFAULT_SOCK_RECEIVE_TIMEOUT_MS,
        }
    }
}

impl RpcConfig {
    /// Check limits before creating sockets or starting a host.
    pub fn validate(&self) -> Result<(), RpcError> {
        if self.control_reserved_sockets == 0 || self.max_sockets <= self.control_reserved_sockets {
            return Err(RpcError::Fatal(
                "RPC client and control capacity must both be positive".into(),
            ));
        }
        if [self.max_sockets, self.max_waiters, self.control_max_waiters]
            .into_iter()
            .any(|limit| limit > Semaphore::MAX_PERMITS)
        {
            return Err(RpcError::Fatal(
                "RPC limit exceeds semaphore capacity".into(),
            ));
        }
        if self.send_timeout_ms < -1 || self.receive_timeout_ms < -1 {
            return Err(RpcError::Fatal(
                "RPC socket timeouts must be -1 or nonnegative".into(),
            ));
        }
        Ok(())
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
#[derive(Clone)]
pub struct RpcClient {
    inner: Arc<RpcClientInner>,
}

struct RpcClientInner {
    zmq_context: Arc<r0z_async::Context>,
    rpc_addr: String,
    curve_keys: Option<CurveKeys>,
    config: RpcConfig,
    connection_pool: Mutex<[VecDeque<RequestReply>; 2]>,
    admission: [Admission; 2],
}

#[derive(Clone, Copy)]
enum CallClass {
    Client = 0,
    Control = 1,
}

struct Admission {
    slots: Semaphore,
    waiters: Semaphore,
}

impl Admission {
    fn new(slots: usize, waiters: usize) -> Self {
        Self {
            slots: Semaphore::new(slots),
            waiters: Semaphore::new(waiters),
        }
    }

    async fn acquire(&self, timeout_ms: u64) -> Result<SemaphorePermit<'_>, RpcError> {
        if let Ok(permit) = self.slots.try_acquire() {
            return Ok(permit);
        }
        let _waiter = self
            .waiters
            .try_acquire()
            .map_err(|_| RpcError::Recoverable("RPC admission queue is full".to_string()))?;
        tokio::time::timeout(Duration::from_millis(timeout_ms), self.slots.acquire())
            .await
            .map_err(|_| {
                RpcError::Recoverable(format!("RPC admission timed out after {timeout_ms}ms"))
            })?
            .map_err(|_| RpcError::Recoverable("RPC admission is closed".to_string()))
    }
}

/// Socket guard that ensures socket cleanup regardless of cancellation
struct SocketGuard<'a> {
    client: &'a RpcClient,
    socket: Option<RequestReply>,
    class: CallClass,
    // Return or discard the socket before releasing admission, including on cancellation.
    _permit: SemaphorePermit<'a>,
}

impl<'a> SocketGuard<'a> {
    /// Create a new socket guard, acquiring a socket from the pool
    async fn new(
        client: &'a RpcClient,
        class: CallClass,
        receive_timeout_ms: i32,
    ) -> Result<Self, RpcError> {
        let permit = client.inner.admission[class as usize]
            .acquire(client.inner.config.acquire_timeout_ms)
            .await?;
        let socket = client.acquire_socket(class)?;
        socket
            .get_socket()
            .set_rcvtimeo(receive_timeout_ms)
            .map_err(|e| RpcError::CouldNotReceive(e.to_string()))?;
        Ok(Self {
            client,
            socket: Some(socket),
            class,
            _permit: permit,
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
        if socket.state() == RequestReplyState::SendReady {
            self.client.return_socket(self.class, socket);
        }
    }
}

impl RpcClient {
    /// Create a new managed RPC client
    ///
    /// Clones share the pool and admission limits. A new client owns a separate pool.
    ///
    /// # Panics
    /// Panics if [`RpcConfig::validate`] rejects the configuration.
    pub fn new(
        zmq_context: Arc<r0z_async::Context>,
        rpc_addr: String,
        curve_keys: Option<CurveKeys>,
        config: RpcConfig,
    ) -> Self {
        config.validate().expect("invalid RPC configuration");
        let admission = [
            Admission::new(
                config.max_sockets - config.control_reserved_sockets,
                config.max_waiters,
            ),
            Admission::new(config.control_reserved_sockets, config.control_max_waiters),
        ];
        Self {
            inner: Arc::new(RpcClientInner {
                zmq_context,
                rpc_addr,
                curve_keys,
                config,
                connection_pool: Mutex::new(Default::default()),
                admission,
            }),
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
        let configured_timeout = self.inner.config.receive_timeout_ms;
        let receive_timeout = match required_receive_timeout_ms(&rpc_msg) {
            Some(timeout_ms) if configured_timeout >= 0 => timeout_ms.max(configured_timeout),
            _ => configured_timeout,
        };
        let class = if matches!(
            &rpc_msg.message,
            moor_rpc::HostClientToDaemonMessageUnion::ClientPong(_)
        ) {
            CallClass::Control
        } else {
            CallClass::Client
        };
        let mut socket_guard = SocketGuard::new(self, class, receive_timeout).await?;
        Self::perform_rpc_call(socket_guard.socket_mut(), client_id, rpc_msg).await
    }

    /// Make a host RPC call with cancellation safety and connection pooling
    pub async fn make_host_rpc_call(
        &self,
        host_id: Uuid,
        rpc_message: moor_rpc::HostToDaemonMessage,
    ) -> Result<Vec<u8>, RpcError> {
        // Use a guard pattern to ensure socket cleanup regardless of cancellation
        let mut socket_guard = SocketGuard::new(
            self,
            CallClass::Control,
            self.inner.config.receive_timeout_ms,
        )
        .await?;
        Self::perform_host_rpc_call(socket_guard.socket_mut(), host_id, rpc_message).await
    }

    /// Acquire a socket from the pool or create a new one
    // A class permit must be held before checkout. Always reuse an idle socket before creating
    // one, and return it before releasing the permit. This bounds idle plus borrowed sockets by
    // the class capacity. Separate idle lists keep ordinary calls out of the control reservation.
    fn acquire_socket(&self, class: CallClass) -> Result<RequestReply, RpcError> {
        let socket = self.inner.connection_pool.lock().unwrap()[class as usize].pop_front();
        if let Some(socket) = socket {
            debug!("Reusing socket from pool");
            return Ok(socket);
        }
        self.create_socket()
    }

    /// Return a socket to the pool, discarding if pool is full
    fn return_socket(&self, class: CallClass, socket: RequestReply) {
        let mut pool = self.inner.connection_pool.lock().unwrap();

        let limit = match class {
            CallClass::Client => self.inner.config.max_pool_size,
            CallClass::Control => self.inner.config.control_reserved_sockets,
        };
        if pool[class as usize].len() < limit {
            pool[class as usize].push_back(socket);
        } else {
            drop(socket);
        }
    }

    /// Allocate control sockets before accepting sessions, while the context has capacity.
    pub(crate) async fn reserve_control_sockets(&self) -> Result<(), RpcError> {
        let mut guards = Vec::with_capacity(self.inner.config.control_reserved_sockets);
        for _ in 0..self.inner.config.control_reserved_sockets {
            guards.push(
                SocketGuard::new(
                    self,
                    CallClass::Control,
                    self.inner.config.receive_timeout_ms,
                )
                .await?,
            );
        }
        drop(guards);
        Ok(())
    }

    /// Create a new socket with proper configuration
    fn create_socket(&self) -> Result<RequestReply, RpcError> {
        let mut socket_builder = r0z_async::request(&self.inner.zmq_context)
            .set_sndtimeo(self.inner.config.send_timeout_ms)
            // Fail immediately if no connection instead of queuing messages indefinitely
            .set_immediate(true)
            // Don't linger on close - drop queued messages immediately
            .set_linger(0);

        // Configure CURVE encryption if keys provided
        if let Some(curve_keys) = &self.inner.curve_keys {
            socket_builder = super::configure_curve_client(
                socket_builder,
                &curve_keys.client_secret,
                &curve_keys.client_public,
                &curve_keys.server_public,
            )
            .map_err(|e| RpcError::Fatal(format!("Failed to configure CURVE: {}", e)))?;
        }

        socket_builder
            .connect(&self.inner.rpc_addr)
            .map_err(|e| match e {
                // Native close is asynchronous, and non-RPC sockets also consume context capacity.
                // Leave retries to the caller; no request has been sent at this point.
                r0z_async::TmqError::Zmq(r0z::Error::EMFILE) => {
                    RpcError::Recoverable(format!("RPC socket capacity exhausted: {e}"))
                }
                _ => RpcError::Fatal(format!("Failed to connect to RPC server: {e}")),
            })
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
        let pool = self.inner.connection_pool.lock().unwrap();
        pool.iter().map(VecDeque::len).sum()
    }

    /// Clear the connection pool (useful for cleanup)
    pub async fn clear_pool(&self) {
        let mut pool = self.inner.connection_pool.lock().unwrap();
        for sockets in pool.iter_mut() {
            sockets.clear();
        }
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
    use futures_util::{SinkExt, StreamExt};
    use moor_runtime_api::{
        AuthToken, ClientToken, mk_command_capture_msg, mk_eval_capture_msg,
        mk_invoke_system_handler_msg, mk_invoke_verb_capture_msg, mk_invoke_verb_msg,
        mk_invoke_welcome_message_msg, mk_list_objects_msg,
    };
    use moor_var::Symbol;
    use planus::ReadAsRoot;
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
            Arc::get_mut(&mut client.inner)
                .unwrap()
                .config
                .receive_timeout_ms = 1000;
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
                send_timeout_ms: 20,
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
    async fn borrowed_sockets_reset_receive_timeout_and_reuse_the_same_socket() {
        let (client, _server) = socket_fixture(RpcConfig::default());
        let mut original_fd = None;
        for timeout in [5000, 120_000, 5000, -1, 5000] {
            let mut guard = SocketGuard::new(&client, CallClass::Client, timeout)
                .await
                .unwrap();
            let socket = guard.socket_mut().get_socket();
            assert_eq!(socket.get_rcvtimeo().unwrap(), timeout);
            let fd = socket.get_fd().unwrap();
            assert_eq!(*original_fd.get_or_insert(fd), fd);
            drop(guard);
            assert_eq!(client.pool_size().await, 1);
        }
    }

    fn small_config() -> RpcConfig {
        RpcConfig {
            max_sockets: 2,
            control_reserved_sockets: 1,
            max_waiters: 1,
            control_max_waiters: 1,
            acquire_timeout_ms: 30,
            ..RpcConfig::default()
        }
    }

    #[tokio::test]
    async fn clones_share_bounded_admission_and_cancelled_waiters_release_capacity() {
        let (client, _server) = socket_fixture(small_config());
        let clone = client.clone();
        let held = SocketGuard::new(&client, CallClass::Client, 5000)
            .await
            .unwrap();
        let admission = &client.inner.admission[CallClass::Client as usize];
        {
            let waiting = SocketGuard::new(&clone, CallClass::Client, 5000);
            tokio::pin!(waiting);
            assert!(futures_util::poll!(&mut waiting).is_pending());
            assert_eq!(admission.waiters.available_permits(), 0);
            assert!(matches!(
                SocketGuard::new(&client, CallClass::Client, 5000).await,
                Err(RpcError::Recoverable(message)) if message.contains("queue is full")
            ));
        }
        assert_eq!(admission.waiters.available_permits(), 1);
        assert!(matches!(
            SocketGuard::new(&clone, CallClass::Client, 5000).await,
            Err(RpcError::Recoverable(message)) if message.contains("timed out")
        ));
        assert_eq!(admission.waiters.available_permits(), 1);
        let waiting = SocketGuard::new(&clone, CallClass::Client, 5000);
        tokio::pin!(waiting);
        assert!(futures_util::poll!(&mut waiting).is_pending());
        let fd = held.socket.as_ref().unwrap().get_socket().get_fd().unwrap();
        drop(held);
        let mut admitted = waiting.await.unwrap();
        assert_eq!(admitted.socket_mut().get_socket().get_fd().unwrap(), fd);
        drop(admitted);
        assert_eq!(client.pool_size().await, 1);
        clone.clear_pool().await;
        assert_eq!(client.pool_size().await, 0);
    }

    #[tokio::test]
    async fn idle_and_borrowed_sockets_share_the_limit() {
        let (client, _server) = socket_fixture(RpcConfig {
            max_sockets: 4,
            control_reserved_sockets: 1,
            max_waiters: 0,
            control_max_waiters: 0,
            max_pool_size: 100,
            ..RpcConfig::default()
        });
        let mut originals = Vec::new();
        let mut guards = Vec::new();
        for class in [
            CallClass::Client,
            CallClass::Client,
            CallClass::Client,
            CallClass::Control,
        ] {
            let mut guard = SocketGuard::new(&client, class, 5000).await.unwrap();
            originals.push(guard.socket_mut().get_socket().get_fd().unwrap());
            guards.push(guard);
        }
        for class in [CallClass::Client, CallClass::Control] {
            assert!(matches!(
                SocketGuard::new(&client, class, 5000).await,
                Err(RpcError::Recoverable(_))
            ));
        }
        drop(guards);
        assert_eq!(client.pool_size().await, 4);
        for _ in 0..3 {
            let mut borrowed = Vec::new();
            for class in [
                CallClass::Client,
                CallClass::Client,
                CallClass::Client,
                CallClass::Control,
            ] {
                let mut guard = SocketGuard::new(&client, class, 5000).await.unwrap();
                assert!(originals.contains(&guard.socket_mut().get_socket().get_fd().unwrap()));
                borrowed.push(guard);
            }
            assert_eq!(client.pool_size().await, 0);
            drop(borrowed);
            assert_eq!(client.pool_size().await, 4);
        }
    }

    #[tokio::test]
    async fn host_services_share_clients_but_keep_distinct_endpoints_and_credentials_separate() {
        use moor_runtime_api::api::HostServices;
        let context = r0z::Context::new();
        let services = crate::ZmqHostServices::new(
            context.clone(),
            "inproc://shared".into(),
            String::new(),
            None,
        );
        let clone = services.clone();
        assert!(Arc::ptr_eq(
            &services.runtime_client(),
            &clone.runtime_client()
        ));
        let client = services.rpc_client();
        let other = clone.rpc_client();
        assert!(Arc::ptr_eq(&client.inner, &other.inner));
        let held = SocketGuard::new(&client, CallClass::Client, 5000)
            .await
            .unwrap();
        drop(held);
        assert_eq!(other.pool_size().await, 1);
        for (address, keys) in [
            ("inproc://different", None),
            (
                "inproc://shared",
                Some(("secret".into(), "public".into(), "server".into())),
            ),
        ] {
            let separate =
                crate::ZmqHostServices::new(context.clone(), address.into(), String::new(), keys);
            assert!(!Arc::ptr_eq(&client.inner, &separate.rpc_client().inner));
            assert_eq!(separate.rpc_client().pool_size().await, 0);
        }
    }

    #[tokio::test]
    async fn long_and_ordinary_calls_reuse_a_socket_across_clones() {
        let (client, mut server) = socket_fixture(RpcConfig::default());
        let clone = client.clone();
        let peer = async {
            for _ in 0..3 {
                server.recv().await.unwrap();
                server.send(vec!["reply"].into()).await.unwrap();
            }
        };
        let calls = async {
            let mut original_fd = None;
            for long in [false, true, false] {
                let msg = if long {
                    mk_invoke_system_handler_msg(
                        &Uuid::new_v4(),
                        "http",
                        vec![],
                        None,
                        Some(Duration::from_secs(30)),
                    )
                    .unwrap()
                } else {
                    mk_list_objects_msg(&auth_token())
                };
                let active = if long { &clone } else { &client };
                assert_eq!(
                    active
                        .make_client_rpc_call(Uuid::new_v4(), msg)
                        .await
                        .unwrap(),
                    b"reply"
                );
                let pool = client.inner.connection_pool.lock().unwrap();
                assert_eq!(pool[0].len(), 1);
                let socket = pool[0][0].get_socket();
                let fd = socket.get_fd().unwrap();
                assert_eq!(*original_fd.get_or_insert(fd), fd);
                assert_eq!(
                    socket.get_rcvtimeo().unwrap(),
                    if long { 45_000 } else { 5000 }
                );
            }
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(peer, calls);
        })
        .await
        .unwrap();
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_calls_reuse_bounded_sockets_without_mixing_replies() {
        use std::collections::HashSet;
        let context = Arc::new(r0z::Context::new());
        let endpoint = format!("inproc://rpc-concurrent-{}", Uuid::new_v4());
        let mut server = r0z_async::router(&context).bind(&endpoint).unwrap();
        let client = RpcClient::new(
            context,
            endpoint,
            None,
            RpcConfig {
                max_sockets: 4,
                control_reserved_sockets: 1,
                max_waiters: 32,
                acquire_timeout_ms: 2000,
                ..RpcConfig::default()
            },
        );
        tokio::time::timeout(Duration::from_secs(5), async {
            let mut tasks = tokio::task::JoinSet::new();
            for _ in 0..32 {
                let client = client.clone();
                tasks.spawn(async move {
                    let id = Uuid::new_v4();
                    let reply = client
                        .make_client_rpc_call(id, mk_list_objects_msg(&auth_token()))
                        .await
                        .unwrap();
                    let message = moor_rpc::MessageTypeRef::read_as_root(&reply).unwrap();
                    let moor_rpc::MessageTypeUnionRef::HostClientToDaemonMsg(message) =
                        message.message().unwrap()
                    else {
                        panic!("expected client discriminator");
                    };
                    assert_eq!(message.client_data().unwrap(), id.as_bytes());
                });
            }
            // Fill every client slot before replying, so the other calls must queue.
            let mut pending = VecDeque::new();
            for _ in 0..3 {
                pending.push_back(server.next().await.unwrap().unwrap());
            }
            let mut identities = HashSet::new();
            for _ in 0..32 {
                let request = match pending.pop_front() {
                    Some(request) => request,
                    None => server.next().await.unwrap().unwrap(),
                };
                identities.insert(request[0].to_vec());
                server
                    .send(Multipart::from(vec![
                        request[0].to_vec(),
                        vec![],
                        request[2].to_vec(),
                    ]))
                    .await
                    .unwrap();
            }
            while let Some(result) = tasks.join_next().await {
                result.unwrap();
            }
            assert_eq!(identities.len(), 3);
            assert_eq!(client.pool_size().await, 3);
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn host_control_completes_while_client_calls_and_queue_are_full() {
        use moor_runtime_api::{mk_host_pong_msg, mk_register_host_msg};
        let context = Arc::new(r0z::Context::new());
        let endpoint = format!("inproc://rpc-control-{}", Uuid::new_v4());
        let mut server = r0z_async::router(&context).bind(&endpoint).unwrap();
        let client = RpcClient::new(
            context,
            endpoint,
            None,
            RpcConfig {
                acquire_timeout_ms: 1000,
                ..small_config()
            },
        );
        tokio::time::timeout(Duration::from_secs(2), async {
            let long_msg =
                mk_invoke_system_handler_msg(&Uuid::new_v4(), "http", vec![], None, None).unwrap();
            {
                let long = client.make_client_rpc_call(Uuid::new_v4(), long_msg);
                tokio::pin!(long);
                tokio::select! {
                    result = &mut long => panic!("long call completed: {result:?}"),
                    request = server.next() => { request.unwrap().unwrap(); }
                }
                let queued =
                    client.make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()));
                tokio::pin!(queued);
                assert!(futures_util::poll!(&mut queued).is_pending());
                assert!(matches!(
                    client
                        .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                        .await,
                    Err(RpcError::Recoverable(_))
                ));
                let host_id = Uuid::new_v4();
                for msg in [
                    mk_register_host_msg(host_id, 0, &[], vec![]),
                    mk_host_pong_msg(host_id, 0, &[], vec![]),
                ] {
                    let control = client.make_host_rpc_call(host_id, msg);
                    let peer = async {
                        let request = server.next().await.unwrap().unwrap();
                        server
                            .send(Multipart::from(vec![
                                request[0].to_vec(),
                                vec![],
                                b"ack".to_vec(),
                            ]))
                            .await
                            .unwrap();
                    };
                    let (result, ()) = tokio::join!(control, peer);
                    assert_eq!(result.unwrap(), b"ack");
                }
            }
            // Cancelling both the queued and sent call releases their admission. The host socket
            // remains pooled; the unanswered client socket must be discarded.
            assert_eq!(client.pool_size().await, 1);
            assert_eq!(client.inner.admission[0].slots.available_permits(), 1);
            assert_eq!(client.inner.admission[0].waiters.available_permits(), 1);
            let next =
                client.make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()));
            let peer = async {
                let request = server.next().await.unwrap().unwrap();
                server
                    .send(Multipart::from(vec![
                        request[0].to_vec(),
                        vec![],
                        b"fresh".to_vec(),
                    ]))
                    .await
                    .unwrap();
            };
            let (result, ()) = tokio::join!(next, peer);
            assert_eq!(result.unwrap(), b"fresh");
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn socket_exhaustion_is_recoverable_and_does_not_leak_admission() {
        let context = Arc::new(r0z::Context::new());
        context.set_max_sockets(4).unwrap();
        let mut occupied = Vec::new();
        loop {
            match context.socket(r0z::PAIR) {
                Ok(socket) => {
                    socket.set_linger(0).unwrap();
                    occupied.push(socket);
                }
                Err(r0z::Error::EMFILE) => break,
                Err(error) => panic!("unexpected socket error: {error}"),
            }
        }
        let client = RpcClient::new(context, "inproc://exhaustion".into(), None, small_config());
        assert!(matches!(
            client
                .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                .await,
            Err(RpcError::Recoverable(_))
        ));
        assert_eq!(client.inner.admission[0].slots.available_permits(), 1);
        drop(occupied);
        // libzmq reclaims closed sockets asynchronously. Only retry creation, never an exchange.
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                match SocketGuard::new(&client, CallClass::Client, 5000).await {
                    Ok(guard) => {
                        drop(guard);
                        break;
                    }
                    Err(RpcError::Recoverable(_)) => {
                        tokio::time::sleep(Duration::from_millis(1)).await
                    }
                    Err(error) => panic!("unexpected recovery error: {error}"),
                }
            }
        })
        .await
        .unwrap();
        assert_eq!(client.pool_size().await, 1);
    }

    #[tokio::test]
    async fn configuration_errors_remain_fatal_and_release_admission() {
        let client = RpcClient::new(
            Arc::new(r0z::Context::new()),
            "invalid://address".into(),
            None,
            small_config(),
        );
        assert!(matches!(
            SocketGuard::new(&client, CallClass::Client, 5000).await,
            Err(RpcError::Fatal(_))
        ));
        assert_eq!(client.inner.admission[0].slots.available_permits(), 1);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn session_pongs_use_reserved_capacity_when_ordinary_admission_is_full() {
        use moor_runtime_api::mk_client_pong_msg;
        let context = Arc::new(r0z::Context::new());
        let endpoint = format!("inproc://rpc-session-pongs-{}", Uuid::new_v4());
        let mut server = r0z_async::router(&context).bind(&endpoint).unwrap();
        let client = RpcClient::new_with_defaults(context, endpoint, None);
        client.reserve_control_sockets().await.unwrap();
        tokio::time::timeout(Duration::from_secs(5), async {
            let mut held = Vec::new();
            for _ in 0..60 {
                held.push(
                    SocketGuard::new(&client, CallClass::Client, 5000)
                        .await
                        .unwrap(),
                );
            }
            let mut waiting = Vec::new();
            for _ in 0..128 {
                let mut call = Box::pin(
                    client.make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token())),
                );
                assert!(futures_util::poll!(&mut call).is_pending());
                waiting.push(call);
            }
            assert!(matches!(
                client
                    .make_client_rpc_call(Uuid::new_v4(), mk_list_objects_msg(&auth_token()))
                    .await,
                Err(RpcError::Recoverable(_))
            ));
            let mut pongs = tokio::task::JoinSet::new();
            for _ in 0..160 {
                let clone = client.clone();
                pongs.spawn(async move {
                    clone
                        .make_client_rpc_call(
                            Uuid::new_v4(),
                            mk_client_pong_msg(
                                &ClientToken("client".into()),
                                0,
                                &moor_var::SYSTEM_OBJECT,
                                "test".into(),
                            ),
                        )
                        .await
                        .unwrap()
                });
            }
            for _ in 0..160 {
                let request = server.next().await.unwrap().unwrap();
                server
                    .send(Multipart::from(vec![
                        request[0].to_vec(),
                        vec![],
                        b"pong".to_vec(),
                    ]))
                    .await
                    .unwrap();
            }
            while let Some(pong) = pongs.join_next().await {
                assert_eq!(pong.unwrap(), b"pong");
            }
            assert_eq!(client.inner.admission[0].slots.available_permits(), 0);
            assert_eq!(client.inner.admission[0].waiters.available_permits(), 0);
            assert_eq!(client.pool_size().await, 4);
            drop(waiting);
            drop(held);
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn control_sockets_survive_full_client_idle_pool_and_native_exhaustion() {
        use moor_runtime_api::{mk_client_pong_msg, mk_host_pong_msg};
        let context = Arc::new(r0z::Context::new());
        context.set_max_sockets(5).unwrap();
        let endpoint = format!("inproc://rpc-retained-control-{}", Uuid::new_v4());
        let mut server = r0z_async::reply(&context).bind(&endpoint).unwrap();
        let client = RpcClient::new(
            context.clone(),
            endpoint,
            None,
            RpcConfig {
                max_pool_size: 1,
                ..small_config()
            },
        );
        client.reserve_control_sockets().await.unwrap();
        let control = SocketGuard::new(&client, CallClass::Control, 5000)
            .await
            .unwrap();
        // Return the ordinary socket first, filling its idle allowance.
        drop(
            SocketGuard::new(&client, CallClass::Client, 5000)
                .await
                .unwrap(),
        );
        drop(control);
        assert_eq!(client.pool_size().await, 2);
        let mut occupied = Vec::new();
        loop {
            match context.socket(r0z::PAIR) {
                Ok(socket) => {
                    socket.set_linger(0).unwrap();
                    occupied.push(socket);
                }
                Err(r0z::Error::EMFILE) => break,
                Err(error) => panic!("unexpected exhaustion error: {error}"),
            }
        }
        let peer = async {
            for _ in 0..2 {
                server.recv().await.unwrap();
                server.send(vec!["ack"].into()).await.unwrap();
            }
        };
        let calls = async {
            let id = Uuid::new_v4();
            assert_eq!(
                client
                    .make_host_rpc_call(id, mk_host_pong_msg(id, 0, &[], vec![]))
                    .await
                    .unwrap(),
                b"ack"
            );
            assert_eq!(
                client
                    .make_client_rpc_call(
                        id,
                        mk_client_pong_msg(
                            &ClientToken("client".into()),
                            0,
                            &moor_var::SYSTEM_OBJECT,
                            "test".into(),
                        )
                    )
                    .await
                    .unwrap(),
                b"ack"
            );
        };
        tokio::time::timeout(Duration::from_secs(2), async {
            tokio::join!(peer, calls);
        })
        .await
        .unwrap();
        assert_eq!(client.pool_size().await, 2);
    }
}
