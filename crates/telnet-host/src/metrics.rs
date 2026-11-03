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

//! The telnet host's metrics, served from its health check port at `GET /metrics`.

use std::sync::{
    LazyLock,
    atomic::{AtomicI64, Ordering},
};

use fast_telemetry::{
    Counter, DeriveLabel, ExportMetrics, LabeledCounter, MetricKind, MetricLabels, MetricMeta,
    MetricVisitor,
};
use moor_common::util::render_service_metrics;
use moor_zmq_client::metrics::visit_rpc_client_metrics;

#[derive(Clone, Copy, Debug, DeriveLabel)]
#[label_name = "transport"]
pub(crate) enum Transport {
    Plain,
    Tls,
}

#[derive(ExportMetrics)]
#[metric_prefix = "telnet"]
pub(crate) struct TelnetMetrics {
    #[help = "Telnet connections accepted"]
    pub(crate) connections: LabeledCounter<Transport>,
    #[help = "Telnet connections that ended with an error"]
    pub(crate) connection_errors: Counter,
    #[help = "Lines received from telnet clients"]
    pub(crate) lines_received: Counter,
    #[help = "Lines sent to telnet clients"]
    pub(crate) lines_sent: Counter,
    #[help = "Writes abandoned because the client stopped reading"]
    pub(crate) output_timeouts: Counter,
}

pub(crate) static TELNET_METRICS: LazyLock<TelnetMetrics> = LazyLock::new(|| TelnetMetrics {
    connections: LabeledCounter::new(8),
    connection_errors: Counter::new(8),
    lines_received: Counter::new(8),
    lines_sent: Counter::new(8),
    output_timeouts: Counter::new(8),
});

static OPEN_CONNECTIONS: AtomicI64 = AtomicI64::new(0);

const OPEN: MetricMeta<'static> = MetricMeta {
    name: "telnet_connections_open",
    help: "Telnet connections open",
    kind: MetricKind::Gauge,
    unit: None,
};

/// Counts a connection as open until it is dropped, however the connection ends.
pub(crate) struct OpenConnection;

impl OpenConnection {
    pub(crate) fn start(transport: Transport) -> Self {
        TELNET_METRICS.connections.inc(transport);
        OPEN_CONNECTIONS.fetch_add(1, Ordering::Relaxed);
        Self
    }
}

impl Drop for OpenConnection {
    fn drop(&mut self) {
        OPEN_CONNECTIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

pub fn visit_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    TELNET_METRICS.visit_metrics(visitor);
    visitor.gauge_i64(
        OPEN,
        MetricLabels::none(),
        OPEN_CONNECTIONS.load(Ordering::Relaxed),
    );
    visit_rpc_client_metrics(visitor);
}

/// The host's metrics in the Prometheus text format, with `service="telnet-host"`.
pub fn render() -> String {
    render_service_metrics("telnet-host", visit_metrics)
}
