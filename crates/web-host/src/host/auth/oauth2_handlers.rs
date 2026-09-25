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

//! HTTP handlers for OAuth2 authentication endpoints.

use super::oauth2::{FlowBinding, OAuth2Manager, PendingOAuth2Code, PendingOAuth2Store};
use crate::host::WebHost;
use axum::{
    Json,
    extract::{ConnectInfo, Path, Query, State},
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Redirect, Response},
};
use moor_common::model::ObjectRef;
use moor_runtime_api::{
    AuthToken, ClientToken,
    api::{ClientReply, ClientRequest, RuntimeClient},
};
use moor_var::Obj;
use serde_derive::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

const OAUTH2_NONCE_COOKIE: &str = "moor_oauth_nonce";
const OAUTH2_NONCE_COOKIE_MAX_AGE: u64 = 600;

fn extract_cookie_value(headers: &HeaderMap, name: &str) -> Option<String> {
    let cookie_header = headers.get(header::COOKIE)?.to_str().ok()?;
    for part in cookie_header.split(';') {
        let trimmed = part.trim();
        if let Some((cookie_name, value)) = trimmed.split_once('=')
            && cookie_name == name
        {
            return Some(value.to_string());
        }
    }
    None
}

fn make_nonce_cookie_value(nonce: &str, max_age_seconds: u64, secure: bool) -> String {
    let mut value = format!(
        "{}={}; Max-Age={}; Path=/; HttpOnly; SameSite=Lax",
        OAUTH2_NONCE_COOKIE, nonce, max_age_seconds
    );
    if secure {
        value.push_str("; Secure");
    }
    value
}

fn attach_set_cookie(mut response: Response, cookie: &str) -> Response {
    if let Ok(cookie_value) = cookie.parse() {
        response
            .headers_mut()
            .append(header::SET_COOKIE, cookie_value);
    }
    response
}

/// Shared state for OAuth2 handlers
#[derive(Clone)]
pub struct OAuth2State {
    pub manager: Arc<OAuth2Manager>,
    pub web_host: WebHost,
    pub pending: Arc<PendingOAuth2Store>,
}

/// Response for authorization URL request
#[derive(Serialize)]
pub struct AuthUrlResponse {
    pub auth_url: String,
    pub state: String,
}

/// Response for app-bound OAuth2 start request
#[derive(Serialize)]
pub struct AppAuthUrlResponse {
    pub auth_url: String,
}

/// Response for OAuth2 configuration
#[derive(Serialize)]
pub struct OAuth2ConfigResponse {
    pub enabled: bool,
    pub providers: Vec<String>,
}

/// Query parameters for OAuth2 callback
#[derive(Deserialize)]
pub struct OAuth2CallbackQuery {
    pub code: String,
    pub state: String,
}

/// Response for successful OAuth2 login
#[derive(Serialize)]
pub struct OAuth2LoginResponse {
    pub success: bool,
    pub auth_token: Option<String>,
    pub player: Option<String>,
    pub player_flags: Option<u16>,
    pub client_token: Option<String>,
    pub client_id: Option<String>,
    pub error: Option<String>,
}

struct OAuthLoginSuccess {
    auth_token: AuthToken,
    player: Obj,
    player_flags: u16,
}

async fn call_oauth_login(
    rpc_client: &Arc<dyn RuntimeClient>,
    client_id: Uuid,
    client_token: &ClientToken,
    args: Vec<String>,
    do_attach: bool,
) -> Result<ClientReply, moor_runtime_api::RpcError> {
    rpc_client
        .client_call(
            client_id,
            ClientRequest::VerifiedOAuthLogin {
                client_token: client_token.clone(),
                connect_args: args,
                do_attach,
            },
        )
        .await
}

fn oauth_login_success(reply: ClientReply) -> Result<Option<OAuthLoginSuccess>, &'static str> {
    let ClientReply::LoginResult {
        success,
        auth_token,
        player,
        player_flags,
        ..
    } = reply
    else {
        return Err("Unexpected reply type from daemon");
    };

    if !success {
        return Ok(None);
    }

    let auth_token = auth_token.ok_or("Missing auth_token in login result")?;
    let player = player.ok_or("Missing player in login result")?;
    Ok(Some(OAuthLoginSuccess {
        auth_token,
        player,
        player_flags,
    }))
}

/// Request body for code exchange (both existing-user auth and new-user identity)
#[derive(Deserialize)]
pub struct CodeExchangeRequest {
    pub code: String,
}

/// Request body for app-bound OAuth2 flow start
#[derive(Deserialize)]
pub struct AppStartRequest {
    pub redirect_uri: String,
    pub intent: Option<String>,
    pub code_challenge: String,
    pub code_challenge_method: String,
}

/// Request body for app-bound handoff code exchange
#[derive(Deserialize)]
pub struct AppExchangeRequest {
    pub handoff_code: String,
    pub code_verifier: String,
}

/// Request body for account choice submission.
/// The `oauth2_code` is a one-time server-side code that resolves to the verified identity.
#[derive(Deserialize)]
pub struct AccountChoiceRequest {
    pub mode: String,                      // "oauth2_create" or "oauth2_connect"
    pub oauth2_code: String,               // One-time code from callback redirect
    pub player_name: Option<String>,       // For oauth2_create
    pub existing_email: Option<String>,    // For oauth2_connect
    pub existing_password: Option<String>, // For oauth2_connect
}

/// Request body for app-bound account choice submission.
#[derive(Deserialize)]
pub struct AppAccountChoiceRequest {
    pub mode: String,                      // "oauth2_create" or "oauth2_connect"
    pub identity_code: String,             // One-time identity code from app exchange
    pub code_verifier: String,             // PKCE verifier for proof binding
    pub player_name: Option<String>,       // For oauth2_create
    pub existing_email: Option<String>,    // For oauth2_connect
    pub existing_password: Option<String>, // For oauth2_connect
}

fn append_query_param(uri: &str, key: &str, value: &str) -> Option<String> {
    let mut parsed = url::Url::parse(uri).ok()?;
    parsed.query_pairs_mut().append_pair(key, value);
    Some(parsed.into())
}

/// GET /auth/oauth2/:provider/authorize
/// Generate and return OAuth2 authorization URL for the specified provider
pub async fn oauth2_authorize_handler(
    State(oauth2_state): State<OAuth2State>,
    Path(provider): Path<String>,
) -> impl IntoResponse {
    debug!("OAuth2 authorization request for provider: {}", provider);

    if !oauth2_state.manager.is_enabled() {
        warn!("OAuth2 is not enabled");
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "OAuth2 not enabled"})),
        )
            .into_response();
    }

    match oauth2_state.manager.get_authorization_url(&provider) {
        Ok((auth_url, csrf_token)) => {
            let state = csrf_token.secret().clone();
            let browser_nonce = uuid::Uuid::new_v4().to_string();
            oauth2_state.pending.store_csrf_token(
                &provider,
                &state,
                FlowBinding::Cookie {
                    browser_nonce: browser_nonce.clone(),
                },
            );
            info!("Generated OAuth2 authorization URL for {}", provider);
            let response = Json(AuthUrlResponse { auth_url, state }).into_response();
            attach_set_cookie(
                response,
                &make_nonce_cookie_value(
                    &browser_nonce,
                    OAUTH2_NONCE_COOKIE_MAX_AGE,
                    oauth2_state.manager.oauth_cookie_secure(),
                ),
            )
        }
        Err(e) => {
            error!("Failed to generate authorization URL: {}", e);
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid provider: {}", e)})),
            )
                .into_response()
        }
    }
}

/// POST /auth/oauth2/:provider/app/start
/// Start a proof-bound OAuth2 flow suitable for desktop/mobile/browser clients.
pub async fn oauth2_app_start_handler(
    State(oauth2_state): State<OAuth2State>,
    Path(provider): Path<String>,
    Json(request): Json<AppStartRequest>,
) -> impl IntoResponse {
    debug!("OAuth2 app start request for provider: {}", provider);

    if !oauth2_state.manager.is_enabled() {
        warn!("OAuth2 is not enabled");
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "OAuth2 not enabled"})),
        )
            .into_response();
    }

    if request.code_challenge_method != "S256" {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Only S256 code_challenge_method is supported"})),
        )
            .into_response();
    }
    if request.code_challenge.is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "code_challenge is required"})),
        )
            .into_response();
    }
    if !oauth2_state
        .manager
        .app_redirect_allowed(&request.redirect_uri)
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "redirect_uri is not allowed"})),
        )
            .into_response();
    }

    match oauth2_state.manager.get_authorization_url(&provider) {
        Ok((auth_url, csrf_token)) => {
            let state = csrf_token.secret().clone();
            oauth2_state.pending.store_csrf_token(
                &provider,
                &state,
                FlowBinding::Proof {
                    redirect_uri: request.redirect_uri,
                    code_challenge: request.code_challenge,
                    code_challenge_method: request.code_challenge_method,
                    intent: request.intent,
                },
            );
            Json(AppAuthUrlResponse { auth_url }).into_response()
        }
        Err(e) => {
            error!("Failed to generate authorization URL: {}", e);
            (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid provider: {}", e)})),
            )
                .into_response()
        }
    }
}

/// GET /auth/oauth2/:provider/callback
/// Handle OAuth2 provider callback with authorization code
pub async fn oauth2_callback_handler(
    State(oauth2_state): State<OAuth2State>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(provider): Path<String>,
    Query(query): Query<OAuth2CallbackQuery>,
    headers: HeaderMap,
) -> impl IntoResponse {
    debug!("OAuth2 callback from provider: {} with code", provider);

    if !oauth2_state.manager.is_enabled() {
        warn!("OAuth2 is not enabled");
        return Redirect::to("/?error=oauth2_disabled").into_response();
    }

    let browser_nonce = extract_cookie_value(&headers, OAUTH2_NONCE_COOKIE);
    let Some(flow_binding) =
        oauth2_state
            .pending
            .consume_csrf_token(&provider, &query.state, browser_nonce.as_deref())
    else {
        warn!("Invalid or expired CSRF state token in OAuth2 callback");
        return Redirect::to("/?error=invalid_state").into_response();
    };

    // Complete OAuth2 flow: exchange code and get user info
    let user_info = match oauth2_state
        .manager
        .complete_oauth2_flow(&provider, query.code)
        .await
    {
        Ok(info) => info,
        Err(e) => {
            error!("OAuth2 flow failed: {}", e);
            return Redirect::to(&format!("/?error=oauth2_failed&details={e}")).into_response();
        }
    };

    info!(
        "OAuth2 flow completed for provider {}, external_id: {}",
        provider, user_info.external_id
    );

    // Check if this OAuth2 identity already exists in the system
    let (client_id, rpc_client, client_token) = match oauth2_state
        .web_host
        .establish_client_connection(addr)
        .await
    {
        Ok(connection) => connection,
        Err(e) => {
            error!("Failed to establish RPC connection: {}", e);
            return Redirect::to("/?error=internal_error").into_response();
        }
    };

    let check_args = vec![
        "oauth2_check".to_string(),
        provider.clone(),
        user_info.external_id.clone(),
    ];

    let reply =
        match call_oauth_login(&rpc_client, client_id, &client_token, check_args, false).await {
            Ok(reply) => reply,
            Err(e) => {
                error!("RPC call failed: {}", e);
                return Redirect::to("/?error=internal_error").into_response();
            }
        };

    if let Some(login) = match oauth_login_success(reply) {
        Ok(login) => login,
        Err(e) => {
            error!("{}", e);
            return Redirect::to("/?error=unexpected_reply").into_response();
        }
    } {
        // Existing user — store auth session server-side, redirect with one-time code
        info!(
            "Existing OAuth2 user logged in: {} (flags: {})",
            login.player, login.player_flags
        );

        let player_curie = ObjectRef::Id(login.player).to_curie();
        let pending = PendingOAuth2Code::AuthSession {
            auth_token: login.auth_token,
            player_curie,
            player_flags: login.player_flags,
            client_token,
            client_id,
        };
        let Some(code) = oauth2_state
            .pending
            .store_pending_code(pending, flow_binding.clone())
        else {
            error!("Failed to store pending auth code");
            return Redirect::to("/?error=internal_error").into_response();
        };
        match flow_binding {
            FlowBinding::Cookie { .. } => {
                Redirect::to(&format!("/#auth_code={}", code)).into_response()
            }
            FlowBinding::Proof { redirect_uri, .. } => {
                let Some(redirect_url) = append_query_param(&redirect_uri, "handoff_code", &code)
                else {
                    error!("Invalid proof-bound redirect URI");
                    return Redirect::to("/?error=internal_error").into_response();
                };
                Redirect::to(&redirect_url).into_response()
            }
        }
    } else {
        // New user — store verified identity server-side, redirect with one-time code + display hints
        let display_info = serde_json::json!({
            "email": user_info.email,
            "name": user_info.name,
            "username": user_info.username,
            "provider": user_info.provider,
        });
        let pending = PendingOAuth2Code::Identity(user_info);
        let Some(code) = oauth2_state
            .pending
            .store_pending_code(pending, flow_binding.clone())
        else {
            error!("Failed to store pending identity code");
            return Redirect::to("/?error=internal_error").into_response();
        };
        match flow_binding {
            FlowBinding::Cookie { .. } => {
                let display_str = display_info.to_string();
                let redirect_url = format!(
                    "/#oauth2_code={}&oauth2_display={}",
                    code,
                    urlencoding::encode(&display_str),
                );
                Redirect::to(&redirect_url).into_response()
            }
            FlowBinding::Proof { redirect_uri, .. } => {
                let Some(redirect_url) = append_query_param(&redirect_uri, "handoff_code", &code)
                else {
                    error!("Invalid proof-bound redirect URI");
                    return Redirect::to("/?error=internal_error").into_response();
                };
                Redirect::to(&redirect_url).into_response()
            }
        }
    }
}

/// POST /auth/oauth2/exchange
/// Exchange a one-time code for auth tokens (existing user) or identity info (new user).
/// Both code types are stored server-side and consumed on use.
pub async fn oauth2_exchange_handler(
    State(oauth2_state): State<OAuth2State>,
    headers: HeaderMap,
    Json(request): Json<CodeExchangeRequest>,
) -> impl IntoResponse {
    let Some(browser_nonce) = extract_cookie_value(&headers, OAUTH2_NONCE_COOKIE) else {
        warn!("Missing OAuth2 browser nonce cookie in exchange request");
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Missing OAuth2 browser nonce"})),
        )
            .into_response();
    };

    let payload = match oauth2_state
        .pending
        .redeem_pending_code_cookie(&request.code, &browser_nonce)
    {
        Some(payload) => payload,
        None => {
            warn!("Invalid or expired code in exchange request");
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({"error": "Invalid or expired code"})),
            )
                .into_response();
        }
    };

    match payload {
        PendingOAuth2Code::AuthSession {
            auth_token,
            player_curie,
            player_flags,
            client_token,
            client_id,
        } => Json(serde_json::json!({
            "type": "auth_session",
            "auth_token": auth_token.0,
            "player": player_curie,
            "player_flags": player_flags,
            "client_token": client_token.0,
            "client_id": client_id.to_string(),
        }))
        .into_response(),

        PendingOAuth2Code::Identity(user_info) => Json(serde_json::json!({
            "type": "identity",
            "provider": user_info.provider,
            "email": user_info.email,
            "name": user_info.name,
            "username": user_info.username,
        }))
        .into_response(),
    }
}

/// POST /auth/oauth2/app/exchange
/// Exchange a proof-bound handoff code for auth session data or identity data.
pub async fn oauth2_app_exchange_handler(
    State(oauth2_state): State<OAuth2State>,
    Json(request): Json<AppExchangeRequest>,
) -> impl IntoResponse {
    let Some((payload, binding)) = oauth2_state
        .pending
        .redeem_pending_code_proof_with_binding(&request.handoff_code, &request.code_verifier)
    else {
        warn!("Invalid or expired handoff_code in app exchange request");
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Invalid or expired handoff_code"})),
        )
            .into_response();
    };

    match payload {
        PendingOAuth2Code::AuthSession {
            auth_token,
            player_curie,
            player_flags,
            client_token,
            client_id,
        } => Json(serde_json::json!({
            "type": "auth_session",
            "auth_token": auth_token.0,
            "player": player_curie,
            "player_flags": player_flags,
            "client_token": client_token.0,
            "client_id": client_id.to_string(),
        }))
        .into_response(),
        PendingOAuth2Code::Identity(user_info) => {
            let Some(identity_code) = oauth2_state
                .pending
                .store_pending_code(PendingOAuth2Code::Identity(user_info.clone()), binding)
            else {
                error!("Failed to store identity code in app exchange");
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "Internal error"})),
                )
                    .into_response();
            };
            Json(serde_json::json!({
                "type": "identity",
                "identity_code": identity_code,
                "provider": user_info.provider,
                "email": user_info.email,
                "name": user_info.name,
                "username": user_info.username,
            }))
            .into_response()
        }
    }
}

/// POST /auth/oauth2/account
/// Handle account choice submission (create new or link existing).
/// The `oauth2_code` in the request is a one-time server-side code that resolves
/// to the verified provider identity. This prevents client-side tampering with
/// external_id or other identity fields.
pub async fn oauth2_account_choice_handler(
    State(oauth2_state): State<OAuth2State>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    Json(choice): Json<AccountChoiceRequest>,
) -> impl IntoResponse {
    debug!("OAuth2 account choice: mode={}", choice.mode);

    if !oauth2_state.manager.is_enabled() {
        warn!("OAuth2 is not enabled");
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "OAuth2 not enabled"})),
        )
            .into_response();
    }

    // Validate mode
    if choice.mode != "oauth2_create" && choice.mode != "oauth2_connect" {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Invalid mode, must be oauth2_create or oauth2_connect"})),
        ).into_response();
    }

    let Some(browser_nonce) = extract_cookie_value(&headers, OAUTH2_NONCE_COOKIE) else {
        warn!("Missing OAuth2 browser nonce cookie in account choice");
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Missing OAuth2 browser nonce"})),
        )
            .into_response();
    };

    // Redeem the one-time code — must resolve to an Identity variant
    let user_info = match oauth2_state
        .pending
        .redeem_pending_code_cookie(&choice.oauth2_code, &browser_nonce)
    {
        Some(PendingOAuth2Code::Identity(info)) => info,
        Some(_) => {
            warn!("Code resolved to wrong type (expected identity)");
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid code type for account choice"})),
            )
                .into_response();
        }
        None => {
            warn!("Invalid or expired OAuth2 code in account choice");
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({"error": "Invalid or expired OAuth2 code"})),
            )
                .into_response();
        }
    };

    info!(
        "Verified OAuth2 identity: provider={}, external_id={}",
        user_info.provider, user_info.external_id
    );

    // Build verified-login arguments from the consumed server-side identity.
    let final_args = if choice.mode == "oauth2_create" {
        vec![
            choice.mode.clone(),
            user_info.provider,
            user_info.external_id,
            user_info.email.unwrap_or_default(),
            user_info.name.unwrap_or_default(),
            user_info.username.unwrap_or_default(),
            choice.player_name.clone().unwrap_or_default(),
        ]
    } else {
        // oauth2_connect
        vec![
            choice.mode.clone(),
            user_info.provider,
            user_info.external_id,
            user_info.email.unwrap_or_default(),
            user_info.name.unwrap_or_default(),
            user_info.username.unwrap_or_default(),
            choice.existing_email.clone().unwrap_or_default(),
            choice.existing_password.clone().unwrap_or_default(),
        ]
    };

    // Establish RPC connection
    let (client_id, rpc_client, client_token) = match oauth2_state
        .web_host
        .establish_client_connection(addr)
        .await
    {
        Ok(connection) => connection,
        Err(e) => {
            error!("Failed to establish RPC connection: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to establish connection"})),
            )
                .into_response();
        }
    };

    let reply =
        match call_oauth_login(&rpc_client, client_id, &client_token, final_args, true).await {
            Ok(reply) => reply,
            Err(e) => {
                error!("RPC call failed: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "RPC call failed"})),
                )
                    .into_response();
            }
        };

    let login = match oauth_login_success(reply) {
        Ok(Some(login)) => login,
        Ok(None) => {
            error!("Account choice failed");
            return (
                StatusCode::UNAUTHORIZED,
                Json(OAuth2LoginResponse {
                    success: false,
                    auth_token: None,
                    player: None,
                    player_flags: None,
                    client_token: None,
                    client_id: None,
                    error: Some("Authentication failed".to_string()),
                }),
            )
                .into_response();
        }
        Err(e) => {
            error!("{}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Internal error"})),
            )
                .into_response();
        }
    };

    info!(
        "OAuth2 account {} successful (player: {}, flags: {})",
        choice.mode, login.player, login.player_flags
    );

    Json(OAuth2LoginResponse {
        success: true,
        auth_token: Some(login.auth_token.0),
        player: Some(ObjectRef::Id(login.player).to_curie()),
        player_flags: Some(login.player_flags),
        client_token: Some(client_token.0.clone()),
        client_id: Some(client_id.to_string()),
        error: None,
    })
    .into_response()
}

/// POST /auth/oauth2/app/account
/// Handle proof-bound account choice submission (create new or link existing).
pub async fn oauth2_app_account_choice_handler(
    State(oauth2_state): State<OAuth2State>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(choice): Json<AppAccountChoiceRequest>,
) -> impl IntoResponse {
    debug!("OAuth2 app account choice: mode={}", choice.mode);

    if !oauth2_state.manager.is_enabled() {
        warn!("OAuth2 is not enabled");
        return (
            StatusCode::NOT_FOUND,
            Json(serde_json::json!({"error": "OAuth2 not enabled"})),
        )
            .into_response();
    }

    if choice.mode != "oauth2_create" && choice.mode != "oauth2_connect" {
        return (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({"error": "Invalid mode, must be oauth2_create or oauth2_connect"})),
        )
            .into_response();
    }

    let user_info = match oauth2_state
        .pending
        .redeem_pending_code_proof(&choice.identity_code, &choice.code_verifier)
    {
        Some(PendingOAuth2Code::Identity(info)) => info,
        Some(_) => {
            warn!("Code resolved to wrong type (expected identity)");
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": "Invalid code type for account choice"})),
            )
                .into_response();
        }
        None => {
            warn!("Invalid or expired identity_code in app account choice");
            return (
                StatusCode::UNAUTHORIZED,
                Json(serde_json::json!({"error": "Invalid or expired identity_code"})),
            )
                .into_response();
        }
    };

    info!(
        "Verified OAuth2 identity: provider={}, external_id={}",
        user_info.provider, user_info.external_id
    );

    let final_args = if choice.mode == "oauth2_create" {
        vec![
            choice.mode.clone(),
            user_info.provider,
            user_info.external_id,
            user_info.email.unwrap_or_default(),
            user_info.name.unwrap_or_default(),
            user_info.username.unwrap_or_default(),
            choice.player_name.clone().unwrap_or_default(),
        ]
    } else {
        vec![
            choice.mode.clone(),
            user_info.provider,
            user_info.external_id,
            user_info.email.unwrap_or_default(),
            user_info.name.unwrap_or_default(),
            user_info.username.unwrap_or_default(),
            choice.existing_email.clone().unwrap_or_default(),
            choice.existing_password.clone().unwrap_or_default(),
        ]
    };

    let (client_id, rpc_client, client_token) = match oauth2_state
        .web_host
        .establish_client_connection(addr)
        .await
    {
        Ok(connection) => connection,
        Err(e) => {
            error!("Failed to establish RPC connection: {}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Failed to establish connection"})),
            )
                .into_response();
        }
    };

    let reply =
        match call_oauth_login(&rpc_client, client_id, &client_token, final_args, true).await {
            Ok(reply) => reply,
            Err(e) => {
                error!("RPC call failed: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(serde_json::json!({"error": "RPC call failed"})),
                )
                    .into_response();
            }
        };

    let login = match oauth_login_success(reply) {
        Ok(Some(login)) => login,
        Ok(None) => {
            error!("Account choice failed");
            return (
                StatusCode::UNAUTHORIZED,
                Json(OAuth2LoginResponse {
                    success: false,
                    auth_token: None,
                    player: None,
                    player_flags: None,
                    client_token: None,
                    client_id: None,
                    error: Some("Authentication failed".to_string()),
                }),
            )
                .into_response();
        }
        Err(e) => {
            error!("{}", e);
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": "Internal error"})),
            )
                .into_response();
        }
    };

    info!(
        "OAuth2 app account {} successful (player: {}, flags: {})",
        choice.mode, login.player, login.player_flags
    );

    Json(OAuth2LoginResponse {
        success: true,
        auth_token: Some(login.auth_token.0),
        player: Some(ObjectRef::Id(login.player).to_curie()),
        player_flags: Some(login.player_flags),
        client_token: Some(client_token.0.clone()),
        client_id: Some(client_id.to_string()),
        error: None,
    })
    .into_response()
}

/// GET /v1/oauth2/config
/// Return OAuth2 configuration including enabled status and available providers
pub async fn oauth2_config_handler(State(oauth2_state): State<OAuth2State>) -> impl IntoResponse {
    debug!("OAuth2 config request");

    let enabled = oauth2_state.manager.is_enabled();
    let providers = if enabled {
        oauth2_state.manager.available_providers()
    } else {
        Vec::new()
    };

    Json(OAuth2ConfigResponse { enabled, providers }).into_response()
}

#[cfg(test)]
mod tests {
    use super::super::oauth2::{ExternalUserInfo, OAuth2Config};
    use super::*;
    use moor_runtime_api::{
        RpcError,
        api::{
            ClientSubscriptions, ConnectType, HostEventSubscription, HostReply, HostRequest,
            HostServices,
        },
    };
    use std::sync::{Mutex, atomic::AtomicU64};

    #[derive(Default)]
    struct RecordingRuntime(Mutex<Vec<ClientRequest>>);
    #[async_trait::async_trait]
    impl RuntimeClient for RecordingRuntime {
        async fn client_call(
            &self,
            _: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, RpcError> {
            let reply = match &request {
                ClientRequest::ConnectionEstablish { .. } => ClientReply::NewConnection {
                    client_token: ClientToken("fixture".into()),
                    connection_obj: Obj::mk_id(-10),
                },
                ClientRequest::VerifiedOAuthLogin { .. } => ClientReply::LoginResult {
                    success: false,
                    auth_token: None,
                    player: None,
                    player_flags: 0,
                    connect_type: ConnectType::Connected,
                },
                other => panic!("unexpected OAuth request: {other:?}"),
            };
            self.0.lock().unwrap().push(request);
            Ok(reply)
        }
        async fn host_call(&self, _: Uuid, _: HostRequest) -> Result<HostReply, RpcError> {
            panic!("unexpected host call")
        }
    }
    struct Services(Arc<RecordingRuntime>);
    impl HostServices for Services {
        fn runtime_client(&self) -> Arc<dyn RuntimeClient> {
            self.0.clone()
        }
        fn client_subscriptions(
            &self,
            _: Uuid,
            _: ClientToken,
        ) -> Result<ClientSubscriptions, RpcError> {
            panic!("unexpected subscription")
        }
        fn host_events(&self) -> Result<Box<dyn HostEventSubscription>, RpcError> {
            panic!("unexpected subscription")
        }
    }
    fn state(runtime: Arc<RecordingRuntime>) -> OAuth2State {
        OAuth2State {
            manager: Arc::new(
                OAuth2Manager::new(OAuth2Config {
                    enabled: true,
                    ..Default::default()
                })
                .unwrap(),
            ),
            web_host: WebHost::new(
                Obj::mk_id(99),
                8080,
                Uuid::new_v4(),
                Arc::new(AtomicU64::new(0)),
                Arc::new(Services(runtime)),
                Arc::new(vec![]),
                Arc::new(Default::default()),
            ),
            pending: Arc::new(PendingOAuth2Store::new()),
        }
    }
    async fn choose(state: OAuth2State, code: &str, nonce: &str) -> StatusCode {
        let mut headers = HeaderMap::new();
        headers.insert(
            header::COOKIE,
            format!("{OAUTH2_NONCE_COOKIE}={nonce}").parse().unwrap(),
        );
        oauth2_account_choice_handler(
            State(state),
            ConnectInfo("127.0.0.1:12345".parse().unwrap()),
            headers,
            Json(AccountChoiceRequest {
                mode: "oauth2_create".into(),
                oauth2_code: code.into(),
                player_name: Some("TestPlayer".into()),
                existing_email: None,
                existing_password: None,
            }),
        )
        .await
        .into_response()
        .status()
    }
    #[tokio::test]
    async fn oauth_account_choice_requires_bound_one_time_identity() {
        let runtime = Arc::new(RecordingRuntime::default());
        let state = state(runtime.clone());
        assert_eq!(
            choose(state.clone(), "forged", "browser").await,
            StatusCode::UNAUTHORIZED
        );
        assert!(runtime.0.lock().unwrap().is_empty());
        let identity = PendingOAuth2Code::Identity(ExternalUserInfo {
            provider: "probe".into(),
            external_id: "Verified-ID".into(),
            email: None,
            name: None,
            username: None,
        });
        let binding = FlowBinding::Cookie {
            browser_nonce: "browser".into(),
        };
        let wrong_browser = state
            .pending
            .store_pending_code(identity.clone(), binding.clone())
            .unwrap();
        assert_eq!(
            choose(state.clone(), &wrong_browser, "attacker").await,
            StatusCode::UNAUTHORIZED
        );
        assert!(runtime.0.lock().unwrap().is_empty());
        let code = state.pending.store_pending_code(identity, binding).unwrap();
        // The mock rejects the account, but only after receiving the verified identity.
        assert_eq!(
            choose(state.clone(), &code, "browser").await,
            StatusCode::UNAUTHORIZED
        );
        {
            let calls = runtime.0.lock().unwrap();
            assert_eq!(calls.len(), 2);
            assert!(
                matches!(&calls[1], ClientRequest::VerifiedOAuthLogin { connect_args, do_attach: true, .. }
                if connect_args == &vec!["oauth2_create", "probe", "Verified-ID", "", "", "", "TestPlayer"])
            );
        }
        assert_eq!(
            choose(state.clone(), &code, "browser").await,
            StatusCode::UNAUTHORIZED
        );
        assert_eq!(
            runtime.0.lock().unwrap().len(),
            2,
            "replayed identity must not reach the daemon"
        );
    }
}
