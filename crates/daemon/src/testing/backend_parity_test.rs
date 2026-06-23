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

//! Backend parity tests for daemon request/reply and event behavior.

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        future::Future,
        sync::{Arc, Mutex},
        time::{Duration, Instant, SystemTime, UNIX_EPOCH},
    };

    use moor_common::tasks::Event;
    use moor_runtime_api::{
        AuthToken, ClientToken, HostType, RpcError, RpcMessageError,
        api::{
            ClientEvent, ClientEventSubscription, ClientReply, ClientRequest, HostReply,
            HostRequest, ListenerInfo, RuntimeClient,
        },
        mk_client_pong_msg, mk_command_msg, mk_connection_establish_msg, mk_host_pong_msg,
        mk_login_command_msg, mk_register_host_msg, obj_fb,
    };
    use moor_schema::{convert::obj_from_flatbuffer_struct, rpc as moor_rpc};
    use moor_var::{Obj, SYSTEM_OBJECT, Symbol};
    use uuid::Uuid;

    use crate::{
        runtime::LocalEventBus,
        testing::{MockTransport, test_env},
    };

    trait DaemonTestBackend {
        fn name(&self) -> &'static str;
        fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, String>;
        fn client_call(
            &self,
            client_id: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, String>;
        fn track_client(&self, _client_id: Uuid) {}
        fn wait_for_narrative_event(
            &self,
            player: Option<Obj>,
            predicate: &mut dyn FnMut(&Event) -> bool,
            description: &str,
        );
    }

    struct FlatBufferBackend {
        env: test_env::TestEnvironment<MockTransport>,
    }

    impl FlatBufferBackend {
        fn new() -> Self {
            Self {
                env: test_env::setup_test_environment(Arc::new(MockTransport::new()), |_| {}),
            }
        }
    }

    impl DaemonTestBackend for FlatBufferBackend {
        fn name(&self) -> &'static str {
            "flatbuffer"
        }

        fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, String> {
            let message = encode_host_request(host_id, request)?;
            self.env
                .transport
                .process_host_message(self.env.message_handler.as_ref(), host_id, message)
                .map(decode_host_reply)
                .map_err(|e| e.to_string())
        }

        fn client_call(
            &self,
            client_id: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, String> {
            let message = encode_client_request(request)?;
            self.env
                .transport
                .process_client_message(
                    self.env.message_handler.as_ref(),
                    self.env.scheduler_client.clone(),
                    client_id,
                    message,
                )
                .and_then(decode_client_reply)
                .map_err(|e| e.to_string())
        }

        fn wait_for_narrative_event(
            &self,
            player: Option<Obj>,
            predicate: &mut dyn FnMut(&Event) -> bool,
            description: &str,
        ) {
            let start = Instant::now();
            loop {
                if start.elapsed() > Duration::from_secs(5) {
                    panic!(
                        "{} backend timed out waiting for {description}; observed events: {}",
                        self.name(),
                        describe_events(self.env.transport.get_narrative_events())
                    );
                }

                for (event_player, event) in self.env.transport.get_narrative_events() {
                    if player.is_some_and(|player| event_player != player) {
                        continue;
                    }
                    assert!(
                        !matches!(event.event(), Event::Traceback(_)),
                        "{} backend received traceback while waiting for {description}",
                        self.name()
                    );
                    if predicate(&event.event()) {
                        return;
                    }
                }

                std::thread::sleep(Duration::from_millis(10));
            }
        }
    }

    struct LocalRuntimeBackend {
        env: test_env::TestEnvironment<LocalEventBus>,
        subscriptions: Mutex<HashMap<Uuid, Box<dyn ClientEventSubscription>>>,
    }

    impl LocalRuntimeBackend {
        fn new() -> Self {
            Self {
                env: test_env::setup_test_environment(Arc::new(LocalEventBus::new()), |_| {}),
                subscriptions: Mutex::new(HashMap::new()),
            }
        }

        fn runtime_client(&self) -> crate::runtime::LocalRuntimeClient {
            self.env
                .rpc_server
                .local_runtime_client(self.env.scheduler_client.clone())
        }
    }

    impl DaemonTestBackend for LocalRuntimeBackend {
        fn name(&self) -> &'static str {
            "local-runtime"
        }

        fn host_call(&self, host_id: Uuid, request: HostRequest) -> Result<HostReply, String> {
            block_on(self.runtime_client().host_call(host_id, request)).map_err(rpc_error_string)
        }

        fn client_call(
            &self,
            client_id: Uuid,
            request: ClientRequest,
        ) -> Result<ClientReply, String> {
            block_on(self.runtime_client().client_call(client_id, request))
                .map_err(rpc_error_string)
        }

        fn track_client(&self, client_id: Uuid) {
            let mut subscriptions = self.subscriptions.lock().unwrap();
            subscriptions
                .entry(client_id)
                .or_insert_with(|| Box::new(self.env.transport.subscribe_client_events(client_id)));
        }

        fn wait_for_narrative_event(
            &self,
            player: Option<Obj>,
            predicate: &mut dyn FnMut(&Event) -> bool,
            description: &str,
        ) {
            let start = Instant::now();
            let mut observed_events = Vec::new();
            loop {
                if start.elapsed() > Duration::from_secs(5) {
                    panic!(
                        "{} backend timed out waiting for {description}; observed events: {}",
                        self.name(),
                        describe_client_events(&observed_events)
                    );
                }

                let mut client_ids = self
                    .subscriptions
                    .lock()
                    .unwrap()
                    .keys()
                    .copied()
                    .collect::<Vec<_>>();
                client_ids.sort_unstable();

                for client_id in client_ids {
                    let Some(mut sub) = self.subscriptions.lock().unwrap().remove(&client_id)
                    else {
                        continue;
                    };

                    let recv = block_on(async {
                        tokio::time::timeout(Duration::from_millis(50), sub.recv_client_event())
                            .await
                    });
                    self.subscriptions.lock().unwrap().insert(client_id, sub);

                    let Ok(Ok(event_msg)) = recv else {
                        continue;
                    };

                    let ClientEvent::Narrative { player: p, event } = event_msg.event else {
                        continue;
                    };
                    observed_events.push((p, event.clone()));
                    if player.is_some_and(|player| p != player) {
                        continue;
                    }
                    assert!(
                        !matches!(event.event(), Event::Traceback(_)),
                        "{} backend received traceback while waiting for {description}",
                        self.name()
                    );
                    if predicate(&event.event()) {
                        return;
                    }
                }
            }
        }
    }

    #[test]
    fn host_registration_and_ping_pong_match_backends() {
        run_for_each_backend(|backend| {
            let host_id = Uuid::new_v4();
            let listeners = vec![ListenerInfo {
                handler_object: SYSTEM_OBJECT,
                socket_addr: "127.0.0.1:7777".parse().unwrap(),
            }];

            let register = backend
                .host_call(
                    host_id,
                    HostRequest::RegisterHost {
                        timestamp: now_nanos(),
                        host_type: HostType::TCP,
                        listeners: listeners.clone(),
                    },
                )
                .unwrap_or_else(|e| panic!("{} register host failed: {e}", backend.name()));
            assert!(matches!(register, HostReply::Ack));

            let pong = backend
                .host_call(
                    host_id,
                    HostRequest::HostPong {
                        timestamp: now_nanos(),
                        host_type: HostType::TCP,
                        listeners,
                    },
                )
                .unwrap_or_else(|e| panic!("{} host pong failed: {e}", backend.name()));
            assert!(matches!(pong, HostReply::Ack));
        });
    }

    #[test]
    fn connection_welcome_and_login_match_backends() {
        run_for_each_backend(|backend| {
            let client_id = Uuid::new_v4();
            let (client_token, connection_obj) = establish_connection(backend, client_id);
            backend.track_client(client_id);

            let (auth_token, player_obj) = login_wizard(backend, client_id, &client_token);
            assert!(
                !auth_token.0.is_empty(),
                "{} login returned an empty auth token",
                backend.name()
            );
            assert_eq!(
                player_obj,
                Obj::mk_id(2),
                "{} login should attach as wizard",
                backend.name()
            );
            assert!(
                connection_obj.id().0 < 0,
                "{} connection object should be a negative connection obj",
                backend.name()
            );
        });
    }

    #[test]
    fn command_execution_and_event_delivery_match_backends() {
        run_for_each_backend(|backend| {
            let client_id = Uuid::new_v4();
            let (client_token, _connection_obj) = establish_connection(backend, client_id);
            backend.track_client(client_id);
            let (auth_token, player_obj) = login_wizard(backend, client_id, &client_token);

            let reply = backend
                .client_call(
                    client_id,
                    ClientRequest::Command {
                        client_token,
                        auth_token,
                        handler_object: player_obj,
                        command: "@who".to_string(),
                    },
                )
                .unwrap_or_else(|e| panic!("{} command failed: {e}", backend.name()));
            assert!(matches!(reply, ClientReply::TaskSubmitted { .. }));

            wait_for_output(backend, player_obj, "Wizard", "command output");
        });
    }

    fn run_for_each_backend(test: impl Fn(&dyn DaemonTestBackend)) {
        let flatbuffer = FlatBufferBackend::new();
        test(&flatbuffer);

        let local = LocalRuntimeBackend::new();
        test(&local);
    }

    fn establish_connection(
        backend: &dyn DaemonTestBackend,
        client_id: Uuid,
    ) -> (ClientToken, Obj) {
        let reply = backend
            .client_call(
                client_id,
                ClientRequest::ConnectionEstablish {
                    peer_addr: "127.0.0.1:12345".to_string(),
                    local_port: 7777,
                    remote_port: 12345,
                    acceptable_content_types: Some(vec![Symbol::mk("text/plain")]),
                    connection_attributes: None,
                },
            )
            .unwrap_or_else(|e| panic!("{} establish failed: {e}", backend.name()));

        let ClientReply::NewConnection {
            client_token,
            connection_obj,
        } = reply
        else {
            panic!(
                "{} expected NewConnection reply, got {reply:?}",
                backend.name()
            );
        };
        (client_token, connection_obj)
    }

    fn login_wizard(
        backend: &dyn DaemonTestBackend,
        client_id: Uuid,
        client_token: &ClientToken,
    ) -> (AuthToken, Obj) {
        let welcome = backend
            .client_call(
                client_id,
                ClientRequest::LoginCommand {
                    client_token: client_token.clone(),
                    handler_object: SYSTEM_OBJECT,
                    connect_args: Vec::new(),
                    do_attach: false,
                    event_log_pubkey: None,
                    registration_data: None,
                },
            )
            .unwrap_or_else(|e| panic!("{} welcome failed: {e}", backend.name()));
        assert!(matches!(welcome, ClientReply::LoginResult { .. }));
        wait_for_any_output(backend, "welcome output");

        let login = backend
            .client_call(
                client_id,
                ClientRequest::LoginCommand {
                    client_token: client_token.clone(),
                    handler_object: SYSTEM_OBJECT,
                    connect_args: vec!["connect".to_string(), "wizard".to_string()],
                    do_attach: true,
                    event_log_pubkey: None,
                    registration_data: None,
                },
            )
            .unwrap_or_else(|e| panic!("{} login failed: {e}", backend.name()));

        let ClientReply::LoginResult {
            success: true,
            auth_token: Some(auth_token),
            player: Some(player),
            ..
        } = login
        else {
            panic!(
                "{} expected successful LoginResult, got {login:?}",
                backend.name()
            );
        };
        wait_for_output(
            backend,
            player,
            "This is all there is right now.",
            "post-login room description",
        );
        (auth_token, player)
    }

    fn wait_for_any_output(backend: &dyn DaemonTestBackend, description: &str) {
        let mut predicate = |event: &Event| matches!(event, Event::Notify { .. });
        backend.wait_for_narrative_event(None, &mut predicate, description);
    }

    fn wait_for_output(
        backend: &dyn DaemonTestBackend,
        player: Obj,
        text: &str,
        description: &str,
    ) {
        let mut predicate = |event: &Event| {
            let Event::Notify { value, .. } = event else {
                return false;
            };
            value.as_string().is_some_and(|s| s.contains(text))
        };
        backend.wait_for_narrative_event(Some(player), &mut predicate, description);
    }

    fn describe_events(events: Vec<(Obj, moor_common::tasks::NarrativeEvent)>) -> String {
        let events = events
            .into_iter()
            .map(|(player, event)| format!("player={player:?} event={:?}", event.event()))
            .collect::<Vec<_>>();
        format!("{events:?}")
    }

    fn describe_client_events(events: &[(Obj, moor_common::tasks::NarrativeEvent)]) -> String {
        let events = events
            .iter()
            .map(|(player, event)| format!("player={player:?} event={:?}", event.event()))
            .collect::<Vec<_>>();
        format!("{events:?}")
    }

    fn encode_host_request(
        host_id: Uuid,
        request: HostRequest,
    ) -> Result<moor_rpc::HostToDaemonMessage, String> {
        match request {
            HostRequest::RegisterHost {
                timestamp,
                host_type,
                listeners,
            } => Ok(mk_register_host_msg(
                host_id,
                timestamp,
                encode_host_type(host_type),
                encode_listeners(listeners),
            )),
            HostRequest::HostPong {
                timestamp,
                host_type,
                listeners,
            } => Ok(mk_host_pong_msg(
                host_id,
                timestamp,
                encode_host_type(host_type),
                encode_listeners(listeners),
            )),
            other => Err(format!(
                "unsupported host request in parity backend: {other:?}"
            )),
        }
    }

    fn encode_client_request(
        request: ClientRequest,
    ) -> Result<moor_rpc::HostClientToDaemonMessage, String> {
        match request {
            ClientRequest::ConnectionEstablish {
                peer_addr,
                local_port,
                remote_port,
                acceptable_content_types,
                connection_attributes,
            } => {
                if connection_attributes.is_some() {
                    return Err("connection attributes not supported in parity backend".to_string());
                }
                Ok(mk_connection_establish_msg(
                    peer_addr,
                    local_port,
                    remote_port,
                    acceptable_content_types.map(|symbols| {
                        symbols
                            .into_iter()
                            .map(|value| moor_rpc::Symbol {
                                value: value.as_string(),
                            })
                            .collect()
                    }),
                    None,
                ))
            }
            ClientRequest::LoginCommand {
                client_token,
                handler_object,
                connect_args,
                do_attach,
                event_log_pubkey,
                registration_data,
            } => {
                if registration_data.is_some() {
                    return Err("registration data not supported in parity backend".to_string());
                }
                Ok(mk_login_command_msg(
                    &client_token,
                    &handler_object,
                    connect_args,
                    do_attach,
                    event_log_pubkey,
                    None,
                ))
            }
            ClientRequest::Command {
                client_token,
                auth_token,
                handler_object,
                command,
            } => Ok(mk_command_msg(
                &client_token,
                &auth_token,
                &handler_object,
                command,
            )),
            ClientRequest::ClientPong {
                client_token,
                client_sys_time,
                player,
                host_type,
                socket_addr,
            } => Ok(mk_client_pong_msg(
                &client_token,
                client_sys_time,
                &player,
                encode_host_type(host_type),
                socket_addr,
            )),
            other => Err(format!(
                "unsupported client request in parity backend: {other:?}"
            )),
        }
    }

    fn decode_host_reply(reply: moor_rpc::DaemonToHostReply) -> HostReply {
        match reply.reply {
            moor_rpc::DaemonToHostReplyUnion::DaemonToHostAck(_) => HostReply::Ack,
            moor_rpc::DaemonToHostReplyUnion::DaemonToHostReject(reject) => HostReply::Reject {
                reason: reject.reason,
            },
            other => panic!("unsupported host reply in parity backend: {other:?}"),
        }
    }

    fn decode_client_reply(
        reply: moor_rpc::DaemonToClientReply,
    ) -> Result<ClientReply, RpcMessageError> {
        match reply.reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => {
                let connection_obj =
                    obj_from_flatbuffer_struct(&new_conn.connection_obj).map_err(|e| {
                        RpcMessageError::InternalError(format!("invalid connection obj: {e}"))
                    })?;
                Ok(ClientReply::NewConnection {
                    client_token: ClientToken(new_conn.client_token.token),
                    connection_obj,
                })
            }
            moor_rpc::DaemonToClientReplyUnion::LoginResult(login) => {
                Ok(ClientReply::LoginResult {
                    success: login.success,
                    auth_token: login.auth_token.map(|token| AuthToken(token.token)),
                    connect_type: moor_runtime_api::api::ConnectType::NoConnect,
                    player: login
                        .player
                        .as_ref()
                        .map(|player| {
                            obj_from_flatbuffer_struct(player).map_err(|e| {
                                RpcMessageError::InternalError(format!("invalid player obj: {e}"))
                            })
                        })
                        .transpose()?,
                    player_flags: login.player_flags,
                })
            }
            moor_rpc::DaemonToClientReplyUnion::TaskSubmitted(task) => {
                Ok(ClientReply::TaskSubmitted {
                    task_id: task.task_id,
                })
            }
            other => Err(RpcMessageError::InternalError(format!(
                "unsupported client reply in parity backend: {other:?}"
            ))),
        }
    }

    fn encode_listeners(listeners: Vec<ListenerInfo>) -> Vec<moor_rpc::Listener> {
        listeners
            .into_iter()
            .map(|listener| moor_rpc::Listener {
                handler_object: obj_fb(&listener.handler_object),
                socket_addr: listener.socket_addr.to_string(),
            })
            .collect()
    }

    fn encode_host_type(host_type: HostType) -> moor_rpc::HostType {
        match host_type {
            HostType::TCP => moor_rpc::HostType::Tcp,
            HostType::WebSocket => moor_rpc::HostType::WebSocket,
        }
    }

    fn now_nanos() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos() as u64
    }

    fn block_on<T>(future: impl Future<Output = T>) -> T {
        tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .unwrap()
            .block_on(future)
    }

    fn rpc_error_string(error: RpcError) -> String {
        match error {
            RpcError::Daemon(error) => error.to_string(),
            other => other.to_string(),
        }
    }
}
