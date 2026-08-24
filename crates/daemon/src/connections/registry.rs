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

use std::{collections::HashMap, sync::Arc, time::SystemTime};

use uuid::Uuid;

use crate::connections::fjall_registry::FjallConnectionRegistry;
use eyre::Report as Error;
use moor_common::tasks::{ConnectionDetails, SessionError};
use moor_runtime_api::RpcMessageError;
use moor_var::{Obj, Symbol, Var};
use std::path::Path;

/// Parameters for creating a new connection
#[derive(Debug)]
pub struct NewConnectionParams {
    pub client_id: Uuid,
    pub hostname: String,
    pub local_port: u16,
    pub remote_port: u16,
    pub player: Option<Obj>,
    pub acceptable_content_types: Option<Vec<Symbol>>,
    pub connection_attributes: Option<HashMap<Symbol, Var>>,
}

/// Read-only connection state shared with runtime sessions.
pub trait ConnectionStateSource: Send + Sync {
    /// Return connected players and, when requested, connection objects.
    fn connected_players(&self, include_all: bool) -> Vec<Obj>;

    fn connection_name(&self, player: Obj) -> Result<String, SessionError>;

    fn connected_seconds(&self, player: Obj) -> Result<f64, SessionError>;

    fn idle_seconds(&self, player: Obj) -> Result<f64, SessionError>;

    fn connections_for(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<Obj>, SessionError>;

    fn connection_details(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError>;

    fn connection_attributes(&self, obj: Obj) -> Result<Var, SessionError>;
}

pub trait ConnectionRegistry: ConnectionStateSource {
    /// Associate the given player object with the connection object.
    /// This is used when a player logs in.
    /// The connection object remains associated with the client.
    fn associate_player_object(
        &self,
        connection_obj: Obj,
        player_obj: Obj,
    ) -> Result<(), eyre::Error>;

    /// Switch every client attached to a connection object to a new player.
    /// Returns the client IDs that must be notified after the registry update commits.
    fn switch_player_for_connection(
        &self,
        connection_obj: Obj,
        new_player: Obj,
        preserve_history: bool,
    ) -> Result<Vec<Uuid>, eyre::Error>;

    /// Create a new connection object for the given client.
    fn new_connection(&self, params: NewConnectionParams) -> Result<Obj, RpcMessageError>;

    /// Record activity for the given client.
    fn record_client_activity(&self, client_id: Uuid, connobj: Obj) -> Result<(), eyre::Error>;

    /// Update the last ping time for a client / connection.
    fn notify_is_alive(&self, client_id: Uuid, connection: Obj) -> Result<(), eyre::Error>;

    /// Prune any connections that have not been active for longer than the required duration.
    fn ping_check(&self);

    fn last_activity_for(&self, connection: Obj) -> Result<SystemTime, SessionError>;

    fn connection_name_for(&self, player: Obj) -> Result<String, SessionError>;

    fn connected_seconds_for(&self, player: Obj) -> Result<f64, SessionError>;

    fn client_ids_for(&self, player: Obj) -> Result<Vec<Uuid>, SessionError>;

    /// Return all connection objects (player or not)
    fn connections(&self) -> Vec<Obj>;

    /// Retrieve the connection object for the given client.
    fn connection_object_for_client(&self, client_id: Uuid) -> Option<Obj>;

    /// Retrieve the player object for the given client (if logged in).
    fn player_object_for_client(&self, client_id: Uuid) -> Option<Obj>;

    /// Retrieve the player whose persistent history owns events from this client.
    fn history_object_for_client(&self, client_id: Uuid) -> Option<Obj>;

    /// Remove the given client from the connection database.
    fn remove_client_connection(&self, client_id: Uuid) -> Result<(), eyre::Error>;

    /// Get the acceptable content types for a connection.
    fn acceptable_content_types_for(&self, connection: Obj) -> Result<Vec<Symbol>, SessionError>;

    /// Set a client attribute (key-value pair) for a client connection.
    /// If value is None, the attribute is removed.
    fn set_client_attribute(
        &self,
        client_id: Uuid,
        key: Symbol,
        value: Option<Var>,
    ) -> Result<(), RpcMessageError>;

    /// Get client attributes for the given object.
    /// If obj is a player object (positive id): returns attributes from first connection
    /// If obj is a connection object (negative id): returns attributes for that connection
    fn get_client_attributes(&self, obj: Obj) -> Result<HashMap<Symbol, Var>, SessionError>;

    /// Perform cleanup operations + maybe-database flush to encourage persistence.
    fn flush(&self);
}

/// Factory for creating connections database instances
pub struct ConnectionRegistryFactory;

impl ConnectionRegistryFactory {
    /// Create in-memory only database (useful for testing)
    pub fn in_memory_only() -> Result<Arc<dyn ConnectionRegistry>, Error> {
        let db = FjallConnectionRegistry::open(None)?;
        Ok(Arc::new(db))
    }

    /// Create database with Fjall persistence
    pub fn with_fjall_persistence<P: AsRef<Path>>(
        path: Option<P>,
    ) -> Result<Arc<dyn ConnectionRegistry>, Error> {
        let path = path.as_ref().map(|p| p.as_ref());
        let db = FjallConnectionRegistry::open(path)?;
        Ok(Arc::new(db))
    }
}

#[cfg(test)]
mod tests {
    use crate::connections::{NewConnectionParams, registry::ConnectionRegistryFactory};
    use uuid::Uuid;

    #[test]
    fn test_in_memory_only_factory() {
        let db = ConnectionRegistryFactory::in_memory_only().unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "test.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );
        assert_eq!(db.player_object_for_client(client_id), None);
        assert_eq!(db.connections(), vec![connection_obj]);
        assert_eq!(db.connected_players(false), vec![]);
        assert_eq!(db.connected_players(true), vec![connection_obj]);
    }

    #[test]
    fn test_fjall_persistence_factory() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db = ConnectionRegistryFactory::with_fjall_persistence(Some(temp_dir.path())).unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "persistent.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );
        assert_eq!(db.player_object_for_client(client_id), None);
        assert_eq!(db.connections(), vec![connection_obj]);
    }

    #[test]
    fn test_configuration_compatibility() {
        // All implementations should behave identically for basic operations
        let configs = vec![
            ConnectionRegistryFactory::in_memory_only().unwrap(),
            ConnectionRegistryFactory::with_fjall_persistence(None::<&str>).unwrap(),
        ];

        for db in configs {
            let client_id = Uuid::new_v4();
            let connection_obj = db
                .new_connection(NewConnectionParams {
                    client_id,
                    hostname: "compat.test".to_string(),
                    local_port: 7777,
                    remote_port: 12345,
                    player: None,
                    acceptable_content_types: None,
                    connection_attributes: None,
                })
                .unwrap();

            // Basic operations should work identically
            assert_eq!(
                db.connection_object_for_client(client_id),
                Some(connection_obj)
            );
            assert_eq!(db.player_object_for_client(client_id), None);
            assert_eq!(db.client_ids_for(connection_obj).unwrap(), vec![client_id]);
            assert_eq!(db.connections(), vec![connection_obj]);

            // Activity tracking
            db.record_client_activity(client_id, connection_obj)
                .unwrap();
            db.notify_is_alive(client_id, connection_obj).unwrap();
            assert!(db.last_activity_for(connection_obj).is_ok());

            // Cleanup
            db.remove_client_connection(client_id).unwrap();
            assert_eq!(db.connections(), vec![]);
        }
    }

    #[test]
    fn test_connection_player_association() {
        let db = ConnectionRegistryFactory::in_memory_only().unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "test.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Initially no player associated
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );
        assert_eq!(db.player_object_for_client(client_id), None);

        // Associate a player object
        use moor_var::Obj;
        let player_obj = Obj::mk_id(100);
        db.associate_player_object(connection_obj, player_obj)
            .unwrap();

        // Now should have both connection and player
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );
        assert_eq!(db.player_object_for_client(client_id), Some(player_obj));
        assert_eq!(db.history_object_for_client(client_id), Some(player_obj));
        assert_eq!(db.connected_players(false), vec![player_obj]);

        // Both connection and player should be in connections list
        let mut connections = db.connections();
        connections.sort();
        let mut expected = vec![connection_obj, player_obj];
        expected.sort();
        assert_eq!(connections, expected);
        assert_eq!(db.connected_players(true), expected);

        // Client IDs should work for both connection and player objects
        assert_eq!(db.client_ids_for(connection_obj).unwrap(), vec![client_id]);
        assert_eq!(db.client_ids_for(player_obj).unwrap(), vec![client_id]);
    }

    #[test]
    fn test_switch_player_updates_both_connection_indexes() {
        use moor_var::Obj;

        let db = ConnectionRegistryFactory::in_memory_only().unwrap();
        let client_id = Uuid::new_v4();
        let old_player = Obj::mk_id(100);
        let new_player = Obj::mk_id(101);
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "switch.test".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: Some(old_player),
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        let switched_clients = db
            .switch_player_for_connection(connection_obj, new_player, false)
            .unwrap();

        assert_eq!(switched_clients, vec![client_id]);
        assert_eq!(db.player_object_for_client(client_id), Some(new_player));
        assert_eq!(db.history_object_for_client(client_id), Some(new_player));
        assert!(db.client_ids_for(old_player).unwrap().is_empty());
        assert_eq!(db.client_ids_for(new_player).unwrap(), vec![client_id]);
        assert_eq!(db.connected_players(false), vec![new_player]);

        db.switch_player_for_connection(connection_obj, new_player, false)
            .unwrap();
        assert_eq!(db.client_ids_for(new_player).unwrap(), vec![client_id]);
    }

    #[test]
    fn test_switch_player_can_preserve_history_owner() {
        use moor_var::Obj;

        let db = ConnectionRegistryFactory::in_memory_only().unwrap();
        let client_id = Uuid::new_v4();
        let old_player = Obj::mk_id(100);
        let new_player = Obj::mk_id(101);
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "switch.test".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: Some(old_player),
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        db.switch_player_for_connection(connection_obj, new_player, true)
            .unwrap();

        assert_eq!(db.player_object_for_client(client_id), Some(new_player));
        assert_eq!(db.history_object_for_client(client_id), Some(old_player));
    }

    #[test]
    fn test_rejected_switch_preserves_player_indexes() {
        use moor_var::Obj;

        let db = ConnectionRegistryFactory::in_memory_only().unwrap();
        let client_id = Uuid::new_v4();
        let old_player = Obj::mk_id(100);
        db.new_connection(NewConnectionParams {
            client_id,
            hostname: "switch.test".to_string(),
            local_port: 7777,
            remote_port: 12345,
            player: Some(old_player),
            acceptable_content_types: None,
            connection_attributes: None,
        })
        .unwrap();

        assert!(
            db.switch_player_for_connection(Obj::mk_id(-999), Obj::mk_id(101), false)
                .is_err()
        );
        assert_eq!(db.player_object_for_client(client_id), Some(old_player));
        assert_eq!(db.history_object_for_client(client_id), Some(old_player));
        assert_eq!(db.client_ids_for(old_player).unwrap(), vec![client_id]);
    }

    #[test]
    fn test_soft_detach_preserves_connection() {
        // Soft detach should call record_client_activity, keeping the connection alive
        let db = ConnectionRegistryFactory::in_memory_only().unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "test.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Simulate soft detach by calling record_client_activity
        db.record_client_activity(client_id, connection_obj)
            .unwrap();

        // Connection should still exist
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );
        assert!(db.last_activity_for(connection_obj).is_ok());
    }

    #[test]
    fn test_hard_detach_removes_connection() {
        // Hard detach should call remove_client_connection, destroying the connection
        let db = ConnectionRegistryFactory::in_memory_only().unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "test.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Verify connection exists
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );

        // Hard detach - remove the connection
        db.remove_client_connection(client_id).unwrap();

        // Connection should be gone
        assert_eq!(db.connection_object_for_client(client_id), None);
        assert_eq!(db.connections(), vec![]);
    }

    #[test]
    fn test_ping_timeout_removes_connection() {
        let db = ConnectionRegistryFactory::in_memory_only().unwrap();

        let client_id = Uuid::new_v4();
        let connection_obj = db
            .new_connection(NewConnectionParams {
                client_id,
                hostname: "test.host".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: None,
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Connection exists initially
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );

        // Notify alive to set last_ping
        db.notify_is_alive(client_id, connection_obj).unwrap();

        // ping_check with fresh timestamp should NOT remove
        db.ping_check();
        assert_eq!(
            db.connection_object_for_client(client_id),
            Some(connection_obj)
        );

        // Note: We can't easily test the timeout without waiting 30+ seconds
        // or modifying the PING_TIMEOUT constant. This test verifies that
        // active connections are NOT removed.
    }

    #[test]
    fn test_multiple_connections_same_player() {
        use moor_var::Obj;

        let db = ConnectionRegistryFactory::in_memory_only().unwrap();
        let player_obj = Obj::mk_id(100);

        // Create first connection
        let client_id_1 = Uuid::new_v4();
        let connection_obj_1 = db
            .new_connection(NewConnectionParams {
                client_id: client_id_1,
                hostname: "host1.test".to_string(),
                local_port: 7777,
                remote_port: 12345,
                player: Some(player_obj),
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Create second connection for same player
        let client_id_2 = Uuid::new_v4();
        let connection_obj_2 = db
            .new_connection(NewConnectionParams {
                client_id: client_id_2,
                hostname: "host2.test".to_string(),
                local_port: 7778,
                remote_port: 12346,
                player: Some(player_obj),
                acceptable_content_types: None,
                connection_attributes: None,
            })
            .unwrap();

        // Both connections should exist
        assert_eq!(
            db.connection_object_for_client(client_id_1),
            Some(connection_obj_1)
        );
        assert_eq!(
            db.connection_object_for_client(client_id_2),
            Some(connection_obj_2)
        );

        // Player should have both client IDs
        let client_ids = db.client_ids_for(player_obj).unwrap();
        assert_eq!(client_ids.len(), 2);
        assert!(client_ids.contains(&client_id_1));
        assert!(client_ids.contains(&client_id_2));

        // Remove first connection
        db.remove_client_connection(client_id_1).unwrap();

        // Player should still have second connection
        let client_ids = db.client_ids_for(player_obj).unwrap();
        assert_eq!(client_ids, vec![client_id_2]);
        assert_eq!(db.player_object_for_client(client_id_2), Some(player_obj));
        assert_eq!(db.connected_players(false), vec![player_obj]);

        // Remove second connection
        db.remove_client_connection(client_id_2).unwrap();

        // Player should have no connections
        let client_ids = db.client_ids_for(player_obj).unwrap();
        assert!(client_ids.is_empty());
        assert!(db.connected_players(false).is_empty());
        assert!(db.connected_players(true).is_empty());
    }
}
