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

//! Every metric the daemon exports, for the metrics file and the `RequestMetrics` RPC.

use std::sync::LazyLock;

use fast_telemetry::{ExportMetrics, Gauge, MetricVisitor};
use moor_kernel::perf_counters::visit_all_metrics;

use crate::rpc::transport::rpc_metrics;

/// Connection and host counts, refreshed by the ping loop every few seconds.
#[derive(ExportMetrics)]
#[metric_prefix = "daemon"]
pub(crate) struct SessionMetrics {
    #[help = "Players connected"]
    pub(crate) connected_players: Gauge,
    #[help = "Connections open, logged in or not"]
    pub(crate) connections: Gauge,
    #[help = "Hosts registered with the daemon"]
    pub(crate) hosts: Gauge,
}

pub(crate) static SESSION_METRICS: LazyLock<SessionMetrics> = LazyLock::new(|| SessionMetrics {
    connected_players: Gauge::new(),
    connections: Gauge::new(),
    hosts: Gauge::new(),
});

/// Visit the runtime's metrics and the daemon's own.
pub(crate) fn visit_daemon_metrics<V: MetricVisitor + ?Sized>(visitor: &mut V) {
    visit_all_metrics(visitor);
    rpc_metrics().visit_metrics(visitor);
    crate::rpc::visit_call_pool_metrics(visitor);
    SESSION_METRICS.visit_metrics(visitor);
}
