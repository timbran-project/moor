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

//! Dynamic telnet/TLS listener lifecycle and accepted-connection bootstrap.

use crate::session::{BoxedAsyncIo, TelnetConnection, codec::ConnectionCodec};
use eyre::bail;
use futures_util::StreamExt;
use hickory_resolver::{TokioResolver, proto::rr::RData};
use moor_schema::{convert::var_to_flatbuffer, rpc as moor_rpc};
use moor_var::{Obj, Symbol};
use rpc_async_client::{
    ListenerInfo, ListenersClient, ListenersError, ListenersMessage, rpc_client::RpcClient, zmq,
};
use rpc_common::{
    CLIENT_BROADCAST_TOPIC, ClientToken, extract_obj, mk_connection_establish_msg,
    read_reply_result,
};
use rustls_pemfile::{certs, private_key};
use std::{
    collections::HashMap,
    fs::File,
    io::BufReader,
    net::{IpAddr, SocketAddr},
    os::fd::{AsRawFd, RawFd},
    path::Path,
    sync::{Arc, atomic::AtomicBool},
};
use tmq::subscribe;
use tmq::subscribe::Subscribe;
use tokio::{
    net::{TcpListener, TcpStream},
    select,
};
use tokio_rustls::{TlsAcceptor, rustls::ServerConfig};
use tokio_util::codec::Framed;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Load TLS configuration from certificate and key files.
pub fn load_tls_config(
    cert_path: &Path,
    key_path: &Path,
) -> Result<Arc<ServerConfig>, eyre::Error> {
    let cert_file = File::open(cert_path)
        .map_err(|e| eyre::eyre!("Failed to open certificate file {:?}: {}", cert_path, e))?;
    let key_file = File::open(key_path)
        .map_err(|e| eyre::eyre!("Failed to open key file {:?}: {}", key_path, e))?;

    let mut cert_reader = BufReader::new(cert_file);
    let mut key_reader = BufReader::new(key_file);

    let cert_chain: Vec<_> = certs(&mut cert_reader)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| eyre::eyre!("Failed to parse certificate: {}", e))?;

    if cert_chain.is_empty() {
        return Err(eyre::eyre!("No certificates found in {:?}", cert_path));
    }

    let key = private_key(&mut key_reader)
        .map_err(|e| eyre::eyre!("Failed to parse private key: {}", e))?
        .ok_or_else(|| eyre::eyre!("No private key found in {:?}", key_path))?;

    let config = ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(cert_chain, key)
        .map_err(|e| eyre::eyre!("Failed to build TLS config: {}", e))?;

    Ok(Arc::new(config))
}

/// Perform async reverse DNS lookup for an IP address
async fn resolve_hostname(ip: IpAddr) -> Result<String, eyre::Error> {
    let resolver = TokioResolver::builder_tokio()?.build()?;
    let response = resolver.reverse_lookup(ip).await?;

    if let Some(name) = response
        .answers()
        .iter()
        .find_map(|record| match &record.data {
            RData::PTR(name) => Some(name),
            _ => None,
        })
    {
        Ok(name.to_string().trim_end_matches('.').to_string())
    } else {
        Err(eyre::eyre!("No PTR record found"))
    }
}

/// Configure CURVE encryption on a SUB socket builder
fn configure_curve_subscriber(
    mut builder: tmq::SocketBuilder<tmq::subscribe::SubscribeWithoutTopic>,
    curve_keys: &Option<(String, String, String)>,
) -> tmq::SocketBuilder<tmq::subscribe::SubscribeWithoutTopic> {
    if let Some((client_secret, client_public, server_public)) = curve_keys {
        let client_secret_bytes =
            zmq::z85_decode(client_secret).expect("Failed to decode client secret key");
        let client_public_bytes =
            zmq::z85_decode(client_public).expect("Failed to decode client public key");
        let server_public_bytes =
            zmq::z85_decode(server_public).expect("Failed to decode server public key");

        builder = builder
            .set_curve_secretkey(&client_secret_bytes)
            .set_curve_publickey(&client_public_bytes)
            .set_curve_serverkey(&server_public_bytes);
    }
    builder
}

pub struct Listeners {
    listeners: HashMap<SocketAddr, Listener>,
    zmq_ctx: tmq::Context,
    rpc_address: String,
    events_address: String,
    kill_switch: Arc<AtomicBool>,
    curve_keys: Option<(String, String, String)>, // (client_secret, client_public, server_public)
    tls_config: Option<Arc<ServerConfig>>,
}

struct AcceptedConnection {
    stream: TcpStream,
    peer_addr: SocketAddr,
    socket_fd: RawFd,
    listener_port: u16,
    handler_object: Obj,
    tls_acceptor: Option<TlsAcceptor>,
}

#[derive(Clone)]
struct ConnectionBootstrap {
    zmq_ctx: tmq::Context,
    rpc_address: String,
    events_address: String,
    kill_switch: Arc<AtomicBool>,
    curve_keys: Option<(String, String, String)>,
}

impl Listeners {
    pub fn new(
        zmq_ctx: tmq::Context,
        rpc_address: String,
        events_address: String,
        kill_switch: Arc<AtomicBool>,
        curve_keys: Option<(String, String, String)>,
        tls_config: Option<Arc<ServerConfig>>,
    ) -> (
        Self,
        tokio::sync::mpsc::Receiver<ListenersMessage>,
        ListenersClient,
    ) {
        let (tx, rx) = tokio::sync::mpsc::channel(100);
        let listeners = Self {
            listeners: HashMap::new(),
            zmq_ctx,
            rpc_address,
            events_address,
            kill_switch,
            curve_keys,
            tls_config,
        };
        let listeners_client = ListenersClient::new(tx);
        (listeners, rx, listeners_client)
    }

    async fn start_listener(
        &mut self,
        handler: Obj,
        addr: SocketAddr,
        reply: tokio::sync::oneshot::Sender<Result<(), ListenersError>>,
        is_tls: bool,
    ) {
        let listener = match TcpListener::bind(addr).await {
            Ok(listener) => listener,
            Err(e) => {
                let _ = reply.send(Err(ListenersError::AddListenerFailed(handler, addr)));
                error!(?addr, "Unable to bind listener: {}", e);
                return;
            }
        };

        let (terminate_send, terminate_receive) = tokio::sync::watch::channel(false);
        self.listeners
            .insert(addr, Listener::new(terminate_send, handler, is_tls));

        let tls_label = if is_tls { " (TLS)" } else { "" };
        info!("Listening @ {}{}", addr, tls_label);

        let zmq_ctx = self.zmq_ctx.clone();
        let rpc_address = self.rpc_address.clone();
        let events_address = self.events_address.clone();
        let kill_switch = self.kill_switch.clone();
        let curve_keys = self.curve_keys.clone();
        let tls_acceptor = if is_tls {
            self.tls_config
                .as_ref()
                .map(|c| TlsAcceptor::from(c.clone()))
        } else {
            None
        };

        // Signal that the listener is successfully bound
        let _ = reply.send(Ok(()));

        let local_listener_port = listener
            .local_addr()
            .map(|addr| addr.port())
            .unwrap_or(addr.port());

        let bootstrap = ConnectionBootstrap {
            zmq_ctx,
            rpc_address,
            events_address,
            kill_switch,
            curve_keys,
        };
        tokio::spawn(run_listener_accept_loop(
            listener,
            terminate_receive,
            bootstrap,
            handler,
            local_listener_port,
            tls_acceptor,
            is_tls,
        ));
    }

    pub async fn run(
        &mut self,
        mut listeners_channel: tokio::sync::mpsc::Receiver<ListenersMessage>,
    ) {
        self.zmq_ctx
            .set_io_threads(8)
            .expect("Unable to set ZMQ IO threads");

        loop {
            if self.kill_switch.load(std::sync::atomic::Ordering::Relaxed) {
                info!("Host kill switch activated, stopping...");
                return;
            }

            match listeners_channel.recv().await {
                Some(message) => self.handle_listener_message(message).await,
                None => {
                    warn!("Listeners channel closed, stopping...");
                    return;
                }
            }
        }
    }

    async fn handle_listener_message(&mut self, message: ListenersMessage) {
        match message {
            ListenersMessage::AddListener(handler, addr, reply) => {
                self.start_listener(handler, addr, reply, false).await;
            }
            ListenersMessage::AddTlsListener(handler, addr, reply) => {
                if self.tls_config.is_none() {
                    error!("TLS listener requested but no TLS config available");
                    let _ = reply.send(Err(ListenersError::AddListenerFailed(handler, addr)));
                    return;
                }
                self.start_listener(handler, addr, reply, true).await;
            }
            ListenersMessage::RemoveListener(addr, reply) => {
                self.remove_listener(addr, reply);
            }
            ListenersMessage::GetListeners(tx) => {
                self.send_listeners(tx);
            }
        }
    }

    fn remove_listener(
        &mut self,
        addr: SocketAddr,
        reply: tokio::sync::oneshot::Sender<Result<(), ListenersError>>,
    ) {
        info!(?addr, "Removing listener");
        let Some(listener) = self.listeners.remove(&addr) else {
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
                is_tls: listener.is_tls,
            })
            .collect();
        if let Err(e) = tx.send(listeners) {
            error!("Unable to send listeners list: {:?}", e);
        }
    }
}

pub struct Listener {
    pub(crate) handler_object: Obj,
    pub(crate) terminate: tokio::sync::watch::Sender<bool>,
    pub(crate) is_tls: bool,
}

impl Listener {
    pub fn new(
        terminate: tokio::sync::watch::Sender<bool>,
        handler_object: Obj,
        is_tls: bool,
    ) -> Self {
        Self {
            handler_object,
            terminate,
            is_tls,
        }
    }

    async fn handle_accepted_connection(
        bootstrap: ConnectionBootstrap,
        accepted: AcceptedConnection,
    ) -> Result<(), eyre::Report> {
        tokio::spawn(async move {
            let client_id = Uuid::new_v4();
            info!(peer_addr = ?accepted.peer_addr, client_id = ?client_id, port = accepted.listener_port,
                "Accepted connection for listener"
            );

            let rpc_client = RpcClient::new_with_defaults(
                std::sync::Arc::new(bootstrap.zmq_ctx.clone()),
                bootstrap.rpc_address.clone(),
                bootstrap.curve_keys.as_ref().map(
                    |(client_secret, client_public, server_public)| {
                        rpc_async_client::rpc_client::CurveKeys {
                            client_secret: client_secret.clone(),
                            client_public: client_public.clone(),
                            server_public: server_public.clone(),
                        }
                    },
                ),
            );

            let mut connection_attributes = initial_connection_attributes();

            let hostname = resolve_hostname(accepted.peer_addr.ip())
                .await
                .unwrap_or_else(|_| accepted.peer_addr.to_string());

            let (client_token, connection_oid) = establish_connection(
                &rpc_client,
                client_id,
                &hostname,
                accepted.listener_port,
                accepted.peer_addr.port(),
                &connection_attributes,
            )
            .await?;
            debug!(client_id = ?client_id, connection = ?connection_oid, "Connection established");

            let (events_sub, broadcast_sub) = subscribe_for_client(&bootstrap, client_id)?;

            let is_tls = accepted.tls_acceptor.is_some();
            let boxed_stream = boxed_stream_from_accepted(
                accepted.stream,
                accepted.peer_addr,
                accepted.tls_acceptor,
            )
            .await?;

            // Add TLS status to connection attributes
            connection_attributes.insert(Symbol::mk("tls"), moor_var::Var::mk_bool(is_tls));

            // Re-ify the connection.
            let framed_stream = Framed::new(boxed_stream, ConnectionCodec::new());
            let (write, read) = framed_stream.split();
            let mut tcp_connection = TelnetConnection {
                handler_object: accepted.handler_object,
                peer_addr: accepted.peer_addr,
                connection_object: connection_oid,
                player_object: None,
                client_token,
                client_id,
                write,
                read,
                kill_switch: bootstrap.kill_switch,
                broadcast_sub,
                narrative_sub: events_sub,
                auth_token: None,
                rpc_client,
                pending_task: None,
                output_prefix: None,
                output_suffix: None,
                flush_command: crate::session::DEFAULT_FLUSH_COMMAND.to_string(),
                connection_attributes,
                is_binary_mode: false,
                hold_input: None,
                disable_oob: false,
                pending_line_mode: None,
                collecting_input: false,
                socket_fd: accepted.socket_fd,
                supports_utf8: false,
                screen_reader_mode: false,
            };

            tcp_connection.run().await?;
            Ok::<(), eyre::Error>(())
        });
        Ok(())
    }
}

async fn run_listener_accept_loop(
    listener: TcpListener,
    terminate_receive: tokio::sync::watch::Receiver<bool>,
    bootstrap: ConnectionBootstrap,
    handler_object: Obj,
    listener_port: u16,
    tls_acceptor: Option<TlsAcceptor>,
    is_tls: bool,
) {
    loop {
        let mut term_receive = terminate_receive.clone();
        select! {
            _ = term_receive.changed() => {
                info!("Listener terminated, stopping...");
                return;
            }
            result = listener.accept() => {
                let Ok((stream, peer_addr)) = result else {
                    warn!(?result, "Accept failed, can't handle connection");
                    return;
                };

                info!(?peer_addr, is_tls, "Accepted connection for listener");
                let accepted = AcceptedConnection {
                    socket_fd: stream.as_raw_fd(),
                    stream,
                    peer_addr,
                    listener_port,
                    handler_object,
                    tls_acceptor: tls_acceptor.clone(),
                };
                tokio::spawn(Listener::handle_accepted_connection(
                    bootstrap.clone(),
                    accepted,
                ));
            }
        }
    }
}

fn initial_connection_attributes() -> HashMap<Symbol, moor_var::Var> {
    let mut attributes = HashMap::new();
    attributes.insert(Symbol::mk("host_type"), moor_var::Var::from("telnet"));
    attributes.insert(
        Symbol::mk("supports-telnet-protocol"),
        moor_var::Var::mk_bool(true),
    );
    attributes.insert(Symbol::mk("client-echo"), moor_var::Var::mk_bool(true));
    attributes.insert(Symbol::mk("screen-reader"), moor_var::Var::mk_bool(false));
    attributes
}

async fn establish_connection(
    rpc_client: &RpcClient,
    client_id: Uuid,
    hostname: &str,
    listener_port: u16,
    peer_port: u16,
    connection_attributes: &HashMap<Symbol, moor_var::Var>,
) -> Result<(ClientToken, Obj), eyre::Error> {
    let conn_establish_msg = mk_connection_establish_msg(
        hostname.to_string(),
        listener_port,
        peer_port,
        Some(acceptable_content_types()),
        Some(connection_attributes_fb(connection_attributes)),
    );

    let bytes = rpc_client
        .make_client_rpc_call(client_id, conn_establish_msg)
        .await
        .map_err(|e| eyre::eyre!("Unable to establish connection: {}", e))?;
    let reply_ref =
        read_reply_result(&bytes).map_err(|e| eyre::eyre!("Invalid flatbuffer: {}", e))?;

    let (client_token, connection_oid) =
        new_connection_from_reply(reply_ref, connection_attributes.len())?;
    Ok((client_token, connection_oid))
}

fn acceptable_content_types() -> Vec<moor_rpc::Symbol> {
    vec![
        moor_rpc::Symbol {
            value: "text_djot".to_string(),
        },
        moor_rpc::Symbol {
            value: "text_plain".to_string(),
        },
    ]
}

fn connection_attributes_fb(
    connection_attributes: &HashMap<Symbol, moor_var::Var>,
) -> Vec<moor_rpc::ConnectionAttribute> {
    connection_attributes
        .iter()
        .filter_map(|(key, value)| {
            let var_fb = var_to_flatbuffer(value).ok()?;
            Some(moor_rpc::ConnectionAttribute {
                key: Box::new(moor_rpc::Symbol {
                    value: key.as_string(),
                }),
                value: Box::new(var_fb),
            })
        })
        .collect()
}

fn subscribe_for_client(
    bootstrap: &ConnectionBootstrap,
    client_id: Uuid,
) -> Result<(Subscribe, Subscribe), eyre::Error> {
    let events_sub =
        configure_curve_subscriber(subscribe(&bootstrap.zmq_ctx), &bootstrap.curve_keys)
            .connect(bootstrap.events_address.as_str())
            .map_err(|e| eyre::eyre!("Unable to connect narrative subscriber: {}", e))?;
    let events_sub = events_sub
        .subscribe(&client_id.as_bytes()[..])
        .map_err(|e| eyre::eyre!("Unable to subscribe to narrative messages: {}", e))?;

    let broadcast_sub =
        configure_curve_subscriber(subscribe(&bootstrap.zmq_ctx), &bootstrap.curve_keys)
            .connect(bootstrap.events_address.as_str())
            .map_err(|e| eyre::eyre!("Unable to connect broadcast subscriber: {}", e))?;
    let broadcast_sub = broadcast_sub
        .subscribe(CLIENT_BROADCAST_TOPIC)
        .map_err(|e| eyre::eyre!("Unable to subscribe to broadcast messages: {}", e))?;

    info!(
        "Subscribed on pubsub events socket for {:?}, socket addr {}",
        client_id, bootstrap.events_address
    );
    Ok((events_sub, broadcast_sub))
}

fn new_connection_from_reply(
    reply_ref: moor_rpc::ReplyResultRef<'_>,
    attribute_count: usize,
) -> Result<(ClientToken, Obj), eyre::Error> {
    let result = reply_ref
        .result()
        .map_err(|e| eyre::eyre!("Missing result: {}", e))?;

    let moor_rpc::ReplyResultUnionRef::ClientSuccess(client_success) = result else {
        if let moor_rpc::ReplyResultUnionRef::Failure(failure) = result {
            let error_ref = failure
                .error()
                .map_err(|e| eyre::eyre!("Missing error: {}", e))?;
            let error_msg = error_ref
                .message()
                .unwrap_or(Some("Unknown error"))
                .unwrap_or("Unknown error");
            bail!("RPC failure in connection establishment: {}", error_msg);
        }
        bail!("Unexpected response type");
    };

    let daemon_reply = client_success
        .reply()
        .map_err(|e| eyre::eyre!("Missing reply: {}", e))?;
    let reply_union = daemon_reply
        .reply()
        .map_err(|e| eyre::eyre!("Missing reply union: {}", e))?;

    let moor_rpc::DaemonToClientReplyUnionRef::NewConnection(new_conn) = reply_union else {
        bail!("Unexpected response from RPC server");
    };

    let token_ref = new_conn
        .client_token()
        .map_err(|e| eyre::eyre!("Missing client_token: {}", e))?;
    let token = ClientToken(
        token_ref
            .token()
            .map_err(|e| eyre::eyre!("Missing token: {}", e))?
            .to_string(),
    );

    let objid = extract_obj(&new_conn, "connection_obj", |new_conn| {
        new_conn.connection_obj()
    })
    .map_err(|e| eyre::eyre!("{}", e))?;

    info!(
        "Connection established with {} attributes, connection ID: {}",
        attribute_count, objid
    );
    Ok((token, objid))
}

async fn boxed_stream_from_accepted(
    stream: TcpStream,
    peer_addr: SocketAddr,
    tls_acceptor: Option<TlsAcceptor>,
) -> Result<BoxedAsyncIo, eyre::Error> {
    let Some(acceptor) = tls_acceptor else {
        return Ok(Box::pin(stream));
    };

    match acceptor.accept(stream).await {
        Ok(tls_stream) => Ok(Box::pin(tls_stream)),
        Err(e) => {
            error!(?peer_addr, "TLS handshake failed: {}", e);
            bail!("TLS handshake failed: {}", e);
        }
    }
}
