# Performance Tools

## Profile a running server

To record ten seconds from the active `moor-daemon` or `moor` process and bundle the resulting
`perf.data` with the exact executable image used by that process:

```bash
tools/perf/profile-running-moor.sh
```

Pass a duration and PID explicitly when needed:

```bash
tools/perf/profile-running-moor.sh --duration 30 428948
```

The archive is written to the current directory. Set `OUT_DIR` to put it elsewhere. If multiple
matching processes are active, pass the desired PID as the final argument. The script checks access
to the CPU performance counters before recording and reports how to adjust `perf_event_paranoid`
when the kernel setting blocks access.

## Profile activation paths

Use these scripts to profile activation/frame construction paths in isolation from Criterion.

## 1) Collect counters and samples

```bash
tools/perf/activation-profile.sh
```

This builds `activation_profile` in release mode and writes outputs under `target/perf/activation`
by default:

- `stat-default.csv` (`perf stat -d -d -d`)
- `stat-events.csv` (explicit hardware counter set)
- `perf.data` (`perf record`)
- `report-self.txt`
- `report-inclusive.txt`

Config can be overridden with environment variables:

```bash
SCENARIO=nested_simple ITERS=8000000 WARMUP=500000 tools/perf/activation-profile.sh
```

## 2) Regenerate reports from existing `perf.data`

```bash
tools/perf/activation-analyze.sh
```

Outputs:

- `report-top.txt`
- `report-children.txt`
- `annotate-for_call.txt` (when symbol resolution succeeds)

## Scenarios

The binary supports:

- `simple`
- `medium`
- `complex`
- `with_args`
- `with_argstr`
- `nested_simple`
- `mixed`
