# moor-common

TLDR: Shared model types and utilities above raw MOO values, including object references, events,
command matching, configuration, tracing, and common world-state contracts.

Downstream uses:

- Used by most workspace crates that need common contracts without depending on the database,
  scheduler, hosts, or transport implementations.
- Depends only on `moor-var` among local crates, so it sits low in the dependency graph.
- Keep process assembly, persistence, VM execution, and host protocol logic out of this crate.
