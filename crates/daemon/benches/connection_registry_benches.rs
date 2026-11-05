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

//! The connection registry under the daemon's own load: the lookups every event and every
//! request makes, the writes connecting, logging in and leaving make, and both at once.
//!
//! The registry is opened on disk, as the daemon opens it, under `MOOR_BENCH_DIR`, or the
//! workspace's `target/bench-connections` by default. A temporary directory is often on tmpfs,
//! where syncing costs nothing and a slow disk can't show. To see one, preload
//! `benches/slow_disk.c`, which says how.
//!
//! Readers in the concurrent scenarios count the reads that took over a millisecond and over ten:
//! a registry whose readers wait on its writers, or its writers on the disk, shows there first.

use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use micromeasure::{
    BenchContext, BenchmarkMainOptions, BenchmarkRuntimeOptions, ConcurrentBenchContext,
    ConcurrentBenchControl, ConcurrentWorker, ConcurrentWorkerResult, Throughput, benchmark_main,
    black_box,
};
use moor_daemon::connections::{
    ConnectionRegistry, ConnectionRegistryFactory, ConnectionStateSource, NewConnectionParams,
};
use moor_var::{Obj, Symbol, v_str};
use tempfile::TempDir;
use uuid::Uuid;

/// The daemon's allocator, since readers allocate their answers.
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

/// Players connected when a scenario starts, each with two connections, as a player with a game
/// client and a web client has.
const PLAYERS: usize = 500;
const CONNECTIONS_PER_PLAYER: usize = 2;

/// A registry on disk, with `PLAYERS` players connected.
struct Populated {
    registry: Arc<dyn ConnectionRegistry>,
    players: Vec<Obj>,
    /// Every client, with its player.
    clients: Vec<(Uuid, Obj)>,
    /// Dropped after the registry, which it holds.
    _dir: TempDir,
}

fn bench_dir() -> PathBuf {
    std::env::var_os("MOOR_BENCH_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/bench-connections")
        })
}

fn params(client_id: Uuid, player: Option<Obj>) -> NewConnectionParams {
    NewConnectionParams {
        client_id,
        hostname: "bench.host".to_string(),
        local_port: 7777,
        remote_port: 40000,
        player,
        acceptable_content_types: Some(vec![Symbol::mk("text_djot"), Symbol::mk("text_plain")]),
        connection_attributes: None,
    }
}

impl Populated {
    fn open() -> Self {
        let root = bench_dir();
        std::fs::create_dir_all(&root).expect("bench directory");
        let dir = tempfile::tempdir_in(&root).expect("bench registry directory");
        let registry = ConnectionRegistryFactory::with_fjall_persistence(Some(dir.path()))
            .expect("open registry");
        let players: Vec<Obj> = (0..PLAYERS).map(|i| Obj::mk_id(1000 + i as i32)).collect();
        let mut clients = Vec::with_capacity(PLAYERS * CONNECTIONS_PER_PLAYER);
        for &player in &players {
            for _ in 0..CONNECTIONS_PER_PLAYER {
                let client_id = Uuid::new_v4();
                registry
                    .new_connection(params(client_id, Some(player)))
                    .expect("connect");
                clients.push((client_id, player));
            }
        }
        // Measure the registry at rest: what connecting everyone wrote is on disk, and
        // nothing is still being written behind the readers' backs.
        registry.flush();
        Self {
            registry,
            players,
            clients,
            _dir: dir,
        }
    }

    fn state(&self) -> &dyn ConnectionStateSource {
        self.registry.as_ref()
    }
}

impl BenchContext for Populated {
    fn prepare(_num_chunks: usize) -> Self {
        Self::open()
    }
}

impl ConcurrentBenchContext for Populated {
    fn prepare(_num_threads: usize) -> Self {
        Self::open()
    }
}

// ---------------------------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------------------------

/// What publishing each narrative event does: the clients of the player it's addressed to.
fn event_recipients(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let player = ctx.players[(chunk_num * chunk_size + i) % ctx.players.len()];
        black_box(ctx.registry.client_ids_for(player).ok());
    }
}

/// What authenticating each client request does: its connection.
fn request_connection(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let (client_id, _) = ctx.clients[(chunk_num * chunk_size + i) % ctx.clients.len()];
        black_box(ctx.registry.connection_object_for_client(client_id));
    }
}

/// What `connection()`, and Cowbell's `tell` and `inform_*`, do from a player's session: the
/// session's connections, with each one's name, idle time and content types.
fn session_connection_details(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let (client_id, _) = ctx.clients[(chunk_num * chunk_size + i) % ctx.clients.len()];
        black_box(ctx.state().connection_details(client_id, None).ok());
    }
}

/// What `connections(player)` does.
fn player_connections(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let (client_id, player) = ctx.clients[(chunk_num * chunk_size + i) % ctx.clients.len()];
        black_box(ctx.state().connections_for(client_id, Some(player)).ok());
    }
}

/// What `connection_options()` and the like do for a player.
fn player_connection_attributes(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let player = ctx.players[(chunk_num * chunk_size + i) % ctx.players.len()];
        black_box(ctx.state().connection_attributes(player).ok());
    }
}

/// What `connected_players()` does.
fn connected_players(ctx: &mut Populated, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(ctx.state().connected_players(false));
    }
}

// ---------------------------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------------------------

/// What each ping answered does.
fn ping_answered(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let (client_id, _) = ctx.clients[(chunk_num * chunk_size + i) % ctx.clients.len()];
        black_box(ctx.registry.notify_is_alive(client_id, Obj::mk_id(-1)).ok());
    }
}

/// What each command typed does.
fn activity(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let (client_id, _) = ctx.clients[(chunk_num * chunk_size + i) % ctx.clients.len()];
        black_box(
            ctx.registry
                .record_client_activity(client_id, Obj::mk_id(-1))
                .ok(),
        );
    }
}

/// What a connection option being set does.
fn set_attribute(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    let key = Symbol::mk("bench_option");
    for i in 0..chunk_size {
        let n = chunk_num * chunk_size + i;
        let (client_id, _) = ctx.clients[n % ctx.clients.len()];
        black_box(
            ctx.registry
                .set_client_attribute(client_id, key, Some(v_str(&n.to_string())))
                .ok(),
        );
    }
}

/// A player connecting, logging in, and leaving.
fn connect_login_leave(ctx: &mut Populated, chunk_size: usize, chunk_num: usize) {
    for i in 0..chunk_size {
        let player = ctx.players[(chunk_num * chunk_size + i) % ctx.players.len()];
        churn_once(ctx.registry.as_ref(), player);
    }
}

fn churn_once(registry: &dyn ConnectionRegistry, player: Obj) {
    let client_id = Uuid::new_v4();
    let connection = registry
        .new_connection(params(client_id, None))
        .expect("connect");
    registry
        .associate_player_object(connection, player)
        .expect("log in");
    black_box(registry.remove_client_connection(client_id).ok());
}

/// A connection object reserved for a captured call's transient connection.
fn reserve_connection_id(ctx: &mut Populated, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        black_box(ctx.registry.reserve_connection_id().ok());
    }
}

/// The periodic flush, with every client's timestamps changed since the last.
fn flush_after_pings(ctx: &mut Populated, chunk_size: usize, _chunk_num: usize) {
    for _ in 0..chunk_size {
        for &(client_id, _) in &ctx.clients {
            let _ = ctx.registry.notify_is_alive(client_id, Obj::mk_id(-1));
        }
        ctx.registry.flush();
    }
}

// ---------------------------------------------------------------------------------------------
// Concurrent scenarios
// ---------------------------------------------------------------------------------------------

/// Reads that took over a millisecond, and over ten.
#[derive(Default)]
struct Stalls {
    over_1ms: u64,
    over_10ms: u64,
}

impl Stalls {
    fn time<T>(&mut self, read: impl FnOnce() -> T) -> T {
        let started = Instant::now();
        let value = read();
        let took = started.elapsed();
        if took > Duration::from_millis(1) {
            self.over_1ms += 1;
        }
        if took > Duration::from_millis(10) {
            self.over_10ms += 1;
        }
        value
    }

    fn report(self, operations: u64) -> ConcurrentWorkerResult {
        ConcurrentWorkerResult::operations(operations)
            .with_counter("reads_over_1ms", self.over_1ms)
            .with_counter("reads_over_10ms", self.over_10ms)
    }
}

fn publishing_reader(ctx: &Populated, control: &ConcurrentBenchControl) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    let mut stalls = Stalls::default();
    let stride = control.thread_index() * 7919;
    while !control.should_stop() {
        let player = ctx.players[(operations as usize + stride) % ctx.players.len()];
        black_box(stalls.time(|| ctx.registry.client_ids_for(player).ok()));
        operations += 1;
    }
    stalls.report(operations)
}

fn session_reader(ctx: &Populated, control: &ConcurrentBenchControl) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    let mut stalls = Stalls::default();
    let stride = control.thread_index() * 7919;
    while !control.should_stop() {
        let (client_id, _) = ctx.clients[(operations as usize + stride) % ctx.clients.len()];
        black_box(stalls.time(|| ctx.state().connection_details(client_id, None).ok()));
        operations += 1;
    }
    stalls.report(operations)
}

fn churning_writer(ctx: &Populated, control: &ConcurrentBenchControl) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        churn_once(
            ctx.registry.as_ref(),
            ctx.players[operations as usize % ctx.players.len()],
        );
        operations += 1;
    }
    ConcurrentWorkerResult::operations(operations)
}

fn pinger(ctx: &Populated, control: &ConcurrentBenchControl) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        let (client_id, _) = ctx.clients[operations as usize % ctx.clients.len()];
        let _ = ctx.registry.notify_is_alive(client_id, Obj::mk_id(-1));
        operations += 1;
    }
    ConcurrentWorkerResult::operations(operations)
}

fn flusher(ctx: &Populated, control: &ConcurrentBenchControl) -> ConcurrentWorkerResult {
    let mut operations = 0_u64;
    while !control.should_stop() {
        ctx.registry.flush();
        operations += 1;
    }
    ConcurrentWorkerResult::operations(operations)
}

benchmark_main!(
    BenchmarkMainOptions {
        filter_help: Some(
            "all, read, write, concurrent, or any benchmark name substring".to_string()
        ),
        runtime: BenchmarkRuntimeOptions {
            warm_up_duration: Duration::from_millis(250),
            benchmark_duration: Duration::from_secs(1),
            min_samples: 8,
            max_samples: 24,
        },
        ..BenchmarkMainOptions::default()
    },
    |runner| {
        runner.group::<Populated>("Connection Registry Reads", |g| {
            let g = g.throughput(Throughput::per_operation(1, "lookups"));
            g.bench("read_event_recipients", event_recipients);
            g.bench("read_request_connection", request_connection);
            g.bench(
                "read_session_connection_details",
                session_connection_details,
            );
            g.bench("read_player_connections", player_connections);
            g.bench(
                "read_player_connection_attributes",
                player_connection_attributes,
            );
            g.bench("read_connected_players", connected_players);
        });

        runner.group::<Populated>("Connection Registry Writes", |g| {
            let g = g.throughput(Throughput::per_operation(1, "writes"));
            g.bench("write_ping_answered", ping_answered);
            g.bench("write_activity", activity);
            g.bench("write_set_attribute", set_attribute);
            g.bench("write_connect_login_leave", connect_login_leave);
            g.bench("write_reserve_connection_id", reserve_connection_id);
        });

        runner.group::<Populated>("Connection Registry Flush", |g| {
            g.throughput(Throughput::per_operation(1, "flushes"))
                .bench("write_flush_after_pings", flush_after_pings);
        });

        let max_threads = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1)
            .min(8);
        for &readers in &[2usize, 4, 7] {
            if readers + 1 > max_threads {
                continue;
            }
            let publishing_vs_churn = [
                ConcurrentWorker {
                    name: "publishing_reader",
                    threads: readers,
                    run: publishing_reader,
                },
                ConcurrentWorker {
                    name: "churning_writer",
                    threads: 1,
                    run: churning_writer,
                },
            ];
            let sessions_vs_pings = [
                ConcurrentWorker {
                    name: "session_reader",
                    threads: readers,
                    run: session_reader,
                },
                ConcurrentWorker {
                    name: "pinger",
                    threads: 1,
                    run: pinger,
                },
            ];
            // Readers alone: the stalls the machine and the harness cause, which the other
            // scenarios' stalls are to be read against.
            let publishing_alone = [ConcurrentWorker {
                name: "publishing_reader",
                threads: readers,
                run: publishing_reader,
            }];
            let sessions_alone = [ConcurrentWorker {
                name: "session_reader",
                threads: readers,
                run: session_reader,
            }];
            let sessions_vs_flush = [
                ConcurrentWorker {
                    name: "session_reader",
                    threads: readers,
                    run: session_reader,
                },
                ConcurrentWorker {
                    name: "flusher",
                    threads: 1,
                    run: flusher,
                },
            ];
            runner.concurrent_group::<Populated>("Connection Registry Concurrent", |g| {
                let g = g
                    .sample_duration(Duration::from_millis(200))
                    .throughput(Throughput::per_operation(1, "ops"));
                g.bench(
                    &format!("concurrent_publishing_alone_{readers}r"),
                    &publishing_alone,
                );
                g.bench(
                    &format!("concurrent_sessions_alone_{readers}r"),
                    &sessions_alone,
                );
                g.bench(
                    &format!("concurrent_publishing_vs_churn_{readers}r"),
                    &publishing_vs_churn,
                );
                g.bench(
                    &format!("concurrent_sessions_vs_pings_{readers}r"),
                    &sessions_vs_pings,
                );
                g.bench(
                    &format!("concurrent_sessions_vs_flush_{readers}r"),
                    &sessions_vs_flush,
                );
            });
        }
    }
);
