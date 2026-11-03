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

//! Writes the runtime's metrics to a file in the Prometheus text format on an interval, for a
//! static file server or node_exporter's textfile collector to serve.

use std::{
    io,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread::JoinHandle,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use eyre::{Report, bail};
use fast_telemetry::{MetricKind, MetricLabels, MetricMeta, MetricVisitor};
use moor_common::{
    threading::spawn_efficient,
    util::{MetricsSnapshot, render_prometheus_text},
};

use crate::metrics::visit_daemon_metrics;
use tracing::{info, warn};

/// Prefix for every metric name in the file.
const NAMESPACE: &str = "moor";

const WRITTEN_AT: MetricMeta<'static> = MetricMeta {
    name: "metrics_written_timestamp_seconds",
    help: "When the daemon wrote this file, in seconds since the Unix epoch",
    kind: MetricKind::Gauge,
    unit: Some("seconds"),
};

#[derive(Clone, Debug)]
pub struct MetricsFileConfig {
    pub path: PathBuf,
    pub interval: Duration,
}

/// The thread that keeps the metrics file current. Stopping it deletes the file, so a file
/// server stops serving numbers from a daemon that has exited cleanly. A crash leaves the file
/// behind; its timestamp shows how old it is.
pub(crate) struct MetricsFileWriter {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl MetricsFileWriter {
    pub(crate) fn spawn(config: MetricsFileConfig) -> Result<Self, Report> {
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

        let stop = Arc::new(AtomicBool::new(false));
        let thread_stop = stop.clone();
        let thread = spawn_efficient("moor-metrics-file", move || {
            run(&config, &thread_stop);
        })?;
        Ok(Self {
            stop,
            thread: Some(thread),
        })
    }
}

/// Dropping the writer, including on an early return from the daemon, stops it and deletes the
/// file.
impl Drop for MetricsFileWriter {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let Some(thread) = self.thread.take() else {
            return;
        };
        thread.thread().unpark();
        if thread.join().is_err() {
            warn!("Metrics file thread panicked");
        }
    }
}

fn run(config: &MetricsFileConfig, stop: &AtomicBool) {
    let mut failing = false;
    while !stop.load(Ordering::SeqCst) {
        match write_atomically(&config.path, &render(SystemTime::now())) {
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
        // Woken early by stop(). A spurious wakeup only writes the file sooner.
        std::thread::park_timeout(config.interval);
    }

    for path in [config.path.clone(), temp_path(&config.path)] {
        if let Err(error) = std::fs::remove_file(&path)
            && error.kind() != io::ErrorKind::NotFound
        {
            warn!(path = %path.display(), %error, "Unable to remove metrics file");
        }
    }
}

fn render(now: SystemTime) -> String {
    let written_at = now
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64();
    let snapshot = MetricsSnapshot::collect(|builder| {
        visit_daemon_metrics(builder);
        builder.gauge_f64(WRITTEN_AT, MetricLabels::none(), written_at);
    });
    render_prometheus_text(&snapshot, NAMESPACE)
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
    fn renders_runtime_metrics_and_timestamp() {
        let text = render(UNIX_EPOCH + Duration::from_millis(1_500));
        assert!(text.contains("# TYPE moor_db_timers_hot_calls counter\n"));
        assert!(text.contains("# TYPE moor_bf_samples histogram\n"));
        assert!(text.contains("# TYPE moor_db_cache_entries gauge\n"));
        assert!(text.contains("moor_db_cache_entries{cache=\"property\"} "));
        assert!(text.contains("# TYPE moor_program_cache_live_slots gauge\n"));
        assert!(text.contains("# TYPE moor_rpc_queue_wait_samples histogram\n"));
        assert!(text.contains("moor_rpc_queued{queue=\"worker\"} "));
        assert!(text.ends_with(
            "# TYPE moor_metrics_written_timestamp_seconds gauge\n\
             moor_metrics_written_timestamp_seconds 1.5\n"
        ));
    }

    #[test]
    fn writes_until_stopped_then_removes_the_file() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("moor.prom");
        let writer = MetricsFileWriter::spawn(MetricsFileConfig {
            path: path.clone(),
            interval: Duration::from_secs(3600),
        })
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
                .contains("moor_metrics_written_timestamp_seconds")
        );

        drop(writer);
        assert!(!path.exists());
        assert!(!temp_path(&path).exists());
    }

    #[test]
    fn rejects_missing_directory() {
        let dir = tempfile::tempdir().unwrap();
        let result = MetricsFileWriter::spawn(MetricsFileConfig {
            path: dir.path().join("missing").join("moor.prom"),
            interval: Duration::from_secs(10),
        });
        assert!(result.is_err());
    }
}
