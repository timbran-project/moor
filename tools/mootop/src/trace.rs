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

//! Runs bpftrace against the daemon and turns its output into snapshots.

use std::{
    fs,
    io::{BufRead, BufReader, Read},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::mpsc::{Receiver, Sender, channel},
    thread,
    time::{Duration, Instant},
};

use serde_json::Value;

use crate::{
    metrics::{MetricSet, MetricValue},
    snapshot::{FrameKey, Snapshot},
};

const SCRIPT: &str = include_str!("mootop.bt");
/// Added when the binary has the metrics probes, which only the daemon's exporter fires.
const METRICS_SCRIPT: &str = include_str!("metrics.bt");

/// Process names of the binaries that run the daemon.
const DAEMON_NAMES: [&str; 2] = ["moor-daemon", "moor"];

/// What the reader thread sends.
pub enum TraceEvent {
    Snapshot(Snapshot),
    /// bpftrace reported a problem that doesn't stop it, such as lost events.
    Warning(String),
    /// bpftrace exited. Carries its stderr.
    Exited(String),
}

pub struct Trace {
    pub pid: u32,
    pub binary: String,
    pub events: Receiver<TraceEvent>,
    /// Whether the binary sends its metrics.
    pub metrics: bool,
    child: Child,
}

impl Trace {
    pub fn start(pid: Option<u32>, hz: u32, bpftrace: &str) -> Result<Self, String> {
        let pid = match pid {
            Some(pid) => pid,
            None => find_daemon()?,
        };
        let binary = daemon_binary(pid)?;
        let metrics = has_probe(bpftrace, &binary, "metrics_begin")?;
        let mut script = SCRIPT.to_string();
        if metrics {
            script.push_str(METRICS_SCRIPT);
        }
        let script = script
            .replace("@BINARY@", &binary)
            .replace("@PID@", &pid.to_string())
            .replace("@HZ@", &hz.to_string());

        let mut child = Command::new(bpftrace)
            // Not `-p`: with it, bpftrace 0.27 sampled nothing. See mootop.bt.
            .args(["-f", "json", "--usdt-file-activation", "-e", &script])
            // Names and map sizes. bpftrace renamed these variables in 0.20; set both.
            .env("BPFTRACE_MAX_STRLEN", "128")
            .env("BPFTRACE_STRLEN", "128")
            .env("BPFTRACE_MAX_MAP_KEYS", "65536")
            .env("BPFTRACE_MAP_KEYS_MAX", "65536")
            // The daemon's metrics arrive as a burst of about a thousand lines on one CPU, more
            // than the default output buffer of 64 pages a CPU holds.
            .env("BPFTRACE_PERF_RB_PAGES", "256")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("Couldn't run {bpftrace}: {e}"))?;

        let stdout = child.stdout.take().expect("piped stdout");
        let mut stderr = child.stderr.take().expect("piped stderr");
        let (tx, rx) = channel();
        thread::spawn(move || {
            read_output(BufReader::new(stdout), &tx);
            let mut err = String::new();
            let _ = stderr.read_to_string(&mut err);
            let _ = tx.send(TraceEvent::Exited(err));
        });

        Ok(Self {
            pid,
            binary,
            events: rx,
            metrics,
            child,
        })
    }
}

impl Drop for Trace {
    fn drop(&mut self) {
        // SIGINT lets bpftrace detach its probes cleanly. Kill it if it doesn't stop.
        unsafe {
            libc::kill(self.child.id() as libc::pid_t, libc::SIGINT);
        }
        let deadline = Instant::now() + Duration::from_secs(3);
        while Instant::now() < deadline {
            if !matches!(self.child.try_wait(), Ok(None)) {
                return;
            }
            thread::sleep(Duration::from_millis(50));
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// Whether `binary` has the USDT probe `moor:name`. bpftrace refuses a script naming a probe
/// that doesn't exist.
fn has_probe(bpftrace: &str, binary: &str, name: &str) -> Result<bool, String> {
    let output = Command::new(bpftrace)
        .args(["-l", &format!("usdt:{binary}:moor:*")])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("Couldn't run {bpftrace}: {e}"))?;
    if !output.status.success() {
        return Err(format!(
            "{bpftrace} couldn't list the probes in {binary}.\n{}",
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    let suffix = format!(":moor:{name}");
    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .any(|line| line.trim().ends_with(&suffix)))
}

fn find_daemon() -> Result<u32, String> {
    let mut found = vec![];
    let entries = fs::read_dir("/proc").map_err(|e| format!("Couldn't read /proc: {e}"))?;
    for entry in entries.flatten() {
        let Ok(pid) = entry.file_name().to_string_lossy().parse::<u32>() else {
            continue;
        };
        let Ok(comm) = fs::read_to_string(entry.path().join("comm")) else {
            continue;
        };
        if DAEMON_NAMES.contains(&comm.trim()) {
            found.push(pid);
        }
    }
    match found.as_slice() {
        [pid] => Ok(*pid),
        [] => Err("No moor-daemon process found. Give one with --pid.".to_string()),
        pids => Err(format!(
            "Several daemon processes found ({pids:?}). Choose one with --pid."
        )),
    }
}

/// The daemon's executable, reachable from this mount namespace, so this also works when the
/// daemon runs in a container.
fn daemon_binary(pid: u32) -> Result<String, String> {
    let exe = fs::read_link(format!("/proc/{pid}/exe"))
        .map_err(|e| format!("Couldn't read the executable of process {pid}: {e}"))?;
    let mut path = PathBuf::from(format!("/proc/{pid}/root"));
    path.push(exe.strip_prefix("/").unwrap_or(&exe));
    Ok(path.to_string_lossy().into_owned())
}

fn read_output(reader: impl BufRead, tx: &Sender<TraceEvent>) {
    let mut current = Snapshot::default();
    let capture_start = Instant::now();
    // Names and metric sets arrive on their own schedule, between snapshots too.
    let mut names = vec![];
    let mut metrics: Option<MetricSet> = None;
    let mut building: Option<MetricSet> = None;
    for line in reader.lines() {
        let Ok(line) = line else {
            return;
        };
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let data = &message["data"];
        match message["type"].as_str() {
            Some("printf") => {
                let text = data.as_str().unwrap_or_default();
                for text in text.lines() {
                    if text == "T" {
                        current = Snapshot::default();
                    } else if text == "E" {
                        // The script prints its counts every second, clearing them, so each
                        // snapshot covers one second of probes, however late it arrives.
                        current.seconds = 1.0;
                        current.names.append(&mut names);
                        current.metrics = metrics.take();
                        let snapshot = std::mem::take(&mut current);
                        if tx.send(TraceEvent::Snapshot(snapshot)).is_err() {
                            return;
                        }
                    } else if let Some(name) = text.strip_prefix("N ").and_then(parse_name) {
                        names.push(name);
                    } else if text.starts_with("MB ") {
                        building = Some(MetricSet::default());
                    } else if text == "ME" {
                        if let Some(mut set) = building.take() {
                            set.at = capture_start.elapsed().as_secs_f64();
                            metrics = Some(set);
                        }
                    } else if let Some(rest) = text.strip_prefix("M ")
                        && let Some(set) = building.as_mut()
                        && let Some(value) = parse_metric(rest)
                    {
                        set.values.push(value);
                    }
                }
            }
            Some("map") => read_map(data, &mut current),
            Some("lost_events") => {
                let _ = tx.send(TraceEvent::Warning(format!("bpftrace lost events: {data}")));
            }
            _ => {}
        }
    }
}

fn parse_name(text: &str) -> Option<(FrameKey, String)> {
    let mut parts = text.splitn(5, ' ');
    let mut num = || parts.next().and_then(parse_u64);
    let key = FrameKey {
        kind: num()?,
        a: num()?,
        b: num()?,
        c: num()?,
    };
    Some((key, unescape(parts.next().unwrap_or_default())))
}

/// Decode the `\xNN` escapes bpftrace's `%r` writes for unprintable bytes.
fn unescape(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && bytes.get(i + 1) == Some(&b'x')
            && let Some(hex) = text.get(i + 2..i + 4)
            && let Ok(byte) = u8::from_str_radix(hex, 16)
        {
            out.push(byte);
            i += 4;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `kind part value bound name labels`; the labels may be empty.
fn parse_metric(text: &str) -> Option<MetricValue> {
    let mut parts = text.splitn(6, ' ');
    let mut num = || parts.next().and_then(parse_u64);
    let (kind, part, value, bound) = (num()?, num()?, num()?, num()?);
    Some(MetricValue {
        kind,
        part,
        value,
        bound,
        name: unescape(parts.next()?),
        labels: unescape(parts.next().unwrap_or_default()),
    })
}

/// bpftrace prints probe arguments as signed integers.
fn parse_u64(text: &str) -> Option<u64> {
    let text = text.trim();
    text.parse::<u64>()
        .ok()
        .or_else(|| text.parse::<i64>().ok().map(|v| v as u64))
}

fn value_u64(value: &Value) -> u64 {
    value
        .as_u64()
        .or_else(|| value.as_i64().map(|v| v as u64))
        .unwrap_or(0)
}

/// Map keys with several parts print as one comma-separated string.
fn key_parts(key: &str) -> Vec<u64> {
    key.trim_matches(|c| c == '[' || c == ']' || c == '(' || c == ')')
        .split(',')
        .filter_map(parse_u64)
        .collect()
}

fn read_map(data: &Value, snapshot: &mut Snapshot) {
    let Some(maps) = data.as_object() else {
        return;
    };
    for (name, value) in maps {
        // A map without keys prints as a number.
        if name == "@samples" {
            snapshot.samples = value_u64(value);
            continue;
        }
        let Some(entries) = value.as_object() else {
            continue;
        };
        for (key, value) in entries {
            let k = key_parts(key);
            let n = value_u64(value);
            match (name.as_str(), k.as_slice()) {
                ("@frame", [task, kind, a, b, c]) => snapshot.frames.push((
                    *task,
                    FrameKey {
                        kind: *kind,
                        a: *a,
                        b: *b,
                        c: *c,
                    },
                    n,
                )),
                ("@commit", [task]) => snapshot.commit_samples.push((*task, n)),
                ("@calls", [kind, a, b, c]) => snapshot.calls.push((
                    FrameKey {
                        kind: *kind,
                        a: *a,
                        b: *b,
                        c: *c,
                    },
                    n,
                )),
                ("@commits", [result]) if *result < 4 => snapshot.commits[*result as usize] = n,
                ("@commit_ns", [result]) if *result < 4 => snapshot.commit_ns[*result as usize] = n,
                _ => {}
            }
        }
    }
}
