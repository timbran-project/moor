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

//! Integration tests using real WorldState DB
//!
//! These tests verify the integration between RPC components and a real database
//! loaded with JHCore.

#[cfg(test)]
mod tests {
    use std::{
        sync::Arc,
        time::{Duration, Instant},
    };
    use uuid::Uuid;

    use crate::testing::{MockTransport, test_env};
    use moor_common::model::ObjectRef;
    use moor_common::tasks::Event;
    use moor_runtime_api::{
        AuthToken, BatchAction, ClientToken, mk_batch_world_state_msg, mk_command_msg,
        mk_connection_establish_msg, mk_login_command_msg, ws_list_objects,
        ws_request_system_property, ws_resolve_object,
    };
    use moor_schema::rpc as moor_rpc;
    use moor_var::{Obj, SYSTEM_OBJECT};

    /// Wait for an event with content matching the given predicate
    ///
    /// Searches through events for the specified player and calls the predicate on each event.
    /// Returns when the predicate returns true for any event, or panics on timeout.
    fn wait_for_event_content<F>(
        transport: &MockTransport,
        player: Obj,
        predicate: F,
        timeout_secs: u64,
        description: &str,
    ) where
        F: Fn(&Event) -> bool,
    {
        let start_time = Instant::now();
        loop {
            if start_time.elapsed() > Duration::from_secs(timeout_secs) {
                panic!(
                    "No expected {} after {}s",
                    description,
                    start_time.elapsed().as_secs_f32()
                );
            }

            let events = transport.get_narrative_events();
            for (event_player, narrative_event) in &events {
                // Check if this event is for the expected player
                if *event_player != player {
                    continue;
                }

                // Check for traceback
                if matches!(narrative_event.event(), Event::Traceback(_)) {
                    panic!("Received exception during {description}");
                }

                // Use the predicate to check if this is the event we're looking for
                if predicate(&narrative_event.event()) {
                    return;
                }
            }

            // Small sleep to avoid busy polling
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    /// Send a command and wait for output containing the expected text
    #[allow(clippy::too_many_arguments)]
    fn send_command_and_wait_for_output(
        env: &TestEnvironment,
        client_id: Uuid,
        client_token: &ClientToken,
        auth_token: &AuthToken,
        player_obj: Obj,
        command: &str,
        expected_output: &str,
        description: &str,
    ) {
        let message = mk_command_msg(client_token, auth_token, &player_obj, command.to_string());

        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            message,
        );

        assert!(
            result.is_ok(),
            "{command} command should succeed: {result:?}"
        );

        wait_for_event_content(
            &env.transport,
            player_obj,
            |event| {
                if let Event::Notify {
                    value: content,
                    content_type: _,
                    no_flush: _,
                    no_newline: _,
                    metadata: _,
                } = event
                {
                    if let Some(str) = content.as_string() {
                        str.contains(expected_output)
                    } else {
                        false
                    }
                } else {
                    false
                }
            },
            5,
            description,
        );
    }

    type TestEnvironment = test_env::TestEnvironment<MockTransport>;

    fn wait_for_scheduler_ready(scheduler_client: &moor_kernel::SchedulerClient) {
        test_env::wait_for_scheduler_ready(scheduler_client);
    }

    fn setup_test_environment_with_checkpoint_output() -> TestEnvironment {
        test_env::setup_test_environment_with_checkpoint_output(Arc::new(MockTransport::new()))
    }

    fn setup_test_environment_with_real_scheduler() -> TestEnvironment {
        setup_test_environment_with_checkpoint_output()
    }

    #[test]
    fn test_real_scheduler_startup() {
        let mut env = setup_test_environment_with_real_scheduler();
        env._temp_output_dir = None; // Don't need output dir for this test
        env.output_dir_path = None;

        // Wait for scheduler to be ready by attempting a simple operation
        wait_for_scheduler_ready(&env.scheduler_client);
    }

    #[test]
    fn test_connection_establishment_with_real_db() {
        let mut env = setup_test_environment_with_real_scheduler();
        env._temp_output_dir = None; // Don't need output dir for this test
        env.output_dir_path = None;
        wait_for_scheduler_ready(&env.scheduler_client);

        let client_id = Uuid::new_v4();

        // Test establishing a connection
        let establish_message = mk_connection_establish_msg(
            "127.0.0.1:8080".to_string(),
            7777,
            8080,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            establish_message,
        );

        assert!(
            establish_result.is_ok(),
            "Connection establishment should succeed"
        );

        let (client_token, connection_obj) = match establish_result.unwrap().reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => (
                ClientToken(new_conn.client_token.token.clone()),
                match &new_conn.connection_obj.obj {
                    moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                    _ => panic!("Unexpected obj variant"),
                },
            ),
            other => panic!("Expected NewConnection, got {other:?}"),
        };

        assert!(
            !client_token.0.is_empty(),
            "Should receive a valid client token"
        );
        assert!(
            connection_obj.id().0 < 0,
            "Should receive a valid connection object"
        );

        // Verify connection is tracked
        let connections = env.message_handler.get_connections();
        assert!(
            connections.contains(&connection_obj),
            "Connection should be tracked"
        );
    }

    #[test]
    fn test_wizard_login_with_real_scheduler() {
        let mut env = setup_test_environment_with_real_scheduler();
        env._temp_output_dir = None; // Don't need output dir for this test
        env.output_dir_path = None;
        wait_for_scheduler_ready(&env.scheduler_client);

        let client_id = Uuid::new_v4();

        // First establish connection
        let establish_message = mk_connection_establish_msg(
            "127.0.0.1:8080".to_string(),
            7777,
            8080,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            establish_message,
        );

        let (client_token, _connection_obj) = match establish_result.unwrap().reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => (
                ClientToken(new_conn.client_token.token.clone()),
                match &new_conn.connection_obj.obj {
                    moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                    _ => panic!("Unexpected obj variant"),
                },
            ),
            other => panic!("Expected NewConnection, got {other:?}"),
        };

        // Follow the proper telnet-host sequence:
        // 1. First call welcome message (empty args, do_attach: false)
        // 2. Then actual login (with args, do_attach: true)

        // Step 1: Welcome message call
        let welcome_message =
            mk_login_command_msg(&client_token, &SYSTEM_OBJECT, vec![], false, None, None);

        let welcome_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            welcome_message,
        );

        // Welcome call should succeed (it just triggers welcome message)
        assert!(
            welcome_result.is_ok(),
            "Welcome message call should succeed: {welcome_result:?}"
        );

        // Wait for welcome message to be processed - check transport for narrative events
        // since EventLog skips events for negative connection objects
        assert!(
            env.transport.wait_for_narrative_events(1, 2000),
            "Should receive welcome message events within 2 seconds"
        );

        // Step 2: Actual login as wizard
        let login_message = mk_login_command_msg(
            &client_token,
            &SYSTEM_OBJECT,
            vec!["connect".to_string(), "wizard".to_string()], // Same as user typing "connect wizard"
            true,
            None,
            None,
        );

        let login_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            login_message,
        );

        // Wait for login task to be processed and events to be generated
        let _login_success = env.transport.wait_for_condition(
            |transport| {
                // Look for completion events or specific narrative events indicating login success
                let narrative_events = transport.get_narrative_events();
                let client_events = transport.get_client_events();

                // Login succeeded if we got any narrative events OR client events indicating completion
                !narrative_events.is_empty() || !client_events.is_empty()
            },
            5000,
        );

        // Collect debugging information if login fails
        if login_result.is_err() {
            // Get all events from MockEventLog
            let all_events = env.event_log.get_all_events();
            let narrative_events = env.transport.get_narrative_events();
            let client_replies = env.transport.get_client_replies();
            let client_events = env.transport.get_client_events();
            let host_events = env.transport.get_host_events();

            let recent_events = env.event_log.get_all_events();

            panic!(
                "Login failed: {:?}\n\nMockEventLog all events ({} total):\n{:#?}\n\nMockEventLog recent events for SYSTEM_OBJECT ({} total):\n{:#?}\n\nMockTransport narrative events ({} total):\n{:#?}\n\nMockTransport client events ({} total):\n{:#?}\n\nMockTransport host events ({} total):\n{:#?}\n\nMockTransport client replies ({} total):\n{:#?}",
                login_result,
                all_events.len(),
                all_events,
                recent_events.len(),
                recent_events,
                narrative_events.len(),
                narrative_events,
                client_events.len(),
                client_events,
                host_events.len(),
                host_events,
                client_replies.len(),
                client_replies
            );
        }

        // Should be LoginResult with success=true, ConnectType::Connected, and objid 2
        let login_result = login_result.expect("Bad login result");
        let moor_rpc::DaemonToClientReplyUnion::LoginResult(login_res) = login_result.reply else {
            // Get debugging information for unexpected results too
            let all_events = env.event_log.get_all_events();
            let narrative_events = env.transport.get_narrative_events();
            let client_replies = env.transport.get_client_replies();

            panic!(
                "Unexpected login result: {:?}\n\nMockEventLog events ({} total):\n{:#?}\n\nMockTransport narrative events ({} total):\n{:#?}\n\nMockTransport client replies ({} total):\n{:#?}",
                login_result,
                all_events.len(),
                all_events,
                narrative_events.len(),
                narrative_events,
                client_replies.len(),
                client_replies
            );
        };

        assert!(login_res.success, "Login should be successful");
        let auth_token = login_res
            .auth_token
            .as_ref()
            .expect("Should have auth token");
        let auth_token = AuthToken(auth_token.token.clone());
        let connect_type = login_res.connect_type;
        let player_obj = login_res
            .player
            .as_ref()
            .expect("Should have player object");
        let player_obj = match &player_obj.obj {
            moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
            _ => panic!("Unexpected obj variant"),
        };

        assert_eq!(
            connect_type,
            moor_rpc::ConnectType::Connected,
            "Expected connected type"
        );
        assert!(player_obj.id().0 > 0, "Expected valid player object ID");

        // Verify player object is tracked in connections
        let connections = env.message_handler.get_connections();
        assert!(
            connections.contains(&player_obj),
            "Player object should be tracked in connections"
        );

        // Player should be #2
        assert_eq!(player_obj, Obj::mk_id(2));

        // Now we should keep polling received events until we see at lease part of:
        // *** Connected ***
        // Before going anywhere, you might want to describe yourself; type `help describe' for information.
        // #$#mcp version: 2.1 to: 2.1
        // The First Room
        // This is all there is right now.
        // Your previous connection was before we started keeping track.
        wait_for_event_content(
            &env.transport,
            player_obj,
            |event| {
                if let Event::Notify {
                    value: content,
                    content_type: _,
                    no_flush: _,
                    no_newline: _,
                    metadata: _,
                } = event
                {
                    if let Some(str) = content.as_string() {
                        str == "This is all there is right now."
                    } else {
                        false
                    }
                } else {
                    false
                }
            },
            5,
            "connection events with room description",
        );

        // Send "@who" command to verify the logged-in player appears in the listing
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "@who",
            "Wizard",
            "@who command output with wizard player listing",
        );

        // Send @create $thing named "my thing" command
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "@create $thing named \"my thing\"",
            "You now have my thing with object number",
            "@create command output confirming object creation",
        );

        // Send "drop my thing" command
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "drop my thing",
            "You drop the my thing",
            "drop command output",
        );

        // Send @describe my thing command
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "@describe my thing as \"A thing that's thingly.\"",
            "Description set",
            "@describe command output",
        );

        // Send @audit command to verify object ownership
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "@audit",
            "my thing",
            "@audit command output showing owned objects",
        );

        // Send MOO expression to verify max_object().name
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            ";max_object().name == \"my thing\"",
            "=> 1",
            "MOO expression verification",
        );

        // Send say command
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            "say Why hello there...",
            "You say, \"Why hello there...\"",
            "say command output",
        );

        // Verify no tracebacks in the transport events (which are unencrypted)
        let events = env.transport.get_narrative_events();
        for (_player, narrative_event) in events {
            if matches!(narrative_event.event(), Event::Traceback(_)) {
                panic!("Unexpected traceback in events");
            }
        }
    }

    #[test]
    fn test_checkpoint_functionality() {
        let env = setup_test_environment_with_checkpoint_output();
        wait_for_scheduler_ready(&env.scheduler_client);

        // Step 1: Verify scheduler is running and responsive
        assert!(
            env.scheduler_client.check_status().is_ok(),
            "Scheduler should be responsive before checkpoint"
        );

        // Step 2: Request a blocking checkpoint from the scheduler
        let checkpoint_result = env.scheduler_client.request_checkpoint_blocking();

        // Step 3: Verify checkpoint completed successfully
        assert!(
            checkpoint_result.is_ok(),
            "Blocking checkpoint should succeed: {checkpoint_result:?}"
        );

        // Step 4: Verify scheduler is still responsive after checkpoint
        assert!(
            env.scheduler_client.check_status().is_ok(),
            "Scheduler should remain responsive after checkpoint"
        );

        // Step 5: Verify that the database is still functional by establishing a connection
        let client_id = Uuid::new_v4();
        let establish_message = mk_connection_establish_msg(
            "127.0.0.1:8080".to_string(),
            7777,
            8080,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            establish_message,
        );

        assert!(
            establish_result.is_ok(),
            "Database operations should work after checkpoint: {establish_result:?}"
        );

        // Step 6: Verify the connection was established properly
        match establish_result.unwrap().reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => {
                let token = ClientToken(new_conn.client_token.token.clone());
                let obj = match &new_conn.connection_obj.obj {
                    moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                    _ => panic!("Unexpected obj variant"),
                };
                assert!(!token.0.is_empty(), "Should receive valid client token");
                assert!(obj.id().0 < 0, "Should receive valid connection object");
            }
            other => panic!("Expected NewConnection, got {other:?}"),
        }

        let output_dir = env.output_dir_path.as_ref().unwrap();
        // Since we used blocking checkpoint, the file should already exist
        let entries =
            std::fs::read_dir(output_dir).expect("Should be able to read output directory");

        // Checkpoints are always written as objdef directories with .moo extension
        let mut checkpoint_files: Vec<_> = entries
            .flatten()
            .filter(|entry| {
                if let Some(filename) = entry.file_name().to_str() {
                    filename.starts_with("checkpoint-")
                        && filename.ends_with(".moo")
                        && !filename.contains(".in-progress")
                } else {
                    false
                }
            })
            .collect();

        assert!(
            !checkpoint_files.is_empty(),
            "Checkpoint file should exist after blocking checkpoint in directory: {}",
            output_dir.display()
        );

        // Get the most recent file (there should be exactly one from our checkpoint)
        checkpoint_files.sort_by_key(|entry| entry.metadata().unwrap().modified().unwrap());
        let checkpoint_path = checkpoint_files.last().unwrap().path();

        // Verify the checkpoint directory has content (JHCore should produce substantial data)
        // For objdef format, the checkpoint is a directory containing .moo files
        assert!(
            checkpoint_path.is_dir(),
            "Checkpoint should be a directory: {}",
            checkpoint_path.display()
        );

        let dir_entries: Vec<_> = std::fs::read_dir(&checkpoint_path)
            .expect("Should be able to read checkpoint directory")
            .flatten()
            .collect();
        assert!(
            !dir_entries.is_empty(),
            "Checkpoint directory should contain files: {}",
            checkpoint_path.display()
        );

        // Step 8: Verify there are no errors in the transport events (which are unencrypted)
        let events = env.transport.get_narrative_events();
        for (_player, narrative_event) in events {
            if matches!(narrative_event.event(), Event::Traceback(_)) {
                panic!("Unexpected traceback after checkpoint");
            }
        }
    }

    #[test]
    fn test_gc_collect_builtin() {
        let mut env = setup_test_environment_with_real_scheduler();
        env._temp_output_dir = None; // Don't need output dir for this test
        env.output_dir_path = None;
        wait_for_scheduler_ready(&env.scheduler_client);

        let client_id = Uuid::new_v4();

        // First establish connection
        let establish_message = mk_connection_establish_msg(
            "127.0.0.1:8080".to_string(),
            7777,
            8080,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            establish_message,
        );

        let (client_token, _connection_obj) = match establish_result.unwrap().reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => (
                ClientToken(new_conn.client_token.token.clone()),
                match &new_conn.connection_obj.obj {
                    moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                    _ => panic!("Unexpected obj variant"),
                },
            ),
            other => panic!("Expected NewConnection, got {other:?}"),
        };

        // Welcome message call
        let welcome_message =
            mk_login_command_msg(&client_token, &SYSTEM_OBJECT, vec![], false, None, None);

        let _welcome_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            welcome_message,
        );

        // Wait for welcome message
        assert!(
            env.transport.wait_for_narrative_events(1, 2000),
            "Should receive welcome message events within 2 seconds"
        );

        // Login as wizard
        let login_message = mk_login_command_msg(
            &client_token,
            &SYSTEM_OBJECT,
            vec!["connect".to_string(), "wizard".to_string()],
            true,
            None,
            None,
        );

        let login_result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            client_id,
            login_message,
        );

        // Wait for login task completion
        let _login_success = env.transport.wait_for_condition(
            |transport| {
                let narrative_events = transport.get_narrative_events();
                let client_events = transport.get_client_events();
                !narrative_events.is_empty() || !client_events.is_empty()
            },
            5000,
        );

        let moor_rpc::DaemonToClientReplyUnion::LoginResult(login_res) =
            login_result.expect("Login should succeed").reply
        else {
            panic!("Expected successful login result");
        };

        assert!(login_res.success, "Login should be successful");
        let auth_token = login_res
            .auth_token
            .as_ref()
            .expect("Should have auth token");
        let auth_token = AuthToken(auth_token.token.clone());
        let connect_type = login_res.connect_type;
        let player_obj = login_res
            .player
            .as_ref()
            .expect("Should have player object");
        let player_obj = match &player_obj.obj {
            moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
            _ => panic!("Unexpected obj variant"),
        };

        assert_eq!(connect_type, moor_rpc::ConnectType::Connected);
        assert_eq!(player_obj, Obj::mk_id(2));

        // Wait for connection events
        wait_for_event_content(
            &env.transport,
            player_obj,
            |event| {
                if let Event::Notify {
                    value: content,
                    content_type: _,
                    no_flush: _,
                    no_newline: _,
                    metadata: _,
                } = event
                {
                    if let Some(str) = content.as_string() {
                        str == "This is all there is right now."
                    } else {
                        false
                    }
                } else {
                    false
                }
            },
            5,
            "connection events with room description",
        );

        // Get initial GC stats before running collection
        let initial_stats = env
            .scheduler_client
            .get_gc_stats()
            .expect("Should be able to get GC stats");
        let initial_count = initial_stats.cycle_count;

        // Test gc_collect() builtin - should trigger GC cycle and return nil
        send_command_and_wait_for_output(
            &env,
            client_id,
            &client_token,
            &auth_token,
            player_obj,
            ";gc_collect()",
            "=> 0", // Should return nil (0)
            "gc_collect() builtin execution",
        );

        // Verify scheduler is still responsive after GC
        assert!(
            env.scheduler_client.check_status().is_ok(),
            "Scheduler should remain responsive after GC"
        );

        // Wait for the GC cycle to complete (it runs asynchronously in the timer thread)
        let gc_start = Instant::now();
        loop {
            let stats = env
                .scheduler_client
                .get_gc_stats()
                .expect("Should be able to get GC stats after GC");
            if stats.cycle_count > initial_count {
                break;
            }
            if gc_start.elapsed() > Duration::from_secs(10) {
                panic!(
                    "GC cycle count should have incremented: was {}, now {}",
                    initial_count, stats.cycle_count
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        // Test that non-wizard cannot call gc_collect()
        // First create a regular player by connecting as a different user
        let non_wizard_client_id = Uuid::new_v4();

        let establish_message_2 = mk_connection_establish_msg(
            "127.0.0.1:8081".to_string(),
            7777,
            8081,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result_2 = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            non_wizard_client_id,
            establish_message_2,
        );

        let (client_token_2, _connection_obj_2) = match establish_result_2.unwrap().reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => (
                ClientToken(new_conn.client_token.token.clone()),
                match &new_conn.connection_obj.obj {
                    moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                    _ => panic!("Unexpected obj variant"),
                },
            ),
            other => panic!("Expected NewConnection, got {other:?}"),
        };

        // For non-wizard test, we'll connect as a guest (which should be non-wizard)
        let welcome_message_2 =
            mk_login_command_msg(&client_token_2, &SYSTEM_OBJECT, vec![], false, None, None);

        let _welcome_result_2 = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            non_wizard_client_id,
            welcome_message_2,
        );

        // Try to connect as guest
        let login_message_2 = mk_login_command_msg(
            &client_token_2,
            &SYSTEM_OBJECT,
            vec!["connect".to_string(), "guest".to_string()],
            true,
            None,
            None,
        );

        let login_result_2 = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            non_wizard_client_id,
            login_message_2,
        );

        // If guest login succeeds, test that gc_collect() fails with permission error
        if let Ok(reply) = login_result_2
            && let moor_rpc::DaemonToClientReplyUnion::LoginResult(login_res) = reply.reply
        {
            if !login_res.success {
                return;
            }
            let auth_token_2 = login_res
                .auth_token
                .as_ref()
                .expect("Should have auth token");
            let auth_token_2 = AuthToken(auth_token_2.token.clone());
            let player_obj_2 = login_res
                .player
                .as_ref()
                .expect("Should have player object");
            let player_obj_2 = match &player_obj_2.obj {
                moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
                _ => panic!("Unexpected obj variant"),
            };
            // Wait for guest connection to complete
            std::thread::sleep(Duration::from_millis(500));

            // Try gc_collect() as non-wizard - should get permission error
            let message_2 = mk_command_msg(
                &client_token_2,
                &auth_token_2,
                &player_obj_2,
                ";gc_collect()".to_string(),
            );

            let _result_2 = env.transport.process_client_message(
                env.message_handler.as_ref(),
                env.scheduler_client.clone(),
                non_wizard_client_id,
                message_2,
            );

            // Wait for and verify permission error
            wait_for_event_content(
                &env.transport,
                player_obj_2,
                |event| {
                    if let Event::Notify {
                        value: content,
                        content_type: _,
                        no_flush: _,
                        no_newline: _,
                        metadata: _,
                    } = event
                    {
                        if let Some(str) = content.as_string() {
                            str.contains("Permission denied") || str.contains("E_PERM")
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                },
                5,
                "permission error for non-wizard gc_collect() call",
            );
        }

        // Test direct GC calls via scheduler client to verify counter increments properly
        let current_count = env
            .scheduler_client
            .get_gc_stats()
            .expect("Should be able to get GC stats")
            .cycle_count;

        // Request another GC cycle directly via scheduler client
        env.scheduler_client
            .request_gc()
            .expect("Direct GC request should succeed");

        // Wait for GC cycle to complete
        let gc_start = Instant::now();
        loop {
            let stats = env
                .scheduler_client
                .get_gc_stats()
                .expect("Should be able to get GC stats after direct GC");
            if stats.cycle_count > current_count {
                break;
            }
            if gc_start.elapsed() > Duration::from_secs(10) {
                panic!(
                    "GC cycle count should have incremented after direct GC request: was {}, now {}",
                    current_count, stats.cycle_count
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        let count_after_direct = env
            .scheduler_client
            .get_gc_stats()
            .expect("stats")
            .cycle_count;

        // Request one more GC to verify it keeps working
        env.scheduler_client
            .request_gc()
            .expect("Second direct GC request should succeed");

        // Wait for second GC cycle
        let gc_start = Instant::now();
        loop {
            let stats = env
                .scheduler_client
                .get_gc_stats()
                .expect("Should be able to get final GC stats");
            if stats.cycle_count > count_after_direct {
                break;
            }
            if gc_start.elapsed() > Duration::from_secs(10) {
                panic!(
                    "GC cycle count should have incremented after second GC request: was {}, now {}",
                    count_after_direct, stats.cycle_count
                );
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        // Verify no unexpected tracebacks in the transport events (which are unencrypted)
        let events = env.transport.get_narrative_events();
        for (_player, narrative_event) in events {
            if matches!(narrative_event.event(), Event::Traceback(_)) {
                // For now, just ignore tracebacks - proper handling would require
                // inspecting traceback details to filter out expected E_PERM errors
                // TODO: Add proper traceback inspection and E_PERM filtering
            }
        }
    }

    /// Helper: establish connection, login as wizard, return (client_id, client_token, auth_token, player_obj).
    fn login_as_wizard(env: &TestEnvironment) -> (Uuid, ClientToken, AuthToken, Obj) {
        let client_id = Uuid::new_v4();

        let establish_message = mk_connection_establish_msg(
            "127.0.0.1:8080".to_string(),
            7777,
            8080,
            Some(vec![moor_rpc::Symbol {
                value: "text/plain".to_string(),
            }]),
            None,
        );

        let establish_result = env
            .transport
            .process_client_message(
                env.message_handler.as_ref(),
                env.scheduler_client.clone(),
                client_id,
                establish_message,
            )
            .expect("Connection establishment should succeed");

        let client_token = match establish_result.reply {
            moor_rpc::DaemonToClientReplyUnion::NewConnection(new_conn) => {
                ClientToken(new_conn.client_token.token.clone())
            }
            other => panic!("Expected NewConnection, got {other:?}"),
        };

        // Welcome message
        let welcome_message =
            mk_login_command_msg(&client_token, &SYSTEM_OBJECT, vec![], false, None, None);
        env.transport
            .process_client_message(
                env.message_handler.as_ref(),
                env.scheduler_client.clone(),
                client_id,
                welcome_message,
            )
            .expect("Welcome message should succeed");
        assert!(
            env.transport.wait_for_narrative_events(1, 2000),
            "Should receive welcome message events"
        );

        // Login as wizard
        let login_message = mk_login_command_msg(
            &client_token,
            &SYSTEM_OBJECT,
            vec!["connect".to_string(), "wizard".to_string()],
            true,
            None,
            None,
        );

        let login_result = env
            .transport
            .process_client_message(
                env.message_handler.as_ref(),
                env.scheduler_client.clone(),
                client_id,
                login_message,
            )
            .expect("Login should succeed");

        let moor_rpc::DaemonToClientReplyUnion::LoginResult(login_res) = login_result.reply else {
            panic!("Expected LoginResult");
        };
        assert!(login_res.success, "Login should be successful");

        let auth_token = AuthToken(
            login_res
                .auth_token
                .as_ref()
                .expect("Should have auth token")
                .token
                .clone(),
        );
        let player_obj = match &login_res.player.as_ref().unwrap().obj {
            moor_rpc::ObjUnion::ObjId(obj_id) => Obj::mk_id(obj_id.id),
            _ => panic!("Unexpected obj variant"),
        };

        // Wait for connection events to settle
        wait_for_event_content(
            &env.transport,
            player_obj,
            |event| {
                if let Event::Notify { value: content, .. } = event {
                    content
                        .as_string()
                        .is_some_and(|s| s == "This is all there is right now.")
                } else {
                    false
                }
            },
            5,
            "connection events",
        );

        (client_id, client_token, auth_token, player_obj)
    }

    #[test]
    fn test_batch_world_state_empty() {
        let env = setup_test_environment_with_real_scheduler();
        wait_for_scheduler_ready(&env.scheduler_client);
        let (_client_id, _client_token, auth_token, _player_obj) = login_as_wizard(&env);

        // Submit an empty batch
        let message = mk_batch_world_state_msg(&auth_token, vec![], false);
        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        );

        let reply = result.expect("Empty batch should succeed");
        let moor_rpc::DaemonToClientReplyUnion::BatchWorldStateReply(batch_reply) = reply.reply
        else {
            panic!("Expected BatchWorldStateReply, got {:?}", reply.reply);
        };
        assert!(
            batch_reply.results.is_empty(),
            "Empty batch should return empty results"
        );
    }

    #[test]
    fn test_batch_world_state_read_system_property() {
        let env = setup_test_environment_with_real_scheduler();
        wait_for_scheduler_ready(&env.scheduler_client);
        let (_client_id, _client_token, auth_token, _player_obj) = login_as_wizard(&env);

        // Read system_object.name via batch
        let actions = vec![BatchAction {
            id: "req-1".to_string(),
            action: ws_request_system_property(
                &ObjectRef::Id(SYSTEM_OBJECT),
                &moor_var::Symbol::mk("name"),
            ),
        }];

        let message = mk_batch_world_state_msg(&auth_token, actions, false);
        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        );

        let reply = result.expect("Batch system property read should succeed");
        let moor_rpc::DaemonToClientReplyUnion::BatchWorldStateReply(batch_reply) = reply.reply
        else {
            panic!("Expected BatchWorldStateReply");
        };
        assert_eq!(batch_reply.results.len(), 1);
        assert_eq!(batch_reply.results[0].id, "req-1");
        // The result should be a WsSystemPropertyResult
        assert!(
            matches!(
                batch_reply.results[0].result,
                moor_rpc::WorldStateResultUnion::WsSystemPropertyResult(_)
            ),
            "Expected WsSystemPropertyResult, got {:?}",
            batch_reply.results[0].result
        );
    }

    #[test]
    fn test_batch_world_state_resolve_object() {
        let env = setup_test_environment_with_real_scheduler();
        wait_for_scheduler_ready(&env.scheduler_client);
        let (_client_id, _client_token, auth_token, _player_obj) = login_as_wizard(&env);

        // Resolve $room (should be a well-known object in JHCore)
        let actions = vec![BatchAction {
            id: "resolve-1".to_string(),
            action: ws_resolve_object(&ObjectRef::SysObj(vec![moor_var::Symbol::mk("room")])),
        }];

        let message = mk_batch_world_state_msg(&auth_token, actions, false);
        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        );

        let reply = result.expect("Batch resolve should succeed");
        let moor_rpc::DaemonToClientReplyUnion::BatchWorldStateReply(batch_reply) = reply.reply
        else {
            panic!("Expected BatchWorldStateReply");
        };
        assert_eq!(batch_reply.results.len(), 1);
        assert_eq!(batch_reply.results[0].id, "resolve-1");
        assert!(
            matches!(
                batch_reply.results[0].result,
                moor_rpc::WorldStateResultUnion::WsResolveResult(_)
            ),
            "Expected WsResolveResult, got {:?}",
            batch_reply.results[0].result
        );
    }

    #[test]
    fn test_batch_world_state_multiple_actions() {
        let env = setup_test_environment_with_real_scheduler();
        wait_for_scheduler_ready(&env.scheduler_client);
        let (_client_id, _client_token, auth_token, _player_obj) = login_as_wizard(&env);

        // Submit multiple heterogeneous actions in one batch
        let actions = vec![
            BatchAction {
                id: "name".to_string(),
                action: ws_request_system_property(
                    &ObjectRef::Id(SYSTEM_OBJECT),
                    &moor_var::Symbol::mk("name"),
                ),
            },
            BatchAction {
                id: "resolve".to_string(),
                action: ws_resolve_object(&ObjectRef::SysObj(vec![moor_var::Symbol::mk("room")])),
            },
            BatchAction {
                id: "list".to_string(),
                action: ws_list_objects(),
            },
        ];

        let message = mk_batch_world_state_msg(&auth_token, actions, false);
        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        );

        let reply = result.expect("Multi-action batch should succeed");
        let moor_rpc::DaemonToClientReplyUnion::BatchWorldStateReply(batch_reply) = reply.reply
        else {
            panic!("Expected BatchWorldStateReply");
        };

        assert_eq!(batch_reply.results.len(), 3);
        // Verify correlation IDs are preserved in order
        assert_eq!(batch_reply.results[0].id, "name");
        assert_eq!(batch_reply.results[1].id, "resolve");
        assert_eq!(batch_reply.results[2].id, "list");

        // Verify each result has the expected type
        assert!(matches!(
            batch_reply.results[0].result,
            moor_rpc::WorldStateResultUnion::WsSystemPropertyResult(_)
        ));
        assert!(matches!(
            batch_reply.results[1].result,
            moor_rpc::WorldStateResultUnion::WsResolveResult(_)
        ));
        assert!(matches!(
            batch_reply.results[2].result,
            moor_rpc::WorldStateResultUnion::WsObjectsListResult(_)
        ));
    }

    #[test]
    fn test_batch_world_state_rollback_mode() {
        let env = setup_test_environment_with_real_scheduler();
        wait_for_scheduler_ready(&env.scheduler_client);
        let (_client_id, _client_token, auth_token, _player_obj) = login_as_wizard(&env);

        // Read-only batch with rollback=true should still succeed
        let actions = vec![BatchAction {
            id: "sys-name".to_string(),
            action: ws_request_system_property(
                &ObjectRef::Id(SYSTEM_OBJECT),
                &moor_var::Symbol::mk("name"),
            ),
        }];

        let message = mk_batch_world_state_msg(&auth_token, actions, true);
        let result = env.transport.process_client_message(
            env.message_handler.as_ref(),
            env.scheduler_client.clone(),
            Uuid::new_v4(),
            message,
        );

        let reply = result.expect("Rollback batch should succeed");
        let moor_rpc::DaemonToClientReplyUnion::BatchWorldStateReply(batch_reply) = reply.reply
        else {
            panic!("Expected BatchWorldStateReply");
        };
        assert_eq!(batch_reply.results.len(), 1);
        assert!(matches!(
            batch_reply.results[0].result,
            moor_rpc::WorldStateResultUnion::WsSystemPropertyResult(_)
        ));
    }
}
