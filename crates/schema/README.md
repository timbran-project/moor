# moor-schema

TLDR: FlatBuffer schema bindings and conversion helpers for wire and persistence-facing data.

Downstream uses:

- Used by runtime API, daemon, database, kernel, host, and client crates that serialize shared
  schema types.
- Depends on `moor-schema-macros` for schema conversion support.
- Keep schema representation and conversion code here; runtime behavior belongs in higher-level
  crates.
