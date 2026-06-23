# moor-compiler

TLDR: Parser, compiler, unparser, and decompiler support for the MOO language.

Downstream uses:

- Used by `moor-kernel` and `moor-vm` to compile and execute user-authored code.
- Used by import/export and tooling crates such as `moor-objdef`, `moor-textdump`, `moorc`, and
  `moor-emh`.
- Used by host-facing crates when they need compile/eval surfaces, but runtime scheduling and
  persistence stay outside this crate.
