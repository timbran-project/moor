# Native Verbs

A native verb is a verb whose body is a function in a native library rather than MOO code. Calling
it runs the function at native speed, with the verb's arguments, and returns its value like any
other verb. Native verbs suit heavy computation, such as generating terrain or decoding a format,
that would be slow in MOO.

Native verbs are off unless the server's administrator lists native libraries when starting the
daemon. The daemon loads every listed library at startup, and only those libraries' functions can be
bound to verbs. Only wizards can bind a verb to a native function.

## What a native verb can do

A native verb runs as its owner, as a MOO verb does, and appears in `callers()` like one. It can:

- read the values it was called with, and make new ones, through the functions the daemon gives it;
- read and change the world: an object's parent, children, ancestors, location, contents, owner,
  name and flags, its properties and its metadata, and whether it has a verb. Each of these is
  checked against the verb owner's permissions, as the matching builtin is;
- call a verb or a builtin, and carry on with its result.

What changes the world through MOO's own rules, such as `create()`, `move()` and `recycle()` with
their `:initialize`, `:accept` and `:exitfunc` verbs, and what sends output, such as `notify()`, a
native verb does by calling the builtin.

A native library runs inside the daemon with its full access, and a crash in it stops the server.
Nothing can interrupt native code while it runs, so a function that never returns blocks a task
worker. Each request a native verb makes of the world, and each verb or builtin it calls, counts as
a tick. When a step ends, the task's tick and time limits are checked before the step's result takes
effect, and a task past either is aborted. List only libraries you trust.

## Steps and calls

A native verb runs in steps. It is first called at step 0, and each step ends one of three ways: it
returns a value, it raises an error, or it asks to call a verb or builtin. When it calls out, it
names the step to resume at and a value to carry. The callee then runs like any other call, and may
itself suspend or read input, and the native verb is called again at the step it named, with that
value and the callee's result.

Because what a native verb carries between steps is a value, a task suspended in a verb that a
native verb called keeps the native verb's frame like any other, and survives a restart.

An error raised by a verb or builtin the native verb called passes through the native verb to its
caller. When the native verb has no `d` flag, an error in a call it makes becomes that call's result
instead, as in MOO code.

A native verb's own error is raised in the verb that called it.

A verb a native verb calls sees the command's parsing variables, `argstr`, `dobj`, `dobjstr`,
`prepstr`, `iobj` and `iobjstr`, as it would if a MOO verb had called it: the native verb carries
them from its own caller, and keeps them across suspension.

## Values

An integer, float, boolean or object passes to and from a library as itself. Any other value, such
as a string, list or map, stays in the daemon: the library holds a reference to it, valid until the
step ends, and reads it and makes new values through functions the daemon passes it. A library never
shares the daemon's layout of values in memory, so one built with another compiler or language
works. Lists of numbers are read and made in one call, without a reference per item.

To keep a reference longer, such as to a large table it has decoded into its own structures, a
library retains it and releases it when done. The daemon can say whether two values are the very
same, not just equal. A property read twice while it is unchanged gives the same value, so a library
that keeps what it decoded, with the value it decoded it from, can tell cheaply whether its decoding
still holds.

A retained reference does not keep an anonymous object it refers to alive.

## Loading libraries

Name each library with `--native-library`, once per library:

```bash
moor-daemon --native-library /opt/moor/lib/libterrain.so ...
```

Or list them in the configuration file:

```yaml
runtime:
  native_libraries:
    - /opt/moor/lib/libterrain.so
```

If a library cannot be loaded, was built for a different native verb interface, or has the same name
as another, the daemon does not start. The set of libraries is fixed until the daemon restarts, and
replacing a library also needs a restart.

## Binding a verb

A library declares its own name and the names of its functions. A verb names both:

```moo
set_verb_native(#123, "column", "terrain", "column");
verb_native(#123, "column")    =>  {"terrain", "column"}
native_libraries()             =>  {{"terrain", "0.1.0", {"column", "fill"}}}
```

The binding is stored in the database, not the library's file name, so a database moves between
machines that install the same libraries. A verb whose library is not loaded raises `E_VERBNF` when
called. `verb_code()` raises `E_INVARG` for a native verb, which has no MOO code; setting its code
with `set_verb_code()` makes it a MOO verb again.

In objdef files, a native verb is one line, with `native` in place of `verb` or `method`:

```
native column owner: #2 "terrain" "column"
```

Only a wizard's `load_object()` and `reload_object()`, the daemon's own import, and wizards applying
`@changes` may define native verbs.

## Licensing

The `moor-native-verb` crate and its header, which a library uses, are licensed under the GNU Lesser
General Public License, version 3 or later. The mooR Native Verb Library Exception, in the
repository's `NATIVE-VERB-EXCEPTION.md`, permits a library that mooR loads only through the native
verb interface, and that uses no other part of mooR, to be distributed under terms of its author's
choice. mooR itself remains under the GNU Affero General Public License.

## Writing a library

The interface is C, defined in `crates/native-verb/include/moor_native.h`. A library exports
`moor_native_library`, which the daemon calls once with its table of functions; the library keeps
the table and returns its descriptor. Each function the daemon gives that can fail returns a status:
on `MOOR_ERROR` an error is pending, and returning `MOOR_ERROR` from the verb raises it; on
`MOOR_CONFLICT` the transaction conflicted, and the verb returns `MOOR_CONFLICT` so the task is
retried. In C:

```c
#include "moor_native.h"

static const moor_api *api;

static moor_status sum(moor_call *call) {
    int64_t total = 0;
    for (size_t i = 0; i < api->arg_count(call); i++) {
        moor_value arg;
        moor_status status = api->arg(call, i, &arg);
        if (status != MOOR_OK) return status;
        if (arg.type != MOOR_TYPE_INT) {
            return api->raise(call, "E_TYPE", 6, "sum adds integers", 17);
        }
        total += arg.as.i;
    }
    return api->ret(call, moor_int(total));
}

static const moor_function functions[] = {{"sum", sum}};
static const moor_library library = {MOOR_NATIVE_ABI, "example", "1.0.0", functions, 1};

const moor_library *moor_native_library(const moor_api *given) {
    if (given->abi_version != MOOR_NATIVE_ABI || given->size < sizeof(moor_api)) return 0;
    api = given;
    return &library;
}
```

In Rust, depend on the `moor-native-verb` crate, build a `cdylib`, and declare the functions. A
`Value` is a scalar or a `Ref` to a value the daemon holds; a failing call returns `Err`, so `?`
passes errors on:

```rust
use moor_native_verb::{Call, Done, Result};

fn sum(call: &Call) -> Result<Done> {
    let mut total = 0;
    for arg in call.arg_values()? {
        total += arg.int(call)?;
    }
    Ok(call.ret(total))
}

moor_native_verb::native_verb_library! {
    name: "example",
    version: "1.0.0",
    functions: { "sum" => sum },
}
```

A verb that calls out ends its step with `call.call_verb(...)` or `call.call_builtin(...)`, and
reads `call.step()`, `call.state()` and `call.result()` when it resumes. The macro catches panics,
so a panicking function raises an error instead of unwinding into the daemon. The crate's
`sum_library` example is a complete library.
