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

use clap::Parser;
use clap_derive::Parser;
use colored::control;
use moor_runtime_api::client_args::{RpcClientArgs, RpcClientConfig};
use moor_telnet_host::{HostRuntime, TelnetHostConfig, ZmqTelnetHostConfig};
use serde::{Deserialize, Serialize};
use std::{
    path::PathBuf,
    sync::{Arc, LazyLock, atomic::AtomicBool},
};
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
        value_name = "telnet-address",
        help = "Listen address for the default telnet connections listener",
        default_value = "0.0.0.0"
    )]
    telnet_address: String,

    #[arg(
        long,
        value_name = "telnet-port",
        help = "Listen port for the default telnet connections listener",
        default_value = "8888"
    )]
    telnet_port: u16,

    #[arg(long, help = "Enable debug logging", default_value = "false")]
    debug: bool,

    #[arg(long, help = "Yaml config file to use, overrides values in CLI args")]
    config_file: Option<String>,

    #[arg(
        long,
        value_name = "health-check-port",
        help = "Port for HTTP-style health check endpoint (responds with OK)",
        default_value = "9888"
    )]
    health_check_port: u16,

    #[arg(
        long,
        value_name = "tls-port",
        help = "Listen port for TLS connections (requires --tls-cert and --tls-key)"
    )]
    tls_port: Option<u16>,

    #[arg(
        long,
        value_name = "tls-cert",
        help = "Path to TLS certificate chain file (PEM format)"
    )]
    tls_cert: Option<PathBuf>,

    #[arg(
        long,
        value_name = "tls-key",
        help = "Path to TLS private key file (PEM format)"
    )]
    tls_key: Option<PathBuf>,
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<(), eyre::Error> {
    color_eyre::install()?;
    let cli_args = Args::parse();
    let config_file = cli_args.config_file.clone();
    let args = moor_common::config::apply_yaml_config_file_with_flattened_sections(
        cli_args,
        config_file.as_deref().map(std::path::Path::new),
        &["client_args"],
    )?;

    moor_common::tracing::init_tracing(args.debug).unwrap_or_else(|e| {
        eprintln!("Unable to configure logging: {e}");
        std::process::exit(1);
    });
    control::set_override(true);
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

    let config = ZmqTelnetHostConfig {
        connection: RpcClientConfig::from(&args.client_args),
        host: TelnetHostConfig {
            telnet_address: args.telnet_address,
            telnet_port: args.telnet_port,
            health_check_port: args.health_check_port,
            tls_port: args.tls_port,
            tls_cert: args.tls_cert,
            tls_key: args.tls_key,
        },
    };
    let runtime = HostRuntime {
        kill_switch: kill_switch.clone(),
    };

    let host_runtime = moor_telnet_host::run(config, runtime);
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
