# moor-daemon

TLDR: Top-level server/runtime assembly crate for the mooR daemon binaries.

Downstream uses:

- Produces the daemon entry points that wire together the database, scheduler, VM, runtime services,
  workers, and host listeners.
- No workspace crate should depend on this as a library boundary; it is the process assembly layer.
- Host protocol implementations belong in `moor-telnet-host`, `moor-web-host`, and related host
  crates rather than in daemon internals.
