This is meant to be a "core" which is in fact a set of objdef files that can be used to benchmark
the performance of some mooR workloads.

Run `make bench` to build and run the benchmarks, which present as mooR `objdef` test_ runs.

Run `make bench-string-history` to measure appends to large string-list properties. The benchmark
starts four writer tasks by default. Each task appends 20 strings to a list that contains 1,024
distinct strings. Each string contains 2,048 bytes.

Use `HISTORY_WRITERS`, `HISTORY_ENTRIES`, `HISTORY_ENTRY_BYTES`, `HISTORY_APPENDS`, and
`HISTORY_APPEND_DELAY` to change the workload. `HISTORY_APPEND_WIDTH` appends multiple strings in
one update. `HISTORY_MUTATION_MODE=1` replaces one element, while mode 2 rebuilds the prefix before
each append. The setup phase persists the initial lists before the benchmark captures the
performance counters.

Use this command to put pressure on the batch-writer queue:

```shell
make bench-string-history HISTORY_WRITERS=8 HISTORY_ENTRIES=1024 \
  HISTORY_ENTRY_BYTES=2048 HISTORY_APPENDS=150 HISTORY_SETTLE_SECONDS=0
```

This preset submits 1,200 property updates. The `HISTORY_APPEND_RESULT` line reports the time that
the producer tasks require. The batch-writer counters report queue-full events and blocked time.
