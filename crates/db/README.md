# moor-db

TLDR: Transactional persistent world-state storage for objects, properties, verbs, tasks, and
related database state.

Downstream uses:

- Used by `moor-kernel` and `moor-daemon` for runtime persistence.
- Used by import/export and tools such as `moor-textdump`, `moor-objdef`, `moorc`, and the load
  testing crates.
- Owns the database layer; scheduler policy, VM semantics, and network protocol handling belong
  elsewhere.
