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

use fast_telemetry::{
    DistributionSnapshot, HistogramSnapshot, MetricLabels, MetricMeta, MetricVisitor,
};
use moor_var::Symbol;
use std::collections::HashMap;

pub type MetricEntry = (Symbol, isize, isize);

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

pub struct MetricEntriesVisitor<F>
where
    F: Fn(&str, u64) -> u64,
{
    entries: HashMap<Symbol, (isize, isize)>,
    scale_histogram_sum: F,
}

impl<F> MetricEntriesVisitor<F>
where
    F: Fn(&str, u64) -> u64,
{
    pub fn new(scale_histogram_sum: F) -> Self {
        Self {
            entries: HashMap::new(),
            scale_histogram_sum,
        }
    }

    pub fn into_entries(self) -> Vec<MetricEntry> {
        self.entries
            .into_iter()
            .map(|(name, (count, nanos))| (name, count, nanos))
            .collect()
    }
}

impl<F> MetricVisitor for MetricEntriesVisitor<F>
where
    F: Fn(&str, u64) -> u64,
{
    fn counter(&mut self, meta: MetricMeta<'_>, labels: MetricLabels<'_>, value: i64) {
        let entry = self
            .entries
            .entry(entry_name(meta, labels))
            .or_insert((0, 0));
        entry.0 = entry.0.saturating_add(i64_to_isize(value));
    }

    fn gauge_i64(&mut self, _meta: MetricMeta<'_>, _labels: MetricLabels<'_>, _value: i64) {}

    fn gauge_f64(&mut self, _meta: MetricMeta<'_>, _labels: MetricLabels<'_>, _value: f64) {}

    fn histogram(
        &mut self,
        meta: MetricMeta<'_>,
        labels: MetricLabels<'_>,
        histogram: &dyn HistogramSnapshot,
    ) {
        let scaled_sum = (self.scale_histogram_sum)(meta.name, histogram.sum());
        let entry = self
            .entries
            .entry(entry_name(meta, labels))
            .or_insert((0, 0));
        entry.1 = entry.1.saturating_add(u64_to_isize(scaled_sum));
    }

    fn distribution(
        &mut self,
        _meta: MetricMeta<'_>,
        _labels: MetricLabels<'_>,
        _distribution: &dyn DistributionSnapshot,
    ) {
    }
}
