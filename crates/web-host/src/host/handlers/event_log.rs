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

//! Event log encryption and history endpoints

use crate::host::{
    auth::StatelessAuth,
    flatbuffer_response,
    negotiate::{BOTH_FORMATS, ResponseFormat, negotiate_response_format, reply_result_to_json},
    web_host::rpc_call,
};
use axum::{
    Json,
    extract::{Path, Query},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use moor_runtime_api::api::{ClientReply, ClientRequest, HistoryRecall};
use serde_derive::Deserialize;
use serde_json::json;
use tracing::error;
use uuid::Uuid;

#[derive(Deserialize)]
pub struct HistoryQuery {
    since_seconds: Option<u64>,
    since_event: Option<String>, // UUID as string
    until_event: Option<String>, // UUID as string
    limit: Option<usize>,
}

pub async fn history_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    Query(query): Query<HistoryQuery>,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let recall = if let Some(since_seconds) = query.since_seconds {
        HistoryRecall::SinceSeconds {
            seconds_ago: since_seconds,
            limit: query.limit,
        }
    } else if let Some(since_event_str) = query.since_event {
        match Uuid::parse_str(&since_event_str) {
            Ok(event_id) => HistoryRecall::SinceEvent {
                event_id,
                limit: query.limit,
            },
            Err(_) => return StatusCode::BAD_REQUEST.into_response(),
        }
    } else if let Some(until_event_str) = query.until_event {
        match Uuid::parse_str(&until_event_str) {
            Ok(event_id) => HistoryRecall::UntilEvent {
                event_id,
                limit: query.limit,
            },
            Err(_) => return StatusCode::BAD_REQUEST.into_response(),
        }
    } else {
        HistoryRecall::None
    };

    let history_msg = ClientRequest::RequestHistory { auth_token, recall };

    let reply_bytes = match rpc_call(client_id, &rpc_client, history_msg).await {
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

/// REST endpoint to get player's event log public key
pub async fn get_pubkey_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
) -> Response {
    let reply = match rpc_client
        .client_call(
            client_id,
            ClientRequest::GetEventLogPublicKey { auth_token },
        )
        .await
    {
        Ok(reply) => reply,
        Err(e) => {
            error!("RPC failure: {:?}", e);
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let ClientReply::EventLogPublicKey { public_key } = reply else {
        error!("Unexpected response type: expected EventLogPublicKey");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };

    let response = Json(json!({
        "public_key": public_key
    }));

    response.into_response()
}

/// REST endpoint to delete all event history for the authenticated player
pub async fn delete_history_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
) -> Response {
    let reply = match rpc_client
        .client_call(
            client_id,
            ClientRequest::DeleteEventLogHistory { auth_token },
        )
        .await
    {
        Ok(reply) => reply,
        Err(e) => {
            error!("RPC failure: {:?}", e);
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let ClientReply::EventLogHistoryDeleted { success } = reply else {
        error!("Unexpected response type: expected EventLogHistoryDeleted");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };

    let response = Json(json!({
        "success": success
    }));

    response.into_response()
}

/// REST endpoint to set player's event log public key
/// Expects JSON body with `public_key` field containing age public key string (age1...)
pub async fn set_pubkey_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    Json(payload): Json<serde_json::Value>,
) -> Response {
    // Extract public key from request
    let public_key = match payload.get("public_key").and_then(|v| v.as_str()) {
        Some(key) => key.to_string(),
        None => {
            return (StatusCode::BAD_REQUEST, "Missing public_key field").into_response();
        }
    };

    let reply = match rpc_client
        .client_call(
            client_id,
            ClientRequest::SetEventLogPublicKey {
                auth_token,
                public_key,
            },
        )
        .await
    {
        Ok(reply) => reply,
        Err(e) => {
            error!("RPC failure: {:?}", e);
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let ClientReply::EventLogPublicKey { public_key } = reply else {
        error!("Unexpected response type: expected EventLogPublicKey");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };

    let response = Json(json!({
        "public_key": public_key,
        "status": "set"
    }));

    response.into_response()
}

/// REST endpoint to dismiss a specific presentation for the authenticated player
pub async fn dismiss_presentation_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    Path(presentation_id): Path<String>,
) -> Response {
    let reply = match rpc_client
        .client_call(
            client_id,
            ClientRequest::DismissPresentation {
                auth_token,
                presentation_id: presentation_id.clone(),
            },
        )
        .await
    {
        Ok(reply) => reply,
        Err(e) => {
            error!("RPC failure: {:?}", e);
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let ClientReply::PresentationDismissed = reply else {
        error!("Unexpected response type: expected PresentationDismissed");
        return StatusCode::INTERNAL_SERVER_ERROR.into_response();
    };

    let response = Json(json!({
        "dismissed": true,
        "presentation_id": presentation_id
    }));

    response.into_response()
}

pub async fn presentations_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let presentations_msg = ClientRequest::RequestCurrentPresentations { auth_token };

    let reply_bytes = match rpc_call(client_id, &rpc_client, presentations_msg).await {
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
