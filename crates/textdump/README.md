# moor-textdump

TLDR: LambdaMOO-compatible textdump parser and writer.

Downstream uses:

- Used by daemon import/export flows and developer tools.
- Used by `moor-objdef` and `moor-kernel` tests where legacy textdump compatibility matters.
- Keep textdump format handling here; directory-based source layout belongs in `moor-objdef`.
