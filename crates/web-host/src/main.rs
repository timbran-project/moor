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

//! Web host process startup, configuration loading, and shutdown coordination.

mod host;
mod listeners;
mod routes;

use crate::host::webrtc::WebRtcConfig;
use crate::host::{OAuth2Config, OAuth2Manager};
use crate::listeners::Listeners;
use crate::routes::{CorsConfig, RateLimitConfig};
use std::sync::Arc;

use clap::Parser;
use clap_derive::Parser;

use ipnet::IpNet;
use moor_var::SYSTEM_OBJECT;
use rpc_async_client::{process_hosts_events, start_host_session};
use rpc_common::{HostType, client_args::RpcClientArgs};
use serde_derive::{Deserialize, Serialize};
use std::sync::{
    LazyLock,
    atomic::{AtomicBool, AtomicU64},
};
use tokio::{
    select,
    signal::unix::{SignalKind, signal},
};
use tracing::{error, info};
use uuid::Uuid;

static VERSION_STRING: LazyLock<String> = LazyLock::new(|| {
    format!(
        "{} (commit: {})",
        env!("CARGO_PKG_VERSION"),
        moor_common::build::short_commit()
    )
});

#[derive(Parser, Debug, Serialize, Deserialize)]
#[command(version = VERSION_STRING.as_str())]
struct Args {
    #[command(flatten)]
    #[serde(flatten)]
    client_args: RpcClientArgs,

    #[arg(
        long,
        value_name = "listen-address",
        help = "HTTP listen address",
        default_value = "0.0.0.0:8080"
    )]
    listen_address: String,

    #[arg(long, help = "Enable debug logging", default_value = "false")]
    pub debug: bool,

    #[arg(long, help = "Yaml config file to use, overrides values in CLI args")]
    config_file: Option<String>,

    #[serde(default)]
    #[arg(skip)]
    pub oauth2: OAuth2Config,

    #[arg(long, help = "Enable webhooks", default_value = "true")]
    pub enable_webhooks: bool,

    #[serde(default)]
    #[arg(skip)]
    pub cors: CorsConfig,

    #[serde(default)]
    #[arg(skip)]
    pub rate_limit: RateLimitConfig,

    /// Trusted proxy CIDRs. Only connections from these CIDRs will have
    /// X-Forwarded-For / X-Real-IP headers honoured. Default empty = trust nothing.
    #[serde(default)]
    #[arg(skip)]
    pub trusted_proxy_cidrs: Vec<String>,

    #[serde(default)]
    #[arg(skip)]
    pub webrtc: WebRtcConfig,

    /// Enable WebRTC data channel for realtime event delivery.
    #[arg(long, help = "Enable WebRTC data channel")]
    pub webrtc_enabled: Option<bool>,

    /// Domains eligible for WebRTC data channel delivery (comma-separated).
    #[arg(
        long,
        help = "Comma-separated realtime domains for WebRTC",
        value_delimiter = ','
    )]
    pub webrtc_realtime_domains: Option<Vec<String>>,
}

fn apply_cli_overrides(args: &mut Args) {
    if let Some(enabled) = args.webrtc_enabled {
        args.webrtc.enabled = enabled;
    }
    if let Some(domains) = args.webrtc_realtime_domains.take() {
        args.webrtc.realtime_domains = domains;
    }
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

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<(), eyre::Error> {
    color_eyre::install()?;
    let cli_args = Args::parse();
    let config_file = cli_args.config_file.clone();
    let mut args = match moor_common::config::apply_yaml_config_file_with_flattened_sections(
        cli_args,
        config_file.as_deref().map(std::path::Path::new),
        &["client_args"],
    ) {
        Ok(args) => args,
        Err(e) => {
            eprintln!("Unable to parse arguments/configuration: {e}");
            std::process::exit(1);
        }
    };

    apply_cli_overrides(&mut args);

    moor_common::tracing::init_tracing(args.debug).unwrap_or_else(|e| {
        eprintln!("Unable to configure logging: {e}");
        std::process::exit(1);
    });

    let mut hup_signal = match signal(SignalKind::hangup()) {
        Ok(signal) => signal,
        Err(e) => {
            error!("Unable to register HUP signal handler: {}", e);
            std::process::exit(1);
        }
    };
    let mut stop_signal = match signal(SignalKind::interrupt()) {
        Ok(signal) => signal,
        Err(e) => {
            error!("Unable to register STOP signal handler: {}", e);
            std::process::exit(1);
        }
    };

    let kill_switch = Arc::new(AtomicBool::new(false));

    // Setup CURVE encryption if using TCP endpoint
    let curve_keys = match rpc_async_client::enrollment_client::setup_curve_auth(
        &args.client_args.rpc_address,
        &args.client_args.enrollment_address,
        args.client_args.enrollment_token_file.as_deref(),
        "web-host",
        &args.client_args.data_dir,
    ) {
        Ok(keys) => keys,
        Err(e) => {
            error!("Failed to setup CURVE authentication: {}", e);
            std::process::exit(1);
        }
    };

    let zmq_ctx = tmq::Context::new();

    let oauth2_manager = init_oauth2_manager(&args.oauth2);
    let trusted_proxy_cidrs = Arc::new(parse_trusted_proxy_cidrs(&args.trusted_proxy_cidrs));

    let host_id = Uuid::new_v4();
    let last_daemon_ping = Arc::new(AtomicU64::new(0));
    let (mut listeners_server, listeners_channel, listeners) = Listeners::new(
        host_id,
        zmq_ctx.clone(),
        args.client_args.rpc_address.clone(),
        args.client_args.events_address.clone(),
        kill_switch.clone(),
        oauth2_manager,
        curve_keys.clone(),
        args.enable_webhooks,
        last_daemon_ping.clone(),
        args.cors.clone(),
        args.rate_limit.clone(),
        trusted_proxy_cidrs,
        Arc::new(args.webrtc.clone()),
    );
    info!("Starting up listener thread...");
    let listeners_thread = tokio::spawn(async move {
        listeners_server.run(listeners_channel).await;
    });
    listeners
        .add_listener(
            &SYSTEM_OBJECT,
            match args.listen_address.parse() {
                Ok(addr) => addr,
                Err(e) => {
                    error!(
                        "Unable to parse listen address {}: {}",
                        args.listen_address, e
                    );
                    std::process::exit(1);
                }
            },
        )
        .await
        .unwrap_or_else(|e| {
            error!("Unable to start default listener: {}", e);
            std::process::exit(1);
        });

    info!("Starting host session....");
    let (rpc_client, host_id) = match start_host_session(
        host_id,
        zmq_ctx.clone(),
        args.client_args.rpc_address.clone(),
        kill_switch.clone(),
        listeners.clone(),
        curve_keys.clone(),
    )
    .await
    {
        Ok((client, id)) => (client, id),
        Err(e) => {
            error!("Unable to establish initial host session: {}", e);
            std::process::exit(1);
        }
    };

    let host_listen_loop = process_hosts_events(
        rpc_client,
        host_id,
        zmq_ctx.clone(),
        args.client_args.events_address.clone(),
        args.listen_address.clone(),
        kill_switch.clone(),
        listeners.clone(),
        HostType::TCP,
        curve_keys,
        Some(last_daemon_ping),
    );

    select! {
        _ = host_listen_loop => {
            info!("Host events loop exited.");
        },
        _ = listeners_thread => {
            info!("Listener set exited.");
        }
        _ = hup_signal.recv() => {
            info!("HUP received, stopping...");
            kill_switch.store(true, std::sync::atomic::Ordering::SeqCst);
        },
        _ = stop_signal.recv() => {
            info!("STOP received, stopping...");
            kill_switch.store(true, std::sync::atomic::Ordering::SeqCst);
        }
    }
    info!("Done.");

    Ok(())
}
