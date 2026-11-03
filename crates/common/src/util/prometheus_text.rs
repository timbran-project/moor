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

//! Renders metrics in the Prometheus text exposition format (version 0.0.4) from a
//! [`MetricVisitor`] walk, so every metric source can be written the same way.

use fast_telemetry::{
    DistributionSnapshot, HistogramSnapshot, MetricKind, MetricLabels, MetricMeta, MetricVisitor,
};
use std::{collections::HashMap, fmt::Write};

struct Family {
    name: String,
    help: String,
    kind: &'static str,
    samples: String,
}

/// Collects observations into metric families and renders them as Prometheus text.
///
/// Prometheus requires all samples of a family to be contiguous, but sources may visit families
/// interleaved (a sampled timer visits its call counter and histogram for each label in turn), so
/// samples are grouped by family and written in the order each family was first seen. Every
/// metric name gets `namespace` and an underscore as a prefix.
pub struct PrometheusTextWriter {
    namespace: String,
    families: Vec<Family>,
    index: HashMap<String, usize>,
}

impl PrometheusTextWriter {
    pub fn new(namespace: &str) -> Self {
        Self {
            namespace: namespace.to_string(),
            families: Vec::new(),
            index: HashMap::new(),
        }
    }

    /// Render the collected families.
    pub fn finish(self) -> String {
        let mut output = String::new();
        for family in self.families {
            let _ = writeln!(
                output,
                "# HELP {} {}",
                family.name,
                escape_help(&family.help)
            );
            let _ = writeln!(output, "# TYPE {} {}", family.name, family.kind);
            output.push_str(&family.samples);
        }
        output
    }

    fn family(&mut self, meta: MetricMeta<'_>, kind: &'static str) -> &mut Family {
        let name = format!("{}_{}", self.namespace, meta.name);
        let index = match self.index.get(&name) {
            Some(index) => *index,
            None => {
                self.families.push(Family {
                    name: name.clone(),
                    help: meta.help.to_string(),
                    kind,
                    samples: String::new(),
                });
                self.index.insert(name, self.families.len() - 1);
                self.families.len() - 1
            }
        };
        &mut self.families[index]
    }

    fn write_sample(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: &str) {
        let kind = match meta.kind {
            MetricKind::Counter => "counter",
            MetricKind::Gauge => "gauge",
            _ => "untyped",
        };
        let family = self.family(meta, kind);
        let name = family.name.clone();
        write_series(&mut family.samples, &name, "", labels, None, value);
    }
}

impl MetricVisitor for PrometheusTextWriter {
    fn counter(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        self.write_sample(meta, labels, &value.to_string());
    }

    fn gauge_i64(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        self.write_sample(meta, labels, &value.to_string());
    }

    fn gauge_f64(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: f64) {
        self.write_sample(meta, labels, &format_f64(value));
    }

    fn histogram(
        &mut self,
        meta: MetricMeta<'_>,
        labels: MetricLabels<'_>,
        histogram: &dyn HistogramSnapshot,
    ) {
        let family = self.family(meta, "histogram");
        let name = family.name.clone();
        let samples = &mut family.samples;
        histogram.visit_buckets(&mut |upper_bound, cumulative_count| {
            let le = if upper_bound == u64::MAX {
                "+Inf".to_string()
            } else {
                upper_bound.to_string()
            };
            write_series(
                samples,
                &name,
                "_bucket",
                labels,
                Some(&le),
                &cumulative_count.to_string(),
            );
        });
        write_series(
            samples,
            &name,
            "_sum",
            labels,
            None,
            &histogram.sum().to_string(),
        );
        write_series(
            samples,
            &name,
            "_count",
            labels,
            None,
            &histogram.count().to_string(),
        );
    }

    /// No mooR metric is a distribution, and the text format has no equivalent, so these are
    /// skipped.
    fn distribution(
        &mut self,
        _meta: MetricMeta<'_>,
        _labels: MetricLabels<'_>,
        _distribution: &dyn DistributionSnapshot,
    ) {
    }
}

fn write_series(
    output: &mut String,
    name: &str,
    suffix: &str,
    labels: MetricLabels<'_>,
    le: Option<&str>,
    value: &str,
) {
    output.push_str(name);
    output.push_str(suffix);
    let mut first = true;
    let mut push_label = |output: &mut String, label_name: &str, label_value: &str| {
        output.push(if first { '{' } else { ',' });
        first = false;
        output.push_str(label_name);
        output.push_str("=\"");
        escape_label_value(output, label_value);
        output.push('"');
    };
    for label in labels.iter() {
        push_label(output, label.name, label.value);
    }
    if let Some(le) = le {
        push_label(output, "le", le);
    }
    if !first {
        output.push('}');
    }
    output.push(' ');
    output.push_str(value);
    output.push('\n');
}

fn escape_label_value(output: &mut String, value: &str) {
    for c in value.chars() {
        match c {
            '\\' => output.push_str("\\\\"),
            '"' => output.push_str("\\\""),
            '\n' => output.push_str("\\n"),
            c => output.push(c),
        }
    }
}

fn escape_help(help: &str) -> String {
    help.replace('\\', "\\\\").replace('\n', "\\n")
}

fn format_f64(value: f64) -> String {
    if value.is_nan() {
        "NaN".to_string()
    } else if value == f64::INFINITY {
        "+Inf".to_string()
    } else if value == f64::NEG_INFINITY {
        "-Inf".to_string()
    } else {
        value.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fast_telemetry::{
        DeriveLabel, ExportMetrics, Gauge, Histogram, LabeledCounter, LabeledSampledTimer,
        MetricLabel,
    };

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
        #[help = "Queue depth"]
        depth: Gauge,
    }

    #[test]
    fn groups_interleaved_families() {
        let metrics = TestMetrics {
            timers: LabeledSampledTimer::new(&[100, 1000], 1, 1),
            ops: LabeledCounter::new(1),
            depth: Gauge::new(),
        };
        metrics
            .timers
            .record_elapsed(TestOp::Read, std::time::Duration::from_nanos(50));
        metrics
            .timers
            .record_elapsed(TestOp::Write, std::time::Duration::from_nanos(500));
        metrics.ops.add(TestOp::Write, 3);
        metrics.depth.set(-2);

        let mut writer = PrometheusTextWriter::new("moor");
        metrics.visit_metrics(&mut writer);
        let text = writer.finish();

        let expected = "\
# HELP moor_test_timers_calls Operation latency total calls
# TYPE moor_test_timers_calls counter
moor_test_timers_calls{op=\"read\"} 1
moor_test_timers_calls{op=\"write\"} 1
# HELP moor_test_timers_samples Operation latency sampled latency in nanoseconds
# TYPE moor_test_timers_samples histogram
moor_test_timers_samples_bucket{op=\"read\",le=\"100\"} 1
moor_test_timers_samples_bucket{op=\"read\",le=\"1000\"} 1
moor_test_timers_samples_bucket{op=\"read\",le=\"+Inf\"} 1
moor_test_timers_samples_sum{op=\"read\"} 50
moor_test_timers_samples_count{op=\"read\"} 1
moor_test_timers_samples_bucket{op=\"write\",le=\"100\"} 0
moor_test_timers_samples_bucket{op=\"write\",le=\"1000\"} 1
moor_test_timers_samples_bucket{op=\"write\",le=\"+Inf\"} 1
moor_test_timers_samples_sum{op=\"write\"} 500
moor_test_timers_samples_count{op=\"write\"} 1
# HELP moor_test_ops Operations
# TYPE moor_test_ops counter
moor_test_ops{op=\"read\"} 0
moor_test_ops{op=\"write\"} 3
# HELP moor_test_depth Queue depth
# TYPE moor_test_depth gauge
moor_test_depth -2
";
        assert_eq!(text, expected);
    }

    #[test]
    fn escapes_label_values_and_help() {
        let mut writer = PrometheusTextWriter::new("moor");
        let meta = MetricMeta {
            name: "odd",
            help: "line one\nback\\slash",
            kind: MetricKind::Gauge,
            unit: None,
        };
        let label = MetricLabel {
            name: "name",
            value: "a\"b\\c\nd",
        };
        writer.gauge_f64(meta, MetricLabels::one(label), f64::NAN);
        let histogram = Histogram::new(&[10], 1);
        let meta = MetricMeta {
            name: "empty",
            help: "Empty",
            kind: MetricKind::Histogram,
            unit: None,
        };
        writer.histogram(meta, MetricLabels::none(), &histogram);

        assert_eq!(
            writer.finish(),
            "# HELP moor_odd line one\\nback\\\\slash\n\
             # TYPE moor_odd gauge\n\
             moor_odd{name=\"a\\\"b\\\\c\\nd\"} NaN\n\
             # HELP moor_empty Empty\n\
             # TYPE moor_empty histogram\n\
             moor_empty_bucket{le=\"10\"} 0\n\
             moor_empty_bucket{le=\"+Inf\"} 0\n\
             moor_empty_sum 0\n\
             moor_empty_count 0\n"
        );
    }
}
