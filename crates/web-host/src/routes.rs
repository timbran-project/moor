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

//! Route table construction, request body limits and CORS.

use axum::{
    Router,
    extract::DefaultBodyLimit,
    routing::{get, post, put},
};
use serde_derive::{Deserialize, Serialize};
use tower_http::cors::{AllowHeaders, AllowMethods, AllowOrigin, CorsLayer};
use tracing::info;

use crate::host::{self, OAuth2State, WebHost};

/// CORS middleware configuration.
/// Disabled by default; when enabled, explicit origins must be provided.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CorsConfig {
    #[serde(default)]
    pub enabled: bool,
    /// Allowed origins. Required when enabled; wildcard "*" is only permitted
    /// when `allow_credentials` is false.
    #[serde(default)]
    pub allowed_origins: Vec<String>,
    #[serde(default)]
    pub allow_credentials: bool,
    /// HTTP methods to allow. Defaults to GET, POST, PUT, DELETE, OPTIONS.
    #[serde(default)]
    pub allowed_methods: Vec<String>,
    /// Headers to allow. Defaults to the common API/auth headers.
    #[serde(default)]
    pub allowed_headers: Vec<String>,
}

/// A removed configuration setting. It serializes as `null` and accepts any value, so files that
/// still set it load, and the host can warn that it is ignored.
#[derive(Debug, Clone, Copy, Default)]
pub struct RemovedSetting;

impl serde::Serialize for RemovedSetting {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_none()
    }
}

impl<'de> serde::Deserialize<'de> for RemovedSetting {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        serde::de::IgnoredAny::deserialize(deserializer).map(|_| RemovedSetting)
    }
}

/// Logged when a configuration still carries the removed `rate_limit` section.
pub const RATE_LIMIT_REMOVED: &str = "The rate_limit setting has been removed and is ignored; \
     rate-limit the /auth/connect and /auth/create endpoints in the reverse proxy instead";

/// HTTP routing options shared by every listener.
#[derive(Debug, Clone)]
pub struct RouteOptions {
    pub enable_webhooks: bool,
    pub cors: CorsConfig,
}

pub fn mk_routes(
    web_host: WebHost,
    oauth2_state: Option<OAuth2State>,
    options: &RouteOptions,
) -> eyre::Result<Router> {
    let auth_routes = Router::new()
        .route("/auth/connect", post(host::connect_auth_handler))
        .route("/auth/create", post(host::create_auth_handler))
        .layer(DefaultBodyLimit::max(64 * 1024))
        .with_state(web_host.clone());

    let mut webhost_router = Router::new()
        .route("/ws/attach/connect", get(host::ws_connect_attach_handler))
        .route("/ws/attach/create", get(host::ws_create_attach_handler))
        .route("/auth/validate", get(host::validate_auth_handler))
        .route("/auth/logout", post(host::logout_handler))
        .route(
            "/v1/system_property/{*path}",
            get(host::system_property_handler),
        )
        .route("/v1/session", post(host::attach_stream_handler))
        .route("/v1/session/command", post(host::session_command_handler))
        .route(
            "/v1/session/input/{request_id}",
            post(host::session_input_handler),
        )
        .route("/v1/events/stream", get(host::event_stream_handler))
        .route("/v1/events/ack", post(host::acknowledge_events_handler))
        .route("/v1/command", post(host::command_handler))
        .route("/v1/eval", post(host::eval_handler))
        .route("/v1/features", get(host::features_handler))
        .route("/health", get(host::health_handler))
        .route("/version", get(host::version_handler))
        .route("/openapi.yaml", get(host::openapi_handler))
        .route(
            "/v1/invoke_welcome_message",
            get(host::invoke_welcome_message_handler),
        )
        .route(
            "/v1/verbs/{object}/{name}",
            post(host::verb_program_handler),
        )
        .route("/v1/verbs/{object}", get(host::verbs_handler))
        .route(
            "/v1/verbs/{object}/{name}",
            get(host::verb_retrieval_handler),
        )
        .route(
            "/v1/verbs/{object}/{name}/invoke",
            post(host::invoke_verb_handler),
        )
        .route("/v1/properties/{object}", get(host::properties_handler))
        .route(
            "/v1/properties/{object}/{name}",
            get(host::property_retrieval_handler),
        )
        .route(
            "/v1/properties/{object}/{name}",
            post(host::update_property_handler),
        )
        .route("/v1/objects", get(host::list_objects_handler))
        .route("/v1/objects/query", get(host::query_objects_handler))
        .route("/v1/objects/{object}", get(host::resolve_objref_handler))
        .route("/v1/history", get(host::history_handler))
        .route("/v1/batch", post(host::batch_handler))
        .route("/v1/presentations", get(host::presentations_handler))
        .route(
            "/v1/presentations/{presentation_id}",
            axum::routing::delete(host::dismiss_presentation_handler),
        )
        .route("/v1/event-log/pubkey", get(host::get_pubkey_handler))
        .route("/v1/event-log/pubkey", put(host::set_pubkey_handler))
        .route(
            "/v1/event-log/history",
            axum::routing::delete(host::delete_history_handler),
        )
        .with_state(web_host.clone());

    webhost_router = webhost_router.merge(auth_routes);

    if let Some(oauth2_state) = oauth2_state {
        let oauth2_router = Router::new()
            .route("/v1/oauth2/config", get(host::oauth2_config_handler))
            .route(
                "/auth/oauth2/{provider}/authorize",
                get(host::oauth2_authorize_handler),
            )
            .route(
                "/auth/oauth2/{provider}/app/start",
                post(host::oauth2_app_start_handler),
            )
            .route(
                "/auth/oauth2/{provider}/callback",
                get(host::oauth2_callback_handler),
            )
            .route(
                "/auth/oauth2/app/exchange",
                post(host::oauth2_app_exchange_handler),
            )
            .route(
                "/auth/oauth2/app/account",
                post(host::oauth2_app_account_choice_handler),
            )
            .route(
                "/auth/oauth2/account",
                post(host::oauth2_account_choice_handler),
            )
            .route("/auth/oauth2/exchange", post(host::oauth2_exchange_handler))
            .layer(DefaultBodyLimit::max(64 * 1024))
            .with_state(oauth2_state);

        webhost_router = webhost_router.merge(oauth2_router);
    }

    webhost_router = webhost_router.layer(DefaultBodyLimit::max(1024 * 1024));

    if options.enable_webhooks {
        let webhook_router = Router::new()
            .route(
                "/webhooks/{*path}",
                axum::routing::any(host::web_hook_handler),
            )
            .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
            .with_state(web_host.clone());
        webhost_router = webhost_router.merge(webhook_router);
    }

    // Applied to matched routes only, so each request is labelled with its route template.
    webhost_router = webhost_router
        .route_layer(axum::middleware::from_fn(crate::metrics::track_request))
        .fallback(crate::metrics::unmatched);

    if let Some(cors_layer) = build_cors_layer(&options.cors)? {
        info!("CORS policy enabled");
        webhost_router = webhost_router.layer(cors_layer);
    }

    Ok(webhost_router)
}

fn build_cors_layer(config: &CorsConfig) -> eyre::Result<Option<CorsLayer>> {
    if !config.enabled {
        return Ok(None);
    }

    if config.allowed_origins.is_empty() {
        return Err(eyre::eyre!(
            "CORS enabled but no allowed_origins configured"
        ));
    }

    let origins = cors_origins(config)?;
    let methods = cors_methods(config)?;
    let headers = cors_headers(config)?;

    let mut layer = CorsLayer::new()
        .allow_origin(origins)
        .allow_methods(methods)
        .allow_headers(headers);

    if config.allow_credentials {
        layer = layer.allow_credentials(true);
    }

    Ok(Some(layer))
}

fn cors_origins(config: &CorsConfig) -> eyre::Result<AllowOrigin> {
    if config.allowed_origins.len() == 1 && config.allowed_origins[0] == "*" {
        if config.allow_credentials {
            return Err(eyre::eyre!(
                "CORS: wildcard origin '*' cannot be used with allow_credentials=true"
            ));
        }
        return Ok(AllowOrigin::any());
    }

    let origins = config
        .allowed_origins
        .iter()
        .map(|origin| {
            origin
                .parse()
                .map_err(|_| eyre::eyre!("Invalid CORS origin: {}", origin))
        })
        .collect::<eyre::Result<Vec<axum::http::HeaderValue>>>()?;
    Ok(AllowOrigin::list(origins))
}

fn cors_methods(config: &CorsConfig) -> eyre::Result<AllowMethods> {
    if config.allowed_methods.is_empty() {
        return Ok(AllowMethods::list([
            axum::http::Method::GET,
            axum::http::Method::POST,
            axum::http::Method::PUT,
            axum::http::Method::DELETE,
            axum::http::Method::OPTIONS,
        ]));
    }

    let methods = config
        .allowed_methods
        .iter()
        .map(|method| {
            method
                .parse()
                .map_err(|_| eyre::eyre!("Invalid CORS method: {}", method))
        })
        .collect::<eyre::Result<Vec<axum::http::Method>>>()?;
    Ok(AllowMethods::list(methods))
}

fn cors_headers(config: &CorsConfig) -> eyre::Result<AllowHeaders> {
    if config.allowed_headers.is_empty() {
        return Ok(AllowHeaders::list([
            axum::http::header::CONTENT_TYPE,
            axum::http::header::AUTHORIZATION,
            axum::http::header::ACCEPT,
            axum::http::HeaderName::from_static("x-moor-auth-token"),
            axum::http::HeaderName::from_static("x-moor-client-token"),
            axum::http::HeaderName::from_static("x-moor-client-id"),
        ]));
    }

    let headers = config
        .allowed_headers
        .iter()
        .map(|header| {
            header
                .parse()
                .map_err(|_| eyre::eyre!("Invalid CORS header: {}", header))
        })
        .collect::<eyre::Result<Vec<axum::http::HeaderName>>>()?;
    Ok(AllowHeaders::list(headers))
}
