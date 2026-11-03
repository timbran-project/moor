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

//! Message handler for RPC business logic, separated from transport concerns

use ahash::AHasher;
use eyre::Error;
use flume::Sender;
use moor_rpc::{DaemonToClientReply, DaemonToHostReply, HostClientToDaemonMessageRef};
use moor_schema::rpc as moor_rpc;
use papaya::HashMap as PapayaHashMap;
#[cfg(test)]
use std::sync::{Condvar, Mutex};
use std::{
    hash::BuildHasherDefault,
    sync::{Arc, LazyLock, RwLock},
    time::{Duration, Instant},
};
use uuid::Uuid;

use super::deferred_calls::DeferredCalls;
use super::{
    client_event_buffer::{ClientEventBuffer, ClientEventBufferError},
    hosts::Hosts,
    session::{RpcSession, SessionActions},
    transport::Transport,
};
use crate::{
    connections::{ConnectionRegistry, RemovedConnection},
    event_log::EventLogOps,
    tasks::task_monitor::TaskMonitor,
};
use moor_common::tasks::{Event, NarrativeEvent, SessionError};
#[cfg(test)]
use moor_kernel::tasks::{TaskHandle, TaskNotification};
use moor_kernel::{SchedulerClient, config::Config};
use std::sync::{OnceLock, Weak};

use crate::runtime::{RunOnWorker, RuntimeApi};
use moor_runtime_api::{
    AuthToken, ClientToken, ListenerKind, RpcMessageError,
    api::{BroadcastEvent, ClientEvent, ClientEventMessage, HostBroadcastEvent},
    api_codec::encode_client_event_bytes,
};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var};
use rusty_paseto::prelude::Key;
use tracing::{error, warn};

pub(crate) static USER_CONNECTED_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("user_connected"));
pub(crate) static USER_DISCONNECTED_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("user_disconnected"));
pub(crate) static USER_RECONNECTED_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("user_reconnected"));
pub(crate) static USER_CREATED_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("user_created"));
pub(crate) static DO_LOGIN_COMMAND: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("do_login_command"));
pub(crate) static SCHED_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("sched"));
pub(crate) static DB_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("db"));
pub(crate) static BF_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("bf"));

/// Delivers a client request's reply when it comes later. It may run on any thread.
pub type DaemonReplySink = Box<dyn FnOnce(Result<DaemonToClientReply, RpcMessageError>) + Send>;

/// If we don't hear from a host in this time, we consider it dead and its listeners gone.
pub const HOST_TIMEOUT: Duration = Duration::from_secs(10);

/// Internal listener info: (handler_object, kind, port, options)
type InternalListenerInfo = (Obj, ListenerKind, u16, Vec<(Symbol, Var)>);

/// Trait for handling RPC message business logic
pub trait MessageHandler: RuntimeApi + Send + Sync {
    /// Process a host-to-daemon message (FlatBuffer refs)
    fn handle_host_message(
        &self,
        host_id: Uuid,
        message: moor_rpc::HostToDaemonMessageRef<'_>,
    ) -> Result<DaemonToHostReply, RpcMessageError>;

    /// Process a client-to-daemon message (FlatBuffer refs)
    fn handle_client_message(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        message: HostClientToDaemonMessageRef<'_>,
    ) -> Result<DaemonToClientReply, RpcMessageError>;

    /// Process a client message that may reply later. Returns the reply if there is one now.
    /// Otherwise `sink` will receive it when the request's task finishes, so this thread is free.
    fn handle_client_message_deferred(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        message: HostClientToDaemonMessageRef<'_>,
        sink: DaemonReplySink,
        run_on_worker: RunOnWorker,
    ) -> Option<Result<DaemonToClientReply, RpcMessageError>> {
        let _ = (sink, run_on_worker);
        Some(self.handle_client_message(scheduler_client, client_id, message))
    }

    /// Broadcast a listen event to hosts
    fn broadcast_listen(
        &self,
        handler_object: Obj,
        kind: ListenerKind,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Result<(), SessionError>;

    /// Broadcast an unlisten event to hosts
    fn broadcast_unlisten(&self, kind: ListenerKind, port: u16) -> Result<(), SessionError>;

    /// Get current listeners
    fn get_listeners(&self) -> Vec<InternalListenerInfo>;

    /// Get current connections
    #[allow(dead_code)]
    fn get_connections(&self) -> Vec<Obj>;

    fn ping_pong(&self) -> Result<(), SessionError>;

    /// Trigger database compaction to reclaim space and reduce journal size.
    fn compact(&self);

    fn handle_session_event(
        &self,
        scheduler_client: &SchedulerClient,
        session_event: SessionActions,
    ) -> Result<(), Error>;

    #[cfg(test)]
    fn wait_for_disconnect_tasks(&self, expected: usize) -> Result<(), Error>;

    /// Switch the player for the given connection object to the new player.
    fn switch_player(
        &self,
        connection_obj: Obj,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), SessionError>;
}

/// Implementation of message handler that contains the actual business logic
pub struct RpcMessageHandler {
    pub(crate) config: Arc<Config>,
    pub(crate) public_key: Key<32>,
    pub(crate) private_key: Key<64>,

    pub(crate) connections: Arc<dyn ConnectionRegistry>,
    pub(crate) task_monitor: Arc<TaskMonitor>,
    pub(crate) deferred_calls: Arc<DeferredCalls>,
    /// A handle to this handler, for work that outlives the request that started it.
    self_handle: OnceLock<Weak<RpcMessageHandler>>,

    pub(crate) hosts: Arc<RwLock<Hosts>>,

    pub(crate) auth_token_cache:
        PapayaHashMap<AuthToken, (Instant, Obj), BuildHasherDefault<AHasher>>,
    pub(crate) client_token_cache:
        PapayaHashMap<ClientToken, (Instant, Uuid), BuildHasherDefault<AHasher>>,

    pub(crate) mailbox_sender: Sender<SessionActions>,
    #[cfg(test)]
    pub(crate) disconnect_tasks: (Mutex<Vec<TaskHandle>>, Condvar),
    pub(crate) event_log: Arc<dyn EventLogOps>,
    pub(crate) transport: Arc<dyn Transport>,
    pub(crate) client_events: ClientEventBuffer,
}

impl RpcMessageHandler {
    /// Record this handler's own `Arc`. Without it, logins wait on the thread that started them.
    pub(crate) fn set_self_handle(self: &Arc<Self>) {
        let _ = self.self_handle.set(Arc::downgrade(self));
    }

    pub(crate) fn self_handle(&self) -> Option<Arc<Self>> {
        self.self_handle.get().and_then(Weak::upgrade)
    }

    pub(crate) fn new_rpc_session(
        &self,
        client_id: Uuid,
        connection: Obj,
        active_player: Obj,
    ) -> RpcSession {
        let history_player = self
            .connections
            .history_object_for_client(client_id)
            .unwrap_or(active_player);
        RpcSession::new(
            client_id,
            connection,
            active_player,
            history_player,
            self.event_log.clone(),
            self.connections.clone(),
            self.mailbox_sender.clone(),
        )
    }

    #[allow(clippy::too_many_arguments)]
    pub fn new(
        config: Arc<Config>,
        public_key: Key<32>,
        private_key: Key<64>,
        connections: Arc<dyn ConnectionRegistry>,
        hosts: Arc<RwLock<Hosts>>,
        mailbox_sender: Sender<SessionActions>,
        event_log: Arc<dyn EventLogOps>,
        task_monitor: Arc<TaskMonitor>,
        deferred_calls: Arc<DeferredCalls>,
        transport: Arc<dyn Transport>,
    ) -> Self {
        Self {
            config,
            public_key,
            private_key,
            connections,
            task_monitor,
            deferred_calls,
            self_handle: OnceLock::new(),
            hosts,
            auth_token_cache: Default::default(),
            client_token_cache: Default::default(),
            mailbox_sender,
            #[cfg(test)]
            disconnect_tasks: (Mutex::new(Vec::new()), Condvar::new()),
            event_log,
            transport,
            client_events: ClientEventBuffer::new(),
        }
    }
}

impl MessageHandler for RpcMessageHandler {
    fn handle_host_message(
        &self,
        host_id: Uuid,
        message: moor_rpc::HostToDaemonMessageRef<'_>,
    ) -> Result<DaemonToHostReply, RpcMessageError> {
        let request = super::api_codec::decode_host_request(message)?;
        let reply = RuntimeApi::handle_host_request(self, host_id, request)?;
        Ok(super::api_codec::encode_host_reply(reply))
    }

    fn handle_client_message(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        message: HostClientToDaemonMessageRef<'_>,
    ) -> Result<DaemonToClientReply, RpcMessageError> {
        let request = super::api_codec::decode_client_request(message)?;
        let reply = RuntimeApi::handle_client_request(self, scheduler_client, client_id, request)?;
        super::api_codec::encode_client_reply(reply)
    }

    fn handle_client_message_deferred(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        message: HostClientToDaemonMessageRef<'_>,
        sink: DaemonReplySink,
        run_on_worker: RunOnWorker,
    ) -> Option<Result<DaemonToClientReply, RpcMessageError>> {
        let request = match super::api_codec::decode_client_request(message) {
            Ok(request) => request,
            Err(error) => return Some(Err(error)),
        };
        let sink = Box::new(
            move |reply: Result<moor_runtime_api::api::ClientReply, RpcMessageError>| {
                sink(reply.and_then(super::api_codec::encode_client_reply));
            },
        );
        let reply = RuntimeApi::start_client_request(
            self,
            scheduler_client,
            client_id,
            request,
            sink,
            run_on_worker,
        )?;
        Some(reply.and_then(super::api_codec::encode_client_reply))
    }

    fn broadcast_listen(
        &self,
        handler_object: Obj,
        kind: ListenerKind,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Result<(), SessionError> {
        if !self.hosts.read().unwrap().offers(kind) {
            warn!(%kind, port, "No connected host opens this kind of listener");
        }
        let event = HostBroadcastEvent::Listen {
            handler_object,
            kind,
            port,
            options,
        };

        self.transport
            .broadcast_host_event(event)
            .map_err(|_| SessionError::DeliveryError)
    }

    fn broadcast_unlisten(&self, kind: ListenerKind, port: u16) -> Result<(), SessionError> {
        let event = HostBroadcastEvent::Unlisten { kind, port };

        self.transport
            .broadcast_host_event(event)
            .map_err(|_| SessionError::DeliveryError)
    }

    fn get_listeners(&self) -> Vec<InternalListenerInfo> {
        let hosts = self.hosts.read().unwrap();
        hosts
            .listeners()
            .iter()
            .map(|(o, t, h)| (*o, *t, h.port(), vec![]))
            .collect()
    }

    fn get_connections(&self) -> Vec<Obj> {
        self.connections.connections()
    }

    fn ping_pong(&self) -> Result<(), SessionError> {
        self.client_events.expire();
        // Send ping to all clients
        let client_event = BroadcastEvent::PingPong;
        self.transport
            .broadcast_client_event(client_event)
            .map_err(|_| SessionError::DeliveryError)?;
        for removed in self.connections.ping_check() {
            if let Err(error) = self.finish_connection_removal(removed, None) {
                error!(?error, "Unable to queue expired connection's departure");
            }
        }

        // Send ping to all hosts
        let host_event = HostBroadcastEvent::PingPong;
        self.transport
            .broadcast_host_event(host_event)
            .map_err(|_| SessionError::DeliveryError)?;

        let mut hosts = self.hosts.write().unwrap();
        hosts.ping_check(HOST_TIMEOUT);
        Ok(())
    }

    fn compact(&self) {
        self.connections.flush();
    }

    fn handle_session_event(
        &self,
        scheduler_client: &SchedulerClient,
        session_event: SessionActions,
    ) -> Result<(), Error> {
        match session_event {
            #[cfg(test)]
            SessionActions::Barrier(done) => {
                done.send(())?;
            }
            SessionActions::UserDisconnected(removed) => {
                if let Some(player) = removed.disconnected_player {
                    self.submit_disconnected_task(
                        &SYSTEM_OBJECT,
                        scheduler_client.clone(),
                        removed.client_id,
                        &player,
                        &removed.connection,
                    )?;
                }
            }
            SessionActions::PublishNarrativeEvents(events) => {
                if let Err(e) = self.publish_narrative_events(&events) {
                    error!(error = ?e, "Unable to publish narrative events");
                }
            }
            SessionActions::RequestClientInput {
                client_id,
                connection,
                request_id: input_request_id,
                metadata,
            } => {
                if let Err(e) =
                    self.request_client_input(client_id, connection, input_request_id, metadata)
                {
                    error!(error = ?e, "Unable to request client input");
                }
            }
            SessionActions::SendSystemMessage {
                client_id,
                connection,
                system_message: message,
            } => {
                if let Err(e) = self.send_system_message(client_id, connection, message) {
                    error!(error = ?e, "Unable to send system message");
                }
            }
            SessionActions::Disconnect(_client_id, connection) => {
                if let Err(e) = self.disconnect(connection) {
                    error!(error = ?e, "Unable to disconnect client");
                }
            }
            SessionActions::SetClientAttribute(client_id, connection_obj, key, value) => {
                if let Err(e) = self.set_client_attribute(client_id, connection_obj, key, value) {
                    error!(error = ?e, client_id = ?client_id, "Unable to set client attribute");
                }
            }
            SessionActions::PublishTaskCompletion(client_id, task_event) => {
                if let Err(e) = self.publish_task_completion(client_id, task_event) {
                    error!(error = ?e, client_id = ?client_id, "Unable to publish task completion");
                }
            }
        }
        Ok(())
    }

    #[cfg(test)]
    fn wait_for_disconnect_tasks(&self, expected: usize) -> Result<(), Error> {
        let barrier = || -> Result<(), Error> {
            let (done, received) = flume::bounded(1);
            self.mailbox_sender.send(SessionActions::Barrier(done))?;
            received.recv_timeout(Duration::from_secs(5))?;
            Ok(())
        };
        barrier()?;

        let (pending, ready) = &self.disconnect_tasks;
        let handles = pending
            .lock()
            .map_err(|_| eyre::eyre!("disconnect task handles poisoned"))?;
        let (mut handles, timeout) = ready
            .wait_timeout_while(handles, Duration::from_secs(5), |tasks| {
                tasks.len() < expected
            })
            .map_err(|_| eyre::eyre!("disconnect task handles poisoned"))?;
        eyre::ensure!(
            !timeout.timed_out() || handles.len() >= expected,
            "expected {expected} disconnect task(s), submitted {}",
            handles.len()
        );
        eyre::ensure!(
            handles.len() == expected,
            "expected {expected} disconnect task(s), submitted {}",
            handles.len()
        );
        let tasks = std::mem::take(&mut *handles);
        drop(handles);
        for task in tasks {
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                let remaining = deadline.saturating_duration_since(Instant::now());
                let notification = task.receiver().recv_timeout(remaining).map_err(|_| {
                    eyre::eyre!("disconnect hook task did not finish within 5 seconds")
                })?;
                match notification {
                    (_, Ok(TaskNotification::Suspended)) => continue,
                    (_, Ok(TaskNotification::Result(_))) => break,
                    (_, Err(error)) => eyre::bail!("disconnect hook task failed: {error:?}"),
                }
            }
        }

        barrier()?;
        let unexpected = pending
            .lock()
            .map_err(|_| eyre::eyre!("disconnect task handles poisoned"))?
            .len();
        eyre::ensure!(
            unexpected == 0,
            "{unexpected} extra disconnect task(s) submitted"
        );
        Ok(())
    }

    fn switch_player(
        &self,
        connection_obj: Obj,
        new_player: Obj,
        silent: bool,
        preserve_history: bool,
    ) -> Result<(), SessionError> {
        let client_ids = self
            .connections
            .switch_player_for_connection(connection_obj, new_player, preserve_history)
            .map_err(|_| SessionError::DeliveryError)?;

        let new_auth_token = self.make_auth_token(&new_player);

        for client_id in client_ids {
            let event = ClientEvent::PlayerSwitched {
                new_player,
                new_auth_token: new_auth_token.clone(),
                silent,
                preserve_history,
            };
            if let Err(e) = self.publish_client_event(client_id, event) {
                error!(
                    client_id = ?client_id,
                    new_player = ?new_player,
                    connection_obj = ?connection_obj,
                    error = ?e,
                    "Failed to send PlayerSwitched event to client after successful connection switch"
                );
            }
        }

        Ok(())
    }
}

impl RpcMessageHandler {
    fn publish_narrative_events(&self, events: &[(Obj, Box<NarrativeEvent>)]) -> Result<(), Error> {
        for (player, event) in events {
            let client_ids = self.connections.client_ids_for(*player)?;
            let client_event = match &event.event {
                Event::SetConnectionOption {
                    connection,
                    option,
                    value,
                } => {
                    if let Some(&client_id) = client_ids.first() {
                        self.connections.set_client_attribute(
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

            for client_id in client_ids {
                self.publish_client_event(client_id, client_event.clone())?;
            }
        }
        Ok(())
    }

    fn publish_client_event(&self, client_id: Uuid, event: ClientEvent) -> Result<(), Error> {
        if event.is_ephemeral() {
            // Ephemeral events bypass the delivery queue: they are never retained, replayed
            // or counted against the backlog, and a client that misses one misses it.
            let message = ClientEventMessage::unsequenced(event);
            let encoded = encode_client_event_bytes(&message)?;
            return self
                .transport
                .publish_client_event(client_id, message, encoded);
        }
        let (message, encoded) = match self.client_events.push(client_id, event) {
            Ok(published) => published,
            Err(error @ ClientEventBufferError::BacklogExceeded { .. }) => {
                error!(?client_id, %error, "Disconnecting client with an unacknowledged event backlog");
                self.remove_client(client_id, None)?;
                return Err(error.into());
            }
            Err(error) => return Err(error.into()),
        };
        self.transport
            .publish_client_event(client_id, message, encoded)
    }

    pub fn disconnect(&self, player: Obj) -> Result<(), SessionError> {
        warn!("Disconnecting player: {}", player);
        let all_client_ids = self.connections.client_ids_for(player)?;

        // Send disconnect event to all client connections for this player
        let event = ClientEvent::Disconnect;

        for client_id in &all_client_ids {
            // First send the disconnect event to the client
            if let Err(e) = self.publish_client_event(*client_id, event.clone()) {
                error!(error = ?e, client_id = ?client_id, "Unable to send disconnect event to client");
            }

            // Then remove the client connection
            if let Err(e) = self.remove_client(*client_id, None) {
                error!(error = ?e, "Unable to remove client connection for disconnect");
            }
        }

        Ok(())
    }

    /// Share removal and lifecycle delivery across detach, boot, and backlog eviction.
    pub(crate) fn remove_client(
        &self,
        client_id: Uuid,
        scheduler_client: Option<&SchedulerClient>,
    ) -> Result<(), Error> {
        if let Some(removed) = self.connections.remove_client_connection(client_id)? {
            self.finish_connection_removal(removed, scheduler_client)?;
        }
        Ok(())
    }

    fn finish_connection_removal(
        &self,
        removed: RemovedConnection,
        scheduler_client: Option<&SchedulerClient>,
    ) -> Result<(), Error> {
        self.client_events.remove_client(removed.client_id);
        if removed.disconnected_player.is_some() {
            let event = SessionActions::UserDisconnected(removed);
            if let Some(scheduler_client) = scheduler_client {
                // Hard detach submits its hook before replying; a subsequent attach can submit another.
                self.handle_session_event(scheduler_client, event)?;
            } else {
                self.mailbox_sender.send(event)?;
            }
        }
        Ok(())
    }

    pub fn request_client_input(
        &self,
        client_id: Uuid,
        input_player: Obj,
        input_request_id: Uuid,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), Error> {
        let Some(logged_in_player) = self.connections.player_object_for_client(client_id) else {
            return Err(eyre::eyre!("No connection for player"));
        };
        let current_connection = self.connections.connection_object_for_client(client_id);
        let target_client_id =
            if logged_in_player == input_player || current_connection == Some(input_player) {
                client_id
            } else {
                self.connections
                    .client_ids_for(input_player)?
                    .into_iter()
                    .next()
                    .ok_or_else(|| eyre::eyre!("No connection for player {input_player}"))?
            };

        let event = ClientEvent::RequestInput {
            request_id: input_request_id,
            metadata: metadata.unwrap_or_default(),
        };
        self.publish_client_event(target_client_id, event)
    }

    pub fn send_system_message(
        &self,
        client_id: Uuid,
        player: Obj,
        message: String,
    ) -> Result<(), Error> {
        let event = ClientEvent::SystemMessage { player, message };
        self.publish_client_event(client_id, event)
    }

    fn set_client_attribute(
        &self,
        client_id: Uuid,
        connection_obj: Obj,
        key: Symbol,
        value: Var,
    ) -> Result<(), Error> {
        // Store the attribute in the connection registry
        self.connections
            .set_client_attribute(client_id, key, Some(value.clone()))?;

        // Send SetConnectionOption event to the host
        self.publish_client_event(
            client_id,
            ClientEvent::SetConnectionOption {
                connection_obj,
                option_name: key,
                value,
            },
        )
    }

    fn publish_task_completion(
        &self,
        client_id: Uuid,
        task_event: ClientEvent,
    ) -> Result<(), Error> {
        self.publish_client_event(client_id, task_event)
    }
}
