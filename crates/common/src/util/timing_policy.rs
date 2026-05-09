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

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct PerfTimingPolicy {
    pub enabled: bool,
    pub hot_path_shift: u32,
}

impl Default for PerfTimingPolicy {
    fn default() -> Self {
        Self {
            enabled: true,
            hot_path_shift: 6,
        }
    }
}

const MAX_SAMPLE_SHIFT: u32 = 30;
const DISABLED_SAMPLE_STRIDE: u64 = 1 << MAX_SAMPLE_SHIFT;

static PERF_TIMING_ENABLED: AtomicBool = AtomicBool::new(true);
static PERF_TIMING_HOT_SHIFT: AtomicU32 = AtomicU32::new(6);

#[inline]
const fn clamp_sample_shift(shift: u32) -> u32 {
    if shift > MAX_SAMPLE_SHIFT {
        MAX_SAMPLE_SHIFT
    } else {
        shift
    }
}

#[inline]
pub fn perf_timing_policy() -> PerfTimingPolicy {
    PerfTimingPolicy {
        enabled: PERF_TIMING_ENABLED.load(Ordering::Relaxed),
        hot_path_shift: PERF_TIMING_HOT_SHIFT.load(Ordering::Relaxed),
    }
}

#[inline]
pub fn set_perf_timing_policy(policy: PerfTimingPolicy) {
    PERF_TIMING_ENABLED.store(policy.enabled, Ordering::Relaxed);
    PERF_TIMING_HOT_SHIFT.store(clamp_sample_shift(policy.hot_path_shift), Ordering::Relaxed);
}

#[inline]
fn enabled_sample_stride(shift: u32) -> u64 {
    1u64 << clamp_sample_shift(shift)
}

/// Compute the stride value for hot-path timers from the current policy.
/// If timing is disabled, returns a very large stride (effectively never samples).
#[inline]
pub fn hot_stride() -> u64 {
    let policy = perf_timing_policy();
    if !policy.enabled {
        return DISABLED_SAMPLE_STRIDE;
    }
    enabled_sample_stride(policy.hot_path_shift)
}

/// Stride for rare-path timers.
#[inline]
pub fn rare_stride() -> u64 {
    let policy = perf_timing_policy();
    if !policy.enabled {
        return DISABLED_SAMPLE_STRIDE;
    }
    1
}

/// Estimate total elapsed nanoseconds from a hot-path sampled sum.
#[inline]
pub fn scale_hot_sample_sum_nanos(sample_sum_nanos: u64) -> u64 {
    let policy = perf_timing_policy();
    if !policy.enabled {
        return 0;
    }
    sample_sum_nanos.saturating_mul(enabled_sample_stride(policy.hot_path_shift))
}

/// Estimate total elapsed nanoseconds from a rare-path sampled sum.
#[inline]
pub fn scale_rare_sample_sum_nanos(sample_sum_nanos: u64) -> u64 {
    let policy = perf_timing_policy();
    if !policy.enabled {
        return 0;
    }
    sample_sum_nanos
}
