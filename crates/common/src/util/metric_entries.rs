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

//! Flattens perf metrics into `(name, count, nanos)` entries keyed by their `op` label.

use fast_telemetry::{
    DistributionSnapshot, HistogramSnapshot, MetricLabels, MetricMeta, MetricVisitor,
};
use moor_var::Symbol;
use std::collections::HashMap;

use crate::util::scale_sample_sum;

pub type MetricEntry = (Symbol, isize, isize);

/// Suffixes that `fast-telemetry` gives the two halves of a sampled timer: an exact call counter
/// and a histogram of the sampled latencies.
const CALLS_SUFFIX: &str = "_calls";
const SAMPLES_SUFFIX: &str = "_samples";

fn u64_to_isize(value: u64) -> isize {
    value.min(isize::MAX as u64) as isize
}

fn i64_to_isize(value: i64) -> isize {
    value.clamp(isize::MIN as i64, isize::MAX as i64) as isize
}

fn entry_name(meta: MetricMeta<'_>, labels: MetricLabels<'_>) -> Symbol {
    if let Some(label) = labels.iter().find(|label| label.name == "op") {
        return Symbol::from(label.value);
    }

    Symbol::from(meta.name)
}

#[derive(Default)]
struct TimerSeries {
    calls: Option<u64>,
    sample_count: u64,
    sample_sum: u64,
}

impl TimerSeries {
    /// Total nanoseconds, estimated from the share of calls that were sampled. Using the counts
    /// the timer recorded means the estimate does not depend on the stride it was built with.
    fn estimated_total_nanos(&self) -> u64 {
        match self.calls {
            Some(calls) => scale_sample_sum(calls, self.sample_count, self.sample_sum),
            // A histogram without a call counter records every value.
            None => self.sample_sum,
        }
    }
}

/// Collects counters as entry counts and histograms as entry nanoseconds. Sampled timers are
/// matched to their call counters by name, and their sampled sums are scaled up to totals.
/// Gauges and distributions are not part of the entry format and are skipped.
#[derive(Default)]
pub struct MetricEntriesVisitor {
    counts: HashMap<Symbol, isize>,
    /// Keyed by metric name without its timer suffix, and entry name.
    timers: HashMap<(String, Symbol), TimerSeries>,
}

impl MetricEntriesVisitor {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn into_entries(self) -> Vec<MetricEntry> {
        let mut entries: HashMap<Symbol, (isize, isize)> = self
            .counts
            .into_iter()
            .map(|(name, count)| (name, (count, 0)))
            .collect();
        for ((_, name), series) in self.timers {
            let entry = entries.entry(name).or_insert((0, 0));
            entry.1 = entry
                .1
                .saturating_add(u64_to_isize(series.estimated_total_nanos()));
        }
        entries
            .into_iter()
            .map(|(name, (count, nanos))| (name, count, nanos))
            .collect()
    }

    fn timer_series(
        &mut self,
        series_name: &str,
        meta: MetricMeta<'_>,
        labels: MetricLabels<'_>,
    ) -> &mut TimerSeries {
        self.timers
            .entry((series_name.to_string(), entry_name(meta, labels)))
            .or_default()
    }
}

impl MetricVisitor for MetricEntriesVisitor {
    fn counter(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        let count = self.counts.entry(entry_name(meta, labels)).or_insert(0);
        *count = count.saturating_add(i64_to_isize(value));

        if let Some(series_name) = meta.name.strip_suffix(CALLS_SUFFIX) {
            let series = self.timer_series(series_name, meta, labels);
            series.calls = Some(
                series
                    .calls
                    .unwrap_or(0)
                    .saturating_add(value.max(0) as u64),
            );
        }
    }

    fn gauge_i64(&mut self, _meta: MetricMeta<'_>, _labels: MetricLabels<'_>, _value: i64) {}

    fn gauge_f64(&mut self, _meta: MetricMeta<'_>, _labels: MetricLabels<'_>, _value: f64) {}

    fn histogram(
        &mut self,
        meta: MetricMeta<'_>,
        labels: MetricLabels<'_>,
        histogram: &dyn HistogramSnapshot,
    ) {
        let series_name = meta.name.strip_suffix(SAMPLES_SUFFIX).unwrap_or(meta.name);
        let series = self.timer_series(series_name, meta, labels);
        series.sample_count = series.sample_count.saturating_add(histogram.count());
        series.sample_sum = series.sample_sum.saturating_add(histogram.sum());
    }

    fn distribution(
        &mut self,
        _meta: MetricMeta<'_>,
        _labels: MetricLabels<'_>,
        _distribution: &dyn DistributionSnapshot,
    ) {
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fast_telemetry::{DeriveLabel, ExportMetrics, LabeledCounter, LabeledSampledTimer};

    #[derive(Copy, Clone, Debug, DeriveLabel)]
    #[label_name = "op"]
    enum TestOp {
        Fast,
        Slow,
    }

    #[derive(ExportMetrics)]
    #[metric_prefix = "test"]
    struct TestMetrics {
        #[help = "Sampled one call in four"]
        sampled: LabeledSampledTimer<TestOp>,
        #[help = "Sampled every call"]
        exact: LabeledSampledTimer<TestOp>,
        #[help = "Plain counters"]
        counters: LabeledCounter<TestOp>,
    }

    fn entries(metrics: &TestMetrics) -> HashMap<Symbol, (isize, isize)> {
        let mut visitor = MetricEntriesVisitor::new();
        metrics.visit_metrics(&mut visitor);
        visitor
            .into_entries()
            .into_iter()
            .map(|(name, count, nanos)| (name, (count, nanos)))
            .collect()
    }

    #[test]
    fn scales_each_timer_by_its_own_sampling() {
        let metrics = TestMetrics {
            sampled: LabeledSampledTimer::with_latency_buckets(1, 4),
            exact: LabeledSampledTimer::with_latency_buckets(1, 1),
            counters: LabeledCounter::new(1),
        };
        for _ in 0..8 {
            metrics
                .sampled
                .record_elapsed(TestOp::Fast, std::time::Duration::from_nanos(100));
        }
        for _ in 0..3 {
            metrics
                .exact
                .record_elapsed(TestOp::Slow, std::time::Duration::from_nanos(1000));
        }
        metrics.counters.add(TestOp::Slow, 2);

        let entries = entries(&metrics);
        assert_eq!(metrics.sampled.sample_count(TestOp::Fast), 2);
        assert_eq!(entries[&Symbol::mk("fast")], (8, 800));
        assert_eq!(entries[&Symbol::mk("slow")], (5, 3000));
    }

    #[test]
    fn unsampled_calls_report_no_time() {
        let metrics = TestMetrics {
            sampled: LabeledSampledTimer::with_latency_buckets(1, 1 << 30),
            exact: LabeledSampledTimer::with_latency_buckets(1, 1),
            counters: LabeledCounter::new(1),
        };
        metrics
            .sampled
            .record_elapsed(TestOp::Fast, std::time::Duration::from_nanos(100));

        let entries = entries(&metrics);
        assert_eq!(entries[&Symbol::mk("fast")], (1, 0));
    }
}
