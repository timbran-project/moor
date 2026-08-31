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

//! Command invocation over HTTP.

use super::invocation_response;
use crate::host::{
    WebHost,
    auth::StatelessAuth,
    flatbuffer_response,
    negotiate::{
        BOTH_FORMATS, ResponseFormat, TEXT_PLAIN_CONTENT_TYPE, invocation_response_to_json,
        negotiate_response_format, require_content_type,
    },
};
use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use moor_runtime_api::api::{ClientRequest, InvocationMode};
use tracing::error;

pub async fn command_handler(
    State(host): State<WebHost>,
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    body: Bytes,
) -> Response {
    if let Err(status) = require_content_type(
        header_map.get(header::CONTENT_TYPE),
        &[TEXT_PLAIN_CONTENT_TYPE],
        true,
    ) {
        return status.into_response();
    }

    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(format) => format,
        Err(status) => return status.into_response(),
    };

    let command = match std::str::from_utf8(&body) {
        Ok(command) => command.trim_end_matches(&['\r', '\n'][..]).to_string(),
        Err(_) => return StatusCode::BAD_REQUEST.into_response(),
    };
    let request = ClientRequest::Command {
        auth_token,
        handler_object: host.handler_object,
        command,
        mode: InvocationMode::CaptureOutput { timeout: None },
    };
    let reply = match rpc_client.client_call(client_id, request).await {
        Ok(reply) => reply,
        Err(error) => {
            error!(?error, "Command RPC failed");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };
    let response = match invocation_response(reply) {
        Ok(response) => response,
        Err(status) => return status.into_response(),
    };

    match format {
        ResponseFormat::FlatBuffers => {
            let mut builder = planus::Builder::new();
            flatbuffer_response(builder.finish(&response, None).to_vec())
        }
        ResponseFormat::Json => {
            invocation_response_to_json(&response).unwrap_or_else(|status| status.into_response())
        }
    }
}
