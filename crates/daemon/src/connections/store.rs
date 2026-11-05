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

//! Where the registry keeps its clients between runs: one fjall keyspace of clients by id, and
//! the connection id sequence. Only the registry's writer thread uses it, so nothing that serves
//! a request ever waits on the disk.
//!
//! Opening it sanitises what it finds, since a crash or an older daemon may have left anything:
//! records that don't decode, or whose key isn't their client, or that aren't connections, are
//! dropped; of two clients claiming one connection the later is kept; and the sequence is moved
//! past any connection found, so none is handed out twice. A database in the registry's earlier
//! layout, five keyspaces kept in step by hand, is read once into this one and the old keyspaces
//! dropped.

use std::{collections::HashMap, path::Path, sync::Arc, time::SystemTime};

use eyre::{Error, eyre};
use fjall::{Database, Keyspace, KeyspaceCreateOptions, PersistMode};
use moor_schema::convert as convert_schema;
use moor_var::{Obj, Symbol, Var};
use planus::{ReadAsRoot, WriteAsOffset};
use tracing::{info, warn};
use uuid::Uuid;
use zerocopy::IntoBytes;

use crate::connections::{
    FIRST_CONNECTION_ID,
    connections_generated::moor_connections::{StoredAttribute, StoredClient, StoredClientRef},
    conversions::connections_records_from_bytes,
    state::{Client, Times, nanos, time},
};

const CLIENTS: &str = "clients";
const SEQUENCES: &str = "connection_sequences";
const SEQUENCE_KEY: &str = "connection_id_sequence";
const LEGACY_KEYSPACES: [&str; 5] = [
    "client_connection",
    "client_player",
    "client_history",
    "connection_records",
    "player_clients",
];

/// What a store held when it was opened.
pub(crate) struct Loaded {
    pub(crate) clients: Vec<Client>,
    /// The first connection id this run may hand out: every one above it may have been.
    pub(crate) next_id: i32,
}

pub(crate) struct FjallStore {
    db: Database,
    clients: Keyspace,
    sequences: Keyspace,
}

impl FjallStore {
    pub(crate) fn open(path: &Path) -> Result<(Self, Loaded), Error> {
        info!(?path, "Opening connections database");
        let db = Database::builder(path).open()?;
        let clients = db.keyspace(CLIENTS, KeyspaceCreateOptions::default)?;
        let sequences = db.keyspace(SEQUENCES, KeyspaceCreateOptions::default)?;
        let store = Self {
            db,
            clients,
            sequences,
        };
        store.migrate_legacy()?;
        let loaded = store.load()?;
        Ok((store, loaded))
    }

    fn load(&self) -> Result<Loaded, Error> {
        let mut by_connection: HashMap<Obj, Client> = HashMap::new();
        let mut dropped: Vec<Vec<u8>> = vec![];
        for entry in self.clients.iter() {
            let (key, value) = entry.into_inner()?;
            let client = match decode(&value) {
                Ok(client) if client.client_id.as_bytes() == key.as_ref() => client,
                Ok(client) => {
                    warn!(client = ?client.client_id, "Dropping a client stored under another's id");
                    dropped.push(key.to_vec());
                    continue;
                }
                Err(error) => {
                    warn!(?error, "Dropping a client record that doesn't decode");
                    dropped.push(key.to_vec());
                    continue;
                }
            };
            if client.connection.is_positive() {
                warn!(client = ?client.client_id, connection = %client.connection,
                    "Dropping a client whose connection isn't a connection object");
                dropped.push(key.to_vec());
                continue;
            }
            match by_connection.get(&client.connection) {
                Some(other) if other.connected_time >= client.connected_time => {
                    warn!(client = ?client.client_id, connection = %client.connection,
                        "Dropping a client whose connection a later client has");
                    dropped.push(key.to_vec());
                }
                Some(other) => {
                    warn!(client = ?other.client_id, connection = %other.connection,
                        "Dropping a client whose connection a later client has");
                    dropped.push(other.client_id.as_bytes().to_vec());
                    by_connection.insert(client.connection, client);
                }
                None => {
                    by_connection.insert(client.connection, client);
                }
            }
        }
        if !dropped.is_empty() {
            let mut batch = self.db.batch();
            for key in &dropped {
                batch.remove(&self.clients, key.as_slice());
            }
            batch.commit()?;
            info!(dropped = dropped.len(), "Dropped invalid client records");
        }

        let stored_sequence = match self.sequences.get(SEQUENCE_KEY)? {
            Some(bytes) => i32::from_le_bytes(
                bytes
                    .get(..size_of::<i32>())
                    .ok_or_else(|| eyre!("short connection id sequence"))?
                    .try_into()?,
            ),
            None => FIRST_CONNECTION_ID,
        };
        let lowest = by_connection.keys().map(|obj| obj.id().0).min();
        let next_id = match lowest {
            Some(lowest) if lowest <= stored_sequence => {
                warn!(
                    lowest,
                    stored_sequence,
                    "The connection id sequence was behind a stored connection; moving it past"
                );
                lowest - 1
            }
            _ => stored_sequence,
        };
        let mut clients: Vec<Client> = by_connection.into_values().collect();
        clients.sort_by_key(|client| client.joined);
        info!(clients = clients.len(), next_id, "Loaded connections");
        Ok(Loaded { clients, next_id })
    }

    /// Read a database in the earlier layout into this one, and drop the old keyspaces.
    fn migrate_legacy(&self) -> Result<(), Error> {
        if !LEGACY_KEYSPACES
            .iter()
            .any(|name| self.db.keyspace_exists(name))
        {
            return Ok(());
        }
        let open = |name| self.db.keyspace(name, KeyspaceCreateOptions::default);
        let [connections, players, histories, records, player_clients] = LEGACY_KEYSPACES.map(open);
        let (connections, players, histories, records) =
            (connections?, players?, histories?, records?);
        let player_of = |keyspace: &Keyspace, key: &[u8]| -> Option<Obj> {
            let bytes = keyspace.get(key).ok()??;
            Obj::from_bytes(bytes.as_ref()).ok()
        };
        let player_clients = player_clients?;
        // Each client's place among its player's, which the earlier layout kept as a list.
        let mut places: HashMap<u128, u64> = HashMap::new();
        for entry in player_clients.iter() {
            let Ok(value) = entry.value() else {
                continue;
            };
            if let Ok(records) = connections_records_from_bytes(&value) {
                for (place, record) in records.connections.iter().enumerate() {
                    places.insert(record.client_id, place as u64);
                }
            }
        }

        let mut migrated = 0;
        let mut batch = self.db.batch();
        for entry in connections.iter() {
            let Ok((key, value)) = entry.into_inner() else {
                continue;
            };
            let Ok(id_bytes) = <[u8; 16]>::try_from(key.as_ref()) else {
                continue;
            };
            let client_id = Uuid::from_u128(u128::from_le_bytes(id_bytes));
            let Ok(connection) = Obj::from_bytes(value.as_ref()) else {
                continue;
            };
            let Some(record) = records
                .get(value.as_ref())
                .ok()
                .flatten()
                .and_then(|bytes| connections_records_from_bytes(&bytes).ok())
                .and_then(|records| {
                    records
                        .connections
                        .into_iter()
                        .find(|record| record.client_id == client_id.as_u128())
                })
            else {
                continue;
            };
            let client = Client {
                client_id,
                connection,
                player: player_of(&players, key.as_ref()),
                history: player_of(&histories, key.as_ref()),
                joined: places.get(&client_id.as_u128()).copied().unwrap_or(0),
                hostname: record.hostname.into(),
                local_port: record.local_port,
                remote_port: record.remote_port,
                connected_time: record.connected_time,
                content_types: record.acceptable_content_types.into(),
                attributes: Arc::new(record.client_attributes),
                times: Arc::new(Times::new(record.last_activity, record.last_ping)),
            };
            batch.insert(&self.clients, client_id.as_bytes(), encode(&client)?);
            migrated += 1;
        }
        batch.commit()?;
        for keyspace in [connections, players, histories, records, player_clients] {
            self.db.delete_keyspace(keyspace)?;
        }
        self.db.persist(PersistMode::SyncAll)?;
        info!(migrated, "Migrated connections from the earlier layout");
        Ok(())
    }

    /// Write these clients as they are, and forget these.
    pub(crate) fn write(&self, puts: &[Arc<Client>], deletes: &[Uuid]) -> Result<(), Error> {
        let mut batch = self.db.batch();
        for client in puts {
            batch.insert(&self.clients, client.client_id.as_bytes(), encode(client)?);
        }
        for client_id in deletes {
            batch.remove(&self.clients, client_id.as_bytes());
        }
        batch.commit()?;
        Ok(())
    }

    /// Record, durably, that connection ids down to `next_id` exclusive may be handed out.
    pub(crate) fn reserve(&self, next_id: i32) -> Result<(), Error> {
        self.sequences.insert(SEQUENCE_KEY, next_id.to_le_bytes())?;
        self.db.persist(PersistMode::SyncAll)?;
        Ok(())
    }

    pub(crate) fn sync(&self) -> Result<(), Error> {
        self.db.persist(PersistMode::SyncAll)?;
        Ok(())
    }
}

fn split(time: SystemTime) -> (u64, u32) {
    let nanos = nanos(time);
    (nanos / 1_000_000_000, (nanos % 1_000_000_000) as u32)
}

fn join(secs: u64, nanos: u32) -> SystemTime {
    time(
        secs.saturating_mul(1_000_000_000)
            .saturating_add(u64::from(nanos)),
    )
}

pub(crate) fn encode(client: &Client) -> Result<Vec<u8>, Error> {
    let (connected_secs, connected_nanos) = split(client.connected_time);
    let (last_activity_secs, last_activity_nanos) = split(client.times.last_activity());
    let (last_ping_secs, last_ping_nanos) = split(client.times.last_ping());
    let mut attributes = Vec::with_capacity(client.attributes.len());
    for (key, value) in client.attributes.iter() {
        attributes.push(StoredAttribute {
            key: key.as_string(),
            value: var_bytes(value)?,
        });
    }
    let id = client.client_id.as_u128();
    let stored = StoredClient {
        client_id_high: (id >> 64) as u64,
        client_id_low: id as u64,
        connection: client.connection.as_bytes().to_vec(),
        player: client.player.map(|p| p.as_bytes().to_vec()),
        history: client.history.map(|h| h.as_bytes().to_vec()),
        joined: client.joined,
        connected_secs,
        connected_nanos,
        last_activity_secs,
        last_activity_nanos,
        last_ping_secs,
        last_ping_nanos,
        hostname: client.hostname.to_string(),
        local_port: client.local_port,
        remote_port: client.remote_port,
        content_types: client
            .content_types
            .iter()
            .map(|content_type| content_type.as_string())
            .collect(),
        attributes,
    };
    let mut builder = planus::Builder::new();
    let offset = WriteAsOffset::prepare(&stored, &mut builder);
    builder.finish(offset, None);
    Ok(builder.as_slice().to_vec())
}

pub(crate) fn decode(bytes: &[u8]) -> Result<Client, Error> {
    let stored = StoredClientRef::read_as_root(bytes)?;
    let obj = |bytes: Option<&[u8]>| -> Result<Option<Obj>, Error> {
        bytes
            .map(|bytes| Obj::from_bytes(bytes).map_err(|e| eyre!("bad object: {e:?}")))
            .transpose()
    };
    let client_id = Uuid::from_u128(
        (u128::from(stored.client_id_high()?) << 64) | u128::from(stored.client_id_low()?),
    );
    let connection = obj(Some(stored.connection()?))?.expect("present");
    let mut content_types = vec![];
    for content_type in stored.content_types()? {
        content_types.push(Symbol::mk(content_type?));
    }
    let mut attributes = HashMap::new();
    for attribute in stored.attributes()? {
        let attribute = attribute?;
        attributes.insert(
            Symbol::mk(attribute.key()?),
            var_from_bytes(attribute.value()?)?,
        );
    }
    Ok(Client {
        client_id,
        connection,
        player: obj(stored.player()?)?,
        history: obj(stored.history()?)?,
        joined: stored.joined()?,
        hostname: stored.hostname()?.into(),
        local_port: stored.local_port()?,
        remote_port: stored.remote_port()?,
        connected_time: join(stored.connected_secs()?, stored.connected_nanos()?),
        content_types: content_types.into(),
        attributes: Arc::new(attributes),
        times: Arc::new(Times::new(
            join(stored.last_activity_secs()?, stored.last_activity_nanos()?),
            join(stored.last_ping_secs()?, stored.last_ping_nanos()?),
        )),
    })
}

fn var_bytes(value: &Var) -> Result<Vec<u8>, Error> {
    let var = convert_schema::var_to_db_flatbuffer(value)?;
    let mut builder = planus::Builder::new();
    let offset = WriteAsOffset::prepare(&var, &mut builder);
    builder.finish(offset, None);
    Ok(builder.as_slice().to_vec())
}

fn var_from_bytes(bytes: &[u8]) -> Result<Var, Error> {
    let var = moor_schema::var::VarRef::read_as_root(bytes)?;
    convert_schema::var_from_ref(var).map_err(|e| eyre!("bad attribute value: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::v_str;

    fn client(connection: i32, connected_secs: u64) -> Client {
        let at = join(connected_secs, 0);
        Client {
            client_id: Uuid::new_v4(),
            connection: Obj::mk_id(connection),
            player: Some(Obj::mk_id(100)),
            history: Some(Obj::mk_id(99)),
            joined: 3,
            hostname: "a.host".into(),
            local_port: 7777,
            remote_port: 40000,
            connected_time: at,
            content_types: vec![Symbol::mk("text_djot")].into(),
            attributes: Arc::new([(Symbol::mk("colour"), v_str("green"))].into()),
            times: Arc::new(Times::new(at, at)),
        }
    }

    #[test]
    fn a_client_round_trips() {
        let original = client(-7, 1_700_000_000);
        let back = decode(&encode(&original).unwrap()).unwrap();
        assert_eq!(back.client_id, original.client_id);
        assert_eq!(back.connection, original.connection);
        assert_eq!(back.player, original.player);
        assert_eq!(back.history, original.history);
        assert_eq!(back.joined, original.joined);
        assert_eq!(back.hostname, original.hostname);
        assert_eq!(back.connected_time, original.connected_time);
        assert_eq!(back.content_types, original.content_types);
        assert_eq!(back.attributes, original.attributes);
        assert_eq!(back.times.raw(), original.times.raw());
    }

    /// A database the earlier registry wrote: five keyspaces, its records under both their
    /// connection and their player, and its sequence.
    #[test]
    fn a_database_in_the_earlier_layout_is_migrated() {
        use crate::connections::{
            ConnectionRecord, ConnectionsRecords, conversions::connections_records_to_bytes,
        };
        let dir = tempfile::tempdir().unwrap();
        let (logged_in, unlogged) = (Uuid::new_v4(), Uuid::new_v4());
        let (player, history) = (Obj::mk_id(100), Obj::mk_id(99));
        let record = |client_id: Uuid| ConnectionRecord {
            client_id: client_id.as_u128(),
            connected_time: join(1_000, 0),
            last_activity: join(2_000, 0),
            last_ping: join(3_000, 0),
            hostname: "old.host".to_string(),
            local_port: 7777,
            remote_port: 40000,
            acceptable_content_types: vec![Symbol::mk("text_djot")],
            client_attributes: [(Symbol::mk("colour"), v_str("green"))].into(),
        };
        let records = |client_id| {
            connections_records_to_bytes(&ConnectionsRecords {
                connections: vec![record(client_id)],
            })
            .unwrap()
        };
        {
            let db = Database::builder(dir.path()).open().unwrap();
            let ks = |name| db.keyspace(name, KeyspaceCreateOptions::default).unwrap();
            let [connections, players, histories, records_ks, player_clients] =
                LEGACY_KEYSPACES.map(ks);
            let key = |id: Uuid| id.as_u128().to_le_bytes();
            for (client_id, connection) in [(logged_in, -5), (unlogged, -6)] {
                let connection = Obj::mk_id(connection);
                connections
                    .insert(key(client_id), connection.as_bytes())
                    .unwrap();
                records_ks
                    .insert(connection.as_bytes(), records(client_id))
                    .unwrap();
            }
            players.insert(key(logged_in), player.as_bytes()).unwrap();
            histories
                .insert(key(logged_in), history.as_bytes())
                .unwrap();
            player_clients
                .insert(player.as_bytes(), records(logged_in))
                .unwrap();
            ks(SEQUENCES)
                .insert(SEQUENCE_KEY, (-7_i32).to_le_bytes())
                .unwrap();
            db.persist(PersistMode::SyncAll).unwrap();
        }

        let (store, loaded) = FjallStore::open(dir.path()).unwrap();
        let mut clients = loaded.clients;
        clients.sort_by_key(|c| c.connection);
        let found: Vec<_> = clients
            .iter()
            .map(|c| (c.client_id, c.connection, c.player, c.history))
            .collect();
        assert_eq!(
            found,
            vec![
                (unlogged, Obj::mk_id(-6), None, None),
                (logged_in, Obj::mk_id(-5), Some(player), Some(history)),
            ]
        );
        let migrated = &clients[1];
        assert_eq!(&*migrated.hostname, "old.host");
        assert_eq!(migrated.attributes[&Symbol::mk("colour")], v_str("green"));
        assert_eq!(migrated.times.last_ping(), join(3_000, 0));
        assert_eq!(loaded.next_id, -7, "the earlier sequence carries on");
        for name in LEGACY_KEYSPACES {
            assert!(!store.db.keyspace_exists(name), "{name} is dropped");
        }
        drop(store);
        let (_, reopened) = FjallStore::open(dir.path()).unwrap();
        assert_eq!(reopened.clients.len(), 2, "and it stays migrated");
    }

    #[test]
    fn opening_drops_what_it_cant_trust() {
        let dir = tempfile::tempdir().unwrap();
        let (kept, older, impostor) = (client(-7, 2_000), client(-7, 1_000), client(-8, 1_000));
        {
            let (store, _) = FjallStore::open(dir.path()).unwrap();
            for c in [&kept, &older] {
                store
                    .clients
                    .insert(c.client_id.as_bytes(), encode(c).unwrap())
                    .unwrap();
            }
            store
                .clients
                .insert(Uuid::new_v4().as_bytes(), encode(&impostor).unwrap())
                .unwrap();
            store
                .clients
                .insert(Uuid::new_v4().as_bytes(), b"not a client".to_vec())
                .unwrap();
            let mut positive = client(5, 1_000);
            positive.client_id = Uuid::new_v4();
            store
                .clients
                .insert(positive.client_id.as_bytes(), encode(&positive).unwrap())
                .unwrap();
            store.sync().unwrap();
        }
        let (store, loaded) = FjallStore::open(dir.path()).unwrap();
        let ids: Vec<Uuid> = loaded.clients.iter().map(|c| c.client_id).collect();
        assert_eq!(
            ids,
            vec![kept.client_id],
            "only the later of two on one connection"
        );
        assert_eq!(
            store.clients.iter().count(),
            1,
            "and the rest are gone from disk"
        );
        assert!(
            loaded.next_id < -7,
            "the sequence is moved past what was found"
        );
    }
}
