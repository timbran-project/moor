# Watching a Server with mootop

`mootop` shows, live, where a running mooR server spends its CPU time: which verbs, which builtins,
and which tasks. It works like `top` or `htop`, but for MOO code rather than for processes. It can
also record a session to a file and print a report from it later.

The [performance counters](performance-and-concurrency.md#performance-counters) and the Prometheus
metrics answer "how busy is the server, and in which subsystem". `mootop` answers "which MOO code is
keeping it busy".

## Requirements

- Linux, with [bpftrace](https://github.com/bpftrace/bpftrace) installed. `mootop` has been tested
  with bpftrace 0.20.
- Root, or the capabilities bpftrace needs to attach probes.
- A mooR server built from this version or later. The probes `mootop` reads are part of every build;
  nothing needs to be turned on.

`mootop` is not built by default. Build it from the repository:

```bash
cargo build --release -p mootop
```

## Watching a server

```bash
sudo target/release/mootop
```

With no options, `mootop` attaches to the only running `moor-daemon` (or single-process `moor`)
process. Use `--pid` to choose one. When the daemon runs in a container, run `mootop` on the host
and give the daemon's host PID; `mootop` finds the daemon's binary through `/proc`.

The top line shows the daemon's CPU, the players connected, the tasks active and suspended, and how
many warnings there are. Below it are six views:

| Key | View     | Shows                                                                                    |
| --- | -------- | ---------------------------------------------------------------------------------------- |
| `1` | Overview | Headline figures with their last two minutes, CPU and commit charts, and warnings        |
| `2` | Verbs    | Each verb, as `definer:name`, with CPU and calls per second                              |
| `3` | Builtins | Each builtin function, with CPU, calls per second, and latency                           |
| `4` | Tasks    | Each task's CPU and busiest frame, and what the scheduler is doing                       |
| `5` | Database | Commits, the database operations taking the most thread time, caches, and the write path |
| `6` | RPC      | Requests waiting for a daemon thread, deferred call pools, sessions, and workers         |

Other keys:

| Key                      | Does                                                                 |
| ------------------------ | -------------------------------------------------------------------- |
| `tab`, `←`, `→`          | Switch view                                                          |
| `a`                      | Show totals since `mootop` started, rather than the last few seconds |
| `p`, `space`             | Pause the display; data is still collected                           |
| `↑`, `↓`, `PgUp`, `PgDn` | Scroll                                                               |
| `q`                      | Quit                                                                 |

The Verbs and Tasks views, and the CPU figures, come from sampling the daemon (see below). The rest
comes from the daemon's own metrics, the same ones it exports to Prometheus (see `--metrics-file` in
[Server Configuration](server-configuration.md)), which it sends to `mootop` directly while it is
attached. Only the daemon sends them: `moor-daemon` and the single-process `moor`.

### Overview

Ten figures, each with a sparkline of its last two minutes: daemon CPU, verb calls per second,
players, tasks active and suspended, tasks started, commits and conflicts per second, and RPC
requests waiting and their 99th-percentile wait. Below them, charts of CPU (split into MOO tasks,
commits, and the daemon's other threads) and of commits per second by outcome.

The warnings list problems seen since `mootop` started: calls refused because a pool was full,
commits refused by the commit queue timeout, RPC requests waiting over a second or dropped,
schedules retired after repeated faults, a worker type with no worker attached, and commit conflicts
of one a second or more.

### Builtins

CPU comes from sampling. Calls per second, mean, and 99th percentile come from the daemon's builtin
counters, which count every call and time a sample of them. **Thread** is the mean time times the
calls: the share of one thread the builtin takes.

### Tasks

Beside the tasks table: tasks started, resumed, forked, and killed per second; conflict retries,
aborts at limits, cancellations, and uncaught errors per second; how long tasks wait to be scheduled
(from submission to first running, from waking to running, and handing over between threads);
suspended tasks by what they wait for; and scheduled tasks.

### Database

Commits per second by outcome, commit latency with each phase's 99th percentile, and the database
operations taking the most thread time, with their calls per second and latency. Commits are left
out of that table, since the commit figures cover them. Below: each cache's hit ratio, size, and
flushes; the write path; and how long garbage collection and checkpoints take when they run.

### RPC

The daemon's request queues: requests waiting for a thread, taken per second, how long they waited,
and how many were dropped because the queue was full. Each deferred call pool's places in use
against its limit, and calls it refused. Sessions, and the workers attached, with their requests by
result.

Rates and percentiles cover the last five seconds, or with `a`, everything since `mootop` started.
Latencies come from histograms, so a percentile is the upper bound of the bucket it falls in.

## What the numbers mean

`mootop` samples each CPU 499 times a second (change it with `--hz`) and notes what the daemon is
running there at that moment. A row's **%CPU** is its share of those samples, as a percentage of one
CPU core: a verb at 150% kept one and a half cores busy. Rows can add up to more than 100% on a
machine with several cores.

The time is **self time**: a verb's row counts only the time spent running that verb's own code.
Time in a verb it calls, or in a builtin it calls, goes to that verb's or builtin's row. Lambdas
count as part of the verb that defines them. [Native verbs](native-verbs.md) appear as verbs, marked
`(native)`. Time spent committing goes to the commits line, not to the verb.

Samples only see work on a CPU. A task that is suspended, or waiting for input or for a worker,
costs nothing and doesn't appear. `mootop` shows where CPU goes, not why a command is slow to
answer; for waiting, see [Why Is My MOO Slow?](performance-and-concurrency.md#why-is-my-moo-slow).

**Calls/s** counts how often a verb or builtin started.

A verb shows its name once it has been called, or its task has resumed, while `mootop` is attached.
Until then it shows its definer and the verb's internal ID.

## Recording and reports

Record for a period without the live display, then print a report:

```bash
sudo target/release/mootop record --duration 60 --output capture.jsonl
target/release/mootop report capture.jsonl
```

The report shows the same figures as the live views, over the whole recording, with the top 30 rows
of each table (change it with `--top`). To record while watching, give the live view an output file:
`mootop --output capture.jsonl`.

A recording holds one JSON line per second, and contains the verb and builtin names and the server
metrics, so a report needs nothing else: not the server, its database or its binary.

## Overhead

When `mootop` isn't attached, the probes cost one memory read and one predicted branch each. In the
VM benchmarks, a verb call costs 12 more instructions (about 0.3%) and a builtin call 2 more, with
no measurable change in time.

The daemon's metrics exporter wakes once a second to check whether a tracer wants its metrics. With
none attached, that check is one memory read. It is the same thread that writes `--metrics-file`, so
it costs no extra thread when a metrics file is set.

While `mootop` is attached, each verb call, builtin call and commit runs a short BPF program in the
kernel, and each sample runs another. Expect the daemon to use noticeably more CPU on call-heavy
workloads while it is attached. Once a second the exporter also collects every metric, as it does to
write the metrics file, and sends each value through a probe. Detaching removes the cost.

`mootop` turns the probes on for the daemon's binary file, not just its process, because given the
process, bpftrace 0.27 took no samples. While it is attached, other processes started from the same
binary, such as a second daemon, also run the probes, though `mootop` ignores them.

## Probes

`mootop` uses these USDT probes, under the provider `moor`. They can also be used from bpftrace
scripts, `perf`, or other USDT tools.

| Probe           | Arguments                                                              | Fires when                                                                                            |
| --------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `frame_enter`   | `task, kind, a, b, c, name_ptr, name_len`                              | A frame is pushed and starts running                                                                  |
| `frame_top`     | `task, kind, a, b, c, name_ptr, name_len`                              | The top frame changes without a push: after a return or an unwind, or when a task resumes on a thread |
| `task_off`      | `task`                                                                 | A task stops running on a thread                                                                      |
| `commit_start`  | none                                                                   | A transaction starts committing                                                                       |
| `commit_done`   | `result`                                                               | The commit finishes: 0 read-only, 1 write, 2 conflict, 3 error                                        |
| `metrics_begin` | `service_ptr, service_len`                                             | Once a second, while a tracer is attached, before the daemon sends its metrics                        |
| `metric`        | `name_ptr, name_len, labels_ptr, labels_len, kind, part, value, bound` | Once per metric value, between `metrics_begin` and `metrics_end`                                      |
| `metrics_end`   | none                                                                   | After the last value                                                                                  |

`kind` is 0 for no frame (an empty stack), 1 for a verb, 2 for a lambda, 3 for a builtin, 4 for an
eval, and 5 for a native verb. For a verb, a lambda or a native verb, `a` is the definer object and
`b` and `c` are the verb ID's two halves; for a builtin, `a` is the builtin's number. `name_ptr` and
`name_len` give the name, valid only while the probe runs.

For `metric`, `labels` are `key=value` pairs joined by commas. `kind` is 0 for a counter, 1 for a
gauge, 2 for a histogram. `part` says what `value` is: 0 an integer, 1 the bits of a float, 2 a
histogram's count, 3 its sum, 4 a cumulative bucket count, whose upper bound is `bound` (the largest
64-bit value for `+Inf`). Counters still at zero and histograms with no observations are not sent;
treat a series that hasn't been seen as zero.

The scripts `mootop` runs are in `tools/mootop/src/`: `mootop.bt`, and `metrics.bt`, which it adds
when the binary has the metrics probes.
