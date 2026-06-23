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

use crate::{ListenersClient, ZmqHostServices, rpc_client::RpcClient};
use moor_var::{Symbol, Var};
use rpc_common::{
    HostType, RpcError,
    api::{HostBroadcastEvent, HostReply, HostRequest, HostServices, ListenerInfo},
};
use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::SystemTime,
};
use tracing::{error, info, warn};
use uuid::Uuid;

/// Start the host session with the daemon, and return the RPC client and host_id to use for further
/// communication.
pub async fn start_host_session(
    host_id: Uuid,
    zmq_ctx: tmq::Context,
    rpc_address: String,
    kill_switch: Arc<AtomicBool>,
    listeners: ListenersClient,
    curve_keys: Option<(String, String, String)>, // (client_secret, client_public, server_public) - Z85 encoded
) -> Result<(RpcClient, Uuid), RpcError> {
    let services = ZmqHostServices::new(zmq_ctx, rpc_address, String::new(), curve_keys);
    start_host_session_with_services(
        host_id,
        kill_switch,
        listeners,
        HostType::TCP,
        Arc::new(services.clone()),
    )
    .await?;
    Ok((services.rpc_client(), host_id))
}

pub async fn start_host_session_with_services(
    host_id: Uuid,
    kill_switch: Arc<AtomicBool>,
    listeners: ListenersClient,
    host_type: HostType,
    services: Arc<dyn HostServices>,
) -> Result<Uuid, RpcError> {
    loop {
        if kill_switch.load(Ordering::Relaxed) {
            info!("Host shutdown requested during connection attempt");
            return Err(RpcError::CouldNotInitiateSession(
                "Host shutdown requested during connection".to_string(),
            ));
        }

        info!("Registering host with daemon...");
        let timestamp = SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|e| RpcError::CouldNotSend(format!("Invalid timestamp: {e}")))?
            .as_nanos() as u64;

        let listener_list = listeners
            .get_listeners()
            .await
            .map_err(|e| RpcError::CouldNotSend(e.to_string()))?;
        let listeners = listener_list
            .iter()
            .map(|info| ListenerInfo {
                handler_object: info.handler,
                socket_addr: info.addr,
            })
            .collect();

        let reply = services
            .runtime_client()
            .host_call(
                host_id,
                HostRequest::RegisterHost {
                    timestamp,
                    host_type,
                    listeners,
                },
            )
            .await;
        match reply {
            Ok(HostReply::Ack) => {
                info!("Host token accepted by daemon.");
                return Ok(host_id);
            }
            Ok(HostReply::Reject { reason }) => {
                error!("Daemon has rejected this host: {}. Shutting down.", reason);
                kill_switch.store(true, Ordering::SeqCst);
                return Err(RpcError::AuthenticationError(format!(
                    "Daemon rejected host token: {reason}"
                )));
            }
            Ok(_) => return Err(RpcError::UnexpectedReply("Expected Ack".to_string())),
            Err(e) => {
                warn!("Error communicating with daemon to send host token: {}", e);
                tokio::select! {
                    _ = wait_for_kill_switch(kill_switch.clone()) => {
                        info!("Host shutdown requested during connection retry");
                        return Err(RpcError::CouldNotInitiateSession(
                            "Host shutdown requested during connection".to_string(),
                        ));
                    }
                    _ = tokio::time::sleep(tokio::time::Duration::from_secs(5)) => {}
                }
            }
        }
    }
}

pub async fn process_hosts_events(
    rpc_client: RpcClient,
    host_id: Uuid,
    zmq_ctx: tmq::Context,
    events_zmq_address: String,
    listen_address: String,
    kill_switch: Arc<AtomicBool>,
    listeners: ListenersClient,
    our_host_type: HostType,
    curve_keys: Option<(String, String, String)>, // (client_secret, client_public, server_public) - Z85 encoded
    last_daemon_ping: Option<Arc<AtomicU64>>,
) -> Result<(), RpcError> {
    let _ = rpc_client;
    let services = Arc::new(ZmqHostServices::new(
        zmq_ctx,
        String::new(),
        events_zmq_address,
        curve_keys,
    ));
    process_hosts_events_with_services(
        host_id,
        listen_address,
        kill_switch,
        listeners,
        our_host_type,
        services,
        last_daemon_ping,
    )
    .await
}

pub async fn process_hosts_events_with_services(
    host_id: Uuid,
    listen_address: String,
    kill_switch: Arc<AtomicBool>,
    listeners: ListenersClient,
    our_host_type: HostType,
    services: Arc<dyn HostServices>,
    last_daemon_ping: Option<Arc<AtomicU64>>,
) -> Result<(), RpcError> {
    let mut events_sub = services.host_events()?;
    loop {
        let event = tokio::select! {
            _ = wait_for_kill_switch(kill_switch.clone()) => {
                info!("Kill switch activated, stopping...");
                return Ok(());
            }
            event = events_sub.recv_host_event() => event?,
        };

        match event {
            HostBroadcastEvent::PingPong => {
                let timestamp = SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_err(|e| RpcError::CouldNotSend(format!("Invalid timestamp: {e}")))?
                    .as_secs();
                if let Some(ref ping_atomic) = last_daemon_ping {
                    ping_atomic.store(timestamp, Ordering::Relaxed);
                }

                let timestamp = SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_err(|e| RpcError::CouldNotSend(format!("Invalid timestamp: {e}")))?
                    .as_nanos() as u64;

                let listener_list = listeners
                    .get_listeners()
                    .await
                    .map_err(|e| RpcError::CouldNotSend(e.to_string()))?;
                let listeners = listener_list
                    .iter()
                    .map(|info| ListenerInfo {
                        handler_object: info.handler,
                        socket_addr: info.addr,
                    })
                    .collect();

                match services
                    .runtime_client()
                    .host_call(
                        host_id,
                        HostRequest::HostPong {
                            timestamp,
                            host_type: our_host_type,
                            listeners,
                        },
                    )
                    .await
                {
                    Ok(HostReply::Ack) => {}
                    Ok(HostReply::Reject { reason }) => {
                        error!("Daemon has rejected this host: {}. Shutting down.", reason);
                        kill_switch.store(true, Ordering::SeqCst);
                    }
                    Ok(_) => return Err(RpcError::UnexpectedReply("Expected Ack".to_string())),
                    Err(e) => warn!(
                        "Error communicating with daemon to respond to ping: {:?}",
                        e
                    ),
                }
            }
            HostBroadcastEvent::Listen {
                handler_object,
                host_type,
                port,
                options,
            } => {
                let use_tls = bool_option(&options, "tls");
                if host_type != our_host_type {
                    continue;
                }

                let listen_addr = format!("{listen_address}:{port}");
                let sockaddr = match listen_addr.parse::<SocketAddr>() {
                    Ok(sockaddr) => sockaddr,
                    Err(e) => {
                        warn!("Unable to parse listen address {}: {}", listen_addr, e);
                        continue;
                    }
                };
                let tls_label = if use_tls { " (TLS)" } else { "" };
                info!(
                    "Starting listener for {} on {}{}",
                    host_type.id_str(),
                    sockaddr,
                    tls_label
                );
                let listeners = listeners.clone();
                tokio::spawn(async move {
                    let sockaddr = match listen_addr.parse::<SocketAddr>() {
                        Ok(sockaddr) => sockaddr,
                        Err(e) => {
                            error!("Unable to parse address {}: {}", listen_addr, e);
                            return;
                        }
                    };
                    let result = if use_tls {
                        listeners.add_tls_listener(&handler_object, sockaddr).await
                    } else {
                        listeners.add_listener(&handler_object, sockaddr).await
                    };
                    if let Err(e) = result {
                        error!("Error starting listener: {}", e);
                    }
                });
            }
            HostBroadcastEvent::Unlisten { host_type, port } => {
                if host_type == our_host_type {
                    let listen_addr = format!("{listen_address}:{port}");
                    let sockaddr = match listen_addr.parse::<SocketAddr>() {
                        Ok(sockaddr) => sockaddr,
                        Err(e) => {
                            warn!("Unable to parse unlisten address {}: {}", listen_addr, e);
                            continue;
                        }
                    };
                    info!(
                        "Stopping listener for {} on {}",
                        host_type.id_str(),
                        sockaddr
                    );
                    if let Err(e) = listeners.remove_listener(sockaddr).await {
                        error!("Unable to stop listener {}: {}", sockaddr, e);
                    }
                }
            }
        }
    }
}

async fn wait_for_kill_switch(kill_switch: Arc<AtomicBool>) {
    while !kill_switch.load(Ordering::Relaxed) {
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
}

fn bool_option(options: &[(Symbol, Var)], key_name: &str) -> bool {
    let key = Symbol::mk(key_name);
    options
        .iter()
        .find_map(|(option, value)| {
            if *option != key {
                return None;
            }
            if let Some(value) = value.as_bool() {
                return Some(value);
            }
            if let Some(value) = value.as_integer() {
                return Some(value != 0);
            }
            Some(false)
        })
        .unwrap_or(false)
}
