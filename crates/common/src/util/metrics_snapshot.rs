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

//! An owned copy of a metrics walk, so it can be sent elsewhere, rendered, or replayed into any
//! other [`MetricVisitor`].

use fast_telemetry::{
    DistributionSnapshot, HistogramSnapshot, MetricKind, MetricLabel, MetricLabels, MetricMeta,
    MetricVisitor,
};
use std::collections::HashMap;

/// What kind of series a family holds, following the Prometheus data model.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum MetricFamilyKind {
    Counter,
    Gauge,
    Histogram,
}

#[derive(Clone, Debug, PartialEq)]
pub struct HistogramValue {
    pub count: u64,
    pub sum: u64,
    /// `(upper_bound, cumulative_count)` in increasing order. `u64::MAX` is the `+Inf` bucket.
    pub buckets: Vec<(u64, u64)>,
}

#[derive(Clone, Debug, PartialEq)]
pub enum MetricValue {
    Int(i64),
    Float(f64),
    Histogram(HistogramValue),
}

/// One labelled series.
#[derive(Clone, Debug, PartialEq)]
pub struct MetricSample {
    pub labels: Vec<(String, String)>,
    pub value: MetricValue,
}

/// One metric name, with all its series.
#[derive(Clone, Debug, PartialEq)]
pub struct MetricFamily {
    pub name: String,
    pub help: String,
    pub unit: Option<String>,
    pub kind: MetricFamilyKind,
    pub samples: Vec<MetricSample>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct MetricsSnapshot {
    pub families: Vec<MetricFamily>,
}

impl MetricsSnapshot {
    /// Record everything `visit` reports. Sources may visit families interleaved (a sampled timer
    /// visits its call counter and histogram for each label in turn), so samples are grouped by
    /// family, and families kept in the order each was first seen.
    pub fn collect(visit: impl FnOnce(&mut MetricsSnapshotBuilder)) -> Self {
        let mut builder = MetricsSnapshotBuilder::default();
        visit(&mut builder);
        builder.snapshot
    }

    /// Replay every sample into `visitor`, as the original sources would have.
    pub fn visit_metrics<V: MetricVisitor + ?Sized>(&self, visitor: &mut V) {
        for family in &self.families {
            family.visit_metrics(visitor);
        }
    }
}

impl MetricFamily {
    pub fn visit_metrics<V: MetricVisitor + ?Sized>(&self, visitor: &mut V) {
        let meta = MetricMeta {
            name: &self.name,
            help: &self.help,
            kind: match self.kind {
                MetricFamilyKind::Counter => MetricKind::Counter,
                MetricFamilyKind::Gauge => MetricKind::Gauge,
                MetricFamilyKind::Histogram => MetricKind::Histogram,
            },
            unit: self.unit.as_deref(),
        };
        for sample in &self.samples {
            let labels: Vec<MetricLabel<'_>> = sample
                .labels
                .iter()
                .map(|(name, value)| MetricLabel { name, value })
                .collect();
            let labels = MetricLabels::slice(&labels);
            match (&sample.value, self.kind) {
                (MetricValue::Int(value), MetricFamilyKind::Counter) => {
                    visitor.counter(meta, labels, *value)
                }
                (MetricValue::Int(value), _) => visitor.gauge_i64(meta, labels, *value),
                (MetricValue::Float(value), _) => visitor.gauge_f64(meta, labels, *value),
                (MetricValue::Histogram(histogram), _) => {
                    visitor.histogram(meta, labels, histogram)
                }
            }
        }
    }
}

impl HistogramSnapshot for HistogramValue {
    fn count(&self) -> u64 {
        self.count
    }

    fn sum(&self) -> u64 {
        self.sum
    }

    fn visit_buckets(&self, visitor: &mut dyn FnMut(u64, u64)) {
        for (upper_bound, cumulative_count) in &self.buckets {
            visitor(*upper_bound, *cumulative_count);
        }
    }
}

/// Collects a [`MetricsSnapshot`]; see [`MetricsSnapshot::collect`].
#[derive(Default)]
pub struct MetricsSnapshotBuilder {
    snapshot: MetricsSnapshot,
    index: HashMap<String, usize>,
}

impl MetricsSnapshotBuilder {
    fn push(
        &mut self,
        meta: MetricMeta<'_>,
        kind: MetricFamilyKind,
        labels: MetricLabels<'_>,
        value: MetricValue,
    ) {
        let families = &mut self.snapshot.families;
        let index = *self.index.entry(meta.name.to_string()).or_insert_with(|| {
            families.push(MetricFamily {
                name: meta.name.to_string(),
                help: meta.help.to_string(),
                unit: meta.unit.map(str::to_string),
                kind,
                samples: Vec::new(),
            });
            families.len() - 1
        });
        families[index].samples.push(MetricSample {
            labels: labels
                .iter()
                .map(|label| (label.name.to_string(), label.value.to_string()))
                .collect(),
            value,
        });
    }
}

impl MetricVisitor for MetricsSnapshotBuilder {
    fn counter(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        self.push(
            meta,
            MetricFamilyKind::Counter,
            labels,
            MetricValue::Int(value),
        );
    }

    fn gauge_i64(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        self.push(
            meta,
            MetricFamilyKind::Gauge,
            labels,
            MetricValue::Int(value),
        );
    }

    fn gauge_f64(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: f64) {
        self.push(
            meta,
            MetricFamilyKind::Gauge,
            labels,
            MetricValue::Float(value),
        );
    }

    fn histogram(
        &mut self,
        meta: MetricMeta<'_>,
        labels: MetricLabels<'_>,
        histogram: &dyn HistogramSnapshot,
    ) {
        let mut buckets = Vec::new();
        histogram.visit_buckets(&mut |upper_bound, cumulative_count| {
            buckets.push((upper_bound, cumulative_count));
        });
        let value = MetricValue::Histogram(HistogramValue {
            count: histogram.count(),
            sum: histogram.sum(),
            buckets,
        });
        self.push(meta, MetricFamilyKind::Histogram, labels, value);
    }

    /// No mooR metric is a distribution, and the Prometheus model has no equivalent, so these are
    /// skipped.
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
    use crate::util::MetricEntriesVisitor;
    use fast_telemetry::{DeriveLabel, ExportMetrics, LabeledCounter, LabeledSampledTimer};
    use moor_var::Symbol;

    #[derive(Copy, Clone, Debug, DeriveLabel)]
    #[label_name = "op"]
    enum TestOp {
        Read,
        Write,
    }

    #[derive(ExportMetrics)]
    #[metric_prefix = "test"]
    struct TestMetrics {
        #[help = "Operation latency"]
        timers: LabeledSampledTimer<TestOp>,
        #[help = "Operations"]
        ops: LabeledCounter<TestOp>,
    }

    fn sorted_entries(
        visit: impl FnOnce(&mut MetricEntriesVisitor),
    ) -> Vec<(Symbol, isize, isize)> {
        let mut visitor = MetricEntriesVisitor::new();
        visit(&mut visitor);
        let mut entries = visitor.into_entries();
        entries.sort_by_key(|(name, _, _)| name.as_string());
        entries
    }

    #[test]
    fn groups_interleaved_series_by_family() {
        let metrics = TestMetrics {
            timers: LabeledSampledTimer::new(&[100], 1, 1),
            ops: LabeledCounter::new(1),
        };
        metrics
            .timers
            .record_elapsed(TestOp::Write, std::time::Duration::from_nanos(50));

        let snapshot = MetricsSnapshot::collect(|builder| metrics.visit_metrics(builder));
        let names: Vec<_> = snapshot.families.iter().map(|f| f.name.as_str()).collect();
        assert_eq!(
            names,
            ["test_timers_calls", "test_timers_samples", "test_ops"]
        );
        let samples = &snapshot.families[1].samples;
        assert_eq!(samples.len(), 2);
        assert_eq!(samples[1].labels, [("op".to_string(), "write".to_string())]);
        assert_eq!(
            samples[1].value,
            MetricValue::Histogram(HistogramValue {
                count: 1,
                sum: 50,
                buckets: vec![(100, 1), (u64::MAX, 1)],
            })
        );
    }

    #[test]
    fn replays_as_the_original_sources() {
        let metrics = TestMetrics {
            timers: LabeledSampledTimer::new(&[100], 1, 2),
            ops: LabeledCounter::new(1),
        };
        for _ in 0..4 {
            metrics
                .timers
                .record_elapsed(TestOp::Read, std::time::Duration::from_nanos(30));
        }
        metrics.ops.add(TestOp::Write, 5);

        let snapshot = MetricsSnapshot::collect(|builder| metrics.visit_metrics(builder));
        assert_eq!(
            sorted_entries(|visitor| snapshot.visit_metrics(visitor)),
            sorted_entries(|visitor| metrics.visit_metrics(visitor)),
        );
    }
}
