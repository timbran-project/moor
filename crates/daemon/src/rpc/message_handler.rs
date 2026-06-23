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
use std::{
    hash::BuildHasherDefault,
    sync::{Arc, LazyLock, RwLock},
    time::{Duration, Instant},
};
use uuid::Uuid;

use super::{hosts::Hosts, session::SessionActions, transport::Transport};
use crate::{
    connections::ConnectionRegistry, event_log::EventLogOps, tasks::task_monitor::TaskMonitor,
};
use moor_common::{
    tasks::{ConnectionDetails, NarrativeEvent, SessionError},
    util::{
        MetricEntriesVisitor, MetricEntry, scale_hot_sample_sum_nanos, scale_rare_sample_sum_nanos,
    },
};
use moor_db::db_counters;
use moor_kernel::{
    SchedulerClient, config::Config, tasks::sched_counters, vm::builtins::bf_perf_counters,
};

use crate::runtime::RuntimeApi;
use moor_runtime_api::{
    AuthToken, ClientToken, HostType, RpcMessageError,
    api::{BroadcastEvent, ClientEvent, HostBroadcastEvent},
};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var};
use rusty_paseto::prelude::Key;
use tracing::{error, warn};

pub(crate) fn db_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new(|metric_name, sum| {
        if metric_name == "db_timers_rare_samples" {
            return scale_rare_sample_sum_nanos(sum);
        }

        scale_hot_sample_sum_nanos(sum)
    });
    db_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}

pub(crate) fn sched_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new(|_, sum| scale_hot_sample_sum_nanos(sum));
    sched_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}

pub(crate) fn bf_counter_entries() -> Vec<MetricEntry> {
    let mut visitor = MetricEntriesVisitor::new(|_, sum| scale_hot_sample_sum_nanos(sum));
    bf_perf_counters().visit_metrics(&mut visitor);
    visitor.into_entries()
}

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

/// If we don't hear from a host in this time, we consider it dead and its listeners gone.
pub const HOST_TIMEOUT: Duration = Duration::from_secs(10);

/// Type alias for connection attributes result to reduce complexity
type ConnectionAttributesResult =
    Result<Vec<(Obj, std::collections::HashMap<Symbol, Var>)>, SessionError>;

/// Internal listener info: (handler_object, host_type, port, options)
type InternalListenerInfo = (Obj, HostType, u16, Vec<(Symbol, Var)>);

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

    /// Broadcast a listen event to hosts
    fn broadcast_listen(
        &self,
        handler_object: Obj,
        host_type: HostType,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Result<(), SessionError>;

    /// Broadcast an unlisten event to hosts
    fn broadcast_unlisten(&self, host_type: HostType, port: u16) -> Result<(), SessionError>;

    /// Get current listeners
    fn get_listeners(&self) -> Vec<InternalListenerInfo>;

    /// Get current connections
    #[allow(dead_code)]
    fn get_connections(&self) -> Vec<Obj>;

    fn ping_pong(&self) -> Result<(), SessionError>;

    /// Trigger database compaction to reclaim space and reduce journal size.
    fn compact(&self);

    fn handle_session_event(&self, session_event: SessionActions) -> Result<(), Error>;

    /// Switch the player for the given connection object to the new player.
    fn switch_player(&self, connection_obj: Obj, new_player: Obj) -> Result<(), SessionError>;
}

/// Implementation of message handler that contains the actual business logic
pub struct RpcMessageHandler {
    pub(crate) config: Arc<Config>,
    pub(crate) public_key: Key<32>,
    pub(crate) private_key: Key<64>,

    pub(crate) connections: Box<dyn ConnectionRegistry + Send + Sync>,
    pub(crate) task_monitor: Arc<TaskMonitor>,

    pub(crate) hosts: Arc<RwLock<Hosts>>,

    pub(crate) auth_token_cache:
        PapayaHashMap<AuthToken, (Instant, Obj), BuildHasherDefault<AHasher>>,
    pub(crate) client_token_cache: PapayaHashMap<ClientToken, Instant, BuildHasherDefault<AHasher>>,

    pub(crate) mailbox_sender: Sender<SessionActions>,
    pub(crate) event_log: Arc<dyn EventLogOps>,
    pub(crate) transport: Arc<dyn Transport>,
}

impl RpcMessageHandler {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        config: Arc<Config>,
        public_key: Key<32>,
        private_key: Key<64>,
        connections: Box<dyn ConnectionRegistry + Send + Sync>,
        hosts: Arc<RwLock<Hosts>>,
        mailbox_sender: Sender<SessionActions>,
        event_log: Arc<dyn EventLogOps>,
        task_monitor: Arc<TaskMonitor>,
        transport: Arc<dyn Transport>,
    ) -> Self {
        Self {
            config,
            public_key,
            private_key,
            connections,
            task_monitor,
            hosts,
            auth_token_cache: Default::default(),
            client_token_cache: Default::default(),
            mailbox_sender,
            event_log,
            transport,
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

    fn broadcast_listen(
        &self,
        handler_object: Obj,
        host_type: HostType,
        port: u16,
        options: Vec<(Symbol, Var)>,
    ) -> Result<(), SessionError> {
        let event = HostBroadcastEvent::Listen {
            handler_object,
            host_type,
            port,
            options,
        };

        self.transport
            .broadcast_host_event(event)
            .map_err(|_| SessionError::DeliveryError)
    }

    fn broadcast_unlisten(&self, host_type: HostType, port: u16) -> Result<(), SessionError> {
        let event = HostBroadcastEvent::Unlisten { host_type, port };

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
        // Send ping to all clients
        let client_event = BroadcastEvent::PingPong;
        self.transport
            .broadcast_client_event(client_event)
            .map_err(|_| SessionError::DeliveryError)?;
        self.connections.ping_check();

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

    fn handle_session_event(&self, session_event: SessionActions) -> Result<(), Error> {
        match session_event {
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
            SessionActions::RequestConnectionName(_client_id, connection, reply) => {
                let connection_send_result = match self.connection_name_for(connection) {
                    Ok(c) => reply.send(Ok(c)),
                    Err(e) => {
                        if !matches!(e, SessionError::NoConnectionForPlayer(_)) {
                            error!(error = ?e, "Unable to get connection name");
                        }
                        reply.send(Err(e))
                    }
                };
                if let Err(e) = connection_send_result {
                    error!(error = ?e, "Unable to send connection name");
                }
            }
            SessionActions::Disconnect(_client_id, connection) => {
                if let Err(e) = self.disconnect(connection) {
                    error!(error = ?e, "Unable to disconnect client");
                }
            }
            SessionActions::RequestConnectedPlayers(_client_id, reply) => {
                let connected_players_send_result = match self.connected_players() {
                    Ok(c) => reply.send(Ok(c)),
                    Err(e) => {
                        error!(error = ?e, "Unable to get connected players");
                        reply.send(Err(e))
                    }
                };
                if let Err(e) = connected_players_send_result {
                    error!(error = ?e, "Unable to send connected players");
                }
            }
            SessionActions::RequestConnectedSeconds(_client_id, connection, reply) => {
                let connected_seconds_send_result = match self.connected_seconds_for(connection) {
                    Ok(c) => reply.send(Ok(c)),
                    Err(e) => {
                        if !matches!(e, SessionError::NoConnectionForPlayer(_)) {
                            error!(error = ?e, "Unable to get connected seconds");
                        }
                        reply.send(Err(e))
                    }
                };
                if let Err(e) = connected_seconds_send_result {
                    error!(error = ?e, "Unable to send connected seconds");
                }
            }
            SessionActions::RequestIdleSeconds(_client_id, connection, reply) => {
                let idle_seconds_send_result = match self.idle_seconds_for(connection) {
                    Ok(c) => reply.send(Ok(c)),
                    Err(e) => {
                        if !matches!(e, SessionError::NoConnectionForPlayer(_)) {
                            error!(error = ?e, "Unable to get idle seconds");
                        }
                        reply.send(Err(e))
                    }
                };
                if let Err(e) = idle_seconds_send_result {
                    error!(error = ?e, "Unable to send idle seconds");
                }
            }
            SessionActions::RequestConnections(client_id, player, reply) => {
                let connections_send_result = match self.connections_for(client_id, player) {
                    Ok(c) => reply.send(Ok(c)),
                    Err(e) => {
                        if !matches!(e, SessionError::NoConnectionForPlayer(_)) {
                            error!(error = ?e, "Unable to get connections");
                        }
                        reply.send(Err(e))
                    }
                };
                if let Err(e) = connections_send_result {
                    error!(error = ?e, "Unable to send connections");
                }
            }
            SessionActions::RequestConnectionDetails(client_id, player, reply) => {
                let connection_details_send_result =
                    match self.connection_details_for(client_id, player) {
                        Ok(details) => reply.send(Ok(details)),
                        Err(e) => {
                            if !matches!(e, SessionError::NoConnectionForPlayer(_)) {
                                error!(error = ?e, "Unable to get connection details");
                            }
                            reply.send(Err(e))
                        }
                    };
                if let Err(e) = connection_details_send_result {
                    error!(error = ?e, "Unable to send connection details");
                }
            }
            SessionActions::RequestClientAttributes(_client_id, obj, reply) => {
                use moor_var::{v_list, v_map, v_obj, v_sym};

                let handle_result = || -> Result<Var, SessionError> {
                    if !obj.is_positive() {
                        // This is a connection object - return just its attributes
                        let attributes =
                            self.get_connection_attributes_for_single_connection(obj)?;
                        let attr_pairs: Vec<_> =
                            attributes.into_iter().map(|(k, v)| (v_sym(k), v)).collect();
                        Ok(v_map(&attr_pairs))
                    } else {
                        // This is a player object - return list of [connection_obj, attributes] pairs
                        let connection_attrs_list =
                            self.get_connection_attributes_for_player(obj)?;
                        let items: Vec<_> = connection_attrs_list
                            .into_iter()
                            .map(|(conn_obj, attributes)| {
                                let attr_pairs: Vec<_> =
                                    attributes.into_iter().map(|(k, v)| (v_sym(k), v)).collect();
                                v_list(&[v_obj(conn_obj), v_map(&attr_pairs)])
                            })
                            .collect();
                        Ok(v_list(&items))
                    }
                };

                let result = handle_result();
                if let Err(e) = reply.send(result) {
                    error!(error = ?e, "Unable to send client attributes");
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

    fn switch_player(&self, connection_obj: Obj, new_player: Obj) -> Result<(), SessionError> {
        // Get the client IDs for this connection object
        let client_ids = self
            .connections
            .client_ids_for(connection_obj)
            .map_err(|_| SessionError::DeliveryError)?;

        // Generate a new auth token for the new player
        let new_auth_token = self.make_auth_token(&new_player);

        // Prepare events for all clients before making any changes
        let mut events_to_send = Vec::new();
        for client_id in &client_ids {
            let event = ClientEvent::PlayerSwitched {
                new_player,
                new_auth_token: new_auth_token.clone(),
            };
            events_to_send.push((*client_id, event));
        }

        // Switch the player for each client ID associated with this connection
        // Do this in one batch to minimize the window for inconsistency
        for client_id in &client_ids {
            self.connections
                .switch_player_for_client(*client_id, new_player)
                .map_err(|_| SessionError::DeliveryError)?;
        }

        // Send events after all connection updates are complete
        // If any event fails to send, log it but don't fail the entire operation
        // since the connection registry has already been updated
        for (client_id, event) in events_to_send {
            if let Err(e) = self.transport.publish_client_event(client_id, event) {
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
        self.transport
            .publish_narrative_events(events, self.connections.as_ref())
    }

    // Helper methods that delegate to connections
    pub fn connection_name_for(&self, connection: Obj) -> Result<String, SessionError> {
        self.connections.connection_name_for(connection)
    }

    pub fn connected_seconds_for(&self, connection: Obj) -> Result<f64, SessionError> {
        self.connections.connected_seconds_for(connection)
    }

    pub fn disconnect(&self, player: Obj) -> Result<(), SessionError> {
        warn!("Disconnecting player: {}", player);
        let all_client_ids = self.connections.client_ids_for(player)?;

        // Send disconnect event to all client connections for this player
        let event = ClientEvent::Disconnect;

        for client_id in &all_client_ids {
            // First send the disconnect event to the client
            if let Err(e) = self
                .transport
                .publish_client_event(*client_id, event.clone())
            {
                error!(error = ?e, client_id = ?client_id, "Unable to send disconnect event to client");
            }

            // Then remove the client connection
            if let Err(e) = self.connections.remove_client_connection(*client_id) {
                error!(error = ?e, "Unable to remove client connection for disconnect");
            }
        }

        Ok(())
    }

    pub fn request_client_input(
        &self,
        client_id: Uuid,
        player: Obj,
        input_request_id: Uuid,
        metadata: Option<Vec<(Symbol, Var)>>,
    ) -> Result<(), Error> {
        // Validate first - check that the player matches the logged-in player for this client
        let Some(logged_in_player) = self.connections.player_object_for_client(client_id) else {
            return Err(eyre::eyre!("No connection for player"));
        };
        if logged_in_player != player {
            return Err(eyre::eyre!("Player mismatch"));
        }

        let event = ClientEvent::RequestInput {
            request_id: input_request_id,
            metadata: metadata.unwrap_or_default(),
        };
        self.transport.publish_client_event(client_id, event)
    }

    pub fn send_system_message(
        &self,
        client_id: Uuid,
        player: Obj,
        message: String,
    ) -> Result<(), Error> {
        let event = ClientEvent::SystemMessage { player, message };
        self.transport.publish_client_event(client_id, event)
    }

    pub fn connected_players(&self) -> Result<Vec<Obj>, SessionError> {
        let connections = self.connections.connections();
        Ok(connections
            .iter()
            .filter(|o| o > &&SYSTEM_OBJECT)
            .cloned()
            .collect())
    }

    pub fn idle_seconds_for(&self, player: Obj) -> Result<f64, SessionError> {
        let last_activity = self.connections.last_activity_for(player)?;
        Ok(last_activity
            .elapsed()
            .map(|e| e.as_secs_f64())
            .unwrap_or(0.0))
    }

    pub fn connections_for(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<Obj>, SessionError> {
        if let Some(target_player) = player {
            // First find the client IDs for the player
            let client_ids = self.connections.client_ids_for(target_player)?;
            // Then return the connections for those client IDs
            let mut connections = vec![];
            for id in client_ids {
                if let Some(connection) = self.connections.connection_object_for_client(id) {
                    connections.push(connection);
                }
            }
            Ok(connections)
        } else {
            // We want all connections for the player associated with this client_id, but we'll
            // put the connection associated with the client_id first.  So let's get that first.
            let mut connections = vec![];
            if let Some(connection) = self.connections.connection_object_for_client(client_id) {
                connections.push(connection);
            }
            // Now get all connections for the player associated with this client_id
            let player_obj = self.connections.player_object_for_client(client_id);
            if let Some(player_obj) = player_obj {
                let client_ids = self.connections.client_ids_for(player_obj)?;
                for id in client_ids {
                    if let Some(connection) = self.connections.connection_object_for_client(id) {
                        // Avoid adding the same connection again
                        if !connections.contains(&connection) {
                            connections.push(connection);
                        }
                    }
                }
            }
            Ok(connections)
        }
    }

    pub fn connection_details_for(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        if let Some(target_player) = player {
            // Get connection details for the specified player
            let client_ids = self.connections.client_ids_for(target_player)?;
            let mut details = vec![];
            for id in client_ids {
                if let Some(connection_obj) = self.connections.connection_object_for_client(id) {
                    let hostname = self.connections.connection_name_for(connection_obj)?;
                    let idle_seconds = self.idle_seconds_for(connection_obj)?;
                    let acceptable_content_types = self
                        .connections
                        .acceptable_content_types_for(connection_obj)?;
                    details.push(ConnectionDetails {
                        connection_obj,
                        peer_addr: hostname,
                        idle_seconds,
                        acceptable_content_types,
                    });
                }
            }
            Ok(details)
        } else {
            // Get connection details for the player associated with this client_id
            let mut details = vec![];

            // Start with the connection for this specific client_id
            if let Some(connection_obj) = self.connections.connection_object_for_client(client_id) {
                let hostname = self.connections.connection_name_for(connection_obj)?;
                let idle_seconds = self.idle_seconds_for(connection_obj)?;
                let acceptable_content_types = self
                    .connections
                    .acceptable_content_types_for(connection_obj)?;
                details.push(ConnectionDetails {
                    connection_obj,
                    peer_addr: hostname,
                    idle_seconds,
                    acceptable_content_types,
                });
            }

            // Now get all other connections for the same player
            if let Some(player_obj) = self.connections.player_object_for_client(client_id) {
                let client_ids = self.connections.client_ids_for(player_obj)?;
                for id in client_ids {
                    if id != client_id {
                        // Skip the one we already added
                        if let Some(connection_obj) =
                            self.connections.connection_object_for_client(id)
                        {
                            // Check if we already have this connection to avoid duplicates
                            if !details.iter().any(|d| d.connection_obj == connection_obj) {
                                let hostname =
                                    self.connections.connection_name_for(connection_obj)?;
                                let idle_seconds = self.idle_seconds_for(connection_obj)?;
                                let acceptable_content_types = self
                                    .connections
                                    .acceptable_content_types_for(connection_obj)?;
                                details.push(ConnectionDetails {
                                    connection_obj,
                                    peer_addr: hostname,
                                    idle_seconds,
                                    acceptable_content_types,
                                });
                            }
                        }
                    }
                }
            }
            Ok(details)
        }
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
        self.transport.publish_client_event(
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
        self.transport.publish_client_event(client_id, task_event)
    }
    /// Get attributes for a single connection object
    fn get_connection_attributes_for_single_connection(
        &self,
        connection_obj: Obj,
    ) -> Result<std::collections::HashMap<Symbol, Var>, SessionError> {
        // Get attributes directly from the connection registry
        // The connection registry now handles both player and connection objects
        self.connections.get_client_attributes(connection_obj)
    }

    /// Get attributes for all connections of a player
    fn get_connection_attributes_for_player(&self, player: Obj) -> ConnectionAttributesResult {
        // Get all client IDs for this player
        let client_ids = self.connections.client_ids_for(player)?;

        let mut result = Vec::new();
        for client_id in client_ids {
            // Get the connection object for this client
            let Some(connection_obj) = self.connections.connection_object_for_client(client_id)
            else {
                continue;
            };

            // Get attributes for this specific connection
            let attributes = self
                .get_connection_attributes_for_single_connection(connection_obj)
                .unwrap_or_else(|_| std::collections::HashMap::new());
            result.push((connection_obj, attributes));
        }

        Ok(result)
    }
}
