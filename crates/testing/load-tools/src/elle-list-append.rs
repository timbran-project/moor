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

//! Elle list-append workload against `moor_db`, bypassing the scheduler.
//!
//! Each transaction is a short sequence of reads and appends over several list properties, run
//! in one database transaction. Keys rotate: a key takes a bounded number of appends, then a
//! fresh key replaces it, so lists stay short. The history is written as EDN for elle-cli's
//! `list-append` model.

use clap::Parser;
use clap_derive::Parser;
use edn_format::{Keyword, Value};
use moor_common::{
    model::{CommitResult, TaskPermissions, WorldStateSource},
    util::BitEnum,
};
use moor_db::TxDB;
use moor_model_checker::elle_common::{self, EdnEvent};
use moor_var::{Obj, Symbol, Var, v_int, v_list};
use rand::{Rng, RngExt};
use std::{
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicI64, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

#[derive(Clone, Parser, Debug)]
struct Args {
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
        help = "Commit attempts before a transaction is recorded as failed",
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

struct Workload {
    db: Arc<TxDB>,
    obj: Obj,
    props: Vec<Symbol>,
    keys: Mutex<KeyRotation>,
    next_value: AtomicI64,
    args: Args,
}

impl Workload {
    fn generate(&self, rng: &mut impl Rng) -> Result<Vec<MicroOp>, eyre::Error> {
        let length = rng.random_range(1..=self.args.max_txn_length);
        let mut keys = self.keys.lock().unwrap();
        (0..length)
            .map(|_| {
                if rng.random_bool(self.args.read_fraction) {
                    Ok(MicroOp::Read(keys.read(rng)))
                } else {
                    let value = self.next_value.fetch_add(1, Ordering::Relaxed);
                    Ok(MicroOp::Append(keys.append(rng)?, value))
                }
            })
            .collect()
    }

    /// Run the operations in one transaction. Returns the values each read saw, or `None` if the
    /// commit conflicted.
    fn attempt(&self, ops: &[MicroOp]) -> Result<Option<Vec<Option<Vec<i64>>>>, eyre::Error> {
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

    fn process(&self, process_id: usize) -> Result<ProcessResult, eyre::Error> {
        let mut rng = rand::rng();
        let mut result = ProcessResult::default();
        for _ in 0..self.args.num_workload_iterations {
            let ops = self.generate(&mut rng)?;
            let invoked = Instant::now();
            result.events.push(EdnEvent::invoke(
                invoked,
                process_id,
                "txn".to_string(),
                txn_value(&ops, None),
            ));

            let mut committed = None;
            for attempt in 0..self.args.max_retries {
                if attempt > 0 {
                    result.retries += 1;
                }
                if let Some(reads) = self.attempt(&ops)? {
                    committed = Some(reads);
                    break;
                }
            }

            let completed = Instant::now();
            match committed {
                Some(reads) => {
                    result.latencies.push(completed - invoked);
                    result.events.push(EdnEvent::ok(
                        completed,
                        process_id,
                        "txn".to_string(),
                        txn_value(&ops, Some(&reads)),
                    ));
                }
                None => {
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
}

#[derive(Default)]
struct ProcessResult {
    events: Vec<EdnEvent>,
    latencies: Vec<Duration>,
    retries: usize,
    failed: usize,
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
    let db = Arc::new(db);
    let (obj, props) = elle_common::setup_test_database(&db, pool_size, "key", |_| v_list(&[]))?;

    println!(
        "list-append: {} processes x {} transactions, up to {} operations each, {} active keys, \
         {} appends per key, {} keys defined",
        args.num_concurrent_workloads,
        args.num_workload_iterations,
        args.max_txn_length,
        args.num_active_keys,
        args.max_writes_per_key,
        pool_size
    );

    let workload = Arc::new(Workload {
        db,
        obj,
        props,
        keys: Mutex::new(KeyRotation::new(
            args.num_active_keys,
            args.max_writes_per_key,
            pool_size,
        )),
        next_value: AtomicI64::new(1),
        args: args.clone(),
    });

    let started = Instant::now();
    let handles: Vec<_> = (0..args.num_concurrent_workloads)
        .map(|process_id| {
            let workload = workload.clone();
            thread::spawn(move || workload.process(process_id))
        })
        .collect();
    let mut events = Vec::new();
    let mut latencies = Vec::new();
    let (mut retries, mut failed) = (0, 0);
    for handle in handles {
        let result = handle
            .join()
            .map_err(|_| eyre::eyre!("workload thread panicked"))??;
        events.extend(result.events);
        latencies.extend(result.latencies);
        retries += result.retries;
        failed += result.failed;
    }
    let elapsed = started.elapsed();

    events.sort_by_key(|event| event.timestamp);
    elle_common::write_edn_history(&events, &args.output_file)?;

    latencies.sort();
    println!(
        "{} committed, {failed} failed, {retries} retries in {:.2}s ({:.0} txn/s)",
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
