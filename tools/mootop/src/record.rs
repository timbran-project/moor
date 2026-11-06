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

//! Recordings: a header line, then one snapshot per line, as JSON.

use std::{
    fs::File,
    io::{BufRead, BufReader, BufWriter, Write},
    path::Path,
};

use crate::{
    dash::{self, Figure},
    metrics::{History, Timer, Window, duration, short},
    snapshot::{Header, Names, Snapshot, View, rows, summary},
};

pub struct Recorder {
    out: BufWriter<File>,
}

impl Recorder {
    pub fn create(path: &Path, header: &Header) -> Result<Self, String> {
        let file = File::create(path).map_err(|e| format!("Couldn't create {path:?}: {e}"))?;
        let mut recorder = Self {
            out: BufWriter::new(file),
        };
        recorder.line(header)?;
        Ok(recorder)
    }

    pub fn write(&mut self, snapshot: &Snapshot) -> Result<(), String> {
        self.line(snapshot)
    }

    fn line(&mut self, value: &impl serde::Serialize) -> Result<(), String> {
        serde_json::to_writer(&mut self.out, value).map_err(|e| e.to_string())?;
        // Flush each line, so an interrupted recording is still readable.
        writeln!(self.out)
            .and_then(|_| self.out.flush())
            .map_err(|e| format!("Couldn't write the recording: {e}"))
    }
}

/// Print a report of a recording.
pub fn report(path: &Path, top: usize) -> Result<(), String> {
    let file = File::open(path).map_err(|e| format!("Couldn't open {path:?}: {e}"))?;
    let mut lines = BufReader::new(file).lines();
    let header: Header = lines
        .next()
        .ok_or("The recording is empty.")?
        .map_err(|e| e.to_string())
        .and_then(|l| serde_json::from_str(&l).map_err(|e| format!("Bad header: {e}")))?;

    let mut total = Snapshot::default();
    let mut names = Names::default();
    let mut history = History::default();
    let mut intervals = 0;
    for line in lines {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let snapshot: Snapshot =
            serde_json::from_str(&line).map_err(|e| format!("Bad snapshot: {e}"))?;
        names.learn(&snapshot);
        total.merge(&snapshot);
        intervals += 1;
        if let Some(set) = &snapshot.metrics {
            history.push(set);
        }
    }

    let s = summary(&total, header.hz);
    let [ro, w, c, _] = s.commits;
    println!(
        "mootop recording of pid {} ({}), {intervals} intervals over {:.0}s, sampled at {} Hz",
        header.pid, header.binary, total.seconds, header.hz
    );
    println!();
    println!(
        "CPU      daemon {:.1}%   tasks {:.1}%   commits {:.1}%   other threads {:.1}%",
        s.daemon_cpu, s.task_cpu, s.commit_cpu, s.other_cpu
    );
    println!(
        "Commits  {:.1}/s: read-only {ro:.1}, write {w:.1} (mean {:.0}µs), conflict {c:.1}, \
         error {:.1}",
        s.commits.iter().sum::<f64>(),
        s.commit_us[1],
        s.commits[3]
    );
    let q = history.query(Window::All);
    if let Some(q) = &q {
        let h = dash::headline(q);
        println!(
            "At end   players {:.0}, tasks active {:.0}, suspended {:.0}",
            h.players, h.tasks_active, h.tasks_suspended
        );
        let warnings = dash::warnings(q);
        println!();
        if warnings.is_empty() {
            println!("Warnings: none");
        } else {
            println!("Warnings");
            for w in warnings {
                println!("  {w}");
            }
        }
    }

    for view in [View::Verbs, View::Builtins, View::Tasks] {
        let rows = rows(&total, header.hz, &names, view);
        println!();
        println!("{} by CPU (top {top} of {})", view.title(), rows.len());
        match view {
            View::Tasks => println!("{:>7}  {:<14}  Busiest frame", "%CPU", "Task"),
            _ => println!("{:>7}  {:>9}  Name", "%CPU", "Calls/s"),
        }
        for r in rows.iter().take(top) {
            match view {
                View::Tasks => println!("{:7.2}  {:<14}  {}", r.cpu, r.label, r.detail),
                _ => println!(
                    "{:7.2}  {:>9}  {}",
                    r.cpu,
                    r.calls.map(short).unwrap_or_default(),
                    r.label
                ),
            }
        }
    }

    let Some(q) = q else {
        println!();
        println!("Server metrics: none in this recording");
        return Ok(());
    };
    println!();
    println!(
        "Server metrics over the recording (per second, and percentiles of what was observed)"
    );
    timers(
        "Builtins by thread time, from the daemon's counts",
        &dash::builtin_timers(&q),
        top,
    );
    figures("Tasks per second", &dash::task_activity(&q));
    figures("Trouble per second", &dash::task_trouble(&q));
    figures("Scheduling delay, p99", &dash::task_latency(&q));
    println!();
    println!("Suspended at end, waiting for");
    for (what, n) in dash::suspended(&q) {
        println!("  {:<24} {}", what, short(n));
    }
    figures("Schedules", &dash::schedules(&q));
    figures("Commit latency", &dash::commit_latency(&q));
    timers(
        "Database operations by thread time",
        &dash::db_operations(&q),
        top,
    );
    figures("Writes per second", &dash::write_path(&q));
    println!();
    println!("Caches             hit ratio   entries  flushes/s");
    for cache in dash::caches(&q) {
        println!(
            "  {:<16} {:>9}  {:>8}  {:>9}",
            cache.name,
            cache
                .hit_ratio
                .map(|r| format!("{:.0}%", r * 100.0))
                .unwrap_or_default(),
            short(cache.entries),
            cache.flushes.map(short).unwrap_or_default()
        );
    }
    figures("Maintenance, mean", &dash::maintenance(&q));
    println!();
    println!("RPC queues        waiting   taken/s  wait p50  wait p99  dropped/s");
    for r in dash::rpc_queues(&q) {
        let opt = |v: Option<f64>, f: fn(f64) -> String| v.map(f).unwrap_or_default();
        println!(
            "  {:<14} {:>8}  {:>8}  {:>8}  {:>8}  {:>9}",
            r.name,
            short(r.queued),
            opt(r.taken, short),
            opt(r.p50, duration),
            opt(r.p99, duration),
            opt(r.dropped, short)
        );
    }
    println!();
    println!("Call pools        in use / limit   refused");
    for p in dash::pools(&q) {
        println!(
            "  {:<14} {:>6} / {:<6}  {:>8}",
            p.name,
            short(p.in_use),
            short(p.limit),
            short(p.refused)
        );
    }
    figures("Sessions at end", &dash::sessions(&q));
    let workers = dash::workers(&q);
    if !workers.is_empty() {
        println!();
        println!("Workers           attached  pending  requests by result");
        for w in workers {
            let results = w
                .results
                .iter()
                .map(|(r, n)| format!("{r} {}/s", short(*n)))
                .collect::<Vec<_>>()
                .join(", ");
            println!(
                "  {:<14} {:>8}  {:>7}  {results}",
                w.name,
                short(w.attached),
                short(w.pending)
            );
        }
    }
    Ok(())
}

fn figures(title: &str, figs: &[Figure]) {
    println!();
    println!("{title}");
    for f in figs {
        println!("  {:<24} {:>10}", f.label, f.value);
    }
}

fn timers(title: &str, timers: &[Timer], top: usize) {
    println!();
    println!("{title} (top {top} of {})", timers.len());
    println!(
        "  {:<36} {:>7}  {:>9}  {:>9}  {:>9}",
        "Operation", "Thread", "Calls/s", "Mean", "p99 ≤"
    );
    for t in timers.iter().take(top) {
        let opt = |v: Option<f64>| v.map(duration).unwrap_or_default();
        println!(
            "  {:<36} {:>7}  {:>9}  {:>9}  {:>9}",
            t.name,
            t.thread
                .map(|x| format!("{:.1}%", x * 100.0))
                .unwrap_or_default(),
            short(t.rate),
            opt(t.mean),
            opt(t.p99)
        );
    }
}
