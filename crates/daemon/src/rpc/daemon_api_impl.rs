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

//! [`RuntimeApi`] implementation for [`RpcMessageHandler`], operating on the
//! typed [`rpc_common::api`] enums. The existing [`MessageHandler`] methods
//! decode FlatBuffer refs into these enums, dispatch here, and encode replies
//! back, keeping FlatBuffer knowledge at the wire boundary.

use moor_common::model::ObjectRef;
use moor_kernel::SchedulerClient;
use moor_schema::rpc as moor_rpc;
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var, Variant, v_empty_str, v_str, v_string};
use rpc_common::api::{
    ClientReply, ClientRequest, ConnectType, CounterCategory, EntityType, HostReply, HostRequest,
    ObjectInfo, ServerFeatures, VerbCallResponse, VerbProgramResponse, WorldStateResult,
    WorldStateResultEntry,
};
use rpc_common::{AuthToken, ClientToken, RpcMessageError};
use std::sync::Arc;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::connections::NewConnectionParams;
use crate::rpc::message_handler::{
    BF_SYM, DB_SYM, DO_LOGIN_COMMAND, RpcMessageHandler, SCHED_SYM, bf_counter_entries,
    db_counter_entries, sched_counter_entries,
};
use crate::rpc::session::RpcSession;
use crate::runtime::RuntimeApi;

impl RuntimeApi for RpcMessageHandler {
    fn handle_host_request(
        &self,
        host_id: Uuid,
        request: HostRequest,
    ) -> Result<HostReply, RpcMessageError> {
        match request {
            HostRequest::RegisterHost {
                timestamp: _,
                host_type,
                listeners,
            } => {
                let listeners: Vec<(Obj, std::net::SocketAddr)> = listeners
                    .into_iter()
                    .map(|l| (l.handler_object, l.socket_addr))
                    .collect();
                info!(
                    "Host {} registered with {} listeners",
                    host_id,
                    listeners.len()
                );
                let mut hosts = self.hosts.write().unwrap();
                hosts.receive_ping(host_id, host_type, listeners);
                Ok(HostReply::Ack)
            }
            HostRequest::HostPong {
                timestamp: _,
                host_type,
                listeners,
            } => {
                let listeners: Vec<(Obj, std::net::SocketAddr)> = listeners
                    .into_iter()
                    .map(|l| (l.handler_object, l.socket_addr))
                    .collect();
                let num_listeners = listeners.len();
                let mut hosts = self.hosts.write().unwrap();
                if hosts.receive_ping(host_id, host_type, listeners) {
                    info!(
                        "Host {} registered with {} listeners",
                        host_id, num_listeners
                    );
                }
                Ok(HostReply::Ack)
            }
            HostRequest::DetachHost => {
                let mut hosts = self.hosts.write().unwrap();
                hosts.unregister_host(&host_id);
                Ok(HostReply::Ack)
            }
            HostRequest::RequestPerformanceCounters => {
                let all_counters = [
                    (*SCHED_SYM, sched_counter_entries()),
                    (*DB_SYM, db_counter_entries()),
                    (*BF_SYM, bf_counter_entries()),
                ];
                let timestamp = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos() as u64;
                let counters = all_counters
                    .into_iter()
                    .map(|(category_sym, counters_list)| CounterCategory {
                        category: category_sym,
                        counters: counters_list
                            .into_iter()
                            .map(|(name_sym, count, cumulative_ns)| {
                                rpc_common::api::CounterSample {
                                    name: name_sym,
                                    count: count as i64,
                                    total_cumulative_ns: cumulative_ns as i64,
                                }
                            })
                            .collect(),
                    })
                    .collect();
                Ok(HostReply::PerformanceCounters {
                    timestamp,
                    counters,
                })
            }
            HostRequest::GetServerFeatures => {
                let features = self.config.features.as_ref();
                Ok(HostReply::ServerFeatures(ServerFeatures {
                    persistent_tasks: features.persistent_tasks,
                    rich_notify: features.rich_notify,
                    lexical_scopes: true,
                    type_dispatch: features.type_dispatch,
                    flyweight_type: features.flyweight_type,
                    list_comprehensions: true,
                    bool_type: features.bool_type,
                    use_boolean_returns: features.use_boolean_returns,
                    symbol_type: features.symbol_type,
                    use_symbols_in_builtins: features.use_symbols_in_builtins,
                    custom_errors: features.custom_errors,
                    use_uuobjids: features.use_uuobjids,
                    enable_eventlog: features.enable_eventlog,
                    anonymous_objects: features.anonymous_objects,
                }))
            }
        }
    }

    fn handle_client_request(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcMessageError> {
        match request {
            ClientRequest::ConnectionEstablish {
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            } => {
                let acceptable_content_types =
                    acceptable_content_types.map(|v| v.into_iter().collect());
                let connection_attributes = connection_attributes
                    .map(|attrs| attrs.into_iter().map(|a| (a.key, a.value)).collect());
                let oid = self.connections.new_connection(NewConnectionParams {
                    client_id,
                    hostname: peer_addr,
                    local_port,
                    remote_port,
                    player: None,
                    acceptable_content_types,
                    connection_attributes,
                })?;
                let token = self.make_client_token(client_id);
                Ok(ClientReply::NewConnection {
                    client_token: token,
                    connection_obj: oid,
                })
            }

            ClientRequest::Reattach {
                client_token,
                auth_token,
                peer_addr: _,
                local_port: _,
                remote_port: _,
                acceptable_content_types: _,
                connection_attributes: _,
            } => {
                let connection = self.client_auth(client_token, client_id)?;
                let player = self.validate_auth_token(auth_token, None)?;
                let Some(current_player) = self.connections.player_object_for_client(client_id)
                else {
                    return Err(RpcMessageError::NoConnection);
                };
                if current_player != player {
                    return Err(RpcMessageError::PermissionDenied);
                }
                let _ = self
                    .connections
                    .record_client_activity(client_id, connection);
                let player_flags = scheduler_client.get_object_flags(&player).unwrap_or(0);
                Ok(ClientReply::AttachResult {
                    success: true,
                    client_token: Some(self.make_client_token(client_id)),
                    player: Some(player),
                    player_flags,
                })
            }

            ClientRequest::ClientPong { client_token, .. } => {
                let connection = self.client_auth(client_token, client_id)?;
                if self
                    .connections
                    .notify_is_alive(client_id, connection)
                    .is_err()
                {
                    warn!("Unable to notify connection is alive: {}", client_id);
                }
                let timestamp = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos() as u64;
                Ok(ClientReply::ThanksPong { timestamp })
            }

            ClientRequest::RequestSysProp {
                auth_token,
                object,
                property,
            } => {
                let player = match auth_token {
                    Some(auth_token) => self.validate_auth_token(auth_token, None)?,
                    None => SYSTEM_OBJECT,
                };
                self.request_sys_prop_typed(scheduler_client, player, object, property)
            }

            ClientRequest::LoginCommand {
                client_token,
                handler_object,
                connect_args,
                do_attach,
                event_log_pubkey,
                registration_data: _,
            } => {
                let connection = self.client_auth(client_token, client_id)?;
                self.perform_login_typed(
                    &handler_object,
                    scheduler_client,
                    client_id,
                    &connection,
                    connect_args,
                    do_attach,
                    event_log_pubkey,
                )
            }

            ClientRequest::Attach {
                auth_token,
                connect_type,
                handler_object,
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let acceptable_content_types =
                    acceptable_content_types.map(|v| v.into_iter().collect());
                self.connections.new_connection(NewConnectionParams {
                    client_id,
                    hostname: peer_addr,
                    local_port,
                    remote_port,
                    player: Some(player),
                    acceptable_content_types,
                    connection_attributes: None,
                })?;
                let client_token = self.make_client_token(client_id);
                if connect_type != ConnectType::NoConnect {
                    let connection = self
                        .connections
                        .connection_object_for_client(client_id)
                        .ok_or(RpcMessageError::InternalError(
                            "Connection not found".to_string(),
                        ))?;
                    let fb_connect_type = match connect_type {
                        ConnectType::Connected => moor_rpc::ConnectType::Connected,
                        ConnectType::Reconnected => moor_rpc::ConnectType::Reconnected,
                        ConnectType::Created => moor_rpc::ConnectType::Created,
                        ConnectType::NoConnect => moor_rpc::ConnectType::NoConnect,
                    };
                    if let Err(e) = self.submit_connected_task(
                        &handler_object,
                        scheduler_client.clone(),
                        client_id,
                        &player,
                        &connection,
                        fb_connect_type,
                    ) {
                        error!(error = ?e, "Error submitting user_connected task");
                    }
                }
                let player_flags = scheduler_client.get_object_flags(&player).unwrap_or(0);
                Ok(ClientReply::AttachResult {
                    success: true,
                    client_token: Some(client_token),
                    player: Some(player),
                    player_flags,
                })
            }

            ClientRequest::Command {
                client_token,
                auth_token,
                handler_object,
                command,
            } => {
                let (_connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                self.submit_command_task_typed(
                    scheduler_client,
                    client_id,
                    &handler_object,
                    &player,
                    command,
                )
            }

            ClientRequest::Detach {
                client_token,
                disconnected,
            } => {
                let connection = self.client_auth(client_token, client_id)?;
                if disconnected {
                    if let Some(player) = self.connections.player_object_for_client(client_id) {
                        let _ = self.connections.remove_client_connection(client_id);
                        match self.connections.client_ids_for(player) {
                            Ok(remaining) if remaining.is_empty() => {
                                if let Err(e) = self.submit_disconnected_task(
                                    &SYSTEM_OBJECT,
                                    scheduler_client,
                                    client_id,
                                    &player,
                                    &connection,
                                ) {
                                    error!(error = ?e, "Error submitting user_disconnected task");
                                }
                            }
                            Ok(_) => {}
                            Err(e) => {
                                error!(error = ?e, "Error checking remaining connections for player");
                            }
                        }
                    } else {
                        let _ = self.connections.remove_client_connection(client_id);
                    }
                } else {
                    let _ = self
                        .connections
                        .record_client_activity(client_id, connection);
                }
                Ok(ClientReply::Disconnected)
            }

            ClientRequest::RequestedInput {
                client_token,
                auth_token,
                request_id,
                input,
            } => {
                let (connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                let _ = self
                    .connections
                    .record_client_activity(client_id, connection);
                if let Err(e) = scheduler_client.submit_requested_input(&player, request_id, input)
                {
                    error!(error = ?e, "Error submitting requested input");
                    return Err(RpcMessageError::InternalError(e.to_string()));
                }
                Ok(ClientReply::InputThanks)
            }

            ClientRequest::OutOfBand {
                client_token,
                auth_token,
                handler_object,
                args,
                argstr,
            } => {
                let (connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                let session = Arc::new(RpcSession::new(
                    client_id,
                    connection,
                    self.event_log.clone(),
                    self.mailbox_sender.clone(),
                ));
                let args_list = match args.variant() {
                    Variant::List(l) => l.clone(),
                    _ => moor_var::List::from_iter(std::iter::once(args)),
                };
                let task_handle = match scheduler_client.submit_out_of_band_task(
                    &handler_object,
                    &player,
                    args_list,
                    argstr,
                    session,
                ) {
                    Ok(t) => t,
                    Err(e) => {
                        error!(error = ?e, "Error submitting command task");
                        return Err(RpcMessageError::InternalError(e.to_string()));
                    }
                };
                Ok(ClientReply::TaskSubmitted {
                    task_id: task_handle.task_id() as u64,
                })
            }

            ClientRequest::Eval {
                client_token,
                auth_token,
                expression,
            } => {
                let (connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                let session = Arc::new(RpcSession::new(
                    client_id,
                    connection,
                    self.event_log.clone(),
                    self.mailbox_sender.clone(),
                ));
                let task_handle = match scheduler_client.submit_eval_task(
                    &player,
                    &player,
                    expression,
                    None,
                    session,
                    self.config.features.clone(),
                ) {
                    Ok(t) => t,
                    Err(e) => {
                        error!(error = ?e, "Error submitting eval task");
                        return Err(RpcMessageError::TaskError(e));
                    }
                };
                use moor_kernel::tasks::TaskNotification;
                let receiver = task_handle.into_receiver();
                loop {
                    match receiver.recv() {
                        Ok((_, Ok(TaskNotification::Result(v)))) => {
                            break Ok(ClientReply::EvalResult { result: v });
                        }
                        Ok((_, Ok(TaskNotification::Suspended))) => continue,
                        Ok((_, Err(e))) => break Err(RpcMessageError::TaskError(e)),
                        Err(e) => {
                            error!(error = ?e, "Error processing eval");
                            break Err(RpcMessageError::InternalError(e.to_string()));
                        }
                    }
                }
            }

            ClientRequest::InvokeVerb {
                client_token,
                auth_token,
                object,
                verb,
                args,
            } => {
                let (connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                let session = Arc::new(RpcSession::new(
                    client_id,
                    connection,
                    self.event_log.clone(),
                    self.mailbox_sender.clone(),
                ));
                let task_handle = match scheduler_client.submit_verb_task(
                    &player,
                    &object,
                    verb,
                    moor_var::List::from_iter(args),
                    v_empty_str(),
                    &SYSTEM_OBJECT,
                    session,
                ) {
                    Ok(t) => t,
                    Err(e) => {
                        error!(error = ?e, "Error submitting verb task");
                        return Err(RpcMessageError::InternalError(e.to_string()));
                    }
                };
                let task_id = task_handle.task_id();
                if let Err(e) = self.task_monitor.add_task(task_id, client_id, task_handle) {
                    error!(error = ?e, "Error adding task to monitor");
                    return Err(RpcMessageError::InternalError(e.to_string()));
                }
                Ok(ClientReply::TaskSubmitted {
                    task_id: task_id as u64,
                })
            }

            ClientRequest::Retrieve {
                auth_token,
                object,
                entity_type,
                name,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                match entity_type {
                    EntityType::Property => {
                        let (propdef, propperms, value) = scheduler_client
                            .request_property(&player, &player, &object, name)
                            .map_err(|e| {
                                error!(error = ?e, "Error requesting property");
                                RpcMessageError::EntityRetrievalError(
                                    "error requesting property".to_string(),
                                )
                            })?;
                        Ok(ClientReply::PropertyValue {
                            prop_info: (propdef, propperms),
                            value,
                        })
                    }
                    EntityType::Verb => {
                        let (verbdef, code) = scheduler_client
                            .request_verb(&player, &player, &object, name)
                            .map_err(|e| {
                                error!(error = ?e, "Error requesting verb");
                                RpcMessageError::EntityRetrievalError(
                                    "error requesting verb".to_string(),
                                )
                            })?;
                        Ok(ClientReply::VerbValue {
                            verb_info: verbdef,
                            code,
                        })
                    }
                }
            }

            ClientRequest::Properties {
                auth_token,
                object,
                inherited,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let prop_list = scheduler_client
                    .request_properties(&player, &player, &object, inherited)
                    .map_err(|e| {
                        error!(error = ?e, "Error requesting properties");
                        RpcMessageError::EntityRetrievalError(
                            "error requesting properties".to_string(),
                        )
                    })?;
                Ok(ClientReply::PropertiesReply {
                    properties: prop_list.into_iter().collect(),
                })
            }

            ClientRequest::Verbs {
                auth_token,
                object,
                inherited,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let verb_list = scheduler_client
                    .request_verbs(&player, &player, &object, inherited)
                    .map_err(|e| {
                        error!(error = ?e, "Error requesting verbs");
                        RpcMessageError::EntityRetrievalError("error requesting verbs".to_string())
                    })?;
                Ok(ClientReply::VerbsReply {
                    verbs: verb_list.into_iter().collect(),
                })
            }

            ClientRequest::Resolve { auth_token, objref } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let resolved = scheduler_client
                    .resolve_object(player, objref)
                    .map_err(|e| {
                        error!(error = ?e, "Error resolving object");
                        RpcMessageError::EntityRetrievalError("error resolving object".to_string())
                    })?;
                Ok(ClientReply::ResolveResult { result: resolved })
            }

            ClientRequest::RequestHistory { auth_token, recall } => {
                let player = self.validate_auth_token(auth_token, None)?;
                self.build_history_response_typed(player, recall)
            }

            ClientRequest::RequestCurrentPresentations { auth_token } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let presentations = self.event_log.current_presentations(player);
                let snapshots = presentations
                    .into_iter()
                    .map(|p| rpc_common::api::PresentationSnapshot {
                        id: p.id,
                        encrypted_blob: p.encrypted_content,
                    })
                    .collect();
                Ok(ClientReply::CurrentPresentations {
                    presentations: snapshots,
                })
            }

            ClientRequest::DismissPresentation {
                auth_token,
                presentation_id,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                self.event_log.dismiss_presentation(player, presentation_id);
                Ok(ClientReply::PresentationDismissed)
            }

            ClientRequest::SetClientAttribute {
                client_token,
                auth_token,
                key,
                value,
            } => {
                let (_connection, _player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                self.connections
                    .set_client_attribute(client_id, key, value)?;
                Ok(ClientReply::ClientAttributeSet)
            }

            ClientRequest::Program {
                client_token,
                auth_token,
                object,
                verb,
                code,
            } => {
                let (_connection, player) =
                    self.verify_tokens(client_token, auth_token, client_id)?;
                self.program_verb_typed(scheduler_client, &player, &object, verb, code)
            }

            ClientRequest::GetEventLogPublicKey { auth_token } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let public_key = self.event_log.get_pubkey(player);
                Ok(ClientReply::EventLogPublicKey {
                    public_key: public_key.unwrap_or_default(),
                })
            }

            ClientRequest::SetEventLogPublicKey {
                auth_token,
                public_key,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                self.event_log.set_pubkey(player, public_key.clone());
                let public_key = self.event_log.get_pubkey(player);
                Ok(ClientReply::EventLogPublicKey {
                    public_key: public_key.unwrap_or_default(),
                })
            }

            ClientRequest::DeleteEventLogHistory { auth_token } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let success = match self.event_log.delete_all_events(player) {
                    Ok(_) => true,
                    Err(e) => {
                        error!(
                            "Failed to delete event history for player {:?}: {}",
                            player, e
                        );
                        false
                    }
                };
                Ok(ClientReply::EventLogHistoryDeleted { success })
            }

            ClientRequest::ListObjects { auth_token } => {
                let player = self.validate_auth_token(auth_token, None)?;
                let objects = scheduler_client.list_objects(&player).map_err(|e| {
                    error!(error = ?e, "Error listing objects");
                    RpcMessageError::EntityRetrievalError("error listing objects".to_string())
                })?;
                let object_infos = objects
                    .into_iter()
                    .map(|(obj, attrs, verbs_count, props_count)| ObjectInfo {
                        obj,
                        name: attrs.name().map(|n| Symbol::mk(&n)),
                        parent: attrs.parent(),
                        owner: attrs.owner().unwrap_or(obj),
                        flags: attrs.flags().to_u16(),
                        location: attrs.location(),
                        contents_count: 0,
                        verbs_count: verbs_count as u32,
                        properties_count: props_count as u32,
                    })
                    .collect();
                Ok(ClientReply::ListObjectsReply {
                    objects: object_infos,
                })
            }

            ClientRequest::UpdateProperty {
                auth_token,
                object,
                property,
                value,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                if value.type_code() == moor_var::VarType::TYPE_NONE {
                    return Err(RpcMessageError::InvalidRequest(
                        "Property values cannot be TYPE_NONE".to_string(),
                    ));
                }
                scheduler_client
                    .update_property(&player, &player, &object, property, value)
                    .map_err(|e| {
                        error!(error = ?e, "Error updating property");
                        RpcMessageError::EntityRetrievalError("error updating property".to_string())
                    })?;
                Ok(ClientReply::PropertyUpdated)
            }

            ClientRequest::InvokeSystemHandler {
                host_id: _,
                handler_type,
                args,
                auth_token,
            } => {
                let player = match auth_token {
                    Some(auth_token) => self.validate_auth_token(auth_token, None)?,
                    None => SYSTEM_OBJECT,
                };
                self.submit_invoke_system_handler_task_typed(
                    scheduler_client,
                    client_id,
                    &player,
                    handler_type,
                    args,
                )
            }

            ClientRequest::CallSystemVerb {
                auth_token,
                verb,
                args,
            } => {
                let player = match auth_token {
                    Some(auth_token) => self.validate_auth_token(auth_token, None)?,
                    None => SYSTEM_OBJECT,
                };
                self.submit_system_verb_task_typed(
                    scheduler_client,
                    client_id,
                    &player,
                    &ObjectRef::Id(SYSTEM_OBJECT),
                    verb,
                    args,
                )
            }

            ClientRequest::BatchWorldState {
                auth_token,
                actions,
                rollback,
            } => {
                let player = self.validate_auth_token(auth_token, None)?;
                self.handle_batch_world_state_typed(
                    scheduler_client,
                    client_id,
                    &player,
                    actions,
                    rollback,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helper methods for the typed path
// ---------------------------------------------------------------------------

impl RpcMessageHandler {
    fn request_sys_prop_typed(
        &self,
        scheduler_client: SchedulerClient,
        player: Obj,
        object: ObjectRef,
        property: Symbol,
    ) -> Result<ClientReply, RpcMessageError> {
        use moor_common::tasks::CommandError;
        use moor_common::tasks::SchedulerError::CommandExecutionError;
        let pv = match scheduler_client.request_system_property(&player, &object, property) {
            Ok(pv) => pv,
            Err(CommandExecutionError(CommandError::NoObjectMatch)) => {
                return Ok(ClientReply::SysPropValue { value: None });
            }
            Err(e) => {
                error!(error = ?e, "Error requesting system property");
                return Err(RpcMessageError::ErrorCouldNotRetrieveSysProp(
                    "error requesting system property".to_string(),
                ));
            }
        };
        Ok(ClientReply::SysPropValue { value: Some(pv) })
    }

    fn perform_login_typed(
        &self,
        handler_object: &Obj,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        connection: &Obj,
        args: Vec<String>,
        attach: bool,
        event_log_pubkey: Option<String>,
    ) -> Result<ClientReply, RpcMessageError> {
        use moor_kernel::tasks::TaskNotification;

        let connect_type = if args.first() == Some(&"create".to_string()) {
            ConnectType::Created
        } else {
            ConnectType::Connected
        };

        info!(
            "Performing {:?} login for client: {}",
            connect_type, client_id
        );
        let session = Arc::new(RpcSession::new(
            client_id,
            *connection,
            self.event_log.clone(),
            self.mailbox_sender.clone(),
        ));
        let task_handle = match scheduler_client.submit_verb_task(
            connection,
            &ObjectRef::Id(*handler_object),
            *DO_LOGIN_COMMAND,
            args.iter().map(|s| v_str(s)).collect(),
            v_string(args.join(" ")),
            &SYSTEM_OBJECT,
            session,
        ) {
            Ok(t) => t,
            Err(e) => {
                error!(error = ?e, "Error submitting login task");
                return Err(RpcMessageError::InternalError(e.to_string()));
            }
        };
        let receiver = task_handle.into_receiver();
        let player = loop {
            match receiver.recv() {
                Ok((_, Ok(TaskNotification::Result(v)))) => match v.variant() {
                    Variant::Obj(o) => break o,
                    _ => {
                        return Ok(ClientReply::LoginResult {
                            success: false,
                            auth_token: None,
                            connect_type: ConnectType::Connected,
                            player: None,
                            player_flags: 0,
                        });
                    }
                },
                Ok((_, Ok(TaskNotification::Suspended))) => continue,
                Ok((_, Err(e))) => {
                    error!(error = ?e, "Error waiting for login results");
                    return Err(RpcMessageError::LoginTaskFailed(e.to_string()));
                }
                Err(e) => {
                    error!(error = ?e, "Error waiting for login results");
                    return Err(RpcMessageError::InternalError(e.to_string()));
                }
            }
        };

        let Ok(_) = self
            .connections
            .associate_player_object(*connection, player)
        else {
            return Err(RpcMessageError::InternalError(
                "Unable to update client connection".to_string(),
            ));
        };

        if let Some(pubkey) = event_log_pubkey {
            self.event_log.set_pubkey(player, pubkey);
        }

        if attach {
            let fb_connect_type = match connect_type {
                ConnectType::Connected => moor_rpc::ConnectType::Connected,
                ConnectType::Reconnected => moor_rpc::ConnectType::Reconnected,
                ConnectType::Created => moor_rpc::ConnectType::Created,
                ConnectType::NoConnect => moor_rpc::ConnectType::NoConnect,
            };
            if let Err(e) = self.submit_connected_task(
                handler_object,
                scheduler_client.clone(),
                client_id,
                &player,
                connection,
                fb_connect_type,
            ) {
                error!(error = ?e, "Error submitting user_connected task");
            }
        }

        let auth_token = self.make_auth_token(&player);
        let player_flags = scheduler_client.get_object_flags(&player).unwrap_or(0);

        Ok(ClientReply::LoginResult {
            success: true,
            auth_token: Some(auth_token),
            connect_type,
            player: Some(player),
            player_flags,
        })
    }

    fn submit_command_task_typed(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        handler_object: &Obj,
        player: &Obj,
        command: String,
    ) -> Result<ClientReply, RpcMessageError> {
        let connection = self
            .connections
            .connection_object_for_client(client_id)
            .ok_or(RpcMessageError::InternalError(
                "Connection not found".to_string(),
            ))?;

        let session = Arc::new(RpcSession::new(
            client_id,
            connection,
            self.event_log.clone(),
            self.mailbox_sender.clone(),
        ));

        if let Err(e) = self
            .connections
            .record_client_activity(client_id, connection)
        {
            warn!("Unable to update client connection activity: {}", e);
        }

        let parse_command_task_handle = match scheduler_client.submit_command_task(
            handler_object,
            player,
            command.as_str(),
            session,
        ) {
            Ok(t) => t,
            Err(e) => return Err(RpcMessageError::TaskError(e)),
        };

        let task_id = parse_command_task_handle.task_id();
        if let Err(e) = self
            .task_monitor
            .add_task(task_id, client_id, parse_command_task_handle)
        {
            error!(error = ?e, "Error adding task to monitor");
        }
        Ok(ClientReply::TaskSubmitted {
            task_id: task_id as u64,
        })
    }

    fn program_verb_typed(
        &self,
        scheduler_client: SchedulerClient,
        player: &Obj,
        object: &ObjectRef,
        verb: Symbol,
        code: Vec<String>,
    ) -> Result<ClientReply, RpcMessageError> {
        match scheduler_client.submit_verb_program(player, player, object, verb, code) {
            Ok((obj, verb_name)) => Ok(ClientReply::VerbProgramResponseReply {
                response: VerbProgramResponse::Success {
                    obj,
                    verb_name: verb_name.to_string(),
                },
            }),
            Err(moor_common::tasks::SchedulerError::VerbProgramFailed(f)) => {
                Ok(ClientReply::VerbProgramResponseReply {
                    response: VerbProgramResponse::Failure {
                        error: moor_common::tasks::SchedulerError::VerbProgramFailed(f),
                    },
                })
            }
            Err(e) => Err(RpcMessageError::TaskError(e)),
        }
    }

    fn submit_invoke_system_handler_task_typed(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        player: &Obj,
        handler_type: String,
        args: Vec<Var>,
    ) -> Result<ClientReply, RpcMessageError> {
        use moor_kernel::tasks::TaskNotification;

        let connection = self
            .connections
            .connection_object_for_client(client_id)
            .ok_or(RpcMessageError::InternalError(
                "Connection not found".to_string(),
            ))?;

        let session = Arc::new(RpcSession::new(
            client_id,
            connection,
            self.event_log.clone(),
            self.mailbox_sender.clone(),
        ));

        let task_handle = match scheduler_client.submit_system_handler_task(
            player,
            handler_type,
            args,
            session,
        ) {
            Ok(t) => t,
            Err(e) => {
                error!(error = ?e, "Error submitting system handler task");
                return Err(RpcMessageError::InternalError(e.to_string()));
            }
        };

        let receiver = task_handle.into_receiver();
        loop {
            match receiver.recv() {
                Ok((_, Ok(TaskNotification::Result(v)))) => {
                    break Ok(ClientReply::SystemHandlerResponseReply {
                        response: rpc_common::api::SystemHandlerResponse::Success { result: v },
                    });
                }
                Ok((_, Ok(TaskNotification::Suspended))) => continue,
                Ok((_, Err(e))) => {
                    break Ok(ClientReply::SystemHandlerResponseReply {
                        response: rpc_common::api::SystemHandlerResponse::Error { error: e },
                    });
                }
                Err(e) => {
                    error!(error = ?e, "Error processing system handler task");
                    break Err(RpcMessageError::InternalError(e.to_string()));
                }
            }
        }
    }

    fn submit_system_verb_task_typed(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        player: &Obj,
        object: &ObjectRef,
        verb: Symbol,
        args: Vec<Var>,
    ) -> Result<ClientReply, RpcMessageError> {
        use crate::rpc::output_capture_session::OutputCaptureSession;
        use moor_kernel::tasks::TaskNotification;

        let session = Arc::new(OutputCaptureSession::new(client_id, *player));

        let task_handle = match scheduler_client.submit_verb_task(
            player,
            object,
            verb,
            moor_var::List::from_iter(args),
            v_empty_str(),
            &SYSTEM_OBJECT,
            session.clone(),
        ) {
            Ok(t) => t,
            Err(e) => {
                error!(error = ?e, "Error submitting system verb task");
                return Err(RpcMessageError::InternalError(e.to_string()));
            }
        };

        let receiver = task_handle.into_receiver();
        loop {
            match receiver.recv() {
                Ok((_, Ok(TaskNotification::Result(v)))) => {
                    let captured_events = session.take_captured_events();
                    let output: Vec<moor_common::tasks::NarrativeEvent> = captured_events
                        .into_iter()
                        .map(|(_, event)| *event)
                        .collect();
                    break Ok(ClientReply::VerbCallResponse {
                        response: VerbCallResponse::Success { result: v, output },
                    });
                }
                Ok((_, Ok(TaskNotification::Suspended))) => continue,
                Ok((_, Err(e))) => {
                    break Ok(ClientReply::VerbCallResponse {
                        response: VerbCallResponse::Error { error: e },
                    });
                }
                Err(e) => {
                    break Err(RpcMessageError::InternalError(e.to_string()));
                }
            }
        }
    }

    fn build_history_response_typed(
        &self,
        player: Obj,
        recall: rpc_common::api::HistoryRecall,
    ) -> Result<ClientReply, RpcMessageError> {
        use std::time::{Duration, SystemTime, UNIX_EPOCH};

        let (events, total_events_available, has_more_before) = match recall {
            rpc_common::api::HistoryRecall::SinceEvent { event_id, limit } => {
                let all_events = self
                    .event_log
                    .events_for_player_since(player, Some(event_id));
                let total_available = all_events.len();
                let has_more = limit.is_some_and(|l| total_available > l);
                let events = if let Some(limit) = limit {
                    all_events.into_iter().take(limit).collect()
                } else {
                    all_events
                };
                (events, total_available, has_more)
            }
            rpc_common::api::HistoryRecall::UntilEvent { event_id, limit } => {
                let all_events = self
                    .event_log
                    .events_for_player_until(player, Some(event_id));
                let total_available = all_events.len();
                let has_more = limit.is_some_and(|l| total_available > l);
                let events = if let Some(limit) = limit {
                    let len = all_events.len();
                    if len > limit {
                        all_events.into_iter().skip(len - limit).collect()
                    } else {
                        all_events
                    }
                } else {
                    all_events
                };
                (events, total_available, has_more)
            }
            rpc_common::api::HistoryRecall::SinceSeconds { seconds_ago, limit } => {
                let all_events = self
                    .event_log
                    .events_for_player_since_seconds(player, seconds_ago);
                let total_available = all_events.len();
                let has_more = limit.is_some_and(|l| total_available > l);
                let events = if let Some(limit) = limit {
                    let len = all_events.len();
                    if len > limit {
                        all_events.into_iter().skip(len - limit).collect()
                    } else {
                        all_events
                    }
                } else {
                    all_events
                };
                (events, total_available, has_more)
            }
            rpc_common::api::HistoryRecall::None => (Vec::new(), 0, false),
        };

        let (earliest_time, latest_time) = if events.is_empty() {
            (SystemTime::now(), SystemTime::now())
        } else {
            (
                UNIX_EPOCH + Duration::from_nanos(events.first().unwrap().timestamp),
                UNIX_EPOCH + Duration::from_nanos(events.last().unwrap().timestamp),
            )
        };

        let (earliest_event_id, latest_event_id) = if events.is_empty() {
            (None, None)
        } else {
            let mut event_ids: Vec<_> = events
                .iter()
                .map(|e| {
                    let uuid_bytes = e.event_id.data.as_slice();
                    if uuid_bytes.len() == 16 {
                        let mut bytes = [0u8; 16];
                        bytes.copy_from_slice(uuid_bytes);
                        Uuid::from_bytes(bytes)
                    } else {
                        Uuid::nil()
                    }
                })
                .collect();
            event_ids.sort();
            (Some(event_ids[0]), Some(event_ids[event_ids.len() - 1]))
        };

        let typed_events = events
            .into_iter()
            .map(|e| {
                let event_id_bytes = e.event_id.data.as_slice();
                let event_id = if event_id_bytes.len() == 16 {
                    let mut bytes = [0u8; 16];
                    bytes.copy_from_slice(event_id_bytes);
                    Uuid::from_bytes(bytes)
                } else {
                    Uuid::nil()
                };
                let player = moor_schema::convert::obj_from_flatbuffer_struct(&e.player)
                    .unwrap_or(SYSTEM_OBJECT);
                rpc_common::api::HistoricalNarrativeEvent {
                    event_id,
                    timestamp: e.timestamp,
                    player,
                    encrypted_blob: e.encrypted_blob,
                }
            })
            .collect();

        let time_range_start = earliest_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64;
        let time_range_end = latest_time
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64;

        Ok(ClientReply::HistoryResponseReply {
            response: rpc_common::api::HistoryResponse {
                events: typed_events,
                time_range_start,
                time_range_end,
                total_events: total_events_available as u64,
                has_more_before,
                earliest_event_id,
                latest_event_id,
            },
        })
    }

    fn handle_batch_world_state_typed(
        &self,
        scheduler_client: SchedulerClient,
        client_id: Uuid,
        player: &Obj,
        actions: Vec<rpc_common::api::BatchActionEntry>,
        rollback: bool,
    ) -> Result<ClientReply, RpcMessageError> {
        use crate::rpc::output_capture_session::OutputCaptureSession;
        use moor_kernel::tasks::TaskNotification;
        use moor_kernel::tasks::world_state_action::WorldStateAction;

        let correlation_ids: Vec<String> = actions.iter().map(|a| a.id.clone()).collect();

        let kernel_actions: Vec<WorldStateAction> = actions
            .into_iter()
            .map(|entry| convert_batch_action_to_kernel(*player, entry.action))
            .collect();

        let session = Arc::new(OutputCaptureSession::new(client_id, *player));

        let (task_handle, result_sink) = scheduler_client
            .submit_batch_world_state_task(player, player, kernel_actions, rollback, session)
            .map_err(|e| {
                error!(error = ?e, "Error submitting batch world state task");
                RpcMessageError::TaskError(e)
            })?;

        let receiver = task_handle.into_receiver();
        loop {
            match receiver.recv() {
                Ok((_, Ok(TaskNotification::Result(_)))) => {
                    let results = result_sink.lock().unwrap().take().unwrap_or_else(|| {
                        Err(moor_common::tasks::SchedulerError::SchedulerNotResponding)
                    });

                    match results {
                        Ok(ws_results) => {
                            let result_entries: Vec<WorldStateResultEntry> = correlation_ids
                                .into_iter()
                                .zip(ws_results)
                                .map(|(id, result)| {
                                    let typed_result = convert_kernel_ws_result_to_typed(result);
                                    WorldStateResultEntry {
                                        id,
                                        result: typed_result,
                                    }
                                })
                                .collect();
                            break Ok(ClientReply::BatchWorldStateReply {
                                results: result_entries,
                            });
                        }
                        Err(e) => break Err(RpcMessageError::TaskError(e)),
                    }
                }
                Ok((_, Ok(TaskNotification::Suspended))) => continue,
                Ok((_, Err(e))) => break Err(RpcMessageError::TaskError(e)),
                Err(e) => {
                    error!(error = ?e, "Error processing batch world state task");
                    break Err(RpcMessageError::InternalError(e.to_string()));
                }
            }
        }
    }

    /// Extract and verify both client token and auth token from a typed request.
    /// Returns (connection_obj, player).
    fn verify_tokens(
        &self,
        client_token: ClientToken,
        auth_token: AuthToken,
        client_id: Uuid,
    ) -> Result<(Obj, Obj), RpcMessageError> {
        let connection = self.client_auth(client_token, client_id)?;
        let player = self.validate_auth_token(auth_token, None)?;
        let Some(logged_in_player) = self.connections.player_object_for_client(client_id) else {
            return Err(RpcMessageError::PermissionDenied);
        };
        if player != logged_in_player {
            return Err(RpcMessageError::PermissionDenied);
        }
        Ok((connection, player))
    }
}

/// Convert a kernel WorldStateResult to the typed API equivalent.
/// player/authority_principal from the auth token.
fn convert_batch_action_to_kernel(
    player: Obj,
    action: rpc_common::api::BatchAction,
) -> moor_kernel::tasks::world_state_action::WorldStateAction {
    use moor_common::model::ObjectQuery;
    use moor_common::util::BitEnum;
    use moor_kernel::tasks::world_state_action::WorldStateAction;

    match action {
        rpc_common::api::BatchAction::RequestProperty { obj, property } => {
            WorldStateAction::RequestProperty {
                player,
                authority_principal: player,
                obj,
                property,
            }
        }
        rpc_common::api::BatchAction::RequestProperties { obj, inherited } => {
            WorldStateAction::RequestProperties {
                player,
                authority_principal: player,
                obj,
                inherited,
            }
        }
        rpc_common::api::BatchAction::RequestSystemProperty { obj, property } => {
            WorldStateAction::RequestSystemProperty {
                player,
                obj,
                property,
            }
        }
        rpc_common::api::BatchAction::RequestVerbs { obj, inherited } => {
            WorldStateAction::RequestVerbs {
                player,
                authority_principal: player,
                obj,
                inherited,
            }
        }
        rpc_common::api::BatchAction::RequestVerbCode { obj, verb } => {
            WorldStateAction::RequestVerbCode {
                player,
                authority_principal: player,
                obj,
                verb,
            }
        }
        rpc_common::api::BatchAction::ResolveObject { objref } => WorldStateAction::ResolveObject {
            player,
            obj: objref,
        },
        rpc_common::api::BatchAction::ListObjects => WorldStateAction::ListObjects { player },
        rpc_common::api::BatchAction::RequestAllObjects => {
            WorldStateAction::RequestAllObjects { player }
        }
        rpc_common::api::BatchAction::UpdateProperty {
            obj,
            property,
            value,
        } => WorldStateAction::UpdateProperty {
            player,
            authority_principal: player,
            obj,
            property,
            value,
        },
        rpc_common::api::BatchAction::ProgramVerb {
            obj,
            verb_name,
            code,
        } => WorldStateAction::ProgramVerb {
            player,
            authority_principal: player,
            obj,
            verb_name,
            code,
        },
        rpc_common::api::BatchAction::GetObjectFlags { obj } => {
            WorldStateAction::GetObjectFlags { obj }
        }
        rpc_common::api::BatchAction::QueryObjects {
            parent,
            location,
            owner,
            flags_all,
            flags_any,
        } => WorldStateAction::QueryObjects {
            player,
            query: ObjectQuery {
                parent,
                location,
                owner,
                flags_all: if flags_all != 0 {
                    Some(BitEnum::from_u16(flags_all))
                } else {
                    None
                },
                flags_any: if flags_any != 0 {
                    Some(BitEnum::from_u16(flags_any))
                } else {
                    None
                },
            },
        },
    }
}

/// Convert a kernel WorldStateResult to the typed API equivalent.
fn convert_kernel_ws_result_to_typed(
    result: moor_kernel::tasks::world_state_action::WorldStateResult,
) -> WorldStateResult {
    use moor_kernel::tasks::world_state_action::WorldStateResult as R;

    match result {
        R::Property(propdef, propperms, value) => {
            WorldStateResult::Property(propdef, propperms, value)
        }
        R::Properties(props) => WorldStateResult::Properties(props.into_iter().collect()),
        R::SystemProperty(value) => WorldStateResult::SystemProperty(value),
        R::Verbs(verb_defs) => WorldStateResult::Verbs(verb_defs),
        R::VerbCode(verbdef, code) => WorldStateResult::VerbCode(verbdef, code),
        R::VerbProgrammed { object: _, verb: _ } => {
            // The kernel has a VerbProgrammed variant that doesn't map to the typed API;
            // encode it as a generic success via PropertyUpdated for now.
            // TODO: add a WorldStateResult::VerbProgrammed variant to the typed API if needed.
            WorldStateResult::PropertyUpdated
        }
        R::ResolvedObject(value) => WorldStateResult::ResolvedObject(value),
        R::ObjectsList(objects) => {
            let object_infos = objects
                .into_iter()
                .map(|(obj, attrs, verbs_count, props_count)| ObjectInfo {
                    obj,
                    name: attrs.name().map(|n| Symbol::mk(&n)),
                    parent: attrs.parent(),
                    owner: attrs.owner().unwrap_or(obj),
                    flags: attrs.flags().to_u16(),
                    location: attrs.location(),
                    contents_count: 0,
                    verbs_count: verbs_count as u32,
                    properties_count: props_count as u32,
                })
                .collect();
            WorldStateResult::ObjectsList(object_infos)
        }
        R::AllObjects(objects) => WorldStateResult::AllObjects(objects),
        R::PropertyUpdated => WorldStateResult::PropertyUpdated,
        R::ObjectFlags(flags) => WorldStateResult::ObjectFlags(flags),
        R::QueriedObjects(objects) => WorldStateResult::QueriedObjects(objects),
    }
}
