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

//! Renders a [`MetricsSnapshot`] in the Prometheus text exposition format (version 0.0.4).

use crate::util::metrics_snapshot::{MetricFamilyKind, MetricSample, MetricValue, MetricsSnapshot};
use std::fmt::Write;

/// Render `snapshot`, prefixing every metric name with `namespace` and an underscore.
pub fn render_prometheus_text(snapshot: &MetricsSnapshot, namespace: &str) -> String {
    let mut output = String::new();
    for family in &snapshot.families {
        let name = format!("{namespace}_{}", family.name);
        let kind = match family.kind {
            MetricFamilyKind::Counter => "counter",
            MetricFamilyKind::Gauge => "gauge",
            MetricFamilyKind::Histogram => "histogram",
        };
        let _ = writeln!(output, "# HELP {name} {}", escape_help(&family.help));
        let _ = writeln!(output, "# TYPE {name} {kind}");
        for sample in &family.samples {
            write_sample(&mut output, &name, sample);
        }
    }
    output
}

fn write_sample(output: &mut String, name: &str, sample: &MetricSample) {
    match &sample.value {
        MetricValue::Int(value) => write_series(output, name, "", sample, None, &value.to_string()),
        MetricValue::Float(value) => {
            write_series(output, name, "", sample, None, &format_f64(*value))
        }
        MetricValue::Histogram(histogram) => {
            for (upper_bound, cumulative_count) in &histogram.buckets {
                let le = if *upper_bound == u64::MAX {
                    "+Inf".to_string()
                } else {
                    upper_bound.to_string()
                };
                write_series(
                    output,
                    name,
                    "_bucket",
                    sample,
                    Some(&le),
                    &cumulative_count.to_string(),
                );
            }
            write_series(
                output,
                name,
                "_sum",
                sample,
                None,
                &histogram.sum.to_string(),
            );
            write_series(
                output,
                name,
                "_count",
                sample,
                None,
                &histogram.count.to_string(),
            );
        }
    }
}

fn write_series(
    output: &mut String,
    name: &str,
    suffix: &str,
    sample: &MetricSample,
    le: Option<&str>,
    value: &str,
) {
    output.push_str(name);
    output.push_str(suffix);
    let labels = sample
        .labels
        .iter()
        .map(|(name, value)| (name.as_str(), value.as_str()))
        .chain(le.map(|le| ("le", le)));
    let mut first = true;
    for (label_name, label_value) in labels {
        output.push(if first { '{' } else { ',' });
        first = false;
        output.push_str(label_name);
        output.push_str("=\"");
        escape_label_value(output, label_value);
        output.push('"');
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
        MetricKind, MetricLabel, MetricLabels, MetricMeta, MetricVisitor,
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
    fn renders_families_contiguously() {
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

        let snapshot = MetricsSnapshot::collect(|builder| metrics.visit_metrics(builder));
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
        assert_eq!(render_prometheus_text(&snapshot, "moor"), expected);
    }

    #[test]
    fn escapes_label_values_and_help() {
        let snapshot = MetricsSnapshot::collect(|builder| {
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
            builder.gauge_f64(meta, MetricLabels::one(label), f64::NAN);
            let meta = MetricMeta {
                name: "empty",
                help: "Empty",
                kind: MetricKind::Histogram,
                unit: None,
            };
            builder.histogram(meta, MetricLabels::none(), &Histogram::new(&[10], 1));
        });

        assert_eq!(
            render_prometheus_text(&snapshot, "moor"),
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
