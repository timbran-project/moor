# lambdamoo-harness

TLDR: Optional comparative test and benchmark harness around the original LambdaMOO C
implementation.

Downstream uses:

- Leaf testing crate; no production crate should depend on it.
- Used manually to compare mooR behavior and performance with LambdaMOO after fetching external
  sources.

The embedded harness requires both the `embedded-lambdamoo` feature and the `LAMBDAMOO_SRC_DIR`
environment variable. Without either, the Rust library has no harness API and does not compile or
link LambdaMOO. Workspace builds, tests, and Clippy work without external C sources, including with
`--all-features`.

With the feature alone, the benchmark executable reports that LambdaMOO is disabled and exits with
an error. With both settings, an invalid or unconfigured source path fails the build.

## Setup

1. Run the setup script to fetch LambdaMOO sources:

   ```bash
   ./crates/testing/lambdamoo-harness/setup-lambdamoo.sh
   ```

   This will:
   - Clone `wrog/lambdamoo` from GitHub (pinned to a specific commit)
   - Apply patches from `patches/` for modern compiler compatibility
   - Run `configure` to generate `config.h`

2. Build the harness:

   ```bash
   LAMBDAMOO_SRC_DIR="$PWD/lambdamoo" cargo build -p lambdamoo-harness --features embedded-lambdamoo
   ```

`LAMBDAMOO_SRC_DIR` can name another prepared checkout. Relative paths start at the mooR workspace
root. The directory must contain `server.c`, `config.h`, and `version_src.h`. The setup script
prepares these files in `lambdamoo/`. An enabled build requires a C compiler and Bison.

To check the enabled harness, run:

```bash
LAMBDAMOO_SRC_DIR="$PWD/lambdamoo" cargo test -p lambdamoo-harness --features embedded-lambdamoo
```

## Usage

### Load Testing

The `lambdamoo-load-test` binary measures verb dispatch performance:

```bash
# Basic verb dispatch benchmark
LAMBDAMOO_SRC_DIR="$PWD/lambdamoo" cargo run --release -p lambdamoo-harness \
    --features embedded-lambdamoo --bin lambdamoo-load-test -- \
    --db-path lambdamoo/Minimal.db \
    --num-invocations 100 \
    --num-verb-iterations 1000

# Opcode throughput benchmark (raw interpreter speed)
LAMBDAMOO_SRC_DIR="$PWD/lambdamoo" cargo run --release -p lambdamoo-harness \
    --features embedded-lambdamoo --bin lambdamoo-load-test -- \
    --db-path lambdamoo/Minimal.db \
    --opcode-mode \
    --loop-iterations 100000
```

### Rust API

The `LambdaMooHarness` struct provides a safe Rust wrapper:

```rust
use lambdamoo_harness::LambdaMooHarness;

let harness = LambdaMooHarness::new(Path::new("path/to/db.db"))?;
let conn = harness.create_connection(player_objid)?;
let output = harness.execute_command(&conn, "look")?;
```

## What's Included

- `LambdaMooHarness` - Rust wrapper for initializing and interacting with LambdaMOO
- `lambdamoo-load-test` - Binary for comparative load testing against mooR
- `patches/` - Patches for modern glibc compatibility and build configuration
- `src/net_harness.c` - Custom network layer that captures output for testing

## License Note

**LambdaMOO is NOT GPL.** It is licensed under the
[Xerox License](https://spdx.org/licenses/Xerox.html), which is permissive but requires compliance
with US export control laws. This makes it GPL-incompatible.

This harness is a development/testing tool kept separate from the main mooR distribution. The
LambdaMOO sources are not included in the moor repository and must be fetched separately using the
setup script.
