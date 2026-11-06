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

//! The daemon's own metrics, as its exporter sends them through `moor:metric`, and queries over
//! their recent history.
//!
//! The exporter leaves out counters at zero and empty histograms, so a series missing from a set
//! counts as zero.

use std::collections::{BTreeMap, HashMap, VecDeque};

use serde::{Deserialize, Serialize};

const KIND_HISTOGRAM: u64 = 2;

const PART_INT: u64 = 0;
const PART_FLOAT: u64 = 1;
const PART_COUNT: u64 = 2;
const PART_SUM: u64 = 3;
const PART_BUCKET: u64 = 4;

/// One value from `moor:metric`.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct MetricValue {
    pub name: String,
    pub labels: String,
    pub kind: u64,
    pub part: u64,
    pub value: u64,
    pub bound: u64,
}

/// Every value the exporter sent in one pass.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct MetricSet {
    /// Seconds since the capture started, when the set arrived.
    pub at: f64,
    pub values: Vec<MetricValue>,
}

#[derive(Clone, Debug, Default)]
struct Series {
    kind: u64,
    labels: Vec<(String, String)>,
    /// A counter's or gauge's value.
    number: f64,
    count: f64,
    sum: f64,
    /// Cumulative counts by upper bound, in increasing order.
    buckets: Vec<(u64, f64)>,
}

impl Series {
    /// A counter's or gauge's value, or a histogram's count.
    fn total(&self) -> f64 {
        if self.kind == KIND_HISTOGRAM {
            self.count
        } else {
            self.number
        }
    }

    fn label(&self, key: &str) -> &str {
        self.labels
            .iter()
            .find(|(k, _)| k == key)
            .map_or("", |(_, v)| v.as_str())
    }
}

/// One metric set, parsed. Series are keyed by name, then by their label text.
#[derive(Clone, Debug, Default)]
pub struct Point {
    pub at: f64,
    series: HashMap<String, BTreeMap<String, Series>>,
}

impl Point {
    fn parse(set: &MetricSet) -> Self {
        let mut series: HashMap<String, BTreeMap<String, Series>> = HashMap::new();
        for v in &set.values {
            let s = series
                .entry(v.name.clone())
                .or_default()
                .entry(v.labels.clone())
                .or_insert_with(|| Series {
                    kind: v.kind,
                    labels: parse_labels(&v.labels),
                    ..Series::default()
                });
            match v.part {
                PART_INT => s.number = v.value as i64 as f64,
                PART_FLOAT => s.number = f64::from_bits(v.value),
                PART_COUNT => s.count = v.value as f64,
                PART_SUM => s.sum = v.value as f64,
                PART_BUCKET => s.buckets.push((v.bound, v.value as f64)),
                _ => {}
            }
        }
        Self { at: set.at, series }
    }

    fn matching<'p, 'f>(
        &'p self,
        name: &str,
        filter: &'f Filter,
    ) -> impl Iterator<Item = (&'p String, &'p Series)> + use<'p, 'f> {
        self.series
            .get(name)
            .into_iter()
            .flat_map(|m| m.iter())
            .filter(move |(_, s)| filter.matches(s))
    }

    fn get(&self, name: &str, labels: &str) -> Option<&Series> {
        self.series.get(name).and_then(|m| m.get(labels))
    }
}

fn parse_labels(text: &str) -> Vec<(String, String)> {
    text.split(',')
        .filter_map(|pair| pair.split_once('='))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Which series of a metric to include: each key must have one of its listed values.
#[derive(Clone, Default)]
pub struct Filter(Vec<(String, Vec<String>)>);

impl Filter {
    pub fn all() -> Self {
        Self::default()
    }

    /// `key` is one of `values`, written `a|b|c`.
    pub fn of(key: &str, values: &str) -> Self {
        Self(vec![(
            key.to_string(),
            values.split('|').map(str::to_string).collect(),
        )])
    }

    /// Also require `key` to be `value`.
    pub fn and(mut self, key: &str, value: &str) -> Self {
        self.0.push((key.to_string(), vec![value.to_string()]));
        self
    }

    fn matches(&self, s: &Series) -> bool {
        self.0
            .iter()
            .all(|(key, values)| values.iter().any(|v| v == s.label(key)))
    }
}

/// How far back a query looks.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Window {
    /// The last this many seconds.
    Recent(f64),
    /// Since the first set.
    All,
}

/// The first set seen, and the most recent ones.
#[derive(Default)]
pub struct History {
    first: Option<Point>,
    points: VecDeque<Point>,
}

/// Sets kept for charts: two minutes at one a second.
pub const KEPT: usize = 120;

impl History {
    pub fn push(&mut self, set: &MetricSet) {
        let point = Point::parse(set);
        if self.first.is_none() {
            self.first = Some(point.clone());
        }
        if self.points.len() == KEPT {
            self.points.pop_front();
        }
        self.points.push_back(point);
    }

    /// A query over `window`, ending at the latest set.
    pub fn query(&self, window: Window) -> Option<Query<'_>> {
        let to = self.points.back()?;
        let from = match window {
            Window::All => self.first.as_ref(),
            Window::Recent(seconds) => self
                .points
                .iter()
                .find(|p| to.at - p.at <= seconds + 0.5)
                .or(self.points.front()),
        };
        Some(Query {
            from: from.filter(|f| f.at < to.at),
            to,
        })
    }

    /// Successive one-interval queries, oldest first, for charts.
    pub fn steps(&self) -> impl Iterator<Item = Query<'_>> {
        self.points
            .iter()
            .zip(self.points.iter().skip(1))
            .map(|(from, to)| Query {
                from: Some(from),
                to,
            })
    }
}

/// Values at the end of a period, and changes over it.
#[derive(Clone, Copy)]
pub struct Query<'a> {
    from: Option<&'a Point>,
    to: &'a Point,
}

impl<'a> Query<'a> {
    fn seconds(&self) -> Option<f64> {
        self.from.map(|f| self.to.at - f.at).filter(|s| *s > 0.0)
    }

    pub fn has(&self, name: &str) -> bool {
        self.to.series.contains_key(name)
    }

    /// The sum of a gauge's matching series.
    pub fn gauge(&self, name: &str, filter: &Filter) -> f64 {
        // Folded from 0.0: an empty f64 sum is -0.0.
        self.to
            .matching(name, filter)
            .fold(0.0, |total, (_, s)| total + s.number)
    }

    /// A gauge's matching series, summed by the value of `key`.
    pub fn gauge_by(&self, name: &str, key: &str, filter: &Filter) -> Vec<(String, f64)> {
        let mut by: BTreeMap<String, f64> = BTreeMap::new();
        for (_, s) in self.to.matching(name, filter) {
            *by.entry(s.label(key).to_string()).or_default() += s.number;
        }
        by.into_iter().collect()
    }

    /// How much a counter, or a histogram's count, grew over the period, by series.
    fn deltas(&self, name: &str, filter: &Filter) -> Vec<(&'a Series, f64, Option<&'a Series>)> {
        let from = self.from;
        self.to
            .matching(name, filter)
            .map(|(labels, s)| {
                let before = from.and_then(|f| f.get(name, labels));
                let was = before.map_or(0.0, Series::total);
                (s, (s.total() - was).max(0.0), before)
            })
            .collect()
    }

    /// How much a counter grew over the period. Without a start, its whole value.
    pub fn increase(&self, name: &str, filter: &Filter) -> f64 {
        self.deltas(name, filter).iter().map(|(_, d, _)| d).sum()
    }

    /// `increase`, summed by the value of `key`, leaving out values that didn't grow.
    pub fn increase_by(&self, name: &str, key: &str, filter: &Filter) -> Vec<(String, f64)> {
        let mut by: BTreeMap<String, f64> = BTreeMap::new();
        for (s, d, _) in self.deltas(name, filter) {
            *by.entry(s.label(key).to_string()).or_default() += d;
        }
        by.into_iter().filter(|(_, n)| *n > 0.0).collect()
    }

    /// Per second over the period: a counter's growth, or a histogram's observations.
    pub fn rate(&self, name: &str, filter: &Filter) -> Option<f64> {
        Some(self.increase(name, filter) / self.seconds()?)
    }

    /// `rate`, summed by the value of `key`.
    pub fn rate_by(&self, names: &[&str], key: &str, filter: &Filter) -> Vec<(String, f64)> {
        let Some(seconds) = self.seconds() else {
            return vec![];
        };
        let mut by: BTreeMap<String, f64> = BTreeMap::new();
        for name in names {
            for (s, d, _) in self.deltas(name, filter) {
                *by.entry(s.label(key).to_string()).or_default() += d / seconds;
            }
        }
        by.into_iter().collect()
    }

    /// A histogram's observations in the period, merged across `names` and matching series and
    /// split by `key` (or all together when `key` is empty): count, sum, and bucket counts.
    fn observed(&self, names: &[&str], key: &str, filter: &Filter) -> BTreeMap<String, Observed> {
        let mut by: BTreeMap<String, Observed> = BTreeMap::new();
        for name in names {
            for (labels, s) in self.to.matching(name, filter) {
                let before = self.from.and_then(|f| f.get(name, labels));
                let o = by.entry(s.label(key).to_string()).or_default();
                o.count += s.count - before.map_or(0.0, |b| b.count);
                o.sum += s.sum - before.map_or(0.0, |b| b.sum);
                for (bound, n) in &s.buckets {
                    let was = before
                        .and_then(|b| b.buckets.iter().find(|(x, _)| x == bound))
                        .map_or(0.0, |(_, n)| *n);
                    *o.buckets.entry(*bound).or_default() += n - was;
                }
            }
        }
        by.retain(|_, o| o.count > 0.0);
        by
    }

    /// The upper bound of the bucket holding the `q` quantile of what a histogram observed.
    pub fn quantile(&self, names: &[&str], filter: &Filter, q: f64) -> Option<f64> {
        self.observed(names, "", filter)
            .remove("")
            .and_then(|o| o.quantile(q))
    }

    /// The mean of what a histogram observed.
    pub fn mean(&self, names: &[&str], filter: &Filter) -> Option<f64> {
        self.observed(names, "", filter)
            .remove("")
            .map(|o| o.mean())
    }

    /// For each value of `key`: calls per second from the `calls` counters, and the mean and 99th
    /// percentile from the sampled `samples` histograms. Thread time is mean times calls: the
    /// share of one thread the operation takes.
    pub fn timers(
        &self,
        calls: &[&str],
        samples: &[&str],
        key: &str,
        filter: &Filter,
    ) -> Vec<Timer> {
        let rates: HashMap<String, f64> = self.rate_by(calls, key, filter).into_iter().collect();
        let observed = self.observed(samples, key, filter);
        let mut timers: Vec<Timer> = rates
            .into_iter()
            .filter(|(_, rate)| *rate > 0.0)
            .map(|(name, rate)| {
                let o = observed.get(&name);
                let mean = o.map(Observed::mean);
                Timer {
                    thread: mean.map(|m| m * rate / 1e9),
                    p99: o.and_then(|o| o.quantile(0.99)),
                    name,
                    rate,
                    mean,
                }
            })
            .collect();
        timers.sort_by(|a, b| {
            b.thread
                .unwrap_or(0.0)
                .total_cmp(&a.thread.unwrap_or(0.0))
                .then(b.rate.total_cmp(&a.rate))
        });
        timers
    }
}

#[derive(Default)]
struct Observed {
    count: f64,
    sum: f64,
    buckets: BTreeMap<u64, f64>,
}

impl Observed {
    fn mean(&self) -> f64 {
        self.sum / self.count
    }

    fn quantile(&self, q: f64) -> Option<f64> {
        let want = self.count * q;
        self.buckets
            .iter()
            .find(|(_, n)| **n >= want)
            .map(|(bound, _)| *bound as f64)
    }
}

/// One operation of a timer pair.
pub struct Timer {
    pub name: String,
    pub rate: f64,
    pub mean: Option<f64>,
    pub p99: Option<f64>,
    /// Share of one thread: 1.0 is one thread busy all the time.
    pub thread: Option<f64>,
}

/// A number in a few characters: 1234 as 1234, 12345678 as 12.3M.
pub fn short(n: f64) -> String {
    // No "-0".
    let n = if n == 0.0 { 0.0 } else { n };
    let a = n.abs();
    if a >= 1e9 {
        format!("{:.1}G", n / 1e9)
    } else if a >= 1e6 {
        format!("{:.1}M", n / 1e6)
    } else if a >= 1e4 {
        format!("{:.1}k", n / 1e3)
    } else if a >= 100.0 || a.fract() == 0.0 {
        format!("{n:.0}")
    } else if a >= 1.0 {
        format!("{n:.1}")
    } else {
        format!("{n:.2}")
    }
}

/// A duration in nanoseconds, in its natural unit. `u64::MAX` is a histogram's `+Inf` bucket.
pub fn duration(ns: f64) -> String {
    if ns >= u64::MAX as f64 {
        return "> max".to_string();
    }
    if ns >= 1e9 {
        format!("{:.2}s", ns / 1e9)
    } else if ns >= 1e6 {
        format!("{:.1}ms", ns / 1e6)
    } else if ns >= 1e3 {
        format!("{:.1}µs", ns / 1e3)
    } else {
        format!("{ns:.0}ns")
    }
}
