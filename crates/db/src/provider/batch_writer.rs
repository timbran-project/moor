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

//! Coalescing batch writer for fjall operations.
//!
//! Instead of writing every transaction's changes immediately, we buffer writes
//! in per-partition HashMaps where later writes to the same key overwrite earlier ones.
//! This reduces actual I/O when the same keys are written repeatedly.
//!
//! Flush triggers:
//! - Total pending ops exceed threshold
//! - Time since last flush exceeds interval
//! - Barrier request (for snapshots)
//! - Shutdown

use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

use flume::{Receiver, Sender};
use moor_common::threading::spawn_efficient;
use moor_common::util::{PerfIntensity, Timestamp as MonoTimestamp};
use parking_lot::Mutex;
use tracing::{error, info, warn};

use crate::db_counters;
use crate::tx::{Error, Timestamp};

/// A single operation to be written to fjall.
#[derive(Clone)]
pub struct BatchOp {
    /// The fjall partition (keyspace) to write to
    pub partition: fjall::Keyspace,
    /// The operation type
    pub op_type: BatchOpType,
}

#[derive(Clone)]
pub enum BatchOpType {
    Insert {
        key: Vec<u8>,
        value: Arc<dyn BatchValue>,
    },
    Delete {
        key: Vec<u8>,
    },
}

/// Value hook used by the writer thread to produce serialized bytes.
pub trait BatchValue: Send + Sync {
    fn encode(&self) -> Result<Vec<u8>, Error>;
}

struct EncodedBatchValue(Vec<u8>);

impl BatchValue for EncodedBatchValue {
    fn encode(&self) -> Result<Vec<u8>, Error> {
        Ok(self.0.clone())
    }
}

/// A batch of operations from a single commit, spanning all relations.
pub struct CommitBatch {
    /// Contiguous version of the published world-state snapshot.
    pub version: u64,
    pub timestamp: Timestamp,
    pub operations: Vec<BatchOp>,
}

impl CommitBatch {
    pub fn with_capacity(version: u64, timestamp: Timestamp, expected_operations: usize) -> Self {
        Self {
            version,
            timestamp,
            operations: Vec::with_capacity(expected_operations),
        }
    }

    pub fn insert(&mut self, partition: fjall::Keyspace, key: Vec<u8>, value: Arc<dyn BatchValue>) {
        self.operations.push(BatchOp {
            partition,
            op_type: BatchOpType::Insert { key, value },
        });
    }

    pub fn delete(&mut self, partition: fjall::Keyspace, key: Vec<u8>) {
        self.operations.push(BatchOp {
            partition,
            op_type: BatchOpType::Delete { key },
        });
    }

    pub fn insert_encoded(&mut self, partition: fjall::Keyspace, key: Vec<u8>, value: Vec<u8>) {
        self.insert(partition, key, Arc::new(EncodedBatchValue(value)));
    }
}

/// Manages the current commit batch. Shared across all FjallProviders.
#[derive(Default)]
pub struct BatchCollector {
    current: Mutex<Option<CommitBatch>>,
}

impl BatchCollector {
    pub fn new() -> Self {
        Self {
            current: Mutex::new(None),
        }
    }

    pub fn start_commit(&self, version: u64, timestamp: Timestamp, expected_operations: usize) {
        let mut current = self.current.lock();
        debug_assert!(
            current.is_none(),
            "Previous commit batch not finished (timestamp {:?})",
            current.as_ref().map(|b| b.timestamp)
        );
        *current = Some(CommitBatch::with_capacity(
            version,
            timestamp,
            expected_operations,
        ));
    }

    pub fn insert(&self, partition: fjall::Keyspace, key: Vec<u8>, value: Arc<dyn BatchValue>) {
        let mut current = self.current.lock();
        current
            .as_mut()
            .expect("No active commit batch - call start_commit() first")
            .insert(partition, key, value);
    }

    pub fn delete(&self, partition: fjall::Keyspace, key: Vec<u8>) {
        let mut current = self.current.lock();
        current
            .as_mut()
            .expect("No active commit batch - call start_commit() first")
            .delete(partition, key);
    }

    pub fn finish_commit(&self) -> CommitBatch {
        self.current
            .lock()
            .take()
            .expect("No active commit batch to finish")
    }

    pub fn abort_commit(&self) {
        self.current.lock().take();
    }
}

/// Pending operation for a key - either insert with value or delete.
#[derive(Clone)]
enum PendingOp {
    Insert(Arc<dyn BatchValue>),
    Delete,
}

/// Per-partition coalescing buffer.
struct PartitionBuffer {
    keyspace: fjall::Keyspace,
    pending: HashMap<Vec<u8>, PendingOp>,
}

impl PartitionBuffer {
    fn new(keyspace: fjall::Keyspace) -> Self {
        Self {
            keyspace,
            pending: HashMap::new(),
        }
    }

    fn insert(&mut self, key: Vec<u8>, value: Arc<dyn BatchValue>) {
        self.pending.insert(key, PendingOp::Insert(value));
    }

    fn delete(&mut self, key: Vec<u8>) {
        self.pending.insert(key, PendingOp::Delete);
    }

    fn len(&self) -> usize {
        self.pending.len()
    }

    fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    fn clear(&mut self) {
        self.pending.clear();
    }
}

/// Message sent to the writer thread.
enum WriterMsg {
    /// Persist a published transaction's relation and sequence changes.
    Write(CommitBatch),
    /// Mark the end of all writes for a published transaction.
    TransactionBarrier(u64),
    /// Flush through a transaction boundary and reply when it is durable enough for a snapshot.
    FlushBarrier(u64, oneshot::Sender<Result<(), String>>),
}

/// Bounds for coalescing published transactions into one Fjall batch.
const MAX_PENDING_OPS: usize = 50_000;
const MAX_COALESCE_INTERVAL: Duration = Duration::from_millis(100);
const RECEIVE_POLL_INTERVAL: Duration = Duration::from_millis(10);

struct WriterState {
    buffers: HashMap<String, PartitionBuffer>,
    waiting_batches: BTreeMap<u64, CommitBatch>,
    transaction_barriers: BTreeSet<u64>,
    next_version: u64,
    ready_version: u64,
    total_pending: usize,
    pending_since: Option<Instant>,
}

impl WriterState {
    fn new() -> Self {
        Self {
            buffers: HashMap::new(),
            waiting_batches: BTreeMap::new(),
            transaction_barriers: BTreeSet::new(),
            next_version: 1,
            ready_version: 0,
            total_pending: 0,
            pending_since: None,
        }
    }

    fn add_batch(&mut self, batch: CommitBatch) -> Result<(), String> {
        let version = batch.version;
        if version < self.next_version || self.waiting_batches.insert(version, batch).is_some() {
            return Err(format!("duplicate persistence batch for version {version}"));
        }
        self.merge_ready_versions();
        Ok(())
    }

    fn add_transaction_barrier(&mut self, version: u64) -> Result<(), String> {
        if version < self.next_version || !self.transaction_barriers.insert(version) {
            return Err(format!(
                "duplicate transaction barrier for version {version}"
            ));
        }
        self.merge_ready_versions();
        Ok(())
    }

    fn merge_ready_versions(&mut self) {
        loop {
            if !self.transaction_barriers.contains(&self.next_version) {
                return;
            }
            let Some(batch) = self.waiting_batches.remove(&self.next_version) else {
                return;
            };

            self.transaction_barriers.remove(&self.next_version);
            Self::merge_batch(&mut self.buffers, batch, &mut self.total_pending);
            self.ready_version = self.next_version;
            self.next_version += 1;
            self.pending_since.get_or_insert_with(Instant::now);
        }
    }

    fn merge_batch(
        buffers: &mut HashMap<String, PartitionBuffer>,
        batch: CommitBatch,
        total_pending: &mut usize,
    ) {
        for op in batch.operations {
            let partition_name = op.partition.name().to_string();
            let buffer = buffers
                .entry(partition_name)
                .or_insert_with(|| PartitionBuffer::new(op.partition.clone()));

            let previous_len = buffer.len();
            match op.op_type {
                BatchOpType::Insert { key, value } => buffer.insert(key, value),
                BatchOpType::Delete { key } => buffer.delete(key),
            }
            if buffer.len() > previous_len {
                *total_pending += 1;
            }
        }
    }

    fn flush_due(&self) -> bool {
        self.total_pending >= MAX_PENDING_OPS
            || self
                .pending_since
                .is_some_and(|started| started.elapsed() >= MAX_COALESCE_INTERVAL)
    }

    fn has_ready_boundary(&self, completed_version: u64) -> bool {
        self.ready_version > completed_version
    }

    fn clear_flushed(&mut self) {
        for buffer in self.buffers.values_mut() {
            buffer.clear();
        }
        self.total_pending = 0;
        self.pending_since = None;
    }
}

/// Coalescing batch writer that deduplicates writes before hitting fjall.
pub struct BatchWriter {
    sender: Sender<WriterMsg>,
    kill_switch: Arc<AtomicBool>,
    completed_version: Arc<AtomicU64>,
    join_handle: Mutex<Option<JoinHandle<()>>>,
}

impl BatchWriter {
    pub fn new(db: fjall::Database) -> Self {
        let kill_switch = Arc::new(AtomicBool::new(false));
        let completed_version = Arc::new(AtomicU64::new(0));
        let (sender, receiver) = flume::bounded::<WriterMsg>(1000);

        let ks = kill_switch.clone();
        let completed = completed_version.clone();

        let join_handle = spawn_efficient("moor-batch-writer", move || {
            Self::writer_loop(db, receiver, ks, completed);
        })
        .expect("failed to spawn batch writer thread");

        Self {
            sender,
            kill_switch,
            completed_version,
            join_handle: Mutex::new(Some(join_handle)),
        }
    }

    fn writer_loop(
        db: fjall::Database,
        receiver: Receiver<WriterMsg>,
        kill_switch: Arc<AtomicBool>,
        completed_version: Arc<AtomicU64>,
    ) {
        let mut state = WriterState::new();
        let mut flush_waiters = Vec::new();

        loop {
            if kill_switch.load(Ordering::Relaxed) {
                while let Ok(msg) = receiver.try_recv() {
                    if let Err(error) = Self::handle_message(msg, &mut state, &mut flush_waiters, 0)
                    {
                        Self::fail_writer(&error, &mut flush_waiters);
                        return;
                    }
                }

                if !state.waiting_batches.is_empty() || !state.transaction_barriers.is_empty() {
                    let error = format!(
                        "batch writer stopped with a gap before version {}",
                        state.next_version
                    );
                    Self::fail_writer(&error, &mut flush_waiters);
                    return;
                }

                if state.has_ready_boundary(completed_version.load(Ordering::Acquire)) {
                    info!(
                        pending_ops = state.total_pending,
                        "Flushing batch writer at shutdown"
                    );
                    if let Err(error) = Self::flush_ready(&db, &mut state, &completed_version) {
                        Self::fail_writer(&error, &mut flush_waiters);
                        return;
                    }
                }
                Self::reply_completed_waiters(
                    &mut flush_waiters,
                    completed_version.load(Ordering::Acquire),
                );
                break;
            }

            let completed = completed_version.load(Ordering::Acquire);
            let waiter_ready = flush_waiters
                .iter()
                .any(|(version, _)| *version <= state.ready_version);
            if (state.flush_due() || waiter_ready) && state.has_ready_boundary(completed) {
                if let Err(error) = Self::flush_ready(&db, &mut state, &completed_version) {
                    Self::fail_writer(&error, &mut flush_waiters);
                    return;
                }
                Self::reply_completed_waiters(
                    &mut flush_waiters,
                    completed_version.load(Ordering::Acquire),
                );
                continue;
            }

            match receiver.recv_timeout(RECEIVE_POLL_INTERVAL) {
                Ok(msg) => {
                    if let Err(error) =
                        Self::handle_message(msg, &mut state, &mut flush_waiters, completed)
                    {
                        Self::fail_writer(&error, &mut flush_waiters);
                        return;
                    }
                    while let Ok(msg) = receiver.try_recv() {
                        if let Err(error) =
                            Self::handle_message(msg, &mut state, &mut flush_waiters, completed)
                        {
                            Self::fail_writer(&error, &mut flush_waiters);
                            return;
                        }
                    }
                }
                Err(flume::RecvTimeoutError::Timeout) => {}
                Err(flume::RecvTimeoutError::Disconnected) => break,
            }
        }
    }

    fn handle_message(
        msg: WriterMsg,
        state: &mut WriterState,
        flush_waiters: &mut Vec<(u64, oneshot::Sender<Result<(), String>>)>,
        completed_version: u64,
    ) -> Result<(), String> {
        match msg {
            WriterMsg::Write(batch) => state.add_batch(batch),
            WriterMsg::TransactionBarrier(version) => state.add_transaction_barrier(version),
            WriterMsg::FlushBarrier(version, reply) => {
                if version <= completed_version {
                    reply.send(Ok(())).ok();
                } else {
                    flush_waiters.push((version, reply));
                }
                Ok(())
            }
        }
    }

    fn flush_ready(
        db: &fjall::Database,
        state: &mut WriterState,
        completed_version: &AtomicU64,
    ) -> Result<(), String> {
        if state.total_pending == 0 {
            completed_version.store(state.ready_version, Ordering::Release);
            state.pending_since = None;
            return Ok(());
        }

        let start = Instant::now();
        let op_count = state.total_pending;
        let encode_start = Instant::now();
        let mut encoded_bytes = 0usize;

        let mut write_batch = db.batch();

        for buffer in state.buffers.values() {
            if buffer.is_empty() {
                continue;
            }
            for (key, op) in &buffer.pending {
                match op {
                    PendingOp::Insert(value) => {
                        let encoded = value
                            .encode()
                            .map_err(|error| format!("failed to encode batch value: {error}"))?;
                        encoded_bytes += key.len() + encoded.len();
                        write_batch.insert(&buffer.keyspace, key.clone(), encoded);
                    }
                    PendingOp::Delete => {
                        encoded_bytes += key.len();
                        write_batch.remove(&buffer.keyspace, key.clone());
                    }
                }
            }
        }
        let encode_elapsed = encode_start.elapsed();

        let outstanding_flushes_before = db.outstanding_flushes();
        let active_compactions_before = db.active_compactions();
        let commit_start = Instant::now();
        write_batch
            .commit()
            .map_err(|error| format!("failed to commit Fjall write batch: {error}"))?;
        let commit_elapsed = commit_start.elapsed();

        state.clear_flushed();
        completed_version.store(state.ready_version, Ordering::Release);

        let elapsed = start.elapsed();
        if elapsed > Duration::from_secs(1) {
            warn!(
                op_count,
                encoded_bytes,
                ready_version = state.ready_version,
                ?encode_elapsed,
                ?commit_elapsed,
                outstanding_flushes_before,
                outstanding_flushes_after = db.outstanding_flushes(),
                active_compactions_before,
                active_compactions_after = db.active_compactions(),
                "Slow Fjall batch commit"
            );
        }
        Ok(())
    }

    fn reply_completed_waiters(
        waiters: &mut Vec<(u64, oneshot::Sender<Result<(), String>>)>,
        completed_version: u64,
    ) {
        let mut pending = Vec::with_capacity(waiters.len());
        for (version, reply) in waiters.drain(..) {
            if version <= completed_version {
                reply.send(Ok(())).ok();
            } else {
                pending.push((version, reply));
            }
        }
        *waiters = pending;
    }

    fn fail_writer(detail: &str, waiters: &mut Vec<(u64, oneshot::Sender<Result<(), String>>)>) {
        error!("Batch writer failed: {detail}");
        #[cfg(not(test))]
        moor_common::util::signal_fatal_db_error("batch writer", detail);
        for (_, reply) in waiters.drain(..) {
            reply.send(Err(detail.to_string())).ok();
        }
    }

    pub fn write(&self, batch: CommitBatch) {
        let version = batch.version;
        let ts = batch.timestamp;
        let op_count = batch.operations.len();
        let msg = WriterMsg::Write(batch);

        match self.sender.try_send(msg) {
            Ok(()) => {}
            Err(flume::TrySendError::Full(msg)) => {
                db_counters().batch_writer_backpressure.invocations().add(1);
                warn!(
                    "BatchWriter backpressure: queue full, blocking on version {} / transaction {} ({} ops)",
                    version, ts.0, op_count
                );
                let start = MonoTimestamp::now();
                if let Err(e) = self.sender.send(msg) {
                    error!("Failed to send batch to writer: {}", e);
                    return;
                }
                let elapsed = start.elapsed();
                db_counters()
                    .batch_writer_backpressure_block
                    .record_elapsed_from_with(PerfIntensity::RarePath, start.instant());
                if elapsed > Duration::from_secs(1) {
                    warn!(
                        "BatchWriter backpressure: blocked version {} / transaction {} for {:?}",
                        version, ts.0, elapsed
                    );
                }
            }
            Err(flume::TrySendError::Disconnected(_)) => {
                error!("BatchWriter channel disconnected");
            }
        }
    }

    pub fn send_barrier(&self, version: u64) {
        let msg = WriterMsg::TransactionBarrier(version);
        match self.sender.try_send(msg) {
            Ok(()) => {}
            Err(flume::TrySendError::Full(msg)) => {
                db_counters().batch_writer_backpressure.invocations().add(1);
                let start = MonoTimestamp::now();
                if let Err(e) = self.sender.send(msg) {
                    warn!("Failed to send barrier: {}", e);
                    return;
                }
                db_counters()
                    .batch_writer_backpressure_block
                    .record_elapsed_from_with(PerfIntensity::RarePath, start.instant());
            }
            Err(flume::TrySendError::Disconnected(_)) => {
                warn!("Failed to send barrier: channel disconnected");
            }
        }
    }

    pub fn completed_version(&self) -> u64 {
        self.completed_version.load(Ordering::Acquire)
    }

    pub fn wait_for_barrier(&self, version: u64, timeout: Duration) -> Result<(), String> {
        if self.completed_version.load(Ordering::Acquire) >= version {
            return Ok(());
        }

        let (reply, receiver) = oneshot::channel();
        let msg = WriterMsg::FlushBarrier(version, reply);
        self.sender
            .send(msg)
            .map_err(|_| "batch writer channel disconnected".to_string())?;
        receiver
            .recv_timeout(timeout)
            .map_err(|error| format!("timed out waiting for write barrier {version}: {error}"))?
    }

    pub fn stop(&self) {
        self.kill_switch.store(true, Ordering::SeqCst);

        let mut jh = self.join_handle.lock();
        if let Some(handle) = jh.take() {
            handle.join().ok();
        }
    }
}

impl Drop for BatchWriter {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fjall::{KeyspaceCreateOptions, Readable};
    use std::thread;

    fn test_database() -> (tempfile::TempDir, fjall::Database) {
        let tempdir = tempfile::tempdir().unwrap();
        let database = fjall::Database::builder(tempdir.path()).open().unwrap();
        (tempdir, database)
    }

    fn encoded_batch(
        version: u64,
        partition: &fjall::Keyspace,
        key: &[u8],
        value: &[u8],
    ) -> CommitBatch {
        let mut batch = CommitBatch::with_capacity(version, Timestamp(version), 1);
        batch.insert_encoded(partition.clone(), key.to_vec(), value.to_vec());
        batch
    }

    #[test]
    fn transaction_barrier_is_required_before_flush() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);

        writer.write(encoded_batch(1, &partition, b"key", b"value"));
        thread::sleep(MAX_COALESCE_INTERVAL + Duration::from_millis(25));

        assert_eq!(writer.completed_version(), 0);
        assert_eq!(partition.get(b"key").unwrap(), None);

        writer.send_barrier(1);
        writer.wait_for_barrier(1, Duration::from_secs(1)).unwrap();
        assert_eq!(
            partition.get(b"key").unwrap().as_deref(),
            Some(&b"value"[..])
        );
    }

    #[test]
    fn publication_versions_are_persisted_in_order() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);

        writer.write(encoded_batch(2, &partition, b"key", b"newer"));
        writer.send_barrier(2);
        thread::sleep(Duration::from_millis(25));
        assert_eq!(writer.completed_version(), 0);

        writer.write(encoded_batch(1, &partition, b"key", b"older"));
        writer.send_barrier(1);
        writer.wait_for_barrier(2, Duration::from_secs(1)).unwrap();

        assert_eq!(
            partition.get(b"key").unwrap().as_deref(),
            Some(&b"newer"[..])
        );
    }

    #[test]
    fn explicit_barrier_coalesces_multiple_transactions() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database.clone());
        let initial_seqno = database.visible_seqno();

        writer.write(encoded_batch(1, &partition, b"one", b"1"));
        writer.send_barrier(1);
        writer.write(encoded_batch(2, &partition, b"two", b"2"));
        writer.send_barrier(2);
        writer.wait_for_barrier(2, Duration::from_secs(1)).unwrap();

        assert_eq!(database.visible_seqno(), initial_seqno + 1);
        assert_eq!(partition.get(b"one").unwrap().as_deref(), Some(&b"1"[..]));
        assert_eq!(partition.get(b"two").unwrap().as_deref(), Some(&b"2"[..]));
    }

    #[test]
    fn one_batch_updates_multiple_relations_before_snapshot() {
        let (_tempdir, database) = test_database();
        let first = database
            .keyspace("first", KeyspaceCreateOptions::default)
            .unwrap();
        let second = database
            .keyspace("second", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database.clone());
        let mut batch = CommitBatch::with_capacity(1, Timestamp(1), 2);
        batch.insert_encoded(first.clone(), b"key".to_vec(), b"first".to_vec());
        batch.insert_encoded(second.clone(), b"key".to_vec(), b"second".to_vec());

        writer.write(batch);
        writer.send_barrier(1);
        writer.wait_for_barrier(1, Duration::from_secs(1)).unwrap();
        let snapshot = database.snapshot();

        assert_eq!(
            snapshot.get(&first, b"key").unwrap().as_deref(),
            Some(&b"first"[..])
        );
        assert_eq!(
            snapshot.get(&second, b"key").unwrap().as_deref(),
            Some(&b"second"[..])
        );
    }

    struct FailingValue;

    impl BatchValue for FailingValue {
        fn encode(&self) -> Result<Vec<u8>, Error> {
            Err(Error::EncodingFailure)
        }
    }

    #[test]
    fn failed_encoding_does_not_complete_barrier_or_discard_as_success() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);
        let mut batch = CommitBatch::with_capacity(1, Timestamp(1), 1);
        batch.insert(partition.clone(), b"key".to_vec(), Arc::new(FailingValue));

        writer.write(batch);
        writer.send_barrier(1);
        let error = writer
            .wait_for_barrier(1, Duration::from_secs(1))
            .unwrap_err();

        assert!(error.contains("failed to encode batch value"));
        assert_eq!(writer.completed_version(), 0);
        assert_eq!(partition.get(b"key").unwrap(), None);
    }
}
