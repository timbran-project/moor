# moor-kernel

TLDR: Runtime semantics layer that combines the scheduler, task execution, builtin functions, VM
integration, permissions, and database transactions.

Downstream uses:

- Used by `moor-daemon` to run the live world.
- Used by admin, compiler, and testing tools that need to execute MOO code against a world state.
- Keep process wiring and network host concerns outside this crate; those belong in daemon and host
  crates.
