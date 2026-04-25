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

use fast_telemetry::{DeriveLabel, LabeledCounter};
use std::sync::OnceLock;

pub(crate) const LOCAL_STATS_BATCH_SIZE: u32 = 128;

#[derive(Default)]
pub(crate) struct LocalCacheStats {
    pub(crate) hits: u32,
    pub(crate) negative_hits: u32,
    pub(crate) misses: u32,
}

impl LocalCacheStats {
    #[inline]
    pub(crate) fn should_flush(&self) -> bool {
        self.hits + self.negative_hits + self.misses >= LOCAL_STATS_BATCH_SIZE
    }
}

#[derive(Copy, Clone, Debug, DeriveLabel)]
#[label_name = "op"]
pub enum CacheOp {
    Hits,
    NegativeHits,
    Misses,
    Flushes,
    NumEntries,
}

/// Unified cache statistics structure
pub struct CacheStats {
    counters: LabeledCounter<CacheOp>,
}

impl Default for CacheStats {
    fn default() -> Self {
        Self::new()
    }
}

impl CacheStats {
    #[inline]
    fn default_shard_count() -> usize {
        static SHARD_COUNT: OnceLock<usize> = OnceLock::new();
        *SHARD_COUNT.get_or_init(|| {
            std::thread::available_parallelism()
                .map(|n| n.get())
                .unwrap_or(1)
        })
    }

    pub fn new() -> Self {
        Self {
            counters: LabeledCounter::new(Self::default_shard_count()),
        }
    }

    pub fn hit(&self) {
        self.counters.inc(CacheOp::Hits);
    }
    pub fn negative_hit(&self) {
        self.counters.inc(CacheOp::NegativeHits);
    }
    pub fn miss(&self) {
        self.counters.inc(CacheOp::Misses);
    }
    pub fn flush(&self) {
        self.counters.inc(CacheOp::Flushes);
    }

    pub fn add_entry(&self) {
        self.counters.inc(CacheOp::NumEntries);
    }

    #[inline]
    pub fn add_hits(&self, count: isize) {
        if count != 0 {
            self.counters.add(CacheOp::Hits, count);
        }
    }

    #[inline]
    pub fn add_negative_hits(&self, count: isize) {
        if count != 0 {
            self.counters.add(CacheOp::NegativeHits, count);
        }
    }

    #[inline]
    pub fn add_misses(&self, count: isize) {
        if count != 0 {
            self.counters.add(CacheOp::Misses, count);
        }
    }

    pub fn remove_entries(&self, count: isize) {
        self.counters.add(CacheOp::NumEntries, -count);
    }

    pub fn hit_count(&self) -> isize {
        self.counters.get(CacheOp::Hits)
    }
    pub fn negative_hit_count(&self) -> isize {
        self.counters.get(CacheOp::NegativeHits)
    }
    pub fn miss_count(&self) -> isize {
        self.counters.get(CacheOp::Misses)
    }
    pub fn flush_count(&self) -> isize {
        self.counters.get(CacheOp::Flushes)
    }

    pub fn num_entries(&self) -> isize {
        self.counters.get(CacheOp::NumEntries)
    }

    pub fn hit_rate(&self) -> f64 {
        let hits = self.counters.get(CacheOp::Hits) as f64;
        let negative_hits = self.counters.get(CacheOp::NegativeHits) as f64;
        let misses = self.counters.get(CacheOp::Misses) as f64;
        let total = hits + negative_hits + misses;
        if total > 0.0 {
            ((hits + negative_hits) / total) * 100.0
        } else {
            0.0
        }
    }
}
