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

//! High-level async client for invoking verbs on a moor daemon.
//!
//! `TaskClient` wraps a [`HostServices`] implementation to provide a single
//! `invoke_verb(...).await` that submits a verb invocation and awaits the
//! task completion event. Designed for hundreds of concurrent in-flight
//! verb calls from a game host or similar.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::{
    AuthToken, ClientToken, RpcError,
    api::{
        ClientEvent, ClientEventSubscription, ClientReply, ClientRequest, ConnectType,
        HostServices, RuntimeClient,
    },
};
use moor_common::model::ObjectRef;
use moor_common::tasks::{NarrativeEvent, SchedulerError};
use moor_var::{Obj, Symbol, Var};
use tokio::sync::{broadcast, oneshot};
use tracing::{debug, error, trace, warn};
use uuid::Uuid;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);

/// Result of a completed task.
#[derive(Debug)]
pub enum TaskResult {
    /// Task completed successfully with a return value.
    Success(Var),
    /// Task failed with a scheduler error.
    Error(SchedulerError),
    /// Task suspended (went to background). The task_id is included for reference.
    Suspended(u64),
}

/// Session-level events from the daemon that are not correlated to a specific task.
///
/// These arrive on the PubSub channel alongside task completion events but are
/// player/session-scoped rather than task-scoped.
#[derive(Debug, Clone)]
pub enum SessionEvent {
    /// Narrative output from `notify()`, `tell()`, etc.
    Narrative(Obj, NarrativeEvent),
    /// System message (server announcements, etc.)
    SystemMessage(Obj, String),
    /// The daemon is requesting input (MOO `read()` builtin).
    RequestInput(Uuid),
    /// Server is disconnecting this session.
    Disconnect,
    /// Player identity changed (e.g. after login verb).
    PlayerSwitched { player: Obj, auth_token: AuthToken },
    /// MOO code set a connection option.
    SetConnectionOption {
        connection_obj: Obj,
        option: Symbol,
        value: Var,
    },
    /// Credentials were refreshed (e.g. after reattach).
    CredentialsUpdated {
        client_id: Uuid,
        client_token: ClientToken,
    },
}

const SESSION_EVENT_CHANNEL_CAPACITY: usize = 256;

/// Errors from TaskClient operations (transport/protocol level, not task-level).
#[derive(Debug, thiserror::Error)]
pub enum TaskClientError {
    #[error("RPC error: {0}")]
    Rpc(#[from] RpcError),
    #[error("failed to encode verb arguments")]
    ArgEncoding,
    #[error("unexpected reply from daemon: {0}")]
    UnexpectedReply(String),
    #[error("task {0} timed out after {1:?}")]
    Timeout(u64, Duration),
    #[error("event dispatcher stopped (connection lost)")]
    DispatcherGone,
    #[error("attach failed: {0}")]
    AttachFailed(String),
}

type WaiterMap = Mutex<HashMap<u64, oneshot::Sender<TaskResult>>>;

/// High-level async client for calling verbs on a moor daemon.
///
/// Manages a persistent PubSub subscription and correlates task completion
/// events back to waiting callers via a shared waiter map.
///
/// # Example
/// ```no_run
/// use moor_runtime_api::task_client::TaskClient;
///
/// # async fn example(client: &TaskClient) {
/// use moor_common::model::ObjectRef;
/// use moor_var::{Obj, Symbol};
///
/// let result = client.invoke_verb(
///     &ObjectRef::Id(Obj::mk_id(42)),
///     &Symbol::mk("look"),
///     vec![],
/// ).await;
/// # }
/// ```
pub struct TaskClient {
    rpc: Arc<dyn RuntimeClient>,
    client_id: Uuid,
    client_token: ClientToken,
    auth_token: AuthToken,
    waiters: Arc<WaiterMap>,
    session_events_tx: broadcast::Sender<SessionEvent>,
    dispatcher_handle: tokio::task::JoinHandle<()>,
    default_timeout: Duration,
}

/// Configuration for creating a TaskClient session.
pub struct TaskClientConfig {
    /// Auth token for the player session.
    pub auth_token: AuthToken,
    /// Handler object for this connection (e.g. `#0`).
    pub handler_object: Obj,
    /// Peer address string for connection metadata.
    pub peer_addr: String,
    /// Local port for connection metadata.
    pub local_port: u16,
    /// Default timeout for verb invocations.
    pub default_timeout: Duration,
}

impl Default for TaskClientConfig {
    fn default() -> Self {
        Self {
            auth_token: AuthToken(String::new()),
            handler_object: Obj::mk_id(0),
            peer_addr: "localhost".to_string(),
            local_port: 0,
            default_timeout: DEFAULT_TIMEOUT,
        }
    }
}

impl TaskClient {
    /// Create a new TaskClient through a host services implementation.
    ///
    /// This performs the full attach flow: creates a client id, sends an
    /// attach request, sets up the event subscription, and spawns the
    /// background event dispatcher.
    pub async fn connect_with_services(
        config: TaskClientConfig,
        services: Arc<dyn HostServices>,
    ) -> Result<Self, TaskClientError> {
        let rpc = services.runtime_client();
        let client_id = Uuid::new_v4();

        let reply = rpc
            .client_call(
                client_id,
                ClientRequest::Attach {
                    auth_token: config.auth_token.clone(),
                    connect_type: ConnectType::NoConnect,
                    handler_object: config.handler_object,
                    peer_addr: config.peer_addr,
                    local_port: config.local_port,
                    remote_port: 0,
                    acceptable_content_types: None,
                },
            )
            .await
            .map_err(TaskClientError::Rpc)?;

        let ClientReply::AttachResult {
            success: true,
            client_token: Some(client_token),
            ..
        } = reply
        else {
            return Err(TaskClientError::AttachFailed(format!(
                "unexpected attach reply: {reply:?}"
            )));
        };

        let (subscribe, _) = services
            .client_subscriptions(client_id)
            .map_err(TaskClientError::Rpc)?;

        let waiters = Arc::new(Mutex::new(HashMap::new()));
        let (session_events_tx, _) = broadcast::channel(SESSION_EVENT_CHANNEL_CAPACITY);

        let dispatcher_handle = tokio::spawn(dispatcher_loop(
            subscribe,
            waiters.clone(),
            session_events_tx.clone(),
        ));

        debug!("TaskClient connected: client_id={}", client_id);

        Ok(Self {
            rpc,
            client_id,
            client_token,
            auth_token: config.auth_token,
            waiters,
            session_events_tx,
            dispatcher_handle,
            default_timeout: config.default_timeout,
        })
    }

    /// Create a TaskClient from an already-attached session.
    pub fn from_attached_session(
        rpc: Arc<dyn RuntimeClient>,
        subscription: Box<dyn ClientEventSubscription>,
        client_id: Uuid,
        client_token: ClientToken,
        auth_token: AuthToken,
        default_timeout: Duration,
    ) -> Self {
        let waiters = Arc::new(WaiterMap::new(HashMap::new()));
        let (session_events_tx, _) = broadcast::channel(SESSION_EVENT_CHANNEL_CAPACITY);

        let dispatcher_handle = tokio::spawn(dispatcher_loop(
            subscription,
            waiters.clone(),
            session_events_tx.clone(),
        ));

        Self {
            rpc,
            client_id,
            client_token,
            auth_token,
            waiters,
            session_events_tx,
            dispatcher_handle,
            default_timeout,
        }
    }

    /// Invoke a verb on an object and await the result.
    ///
    /// Uses the default timeout configured at construction time.
    pub async fn invoke_verb(
        &self,
        object: &ObjectRef,
        verb_name: &Symbol,
        args: Vec<&Var>,
    ) -> Result<TaskResult, TaskClientError> {
        self.invoke_verb_with_timeout(object, verb_name, args, self.default_timeout)
            .await
    }

    /// Invoke a verb on an object and await the result with a custom timeout.
    pub async fn invoke_verb_with_timeout(
        &self,
        object: &ObjectRef,
        verb_name: &Symbol,
        args: Vec<&Var>,
        timeout_duration: Duration,
    ) -> Result<TaskResult, TaskClientError> {
        let args = args.into_iter().cloned().collect();
        let reply = self
            .rpc
            .client_call(
                self.client_id,
                ClientRequest::InvokeVerb {
                    client_token: self.client_token.clone(),
                    auth_token: self.auth_token.clone(),
                    object: object.clone(),
                    verb: *verb_name,
                    args,
                },
            )
            .await
            .map_err(TaskClientError::Rpc)?;

        let ClientReply::TaskSubmitted { task_id } = reply else {
            return Err(TaskClientError::UnexpectedReply(format!("{reply:?}")));
        };

        trace!("Task {} submitted for {}:{}", task_id, object, verb_name);

        // Register waiter. This happens after we get the task_id but before the
        // task could complete — the daemon returns TaskSubmitted before starting
        // execution, and the PubSub event requires a network round-trip.
        let (tx, rx) = oneshot::channel();
        self.waiters.lock().unwrap().insert(task_id, tx);

        // Await result with timeout
        match tokio::time::timeout(timeout_duration, rx).await {
            Ok(Ok(result)) => Ok(result),
            Ok(Err(_)) => {
                // Sender was dropped — dispatcher died
                Err(TaskClientError::DispatcherGone)
            }
            Err(_) => {
                // Timeout — clean up the waiter to prevent leak
                self.waiters.lock().unwrap().remove(&task_id);
                Err(TaskClientError::Timeout(task_id, timeout_duration))
            }
        }
    }

    /// Get the client_id for this session.
    pub fn client_id(&self) -> Uuid {
        self.client_id
    }

    /// Subscribe to session-level events (narrative, system messages, input
    /// requests, disconnect, etc.).
    ///
    /// Returns a broadcast receiver. Multiple subscribers are supported.
    /// Events that arrive before any subscriber is created are dropped.
    pub fn session_events(&self) -> broadcast::Receiver<SessionEvent> {
        self.session_events_tx.subscribe()
    }

    /// Get the number of currently in-flight (waiting) tasks.
    pub fn pending_tasks(&self) -> usize {
        self.waiters.lock().unwrap().len()
    }

    /// Gracefully shut down the client, detaching from the daemon.
    pub async fn shutdown(self) {
        if let Err(e) = self
            .rpc
            .client_call(
                self.client_id,
                ClientRequest::Detach {
                    client_token: self.client_token.clone(),
                    disconnected: true,
                },
            )
            .await
        {
            warn!("Failed to send detach on shutdown: {}", e);
        }

        // Stop the dispatcher
        self.dispatcher_handle.abort();
        debug!("TaskClient shut down: client_id={}", self.client_id);
    }
}

impl Drop for TaskClient {
    fn drop(&mut self) {
        // Safety net: abort dispatcher if shutdown() wasn't called.
        // The detach message won't be sent (requires async), but at least
        // we stop the background task.
        self.dispatcher_handle.abort();
    }
}

// ---------------------------------------------------------------------------
// Background event dispatcher
// ---------------------------------------------------------------------------

async fn dispatcher_loop(
    mut subscribe: Box<dyn ClientEventSubscription>,
    waiters: Arc<WaiterMap>,
    session_tx: broadcast::Sender<SessionEvent>,
) {
    loop {
        let event_msg = match subscribe.recv_client_event().await {
            Ok(msg) => msg,
            Err(e) => {
                error!(
                    "TaskClient event subscription error, dispatcher exiting: {}",
                    e
                );
                break;
            }
        };

        match event_msg.event {
            // ----- Task-correlated events → resolve waiters -----
            ClientEvent::TaskSuccess { task_id, result } => {
                let sender = waiters.lock().unwrap().remove(&task_id);
                if let Some(sender) = sender {
                    let _ = sender.send(TaskResult::Success(result));
                }
            }
            ClientEvent::TaskError { task_id, error } => {
                let sender = waiters.lock().unwrap().remove(&task_id);
                if let Some(sender) = sender {
                    let _ = sender.send(TaskResult::Error(error));
                }
            }
            ClientEvent::TaskSuspended { task_id } => {
                let sender = waiters.lock().unwrap().remove(&task_id);
                if let Some(sender) = sender {
                    let _ = sender.send(TaskResult::Suspended(task_id));
                }
            }

            // ----- Session-level events → broadcast channel -----
            ClientEvent::Narrative { player, event } => {
                let _ = session_tx.send(SessionEvent::Narrative(player, event));
            }
            ClientEvent::SystemMessage { player, message } => {
                let _ = session_tx.send(SessionEvent::SystemMessage(player, message));
            }
            ClientEvent::RequestInput { request_id, .. } => {
                let _ = session_tx.send(SessionEvent::RequestInput(request_id));
            }
            ClientEvent::Disconnect => {
                let _ = session_tx.send(SessionEvent::Disconnect);
            }
            ClientEvent::PlayerSwitched {
                new_player,
                new_auth_token,
            } => {
                let _ = session_tx.send(SessionEvent::PlayerSwitched {
                    player: new_player,
                    auth_token: new_auth_token,
                });
            }
            ClientEvent::SetConnectionOption {
                connection_obj,
                option_name,
                value,
            } => {
                let _ = session_tx.send(SessionEvent::SetConnectionOption {
                    connection_obj,
                    option: option_name,
                    value,
                });
            }
            ClientEvent::CredentialsUpdated {
                client_id,
                client_token,
            } => {
                let _ = session_tx.send(SessionEvent::CredentialsUpdated {
                    client_id,
                    client_token,
                });
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extract task_id from a TaskSubmitted RPC reply.
#[cfg(test)]
fn extract_task_id(reply_bytes: &[u8]) -> Result<u64, TaskClientError> {
    let reply = crate::read_reply_result(reply_bytes)
        .map_err(|e| TaskClientError::UnexpectedReply(format!("bad flatbuffer: {e}")))?;

    let result_union = reply
        .result()
        .map_err(|e| TaskClientError::UnexpectedReply(format!("missing result: {e}")))?;

    let moor_schema::rpc::ReplyResultUnionRef::ClientSuccess(client_success) = result_union else {
        return Err(TaskClientError::UnexpectedReply(
            "expected ClientSuccess".into(),
        ));
    };

    let daemon_reply = client_success
        .reply()
        .map_err(|e| TaskClientError::UnexpectedReply(format!("missing reply: {e}")))?;

    let reply_union = daemon_reply
        .reply()
        .map_err(|e| TaskClientError::UnexpectedReply(format!("missing reply union: {e}")))?;

    let moor_schema::rpc::DaemonToClientReplyUnionRef::TaskSubmitted(task_submitted) = reply_union
    else {
        return Err(TaskClientError::UnexpectedReply(
            "expected TaskSubmitted".into(),
        ));
    };

    task_submitted
        .task_id()
        .map_err(|e| TaskClientError::UnexpectedReply(format!("missing task_id: {e}")))
}

/// Decode the attach reply, extracting the client token.
#[cfg(test)]
fn decode_attach_reply(reply_bytes: &[u8]) -> Result<ClientToken, TaskClientError> {
    let reply = crate::read_reply_result(reply_bytes)
        .map_err(|e| TaskClientError::AttachFailed(format!("bad flatbuffer: {e}")))?;

    let result_union = reply
        .result()
        .map_err(|e| TaskClientError::AttachFailed(format!("missing result: {e}")))?;

    let moor_schema::rpc::ReplyResultUnionRef::ClientSuccess(client_success) = result_union else {
        return Err(TaskClientError::AttachFailed(
            "expected ClientSuccess".into(),
        ));
    };

    let daemon_reply = client_success
        .reply()
        .map_err(|e| TaskClientError::AttachFailed(format!("missing reply: {e}")))?;

    let reply_union = daemon_reply
        .reply()
        .map_err(|e| TaskClientError::AttachFailed(format!("missing reply union: {e}")))?;

    let moor_schema::rpc::DaemonToClientReplyUnionRef::AttachResult(attach_result) = reply_union
    else {
        return Err(TaskClientError::AttachFailed(
            "expected AttachResult".into(),
        ));
    };

    let success = attach_result
        .success()
        .map_err(|e| TaskClientError::AttachFailed(format!("missing success flag: {e}")))?;
    if !success {
        return Err(TaskClientError::AttachFailed(
            "daemon rejected attach".into(),
        ));
    }

    let client_token_ref = attach_result
        .client_token()
        .ok()
        .flatten()
        .ok_or_else(|| TaskClientError::AttachFailed("missing client_token".into()))?;

    let token_str = client_token_ref
        .token()
        .map_err(|e| TaskClientError::AttachFailed(format!("missing token string: {e}")))?;

    Ok(ClientToken(token_str.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_schema::rpc as moor_rpc;
    use moor_var::v_int;

    /// Helper: build a ReplyResult containing a ClientSuccess with a DaemonToClientReply.
    fn build_reply_result(reply: moor_rpc::DaemonToClientReply) -> Vec<u8> {
        let reply_result = moor_rpc::ReplyResult {
            result: moor_rpc::ReplyResultUnion::ClientSuccess(Box::new(moor_rpc::ClientSuccess {
                reply: Box::new(reply),
            })),
        };
        let mut builder = planus::Builder::new();
        builder.finish(&reply_result, None).to_vec()
    }

    // -----------------------------------------------------------------------
    // Unit tests for extract_task_id
    // -----------------------------------------------------------------------

    #[test]
    fn test_extract_task_id_success() {
        let reply = moor_rpc::DaemonToClientReply {
            reply: moor_rpc::DaemonToClientReplyUnion::TaskSubmitted(Box::new(
                moor_rpc::TaskSubmitted { task_id: 42 },
            )),
        };
        let bytes = build_reply_result(reply);
        let task_id = extract_task_id(&bytes).unwrap();
        assert_eq!(task_id, 42);
    }

    #[test]
    fn test_extract_task_id_wrong_reply_type() {
        let reply = moor_rpc::DaemonToClientReply {
            reply: moor_rpc::DaemonToClientReplyUnion::Disconnected(Box::new(
                moor_rpc::Disconnected {},
            )),
        };
        let bytes = build_reply_result(reply);
        let err = extract_task_id(&bytes).unwrap_err();
        assert!(matches!(err, TaskClientError::UnexpectedReply(_)));
    }

    #[test]
    fn test_extract_task_id_garbage_bytes() {
        let err = extract_task_id(b"not a flatbuffer").unwrap_err();
        assert!(matches!(err, TaskClientError::UnexpectedReply(_)));
    }

    // -----------------------------------------------------------------------
    // Unit tests for decode_attach_reply
    // -----------------------------------------------------------------------

    #[test]
    fn test_decode_attach_reply_success() {
        let reply = moor_rpc::DaemonToClientReply {
            reply: moor_rpc::DaemonToClientReplyUnion::AttachResult(Box::new(
                moor_rpc::AttachResult {
                    success: true,
                    client_token: Some(Box::new(moor_rpc::ClientToken {
                        token: "test-token-123".to_string(),
                    })),
                    player: None,
                    player_flags: 0,
                },
            )),
        };
        let bytes = build_reply_result(reply);
        let token = decode_attach_reply(&bytes).unwrap();
        assert_eq!(token.0, "test-token-123");
    }

    #[test]
    fn test_decode_attach_reply_rejected() {
        let reply = moor_rpc::DaemonToClientReply {
            reply: moor_rpc::DaemonToClientReplyUnion::AttachResult(Box::new(
                moor_rpc::AttachResult {
                    success: false,
                    client_token: None,
                    player: None,
                    player_flags: 0,
                },
            )),
        };
        let bytes = build_reply_result(reply);
        let err = decode_attach_reply(&bytes).unwrap_err();
        assert!(matches!(err, TaskClientError::AttachFailed(_)));
    }

    #[test]
    fn test_decode_attach_reply_wrong_type() {
        let reply = moor_rpc::DaemonToClientReply {
            reply: moor_rpc::DaemonToClientReplyUnion::TaskSubmitted(Box::new(
                moor_rpc::TaskSubmitted { task_id: 1 },
            )),
        };
        let bytes = build_reply_result(reply);
        let err = decode_attach_reply(&bytes).unwrap_err();
        assert!(matches!(err, TaskClientError::AttachFailed(_)));
    }

    struct TestSubscription {
        rx: tokio::sync::mpsc::Receiver<crate::api::ClientEventMessage>,
    }

    #[async_trait::async_trait]
    impl ClientEventSubscription for TestSubscription {
        async fn recv_client_event(&mut self) -> Result<crate::api::ClientEventMessage, RpcError> {
            self.rx
                .recv()
                .await
                .ok_or_else(|| RpcError::CouldNotReceive("test subscription closed".to_string()))
        }
    }

    fn test_subscription() -> (
        tokio::sync::mpsc::Sender<crate::api::ClientEventMessage>,
        Box<dyn ClientEventSubscription>,
    ) {
        let (tx, rx) = tokio::sync::mpsc::channel(16);
        (tx, Box::new(TestSubscription { rx }))
    }

    async fn send_test_event(
        tx: &tokio::sync::mpsc::Sender<crate::api::ClientEventMessage>,
        event: ClientEvent,
    ) {
        tx.send(crate::api::ClientEventMessage {
            event,
            raw_bytes: Vec::new(),
        })
        .await
        .expect("send test event");
    }

    // -----------------------------------------------------------------------
    // Unit tests for typed dispatcher_loop
    // -----------------------------------------------------------------------

    #[tokio::test]
    async fn test_dispatcher_loop_success_event() {
        let task_id: u64 = 99;
        let (event_tx, sub) = test_subscription();

        let waiters = Arc::new(WaiterMap::new(HashMap::new()));
        let (session_tx, _) = broadcast::channel(16);
        let (tx, rx) = oneshot::channel();
        waiters.lock().unwrap().insert(task_id, tx);

        let handle = tokio::spawn(dispatcher_loop(sub, waiters.clone(), session_tx));
        send_test_event(
            &event_tx,
            ClientEvent::TaskSuccess {
                task_id,
                result: v_int(42),
            },
        )
        .await;

        let result = tokio::time::timeout(Duration::from_secs(5), rx)
            .await
            .expect("timeout")
            .expect("channel");

        match result {
            TaskResult::Success(v) => assert_eq!(v, v_int(42)),
            other => panic!("expected success, got: {:?}", other),
        }

        handle.abort();
    }

    #[tokio::test]
    async fn test_dispatcher_loop_error_event() {
        let task_id: u64 = 100;
        let (event_tx, sub) = test_subscription();

        let waiters = Arc::new(WaiterMap::new(HashMap::new()));
        let (session_tx, _) = broadcast::channel(16);
        let (tx, rx) = oneshot::channel();
        waiters.lock().unwrap().insert(task_id, tx);

        let handle = tokio::spawn(dispatcher_loop(sub, waiters.clone(), session_tx));

        let sched_err = SchedulerError::TaskAbortedError;
        send_test_event(
            &event_tx,
            ClientEvent::TaskError {
                task_id,
                error: sched_err,
            },
        )
        .await;

        let result = tokio::time::timeout(Duration::from_secs(5), rx)
            .await
            .expect("timeout")
            .expect("channel");

        match result {
            TaskResult::Error(e) => {
                assert!(
                    matches!(e, SchedulerError::TaskAbortedError),
                    "expected TaskAbortedError, got: {:?}",
                    e
                );
            }
            other => panic!("expected error, got: {:?}", other),
        }

        handle.abort();
    }

    #[tokio::test]
    async fn test_dispatcher_loop_unmatched_event_ignored() {
        let task_id_registered: u64 = 200;
        let task_id_unmatched: u64 = 999;
        let (event_tx, sub) = test_subscription();

        let waiters = Arc::new(WaiterMap::new(HashMap::new()));
        let (session_tx, _) = broadcast::channel(16);
        let (tx, rx) = oneshot::channel();
        waiters.lock().unwrap().insert(task_id_registered, tx);

        let handle = tokio::spawn(dispatcher_loop(sub, waiters.clone(), session_tx));

        send_test_event(
            &event_tx,
            ClientEvent::TaskSuccess {
                task_id: task_id_unmatched,
                result: v_int(0),
            },
        )
        .await;

        // Brief sleep to ensure the unmatched event is processed
        tokio::time::sleep(Duration::from_millis(50)).await;

        // The registered waiter should still be pending
        assert_eq!(waiters.lock().unwrap().len(), 1);

        send_test_event(
            &event_tx,
            ClientEvent::TaskSuccess {
                task_id: task_id_registered,
                result: v_int(7),
            },
        )
        .await;

        let result = tokio::time::timeout(Duration::from_secs(5), rx)
            .await
            .expect("timeout")
            .expect("channel");

        match result {
            TaskResult::Success(v) => assert_eq!(v, v_int(7)),
            other => panic!("expected success, got: {:?}", other),
        }

        handle.abort();
    }

    #[tokio::test]
    async fn test_dispatcher_loop_session_events() {
        let (event_tx, sub) = test_subscription();

        let waiters = Arc::new(WaiterMap::new(HashMap::new()));
        let (session_tx, mut session_rx) = broadcast::channel(16);

        let handle = tokio::spawn(dispatcher_loop(sub, waiters.clone(), session_tx));
        send_test_event(&event_tx, ClientEvent::Disconnect).await;

        let session_event = tokio::time::timeout(Duration::from_secs(5), session_rx.recv())
            .await
            .expect("timeout")
            .expect("recv");

        assert!(matches!(session_event, SessionEvent::Disconnect));

        handle.abort();
    }
}
