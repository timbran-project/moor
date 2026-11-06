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

//! What the daemon's metrics mean: the figures each view shows, and the warnings, built from
//! queries over the metric history. The live view and the report both use these.

use crate::metrics::{Filter, Query, Timer, duration, short};

// Metric names, without the `moor_` prefix the Prometheus export adds.
pub const PLAYERS: &str = "daemon_connected_players";
pub const CONNECTIONS: &str = "daemon_connections";
pub const HOSTS: &str = "daemon_hosts";
pub const TASKS_ACTIVE: &str = "tasks_active";
pub const TASKS_SUSPENDED: &str = "tasks_suspended";
pub const SCHED_CALLS: &str = "sched_timers_calls";
pub const SCHED_SAMPLES: &str = "sched_timers_samples";
pub const DB_CALLS: [&str; 2] = ["db_timers_hot_calls", "db_timers_rare_calls"];
pub const DB_SAMPLES: [&str; 2] = ["db_timers_hot_samples", "db_timers_rare_samples"];
pub const DB_COUNTERS: &str = "db_counters";
pub const DB_CACHE_OPS: &str = "db_cache_ops";
pub const DB_CACHE_ENTRIES: &str = "db_cache_entries";
pub const PROGRAM_CACHE_OPS: &str = "program_cache_ops";
pub const PROGRAM_CACHE_SLOTS: &str = "program_cache_live_slots";
pub const BF_CALLS: &str = "bf_calls";
pub const BF_SAMPLES: &str = "bf_samples";
pub const RPC_QUEUED: &str = "rpc_queued";
pub const RPC_WAIT_CALLS: &str = "rpc_queue_wait_calls";
pub const RPC_WAIT: &str = "rpc_queue_wait_samples";
pub const RPC_DROPPED: &str = "rpc_dropped";
pub const POOL_IN_USE: &str = "call_pool_in_use";
pub const POOL_LIMIT: &str = "call_pool_limit";
pub const POOL_REFUSED: &str = "call_pool_refused";
pub const SCHEDULES_ACTIVE: &str = "schedule_active";
pub const SCHEDULE_FIRINGS: &str = "schedule_firings";
pub const SCHEDULE_OUTCOMES: &str = "schedule_outcomes";
pub const SCHEDULE_LATENESS: &str = "schedule_lateness";
pub const SCHEDULE_SKIPPED: &str = "schedule_skipped";
pub const SCHEDULE_RETIRED: &str = "schedule_retired";
pub const WORKERS: &str = "worker_dispatch_workers";
pub const WORKERS_PENDING: &str = "worker_dispatch_pending";
pub const WORKER_REQUESTS: &str = "worker_dispatch_requests";

/// One labelled figure.
pub struct Figure {
    pub label: &'static str,
    pub value: String,
}

fn fig(label: &'static str, value: String) -> Figure {
    Figure { label, value }
}

fn per_sec(v: Option<f64>) -> String {
    v.map(|v| format!("{}/s", short(v)))
        .unwrap_or_else(|| "–".to_string())
}

fn dur(v: Option<f64>) -> String {
    v.map(duration).unwrap_or_else(|| "–".to_string())
}

fn op(values: &'static str) -> Filter {
    Filter::of("op", values)
}

/// Commits per second by outcome: read-only, write, conflict.
pub fn commit_rates(q: &Query) -> [Option<f64>; 3] {
    let rate = |o| {
        q.rate(DB_CALLS[0], &op(o))
            .zip(q.rate(DB_CALLS[1], &op(o)))
            .map(|(a, b)| a + b)
    };
    [
        rate("commit_success_readonly"),
        rate("commit_success_write"),
        rate("commit_conflict"),
    ]
}

/// The headline numbers on the Overview.
pub struct Headline {
    pub players: f64,
    pub tasks_active: f64,
    pub tasks_suspended: f64,
    pub tasks_started: Option<f64>,
    pub commits: Option<f64>,
    pub conflicts: Option<f64>,
    pub rpc_queued: f64,
    pub rpc_wait_p99: Option<f64>,
}

pub fn headline(q: &Query) -> Headline {
    let [ro, w, c] = commit_rates(q);
    Headline {
        players: q.gauge(PLAYERS, &Filter::all()),
        tasks_active: q.gauge(TASKS_ACTIVE, &Filter::all()),
        tasks_suspended: q.gauge(TASKS_SUSPENDED, &Filter::all()),
        tasks_started: q.rate(SCHED_CALLS, &op("start_task")),
        commits: ro.zip(w).map(|(a, b)| a + b),
        conflicts: c,
        rpc_queued: q.gauge(RPC_QUEUED, &Filter::of("queue", "worker")),
        rpc_wait_p99: q.quantile(&[RPC_WAIT], &Filter::of("queue", "worker"), 0.99),
    }
}

/// Problems worth an operator's attention, over the query's period. The conditions follow the
/// alert rules the Timbran deployment uses.
pub fn warnings(q: &Query) -> Vec<String> {
    let mut w = vec![];
    for (pool, n) in q.increase_by(POOL_REFUSED, "pool", &Filter::all()) {
        w.push(format!(
            "{} {pool} calls refused: the pool was full",
            short(n)
        ));
    }
    let refused = q.increase(DB_COUNTERS, &op("commit_queue_timeout"));
    if refused > 0.0 {
        w.push(format!(
            "{} commits refused by the commit queue timeout (tasks got E_QUOTA)",
            short(refused)
        ));
    }
    if let Some(p99) = q.quantile(&[RPC_WAIT], &Filter::of("queue", "worker"), 0.99)
        && p99 > 1e9
    {
        w.push(format!(
            "RPC requests waiting {} for a worker thread (p99)",
            duration(p99)
        ));
    }
    for (queue, n) in q.increase_by(RPC_DROPPED, "queue", &Filter::all()) {
        w.push(format!(
            "{} RPC requests dropped: the {queue} queue was full",
            short(n)
        ));
    }
    let faulted = q.increase(SCHEDULE_RETIRED, &Filter::of("reason", "max_faults"));
    if faulted > 0.0 {
        w.push(format!(
            "{} schedules retired after faulting repeatedly",
            short(faulted)
        ));
    }
    for (kind, n) in q.gauge_by(WORKERS, "worker_type", &Filter::all()) {
        if n == 0.0 {
            w.push(format!("No {kind} worker attached"));
        }
    }
    let no_worker = q.increase(WORKER_REQUESTS, &Filter::of("result", "no_worker"));
    if no_worker > 2.0 {
        w.push(format!(
            "{} worker requests failed with no worker to take them",
            short(no_worker)
        ));
    }
    if let Some(c) = commit_rates(q)[2]
        && c >= 1.0
    {
        w.push(format!("{} commit conflicts a second", short(c)));
    }
    w
}

/// Rates of scheduler operations, labelled for display.
fn sched_rates(q: &Query, ops: &[(&'static str, &'static str)]) -> Vec<Figure> {
    ops.iter()
        .map(|(name, label)| fig(label, per_sec(q.rate(SCHED_CALLS, &Filter::of("op", name)))))
        .collect()
}

pub fn task_activity(q: &Query) -> Vec<Figure> {
    sched_rates(
        q,
        &[
            ("start_task", "started"),
            ("resume_task", "resumed"),
            ("fork_task", "forked"),
            ("kill_task", "killed"),
        ],
    )
}

pub fn task_trouble(q: &Query) -> Vec<Figure> {
    sched_rates(
        q,
        &[
            ("task_conflict_retry", "conflict retries"),
            ("retry_task", "retried"),
            ("task_abort_limits", "aborted at limits"),
            ("task_abort_cancelled", "cancelled"),
            ("task_exception", "uncaught errors"),
        ],
    )
}

pub fn task_latency(q: &Query) -> Vec<Figure> {
    [
        ("task_submit_to_first_run_latency", "submit → first run"),
        ("task_wake_to_dispatch_latency", "wake → dispatch"),
        ("task_thread_handoff_latency", "thread handoff"),
        ("submit_command_task_latency", "submit command"),
        ("submit_verb_task_latency", "submit verb call"),
    ]
    .iter()
    .map(|(name, label)| {
        fig(
            label,
            dur(q.quantile(&[SCHED_SAMPLES], &Filter::of("op", name), 0.99)),
        )
    })
    .collect()
}

/// Suspended tasks by what they wait for, leaving out kinds with none.
pub fn suspended(q: &Query) -> Vec<(String, f64)> {
    q.gauge_by(TASKS_SUSPENDED, "waiting_for", &Filter::all())
        .into_iter()
        .filter(|(_, n)| *n > 0.0)
        .collect()
}

pub fn schedules(q: &Query) -> Vec<Figure> {
    let outcome = |o| per_sec(q.rate(SCHEDULE_OUTCOMES, &Filter::of("outcome", o)));
    vec![
        fig("active", short(q.gauge(SCHEDULES_ACTIVE, &Filter::all()))),
        fig("firings", per_sec(q.rate(SCHEDULE_FIRINGS, &Filter::all()))),
        fig("succeeded", outcome("success")),
        fig("faulted", outcome("fault")),
        fig(
            "late by (p99)",
            dur(q.quantile(&[SCHEDULE_LATENESS], &Filter::all(), 0.99)),
        ),
        fig(
            "skipped",
            short(q.increase(SCHEDULE_SKIPPED, &Filter::all())),
        ),
        fig(
            "retired",
            short(q.increase(SCHEDULE_RETIRED, &Filter::all())),
        ),
    ]
}

/// Commit latency: overall p50 and p99, then each phase's p99.
pub fn commit_latency(q: &Query) -> Vec<Figure> {
    let p =
        |name: &'static str, quant| dur(q.quantile(&DB_SAMPLES, &Filter::of("op", name), quant));
    vec![
        fig("commit p50", p("commit", 0.5)),
        fig("commit p99", p("commit", 0.99)),
        fig("  prepare", p("commit_prepare_working_set_phase", 0.99)),
        fig("  check", p("commit_check_phase", 0.99)),
        fig("  apply", p("commit_apply_phase", 0.99)),
        fig("  wait", p("commit_wait_phase", 0.99)),
        fig("  process", p("commit_process_phase", 0.99)),
    ]
}

/// Database operations by share of a thread. Commits and their phases are left out: they overlap
/// each other and the operations inside them, and the commit figures cover them.
pub fn db_operations(q: &Query) -> Vec<Timer> {
    let mut timers = q.timers(&DB_CALLS, &DB_SAMPLES, "op", &Filter::all());
    timers.retain(|t| !t.name.starts_with("commit"));
    timers
}

/// Builtins by share of a thread, from the daemon's exact call counts and sampled latencies.
pub fn builtin_timers(q: &Query) -> Vec<Timer> {
    q.timers(&[BF_CALLS], &[BF_SAMPLES], "op", &Filter::all())
}

pub fn write_path(q: &Query) -> Vec<Figure> {
    [
        (
            "property_value_complete_replacement",
            "property values replaced",
        ),
        ("property_list_append_accepted", "list appends"),
        ("crdt_resolve_success", "merges resolved"),
        ("crdt_resolve_fail", "merges failed"),
        ("batch_writer_backpressure", "writer backpressure"),
        ("commit_queue_timeout", "commits refused"),
    ]
    .iter()
    .map(|(name, label)| fig(label, per_sec(q.rate(DB_COUNTERS, &Filter::of("op", name)))))
    .collect()
}

/// A cache's hit ratio over the period, its size, and flushes per second.
pub struct Cache {
    pub name: String,
    pub hit_ratio: Option<f64>,
    pub entries: f64,
    pub flushes: Option<f64>,
}

pub fn caches(q: &Query) -> Vec<Cache> {
    let mut caches = vec![];
    for (name, entries) in q.gauge_by(DB_CACHE_ENTRIES, "cache", &Filter::all()) {
        let of = |ops| q.increase(DB_CACHE_OPS, &Filter::of("op", ops).and("cache", &name));
        let hits = of("hits|negative_hits");
        let total = hits + of("misses");
        caches.push(Cache {
            hit_ratio: (total > 0.0).then(|| hits / total),
            entries,
            flushes: q.rate(
                DB_CACHE_OPS,
                &Filter::of("op", "flushes").and("cache", &name),
            ),
            name,
        });
    }
    if q.has(PROGRAM_CACHE_OPS) || q.has(PROGRAM_CACHE_SLOTS) {
        let hits = q.increase(PROGRAM_CACHE_OPS, &op("hits"));
        let total = hits + q.increase(PROGRAM_CACHE_OPS, &op("misses"));
        caches.push(Cache {
            name: "program".to_string(),
            hit_ratio: (total > 0.0).then(|| hits / total),
            entries: q.gauge(PROGRAM_CACHE_SLOTS, &Filter::all()),
            flushes: None,
        });
    }
    caches
}

pub fn maintenance(q: &Query) -> Vec<Figure> {
    [
        ("gc_mark_phase", "GC mark"),
        ("gc_sweep_phase", "GC sweep"),
        ("checkpoint_latency", "checkpoint"),
    ]
    .iter()
    .map(|(name, label)| {
        fig(
            label,
            dur(q.mean(&[SCHED_SAMPLES], &Filter::of("op", name))),
        )
    })
    .collect()
}

/// One RPC queue.
pub struct RpcQueue {
    pub name: String,
    pub queued: f64,
    pub taken: Option<f64>,
    pub p50: Option<f64>,
    pub p99: Option<f64>,
    pub dropped: Option<f64>,
}

pub fn rpc_queues(q: &Query) -> Vec<RpcQueue> {
    q.gauge_by(RPC_QUEUED, "queue", &Filter::all())
        .into_iter()
        .map(|(name, queued)| {
            let f = || Filter::of("queue", &name);
            RpcQueue {
                queued,
                taken: q.rate(RPC_WAIT_CALLS, &f()),
                p50: q.quantile(&[RPC_WAIT], &f(), 0.5),
                p99: q.quantile(&[RPC_WAIT], &f(), 0.99),
                dropped: q.rate(RPC_DROPPED, &f()),
                name,
            }
        })
        .collect()
}

/// One deferred call pool: places in use, its limit, and calls refused over the period.
pub struct Pool {
    pub name: String,
    pub in_use: f64,
    pub limit: f64,
    pub refused: f64,
}

pub fn pools(q: &Query) -> Vec<Pool> {
    q.gauge_by(POOL_LIMIT, "pool", &Filter::all())
        .into_iter()
        .map(|(name, limit)| Pool {
            in_use: q.gauge(POOL_IN_USE, &Filter::of("pool", &name)),
            refused: q.increase(POOL_REFUSED, &Filter::of("pool", &name)),
            limit,
            name,
        })
        .collect()
}

pub fn sessions(q: &Query) -> Vec<Figure> {
    vec![
        fig("players", short(q.gauge(PLAYERS, &Filter::all()))),
        fig("connections", short(q.gauge(CONNECTIONS, &Filter::all()))),
        fig("hosts", short(q.gauge(HOSTS, &Filter::all()))),
    ]
}

/// One worker type: attached, requests pending, and requests per second by result.
pub struct Worker {
    pub name: String,
    pub attached: f64,
    pub pending: f64,
    pub results: Vec<(String, f64)>,
}

pub fn workers(q: &Query) -> Vec<Worker> {
    q.gauge_by(WORKERS, "worker_type", &Filter::all())
        .into_iter()
        .map(|(name, attached)| Worker {
            pending: q.gauge(WORKERS_PENDING, &Filter::of("worker_type", &name)),
            results: q
                .rate_by(
                    &[WORKER_REQUESTS],
                    "result",
                    &Filter::of("worker_type", &name),
                )
                .into_iter()
                .filter(|(_, r)| *r > 0.0)
                .collect(),
            attached,
            name,
        })
        .collect()
}
