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

//! What any connection registry must do, checked through its traits alone: against a model of
//! connections, players and their histories that random sequences of the daemon's operations
//! are applied to, and across reopening the registry from disk.

use std::{collections::BTreeMap, path::Path, sync::Arc, time::Duration};

use moor_var::{Obj, Symbol, Var, v_int, v_str};
use rand::{RngExt, SeedableRng, rngs::StdRng};
use uuid::Uuid;

use crate::connections::{
    ConnectionRegistry, ConnectionRegistryFactory, ConnectionStateSource, NewConnectionParams,
    RemovedConnection,
};

fn open_at(path: &Path) -> Arc<dyn ConnectionRegistry> {
    ConnectionRegistryFactory::with_fjall_persistence(Some(path)).expect("open registry")
}

fn params(client_id: Uuid, player: Option<Obj>, host: &str) -> NewConnectionParams {
    NewConnectionParams {
        client_id,
        hostname: host.to_string(),
        local_port: 7777,
        remote_port: 40000,
        player,
        acceptable_content_types: Some(vec![Symbol::mk("text_djot"), Symbol::mk("text_plain")]),
        connection_attributes: Some([(Symbol::mk("host_type"), v_str("test"))].into()),
    }
}

// ---------------------------------------------------------------------------------------------
// The model
// ---------------------------------------------------------------------------------------------

#[derive(Clone, Debug)]
struct ModelClient {
    connection: Obj,
    player: Option<Obj>,
    history: Option<Obj>,
    host: String,
    attributes: BTreeMap<Symbol, Var>,
}

/// Connections as the daemon means them: each client has one connection object, which no
/// other connection ever has, a player once it logs in, and a history owner; a player's clients
/// are in the order they joined that player.
#[derive(Default, Debug)]
struct Model {
    clients: BTreeMap<Uuid, ModelClient>,
    /// Each player's clients, in the order they joined.
    players: BTreeMap<Obj, Vec<Uuid>>,
    /// Every connection object handed out, connections' and reserved ones.
    handed_out: Vec<Obj>,
}

impl Model {
    fn connect(&mut self, client_id: Uuid, connection: Obj, player: Option<Obj>, host: &str) {
        self.clients.insert(
            client_id,
            ModelClient {
                connection,
                player,
                history: player,
                host: host.to_string(),
                attributes: [(Symbol::mk("host_type"), v_str("test"))].into(),
            },
        );
        if let Some(player) = player {
            self.players.entry(player).or_default().push(client_id);
        }
    }

    fn join(&mut self, client_id: Uuid, player: Obj) {
        if let Some(previous) = self.clients[&client_id].player {
            self.leave_player(client_id, previous);
        }
        self.players.entry(player).or_default().push(client_id);
        self.clients.get_mut(&client_id).unwrap().player = Some(player);
    }

    fn leave_player(&mut self, client_id: Uuid, player: Obj) {
        let clients = self.players.get_mut(&player).unwrap();
        clients.retain(|&id| id != client_id);
        if clients.is_empty() {
            self.players.remove(&player);
        }
    }

    fn login(&mut self, client_id: Uuid, player: Obj) {
        self.join(client_id, player);
        self.clients.get_mut(&client_id).unwrap().history = Some(player);
    }

    fn switch(&mut self, client_id: Uuid, player: Obj, preserve_history: bool) {
        let previous = self.clients[&client_id].player;
        self.join(client_id, player);
        let client = self.clients.get_mut(&client_id).unwrap();
        if !preserve_history {
            client.history = Some(player);
        } else if client.history.is_none() {
            client.history = previous;
        }
    }

    fn remove(&mut self, client_id: Uuid) -> Option<RemovedConnection> {
        let client = self.clients.remove(&client_id)?;
        let mut disconnected_player = None;
        if let Some(player) = client.player {
            self.leave_player(client_id, player);
            if !self.players.contains_key(&player) {
                disconnected_player = Some(player);
            }
        }
        Some(RemovedConnection {
            client_id,
            connection: client.connection,
            disconnected_player,
        })
    }

    fn connections_of(&self, player: Obj) -> Vec<Obj> {
        self.players
            .get(&player)
            .map(|ids| ids.iter().map(|id| self.clients[id].connection).collect())
            .unwrap_or_default()
    }
}

/// Check every observable query of `registry` against `model`.
fn assert_matches(registry: &dyn ConnectionRegistry, model: &Model, step: &str) {
    let state: &dyn ConnectionStateSource = registry;
    for (&client_id, client) in &model.clients {
        let at = format!("{step}: client {client_id}");
        assert_eq!(
            registry.connection_object_for_client(client_id),
            Some(client.connection),
            "{at}: connection"
        );
        assert_eq!(
            registry.player_object_for_client(client_id),
            client.player,
            "{at}: player"
        );
        assert_eq!(
            registry.history_object_for_client(client_id),
            client.history,
            "{at}: history"
        );
        assert_eq!(
            registry.client_ids_for(client.connection).unwrap(),
            vec![client_id],
            "{at}: the connection's clients"
        );
        let attributes: BTreeMap<_, _> = registry
            .get_client_attributes(client.connection)
            .unwrap()
            .into_iter()
            .collect();
        assert_eq!(attributes, client.attributes, "{at}: attributes");
        assert_eq!(
            registry
                .acceptable_content_types_for(client.connection)
                .unwrap(),
            vec![Symbol::mk("text_djot"), Symbol::mk("text_plain")],
            "{at}: content types"
        );
        assert_eq!(
            registry.connection_name_for(client.connection).unwrap(),
            format!("port 7777 from {}, port 40000", client.host),
            "{at}: name"
        );
        let mut session = vec![client.connection];
        if let Some(player) = client.player {
            session.extend(
                model
                    .connections_of(player)
                    .into_iter()
                    .filter(|&c| c != client.connection),
            );
        }
        assert_eq!(
            state.connections_for(client_id, None).unwrap(),
            session,
            "{at}: the session's connections"
        );
    }
    for (&player, clients) in &model.players {
        let at = format!("{step}: player {player}");
        assert_eq!(
            &registry.client_ids_for(player).unwrap(),
            clients,
            "{at}: clients"
        );
        assert_eq!(
            state.connections_for(Uuid::nil(), Some(player)).unwrap(),
            model.connections_of(player),
            "{at}: connections"
        );
    }
    let players: Vec<Obj> = model.players.keys().copied().collect();
    assert_eq!(
        registry.connected_players(false),
        players,
        "{step}: connected players"
    );
    let mut everything: Vec<Obj> = model.clients.values().map(|c| c.connection).collect();
    everything.extend(&players);
    everything.sort_unstable();
    assert_eq!(
        registry.connected_players(true),
        everything,
        "{step}: connected players and connections"
    );
}

/// What a step of a random run does.
#[derive(Debug, Clone, Copy)]
enum Step {
    Connect { logged_in: bool },
    Login,
    Switch { preserve_history: bool },
    SetAttribute,
    ClearAttribute,
    Remove,
    Reserve,
    Reopen,
}

const STEPS: [Step; 10] = [
    Step::Connect { logged_in: false },
    Step::Connect { logged_in: true },
    Step::Login,
    Step::Switch {
        preserve_history: false,
    },
    Step::Switch {
        preserve_history: true,
    },
    Step::SetAttribute,
    Step::ClearAttribute,
    Step::Remove,
    Step::Reserve,
    Step::Reopen,
];

/// Apply `steps` random steps from `seed` to a registry at `path` and to the model, checking
/// they agree after each, and that no connection object is handed out twice.
fn run_against_model(path: &Path, seed: u64, steps: usize, reopen: bool) {
    let mut rng = StdRng::seed_from_u64(seed);
    let mut registry = open_at(path);
    let mut model = Model::default();
    let players: Vec<Obj> = (0..6).map(|i| Obj::mk_id(100 + i)).collect();
    let pick_player = |rng: &mut StdRng| players[rng.random_range(0..players.len())];

    for n in 0..steps {
        let step = STEPS[rng.random_range(0..STEPS.len())];
        let clients: Vec<Uuid> = model.clients.keys().copied().collect();
        let any_client = |rng: &mut StdRng| clients[rng.random_range(0..clients.len())];
        let at = format!("seed {seed} step {n} {step:?}");
        match step {
            Step::Connect { logged_in } => {
                let client_id = Uuid::from_u128(rng.random());
                let player = logged_in.then(|| pick_player(&mut rng));
                let host = format!("host{n}");
                let connection = registry
                    .new_connection(params(client_id, player, &host))
                    .unwrap();
                assert!(
                    !model.handed_out.contains(&connection),
                    "{at}: {connection} handed out twice"
                );
                model.handed_out.push(connection);
                model.connect(client_id, connection, player, &host);
            }
            Step::Login => {
                let unlogged: Vec<Uuid> = model
                    .clients
                    .iter()
                    .filter(|(_, c)| c.player.is_none())
                    .map(|(&id, _)| id)
                    .collect();
                if unlogged.is_empty() {
                    continue;
                }
                let client_id = unlogged[rng.random_range(0..unlogged.len())];
                let player = pick_player(&mut rng);
                let connection = model.clients[&client_id].connection;
                registry
                    .associate_player_object(connection, player)
                    .unwrap();
                model.login(client_id, player);
            }
            Step::Switch { preserve_history } => {
                if clients.is_empty() {
                    continue;
                }
                let client_id = any_client(&mut rng);
                let player = pick_player(&mut rng);
                let connection = model.clients[&client_id].connection;
                let switched = registry
                    .switch_player_for_connection(connection, player, preserve_history)
                    .unwrap();
                assert_eq!(switched, vec![client_id], "{at}: switched clients");
                model.switch(client_id, player, preserve_history);
            }
            Step::SetAttribute | Step::ClearAttribute => {
                if clients.is_empty() {
                    continue;
                }
                let client_id = any_client(&mut rng);
                let key = Symbol::mk(["colour", "width", "host_type"][rng.random_range(0..3)]);
                let value = matches!(step, Step::SetAttribute).then(|| v_int(n as i64));
                registry
                    .set_client_attribute(client_id, key, value.clone())
                    .unwrap();
                let attributes = &mut model.clients.get_mut(&client_id).unwrap().attributes;
                match value {
                    Some(value) => {
                        attributes.insert(key, value);
                    }
                    None => {
                        attributes.remove(&key);
                    }
                }
            }
            Step::Remove => {
                if clients.is_empty() {
                    continue;
                }
                let client_id = any_client(&mut rng);
                assert_eq!(
                    registry.remove_client_connection(client_id).unwrap(),
                    model.remove(client_id),
                    "{at}: removal"
                );
                assert_eq!(
                    registry.remove_client_connection(client_id).unwrap(),
                    None,
                    "{at}: removing again"
                );
            }
            Step::Reserve => {
                let reserved = registry.reserve_connection_id().unwrap();
                assert!(
                    !model.handed_out.contains(&reserved),
                    "{at}: {reserved} handed out twice"
                );
                model.handed_out.push(reserved);
            }
            Step::Reopen => {
                if !reopen {
                    continue;
                }
                registry.flush();
                drop(registry);
                registry = open_at(path);
            }
        }
        assert_matches(registry.as_ref(), &model, &at);
    }
}

#[test]
fn random_runs_agree_with_the_model() {
    for seed in 0..24 {
        let dir = tempfile::tempdir().unwrap();
        run_against_model(dir.path(), seed, 120, false);
    }
}

#[test]
fn random_runs_agree_with_the_model_across_reopening() {
    for seed in 100..112 {
        let dir = tempfile::tempdir().unwrap();
        run_against_model(dir.path(), seed, 120, true);
    }
}

// ---------------------------------------------------------------------------------------------
// Reopening
// ---------------------------------------------------------------------------------------------

/// A daemon that restarts keeps its connections, so that hosts carry on with them: who they
/// are, who's logged in on them, whose history they're in, and what they've said of themselves.
#[test]
fn a_reopened_registry_has_its_connections() {
    let dir = tempfile::tempdir().unwrap();
    let (player, other) = (Obj::mk_id(100), Obj::mk_id(101));
    let (a, b, c) = (Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4());
    let (conn_a, conn_b, conn_c);
    {
        let registry = open_at(dir.path());
        conn_a = registry
            .new_connection(params(a, Some(player), "a"))
            .unwrap();
        conn_b = registry.new_connection(params(b, None, "b")).unwrap();
        conn_c = registry.new_connection(params(c, None, "c")).unwrap();
        registry.associate_player_object(conn_b, player).unwrap();
        registry
            .switch_player_for_connection(conn_b, other, true)
            .unwrap();
        registry
            .set_client_attribute(a, Symbol::mk("colour"), Some(v_str("green")))
            .unwrap();
        registry.flush();
    }
    let registry = open_at(dir.path());
    assert_eq!(registry.connection_object_for_client(a), Some(conn_a));
    assert_eq!(registry.connection_object_for_client(c), Some(conn_c));
    assert_eq!(registry.player_object_for_client(b), Some(other));
    assert_eq!(registry.history_object_for_client(b), Some(player));
    assert_eq!(registry.player_object_for_client(c), None);
    assert_eq!(registry.client_ids_for(player).unwrap(), vec![a]);
    assert_eq!(registry.client_ids_for(other).unwrap(), vec![b]);
    assert_eq!(
        registry.get_client_attributes(conn_a).unwrap()[&Symbol::mk("colour")],
        v_str("green")
    );
    assert_eq!(registry.connected_players(false), vec![player, other]);
}

/// A connection object, once handed out, is never handed out again, even by a registry
/// reopened after it.
#[test]
fn a_reopened_registry_never_reuses_a_connection_object() {
    let dir = tempfile::tempdir().unwrap();
    let mut seen = vec![];
    for _ in 0..3 {
        let registry = open_at(dir.path());
        for _ in 0..5 {
            let connection = registry
                .new_connection(params(Uuid::new_v4(), None, "h"))
                .unwrap();
            let reserved = registry.reserve_connection_id().unwrap();
            for obj in [connection, reserved] {
                assert!(!seen.contains(&obj), "{obj} handed out twice");
                assert!(!obj.is_positive(), "{obj} isn't a connection object");
                seen.push(obj);
            }
        }
        registry.flush();
    }
}

/// A connection restored when the daemon restarts can't have answered pings while the daemon
/// was down, so it isn't expired for that: its host gets the usual time to answer one.
#[test]
fn restored_connections_are_given_time_to_answer_a_ping() {
    let dir = tempfile::tempdir().unwrap();
    let client_id = Uuid::new_v4();
    {
        let registry = open_at(dir.path());
        registry
            .new_connection(params(client_id, Some(Obj::mk_id(100)), "h"))
            .unwrap();
        registry.age_last_ping_for_test(client_id, Duration::from_secs(3600));
        registry.flush();
    }
    let registry = open_at(dir.path());
    assert!(
        registry.ping_check().is_empty(),
        "a connection restored an hour after its last ping shouldn't expire at once"
    );
    assert!(registry.connection_object_for_client(client_id).is_some());
}

// ---------------------------------------------------------------------------------------------
// Logging in again
// ---------------------------------------------------------------------------------------------

/// A connection logged in as one player and then associated with another is that player's
/// alone: it isn't left among the first player's connections.
#[test]
fn associating_a_logged_in_connection_moves_it() {
    let registry = ConnectionRegistryFactory::in_memory_only().unwrap();
    let (first, second) = (Obj::mk_id(100), Obj::mk_id(101));
    let client_id = Uuid::new_v4();
    let connection = registry
        .new_connection(params(client_id, Some(first), "h"))
        .unwrap();
    registry
        .associate_player_object(connection, second)
        .unwrap();
    assert_eq!(registry.player_object_for_client(client_id), Some(second));
    assert!(registry.client_ids_for(first).unwrap().is_empty());
    assert_eq!(registry.client_ids_for(second).unwrap(), vec![client_id]);
    assert_eq!(registry.connected_players(false), vec![second]);
}

// ---------------------------------------------------------------------------------------------
// Concurrency
// ---------------------------------------------------------------------------------------------

/// Many players' connections arriving, logging in, and leaving at once leave the registry
/// consistent, with each player's departure reported exactly once per time they left.
#[test]
fn concurrent_churn_leaves_the_registry_consistent() {
    let dir = tempfile::tempdir().unwrap();
    let registry = open_at(dir.path());
    let players: Vec<Obj> = (0..4).map(|i| Obj::mk_id(100 + i)).collect();
    let departures = std::thread::scope(|scope| {
        let workers: Vec<_> = (0..8)
            .map(|worker| {
                let registry = &registry;
                let player = players[worker % players.len()];
                scope.spawn(move || {
                    let mut departures = 0;
                    for _ in 0..200 {
                        let client_id = Uuid::new_v4();
                        let connection = registry
                            .new_connection(params(client_id, None, "h"))
                            .unwrap();
                        registry
                            .associate_player_object(connection, player)
                            .unwrap();
                        let removed = registry.remove_client_connection(client_id).unwrap();
                        let removed = removed.expect("its own connection");
                        assert_eq!(removed.connection, connection);
                        departures += usize::from(removed.disconnected_player.is_some());
                    }
                    departures
                })
            })
            .collect();
        workers
            .into_iter()
            .map(|w| w.join().unwrap())
            .sum::<usize>()
    });
    assert!(
        departures >= players.len(),
        "every player left at least once"
    );
    assert!(registry.connected_players(true).is_empty());
    for player in players {
        assert!(registry.client_ids_for(player).unwrap().is_empty());
    }
}

// ---------------------------------------------------------------------------------------------
// Expiry
// ---------------------------------------------------------------------------------------------

/// A player whose connections stop answering pings one at a time departs only with the last.
#[test]
fn expiry_reports_only_the_final_player_connection() {
    let registry = ConnectionRegistryFactory::in_memory_only().unwrap();
    let player = Obj::mk_id(2);
    let ids = [Uuid::new_v4(), Uuid::new_v4()];
    for client_id in ids {
        registry
            .new_connection(params(client_id, Some(player), "h"))
            .unwrap();
    }
    let expire = |id| registry.age_last_ping_for_test(id, Duration::from_secs(31));

    expire(ids[0]);
    let first = registry.ping_check();
    assert_eq!(first.len(), 1);
    assert_eq!(first[0].client_id, ids[0]);
    assert_eq!(first[0].disconnected_player, None);
    assert_eq!(registry.client_ids_for(player).unwrap(), vec![ids[1]]);

    expire(ids[1]);
    let last = registry.ping_check();
    assert_eq!(last.len(), 1);
    assert_eq!(last[0].disconnected_player, Some(player));
    assert!(registry.ping_check().is_empty());
    assert!(registry.connected_players(true).is_empty());
}

/// A connection that answers a ping isn't expired, however long ago it last did anything.
#[test]
fn answering_pings_keeps_an_idle_connection() {
    let registry = ConnectionRegistryFactory::in_memory_only().unwrap();
    let client_id = Uuid::new_v4();
    let connection = registry
        .new_connection(params(client_id, Some(Obj::mk_id(2)), "h"))
        .unwrap();
    registry.age_last_ping_for_test(client_id, Duration::from_secs(31));
    registry.notify_is_alive(client_id, connection).unwrap();
    assert!(registry.ping_check().is_empty());
    assert_eq!(
        registry.connection_object_for_client(client_id),
        Some(connection)
    );
}
