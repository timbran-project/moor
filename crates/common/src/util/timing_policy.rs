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

use fast_telemetry::{LabelEnum, LabeledSampledTimer};
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

/// Estimate the total of all calls' durations from the sampled ones: `sample_sum` covers
/// `sample_count` of `calls` calls. Returns 0 when nothing was sampled.
#[inline]
pub fn scale_sample_sum(calls: u64, sample_count: u64, sample_sum: u64) -> u64 {
    if sample_count == 0 {
        return 0;
    }
    let total = (sample_sum as u128).saturating_mul(calls as u128) / sample_count as u128;
    total.min(u64::MAX as u128) as u64
}

/// Estimated total nanoseconds spent in `label`'s calls, scaled from that timer's own samples.
#[inline]
pub fn estimated_total_nanos<L: LabelEnum>(timer: &LabeledSampledTimer<L>, label: L) -> u64 {
    scale_sample_sum(
        timer.calls(label),
        timer.sample_count(label),
        timer.sample_sum_nanos(label),
    )
}

#[cfg(test)]
mod tests {
    use super::scale_sample_sum;

    #[test]
    fn scales_by_sampled_share() {
        assert_eq!(scale_sample_sum(64, 1, 500), 32_000);
        assert_eq!(scale_sample_sum(10, 10, 500), 500);
        assert_eq!(scale_sample_sum(10, 0, 0), 0);
        assert_eq!(scale_sample_sum(u64::MAX, 1, u64::MAX), u64::MAX);
    }
}
