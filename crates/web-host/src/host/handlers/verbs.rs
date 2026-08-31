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
use moor_runtime_api::{
    api::{ClientReply, ClientRequest, EntityType, InvocationMode},
    api_codec::encode_verb_call_response,
};
use moor_schema::{convert::var_from_flatbuffer_ref, rpc as moor_rpc, var as moor_var_schema};
use moor_var::Symbol;
use planus::ReadAsRoot;
use serde::Deserialize;
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
    // root task commits, and answers once the call finishes. Leaving the deadline to the daemon
    // means a daemon configured below the protocol maximum is not asked for more than it allows.
    let invoke_msg = ClientRequest::InvokeVerb {
        auth_token,
        object: object_ref,
        verb: verb_symbol,
        args: moo_args,
        mode: InvocationMode::CaptureOutput { timeout: None },
    };

    // This endpoint answers with a bare VerbCallResponse rather than the ReplyResult envelope the
    // other endpoints use, so take the typed reply and encode only the final HTTP form.
    let reply = match rpc_client.client_call(client_id, invoke_msg).await {
        Ok(reply) => reply,
        Err(e) => {
            error!("RPC failure: {e:?}");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let response = match verb_call_response(reply) {
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

/// Turn the daemon's typed reply to a verb invocation into the FlatBuffer this endpoint returns.
fn verb_call_response(reply: ClientReply) -> Result<moor_rpc::VerbCallResponse, StatusCode> {
    let ClientReply::VerbCallResponse { response } = reply else {
        error!("Unexpected daemon reply to a verb invocation: {reply:?}");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    };
    encode_verb_call_response(response).map_err(|e| {
        error!("Failed to encode verb call response: {e:?}");
        StatusCode::INTERNAL_SERVER_ERROR
    })
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
    use moor_common::tasks::{NarrativeEvent, SchedulerError};
    use moor_runtime_api::api::{VerbCallOutcome, VerbCallResponse};
    use moor_var::{Obj, v_int, v_obj, v_str};

    #[test]
    fn a_verb_call_result_and_its_output_survive_encoding() {
        let event = NarrativeEvent::notify(
            v_obj(Obj::mk_id(1)),
            v_str("said something"),
            None,
            false,
            false,
            None,
        );
        let reply = ClientReply::VerbCallResponse {
            response: VerbCallResponse {
                outcome: VerbCallOutcome::Success { result: v_int(7) },
                output: vec![event],
            },
        };

        let encoded = verb_call_response(reply).expect("Should encode the response");
        let moor_rpc::VerbCallResponseUnion::VerbCallSuccess(success) = encoded.response else {
            panic!("Expected a success response");
        };
        assert_eq!(encoded.output.len(), 1);
        assert!(matches!(
            success.result.variant,
            moor_var_schema::VarUnion::VarInt(_)
        ));
    }

    #[test]
    fn a_task_error_is_encoded_as_a_verb_call_error() {
        let reply = ClientReply::VerbCallResponse {
            response: VerbCallResponse {
                outcome: VerbCallOutcome::Error {
                    error: SchedulerError::TaskAbortedCancelled,
                },
                output: vec![NarrativeEvent::notify(
                    v_obj(Obj::mk_id(1)),
                    v_str("before failure"),
                    None,
                    false,
                    false,
                    None,
                )],
            },
        };

        let encoded = verb_call_response(reply).expect("Should encode the response");
        assert!(matches!(
            encoded.response,
            moor_rpc::VerbCallResponseUnion::VerbCallError(_)
        ));
        assert_eq!(encoded.output.len(), 1);
    }

    #[test]
    fn a_reply_that_is_not_a_verb_call_response_is_an_error() {
        let reply = ClientReply::TaskSubmitted { task_id: 1 };

        assert_eq!(
            verb_call_response(reply),
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        );
    }
}
