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

//! Runtime assembly for the line-oriented telnet host.

#![allow(clippy::too_many_arguments)]

pub mod config;
mod health;
pub mod listeners;
pub mod session;

use std::{
    net::SocketAddr,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::SystemTime,
};

use eyre::{Result, bail, eyre};
pub use listeners::load_tls_config;
use listeners::{Listeners, SessionSettings};
use moor_runtime_api::{
    HostType,
    api::{HostReply, HostRequest, HostServices},
    client_args::RpcClientConfig,
};
use moor_var::SYSTEM_OBJECT;
use moor_zmq_client::{
    ZmqHostServices, process_hosts_events_with_services, start_host_session_with_services,
};
use tokio::select;
use tracing::{info, warn};
use uuid::Uuid;

use crate::health::spawn_health_check;
pub use config::TelnetProtocolConfig;

#[derive(Clone, Debug)]
pub struct TelnetHostConfig {
    pub telnet_address: String,
    pub telnet_port: u16,
    pub health_check_port: u16,
    pub tls_port: Option<u16>,
    pub tls_cert: Option<PathBuf>,
    pub tls_key: Option<PathBuf>,
    /// Out-of-band telnet protocols; all off by default.
    pub protocols: TelnetProtocolConfig,
}

#[derive(Clone, Debug)]
pub struct ZmqTelnetHostConfig {
    pub connection: RpcClientConfig,
    pub host: TelnetHostConfig,
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

pub async fn run(config: ZmqTelnetHostConfig, runtime: HostRuntime) -> Result<()> {
    let curve_keys = moor_zmq_client::enrollment_client::setup_curve_auth(
        &config.connection.rpc_address,
        &config.connection.enrollment_address,
        config.connection.enrollment_token_file.as_deref(),
        "telnet-host",
        &config.connection.data_dir,
    )
    .map_err(|e| eyre!("Failed to setup CURVE authentication: {e}"))?;

    let host_services = Arc::new(ZmqHostServices::new(
        r0z_async::Context::new(),
        config.connection.rpc_address.clone(),
        config.connection.events_address.clone(),
        curve_keys.clone(),
    )) as Arc<dyn HostServices>;
    run_with_host_services(config.host, runtime, host_services).await
}

pub async fn run_with_services(
    config: TelnetHostConfig,
    runtime: HostRuntime,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    run_with_host_services(config, runtime, host_services).await
}

async fn run_with_host_services(
    config: TelnetHostConfig,
    runtime: HostRuntime,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    let listen_addr = format!("{}:{}", config.telnet_address, config.telnet_port);
    let telnet_sockaddr = listen_addr
        .parse::<SocketAddr>()
        .map_err(|e| eyre!("Failed to parse telnet socket address {listen_addr}: {e}"))?;

    let host_id = Uuid::new_v4();
    let last_daemon_ping = Arc::new(AtomicU64::new(0));
    let tls_config = load_optional_tls_config(&config)?;

    let started_at = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();
    let settings = SessionSettings {
        protocols: Arc::new(config.protocols.clone()),
        boolean_returns: Arc::new(AtomicBool::new(false)),
        started_at,
    };
    let boolean_returns = settings.boolean_returns.clone();

    let (mut listeners_server, listeners_channel, listeners) = Listeners::new(
        runtime.kill_switch.clone(),
        host_services.clone(),
        tls_config,
        settings,
    );

    let listeners_thread = tokio::spawn(async move {
        listeners_server.run(listeners_channel).await;
    });

    listeners
        .add_listener(&SYSTEM_OBJECT, telnet_sockaddr)
        .await?;

    if let Some(tls_port) = config.tls_port {
        let tls_listen_addr = format!("{}:{}", config.telnet_address, tls_port);
        let tls_sockaddr = tls_listen_addr
            .parse::<SocketAddr>()
            .map_err(|e| eyre!("Failed to parse TLS socket address {tls_listen_addr}: {e}"))?;
        listeners
            .add_tls_listener(&SYSTEM_OBJECT, tls_sockaddr)
            .await?;
    }

    let health_check_addr = format!("{}:{}", config.telnet_address, config.health_check_port);
    spawn_health_check(
        health_check_addr,
        runtime.kill_switch.clone(),
        last_daemon_ping.clone(),
    );

    info!("Starting host session...");
    let host_id = start_host_session_with_services(
        host_id,
        runtime.kill_switch.clone(),
        listeners.clone(),
        HostType::TCP,
        host_services.clone(),
    )
    .await
    .map_err(|e| eyre!("Unable to establish initial host session: {e}"))?;

    // Inbound GMCP JSON booleans follow the daemon's `use_boolean_returns`.
    if config.protocols.gmcp {
        fetch_boolean_returns(host_id, host_services.as_ref(), &boolean_returns).await;
    }

    let host_listen_loop = process_hosts_events_with_services(
        host_id,
        config.telnet_address.clone(),
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

async fn fetch_boolean_returns(
    host_id: Uuid,
    host_services: &dyn HostServices,
    boolean_returns: &AtomicBool,
) {
    match host_services
        .runtime_client()
        .host_call(host_id, HostRequest::GetServerFeatures)
        .await
    {
        Ok(HostReply::ServerFeatures(features)) => {
            boolean_returns.store(features.use_boolean_returns, Ordering::Relaxed);
        }
        Ok(other) => warn!(?other, "unexpected reply to GetServerFeatures"),
        Err(e) => warn!("unable to fetch server features: {e}"),
    }
}

fn load_optional_tls_config(
    config: &TelnetHostConfig,
) -> Result<Option<Arc<tokio_rustls::rustls::ServerConfig>>> {
    let tls_config = match (&config.tls_cert, &config.tls_key) {
        (Some(cert_path), Some(key_path)) => {
            info!("Loading TLS certificate from {:?}", cert_path);
            Some(load_tls_config(cert_path, key_path)?)
        }
        (Some(_), None) | (None, Some(_)) => {
            bail!("Both --tls-cert and --tls-key must be provided together");
        }
        (None, None) => None,
    };

    if config.tls_port.is_some() && tls_config.is_none() {
        bail!("--tls-port requires --tls-cert and --tls-key");
    }

    Ok(tls_config)
}
