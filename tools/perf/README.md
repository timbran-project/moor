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

Use the static `moor_v1` probes to measure tasks, MOO verb calls, interpreter slices, native
builtins, and database commit stages:

```bash
sudo tools/perf/snapshot-running-moor.sh --duration 30 428948
```

The archive contains a text report, the aggregate data, and the process executable. The report
includes completed intervals, active intervals, and sampled MOO program counters.

The command attaches to static USDT probe points through uprobes. The Linux kernel patches each
active probe site for the duration of the capture. The process crosses into the kernel only at
attached probe sites. Detaching restores the dormant probe sites.

The attached probes run a BPF program at each boundary. BPF maps aggregate the counts and durations
in the kernel. The command reads the maps after the capture. It does not send each boundary event to
user space.

Each CPU has separate aggregate keys. The analyzer merges these keys after the capture. This design
prevents concurrent initialization from losing the first sample.

Task rows show the numeric task ID and the root verb identity. Verb identities contain a definer and
UUID because verb names are database data.

MOO verb-call rows count real verb activations. The `started` column counts activations created
during the capture. The `done` column counts those activations that also finished during the
capture.

Verb-call elapsed time covers the full activation lifetime. It includes native builtins, child verb
calls, suspension, and scheduler waits. Nested calls overlap, so these elapsed values are not CPU
usage. The verb-call table does not show `% core`.

The `% elapsed` column shows each verb's share of the elapsed total in the call table. It does not
show a share of capture time.

MOO interpreter rows count execution slices. A slice starts when mooR enters `moo_frame_execute`.
The slice ends when the interpreter returns control to the VM host. One verb call can create many
slices.

Interpreter-slice time excludes work after control returns to the VM host. This excluded work
includes native builtins, child verb calls, and suspension.

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

The report calculates `p95~` from a power-of-two logarithmic histogram. The value is the upper limit
of the selected histogram bucket. This portable histogram form works with bpftrace versions before
0.20, but its percentile estimate is coarse.

The `% section` column shows the share for each row in the measured section. The `% core` column
divides the interval total by the capture duration. This value shows the equivalent use of one CPU
core. Concurrent intervals can make the total more than 100%. Values from overlapping sections do
not form a valid sum.

The command checks for lost output and BPF helper errors. If it finds either condition, the report
replaces all percentages with `--`.

The command permits 65,536 entries in each BPF map. Each observed CPU and identity pair uses an
entry in each aggregate map. Each active verb call uses an entry keyed by task and activation depth.
Each named verb uses an entry in the metadata map. Set `BPFTRACE_MAX_MAP_KEYS` to change this limit.

The capture cannot reconstruct an interval that started before attachment. It reports a completion
without a start as an interval that was already active.

The verb-call table omits calls that started before attachment. Calls that remain active at capture
end appear in a separate list.

If a VM thread panics inside a verb span, its BPF state can retain an invalid program-counter
address. The `-k` option reports a failed pointer read and continues the capture.

The `db_persist` interval ends after the batch enters the writer queue. It does not include the
asynchronous durable write.

The result values have these meanings:

- `task_commit`: `0` is success, `1` is a conflict, and `2` is an error.
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

The tool does not print its transient matching maps. Probes remove entries from these maps when an
interval ends. bpftrace 0.17 can stop if removal occurs while userspace reads the same map.

The active totals use a cumulative per-CPU map. Probes do not remove entries from this map.

The verb-call start rate belongs to the current interval. Completed-call elapsed time belongs to the
interval in which the call finishes. One completed call can span several earlier intervals.

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

An identity shows its UUID when the metadata does not contain its verb name. The cause can be an
incomplete scan, a full BPF map, a long name, or a verb that changed after its task started.

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

The `perf` executable must support the host kernel. The diagnostic image installs the Ubuntu generic
Linux tools package. This package can lack a suitable `perf` version for a different host kernel. If
profile mode reports a version mismatch, install `linux-tools-$(uname -r)` on the host. Then use
`profile-running-moor.sh` on the host. You can also supply a diagnostic image that contains a
suitable `perf` executable.

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
