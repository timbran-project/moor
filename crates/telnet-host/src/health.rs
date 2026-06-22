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

//! Lightweight TCP health-check endpoint for process and daemon liveness.

use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
};

use tokio::{io::AsyncWriteExt, net::TcpListener};
use tracing::{debug, error, info};

pub fn spawn_health_check(
    address: String,
    kill_switch: Arc<AtomicBool>,
    last_daemon_ping: Arc<AtomicU64>,
) {
    info!("Starting health check endpoint on {}", address);
    tokio::spawn(async move {
        run_health_check(address, kill_switch, last_daemon_ping).await;
    });
}

async fn run_health_check(
    address: String,
    kill_switch: Arc<AtomicBool>,
    last_daemon_ping: Arc<AtomicU64>,
) {
    let health_sockaddr = match address.parse::<SocketAddr>() {
        Ok(addr) => addr,
        Err(e) => {
            error!("Failed to parse health check address {}: {}", address, e);
            return;
        }
    };

    let listener = match TcpListener::bind(health_sockaddr).await {
        Ok(listener) => listener,
        Err(e) => {
            error!("Unable to bind health check listener: {}", e);
            return;
        }
    };

    loop {
        if kill_switch.load(std::sync::atomic::Ordering::Relaxed) {
            return;
        }

        match listener.accept().await {
            Ok((mut socket, addr)) => {
                debug!("Health check probe from {}", addr);
                let response = if daemon_ping_is_recent(&last_daemon_ping) {
                    b"OK\n".as_slice()
                } else {
                    b"UNHEALTHY\n".as_slice()
                };
                let _ = socket.write_all(response).await;
            }
            Err(e) => {
                debug!("Health check accept error: {}", e);
            }
        }
    }
}

fn daemon_ping_is_recent(last_daemon_ping: &AtomicU64) -> bool {
    let last_ping = last_daemon_ping.load(std::sync::atomic::Ordering::Relaxed);
    if last_ping == 0 {
        return true;
    }

    let Ok(now) = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) else {
        return false;
    };
    now.as_secs().saturating_sub(last_ping) < 30
}
