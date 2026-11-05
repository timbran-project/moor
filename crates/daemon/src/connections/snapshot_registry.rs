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

//! The connection registry: its state in memory, in snapshots readers take without locking,
//! and its changes written through to disk by one writer thread.
//!
//! A reader loads the current snapshot and answers from it, so it never waits for a writer, a
//! lock, or the disk, and sees one consistent state however many lookups it makes. A change
//! makes a new snapshot from the current one and swaps it in, trying again if another change
//! got there first, so changes don't wait for each other either. Then it tells the writer which
//! clients changed. The writer, which alone touches the disk, writes them as the latest snapshot
//! has them, in batches, and syncs at most once a second and whenever the registry is flushed.
//! Pings and activity change a client's own atomics, not the snapshot, and reach the disk when
//! the registry is flushed.
//!
//! What's lost in a crash is at most the last second's changes: a connection made in it is
//! unknown when the daemon restarts, so its host reconnects; one removed in it is restored and
//! expires when it doesn't answer pings. Connection ids are reserved on disk in blocks before
//! any is handed out, so none is ever handed out twice.

use std::{
    collections::{HashMap, HashSet},
    path::Path,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicI32, AtomicU64, Ordering},
    },
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime},
};

use arc_swap::ArcSwap;
use eyre::{Error, bail};
use moor_common::tasks::{ConnectionDetails, SessionError};
use moor_runtime_api::RpcMessageError;
use moor_var::{Obj, Symbol, Var, v_list, v_map, v_obj, v_sym};
use tracing::{debug, error, warn};
use uuid::Uuid;

use crate::connections::{
    FIRST_CONNECTION_ID, RemovedConnection,
    registry::{ConnectionRegistry, ConnectionStateSource, NewConnectionParams},
    state::{Client, State, Times},
    store::FjallStore,
};

/// How long a client may go without answering a ping before it's taken to be gone: about three
/// of the daemon's ping cycles.
const PING_TIMEOUT: Duration = Duration::from_secs(30);

/// How many connection ids are reserved on disk at a time. A connection waits for the disk only
/// if more than half a block connect within one sync; a restart skips at most a block, of the
/// two billion there are.
const ID_BLOCK: i32 = 1 << 16;

/// The longest the writer leaves written changes unsynced.
const SYNC_INTERVAL: Duration = Duration::from_secs(1);

/// What only changes write: the snapshot readers load, kept off the cache line of the id
/// counters that connecting threads write.
#[repr(align(64))]
struct Snapshot(ArcSwap<State>);

#[repr(align(64))]
struct Ids {
    /// The next connection id to hand out. Ids count down.
    next: AtomicI32,
    /// Ids above this are reserved on disk and may be handed out.
    reserved_above: AtomicI32,
    /// Whether the writer has been asked to reserve the next block.
    reserving: AtomicBool,
}

struct Shared {
    snapshot: Snapshot,
    ids: Ids,
    /// The next in the sequence of clients joining players.
    joins: AtomicU64,
}

enum Command {
    Changed(Vec<Uuid>),
    /// Reserve ids down to this, exclusive, and answer when it's durable.
    Reserve(i32, Option<oneshot::Sender<()>>),
    /// Write everything, timestamps too, sync, and answer.
    Flush(oneshot::Sender<()>),
    Stop,
}

struct Writer {
    commands: flume::Sender<Command>,
    thread: Option<JoinHandle<()>>,
}

pub struct SnapshotRegistry {
    shared: Arc<Shared>,
    /// None for a registry kept in memory only.
    writer: Option<Writer>,
}

impl SnapshotRegistry {
    /// A registry kept in memory only, which a restart forgets.
    pub fn in_memory() -> Self {
        Self {
            shared: Arc::new(Shared {
                snapshot: Snapshot(ArcSwap::from_pointee(State::default())),
                ids: Ids {
                    next: AtomicI32::new(FIRST_CONNECTION_ID),
                    reserved_above: AtomicI32::new(i32::MIN),
                    reserving: AtomicBool::new(false),
                },
                joins: AtomicU64::new(0),
            }),
            writer: None,
        }
    }

    /// A registry kept at `path`, with what's there.
    pub fn open(path: &Path) -> Result<Self, Error> {
        let (store, loaded) = FjallStore::open(path)?;
        let next_id = loaded.next_id;
        let reserved_above = next_id.saturating_sub(ID_BLOCK);
        store.reserve(reserved_above)?;

        // A restored client can't have answered pings while the daemon was down, so it's
        // given the usual time to answer one now.
        let now = SystemTime::now();
        let mut state = State::default();
        let mut joins = 0;
        for client in loaded.clients {
            client.times.pinged(now);
            joins = joins.max(client.joined + 1);
            state.insert(client);
        }

        let shared = Arc::new(Shared {
            snapshot: Snapshot(ArcSwap::from_pointee(state)),
            ids: Ids {
                next: AtomicI32::new(next_id),
                reserved_above: AtomicI32::new(reserved_above),
                reserving: AtomicBool::new(false),
            },
            joins: AtomicU64::new(joins),
        });
        let (commands, received) = flume::unbounded();
        let thread = std::thread::Builder::new()
            .name("moor-connections".to_string())
            .spawn({
                let shared = shared.clone();
                move || write_through(store, shared, received)
            })?;
        Ok(Self {
            shared,
            writer: Some(Writer {
                commands,
                thread: Some(thread),
            }),
        })
    }

    /// The next place in the sequence of joins.
    fn join(&self) -> u64 {
        self.shared.joins.fetch_add(1, Ordering::Relaxed)
    }

    fn state(&self) -> arc_swap::Guard<Arc<State>> {
        self.shared.snapshot.0.load()
    }

    /// Change the state with `change`, which may run more than once if other changes land
    /// meanwhile, and tell the writer about the clients it names. `change` gives no state when
    /// there's nothing to change.
    fn change<R>(
        &self,
        change: impl Fn(&State) -> Result<(Option<State>, R, Vec<Uuid>), Error>,
    ) -> Result<R, Error> {
        let mut current = self.shared.snapshot.0.load_full();
        loop {
            let (next, result, changed) = change(&current)?;
            let Some(next) = next else {
                return Ok(result);
            };
            let previous = self
                .shared
                .snapshot
                .0
                .compare_and_swap(&current, Arc::new(next));
            if Arc::ptr_eq(&previous, &current) {
                if !changed.is_empty() {
                    self.tell_writer(Command::Changed(changed));
                }
                return Ok(result);
            }
            current = arc_swap::Guard::into_inner(previous);
        }
    }

    fn tell_writer(&self, command: Command) {
        if let Some(writer) = &self.writer
            && writer.commands.send(command).is_err()
        {
            error!("The connections writer has stopped; changes aren't reaching the disk");
        }
    }

    /// A connection id no connection has had.
    fn next_connection_id(&self) -> Result<Obj, RpcMessageError> {
        let ids = &self.shared.ids;
        let id = ids
            .next
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |next| {
                next.checked_sub(1)
            })
            .map_err(|_| {
                RpcMessageError::InternalError("connection ids are exhausted".to_string())
            })?;
        let Some(writer) = &self.writer else {
            return Ok(Obj::mk_id(id));
        };
        let reserved_above = ids.reserved_above.load(Ordering::Acquire);
        if id <= reserved_above {
            // Past the reservation: wait for the writer to reserve further, which a burst of
            // more than half a block within one sync can need.
            let (done, wait) = oneshot::channel();
            let _ = writer
                .commands
                .send(Command::Reserve(id.saturating_sub(ID_BLOCK), Some(done)));
            wait.recv().map_err(|_| {
                RpcMessageError::InternalError("the connections writer has stopped".to_string())
            })?;
            if id <= ids.reserved_above.load(Ordering::Acquire) {
                return Err(RpcMessageError::InternalError(
                    "unable to reserve connection ids".to_string(),
                ));
            }
        } else if id.saturating_sub(reserved_above) < ID_BLOCK / 2
            && !ids.reserving.swap(true, Ordering::AcqRel)
        {
            let _ = writer.commands.send(Command::Reserve(
                reserved_above.saturating_sub(ID_BLOCK),
                None,
            ));
        }
        Ok(Obj::mk_id(id))
    }

    /// Remove a client if `still` holds of it as it is when it's removed, saying whether it was
    /// its player's last.
    fn remove_if(
        &self,
        client_id: Uuid,
        still: impl Fn(&Client) -> bool,
    ) -> Result<Option<RemovedConnection>, Error> {
        self.change(|state| {
            if !state.client(&client_id).is_some_and(|client| still(client)) {
                return Ok((None, None, vec![]));
            }
            let mut next = state.clone();
            let removed = next
                .remove(&client_id)
                .map(|(client, last)| RemovedConnection {
                    client_id,
                    connection: client.connection,
                    disconnected_player: if last { client.player } else { None },
                });
            Ok((Some(next), removed, vec![client_id]))
        })
    }

    fn details(client: &Client) -> ConnectionDetails {
        ConnectionDetails {
            connection_obj: client.connection,
            peer_addr: client.name(),
            idle_seconds: idle_seconds(client),
            acceptable_content_types: client.content_types.to_vec(),
        }
    }

    /// The connections of `client_id`'s session: its own, then its player's others.
    fn session_clients<'a>(state: &'a State, client_id: &Uuid) -> Vec<&'a Arc<Client>> {
        let Some(own) = state.client(client_id) else {
            return vec![];
        };
        let mut clients = vec![own];
        if let Some(player) = own.player {
            clients.extend(
                state
                    .player_clients(&player)
                    .filter(|c| c.client_id != *client_id),
            );
        }
        clients
    }
}

fn idle_seconds(client: &Client) -> f64 {
    client
        .times
        .last_activity()
        .elapsed()
        .map(|elapsed| elapsed.as_secs_f64())
        .unwrap_or(0.0)
}

fn attributes_var(attributes: &HashMap<Symbol, Var>) -> Var {
    let pairs: Vec<_> = attributes
        .iter()
        .map(|(key, value)| (v_sym(*key), value.clone()))
        .collect();
    v_map(&pairs)
}

impl Drop for SnapshotRegistry {
    fn drop(&mut self) {
        let Some(writer) = &mut self.writer else {
            return;
        };
        let _ = writer.commands.send(Command::Stop);
        if let Some(thread) = writer.thread.take()
            && thread.join().is_err()
        {
            error!("The connections writer panicked");
        }
    }
}

/// The writer: write what changed, as the latest snapshot has it, in batches.
fn write_through(store: FjallStore, shared: Arc<Shared>, commands: flume::Receiver<Command>) {
    // The times of each client as last written, to write only those that have changed.
    let mut written_times: HashMap<Uuid, (u64, u64)> = shared
        .snapshot
        .0
        .load()
        .clients
        .values()
        .map(|client| (client.client_id, client.times.raw()))
        .collect();
    let mut unsynced_since: Option<Instant> = None;
    loop {
        let wait = unsynced_since
            .map(|since| SYNC_INTERVAL.saturating_sub(since.elapsed()))
            .unwrap_or(Duration::from_secs(3600));
        let first = match commands.recv_timeout(wait) {
            Ok(command) => Some(command),
            Err(flume::RecvTimeoutError::Timeout) => None,
            Err(flume::RecvTimeoutError::Disconnected) => Some(Command::Stop),
        };
        let mut changed: HashSet<Uuid> = HashSet::new();
        let mut reserve: Option<i32> = None;
        let mut waiting: Vec<oneshot::Sender<()>> = vec![];
        let mut flushes: Vec<oneshot::Sender<()>> = vec![];
        let mut stop = false;
        for command in first.into_iter().chain(commands.try_iter()) {
            match command {
                Command::Changed(ids) => changed.extend(ids),
                Command::Reserve(to, done) => {
                    reserve = Some(reserve.map_or(to, |r| r.min(to)));
                    waiting.extend(done);
                }
                Command::Flush(done) => flushes.push(done),
                Command::Stop => stop = true,
            }
        }

        let state = shared.snapshot.0.load_full();
        if !flushes.is_empty() || stop {
            for client in state.clients.values() {
                if written_times.get(&client.client_id) != Some(&client.times.raw()) {
                    changed.insert(client.client_id);
                }
            }
        }
        if !changed.is_empty() {
            let mut puts = vec![];
            let mut deletes = vec![];
            for client_id in changed {
                match state.client(&client_id) {
                    Some(client) => {
                        written_times.insert(client_id, client.times.raw());
                        puts.push(client.clone());
                    }
                    None => {
                        written_times.remove(&client_id);
                        deletes.push(client_id);
                    }
                }
            }
            match store.write(&puts, &deletes) {
                Ok(()) => {
                    unsynced_since.get_or_insert_with(Instant::now);
                }
                Err(error) => error!(?error, "Unable to write connections"),
            }
        }
        if let Some(to) = reserve {
            let ids = &shared.ids;
            let reserved_above = ids.reserved_above.load(Ordering::Acquire);
            if to < reserved_above {
                match store.reserve(to) {
                    Ok(()) => ids.reserved_above.store(to, Ordering::Release),
                    Err(error) => error!(?error, "Unable to reserve connection ids"),
                }
            }
            ids.reserving.store(false, Ordering::Release);
            for done in waiting {
                let _ = done.send(());
            }
        }
        let due = unsynced_since.is_some_and(|since| since.elapsed() >= SYNC_INTERVAL);
        if due || !flushes.is_empty() || stop {
            match store.sync() {
                Ok(()) => unsynced_since = None,
                Err(error) => error!(?error, "Unable to sync connections"),
            }
        }
        for done in flushes {
            let _ = done.send(());
        }
        if stop {
            debug!("The connections writer is stopping");
            return;
        }
    }
}

impl ConnectionStateSource for SnapshotRegistry {
    fn connected_players(&self, include_all: bool) -> Vec<Obj> {
        let connected = self.state().connected();
        if include_all {
            connected.all.clone()
        } else {
            connected.players.clone()
        }
    }

    fn connection_name(&self, player: Obj) -> Result<String, SessionError> {
        self.connection_name_for(player)
    }

    fn connected_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        self.connected_seconds_for(player)
    }

    fn idle_seconds(&self, player: Obj) -> Result<f64, SessionError> {
        let last_activity = self.last_activity_for(player)?;
        Ok(last_activity
            .elapsed()
            .map(|elapsed| elapsed.as_secs_f64())
            .unwrap_or(0.0))
    }

    fn connections_for(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<Obj>, SessionError> {
        let state = self.state();
        Ok(match player {
            Some(player) => state
                .player_clients(&player)
                .map(|client| client.connection)
                .collect(),
            None => Self::session_clients(&state, &client_id)
                .into_iter()
                .map(|client| client.connection)
                .collect(),
        })
    }

    fn connection_details(
        &self,
        client_id: Uuid,
        player: Option<Obj>,
    ) -> Result<Vec<ConnectionDetails>, SessionError> {
        let state = self.state();
        Ok(match player {
            Some(player) => state
                .player_clients(&player)
                .map(|client| Self::details(client))
                .collect(),
            None => Self::session_clients(&state, &client_id)
                .into_iter()
                .map(|client| Self::details(client))
                .collect(),
        })
    }

    fn connection_attributes(&self, obj: Obj) -> Result<Var, SessionError> {
        let state = self.state();
        if !obj.is_positive() {
            let client = state
                .client_of(&obj)
                .ok_or(SessionError::NoConnectionForPlayer(obj))?;
            return Ok(attributes_var(&client.attributes));
        }
        Ok(v_list(
            &state
                .player_clients(&obj)
                .map(|client| {
                    v_list(&[v_obj(client.connection), attributes_var(&client.attributes)])
                })
                .collect::<Vec<_>>(),
        ))
    }
}

impl ConnectionRegistry for SnapshotRegistry {
    fn associate_player_object(&self, connection_obj: Obj, player_obj: Obj) -> Result<(), Error> {
        self.change(|state| {
            let mut next = state.clone();
            let Some(client) = state.client_of(&connection_obj) else {
                bail!("No connection found for {connection_obj:?}");
            };
            let client_id = client.client_id;
            let rejoins = client.player != Some(player_obj);
            let joined = self.join();
            next.update(&client_id, |client| {
                if rejoins {
                    client.joined = joined;
                }
                client.player = Some(player_obj);
                client.history = Some(player_obj);
            });
            Ok((Some(next), (), vec![client_id]))
        })
    }

    fn switch_player_for_connection(
        &self,
        connection_obj: Obj,
        new_player: Obj,
        preserve_history: bool,
    ) -> Result<Vec<Uuid>, Error> {
        self.change(|state| {
            let mut next = state.clone();
            let Some(client) = state.client_of(&connection_obj) else {
                bail!("No connection records found for {connection_obj:?}");
            };
            let client_id = client.client_id;
            let previous = client.player;
            let joined = self.join();
            next.update(&client_id, |client| {
                client.joined = joined;
                client.player = Some(new_player);
                if !preserve_history {
                    client.history = Some(new_player);
                } else if client.history.is_none() {
                    client.history = previous;
                }
            });
            if previous == Some(new_player) {
                next.rejoin(new_player, client_id);
            }
            Ok((Some(next), vec![client_id], vec![client_id]))
        })
    }

    fn reserve_connection_id(&self) -> Result<Obj, RpcMessageError> {
        self.next_connection_id()
    }

    fn new_connection(&self, params: NewConnectionParams) -> Result<Obj, RpcMessageError> {
        let NewConnectionParams {
            client_id,
            hostname,
            local_port,
            remote_port,
            player,
            acceptable_content_types,
            connection_attributes,
        } = params;
        let connection = self.next_connection_id()?;
        let now = SystemTime::now();
        let client = Client {
            client_id,
            connection,
            player,
            history: player,
            joined: self.join(),
            hostname: hostname.into(),
            local_port,
            remote_port,
            connected_time: now,
            content_types: acceptable_content_types
                .unwrap_or_else(|| vec![Symbol::mk("text_plain")])
                .into(),
            attributes: Arc::new(connection_attributes.unwrap_or_default()),
            times: Arc::new(Times::new(now, now)),
        };
        self.change(|state| {
            let mut next = state.clone();
            next.insert(client.clone());
            Ok((Some(next), (), vec![client_id]))
        })
        .map_err(|error| RpcMessageError::InternalError(error.to_string()))?;
        debug!(?client_id, %connection, "New connection");
        Ok(connection)
    }

    fn record_client_activity(&self, client_id: Uuid, _connobj: Obj) -> Result<(), Error> {
        if let Some(client) = self.state().client(&client_id) {
            client.times.touch(SystemTime::now());
        }
        Ok(())
    }

    fn notify_is_alive(&self, client_id: Uuid, _connection: Obj) -> Result<(), Error> {
        if let Some(client) = self.state().client(&client_id) {
            client.times.pinged(SystemTime::now());
        }
        Ok(())
    }

    fn ping_check(&self) -> Vec<RemovedConnection> {
        let now = SystemTime::now();
        let expired: Vec<Uuid> = self
            .state()
            .clients
            .values()
            .filter(|client| {
                now.duration_since(client.times.last_ping())
                    .is_ok_and(|since| since >= PING_TIMEOUT)
            })
            .map(|client| {
                warn!(
                    client_id = ?client.client_id,
                    connection = %client.connection,
                    hostname = %client.hostname,
                    local_port = client.local_port,
                    "Removing connection due to ping timeout"
                );
                client.client_id
            })
            .collect();
        let still_expired = |client: &Client| {
            now.duration_since(client.times.last_ping())
                .is_ok_and(|since| since >= PING_TIMEOUT)
        };
        expired
            .into_iter()
            .filter_map(|client_id| match self.remove_if(client_id, still_expired) {
                Ok(removed) => removed,
                Err(error) => {
                    warn!(?client_id, ?error, "Unable to remove expired connection");
                    None
                }
            })
            .collect()
    }

    #[cfg(test)]
    fn age_last_ping_for_test(&self, client_id: Uuid, age: Duration) {
        self.state()
            .client(&client_id)
            .expect("test connection has no timestamp")
            .times
            .set_last_ping(SystemTime::now() - age);
    }

    fn last_activity_for(&self, connection: Obj) -> Result<SystemTime, SessionError> {
        self.state()
            .clients_of(&connection)
            .into_iter()
            .map(|client| client.times.last_activity())
            .max()
            .ok_or(SessionError::NoConnectionForPlayer(connection))
    }

    fn connection_name_for(&self, obj: Obj) -> Result<String, SessionError> {
        self.state()
            .clients_of(&obj)
            .first()
            .map(|client| client.name())
            .ok_or(SessionError::NoConnectionForPlayer(obj))
    }

    fn connected_seconds_for(&self, obj: Obj) -> Result<f64, SessionError> {
        let state = self.state();
        let clients = state.clients_of(&obj);
        if clients.is_empty() {
            return Err(SessionError::NoConnectionForPlayer(obj));
        }
        Ok(clients
            .iter()
            .map(|client| {
                client
                    .connected_time
                    .elapsed()
                    .unwrap_or_default()
                    .as_secs_f64()
            })
            .sum())
    }

    fn client_ids_for(&self, obj: Obj) -> Result<Vec<Uuid>, SessionError> {
        let state = self.state();
        if let Some(client_id) = state.by_connection.get(&obj) {
            return Ok(vec![*client_id]);
        }
        Ok(state
            .by_player
            .get(&obj)
            .map(|clients| clients.to_vec())
            .unwrap_or_default())
    }

    fn connections(&self) -> Vec<Obj> {
        self.state().connected().all.clone()
    }

    fn connection_object_for_client(&self, client_id: Uuid) -> Option<Obj> {
        self.state()
            .client(&client_id)
            .map(|client| client.connection)
    }

    fn player_object_for_client(&self, client_id: Uuid) -> Option<Obj> {
        self.state()
            .client(&client_id)
            .and_then(|client| client.player)
    }

    fn history_object_for_client(&self, client_id: Uuid) -> Option<Obj> {
        self.state()
            .client(&client_id)
            .and_then(|client| client.history)
    }

    fn remove_client_connection(
        &self,
        client_id: Uuid,
    ) -> Result<Option<RemovedConnection>, Error> {
        self.remove_if(client_id, |_| true)
    }

    fn acceptable_content_types_for(&self, obj: Obj) -> Result<Vec<Symbol>, SessionError> {
        self.state()
            .clients_of(&obj)
            .first()
            .map(|client| client.content_types.to_vec())
            .ok_or(SessionError::NoConnectionForPlayer(obj))
    }

    fn set_client_attribute(
        &self,
        client_id: Uuid,
        key: Symbol,
        value: Option<Var>,
    ) -> Result<(), RpcMessageError> {
        self.change(|state| {
            let mut next = state.clone();
            if !next.update(&client_id, |client| {
                let mut attributes = HashMap::clone(&client.attributes);
                match &value {
                    Some(value) => {
                        attributes.insert(key, value.clone());
                    }
                    None => {
                        attributes.remove(&key);
                    }
                }
                client.attributes = Arc::new(attributes);
            }) {
                bail!("no connection");
            }
            Ok((Some(next), (), vec![client_id]))
        })
        .map_err(|_| RpcMessageError::NoConnection)
    }

    fn get_client_attributes(&self, obj: Obj) -> Result<HashMap<Symbol, Var>, SessionError> {
        let state = self.state();
        let client = if !obj.is_positive() {
            state.client_of(&obj)
        } else {
            state.player_clients(&obj).next()
        };
        client
            .map(|client| HashMap::clone(&client.attributes))
            .ok_or(SessionError::NoConnectionForPlayer(obj))
    }

    fn flush(&self) {
        let Some(writer) = &self.writer else {
            return;
        };
        let (done, wait) = oneshot::channel();
        if writer.commands.send(Command::Flush(done)).is_err() || wait.recv().is_err() {
            error!("The connections writer has stopped; unable to flush connections");
        }
    }
}
