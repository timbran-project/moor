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

//! The registry's state: an immutable snapshot of every client, its connection and its player,
//! replaced whole by each change, so that a reader sees one consistent state without locking and
//! a writer never waits for readers.
//!
//! Snapshots share structure: the maps are persistent, so a change copies only the path to what
//! it changes. A client's activity and ping times change far more often than anything else, so
//! they aren't in the snapshot: each client holds its own pair of atomics, on a cache line of
//! their own, which every version of the client shares.

use std::{
    collections::HashMap,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use moor_var::{Obj, Symbol, Var};
use uuid::Uuid;

/// A client's last activity and last answered ping, as nanoseconds since the epoch.
///
/// Each is on a cache line of its own: pings, which come for every client every few seconds,
/// write only `last_ping`, and readers working out how long a client has been idle read only
/// `last_activity`, so neither waits on the other, or on another client's.
#[derive(Debug)]
pub(crate) struct Times {
    last_activity: Line,
    last_ping: Line,
}

#[repr(align(64))]
#[derive(Debug)]
struct Line(AtomicU64);

pub(crate) fn nanos(time: SystemTime) -> u64 {
    time.duration_since(UNIX_EPOCH)
        .map(|since| since.as_nanos().min(u128::from(u64::MAX)) as u64)
        .unwrap_or(0)
}

pub(crate) fn time(nanos: u64) -> SystemTime {
    UNIX_EPOCH + Duration::from_nanos(nanos)
}

impl Times {
    pub(crate) fn new(last_activity: SystemTime, last_ping: SystemTime) -> Self {
        Self {
            last_activity: Line(AtomicU64::new(nanos(last_activity))),
            last_ping: Line(AtomicU64::new(nanos(last_ping))),
        }
    }

    pub(crate) fn last_activity(&self) -> SystemTime {
        time(self.last_activity.0.load(Ordering::Relaxed))
    }

    pub(crate) fn last_ping(&self) -> SystemTime {
        time(self.last_ping.0.load(Ordering::Relaxed))
    }

    /// Both times, as they'd be persisted.
    pub(crate) fn raw(&self) -> (u64, u64) {
        (
            self.last_activity.0.load(Ordering::Relaxed),
            self.last_ping.0.load(Ordering::Relaxed),
        )
    }

    /// The client did something, which is also proof it's alive.
    pub(crate) fn touch(&self, now: SystemTime) {
        let now = nanos(now);
        self.last_activity.0.store(now, Ordering::Relaxed);
        self.last_ping.0.store(now, Ordering::Relaxed);
    }

    /// The client answered a ping.
    pub(crate) fn pinged(&self, now: SystemTime) {
        self.last_ping.0.store(nanos(now), Ordering::Relaxed);
    }

    #[cfg(test)]
    pub(crate) fn set_last_ping(&self, at: SystemTime) {
        self.last_ping.0.store(nanos(at), Ordering::Relaxed);
    }
}

/// One client, as of one snapshot. A change makes a new `Client`, sharing its `times`.
#[derive(Debug, Clone)]
pub(crate) struct Client {
    pub(crate) client_id: Uuid,
    pub(crate) connection: Obj,
    pub(crate) player: Option<Obj>,
    pub(crate) history: Option<Obj>,
    /// When it joined its player, in the registry's sequence of joins: a player's clients are in
    /// this order, which persists with them.
    pub(crate) joined: u64,
    pub(crate) hostname: Arc<str>,
    pub(crate) local_port: u16,
    pub(crate) remote_port: u16,
    pub(crate) connected_time: SystemTime,
    pub(crate) content_types: Arc<[Symbol]>,
    pub(crate) attributes: Arc<HashMap<Symbol, Var>>,
    pub(crate) times: Arc<Times>,
}

impl Client {
    /// What `connection_name()` says of it.
    pub(crate) fn name(&self) -> String {
        format!(
            "port {} from {}, port {}",
            self.local_port, self.hostname, self.remote_port
        )
    }
}

/// The objects connected, in order, for `connected_players()`: players, and players with
/// connections.
#[derive(Debug, Default)]
pub(crate) struct Connected {
    pub(crate) players: Vec<Obj>,
    pub(crate) all: Vec<Obj>,
}

/// Every client, indexed by its connection and its player.
#[derive(Debug, Default)]
pub(crate) struct State {
    pub(crate) clients: imbl::HashMap<Uuid, Arc<Client>>,
    pub(crate) by_connection: imbl::HashMap<Obj, Uuid>,
    /// Each player's clients, in the order they joined the player.
    pub(crate) by_player: imbl::HashMap<Obj, Arc<[Uuid]>>,
    /// `connected_players()`, worked out the first time it's asked of this snapshot.
    connected: OnceLock<Arc<Connected>>,
}

impl Clone for State {
    fn clone(&self) -> Self {
        Self {
            clients: self.clients.clone(),
            by_connection: self.by_connection.clone(),
            by_player: self.by_player.clone(),
            connected: OnceLock::new(),
        }
    }
}

impl State {
    pub(crate) fn client(&self, client_id: &Uuid) -> Option<&Arc<Client>> {
        self.clients.get(client_id)
    }

    pub(crate) fn client_of(&self, connection: &Obj) -> Option<&Arc<Client>> {
        self.by_connection
            .get(connection)
            .and_then(|id| self.clients.get(id))
    }

    /// The clients of `obj`: the one whose connection it is, or a player's.
    pub(crate) fn clients_of(&self, obj: &Obj) -> Vec<&Arc<Client>> {
        if let Some(client) = self.client_of(obj) {
            return vec![client];
        }
        self.player_clients(obj).collect()
    }

    pub(crate) fn player_clients(&self, player: &Obj) -> impl Iterator<Item = &Arc<Client>> {
        self.by_player
            .get(player)
            .into_iter()
            .flat_map(|ids| ids.iter())
            .filter_map(|id| self.clients.get(id))
    }

    pub(crate) fn connected(&self) -> Arc<Connected> {
        self.connected
            .get_or_init(|| {
                let mut players: Vec<Obj> = self.by_player.keys().copied().collect();
                players.sort_unstable();
                let mut all: Vec<Obj> = self.by_connection.keys().copied().collect();
                all.extend_from_slice(&players);
                all.sort_unstable();
                all.dedup();
                Arc::new(Connected { players, all })
            })
            .clone()
    }

    /// Add `client`, or replace the client with its id.
    pub(crate) fn insert(&mut self, client: Client) {
        self.remove(&client.client_id);
        self.by_connection
            .insert(client.connection, client.client_id);
        if let Some(player) = client.player {
            self.join(player, client.client_id);
        }
        self.clients.insert(client.client_id, Arc::new(client));
    }

    /// Remove a client, returning it and whether it was its player's last.
    pub(crate) fn remove(&mut self, client_id: &Uuid) -> Option<(Arc<Client>, bool)> {
        let client = self.clients.remove(client_id)?;
        if self.by_connection.get(&client.connection) == Some(client_id) {
            self.by_connection.remove(&client.connection);
        }
        let last = client
            .player
            .is_some_and(|player| self.leave(player, client_id));
        Some((client, last))
    }

    /// Replace a client's version, with its player and history as `change` makes them, keeping
    /// its place among its player's clients unless its player changes.
    pub(crate) fn update(&mut self, client_id: &Uuid, change: impl FnOnce(&mut Client)) -> bool {
        let Some(current) = self.clients.get(client_id) else {
            return false;
        };
        let mut next = Client::clone(current);
        change(&mut next);
        let before = current.player;
        if before != next.player {
            if let Some(player) = before {
                self.leave(player, client_id);
            }
            if let Some(player) = next.player {
                self.join(player, *client_id);
            }
        }
        self.clients.insert(*client_id, Arc::new(next));
        true
    }

    /// Put a client last among its player's, as switching to the player it's already on does.
    pub(crate) fn rejoin(&mut self, player: Obj, client_id: Uuid) {
        self.leave(player, &client_id);
        self.join(player, client_id);
    }

    fn join(&mut self, player: Obj, client_id: Uuid) {
        let clients: Arc<[Uuid]> = match self.by_player.get(&player) {
            Some(clients) if clients.contains(&client_id) => return,
            Some(clients) => clients.iter().copied().chain([client_id]).collect(),
            None => Arc::from([client_id]),
        };
        self.by_player.insert(player, clients);
    }

    /// Take a client from its player's, returning whether none are left.
    fn leave(&mut self, player: Obj, client_id: &Uuid) -> bool {
        let Some(clients) = self.by_player.get(&player) else {
            return false;
        };
        let rest: Arc<[Uuid]> = clients
            .iter()
            .copied()
            .filter(|id| id != client_id)
            .collect();
        if rest.is_empty() {
            self.by_player.remove(&player);
            return true;
        }
        self.by_player.insert(player, rest);
        false
    }
}
