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

//! OAuth login trust-boundary regressions against the shipped cores.

use super::{
    MockTransport,
    test_env::{self, TestEnvironment},
};
use moor_common::{model::ObjectRef, tasks::NoopClientSession};
use moor_kernel::{
    config::FeaturesConfig,
    tasks::{TaskHandle, TaskNotification},
};
use moor_runtime_api::{
    AuthToken, ClientToken, RpcMessageError,
    api::{ClientEvent, ClientReply, ClientRequest, InvocationMode, InvocationOutcome},
    mk_verified_oauth_login_msg,
};
use moor_schema::{convert::obj_from_flatbuffer_struct, rpc as fb};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var, v_int, v_str};
use std::{path::PathBuf, sync::Arc, time::Duration};
use uuid::Uuid;

struct Fixture {
    env: TestEnvironment<MockTransport>,
    features: Arc<FeaturesConfig>,
}
impl Fixture {
    fn new(core: &str) -> Self {
        let _ = moor_kernel::initialize_server_symmetric_key([42; 32]);
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../cores")
            .join(core)
            .join("src");
        let features = Arc::new(FeaturesConfig {
            bool_type: true,
            symbol_type: true,
            custom_errors: true,
            use_uuobjids: true,
            use_boolean_returns: true,
            use_symbols_in_builtins: true,
            anonymous_objects: true,
            ..Default::default()
        });
        let env = test_env::setup_test_environment_with_core(
            Arc::new(MockTransport::new()),
            |config| config.features = features.clone(),
            Some(&path),
        );
        let fixture = Self { env, features };
        if core == "cowbell" {
            fixture.eval("$login.player_setup_capability = $player:issue_capability($login.default_player_class, {'create_child, 'make_player}, 0, $arch_wizard); return 1;");
        } else {
            fixture.eval("$login.create_enabled = 1; return 1;");
        }
        fixture
    }
    fn eval(&self, source: &str) -> Var {
        let task = self
            .env
            .scheduler_client
            .submit_eval_task(
                &Obj::mk_id(2),
                &Obj::mk_id(2),
                source.into(),
                None,
                Arc::new(NoopClientSession::new()),
                self.features.clone(),
            )
            .unwrap();
        wait(task)
    }
    fn call(&self, id: Uuid, request: ClientRequest) -> Result<ClientReply, RpcMessageError> {
        self.env.rpc_server.runtime_api().handle_client_request(
            self.env.scheduler_client.clone(),
            id,
            request,
        )
    }
    fn connection(&self) -> (Uuid, ClientToken) {
        let id = Uuid::new_v4();
        let reply = self
            .call(
                id,
                ClientRequest::ConnectionEstablish {
                    peer_addr: "127.0.0.1".into(),
                    local_port: 7777,
                    remote_port: 12345,
                    acceptable_content_types: None,
                    connection_attributes: None,
                },
            )
            .unwrap();
        let ClientReply::NewConnection { client_token, .. } = reply else {
            panic!("{reply:?}")
        };
        (id, client_token)
    }
    fn login(&self, verified: bool, args: &[&str]) -> Result<ClientReply, RpcMessageError> {
        let (id, token) = self.connection();
        let args = args.iter().map(|s| (*s).to_string()).collect();
        let request = if verified {
            ClientRequest::VerifiedOAuthLogin {
                client_token: token,
                connect_args: args,
                do_attach: false,
            }
        } else {
            ClientRequest::LoginCommand {
                client_token: token,
                handler_object: SYSTEM_OBJECT,
                connect_args: args,
                do_attach: false,
                registration_data: None,
            }
        };
        self.call(id, request)
    }
}
fn wait(task: TaskHandle) -> Var {
    loop {
        match task
            .receiver()
            .recv_timeout(Duration::from_secs(20))
            .expect("task timeout")
        {
            (_, Ok(TaskNotification::Result(value))) => return value,
            (_, Ok(TaskNotification::Suspended)) => continue,
            (_, Err(error)) => panic!("{error:?}"),
        }
    }
}
fn success(reply: Result<ClientReply, RpcMessageError>) -> (Obj, AuthToken) {
    match reply.unwrap() {
        ClientReply::LoginResult {
            success: true,
            player: Some(player),
            auth_token: Some(token),
            ..
        } => (player, token),
        other => panic!("expected successful login, got {other:?}"),
    }
}
fn denied(reply: Result<ClientReply, RpcMessageError>) {
    match reply {
        Ok(ClientReply::LoginResult {
            success: false,
            auth_token: None,
            player: None,
            ..
        })
        | Err(RpcMessageError::LoginTaskFailed(_)) => (),
        other => panic!("expected denial, got {other:?}"),
    }
}
fn exercise(core: &str) {
    let fixture = Fixture::new(core);
    // Create real accounts through password login before attaching test identities.
    let (target, _) = success(fixture.login(false, &["create", "OAuthTarget", "correct-password"]));
    let (other, _) = success(fixture.login(false, &["create", "OAuthOther", "other-password"]));
    fixture.eval(&format!(
        "{target}.oauth2_identities = {{{{\"probe\", \"Known-ID\"}}}}; return 1;"
    ));
    for operation in [
        "oauth2_check",
        "OAUTH2_CHECK",
        "@oauth2_check",
        "oauth2_create",
        "oauth2_connect",
        "do_oauth_login",
    ] {
        denied(fixture.login(
            false,
            &[
                operation,
                "probe",
                "Known-ID",
                "unused",
                "unused",
                "unused",
                "OAuthTarget",
                "wrong",
            ],
        ));
    }
    let (found, token) = success(fixture.login(true, &["oauth2_check", "probe", "Known-ID"]));
    assert_eq!(found, target);
    denied(fixture.login(true, &["oauth2_check", "probe", "known-id"]));
    denied(fixture.login(true, &["oauth2_check", "PROBE", "Known-ID"]));
    denied(fixture.login(true, &["oauth2_check", "probe", "absent"]));
    // A normal player cannot impersonate the host by invoking either layer directly.
    for (object, verb, args) in [
        (
            SYSTEM_OBJECT,
            "do_oauth_login",
            vec![v_str("oauth2_check"), v_str("probe"), v_str("Known-ID")],
        ),
        (
            fixture.eval("return $login;").as_object().unwrap(),
            "oauth2_check",
            vec![v_str("probe"), v_str("Known-ID")],
        ),
    ] {
        let reply = fixture
            .call(
                Uuid::new_v4(),
                ClientRequest::InvokeVerb {
                    auth_token: token.clone(),
                    object: ObjectRef::Id(object),
                    verb: Symbol::mk(verb),
                    args,
                    mode: InvocationMode::CaptureOutput {
                        timeout: Some(Duration::from_secs(5)),
                    },
                },
            )
            .unwrap();
        assert!(
            matches!(reply, ClientReply::InvocationResponse { response } if matches!(response.outcome, InvocationOutcome::Error { .. })),
            "direct {verb} must fail"
        );
    }
    let (connected_id, connected_token) = fixture.connection();
    success(fixture.call(
        connected_id,
        ClientRequest::VerifiedOAuthLogin {
            client_token: connected_token.clone(),
            connect_args: vec!["oauth2_check".into(), "probe".into(), "Known-ID".into()],
            do_attach: false,
        },
    ));
    let reply = fixture
        .call(
            connected_id,
            ClientRequest::InvokeVerb {
                auth_token: token.clone(),
                object: ObjectRef::Id(SYSTEM_OBJECT),
                verb: Symbol::mk("do_oauth_login"),
                args: vec![v_str("oauth2_check"), v_str("probe"), v_str("Known-ID")],
                mode: InvocationMode::Connected {
                    client_token: connected_token,
                },
            },
        )
        .unwrap();
    let ClientReply::TaskSubmitted { task_id } = reply else {
        panic!("{reply:?}")
    };
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        let events = fixture.env.transport.get_client_events();
        assert!(!events.iter().any(|(id, event)| *id == connected_id && matches!(event, ClientEvent::TaskSuccess { task_id: completed, .. } if *completed == task_id)));
        if events.iter().any(|(id, event)| *id == connected_id && matches!(event, ClientEvent::TaskError { task_id: completed, .. } if *completed == task_id)) { break; }
        assert!(std::time::Instant::now() < deadline, "no denial event");
        std::thread::sleep(Duration::from_millis(10));
    }
    assert_eq!(fixture.eval("player = #-100; caller = player; return `#0:do_oauth_login(\"oauth2_check\", \"probe\", \"Known-ID\") ! E_PERM => 42';"), v_int(42));
    assert_eq!(fixture.eval(&format!("set_task_perms({target}); return `{target}.oauth2_identities = {{{{\"probe\", \"forged\"}}}} ! E_PERM => 42';")), v_int(42));
    if core == "cowbell" {
        assert_eq!(fixture.eval(&format!("set_task_perms({target}); return `{target}:set_oauth2_identities({{{{\"probe\", \"forged\"}}}}) ! E_PERM => 42';")), v_int(42));
    }
    if core == "cowbell" {
        // A wizard may explicitly delegate identity repair, including to the account owner.
        assert_eq!(fixture.eval(&format!("let cap = $root:issue_capability({target}, {{'set_oauth2_identities}}, 0, #2); let entries = {target}.oauth2_identities; set_task_perms({target}); cap:set_oauth2_identities(entries); return 42;")), v_int(42));
        // A nonwizard issuer cannot borrow a wizard task's player identity for this operation.
        assert_eq!(fixture.eval(&format!("set_task_perms({target}); let cap = $root:issue_capability({target}, {{'set_oauth2_identities}}, 0, player); return `cap:set_oauth2_identities({{}}) ! E_PERM => 42';")), v_int(42));
        assert_eq!(fixture.eval(&format!("let cap = $root:issue_capability({target}, {{'set_oauth2_identities}}, time() - 1, #2); return `cap:set_oauth2_identities({{}}) ! E_PERM => 42';")), v_int(42));
    }
    // Exercise the serialized host protocol as well as the in-process API.
    let (id, client_token) = fixture.connection();
    let response = fixture
        .env
        .transport
        .process_client_message(
            fixture.env.message_handler.as_ref(),
            fixture.env.scheduler_client.clone(),
            id,
            mk_verified_oauth_login_msg(
                &client_token,
                vec!["oauth2_check".into(), "probe".into(), "Known-ID".into()],
                false,
            ),
        )
        .unwrap();
    let fb::DaemonToClientReplyUnion::LoginResult(login) = response.reply else {
        panic!("{response:?}")
    };
    assert!(login.success);
    assert_eq!(
        obj_from_flatbuffer_struct(login.player.as_ref().unwrap()).unwrap(),
        target
    );
    denied(fixture.login(
        true,
        &[
            "oauth2_connect",
            "probe",
            "new-id",
            "",
            "",
            "",
            "OAuthTarget",
            "wrong",
        ],
    ));
    assert_eq!(
        success(fixture.login(
            true,
            &[
                "oauth2_connect",
                "probe",
                "new-id",
                "",
                "",
                "",
                "OAuthTarget",
                "correct-password"
            ]
        ))
        .0,
        target
    );
    denied(fixture.login(
        true,
        &[
            "oauth2_connect",
            "probe",
            "new-id",
            "",
            "",
            "",
            "OAuthOther",
            "other-password",
        ],
    ));
    assert_eq!(
        fixture.eval(&format!("return length({other}.oauth2_identities);")),
        v_int(0)
    );
    let (created, _) = success(fixture.login(
        true,
        &[
            "oauth2_create",
            "probe",
            "created-id",
            "",
            "",
            "",
            "OAuthCreated",
        ],
    ));
    assert_eq!(
        success(fixture.login(true, &["oauth2_check", "probe", "created-id"])).0,
        created
    );
    denied(fixture.login(false, &["connect", "OAuthCreated", "anything"]));
    denied(fixture.login(
        true,
        &[
            "oauth2_connect",
            "probe",
            "attacker-id",
            "",
            "",
            "",
            "OAuthCreated",
            "anything",
        ],
    ));
    denied(fixture.login(
        true,
        &[
            "oauth2_create",
            "probe",
            "created-id",
            "",
            "",
            "",
            "DuplicateIdentity",
        ],
    ));
    assert_eq!(
        success(fixture.login(false, &["connect", "OAuthTarget", "correct-password"])).0,
        target
    );
    if core != "cowbell" {
        fixture.eval(&format!("$login.newted = {{{target}}}; return 1;"));
        denied(fixture.login(true, &["oauth2_check", "probe", "Known-ID"]));
        denied(fixture.login(
            true,
            &[
                "oauth2_connect",
                "probe",
                "banned-link",
                "",
                "",
                "",
                "OAuthTarget",
                "correct-password",
            ],
        ));
        fixture.eval(
            "$login.newted = {}; $no_connect_message = \"Closed for maintenance\"; return 1;",
        );
        denied(fixture.login(true, &["oauth2_check", "probe", "Known-ID"]));
        denied(fixture.login(
            true,
            &[
                "oauth2_create",
                "probe",
                "closed-id",
                "",
                "",
                "",
                "ClosedAccount",
            ],
        ));
        fixture.eval("$no_connect_message = \"\"; return 1;");
    }
    let results = std::thread::scope(|scope| {
        let first = scope.spawn(|| {
            fixture.login(
                true,
                &["oauth2_create", "probe", "racing-id", "", "", "", "RaceOne"],
            )
        });
        let second = scope.spawn(|| {
            fixture.login(
                true,
                &["oauth2_create", "probe", "racing-id", "", "", "", "RaceTwo"],
            )
        });
        [first.join().unwrap(), second.join().unwrap()]
    });
    assert_eq!(
        results
            .iter()
            .filter(|reply| matches!(reply, Ok(ClientReply::LoginResult { success: true, .. })))
            .count(),
        1,
        "{results:?}"
    );
    assert_eq!(fixture.eval("return length({p for p in (players()) if ({\"probe\", \"racing-id\"} in p.oauth2_identities)});"), v_int(1));
    fixture.eval(&format!(
        "{other}.oauth2_identities = {{{{\"probe\", \"Known-ID\"}}}}; return 1;"
    ));
    denied(fixture.login(true, &["oauth2_check", "probe", "Known-ID"]));
    fixture.eval(&format!("{other}.oauth2_identities = {{}}; return 1;"));
    let (bad_id, _) = fixture.connection();
    assert!(
        fixture
            .call(
                bad_id,
                ClientRequest::VerifiedOAuthLogin {
                    client_token: ClientToken("invalid".into()),
                    connect_args: vec!["oauth2_check".into(), "probe".into(), "Known-ID".into()],
                    do_attach: false
                }
            )
            .is_err()
    );
    let (stale, stale_token) =
        success(fixture.login(false, &["create", "StaleAccount", "stale-password"]));
    fixture.eval(&format!("recycle({stale}); return 1;"));
    let reply = fixture.call(
        Uuid::new_v4(),
        ClientRequest::InvokeVerb {
            auth_token: stale_token,
            object: ObjectRef::Id(SYSTEM_OBJECT),
            verb: Symbol::mk("do_oauth_login"),
            args: vec![v_str("oauth2_check"), v_str("probe"), v_str("Known-ID")],
            mode: InvocationMode::CaptureOutput {
                timeout: Some(Duration::from_secs(5)),
            },
        },
    );
    assert!(
        !matches!(reply, Ok(ClientReply::InvocationResponse { response }) if matches!(response.outcome, InvocationOutcome::Success { .. }))
    );
    assert!(matches!(
        fixture.login(true, &["connect", "OAuthTarget", "correct-password"]),
        Err(RpcMessageError::InvalidRequest(_))
    ));
}
#[test]
fn cowbell_oauth_boundary() {
    exercise("cowbell");
}
#[test]
fn lambda_moor_oauth_boundary() {
    exercise("lambda-moor");
}

#[test]
fn snore_oauth_boundary() {
    exercise("snore");
}
