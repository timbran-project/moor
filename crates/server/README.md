# moor-server

TLDR: Single-process server binary for running mooR without separate daemon, host, and worker
processes.

Downstream uses:

- Produces the `moor` binary, which starts the daemon runtime, telnet host, web host, and selected
  embedded workers in one process.
- Owns local in-process runtime and worker service adapters used by the single-process binary.
- Depends on `moor-daemon` for the core runtime/database/scheduler assembly, but keeps async
  host-facing orchestration out of the split-process daemon crate.
- Split deployments should use `moor-daemon` plus standalone host/worker crates instead.
