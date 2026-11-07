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

//! Elle list-append workload.
//!
//! Each transaction is a short sequence of reads and appends over several list properties. Keys
//! rotate: a key takes a bounded number of appends, then a fresh key replaces it, so lists stay
//! short. The history is written as EDN for elle-cli's `list-append` model.
//!
//! The target decides how a transaction runs:
//!
//! - `db`: one `moor_db` transaction, retried here on a commit conflict.
//! - `scheduler`: one MOO eval task on an in-process scheduler, which retries conflicts itself.

use clap::Parser;
use clap_derive::{Parser, ValueEnum};
use edn_format::{Keyword, Value};
use moor_common::{
    model::{CommitResult, ObjAttrs, ObjFlag, ObjectKind, TaskPermissions, WorldStateSource},
    util::BitEnum,
};
use moor_db::{Database, TxDB};
use moor_kernel::{
    SchedulerClient,
    config::{Config, FeaturesConfig},
    tasks::{NoopTasksDb, SchedulerOp, TaskNotification, sched_counters, scheduler::Scheduler},
};
use moor_model_checker::{
    DirectSession, DirectSessionFactory, NoopSystemControl,
    elle_common::{self, EdnEvent},
};
use moor_var::{NOTHING, Obj, Symbol, Var, v_int, v_list};
use rand::{Rng, RngExt};
use std::{
    fmt::Write as _,
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicI64, AtomicUsize, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Copy, Debug, ValueEnum)]
enum Target {
    /// One `moor_db` transaction per Elle transaction.
    Db,
    /// One MOO eval task on an in-process scheduler per Elle transaction.
    Scheduler,
}

#[derive(Clone, Parser, Debug)]
struct Args {
    #[arg(
        long,
        value_enum,
        help = "What runs each transaction",
        default_value = "db"
    )]
    target: Target,

    #[arg(long, help = "Database path; a temporary directory if not given")]
    db_path: Option<PathBuf>,

    #[arg(
        long,
        help = "Number of keys open for reads and appends at once",
        default_value = "5"
    )]
    num_active_keys: usize,

    #[arg(
        long,
        help = "Appends a key takes before a fresh key replaces it",
        default_value = "32"
    )]
    max_writes_per_key: usize,

    #[arg(long, help = "Maximum operations per transaction", default_value = "4")]
    max_txn_length: usize,

    #[arg(
        long,
        help = "Chance that an operation is a read",
        default_value = "0.5"
    )]
    read_fraction: f64,

    #[arg(long, help = "Number of concurrent processes", default_value = "20")]
    num_concurrent_workloads: usize,

    #[arg(long, help = "Transactions per process", default_value = "1000")]
    num_workload_iterations: usize,

    #[arg(
        long,
        help = "Commit attempts before a db-target transaction is recorded as failed",
        default_value = "100"
    )]
    max_retries: usize,

    #[arg(
        long,
        help = "File to write the EDN history to",
        default_value = "workload.edn"
    )]
    output_file: PathBuf,
}

#[derive(Clone, Copy, Debug)]
enum MicroOp {
    Read(usize),
    Append(usize, i64),
}

/// What a read returned, for each operation; `None` for appends.
type Reads = Vec<Option<Vec<i64>>>;

enum Outcome {
    /// The transaction committed, with these reads.
    Committed(Reads),
    /// The transaction did not commit.
    Failed,
}

/// Runs one transaction's operations.
trait Executor: Send + Sync {
    fn execute(&self, ops: &[MicroOp]) -> Result<Outcome, eyre::Error>;

    /// Commit conflicts retried so far, if the executor sees them.
    fn retries(&self) -> Option<usize> {
        None
    }
}

/// The keys open for operations, and the appends each has been given.
struct KeyRotation {
    active: Vec<(usize, usize)>,
    next_key: usize,
    max_writes: usize,
    pool_size: usize,
}

impl KeyRotation {
    fn new(num_active: usize, max_writes: usize, pool_size: usize) -> Self {
        Self {
            active: (0..num_active).map(|key| (key, 0)).collect(),
            next_key: num_active,
            max_writes,
            pool_size,
        }
    }

    /// Choose an active key, favouring the first slots so a few keys see most of the contention.
    fn choose(&self, rng: &mut impl Rng) -> usize {
        let mut slot = 0;
        while slot + 1 < self.active.len() && rng.random_bool(0.5) {
            slot += 1;
        }
        slot
    }

    fn read(&self, rng: &mut impl Rng) -> usize {
        self.active[self.choose(rng)].0
    }

    /// Choose a key for an append and count it, retiring the key once it is full.
    fn append(&mut self, rng: &mut impl Rng) -> Result<usize, eyre::Error> {
        let slot = self.choose(rng);
        let (key, writes) = &mut self.active[slot];
        let key = *key;
        *writes += 1;
        if *writes >= self.max_writes {
            if self.next_key >= self.pool_size {
                return Err(eyre::eyre!("key pool of {} exhausted", self.pool_size));
            }
            self.active[slot] = (self.next_key, 0);
            self.next_key += 1;
        }
        Ok(key)
    }
}

struct Generator {
    keys: Mutex<KeyRotation>,
    next_value: AtomicI64,
    max_txn_length: usize,
    read_fraction: f64,
}

impl Generator {
    fn generate(&self, rng: &mut impl Rng) -> Result<Vec<MicroOp>, eyre::Error> {
        let length = rng.random_range(1..=self.max_txn_length);
        let mut keys = self.keys.lock().unwrap();
        (0..length)
            .map(|_| {
                if rng.random_bool(self.read_fraction) {
                    Ok(MicroOp::Read(keys.read(rng)))
                } else {
                    let value = self.next_value.fetch_add(1, Ordering::Relaxed);
                    Ok(MicroOp::Append(keys.append(rng)?, value))
                }
            })
            .collect()
    }
}

/// Runs each transaction as one database transaction.
struct DbExecutor {
    db: Arc<TxDB>,
    obj: Obj,
    props: Vec<Symbol>,
    max_retries: usize,
    retries: AtomicUsize,
}

impl DbExecutor {
    fn attempt(&self, ops: &[MicroOp]) -> Result<Option<Reads>, eyre::Error> {
        let perms = TaskPermissions::new(self.obj, BitEnum::new());
        let mut tx = self.db.new_world_state()?;
        let mut reads = Vec::with_capacity(ops.len());
        for op in ops {
            match *op {
                MicroOp::Read(key) => {
                    let value = tx.retrieve_property(&perms, &self.obj, self.props[key])?;
                    reads.push(Some(list_values(&value)?));
                }
                MicroOp::Append(key, value) => {
                    let current = tx.retrieve_property(&perms, &self.obj, self.props[key])?;
                    let appended = current
                        .push(&v_int(value))
                        .map_err(|error| eyre::eyre!("append to key {key}: {error:?}"))?;
                    tx.update_property(&perms, &self.obj, self.props[key], &appended)?;
                    reads.push(None);
                }
            }
        }
        match tx.commit()? {
            CommitResult::Success { .. } => Ok(Some(reads)),
            CommitResult::ConflictRetry { .. } => Ok(None),
        }
    }
}

impl Executor for DbExecutor {
    fn execute(&self, ops: &[MicroOp]) -> Result<Outcome, eyre::Error> {
        for attempt in 0..self.max_retries {
            if attempt > 0 {
                self.retries.fetch_add(1, Ordering::Relaxed);
            }
            if let Some(reads) = self.attempt(ops)? {
                return Ok(Outcome::Committed(reads));
            }
        }
        Ok(Outcome::Failed)
    }

    fn retries(&self) -> Option<usize> {
        Some(self.retries.load(Ordering::Relaxed))
    }
}

/// Runs each transaction as one MOO eval task. The scheduler retries commit conflicts by
/// rerunning the task, and a task that aborts rolls back.
struct SchedulerExecutor {
    client: SchedulerClient,
    player: Obj,
    obj: Obj,
    features: Arc<FeaturesConfig>,
}

impl Executor for SchedulerExecutor {
    fn execute(&self, ops: &[MicroOp]) -> Result<Outcome, eyre::Error> {
        let handle = self.client.submit_eval_task(
            &self.player,
            &self.player,
            moo_program(self.obj, ops),
            None,
            Arc::new(DirectSession::new(self.player)),
            self.features.clone(),
        )?;
        let receiver = handle.into_receiver();
        loop {
            match receiver.recv()? {
                (_, Ok(TaskNotification::Suspended)) => continue,
                (_, Ok(TaskNotification::Result(result))) => {
                    return Ok(Outcome::Committed(eval_reads(ops, &result)?));
                }
                (_, Err(_)) => return Ok(Outcome::Failed),
            }
        }
    }

    fn retries(&self) -> Option<usize> {
        let retries = sched_counters()
            .timers
            .calls(SchedulerOp::TaskConflictRetry);
        Some(usize::try_from(retries).unwrap_or(usize::MAX))
    }
}

/// The transaction as MOO code. It returns a list of what each read saw, in order.
fn moo_program(obj: Obj, ops: &[MicroOp]) -> String {
    let mut code = String::from("r = {};\n");
    for op in ops {
        match *op {
            MicroOp::Read(key) => writeln!(code, "r = {{@r, {obj}.key_{key}}};"),
            MicroOp::Append(key, value) => {
                writeln!(code, "{obj}.key_{key} = {{@{obj}.key_{key}, {value}}};")
            }
        }
        .expect("writing to a String does not fail");
    }
    code.push_str("return r;\n");
    code
}

/// Match an eval result's read values to the transaction's read operations.
fn eval_reads(ops: &[MicroOp], result: &Var) -> Result<Reads, eyre::Error> {
    let list = result
        .as_list()
        .ok_or_else(|| eyre::eyre!("eval returned a non-list: {result:?}"))?;
    let mut values = list.iter();
    let reads = ops
        .iter()
        .map(|op| match op {
            MicroOp::Read(key) => {
                let value = values
                    .next()
                    .ok_or_else(|| eyre::eyre!("eval returned too few reads: {result:?}"))?;
                list_values(&value)
                    .map(Some)
                    .map_err(|error| eyre::eyre!("read of key {key}: {error}"))
            }
            MicroOp::Append(..) => Ok(None),
        })
        .collect::<Result<_, _>>()?;
    if values.next().is_some() {
        return Err(eyre::eyre!("eval returned too many reads: {result:?}"));
    }
    Ok(reads)
}

fn list_values(value: &Var) -> Result<Vec<i64>, eyre::Error> {
    let list = value
        .as_list()
        .ok_or_else(|| eyre::eyre!("key value is not a list: {value:?}"))?;
    list.iter()
        .map(|element| {
            element
                .as_integer()
                .ok_or_else(|| eyre::eyre!("list element is not an integer: {element:?}"))
        })
        .collect()
}

/// The transaction as an EDN vector of micro-operations. Reads carry `nil` until completion.
fn txn_value(ops: &[MicroOp], reads: Option<&[Option<Vec<i64>>]>) -> Value {
    let keyword = |name| Value::Keyword(Keyword::from_name(name));
    Value::Vector(
        ops.iter()
            .enumerate()
            .map(|(index, op)| match *op {
                MicroOp::Read(key) => {
                    let seen = reads
                        .and_then(|reads| reads[index].as_ref())
                        .map(|values| {
                            Value::Vector(values.iter().map(|v| Value::Integer(*v)).collect())
                        })
                        .unwrap_or(Value::Nil);
                    Value::Vector(vec![keyword("r"), Value::Integer(key as i64), seen])
                }
                MicroOp::Append(key, value) => Value::Vector(vec![
                    keyword("append"),
                    Value::Integer(key as i64),
                    Value::Integer(value),
                ]),
            })
            .collect(),
    )
}

#[derive(Default)]
struct ProcessResult {
    events: Vec<EdnEvent>,
    latencies: Vec<Duration>,
    failed: usize,
}

fn run_process(
    generator: &Generator,
    executor: &dyn Executor,
    process_id: usize,
    iterations: usize,
) -> Result<ProcessResult, eyre::Error> {
    let mut rng = rand::rng();
    let mut result = ProcessResult::default();
    for _ in 0..iterations {
        let ops = generator.generate(&mut rng)?;
        let invoked = Instant::now();
        result.events.push(EdnEvent::invoke(
            invoked,
            process_id,
            "txn".to_string(),
            txn_value(&ops, None),
        ));
        let outcome = executor.execute(&ops)?;
        let completed = Instant::now();
        match outcome {
            Outcome::Committed(reads) => {
                result.latencies.push(completed - invoked);
                result.events.push(EdnEvent::ok(
                    completed,
                    process_id,
                    "txn".to_string(),
                    txn_value(&ops, Some(&reads)),
                ));
            }
            Outcome::Failed => {
                result.failed += 1;
                result.events.push(EdnEvent::fail(
                    completed,
                    process_id,
                    "txn".to_string(),
                    txn_value(&ops, None),
                ));
            }
        }
    }
    Ok(result)
}

/// Create the system object and a wizard player for eval tasks to run as.
fn setup_scheduler_objects(db: &TxDB) -> Result<Obj, eyre::Error> {
    let mut loader = db.loader_client()?;
    let system = loader.create_object(
        ObjectKind::Objid(Obj::mk_id(0)),
        &ObjAttrs::new(
            NOTHING,
            NOTHING,
            NOTHING,
            ObjFlag::User.into(),
            "System Object",
        ),
    )?;
    loader.set_object_owner(&system, &system)?;
    let player = loader.create_object(
        ObjectKind::Objid(Obj::mk_id(1)),
        &ObjAttrs::new(
            NOTHING,
            NOTHING,
            NOTHING,
            BitEnum::new_with(ObjFlag::User) | ObjFlag::Programmer | ObjFlag::Wizard,
            "Wizard",
        ),
    )?;
    loader.set_object_owner(&player, &player)?;
    match loader.commit()? {
        CommitResult::Success { .. } => Ok(player),
        CommitResult::ConflictRetry { .. } => Err(eyre::eyre!("conflict creating test objects")),
    }
}

fn percentile(sorted: &[Duration], fraction: f64) -> Duration {
    if sorted.is_empty() {
        return Duration::ZERO;
    }
    sorted[((sorted.len() - 1) as f64 * fraction).round() as usize]
}

fn main() -> Result<(), eyre::Error> {
    color_eyre::install()?;
    let args = Args::parse();
    if args.num_active_keys == 0 || args.max_txn_length == 0 || args.max_writes_per_key == 0 {
        return Err(eyre::eyre!(
            "--num-active-keys, --max-txn-length and --max-writes-per-key must be at least 1"
        ));
    }

    // Enough keys for every append the run can generate.
    let max_appends =
        args.num_concurrent_workloads * args.num_workload_iterations * args.max_txn_length;
    let pool_size = args.num_active_keys + max_appends.div_ceil(args.max_writes_per_key);

    let temp_dir = tempfile::tempdir()?;
    let db_path = args
        .db_path
        .clone()
        .unwrap_or_else(|| temp_dir.path().join("test_db"));
    let (db, _) = TxDB::try_open(Some(&db_path), Default::default())
        .map_err(|error| eyre::eyre!("open database at {}: {error}", db_path.display()))?;

    let player = match args.target {
        Target::Db => None,
        Target::Scheduler => Some(setup_scheduler_objects(&db)?),
    };
    let (obj, props) = elle_common::setup_test_database(&db, pool_size, "key", |_| v_list(&[]))?;

    let mut scheduler_threads = None;
    let executor: Arc<dyn Executor> = match args.target {
        Target::Db => Arc::new(DbExecutor {
            db: Arc::new(db),
            obj,
            props,
            max_retries: args.max_retries,
            retries: AtomicUsize::new(0),
        }),
        Target::Scheduler => {
            let features = Arc::new(FeaturesConfig::default());
            let config = Arc::new(Config {
                features: features.clone(),
                ..Default::default()
            });
            let scheduler = Scheduler::new(
                semver::Version::new(0, 0, 0),
                Box::new(db),
                Box::new(NoopTasksDb {}),
                config,
                Arc::new(NoopSystemControl {}),
                None,
                None,
            );
            let client = scheduler.client()?;
            scheduler_threads = Some((
                scheduler.start(Arc::new(DirectSessionFactory {}))?,
                client.clone(),
            ));
            Arc::new(SchedulerExecutor {
                client,
                player: player.expect("scheduler target creates a player"),
                obj,
                features,
            })
        }
    };

    println!(
        "list-append ({:?}): {} processes x {} transactions, up to {} operations each, {} active \
         keys, {} appends per key, {} keys defined",
        args.target,
        args.num_concurrent_workloads,
        args.num_workload_iterations,
        args.max_txn_length,
        args.num_active_keys,
        args.max_writes_per_key,
        pool_size
    );

    let generator = Arc::new(Generator {
        keys: Mutex::new(KeyRotation::new(
            args.num_active_keys,
            args.max_writes_per_key,
            pool_size,
        )),
        next_value: AtomicI64::new(1),
        max_txn_length: args.max_txn_length,
        read_fraction: args.read_fraction,
    });

    let started = Instant::now();
    let handles: Vec<_> = (0..args.num_concurrent_workloads)
        .map(|process_id| {
            let generator = generator.clone();
            let executor = executor.clone();
            let iterations = args.num_workload_iterations;
            thread::spawn(move || run_process(&generator, &*executor, process_id, iterations))
        })
        .collect();
    let mut events = Vec::new();
    let mut latencies = Vec::new();
    let mut failed = 0;
    for handle in handles {
        let result = handle
            .join()
            .map_err(|_| eyre::eyre!("workload thread panicked"))??;
        events.extend(result.events);
        latencies.extend(result.latencies);
        failed += result.failed;
    }
    let elapsed = started.elapsed();

    if let Some((threads, client)) = scheduler_threads {
        client.submit_shutdown("list-append workload finished")?;
        threads
            .join()
            .map_err(|_| eyre::eyre!("scheduler thread panicked"))?;
    }

    events.sort_by_key(|event| event.timestamp);
    elle_common::write_edn_history(&events, &args.output_file)?;

    latencies.sort();
    let retries = executor
        .retries()
        .map(|retries| format!(", {retries} retries"))
        .unwrap_or_default();
    println!(
        "{} committed, {failed} failed{retries} in {:.2}s ({:.0} txn/s)",
        latencies.len(),
        elapsed.as_secs_f64(),
        latencies.len() as f64 / elapsed.as_secs_f64()
    );
    println!(
        "latency p50 {:?}, p95 {:?}, p99 {:?}, max {:?}",
        percentile(&latencies, 0.50),
        percentile(&latencies, 0.95),
        percentile(&latencies, 0.99),
        latencies.last().copied().unwrap_or_default()
    );
    println!(
        "wrote {} events to {}",
        events.len(),
        args.output_file.display()
    );
    Ok(())
}
