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

//! Runtime assembly for the outbound HTTP worker.

use std::{
    net::SocketAddr,
    str::FromStr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};

use eyre::{Result, eyre};
use moor_common::tasks::WorkerError;
use moor_var::{Obj, Symbol, Var, Variant, v_int, v_list, v_list_iter, v_str};
use reqwest::Url;
use rpc_async_client::worker_loop_with_context;
use rpc_common::client_args::RpcClientConfig;
use tokio::{io::AsyncWriteExt, net::TcpListener};
use tracing::{debug, error, info};
use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct CurlWorkerConfig {
    pub connection: RpcClientConfig,
    pub health_check_port: Option<u16>,
}

#[derive(Clone)]
pub struct WorkerRuntime {
    pub zmq_context: tmq::Context,
    pub kill_switch: Arc<AtomicBool>,
}

impl Default for WorkerRuntime {
    fn default() -> Self {
        Self {
            zmq_context: tmq::Context::new(),
            kill_switch: Arc::new(AtomicBool::new(false)),
        }
    }
}

pub async fn run(config: CurlWorkerConfig, runtime: WorkerRuntime) -> Result<()> {
    let curve_keys = rpc_async_client::enrollment_client::setup_curve_auth(
        &config.connection.rpc_address,
        &config.connection.enrollment_address,
        config.connection.enrollment_token_file.as_deref(),
        "curl-worker",
        &config.connection.data_dir,
    )
    .map_err(|e| eyre!("Failed to setup CURVE authentication: {e}"))?;

    let worker_id = Uuid::new_v4();
    let last_daemon_ping = Arc::new(AtomicU64::new(0));

    if let Some(health_check_port) = config.health_check_port {
        spawn_health_check(
            format!("0.0.0.0:{health_check_port}"),
            runtime.kill_switch.clone(),
            last_daemon_ping.clone(),
        );
    }

    let worker_type = Symbol::mk("curl");
    let perform_func = Arc::new(perform_http_request);

    worker_loop_with_context(
        &runtime.kill_switch,
        worker_id,
        runtime.zmq_context,
        &config.connection.workers_response_address,
        &config.connection.workers_request_address,
        worker_type,
        perform_func,
        curve_keys,
        Some(last_daemon_ping),
    )
    .await
    .map_err(|e| eyre!("Worker loop for {worker_id} exited with error: {e}"))
}

fn spawn_health_check(
    health_check_addr: String,
    kill_switch: Arc<AtomicBool>,
    last_daemon_ping: Arc<AtomicU64>,
) {
    info!("Starting health check endpoint on {}", health_check_addr);

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
            Ok(listener) => listener,
            Err(e) => {
                error!("Unable to bind health check listener: {}", e);
                return;
            }
        };

        loop {
            if kill_switch.load(Ordering::Relaxed) {
                break;
            }

            match listener.accept().await {
                Ok((mut socket, addr)) => {
                    debug!("Health check probe from {}", addr);

                    let last_ping = last_daemon_ping.load(Ordering::Relaxed);
                    let now = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs();

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
}

async fn perform_http_request(
    _request_id: Uuid,
    _worker_type: Symbol,
    _perms: Obj,
    arguments: Vec<Var>,
    timeout: Option<std::time::Duration>,
) -> Result<Var, WorkerError> {
    if arguments.len() < 2 {
        return Err(WorkerError::RequestError(
            "At least two arguments are required".to_string(),
        ));
    }

    let client = if let Some(timeout) = timeout {
        reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|e| {
                WorkerError::RequestError(format!("Failed to build client with timeout: {e}"))
            })?
    } else {
        reqwest::Client::new()
    };
    let method = arguments[0].as_symbol().map_err(|_| {
        WorkerError::RequestError("First argument must be a symbol or string".to_string())
    })?;

    let Some(url) = arguments[1].as_string() else {
        return Err(WorkerError::RequestError(
            "Second argument must be a string".to_string(),
        ));
    };

    let Ok(url) = Url::parse(url) else {
        return Err(WorkerError::RequestError("Invalid URL".to_string()));
    };

    let headers = if arguments.len() > 3 {
        let Some(headers) = arguments[3].as_list() else {
            return Err(WorkerError::RequestError(
                "Headers must be a list".to_string(),
            ));
        };

        let mut headers_map = reqwest::header::HeaderMap::new();
        for header_pair in headers.iter() {
            let Some(pair) = header_pair.as_list() else {
                return Err(WorkerError::RequestError(
                    "Header pair must be a list".to_string(),
                ));
            };

            if pair.len() != 2 {
                return Err(WorkerError::RequestError(
                    "Header pair must have exactly two elements".to_string(),
                ));
            }

            let Some(key) = pair[0].as_string() else {
                return Err(WorkerError::RequestError(
                    "Header key must be a string".to_string(),
                ));
            };

            let Some(value) = pair[1].as_string() else {
                return Err(WorkerError::RequestError(
                    "Header value must be a string".to_string(),
                ));
            };

            let key = reqwest::header::HeaderName::from_str(key)
                .map_err(|e| WorkerError::RequestError(format!("Invalid header key: {e}")))?;
            let value = reqwest::header::HeaderValue::from_str(value)
                .map_err(|e| WorkerError::RequestError(format!("Invalid header value: {e}")))?;
            headers_map.insert(key, value);
        }
        Some(headers_map)
    } else {
        None
    };

    let body = if arguments.len() > 2 {
        match arguments[2].variant() {
            Variant::Str(body) => Some(body.as_str().to_string()),
            Variant::List(list) => {
                let mut body = String::new();
                for item in list.iter() {
                    match item.variant() {
                        Variant::Str(s) => body.push_str(s.as_str()),
                        _ => {
                            return Err(WorkerError::RequestError(
                                "List items must be strings".to_string(),
                            ));
                        }
                    }
                }
                Some(body)
            }
            _ => {
                return Err(WorkerError::RequestError(
                    "Body must be a string or list".to_string(),
                ));
            }
        }
    } else {
        None
    };

    info!(
        method = method.as_arc_str().as_str(),
        url = url.as_str(),
        "HTTP request"
    );
    let response = match method.as_arc_str().to_lowercase().as_str() {
        "get" => {
            let client = client.get(url);
            let client = if let Some(headers) = headers {
                client.headers(headers)
            } else {
                client
            };
            let client = if let Some(body) = body {
                client.body(body)
            } else {
                client
            };
            client.send().await.map_err(|e| {
                WorkerError::RequestError(format!("Failed to send GET request: {e}"))
            })?
        }
        "post" => {
            let client = client.post(url);
            let client = if let Some(headers) = headers {
                client.headers(headers)
            } else {
                client
            };
            let client = if let Some(body) = body {
                client.body(body)
            } else {
                client
            };
            client.send().await.map_err(|e| {
                WorkerError::RequestError(format!("Failed to send POST request: {e}"))
            })?
        }
        "put" => {
            let client = client.put(url);
            let client = if let Some(headers) = headers {
                client.headers(headers)
            } else {
                client
            };
            let client = if let Some(body) = body {
                client.body(body)
            } else {
                client
            };
            client.send().await.map_err(|e| {
                WorkerError::RequestError(format!("Failed to send PUT request: {e}"))
            })?
        }
        _ => {
            return Err(WorkerError::RequestError(format!(
                "Unsupported HTTP method ({})",
                method.as_arc_str()
            )));
        }
    };

    let status_code = v_int(response.status().as_u16() as i64);
    let headers = response
        .headers()
        .iter()
        .map(|(k, v)| v_list(&[v_str(k.as_str()), v_str(v.to_str().unwrap_or(""))]));
    let headers = v_list_iter(headers);
    let body = response
        .text()
        .await
        .map_err(|e| WorkerError::RequestError(format!("Failed to read response body: {e}")))?;
    let body = v_str(body.as_str());

    Ok(v_list(&[status_code, headers, body]))
}
