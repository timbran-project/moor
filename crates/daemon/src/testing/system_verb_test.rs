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

//! Integration tests for connection-free system verb calls.
//!
//! `CallSystemVerb` submits a task without a login or a connection record. These
//! tests cover who the task runs as, which object it targets, and that the
//! absence of a connection is visible in-world.

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use uuid::Uuid;

    use crate::testing::{MockTransport, test_env};
    use moor_common::model::{ObjFlag, ObjectRef};
    use moor_common::tasks::NoopClientSession;
    use moor_kernel::SchedulerClient;
    use moor_kernel::config::Config;
    use moor_kernel::tasks::TaskNotification;
    use moor_runtime_api::{
        AuthToken, MOOR_AUTH_TOKEN_FOOTER, RpcMessageError, mk_call_system_verb_msg,
    };
    use moor_schema::rpc as moor_rpc;
    use moor_var::{Obj, SYSTEM_OBJECT, Symbol, Var, v_int};
    use planus::ReadAsRoot;
    use rusty_paseto::core::{Footer, Paseto, PasetoAsymmetricPrivateKey, Payload, Public, V4};
    use serde_json::json;

    type TestEnvironment = test_env::TestEnvironment<MockTransport>;

    /// Mint an auth token for `player` with the test keypair, which is what
    /// holding the daemon's signing key amounts to. No login involved.
    fn auth_token_for(player: &Obj) -> AuthToken {
        let (_public_key, private_key) = test_env::create_test_keys();
        let privkey = PasetoAsymmetricPrivateKey::from(&private_key);
        let token = Paseto::<V4, Public>::default()
            .set_footer(Footer::from(MOOR_AUTH_TOKEN_FOOTER))
            .set_payload(Payload::from(
                json!({ "player": player.to_string() }).to_string().as_str(),
            ))
            .try_sign(&privkey)
            .expect("token should sign");
        AuthToken(token)
    }

    fn setup() -> TestEnvironment {
        let mut env =
            test_env::setup_test_environment_with_checkpoint_output(Arc::new(MockTransport::new()));
        env._temp_output_dir = None;
        env.output_dir_path = None;
        test_env::wait_for_scheduler_ready(&env.scheduler_client);
        env
    }

    /// JHCore's wizard.
    const WIZARD: Obj = Obj::mk_id(2);

    /// Test verbs are created owned by the wizard, so this is what a verb body
    /// runs as under ordinary MOO activation rules.
    const VERB_OWNER: Obj = WIZARD;

    /// Run `code` as a wizard eval, returning its value.
    fn eval(env: &TestEnvironment, code: &str) -> Var {
        let task_handle = env
            .scheduler_client
            .submit_eval_task(
                &WIZARD,
                &WIZARD,
                code.to_string(),
                None,
                Arc::new(NoopClientSession::new()),
                Arc::new(Config::default()).features.clone(),
            )
            .expect("eval should submit");

        match task_handle.into_receiver().recv() {
            Ok((_, Ok(TaskNotification::Result(v)))) => v,
            Ok((_, Err(e))) => panic!("eval of {code:?} failed: {e:?}"),
            _ => panic!("eval of {code:?} did not return a result"),
        }
    }

    /// Add a verb on `object` and program it, so a test can observe what the
    /// task sees. `submit_verb_program` only rewrites an existing verb, so the
    /// verb has to be created first.
    fn program_verb(env: &TestEnvironment, object: Obj, verb: &str, code: &str) {
        eval(
            env,
            &format!(
                "add_verb(#{0}, {{#2, \"rxd\", \"{verb}\"}}, {{\"this\", \"none\", \"this\"}}); return 1;",
                object.id().0
            ),
        );

        env.scheduler_client
            .submit_verb_program(
                &WIZARD,
                &WIZARD,
                &ObjectRef::Id(object),
                Symbol::mk(verb),
                code.lines().map(|l| l.to_string()).collect(),
            )
            .expect("verb should program");
    }

    /// Call a verb through the RPC path under test, returning the raw reply.
    fn call_system_verb(
        env: &TestEnvironment,
        auth_token: Option<&AuthToken>,
        verb: &str,
        object: Option<ObjectRef>,
        authority_principal: Option<Obj>,
    ) -> Result<moor_rpc::DaemonToClientReply, RpcMessageError> {
        let message = mk_call_system_verb_msg(
            auth_token,
            &Symbol::mk(verb),
            vec![],
            object.as_ref(),
            authority_principal.as_ref(),
        )
        .expect("message should encode");

        env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        )
    }

    /// Unwrap a successful verb call, returning the result value. The owned
    /// FlatBuffer is re-serialised because the conversions are all ref-based.
    fn expect_success(reply: moor_rpc::DaemonToClientReply) -> Var {
        let result = match reply.reply {
            moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(response) => {
                match response.response {
                    moor_rpc::VerbCallResponseUnion::VerbCallSuccess(success) => success.result,
                    moor_rpc::VerbCallResponseUnion::VerbCallError(e) => {
                        panic!("Expected success, got error: {e:?}")
                    }
                }
            }
            other => panic!("Expected VerbCallResponse, got {other:?}"),
        };

        let mut builder = planus::Builder::new();
        let bytes = builder.finish(&*result, None).to_vec();
        let var_ref = moor_schema::var::VarRef::read_as_root(&bytes).expect("var should read");
        moor_schema::convert::var_from_flatbuffer_ref(var_ref).expect("var should decode")
    }

    /// The task's `player` comes from the auth token, so in-world code sees a
    /// real identity even though nothing logged in.
    #[test]
    fn player_comes_from_the_auth_token() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_who_am_i", "return player;");

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_who_am_i", None, None)
            .expect("call should succeed");

        assert_eq!(
            expect_success(reply).as_object(),
            Some(WIZARD),
            "player should be the auth token's player, not #0"
        );
    }

    /// Without a token the task runs as #0, which is what the welcome-message
    /// path relies on.
    #[test]
    fn player_defaults_to_system_object_without_a_token() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_who_am_i", "return player;");

        let reply =
            call_system_verb(&env, None, "test_who_am_i", None, None).expect("call should succeed");

        assert_eq!(expect_success(reply).as_object(), Some(SYSTEM_OBJECT));
    }

    /// An absent `object` keeps the previous behaviour of targeting #0.
    #[test]
    fn object_defaults_to_system_object() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_where_am_i", "return this;");

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_where_am_i", None, None)
            .expect("call should succeed");

        assert_eq!(expect_success(reply).as_object(), Some(SYSTEM_OBJECT));
    }

    /// A verb on an object other than #0 is now reachable directly.
    #[test]
    fn object_may_be_any_object() {
        let env = setup();
        program_verb(&env, WIZARD, "test_where_am_i", "return this;");

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(
            &env,
            Some(&auth_token),
            "test_where_am_i",
            Some(ObjectRef::Id(WIZARD)),
            None,
        )
        .expect("call should succeed");

        assert_eq!(
            expect_success(reply).as_object(),
            Some(WIZARD),
            "the verb should have run on the requested object"
        );
    }

    /// Choosing the permissions object is a privilege escalation, so a
    /// non-wizard token may not do it.
    #[test]
    fn authority_principal_is_wizard_only() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_who_am_i", "return player;");

        // Find a player that is not a wizard to mint a token for.
        let non_wizard = non_wizard_player(&env.scheduler_client);
        let auth_token = auth_token_for(&non_wizard);

        let result = call_system_verb(
            &env,
            Some(&auth_token),
            "test_who_am_i",
            None,
            Some(SYSTEM_OBJECT),
        );

        assert!(
            matches!(result, Err(RpcMessageError::PermissionDenied)),
            "a non-wizard should not choose the permissions object, got {result:?}"
        );
    }

    /// A wizard token may set the permissions object.
    #[test]
    fn authority_principal_accepted_from_a_wizard() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_perms", "return task_perms()[1];");

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_perms", None, Some(WIZARD))
            .expect("call should succeed");

        // See `authority_principal_does_not_change_verb_body_permissions`: the
        // principal governs dispatch, not the running activation.
        assert_eq!(expect_success(reply).as_object(), Some(VERB_OWNER));
    }

    /// The authority principal governs the task's initial verb dispatch and
    /// object-reference resolution, not the permissions of the verb body: a MOO
    /// activation runs with the called verb's owner permissions as usual.
    #[test]
    fn authority_principal_does_not_change_verb_body_permissions() {
        let env = setup();
        program_verb(&env, SYSTEM_OBJECT, "test_perms", "return task_perms()[1];");

        let auth_token = auth_token_for(&WIZARD);
        let non_wizard = non_wizard_player(&env.scheduler_client);

        for authority in [None, Some(SYSTEM_OBJECT), Some(non_wizard)] {
            let reply = call_system_verb(&env, Some(&auth_token), "test_perms", None, authority)
                .expect("call should succeed");
            assert_eq!(
                expect_success(reply).as_object(),
                Some(VERB_OWNER),
                "verb body permissions should be the verb owner, not {authority:?}"
            );
        }
    }

    /// A verb without the executable bit is not dispatchable, and the authority
    /// principal does not override that.
    #[test]
    fn authority_principal_does_not_bypass_the_executable_bit() {
        let env = setup();
        eval(
            &env,
            "add_verb(#0, {#2, \"rd\", \"test_noexec\"}, {\"this\", \"none\", \"this\"}); return 1;",
        );
        env.scheduler_client
            .submit_verb_program(
                &WIZARD,
                &WIZARD,
                &ObjectRef::Id(SYSTEM_OBJECT),
                Symbol::mk("test_noexec"),
                vec!["return 1;".to_string()],
            )
            .expect("verb should program");

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(
            &env,
            Some(&auth_token),
            "test_noexec",
            None,
            Some(SYSTEM_OBJECT),
        )
        .expect("the call itself should succeed");

        match reply.reply {
            moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(response) => assert!(
                matches!(
                    response.response,
                    moor_rpc::VerbCallResponseUnion::VerbCallError(_)
                ),
                "a non-executable verb should not dispatch"
            ),
            other => panic!("Expected VerbCallResponse, got {other:?}"),
        }
    }

    /// The point of the exercise: the task runs as a real player without
    /// producing a connection.
    #[test]
    fn no_connection_record_is_created() {
        let env = setup();
        program_verb(
            &env,
            SYSTEM_OBJECT,
            "test_connected",
            "return length(connected_players());",
        );

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_connected", None, None)
            .expect("call should succeed");

        assert_eq!(
            expect_success(reply),
            v_int(0),
            "connected_players() should be empty for a system verb call"
        );
    }

    /// Narrative output is captured and returned rather than published.
    #[test]
    fn narrative_output_is_captured() {
        let env = setup();
        program_verb(
            &env,
            SYSTEM_OBJECT,
            "test_notify",
            "notify(player, \"captured\");\nreturn 1;",
        );

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_notify", None, None)
            .expect("call should succeed");

        let output = match reply.reply {
            moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(response) => {
                match response.response {
                    moor_rpc::VerbCallResponseUnion::VerbCallSuccess(success) => success.output,
                    moor_rpc::VerbCallResponseUnion::VerbCallError(e) => {
                        panic!("Expected success, got {e:?}")
                    }
                }
            }
            other => panic!("Expected VerbCallResponse, got {other:?}"),
        };

        assert_eq!(output.len(), 1, "the notify should have been captured");
        assert!(
            env.transport.get_narrative_events().is_empty(),
            "captured output should not be published to a connection"
        );
    }

    /// A missing verb is reported as an error rather than a panic.
    #[test]
    fn missing_verb_returns_an_error() {
        let env = setup();

        let auth_token = auth_token_for(&WIZARD);
        let reply = call_system_verb(&env, Some(&auth_token), "test_no_such_verb", None, None)
            .expect("the call itself should succeed");

        match reply.reply {
            moor_rpc::DaemonToClientReplyUnion::VerbCallResponse(response) => assert!(
                matches!(
                    response.response,
                    moor_rpc::VerbCallResponseUnion::VerbCallError(_)
                ),
                "a missing verb should produce a VerbCallError"
            ),
            other => panic!("Expected VerbCallResponse, got {other:?}"),
        }
    }

    /// Find a player in the core that does not have the wizard bit set.
    fn non_wizard_player(scheduler_client: &SchedulerClient) -> Obj {
        for id in 3..200 {
            let obj = Obj::mk_id(id);
            let Ok(flags) = scheduler_client.get_object_flags(&obj) else {
                continue;
            };
            let is_user = flags & (1 << ObjFlag::User as u8) != 0;
            let is_wizard = flags & (1 << ObjFlag::Wizard as u8) != 0;
            if is_user && !is_wizard {
                return obj;
            }
        }
        panic!("no non-wizard player found in the test core");
    }
}
