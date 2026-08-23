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

## Capture a mooR runtime snapshot

Use the static `moor_v1` probes to measure tasks, MOO verbs, native builtins, and database commit
stages:

```bash
sudo tools/perf/snapshot-running-moor.sh --duration 30 428948
```

The archive contains a text report, the aggregate data, and the process executable. The report
includes completed intervals, active intervals, and sampled MOO program counters.

The command attaches dynamic uprobes to the selected process. The Linux kernel patches each active
probe site for the duration of the capture. The process crosses into the kernel only at attached
probe sites. Detaching restores the dormant probe sites.

The attached probes run a BPF program at each boundary. BPF maps aggregate the counts and durations
in the kernel. The command reads the maps after the capture. It does not send each boundary event to
user space.

Each CPU has separate aggregate keys. The analyzer merges these keys after the capture. This design
prevents concurrent initialization from losing the first sample.

Task rows show the numeric task ID and the root verb identity. Verb identities contain a definer and
UUID because verb names are database data.

Builtin rows show native builtin execution slices. An initial call is one slice. Each trampoline
re-entry that calls native builtin code is another slice. Proxy overrides do not count as native
builtin execution.

The probes emit only numeric builtin IDs. The snapshot command reads `crates/common/src/builtins.rs`
after capture and stores `builtin-map.json` in the archive. Set `BUILTIN_SOURCE` when the registry
source is in a different location.

Use the map tool to resolve IDs without a capture:

```bash
tools/perf/builtin-id-map.py 0 256 512
```

The report calculates `p95~` from a fine-grained logarithmic histogram. The value is the upper limit
of the selected histogram bucket.

The command checks for lost output and BPF helper errors. If it finds either condition, the report
replaces all percentages with `--`.

The command permits 65,536 entries in each BPF map. Set `BPFTRACE_MAX_MAP_KEYS` to change this
limit.

The capture cannot reconstruct an interval that started before attachment. It reports a completion
without a start as an interval that was already active.

The `db_persist` interval ends after the batch enters the writer queue. It does not include the
asynchronous durable write.

The result values have these meanings:

- `db_total`: `0` is a read-only success, `1` is a write success, `2` is a conflict, and `3` is
  rebase exhaustion.
- `db_prepare`: `0` is success and `1` is an error.
- `db_check`: `0` is success and `1` is a conflict.
- `db_publish`: `0` is a lost compare-and-swap and `1` is a published snapshot.
- `db_rebase`: `0` is a lost compare-and-swap, `1` is a published snapshot, and `2` is an overlap.
- `db_persist`: `0` is success, `1` is an encoding error, and `2` is an enqueue error.

## Watch a running server

Use `mootop` to show five-second deltas from the same probes:

```bash
sudo tools/perf/mootop.sh
```

Use `--interval` to change the refresh period. Use `--once` to print one interval and stop.

The live values are approximate because userspace reads the cumulative maps while probes continue to
update them. The tool never clears a live map, which avoids clear-and-update races between windows.

When `mootop` attaches, the daemon reads verb names from its current database snapshot. It emits the
names from a background diagnostics thread. The VM and scheduler hot paths do not read or copy verb
names.

`mootop` writes the names to `moor-verb-map-PID.json` in the current directory. Use
`--verb-map-output` to select a different path:

```bash
sudo tools/perf/mootop.sh --verb-map-output /tmp/verb-map.json
```

The tool writes the map only after it receives every name. It reports a warning if the BPF map is
too small or a name is too long. Increase `BPFTRACE_MAX_MAP_KEYS` or `BPFTRACE_MAX_STRLEN` and run
the command again.

The diagnostics thread checks the USDT semaphore once per second. It scans the database only when
the probe changes from detached to attached. Do not open the active Fjall database from a second
process.

You can also start with an existing JSON map. This can supply names from a previous run:

```json
{
  "5d18a043-8852-49af-932c-bbe8f80e0edf": "run_once"
}
```

```bash
sudo tools/perf/mootop.sh --verb-map verb-map.json
```

The live metadata replaces matching entries from the supplied map.

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

## Profile a server in Docker

These commands require a local Docker daemon on Linux. The profiler uses the kernel of the Docker
host.

If the host has the required tools, attach to the server by its container name:

```bash
sudo tools/perf/snapshot-running-moor.sh --duration 30 --container moor
sudo tools/perf/profile-running-moor.sh --duration 30 --container moor
sudo tools/perf/mootop.sh --container moor
```

The scripts use `docker top` to find the host PID. This also works when an init process is PID 1 in
the container. The target container does not need more packages or privileges.

If the host does not have the required tools, use the diagnostic image:

```bash
tools/perf/run-containerized-moor-perf.sh snapshot moor
tools/perf/run-containerized-moor-perf.sh profile moor
tools/perf/run-containerized-moor-perf.sh top moor
```

The first command builds `moor-perf-tools:local` when the image does not exist. Use `--build` after
you change the performance tools or switch to a different mooR version.

Set `MOOR_PERF_IMAGE` to use a different image name. Set `OUT_DIR` or use `--output` to select the
archive directory. In `top` mode, the same directory receives `moor-verb-map-PID.json`.

CAUTION: Use the diagnostic image only on a host that you administer. The privileged container can
control the Docker host.

The diagnostic container uses the host PID namespace and mounts the host tracing filesystems. It
stops after the capture. The target server container stays unchanged.

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
