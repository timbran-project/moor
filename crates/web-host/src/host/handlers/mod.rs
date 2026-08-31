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

//! HTTP endpoint handlers that translate REST requests into daemon RPC calls.

mod batch;
mod commands;
mod event_log;
mod objects;
mod props;
mod verbs;
mod webhooks;

pub use batch::batch_handler;
pub use commands::command_handler;
pub use event_log::{
    delete_history_handler, dismiss_presentation_handler, get_pubkey_handler, history_handler,
    presentations_handler, set_pubkey_handler,
};
pub use objects::{list_objects_handler, query_objects_handler, update_property_handler};
pub use props::{properties_handler, property_retrieval_handler};
pub use verbs::{invoke_verb_handler, verb_program_handler, verb_retrieval_handler, verbs_handler};
pub use webhooks::web_hook_handler;

use axum::http::StatusCode;
use moor_common::config::MAX_CAPTURE_DEADLINE_MS;
use moor_runtime_api::{
    RpcError, RpcMessageError,
    api::{ClientReply, ClientRequest, RuntimeClient},
    api_codec::encode_invocation_response,
};
use moor_schema::rpc as moor_rpc;
use serde::Deserialize;
use std::{sync::Arc, time::Duration};
use tracing::error;
use uuid::Uuid;

/// Query parameters shared by HTTP endpoints that wait for a captured task.
#[derive(Debug, Default, Deserialize)]
pub struct CapturedInvocationQuery {
    timeout_ms: Option<u64>,
}

impl CapturedInvocationQuery {
    /// Convert the HTTP timeout to the typed RPC value.
    pub(crate) fn timeout(&self) -> Result<Option<Duration>, StatusCode> {
        let Some(timeout_ms) = self.timeout_ms else {
            return Ok(None);
        };
        if timeout_ms == 0 {
            return Ok(None);
        }
        if timeout_ms > MAX_CAPTURE_DEADLINE_MS {
            return Err(StatusCode::BAD_REQUEST);
        }
        Ok(Some(Duration::from_millis(timeout_ms)))
    }
}

pub(super) fn invocation_response(
    reply: ClientReply,
) -> Result<moor_rpc::InvocationResponse, StatusCode> {
    let ClientReply::InvocationResponse { response } = reply else {
        error!(?reply, "Unexpected daemon reply to captured invocation");
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    };
    encode_invocation_response(response).map_err(|error| {
        error!(?error, "Failed to encode invocation response");
        StatusCode::INTERNAL_SERVER_ERROR
    })
}

/// Run a captured request and convert its daemon reply to the shared response envelope.
pub(super) async fn run_captured_invocation(
    client_id: Uuid,
    rpc_client: &Arc<dyn RuntimeClient>,
    request: ClientRequest,
    operation: &'static str,
) -> Result<moor_rpc::InvocationResponse, StatusCode> {
    let reply = rpc_client
        .client_call(client_id, request)
        .await
        .map_err(|error| {
            error!(?error, operation, "Captured invocation RPC failed");
            captured_rpc_error_status(&error)
        })?;
    invocation_response(reply)
}

fn captured_rpc_error_status(error: &RpcError) -> StatusCode {
    match error {
        RpcError::Daemon(RpcMessageError::InvalidRequest(_)) => StatusCode::BAD_REQUEST,
        RpcError::Daemon(RpcMessageError::PermissionDenied) | RpcError::AuthenticationError(_) => {
            StatusCode::UNAUTHORIZED
        }
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_absent_or_zero_http_timeout_uses_the_daemon_maximum() {
        assert_eq!(CapturedInvocationQuery::default().timeout(), Ok(None));
        assert_eq!(
            CapturedInvocationQuery {
                timeout_ms: Some(0),
            }
            .timeout(),
            Ok(None)
        );
    }

    #[test]
    fn a_positive_http_timeout_becomes_an_rpc_deadline() {
        let uri = "/v1/command?timeout_ms=5000".parse().unwrap();
        let axum::extract::Query(query) =
            axum::extract::Query::<CapturedInvocationQuery>::try_from_uri(&uri).unwrap();
        assert_eq!(query.timeout(), Ok(Some(Duration::from_secs(5))));
    }

    #[test]
    fn a_non_numeric_http_timeout_is_rejected_by_the_query_extractor() {
        let uri = "/v1/command?timeout_ms=soon".parse().unwrap();
        assert!(axum::extract::Query::<CapturedInvocationQuery>::try_from_uri(&uri).is_err());
    }

    #[test]
    fn an_http_timeout_over_the_protocol_maximum_is_rejected() {
        assert_eq!(
            CapturedInvocationQuery {
                timeout_ms: Some(MAX_CAPTURE_DEADLINE_MS + 1),
            }
            .timeout(),
            Err(StatusCode::BAD_REQUEST)
        );
    }

    #[test]
    fn daemon_request_errors_keep_their_http_meaning() {
        assert_eq!(
            captured_rpc_error_status(&RpcError::Daemon(RpcMessageError::InvalidRequest(
                "deadline exceeds daemon maximum".to_string(),
            ))),
            StatusCode::BAD_REQUEST
        );
        assert_eq!(
            captured_rpc_error_status(&RpcError::Daemon(RpcMessageError::PermissionDenied)),
            StatusCode::UNAUTHORIZED
        );
    }
}
