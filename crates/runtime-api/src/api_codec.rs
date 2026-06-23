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

//! Conversion functions between typed [`crate::api`] enums and FlatBuffer
//! wire structs. This is the only place that should know both the typed shapes
//! and the FlatBuffer shapes — keeping the boundary clean.

use std::net::SocketAddr;

use crate::api::{
    self, BatchAction, BatchActionEntry, BroadcastEvent, ClientEvent, ClientReply, ClientRequest,
    ConnectType, EntityType, HostBroadcastEvent, HostReply, HostRequest, ListenerInfo,
};
use crate::{
    AuthToken, HostType, RpcErr, RpcError, RpcMessageError, auth_token_fb, auth_token_from_ref,
    client_token_from_ref, extract_field_rpc, extract_host_type, extract_obj, extract_obj_rpc,
    extract_object_ref_rpc, extract_string_list_rpc, extract_string_rpc, extract_symbol,
    extract_symbol_rpc, extract_uuid_rpc, extract_var, extract_var_rpc,
    mk_client_attribute_set_reply, mk_daemon_to_host_ack, mk_disconnected_reply,
    mk_new_connection_reply, mk_presentation_dismissed_reply, mk_thanks_pong_reply, obj_fb,
    scheduler_error_from_ref, scheduler_error_to_flatbuffer_struct, uuid_fb, var_to_flatbuffer_rpc,
    verb_program_error_to_flatbuffer_struct,
};
use moor_common::model::{Named, ValSet};
use moor_schema::{common, convert, rpc as moor_rpc};
use moor_var::{Symbol, Var};
use planus::ReadAsRoot;

// ===========================================================================
// Host-side decode: FlatBuffer ref → typed HostRequest
// ===========================================================================

pub fn decode_host_request(
    message: moor_rpc::HostToDaemonMessageRef<'_>,
) -> Result<HostRequest, RpcMessageError> {
    match message.message().map_err(|e| {
        RpcMessageError::InvalidRequest(format!("missing host message union: {e:?}"))
    })? {
        moor_rpc::HostToDaemonMessageUnionRef::RegisterHost(reg) => {
            let host_type = extract_host_type(&reg, "host_type", |r| r.host_type())?;
            let listeners = decode_listeners(reg.listeners().ok());
            let timestamp = reg.timestamp().unwrap_or(0);
            Ok(HostRequest::RegisterHost {
                timestamp,
                host_type,
                listeners,
            })
        }
        moor_rpc::HostToDaemonMessageUnionRef::HostPong(pong) => {
            let host_type = extract_host_type(&pong, "host_type", |p| p.host_type())?;
            let listeners = decode_listeners(pong.listeners().ok());
            let timestamp = pong.timestamp().unwrap_or(0);
            Ok(HostRequest::HostPong {
                timestamp,
                host_type,
                listeners,
            })
        }
        moor_rpc::HostToDaemonMessageUnionRef::DetachHost(_) => Ok(HostRequest::DetachHost),
        moor_rpc::HostToDaemonMessageUnionRef::RequestPerformanceCounters(_) => {
            Ok(HostRequest::RequestPerformanceCounters)
        }
        moor_rpc::HostToDaemonMessageUnionRef::GetServerFeatures(_) => {
            Ok(HostRequest::GetServerFeatures)
        }
    }
}

fn decode_listeners<'a>(
    listeners: Option<planus::Vector<'a, ::planus::Result<moor_rpc::ListenerRef<'a>>>>,
) -> Vec<ListenerInfo> {
    listeners
        .map(|ls| {
            ls.iter()
                .filter_map(|l| {
                    let l = l.ok()?;
                    let obj = convert::obj_from_ref(l.handler_object().ok()?).ok()?;
                    let addr_str = l.socket_addr().ok()?;
                    let socket_addr: SocketAddr = addr_str.parse().ok()?;
                    Some(ListenerInfo {
                        handler_object: obj,
                        socket_addr,
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

// ===========================================================================
// Host-side encode: typed HostReply → FlatBuffer DaemonToHostReply
// ===========================================================================

pub fn encode_host_reply(reply: HostReply) -> moor_rpc::DaemonToHostReply {
    match reply {
        HostReply::Ack => mk_daemon_to_host_ack(),
        HostReply::Reject { reason } => moor_rpc::DaemonToHostReply {
            reply: moor_rpc::DaemonToHostReplyUnion::DaemonToHostReject(Box::new(
                moor_rpc::DaemonToHostReject { reason },
            )),
        },
        HostReply::PerformanceCounters {
            timestamp,
            counters,
        } => {
            let counters_fb: Vec<moor_rpc::CounterCategory> = counters
                .into_iter()
                .map(|cat| {
                    let counters: Vec<moor_rpc::Counter> = cat
                        .counters
                        .into_iter()
                        .map(|c| moor_rpc::Counter {
                            name: Box::new(moor_rpc::Symbol {
                                value: c.name.as_string(),
                            }),
                            count: c.count,
                            total_cumulative_ns: c.total_cumulative_ns,
                        })
                        .collect();
                    moor_rpc::CounterCategory {
                        category: Box::new(moor_rpc::Symbol {
                            value: cat.category.as_string(),
                        }),
                        counters,
                    }
                })
                .collect();
            moor_rpc::DaemonToHostReply {
                reply: moor_rpc::DaemonToHostReplyUnion::DaemonToHostPerfCounters(Box::new(
                    moor_rpc::DaemonToHostPerfCounters {
                        timestamp,
                        counters: counters_fb,
                    },
                )),
            }
        }
        HostReply::ServerFeatures(features) => moor_rpc::DaemonToHostReply {
            reply: moor_rpc::DaemonToHostReplyUnion::ServerFeatures(Box::new(
                moor_rpc::ServerFeatures {
                    persistent_tasks: features.persistent_tasks,
                    rich_notify: features.rich_notify,
                    lexical_scopes: features.lexical_scopes,
                    type_dispatch: features.type_dispatch,
                    flyweight_type: features.flyweight_type,
                    list_comprehensions: features.list_comprehensions,
                    bool_type: features.bool_type,
                    use_boolean_returns: features.use_boolean_returns,
                    symbol_type: features.symbol_type,
                    use_symbols_in_builtins: features.use_symbols_in_builtins,
                    custom_errors: features.custom_errors,
                    use_uuobjids: features.use_uuobjids,
                    enable_eventlog: features.enable_eventlog,
                    anonymous_objects: features.anonymous_objects,
                },
            )),
        },
    }
}

pub fn encode_host_success_bytes(reply: HostReply) -> Vec<u8> {
    let reply = encode_host_reply(reply);
    let reply_result = moor_rpc::ReplyResult {
        result: moor_rpc::ReplyResultUnion::HostSuccess(Box::new(moor_rpc::HostSuccess {
            reply: Box::new(reply),
        })),
    };
    let mut builder = planus::Builder::new();
    builder.finish(&reply_result, None).to_vec()
}

// ===========================================================================
// Event decode: FlatBuffer refs -> typed event enums
// ===========================================================================

pub fn decode_client_event_ref(
    event: moor_rpc::ClientEventRef<'_>,
) -> Result<ClientEvent, RpcError> {
    let event = event
        .event()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing client event union: {e}")))?;

    match event {
        moor_rpc::ClientEventUnionRef::NarrativeEventMessage(narrative) => {
            let player = extract_obj(&narrative, "player", |n| n.player())
                .map_err(RpcError::CouldNotDecode)?;
            let event_ref = narrative
                .event()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing narrative event: {e}")))?;
            let event = convert::narrative_event_from_ref(event_ref).map_err(|e| {
                RpcError::CouldNotDecode(format!("Failed to decode narrative event: {e}"))
            })?;
            Ok(ClientEvent::Narrative { player, event })
        }
        moor_rpc::ClientEventUnionRef::RequestInputEvent(input) => {
            let request_id = input
                .request_id()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing request_id: {e}")))
                .and_then(|r| {
                    convert::uuid_from_ref(r)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid request_id: {e}")))
                })?;
            let metadata = decode_metadata(input.metadata().ok().flatten())?;
            Ok(ClientEvent::RequestInput {
                request_id,
                metadata,
            })
        }
        moor_rpc::ClientEventUnionRef::SystemMessageEvent(system) => {
            let player =
                extract_obj(&system, "player", |s| s.player()).map_err(RpcError::CouldNotDecode)?;
            let message = system
                .message()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing system message: {e}")))?
                .to_string();
            Ok(ClientEvent::SystemMessage { player, message })
        }
        moor_rpc::ClientEventUnionRef::DisconnectEvent(_) => Ok(ClientEvent::Disconnect),
        moor_rpc::ClientEventUnionRef::TaskErrorEvent(task_error) => {
            let task_id = task_error.task_id().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing task error task_id: {e}"))
            })?;
            let error_ref = task_error
                .error()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing task error: {e}")))?;
            let error = scheduler_error_from_ref(error_ref).map_err(|e| {
                RpcError::CouldNotDecode(format!("Failed to decode scheduler error: {e}"))
            })?;
            Ok(ClientEvent::TaskError { task_id, error })
        }
        moor_rpc::ClientEventUnionRef::TaskSuccessEvent(task_success) => {
            let task_id = task_success.task_id().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing task success task_id: {e}"))
            })?;
            let result = extract_var(&task_success, "result", |t| t.result())
                .map_err(RpcError::CouldNotDecode)?;
            Ok(ClientEvent::TaskSuccess { task_id, result })
        }
        moor_rpc::ClientEventUnionRef::TaskSuspendedEvent(task_suspended) => {
            let task_id = task_suspended.task_id().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing task suspended task_id: {e}"))
            })?;
            Ok(ClientEvent::TaskSuspended { task_id })
        }
        moor_rpc::ClientEventUnionRef::PlayerSwitchedEvent(switch) => {
            let new_player = extract_obj(&switch, "new_player", |s| s.new_player())
                .map_err(RpcError::CouldNotDecode)?;
            let new_auth_token = switch
                .new_auth_token()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing new_auth_token: {e}")))
                .and_then(|t| auth_token_from_ref(t).map_err(RpcError::CouldNotDecode))?;
            Ok(ClientEvent::PlayerSwitched {
                new_player,
                new_auth_token,
            })
        }
        moor_rpc::ClientEventUnionRef::SetConnectionOptionEvent(set_opt) => {
            let connection_obj = extract_obj(&set_opt, "connection_obj", |s| s.connection_obj())
                .map_err(RpcError::CouldNotDecode)?;
            let option_name = extract_symbol(&set_opt, "option_name", |s| s.option_name())
                .map_err(RpcError::CouldNotDecode)?;
            let value =
                extract_var(&set_opt, "value", |s| s.value()).map_err(RpcError::CouldNotDecode)?;
            Ok(ClientEvent::SetConnectionOption {
                connection_obj,
                option_name,
                value,
            })
        }
        moor_rpc::ClientEventUnionRef::CredentialsUpdatedEvent(credentials) => {
            let client_id = credentials
                .client_id()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing client_id: {e}")))
                .and_then(|r| {
                    convert::uuid_from_ref(r)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid client_id: {e}")))
                })?;
            let client_token = credentials
                .client_token()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing client_token: {e}")))
                .and_then(|t| client_token_from_ref(t).map_err(RpcError::CouldNotDecode))?;
            Ok(ClientEvent::CredentialsUpdated {
                client_id,
                client_token,
            })
        }
    }
}

pub fn decode_broadcast_event_ref(
    event: moor_rpc::ClientsBroadcastEventRef<'_>,
) -> Result<BroadcastEvent, RpcError> {
    match event
        .event()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing broadcast event union: {e}")))?
    {
        moor_rpc::ClientsBroadcastEventUnionRef::ClientsBroadcastPingPong(_) => {
            Ok(BroadcastEvent::PingPong)
        }
    }
}

pub fn decode_host_broadcast_event_ref(
    event: moor_rpc::HostBroadcastEventRef<'_>,
) -> Result<HostBroadcastEvent, RpcError> {
    match event
        .event()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing host event union: {e}")))?
    {
        moor_rpc::HostBroadcastEventUnionRef::HostBroadcastListen(listen) => {
            let handler_object = extract_obj(&listen, "handler_object", |l| l.handler_object())
                .map_err(RpcError::CouldNotDecode)?;
            let host_type = match listen
                .host_type()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing host_type: {e}")))?
            {
                moor_rpc::HostType::Tcp => HostType::TCP,
                moor_rpc::HostType::WebSocket => HostType::WebSocket,
            };
            let port = listen
                .port()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing port: {e}")))?;
            let options = decode_var_map_options(listen.options().ok().flatten())?;
            Ok(HostBroadcastEvent::Listen {
                handler_object,
                host_type,
                port,
                options,
            })
        }
        moor_rpc::HostBroadcastEventUnionRef::HostBroadcastUnlisten(unlisten) => {
            let host_type = match unlisten
                .host_type()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing host_type: {e}")))?
            {
                moor_rpc::HostType::Tcp => HostType::TCP,
                moor_rpc::HostType::WebSocket => HostType::WebSocket,
            };
            let port = unlisten
                .port()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing port: {e}")))?;
            Ok(HostBroadcastEvent::Unlisten { host_type, port })
        }
        moor_rpc::HostBroadcastEventUnionRef::HostBroadcastPingPong(_) => {
            Ok(HostBroadcastEvent::PingPong)
        }
    }
}

fn decode_metadata<'a>(
    metadata: Option<planus::Vector<'a, planus::Result<moor_rpc::MetadataPairRef<'a>>>>,
) -> Result<Vec<(Symbol, Var)>, RpcError> {
    let Some(metadata) = metadata else {
        return Ok(Vec::new());
    };

    let mut result = Vec::with_capacity(metadata.len());
    for pair in metadata {
        let pair = pair.map_err(|e| RpcError::CouldNotDecode(format!("Invalid metadata: {e}")))?;
        let key = extract_symbol(&pair, "key", |p| p.key()).map_err(RpcError::CouldNotDecode)?;
        let value = extract_var(&pair, "value", |p| p.value()).map_err(RpcError::CouldNotDecode)?;
        result.push((key, value));
    }
    Ok(result)
}

fn decode_var_map_options<'a>(
    options: Option<planus::Vector<'a, planus::Result<moor_schema::var::VarMapPairRef<'a>>>>,
) -> Result<Vec<(Symbol, Var)>, RpcError> {
    let Some(options) = options else {
        return Ok(Vec::new());
    };

    let mut result = Vec::with_capacity(options.len());
    for pair in options {
        let pair = pair.map_err(|e| RpcError::CouldNotDecode(format!("Invalid option: {e}")))?;
        let key = pair
            .key()
            .map_err(|e| RpcError::CouldNotDecode(format!("Missing option key: {e}")))?;
        let key = convert::var_from_flatbuffer_ref(key)
            .map_err(|e| RpcError::CouldNotDecode(format!("Failed to decode option key: {e}")))?;
        let key = if let Ok(symbol) = key.as_symbol() {
            symbol
        } else if let Some(string) = key.as_string() {
            Symbol::mk(string)
        } else {
            return Err(RpcError::CouldNotDecode(
                "Host option key must be a symbol or string".to_string(),
            ));
        };
        let value = pair
            .value()
            .map_err(|e| RpcError::CouldNotDecode(format!("Missing option value: {e}")))
            .and_then(|v| {
                convert::var_from_flatbuffer_ref(v).map_err(|e| {
                    RpcError::CouldNotDecode(format!("Failed to decode option value: {e}"))
                })
            })?;
        result.push((key, value));
    }
    Ok(result)
}

// ===========================================================================
// Client-side decode: FlatBuffer ref → typed ClientRequest
// ===========================================================================

pub fn decode_client_request(
    message: moor_rpc::HostClientToDaemonMessageRef<'_>,
) -> Result<ClientRequest, RpcMessageError> {
    use moor_rpc::HostClientToDaemonMessageUnionRef as U;

    match message
        .message()
        .map_err(|_| RpcMessageError::InvalidRequest("Missing message union".to_string()))?
    {
        U::ConnectionEstablish(conn_est) => {
            let peer_addr = extract_string_rpc(&conn_est, "peer_addr", |c| c.peer_addr())?;
            let local_port = extract_field_rpc(&conn_est, "local_port", |c| c.local_port())?;
            let remote_port = extract_field_rpc(&conn_est, "remote_port", |c| c.remote_port())?;
            let acceptable_content_types =
                conn_est
                    .acceptable_content_types()
                    .ok()
                    .flatten()
                    .map(|types| {
                        types
                            .iter()
                            .filter_map(|s| s.ok().and_then(|s| symbol_from_ref(s).ok()))
                            .collect()
                    });
            let connection_attributes =
                conn_est
                    .connection_attributes()
                    .ok()
                    .flatten()
                    .map(|attrs| {
                        attrs
                            .iter()
                            .filter_map(|attr| {
                                let attr = attr.ok()?;
                                let key = symbol_from_ref(attr.key().ok()?).ok()?;
                                let value = convert::var_from_ref(attr.value().ok()?).ok()?;
                                Some(api::ConnectionAttribute { key, value })
                            })
                            .collect()
                    });
            Ok(ClientRequest::ConnectionEstablish {
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            })
        }
        U::Reattach(reattach) => {
            let client_token = reattach
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = reattach
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let peer_addr = reattach.peer_addr().ok().flatten().map(|s| s.to_string());
            let local_port = reattach.local_port().ok();
            let remote_port = reattach.remote_port().ok();
            let acceptable_content_types =
                reattach
                    .acceptable_content_types()
                    .ok()
                    .flatten()
                    .map(|types| {
                        types
                            .iter()
                            .filter_map(|s| s.ok().and_then(|s| symbol_from_ref(s).ok()))
                            .collect()
                    });
            let connection_attributes =
                reattach
                    .connection_attributes()
                    .ok()
                    .flatten()
                    .map(|attrs| {
                        attrs
                            .iter()
                            .filter_map(|attr| {
                                let attr = attr.ok()?;
                                let key = symbol_from_ref(attr.key().ok()?).ok()?;
                                let value = convert::var_from_ref(attr.value().ok()?).ok()?;
                                Some(api::ConnectionAttribute { key, value })
                            })
                            .collect()
                    });
            Ok(ClientRequest::Reattach {
                client_token,
                auth_token,
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            })
        }
        U::ClientPong(pong) => {
            let client_token = pong
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let client_sys_time = pong.client_sys_time().unwrap_or(0);
            let player = extract_obj_rpc(&pong, "player", |p| p.player())?;
            let host_type = extract_host_type(&pong, "host_type", |p| p.host_type())?;
            let socket_addr = extract_string_rpc(&pong, "socket_addr", |p| p.socket_addr())?;
            Ok(ClientRequest::ClientPong {
                client_token,
                client_sys_time,
                player,
                host_type,
                socket_addr,
            })
        }
        U::RequestSysProp(req) => {
            let auth_token = match req.auth_token() {
                Ok(Some(auth_ref)) => Some(auth_token_from_ref(auth_ref).rpc_err()?),
                _ => None,
            };
            let object = extract_object_ref_rpc(&req, "object", |r| r.object())?;
            let property = extract_symbol_rpc(&req, "property", |r| r.property())?;
            Ok(ClientRequest::RequestSysProp {
                auth_token,
                object,
                property,
            })
        }
        U::LoginCommand(login) => {
            let client_token = login
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let handler_object = extract_obj_rpc(&login, "handler_object", |l| l.handler_object())?;
            let connect_args =
                extract_string_list_rpc(&login, "connect_args", |l| l.connect_args())?;
            let do_attach = extract_field_rpc(&login, "do_attach", |l| l.do_attach())?;
            let event_log_pubkey = login
                .event_log_pubkey()
                .ok()
                .flatten()
                .map(|s| s.to_string());
            // registration_data is a VarMap in the FlatBuffer, not a Var;
            // extraction will be added when the typed API gains a VarMap field type.
            let registration_data: Option<Var> = None;
            Ok(ClientRequest::LoginCommand {
                client_token,
                handler_object,
                connect_args,
                do_attach,
                event_log_pubkey,
                registration_data,
            })
        }
        U::Attach(attach_msg) => {
            let auth_token = attach_msg
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let connect_type = attach_msg.connect_type().rpc_err()?;
            let connect_type = match connect_type {
                moor_rpc::ConnectType::Connected => ConnectType::Connected,
                moor_rpc::ConnectType::Reconnected => ConnectType::Reconnected,
                moor_rpc::ConnectType::Created => ConnectType::Created,
                moor_rpc::ConnectType::NoConnect => ConnectType::NoConnect,
            };
            let handler_object =
                extract_obj_rpc(&attach_msg, "handler_object", |a| a.handler_object())?;
            let peer_addr = extract_string_rpc(&attach_msg, "peer_addr", |a| a.peer_addr())?;
            let local_port = extract_field_rpc(&attach_msg, "local_port", |a| a.local_port())?;
            let remote_port = extract_field_rpc(&attach_msg, "remote_port", |a| a.remote_port())?;
            let acceptable_content_types = attach_msg
                .acceptable_content_types()
                .ok()
                .flatten()
                .map(|types| {
                    types
                        .iter()
                        .filter_map(|s| s.ok().and_then(|s| symbol_from_ref(s).ok()))
                        .collect()
                });
            Ok(ClientRequest::Attach {
                auth_token,
                connect_type,
                handler_object,
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
            })
        }
        U::Command(cmd) => {
            let client_token = cmd
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = cmd
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let handler_object = extract_obj_rpc(&cmd, "handler_object", |c| c.handler_object())?;
            let command = extract_string_rpc(&cmd, "command", |c| c.command())?;
            Ok(ClientRequest::Command {
                client_token,
                auth_token,
                handler_object,
                command,
            })
        }
        U::Detach(detach) => {
            let client_token = detach
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let disconnected = detach.disconnected().rpc_err()?;
            Ok(ClientRequest::Detach {
                client_token,
                disconnected,
            })
        }
        U::RequestedInput(input) => {
            let client_token = input
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = input
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let request_id = extract_uuid_rpc(&input, "request_id", |i| i.request_id())?;
            let input_var = extract_var_rpc(&input, "input", |i| i.input())?;
            Ok(ClientRequest::RequestedInput {
                client_token,
                auth_token,
                request_id,
                input: input_var,
            })
        }
        U::OutOfBand(oob) => {
            let client_token = oob
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = oob
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let handler_object = extract_obj_rpc(&oob, "handler_object", |o| o.handler_object())?;
            let args = extract_var_rpc(&oob, "args", |o| o.args())?;
            let argstr = extract_var_rpc(&oob, "argstr", |o| o.argstr())?;
            Ok(ClientRequest::OutOfBand {
                client_token,
                auth_token,
                handler_object,
                args,
                argstr,
            })
        }
        U::Eval(eval) => {
            let client_token = eval
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = eval
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let expression = extract_string_rpc(&eval, "expression", |e| e.expression())?;
            Ok(ClientRequest::Eval {
                client_token,
                auth_token,
                expression,
            })
        }
        U::InvokeVerb(invoke) => {
            let client_token = invoke
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = invoke
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&invoke, "object", |i| i.object())?;
            let verb = extract_symbol_rpc(&invoke, "verb", |i| i.verb())?;
            let args_vec = invoke.args().rpc_err()?;
            let args: Vec<Var> = args_vec
                .iter()
                .filter_map(|v| v.ok().and_then(|v| convert::var_from_ref(v).ok()))
                .collect();
            Ok(ClientRequest::InvokeVerb {
                client_token,
                auth_token,
                object,
                verb,
                args,
            })
        }
        U::Retrieve(retr) => {
            let auth_token = retr
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&retr, "object", |r| r.object())?;
            let retr_type = extract_field_rpc(&retr, "entity_type", |r| r.entity_type())?;
            let entity_type = match retr_type {
                moor_rpc::EntityType::Property => EntityType::Property,
                moor_rpc::EntityType::Verb => EntityType::Verb,
            };
            let name = extract_symbol_rpc(&retr, "name", |r| r.name())?;
            Ok(ClientRequest::Retrieve {
                auth_token,
                object,
                entity_type,
                name,
            })
        }
        U::Properties(props) => {
            let auth_token = props
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&props, "object", |p| p.object())?;
            let inherited = props.inherited().rpc_err()?;
            Ok(ClientRequest::Properties {
                auth_token,
                object,
                inherited,
            })
        }
        U::Verbs(verbs) => {
            let auth_token = verbs
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&verbs, "object", |v| v.object())?;
            let inherited = verbs.inherited().rpc_err()?;
            Ok(ClientRequest::Verbs {
                auth_token,
                object,
                inherited,
            })
        }
        U::RequestHistory(hist) => {
            let auth_token = hist
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let recall = decode_history_recall(hist.history_recall().map_err(|_| {
                RpcMessageError::InvalidRequest("Missing history_recall".to_string())
            })?)?;
            Ok(ClientRequest::RequestHistory { auth_token, recall })
        }
        U::RequestCurrentPresentations(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            Ok(ClientRequest::RequestCurrentPresentations { auth_token })
        }
        U::DismissPresentation(dismiss) => {
            let auth_token = dismiss
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let presentation_id = dismiss.presentation_id().rpc_err()?.to_string();
            Ok(ClientRequest::DismissPresentation {
                auth_token,
                presentation_id,
            })
        }
        U::SetClientAttribute(set_attr) => {
            let client_token = set_attr
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = set_attr
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let key = extract_symbol_rpc(&set_attr, "key", |s| s.key())?;
            let value = set_attr
                .value()
                .ok()
                .and_then(|v_opt| v_opt.and_then(|v_ref| convert::var_from_ref(v_ref).ok()));
            Ok(ClientRequest::SetClientAttribute {
                client_token,
                auth_token,
                key,
                value,
            })
        }
        U::Program(prog) => {
            let client_token = prog
                .client_token()
                .rpc_err()
                .and_then(|r| client_token_from_ref(r).rpc_err())?;
            let auth_token = prog
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&prog, "object", |p| p.object())?;
            let verb = extract_symbol_rpc(&prog, "verb", |p| p.verb())?;
            let code_vec = prog.code().rpc_err()?;
            let code: Vec<String> = code_vec
                .iter()
                .filter_map(|s| s.ok().map(|s| s.to_string()))
                .collect();
            Ok(ClientRequest::Program {
                client_token,
                auth_token,
                object,
                verb,
                code,
            })
        }
        U::GetEventLogPublicKey(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            Ok(ClientRequest::GetEventLogPublicKey { auth_token })
        }
        U::SetEventLogPublicKey(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let public_key = extract_string_rpc(&req, "public_key", |r| r.public_key())?;
            Ok(ClientRequest::SetEventLogPublicKey {
                auth_token,
                public_key,
            })
        }
        U::DeleteEventLogHistory(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            Ok(ClientRequest::DeleteEventLogHistory { auth_token })
        }
        U::ListObjects(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            Ok(ClientRequest::ListObjects { auth_token })
        }
        U::UpdateProperty(req) => {
            let auth_token = req
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let object = extract_object_ref_rpc(&req, "object", |r| r.object())?;
            let property = extract_symbol_rpc(&req, "property", |r| r.property())?;
            let value = extract_var_rpc(&req, "value", |r| r.value())?;
            Ok(ClientRequest::UpdateProperty {
                auth_token,
                object,
                property,
                value,
            })
        }
        U::InvokeSystemHandler(invoke) => {
            let host_id = extract_uuid_rpc(&invoke, "host_id", |i| i.host_id())?;
            let handler_type = extract_string_rpc(&invoke, "handler_type", |i| i.handler_type())?;
            let args_vec = invoke.args().rpc_err()?;
            let args: Vec<Var> = args_vec
                .iter()
                .filter_map(|v| v.ok().and_then(|v| convert::var_from_ref(v).ok()))
                .collect();
            let auth_token = match invoke.auth_token() {
                Ok(Some(auth_ref)) => Some(auth_token_from_ref(auth_ref).rpc_err()?),
                _ => None,
            };
            Ok(ClientRequest::InvokeSystemHandler {
                host_id,
                handler_type,
                args,
                auth_token,
            })
        }
        U::CallSystemVerb(call) => {
            let auth_token = match call.auth_token() {
                Ok(Some(auth_ref)) => Some(auth_token_from_ref(auth_ref).rpc_err()?),
                _ => None,
            };
            let verb = extract_symbol_rpc(&call, "verb", |c| c.verb())?;
            let args_vec = call.args().rpc_err()?;
            let args: Vec<Var> = args_vec
                .iter()
                .filter_map(|v| v.ok().and_then(|v| convert::var_from_ref(v).ok()))
                .collect();
            Ok(ClientRequest::CallSystemVerb {
                auth_token,
                verb,
                args,
            })
        }
        U::BatchWorldState(batch) => {
            let auth_token = batch
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let rollback = batch.rollback().unwrap_or(false);
            let fb_actions = batch.actions().rpc_err()?;
            let mut actions = Vec::with_capacity(fb_actions.len());
            for entry_result in fb_actions.iter() {
                let entry = entry_result.rpc_err()?;
                let id = entry.id().rpc_err()?.to_string();
                let action = decode_batch_action(entry.action().rpc_err()?)?;
                actions.push(BatchActionEntry { id, action });
            }
            Ok(ClientRequest::BatchWorldState {
                auth_token,
                actions,
                rollback,
            })
        }
        U::Resolve(resolve) => {
            let auth_token = resolve
                .auth_token()
                .rpc_err()
                .and_then(|r| auth_token_from_ref(r).rpc_err())?;
            let objref = extract_object_ref_rpc(&resolve, "objref", |r| r.objref())?;
            Ok(ClientRequest::Resolve { auth_token, objref })
        }
    }
}

fn decode_history_recall(
    recall_ref: moor_rpc::HistoryRecallRef<'_>,
) -> Result<api::HistoryRecall, RpcMessageError> {
    use moor_schema::convert::uuid_from_ref;

    match recall_ref
        .recall()
        .map_err(|_| RpcMessageError::InvalidRequest("Missing history recall".to_string()))?
    {
        moor_rpc::HistoryRecallUnionRef::HistoryRecallSinceEvent(since) => {
            let event_id_ref = since
                .event_id()
                .map_err(|_| RpcMessageError::InvalidRequest("Missing event_id".to_string()))?;
            let event_id = uuid_from_ref(event_id_ref).rpc_err()?;
            let limit = since.limit().unwrap_or(0);
            let limit = if limit == 0 {
                None
            } else {
                Some(limit as usize)
            };
            Ok(api::HistoryRecall::SinceEvent { event_id, limit })
        }
        moor_rpc::HistoryRecallUnionRef::HistoryRecallUntilEvent(until) => {
            let event_id_ref = until
                .event_id()
                .map_err(|_| RpcMessageError::InvalidRequest("Missing event_id".to_string()))?;
            let event_id = uuid_from_ref(event_id_ref).rpc_err()?;
            let limit = until.limit().unwrap_or(0);
            let limit = if limit == 0 {
                None
            } else {
                Some(limit as usize)
            };
            Ok(api::HistoryRecall::UntilEvent { event_id, limit })
        }
        moor_rpc::HistoryRecallUnionRef::HistoryRecallSinceSeconds(since_seconds) => {
            let seconds_ago = since_seconds
                .seconds_ago()
                .map_err(|_| RpcMessageError::InvalidRequest("Missing seconds_ago".to_string()))?;
            let limit = since_seconds.limit().unwrap_or(0);
            let limit = if limit == 0 {
                None
            } else {
                Some(limit as usize)
            };
            Ok(api::HistoryRecall::SinceSeconds { seconds_ago, limit })
        }
        moor_rpc::HistoryRecallUnionRef::HistoryRecallNone(_) => Ok(api::HistoryRecall::None),
    }
}

pub fn decode_batch_action(
    action: moor_rpc::WorldStateActionUnionRef<'_>,
) -> Result<BatchAction, RpcMessageError> {
    use crate::RpcErr;
    use moor_schema::convert::{obj_from_ref, objectref_from_ref, var_from_ref};

    match action {
        moor_rpc::WorldStateActionUnionRef::WsRequestProperty(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let property = Symbol::mk(req.property().rpc_err()?.value().rpc_err()?);
            Ok(BatchAction::RequestProperty { obj, property })
        }
        moor_rpc::WorldStateActionUnionRef::WsRequestProperties(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let inherited = req.inherited().unwrap_or(false);
            Ok(BatchAction::RequestProperties { obj, inherited })
        }
        moor_rpc::WorldStateActionUnionRef::WsRequestSystemProperty(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let property = Symbol::mk(req.property().rpc_err()?.value().rpc_err()?);
            Ok(BatchAction::RequestSystemProperty { obj, property })
        }
        moor_rpc::WorldStateActionUnionRef::WsRequestVerbs(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let inherited = req.inherited().unwrap_or(false);
            Ok(BatchAction::RequestVerbs { obj, inherited })
        }
        moor_rpc::WorldStateActionUnionRef::WsRequestVerbCode(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let verb = Symbol::mk(req.verb().rpc_err()?.value().rpc_err()?);
            Ok(BatchAction::RequestVerbCode { obj, verb })
        }
        moor_rpc::WorldStateActionUnionRef::WsResolveObject(req) => {
            let obj = objectref_from_ref(req.objref().rpc_err()?).rpc_err()?;
            Ok(BatchAction::ResolveObject { objref: obj })
        }
        moor_rpc::WorldStateActionUnionRef::WsListObjects(_) => Ok(BatchAction::ListObjects),
        moor_rpc::WorldStateActionUnionRef::WsRequestAllObjects(_) => {
            Ok(BatchAction::RequestAllObjects)
        }
        moor_rpc::WorldStateActionUnionRef::WsUpdateProperty(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let property = Symbol::mk(req.property().rpc_err()?.value().rpc_err()?);
            let value = var_from_ref(req.value().rpc_err()?).rpc_err()?;
            Ok(BatchAction::UpdateProperty {
                obj,
                property,
                value,
            })
        }
        moor_rpc::WorldStateActionUnionRef::WsProgramVerb(req) => {
            let obj = objectref_from_ref(req.object().rpc_err()?).rpc_err()?;
            let verb_name = Symbol::mk(req.verb_name().rpc_err()?.value().rpc_err()?);
            let code_vec = req.code().rpc_err()?;
            let code: Vec<String> = code_vec
                .iter()
                .filter_map(|s| s.ok().map(|s| s.to_string()))
                .collect();
            Ok(BatchAction::ProgramVerb {
                obj,
                verb_name,
                code,
            })
        }
        moor_rpc::WorldStateActionUnionRef::WsGetObjectFlags(req) => {
            let obj = obj_from_ref(req.obj().rpc_err()?).rpc_err()?;
            Ok(BatchAction::GetObjectFlags { obj })
        }
        moor_rpc::WorldStateActionUnionRef::WsQueryObjects(req) => {
            let parent = req
                .parent()
                .ok()
                .flatten()
                .and_then(|r| obj_from_ref(r).ok());
            let location = req
                .location()
                .ok()
                .flatten()
                .and_then(|r| obj_from_ref(r).ok());
            let owner = req
                .owner()
                .ok()
                .flatten()
                .and_then(|r| obj_from_ref(r).ok());
            let flags_all = req.flags_all().unwrap_or(0);
            let flags_any = req.flags_any().unwrap_or(0);
            Ok(BatchAction::QueryObjects {
                parent,
                location,
                owner,
                flags_all,
                flags_any,
            })
        }
    }
}

pub fn decode_owned_batch_action(
    action: moor_rpc::WorldStateActionUnion,
) -> Result<BatchAction, RpcMessageError> {
    let batch = moor_rpc::BatchWorldState {
        auth_token: auth_token_fb(&AuthToken("decode".to_string())),
        actions: vec![moor_rpc::WorldStateActionEntry {
            id: "decode".to_string(),
            action,
        }],
        rollback: false,
    };
    let mut builder = planus::Builder::new();
    let bytes = builder.finish(&batch, None).to_vec();
    let batch_ref = moor_rpc::BatchWorldStateRef::read_as_root(&bytes)
        .map_err(|e| RpcMessageError::InvalidRequest(format!("Invalid batch action: {e}")))?;
    let actions = batch_ref.actions().rpc_err()?;
    let entry = actions
        .iter()
        .next()
        .ok_or_else(|| RpcMessageError::InvalidRequest("Missing batch action".to_string()))?
        .rpc_err()?;
    let action = entry.action().rpc_err()?;
    decode_batch_action(action)
}

// ===========================================================================
// Client-side encode: typed ClientReply → FlatBuffer DaemonToClientReply
// ===========================================================================

pub fn encode_client_reply(
    reply: ClientReply,
) -> Result<moor_rpc::DaemonToClientReply, RpcMessageError> {
    use moor_common::model::preposition_to_string;
    use moor_rpc::DaemonToClientReplyUnion as U;

    let reply = match reply {
        ClientReply::NewConnection {
            client_token,
            connection_obj,
        } => mk_new_connection_reply(client_token, &connection_obj),
        ClientReply::LoginResult {
            success,
            auth_token,
            connect_type,
            player,
            player_flags,
        } => moor_rpc::DaemonToClientReply {
            reply: U::LoginResult(Box::new(moor_rpc::LoginResult {
                success,
                auth_token: auth_token.map(|t| crate::auth_token_fb(&t)),
                connect_type: encode_connect_type(connect_type),
                player: player.map(|p| obj_fb(&p)),
                player_flags,
            })),
        },
        ClientReply::AttachResult {
            success,
            client_token,
            player,
            player_flags,
        } => moor_rpc::DaemonToClientReply {
            reply: U::AttachResult(Box::new(moor_rpc::AttachResult {
                success,
                client_token: client_token.map(|t| crate::client_token_fb(&t)),
                player: player.map(|p| obj_fb(&p)),
                player_flags,
            })),
        },
        ClientReply::SysPropValue { value } => moor_rpc::DaemonToClientReply {
            reply: U::SysPropValue(Box::new(moor_rpc::SysPropValue {
                value: value
                    .map(|v| var_to_flatbuffer_rpc(&v).map(Box::new))
                    .transpose()?,
            })),
        },
        ClientReply::TaskSubmitted { task_id } => moor_rpc::DaemonToClientReply {
            reply: U::TaskSubmitted(Box::new(moor_rpc::TaskSubmitted { task_id })),
        },
        ClientReply::InputThanks => moor_rpc::DaemonToClientReply {
            reply: U::InputThanks(Box::new(moor_rpc::InputThanks {})),
        },
        ClientReply::EvalResult { result } => {
            let result_fb = var_to_flatbuffer_rpc(&result)?;
            moor_rpc::DaemonToClientReply {
                reply: U::EvalResult(Box::new(moor_rpc::EvalResult {
                    result: Box::new(result_fb),
                })),
            }
        }
        ClientReply::ThanksPong { timestamp } => mk_thanks_pong_reply(timestamp),
        ClientReply::VerbsReply { verbs } => {
            let verbs_fb: Vec<common::VerbInfo> = verbs
                .iter()
                .map(|v| {
                    let names: Vec<moor_rpc::Symbol> = v
                        .names()
                        .iter()
                        .map(|n| moor_rpc::Symbol {
                            value: n.as_string(),
                        })
                        .collect();
                    let arg_spec = vec![
                        moor_rpc::Symbol {
                            value: v.args().dobj.to_string().to_string(),
                        },
                        moor_rpc::Symbol {
                            value: preposition_to_string(&v.args().prep).to_string(),
                        },
                        moor_rpc::Symbol {
                            value: v.args().iobj.to_string().to_string(),
                        },
                    ];
                    common::VerbInfo {
                        location: obj_fb(&v.location()),
                        owner: obj_fb(&v.owner()),
                        names,
                        r: v.flags().contains(moor_common::model::VerbFlag::Read),
                        w: v.flags().contains(moor_common::model::VerbFlag::Write),
                        x: v.flags().contains(moor_common::model::VerbFlag::Exec),
                        d: v.flags().contains(moor_common::model::VerbFlag::Debug),
                        arg_spec,
                    }
                })
                .collect();
            moor_rpc::DaemonToClientReply {
                reply: U::VerbsReply(Box::new(moor_rpc::VerbsReply { verbs: verbs_fb })),
            }
        }
        ClientReply::PropertiesReply { properties } => {
            let props_fb: Vec<common::PropInfo> = properties
                .iter()
                .map(|(propdef, propperms)| common::PropInfo {
                    definer: obj_fb(&propdef.definer()),
                    location: obj_fb(&propdef.location()),
                    name: Box::new(moor_rpc::Symbol {
                        value: propdef.name().as_string(),
                    }),
                    owner: obj_fb(&propperms.owner()),
                    r: propperms
                        .flags()
                        .contains(moor_common::model::PropFlag::Read),
                    w: propperms
                        .flags()
                        .contains(moor_common::model::PropFlag::Write),
                    chown: propperms
                        .flags()
                        .contains(moor_common::model::PropFlag::Chown),
                })
                .collect();
            moor_rpc::DaemonToClientReply {
                reply: U::PropertiesReply(Box::new(moor_rpc::PropertiesReply {
                    properties: props_fb,
                })),
            }
        }
        ClientReply::VerbProgramResponseReply { response } => {
            let response_fb = match response {
                api::VerbProgramResponse::Success { obj, verb_name } => {
                    moor_rpc::VerbProgramResponse {
                        response: moor_rpc::VerbProgramResponseUnion::VerbProgramSuccess(Box::new(
                            moor_rpc::VerbProgramSuccess {
                                obj: obj_fb(&obj),
                                verb_name,
                            },
                        )),
                    }
                }
                api::VerbProgramResponse::Failure { error } => {
                    let verb_program_error = match error {
                        moor_common::tasks::SchedulerError::VerbProgramFailed(e) => e,
                        other => {
                            return Err(RpcMessageError::InternalError(format!(
                                "Expected VerbProgramFailed, got {other:?}"
                            )));
                        }
                    };
                    let verb_error = verb_program_error_to_flatbuffer_struct(&verb_program_error)
                        .map_err(|e| {
                        RpcMessageError::InternalError(format!(
                            "Failed to convert VerbProgramError: {e}"
                        ))
                    })?;
                    moor_rpc::VerbProgramResponse {
                        response: moor_rpc::VerbProgramResponseUnion::VerbProgramFailure(Box::new(
                            moor_rpc::VerbProgramFailure {
                                error: Box::new(verb_error),
                            },
                        )),
                    }
                }
            };
            moor_rpc::DaemonToClientReply {
                reply: U::VerbProgramResponseReply(Box::new(moor_rpc::VerbProgramResponseReply {
                    response: Box::new(response_fb),
                })),
            }
        }
        ClientReply::PropertyValue { prop_info, value } => {
            let (propdef, propperms) = prop_info;
            let value_fb = var_to_flatbuffer_rpc(&value)?;
            moor_rpc::DaemonToClientReply {
                reply: U::PropertyValue(Box::new(moor_rpc::PropertyValue {
                    prop_info: Box::new(common::PropInfo {
                        definer: obj_fb(&propdef.definer()),
                        location: obj_fb(&propdef.location()),
                        name: Box::new(moor_rpc::Symbol {
                            value: propdef.name().as_string(),
                        }),
                        owner: obj_fb(&propperms.owner()),
                        r: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Read),
                        w: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Write),
                        chown: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Chown),
                    }),
                    value: Box::new(value_fb),
                })),
            }
        }
        ClientReply::VerbValue { verb_info, code } => {
            let names: Vec<moor_rpc::Symbol> = verb_info
                .names()
                .iter()
                .map(|n| moor_rpc::Symbol {
                    value: n.as_string(),
                })
                .collect();
            let arg_spec = vec![
                moor_rpc::Symbol {
                    value: verb_info.args().dobj.to_string().to_string(),
                },
                moor_rpc::Symbol {
                    value: preposition_to_string(&verb_info.args().prep).to_string(),
                },
                moor_rpc::Symbol {
                    value: verb_info.args().iobj.to_string().to_string(),
                },
            ];
            moor_rpc::DaemonToClientReply {
                reply: U::VerbValue(Box::new(moor_rpc::VerbValue {
                    verb_info: Box::new(common::VerbInfo {
                        location: obj_fb(&verb_info.location()),
                        owner: obj_fb(&verb_info.owner()),
                        names,
                        r: verb_info
                            .flags()
                            .contains(moor_common::model::VerbFlag::Read),
                        w: verb_info
                            .flags()
                            .contains(moor_common::model::VerbFlag::Write),
                        x: verb_info
                            .flags()
                            .contains(moor_common::model::VerbFlag::Exec),
                        d: verb_info
                            .flags()
                            .contains(moor_common::model::VerbFlag::Debug),
                        arg_spec,
                    }),
                    code,
                })),
            }
        }
        ClientReply::ResolveResult { result } => {
            let result_fb = var_to_flatbuffer_rpc(&result)?;
            moor_rpc::DaemonToClientReply {
                reply: U::ResolveResult(Box::new(moor_rpc::ResolveResult {
                    result: Box::new(result_fb),
                })),
            }
        }
        ClientReply::HistoryResponseReply { response } => {
            let fb_events: Vec<_> = response
                .events
                .into_iter()
                .map(|e| moor_rpc::HistoricalNarrativeEvent {
                    event_id: uuid_fb(e.event_id),
                    timestamp: e.timestamp,
                    player: obj_fb(&e.player),
                    is_historical: true,
                    encrypted_blob: e.encrypted_blob,
                })
                .collect();
            moor_rpc::DaemonToClientReply {
                reply: U::HistoryResponseReply(Box::new(moor_rpc::HistoryResponseReply {
                    response: Box::new(moor_rpc::HistoryResponse {
                        events: fb_events,
                        time_range_start: response.time_range_start,
                        time_range_end: response.time_range_end,
                        total_events: response.total_events,
                        has_more_before: response.has_more_before,
                        earliest_event_id: response.earliest_event_id.map(uuid_fb),
                        latest_event_id: response.latest_event_id.map(uuid_fb),
                    }),
                })),
            }
        }
        ClientReply::CurrentPresentations { presentations } => {
            let presentation_snapshots = presentations
                .into_iter()
                .map(|p| moor_rpc::PresentationSnapshot {
                    id: p.id,
                    encrypted_blob: p.encrypted_blob,
                })
                .collect();
            moor_rpc::DaemonToClientReply {
                reply: U::CurrentPresentations(Box::new(moor_rpc::CurrentPresentations {
                    presentations: presentation_snapshots,
                })),
            }
        }
        ClientReply::PresentationDismissed => mk_presentation_dismissed_reply(),
        ClientReply::ClientAttributeSet => mk_client_attribute_set_reply(),
        ClientReply::Disconnected => mk_disconnected_reply(),
        ClientReply::EventLogPublicKey { public_key } => moor_rpc::DaemonToClientReply {
            reply: U::EventLogPublicKey(Box::new(moor_rpc::EventLogPublicKey {
                public_key: Some(public_key),
            })),
        },
        ClientReply::EventLogHistoryDeleted { success } => moor_rpc::DaemonToClientReply {
            reply: U::EventLogHistoryDeleted(Box::new(moor_rpc::EventLogHistoryDeleted {
                success,
            })),
        },
        ClientReply::ListObjectsReply { objects } => {
            let object_infos: Vec<moor_rpc::ObjectInfo> = objects
                .into_iter()
                .map(|o| moor_rpc::ObjectInfo {
                    obj: obj_fb(&o.obj),
                    name: o.name.map(|n| {
                        Box::new(moor_rpc::Symbol {
                            value: n.as_string(),
                        })
                    }),
                    parent: o.parent.map(|p| obj_fb(&p)),
                    owner: obj_fb(&o.owner),
                    flags: o.flags,
                    location: o.location.map(|l| obj_fb(&l)),
                    contents_count: o.contents_count,
                    verbs_count: o.verbs_count,
                    properties_count: o.properties_count,
                })
                .collect();
            moor_rpc::DaemonToClientReply {
                reply: U::ListObjectsReply(Box::new(moor_rpc::ListObjectsReply {
                    objects: object_infos,
                })),
            }
        }
        ClientReply::PropertyUpdated => moor_rpc::DaemonToClientReply {
            reply: U::PropertyUpdated(Box::new(moor_rpc::PropertyUpdated {})),
        },
        ClientReply::SystemHandlerResponseReply { response } => {
            let response_fb = match response {
                api::SystemHandlerResponse::Success { result } => {
                    let result_fb = convert::var_to_flatbuffer(&result).map_err(|e| {
                        RpcMessageError::InternalError(format!("Failed to encode result: {e}"))
                    })?;
                    moor_rpc::SystemHandlerResponseUnion::SystemHandlerSuccess(Box::new(
                        moor_rpc::SystemHandlerSuccess {
                            result: Box::new(result_fb),
                        },
                    ))
                }
                api::SystemHandlerResponse::Error { error } => {
                    let scheduler_error_fb =
                        scheduler_error_to_flatbuffer_struct(&error).map_err(|e| {
                            RpcMessageError::InternalError(format!(
                                "Failed to encode scheduler error: {e}"
                            ))
                        })?;
                    moor_rpc::SystemHandlerResponseUnion::SystemHandlerError(Box::new(
                        moor_rpc::SystemHandlerError {
                            error: Box::new(scheduler_error_fb),
                        },
                    ))
                }
            };
            moor_rpc::DaemonToClientReply {
                reply: U::SystemHandlerResponseReply(Box::new(
                    moor_rpc::SystemHandlerResponseReply {
                        response: response_fb,
                    },
                )),
            }
        }
        ClientReply::VerbCallResponse { response } => {
            let response_fb = match response {
                api::VerbCallResponse::Success { result, output } => {
                    let result_fb = convert::var_to_flatbuffer(&result).map_err(|e| {
                        RpcMessageError::InternalError(format!("Failed to encode result: {e}"))
                    })?;
                    let output_fb: Vec<moor_rpc::NarrativeEvent> = output
                        .into_iter()
                        .map(|event| {
                            convert::narrative_event_to_flatbuffer_struct(&event).map_err(|e| {
                                RpcMessageError::InternalError(format!(
                                    "Failed to encode narrative event: {e}"
                                ))
                            })
                        })
                        .collect::<Result<_, _>>()?;
                    moor_rpc::VerbCallResponseUnion::VerbCallSuccess(Box::new(
                        moor_rpc::VerbCallSuccess {
                            result: Box::new(result_fb),
                            output: output_fb,
                        },
                    ))
                }
                api::VerbCallResponse::Error { error } => {
                    let scheduler_error_fb =
                        scheduler_error_to_flatbuffer_struct(&error).map_err(|e| {
                            RpcMessageError::InternalError(format!(
                                "Failed to encode scheduler error: {e}"
                            ))
                        })?;
                    moor_rpc::VerbCallResponseUnion::VerbCallError(Box::new(
                        moor_rpc::VerbCallError {
                            error: Box::new(scheduler_error_fb),
                        },
                    ))
                }
            };
            moor_rpc::DaemonToClientReply {
                reply: U::VerbCallResponse(Box::new(moor_rpc::VerbCallResponse {
                    response: response_fb,
                })),
            }
        }
        ClientReply::BatchWorldStateReply { results } => {
            let result_entries = encode_ws_results(results)?;
            moor_rpc::DaemonToClientReply {
                reply: U::BatchWorldStateReply(Box::new(moor_rpc::BatchWorldStateReply {
                    results: result_entries,
                })),
            }
        }
    };
    Ok(reply)
}

pub fn encode_client_success_bytes(reply: ClientReply) -> Result<Vec<u8>, RpcMessageError> {
    let reply = encode_client_reply(reply)?;
    let reply_result = moor_rpc::ReplyResult {
        result: moor_rpc::ReplyResultUnion::ClientSuccess(Box::new(moor_rpc::ClientSuccess {
            reply: Box::new(reply),
        })),
    };
    let mut builder = planus::Builder::new();
    Ok(builder.finish(&reply_result, None).to_vec())
}

fn encode_connect_type(ct: ConnectType) -> moor_rpc::ConnectType {
    match ct {
        ConnectType::Connected => moor_rpc::ConnectType::Connected,
        ConnectType::Reconnected => moor_rpc::ConnectType::Reconnected,
        ConnectType::Created => moor_rpc::ConnectType::Created,
        ConnectType::NoConnect => moor_rpc::ConnectType::NoConnect,
    }
}

fn encode_ws_results(
    results: Vec<api::WorldStateResultEntry>,
) -> Result<Vec<moor_rpc::WorldStateResultEntry>, RpcMessageError> {
    use moor_common::model::preposition_to_string;

    let mut entries = Vec::with_capacity(results.len());
    for entry in results {
        let result_union = match entry.result {
            api::WorldStateResult::Property(propdef, propperms, value) => {
                let value_fb = var_to_flatbuffer_rpc(&value)?;
                moor_rpc::WorldStateResultUnion::WsPropertyResult(Box::new(
                    moor_rpc::WsPropertyResult {
                        prop_info: Box::new(common::PropInfo {
                            definer: obj_fb(&propdef.definer()),
                            location: obj_fb(&propdef.location()),
                            name: Box::new(moor_rpc::Symbol {
                                value: propdef.name().as_string(),
                            }),
                            owner: obj_fb(&propperms.owner()),
                            r: propperms
                                .flags()
                                .contains(moor_common::model::PropFlag::Read),
                            w: propperms
                                .flags()
                                .contains(moor_common::model::PropFlag::Write),
                            chown: propperms
                                .flags()
                                .contains(moor_common::model::PropFlag::Chown),
                        }),
                        value: Box::new(value_fb),
                    },
                ))
            }
            api::WorldStateResult::Properties(prop_list) => {
                let props: Vec<common::PropInfo> = prop_list
                    .iter()
                    .map(|(propdef, propperms)| common::PropInfo {
                        definer: obj_fb(&propdef.definer()),
                        location: obj_fb(&propdef.location()),
                        name: Box::new(moor_rpc::Symbol {
                            value: propdef.name().as_string(),
                        }),
                        owner: obj_fb(&propperms.owner()),
                        r: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Read),
                        w: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Write),
                        chown: propperms
                            .flags()
                            .contains(moor_common::model::PropFlag::Chown),
                    })
                    .collect();
                moor_rpc::WorldStateResultUnion::WsPropertiesResult(Box::new(
                    moor_rpc::WsPropertiesResult { properties: props },
                ))
            }
            api::WorldStateResult::SystemProperty(value) => {
                let value_fb = var_to_flatbuffer_rpc(&value)?;
                moor_rpc::WorldStateResultUnion::WsSystemPropertyResult(Box::new(
                    moor_rpc::WsSystemPropertyResult {
                        value: Box::new(value_fb),
                    },
                ))
            }
            api::WorldStateResult::Verbs(verb_defs) => {
                let verbs: Vec<common::VerbInfo> = verb_defs
                    .iter()
                    .map(|v| {
                        let names: Vec<moor_rpc::Symbol> = v
                            .names()
                            .iter()
                            .map(|n| moor_rpc::Symbol {
                                value: n.as_string(),
                            })
                            .collect();
                        let arg_spec = vec![
                            moor_rpc::Symbol {
                                value: v.args().dobj.to_string().to_string(),
                            },
                            moor_rpc::Symbol {
                                value: preposition_to_string(&v.args().prep).to_string(),
                            },
                            moor_rpc::Symbol {
                                value: v.args().iobj.to_string().to_string(),
                            },
                        ];
                        common::VerbInfo {
                            location: obj_fb(&v.location()),
                            owner: obj_fb(&v.owner()),
                            names,
                            r: v.flags().contains(moor_common::model::VerbFlag::Read),
                            w: v.flags().contains(moor_common::model::VerbFlag::Write),
                            x: v.flags().contains(moor_common::model::VerbFlag::Exec),
                            d: v.flags().contains(moor_common::model::VerbFlag::Debug),
                            arg_spec,
                        }
                    })
                    .collect();
                moor_rpc::WorldStateResultUnion::WsVerbsResult(Box::new(moor_rpc::WsVerbsResult {
                    verbs,
                }))
            }
            api::WorldStateResult::VerbCode(verbdef, code) => {
                let names: Vec<moor_rpc::Symbol> = verbdef
                    .names()
                    .iter()
                    .map(|n| moor_rpc::Symbol {
                        value: n.as_string(),
                    })
                    .collect();
                let arg_spec = vec![
                    moor_rpc::Symbol {
                        value: verbdef.args().dobj.to_string().to_string(),
                    },
                    moor_rpc::Symbol {
                        value: preposition_to_string(&verbdef.args().prep).to_string(),
                    },
                    moor_rpc::Symbol {
                        value: verbdef.args().iobj.to_string().to_string(),
                    },
                ];
                moor_rpc::WorldStateResultUnion::WsVerbCodeResult(Box::new(
                    moor_rpc::WsVerbCodeResult {
                        verb_info: Box::new(common::VerbInfo {
                            location: obj_fb(&verbdef.location()),
                            owner: obj_fb(&verbdef.owner()),
                            names,
                            r: verbdef.flags().contains(moor_common::model::VerbFlag::Read),
                            w: verbdef
                                .flags()
                                .contains(moor_common::model::VerbFlag::Write),
                            x: verbdef.flags().contains(moor_common::model::VerbFlag::Exec),
                            d: verbdef
                                .flags()
                                .contains(moor_common::model::VerbFlag::Debug),
                            arg_spec,
                        }),
                        code,
                    },
                ))
            }
            api::WorldStateResult::ResolvedObject(value) => {
                let value_fb = var_to_flatbuffer_rpc(&value)?;
                moor_rpc::WorldStateResultUnion::WsResolveResult(Box::new(
                    moor_rpc::WsResolveResult {
                        result: Box::new(value_fb),
                    },
                ))
            }
            api::WorldStateResult::ObjectsList(objects) => {
                let object_infos: Vec<moor_rpc::ObjectInfo> = objects
                    .into_iter()
                    .map(|o| moor_rpc::ObjectInfo {
                        obj: obj_fb(&o.obj),
                        name: o.name.map(|n| {
                            Box::new(moor_rpc::Symbol {
                                value: n.as_string(),
                            })
                        }),
                        parent: o.parent.map(|p| obj_fb(&p)),
                        owner: obj_fb(&o.owner),
                        flags: o.flags,
                        location: o.location.map(|l| obj_fb(&l)),
                        contents_count: o.contents_count,
                        verbs_count: o.verbs_count,
                        properties_count: o.properties_count,
                    })
                    .collect();
                moor_rpc::WorldStateResultUnion::WsObjectsListResult(Box::new(
                    moor_rpc::WsObjectsListResult {
                        objects: object_infos,
                    },
                ))
            }
            api::WorldStateResult::AllObjects(objects) => {
                let objs: Vec<common::Obj> = objects.into_iter().map(|o| *obj_fb(&o)).collect();
                moor_rpc::WorldStateResultUnion::WsAllObjectsResult(Box::new(
                    moor_rpc::WsAllObjectsResult { objects: objs },
                ))
            }
            api::WorldStateResult::PropertyUpdated => {
                moor_rpc::WorldStateResultUnion::WsPropertyUpdatedResult(Box::new(
                    moor_rpc::WsPropertyUpdatedResult {},
                ))
            }
            api::WorldStateResult::ObjectFlags(flags) => {
                moor_rpc::WorldStateResultUnion::WsObjectFlagsResult(Box::new(
                    moor_rpc::WsObjectFlagsResult { flags },
                ))
            }
            api::WorldStateResult::QueriedObjects(objects) => {
                let objs: Vec<common::Obj> = objects.into_iter().map(|o| *obj_fb(&o)).collect();
                moor_rpc::WorldStateResultUnion::WsQueryObjectsResult(Box::new(
                    moor_rpc::WsQueryObjectsResult { objects: objs },
                ))
            }
        };
        entries.push(moor_rpc::WorldStateResultEntry {
            id: entry.id,
            result: result_union,
        });
    }
    Ok(entries)
}

/// Helper to extract a Symbol from a FlatBuffer SymbolRef.
fn symbol_from_ref(sym_ref: moor_rpc::SymbolRef<'_>) -> Result<Symbol, RpcMessageError> {
    let value = sym_ref.value().rpc_err()?;
    Ok(Symbol::mk(value))
}
