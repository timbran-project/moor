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

//! Ordered background writer for atomic Fjall transaction batches.
//!
//! Published transactions may reach this thread out of order because their CAS
//! winners enqueue from different task threads. The writer holds only those
//! out-of-order transactions and commits each contiguous transaction to Fjall
//! immediately as its own cross-keyspace write batch.

use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    thread::JoinHandle,
    time::{Duration, Instant},
};

use ahash::AHashMap;
use flume::{Receiver, Sender};
use moor_common::model::HasUuid;
use moor_common::threading::spawn_efficient;
use moor_var::{Obj, Symbol};
use parking_lot::Mutex;
use tracing::{error, warn};
use uuid::Uuid;

use crate::engine::property_definitions::PropertyDefinitionChange;
use crate::tx::{Error, Timestamp};
use crate::{DEFAULT_COMMIT_QUEUE_TIMEOUT, DEFAULT_COMMIT_QUEUE_WARN, db_counters};
use moor_common::model::{WorldStateCountOp, WorldStateTimerOp};

/// A single operation to be written to fjall.
pub struct BatchOp {
    /// The fjall partition (keyspace) to write to
    pub partition: fjall::Keyspace,
    /// The operation type
    pub op_type: BatchOpType,
    /// Logical source of the operation for slow-write diagnostics.
    pub source: BatchOpSource,
}

/// Logical source of a batch operation.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BatchOpSource {
    Relation(&'static str),
    Property {
        relation: &'static str,
        object: Obj,
        uuid: Uuid,
    },
    Internal(&'static str),
}

impl std::fmt::Display for BatchOpSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Relation(relation) | Self::Internal(relation) => f.write_str(relation),
            Self::Property {
                relation,
                object,
                uuid,
            } => write!(f, "{relation} {object} ({uuid})"),
        }
    }
}

struct BatchOpSourceDisplay<'a> {
    source: &'a BatchOpSource,
    property_names: &'a PropertyNames,
}

impl std::fmt::Display for BatchOpSourceDisplay<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let BatchOpSource::Property {
            relation,
            object,
            uuid,
        } = self.source
        else {
            return std::fmt::Display::fmt(self.source, f);
        };

        let Some(name) = self.property_names.by_uuid.get(uuid) else {
            return std::fmt::Display::fmt(self.source, f);
        };
        write!(f, "{relation} {object}.{} ({uuid})", name.as_str())
    }
}

struct PropertyNames {
    by_uuid: AHashMap<Uuid, Symbol>,
}

impl PropertyNames {
    fn new(by_uuid: AHashMap<Uuid, Symbol>) -> Self {
        Self { by_uuid }
    }

    fn apply(&mut self, changes: impl IntoIterator<Item = PropertyDefinitionChange>) {
        for change in changes {
            match change {
                PropertyDefinitionChange::Remove(uuid) => {
                    self.by_uuid.remove(&uuid);
                }
                PropertyDefinitionChange::Upsert(definition) => {
                    self.by_uuid.insert(definition.uuid(), definition.name());
                }
            }
        }
    }

    fn display<'a>(&'a self, source: &'a BatchOpSource) -> BatchOpSourceDisplay<'a> {
        BatchOpSourceDisplay {
            source,
            property_names: self,
        }
    }
}

pub enum BatchOpType {
    Insert {
        key: fjall::Slice,
        value: Box<dyn BatchValue>,
    },
    Delete {
        key: fjall::Slice,
    },
}

/// Reusable serialization state owned by an encoding worker.
pub struct BatchEncoder {
    var_builder: planus::Builder,
}

impl BatchEncoder {
    pub(crate) fn new() -> Self {
        Self {
            var_builder: planus::Builder::new(),
        }
    }

    pub(crate) fn var_builder(&mut self) -> &mut planus::Builder {
        &mut self.var_builder
    }
}

/// Value hook used by the writer thread to produce serialized bytes.
pub trait BatchValue: Send {
    fn encode(
        self: Box<Self>,
        timestamp: Timestamp,
        encoder: &mut BatchEncoder,
    ) -> Result<fjall::Slice, Error>;
}

struct EncodedBatchValue(fjall::Slice);

impl BatchValue for EncodedBatchValue {
    fn encode(
        self: Box<Self>,
        _timestamp: Timestamp,
        _encoder: &mut BatchEncoder,
    ) -> Result<fjall::Slice, Error> {
        Ok(self.0)
    }
}

/// A batch of operations from a single commit, spanning all relations.
pub struct CommitBatch {
    /// Contiguous version of the published world-state snapshot.
    pub version: u64,
    pub timestamp: Timestamp,
    pub operations: Vec<BatchOp>,
    property_definition_changes: Box<[PropertyDefinitionChange]>,
}

struct EncodedBatchOp {
    partition: fjall::Keyspace,
    op_type: EncodedBatchOpType,
}

enum EncodedBatchOpType {
    Insert {
        key: fjall::Slice,
        value: fjall::Slice,
    },
    Delete {
        key: fjall::Slice,
    },
}

struct EncodingStats {
    elapsed: Duration,
    encoded_bytes: usize,
    slowest: Option<(BatchOpSource, Duration, usize)>,
}

struct EncodedCommitBatch {
    version: u64,
    timestamp: Timestamp,
    operations: Vec<EncodedBatchOp>,
    property_definition_changes: Box<[PropertyDefinitionChange]>,
    encoding: EncodingStats,
}

struct EncodedBatchResult {
    version: u64,
    result: Result<EncodedCommitBatch, String>,
}

impl CommitBatch {
    #[allow(dead_code)]
    pub fn with_capacity(version: u64, timestamp: Timestamp, expected_operations: usize) -> Self {
        Self {
            version,
            timestamp,
            operations: Vec::with_capacity(expected_operations),
            property_definition_changes: Box::default(),
        }
    }

    pub fn insert(
        &mut self,
        partition: fjall::Keyspace,
        key: impl Into<fjall::Slice>,
        value: Box<dyn BatchValue>,
    ) {
        self.operations.push(BatchOp {
            partition,
            op_type: BatchOpType::Insert {
                key: key.into(),
                value,
            },
            source: BatchOpSource::Internal("direct batch value"),
        });
    }

    pub fn insert_encoded(
        &mut self,
        partition: fjall::Keyspace,
        key: impl Into<fjall::Slice>,
        value: impl Into<fjall::Slice>,
    ) {
        self.insert(partition, key, Box::new(EncodedBatchValue(value.into())));
    }

    pub fn from_ops(version: u64, timestamp: Timestamp, operations: Vec<BatchOp>) -> Self {
        Self {
            version,
            timestamp,
            operations,
            property_definition_changes: Box::default(),
        }
    }

    pub(crate) fn set_property_definition_changes(
        &mut self,
        changes: Vec<PropertyDefinitionChange>,
    ) {
        self.property_definition_changes = changes.into_boxed_slice();
    }
}

/// Message sent to the writer thread.
enum WriterMsg {
    /// Persist one complete published transaction.
    Commit(EncodedBatchResult),
    /// Confirm that Fjall has committed through this publication version.
    Barrier {
        through_version: u64,
        reply: oneshot::Sender<Result<(), String>>,
    },
    /// Return a cross-keyspace snapshot after committing through this version.
    Snapshot {
        through_version: u64,
        reply: oneshot::Sender<Result<fjall::Snapshot, String>>,
    },
}

enum EncoderMsg {
    Commit {
        batch: CommitBatch,
        admission: CommitAdmission,
    },
    Stop,
}

const RECEIVE_POLL_INTERVAL: Duration = Duration::from_millis(10);
const ENCODE_QUEUE_CAPACITY: usize = 1000;
const WRITER_QUEUE_CAPACITY: usize = 64;
const MAX_ENCODER_THREADS: usize = 8;

#[derive(Clone, Copy, Debug)]
struct CommitAdmissionPolicy {
    warn_after: Duration,
    timeout: Duration,
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum CommitAdmissionError {
    #[error("database commit queue remained full for {waited:?}")]
    Timeout { waited: Duration },
    #[error("database commit queue admission is unavailable")]
    Unavailable,
}

pub(crate) struct CommitAdmission {
    return_to: Sender<()>,
}

impl Drop for CommitAdmission {
    fn drop(&mut self) {
        let _ = self.return_to.try_send(());
    }
}

#[derive(Default)]
struct BackpressureEpisode {
    started_at: Option<Instant>,
    waiters: usize,
    rejected: usize,
    warned: bool,
}

struct CommitAdmissionGate {
    available: Receiver<()>,
    return_to: Sender<()>,
    capacity: usize,
    warn_after_nanos: AtomicU64,
    timeout_nanos: AtomicU64,
    episode: Mutex<BackpressureEpisode>,
}

impl CommitAdmissionGate {
    fn new(capacity: usize, policy: CommitAdmissionPolicy) -> Self {
        let (return_to, available) = flume::bounded(capacity);
        for _ in 0..capacity {
            return_to
                .send(())
                .expect("commit admission token channel must accept its initial capacity");
        }
        Self {
            available,
            return_to,
            capacity,
            warn_after_nanos: AtomicU64::new(Self::duration_nanos(policy.warn_after)),
            timeout_nanos: AtomicU64::new(Self::duration_nanos(policy.timeout)),
            episode: Mutex::new(BackpressureEpisode::default()),
        }
    }

    fn duration_nanos(duration: Duration) -> u64 {
        u64::try_from(duration.as_nanos()).unwrap_or(u64::MAX)
    }

    fn duration_from_nanos(nanos: u64) -> Duration {
        Duration::from_nanos(nanos)
    }

    fn set_policy(&self, warn_after: Duration, timeout: Duration) {
        self.warn_after_nanos
            .store(Self::duration_nanos(warn_after), Ordering::Release);
        self.timeout_nanos
            .store(Self::duration_nanos(timeout), Ordering::Release);
    }

    fn policy(&self) -> CommitAdmissionPolicy {
        CommitAdmissionPolicy {
            warn_after: Self::duration_from_nanos(self.warn_after_nanos.load(Ordering::Acquire)),
            timeout: Self::duration_from_nanos(self.timeout_nanos.load(Ordering::Acquire)),
        }
    }

    fn permit(&self) -> CommitAdmission {
        CommitAdmission {
            return_to: self.return_to.clone(),
        }
    }

    fn begin_wait(&self) {
        let mut episode = self.episode.lock();
        episode.waiters += 1;
        episode.started_at.get_or_insert_with(Instant::now);
    }

    fn warn_if_needed(&self, transaction: Timestamp, waited: Duration) {
        let waiters = {
            let mut episode = self.episode.lock();
            if episode.warned {
                return;
            }
            episode.warned = true;
            episode.waiters
        };
        warn!(
            transaction = transaction.0,
            ?waited,
            waiters,
            queue_used = self.capacity.saturating_sub(self.available.len()),
            queue_capacity = self.capacity,
            "Database commit queue remains full"
        );
    }

    fn finish_wait(&self, rejected: bool) {
        let finished = {
            let mut episode = self.episode.lock();
            episode.waiters = episode.waiters.saturating_sub(1);
            if rejected {
                episode.rejected += 1;
            }
            if episode.waiters != 0 {
                return;
            }
            let result = episode
                .started_at
                .map(|started_at| (started_at.elapsed(), episode.rejected, episode.warned));
            *episode = BackpressureEpisode::default();
            result
        };
        if let Some((elapsed, rejected, true)) = finished {
            warn!(
                ?elapsed,
                rejected, "Database commit queue wait episode ended"
            );
        }
    }

    fn acquire(&self, transaction: Timestamp) -> Result<CommitAdmission, CommitAdmissionError> {
        match self.available.try_recv() {
            Ok(()) => return Ok(self.permit()),
            Err(flume::TryRecvError::Disconnected) => {
                return Err(CommitAdmissionError::Unavailable);
            }
            Err(flume::TryRecvError::Empty) => {}
        }

        db_counters()
            .counters
            .inc(WorldStateCountOp::BatchWriterBackpressure);
        let started_at = Instant::now();
        self.begin_wait();

        loop {
            let policy = self.policy();
            let waited = started_at.elapsed();
            if waited >= policy.timeout {
                self.warn_if_needed(transaction, waited);
                self.finish_wait(true);
                db_counters()
                    .timers_rare
                    .record_elapsed(WorldStateTimerOp::BatchWriterBackpressureBlock, waited);
                return Err(CommitAdmissionError::Timeout { waited });
            }

            let until_warning = policy.warn_after.saturating_sub(waited);
            let until_timeout = policy.timeout.saturating_sub(waited);
            let wait_for = if until_warning.is_zero() {
                self.warn_if_needed(transaction, waited);
                until_timeout
            } else {
                until_warning.min(until_timeout)
            };

            match self.available.recv_timeout(wait_for) {
                Ok(()) => {
                    let waited = started_at.elapsed();
                    self.finish_wait(false);
                    db_counters()
                        .timers_rare
                        .record_elapsed(WorldStateTimerOp::BatchWriterBackpressureBlock, waited);
                    return Ok(self.permit());
                }
                Err(flume::RecvTimeoutError::Timeout) => {
                    let waited = started_at.elapsed();
                    if waited >= policy.warn_after {
                        self.warn_if_needed(transaction, waited);
                    }
                }
                Err(flume::RecvTimeoutError::Disconnected) => {
                    self.finish_wait(false);
                    return Err(CommitAdmissionError::Unavailable);
                }
            }
        }
    }
}

struct WriterState {
    waiting_batches: BTreeMap<u64, Result<EncodedCommitBatch, String>>,
    barrier_waiters: Vec<(u64, oneshot::Sender<Result<(), String>>)>,
    snapshot_waiters: Vec<(u64, oneshot::Sender<Result<fjall::Snapshot, String>>)>,
    next_version: u64,
    property_names: PropertyNames,
}

impl WriterState {
    fn new(property_names: AHashMap<Uuid, Symbol>) -> Self {
        Self {
            waiting_batches: BTreeMap::new(),
            barrier_waiters: Vec::new(),
            snapshot_waiters: Vec::new(),
            next_version: 1,
            property_names: PropertyNames::new(property_names),
        }
    }

    fn add_batch(&mut self, batch: EncodedBatchResult) -> Result<(), String> {
        let version = batch.version;
        if version < self.next_version
            || self.waiting_batches.insert(version, batch.result).is_some()
        {
            return Err(format!("duplicate persistence batch for version {version}"));
        }
        Ok(())
    }
}

/// Background writer that commits published transactions to Fjall in version order.
pub struct BatchWriter {
    sender: Sender<WriterMsg>,
    encoder_sender: Sender<EncoderMsg>,
    kill_switch: Arc<AtomicBool>,
    completed_version: Arc<AtomicU64>,
    join_handle: Mutex<Option<JoinHandle<Result<(), String>>>>,
    encoder_handles: Mutex<Vec<JoinHandle<Result<(), String>>>>,
    admission: Arc<CommitAdmissionGate>,
}

// If batch writes take longer than this, give a friendly warning to alert the user that something
// might be up in I/O land.
const WRITE_WARNING_DURATION: Duration = Duration::from_secs(5);
const ENCODE_WARNING_DURATION: Duration = Duration::from_secs(1);

impl BatchWriter {
    #[cfg(test)]
    pub fn new(db: fjall::Database) -> Self {
        Self::with_property_names(db, AHashMap::new())
    }

    pub(crate) fn with_property_names(
        db: fjall::Database,
        property_names: AHashMap<Uuid, Symbol>,
    ) -> Self {
        let kill_switch = Arc::new(AtomicBool::new(false));
        let completed_version = Arc::new(AtomicU64::new(0));
        let (sender, receiver) = flume::bounded::<WriterMsg>(WRITER_QUEUE_CAPACITY);
        let (encoder_sender, encoder_receiver) =
            flume::bounded::<EncoderMsg>(ENCODE_QUEUE_CAPACITY);
        let admission = Arc::new(CommitAdmissionGate::new(
            ENCODE_QUEUE_CAPACITY,
            CommitAdmissionPolicy {
                warn_after: DEFAULT_COMMIT_QUEUE_WARN,
                timeout: DEFAULT_COMMIT_QUEUE_TIMEOUT,
            },
        ));

        let ks = kill_switch.clone();
        let completed = completed_version.clone();

        let join_handle = spawn_efficient("moor-batch-writer", move || {
            Self::writer_loop(db, receiver, ks, completed, property_names)
        })
        .expect("failed to spawn batch writer thread");

        let encoder_count = Self::encoder_thread_count();
        let mut encoder_handles = Vec::with_capacity(encoder_count);
        for index in 0..encoder_count {
            let receiver = encoder_receiver.clone();
            let sender = sender.clone();
            let handle =
                moor_common::threading::spawn_perf(format!("moor-db-enc-{index}"), move || {
                    Self::encoder_loop(receiver, sender)
                })
                .expect("failed to spawn batch encoder thread");
            encoder_handles.push(handle);
        }

        Self {
            sender,
            encoder_sender,
            kill_switch,
            completed_version,
            join_handle: Mutex::new(Some(join_handle)),
            encoder_handles: Mutex::new(encoder_handles),
            admission,
        }
    }

    fn encoder_thread_count() -> usize {
        std::thread::available_parallelism()
            .map(|cores| cores.get().div_ceil(8).clamp(1, MAX_ENCODER_THREADS))
            .unwrap_or(1)
    }

    fn encoder_loop(
        receiver: Receiver<EncoderMsg>,
        sender: Sender<WriterMsg>,
    ) -> Result<(), String> {
        let mut encoder = BatchEncoder::new();
        loop {
            let msg = receiver
                .recv()
                .map_err(|_| "batch encoder channel disconnected".to_string())?;
            let EncoderMsg::Commit { batch, admission } = msg else {
                return Ok(());
            };
            drop(admission);

            let encoded = Self::encode_batch(batch, &mut encoder);
            sender
                .send(WriterMsg::Commit(encoded))
                .map_err(|_| "batch writer channel disconnected".to_string())?;
        }
    }

    fn writer_loop(
        db: fjall::Database,
        receiver: Receiver<WriterMsg>,
        kill_switch: Arc<AtomicBool>,
        completed_version: Arc<AtomicU64>,
        property_names: AHashMap<Uuid, Symbol>,
    ) -> Result<(), String> {
        let result = Self::run_writer(db, receiver, kill_switch, completed_version, property_names);
        if let Err(error) = &result {
            error!("Batch writer failed: {error}");
            #[cfg(not(test))]
            moor_common::util::signal_fatal_db_error("batch writer", error);
        }
        result
    }

    fn run_writer(
        db: fjall::Database,
        receiver: Receiver<WriterMsg>,
        kill_switch: Arc<AtomicBool>,
        completed_version: Arc<AtomicU64>,
        property_names: AHashMap<Uuid, Symbol>,
    ) -> Result<(), String> {
        let mut state = WriterState::new(property_names);

        loop {
            if kill_switch.load(Ordering::Relaxed) {
                while let Ok(msg) = receiver.try_recv() {
                    Self::handle_message(
                        &db,
                        msg,
                        &mut state,
                        completed_version.load(Ordering::Acquire),
                    )?;
                    Self::persist_ready(&db, &mut state, &completed_version)?;
                }

                if !state.waiting_batches.is_empty() {
                    let error = format!(
                        "batch writer stopped with a gap before version {}",
                        state.next_version
                    );
                    Self::fail_waiters(&mut state, &error);
                    return Err(error);
                }

                Self::reply_ready_barriers(&mut state, completed_version.load(Ordering::Acquire));
                Self::reply_ready_snapshots(
                    &db,
                    &mut state,
                    completed_version.load(Ordering::Acquire),
                );
                return Ok(());
            }

            match receiver.recv_timeout(RECEIVE_POLL_INTERVAL) {
                Ok(msg) => {
                    Self::handle_message(
                        &db,
                        msg,
                        &mut state,
                        completed_version.load(Ordering::Acquire),
                    )?;
                    Self::persist_ready(&db, &mut state, &completed_version)?;
                }
                Err(flume::RecvTimeoutError::Timeout) => {}
                Err(flume::RecvTimeoutError::Disconnected) => {
                    let error = "batch writer channel disconnected".to_string();
                    Self::fail_waiters(&mut state, &error);
                    return Err(error);
                }
            }
        }
    }

    fn handle_message(
        db: &fjall::Database,
        msg: WriterMsg,
        state: &mut WriterState,
        completed_version: u64,
    ) -> Result<(), String> {
        match msg {
            WriterMsg::Commit(batch) => state.add_batch(batch),
            WriterMsg::Barrier {
                through_version,
                reply,
            } => {
                if through_version <= completed_version {
                    reply.send(Ok(())).ok();
                } else {
                    state.barrier_waiters.push((through_version, reply));
                }
                Ok(())
            }
            WriterMsg::Snapshot {
                through_version,
                reply,
            } => {
                if through_version <= completed_version {
                    reply.send(Ok(db.snapshot())).ok();
                } else {
                    state.snapshot_waiters.push((through_version, reply));
                }
                Ok(())
            }
        }
    }

    fn persist_ready(
        db: &fjall::Database,
        state: &mut WriterState,
        completed_version: &AtomicU64,
    ) -> Result<(), String> {
        while let Some(batch) = state.waiting_batches.remove(&state.next_version) {
            let batch = match batch {
                Ok(batch) => batch,
                Err(error) => {
                    Self::fail_waiters(state, &error);
                    return Err(error);
                }
            };
            let version = batch.version;
            if let Err(error) = Self::commit_batch(db, batch, &mut state.property_names) {
                Self::fail_waiters(state, &error);
                return Err(error);
            }

            completed_version.store(version, Ordering::Release);
            state.next_version += 1;
            Self::reply_ready_barriers(state, version);
            Self::reply_ready_snapshots(db, state, version);
        }
        Ok(())
    }

    fn encode_batch(batch: CommitBatch, encoder: &mut BatchEncoder) -> EncodedBatchResult {
        let version = batch.version;
        let result = (|| {
            let CommitBatch {
                version,
                timestamp,
                operations,
                property_definition_changes,
            } = batch;
            let start = Instant::now();
            let mut encoded_bytes = 0usize;
            let mut slowest = None;
            let mut encoded_operations = Vec::with_capacity(operations.len());

            for op in operations {
                let BatchOp {
                    partition,
                    op_type,
                    source,
                } = op;
                let op_type = match op_type {
                    BatchOpType::Insert { key, value } => {
                        let op_start = Instant::now();
                        let value = value
                            .encode(timestamp, encoder)
                            .map_err(|error| format!("failed to encode batch value: {error}"))?;
                        let elapsed = op_start.elapsed();
                        let bytes = key.len() + value.len();
                        encoded_bytes += bytes;
                        if slowest
                            .as_ref()
                            .is_none_or(|(_, slowest_elapsed, _)| elapsed > *slowest_elapsed)
                        {
                            slowest = Some((source, elapsed, bytes));
                        }
                        EncodedBatchOpType::Insert { key, value }
                    }
                    BatchOpType::Delete { key } => {
                        encoded_bytes += key.len();
                        EncodedBatchOpType::Delete { key }
                    }
                };
                encoded_operations.push(EncodedBatchOp { partition, op_type });
            }

            let elapsed = start.elapsed();
            db_counters()
                .timers_rare
                .record_elapsed(WorldStateTimerOp::BatchWriterEncode, elapsed);

            Ok(EncodedCommitBatch {
                version,
                timestamp,
                operations: encoded_operations,
                property_definition_changes,
                encoding: EncodingStats {
                    elapsed,
                    encoded_bytes,
                    slowest,
                },
            })
        })();

        EncodedBatchResult { version, result }
    }

    fn commit_batch(
        db: &fjall::Database,
        batch: EncodedCommitBatch,
        property_names: &mut PropertyNames,
    ) -> Result<(), String> {
        let EncodedCommitBatch {
            version,
            timestamp,
            operations,
            property_definition_changes,
            encoding,
        } = batch;
        let transaction = timestamp.0;
        let op_count = operations.len();
        let mut write_batch = db.batch();

        for op in operations {
            let EncodedBatchOp { partition, op_type } = op;
            match op_type {
                EncodedBatchOpType::Insert { key, value } => {
                    write_batch.insert(&partition, key, value);
                }
                EncodedBatchOpType::Delete { key } => {
                    write_batch.remove(&partition, key);
                }
            }
        }

        let outstanding_flushes_before = db.outstanding_flushes();
        let active_compactions_before = db.active_compactions();
        let commit_start = Instant::now();
        write_batch
            .commit()
            .map_err(|error| format!("failed to commit Fjall write batch: {error}"))?;
        let commit_elapsed = commit_start.elapsed();
        db_counters()
            .timers_rare
            .record_elapsed(WorldStateTimerOp::BatchWriterCommit, commit_elapsed);
        property_names.apply(property_definition_changes);

        if encoding.elapsed > ENCODE_WARNING_DURATION
            && let Some((slowest_target, slowest_encode_elapsed, slowest_encoded_bytes)) =
                encoding.slowest
        {
            let slowest_target = property_names.display(&slowest_target);
            warn!(
                op_count,
                encoded_bytes = encoding.encoded_bytes,
                version,
                transaction,
                encode_elapsed = ?encoding.elapsed,
                ?commit_elapsed,
                slowest_target = %slowest_target,
                ?slowest_encode_elapsed,
                slowest_encoded_bytes,
                outstanding_flushes_before,
                outstanding_flushes_after = db.outstanding_flushes(),
                active_compactions_before,
                active_compactions_after = db.active_compactions(),
                "Slow batch encoding. This value used the most encoding time. Split large property values across properties."
            );
        } else if commit_elapsed > WRITE_WARNING_DURATION {
            warn!(
                op_count,
                encoded_bytes = encoding.encoded_bytes,
                version,
                transaction,
                encode_elapsed = ?encoding.elapsed,
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

    fn reply_ready_barriers(state: &mut WriterState, completed_version: u64) {
        let mut pending = Vec::with_capacity(state.barrier_waiters.len());
        for (version, reply) in state.barrier_waiters.drain(..) {
            if version <= completed_version {
                reply.send(Ok(())).ok();
            } else {
                pending.push((version, reply));
            }
        }
        state.barrier_waiters = pending;
    }

    fn reply_ready_snapshots(
        db: &fjall::Database,
        state: &mut WriterState,
        completed_version: u64,
    ) {
        let mut pending = Vec::with_capacity(state.snapshot_waiters.len());
        for (version, reply) in state.snapshot_waiters.drain(..) {
            if version <= completed_version {
                reply.send(Ok(db.snapshot())).ok();
            } else {
                pending.push((version, reply));
            }
        }
        state.snapshot_waiters = pending;
    }

    fn fail_waiters(state: &mut WriterState, detail: &str) {
        for (_, reply) in state.barrier_waiters.drain(..) {
            reply.send(Err(detail.to_string())).ok();
        }
        for (_, reply) in state.snapshot_waiters.drain(..) {
            reply.send(Err(detail.to_string())).ok();
        }
    }

    pub(crate) fn admit_commit(
        &self,
        transaction: Timestamp,
    ) -> Result<CommitAdmission, CommitAdmissionError> {
        self.admission.acquire(transaction)
    }

    pub(crate) fn set_commit_queue_policy(&self, warn_after: Duration, timeout: Duration) {
        self.admission.set_policy(warn_after, timeout);
    }

    #[cfg(test)]
    pub(crate) fn hold_all_admission(&self) -> Vec<CommitAdmission> {
        (0..self.admission.capacity)
            .map(|index| {
                self.admit_commit(Timestamp(index as u64))
                    .expect("test should be able to reserve the configured admission capacity")
            })
            .collect()
    }

    pub fn write(&self, batch: CommitBatch, admission: CommitAdmission) -> Result<(), String> {
        self.encoder_sender
            .try_send(EncoderMsg::Commit { batch, admission })
            .map_err(|error| match error {
                flume::TrySendError::Full(_) => {
                    "batch encoder queue full after admission was reserved".to_string()
                }
                flume::TrySendError::Disconnected(_) => {
                    "batch encoder channel disconnected".to_string()
                }
            })
    }

    pub fn completed_version(&self) -> u64 {
        self.completed_version.load(Ordering::Acquire)
    }

    /// Wait until Fjall has accepted every transaction through `through_version`.
    ///
    /// This does not request an fsync or wait for memtable flushing or compaction.
    pub fn wait_for_version(&self, through_version: u64) -> Result<(), String> {
        let (reply, receiver) = oneshot::channel();
        self.sender
            .send(WriterMsg::Barrier {
                through_version,
                reply,
            })
            .map_err(|_| "batch writer channel disconnected".to_string())?;
        receiver.recv().map_err(|error| {
            format!("failed waiting for Fjall through version {through_version}: {error}")
        })?
    }

    pub fn snapshot(
        &self,
        through_version: u64,
        timeout: Duration,
    ) -> Result<fjall::Snapshot, String> {
        let (reply, receiver) = oneshot::channel();
        let msg = WriterMsg::Snapshot {
            through_version,
            reply,
        };
        self.sender
            .send(msg)
            .map_err(|_| "batch writer channel disconnected".to_string())?;
        receiver.recv_timeout(timeout).map_err(|error| {
            format!(
                "timed out waiting for Fjall snapshot through version {through_version}: {error}"
            )
        })?
    }

    pub fn stop(&self) -> Result<(), String> {
        let mut encoder_error = None;
        let mut encoder_handles = self.encoder_handles.lock();
        for _ in 0..encoder_handles.len() {
            self.encoder_sender.send(EncoderMsg::Stop).ok();
        }
        for handle in encoder_handles.drain(..) {
            match handle.join() {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    encoder_error.get_or_insert(error);
                }
                Err(_) => {
                    encoder_error.get_or_insert("batch encoder thread panicked".to_string());
                }
            };
        }
        drop(encoder_handles);

        self.kill_switch.store(true, Ordering::SeqCst);
        let mut jh = self.join_handle.lock();
        if let Some(handle) = jh.take() {
            let writer_result = handle
                .join()
                .map_err(|_| "batch writer thread panicked".to_string())?;
            writer_result?;
        }
        encoder_error.map_or(Ok(()), Err)
    }
}

impl Drop for BatchWriter {
    fn drop(&mut self) {
        if let Err(error) = self.stop() {
            error!("Failed to stop batch writer: {error}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fjall::{KeyspaceCreateOptions, Readable};
    use moor_common::model::PropDef;

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

    fn write(writer: &BatchWriter, batch: CommitBatch) -> Result<(), String> {
        let admission = writer
            .admit_commit(batch.timestamp)
            .map_err(|error| error.to_string())?;
        writer.write(batch, admission)
    }

    #[test]
    fn admission_times_out_and_recovers_without_waiting_forever() {
        let gate = CommitAdmissionGate::new(
            1,
            CommitAdmissionPolicy {
                warn_after: Duration::from_millis(1),
                timeout: Duration::from_millis(10),
            },
        );
        let held = gate.acquire(Timestamp(1)).unwrap();

        let error = match gate.acquire(Timestamp(2)) {
            Ok(_) => panic!("admission unexpectedly succeeded while its only permit was held"),
            Err(error) => error,
        };
        assert!(matches!(error, CommitAdmissionError::Timeout { .. }));

        drop(held);
        assert!(gate.acquire(Timestamp(3)).is_ok());
    }

    #[test]
    fn property_source_uses_writer_local_name() {
        let object = Obj::mk_id(42);
        let uuid = Uuid::new_v4();
        let source = BatchOpSource::Property {
            relation: "object_propvalues",
            object,
            uuid,
        };
        let name = Symbol::mk("context");
        let definition = PropDef::new(uuid, object, object, name);
        let mut property_names = PropertyNames::new(AHashMap::new());
        property_names.apply(vec![PropertyDefinitionChange::Upsert(definition)]);

        let rendered = property_names.display(&source).to_string();
        assert!(rendered.contains("object_propvalues"));
        assert!(rendered.contains("context"));
        assert!(rendered.contains(&uuid.to_string()));

        let renamed = PropDef::new(uuid, object, object, Symbol::mk("history"));
        property_names.apply(vec![PropertyDefinitionChange::Upsert(renamed)]);
        let rendered = property_names.display(&source).to_string();
        assert!(rendered.contains("history"));
        assert!(!rendered.contains("context"));

        property_names.apply(vec![PropertyDefinitionChange::Remove(uuid)]);
        let rendered = property_names.display(&source).to_string();
        assert!(!rendered.contains("context"));
        assert!(rendered.contains(&uuid.to_string()));
    }

    #[test]
    fn transaction_is_committed_before_snapshot() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);

        write(&writer, encoded_batch(1, &partition, b"key", b"value")).unwrap();
        let snapshot = writer.snapshot(1, Duration::from_secs(1)).unwrap();

        assert_eq!(writer.completed_version(), 1);
        assert_eq!(
            snapshot.get(&partition, b"key").unwrap().as_deref(),
            Some(&b"value"[..])
        );
    }

    #[test]
    fn persistence_barrier_waits_for_transaction() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);

        write(&writer, encoded_batch(1, &partition, b"key", b"value")).unwrap();
        writer.wait_for_version(1).unwrap();

        assert_eq!(writer.completed_version(), 1);
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

        write(&writer, encoded_batch(2, &partition, b"key", b"newer")).unwrap();
        assert_eq!(writer.completed_version(), 0);

        write(&writer, encoded_batch(1, &partition, b"key", b"older")).unwrap();
        let snapshot = writer.snapshot(2, Duration::from_secs(1)).unwrap();

        assert_eq!(
            snapshot.get(&partition, b"key").unwrap().as_deref(),
            Some(&b"newer"[..])
        );
    }

    #[test]
    fn separate_transactions_use_separate_fjall_batches() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database.clone());
        let initial_seqno = database.visible_seqno();

        write(&writer, encoded_batch(1, &partition, b"key", b"first")).unwrap();
        write(&writer, encoded_batch(2, &partition, b"key", b"second")).unwrap();
        let snapshot = writer.snapshot(2, Duration::from_secs(1)).unwrap();

        assert_eq!(database.visible_seqno(), initial_seqno + 2);
        assert_eq!(
            snapshot.get(&partition, b"key").unwrap().as_deref(),
            Some(&b"second"[..])
        );
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

        write(&writer, batch).unwrap();
        let snapshot = writer.snapshot(1, Duration::from_secs(1)).unwrap();

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
        fn encode(
            self: Box<Self>,
            _timestamp: Timestamp,
            _encoder: &mut BatchEncoder,
        ) -> Result<fjall::Slice, Error> {
            Err(Error::EncodingFailure)
        }
    }

    #[test]
    fn failed_encoding_does_not_complete_snapshot_boundary() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let writer = BatchWriter::new(database);
        let mut batch = CommitBatch::with_capacity(2, Timestamp(2), 1);
        batch.insert(partition.clone(), b"key".to_vec(), Box::new(FailingValue));

        write(&writer, batch).unwrap();

        let (reply, receiver) = oneshot::channel();
        writer
            .sender
            .send(WriterMsg::Snapshot {
                through_version: 2,
                reply,
            })
            .unwrap();

        write(&writer, encoded_batch(1, &partition, b"other", b"value")).unwrap();
        let error = match receiver.recv_timeout(Duration::from_secs(1)).unwrap() {
            Ok(_) => panic!("snapshot unexpectedly succeeded"),
            Err(error) => error,
        };

        assert!(error.contains("failed to encode batch value"));
        assert_eq!(writer.completed_version(), 1);
        assert_eq!(partition.get(b"key").unwrap(), None);
    }
}
