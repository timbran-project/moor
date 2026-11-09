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

//! Authentication endpoints, extractors, and session-token validation.

mod oauth2;
mod oauth2_handlers;

pub use oauth2::{OAuth2Config, OAuth2Manager, PendingOAuth2Store};
pub use oauth2_handlers::{
    OAuth2State, oauth2_account_choice_handler, oauth2_app_account_choice_handler,
    oauth2_app_exchange_handler, oauth2_app_start_handler, oauth2_authorize_handler,
    oauth2_callback_handler, oauth2_config_handler, oauth2_exchange_handler,
};

use crate::host::{
    WebHost,
    web_host::{LoginType, WsHostError},
};
use axum::{
    Form,
    body::Body,
    extract::{ConnectInfo, FromRequestParts, State},
    http::{HeaderMap, StatusCode, request::Parts},
    response::{IntoResponse, Response},
};
use moor_common::model::ObjectRef;
use moor_runtime_api::{
    AuthToken, ClientToken, RpcError, RpcMessageError,
    api::{ClientReply, ClientRequest, RuntimeClient},
    api_codec::encode_client_success_bytes,
};
use serde_derive::Deserialize;
use std::{net::SocketAddr, sync::Arc};
use tracing::{debug, error, warn};
use uuid::Uuid;

pub fn extract_auth_token_header(header_map: &HeaderMap) -> Result<AuthToken, StatusCode> {
    header_map
        .get("X-Moor-Auth-Token")
        .and_then(|value| value.to_str().ok())
        .map(|token| AuthToken(token.to_string()))
        .ok_or(StatusCode::UNAUTHORIZED)
}

pub fn extract_client_credentials(header_map: &HeaderMap) -> Option<(Uuid, ClientToken)> {
    let client_token = header_map
        .get("X-Moor-Client-Token")
        .and_then(|value| value.to_str().ok())
        .map(|token| ClientToken(token.to_string()))?;
    let client_id = header_map
        .get("X-Moor-Client-Id")
        .and_then(|value| value.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())?;
    Some((client_id, client_token))
}

/// Auth extractor for stateless (fire-and-forget) RPC calls.
/// No daemon-side connection state — just a token, a throwaway client_id, and an RPC client.
pub struct StatelessAuth {
    pub auth_token: AuthToken,
    pub client_id: Uuid,
    pub rpc_client: Arc<dyn RuntimeClient>,
}

impl FromRequestParts<WebHost> for StatelessAuth {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &WebHost,
    ) -> Result<Self, Self::Rejection> {
        let auth_token = extract_auth_token_header(&parts.headers)?;
        let (client_id, rpc_client) = state.new_stateless_client();
        Ok(StatelessAuth {
            auth_token,
            client_id,
            rpc_client,
        })
    }
}

#[derive(Deserialize)]
pub struct AuthRequest {
    player: String,
    password: String,
}

pub async fn connect_auth_handler(
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(ws_host): State<WebHost>,
    Form(AuthRequest { player, password }): Form<AuthRequest>,
) -> impl IntoResponse {
    auth_handler(LoginType::Connect, addr, ws_host, player, password).await
}

pub async fn create_auth_handler(
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(ws_host): State<WebHost>,
    Form(AuthRequest { player, password }): Form<AuthRequest>,
) -> impl IntoResponse {
    auth_handler(LoginType::Create, addr, ws_host, player, password).await
}

/// Stand-alone HTTP POST authentication handler which connects and then gets a valid authentication token
/// which can then be used in the headers/query-string for subsequent websocket request.
async fn auth_handler(
    login_type: LoginType,
    addr: SocketAddr,
    host: WebHost,
    player: String,
    password: String,
) -> impl IntoResponse {
    debug!("Authenticating player: {}", player);
    let (client_id, rpc_client, client_token) = match host.establish_client_connection(addr).await {
        Ok((client_id, rpc_client, client_token)) => (client_id, rpc_client, client_token),
        Err(WsHostError::AuthenticationFailed) => {
            warn!("Authentication failed for {}", player);
            return StatusCode::FORBIDDEN.into_response();
        }
        Err(e) => {
            error!("Unable to establish connection: {}", e);
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
    };

    let auth_verb = match login_type {
        LoginType::Connect => "connect",
        LoginType::Create => "create",
    };

    let words = vec![auth_verb.to_string(), player, password];
    let login_msg = ClientRequest::LoginCommand {
        client_token: client_token.clone(),
        handler_object: host.handler_object,
        connect_args: words,
        do_attach: false,
        registration_data: None,
    };

    let reply = match rpc_client.client_call(client_id, login_msg).await {
        Ok(reply) => reply,
        Err(e) => {
            error!("Unable to send login request to RPC server: {}", e);
            return StatusCode::SERVICE_UNAVAILABLE.into_response();
        }
    };

    let auth_token = match auth_token_from_login_reply(&reply) {
        Ok(auth_token) => auth_token,
        Err(status) => return status.into_response(),
    };

    let reply_bytes = match encode_client_success_bytes(reply) {
        Ok(reply_bytes) => reply_bytes,
        Err(e) => {
            error!("Failed to encode login reply: {}", e);
            return StatusCode::BAD_GATEWAY.into_response();
        }
    };

    // Keep the connection alive - WebSocket will reattach to it, preserving the connection ID
    // from :do_login_command. This is the user's "real" connection.
    match Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/x-flatbuffers")
        .header("X-Moor-Auth-Token", auth_token.0)
        .header("X-Moor-Client-Token", client_token.0.clone())
        .header("X-Moor-Client-Id", client_id.to_string())
        .body(Body::from(reply_bytes))
    {
        Ok(response) => response,
        Err(e) => {
            error!("Failed to build auth response: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

fn auth_token_from_login_reply(reply: &ClientReply) -> Result<AuthToken, StatusCode> {
    let ClientReply::LoginResult {
        success,
        auth_token,
        ..
    } = reply
    else {
        error!("Unexpected reply type");
        return Err(StatusCode::BAD_GATEWAY);
    };

    if !success {
        error!("Login failed");
        return Err(StatusCode::UNAUTHORIZED);
    }

    let Some(auth_token) = auth_token else {
        error!("LoginResult missing auth token");
        return Err(StatusCode::BAD_GATEWAY);
    };

    Ok(auth_token.clone())
}

/// Validate an auth token by round-tripping to the daemon.
///
/// This opens no connection. A connection opened and closed here would be the player's last when
/// they have no other, and closing it would run the world's disconnect hooks.
/// Returns:
///   200 — token is valid
///   401 — token is invalid or expired
///   503 — daemon is unreachable
pub async fn validate_auth_handler(
    StatelessAuth {
        auth_token,
        client_id,
        rpc_client,
    }: StatelessAuth,
) -> impl IntoResponse {
    let reply = rpc_client
        .client_call(client_id, ClientRequest::ValidateAuth { auth_token })
        .await;
    let (player, player_flags) = match reply {
        Ok(ClientReply::AttachResult {
            success: true,
            player: Some(player),
            player_flags,
            ..
        }) => (player, player_flags),
        Ok(ClientReply::AttachResult { .. })
        | Err(RpcError::Daemon(RpcMessageError::PermissionDenied))
        | Err(RpcError::AuthenticationError(_)) => {
            return StatusCode::UNAUTHORIZED.into_response();
        }
        Ok(other) => {
            error!(?other, "Unexpected reply to auth validation");
            return StatusCode::INTERNAL_SERVER_ERROR.into_response();
        }
        Err(e) => {
            warn!(error = ?e, "Unable to validate auth token");
            return StatusCode::SERVICE_UNAVAILABLE.into_response();
        }
    };
    debug!("Auth token validated via daemon");
    match Response::builder()
        .status(StatusCode::OK)
        .header("X-Moor-Player", ObjectRef::Id(player).to_curie())
        .header("X-Moor-Player-Flags", player_flags.to_string())
        .body(Body::empty())
    {
        Ok(response) => response,
        Err(e) => {
            error!("Failed to build auth validation response: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

/// Explicit logout endpoint that notifies daemon that player is disconnecting
pub async fn logout_handler(
    State(host): State<WebHost>,
    header_map: HeaderMap,
) -> impl IntoResponse {
    // Verify auth token is present (though we don't use it directly)
    let _auth_token = match extract_auth_token_header(&header_map) {
        Ok(token) => token,
        Err(status) => return status.into_response(),
    };

    // Client credentials are required for logout
    let (client_id, client_token) = match extract_client_credentials(&header_map) {
        Some(creds) => creds,
        None => {
            debug!("No client credentials provided for logout");
            return StatusCode::UNAUTHORIZED.into_response();
        }
    };

    debug!("Processing explicit logout for client: {}", client_id);

    let rpc_client = host.create_rpc_client();

    match rpc_client
        .client_call(
            client_id,
            ClientRequest::Detach {
                client_token,
                disconnected: true,
            },
        )
        .await
    {
        Ok(_) => {
            debug!("Logout detach sent successfully");
            StatusCode::OK.into_response()
        }
        Err(e) => {
            error!("Failed to send logout detach: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}
