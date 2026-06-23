# moor-var

TLDR: Core MOO value representation, including `Var`, object ids, symbols, errors, lists, maps,
flyweights, and related data structures.

Downstream uses:

- Used by almost every crate that needs to represent MOO values or object references.
- Provides the low-level data model under `moor-common`, compiler, runtime, database, and host
  crates.
- Keep this crate free of database, scheduler, transport, and host concerns.
