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

//! What one capture interval measured, and the views built from one or more of them.

use std::collections::HashMap;

use moor_var::Obj;

use crate::metrics::MetricSet;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Frame kinds, as the daemon's probes report them.
pub const KIND_NONE: u64 = 0;
pub const KIND_VERB: u64 = 1;
pub const KIND_LAMBDA: u64 = 2;
pub const KIND_BUILTIN: u64 = 3;
pub const KIND_EVAL: u64 = 4;
pub const KIND_NATIVE: u64 = 5;

/// The identity of a frame: its kind and three kind-specific values.
#[derive(
    Clone, Copy, Debug, Default, Eq, Hash, PartialEq, Ord, PartialOrd, Serialize, Deserialize,
)]
pub struct FrameKey {
    pub kind: u64,
    pub a: u64,
    pub b: u64,
    pub c: u64,
}

/// The first line of a recording.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Header {
    pub pid: u32,
    pub binary: String,
    pub hz: u32,
    /// Seconds since the Unix epoch.
    pub started: u64,
}

/// Counts for one interval.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Snapshot {
    /// Wall time this interval covered, in seconds.
    pub seconds: f64,
    /// Daemon samples on any thread.
    pub samples: u64,
    /// Samples by task and top frame.
    pub frames: Vec<(u64, FrameKey, u64)>,
    /// Samples inside a commit, by task. Task 0 means outside any task.
    pub commit_samples: Vec<(u64, u64)>,
    /// Frames entered.
    pub calls: Vec<(FrameKey, u64)>,
    /// Commits finished, and their total nanoseconds, indexed by result: read-only, write,
    /// conflict, error.
    pub commits: [u64; 4],
    pub commit_ns: [u64; 4],
    /// Names first seen in this interval.
    pub names: Vec<(FrameKey, String)>,
    /// The daemon's metrics, the last set that arrived in this interval.
    #[serde(default)]
    pub metrics: Option<MetricSet>,
}

impl Snapshot {
    /// Add `other` into this one.
    pub fn merge(&mut self, other: &Snapshot) {
        self.seconds += other.seconds;
        self.samples += other.samples;
        self.frames.extend_from_slice(&other.frames);
        self.commit_samples.extend_from_slice(&other.commit_samples);
        self.calls.extend_from_slice(&other.calls);
        for i in 0..4 {
            self.commits[i] += other.commits[i];
            self.commit_ns[i] += other.commit_ns[i];
        }
        self.names.extend_from_slice(&other.names);
        if other.metrics.is_some() {
            self.metrics.clone_from(&other.metrics);
        }
    }
}

/// Every name seen so far in a capture.
#[derive(Default)]
pub struct Names(HashMap<FrameKey, String>);

impl Names {
    pub fn learn(&mut self, snapshot: &Snapshot) {
        for (key, name) in &snapshot.names {
            self.0.insert(*key, name.clone());
        }
    }

    /// A display label: `#definer:verb` for verbs, the name for builtins.
    pub fn label(&self, key: &FrameKey) -> String {
        let name = self.0.get(key).map(String::as_str);
        match key.kind {
            KIND_NONE => "(between frames)".to_string(),
            KIND_EVAL => "(eval)".to_string(),
            KIND_BUILTIN => match name {
                Some(name) => format!("{name}()"),
                None => format!("builtin {}", key.a),
            },
            KIND_VERB | KIND_LAMBDA | KIND_NATIVE => {
                let definer = format_obj(key.a);
                let native = if key.kind == KIND_NATIVE {
                    " (native)"
                } else {
                    ""
                };
                match name {
                    Some(name) => format!("{definer}:{name}{native}"),
                    None => format!("{definer}:{}{native}", Uuid::from_u64_pair(key.b, key.c)),
                }
            }
            kind => format!("kind {kind}"),
        }
    }
}

/// Format an object the way MOO prints it, from its raw encoding.
fn format_obj(raw: u64) -> String {
    match Obj::from_bytes(&raw.to_ne_bytes()) {
        Ok(obj) => obj.to_string(),
        Err(_) => format!("#?{raw:x}"),
    }
}

/// One row of a view.
#[derive(Clone, Debug)]
pub struct Row {
    pub label: String,
    /// Samples, as a percentage of one CPU.
    pub cpu: f64,
    /// Calls per second, where the view counts calls.
    pub calls: Option<f64>,
    /// Extra text, such as a task's busiest frame.
    pub detail: String,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum View {
    Overview,
    Verbs,
    Builtins,
    Tasks,
    Database,
    Rpc,
}

impl View {
    pub const ALL: [View; 6] = [
        View::Overview,
        View::Verbs,
        View::Builtins,
        View::Tasks,
        View::Database,
        View::Rpc,
    ];

    pub fn title(self) -> &'static str {
        match self {
            View::Overview => "Overview",
            View::Verbs => "Verbs",
            View::Builtins => "Builtins",
            View::Tasks => "Tasks",
            View::Database => "Database",
            View::Rpc => "RPC",
        }
    }
}

/// Totals for the header line.
#[derive(Clone, Copy, Debug, Default)]
pub struct Summary {
    /// CPU percentages: the whole daemon, MOO tasks running frames, commits, and everything
    /// else (other daemon threads). The last three add up to the first.
    pub daemon_cpu: f64,
    pub task_cpu: f64,
    pub commit_cpu: f64,
    pub other_cpu: f64,
    /// Commits per second by result, and mean commit time in microseconds.
    pub commits: [f64; 4],
    pub commit_us: [f64; 4],
}

/// Turns sample counts into CPU percentages.
struct Scale {
    per_sample: f64,
    seconds: f64,
}

impl Scale {
    fn new(snapshot: &Snapshot, hz: u32) -> Self {
        let seconds = snapshot.seconds.max(1e-9);
        Self {
            per_sample: 100.0 / (f64::from(hz) * seconds),
            seconds,
        }
    }
}

pub fn summary(snapshot: &Snapshot, hz: u32) -> Summary {
    let scale = Scale::new(snapshot, hz);
    let frame_samples: u64 = snapshot.frames.iter().map(|(_, _, n)| n).sum();
    let commit_samples: u64 = snapshot.commit_samples.iter().map(|(_, n)| n).sum();
    let other_samples = snapshot
        .samples
        .saturating_sub(frame_samples + commit_samples);
    let mut commits = [0.0; 4];
    let mut commit_us = [0.0; 4];
    for i in 0..4 {
        commits[i] = snapshot.commits[i] as f64 / scale.seconds;
        if snapshot.commits[i] > 0 {
            commit_us[i] = snapshot.commit_ns[i] as f64 / snapshot.commits[i] as f64 / 1000.0;
        }
    }
    Summary {
        daemon_cpu: snapshot.samples as f64 * scale.per_sample,
        task_cpu: frame_samples as f64 * scale.per_sample,
        commit_cpu: commit_samples as f64 * scale.per_sample,
        other_cpu: other_samples as f64 * scale.per_sample,
        commits,
        commit_us,
    }
}

/// Build the rows for `view`, busiest first.
pub fn rows(snapshot: &Snapshot, hz: u32, names: &Names, view: View) -> Vec<Row> {
    let scale = Scale::new(snapshot, hz);
    let mut rows = match view {
        View::Verbs => frame_rows(snapshot, &scale, names, |k| {
            matches!(
                k.kind,
                KIND_VERB | KIND_LAMBDA | KIND_NATIVE | KIND_EVAL | KIND_NONE
            )
        }),
        View::Builtins => frame_rows(snapshot, &scale, names, |k| k.kind == KIND_BUILTIN),
        View::Tasks => task_rows(snapshot, &scale, names),
        View::Overview | View::Database | View::Rpc => vec![],
    };
    rows.sort_by(|x, y| {
        y.cpu
            .total_cmp(&x.cpu)
            .then_with(|| y.calls.unwrap_or(0.0).total_cmp(&x.calls.unwrap_or(0.0)))
    });
    rows
}

/// Lambdas count as part of the verb that defines them.
fn merge_lambda(key: FrameKey) -> FrameKey {
    if key.kind == KIND_LAMBDA {
        FrameKey {
            kind: KIND_VERB,
            ..key
        }
    } else {
        key
    }
}

fn frame_rows(
    snapshot: &Snapshot,
    scale: &Scale,
    names: &Names,
    include: impl Fn(&FrameKey) -> bool,
) -> Vec<Row> {
    let mut by_frame: HashMap<FrameKey, (u64, u64)> = HashMap::new();
    for (_, key, n) in &snapshot.frames {
        if include(key) {
            by_frame.entry(merge_lambda(*key)).or_default().0 += n;
        }
    }
    for (key, n) in &snapshot.calls {
        // Lambda calls are not verb calls.
        if include(key) && key.kind != KIND_LAMBDA {
            by_frame.entry(*key).or_default().1 += n;
        }
    }
    by_frame
        .into_iter()
        .map(|(key, (samples, calls))| Row {
            label: names.label(&key),
            cpu: samples as f64 * scale.per_sample,
            calls: (key.kind != KIND_NONE).then(|| calls as f64 / scale.seconds),
            detail: String::new(),
        })
        .collect()
}

fn task_rows(snapshot: &Snapshot, scale: &Scale, names: &Names) -> Vec<Row> {
    #[derive(Default)]
    struct Task {
        samples: u64,
        commit: u64,
        busiest: HashMap<FrameKey, u64>,
    }
    let mut tasks: HashMap<u64, Task> = HashMap::new();
    for (task, key, n) in &snapshot.frames {
        let t = tasks.entry(*task).or_default();
        t.samples += n;
        *t.busiest.entry(merge_lambda(*key)).or_default() += n;
    }
    for (task, n) in &snapshot.commit_samples {
        if *task != 0 {
            let t = tasks.entry(*task).or_default();
            t.samples += n;
            t.commit += n;
        }
    }
    tasks
        .into_iter()
        .map(|(task, t)| {
            let mut detail = t
                .busiest
                .iter()
                .max_by_key(|(_, n)| **n)
                .map(|(key, _)| names.label(key))
                .unwrap_or_default();
            if t.commit > 0 {
                let pct = 100.0 * t.commit as f64 / t.samples as f64;
                detail = format!("{detail}  [commit {pct:.0}%]");
            }
            Row {
                // The probes report task ids plus one, so that zero means no task.
                label: format!("task {}", task - 1),
                cpu: t.samples as f64 * scale.per_sample,
                calls: None,
                detail,
            }
        })
        .collect()
}
