# moor-builtin-docs-macro

TLDR: Procedural macro support for extracting builtin-function documentation at compile time.

Downstream uses:

- Used by `moor-kernel` when defining VM builtin functions.
- Keeps builtin documentation attached to the Rust definitions that implement those builtins.
- Runtime builtin behavior belongs in `moor-kernel`; this crate should stay macro-only.
