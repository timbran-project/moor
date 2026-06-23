# moor-vm

TLDR: Virtual-machine execution machinery for compiled MOO programs.

Downstream uses:

- Used by `moor-kernel` to run compiled tasks.
- Depends on compiler and value/common types, but should not own database transactions, scheduling
  policy, or network protocol behavior.
- Keep opcode execution and VM state here; task orchestration belongs in `moor-kernel`.
