# Starting a MOO from Objdef Source

A running MOO keeps its objects, properties, and programs in a persistent database. But a new MOO
can begin as a directory of ordinary text files that you can read, edit, and keep in version
control. mooR calls these **object definition files**, or **objdef files**.

The important point is that mooR does not read those source files every time it starts. It imports
them once to create the database. After that, the database is the live world.

## Source Files and the Live Database

It helps to think of the source directory as the plans for a house and the database as the house
that was built from them:

- The **objdef source directory** contains human-readable `.moo` files. It is convenient for text
  editors, sharing, and version control.
- The **database** contains the world that the server actually runs. It includes objects, property
  values, compiled verb programs, and changes made by people inside the MOO.

They can describe the same world, but they are not kept synchronized automatically.

## What Happens on the First Start

When you start mooR with `--import` and the requested database does not exist yet, mooR:

1. Creates a new, empty database.
2. Reads the objdef files from the import directory.
3. Creates the objects, properties, and verbs described by those files.
4. Compiles the MOO code in each verb.
5. Saves the result in the new database.
6. Starts the server using that database.

```text
objdef source directory ---- first import and compilation ----> persistent database ----> running MOO
```

For example, this starts a new database using the Cowbell core source included with mooR:

```bash
moor ./moor-data \
    --db world.db \
    --import cores/cowbell/src \
    --import-format objdef \
    --export ./exports
```

Here, `cores/cowbell/src` is the source directory and `./moor-data/world.db` is the database created
from it.

The provided quick-start scripts do the same thing for you. For example,
`./scripts/start-moor-cowbell.sh` selects `cores/cowbell/src` and stores the resulting database
under `run-cowbell/moor-data/`.

## What Happens on Later Starts

When mooR finds that the database already exists, it opens that database and skips the import. The
server can therefore restart without rebuilding the world from source:

```text
persistent database -------------------------------------------> running MOO
```

The start command may still contain `--import`. This is normal. The option tells mooR what to use if
it needs to create the database; it does not replace an existing database.

This also means that editing a `.moo` file in the source directory does **not** change an existing
database, even after restarting the server. mooR does not watch the source directory for changes.

## Bringing Source Changes into a MOO

There are several ways to work, depending on what you are trying to do.

### Rebuild a Development World

During core development, you can create a fresh database and import the complete objdef directory
again. This gives you a world containing exactly what the source describes.

Creating a fresh database discards changes that exist only in the old database. Keep the old
database or export it first if those changes matter.

### Change the Live World

MOO is a live programming environment. Programmers can create objects and edit properties and verb
code from inside the running system. Those changes are saved directly in the database and survive
restarts. They do not automatically change the original source files.

### Load or Reload Particular Objects

mooR can explicitly load an objdef into a live database or replace an existing object from an
objdef. This is useful when you want to apply a selected source change without rebuilding the whole
world. See [Loading and Updating Individual Objects](object-loading.md) for the available loading
tools and their conflict-handling options.

## Exporting the Live World

Importing and exporting go in opposite directions:

```text
objdef source ---- import ----> database
database -------- export ----> objdef files
```

If an export directory is configured, mooR can write checkpoints of the live database as objdef
files. An export includes changes made inside the MOO, so it can be used for backup, inspection, or
bringing live changes back into a source-controlled directory.

An export does not overwrite the original import directory. Import sources and checkpoint exports
are separate paths unless you deliberately copy or merge files between them.

## How This Differs from LambdaMOO

Classic LambdaMOO normally started from a textdump: one large database dump intended for the server
to read and write. It did not have mooR's directory of individual, human-readable objdef source
files.

mooR can still import a LambdaMOO textdump, but objdef directories make it practical to maintain a
core as ordinary source files. In both cases, the import creates the persistent database used by
later server starts.

## Where to Go Next

- [Object Definition File Format Reference](objdef-file-format.md) describes the contents of `.moo`
  files.
- [Importing and Exporting Objdef Databases](object-packaging.md) covers complete databases.
- [Loading and Updating Individual Objects](object-loading.md) covers selected object definitions.
- [Server Configuration](server-configuration.md#importexport-configuration) lists the relevant
  server options.
- [Emergency Medical Hologram Tool](moor-emh-tool.md) can load or reload objdef files while the
  regular server is stopped.
