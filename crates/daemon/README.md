# moor-daemon

TLDR: Split-process daemon runtime crate for the mooR database, scheduler, VM, workers, and
ZeroMQ/FlatBuffer RPC server.

Downstream uses:

- Produces the `moor-daemon` binary for deployments where hosts and workers run as separate
  processes.
- Provides the daemon runtime assembly used by `moor-server`, without depending on telnet/web host
  crates or Tokio in its normal dependency graph.
- Owns the database, scheduler, VM, event log, connection registry, worker routing, and ZMQ/RPC
  transport.
- Host protocol implementations belong in `moor-telnet-host`, `moor-web-host`, and related host
  crates rather than in daemon internals.
