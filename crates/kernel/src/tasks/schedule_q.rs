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

//! Native scheduled tasks: a *record of intent* (target, verb, when, how often)
//! held by the scheduler, from which a fresh task is created at each firing.
//!
//! This module is the pure data structure. It owns no lock and touches no
//! world state; `Scheduler` wraps it, drives `expired()` from the timer loop,
//! and calls `mark_fired`/`complete` from the task completion callbacks.
//!
//! Deadlines are wall-clock (`SystemTime`) so they survive a restart; the
//! timer wheel is monotonic (`Instant`) and is re-derived from wall clock on
//! load. Each wheel entry carries a generation stamp so an entry left behind by
//! an earlier arm of the same schedule is ignored, exactly as `SuspensionQ`
//! does for suspended tasks.

use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use hierarchical_hash_wheel_timer::wheels::{
    Skip, TimerEntryWithDelay,
    quad_wheel::{PruneDecision, QuadWheelWithOverflow},
};
use moor_common::tasks::TaskId;
use moor_var::{ByteSized, List, Obj, Symbol, Var, v_bool, v_float, v_int, v_map, v_str};
use rand::RngExt;

use crate::vm::extract_anonymous_refs_from_var;

pub type ScheduleId = u64;

/// Upper bound on the serialized size of the per-schedule `state` slot. An
/// unbounded slot would recreate the hot-property problem in scheduler memory.
pub const MAX_STATE_BYTES: usize = 4096;

/// How many firing durations to keep for `mean_duration`/`p99_duration`.
const DURATION_SAMPLES: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScheduleKind {
    /// Fire once at a deadline. Under the adaptive protocol the verb may
    /// re-arm itself by returning a positive number of seconds.
    At,
    /// Fire every `interval`, deadlines computed from the previous deadline
    /// (drift-free), not from completion time.
    Every { interval: Duration },
}

/// What to do about firings that were missed: after a restart, after a stall,
/// or after a slow firing under `OverlapPolicy::Skip`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CatchupPolicy {
    /// Advance to the next future deadline on cadence; count the misses.
    #[default]
    Skip,
    /// Fire once immediately, then resume cadence.
    Once,
    /// Fire once per missed interval.
    All,
}

/// What to do when a deadline arrives while the previous firing is still running.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OverlapPolicy {
    /// Drop the new firing; count it in `overlap_count`.
    #[default]
    Skip,
    /// Run it as soon as the current firing completes.
    Queue,
    /// Fire anyway.
    Concurrent,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ScheduleOptions {
    /// Enable the return-value protocol (a numeric return sets the next delay).
    pub adaptive: bool,
    pub catchup: CatchupPolicy,
    pub overlap: OverlapPolicy,
    /// Randomise each deadline by up to ± this much.
    pub jitter: Duration,
    /// Consecutive faults before retirement. `None` = unlimited.
    pub max_faults: Option<u32>,
    /// Append real seconds since the previous firing to the verb's args.
    pub pass_elapsed: bool,
    /// Opaque per-schedule value handed to the verb.
    pub state: Option<Var>,
    /// Whether the schedule survives a restart.
    pub persist: bool,
    /// `player` inside the fired verb. `None` = the target.
    pub player: Option<Obj>,
}

impl ScheduleOptions {
    /// The defaults from the proposal: the return protocol is on for one-shots
    /// (that is what it was designed for) and off for recurring schedules
    /// (the cadence is what the author asked for).
    pub fn for_kind(kind: &ScheduleKind) -> Self {
        Self {
            adaptive: matches!(kind, ScheduleKind::At),
            catchup: CatchupPolicy::Skip,
            overlap: OverlapPolicy::Skip,
            jitter: Duration::ZERO,
            max_faults: Some(50),
            pass_elapsed: true,
            state: None,
            persist: true,
            player: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScheduleError {
    InvalidInterval,
    InvalidWhen,
    StateTooLarge(usize),
}

impl fmt::Display for ScheduleError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ScheduleError::InvalidInterval => write!(f, "schedule interval must be > 0"),
            ScheduleError::InvalidWhen => write!(f, "schedule deadline is not representable"),
            ScheduleError::StateTooLarge(n) => {
                write!(f, "schedule state is {n} bytes; limit is {MAX_STATE_BYTES}")
            }
        }
    }
}

impl std::error::Error for ScheduleError {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RetireReason {
    /// A non-adaptive one-shot fired.
    OneShotDone,
    /// An adaptive one-shot declined to reschedule by returning 0.
    ReturnedZero,
    /// An adaptive verb returned a negative number.
    NegativeReturn,
    /// `max_faults` consecutive faults.
    MaxFaults,
    /// Target recycled, verb gone, or principal invalid at firing time.
    InvalidTarget,
}

impl RetireReason {
    pub fn as_str(&self) -> &'static str {
        match self {
            RetireReason::OneShotDone => "one_shot_done",
            RetireReason::ReturnedZero => "returned_zero",
            RetireReason::NegativeReturn => "negative_return",
            RetireReason::MaxFaults => "max_faults",
            RetireReason::InvalidTarget => "invalid_target",
        }
    }
}

/// How a firing ended, as reported by the scheduler's completion callbacks.
#[derive(Debug, Clone)]
pub enum Outcome {
    Success(Var),
    Fault(Var),
}

/// What `complete` decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Completion {
    Rearmed(SystemTime),
    Retired(RetireReason),
}

/// A schedule creation a task has requested but not yet committed. The id is
/// allocated eagerly so the builtin can return it; the entry is inserted only
/// when the creating task commits (see `ScheduleQ::add_pending`).
#[derive(Debug, Clone)]
pub struct PendingCreate {
    pub id: ScheduleId,
    pub kind: PendingKind,
    pub target: Obj,
    pub verb: Symbol,
    pub args: List,
    pub authority_principal: Obj,
    pub owner: Obj,
    pub options: ScheduleOptions,
}

#[derive(Debug, Clone, Copy)]
pub enum PendingKind {
    At(SystemTime),
    Every(Duration),
}

#[derive(Debug, Clone)]
pub struct ScheduleEntry {
    pub id: ScheduleId,
    pub target: Obj,
    pub verb: Symbol,
    pub args: List,
    /// The creating task's permissions, captured once. Governs verb lookup
    /// and `caller_perms()`; the verb itself runs as its owner as always.
    pub authority_principal: Obj,
    pub owner: Obj,
    pub kind: ScheduleKind,
    pub options: ScheduleOptions,
    pub created_at: SystemTime,
    /// `None` once retired.
    pub next_run: Option<SystemTime>,
    /// The cadence point the current arm was computed from (pre-jitter), so
    /// `Every` stays in phase regardless of firing duration or jitter.
    pub scheduled_deadline: Option<SystemTime>,
    pub last_run: Option<SystemTime>,
    pub last_duration: Option<Duration>,
    pub run_count: u64,
    pub fault_count: u64,
    pub consecutive_faults: u32,
    pub last_fault: Option<Var>,
    pub missed_count: u64,
    pub overlap_count: u64,
    pub running_task: Option<TaskId>,
    /// Set under `OverlapPolicy::Queue` when a deadline arrived mid-firing.
    pub queued_firing: bool,
    pub interval_clamped: bool,
    pub retired: Option<RetireReason>,
    durations: VecDeque<Duration>,
}

impl ScheduleEntry {
    /// Rebuild an entry from persisted fields. Runtime-only state
    /// (`running_task`, `queued_firing`, duration samples, `last_fault`)
    /// starts empty; `ScheduleQ::load` then applies the catchup policy.
    #[allow(clippy::too_many_arguments)]
    pub fn from_persisted(
        id: ScheduleId,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        kind: ScheduleKind,
        options: ScheduleOptions,
        created_at: SystemTime,
        next_run: Option<SystemTime>,
        scheduled_deadline: Option<SystemTime>,
        last_run: Option<SystemTime>,
        run_count: u64,
        fault_count: u64,
        consecutive_faults: u32,
        missed_count: u64,
        overlap_count: u64,
        interval_clamped: bool,
    ) -> Self {
        Self {
            id,
            target,
            verb,
            args,
            authority_principal,
            owner,
            kind,
            options,
            created_at,
            next_run,
            scheduled_deadline,
            last_run,
            last_duration: None,
            run_count,
            fault_count,
            consecutive_faults,
            last_fault: None,
            missed_count,
            overlap_count,
            running_task: None,
            queued_firing: false,
            interval_clamped,
            retired: None,
            durations: VecDeque::new(),
        }
    }

    pub fn is_live(&self) -> bool {
        self.next_run.is_some()
    }

    pub fn mean_duration(&self) -> Option<Duration> {
        if self.durations.is_empty() {
            return None;
        }
        let total: Duration = self.durations.iter().sum();
        Some(total / self.durations.len() as u32)
    }

    pub fn p99_duration(&self) -> Option<Duration> {
        if self.durations.is_empty() {
            return None;
        }
        let mut sorted: Vec<Duration> = self.durations.iter().copied().collect();
        sorted.sort();
        let idx = ((sorted.len() as f64) * 0.99).ceil() as usize;
        sorted
            .get(idx.saturating_sub(1).min(sorted.len() - 1))
            .copied()
    }

    fn push_duration(&mut self, d: Duration) {
        if self.durations.len() == DURATION_SAMPLES {
            self.durations.pop_front();
        }
        self.durations.push_back(d);
        self.last_duration = Some(d);
    }

    /// The `schedule_info()` map. String keys: not every core has symbols on.
    pub fn to_info_map(&self) -> Var {
        fn secs(t: Option<SystemTime>) -> Var {
            v_float(
                t.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                    .map(|d| d.as_secs_f64())
                    .unwrap_or(0.0),
            )
        }
        fn nanos(d: Option<Duration>) -> Var {
            v_int(d.map(|d| d.as_nanos() as i64).unwrap_or(0))
        }
        let (kind, interval) = match self.kind {
            ScheduleKind::At => ("at", 0.0),
            ScheduleKind::Every { interval } => ("every", interval.as_secs_f64()),
        };
        let catchup = match self.options.catchup {
            CatchupPolicy::Skip => "skip",
            CatchupPolicy::Once => "once",
            CatchupPolicy::All => "all",
        };
        let overlap = match self.options.overlap {
            OverlapPolicy::Skip => "skip",
            OverlapPolicy::Queue => "queue",
            OverlapPolicy::Concurrent => "concurrent",
        };
        let pairs = [
            (v_str("id"), v_int(self.id as i64)),
            (v_str("target"), Var::from(self.target)),
            (v_str("verb"), v_str(&self.verb.as_string())),
            (v_str("args"), Var::from(self.args.clone())),
            (v_str("owner"), Var::from(self.owner)),
            (v_str("authority"), Var::from(self.authority_principal)),
            (v_str("created_at"), secs(Some(self.created_at))),
            (v_str("kind"), v_str(kind)),
            (v_str("interval"), v_float(interval)),
            (v_str("next_run"), secs(self.next_run)),
            (v_str("last_run"), secs(self.last_run)),
            (v_str("last_duration_ns"), nanos(self.last_duration)),
            (v_str("run_count"), v_int(self.run_count as i64)),
            (v_str("fault_count"), v_int(self.fault_count as i64)),
            (
                v_str("consecutive_faults"),
                v_int(self.consecutive_faults as i64),
            ),
            (
                v_str("last_fault"),
                self.last_fault.clone().unwrap_or_else(|| v_int(0)),
            ),
            (v_str("missed_count"), v_int(self.missed_count as i64)),
            (v_str("overlap_count"), v_int(self.overlap_count as i64)),
            (v_str("mean_duration_ns"), nanos(self.mean_duration())),
            (v_str("p99_duration_ns"), nanos(self.p99_duration())),
            (
                v_str("state"),
                self.options.state.clone().unwrap_or_else(|| v_int(0)),
            ),
            (
                v_str("running_task"),
                v_int(self.running_task.map(|t| t as i64).unwrap_or(0)),
            ),
            (v_str("interval_clamped"), v_bool(self.interval_clamped)),
            (v_str("retired"), v_bool(self.retired.is_some())),
            (
                v_str("retire_reason"),
                v_str(self.retired.map(|r| r.as_str()).unwrap_or("")),
            ),
            (v_str("adaptive"), v_bool(self.options.adaptive)),
            (v_str("catchup"), v_str(catchup)),
            (v_str("overlap"), v_str(overlap)),
            (v_str("jitter"), v_float(self.options.jitter.as_secs_f64())),
            (
                v_str("max_faults"),
                v_int(self.options.max_faults.map(|n| n as i64).unwrap_or(0)),
            ),
            (v_str("pass_elapsed"), v_bool(self.options.pass_elapsed)),
            (v_str("persist"), v_bool(self.options.persist)),
            (
                v_str("player"),
                Var::from(self.options.player.unwrap_or(self.target)),
            ),
        ];
        v_map(&pairs)
    }
}

/// Wheel entry. `generation` is compared against the schedule's current
/// generation on expiry so a stale entry from an earlier arm is discarded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ScheduleTimerEntry {
    id: ScheduleId,
    delay: Duration,
    generation: u64,
}

impl TimerEntryWithDelay for ScheduleTimerEntry {
    fn delay(&self) -> Duration {
        self.delay
    }
}

pub struct ScheduleQ {
    entries: HashMap<ScheduleId, ScheduleEntry>,
    wheel: QuadWheelWithOverflow<ScheduleTimerEntry>,
    /// Current generation per live schedule; entries in the wheel with an
    /// older generation are ignored.
    generations: HashMap<ScheduleId, u64>,
    next_generation: u64,
    /// Schedules whose deadline was already past when armed: fire on the
    /// next `expired()` without going through the wheel.
    immediate: Vec<ScheduleId>,
    next_id: ScheduleId,
    by_owner: HashMap<Obj, HashSet<ScheduleId>>,
    by_target: HashMap<Obj, HashSet<ScheduleId>>,
    by_task: HashMap<TaskId, ScheduleId>,
    /// The scheduler tick. Intervals below it are clamped to it and flagged.
    tick: Duration,
    last_advance: Option<Instant>,
}

impl ScheduleQ {
    pub fn new(tick: Duration) -> Self {
        Self {
            entries: HashMap::new(),
            wheel: QuadWheelWithOverflow::new(|_| PruneDecision::Keep),
            generations: HashMap::new(),
            next_generation: 0,
            immediate: Vec::new(),
            next_id: 1,
            by_owner: HashMap::new(),
            by_target: HashMap::new(),
            by_task: HashMap::new(),
            tick,
            last_advance: None,
        }
    }

    // ---- creation -------------------------------------------------------

    /// Allocate an id without inserting anything. Used by the buffered
    /// creation path: the builtin returns this id immediately, and the entry
    /// is inserted by `add_pending` when the creating task commits. A rolled
    /// back task simply never uses the id.
    pub fn reserve_id(&mut self) -> ScheduleId {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Insert a previously reserved creation. Errors here (interval, state
    /// size) were validated when the builtin was called, so they are
    /// logged and dropped rather than surfaced.
    pub fn add_pending(&mut self, pending: PendingCreate, now: SystemTime) {
        let PendingCreate {
            id,
            kind,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
        } = pending;
        let result = match kind {
            PendingKind::At(when) => self.insert_at(
                id,
                when,
                target,
                verb,
                args,
                authority_principal,
                owner,
                options,
                now,
            ),
            PendingKind::Every(interval) => self.insert_every(
                id,
                interval,
                target,
                verb,
                args,
                authority_principal,
                owner,
                options,
                now,
            ),
        };
        if let Err(e) = result {
            tracing::warn!(schedule_id = id, error = %e, "Dropping pending schedule at commit");
        }
    }

    /// One-shot at `when`. A `when` in the past fires on the next `expired()`.
    #[allow(clippy::too_many_arguments)]
    pub fn add_at(
        &mut self,
        when: SystemTime,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
        now: SystemTime,
    ) -> Result<ScheduleId, ScheduleError> {
        Self::validate_state(&options)?;
        let id = self.reserve_id();
        self.insert_at(
            id,
            when,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
            now,
        )?;
        Ok(id)
    }

    /// Recurring every `interval`, first firing at `now + interval`.
    /// `interval == 0` is an error; `interval < tick` is clamped and flagged.
    #[allow(clippy::too_many_arguments)]
    pub fn add_every(
        &mut self,
        interval: Duration,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
        now: SystemTime,
    ) -> Result<ScheduleId, ScheduleError> {
        if interval == Duration::ZERO {
            return Err(ScheduleError::InvalidInterval);
        }
        Self::validate_state(&options)?;
        let id = self.reserve_id();
        self.insert_every(
            id,
            interval,
            target,
            verb,
            args,
            authority_principal,
            owner,
            options,
            now,
        )?;
        Ok(id)
    }

    /// Validate what a builtin can validate before buffering a creation.
    pub fn validate_every(
        &self,
        interval: Duration,
        options: &ScheduleOptions,
    ) -> Result<(), ScheduleError> {
        if interval == Duration::ZERO {
            return Err(ScheduleError::InvalidInterval);
        }
        Self::validate_state(options)
    }

    /// Validate what a builtin can validate before buffering a one-shot.
    pub fn validate_at(&self, options: &ScheduleOptions) -> Result<(), ScheduleError> {
        Self::validate_state(options)
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_at(
        &mut self,
        id: ScheduleId,
        when: SystemTime,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
        now: SystemTime,
    ) -> Result<(), ScheduleError> {
        Self::validate_state(&options)?;
        let entry = ScheduleEntry {
            id,
            target,
            verb,
            args,
            authority_principal,
            owner,
            kind: ScheduleKind::At,
            options,
            created_at: now,
            next_run: Some(when),
            scheduled_deadline: Some(when),
            last_run: None,
            last_duration: None,
            run_count: 0,
            fault_count: 0,
            consecutive_faults: 0,
            last_fault: None,
            missed_count: 0,
            overlap_count: 0,
            running_task: None,
            queued_firing: false,
            interval_clamped: false,
            retired: None,
            durations: VecDeque::new(),
        };
        self.entries.insert(id, entry);
        self.by_owner.entry(owner).or_default().insert(id);
        self.by_target.entry(target).or_default().insert(id);
        self.arm(id, when, now);
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn insert_every(
        &mut self,
        id: ScheduleId,
        interval: Duration,
        target: Obj,
        verb: Symbol,
        args: List,
        authority_principal: Obj,
        owner: Obj,
        options: ScheduleOptions,
        now: SystemTime,
    ) -> Result<(), ScheduleError> {
        if interval == Duration::ZERO {
            return Err(ScheduleError::InvalidInterval);
        }
        Self::validate_state(&options)?;
        let mut interval_clamped = false;
        let mut interval = interval;
        if interval < self.tick {
            interval = self.tick;
            interval_clamped = true;
        }
        let first = now.checked_add(interval).unwrap_or(now);
        let jittered_first = self.jittered(first, options.jitter, now);
        let entry = ScheduleEntry {
            id,
            target,
            verb,
            args,
            authority_principal,
            owner,
            kind: ScheduleKind::Every { interval },
            options,
            created_at: now,
            next_run: Some(jittered_first),
            scheduled_deadline: Some(first),
            last_run: None,
            last_duration: None,
            run_count: 0,
            fault_count: 0,
            consecutive_faults: 0,
            last_fault: None,
            missed_count: 0,
            overlap_count: 0,
            running_task: None,
            queued_firing: false,
            interval_clamped,
            retired: None,
            durations: VecDeque::new(),
        };
        self.entries.insert(id, entry);
        self.by_owner.entry(owner).or_default().insert(id);
        self.by_target.entry(target).or_default().insert(id);
        self.arm(id, jittered_first, now);
        Ok(())
    }

    // ---- queries --------------------------------------------------------

    /// Exists and is not retired.
    pub fn is_valid(&self, id: ScheduleId) -> bool {
        self.entries.get(&id).is_some_and(|e| e.is_live())
    }

    /// `Some` for retired-but-not-purged entries too, so retirement is visible.
    pub fn info(&self, id: ScheduleId) -> Option<&ScheduleEntry> {
        self.entries.get(&id)
    }

    pub fn for_owner(&self, owner: &Obj) -> Vec<ScheduleId> {
        let mut v: Vec<_> = self
            .by_owner
            .get(owner)
            .map(|s| s.iter().copied().collect())
            .unwrap_or_default();
        v.sort_unstable();
        v
    }

    pub fn for_target(&self, target: &Obj) -> Vec<ScheduleId> {
        let mut v: Vec<_> = self
            .by_target
            .get(target)
            .map(|s| s.iter().copied().collect())
            .unwrap_or_default();
        v.sort_unstable();
        v
    }

    pub fn all_ids(&self) -> Vec<ScheduleId> {
        let mut v: Vec<_> = self.entries.keys().copied().collect();
        v.sort_unstable();
        v
    }

    pub fn schedule_for_task(&self, task: TaskId) -> Option<ScheduleId> {
        self.by_task.get(&task).copied()
    }

    /// Live, persistable entries (for the tasks database).
    pub fn persistable(&self) -> impl Iterator<Item = &ScheduleEntry> {
        self.entries
            .values()
            .filter(|e| e.options.persist && e.is_live())
    }

    // ---- lifecycle ------------------------------------------------------

    /// Cancel and forget. `false` for an unknown or already-retired id: a
    /// stale id is an ordinary race, not an error.
    pub fn stop(&mut self, id: ScheduleId) -> bool {
        if !self.is_valid(id) {
            return false;
        }
        let Some(entry) = self.entries.remove(&id) else {
            return false;
        };
        self.generations.remove(&id);
        if let Some(set) = self.by_owner.get_mut(&entry.owner) {
            set.remove(&id);
            if set.is_empty() {
                self.by_owner.remove(&entry.owner);
            }
        }
        if let Some(set) = self.by_target.get_mut(&entry.target) {
            set.remove(&id);
            if set.is_empty() {
                self.by_target.remove(&entry.target);
            }
        }
        if let Some(task) = entry.running_task {
            self.by_task.remove(&task);
        }
        self.immediate.retain(|&i| i != id);
        true
    }

    /// Stop scheduling but keep the entry so `info()` shows why.
    pub fn retire(&mut self, id: ScheduleId, reason: RetireReason) {
        let Some(entry) = self.entries.get_mut(&id) else {
            return;
        };
        entry.next_run = None;
        entry.retired = Some(reason);
        let running_task = entry.running_task.take();
        entry.queued_firing = false;
        let owner = entry.owner;
        let target = entry.target;
        self.generations.remove(&id);
        if let Some(set) = self.by_owner.get_mut(&owner) {
            set.remove(&id);
            if set.is_empty() {
                self.by_owner.remove(&owner);
            }
        }
        if let Some(set) = self.by_target.get_mut(&target) {
            set.remove(&id);
            if set.is_empty() {
                self.by_target.remove(&target);
            }
        }
        if let Some(task) = running_task {
            self.by_task.remove(&task);
        }
        self.immediate.retain(|&i| i != id);
    }

    /// Drop every retired entry.
    pub fn purge_retired(&mut self) {
        self.entries.retain(|_, e| e.is_live());
    }

    /// Advance the wheel to `now` and return the schedules to fire, after
    /// dropping stale generations and applying each entry's overlap policy.
    pub fn expired(&mut self, now: Instant, now_sys: SystemTime) -> Vec<ScheduleId> {
        let mut ids: Vec<ScheduleId> = std::mem::take(&mut self.immediate);
        for e in self.advance_wheel(now) {
            if self.generations.get(&e.id) == Some(&e.generation) {
                ids.push(e.id);
            }
        }
        // Dedupe while preserving order.
        let mut seen = HashSet::new();
        ids.retain(|id| seen.insert(*id));

        let mut kept = Vec::with_capacity(ids.len());
        for id in ids {
            let is_live = self.entries.get(&id).is_some_and(|e| e.is_live());
            if !is_live {
                continue;
            }
            let running = self.entries.get(&id).and_then(|e| e.running_task);
            if running.is_some() {
                let overlap = self.entries.get(&id).unwrap().options.overlap;
                match overlap {
                    OverlapPolicy::Skip => {
                        let entry = self.entries.get_mut(&id).unwrap();
                        entry.overlap_count += 1;
                        if let ScheduleKind::Every { interval } = entry.kind {
                            let base = entry.scheduled_deadline.unwrap_or(now_sys);
                            let jitter = entry.options.jitter;
                            let mut next = base.checked_add(interval).unwrap_or(base);
                            while next <= now_sys {
                                next = next.checked_add(interval).unwrap_or(next);
                            }
                            entry.scheduled_deadline = Some(next);
                            let jittered = self.jittered(next, jitter, now_sys);
                            self.arm(id, jittered, now_sys);
                        }
                    }
                    OverlapPolicy::Queue => {
                        if let Some(entry) = self.entries.get_mut(&id) {
                            entry.queued_firing = true;
                        }
                    }
                    OverlapPolicy::Concurrent => {
                        kept.push(id);
                    }
                }
            } else {
                kept.push(id);
            }
        }
        kept
    }

    /// Record that `id` is now running as `task`. Returns the elapsed time
    /// since the previous firing (for `pass_elapsed`); `None` on the first.
    pub fn mark_fired(
        &mut self,
        id: ScheduleId,
        task: TaskId,
        fired_at: SystemTime,
    ) -> Option<Duration> {
        let entry = self.entries.get_mut(&id)?;
        if !entry.is_live() {
            return None;
        }
        let elapsed = entry
            .last_run
            .map(|l| fired_at.duration_since(l).unwrap_or(Duration::ZERO));
        entry.running_task = Some(task);
        self.by_task.insert(task, id);
        entry.last_run = Some(fired_at);
        elapsed
    }

    /// Record the outcome of a firing and re-arm or retire.
    pub fn complete(
        &mut self,
        id: ScheduleId,
        outcome: Outcome,
        finished_at: SystemTime,
    ) -> Option<Completion> {
        // The entry may have been stopped mid-flight.
        if !self.entries.contains_key(&id) {
            return None;
        }

        // Clear running-task bookkeeping first.
        {
            let entry = self.entries.get_mut(&id).unwrap();
            if let Some(t) = entry.running_task.take() {
                self.by_task.remove(&t);
            }
            let duration = entry
                .last_run
                .map(|l| finished_at.duration_since(l).unwrap_or(Duration::ZERO))
                .unwrap_or(Duration::ZERO);
            entry.push_duration(duration);
        }

        // Record the outcome.
        match &outcome {
            Outcome::Success(_) => {
                let entry = self.entries.get_mut(&id).unwrap();
                entry.run_count += 1;
                entry.consecutive_faults = 0;
            }
            Outcome::Fault(v) => {
                let entry = self.entries.get_mut(&id).unwrap();
                entry.fault_count += 1;
                entry.consecutive_faults += 1;
                entry.last_fault = Some(v.clone());
                if entry.options.max_faults == Some(entry.consecutive_faults) {
                    self.retire(id, RetireReason::MaxFaults);
                    return Some(Completion::Retired(RetireReason::MaxFaults));
                }
            }
        }

        // Someone else retired it while it was running.
        if let Some(reason) = self.entries.get(&id).unwrap().retired {
            return Some(Completion::Retired(reason));
        }

        let entry = self.entries.get(&id).unwrap();
        let base = entry
            .scheduled_deadline
            .unwrap_or_else(|| entry.last_run.unwrap_or(finished_at));
        let adaptive = entry.options.adaptive;
        let jitter = entry.options.jitter;
        let kind = entry.kind;
        let queued_firing = entry.queued_firing;

        if adaptive
            && let Outcome::Success(v) = &outcome
            && let Some(n) = v.as_float_numeric()
        {
            if n > 0.0 {
                let delta = Duration::from_secs_f64(if n.is_finite() { n } else { 0.0 });
                let next = base.checked_add(delta).unwrap_or(base);
                let entry = self.entries.get_mut(&id).unwrap();
                entry.scheduled_deadline = Some(next);
                let jittered = self.jittered(next, jitter, finished_at);
                self.arm(id, jittered, finished_at);
                return Some(Completion::Rearmed(next));
            } else if n == 0.0 {
                match kind {
                    ScheduleKind::At => {
                        self.retire(id, RetireReason::ReturnedZero);
                        return Some(Completion::Retired(RetireReason::ReturnedZero));
                    }
                    ScheduleKind::Every { .. } => {
                        // fall through to cadence
                    }
                }
            } else {
                let entry = self.entries.get_mut(&id).unwrap();
                entry.fault_count += 1;
                self.retire(id, RetireReason::NegativeReturn);
                return Some(Completion::Retired(RetireReason::NegativeReturn));
            }
        }

        match kind {
            ScheduleKind::At => {
                self.retire(id, RetireReason::OneShotDone);
                Some(Completion::Retired(RetireReason::OneShotDone))
            }
            ScheduleKind::Every { interval } => {
                let mut next = base.checked_add(interval).unwrap_or(base);
                if queued_firing {
                    let entry = self.entries.get_mut(&id).unwrap();
                    entry.queued_firing = false;
                    next = finished_at;
                } else {
                    let catchup = self.entries.get(&id).unwrap().options.catchup;
                    loop {
                        if next > finished_at {
                            break;
                        }
                        match catchup {
                            CatchupPolicy::Skip => {
                                next = next.checked_add(interval).unwrap_or(next);
                                let entry = self.entries.get_mut(&id).unwrap();
                                entry.missed_count += 1;
                            }
                            CatchupPolicy::Once => {
                                next = finished_at;
                                break;
                            }
                            CatchupPolicy::All => break,
                        }
                    }
                }
                let entry = self.entries.get_mut(&id).unwrap();
                entry.scheduled_deadline = Some(next);
                let jittered = self.jittered(next, jitter, finished_at);
                self.arm(id, jittered, finished_at);
                let next_run = self.entries.get(&id).unwrap().next_run.unwrap_or(next);
                Some(Completion::Rearmed(next_run))
            }
        }
    }

    /// Restore an entry from persistence. Past deadlines go through the
    /// catchup policy; the id counter is floored above the loaded id.
    pub fn load(&mut self, mut entry: ScheduleEntry, now: SystemTime) {
        if entry.id >= self.next_id {
            self.next_id = entry.id + 1;
        }
        let id = entry.id;
        self.by_owner.entry(entry.owner).or_default().insert(id);
        self.by_target.entry(entry.target).or_default().insert(id);
        entry.running_task = None;
        entry.queued_firing = false;

        if entry.retired.is_some() || entry.next_run.is_none() {
            self.entries.insert(id, entry);
            return;
        }

        let deadline = entry.next_run.unwrap();
        let deadline = if deadline <= now {
            match (entry.kind, entry.options.catchup) {
                (ScheduleKind::Every { interval }, CatchupPolicy::Skip) => {
                    let mut d = deadline;
                    while d <= now {
                        d = d.checked_add(interval).unwrap_or(d);
                        entry.missed_count += 1;
                    }
                    d
                }
                (_, CatchupPolicy::Once) | (ScheduleKind::At, _) => now,
                (ScheduleKind::Every { .. }, CatchupPolicy::All) => deadline,
            }
        } else {
            deadline
        };
        entry.scheduled_deadline = Some(deadline);
        self.entries.insert(id, entry);
        self.arm(id, deadline, now);
    }

    /// Schedules are GC roots for anonymous objects: target, args, state,
    /// and the last fault value.
    pub fn collect_anonymous_object_references(&self, refs: &mut HashSet<Obj>) {
        for e in self.entries.values() {
            if e.target.is_anonymous() {
                refs.insert(e.target);
            }
            for a in e.args.iter_ref() {
                extract_anonymous_refs_from_var(a, refs);
            }
            if let Some(s) = &e.options.state {
                extract_anonymous_refs_from_var(s, refs);
            }
            if let Some(f) = &e.last_fault {
                extract_anonymous_refs_from_var(f, refs);
            }
        }
    }

    // ---- internals ------------------------------------------------------

    fn validate_state(options: &ScheduleOptions) -> Result<(), ScheduleError> {
        if let Some(s) = &options.state {
            let n = s.size_bytes();
            if n > MAX_STATE_BYTES {
                return Err(ScheduleError::StateTooLarge(n));
            }
        }
        Ok(())
    }

    /// Arm `id` for `deadline`: bump generation, insert into the wheel (or
    /// the immediate list if the deadline has passed).
    fn arm(&mut self, id: ScheduleId, deadline: SystemTime, now: SystemTime) {
        self.next_generation += 1;
        let generation = self.next_generation;
        self.generations.insert(id, generation);
        if deadline <= now {
            self.immediate.push(id);
        } else {
            let delay = deadline.duration_since(now).unwrap_or(Duration::ZERO);
            let timer_entry = ScheduleTimerEntry {
                id,
                delay,
                generation,
            };
            if let Err(e) = self.wheel.insert_with_delay(timer_entry, delay) {
                tracing::warn!(
                    "ScheduleQ: failed to arm schedule {id} (delay {delay:?}): {e:?}; \
                     firing immediately as a fallback"
                );
                self.immediate.push(id);
            }
        }
        if let Some(entry) = self.entries.get_mut(&id) {
            entry.next_run = Some(deadline);
        }
    }

    /// `deadline ± jitter`, never earlier than `floor + tick`.
    fn jittered(&self, deadline: SystemTime, jitter: Duration, floor: SystemTime) -> SystemTime {
        if jitter == Duration::ZERO {
            return deadline;
        }
        let jitter_secs = jitter.as_secs_f64();
        let mut rng = rand::rng();
        let offset_secs = rng.random_range(-jitter_secs..=jitter_secs);
        let result = if offset_secs >= 0.0 {
            deadline
                .checked_add(Duration::from_secs_f64(offset_secs))
                .unwrap_or(deadline)
        } else {
            deadline
                .checked_sub(Duration::from_secs_f64(-offset_secs))
                .unwrap_or(deadline)
        };
        let min = floor.checked_add(self.tick).unwrap_or(floor);
        if result < min { min } else { result }
    }

    /// Copy of `SuspensionQ::advance_timer_wheel`, parameterised by `now`.
    fn advance_wheel(&mut self, now: Instant) -> Vec<ScheduleTimerEntry> {
        let last = self.last_advance.unwrap_or(now);
        if now <= last {
            self.last_advance = Some(now);
            return Vec::new();
        }
        let elapsed_millis = now.duration_since(last).as_millis() as u32;
        let mut remaining = elapsed_millis;
        let mut expired = Vec::new();
        while remaining > 0 {
            match self.wheel.can_skip() {
                Skip::Empty => {
                    self.wheel.skip(remaining);
                    break;
                }
                Skip::Millis(skippable) => {
                    let to_skip = skippable.min(remaining);
                    self.wheel.skip(to_skip);
                    remaining -= to_skip;
                }
                Skip::None => {
                    expired.extend(self.wheel.tick());
                    remaining -= 1;
                }
            }
        }
        self.last_advance = Some(last + Duration::from_millis(elapsed_millis as u64));
        expired
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target() -> Obj {
        Obj::mk_id(100)
    }
    fn owner() -> Obj {
        Obj::mk_id(1)
    }
    fn verb() -> Symbol {
        Symbol::mk("heartbeat")
    }
    fn args() -> List {
        List::mk_list(&[])
    }
    fn at_opts() -> ScheduleOptions {
        ScheduleOptions::for_kind(&ScheduleKind::At)
    }
    fn every_opts(interval: Duration) -> ScheduleOptions {
        ScheduleOptions::for_kind(&ScheduleKind::Every { interval })
    }
    fn t0() -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(1_700_000_000)
    }

    // ---- 1: drift-free cadence -------------------------------------------

    #[test]
    fn drift_free_every() {
        let tick = Duration::from_millis(10);
        let mut q = ScheduleQ::new(tick);
        let t0 = t0();
        let i0 = Instant::now();
        q.expired(i0, t0); // prime last_advance
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                every_opts(Duration::from_secs(1)),
                t0,
            )
            .unwrap();
        for k in 0..100u64 {
            let now_i = i0 + Duration::from_secs(k + 1);
            let now_t = t0 + Duration::from_secs(k + 1);
            let ids = q.expired(now_i, now_t);
            assert!(ids.contains(&id), "iteration {k}: {ids:?}");
            q.mark_fired(id, k as TaskId, now_t);
            let finished = now_t + Duration::from_millis(200);
            q.complete(id, Outcome::Success(v_int(0)), finished);
            let entry = q.info(id).unwrap();
            assert_eq!(
                entry.scheduled_deadline,
                Some(t0 + Duration::from_secs(k + 2)),
                "iteration {k}"
            );
        }
    }

    // ---- 2: catchup policies ----------------------------------------------

    #[test]
    fn catchup_skip() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::Skip;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let finished = deadline + Duration::from_millis(3500);
        q.complete(id, Outcome::Success(v_int(0)), finished);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.missed_count, 3);
        assert_eq!(
            entry.scheduled_deadline,
            Some(deadline + Duration::from_secs(4))
        );
    }

    #[test]
    fn catchup_once() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::Once;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let finished = deadline + Duration::from_millis(3500);
        q.complete(id, Outcome::Success(v_int(0)), finished);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.scheduled_deadline, Some(finished));
    }

    #[test]
    fn catchup_all() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::All;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let finished = deadline + Duration::from_millis(3500);
        q.complete(id, Outcome::Success(v_int(0)), finished);
        let entry = q.info(id).unwrap();
        assert_eq!(
            entry.scheduled_deadline,
            Some(deadline + Duration::from_secs(1))
        );
        // Left in the past by arm(), so it lands in `immediate` right away.
        let ids = q.expired(Instant::now(), finished);
        assert!(ids.contains(&id));
    }

    // ---- 3: overlap policies ------------------------------------------------

    #[test]
    fn overlap_skip() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Skip;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        q.mark_fired(id, 1, t0 + Duration::from_secs(1));
        let now2 = t0 + Duration::from_secs(3);
        q.arm(id, now2, now2);
        let ids = q.expired(Instant::now(), now2);
        assert!(!ids.contains(&id));
        let entry = q.info(id).unwrap();
        assert_eq!(entry.overlap_count, 1);
        assert!(entry.next_run.unwrap() > now2);
    }

    #[test]
    fn overlap_queue() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Queue;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        q.mark_fired(id, 1, t0 + Duration::from_secs(1));
        let now2 = t0 + Duration::from_secs(3);
        q.arm(id, now2, now2);
        let ids = q.expired(Instant::now(), now2);
        assert!(!ids.contains(&id));
        assert!(q.info(id).unwrap().queued_firing);
        let finished = t0 + Duration::from_secs(5);
        q.complete(id, Outcome::Success(v_int(0)), finished);
        let entry = q.info(id).unwrap();
        assert!(!entry.queued_firing);
        assert_eq!(entry.scheduled_deadline, Some(finished));
    }

    #[test]
    fn overlap_concurrent() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Concurrent;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        q.mark_fired(id, 1, t0 + Duration::from_secs(1));
        let now2 = t0 + Duration::from_secs(3);
        q.arm(id, now2, now2);
        let ids = q.expired(Instant::now(), now2);
        assert!(ids.contains(&id));
    }

    // ---- 4: jitter ----------------------------------------------------------

    #[test]
    fn jitter_bounded_and_centred() {
        let q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let jitter = Duration::from_millis(100);
        let mut total_offset_secs = 0.0f64;
        let n = 1000;
        for _ in 0..n {
            let cadence = t0 + Duration::from_secs(1);
            let got = q.jittered(cadence, jitter, t0);
            let offset = got
                .duration_since(cadence)
                .map(|d| d.as_secs_f64())
                .unwrap_or_else(|_| -cadence.duration_since(got).unwrap().as_secs_f64());
            assert!(offset.abs() <= 0.1 + 1e-9, "offset {offset} out of range");
            total_offset_secs += offset;
        }
        let mean = total_offset_secs / n as f64;
        assert!(mean.abs() < 0.010, "mean offset {mean} too far from zero");
    }

    #[test]
    fn jitter_zero_is_identity() {
        let q = ScheduleQ::new(Duration::from_millis(10)); // no mutation needed
        let t0 = t0();
        let deadline = t0 + Duration::from_secs(1);
        assert_eq!(q.jittered(deadline, Duration::ZERO, t0), deadline);
    }

    // ---- 5: stale generation --------------------------------------------

    #[test]
    fn stale_generation_dropped() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let i0 = Instant::now();
        q.expired(i0, t0); // prime last_advance
        let id = q
            .add_at(
                t0 + Duration::from_millis(50),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        // Re-arm before the first deadline fires: bumps the generation.
        q.arm(id, t0 + Duration::from_millis(100), t0);

        let ids60 = q.expired(
            i0 + Duration::from_millis(60),
            t0 + Duration::from_millis(60),
        );
        assert!(ids60.is_empty(), "{ids60:?}");

        let ids110 = q.expired(
            i0 + Duration::from_millis(110),
            t0 + Duration::from_millis(110),
        );
        assert_eq!(ids110, vec![id]);
    }

    // ---- 6: max_faults ------------------------------------------------------

    #[test]
    fn max_faults_retirement() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.max_faults = Some(3);
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let t = t0 + Duration::from_secs(1);

        q.mark_fired(id, 1, t);
        q.complete(id, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 2, t);
        q.complete(id, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 3, t);
        q.complete(id, Outcome::Success(v_int(0)), t); // resets consecutive_faults
        q.mark_fired(id, 4, t);
        q.complete(id, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 5, t);
        q.complete(id, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 6, t);
        let completion = q.complete(id, Outcome::Fault(v_int(1)), t);

        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::MaxFaults))
        );
        let entry = q.info(id).unwrap();
        assert_eq!(entry.fault_count, 5);
        assert_eq!(entry.retired, Some(RetireReason::MaxFaults));
    }

    // ---- 7: adaptive protocol table ------------------------------------

    #[test]
    fn adaptive_at_positive_rearms() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let finished = deadline + Duration::from_millis(500);
        let completion = q.complete(id, Outcome::Success(v_int(5)), finished);
        let expected = deadline + Duration::from_secs(5);
        assert_eq!(completion, Some(Completion::Rearmed(expected)));
        assert_eq!(q.info(id).unwrap().scheduled_deadline, Some(expected));
    }

    #[test]
    fn adaptive_at_zero_retires() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let completion = q.complete(id, Outcome::Success(v_int(0)), deadline);
        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::ReturnedZero))
        );
        assert_eq!(
            q.info(id).unwrap().retired,
            Some(RetireReason::ReturnedZero)
        );
    }

    #[test]
    fn adaptive_at_negative_retires() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let completion = q.complete(id, Outcome::Success(v_int(-1)), deadline);
        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::NegativeReturn))
        );
        assert_eq!(q.info(id).unwrap().fault_count, 1);
    }

    #[test]
    fn adaptive_at_nonnumeric_retires_oneshot() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let completion = q.complete(id, Outcome::Success(v_str("x")), deadline);
        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::OneShotDone))
        );
    }

    #[test]
    fn adaptive_every_positive_overrides_cadence() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.adaptive = true;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        q.complete(id, Outcome::Success(v_int(5)), deadline);
        assert_eq!(
            q.info(id).unwrap().scheduled_deadline,
            Some(deadline + Duration::from_secs(5))
        );
    }

    #[test]
    fn adaptive_every_zero_falls_back_to_cadence() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.adaptive = true;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        q.complete(id, Outcome::Success(v_int(0)), deadline);
        let entry = q.info(id).unwrap();
        assert!(entry.retired.is_none());
        assert_eq!(
            entry.scheduled_deadline,
            Some(deadline + Duration::from_secs(1))
        );
    }

    #[test]
    fn adaptive_every_negative_retires() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.adaptive = true;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        let completion = q.complete(id, Outcome::Success(v_int(-1)), deadline);
        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::NegativeReturn))
        );
    }

    #[test]
    fn adaptive_every_nonnumeric_falls_back_to_cadence() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let mut opts = every_opts(Duration::from_secs(1));
        opts.adaptive = true;
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        q.complete(id, Outcome::Success(v_str("x")), deadline);
        assert_eq!(
            q.info(id).unwrap().scheduled_deadline,
            Some(deadline + Duration::from_secs(1))
        );
    }

    #[test]
    fn adaptive_disabled_ignores_return_value() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let opts = every_opts(Duration::from_secs(1)); // adaptive == false by default
        let id = q
            .add_every(
                Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                opts,
                t0,
            )
            .unwrap();
        let deadline = t0 + Duration::from_secs(1);
        q.mark_fired(id, 1, deadline);
        q.complete(id, Outcome::Success(v_int(5)), deadline);
        assert_eq!(
            q.info(id).unwrap().scheduled_deadline,
            Some(deadline + Duration::from_secs(1))
        );
    }

    // ---- 8: stop --------------------------------------------------------

    #[test]
    fn stop_semantics() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        assert!(!q.stop(999));
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        assert!(q.stop(id));
        assert!(!q.is_valid(id));
        assert!(q.info(id).is_none());
        assert!(q.for_target(&target()).is_empty());
    }

    // ---- 9: retire keeps info --------------------------------------------

    #[test]
    fn retire_keeps_info() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        q.retire(id, RetireReason::InvalidTarget);
        assert!(!q.is_valid(id));
        let info = q.info(id).unwrap();
        assert_eq!(info.retired, Some(RetireReason::InvalidTarget));
        let map = info.to_info_map();
        let m = map.as_map().unwrap();
        let retired_val = m
            .iter()
            .find(|(k, _)| k.as_string() == Some("retired"))
            .map(|(_, v)| v)
            .unwrap();
        assert_eq!(retired_val.as_bool(), Some(true));
    }

    // ---- 10: clamp and validation errors -------------------------------

    #[test]
    fn interval_clamp_and_errors() {
        let tick = Duration::from_millis(10);
        let mut q = ScheduleQ::new(tick);
        let t0 = t0();
        let id = q
            .add_every(
                Duration::from_millis(5),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                every_opts(Duration::from_millis(5)),
                t0,
            )
            .unwrap();
        let entry = q.info(id).unwrap();
        assert!(entry.interval_clamped);
        assert_eq!(entry.kind, ScheduleKind::Every { interval: tick });

        let err = q.add_every(
            Duration::ZERO,
            target(),
            verb(),
            args(),
            owner(),
            owner(),
            every_opts(Duration::from_secs(1)),
            t0,
        );
        assert_eq!(err, Err(ScheduleError::InvalidInterval));

        let mut opts = every_opts(Duration::from_secs(1));
        opts.state = Some(v_str(&"a".repeat(5000)));
        let err2 = q.add_every(
            Duration::from_secs(1),
            target(),
            verb(),
            args(),
            owner(),
            owner(),
            opts,
            t0,
        );
        assert!(matches!(err2, Err(ScheduleError::StateTooLarge(_))));
    }

    // ---- 11: load ---------------------------------------------------------

    #[test]
    fn load_applies_catchup_and_floors_next_id() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let loaded_id: ScheduleId = 42;
        let entry = ScheduleEntry {
            id: loaded_id,
            target: target(),
            verb: verb(),
            args: args(),
            authority_principal: owner(),
            owner: owner(),
            kind: ScheduleKind::Every {
                interval: Duration::from_secs(1),
            },
            options: every_opts(Duration::from_secs(1)),
            created_at: t0,
            next_run: Some(t0 - Duration::from_millis(3500)),
            scheduled_deadline: Some(t0 - Duration::from_millis(3500)),
            last_run: None,
            last_duration: None,
            run_count: 0,
            fault_count: 0,
            consecutive_faults: 0,
            last_fault: None,
            missed_count: 0,
            overlap_count: 0,
            running_task: None,
            queued_firing: false,
            interval_clamped: false,
            retired: None,
            durations: VecDeque::new(),
        };
        q.load(entry, t0);
        let loaded = q.info(loaded_id).unwrap();
        assert_eq!(loaded.missed_count, 4);
        assert!(loaded.next_run.unwrap() > t0);

        let new_id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        assert_eq!(new_id, loaded_id + 1);
    }

    // ---- 12: to_info_map completeness --------------------------------

    #[test]
    fn to_info_map_has_every_key() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let entry = q.info(id).unwrap();
        let map = entry.to_info_map();
        let m = map.as_map().unwrap();
        let expected = [
            "id",
            "target",
            "verb",
            "args",
            "owner",
            "authority",
            "created_at",
            "kind",
            "interval",
            "next_run",
            "last_run",
            "last_duration_ns",
            "run_count",
            "fault_count",
            "consecutive_faults",
            "last_fault",
            "missed_count",
            "overlap_count",
            "mean_duration_ns",
            "p99_duration_ns",
            "state",
            "running_task",
            "interval_clamped",
            "retired",
            "retire_reason",
            "adaptive",
            "catchup",
            "overlap",
            "jitter",
            "max_faults",
            "pass_elapsed",
            "persist",
            "player",
        ];
        for key in expected {
            assert!(
                m.iter().any(|(k, _)| k.as_string() == Some(key)),
                "missing key {key}"
            );
        }
        assert_eq!(m.iter().count(), expected.len());
    }

    // ---- 13: mark_fired elapsed --------------------------------------

    #[test]
    fn mark_fired_elapsed() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let first = t0 + Duration::from_secs(1);
        assert_eq!(q.mark_fired(id, 1, first), None);
        // Re-arm directly to fire a second time.
        q.arm(id, first + Duration::from_secs(2), first);
        let second = first + Duration::from_secs(2);
        let elapsed = q.mark_fired(id, 2, second);
        assert_eq!(elapsed, Some(Duration::from_secs(2)));
    }

    // ---- 14: owner/target indexes -------------------------------------

    #[test]
    fn owner_and_target_indexes() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let own = owner();
        let tgt = target();
        let id1 = q
            .add_at(
                t0 + Duration::from_secs(1),
                tgt,
                verb(),
                args(),
                own,
                own,
                at_opts(),
                t0,
            )
            .unwrap();
        let id2 = q
            .add_every(
                Duration::from_secs(1),
                tgt,
                verb(),
                args(),
                own,
                own,
                every_opts(Duration::from_secs(1)),
                t0,
            )
            .unwrap();
        let mut owned = q.for_owner(&own);
        owned.sort_unstable();
        assert_eq!(owned, vec![id1, id2]);
        let mut targeted = q.for_target(&tgt);
        targeted.sort_unstable();
        assert_eq!(targeted, vec![id1, id2]);

        q.stop(id1);
        assert_eq!(q.for_owner(&own), vec![id2]);
        assert_eq!(q.for_target(&tgt), vec![id2]);
    }
}
