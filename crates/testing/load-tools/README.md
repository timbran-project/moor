# moor-model-checker

TLDR: Load, benchmark, and model-checking tools for scheduler/database concurrency and host-level
workloads.

Downstream uses:

- Leaf testing crate; no production crate should depend on it.
- Uses DB, kernel, runtime API, and ZeroMQ client crates to generate stress workloads and histories
  for external checkers.

## Load Testing Tools

Tools for testing the consistency and performance of the moor transaction system.

## list-append

A workload generator for Jepsen/Elle's `list-append` model. It runs against `moor_db` directly,
without the scheduler or VM, and checks the database's snapshot isolation.

### What it does

- Runs concurrent processes. Each issues transactions of one to `--max-txn-length` operations, each
  a read of a list property or an append of a unique integer to one. A transaction's operations run
  in one database transaction.
- Rotates keys: a key takes `--max-writes-per-key` appends, then a fresh key replaces it, so lists
  stay short. Keys are chosen with a skew, so the first few active keys see most of the contention.
- Retries a transaction on a commit conflict, up to `--max-retries` attempts. A transaction that
  never commits is recorded as `:fail`.
- Writes the history as EDN for [elle-cli](https://github.com/ligurio/elle-cli): an `:invoke` with
  `nil` reads when a transaction starts, and an `:ok` with the values read when it commits.

### Usage

#### Running directly

```bash
cargo run --bin list-append -- \
    --num-active-keys 10 \
    --num-concurrent-workloads 16 \
    --num-workload-iterations 2000 \
    --output-file workload.edn
```

Then check with elle-cli. CI builds it from a pinned commit (`ELLE_CLI_COMMIT` in
`.github/workflows/elle.yml`) and runs it on Java 21:

```bash
java -jar elle-cli-*-standalone.jar -m list-append -c snapshot-isolation workload.edn
```

#### With Docker

```bash
# From the workspace root
docker build -f Dockerfile.elle -t moor-elle-test .
docker run moor-elle-test
docker run -e NUM_ACTIVE_KEYS=5 -e NUM_CONCURRENT=8 -e NUM_ITERATIONS=500 moor-elle-test
```

`run-elle-test.sh` builds the image, runs it, and copies the history and Elle's output to
`elle-results/`. Set `CONSISTENCY_MODEL` to check another model.

### Parameters

- `--num-active-keys`: Keys open for operations at once (default: 5)
- `--max-writes-per-key`: Appends a key takes before it is replaced (default: 32)
- `--max-txn-length`: Maximum operations per transaction (default: 4)
- `--read-fraction`: Chance that an operation is a read (default: 0.5)
- `--num-concurrent-workloads`: Concurrent processes (default: 20)
- `--num-workload-iterations`: Transactions per process (default: 1000)
- `--max-retries`: Commit attempts before a transaction fails (default: 100)
- `--output-file`: Where to write the EDN history (default: workload.edn)
- `--db-path`: Database directory (default: temporary)

### Expected Result

The database provides snapshot isolation, so elle-cli with `-c snapshot-isolation` should output:

```
workload.edn	true
```

Any other result indicates a consistency bug in the transaction system. Checked with
`-c serializable`, the history usually fails with `G2-item` (write skew). Snapshot isolation allows
write skew, so that failure is expected.
