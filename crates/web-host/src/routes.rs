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

//! Route table construction, request body limits, CORS, and auth rate limiting.

use std::{
    net::{IpAddr, SocketAddr},
    sync::Arc,
};

use axum::{
    Router,
    extract::DefaultBodyLimit,
    routing::{get, post, put},
};
use ipnet::IpNet;
use serde_derive::{Deserialize, Serialize};
use tower_governor::{GovernorLayer, errors::GovernorError, governor::GovernorConfigBuilder};
use tower_http::cors::{AllowHeaders, AllowMethods, AllowOrigin, CorsLayer};
use tracing::info;

use crate::host::{self, OAuth2State, WebHost};

/// Rate-limit key extractor that only trusts forwarding headers from configured
/// trusted proxy CIDRs. Falls back to peer IP when no trusted proxy is present.
#[derive(Clone, Debug)]
struct TrustedProxyKeyExtractor {
    trusted_cidrs: Arc<Vec<IpNet>>,
}

impl tower_governor::key_extractor::KeyExtractor for TrustedProxyKeyExtractor {
    type Key = IpAddr;

    fn extract<T>(&self, req: &axum::http::Request<T>) -> Result<Self::Key, GovernorError> {
        let peer_ip = req
            .extensions()
            .get::<axum::extract::ConnectInfo<SocketAddr>>()
            .map(|ci| ci.0.ip())
            .ok_or(GovernorError::UnableToExtractKey)?;

        if self.trusted_cidrs.is_empty()
            || !self
                .trusted_cidrs
                .iter()
                .any(|cidr| cidr.contains(&peer_ip))
        {
            return Ok(peer_ip);
        }

        if let Some(ip) = req
            .headers()
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.split(',').next())
            .and_then(|s| s.trim().parse::<IpAddr>().ok())
        {
            return Ok(ip);
        }

        if let Some(ip) = req
            .headers()
            .get("x-real-ip")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.trim().parse::<IpAddr>().ok())
        {
            return Ok(ip);
        }

        Ok(peer_ip)
    }
}

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

/// Rate limiting configuration for auth endpoints.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RateLimitConfig {
    #[serde(default)]
    pub enabled: bool,
    /// Sustained requests per second.
    #[serde(default = "RateLimitConfig::default_rps")]
    pub requests_per_second: u64,
    /// Token bucket capacity.
    #[serde(default = "RateLimitConfig::default_burst")]
    pub burst_size: u32,
}

impl RateLimitConfig {
    fn default_rps() -> u64 {
        5
    }

    fn default_burst() -> u32 {
        10
    }
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            requests_per_second: Self::default_rps(),
            burst_size: Self::default_burst(),
        }
    }
}

pub fn mk_routes(
    web_host: WebHost,
    oauth2_state: Option<OAuth2State>,
    enable_webhooks: bool,
    cors_config: &CorsConfig,
    rate_limit_config: &RateLimitConfig,
    trusted_proxy_cidrs: &Arc<Vec<IpNet>>,
) -> eyre::Result<Router> {
    let mut auth_routes = Router::new()
        .route("/auth/connect", post(host::connect_auth_handler))
        .route("/auth/create", post(host::create_auth_handler))
        .layer(DefaultBodyLimit::max(64 * 1024))
        .with_state(web_host.clone());

    if rate_limit_config.enabled {
        let key_extractor = TrustedProxyKeyExtractor {
            trusted_cidrs: Arc::clone(trusted_proxy_cidrs),
        };
        let governor_conf = GovernorConfigBuilder::default()
            .per_second(rate_limit_config.requests_per_second)
            .burst_size(rate_limit_config.burst_size)
            .key_extractor(key_extractor)
            .finish()
            .ok_or_else(|| eyre::eyre!("Failed to build rate limiter config"))?;
        auth_routes = auth_routes.layer(GovernorLayer::new(Arc::new(governor_conf)));
        info!(
            "Rate limiting enabled on auth endpoints: {}/s burst={}",
            rate_limit_config.requests_per_second, rate_limit_config.burst_size
        );
    }

    let mut webhost_router = Router::new()
        .route("/ws/attach/connect", get(host::ws_connect_attach_handler))
        .route("/ws/attach/create", get(host::ws_create_attach_handler))
        .route("/auth/validate", get(host::validate_auth_handler))
        .route("/auth/logout", post(host::logout_handler))
        .route(
            "/v1/system_property/{*path}",
            get(host::system_property_handler),
        )
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

    if enable_webhooks {
        let webhook_router = Router::new()
            .route(
                "/webhooks/{*path}",
                axum::routing::any(host::web_hook_handler),
            )
            .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
            .with_state(web_host.clone());
        webhost_router = webhost_router.merge(webhook_router);
    }

    if let Some(cors_layer) = build_cors_layer(cors_config)? {
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
