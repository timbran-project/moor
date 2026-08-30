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

//! Verb listing, retrieval, invocation, and programming endpoints.

use crate::host::{
    auth::{EphemeralAuth, StatelessAuth},
    flatbuffer_response,
    negotiate::{
        BOTH_FORMATS, FLATBUFFERS_CONTENT_TYPE, ResponseFormat, TEXT_PLAIN_CONTENT_TYPE,
        negotiate_response_format, reply_result_to_json, require_content_type,
        verb_call_response_to_json,
    },
    web_host,
};
use axum::{
    body::Bytes,
    extract::{Path, Query},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use moor_common::model::ObjectRef;
use moor_runtime_api::api::{ClientRequest, EntityType, InvocationMode};
use moor_schema::{convert::var_from_flatbuffer_ref, rpc as moor_rpc, var as moor_var_schema};
use moor_var::Symbol;
use planus::ReadAsRoot;
use serde::Deserialize;
use std::time::Duration;
use tracing::{debug, error};

#[derive(Deserialize)]
pub struct VerbsQuery {
    inherited: Option<bool>,
}

pub async fn verb_retrieval_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Path((object, name)): Path<(String, String)>,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let Some(object_ref) = ObjectRef::parse_curie(&object) else {
        return StatusCode::BAD_REQUEST.into_response();
    };

    let name = Symbol::mk(&name);

    let retrieve_msg = ClientRequest::Retrieve {
        auth_token,
        object: object_ref,
        entity_type: EntityType::Verb,
        name,
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, retrieve_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

pub async fn verbs_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Path(object): Path<String>,
    Query(query): Query<VerbsQuery>,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let Some(object_ref) = ObjectRef::parse_curie(&object) else {
        return StatusCode::BAD_REQUEST.into_response();
    };

    let inherited = query.inherited.unwrap_or(false);

    let verbs_msg = ClientRequest::Verbs {
        auth_token,
        object: object_ref,
        inherited,
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, verbs_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

/// How long the web host waits for a captured verb invocation to finish.
const INVOKE_VERB_TIMEOUT: Duration = Duration::from_secs(60);

pub async fn invoke_verb_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Path((object_path, verb_name)): Path<(String, String)>,
    body: Bytes,
) -> Response {
    if let Err(status) = require_content_type(
        header_map.get(header::CONTENT_TYPE),
        &[FLATBUFFERS_CONTENT_TYPE],
        true, // allow missing for backwards compat
    ) {
        return status.into_response();
    }
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    debug!(
        "Invoke verb handler: object={}, verb={}, body_len={}",
        object_path,
        verb_name,
        body.len()
    );

    let object_ref = match ObjectRef::parse_curie(&object_path) {
        Some(oref) => oref,
        None => {
            error!("Invalid object CURIE: {}", object_path);
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    let verb_symbol = Symbol::mk(&verb_name);

    // Parse the FlatBuffer request body containing args as a Var (list)
    let args_var = match moor_var_schema::VarRef::read_as_root(&body) {
        Ok(var_ref) => match var_from_flatbuffer_ref(var_ref) {
            Ok(v) => v,
            Err(e) => {
                error!("Failed to parse args var: {}", e);
                return StatusCode::BAD_REQUEST.into_response();
            }
        },
        Err(e) => {
            error!("Failed to parse FlatBuffer args: {}", e);
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    let moo_args: Vec<moor_var::Var> = match args_var.variant() {
        moor_var::Variant::List(l) => l.iter().collect(),
        _ => {
            error!("Args must be a list");
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    // The daemon runs the verb with no connection behind it, collects the narrative output the
    // root task commits, and answers once the call finishes.
    let invoke_msg = ClientRequest::InvokeVerb {
        auth_token,
        object: object_ref,
        verb: verb_symbol,
        args: moo_args,
        mode: InvocationMode::CaptureOutput {
            timeout: Some(INVOKE_VERB_TIMEOUT),
        },
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, invoke_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    // This endpoint answers with a bare VerbCallResponse rather than the ReplyResult envelope the
    // other endpoints use, so unwrap the one the daemon sent.
    let response = match extract_verb_call_response(&reply_bytes) {
        Ok(response) => response,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => {
            let mut builder = planus::Builder::new();
            let response_bytes = builder.finish(&response, None).to_vec();
            flatbuffer_response(response_bytes)
        }
        ResponseFormat::Json => {
            verb_call_response_to_json(&response).unwrap_or_else(|status| status.into_response())
        }
    }
}

/// Pull the `VerbCallResponse` out of an encoded `ReplyResult` from the daemon.
fn extract_verb_call_response(
    reply_bytes: &[u8],
) -> Result<moor_rpc::VerbCallResponse, StatusCode> {
    let reply = moor_rpc::ReplyResult::try_from(
        moor_rpc::ReplyResultRef::read_as_root(reply_bytes).map_err(|e| {
            error!("Failed to read reply: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?,
    )
    .map_err(|e| {
        error!("Failed to convert reply: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let moor_rpc::ReplyResultUnion::ClientSuccess(success) = reply.result else {
        error!("Daemon refused the verb invocation");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    };
    let moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(response) = success.reply.reply else {
        error!("Unexpected daemon reply to a verb invocation");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    };
    Ok(*response)
}

pub async fn verb_program_handler(
    EphemeralAuth {
        auth_token,
        client_id,
        client_token,
        rpc_client,
        ..
    }: EphemeralAuth,
    header_map: HeaderMap,
    Path((object, name)): Path<(String, String)>,
    expression: Bytes,
) -> Response {
    if let Err(status) = require_content_type(
        header_map.get(header::CONTENT_TYPE),
        &[TEXT_PLAIN_CONTENT_TYPE],
        true, // allow missing for backwards compat
    ) {
        return status.into_response();
    }
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let Some(object_ref) = ObjectRef::parse_curie(&object) else {
        return StatusCode::BAD_REQUEST.into_response();
    };

    let name = Symbol::mk(&name);

    let expression = String::from_utf8_lossy(&expression).to_string();

    let code = expression
        .split('\n')
        .map(|s| s.to_string())
        .collect::<Vec<String>>();

    let program_msg = ClientRequest::Program {
        client_token,
        auth_token,
        object: object_ref,
        verb: name,
        code,
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, program_msg).await {
        Ok(bytes) => bytes,
        Err(status) => return status.into_response(),
    };

    // DetachGuard in EphemeralAuth handles cleanup automatically

    match format {
        ResponseFormat::FlatBuffers => flatbuffer_response(reply_bytes),
        ResponseFormat::Json => {
            reply_result_to_json(&reply_bytes).unwrap_or_else(|status| status.into_response())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_schema::convert::var_to_flatbuffer;
    use moor_var::v_int;

    fn encode(reply: moor_rpc::ReplyResult) -> Vec<u8> {
        let mut builder = planus::Builder::new();
        builder.finish(&reply, None).to_vec()
    }

    fn client_success(reply: moor_rpc::DaemonToClientReplyUnion) -> moor_rpc::ReplyResult {
        moor_rpc::ReplyResult {
            result: moor_rpc::ReplyResultUnion::ClientSuccess(Box::new(moor_rpc::ClientSuccess {
                reply: Box::new(moor_rpc::DaemonToClientReply { reply }),
            })),
        }
    }

    #[test]
    fn a_verb_call_response_is_unwrapped_from_the_reply_envelope() {
        let response = moor_rpc::VerbCallResponse {
            response: moor_rpc::VerbCallResponseUnion::VerbCallSuccess(Box::new(
                moor_rpc::VerbCallSuccess {
                    result: Box::new(var_to_flatbuffer(&v_int(7)).unwrap()),
                    output: vec![],
                },
            )),
        };
        let bytes = encode(client_success(
            moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(Box::new(response)),
        ));

        let extracted = extract_verb_call_response(&bytes).expect("Should unwrap the response");
        assert!(matches!(
            extracted.response,
            moor_rpc::VerbCallResponseUnion::VerbCallSuccess(_)
        ));
    }

    #[test]
    fn a_reply_that_is_not_a_verb_call_response_is_an_error() {
        let bytes = encode(client_success(
            moor_rpc::DaemonToClientReplyUnion::TaskSubmitted(Box::new(moor_rpc::TaskSubmitted {
                task_id: 1,
            })),
        ));

        assert_eq!(
            extract_verb_call_response(&bytes),
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        );
    }

    #[test]
    fn a_refused_request_is_an_error() {
        let bytes = encode(moor_rpc::ReplyResult {
            result: moor_rpc::ReplyResultUnion::Failure(Box::new(moor_rpc::Failure {
                error: Box::new(moor_rpc::RpcMessageError {
                    error_code: moor_rpc::RpcMessageErrorCode::PermissionDenied,
                    message: None,
                    scheduler_error: None,
                }),
            })),
        });

        assert_eq!(
            extract_verb_call_response(&bytes),
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        );
    }
}
