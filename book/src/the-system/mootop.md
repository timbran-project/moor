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

The header shows the daemon's total CPU, split into time spent running MOO tasks, time spent
committing transactions, and time on the daemon's other threads (networking, the database writer,
and so on). Below it, it shows commits per second by outcome, and the mean time of a write commit.

The table has three views:

| Key | View     | Shows                                                       |
| --- | -------- | ----------------------------------------------------------- |
| `1` | Verbs    | Each verb, as `definer:name`, with CPU and calls per second |
| `2` | Builtins | Each builtin function, with CPU and calls per second        |
| `3` | Tasks    | Each task, with its CPU and the frame it spent most time in |

Other keys:

| Key                      | Does                                                   |
| ------------------------ | ------------------------------------------------------ |
| `tab`, `←`, `→`          | Switch view                                            |
| `a`                      | Show totals since `mootop` started, or the last second |
| `p`, `space`             | Pause the display; data is still collected             |
| `↑`, `↓`, `PgUp`, `PgDn` | Scroll                                                 |
| `q`                      | Quit                                                   |

## What the numbers mean

`mootop` samples each CPU 499 times a second (change it with `--hz`) and notes what the daemon is
running there at that moment. A row's **%CPU** is its share of those samples, as a percentage of one
CPU core: a verb at 150% kept one and a half cores busy. Rows can add up to more than 100% on a
machine with several cores.

The time is **self time**: a verb's row counts only the time spent running that verb's own code.
Time in a verb it calls, or in a builtin it calls, goes to that verb's or builtin's row. Lambdas
count as part of the verb that defines them. Time spent committing goes to the commits line, not to
the verb.

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

The report shows the same figures as the live view, totalled over the whole recording, with the top
30 rows of each view (change it with `--top`). To record while watching, give the live view an
output file: `mootop --output capture.jsonl`.

A recording holds one JSON line per second, and contains the verb and builtin names, so a report
needs nothing else: not the server, its database or its binary.

## Overhead

When `mootop` isn't attached, the probes cost one memory read and one predicted branch each. In the
VM benchmarks, a verb call costs 12 more instructions (about 0.3%) and a builtin call 2 more, with
no measurable change in time.

While `mootop` is attached, each verb call, builtin call and commit runs a short BPF program in the
kernel, and each sample runs another. Expect the daemon to use noticeably more CPU on call-heavy
workloads while it is attached. Detaching removes the cost.

`mootop` turns the probes on for the daemon's binary file, not just its process, because given the
process, bpftrace 0.27 took no samples. While it is attached, other processes started from the same
binary, such as a second daemon, also run the probes, though `mootop` ignores them.

## Probes

`mootop` uses these USDT probes, under the provider `moor`. They can also be used from bpftrace
scripts, `perf`, or other USDT tools.

| Probe          | Arguments                                 | Fires when                                                                                            |
| -------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `frame_enter`  | `task, kind, a, b, c, name_ptr, name_len` | A frame is pushed and starts running                                                                  |
| `frame_top`    | `task, kind, a, b, c, name_ptr, name_len` | The top frame changes without a push: after a return or an unwind, or when a task resumes on a thread |
| `task_off`     | `task`                                    | A task stops running on a thread                                                                      |
| `commit_start` | none                                      | A transaction starts committing                                                                       |
| `commit_done`  | `result`                                  | The commit finishes: 0 read-only, 1 write, 2 conflict, 3 error                                        |

`kind` is 0 for no frame (an empty stack), 1 for a verb, 2 for a lambda, 3 for a builtin, and 4 for
an eval. For a verb or a lambda, `a` is the definer object and `b` and `c` are the verb ID's two
halves; for a builtin, `a` is the builtin's number. `name_ptr` and `name_len` give the name, valid
only while the probe runs. The script `mootop` runs is in `tools/mootop/src/mootop.bt`.
