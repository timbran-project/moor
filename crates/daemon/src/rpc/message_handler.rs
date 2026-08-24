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

use super::{
    hosts::Hosts,
    session::{RpcSession, SessionActions},
    transport::Transport,
};
use crate::{
    connections::ConnectionRegistry, event_log::EventLogOps, tasks::task_monitor::TaskMonitor,
};
use moor_common::{
    tasks::{NarrativeEvent, SessionError},
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
use moor_var::{Obj, Symbol, Var};
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

    pub(crate) hosts: Arc<RwLock<Hosts>>,

    pub(crate) auth_token_cache:
        PapayaHashMap<AuthToken, (Instant, Obj), BuildHasherDefault<AHasher>>,
    pub(crate) client_token_cache: PapayaHashMap<ClientToken, Instant, BuildHasherDefault<AHasher>>,

    pub(crate) mailbox_sender: Sender<SessionActions>,
    pub(crate) event_log: Arc<dyn EventLogOps>,
    pub(crate) transport: Arc<dyn Transport>,
}

impl RpcMessageHandler {
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
        self.transport.publish_client_event(target_client_id, event)
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
}
