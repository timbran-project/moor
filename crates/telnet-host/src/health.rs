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

//! Lightweight TCP health-check endpoint for process and daemon liveness, which also serves the
//! host's metrics at `GET /metrics`.

use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
    time::Duration,
};

use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    time::timeout,
};
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
            Ok((socket, addr)) => {
                debug!("Health check probe from {}", addr);
                tokio::spawn(answer_probe(socket, last_daemon_ping.clone()));
            }
            Err(e) => {
                debug!("Health check accept error: {}", e);
            }
        }
    }
}

/// How long to wait for a request before answering as a plain health check. TCP probes connect
/// and close without sending anything.
const REQUEST_WAIT: Duration = Duration::from_secs(1);

/// Answer `GET /metrics` with the host's metrics, and anything else, including nothing, with the
/// health status.
async fn answer_probe(mut socket: TcpStream, last_daemon_ping: Arc<AtomicU64>) {
    let mut request = [0u8; 1024];
    let read = timeout(REQUEST_WAIT, socket.read(&mut request))
        .await
        .ok()
        .and_then(Result::ok)
        .unwrap_or(0);
    let response = if is_metrics_request(&request[..read]) {
        let body = crate::metrics::render();
        format!(
            "HTTP/1.0 200 OK\r\nContent-Type: text/plain; version=0.0.4\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        )
        .into_bytes()
    } else if daemon_ping_is_recent(&last_daemon_ping) {
        b"OK\n".to_vec()
    } else {
        b"UNHEALTHY\n".to_vec()
    };
    let _ = socket.write_all(&response).await;
}

fn is_metrics_request(request: &[u8]) -> bool {
    request.starts_with(b"GET /metrics ") || request.starts_with(b"GET /metrics?")
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

#[cfg(test)]
mod tests {
    use super::answer_probe;
    use std::sync::{Arc, atomic::AtomicU64};
    use tokio::{
        io::{AsyncReadExt, AsyncWriteExt},
        net::{TcpListener, TcpStream},
    };

    async fn probe(request: &[u8]) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let mut client = TcpStream::connect(listener.local_addr().unwrap())
            .await
            .unwrap();
        let (server, _) = listener.accept().await.unwrap();
        let answer = tokio::spawn(answer_probe(server, Arc::new(AtomicU64::new(0))));
        client.write_all(request).await.unwrap();
        client.shutdown().await.unwrap();
        let mut response = String::new();
        client.read_to_string(&mut response).await.unwrap();
        answer.await.unwrap();
        response
    }

    #[tokio::test]
    async fn answers_other_requests_and_silence_with_health() {
        assert_eq!(probe(b"GET /health HTTP/1.1\r\n\r\n").await, "OK\n");
        assert_eq!(probe(b"").await, "OK\n");
    }
}
