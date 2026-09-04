# Performance Tools

## Microbenchmark measurements

The value, collection, and VM benchmarks use micromeasure 0.16. Run a target or filter by a
case-name substring:

```bash
cargo bench -p moor-var --bench var_benches -- mixed_int_float_add
cargo bench -p moor-var --bench map_benches
cargo bench -p moor-kernel --bench vm_micro_benches -- dispatch_local_add
```

The VM suite and value drop cases use compact PMU counters: cycles, instructions, branches, and
branch misses. These usually require less multiplexing than the full profile used by the remaining
value and map cases. The bounded drop samples can be too short for a multiplexed event set to
schedule. Check the reported counter scheduling quality before interpreting PMU differences.

Micromeasure prepares a fresh context outside the measurement window for every sample. The VM cases
execute 100 million opcodes per sample, including transaction entry and rollback but excluding
compilation and initial VM construction. Drop cases prepare exactly 50,000 values of the selected
type and time their destruction. Their fixed sample size bounds setup allocations; short-duration
warnings indicate that these runs collected less timing evidence than the requested budget.

Map cases ending in `batches` insert or remove up to 4,096 distinct keys before resetting to the
base map. Reset and disposal costs are included. This keeps inserts absent and removals present even
when calibration selects more operations than the key pool contains. The `insert_remove` and
`remove_insert` cases return an explicit operation count through `BenchSampleResult`: each iteration
counts as two map operations. Their ns/op is the average across the pair, not isolated insertion or
removal latency.

The value and map suites set `workload_revision=2` in their report environment so these corrected
measurements do not automatically compare with earlier workloads. If supplying
`MICROMEASURE_CONTEXT_FILE`, include that field in its `environment` object: the explicit file
replaces the programmatic context.

Use exact report paths to retain evidence for an experiment:

```bash
MICROMEASURE_OUTPUT=/tmp/map-baseline.json cargo bench -p moor-var --bench map_benches
# After an implementation change, on the same machine and with the same configuration:
MICROMEASURE_BASELINE=/tmp/map-baseline.json MICROMEASURE_OUTPUT=/tmp/map-current.json \
    cargo bench -p moor-var --bench map_benches
```

Micromeasure's context, explicit baselines, chunk-aware factories, and operation counts were already
available in 0.14.1. Version 0.16 also supports operation-reported primary durations for
device-timed work and automatic Linux memory-controller bandwidth collection when usable counters
are available. The CPU benchmarks retain the backend's elapsed duration. Memory-bandwidth metrics,
when present, are system-wide and should not be interpreted as traffic attributed exclusively to the
benchmark.

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
