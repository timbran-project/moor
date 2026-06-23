# moor-schema-macros

TLDR: Procedural macros for reducing schema conversion boilerplate.

Downstream uses:

- Used by `moor-schema` to derive or generate repetitive FlatBuffer conversion code.
- Should remain schema-specific macro support.
- Runtime contracts, transport logic, and persistence behavior belong in the crates that consume the
  schema.
