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

//! Exercise driver departures with the donor cores' actual system hooks.

use crate::testing::{MockTransport, test_env};
use moor_common::{model::ObjectRef, tasks::SessionFactory};
use moor_kernel::{config::FeaturesConfig, tasks::TaskNotification};
use moor_runtime_api::{
    ClientToken,
    api::{ClientReply, ClientRequest},
};
use moor_var::{Obj, Symbol, v_int};
use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};
use uuid::Uuid;

fn exercise(core: &str) {
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
    let wizard = Obj::mk_id(2);
    let eval = |source: &str| {
        let task = env
            .scheduler_client
            .submit_eval_task(
                &wizard,
                &wizard,
                source.into(),
                None,
                env.rpc_server
                    .clone()
                    .mk_background_session(&wizard)
                    .unwrap(),
                features.clone(),
            )
            .unwrap();
        loop {
            match task
                .receiver()
                .recv_timeout(Duration::from_secs(10))
                .expect("eval timed out")
            {
                (_, Ok(TaskNotification::Result(value))) => break value,
                (_, Ok(TaskNotification::Suspended)) => continue,
                (_, Err(error)) => panic!("{core}: {error:?}"),
            }
        }
    };
    eval(
        r#"add_property(#2, "disconnect_count", 0, {#2, ""}); add_verb(#2, {#2, "rxd", "disfunc"}, {"this", "none", "this"});"#,
    );
    env.scheduler_client
        .submit_verb_program(
            &wizard,
            &wizard,
            &ObjectRef::Id(wizard),
            Symbol::mk("disfunc"),
            vec!["this.disconnect_count = this.disconnect_count + 1; return pass(@args);".into()],
        )
        .unwrap();
    let call = |id, request| {
        env.rpc_server.runtime_api().handle_client_request(
            env.scheduler_client.clone(),
            id,
            request,
        )
    };
    let connect = || {
        let id = Uuid::new_v4();
        let ClientReply::NewConnection {
            client_token,
            connection_obj,
        } = call(
            id,
            ClientRequest::ConnectionEstablish {
                peer_addr: "127.0.0.1".into(),
                local_port: 7777,
                remote_port: 12345,
                acceptable_content_types: None,
                connection_attributes: None,
            },
        )
        .unwrap()
        else {
            panic!("expected connection")
        };
        env.connections
            .associate_player_object(connection_obj, wizard)
            .unwrap();
        (id, client_token, connection_obj)
    };
    let detach = |id, token: &ClientToken| {
        call(
            id,
            ClientRequest::Detach {
                client_token: token.clone(),
                disconnected: true,
            },
        )
        .unwrap()
    };
    let wait_removed = |id| {
        let deadline = Instant::now() + Duration::from_secs(5);
        while env.connections.connection_object_for_client(id).is_some() {
            assert!(Instant::now() < deadline, "{core}: removal timed out");
            std::thread::sleep(Duration::from_millis(10));
        }
    };
    let timestamp = if core == "cowbell" {
        "last_disconnected"
    } else {
        "last_disconnect_time"
    };
    for mode in ["detach", "boot_connection", "boot_player", "timeout"] {
        eval(&format!("#2.disconnect_count = 0; #2.{timestamp} = 0;"));
        let (first, first_token, connection) = connect();
        if mode == "timeout" {
            std::thread::sleep(Duration::from_secs(31));
            env.message_handler.ping_pong().unwrap();
        } else {
            let (second, second_token, second_connection) = connect();
            if mode == "boot_player" {
                eval("boot_player(#2);");
            } else {
                if mode == "detach" {
                    detach(second, &second_token);
                } else {
                    eval(&format!("boot_player({second_connection});"));
                }
                wait_removed(second);
                std::thread::sleep(Duration::from_millis(200));
                assert_eq!(
                    eval("return #2.disconnect_count;"),
                    v_int(0),
                    "{core}: premature departure"
                );
                assert_eq!(eval(&format!("return #2.{timestamp};")), v_int(0));
                if mode == "detach" {
                    detach(first, &first_token);
                } else {
                    eval(&format!("boot_player({connection});"));
                }
            }
            wait_removed(second);
        }
        wait_removed(first);
        let deadline = Instant::now() + Duration::from_secs(5);
        while eval("return #2.disconnect_count;") != v_int(1) {
            assert!(
                Instant::now() < deadline,
                "{core}/{mode}: disfunc did not run once"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
        assert_ne!(eval(&format!("return #2.{timestamp};")), v_int(0));
        std::thread::sleep(Duration::from_millis(200));
        assert_eq!(
            eval("return #2.disconnect_count;"),
            v_int(1),
            "{core}/{mode}: duplicate departure"
        );
    }
}

#[test]
fn cowbell_disconnect_lifecycle() {
    exercise("cowbell");
}

#[test]
fn lambda_moor_disconnect_lifecycle() {
    exercise("lambda-moor");
}
