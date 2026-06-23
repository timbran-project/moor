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

//! Runtime assembly for the web host.

pub mod host;
pub mod listeners;
pub mod routes;

use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
};

use eyre::{Result, eyre};
use host::{OAuth2Config, OAuth2Manager, WebRtcConfig};
use ipnet::IpNet;
use listeners::Listeners;
use moor_runtime_api::{HostType, api::HostServices, client_args::RpcClientConfig};
use moor_var::SYSTEM_OBJECT;
use moor_zmq_client::{
    ZmqHostServices, process_hosts_events_with_services, start_host_session_with_services,
};
use routes::{CorsConfig, RateLimitConfig};
use tokio::select;
use tracing::{error, info};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct WebHostConfig {
    pub listen_address: String,
    pub enable_webhooks: bool,
    pub oauth2: OAuth2Config,
    pub cors: CorsConfig,
    pub rate_limit: RateLimitConfig,
    pub trusted_proxy_cidrs: Vec<String>,
    pub webrtc: WebRtcConfig,
}

#[derive(Clone, Debug)]
pub struct ZmqWebHostConfig {
    pub connection: RpcClientConfig,
    pub host: WebHostConfig,
}

#[derive(Clone)]
pub struct HostRuntime {
    pub kill_switch: Arc<AtomicBool>,
}

impl Default for HostRuntime {
    fn default() -> Self {
        Self {
            kill_switch: Arc::new(AtomicBool::new(false)),
        }
    }
}

pub async fn run(config: ZmqWebHostConfig, runtime: HostRuntime) -> Result<()> {
    let curve_keys = moor_zmq_client::enrollment_client::setup_curve_auth(
        &config.connection.rpc_address,
        &config.connection.enrollment_address,
        config.connection.enrollment_token_file.as_deref(),
        "web-host",
        &config.connection.data_dir,
    )
    .map_err(|e| eyre!("Failed to setup CURVE authentication: {e}"))?;

    let host_services = Arc::new(ZmqHostServices::new(
        tmq::Context::new(),
        config.connection.rpc_address.clone(),
        config.connection.events_address.clone(),
        curve_keys.clone(),
    )) as Arc<dyn HostServices>;
    run_with_host_services(config.host, runtime, host_services).await
}

pub async fn run_with_services(
    config: WebHostConfig,
    runtime: HostRuntime,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    run_with_host_services(config, runtime, host_services).await
}

async fn run_with_host_services(
    config: WebHostConfig,
    runtime: HostRuntime,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    let oauth2_manager = init_oauth2_manager(&config.oauth2);
    let trusted_proxy_cidrs = Arc::new(parse_trusted_proxy_cidrs(&config.trusted_proxy_cidrs));

    let host_id = Uuid::new_v4();
    let last_daemon_ping = Arc::new(AtomicU64::new(0));
    let (mut listeners_server, listeners_channel, listeners) = Listeners::new(
        host_id,
        runtime.kill_switch.clone(),
        oauth2_manager,
        host_services.clone(),
        config.enable_webhooks,
        last_daemon_ping.clone(),
        config.cors.clone(),
        config.rate_limit.clone(),
        trusted_proxy_cidrs,
        Arc::new(config.webrtc.clone()),
    );

    info!("Starting up listener thread...");
    let listeners_thread = tokio::spawn(async move {
        listeners_server.run(listeners_channel).await;
    });

    let listen_addr = config.listen_address.parse::<SocketAddr>().map_err(|e| {
        eyre!(
            "Unable to parse listen address {}: {e}",
            config.listen_address
        )
    })?;
    listeners.add_listener(&SYSTEM_OBJECT, listen_addr).await?;

    info!("Starting host session....");
    let host_id = start_host_session_with_services(
        host_id,
        runtime.kill_switch.clone(),
        listeners.clone(),
        HostType::TCP,
        host_services.clone(),
    )
    .await
    .map_err(|e| eyre!("Unable to establish initial host session: {e}"))?;

    let host_listen_loop = process_hosts_events_with_services(
        host_id,
        config.listen_address.clone(),
        runtime.kill_switch.clone(),
        listeners.clone(),
        HostType::TCP,
        host_services,
        Some(last_daemon_ping),
    );

    select! {
        _ = host_listen_loop => {
            info!("Host events loop exited.");
        },
        _ = listeners_thread => {
            info!("Listener set exited.");
        }
    }

    info!("Done.");
    Ok(())
}

fn init_oauth2_manager(config: &OAuth2Config) -> Option<Arc<OAuth2Manager>> {
    if !config.enabled {
        info!("OAuth2 authentication is disabled");
        return None;
    }

    match OAuth2Manager::new(config.clone()) {
        Ok(manager) => {
            info!(
                "OAuth2 enabled with {} providers",
                manager.available_providers().len()
            );
            Some(Arc::new(manager))
        }
        Err(e) => {
            error!("Failed to initialize OAuth2Manager: {}", e);
            error!("OAuth2 authentication will be disabled");
            None
        }
    }
}

fn parse_trusted_proxy_cidrs(cidrs: &[String]) -> Vec<IpNet> {
    let trusted_proxy_cidrs = cidrs
        .iter()
        .filter_map(|cidr| match cidr.parse::<IpNet>() {
            Ok(net) => Some(net),
            Err(e) => {
                error!("Invalid trusted proxy CIDR '{}': {}", cidr, e);
                None
            }
        })
        .collect::<Vec<_>>();

    if !trusted_proxy_cidrs.is_empty() {
        info!(
            "Trusted proxy CIDRs: {:?}",
            trusted_proxy_cidrs
                .iter()
                .map(|c| c.to_string())
                .collect::<Vec<_>>()
        );
    }

    trusted_proxy_cidrs
}
