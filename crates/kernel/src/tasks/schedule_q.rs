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

/// The latest deadline a schedule may have, in seconds after the Unix epoch
/// (a little past the year 2554). The tasks database stores deadlines,
/// intervals and jitter as `u64` nanoseconds, so this is the largest instant
/// that survives a restart unchanged. Creation past it is `InvalidWhen`; a
/// firing whose next deadline would pass it retires with
/// `RetireReason::DeadlineOutOfRange`.
pub const MAX_DEADLINE_SECS: u64 = u64::MAX / 1_000_000_000;

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

/// What to do about cadence points that passed before the schedule could
/// fire: after a restart, or when the scheduler fired a deadline late.
/// Deadlines that pass while a firing is running go to `OverlapPolicy`.
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
            ScheduleError::InvalidWhen => write!(
                f,
                "schedule deadline is out of range (latest is {MAX_DEADLINE_SECS} Unix seconds)"
            ),
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
    /// The next deadline would fall after `MAX_DEADLINE_SECS`.
    DeadlineOutOfRange,
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
            RetireReason::DeadlineOutOfRange => "deadline_out_of_range",
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

/// One firing whose task has started and not yet reached a terminal result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RunningFiring {
    pub task: TaskId,
    /// The cadence point (pre-jitter) this firing was for. The adaptive
    /// protocol measures a returned delay from here.
    pub deadline: SystemTime,
    pub started_at: SystemTime,
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
    /// Firings in progress, oldest first. More than one only under
    /// `OverlapPolicy::Concurrent`.
    pub running: Vec<RunningFiring>,
    /// Set under `OverlapPolicy::Queue` when a deadline arrived mid-firing.
    pub queued_firing: bool,
    pub interval_clamped: bool,
    pub retired: Option<RetireReason>,
    durations: VecDeque<Duration>,
}

impl ScheduleEntry {
    /// Rebuild an entry from persisted fields. Runtime-only state
    /// (`running`, `queued_firing`, duration samples, `last_fault`)
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
            running: Vec::new(),
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
                v_int(self.running.first().map(|r| r.task as i64).unwrap_or(0)),
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
    /// Retired entries in retirement order, with the time each retired.
    /// `purge_retired` pops from the front once `RETIRED_RETENTION` has
    /// passed, so the cost per tick is proportional to what expires.
    retired_queue: VecDeque<(SystemTime, ScheduleId)>,
}

impl ScheduleQ {
    /// How long a retired entry stays inspectable through `info()` before it
    /// is dropped. Long enough for the code that created or watches a
    /// schedule to read why it ended; short enough that a steady stream of
    /// one-shots holds at most a minute's worth of entries (and the args,
    /// state and fault values they root for GC).
    pub const RETIRED_RETENTION: Duration = Duration::from_secs(60);

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
            retired_queue: VecDeque::new(),
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

    /// The id the next `reserve_id` will return. Every id below it has been
    /// handed out at some point; persisting it lets a restart continue past
    /// ids whose schedules have since stopped or retired.
    pub fn next_id(&self) -> ScheduleId {
        self.next_id
    }

    /// Raise the id counter to at least `next_id`. Never lowers it, so it
    /// may be called before or after `load` restores the live entries.
    pub fn restore_next_id(&mut self, next_id: ScheduleId) {
        self.next_id = self.next_id.max(next_id);
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
        now: SystemTime,
    ) -> Result<(), ScheduleError> {
        if interval == Duration::ZERO {
            return Err(ScheduleError::InvalidInterval);
        }
        if deadline_after(now, interval.max(self.tick)).is_none() {
            return Err(ScheduleError::InvalidWhen);
        }
        Self::validate_state(options)
    }

    /// Validate what a builtin can validate before buffering a one-shot.
    pub fn validate_at(
        &self,
        when: SystemTime,
        options: &ScheduleOptions,
    ) -> Result<(), ScheduleError> {
        if when > max_deadline() {
            return Err(ScheduleError::InvalidWhen);
        }
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
        if when > max_deadline() {
            return Err(ScheduleError::InvalidWhen);
        }
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
            running: Vec::new(),
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
        let Some(first) = deadline_after(now, interval) else {
            return Err(ScheduleError::InvalidWhen);
        };
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
            running: Vec::new(),
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
    /// stale id is an ordinary race, not an error. A retired entry is
    /// dropped immediately rather than waiting out `RETIRED_RETENTION`.
    pub fn stop(&mut self, id: ScheduleId) -> bool {
        let Some(entry) = self.entries.get(&id) else {
            return false;
        };
        if !entry.is_live() {
            // Retirement already cleared the indexes and timers.
            self.entries.remove(&id);
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
        for r in &entry.running {
            self.by_task.remove(&r.task);
        }
        self.immediate.retain(|&i| i != id);
        true
    }

    /// Stop scheduling but keep the entry so `info()` shows why, until
    /// `RETIRED_RETENTION` after `now`.
    pub fn retire(&mut self, id: ScheduleId, reason: RetireReason, now: SystemTime) {
        let Some(entry) = self.entries.get_mut(&id) else {
            return;
        };
        if entry.retired.is_some() {
            return;
        }
        self.retired_queue.push_back((now, id));
        entry.next_run = None;
        entry.retired = Some(reason);
        let running = std::mem::take(&mut entry.running);
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
        for r in running {
            self.by_task.remove(&r.task);
        }
        self.immediate.retain(|&i| i != id);
    }

    /// Drop retired entries whose retention has passed at `now`. Called
    /// from `expired()` on every tick and before a GC root scan.
    ///
    /// The queue is in retirement order; if the wall clock steps backwards
    /// a later entry may wait behind an earlier one, never longer than the
    /// front entry's own retention.
    pub fn purge_retired(&mut self, now: SystemTime) {
        while let Some(&(retired_at, id)) = self.retired_queue.front() {
            let due = retired_at
                .checked_add(Self::RETIRED_RETENTION)
                .unwrap_or(retired_at);
            if due > now {
                break;
            }
            self.retired_queue.pop_front();
            // Already gone if `stop()` released it early.
            if self.entries.get(&id).is_some_and(|e| e.retired.is_some()) {
                self.entries.remove(&id);
            }
        }
    }

    /// Advance the wheel to `now` and return the schedules to fire, after
    /// dropping stale generations and applying each entry's overlap policy.
    /// Also purges retired entries past their retention.
    pub fn expired(&mut self, now: Instant, now_sys: SystemTime) -> Vec<ScheduleId> {
        self.purge_retired(now_sys);
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
            let entry = self.entries.get_mut(&id).unwrap();
            if entry.running.is_empty() {
                kept.push(id);
                continue;
            }
            match entry.options.overlap {
                OverlapPolicy::Skip => self.skip_overlapped(id, now_sys),
                // Left unarmed: `complete` fires the queued deadline, and
                // that firing arms the next one.
                OverlapPolicy::Queue => entry.queued_firing = true,
                OverlapPolicy::Concurrent => kept.push(id),
            }
        }
        kept
    }

    /// Record that `id` is now running as `task`, and arm a recurring
    /// schedule's next deadline at once, so a deadline that arrives while
    /// this firing is still running reaches the overlap policy in
    /// `expired()`. Returns the elapsed time since the previous firing (for
    /// `pass_elapsed`); `None` on the first.
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
        let deadline = entry.scheduled_deadline.unwrap_or(fired_at);
        entry.running.push(RunningFiring {
            task,
            deadline,
            started_at: fired_at,
        });
        entry.last_run = Some(fired_at);
        let kind = entry.kind;
        self.by_task.insert(task, id);
        if let ScheduleKind::Every { interval } = kind {
            self.arm_after(id, deadline, interval, fired_at);
        }
        elapsed
    }

    /// Record the outcome of `task`'s firing of `id`. A one-shot is retired
    /// or, under the adaptive protocol, re-armed. A recurring schedule was
    /// already armed by `mark_fired`; here it only fires a queued deadline,
    /// takes an adaptive override, or retires.
    pub fn complete(
        &mut self,
        id: ScheduleId,
        task: TaskId,
        outcome: Outcome,
        finished_at: SystemTime,
    ) -> Option<Completion> {
        // The entry may have been stopped or retired mid-flight, which
        // forgets its running firings.
        let entry = self.entries.get_mut(&id)?;

        // Clear running-task bookkeeping first.
        let i = entry.running.iter().position(|r| r.task == task)?;
        let firing = entry.running.remove(i);
        self.by_task.remove(&task);
        entry.push_duration(
            finished_at
                .duration_since(firing.started_at)
                .unwrap_or(Duration::ZERO),
        );

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
                    self.retire(id, RetireReason::MaxFaults, finished_at);
                    return Some(Completion::Retired(RetireReason::MaxFaults));
                }
            }
        }

        let entry = self.entries.get(&id).unwrap();
        let base = firing.deadline;
        let adaptive = entry.options.adaptive;
        let jitter = entry.options.jitter;
        let kind = entry.kind;
        let queued_firing = entry.queued_firing;

        if adaptive
            && let Outcome::Success(v) = &outcome
            && let Some(n) = v.as_float_numeric()
        {
            if n > 0.0 {
                let next = Duration::try_from_secs_f64(n)
                    .ok()
                    .and_then(|delta| deadline_after(base, delta));
                let Some(next) = next else {
                    return Some(self.retire_out_of_range(id, finished_at));
                };
                // The verb named its next time explicitly; that replaces
                // both the cadence deadline and any queued firing.
                let entry = self.entries.get_mut(&id).unwrap();
                entry.scheduled_deadline = Some(next);
                entry.queued_firing = false;
                let jittered = self.jittered(next, jitter, finished_at);
                self.arm(id, jittered, finished_at);
                return Some(Completion::Rearmed(next));
            } else if n == 0.0 {
                match kind {
                    ScheduleKind::At => {
                        self.retire(id, RetireReason::ReturnedZero, finished_at);
                        return Some(Completion::Retired(RetireReason::ReturnedZero));
                    }
                    ScheduleKind::Every { .. } => {
                        // fall through to cadence
                    }
                }
            } else {
                let entry = self.entries.get_mut(&id).unwrap();
                entry.fault_count += 1;
                self.retire(id, RetireReason::NegativeReturn, finished_at);
                return Some(Completion::Retired(RetireReason::NegativeReturn));
            }
        }

        match kind {
            ScheduleKind::At => {
                self.retire(id, RetireReason::OneShotDone, finished_at);
                Some(Completion::Retired(RetireReason::OneShotDone))
            }
            ScheduleKind::Every { interval } if queued_firing => {
                self.fire_queued(id, interval, finished_at);
                Some(Completion::Rearmed(finished_at))
            }
            ScheduleKind::Every { .. } => {
                let next_run = self.entries.get(&id).unwrap().next_run?;
                Some(Completion::Rearmed(next_run))
            }
        }
    }

    /// Restore an entry from persistence. Past deadlines go through the
    /// catchup policy; the id counter is floored above the loaded id. Only
    /// live entries are persisted, so anything else is dropped here.
    pub fn load(&mut self, mut entry: ScheduleEntry, now: SystemTime) {
        if entry.id >= self.next_id {
            self.next_id = entry.id + 1;
        }
        if entry.retired.is_some() || entry.next_run.is_none() {
            return;
        }
        let id = entry.id;
        self.by_owner.entry(entry.owner).or_default().insert(id);
        self.by_target.entry(entry.target).or_default().insert(id);
        entry.running.clear();
        entry.queued_firing = false;

        let deadline = entry.next_run.unwrap();
        let deadline = if deadline <= now {
            match (entry.kind, entry.options.catchup) {
                (ScheduleKind::Every { interval }, CatchupPolicy::Skip) => {
                    let Some((d, missed)) = next_cadence_after(deadline, interval, now) else {
                        entry.fault_count += 1;
                        self.entries.insert(id, entry);
                        self.retire(id, RetireReason::DeadlineOutOfRange, now);
                        return;
                    };
                    entry.missed_count += missed;
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
    /// and the last fault value. Retired entries count until purged, since
    /// `info()` can still hand those values out; callers should
    /// `purge_retired` first.
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

    /// Retire a schedule whose next deadline cannot be represented. Counted
    /// as a fault, like a negative adaptive return: the verb or its creator
    /// asked for something the scheduler cannot do.
    fn retire_out_of_range(&mut self, id: ScheduleId, now: SystemTime) -> Completion {
        if let Some(entry) = self.entries.get_mut(&id) {
            entry.fault_count += 1;
        }
        self.retire(id, RetireReason::DeadlineOutOfRange, now);
        Completion::Retired(RetireReason::DeadlineOutOfRange)
    }

    fn validate_state(options: &ScheduleOptions) -> Result<(), ScheduleError> {
        if let Some(s) = &options.state {
            let n = s.size_bytes();
            if n > MAX_STATE_BYTES {
                return Err(ScheduleError::StateTooLarge(n));
            }
        }
        Ok(())
    }

    /// Drop a deadline that arrived mid-firing, and every further cadence
    /// point already passed, and arm the next future one. Each dropped
    /// point counts in `overlap_count`, regardless of `catchup`: the
    /// firing that was running is what they were dropped for.
    fn skip_overlapped(&mut self, id: ScheduleId, now: SystemTime) {
        let Some(entry) = self.entries.get_mut(&id) else {
            return;
        };
        entry.overlap_count = entry.overlap_count.saturating_add(1);
        let ScheduleKind::Every { interval } = entry.kind else {
            return;
        };
        let base = entry.scheduled_deadline.unwrap_or(now);
        let Some((next, passed)) = deadline_after(base, interval)
            .and_then(|first| next_cadence_after(first, interval, now))
        else {
            self.retire_out_of_range(id, now);
            return;
        };
        let entry = self.entries.get_mut(&id).unwrap();
        entry.overlap_count = entry.overlap_count.saturating_add(passed);
        entry.scheduled_deadline = Some(next);
        let jitter = entry.options.jitter;
        let jittered = self.jittered(next, jitter, now);
        self.arm(id, jittered, now);
    }

    /// Start the firing queued under `OverlapPolicy::Queue` now. The queue
    /// holds one firing; any later cadence points that also passed during
    /// the slow firing are dropped into `overlap_count`, and the queued
    /// firing stands for the latest of them so the cadence resumes in phase.
    fn fire_queued(&mut self, id: ScheduleId, interval: Duration, now: SystemTime) {
        let Some(entry) = self.entries.get_mut(&id) else {
            return;
        };
        entry.queued_firing = false;
        let queued = entry.scheduled_deadline.unwrap_or(now);
        if let Some((next, passed)) = deadline_after(queued, interval)
            .and_then(|first| next_cadence_after(first, interval, now))
            && passed > 0
            && let Some(latest) = next.checked_sub(interval)
        {
            entry.overlap_count = entry.overlap_count.saturating_add(passed);
            entry.scheduled_deadline = Some(latest);
        }
        self.arm(id, now, now);
    }

    /// Arm a recurring schedule for the cadence point after `deadline`. If
    /// the scheduler was late enough that further points have already
    /// passed, the catchup policy decides: `Skip` jumps to the next future
    /// point and counts the rest in `missed_count`, `Once` jumps without
    /// counting (the late firing stood in for them), `All` leaves the next
    /// point in the past so it fires on the next tick.
    fn arm_after(
        &mut self,
        id: ScheduleId,
        deadline: SystemTime,
        interval: Duration,
        now: SystemTime,
    ) {
        let Some(entry) = self.entries.get_mut(&id) else {
            return;
        };
        let Some(first) = deadline_after(deadline, interval) else {
            self.retire_out_of_range(id, now);
            return;
        };
        let next = match entry.options.catchup {
            _ if first > now => first,
            CatchupPolicy::All => first,
            catchup => {
                let Some((next, passed)) = next_cadence_after(first, interval, now) else {
                    self.retire_out_of_range(id, now);
                    return;
                };
                if catchup == CatchupPolicy::Skip {
                    entry.missed_count = entry.missed_count.saturating_add(passed);
                }
                next
            }
        };
        let entry = self.entries.get_mut(&id).unwrap();
        entry.scheduled_deadline = Some(next);
        let jitter = entry.options.jitter;
        let jittered = self.jittered(next, jitter, now);
        self.arm(id, jittered, now);
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
        let offset = Duration::try_from_secs_f64(offset_secs.abs()).unwrap_or(Duration::ZERO);
        let result = if offset_secs >= 0.0 {
            deadline_after(deadline, offset).unwrap_or(deadline)
        } else {
            deadline.checked_sub(offset).unwrap_or(deadline)
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

fn max_deadline() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(MAX_DEADLINE_SECS)
}

/// `base + delta`, or `None` if that is past `MAX_DEADLINE_SECS`.
fn deadline_after(base: SystemTime, delta: Duration) -> Option<SystemTime> {
    base.checked_add(delta).filter(|t| *t <= max_deadline())
}

/// The first point of the cadence `from, from + interval, ...` that is
/// strictly after `now`, and how many points were stepped over to reach it.
/// Computed directly rather than by stepping, so a long gap at a short
/// interval costs nothing. `None` if that point is past `MAX_DEADLINE_SECS`.
fn next_cadence_after(
    from: SystemTime,
    interval: Duration,
    now: SystemTime,
) -> Option<(SystemTime, u64)> {
    let Ok(gap) = now.duration_since(from) else {
        return Some((from, 0));
    };
    let step = interval.as_nanos();
    if step == 0 {
        return None;
    }
    let steps = gap.as_nanos() / step + 1;
    let advance = steps.checked_mul(step)?;
    let secs = u64::try_from(advance / 1_000_000_000).ok()?;
    let nanos = (advance % 1_000_000_000) as u32;
    let next = deadline_after(from, Duration::new(secs, nanos))?;
    Some((next, u64::try_from(steps).ok()?))
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
            q.complete(id, k as TaskId, Outcome::Success(v_int(0)), finished);
            let entry = q.info(id).unwrap();
            assert_eq!(
                entry.scheduled_deadline,
                Some(t0 + Duration::from_secs(k + 2)),
                "iteration {k}"
            );
        }
    }

    // ---- 2: catchup policies ----------------------------------------------

    /// A 1-second recurring schedule created at `t0`, with the wheel primed
    /// at `t0`. Returns the queue, the id, and a clock mapping milliseconds
    /// after `t0` to the `(Instant, SystemTime)` pair `expired` takes.
    fn every_1s(
        opts: ScheduleOptions,
    ) -> (ScheduleQ, ScheduleId, impl Fn(u64) -> (Instant, SystemTime)) {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let i0 = Instant::now();
        q.expired(i0, t0);
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
        let at = move |ms: u64| {
            let d = Duration::from_millis(ms);
            (i0 + d, t0 + d)
        };
        (q, id, at)
    }

    fn secs(n: u64) -> SystemTime {
        t0() + Duration::from_secs(n)
    }

    #[test]
    fn catchup_skip() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::Skip;
        let (mut q, id, at) = every_1s(opts);
        // The scheduler stalls from 1s to 4.5s, then fires the 1s deadline.
        let (i, t) = at(4500);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.missed_count, 3);
        assert_eq!(entry.scheduled_deadline, Some(secs(5)));
        q.complete(id, 1, Outcome::Success(v_int(0)), t);
        assert_eq!(q.info(id).unwrap().next_run, Some(secs(5)));
    }

    #[test]
    fn catchup_once() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::Once;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(4500);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        q.complete(id, 1, Outcome::Success(v_int(0)), t);
        // The late firing stood in for the missed ones; back on cadence.
        let entry = q.info(id).unwrap();
        assert_eq!(entry.missed_count, 0);
        assert_eq!(entry.scheduled_deadline, Some(secs(5)));
        let (i, t) = at(4600);
        assert!(q.expired(i, t).is_empty());
    }

    #[test]
    fn catchup_all() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::All;
        let (mut q, id, at) = every_1s(opts);
        // Stall to 4.5s: deadlines 1, 2, 3 and 4 are all owed.
        let mut fired = Vec::new();
        for (task, ms) in (1..).zip([4500, 4510, 4520, 4530, 4540, 4550]) {
            let (i, t) = at(ms);
            if !q.expired(i, t).contains(&id) {
                continue;
            }
            fired.push(q.info(id).unwrap().scheduled_deadline.unwrap());
            q.mark_fired(id, task, t);
            q.complete(id, task, Outcome::Success(v_int(0)), t);
        }
        assert_eq!(fired, vec![secs(1), secs(2), secs(3), secs(4)]);
        assert_eq!(q.info(id).unwrap().scheduled_deadline, Some(secs(5)));
    }

    #[test]
    fn catchup_long_stall_is_arithmetic() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.catchup = CatchupPolicy::Skip;
        let (mut q, id, at) = every_1s(opts);
        // A stall of ~11.5 days: skipped in one step, not one iteration per
        // missed second.
        let (i, t) = at(1_000_000_500);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.missed_count, 999_999);
        assert_eq!(entry.scheduled_deadline, Some(secs(1_000_001)));
    }

    // ---- 3: overlap policies ------------------------------------------------
    //
    // Each firing below runs from 1s to 3.5s, across the 2s and 3s deadlines.

    #[test]
    fn overlap_skip() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Skip;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(1000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        assert_eq!(q.info(id).unwrap().next_run, Some(secs(2)));

        for ms in [2000, 3000] {
            let (i, t) = at(ms);
            assert!(q.expired(i, t).is_empty(), "at {ms}ms");
        }
        let entry = q.info(id).unwrap();
        assert_eq!(entry.overlap_count, 2);
        assert_eq!(entry.next_run, Some(secs(4)));

        let (_, t) = at(3500);
        q.complete(id, 1, Outcome::Success(v_int(0)), t);
        assert!(q.info(id).unwrap().running.is_empty());
        let (i, t) = at(4000);
        assert_eq!(q.expired(i, t), vec![id]);
        assert_eq!(q.info(id).unwrap().missed_count, 0);
    }

    #[test]
    fn overlap_skip_long_firing_is_bounded() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Skip;
        opts.catchup = CatchupPolicy::All;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(1000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        // The firing is still running when the scheduler next looks, an
        // hour later: one pass drops all 3600 points and arms the next.
        let (i, t) = at(3_601_500);
        assert!(q.expired(i, t).is_empty());
        let entry = q.info(id).unwrap();
        assert_eq!(entry.overlap_count, 3600);
        assert_eq!(entry.next_run, Some(secs(3602)));
        let (i, t) = at(3_601_510);
        assert!(q.expired(i, t).is_empty());
    }

    #[test]
    fn overlap_queue() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Queue;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(1000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);

        let (i, t) = at(2000);
        assert!(q.expired(i, t).is_empty());
        assert!(q.info(id).unwrap().queued_firing);
        // Only one firing is queued, however many deadlines pass.
        let (i, t) = at(3000);
        assert!(q.expired(i, t).is_empty());

        let (_, t) = at(3500);
        q.complete(id, 1, Outcome::Success(v_int(0)), t);
        assert!(!q.info(id).unwrap().queued_firing);
        // The queued firing starts as soon as the first one ends. The 3s
        // point did not fit in the queue and counts as an overlap; the
        // queued firing stands for it, so the cadence resumes at 4s.
        let entry = q.info(id).unwrap();
        assert_eq!(entry.overlap_count, 1);
        assert_eq!(entry.scheduled_deadline, Some(secs(3)));
        let (i, t) = at(3500);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 2, t);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.scheduled_deadline, Some(secs(4)));
        assert_eq!(entry.missed_count, 0);
    }

    #[test]
    fn overlap_queue_single_deadline() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Queue;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(1000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        let (i, t) = at(2000);
        assert!(q.expired(i, t).is_empty());
        // Finishes at 2.5s: only the 2s deadline passed, and it is queued.
        let (_, t) = at(2500);
        q.complete(id, 1, Outcome::Success(v_int(0)), t);
        let (i, t) = at(2500);
        assert_eq!(q.expired(i, t), vec![id]);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.scheduled_deadline, Some(secs(2)));
        assert_eq!(entry.overlap_count, 0);
        q.mark_fired(id, 2, t);
        assert_eq!(q.info(id).unwrap().next_run, Some(secs(3)));
    }

    #[test]
    fn overlap_concurrent() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Concurrent;
        let (mut q, id, at) = every_1s(opts);
        let (i, t) = at(1000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 1, t);
        let (i, t) = at(2000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 2, t);
        let (i, t) = at(3000);
        assert_eq!(q.expired(i, t), vec![id]);
        q.mark_fired(id, 3, t);

        let entry = q.info(id).unwrap();
        let tasks: Vec<TaskId> = entry.running.iter().map(|r| r.task).collect();
        assert_eq!(tasks, vec![1, 2, 3]);
        assert_eq!(entry.next_run, Some(secs(4)));
        for task in [1, 2, 3] {
            assert_eq!(q.schedule_for_task(task), Some(id));
        }

        // Completions in any order each settle their own firing.
        let (_, t) = at(3500);
        q.complete(id, 2, Outcome::Success(v_int(0)), t);
        q.complete(id, 1, Outcome::Fault(v_int(1)), t);
        let entry = q.info(id).unwrap();
        assert_eq!(entry.running.len(), 1);
        assert_eq!(entry.run_count, 1);
        assert_eq!(entry.fault_count, 1);
        assert_eq!(entry.next_run, Some(secs(4)));
        assert_eq!(q.schedule_for_task(2), None);
        // A second terminal result for the same task is ignored.
        assert_eq!(q.complete(id, 2, Outcome::Success(v_int(0)), t), None);
        assert_eq!(q.info(id).unwrap().run_count, 1);
    }

    #[test]
    fn stop_forgets_all_running_firings() {
        let mut opts = every_opts(Duration::from_secs(1));
        opts.overlap = OverlapPolicy::Concurrent;
        let (mut q, id, at) = every_1s(opts);
        for (task, ms) in [(1, 1000), (2, 2000)] {
            let (i, t) = at(ms);
            assert_eq!(q.expired(i, t), vec![id]);
            q.mark_fired(id, task, t);
        }
        assert!(q.stop(id));
        assert_eq!(q.schedule_for_task(1), None);
        assert_eq!(q.schedule_for_task(2), None);
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
        q.complete(id, 1, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 2, t);
        q.complete(id, 2, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 3, t);
        q.complete(id, 3, Outcome::Success(v_int(0)), t); // resets consecutive_faults
        q.mark_fired(id, 4, t);
        q.complete(id, 4, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 5, t);
        q.complete(id, 5, Outcome::Fault(v_int(1)), t);
        q.mark_fired(id, 6, t);
        let completion = q.complete(id, 6, Outcome::Fault(v_int(1)), t);

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
        let completion = q.complete(id, 1, Outcome::Success(v_int(5)), finished);
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
        let completion = q.complete(id, 1, Outcome::Success(v_int(0)), deadline);
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
        let completion = q.complete(id, 1, Outcome::Success(v_int(-1)), deadline);
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
        let completion = q.complete(id, 1, Outcome::Success(v_str("x")), deadline);
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
        q.complete(id, 1, Outcome::Success(v_int(5)), deadline);
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
        q.complete(id, 1, Outcome::Success(v_int(0)), deadline);
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
        let completion = q.complete(id, 1, Outcome::Success(v_int(-1)), deadline);
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
        q.complete(id, 1, Outcome::Success(v_str("x")), deadline);
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
        q.complete(id, 1, Outcome::Success(v_int(5)), deadline);
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
        q.retire(id, RetireReason::InvalidTarget, t0);
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

    // ---- 9b: bounded retention of retired entries ---------------------

    /// Fire a one-shot at `t0 + 1s` and let it complete, returning its id.
    fn completed_one_shot(
        q: &mut ScheduleQ,
        i0: Instant,
        t0: SystemTime,
        args: List,
    ) -> ScheduleId {
        q.expired(i0, t0);
        let id = q
            .add_at(
                t0 + Duration::from_secs(1),
                target(),
                verb(),
                args,
                owner(),
                owner(),
                at_opts(),
                t0,
            )
            .unwrap();
        let fire_t = t0 + Duration::from_secs(1);
        let ids = q.expired(i0 + Duration::from_secs(1), fire_t);
        assert_eq!(ids, vec![id]);
        q.mark_fired(id, 7, fire_t);
        q.complete(id, 7, Outcome::Success(v_int(0)), fire_t);
        assert!(q.info(id).unwrap().retired.is_some());
        id
    }

    #[test]
    fn retired_entry_purged_after_retention() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let i0 = Instant::now();
        let id = completed_one_shot(&mut q, i0, t0, args());
        let retired_at = t0 + Duration::from_secs(1);

        // Still inspectable just inside the retention window.
        let just_before = ScheduleQ::RETIRED_RETENTION - Duration::from_millis(10);
        q.expired(
            i0 + Duration::from_secs(1) + just_before,
            retired_at + just_before,
        );
        assert!(q.info(id).is_some());

        // Gone once the window has passed.
        q.expired(
            i0 + Duration::from_secs(1) + ScheduleQ::RETIRED_RETENTION,
            retired_at + ScheduleQ::RETIRED_RETENTION,
        );
        assert!(q.info(id).is_none());
        assert!(q.all_ids().is_empty());
        assert!(q.schedule_for_task(7).is_none());
    }

    #[test]
    fn stop_releases_retired_entry() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let id = completed_one_shot(&mut q, Instant::now(), t0(), args());
        // A stale id is still `false`, but the diagnostics are dropped.
        assert!(!q.stop(id));
        assert!(q.info(id).is_none());
        assert!(q.all_ids().is_empty());
    }

    #[test]
    fn purged_entry_is_not_a_gc_root() {
        let anon = Obj::mk_anonymous_generated();
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let i0 = Instant::now();
        let id = completed_one_shot(&mut q, i0, t0, List::mk_list(&[Var::from(anon)]));

        // During retention the entry is a root: `schedule_info` may still
        // hand out its args, which must not dangle.
        let mut refs = HashSet::new();
        q.collect_anonymous_object_references(&mut refs);
        assert!(refs.contains(&anon));

        let later = Duration::from_secs(1) + ScheduleQ::RETIRED_RETENTION;
        q.expired(i0 + later, t0 + later);
        assert!(q.info(id).is_none());
        let mut refs = HashSet::new();
        q.collect_anonymous_object_references(&mut refs);
        assert!(refs.is_empty());
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
            running: Vec::new(),
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

    // ---- 11b: unrepresentable deadlines ------------------------------------

    /// Run `f` on another thread and fail the test if it does not return
    /// within ten seconds, so a non-terminating loop shows up as a failure
    /// instead of a stuck test run.
    fn within_deadline<T: Send + 'static>(f: impl FnOnce() -> T + Send + 'static) -> T {
        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let _ = tx.send(f());
        });
        rx.recv_timeout(Duration::from_secs(10))
            .expect("did not finish within 10s (hung or panicked)")
    }

    #[test]
    fn every_with_unrepresentable_first_deadline_is_rejected() {
        let result = within_deadline(|| {
            let mut q = ScheduleQ::new(Duration::from_millis(10));
            let t0 = t0();
            let interval = Duration::from_secs(10_000_000_000_000_000_000);
            let r = q.add_every(
                interval,
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                every_opts(interval),
                t0,
            );
            // Drive a firing the way the scheduler would if it was accepted.
            if let Ok(id) = r {
                q.mark_fired(id, 1, t0);
                q.complete(id, 1, Outcome::Success(v_int(0)), t0);
            }
            r
        });
        assert_eq!(result, Err(ScheduleError::InvalidWhen));
    }

    #[test]
    fn at_past_deadline_limit_is_rejected() {
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        let t0 = t0();
        let too_late = UNIX_EPOCH + Duration::from_secs(MAX_DEADLINE_SECS + 1);
        let err = q.add_at(
            too_late,
            target(),
            verb(),
            args(),
            owner(),
            owner(),
            at_opts(),
            t0,
        );
        assert_eq!(err, Err(ScheduleError::InvalidWhen));
        let at_limit = UNIX_EPOCH + Duration::from_secs(MAX_DEADLINE_SECS);
        assert!(
            q.add_at(
                at_limit,
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                at_opts(),
                t0
            )
            .is_ok()
        );
    }

    #[test]
    fn firing_retires_when_next_deadline_unrepresentable() {
        let (completion, entry) = within_deadline(|| {
            let mut q = ScheduleQ::new(Duration::from_millis(10));
            let t0 = t0();
            // First deadline fits under the limit; the one after does not.
            let interval = Duration::from_secs(9_000_000_000);
            let id = q
                .add_every(
                    interval,
                    target(),
                    verb(),
                    args(),
                    owner(),
                    owner(),
                    every_opts(interval),
                    t0,
                )
                .unwrap();
            let deadline = t0 + interval;
            // Arming the next cadence point happens here, and fails.
            q.mark_fired(id, 1, deadline);
            let c = q.complete(id, 1, Outcome::Success(v_int(0)), deadline);
            (c, q.info(id).cloned().unwrap())
        });
        // Retirement forgot the running firing, so completion has nothing to settle.
        assert_eq!(completion, None);
        assert!(!entry.is_live());
        assert_eq!(entry.retired, Some(RetireReason::DeadlineOutOfRange));
        assert_eq!(entry.fault_count, 1);
    }

    #[test]
    fn adaptive_return_past_limit_retires() {
        let completion = within_deadline(|| {
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
            q.complete(id, 1, Outcome::Success(v_float(1e30)), deadline)
        });
        assert_eq!(
            completion,
            Some(Completion::Retired(RetireReason::DeadlineOutOfRange))
        );
    }

    #[test]
    fn load_retires_unrepresentable_cadence() {
        let entry = within_deadline(|| {
            let mut q = ScheduleQ::new(Duration::from_millis(10));
            let t0 = t0();
            let interval = Duration::from_secs(10_000_000_000_000_000_000);
            let mut entry = ScheduleEntry::from_persisted(
                7,
                target(),
                verb(),
                args(),
                owner(),
                owner(),
                ScheduleKind::Every { interval },
                every_opts(interval),
                t0 - Duration::from_secs(10),
                Some(t0 - Duration::from_secs(5)),
                Some(t0 - Duration::from_secs(5)),
                None,
                0,
                0,
                0,
                0,
                0,
                false,
            );
            entry.options.catchup = CatchupPolicy::Skip;
            q.load(entry, t0);
            q.info(7).cloned().unwrap()
        });
        assert!(!entry.is_live());
        assert_eq!(entry.retired, Some(RetireReason::DeadlineOutOfRange));
    }

    #[test]
    fn catchup_skip_over_a_long_gap_is_arithmetic() {
        let (entry, fired_at) = within_deadline(|| {
            let tick = Duration::from_millis(10);
            let mut q = ScheduleQ::new(tick);
            let t0 = t0();
            let id = q
                .add_every(
                    tick,
                    target(),
                    verb(),
                    args(),
                    owner(),
                    owner(),
                    every_opts(tick),
                    t0,
                )
                .unwrap();
            let deadline = t0 + tick;
            // The scheduler stalled for ten years before firing this
            // deadline: 3.15e10 cadence points of 10 ms have passed.
            let fired_at = deadline + Duration::from_secs(10 * 365 * 86_400) + tick / 2;
            q.mark_fired(id, 1, fired_at);
            (q.info(id).cloned().unwrap(), fired_at)
        });
        let next = entry.scheduled_deadline.unwrap();
        assert!(next > fired_at);
        assert!(next.duration_since(fired_at).unwrap() <= Duration::from_millis(10));
        assert_eq!(entry.missed_count, 10 * 365 * 86_400 * 100);
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
        // The adaptive protocol re-arms the one-shot two seconds on.
        q.complete(id, 1, Outcome::Success(v_int(2)), first);
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

    // ---- 15: id high-water mark ------------------------------------------

    #[test]
    fn restore_next_id_continues_past_finished_schedules() {
        // Nothing live survived the restart, but ids up to 41 were handed out.
        let mut q = ScheduleQ::new(Duration::from_millis(10));
        q.restore_next_id(42);
        assert_eq!(q.reserve_id(), 42);
        assert_eq!(q.next_id(), 43);

        // A lower persisted mark never moves the counter backwards.
        q.restore_next_id(5);
        assert_eq!(q.reserve_id(), 43);
    }
}
