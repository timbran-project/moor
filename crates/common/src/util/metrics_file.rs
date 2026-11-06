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

//! Exporting a process's metrics: in the Prometheus text format, rendered on request for a process
//! that serves HTTP, or written to a file on an interval for one that doesn't (a static file server
//! or node_exporter's textfile collector can serve the file); and to a tracer such as `mootop`,
//! through USDT probes, while one is attached.

use std::fmt::Write as _;
use std::{
    io,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread::JoinHandle,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use eyre::{Report, bail};
use fast_telemetry::{MetricKind, MetricLabels, MetricMeta, MetricVisitor};
use tracing::{info, warn};

use crate::{
    threading::spawn_efficient,
    util::{
        MetricFamilyKind, MetricValue, MetricsSnapshot, MetricsSnapshotBuilder,
        render_prometheus_text,
    },
};

/// Prefix for every metric name.
const NAMESPACE: &str = "moor";

const WRITTEN_AT: MetricMeta<'static> = MetricMeta {
    name: "metrics_written_timestamp_seconds",
    help: "When the process wrote this file, in seconds since the Unix epoch",
    kind: MetricKind::Gauge,
    unit: Some("seconds"),
};

/// Render what `visit` reports in the Prometheus text format. Every name starts with `moor_`, and
/// every series has a `service` label naming the process, so that files from several processes can
/// be served side by side.
pub fn render_service_metrics(
    service: &str,
    visit: impl FnOnce(&mut MetricsSnapshotBuilder),
) -> String {
    render_prometheus_text(
        &MetricsSnapshot::collect(visit),
        NAMESPACE,
        &[("service", service)],
    )
}

#[derive(Clone, Debug)]
pub struct MetricsFileConfig {
    pub path: PathBuf,
    pub interval: Duration,
}

/// How often the exporter checks whether a tracer is attached.
const TRACER_CHECK_INTERVAL: Duration = Duration::from_secs(1);

/// The thread that exports a process's metrics: it keeps a metrics file current, if there is one,
/// and once a second checks whether a tracer is attached to the `moor:metrics_begin` probe. While
/// none is, the check is one load. While one is, it sends every sample through `moor:metric`.
///
/// Dropping it, including on an early return, stops it and deletes the file, so a file server
/// stops serving numbers from a process that has exited. A crash leaves the file behind; its
/// timestamp shows how old it is.
pub struct MetricsExporter {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl MetricsExporter {
    pub fn spawn<F>(
        file: Option<MetricsFileConfig>,
        service: &'static str,
        visit: F,
    ) -> Result<Self, Report>
    where
        F: Fn(&mut MetricsSnapshotBuilder) + Send + 'static,
    {
        if let Some(config) = &file {
            if config.path.file_name().is_none() {
                bail!(
                    "Metrics file path {} has no file name",
                    config.path.display()
                );
            }
            let dir = parent_dir(&config.path);
            if !dir.is_dir() {
                bail!("Metrics file directory {} does not exist", dir.display());
            }
            info!(
                path = %config.path.display(),
                interval = ?config.interval,
                "Writing metrics file"
            );
        }

        let stop = Arc::new(AtomicBool::new(false));
        let thread_stop = stop.clone();
        let thread = spawn_efficient("moor-metrics", move || {
            run(file.as_ref(), service, &visit, &thread_stop);
        })?;
        Ok(Self {
            stop,
            thread: Some(thread),
        })
    }
}

impl Drop for MetricsExporter {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let Some(thread) = self.thread.take() else {
            return;
        };
        thread.thread().unpark();
        if thread.join().is_err() {
            warn!("Metrics thread panicked");
        }
    }
}

fn run<F>(file: Option<&MetricsFileConfig>, service: &str, visit: &F, stop: &AtomicBool)
where
    F: Fn(&mut MetricsSnapshotBuilder),
{
    let mut failing = false;
    let mut next_write = Instant::now();
    let tick = file.map_or(TRACER_CHECK_INTERVAL, |f| {
        f.interval.min(TRACER_CHECK_INTERVAL)
    });
    while !stop.load(Ordering::SeqCst) {
        send_to_tracer(service, visit);
        if let Some(config) = file
            && Instant::now() >= next_write
        {
            next_write = Instant::now() + config.interval;
            match write_atomically(
                &config.path,
                &render_file(SystemTime::now(), service, visit),
            ) {
                Ok(()) if failing => {
                    info!(path = %config.path.display(), "Writing metrics file again");
                    failing = false;
                }
                Ok(()) => {}
                Err(error) if !failing => {
                    warn!(path = %config.path.display(), %error, "Unable to write metrics file");
                    failing = true;
                }
                Err(_) => {}
            }
        }
        // Woken early by drop. A spurious wakeup only checks sooner.
        std::thread::park_timeout(tick);
    }

    let Some(config) = file else {
        return;
    };
    for path in [config.path.clone(), temp_path(&config.path)] {
        if let Err(error) = std::fs::remove_file(&path)
            && error.kind() != io::ErrorKind::NotFound
        {
            warn!(path = %path.display(), %error, "Unable to remove metrics file");
        }
    }
}

/// Parts of a sample sent through `moor:metric`.
const PART_INT: u64 = 0;
const PART_FLOAT: u64 = 1;
const PART_COUNT: u64 = 2;
const PART_SUM: u64 = 3;
const PART_BUCKET: u64 = 4;

/// If a tracer is attached, send it every sample. `moor:metrics_begin(service)` starts a set,
/// `moor:metrics_end` ends it, and between them `moor:metric(name, labels, kind, part, value,
/// bound)` fires once per value:
///
/// - `name` and `labels` are UTF-8 strings, as pointer and length; labels are `key=value` pairs
///   joined by commas
/// - `kind` is 0 for a counter, 1 for a gauge, 2 for a histogram
/// - `part` says what `value` is: 0 an integer, 1 a float's bits, 2 a histogram's count, 3 its sum,
///   4 a cumulative bucket count, whose upper bound is `bound` (`u64::MAX` for `+Inf`)
///
/// Counters at zero and histograms with no observations are not sent: a tracer treats a series
/// it hasn't seen as zero. Most of a process's series are idle, so this sends far fewer values.
fn send_to_tracer<F>(service: &str, visit: &F)
where
    F: Fn(&mut MetricsSnapshotBuilder),
{
    if !probe::probe_lazy!(moor, metrics_begin, service.as_ptr(), service.len()) {
        return;
    }
    let snapshot = MetricsSnapshot::collect(visit);
    let mut labels = String::new();
    for family in &snapshot.families {
        let kind = family.kind as u64;
        let name = family.name.as_str();
        let counter = matches!(family.kind, MetricFamilyKind::Counter);
        for sample in &family.samples {
            let idle = match &sample.value {
                MetricValue::Int(v) => counter && *v == 0,
                MetricValue::Float(v) => counter && *v == 0.0,
                MetricValue::Histogram(h) => h.count == 0,
            };
            if idle {
                continue;
            }
            labels.clear();
            for (i, (key, value)) in sample.labels.iter().enumerate() {
                let comma = if i > 0 { "," } else { "" };
                let _ = write!(labels, "{comma}{key}={value}");
            }
            let send = |part: u64, value: u64, bound: u64| {
                probe::probe_lazy!(
                    moor,
                    metric,
                    name.as_ptr(),
                    name.len(),
                    labels.as_ptr(),
                    labels.len(),
                    kind,
                    part,
                    value,
                    bound
                );
            };
            match &sample.value {
                MetricValue::Int(v) => send(PART_INT, *v as u64, 0),
                MetricValue::Float(v) => send(PART_FLOAT, v.to_bits(), 0),
                MetricValue::Histogram(h) => {
                    send(PART_COUNT, h.count, 0);
                    send(PART_SUM, h.sum, 0);
                    for (bound, count) in &h.buckets {
                        send(PART_BUCKET, *count, *bound);
                    }
                }
            }
        }
    }
    probe::probe_lazy!(moor, metrics_end);
}

fn render_file<F>(now: SystemTime, service: &str, visit: &F) -> String
where
    F: Fn(&mut MetricsSnapshotBuilder),
{
    let written_at = now
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64();
    render_service_metrics(service, |builder| {
        visit(builder);
        builder.gauge_f64(WRITTEN_AT, MetricLabels::none(), written_at);
    })
}

/// Write beside the target and rename over it, so readers never see a partial file.
fn write_atomically(path: &Path, contents: &str) -> io::Result<()> {
    let temp = temp_path(path);
    std::fs::write(&temp, contents)?;
    std::fs::rename(&temp, path)
}

fn parent_dir(path: &Path) -> &Path {
    match path.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent,
        _ => Path::new("."),
    }
}

/// A hidden name in the same directory, which node_exporter's textfile collector ignores because
/// it does not end in `.prom`.
fn temp_path(path: &Path) -> PathBuf {
    let mut name = std::ffi::OsString::from(".");
    name.push(path.file_name().unwrap_or_default());
    name.push(".tmp");
    parent_dir(path).join(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_until_stopped_then_removes_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.prom");
        let writer = MetricsExporter::spawn(
            Some(MetricsFileConfig {
                path: path.clone(),
                interval: Duration::from_secs(3600),
            }),
            "test",
            |_| {},
        )
        .unwrap();

        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while !path.exists() {
            assert!(
                std::time::Instant::now() < deadline,
                "metrics file not written"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(
            std::fs::read_to_string(&path)
                .unwrap()
                .contains("moor_metrics_written_timestamp_seconds{service=\"test\"}")
        );

        drop(writer);
        assert!(!path.exists());
        assert!(!temp_path(&path).exists());
    }

    #[test]
    fn rejects_missing_directory() {
        let dir = tempfile::tempdir().unwrap();
        let result = MetricsExporter::spawn(
            Some(MetricsFileConfig {
                path: dir.path().join("missing").join("test.prom"),
                interval: Duration::from_secs(10),
            }),
            "test",
            |_| {},
        );
        assert!(result.is_err());
    }
}
