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
use moor_var::{Obj, Symbol, Var};
use parking_lot::Mutex;
use tracing::{error, warn};
use uuid::Uuid;

use crate::{
    DEFAULT_COMMIT_QUEUE_TIMEOUT, DEFAULT_COMMIT_QUEUE_WARN, ObjAndUUIDHolder, db_counters,
    engine::property_definitions::PropertyDefinitionChange,
    provider::property_value_store::{
        PROPERTY_RECORD_KEY_BYTES, PreparedPropertyValueMutation, PreparedPropertyValueOp,
        PropertyValueChain, PropertyValueChainLimits, encode_full_record,
        encode_list_append_record, encode_property_value_record_key,
        property_value_record_payload_bytes,
    },
    tx::{Error, Timestamp},
};
use moor_common::model::{WorldStateCountOp, WorldStateTimerOp};

#[cfg(test)]
use crate::provider::property_value_store::PROPERTY_VALUE_CHAIN_LIMITS;

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
    PropertyValue(PreparedPropertyValueOp),
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
    PropertyValue(EncodedPropertyValueOp),
}

struct EncodedPropertyValueOp {
    property: ObjAndUUIDHolder,
    mutation: EncodedPropertyValueMutation,
}

enum EncodedPropertyValueMutation {
    Replace {
        record: fjall::Slice,
    },
    AppendList {
        record: fjall::Slice,
        payload_bytes: usize,
        final_value: Var,
    },
    Delete,
}

enum PropertyValueChainChange {
    Reset {
        property: ObjAndUUIDHolder,
        full_version: u64,
    },
    Append {
        property: ObjAndUUIDHolder,
        record_version: u64,
        payload_bytes: usize,
    },
    Delete(ObjAndUUIDHolder),
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

enum RollupMsg {
    Encode {
        value: Var,
        timestamp: Timestamp,
        reply: oneshot::Sender<Result<RollupResult, String>>,
    },
    Stop,
}

struct RollupResult {
    record: fjall::Slice,
    elapsed: Duration,
}

#[derive(Clone)]
struct RollupEncoder {
    sender: Sender<RollupMsg>,
}

impl RollupEncoder {
    fn encode(&self, value: Var, timestamp: Timestamp) -> Result<RollupResult, String> {
        let (reply, receiver) = oneshot::channel();
        self.sender
            .send(RollupMsg::Encode {
                value,
                timestamp,
                reply,
            })
            .map_err(|_| "property-value rollup encoder disconnected".to_string())?;
        receiver
            .recv()
            .map_err(|error| format!("property-value rollup encoder failed to reply: {error}"))?
    }
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
    property_value_chains: AHashMap<ObjAndUUIDHolder, PropertyValueChain>,
    property_value_limits: PropertyValueChainLimits,
    next_property_value_record_version: u64,
}

struct WriterInit {
    property_names: AHashMap<Uuid, Symbol>,
    property_value_chains: AHashMap<ObjAndUUIDHolder, PropertyValueChain>,
    property_value_limits: PropertyValueChainLimits,
    rollup_encoder: RollupEncoder,
}

impl WriterState {
    fn new(
        property_names: AHashMap<Uuid, Symbol>,
        property_value_chains: AHashMap<ObjAndUUIDHolder, PropertyValueChain>,
        property_value_limits: PropertyValueChainLimits,
    ) -> Self {
        let next_property_value_record_version = property_value_chains
            .values()
            .flat_map(PropertyValueChain::record_versions)
            .max()
            .map_or(1, |version| version.saturating_add(1));
        Self {
            waiting_batches: BTreeMap::new(),
            barrier_waiters: Vec::new(),
            snapshot_waiters: Vec::new(),
            next_version: 1,
            property_names: PropertyNames::new(property_names),
            property_value_chains,
            property_value_limits,
            next_property_value_record_version,
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
    rollup_sender: Sender<RollupMsg>,
    rollup_handle: Mutex<Option<JoinHandle<Result<(), String>>>>,
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

    #[cfg(test)]
    pub(crate) fn with_property_names(
        db: fjall::Database,
        property_names: AHashMap<Uuid, Symbol>,
    ) -> Self {
        Self::with_property_value_state(
            db,
            property_names,
            AHashMap::new(),
            PROPERTY_VALUE_CHAIN_LIMITS,
        )
    }

    pub(crate) fn with_property_value_state(
        db: fjall::Database,
        property_names: AHashMap<Uuid, Symbol>,
        property_value_chains: AHashMap<ObjAndUUIDHolder, PropertyValueChain>,
        property_value_limits: PropertyValueChainLimits,
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
        let (rollup_sender, rollup_receiver) = flume::bounded::<RollupMsg>(1);
        let rollup_handle = moor_common::threading::spawn_perf("moor-db-rollup-enc", move || {
            Self::rollup_encoder_loop(rollup_receiver)
        })
        .expect("failed to spawn property-value rollup encoder thread");
        let rollup_encoder = RollupEncoder {
            sender: rollup_sender.clone(),
        };

        let ks = kill_switch.clone();
        let completed = completed_version.clone();

        let join_handle = spawn_efficient("moor-batch-writer", move || {
            Self::writer_loop(
                db,
                receiver,
                ks,
                completed,
                WriterInit {
                    property_names,
                    property_value_chains,
                    property_value_limits,
                    rollup_encoder,
                },
            )
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
            rollup_sender,
            rollup_handle: Mutex::new(Some(rollup_handle)),
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

    fn rollup_encoder_loop(receiver: Receiver<RollupMsg>) -> Result<(), String> {
        let mut encoder = BatchEncoder::new();
        loop {
            let msg = receiver
                .recv()
                .map_err(|_| "property-value rollup encoder channel disconnected".to_string())?;
            let RollupMsg::Encode {
                value,
                timestamp,
                reply,
            } = msg
            else {
                return Ok(());
            };

            let start = Instant::now();
            let result = encode_full_record(encoder.var_builder(), &value, timestamp)
                .map(|record| RollupResult {
                    record: record.into(),
                    elapsed: start.elapsed(),
                })
                .map_err(|error| format!("failed to encode property-value rollup: {error}"));
            reply.send(result).ok();
        }
    }

    fn writer_loop(
        db: fjall::Database,
        receiver: Receiver<WriterMsg>,
        kill_switch: Arc<AtomicBool>,
        completed_version: Arc<AtomicU64>,
        init: WriterInit,
    ) -> Result<(), String> {
        let result = Self::run_writer(db, receiver, kill_switch, completed_version, init);
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
        init: WriterInit,
    ) -> Result<(), String> {
        let WriterInit {
            property_names,
            property_value_chains,
            property_value_limits,
            rollup_encoder,
        } = init;
        let mut state =
            WriterState::new(property_names, property_value_chains, property_value_limits);

        loop {
            if kill_switch.load(Ordering::Relaxed) {
                while let Ok(msg) = receiver.try_recv() {
                    Self::handle_message(
                        &db,
                        msg,
                        &mut state,
                        completed_version.load(Ordering::Acquire),
                    )?;
                    Self::persist_ready(&db, &mut state, &completed_version, &rollup_encoder)?;
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
                    Self::persist_ready(&db, &mut state, &completed_version, &rollup_encoder)?;
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
        rollup_encoder: &RollupEncoder,
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
            if let Err(error) = Self::commit_batch(db, batch, state, rollup_encoder) {
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
                    BatchOpType::PropertyValue(prepared) => {
                        let op_start = Instant::now();
                        let PreparedPropertyValueOp { property, mutation } = prepared;
                        let mutation = match mutation {
                            PreparedPropertyValueMutation::Replace { value } => {
                                let record =
                                    encode_full_record(encoder.var_builder(), &value, timestamp)
                                        .map_err(|error| {
                                            format!(
                                                "failed to encode complete property value: {error}"
                                            )
                                        })?;
                                db_counters().counters.add(
                                    WorldStateCountOp::PropertyValueFullEncodedBytes,
                                    isize::try_from(record.len()).unwrap_or(isize::MAX),
                                );
                                EncodedPropertyValueMutation::Replace {
                                    record: record.into(),
                                }
                            }
                            PreparedPropertyValueMutation::AppendList {
                                suffix,
                                final_value,
                            } => {
                                let record = encode_list_append_record(
                                    encoder.var_builder(),
                                    &suffix,
                                    timestamp,
                                )
                                .map_err(|error| {
                                    format!("failed to encode property list append: {error}")
                                })?;
                                let payload_bytes = property_value_record_payload_bytes(&record)
                                    .map_err(|error| {
                                        format!(
                                            "failed to inspect encoded property list append: {error}"
                                        )
                                    })?;
                                db_counters().counters.add(
                                    WorldStateCountOp::PropertyValueAppendEncodedBytes,
                                    isize::try_from(record.len()).unwrap_or(isize::MAX),
                                );
                                EncodedPropertyValueMutation::AppendList {
                                    record: record.into(),
                                    payload_bytes,
                                    final_value,
                                }
                            }
                            PreparedPropertyValueMutation::Delete => {
                                EncodedPropertyValueMutation::Delete
                            }
                        };
                        let elapsed = op_start.elapsed();
                        let bytes = match &mutation {
                            EncodedPropertyValueMutation::Replace { record }
                            | EncodedPropertyValueMutation::AppendList { record, .. } => {
                                PROPERTY_RECORD_KEY_BYTES + record.len()
                            }
                            EncodedPropertyValueMutation::Delete => PROPERTY_RECORD_KEY_BYTES,
                        };
                        encoded_bytes += bytes;
                        if slowest
                            .as_ref()
                            .is_none_or(|(_, slowest_elapsed, _)| elapsed > *slowest_elapsed)
                        {
                            slowest = Some((source, elapsed, bytes));
                        }
                        EncodedBatchOpType::PropertyValue(EncodedPropertyValueOp {
                            property,
                            mutation,
                        })
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
        state: &mut WriterState,
        rollup_encoder: &RollupEncoder,
    ) -> Result<(), String> {
        let EncodedCommitBatch {
            version,
            timestamp,
            operations,
            property_definition_changes,
            mut encoding,
        } = batch;
        let transaction = timestamp.0;
        let mut write_batch = db.batch();
        let mut property_value_changes = Vec::new();
        let property_value_record_version = state.next_property_value_record_version;

        for op in operations {
            let EncodedBatchOp { partition, op_type } = op;
            match op_type {
                EncodedBatchOpType::Insert { key, value } => {
                    write_batch.insert(&partition, key, value);
                }
                EncodedBatchOpType::Delete { key } => {
                    write_batch.remove(&partition, key);
                }
                EncodedBatchOpType::PropertyValue(op) => {
                    let EncodedPropertyValueOp { property, mutation } = op;
                    let previous_chain = state.property_value_chains.get(&property);
                    match mutation {
                        EncodedPropertyValueMutation::Replace { record } => {
                            let key = encode_property_value_record_key(
                                &property,
                                property_value_record_version,
                            );
                            write_batch.insert(&partition, key, record);
                            if let Some(chain) = previous_chain {
                                for old_version in chain.record_versions() {
                                    let key =
                                        encode_property_value_record_key(&property, old_version);
                                    write_batch.remove(&partition, key);
                                    encoding.encoded_bytes += PROPERTY_RECORD_KEY_BYTES;
                                }
                            }
                            property_value_changes.push(PropertyValueChainChange::Reset {
                                property,
                                full_version: property_value_record_version,
                            });
                        }
                        EncodedPropertyValueMutation::AppendList {
                            record,
                            payload_bytes,
                            final_value,
                        } => {
                            let Some(chain) = previous_chain else {
                                return Err(format!(
                                    "property-value append for {property} has no complete record"
                                ));
                            };
                            if chain.reaches_limit(payload_bytes, state.property_value_limits) {
                                let rollup = rollup_encoder.encode(final_value, timestamp)?;
                                db_counters().timers_rare.record_elapsed(
                                    WorldStateTimerOp::PropertyValueRollupEncode,
                                    rollup.elapsed,
                                );
                                db_counters()
                                    .counters
                                    .inc(WorldStateCountOp::PropertyValueForegroundRollup);
                                db_counters().counters.add(
                                    WorldStateCountOp::PropertyValueFullEncodedBytes,
                                    isize::try_from(rollup.record.len()).unwrap_or(isize::MAX),
                                );
                                encoding.elapsed += rollup.elapsed;
                                encoding.encoded_bytes +=
                                    PROPERTY_RECORD_KEY_BYTES + rollup.record.len();
                                let source = BatchOpSource::Property {
                                    relation: "object_propvalues",
                                    object: property.obj(),
                                    uuid: property.uuid(),
                                };
                                if encoding.slowest.as_ref().is_none_or(
                                    |(_, slowest_elapsed, _)| rollup.elapsed > *slowest_elapsed,
                                ) {
                                    encoding.slowest = Some((
                                        source,
                                        rollup.elapsed,
                                        PROPERTY_RECORD_KEY_BYTES + rollup.record.len(),
                                    ));
                                }

                                let key = encode_property_value_record_key(
                                    &property,
                                    property_value_record_version,
                                );
                                write_batch.insert(&partition, key, rollup.record);
                                for old_version in chain.record_versions() {
                                    let key =
                                        encode_property_value_record_key(&property, old_version);
                                    write_batch.remove(&partition, key);
                                    encoding.encoded_bytes += PROPERTY_RECORD_KEY_BYTES;
                                }
                                property_value_changes.push(PropertyValueChainChange::Reset {
                                    property,
                                    full_version: property_value_record_version,
                                });
                            } else {
                                let key = encode_property_value_record_key(
                                    &property,
                                    property_value_record_version,
                                );
                                write_batch.insert(&partition, key, record);
                                property_value_changes.push(PropertyValueChainChange::Append {
                                    property,
                                    record_version: property_value_record_version,
                                    payload_bytes,
                                });
                            }
                        }
                        EncodedPropertyValueMutation::Delete => {
                            if let Some(chain) = previous_chain {
                                for old_version in chain.record_versions() {
                                    let key =
                                        encode_property_value_record_key(&property, old_version);
                                    write_batch.remove(&partition, key);
                                    encoding.encoded_bytes += PROPERTY_RECORD_KEY_BYTES;
                                }
                            }
                            property_value_changes.push(PropertyValueChainChange::Delete(property));
                        }
                    }
                }
            }
        }

        let op_count = write_batch.len();
        let next_property_value_record_version = if property_value_changes.is_empty() {
            None
        } else {
            Some(
                property_value_record_version
                    .checked_add(1)
                    .ok_or_else(|| "property-value record version exhausted".to_string())?,
            )
        };

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
        state.property_names.apply(property_definition_changes);
        for change in property_value_changes {
            match change {
                PropertyValueChainChange::Reset {
                    property,
                    full_version,
                } => {
                    state
                        .property_value_chains
                        .insert(property, PropertyValueChain::full(full_version));
                }
                PropertyValueChainChange::Append {
                    property,
                    record_version,
                    payload_bytes,
                } => {
                    state
                        .property_value_chains
                        .get_mut(&property)
                        .expect("validated property-value append chain")
                        .push_append(record_version, payload_bytes);
                }
                PropertyValueChainChange::Delete(property) => {
                    state.property_value_chains.remove(&property);
                }
            }
        }
        if let Some(next_property_value_record_version) = next_property_value_record_version {
            state.next_property_value_record_version = next_property_value_record_version;
        }

        if encoding.elapsed > ENCODE_WARNING_DURATION
            && let Some((slowest_target, slowest_encode_elapsed, slowest_encoded_bytes)) =
                encoding.slowest
        {
            let slowest_target = state.property_names.display(&slowest_target);
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
        let mut shutdown_error = None;
        let mut encoder_handles = self.encoder_handles.lock();
        for _ in 0..encoder_handles.len() {
            self.encoder_sender.send(EncoderMsg::Stop).ok();
        }
        for handle in encoder_handles.drain(..) {
            match handle.join() {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    shutdown_error.get_or_insert(error);
                }
                Err(_) => {
                    shutdown_error.get_or_insert("batch encoder thread panicked".to_string());
                }
            };
        }
        drop(encoder_handles);

        self.kill_switch.store(true, Ordering::SeqCst);
        let mut jh = self.join_handle.lock();
        if let Some(handle) = jh.take() {
            match handle.join() {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    shutdown_error.get_or_insert(error);
                }
                Err(_) => {
                    shutdown_error.get_or_insert("batch writer thread panicked".to_string());
                }
            }
        }
        drop(jh);

        let mut rollup_handle = self.rollup_handle.lock();
        if let Some(handle) = rollup_handle.take() {
            self.rollup_sender.send(RollupMsg::Stop).ok();
            match handle.join() {
                Ok(Ok(())) => {}
                Ok(Err(error)) => {
                    shutdown_error.get_or_insert(error);
                }
                Err(_) => {
                    shutdown_error
                        .get_or_insert("property-value rollup encoder thread panicked".to_string());
                }
            }
        }

        shutdown_error.map_or(Ok(()), Err)
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
    use crate::provider::property_value_store::{
        PropertyValueReconstructor, encode_property_value_record_key,
    };
    use fjall::{KeyspaceCreateOptions, Readable};
    use moor_common::model::PropDef;
    use moor_var::{List, v_int, v_list};

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

    fn property_batch(
        version: u64,
        partition: &fjall::Keyspace,
        property: &ObjAndUUIDHolder,
        mutation: PreparedPropertyValueMutation,
    ) -> CommitBatch {
        CommitBatch::from_ops(
            version,
            Timestamp(version),
            vec![BatchOp {
                partition: partition.clone(),
                op_type: BatchOpType::PropertyValue(PreparedPropertyValueOp {
                    property: property.clone(),
                    mutation,
                }),
                source: BatchOpSource::Property {
                    relation: "object_propvalues",
                    object: property.obj(),
                    uuid: property.uuid(),
                },
            }],
        )
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

    #[test]
    fn property_appends_roll_up_in_publication_order() {
        let (_tempdir, database) = test_database();
        let partition = database
            .keyspace("object_propvalues", KeyspaceCreateOptions::default)
            .unwrap();
        let limits = PropertyValueChainLimits::new(2, usize::MAX);
        let writer = BatchWriter::with_property_value_state(
            database,
            AHashMap::new(),
            AHashMap::new(),
            limits,
        );
        let property = ObjAndUUIDHolder::new(&Obj::mk_id(42), Uuid::from_u128(7));

        write(
            &writer,
            property_batch(
                2,
                &partition,
                &property,
                PreparedPropertyValueMutation::AppendList {
                    suffix: List::mk_list(&[v_int(2)]),
                    final_value: v_list(&[v_int(1), v_int(2)]),
                },
            ),
        )
        .unwrap();
        write(
            &writer,
            property_batch(
                1,
                &partition,
                &property,
                PreparedPropertyValueMutation::Replace {
                    value: v_list(&[v_int(1)]),
                },
            ),
        )
        .unwrap();

        let before_rollup = writer.snapshot(2, Duration::from_secs(2)).unwrap();
        let full_record = before_rollup
            .get(&partition, encode_property_value_record_key(&property, 1))
            .unwrap()
            .expect("complete record");
        let append_record = before_rollup
            .get(&partition, encode_property_value_record_key(&property, 2))
            .unwrap()
            .expect("append record");
        let mut reconstructor = PropertyValueReconstructor::new(limits);
        reconstructor.push(1, &full_record).unwrap();
        reconstructor.push(2, &append_record).unwrap();
        let reconstructed = reconstructor.finish().unwrap();
        assert_eq!(reconstructed.value, v_list(&[v_int(1), v_int(2)]));
        assert_eq!(reconstructed.chain.append_count(), 1);

        write(
            &writer,
            property_batch(
                3,
                &partition,
                &property,
                PreparedPropertyValueMutation::AppendList {
                    suffix: List::mk_list(&[v_int(3)]),
                    final_value: v_list(&[v_int(1), v_int(2), v_int(3)]),
                },
            ),
        )
        .unwrap();
        let after_rollup = writer.snapshot(3, Duration::from_secs(2)).unwrap();
        assert!(
            before_rollup
                .get(&partition, encode_property_value_record_key(&property, 1))
                .unwrap()
                .is_some()
        );
        assert!(
            before_rollup
                .get(&partition, encode_property_value_record_key(&property, 2))
                .unwrap()
                .is_some()
        );
        assert_eq!(
            before_rollup
                .get(&partition, encode_property_value_record_key(&property, 3))
                .unwrap(),
            None
        );
        assert_eq!(
            after_rollup
                .get(&partition, encode_property_value_record_key(&property, 1))
                .unwrap(),
            None
        );
        assert_eq!(
            after_rollup
                .get(&partition, encode_property_value_record_key(&property, 2))
                .unwrap(),
            None
        );
        let record = after_rollup
            .get(&partition, encode_property_value_record_key(&property, 3))
            .unwrap()
            .expect("rollup record");
        let mut reconstructor = PropertyValueReconstructor::new(limits);
        reconstructor.push(3, &record).unwrap();
        let reconstructed = reconstructor.finish().unwrap();
        assert_eq!(reconstructed.logical_timestamp, Timestamp(3));
        assert_eq!(reconstructed.value, v_list(&[v_int(1), v_int(2), v_int(3)]));
        assert_eq!(reconstructed.chain, PropertyValueChain::full(3));
    }

    #[test]
    fn rollup_encoding_does_not_use_the_writer_queue() {
        let (writer_sender, _writer_receiver) = flume::bounded::<WriterMsg>(1);
        let (barrier_reply, _barrier_receiver) = oneshot::channel();
        writer_sender
            .send(WriterMsg::Barrier {
                through_version: 1,
                reply: barrier_reply,
            })
            .unwrap();
        assert!(writer_sender.is_full());

        let (rollup_sender, rollup_receiver) = flume::bounded(1);
        let handle = std::thread::spawn(move || BatchWriter::rollup_encoder_loop(rollup_receiver));
        let encoder = RollupEncoder {
            sender: rollup_sender.clone(),
        };
        let encoded = encoder
            .encode(v_list(&[v_int(1), v_int(2)]), Timestamp(9))
            .unwrap();
        assert!(!encoded.record.is_empty());
        assert!(writer_sender.is_full());

        rollup_sender.send(RollupMsg::Stop).unwrap();
        handle.join().unwrap().unwrap();
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
