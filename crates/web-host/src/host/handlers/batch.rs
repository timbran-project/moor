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

//! Batch world state operation endpoints

use crate::host::{
    auth::StatelessAuth,
    flatbuffer_response,
    negotiate::{
        BOTH_FORMATS, FLATBUFFERS_CONTENT_TYPE, JSON_CONTENT_TYPE, ResponseFormat,
        negotiate_response_format, reply_result_to_json, require_content_type,
    },
    web_host,
};
use axum::{
    body::Bytes,
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use moor_runtime_api::{
    api::{BatchActionEntry, ClientRequest},
    api_codec::{decode_batch_action, decode_owned_batch_actions},
};
use moor_schema::rpc as moor_rpc;
use planus::ReadAsRoot;
use tracing::error;

#[derive(serde::Deserialize)]
struct BatchRequest {
    actions: Vec<BatchActionJson>,
    #[serde(default)]
    rollback: bool,
}

#[derive(serde::Deserialize)]
struct BatchActionJson {
    id: String,
    action: moor_rpc::WorldStateActionUnion,
}

pub async fn batch_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
    header_map: HeaderMap,
    body: Bytes,
) -> Response {
    let format = match negotiate_response_format(
        header_map.get(header::ACCEPT),
        BOTH_FORMATS,
        ResponseFormat::FlatBuffers,
    ) {
        Ok(f) => f,
        Err(status) => return status.into_response(),
    };

    let content_type = header_map.get(header::CONTENT_TYPE);

    let batch = if require_content_type(content_type, &[FLATBUFFERS_CONTENT_TYPE], false).is_ok() {
        decode_flatbuffer_batch(&body)
    } else if require_content_type(content_type, &[JSON_CONTENT_TYPE], false).is_ok() {
        decode_json_batch(&body)
    } else {
        return StatusCode::UNSUPPORTED_MEDIA_TYPE.into_response();
    };
    let (actions, rollback) = match batch {
        Ok(batch) => batch,
        Err(e) => {
            error!("Failed to parse batch request: {e}");
            return StatusCode::BAD_REQUEST.into_response();
        }
    };

    let batch_msg = ClientRequest::BatchWorldState {
        auth_token,
        actions,
        rollback,
    };

    let reply_bytes = match web_host::rpc_call(client_id, &rpc_client, batch_msg).await {
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

fn decode_flatbuffer_batch(body: &[u8]) -> Result<(Vec<BatchActionEntry>, bool), String> {
    let batch = moor_rpc::BatchWorldStateRef::read_as_root(body).map_err(|e| e.to_string())?;
    let action_refs = batch.actions().map_err(|e| e.to_string())?;
    let actions = action_refs
        .iter()
        .enumerate()
        .map(|(index, entry)| {
            let entry = entry.map_err(|e| format!("invalid action {index}: {e}"))?;
            let id = entry
                .id()
                .map_err(|e| format!("invalid action {index} id: {e}"))?;
            let action = entry
                .action()
                .map_err(|e| format!("invalid action {index}: {e}"))?;
            let action =
                decode_batch_action(action).map_err(|e| format!("invalid action {index}: {e}"))?;
            Ok(BatchActionEntry {
                id: id.into(),
                action,
            })
        })
        .collect::<Result<Vec<_>, String>>()?;
    let rollback = batch.rollback().map_err(|e| e.to_string())?;
    Ok((actions, rollback))
}

fn decode_json_batch(body: &[u8]) -> Result<(Vec<BatchActionEntry>, bool), String> {
    let request: BatchRequest = serde_json::from_slice(body).map_err(|e| e.to_string())?;
    let encoded_actions = request
        .actions
        .into_iter()
        .map(|action| moor_rpc::WorldStateActionEntry {
            id: action.id,
            action: action.action,
        })
        .collect();
    let actions = decode_owned_batch_actions(encoded_actions).map_err(|e| e.to_string())?;
    Ok((actions, request.rollback))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn json_batch_decodes_every_action() {
        let body = br#"{
            "actions": [
                {"id": "first", "action": {"WsListObjects": {}}},
                {"id": "second", "action": {"WsRequestAllObjects": {}}}
            ],
            "rollback": true
        }"#;

        let (actions, rollback) = decode_json_batch(body).unwrap();
        assert_eq!(actions.len(), 2);
        assert_eq!(actions[0].id, "first");
        assert_eq!(actions[1].id, "second");
        assert!(rollback);
    }

    #[test]
    fn malformed_json_batch_is_rejected() {
        let body = br#"{
            "actions": [
                {"id": "valid", "action": {"WsListObjects": {}}},
                {"id": "invalid", "action": {"NotAnAction": {}}}
            ]
        }"#;

        assert!(decode_json_batch(body).is_err());
    }
}
