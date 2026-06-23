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

mod health;
pub mod listeners;
pub mod session;

use std::{
    net::SocketAddr,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
};

use eyre::{Result, bail, eyre};
use listeners::{Listeners, load_tls_config};
use moor_var::SYSTEM_OBJECT;
use rpc_async_client::{
    ZmqHostServices, process_hosts_events_with_services, start_host_session_with_services,
};
use rpc_common::{HostType, api::HostServices, client_args::RpcClientConfig};
use tokio::select;
use tracing::info;
use uuid::Uuid;

use crate::health::spawn_health_check;

#[derive(Clone, Debug)]
pub struct TelnetHostConfig {
    pub connection: RpcClientConfig,
    pub telnet_address: String,
    pub telnet_port: u16,
    pub health_check_port: u16,
    pub tls_port: Option<u16>,
    pub tls_cert: Option<PathBuf>,
    pub tls_key: Option<PathBuf>,
}

#[derive(Clone)]
pub struct HostRuntime {
    pub zmq_context: tmq::Context,
    pub kill_switch: Arc<AtomicBool>,
}

impl Default for HostRuntime {
    fn default() -> Self {
        Self {
            zmq_context: tmq::Context::new(),
            kill_switch: Arc::new(AtomicBool::new(false)),
        }
    }
}

pub async fn run(config: TelnetHostConfig, runtime: HostRuntime) -> Result<()> {
    let curve_keys = rpc_async_client::enrollment_client::setup_curve_auth(
        &config.connection.rpc_address,
        &config.connection.enrollment_address,
        config.connection.enrollment_token_file.as_deref(),
        "telnet-host",
        &config.connection.data_dir,
    )
    .map_err(|e| eyre!("Failed to setup CURVE authentication: {e}"))?;

    let host_services = Arc::new(ZmqHostServices::new(
        runtime.zmq_context.clone(),
        config.connection.rpc_address.clone(),
        config.connection.events_address.clone(),
        curve_keys.clone(),
    )) as Arc<dyn HostServices>;
    run_with_host_services(config, runtime, curve_keys, host_services).await
}

pub async fn run_with_services(
    config: TelnetHostConfig,
    runtime: HostRuntime,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    run_with_host_services(config, runtime, None, host_services).await
}

async fn run_with_host_services(
    config: TelnetHostConfig,
    runtime: HostRuntime,
    curve_keys: Option<(String, String, String)>,
    host_services: Arc<dyn HostServices>,
) -> Result<()> {
    let listen_addr = format!("{}:{}", config.telnet_address, config.telnet_port);
    let telnet_sockaddr = listen_addr
        .parse::<SocketAddr>()
        .map_err(|e| eyre!("Failed to parse telnet socket address {listen_addr}: {e}"))?;

    let host_id = Uuid::new_v4();
    let last_daemon_ping = Arc::new(AtomicU64::new(0));
    let tls_config = load_optional_tls_config(&config)?;

    let (mut listeners_server, listeners_channel, listeners) = Listeners::new(
        runtime.zmq_context.clone(),
        config.connection.rpc_address.clone(),
        config.connection.events_address.clone(),
        runtime.kill_switch.clone(),
        curve_keys.clone(),
        host_services.clone(),
        tls_config,
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
