// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// General Public License as published by the Free Software Foundation, version
// 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.
//

mod ops;
mod sandbox;

use clap::Parser;
use clap_derive::Parser;
use rpc_async_client::worker_loop;
use rpc_common::client_args::RpcClientArgs;
use std::{
    net::SocketAddr,
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
    time::Duration,
};
use tokio::{
    io::AsyncWriteExt,
    net::TcpListener,
    select,
    signal::unix::{SignalKind, signal},
};
use tracing::{debug, error, info};

use moor_var::{Obj, Symbol, Var};
use once_cell::sync::Lazy;
use uuid::Uuid;

use crate::sandbox::Sandbox;

static VERSION_STRING: Lazy<String> = Lazy::new(|| {
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

    #[arg(
        long,
        env = "MOOR_FILE_WORKER_SANDBOX",
        value_name = "sandbox-dir",
        help = "Root directory that all file operations are confined to. All request paths are \
                resolved relative to this directory and may not escape it."
    )]
    sandbox_dir: PathBuf,

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
    let args: Args = Args::parse();

    moor_common::tracing::init_tracing(args.debug).expect("Unable to configure logging");

    let sandbox = match Sandbox::new(&args.sandbox_dir) {
        Ok(sandbox) => Arc::new(sandbox),
        Err(e) => {
            error!(
                "Unable to open sandbox directory {:?}: {}",
                args.sandbox_dir, e
            );
            std::process::exit(1);
        }
    };
    info!("File operations confined to sandbox {:?}", sandbox.root());

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
        "file-worker",
        &args.client_args.data_dir,
    ) {
        Ok(keys) => keys,
        Err(e) => {
            error!("Failed to setup CURVE authentication: {}", e);
            std::process::exit(1);
        }
    };

    // Generate a worker ID (or use enrolled UUID if we have one)
    let my_id = uuid::Uuid::new_v4();

    // Create atomic for tracking daemon pings (for health checks)
    let last_daemon_ping = Arc::new(AtomicU64::new(0));

    // Start health check server
    let health_check_addr = format!("0.0.0.0:{}", args.health_check_port);
    info!("Starting health check endpoint on {}", health_check_addr);
    let health_kill_switch = kill_switch.clone();
    let health_ping_tracker = last_daemon_ping.clone();
    tokio::spawn(async move {
        let health_sockaddr = match health_check_addr.parse::<SocketAddr>() {
            Ok(addr) => addr,
            Err(e) => {
                error!(
                    "Failed to parse health check address {}: {}",
                    health_check_addr, e
                );
                return;
            }
        };

        let listener = match TcpListener::bind(health_sockaddr).await {
            Ok(l) => l,
            Err(e) => {
                error!("Unable to bind health check listener: {}", e);
                return;
            }
        };

        loop {
            if health_kill_switch.load(std::sync::atomic::Ordering::Relaxed) {
                break;
            }

            match listener.accept().await {
                Ok((mut socket, addr)) => {
                    debug!("Health check probe from {}", addr);

                    // Check if we've received a daemon ping recently
                    let last_ping = health_ping_tracker.load(std::sync::atomic::Ordering::Relaxed);
                    let now = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs();

                    // Report healthy if: no ping yet (last_ping == 0, still starting up) OR ping within last 30s
                    let response: &[u8] = if last_ping == 0 || now - last_ping < 30 {
                        b"OK\n"
                    } else {
                        b"UNHEALTHY\n"
                    };

                    let _ = socket.write_all(response).await;
                }
                Err(e) => {
                    debug!("Health check accept error: {}", e);
                }
            }
        }
    });

    let worker_response_rpc_addr = args.client_args.workers_response_address.clone();
    let worker_request_rpc_addr = args.client_args.workers_request_address.clone();
    let worker_type = Symbol::mk("file");
    let ks = kill_switch.clone();
    let perform_func = Arc::new(
        move |request_id: Uuid,
              worker_type: Symbol,
              perms: Obj,
              arguments: Vec<Var>,
              timeout: Option<Duration>| {
            let sandbox = sandbox.clone();
            async move {
                ops::perform_file_request(
                    sandbox,
                    request_id,
                    worker_type,
                    perms,
                    arguments,
                    timeout,
                )
                .await
            }
        },
    );
    let worker_loop_thread = tokio::spawn(async move {
        if let Err(e) = worker_loop(
            &ks,
            my_id,
            &worker_response_rpc_addr,
            &worker_request_rpc_addr,
            worker_type,
            perform_func,
            curve_keys,
            Some(last_daemon_ping),
        )
        .await
        {
            error!("Worker loop for {my_id} exited with error: {}", e);
            ks.store(true, std::sync::atomic::Ordering::Relaxed);
        }
    });

    select! {
        _ = hup_signal.recv() => {
            info!("Received HUP signal, reloading configuration is not supported yet");
        },
        _ = stop_signal.recv() => {
            info!("Received STOP signal, shutting down...");
            kill_switch.store(true, std::sync::atomic::Ordering::Relaxed);
        },
        _ = worker_loop_thread => {
            info!("Worker loop thread exited");
        }
    }
    info!("Done");
    Ok(())
}
