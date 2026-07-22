# Importing and Exporting Objdef Databases

## The Challenge of "Living Database" Systems

MOO belongs to a family of programming systems that are fundamentally different from typical
programming languages. Unlike traditional programs where you write code in text files and then
compile or run them, **everything in MOO lives directly in the database**. Your objects, their
properties, their code (verbs), and even the core system itself are all stored as live, interactive
data that can be modified while the system is running.

This "living database" approach draws inspiration from languages like Smalltalk (which calls this
"the image") and Self, and is incredibly powerful for building interactive worlds because:

- **Everything is persistent** - objects you create stick around forever until explicitly destroyed
- **Everything is modifiable** - you can change code, objects, and behaviors while people are using
  the system
- **Everything is interconnected** - objects can reference each other directly, creating complex
  webs of relationships

But this power comes with a significant challenge: **how do you move, share, version, or backup your
work?**

## Traditional MOO Sharing: The @dump Approach

Historically, MOO developers shared code using the `@dump` verb (provided in LambdaCore type
systems), which would generate a series of authoring commands that could be pasted into another MOO
to recreate objects. This approach worked by essentially "puppeting" the receiving user through the
same commands they would have typed to create the object manually. However, this had significant
limitations - it only worked if both MOOs had the same authoring commands available, and it wasn't
well-suited to modern development workflows involving version control, collaboration, or large-scale
code management.

> **For Traditional MOO Users**: If you're familiar with the `@dump` command, think of object
> definition files as a modern, file-based evolution of that concept, designed for today's
> development workflows with version control, text editors, and collaboration tools.

## mooR's Solution: Object Definition Files

mooR introduces "object definition files" (objdef files) to solve these traditional challenges. This
system brings MOO development into the modern world of software development by providing:

- **Human-readable files** that can be opened in any text editor
- **Version control compatibility** with Git, allowing you to track changes over time
- **Easy sharing and collaboration** through file systems and repositories
- **Bulk operations** for entire libraries, worlds, or cores
- **Cross-MOO compatibility** for sharing code between different servers

This chapter covers importing and exporting a complete database as an object definition directory.
It does not cover ordinary live editing or updating one selected object.

If you are first trying to understand how a source directory becomes a running MOO, begin with
[Starting a MOO from Objdef Source](bootstrapping-from-source.md). In particular, startup import
only creates a database when one does not already exist; it does not continually synchronize source
files with a live database.

For complete technical details about the objdef file format syntax and grammar, see the
[Object Definition File Format Reference](objdef-file-format.md).

> **Choose the operation carefully:** Importing a directory creates a new database. It does not
> update a database that already exists. To update one object, see
> [Loading and Updating Individual Objects](object-loading.md).

## Object Definition Files: A Modern Alternative to Textdumps

Traditionally, MOO databases have been stored and transferred using "textdump" files - large,
monolithic text files containing the entire database in a format that only MOO servers can easily
read. While mooR can import textdumps for compatibility with LambdaMOO/ToastStunt databases, it uses
a more modern approach for exports: **object definition directories**.

### What are Object Definition Files?

Object definition files (objdef files) are individual text files that describe MOO objects in a
human-readable format. Instead of one massive textdump file, an object definition directory
contains:

- **Individual files** for each object (e.g., `123.moo`, `456.moo`)
- **Human-readable format** that can be opened in any text editor
- **Version control friendly** structure perfect for Git repositories
- **Database-independent** format that works across different MOO server versions
- **Easily comparable** files for tracking changes over time

### Advantages Over Textdumps

**Revision Control**: Each object is its own file, making Git diffs meaningful and allowing you to
track changes to individual objects over time.

**Collaboration**: Multiple developers can work on different objects simultaneously without merge
conflicts.

**Readability**: Object definitions are formatted for human consumption, making it easy to
understand what an object does just by reading its file.

**Modularity**: You can easily extract, share, or backup individual objects or sets of objects.

**Cross-Platform**: Object definition files work identically across different MOO servers and
versions.

### Uses for Object Definition Directories

**Core Development**: The
[Cowbell core](https://github.com/timbran-project/moor/tree/main/cores/cowbell) is built entirely
from object definition files, making it easy for contributors to add features and track changes.

**Database Backups**: Create readable, version-independent backups of your entire database that will
remain usable even as mooR evolves.

**Code Sharing**: Distribute libraries, utilities, or individual objects as readable files that
others can examine, modify, and integrate into their own databases.

**Development Workflow**: Keep a core in source control, import it into a fresh development
database, and test the resulting world. Applying selected changes to an existing database is a
separate operation described in [Loading and Updating Individual Objects](object-loading.md).

**Core Migration**: Convert existing [LambdaCore](understanding-moo-cores.md) or similar databases
into object definition format for easier maintenance and customization.

## Importing and Exporting a Complete Database

### Command-Line Import and Export

mooR provides command-line tools for importing databases and exporting checkpoints as object
definition directories. This is typically how you work with cores, perform database migrations, or
create comprehensive backups.

The examples below use the separate `moor-daemon` executable. The combined `moor` server used by the
quick-start scripts accepts the same import and export options.

#### Importing Databases

To create a new database by importing source into mooR:

> **Already have a database?** These commands will not replace or update it. mooR skips startup
> import when the requested database already exists.

```bash
# Import from traditional textdump (LambdaMOO/ToastStunt format)
moor-daemon --import /path/to/backup.db --import-format textdump

# Import from objdef directory
moor-daemon --import /path/to/objdef/directory --import-format objdef
```

The import runs only if the requested database does not already exist. On later starts, mooR opens
the persistent database and skips this import, even if `--import` is still present in the command.
See [Starting a MOO from Objdef Source](bootstrapping-from-source.md) for the complete startup
lifecycle.

#### Checkpoint Exports (Always Objdef Format)

mooR exports checkpoints in objdef format only. Textdump export is not supported - use objdef for
all exports and backups:

```bash
# Configure checkpoint export directory
moor-daemon --export /path/to/export/directory
```

Each checkpoint is an objdef directory where every object becomes its own `.moo` file, numbered by
object ID or given a stable name.

> **An export is a copy:** Editing an exported `.moo` file does not change the running database.
> Exporting also does not overwrite the source directory that was used for the original import.

#### Converting Textdump to Objdef

The `moorc` compiler tool is the recommended way to convert a LambdaMOO textdump to objdef format:

```bash
# Convert textdump to objdef directory
moorc --src-textdump old_database.db --out-objdef-dir new_objdef_dir
```

This processes the import and export immediately without running a live server.

> **Note**: When importing textdumps, legacy type constants (`INT`, `OBJ`, `STR`, etc.) are
> automatically converted to the new `TYPE_*` format. No special flags are needed for textdump
> imports.

Alternatively, if you're already running a daemon, you can import the textdump and let checkpoints
produce the objdef export:

```bash
# Import textdump; exports occur at checkpoint intervals
moor-daemon --import old_database.db --import-format textdump \
            --export new_objdef_dir \
            --checkpoint-interval-seconds 60
```

#### Automatic Timestamped Exports

When you configure an export path and a checkpoint interval, mooR automatically creates timestamped
exports. Each export is a directory with a unique name based on Unix time, so it does not overwrite
an earlier checkpoint:

```bash
# Configure automatic exports with checkpoint interval
moor-daemon --export /path/to/backups \
            --checkpoint-interval-seconds 3600  # Export every hour
```

This creates directories like the following. The `.moo` suffix belongs to each checkpoint directory;
the individual objdef files are inside it.

```
/path/to/backups/
├── checkpoint-1704067200.moo/        # Exported at 2024-01-01 00:00:00
├── checkpoint-1704070800.moo/        # Exported at 2024-01-01 01:00:00
├── checkpoint-1704074400.moo/        # Exported at 2024-01-01 02:00:00
└── ...
```

The checkpoint interval controls how frequently these automatic exports occur. This provides:

- **Rolling backups** that don't overwrite each other
- **Point-in-time recovery** to any checkpoint moment
- **Automatic versioning** without manual intervention
- **Safe concurrent operation** using `.in-progress` temporary files

### Directory Structure

An example object definition directory contains:

```
objdef_directory/
├── constants.moo   # Special file with symbolic names for objects
├── sysobj.moo     # System object (#0)
├── root.moo       # Root class (#1)
├── wiz.moo        # Wizard object (#3)
├── thing.moo      # Generic thing prototype ($thing)
├── room.moo       # Room prototype ($room)
├── player.moo     # Player prototype ($player)
├── 123.moo        # Your custom object (#123)
├── 456.moo        # Another object (#456)
└── ...
```

#### The Special `constants.moo` File

The `constants.moo` file is like a set of preprocessor defines that give human-readable names to
important objects. Instead of remembering that the generic thing prototype is object #789, you can
refer to it as `thing`. This file contains mappings like:

```moo
// Example contents of constants.moo
define THING = #789;
define ROOM = #456;
define PLAYER = #123;
define WIZARD = #3;
define ROOT_ROOM = #2;
define SYSOBJ = #0;
```

When you import an objdef directory, these constants become available during compilation, so verb
code can use readable names instead of magic numbers.

#### Object Identity and Export Names

mooR uses object metadata called `import_export_id` to determine how objects are named in exports
and referenced in `constants.moo`. This metadata establishes a stable identity for objects across
import/export cycles.

**How It Works:**

The system works differently depending on whether objects have `import_export_id` metadata:

**During Export:**

If objects have `import_export_id` metadata, mooR uses those values for filenames and constants:

```moo
object #789 [
  import_export_id -> "thing"
]

// Exports as:
thing.moo

// constants.moo includes:
define THING = #789;
```

If objects **don't** have `import_export_id` metadata, mooR falls back to legacy `import_export_id`
properties. If neither metadata nor legacy properties exist, it can use the #0 heuristic for
backward compatibility:

1. **Examines system object (#0)**: Looks for properties that directly reference other objects
2. **Generates constants**: Creates symbolic names from those property names (e.g., `thing`, `room`,
   `player`)
3. **Uses those names**: Exports objects using the discovered names

For example, if #0 has these properties:

```moo
#0.thing = #789      // Generic thing prototype
#0.room = #456       // Room prototype
#0.player = #123     // Player prototype
```

Objects export as:

- Object #789 → `thing.moo` (derived from #0.thing)
- Object #456 → `room.moo` (derived from #0.room)
- Object #123 → `player.moo` (derived from #0.player)

**During Import:**

When importing an objdef created with the #0 heuristic (no `import_export_id` metadata or legacy
properties), mooR automatically creates object metadata in the database:

```moo
object_metadata(#789, 'import_export_id) == "thing"
object_metadata(#456, 'import_export_id) == "room"
object_metadata(#123, 'import_export_id) == "player"
```

This ensures that **subsequent exports** will use the `import_export_id` metadata directly,
maintaining stable filenames across export cycles without needing to analyze #0 properties again.

#### Benefits of This System

**Human Readability**: Files are named `player.moo` instead of `123.moo`, making the directory
structure self-documenting.

**Object Number Independence**: Code can refer to `PLAYER` instead of hardcoding #123, making it
portable between databases.

**Stable Identity**: Objects maintain their identity across import/export cycles, making version
control meaningful.

**Automatic Maintenance**: The first import automatically creates `import_export_id` metadata, and
subsequent exports just read it.

**Backward Compatibility**: Imports from legacy textdumps or objdefs without `import_export_id`
metadata work seamlessly using legacy property fallback and the #0 heuristic.

#### The Special `sysobj.moo` File

Object #0 (the system object) is always exported as `sysobj.moo`, never as `0.moo`. This file
typically contains properties that define the core object references for your MOO:

```moo
// Example properties in sysobj.moo
property thing (owner: WIZARD, flags: "rc") = THING;
property room (owner: WIZARD, flags: "rc") = ROOM;
property player (owner: WIZARD, flags: "rc") = PLAYER;
```

**Note**: While these #0 properties provide a convenient way to access core objects, they are not
required for the import/export system. The `import_export_id` metadata on each object controls
export naming, not references from #0.

#### Creating New Objects with Stable Names

When creating objects that you want to have stable names across import/export cycles, you need to
give them `import_export_id` metadata:

**Step 1: Choose an Object Number** Pick an unused object ID that won't conflict with existing
objects. Check your current database to see what numbers are in use:

```bash
# Look at existing objdef directory to see what numbers are taken
ls objdef_directory/*.moo | grep -E '[0-9]+\.moo$'
```

**Step 2: Add the Constant Definition** Add your new object to `constants.moo`:

```moo
// In constants.moo
define MY_NEW_OBJECT = #12345;
```

**Step 3: Create the Object File** Create your object file with the desired name and include the
`import_export_id` metadata:

```moo
// File: my_new_object.moo
object MY_NEW_OBJECT [
  import_export_id -> "my_new_object"
]
  name: "My New Object"
  parent: THING
  owner: WIZARD

  // ... other properties and verbs
endobject
```

**Step 4: Maintain the Pattern** The `import_export_id` metadata ensures stable filenames across
import/export cycles. Without this metadata, the object will be exported as `12345.moo` (using its
object number).

#### Example: Adding a New Utility Object

Let's say you want to add a new string manipulation utility object:

1. **Choose ID**: Pick #98765 (assuming it's unused)

2. **Update `constants.moo`**:
   ```moo
   define STRING_FORMATTER = #98765;
   ```

3. **Create `string_formatter.moo`**:
   ```moo
   object STRING_FORMATTER [
     import_export_id -> "string_formatter"
   ]
     name: "String Formatting Utilities"
     parent: THING
     owner: WIZARD
     flags: "upw"

     // ... properties and verbs would go here
   endobject
   ```

4. **Import and Export Test**: After importing this objdef directory and then exporting it again,
   the object will continue to be exported as `string_formatter.moo` because it has an
   `import_export_id` metadata value.

#### Common Mistakes to Avoid

- **Wrong filename**: The filename should match the `import_export_id` value
- **Missing import_export_id**: Without this metadata, exports use object number (e.g., `98765.moo`)
- **Case mismatch**: Filenames are lowercase - use `"string_formatter"` not `"STRING_FORMATTER"`
- **Inconsistent naming**: Ensure constants.moo, filename, and import_export_id all match

Each `.moo` file is human-readable and contains the complete definition of that object, including:

- Object metadata (parent, location, owner, flags)
- All properties with values and permissions
- All verbs with code and permissions
- Access to compilation constants from `constants.moo`

### Use Cases for Directory Operations

**Core Development**: Import source into a fresh development database, test it, and export the live
database when you need to bring in-MOO changes back to editable files. Import and export do not keep
the two sides synchronized automatically.

**Database Migration**: Move databases between different mooR versions or even different MOO server
implementations by exporting as objdef.

**Backup and Restore**: Create human-readable backups that remain valid even as the server software
evolves.

**Collaboration**: Share entire databases or core systems through version control systems like Git.

## Loading or Updating Individual Objects

The directory import described above creates a complete database. It is not the usual tool for
changing one object in a database that already exists.

For selected updates, mooR also provides `dump_object`, `load_object`, and `reload_object`. These
operations are explicit: mooR does not watch objdef files or automatically apply edits made on disk.
Reloading can also remove properties or verbs that are absent from the supplied definition.

See [Loading and Updating Individual Objects](object-loading.md) before using these operations.
