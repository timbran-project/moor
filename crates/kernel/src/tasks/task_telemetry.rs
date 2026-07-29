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

use std::time::Duration;

use moor_common::{tasks::TaskId, threading::current_task_worker_index, util::Instant};
use moor_var::Obj;

/// Scheduler-visible execution state of an active task.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActiveTaskPhase {
    /// The task has been submitted but has not yet entered a task-pool worker.
    Dispatching,
    /// The task currently owns a task-pool worker.
    Running,
}

/// A point-in-time view of an active task's scheduler and operating-system activity.
#[derive(Debug, Clone)]
pub struct TaskTelemetry {
    pub task_id: TaskId,
    pub player: Obj,
    pub phase: ActiveTaskPhase,
    pub worker_index: Option<usize>,
    pub dispatch_duration: Duration,
    pub running_duration: Option<Duration>,
    #[cfg(target_os = "linux")]
    pub linux: Option<LinuxTaskTelemetry>,
}

/// Linux counters attributed to the current uninterrupted execution of a task.
#[cfg(target_os = "linux")]
#[derive(Debug, Clone)]
pub struct LinuxTaskTelemetry {
    pub pid: u32,
    pub tid: u32,
    pub state: Option<char>,
    pub cpu_runtime_ns: Option<u64>,
    pub user_cpu_ns: Option<u64>,
    pub system_cpu_ns: Option<u64>,
    pub minor_faults: Option<u64>,
    pub major_faults: Option<u64>,
    pub voluntary_context_switches: Option<u64>,
    pub involuntary_context_switches: Option<u64>,
    pub last_cpu: Option<u32>,
    pub wchan: Option<String>,
}

#[derive(Clone, PartialEq, Eq)]
pub(crate) struct TaskRunBaseline {
    started_at: Instant,
    worker_index: Option<usize>,
    #[cfg(target_os = "linux")]
    linux: LinuxTaskBaseline,
}

impl TaskRunBaseline {
    /// Capture is called by the worker that is about to execute the task. The resulting value is
    /// immutable, so observing telemetry does not cause writes to worker-owned cache lines.
    pub(crate) fn capture() -> Self {
        Self {
            started_at: Instant::now(),
            worker_index: current_task_worker_index(),
            #[cfg(target_os = "linux")]
            linux: LinuxTaskBaseline::capture(),
        }
    }
}

pub(crate) struct TaskTelemetrySource {
    pub(crate) task_id: TaskId,
    pub(crate) player: Obj,
    pub(crate) dispatched_at: Instant,
    pub(crate) baseline: Option<TaskRunBaseline>,
}

impl TaskTelemetrySource {
    pub(crate) fn sample(&self) -> TaskTelemetry {
        let Some(baseline) = &self.baseline else {
            return TaskTelemetry {
                task_id: self.task_id,
                player: self.player,
                phase: ActiveTaskPhase::Dispatching,
                worker_index: None,
                dispatch_duration: self.dispatched_at.elapsed(),
                running_duration: None,
                #[cfg(target_os = "linux")]
                linux: None,
            };
        };

        TaskTelemetry {
            task_id: self.task_id,
            player: self.player,
            phase: ActiveTaskPhase::Running,
            worker_index: baseline.worker_index,
            dispatch_duration: baseline
                .started_at
                .saturating_duration_since(self.dispatched_at),
            running_duration: Some(baseline.started_at.elapsed()),
            #[cfg(target_os = "linux")]
            linux: Some(baseline.linux.sample()),
        }
    }
}

#[cfg(target_os = "linux")]
#[derive(Clone, PartialEq, Eq)]
struct LinuxTaskBaseline {
    pid: u32,
    tid: u32,
    cpu_clock_id: Option<libc::clockid_t>,
    cpu_runtime_ns: Option<u64>,
    usage: Option<LinuxThreadUsage>,
}

#[cfg(target_os = "linux")]
impl LinuxTaskBaseline {
    fn capture() -> Self {
        let cpu_clock_id = current_thread_cpu_clock_id();
        Self {
            pid: std::process::id(),
            tid: unsafe { libc::gettid() as u32 },
            cpu_runtime_ns: cpu_clock_id.and_then(read_cpu_clock_ns),
            cpu_clock_id,
            usage: read_current_thread_usage(),
        }
    }

    fn sample(&self) -> LinuxTaskTelemetry {
        let task_path = format!("/proc/self/task/{}", self.tid);
        let stat = read_proc_stat(&format!("{task_path}/stat"));
        let status = read_proc_status(&format!("{task_path}/status"));
        let wchan = std::fs::read_to_string(format!("{task_path}/wchan"))
            .ok()
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());

        let cpu_runtime_ns = counter_delta(
            self.cpu_clock_id.and_then(read_cpu_clock_ns),
            self.cpu_runtime_ns,
        );
        let minor_faults = counter_delta(
            stat.as_ref().map(|sample| sample.minor_faults),
            self.usage.as_ref().map(|sample| sample.minor_faults),
        );
        let major_faults = counter_delta(
            stat.as_ref().map(|sample| sample.major_faults),
            self.usage.as_ref().map(|sample| sample.major_faults),
        );
        let user_cpu_ns = cpu_time_delta(
            stat.as_ref()
                .and_then(|sample| ticks_to_ns(sample.user_ticks)),
            self.usage.as_ref().map(|sample| sample.user_cpu_ns),
        );
        let system_cpu_ns = cpu_time_delta(
            stat.as_ref()
                .and_then(|sample| ticks_to_ns(sample.system_ticks)),
            self.usage.as_ref().map(|sample| sample.system_cpu_ns),
        );
        let voluntary_context_switches = counter_delta(
            status
                .as_ref()
                .map(|sample| sample.voluntary_context_switches),
            self.usage
                .as_ref()
                .map(|sample| sample.voluntary_context_switches),
        );
        let involuntary_context_switches = counter_delta(
            status
                .as_ref()
                .map(|sample| sample.involuntary_context_switches),
            self.usage
                .as_ref()
                .map(|sample| sample.involuntary_context_switches),
        );

        LinuxTaskTelemetry {
            pid: self.pid,
            tid: self.tid,
            state: stat.as_ref().map(|sample| sample.state),
            cpu_runtime_ns,
            user_cpu_ns,
            system_cpu_ns,
            minor_faults,
            major_faults,
            voluntary_context_switches,
            involuntary_context_switches,
            last_cpu: stat.as_ref().and_then(|sample| sample.last_cpu),
            wchan,
        }
    }
}

#[cfg(target_os = "linux")]
fn counter_delta(current: Option<u64>, baseline: Option<u64>) -> Option<u64> {
    current?.checked_sub(baseline?)
}

#[cfg(target_os = "linux")]
fn cpu_time_delta(current: Option<u64>, baseline: Option<u64>) -> Option<u64> {
    Some(current?.saturating_sub(baseline?))
}

#[cfg(target_os = "linux")]
fn ticks_to_ns(ticks: u64) -> Option<u64> {
    let ticks_per_second = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    if ticks_per_second <= 0 {
        return None;
    }

    let nanos = (ticks as u128)
        .saturating_mul(1_000_000_000)
        .checked_div(ticks_per_second as u128)?;
    Some(nanos.min(u64::MAX as u128) as u64)
}

#[cfg(target_os = "linux")]
fn current_thread_cpu_clock_id() -> Option<libc::clockid_t> {
    let mut clock_id = 0;
    let result = unsafe { libc::pthread_getcpuclockid(libc::pthread_self(), &mut clock_id) };
    (result == 0).then_some(clock_id)
}

#[cfg(target_os = "linux")]
fn read_cpu_clock_ns(clock_id: libc::clockid_t) -> Option<u64> {
    let mut timespec = std::mem::MaybeUninit::<libc::timespec>::uninit();
    if unsafe { libc::clock_gettime(clock_id, timespec.as_mut_ptr()) } != 0 {
        return None;
    }
    let timespec = unsafe { timespec.assume_init() };
    if timespec.tv_sec < 0 || timespec.tv_nsec < 0 {
        return None;
    }
    let nanos = (timespec.tv_sec as u128)
        .saturating_mul(1_000_000_000)
        .saturating_add(timespec.tv_nsec as u128);
    Some(nanos.min(u64::MAX as u128) as u64)
}

#[cfg(target_os = "linux")]
#[derive(Clone, PartialEq, Eq)]
struct LinuxThreadUsage {
    user_cpu_ns: u64,
    system_cpu_ns: u64,
    minor_faults: u64,
    major_faults: u64,
    voluntary_context_switches: u64,
    involuntary_context_switches: u64,
}

#[cfg(target_os = "linux")]
fn read_current_thread_usage() -> Option<LinuxThreadUsage> {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    if unsafe { libc::getrusage(libc::RUSAGE_THREAD, usage.as_mut_ptr()) } != 0 {
        return None;
    }
    let usage = unsafe { usage.assume_init() };

    Some(LinuxThreadUsage {
        user_cpu_ns: timeval_to_ns(usage.ru_utime)?,
        system_cpu_ns: timeval_to_ns(usage.ru_stime)?,
        minor_faults: usage.ru_minflt.try_into().ok()?,
        major_faults: usage.ru_majflt.try_into().ok()?,
        voluntary_context_switches: usage.ru_nvcsw.try_into().ok()?,
        involuntary_context_switches: usage.ru_nivcsw.try_into().ok()?,
    })
}

#[cfg(target_os = "linux")]
fn timeval_to_ns(timeval: libc::timeval) -> Option<u64> {
    if timeval.tv_sec < 0 || timeval.tv_usec < 0 {
        return None;
    }
    let nanos = (timeval.tv_sec as u128)
        .saturating_mul(1_000_000_000)
        .saturating_add((timeval.tv_usec as u128).saturating_mul(1_000));
    Some(nanos.min(u64::MAX as u128) as u64)
}

#[cfg(target_os = "linux")]
#[derive(Clone, PartialEq, Eq)]
struct LinuxProcStat {
    state: char,
    minor_faults: u64,
    major_faults: u64,
    user_ticks: u64,
    system_ticks: u64,
    last_cpu: Option<u32>,
}

#[cfg(target_os = "linux")]
fn read_proc_stat(path: &str) -> Option<LinuxProcStat> {
    let contents = std::fs::read_to_string(path).ok()?;
    parse_proc_stat(&contents)
}

#[cfg(target_os = "linux")]
fn parse_proc_stat(contents: &str) -> Option<LinuxProcStat> {
    // The command name is parenthesized and may itself contain spaces or parentheses.
    let command_end = contents.rfind(')')?;
    let mut fields = contents.get(command_end + 1..)?.split_whitespace();
    let state = fields.next()?.chars().next()?;
    let fields: Vec<_> = fields.collect();

    Some(LinuxProcStat {
        state,
        // Indexes are relative to field 4 because state (field 3) was consumed above.
        minor_faults: fields.get(6)?.parse().ok()?,
        major_faults: fields.get(8)?.parse().ok()?,
        user_ticks: fields.get(10)?.parse().ok()?,
        system_ticks: fields.get(11)?.parse().ok()?,
        // processor is field 39.
        last_cpu: fields.get(35).and_then(|value| value.parse().ok()),
    })
}

#[cfg(target_os = "linux")]
#[derive(Clone, PartialEq, Eq)]
struct LinuxProcStatus {
    voluntary_context_switches: u64,
    involuntary_context_switches: u64,
}

#[cfg(target_os = "linux")]
fn read_proc_status(path: &str) -> Option<LinuxProcStatus> {
    let contents = std::fs::read_to_string(path).ok()?;
    parse_proc_status(&contents)
}

#[cfg(target_os = "linux")]
fn parse_proc_status(contents: &str) -> Option<LinuxProcStatus> {
    let mut voluntary = None;
    let mut involuntary = None;

    for line in contents.lines() {
        if let Some(value) = line.strip_prefix("voluntary_ctxt_switches:") {
            voluntary = value.trim().parse().ok();
        } else if let Some(value) = line.strip_prefix("nonvoluntary_ctxt_switches:") {
            involuntary = value.trim().parse().ok();
        }
    }

    Some(LinuxProcStatus {
        voluntary_context_switches: voluntary?,
        involuntary_context_switches: involuntary?,
    })
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::{LinuxTaskBaseline, parse_proc_stat, parse_proc_status};

    #[test]
    fn samples_current_linux_thread() {
        let baseline = LinuxTaskBaseline::capture();
        let sample = baseline.sample();

        assert_eq!(sample.pid, std::process::id());
        assert_eq!(sample.tid, unsafe { libc::gettid() as u32 });
        assert!(sample.cpu_runtime_ns.is_some());
        assert!(sample.state.is_some());
        assert!(sample.last_cpu.is_some());
    }

    #[test]
    fn parses_proc_stat_with_parentheses_in_command() {
        let fields = [
            "S", "1", "2", "3", "4", "5", "6", "17", "8", "19", "10", "23", "29", "13", "14", "15",
            "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29",
            "30", "31", "32", "33", "34", "35", "7",
        ];
        let input = format!("42 (worker ) name) {}", fields.join(" "));
        let parsed = parse_proc_stat(&input).unwrap();

        assert_eq!(parsed.state, 'S');
        assert_eq!(parsed.minor_faults, 17);
        assert_eq!(parsed.major_faults, 19);
        assert_eq!(parsed.user_ticks, 23);
        assert_eq!(parsed.system_ticks, 29);
        assert_eq!(parsed.last_cpu, Some(7));
    }

    #[test]
    fn parses_context_switch_counts() {
        let parsed = parse_proc_status(
            "Name:\tmoor-task-pool\nvoluntary_ctxt_switches:\t12\n\
             nonvoluntary_ctxt_switches:\t34\n",
        )
        .unwrap();

        assert_eq!(parsed.voluntary_context_switches, 12);
        assert_eq!(parsed.involuntary_context_switches, 34);
    }
}
