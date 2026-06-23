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

use std::{sync::LazyLock, sync::atomic::Ordering};

use clap::Parser;
use clap_derive::Parser;
use moor_curl_worker::{CurlWorkerConfig, WorkerRuntime};
use moor_runtime_api::client_args::RpcClientArgs;
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

#[derive(Parser, Debug)]
#[command(version = VERSION_STRING.as_str())]
struct Args {
    #[command(flatten)]
    client_args: RpcClientArgs,

    #[arg(long, help = "Enable debug logging", default_value = "false")]
    debug: bool,

    #[arg(
        long,
        value_name = "health-check-port",
        help = "Port for health check endpoint (responds with OK)",
        default_value = "9999"
    )]
    health_check_port: u16,
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<(), eyre::Error> {
    color_eyre::install()?;
    let args = Args::parse();

    moor_common::tracing::init_tracing(args.debug).expect("Unable to configure logging");

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

    let runtime = WorkerRuntime::default();
    let kill_switch = runtime.kill_switch.clone();
    let config = CurlWorkerConfig {
        connection: (&args.client_args).into(),
        health_check_port: Some(args.health_check_port),
    };

    let worker_loop_thread =
        tokio::spawn(async move { moor_curl_worker::run(config, runtime).await });

    select! {
        _ = hup_signal.recv() => {
            info!("Received HUP signal, reloading configuration is not supported yet");
        },
        _ = stop_signal.recv() => {
            info!("Received STOP signal, shutting down...");
            kill_switch.store(true, Ordering::Relaxed);
        },
        result = worker_loop_thread => {
            match result {
                Ok(Ok(())) => info!("Worker loop exited"),
                Ok(Err(e)) => {
                    error!("Worker loop exited with error: {}", e);
                    kill_switch.store(true, Ordering::Relaxed);
                }
                Err(e) => {
                    error!("Worker loop task failed: {}", e);
                    kill_switch.store(true, Ordering::Relaxed);
                }
            }
        }
    }

    info!("Done");
    Ok(())
}
