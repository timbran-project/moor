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

//! The web host's metrics, served at `GET /metrics` on `--metrics-listen`, never on the public
//! listener.

use std::{
    net::SocketAddr,
    sync::{
        LazyLock,
        atomic::{AtomicI64, Ordering},
    },
    time::Instant,
};

use axum::{
    Router,
    extract::{MatchedPath, Request},
    http::{Method, StatusCode, header},
    middleware::Next,
    response::{IntoResponse, Response},
    routing::get,
};
use eyre::{Result, eyre};
use fast_telemetry::{
    DynamicHistogram, ExportMetrics, MetricKind, MetricLabels, MetricMeta, MetricVisitor,
};
use moor_common::util::render_service_metrics;
use moor_zmq_client::metrics::visit_rpc_client_metrics;
use tokio::net::TcpListener;
use tracing::{error, info};

/// Request time bounds in nanoseconds, from 10µs to 10s, matching the other timers.
const LATENCY_BOUNDS_NANOS: &[u64] = &[
    10_000,
    50_000,
    100_000,
    500_000,
    1_000_000,
    5_000_000,
    10_000_000,
    50_000_000,
    100_000_000,
    500_000_000,
    1_000_000_000,
    5_000_000_000,
    10_000_000_000,
];

/// Routes, methods and status classes are all bounded, so this is never reached; it only stops a
/// mistake from growing the series without limit.
const MAX_REQUEST_SERIES: usize = 2048;

#[derive(ExportMetrics)]
#[metric_prefix = "http"]
struct HttpMetrics {
    #[help = "HTTP requests by route, method and status class, timed until the response starts"]
    requests: DynamicHistogram,
}

static HTTP_METRICS: LazyLock<HttpMetrics> = LazyLock::new(|| HttpMetrics {
    requests: DynamicHistogram::with_limits(LATENCY_BOUNDS_NANOS, 16, MAX_REQUEST_SERIES),
});

static OPEN_EVENT_STREAMS: AtomicI64 = AtomicI64::new(0);

const EVENT_STREAMS_OPEN: MetricMeta<'static> = MetricMeta {
    name: "http_event_streams_open",
    help: "Server-sent event streams open",
    kind: MetricKind::Gauge,
    unit: None,
};

/// Counts an event stream as open until it is dropped, however the client goes away.
pub(crate) struct OpenEventStream;

impl OpenEventStream {
    pub(crate) fn start() -> Self {
        OPEN_EVENT_STREAMS.fetch_add(1, Ordering::Relaxed);
        Self
    }
}

impl Drop for OpenEventStream {
    fn drop(&mut self) {
        OPEN_EVENT_STREAMS.fetch_sub(1, Ordering::Relaxed);
    }
}

fn method_label(method: &Method) -> &'static str {
    match *method {
        Method::GET => "GET",
        Method::POST => "POST",
        Method::PUT => "PUT",
        Method::DELETE => "DELETE",
        Method::PATCH => "PATCH",
        Method::HEAD => "HEAD",
        Method::OPTIONS => "OPTIONS",
        _ => "other",
    }
}

fn status_label(status: StatusCode) -> &'static str {
    match status.as_u16() {
        ..=199 => "1xx",
        200..=299 => "2xx",
        300..=399 => "3xx",
        400..=499 => "4xx",
        _ => "5xx",
    }
}

/// Route middleware: time each request and label it with its route template, so `/v1/verbs/#1/look`
/// counts as `/v1/verbs/{object}/{name}`.
pub(crate) async fn track_request(request: Request, next: Next) -> Response {
    // Only matched routes reach this layer; `unmatched` counts the rest.
    let route = request
        .extensions()
        .get::<MatchedPath>()
        .map(|path| path.as_str().to_owned())
        .unwrap_or_else(|| "unmatched".to_owned());
    let method = method_label(request.method());
    let started = Instant::now();
    let response = next.run(request).await;
    record_request(&route, method, response.status(), started);
    response
}

/// Fallback for paths that match no route: the usual 404, counted as `route="unmatched"`.
pub(crate) async fn unmatched(method: Method) -> StatusCode {
    let status = StatusCode::NOT_FOUND;
    record_request("unmatched", method_label(&method), status, Instant::now());
    status
}

fn record_request(route: &str, method: &str, status: StatusCode, started: Instant) {
    let elapsed = started.elapsed().as_nanos().min(u64::MAX as u128) as u64;
    HTTP_METRICS.requests.record(
        &[
            ("route", route),
            ("method", method),
            ("status", status_label(status)),
        ],
        elapsed,
    );
}

pub fn visit_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    HTTP_METRICS.visit_metrics(visitor);
    visitor.gauge_i64(
        EVENT_STREAMS_OPEN,
        MetricLabels::none(),
        OPEN_EVENT_STREAMS.load(Ordering::Relaxed),
    );
    visit_rpc_client_metrics(visitor);
}

/// The host's metrics in the Prometheus text format, with `service="web-host"`.
pub fn render() -> String {
    render_service_metrics("web-host", visit_metrics)
}

async fn metrics_handler() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        render(),
    )
}

/// Bind `address` and serve `GET /metrics` on it in the background.
pub(crate) async fn serve_metrics(address: &str) -> Result<()> {
    let address: SocketAddr = address
        .parse()
        .map_err(|e| eyre!("Unable to parse metrics listen address {address}: {e}"))?;
    let listener = TcpListener::bind(address)
        .await
        .map_err(|e| eyre!("Unable to bind metrics listener on {address}: {e}"))?;
    info!(%address, "Serving metrics at /metrics");
    let router = Router::new().route("/metrics", get(metrics_handler));
    tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, router).await {
            error!(error = %e, "Metrics listener failed");
        }
    });
    Ok(())
}
