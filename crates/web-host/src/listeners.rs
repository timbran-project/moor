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

//! Dynamic listener lifecycle and per-listener HTTP server tasks.

use std::{
    collections::HashMap,
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64},
    },
};

use axum::Router;
use ipnet::IpNet;
use moor_var::Obj;
use rpc_async_client::{ListenerInfo, ListenersClient, ListenersError, ListenersMessage};
use tokio::{net::TcpListener, select};
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::{
    host::{OAuth2Manager, OAuth2State, PendingOAuth2Store, WebHost, webrtc::WebRtcConfig},
    routes::{CorsConfig, RateLimitConfig, mk_routes},
};

pub struct Listeners {
    host_id: Uuid,
    listeners: HashMap<SocketAddr, Listener>,
    zmq_ctx: tmq::Context,
    rpc_address: String,
    events_address: String,
    kill_switch: Arc<AtomicBool>,
    oauth2_manager: Option<Arc<OAuth2Manager>>,
    curve_keys: Option<(String, String, String)>,
    enable_webhooks: bool,
    last_daemon_ping: Arc<AtomicU64>,
    cors_config: CorsConfig,
    rate_limit_config: RateLimitConfig,
    trusted_proxy_cidrs: Arc<Vec<IpNet>>,
    webrtc_config: Arc<WebRtcConfig>,
}

impl Listeners {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        host_id: Uuid,
        zmq_ctx: tmq::Context,
        rpc_address: String,
        events_address: String,
        kill_switch: Arc<AtomicBool>,
        oauth2_manager: Option<Arc<OAuth2Manager>>,
        curve_keys: Option<(String, String, String)>,
        enable_webhooks: bool,
        last_daemon_ping: Arc<AtomicU64>,
        cors_config: CorsConfig,
        rate_limit_config: RateLimitConfig,
        trusted_proxy_cidrs: Arc<Vec<IpNet>>,
        webrtc_config: Arc<WebRtcConfig>,
    ) -> (
        Self,
        tokio::sync::mpsc::Receiver<ListenersMessage>,
        ListenersClient,
    ) {
        let (tx, rx) = tokio::sync::mpsc::channel(100);
        let listeners = Self {
            host_id,
            listeners: HashMap::new(),
            zmq_ctx,
            rpc_address,
            events_address,
            kill_switch,
            oauth2_manager,
            curve_keys,
            enable_webhooks,
            last_daemon_ping,
            cors_config,
            rate_limit_config,
            trusted_proxy_cidrs,
            webrtc_config,
        };
        let listeners_client = ListenersClient::new(tx);
        (listeners, rx, listeners_client)
    }

    pub async fn run(
        &mut self,
        mut listeners_channel: tokio::sync::mpsc::Receiver<ListenersMessage>,
    ) {
        if let Err(e) = self.zmq_ctx.set_io_threads(8) {
            error!("Unable to set ZMQ IO threads: {}", e);
            return;
        }

        loop {
            if self.kill_switch.load(std::sync::atomic::Ordering::Relaxed) {
                info!("Host kill switch activated, stopping...");
                return;
            }

            match listeners_channel.recv().await {
                Some(ListenersMessage::AddTlsListener(handler, addr, reply)) => {
                    error!(?addr, "TLS listeners not supported by web-host");
                    let _ = reply.send(Err(ListenersError::AddListenerFailed(handler, addr)));
                }
                Some(ListenersMessage::AddListener(handler, addr, reply)) => {
                    self.add_listener(handler, addr, reply).await;
                }
                Some(ListenersMessage::RemoveListener(addr, reply)) => {
                    self.remove_listener(addr, reply);
                }
                Some(ListenersMessage::GetListeners(tx)) => {
                    self.send_listeners(tx);
                }
                None => {
                    warn!("Listeners channel closed, stopping...");
                    return;
                }
            }
        }
    }

    async fn add_listener(
        &mut self,
        handler: Obj,
        addr: SocketAddr,
        reply: tokio::sync::oneshot::Sender<Result<(), ListenersError>>,
    ) {
        let listener = match TcpListener::bind(addr).await {
            Ok(listener) => listener,
            Err(e) => {
                let _ = reply.send(Err(ListenersError::AddListenerFailed(handler, addr)));
                error!(?addr, "Unable to bind listener: {}", e);
                return;
            }
        };

        let local_addr = match listener.local_addr() {
            Ok(addr) => addr,
            Err(e) => {
                error!(?addr, "Unable to get local address: {}", e);
                return;
            }
        };

        let web_host = WebHost::new(
            self.zmq_ctx.clone(),
            self.rpc_address.clone(),
            self.events_address.clone(),
            handler,
            local_addr.port(),
            self.curve_keys.clone(),
            self.host_id,
            self.last_daemon_ping.clone(),
            self.trusted_proxy_cidrs.clone(),
            self.webrtc_config.clone(),
        );
        let oauth2_state = self.oauth2_state(&web_host);
        let main_router = match mk_routes(
            web_host,
            oauth2_state,
            self.enable_webhooks,
            &self.cors_config,
            &self.rate_limit_config,
            &self.trusted_proxy_cidrs,
        ) {
            Ok(router) => router,
            Err(e) => {
                warn!(?e, "Unable to create main router");
                return;
            }
        };

        let (terminate_send, terminate_receive) = tokio::sync::watch::channel(false);
        self.listeners
            .insert(addr, Listener::new(terminate_send, handler));
        let _ = reply.send(Ok(()));

        tokio::spawn(async move {
            let mut term_receive = terminate_receive.clone();
            select! {
                _ = term_receive.changed() => {
                    info!("Listener terminated, stopping...");
                }
                _ = Listener::serve(listener, main_router) => {
                    info!("Listener exited, restarting...");
                }
            }
        });
    }

    fn oauth2_state(&self, web_host: &WebHost) -> Option<OAuth2State> {
        self.oauth2_manager.as_ref().map(|manager| {
            let pending = Arc::new(PendingOAuth2Store::new());
            let reap_pending = Arc::clone(&pending);
            tokio::spawn(async move {
                let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
                loop {
                    interval.tick().await;
                    reap_pending.reap_expired();
                }
            });
            OAuth2State {
                manager: Arc::clone(manager),
                web_host: web_host.clone(),
                pending,
            }
        })
    }

    fn remove_listener(
        &mut self,
        addr: SocketAddr,
        reply: tokio::sync::oneshot::Sender<Result<(), ListenersError>>,
    ) {
        let listener = self.listeners.remove(&addr);
        info!(?addr, "Removing listener");

        let Some(listener) = listener else {
            let _ = reply.send(Err(ListenersError::RemoveListenerFailed(addr)));
            return;
        };

        if let Err(e) = listener.terminate.send(true) {
            error!("Unable to send terminate message: {}", e);
        }
        let _ = reply.send(Ok(()));
    }

    fn send_listeners(&self, tx: tokio::sync::oneshot::Sender<Vec<ListenerInfo>>) {
        let listeners = self
            .listeners
            .iter()
            .map(|(addr, listener)| ListenerInfo {
                handler: listener.handler_object,
                addr: *addr,
                is_tls: false,
            })
            .collect();
        if let Err(e) = tx.send(listeners) {
            error!("Unable to send listeners list: {:?}", e);
        }
    }
}

pub struct Listener {
    handler_object: Obj,
    terminate: tokio::sync::watch::Sender<bool>,
}

impl Listener {
    fn new(terminate: tokio::sync::watch::Sender<bool>, handler_object: Obj) -> Self {
        Self {
            handler_object,
            terminate,
        }
    }

    async fn serve(listener: TcpListener, main_router: Router) -> eyre::Result<()> {
        let addr = listener.local_addr()?;
        info!("Listening on {:?}", addr);
        axum::serve(
            listener,
            main_router.into_make_service_with_connect_info::<SocketAddr>(),
        )
        .await?;
        info!("Done listening on {:?}", addr);
        Ok(())
    }
}
