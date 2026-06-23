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

//! [`RuntimeClient`] implementation for [`RpcClient`], encoding typed requests
//! to FlatBuffer wire messages and decoding FlatBuffer replies back to typed
//! replies. This is the ZeroMQ adapter for the host side.

use async_trait::async_trait;
use moor_common::{
    model::{
        ArgSpec, PrepSpec, PropDef, PropFlag, PropPerms, ValSet, VerbArgsSpec, VerbDef, VerbFlag,
    },
    util::BitEnum,
};
use moor_runtime_api::api::{
    self, ClientReply, ClientRequest, HostReply, HostRequest, RuntimeClient,
};
use moor_runtime_api::{
    HostType, RpcError, auth_token_from_ref, client_token_from_ref, mk_attach_msg,
    mk_batch_world_state_msg, mk_call_system_verb_msg, mk_client_pong_msg, mk_command_msg,
    mk_connection_establish_msg, mk_delete_event_log_history_msg, mk_detach_host_msg,
    mk_detach_msg, mk_dismiss_presentation_msg, mk_eval_msg, mk_get_event_log_pubkey_msg,
    mk_get_server_features_msg, mk_host_pong_msg, mk_invoke_system_handler_msg, mk_invoke_verb_msg,
    mk_list_objects_msg, mk_login_command_msg, mk_out_of_band_msg, mk_program_msg,
    mk_properties_msg, mk_reattach_msg, mk_register_host_msg, mk_request_current_presentations_msg,
    mk_request_history_msg, mk_request_performance_counters_msg, mk_request_sys_prop_msg,
    mk_requested_input_msg, mk_resolve_msg, mk_retrieve_msg, mk_set_client_attribute_msg,
    mk_set_event_log_pubkey_msg, mk_update_property_msg, mk_verbs_msg, obj_fb, read_reply_result,
    rpc_message_error_from_ref, scheduler_error_from_ref, uuid_fb, verb_program_error_from_ref,
};
use moor_schema::{convert, rpc as moor_rpc};
use moor_var::Var;
use uuid::Uuid;

use crate::rpc_client::RpcClient;

#[async_trait]
impl RuntimeClient for RpcClient {
    async fn client_call(
        &self,
        client_id: Uuid,
        request: ClientRequest,
    ) -> Result<ClientReply, RpcError> {
        let msg = encode_client_request(request)?;
        let reply_bytes = self.make_client_rpc_call(client_id, msg).await?;
        decode_client_reply_bytes(&reply_bytes)
    }

    async fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, RpcError> {
        let msg = encode_host_request(host_id, request);
        let reply_bytes = self.make_host_rpc_call(host_id, msg).await?;
        decode_host_reply_bytes(&reply_bytes)
    }
}

// ===========================================================================
// Encode: typed ClientRequest to FlatBuffer HostClientToDaemonMessage
// ===========================================================================

fn encode_client_request(
    request: ClientRequest,
) -> Result<moor_rpc::HostClientToDaemonMessage, RpcError> {
    Ok(match request {
        ClientRequest::ConnectionEstablish {
            peer_addr,
            local_port,
            remote_port,
            acceptable_content_types,
            connection_attributes,
        } => {
            let acceptable_content_types = acceptable_content_types.map(|types| {
                types
                    .into_iter()
                    .map(|s| moor_rpc::Symbol {
                        value: s.as_string(),
                    })
                    .collect()
            });
            let connection_attributes = match connection_attributes {
                Some(attrs) => {
                    let mut fb_attrs = Vec::new();
                    for a in attrs {
                        fb_attrs.push(moor_rpc::ConnectionAttribute {
                            key: Box::new(moor_rpc::Symbol {
                                value: a.key.as_string(),
                            }),
                            value: Box::new(convert::var_to_flatbuffer(&a.value).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to encode var: {e}"))
                            })?),
                        });
                    }
                    Some(fb_attrs)
                }
                None => None,
            };
            mk_connection_establish_msg(
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            )
        }
        ClientRequest::Reattach {
            client_token,
            auth_token,
            peer_addr,
            local_port,
            remote_port,
            acceptable_content_types,
            connection_attributes,
        } => {
            let acceptable_content_types = acceptable_content_types.map(|types| {
                types
                    .into_iter()
                    .map(|s| moor_rpc::Symbol {
                        value: s.as_string(),
                    })
                    .collect()
            });
            let connection_attributes = match connection_attributes {
                Some(attrs) => {
                    let mut fb_attrs = Vec::new();
                    for a in attrs {
                        fb_attrs.push(moor_rpc::ConnectionAttribute {
                            key: Box::new(moor_rpc::Symbol {
                                value: a.key.as_string(),
                            }),
                            value: Box::new(convert::var_to_flatbuffer(&a.value).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Failed to encode var: {e}"))
                            })?),
                        });
                    }
                    Some(fb_attrs)
                }
                None => None,
            };
            mk_reattach_msg(
                &client_token,
                &auth_token,
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            )
        }
        ClientRequest::ClientPong {
            client_token,
            client_sys_time,
            player,
            host_type,
            socket_addr,
        } => {
            let host_type_fb = encode_host_type(host_type);
            mk_client_pong_msg(
                &client_token,
                client_sys_time,
                &player,
                host_type_fb,
                socket_addr,
            )
        }
        ClientRequest::RequestSysProp {
            auth_token,
            object,
            property,
        } => mk_request_sys_prop_msg(auth_token.as_ref(), &object, &property),
        ClientRequest::LoginCommand {
            client_token,
            handler_object,
            connect_args,
            do_attach,
            event_log_pubkey,
            registration_data: _,
        } => mk_login_command_msg(
            &client_token,
            &handler_object,
            connect_args,
            do_attach,
            event_log_pubkey,
            None,
        ),
        ClientRequest::Attach {
            auth_token,
            connect_type,
            handler_object,
            peer_addr,
            local_port,
            remote_port,
            acceptable_content_types,
        } => {
            let ct = match connect_type {
                api::ConnectType::Connected => moor_rpc::ConnectType::Connected,
                api::ConnectType::Reconnected => moor_rpc::ConnectType::Reconnected,
                api::ConnectType::Created => moor_rpc::ConnectType::Created,
                api::ConnectType::NoConnect => moor_rpc::ConnectType::NoConnect,
            };
            let acceptable_content_types = acceptable_content_types.map(|types| {
                types
                    .into_iter()
                    .map(|s| moor_rpc::Symbol {
                        value: s.as_string(),
                    })
                    .collect()
            });
            mk_attach_msg(
                &auth_token,
                Some(ct),
                &handler_object,
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
            )
        }
        ClientRequest::Command {
            client_token,
            auth_token,
            handler_object,
            command,
        } => mk_command_msg(&client_token, &auth_token, &handler_object, command),
        ClientRequest::Detach {
            client_token,
            disconnected,
        } => mk_detach_msg(&client_token, disconnected),
        ClientRequest::RequestedInput {
            client_token,
            auth_token,
            request_id,
            input,
        } => mk_requested_input_msg(&client_token, &auth_token, request_id, &input)
            .ok_or_else(|| RpcError::CouldNotDecode("Failed to encode input var".to_string()))?,
        ClientRequest::OutOfBand {
            client_token,
            auth_token,
            handler_object,
            args,
            argstr,
        } => mk_out_of_band_msg(&client_token, &auth_token, &handler_object, &args, &argstr)
            .ok_or_else(|| RpcError::CouldNotDecode("Failed to encode OOB vars".to_string()))?,
        ClientRequest::Eval {
            client_token,
            auth_token,
            expression,
        } => mk_eval_msg(&client_token, &auth_token, expression),
        ClientRequest::InvokeVerb {
            client_token,
            auth_token,
            object,
            verb,
            args,
        } => {
            let args_refs: Vec<&Var> = args.iter().collect();
            mk_invoke_verb_msg(&client_token, &auth_token, &object, &verb, args_refs).ok_or_else(
                || RpcError::CouldNotDecode("Failed to encode invoke verb args".to_string()),
            )?
        }
        ClientRequest::Retrieve {
            auth_token,
            object,
            entity_type,
            name,
        } => {
            let et = match entity_type {
                api::EntityType::Property => moor_rpc::EntityType::Property,
                api::EntityType::Verb => moor_rpc::EntityType::Verb,
            };
            mk_retrieve_msg(&auth_token, &object, et, &name)
        }
        ClientRequest::Properties {
            auth_token,
            object,
            inherited,
        } => mk_properties_msg(&auth_token, &object, inherited),
        ClientRequest::Verbs {
            auth_token,
            object,
            inherited,
        } => mk_verbs_msg(&auth_token, &object, inherited),
        ClientRequest::RequestHistory { auth_token, recall } => {
            let fb_recall = encode_history_recall(recall);
            mk_request_history_msg(&auth_token, Box::new(fb_recall))
        }
        ClientRequest::RequestCurrentPresentations { auth_token } => {
            mk_request_current_presentations_msg(&auth_token)
        }
        ClientRequest::DismissPresentation {
            auth_token,
            presentation_id,
        } => mk_dismiss_presentation_msg(&auth_token, presentation_id),
        ClientRequest::SetClientAttribute {
            client_token,
            auth_token,
            key,
            value,
        } => mk_set_client_attribute_msg(&client_token, &auth_token, &key, value.as_ref())
            .ok_or_else(|| {
                RpcError::CouldNotDecode("Failed to encode set client attribute value".to_string())
            })?,
        ClientRequest::Program {
            client_token,
            auth_token,
            object,
            verb,
            code,
        } => mk_program_msg(&client_token, &auth_token, &object, &verb, code),
        ClientRequest::GetEventLogPublicKey { auth_token } => {
            mk_get_event_log_pubkey_msg(&auth_token)
        }
        ClientRequest::SetEventLogPublicKey {
            auth_token,
            public_key,
        } => mk_set_event_log_pubkey_msg(&auth_token, public_key),
        ClientRequest::DeleteEventLogHistory { auth_token } => {
            mk_delete_event_log_history_msg(&auth_token)
        }
        ClientRequest::ListObjects { auth_token } => mk_list_objects_msg(&auth_token),
        ClientRequest::UpdateProperty {
            auth_token,
            object,
            property,
            value,
        } => mk_update_property_msg(&auth_token, &object, &property, &value).ok_or_else(|| {
            RpcError::CouldNotDecode("Failed to encode update property value".to_string())
        })?,
        ClientRequest::InvokeSystemHandler {
            host_id,
            handler_type,
            args,
            auth_token,
        } => {
            let args_refs: Vec<&Var> = args.iter().collect();
            mk_invoke_system_handler_msg(&host_id, &handler_type, args_refs, auth_token.as_ref())
                .ok_or_else(|| {
                    RpcError::CouldNotDecode(
                        "Failed to encode invoke system handler args".to_string(),
                    )
                })?
        }
        ClientRequest::CallSystemVerb {
            auth_token,
            verb,
            args,
        } => {
            let args_refs: Vec<&Var> = args.iter().collect();
            mk_call_system_verb_msg(auth_token.as_ref(), &verb, args_refs).ok_or_else(|| {
                RpcError::CouldNotDecode("Failed to encode call system verb args".to_string())
            })?
        }
        ClientRequest::BatchWorldState {
            auth_token,
            actions,
            rollback,
        } => {
            let batch_actions: Vec<moor_runtime_api::BatchAction> = actions
                .into_iter()
                .map(|entry| moor_runtime_api::BatchAction {
                    id: entry.id,
                    action: encode_batch_action(entry.action),
                })
                .collect();
            mk_batch_world_state_msg(&auth_token, batch_actions, rollback)
        }
        ClientRequest::Resolve { auth_token, objref } => mk_resolve_msg(&auth_token, &objref),
    })
}

// ===========================================================================
// Encode: typed HostRequest to FlatBuffer HostToDaemonMessage
// ===========================================================================

fn encode_host_request(host_id: Uuid, request: HostRequest) -> moor_rpc::HostToDaemonMessage {
    match request {
        HostRequest::RegisterHost {
            timestamp,
            host_type,
            listeners,
        } => {
            let host_type_fb = encode_host_type(host_type);
            let listeners_fb: Vec<moor_rpc::Listener> = listeners
                .into_iter()
                .map(|l| moor_rpc::Listener {
                    handler_object: obj_fb(&l.handler_object),
                    socket_addr: l.socket_addr.to_string(),
                })
                .collect();
            mk_register_host_msg(host_id, timestamp, host_type_fb, listeners_fb)
        }
        HostRequest::HostPong {
            timestamp,
            host_type,
            listeners,
        } => {
            let host_type_fb = encode_host_type(host_type);
            let listeners_fb: Vec<moor_rpc::Listener> = listeners
                .into_iter()
                .map(|l| moor_rpc::Listener {
                    handler_object: obj_fb(&l.handler_object),
                    socket_addr: l.socket_addr.to_string(),
                })
                .collect();
            mk_host_pong_msg(host_id, timestamp, host_type_fb, listeners_fb)
        }
        HostRequest::DetachHost => mk_detach_host_msg(host_id),
        HostRequest::RequestPerformanceCounters => mk_request_performance_counters_msg(),
        HostRequest::GetServerFeatures => mk_get_server_features_msg(),
    }
}

// ===========================================================================
// Decode: raw reply bytes to typed ClientReply / HostReply
// ===========================================================================

fn decode_client_reply_bytes(bytes: &[u8]) -> Result<ClientReply, RpcError> {
    let reply_ref = read_reply_result(bytes)
        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid flatbuffer: {e}")))?;

    match reply_ref
        .result()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing result: {e}")))?
    {
        moor_rpc::ReplyResultUnionRef::ClientSuccess(client_success) => {
            let daemon_reply = client_success
                .reply()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing reply: {e}")))?;
            decode_client_reply_ref(daemon_reply)
        }
        moor_rpc::ReplyResultUnionRef::Failure(failure) => {
            let error_ref = failure
                .error()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing error: {e}")))?;
            let error = rpc_message_error_from_ref(error_ref)
                .map_err(|e| RpcError::CouldNotDecode(format!("Invalid daemon error: {e}")))?;
            Err(RpcError::Daemon(error))
        }
        _ => Err(RpcError::UnexpectedReply(
            "Expected ClientSuccess or Failure".to_string(),
        )),
    }
}

fn decode_host_reply_bytes(bytes: &[u8]) -> Result<HostReply, RpcError> {
    let reply_ref = read_reply_result(bytes)
        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid flatbuffer: {e}")))?;

    match reply_ref
        .result()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing result: {e}")))?
    {
        moor_rpc::ReplyResultUnionRef::HostSuccess(host_success) => {
            let daemon_reply = host_success
                .reply()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing reply: {e}")))?;
            decode_host_reply_ref(daemon_reply)
        }
        moor_rpc::ReplyResultUnionRef::Failure(failure) => {
            let error_ref = failure
                .error()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing error: {e}")))?;
            let error = rpc_message_error_from_ref(error_ref)
                .map_err(|e| RpcError::CouldNotDecode(format!("Invalid daemon error: {e}")))?;
            Err(RpcError::Daemon(error))
        }
        _ => Err(RpcError::UnexpectedReply(
            "Expected HostSuccess or Failure".to_string(),
        )),
    }
}

fn decode_client_reply_ref(
    reply: moor_rpc::DaemonToClientReplyRef<'_>,
) -> Result<ClientReply, RpcError> {
    use moor_rpc::DaemonToClientReplyUnionRef as U;
    use moor_schema::convert::{obj_from_ref, var_from_ref};

    let union = reply
        .reply()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing reply union: {e}")))?;

    Ok(match union {
        U::NewConnection(nc) => {
            let client_token = nc
                .client_token()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing client_token: {e}")))
                .and_then(|r| {
                    client_token_from_ref(r)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid client_token: {e}")))
                })?;
            let connection_obj = nc
                .connection_obj()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing connection_obj: {e}")))
                .and_then(|r| {
                    obj_from_ref(r).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid connection_obj: {e}"))
                    })
                })?;
            ClientReply::NewConnection {
                client_token,
                connection_obj,
            }
        }
        U::LoginResult(lr) => {
            let success = lr.success().unwrap_or(false);
            let auth_token = lr
                .auth_token()
                .ok()
                .flatten()
                .and_then(|r| auth_token_from_ref(r).ok());
            let connect_type = decode_connect_type(
                lr.connect_type()
                    .unwrap_or(moor_rpc::ConnectType::Connected),
            );
            let player = lr
                .player()
                .ok()
                .flatten()
                .and_then(|r| obj_from_ref(r).ok());
            let player_flags = lr.player_flags().unwrap_or(0);
            ClientReply::LoginResult {
                success,
                auth_token,
                connect_type,
                player,
                player_flags,
            }
        }
        U::AttachResult(ar) => {
            let success = ar.success().unwrap_or(false);
            let client_token = ar
                .client_token()
                .ok()
                .flatten()
                .and_then(|r| client_token_from_ref(r).ok());
            let player = ar
                .player()
                .ok()
                .flatten()
                .and_then(|r| obj_from_ref(r).ok());
            let player_flags = ar.player_flags().unwrap_or(0);
            ClientReply::AttachResult {
                success,
                client_token,
                player,
                player_flags,
            }
        }
        U::SysPropValue(sp) => {
            let value = sp.value().ok().flatten().and_then(|v| var_from_ref(v).ok());
            ClientReply::SysPropValue { value }
        }
        U::TaskSubmitted(ts) => {
            let task_id = ts.task_id().unwrap_or(0);
            ClientReply::TaskSubmitted { task_id }
        }
        U::InputThanks(_) => ClientReply::InputThanks,
        U::EvalResult(er) => {
            let result = er
                .result()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing eval result: {e}")))
                .and_then(|r| {
                    var_from_ref(r)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid eval result: {e}")))
                })?;
            ClientReply::EvalResult { result }
        }
        U::ThanksPong(tp) => {
            let timestamp = tp.timestamp().unwrap_or(0);
            ClientReply::ThanksPong { timestamp }
        }
        U::VerbsReply(vr) => {
            let verbs = vr
                .verbs()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verbs: {e}")))?
                .iter()
                .map(|v| {
                    v.map_err(|e| RpcError::CouldNotDecode(format!("Missing verb info: {e}")))
                        .and_then(decode_verb_info)
                })
                .collect::<Result<Vec<_>, _>>()?;
            ClientReply::VerbsReply { verbs }
        }
        U::PropertiesReply(pr) => {
            let properties = pr
                .properties()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing properties: {e}")))?
                .iter()
                .map(|p| {
                    p.map_err(|e| RpcError::CouldNotDecode(format!("Missing property info: {e}")))
                        .and_then(decode_prop_info)
                })
                .collect::<Result<Vec<_>, _>>()?;
            ClientReply::PropertiesReply { properties }
        }
        U::VerbProgramResponseReply(vp) => {
            let response = vp.response().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing verb program response: {e}"))
            })?;
            let response = match response.response() {
                Ok(moor_rpc::VerbProgramResponseUnionRef::VerbProgramSuccess(s)) => {
                    let obj = s
                        .obj()
                        .map_err(|e| RpcError::CouldNotDecode(format!("Missing obj: {e}")))
                        .and_then(|r| {
                            obj_from_ref(r)
                                .map_err(|e| RpcError::CouldNotDecode(format!("Invalid obj: {e}")))
                        })?;
                    let verb_name = s.verb_name().unwrap_or("").to_string();
                    api::VerbProgramResponse::Success { obj, verb_name }
                }
                Ok(moor_rpc::VerbProgramResponseUnionRef::VerbProgramFailure(f)) => {
                    let error = f
                        .error()
                        .map_err(|e| {
                            RpcError::CouldNotDecode(format!("Missing verb program error: {e}"))
                        })
                        .and_then(|r| {
                            verb_program_error_from_ref(r).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid verb program error: {e}"))
                            })
                        })?;
                    api::VerbProgramResponse::Failure {
                        error: moor_common::tasks::SchedulerError::VerbProgramFailed(error),
                    }
                }
                Err(e) => {
                    return Err(RpcError::CouldNotDecode(format!(
                        "Missing verb program response union: {e}"
                    )));
                }
            };
            ClientReply::VerbProgramResponseReply { response }
        }
        U::PropertyValue(pv) => {
            let prop_info = pv
                .prop_info()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing property info: {e}")))
                .and_then(decode_prop_info)?;
            let value = pv
                .value()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing property value: {e}")))
                .and_then(|v| {
                    var_from_ref(v).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid property value: {e}"))
                    })
                })?;
            ClientReply::PropertyValue { prop_info, value }
        }
        U::VerbValue(vv) => {
            let verb_info = vv
                .verb_info()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb info: {e}")))
                .and_then(decode_verb_info)?;
            let code = vv
                .code()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb code: {e}")))?
                .iter()
                .map(|line| {
                    line.map(str::to_string)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid verb code: {e}")))
                })
                .collect::<Result<Vec<_>, _>>()?;
            ClientReply::VerbValue { verb_info, code }
        }
        U::ResolveResult(rr) => {
            let result = rr
                .result()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing resolve result: {e}")))
                .and_then(|r| {
                    var_from_ref(r).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid resolve result: {e}"))
                    })
                })?;
            ClientReply::ResolveResult { result }
        }
        U::HistoryResponseReply(hr) => {
            let response = hr
                .response()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing history response: {e}")))?;
            let events = response
                .events()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing events: {e}")))?
                .iter()
                .filter_map(|e| e.ok())
                .filter_map(|e| {
                    let event_id_bytes = e.event_id().ok()?.data().ok()?;
                    let event_id = Uuid::from_slice(event_id_bytes).ok()?;
                    let player = obj_from_ref(e.player().ok()?).ok()?;
                    Some(api::HistoricalNarrativeEvent {
                        event_id,
                        timestamp: e.timestamp().unwrap_or(0),
                        player,
                        encrypted_blob: e
                            .encrypted_blob()
                            .ok()
                            .map(|b| b.to_vec())
                            .unwrap_or_default(),
                    })
                })
                .collect();
            let time_range_start = response.time_range_start().unwrap_or(0);
            let time_range_end = response.time_range_end().unwrap_or(0);
            let total_events = response.total_events().unwrap_or(0);
            let has_more_before = response.has_more_before().unwrap_or(false);
            let earliest_event_id = response
                .earliest_event_id()
                .ok()
                .flatten()
                .and_then(|u| Uuid::from_slice(u.data().ok()?).ok());
            let latest_event_id = response
                .latest_event_id()
                .ok()
                .flatten()
                .and_then(|u| Uuid::from_slice(u.data().ok()?).ok());
            ClientReply::HistoryResponseReply {
                response: api::HistoryResponse {
                    events,
                    time_range_start,
                    time_range_end,
                    total_events,
                    has_more_before,
                    earliest_event_id,
                    latest_event_id,
                },
            }
        }
        U::CurrentPresentations(cp) => {
            let presentations = cp
                .presentations()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing presentations: {e}")))?
                .iter()
                .filter_map(|p| p.ok())
                .map(|p| api::PresentationSnapshot {
                    id: p.id().unwrap_or("").to_string(),
                    encrypted_blob: p
                        .encrypted_blob()
                        .ok()
                        .map(|b| b.to_vec())
                        .unwrap_or_default(),
                })
                .collect();
            ClientReply::CurrentPresentations { presentations }
        }
        U::PresentationDismissed(_) => ClientReply::PresentationDismissed,
        U::ClientAttributeSet(_) => ClientReply::ClientAttributeSet,
        U::Disconnected(_) => ClientReply::Disconnected,
        U::EventLogPublicKey(pk) => {
            let public_key = pk
                .public_key()
                .ok()
                .flatten()
                .map(|s| s.to_string())
                .unwrap_or_default();
            ClientReply::EventLogPublicKey { public_key }
        }
        U::EventLogHistoryDeleted(ehd) => {
            let success = ehd.success().unwrap_or(false);
            ClientReply::EventLogHistoryDeleted { success }
        }
        U::ListObjectsReply(lor) => {
            let objects = lor
                .objects()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing objects: {e}")))?
                .iter()
                .filter_map(|o| {
                    let o = o.ok()?;
                    let obj = obj_from_ref(o.obj().ok()?).unwrap_or(moor_var::SYSTEM_OBJECT);
                    Some(api::ObjectInfo {
                        obj,
                        name: o
                            .name()
                            .ok()
                            .flatten()
                            .and_then(|s| s.value().ok().map(moor_var::Symbol::mk)),
                        parent: o.parent().ok().flatten().and_then(|p| obj_from_ref(p).ok()),
                        owner: obj_from_ref(o.owner().ok()?).unwrap_or(moor_var::SYSTEM_OBJECT),
                        flags: o.flags().unwrap_or(0),
                        location: o
                            .location()
                            .ok()
                            .flatten()
                            .and_then(|l| obj_from_ref(l).ok()),
                        contents_count: o.contents_count().unwrap_or(0),
                        verbs_count: o.verbs_count().unwrap_or(0),
                        properties_count: o.properties_count().unwrap_or(0),
                    })
                })
                .collect();
            ClientReply::ListObjectsReply { objects }
        }
        U::PropertyUpdated(_) => ClientReply::PropertyUpdated,
        U::SystemHandlerResponseReply(shr) => {
            let response = shr.response().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing system handler response: {e}"))
            })?;
            let response = match response {
                moor_rpc::SystemHandlerResponseUnionRef::SystemHandlerSuccess(s) => {
                    let result = s
                        .result()
                        .map_err(|e| RpcError::CouldNotDecode(format!("Missing result: {e}")))
                        .and_then(|r| {
                            var_from_ref(r).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid result: {e}"))
                            })
                        })?;
                    api::SystemHandlerResponse::Success { result }
                }
                moor_rpc::SystemHandlerResponseUnionRef::SystemHandlerError(e) => {
                    let error = e
                        .error()
                        .map_err(|e| {
                            RpcError::CouldNotDecode(format!("Missing scheduler error: {e}"))
                        })
                        .and_then(|r| {
                            scheduler_error_from_ref(r).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid scheduler error: {e}"))
                            })
                        })?;
                    api::SystemHandlerResponse::Error { error }
                }
            };
            ClientReply::SystemHandlerResponseReply { response }
        }
        U::VerbCallResponse(vcr) => {
            let response = vcr.response().map_err(|e| {
                RpcError::CouldNotDecode(format!("Missing verb call response: {e}"))
            })?;
            let response = match response {
                moor_rpc::VerbCallResponseUnionRef::VerbCallSuccess(s) => {
                    let result = s
                        .result()
                        .map_err(|e| RpcError::CouldNotDecode(format!("Missing result: {e}")))
                        .and_then(|r| {
                            var_from_ref(r).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid result: {e}"))
                            })
                        })?;
                    let output = s
                        .output()
                        .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb output: {e}")))?
                        .iter()
                        .filter_map(|event| {
                            event
                                .ok()
                                .and_then(|event| convert::narrative_event_from_ref(event).ok())
                        })
                        .collect();
                    api::VerbCallResponse::Success { result, output }
                }
                moor_rpc::VerbCallResponseUnionRef::VerbCallError(e) => {
                    let error = e
                        .error()
                        .map_err(|e| {
                            RpcError::CouldNotDecode(format!("Missing scheduler error: {e}"))
                        })
                        .and_then(|r| {
                            scheduler_error_from_ref(r).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid scheduler error: {e}"))
                            })
                        })?;
                    api::VerbCallResponse::Error { error }
                }
            };
            ClientReply::VerbCallResponse { response }
        }
        U::BatchWorldStateReply(bws) => {
            let results = bws
                .results()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing world-state results: {e}")))?
                .iter()
                .map(|entry| {
                    entry
                        .map_err(|e| {
                            RpcError::CouldNotDecode(format!("Missing world-state result: {e}"))
                        })
                        .and_then(decode_world_state_result_entry)
                })
                .collect::<Result<Vec<_>, _>>()?;
            ClientReply::BatchWorldStateReply { results }
        }
    })
}

fn decode_prop_info(
    prop_info: moor_schema::common::PropInfoRef<'_>,
) -> Result<(PropDef, PropPerms), RpcError> {
    use moor_schema::convert::{obj_from_ref, symbol_from_ref};

    let definer = prop_info
        .definer()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing property definer: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid definer: {e}")))
        })?;
    let location = prop_info
        .location()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing property location: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid location: {e}")))
        })?;
    let name = prop_info
        .name()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing property name: {e}")))
        .and_then(|s| {
            symbol_from_ref(s).map_err(|e| RpcError::CouldNotDecode(format!("Invalid name: {e}")))
        })?;
    let owner = prop_info
        .owner()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing property owner: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid owner: {e}")))
        })?;

    let mut flags = BitEnum::new();
    if prop_info.r().unwrap_or(false) {
        flags |= PropFlag::Read;
    }
    if prop_info.w().unwrap_or(false) {
        flags |= PropFlag::Write;
    }
    if prop_info.chown().unwrap_or(false) {
        flags |= PropFlag::Chown;
    }

    Ok((
        PropDef::new(Uuid::nil(), definer, location, name),
        PropPerms::new(owner, flags),
    ))
}

fn decode_verb_info(verb_info: moor_schema::common::VerbInfoRef<'_>) -> Result<VerbDef, RpcError> {
    use moor_schema::convert::{obj_from_ref, symbol_from_ref};

    let location = verb_info
        .location()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb location: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid location: {e}")))
        })?;
    let owner = verb_info
        .owner()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb owner: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid owner: {e}")))
        })?;
    let names = verb_info
        .names()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb names: {e}")))?
        .iter()
        .map(|s| {
            s.map_err(|e| RpcError::CouldNotDecode(format!("Missing verb name: {e}")))
                .and_then(|s| {
                    symbol_from_ref(s)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid verb name: {e}")))
                })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let mut flags = BitEnum::new();
    if verb_info.r().unwrap_or(false) {
        flags |= VerbFlag::Read;
    }
    if verb_info.w().unwrap_or(false) {
        flags |= VerbFlag::Write;
    }
    if verb_info.x().unwrap_or(false) {
        flags |= VerbFlag::Exec;
    }
    if verb_info.d().unwrap_or(false) {
        flags |= VerbFlag::Debug;
    }

    Ok(VerbDef::new(
        Uuid::nil(),
        location,
        owner,
        &names,
        flags,
        decode_verb_args(verb_info)?,
    ))
}

fn decode_verb_args(
    verb_info: moor_schema::common::VerbInfoRef<'_>,
) -> Result<VerbArgsSpec, RpcError> {
    use moor_schema::convert::symbol_from_ref;

    let arg_spec = verb_info
        .arg_spec()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb argument spec: {e}")))?
        .iter()
        .map(|s| {
            s.map_err(|e| RpcError::CouldNotDecode(format!("Missing argument spec: {e}")))
                .and_then(|s| {
                    symbol_from_ref(s).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid argument spec: {e}"))
                    })
                })
        })
        .collect::<Result<Vec<_>, _>>()?;

    if arg_spec.len() != 3 {
        return Err(RpcError::CouldNotDecode(format!(
            "Expected 3 verb argument spec entries, got {}",
            arg_spec.len()
        )));
    }

    let dobj = ArgSpec::from_string(&arg_spec[0].as_string()).ok_or_else(|| {
        RpcError::CouldNotDecode(format!(
            "Invalid direct object argument spec: {}",
            arg_spec[0]
        ))
    })?;
    let prep = PrepSpec::parse(&arg_spec[1].as_string()).ok_or_else(|| {
        RpcError::CouldNotDecode(format!(
            "Invalid preposition argument spec: {}",
            arg_spec[1]
        ))
    })?;
    let iobj = ArgSpec::from_string(&arg_spec[2].as_string()).ok_or_else(|| {
        RpcError::CouldNotDecode(format!(
            "Invalid indirect object argument spec: {}",
            arg_spec[2]
        ))
    })?;

    Ok(VerbArgsSpec { dobj, prep, iobj })
}

fn decode_object_info(info: moor_rpc::ObjectInfoRef<'_>) -> Result<api::ObjectInfo, RpcError> {
    use moor_schema::convert::{obj_from_ref, symbol_from_ref};

    let obj = info
        .obj()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing object id: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid object id: {e}")))
        })?;
    let owner = info
        .owner()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing object owner: {e}")))
        .and_then(|o| {
            obj_from_ref(o).map_err(|e| RpcError::CouldNotDecode(format!("Invalid owner: {e}")))
        })?;
    let name = info
        .name()
        .ok()
        .flatten()
        .map(symbol_from_ref)
        .transpose()
        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid object name: {e}")))?;
    let parent = info
        .parent()
        .ok()
        .flatten()
        .map(obj_from_ref)
        .transpose()
        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid parent: {e}")))?;
    let location = info
        .location()
        .ok()
        .flatten()
        .map(obj_from_ref)
        .transpose()
        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid location: {e}")))?;

    Ok(api::ObjectInfo {
        obj,
        name,
        parent,
        owner,
        flags: info.flags().unwrap_or(0),
        location,
        contents_count: info.contents_count().unwrap_or(0),
        verbs_count: info.verbs_count().unwrap_or(0),
        properties_count: info.properties_count().unwrap_or(0),
    })
}

fn decode_world_state_result_entry(
    entry: moor_rpc::WorldStateResultEntryRef<'_>,
) -> Result<api::WorldStateResultEntry, RpcError> {
    let id = entry
        .id()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing world-state result id: {e}")))?
        .to_string();
    let result = entry
        .result()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing world-state result value: {e}")))
        .and_then(decode_world_state_result)?;

    Ok(api::WorldStateResultEntry { id, result })
}

fn decode_world_state_result(
    result: moor_rpc::WorldStateResultUnionRef<'_>,
) -> Result<api::WorldStateResult, RpcError> {
    use moor_rpc::WorldStateResultUnionRef as W;
    use moor_schema::convert::{obj_from_ref, var_from_ref};

    Ok(match result {
        W::WsPropertyResult(r) => {
            let (propdef, propperms) = r
                .prop_info()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing property info: {e}")))
                .and_then(decode_prop_info)?;
            let value = r
                .value()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing property value: {e}")))
                .and_then(|v| {
                    var_from_ref(v).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid property value: {e}"))
                    })
                })?;
            api::WorldStateResult::Property(propdef, propperms, value)
        }
        W::WsPropertiesResult(r) => {
            let properties = r
                .properties()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing properties: {e}")))?
                .iter()
                .map(|p| {
                    p.map_err(|e| RpcError::CouldNotDecode(format!("Missing property info: {e}")))
                        .and_then(decode_prop_info)
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::Properties(properties)
        }
        W::WsSystemPropertyResult(r) => {
            let value = r
                .value()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing system property: {e}")))
                .and_then(|v| {
                    var_from_ref(v).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid system property: {e}"))
                    })
                })?;
            api::WorldStateResult::SystemProperty(value)
        }
        W::WsVerbsResult(r) => {
            let verbs = r
                .verbs()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verbs: {e}")))?
                .iter()
                .map(|v| {
                    v.map_err(|e| RpcError::CouldNotDecode(format!("Missing verb info: {e}")))
                        .and_then(decode_verb_info)
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::Verbs(moor_common::model::VerbDefs::from_items(&verbs))
        }
        W::WsVerbCodeResult(r) => {
            let verbdef = r
                .verb_info()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb info: {e}")))
                .and_then(decode_verb_info)?;
            let code = r
                .code()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing verb code: {e}")))?
                .iter()
                .map(|line| {
                    line.map(str::to_string)
                        .map_err(|e| RpcError::CouldNotDecode(format!("Invalid verb code: {e}")))
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::VerbCode(verbdef, code)
        }
        W::WsResolveResult(r) => {
            let value = r
                .result()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing resolve result: {e}")))
                .and_then(|v| {
                    var_from_ref(v).map_err(|e| {
                        RpcError::CouldNotDecode(format!("Invalid resolve result: {e}"))
                    })
                })?;
            api::WorldStateResult::ResolvedObject(value)
        }
        W::WsObjectsListResult(r) => {
            let objects = r
                .objects()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing object list: {e}")))?
                .iter()
                .map(|o| {
                    o.map_err(|e| RpcError::CouldNotDecode(format!("Missing object info: {e}")))
                        .and_then(decode_object_info)
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::ObjectsList(objects)
        }
        W::WsAllObjectsResult(r) => {
            let objects = r
                .objects()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing objects: {e}")))?
                .iter()
                .map(|o| {
                    o.map_err(|e| RpcError::CouldNotDecode(format!("Missing object: {e}")))
                        .and_then(|o| {
                            obj_from_ref(o).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid object: {e}"))
                            })
                        })
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::AllObjects(objects)
        }
        W::WsPropertyUpdatedResult(_) => api::WorldStateResult::PropertyUpdated,
        W::WsObjectFlagsResult(r) => api::WorldStateResult::ObjectFlags(r.flags().unwrap_or(0)),
        W::WsQueryObjectsResult(r) => {
            let objects = r
                .objects()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing query objects: {e}")))?
                .iter()
                .map(|o| {
                    o.map_err(|e| RpcError::CouldNotDecode(format!("Missing object: {e}")))
                        .and_then(|o| {
                            obj_from_ref(o).map_err(|e| {
                                RpcError::CouldNotDecode(format!("Invalid object: {e}"))
                            })
                        })
                })
                .collect::<Result<Vec<_>, _>>()?;
            api::WorldStateResult::QueriedObjects(objects)
        }
        W::WsVerbProgrammedResult(_) => {
            return Err(RpcError::CouldNotDecode(
                "typed API has no world-state verb-programmed result".to_string(),
            ));
        }
        W::WsActionError(_) => {
            return Err(RpcError::CouldNotDecode(
                "typed API has no world-state action-error result".to_string(),
            ));
        }
    })
}

fn decode_host_reply_ref(reply: moor_rpc::DaemonToHostReplyRef<'_>) -> Result<HostReply, RpcError> {
    use moor_rpc::DaemonToHostReplyUnionRef as U;

    let union = reply
        .reply()
        .map_err(|e| RpcError::CouldNotDecode(format!("Missing reply union: {e}")))?;

    Ok(match union {
        U::DaemonToHostAck(_) => HostReply::Ack,
        U::DaemonToHostReject(reject) => {
            let reason = reject.reason().unwrap_or("").to_string();
            HostReply::Reject { reason }
        }
        U::DaemonToHostPerfCounters(pc) => {
            let timestamp = pc.timestamp().unwrap_or(0);
            let counters = pc
                .counters()
                .map_err(|e| RpcError::CouldNotDecode(format!("Missing counters: {e}")))?
                .iter()
                .filter_map(|c| c.ok())
                .map(|c| {
                    let category = c
                        .category()
                        .ok()
                        .and_then(|s| s.value().ok().map(moor_var::Symbol::mk))
                        .unwrap_or(moor_var::Symbol::mk(""));
                    let counters = c
                        .counters()
                        .ok()
                        .map(|cs| {
                            cs.iter()
                                .filter_map(|cn| cn.ok())
                                .map(|cn| api::CounterSample {
                                    name: cn
                                        .name()
                                        .ok()
                                        .and_then(|s| s.value().ok().map(moor_var::Symbol::mk))
                                        .unwrap_or(moor_var::Symbol::mk("")),
                                    count: cn.count().unwrap_or(0),
                                    total_cumulative_ns: cn.total_cumulative_ns().unwrap_or(0),
                                })
                                .collect()
                        })
                        .unwrap_or_default();
                    api::CounterCategory { category, counters }
                })
                .collect();
            HostReply::PerformanceCounters {
                timestamp,
                counters,
            }
        }
        U::ServerFeatures(sf) => {
            let features = api::ServerFeatures {
                persistent_tasks: sf.persistent_tasks().unwrap_or(false),
                rich_notify: sf.rich_notify().unwrap_or(false),
                lexical_scopes: true,
                type_dispatch: sf.type_dispatch().unwrap_or(false),
                flyweight_type: sf.flyweight_type().unwrap_or(false),
                list_comprehensions: true,
                bool_type: sf.bool_type().unwrap_or(false),
                use_boolean_returns: sf.use_boolean_returns().unwrap_or(false),
                symbol_type: sf.symbol_type().unwrap_or(false),
                use_symbols_in_builtins: sf.use_symbols_in_builtins().unwrap_or(false),
                custom_errors: sf.custom_errors().unwrap_or(false),
                use_uuobjids: sf.use_uuobjids().unwrap_or(false),
                enable_eventlog: sf.enable_eventlog().unwrap_or(false),
                anonymous_objects: sf.anonymous_objects().unwrap_or(false),
            };
            HostReply::ServerFeatures(features)
        }
    })
}

// ===========================================================================
// Helper functions
// ===========================================================================

fn encode_host_type(host_type: HostType) -> moor_rpc::HostType {
    match host_type {
        HostType::TCP => moor_rpc::HostType::Tcp,
        HostType::WebSocket => moor_rpc::HostType::WebSocket,
    }
}

fn decode_connect_type(ct: moor_rpc::ConnectType) -> api::ConnectType {
    match ct {
        moor_rpc::ConnectType::Connected => api::ConnectType::Connected,
        moor_rpc::ConnectType::Reconnected => api::ConnectType::Reconnected,
        moor_rpc::ConnectType::Created => api::ConnectType::Created,
        moor_rpc::ConnectType::NoConnect => api::ConnectType::NoConnect,
    }
}

fn encode_history_recall(recall: api::HistoryRecall) -> moor_rpc::HistoryRecall {
    let recall_union = match recall {
        api::HistoryRecall::SinceEvent { event_id, limit } => {
            moor_rpc::HistoryRecallUnion::HistoryRecallSinceEvent(Box::new(
                moor_rpc::HistoryRecallSinceEvent {
                    event_id: uuid_fb(event_id),
                    limit: limit.unwrap_or(0) as u64,
                },
            ))
        }
        api::HistoryRecall::UntilEvent { event_id, limit } => {
            moor_rpc::HistoryRecallUnion::HistoryRecallUntilEvent(Box::new(
                moor_rpc::HistoryRecallUntilEvent {
                    event_id: uuid_fb(event_id),
                    limit: limit.unwrap_or(0) as u64,
                },
            ))
        }
        api::HistoryRecall::SinceSeconds { seconds_ago, limit } => {
            moor_rpc::HistoryRecallUnion::HistoryRecallSinceSeconds(Box::new(
                moor_rpc::HistoryRecallSinceSeconds {
                    seconds_ago,
                    limit: limit.unwrap_or(0) as u64,
                },
            ))
        }
        api::HistoryRecall::None => moor_rpc::HistoryRecallUnion::HistoryRecallNone(Box::new(
            moor_rpc::HistoryRecallNone {},
        )),
    };
    moor_rpc::HistoryRecall {
        recall: recall_union,
    }
}

fn encode_batch_action(action: api::BatchAction) -> moor_rpc::WorldStateActionUnion {
    use moor_runtime_api::{
        ws_get_object_flags, ws_list_objects, ws_program_verb, ws_query_objects,
        ws_request_all_objects, ws_request_properties, ws_request_property,
        ws_request_system_property, ws_request_verb_code, ws_request_verbs, ws_resolve_object,
        ws_update_property,
    };

    match action {
        api::BatchAction::RequestProperty { obj, property } => ws_request_property(&obj, &property),
        api::BatchAction::RequestProperties { obj, inherited } => {
            ws_request_properties(&obj, inherited)
        }
        api::BatchAction::RequestSystemProperty { obj, property } => {
            ws_request_system_property(&obj, &property)
        }
        api::BatchAction::RequestVerbs { obj, inherited } => ws_request_verbs(&obj, inherited),
        api::BatchAction::RequestVerbCode { obj, verb } => ws_request_verb_code(&obj, &verb),
        api::BatchAction::ResolveObject { objref } => ws_resolve_object(&objref),
        api::BatchAction::ListObjects => ws_list_objects(),
        api::BatchAction::RequestAllObjects => ws_request_all_objects(),
        api::BatchAction::UpdateProperty {
            obj,
            property,
            value,
        } => ws_update_property(&obj, &property, &value).unwrap_or_else(ws_list_objects),
        api::BatchAction::ProgramVerb {
            obj,
            verb_name,
            code,
        } => ws_program_verb(&obj, &verb_name, code),
        api::BatchAction::GetObjectFlags { obj } => ws_get_object_flags(&obj),
        api::BatchAction::QueryObjects {
            parent,
            location,
            owner,
            flags_all,
            flags_any,
        } => ws_query_objects(
            parent.as_ref(),
            location.as_ref(),
            owner.as_ref(),
            flags_all,
            flags_any,
        ),
    }
}
