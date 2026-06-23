This is a simple "core" which shows how to use the objdefdir/object definition import format, which
is a readable, editable text import format for distribution of objects and MOO cores.

It corresponds basically to Minimal.db from LambdaMOO, having only a single player with an eval
verb.

If there is no existing binary database, the daemon can import this core from `cores/minimal-core/src`.
The Makefile in this directory builds a normalized objdef dump into `gen.objdir`:

```sh
make -C cores/minimal-core
```

TODO: More documentation on the format
