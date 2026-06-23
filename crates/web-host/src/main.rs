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

use std::sync::Arc;

use clap::Parser;
use clap_derive::Parser;

use moor_runtime_api::client_args::{RpcClientArgs, RpcClientConfig};
use moor_web_host::{
    HostRuntime, WebHostConfig, ZmqWebHostConfig,
    host::{OAuth2Config, WebRtcConfig},
    routes::{CorsConfig, RateLimitConfig},
};
use serde_derive::{Deserialize, Serialize};
use std::sync::{LazyLock, atomic::AtomicBool};
use tokio::{
    select,
    signal::unix::{SignalKind, signal},
};
use tracing::{error, info};

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
    let kill_switch = Arc::new(AtomicBool::new(false));

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

    let config = ZmqWebHostConfig {
        connection: RpcClientConfig::from(&args.client_args),
        host: WebHostConfig {
            listen_address: args.listen_address,
            enable_webhooks: args.enable_webhooks,
            oauth2: args.oauth2,
            cors: args.cors,
            rate_limit: args.rate_limit,
            trusted_proxy_cidrs: args.trusted_proxy_cidrs,
            webrtc: args.webrtc,
        },
    };
    let runtime = HostRuntime {
        kill_switch: kill_switch.clone(),
    };

    let host_runtime = moor_web_host::run(config, runtime);
    select! {
        result = host_runtime => {
            result?;
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
