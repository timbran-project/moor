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

//! Exporting a process's metrics in the Prometheus text format: rendered on request, for a process
//! that serves HTTP, or written to a file on an interval, for one that doesn't. A static file server
//! or node_exporter's textfile collector can serve the file.

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
use tracing::{info, warn};

use crate::{
    threading::spawn_efficient,
    util::{MetricsSnapshot, MetricsSnapshotBuilder, render_prometheus_text},
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

/// The thread that keeps a metrics file current. Dropping it, including on an early return,
/// stops it and deletes the file, so a file server stops serving numbers from a process that has
/// exited. A crash leaves the file behind; its timestamp shows how old it is.
pub struct MetricsFileWriter {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl MetricsFileWriter {
    pub fn spawn<F>(
        config: MetricsFileConfig,
        service: &'static str,
        visit: F,
    ) -> Result<Self, Report>
    where
        F: Fn(&mut MetricsSnapshotBuilder) + Send + 'static,
    {
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
            run(&config, service, &visit, &thread_stop);
        })?;
        Ok(Self {
            stop,
            thread: Some(thread),
        })
    }
}

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

fn run<F>(config: &MetricsFileConfig, service: &str, visit: &F, stop: &AtomicBool)
where
    F: Fn(&mut MetricsSnapshotBuilder),
{
    let mut failing = false;
    while !stop.load(Ordering::SeqCst) {
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
        // Woken early by drop. A spurious wakeup only writes the file sooner.
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
        let writer = MetricsFileWriter::spawn(
            MetricsFileConfig {
                path: path.clone(),
                interval: Duration::from_secs(3600),
            },
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
        let result = MetricsFileWriter::spawn(
            MetricsFileConfig {
                path: dir.path().join("missing").join("test.prom"),
                interval: Duration::from_secs(10),
            },
            "test",
            |_| {},
        );
        assert!(result.is_err());
    }
}
