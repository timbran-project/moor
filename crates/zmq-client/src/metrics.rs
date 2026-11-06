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

//! Metrics shared by every process that talks to the daemon: its RPC calls, and for workers, the
//! requests it handles.

use std::{
    path::PathBuf,
    sync::{
        LazyLock,
        atomic::{AtomicI64, Ordering},
    },
    time::Duration,
};

use clap_derive::Args;
use fast_telemetry::{
    DeriveLabel, ExportMetrics, LabeledCounter, LabeledSampledTimer, MetricKind, MetricLabels,
    MetricMeta, MetricVisitor,
};
use moor_common::{tasks::WorkerError, util::MetricsFileConfig};

/// The kinds of RPC call to the daemon. Each has its own socket pool.
#[derive(Clone, Copy, Debug, DeriveLabel)]
#[label_name = "class"]
pub(crate) enum CallClass {
    /// Requests on behalf of a client connection.
    Client = 0,
    /// Pongs, which have sockets reserved so that they get through when the others are busy.
    Control = 1,
    /// Requests on behalf of the host itself.
    Host = 2,
}

#[derive(ExportMetrics)]
#[metric_prefix = "rpc_client"]
struct RpcClientMetrics {
    /// Every call is timed, so the call count is every call made.
    #[help = "RPC calls to the daemon, including the wait for a socket"]
    latency: LabeledSampledTimer<CallClass>,
    #[help = "RPC calls to the daemon that failed"]
    errors: LabeledCounter<CallClass>,
}

static RPC_CLIENT_METRICS: LazyLock<RpcClientMetrics> = LazyLock::new(|| RpcClientMetrics {
    latency: LabeledSampledTimer::with_latency_buckets(16, 1),
    errors: LabeledCounter::new(16),
});

pub(crate) fn record_rpc_call<T, E>(class: CallClass, elapsed: Duration, result: &Result<T, E>) {
    RPC_CLIENT_METRICS.latency.record_elapsed(class, elapsed);
    if result.is_err() {
        RPC_CLIENT_METRICS.errors.inc(class);
    }
}

/// Visit the metrics of this process's RPC calls to the daemon.
pub fn visit_rpc_client_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    RPC_CLIENT_METRICS.visit_metrics(visitor);
}

/// How a worker request ended.
#[derive(Clone, Copy, Debug, DeriveLabel)]
#[label_name = "outcome"]
pub(crate) enum WorkerOutcome {
    Ok,
    PermissionDenied,
    InvalidRequest,
    InternalError,
    RequestTimedOut,
    RequestError,
    WorkerDetached,
    NoWorkerAvailable,
}

impl WorkerOutcome {
    pub(crate) fn of<T>(result: &Result<T, WorkerError>) -> Self {
        match result {
            Ok(_) => Self::Ok,
            Err(WorkerError::PermissionDenied(_)) => Self::PermissionDenied,
            Err(WorkerError::InvalidRequest(_)) => Self::InvalidRequest,
            Err(WorkerError::InternalError(_)) => Self::InternalError,
            Err(WorkerError::RequestTimedOut(_)) => Self::RequestTimedOut,
            Err(WorkerError::RequestError(_)) => Self::RequestError,
            Err(WorkerError::WorkerDetached(_)) => Self::WorkerDetached,
            Err(WorkerError::NoWorkerAvailable(_)) => Self::NoWorkerAvailable,
        }
    }
}

#[derive(ExportMetrics)]
#[metric_prefix = "worker"]
struct WorkerMetrics {
    #[help = "Worker requests handled, by how they ended"]
    requests: LabeledSampledTimer<WorkerOutcome>,
}

static WORKER_METRICS: LazyLock<WorkerMetrics> = LazyLock::new(|| WorkerMetrics {
    requests: LabeledSampledTimer::with_latency_buckets(16, 1),
});

static WORKER_REQUESTS_IN_FLIGHT: AtomicI64 = AtomicI64::new(0);

const IN_FLIGHT: MetricMeta<'static> = MetricMeta {
    name: "worker_requests_in_flight",
    help: "Worker requests being handled",
    kind: MetricKind::Gauge,
    unit: None,
};

/// Counts a worker request as in flight until it is dropped.
pub(crate) struct InFlightRequest;

impl InFlightRequest {
    pub(crate) fn start() -> Self {
        WORKER_REQUESTS_IN_FLIGHT.fetch_add(1, Ordering::Relaxed);
        Self
    }
}

impl Drop for InFlightRequest {
    fn drop(&mut self) {
        WORKER_REQUESTS_IN_FLIGHT.fetch_sub(1, Ordering::Relaxed);
    }
}

pub(crate) fn record_worker_request(outcome: WorkerOutcome, elapsed: Duration) {
    WORKER_METRICS.requests.record_elapsed(outcome, elapsed);
}

/// Visit the metrics of the requests this worker handles.
pub fn visit_worker_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    WORKER_METRICS.visit_metrics(visitor);
    visitor.gauge_i64(
        IN_FLIGHT,
        MetricLabels::none(),
        WORKER_REQUESTS_IN_FLIGHT.load(Ordering::Relaxed),
    );
}

/// Command line options for writing a process's metrics to a file. See
/// [`moor_common::util::MetricsExporter`].
#[derive(Args, Clone, Debug)]
pub struct MetricsFileArgs {
    #[arg(
        long,
        value_name = "FILE",
        help = "Write metrics in the Prometheus text format to this file, replaced on each interval and deleted on shutdown. Serve it with a static file server or node_exporter's textfile collector (name it *.prom). Off unless set."
    )]
    pub metrics_file: Option<PathBuf>,

    #[arg(
        long,
        value_name = "SECONDS",
        help = "Seconds between writes of --metrics-file",
        default_value = "10",
        value_parser = clap::value_parser!(u32).range(1..)
    )]
    pub metrics_interval_seconds: u32,
}

impl MetricsFileArgs {
    pub fn config(&self) -> Option<MetricsFileConfig> {
        self.metrics_file.clone().map(|path| MetricsFileConfig {
            path,
            interval: Duration::from_secs(u64::from(self.metrics_interval_seconds)),
        })
    }
}
