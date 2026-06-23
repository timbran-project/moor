# moor-objdef

TLDR: Directory-based object-definition import/export support for working with MOO objects as source
files.

Downstream uses:

- Used by daemon startup/import flows, developer tools, and kernel-related tests.
- Bridges compiler, textdump, and database representations when loading or materializing object
  definitions.
- Keep source-tree object layout logic here; generic textdump parsing belongs in `moor-textdump`.
