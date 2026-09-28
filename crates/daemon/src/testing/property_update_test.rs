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

//! Property editing through the authenticated daemon API.

use super::{
    MockTransport,
    test_env::{self, TestEnvironment},
};
use moor_common::{
    model::{ObjectRef, WorldStateError},
    tasks::{CommandError, NoopClientSession, SchedulerError},
};
use moor_kernel::{
    config::FeaturesConfig,
    tasks::{TaskHandle, TaskNotification},
};
use moor_runtime_api::{
    AuthToken, MOOR_AUTH_TOKEN_FOOTER, RpcMessageError,
    api::{ClientReply, ClientRequest},
};
use moor_var::{Obj, Symbol, Var, v_int};
use rusty_paseto::core::{Footer, Paseto, PasetoAsymmetricPrivateKey, Payload, Public, V4};
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
        Self { env, features }
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

fn exercise(core: &str) {
    let fixture = Fixture::new(core);
    let actor = fixture
        .eval("o = create(#1); o.owner = o; set_player_flag(o, 1); return o;")
        .as_object()
        .unwrap();
    let target = fixture
        .eval("o = create(#1); add_property(o, \"payload\", 7, {#2, \"r\"}); return o;")
        .as_object()
        .unwrap();
    let (_, key) = test_env::create_test_keys();
    let token = AuthToken(
        Paseto::<V4, Public>::default()
            .set_footer(Footer::from(MOOR_AUTH_TOKEN_FOOTER))
            .set_payload(Payload::from(
                serde_json::json!({"player": actor.to_string()})
                    .to_string()
                    .as_str(),
            ))
            .try_sign(&PasetoAsymmetricPrivateKey::from(&key))
            .unwrap(),
    );
    let update = |property: &str| {
        fixture.call(
            Uuid::new_v4(),
            ClientRequest::UpdateProperty {
                auth_token: token.clone(),
                object: ObjectRef::Id(target),
                property: Symbol::mk(property),
                value: v_int(8),
            },
        )
    };
    assert!(matches!(
        update("payload"),
        Err(RpcMessageError::TaskError(
            SchedulerError::PropertyRetrievalFailed(WorldStateError::PropertyPermissionDenied)
        ))
    ));
    assert_eq!(fixture.eval(&format!("return {target}.payload;")), v_int(7));
    fixture.eval(&format!(
        "set_property_info({target}, \"payload\", {{{actor}, \"r\"}}); return 1;"
    ));
    assert!(matches!(
        update("payload"),
        Ok(ClientReply::PropertyUpdated)
    ));
    assert_eq!(fixture.eval(&format!("return {target}.payload;")), v_int(8));
    assert!(matches!(
        update("missing"),
        Err(RpcMessageError::TaskError(
            SchedulerError::PropertyRetrievalFailed(WorldStateError::PropertyNotFound(..))
        ))
    ));
    fixture.eval(&format!("recycle({target}); return 1;"));
    assert!(matches!(
        update("payload"),
        Err(RpcMessageError::TaskError(
            SchedulerError::CommandExecutionError(CommandError::NoObjectMatch)
        ))
    ));
}

#[test]
fn property_update_cowbell() {
    exercise("cowbell");
}

#[test]
fn property_update_lambda_moor() {
    exercise("lambda-moor");
}
