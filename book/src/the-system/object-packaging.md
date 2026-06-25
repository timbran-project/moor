# Object Definition Files and Object Import/Export

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

This chapter covers how to work with object definition directories as an alternative to traditional
textdump files, and the `dump_object` and `load_object` functions that let you work with individual
object definitions programmatically.

For complete technical details about the objdef file format syntax and grammar, see the
[Object Definition File Format Reference](objdef-file-format.md).

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

**Core Development**: The [cowbell core](https://github.com/rdaum/cowbell/) is built entirely from
object definition files, making it easy for contributors to add features and track changes.

**Database Backups**: Create readable, version-independent backups of your entire database that will
remain usable even as mooR evolves.

**Code Sharing**: Distribute libraries, utilities, or individual objects as readable files that
others can examine, modify, and integrate into their own databases.

**Development Workflow**: Build and test your MOO objects in a development environment, then deploy
them to production by loading the object definition files.

**Core Migration**: Convert existing [LambdaCore](understanding-moo-cores.md) or similar databases
into object definition format for easier maintenance and customization.

## Working with Object Definition Directories

### Command-Line Import and Export

mooR provides command-line tools for importing databases and exporting checkpoints as object
definition directories. This is typically how you work with cores, perform database migrations, or
create comprehensive backups.

#### Importing Databases

To import a database into mooR:

```bash
# Import from traditional textdump (LambdaMOO/ToastStunt format)
moor-daemon --import /path/to/backup.db --import-format textdump

# Import from objdef directory
moor-daemon --import /path/to/objdef/directory --import-format objdef
```

#### Checkpoint Exports (Always Objdef Format)

mooR exports checkpoints in objdef format only. Textdump export is not supported - use objdef for
all exports and backups:

```bash
# Configure checkpoint export directory
moor-daemon --export /path/to/export/directory
```

This creates a directory structure where each object becomes its own `.moo` file, numbered by object
ID (e.g., `1.moo`, `2.moo`, `123.moo`).

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

When you configure an export path, mooR automatically creates timestamped exports during database
checkpoints. Each export gets a unique filename based on Unix timestamp to prevent overwriting
previous backups:

```bash
# Configure automatic exports with checkpoint interval
moor-daemon --export /path/to/backups \
            --checkpoint-interval-seconds 3600  # Export every hour
```

This creates files like:

```
/path/to/backups/
├── checkpoint-1704067200.moo         # Exported at 2024-01-01 00:00:00
├── checkpoint-1704070800.moo         # Exported at 2024-01-01 01:00:00
├── checkpoint-1704074400.moo         # Exported at 2024-01-01 02:00:00
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

**Core Development**: Export a working core as objdef, modify objects in your text editor, and
re-import to test changes.

**Database Migration**: Move databases between different mooR versions or even different MOO server
implementations by exporting as objdef.

**Backup and Restore**: Create human-readable backups that remain valid even as the server software
evolves.

**Collaboration**: Share entire databases or core systems through version control systems like Git.

## Working with Individual Objects

While command-line import/export handles entire databases, mooR also provides built-in functions for
working with individual objects from within the MOO itself. This enables more surgical operations
like cherry-picking specific objects, sharing individual utilities, or performing targeted updates.

Within object definition files and directories, each object is described as a structured text
representation that includes all its properties, verbs, and metadata. When you work with individual
objects using `dump_object` and `load_object`, you're working with pieces of this broader object
definition format.

When you dump an object, you get a list of strings that completely describe that object in the same
format used in object definition files. When you load that definition back, mooR applies it
immediately. Use `preview_objdef_changes` first if you need to review the proposed changes.

## Basic Usage

### Dumping Objects

The `dump_object` function converts any object into its text representation:

```moo
// Dump a single object
definition = dump_object(#123);
// Returns a list of strings representing the object

// Save the definition for later use
player.my_object_backup = dump_object($my_widget);
```

### Loading Objects

The `load_object` function recreates objects from their text definitions:

```moo
// Load a simple object using the object ID from the dump
new_obj = load_object(definition);

// Create a new object with next available ID (ignoring dump's ID)
new_obj = load_object(definition, [], 0);

// Update an existing object
new_obj = load_object(definition, [], #456);

// Create an anonymous object
new_obj = load_object(definition, [], 1);

// Create a UUID-based object
new_obj = load_object(definition, [], 2);

// Load with options and object kind
new_obj = load_object(definition, [
    `constants -> [`MY_CONSTANT -> "value"]  // Set compilation constants
], 0);  // Create new with next ID
```

### Reloading Objects

The `reload_object` function replaces an existing object with a new definition from objdef format.
Properties and verbs not present in the new definition are removed.

```
obj reload_object(list object_lines [, map constants] [, obj target])
```

- `object_lines`: A list of strings containing the objdef text for the object.
- `constants`: (Optional) Map or alist of constant substitutions available during compilation.
- `target`: (Optional) Object to replace. When omitted, uses the object ID from the objdef
  definition.

`reload_object` is wizard-only and returns the loaded object ID.

### Parsing Constants

```
map parse_objdef_constants(str|list lines)
```

Parses constants from objdef content and returns a map of constant name to value. This is useful
when you want to extract `constants.moo` definitions or validate constants before calling
`load_object`.

Raises `E_INVARG` with a formatted error if parsing or compilation fails.

### `preview_objdef_changes`

Sometimes you do not want to load an objdef immediately. You may have a new version of an object, or
a small group of related objects, and want to ask:

- Would this create new objects?
- Would it change existing objects?
- Would it overwrite local edits?
- Does the objdef refer to the same named objects that this database uses?

`preview_objdef_changes` answers those questions without changing the database.

```moo
map preview_objdef_changes(list definitions [, map options])
```

The result is a **change report**: a summary of what would happen if these objdefs were loaded. It
is not a saved update and it does not apply anything by itself.

`definitions` is a list of objdef inputs. Each input can be either one string containing objdef text
or a list of objdef lines:

```moo
cl = preview_objdef_changes({
  {
    "object #10",
    "  name: \"New Room\"",
    "  owner: #0",
    "  parent: #-1",
    "  location: #-1",
    "endobject"
  }
});
```

The result is a map. The most important fields are:

- `"ok"`: true if mooR sees no problem with the proposed changes.
- `"objects"`: one summary for each object mentioned by the objdefs.
- `"conflicts"`: changes that need a person or package manager to choose what to do.
- `"diagnostics"`: problems found while analyzing the objdefs, such as invalid objdef text or a
  constant name that points at different objects locally and in the incoming objdefs.

The analysis treats all incoming objdefs as one proposed object graph. That means a child can refer
to a parent created by another incoming objdef, and a property override can refer to a property
definition introduced by an incoming ancestor. It also means graph problems, such as missing parent
objects, parent cycles, or property-name conflicts caused by a parent change, are reported before
anything is loaded.

Each object summary has a `"status"`:

- `"create"`: the object does not exist yet, so loading would create it.
- `"clean"`: the object exists and already matches the incoming definition.
- `"patch"`: the object exists and would be changed.
- `"unsafe_target"`: the object number already exists, but mooR does not have evidence that it is
  the same object the objdef is meant to update.
- `"conflict"`: both the local object and the incoming objdef appear to have changed from an older
  recorded version.
- `"delete_candidate"`: an object from a previous object set is missing from the incoming objdefs.

The `"unsafe_target"` status is pretty cautious. If incoming objdef text says `object #10`, but this
database already has a different local `#10`, blindly loading the objdef could damage local work. To
treat an existing object as a safe update target, mooR needs some evidence, such as matching
`import_export_id` metadata, matching constants, or membership in a supplied base manifest.

Options include:

- `"constants"`: constants to use while parsing the incoming objdefs.
- `"local_constants"`: constants from the current database. These let mooR notice when the same
  constant name points at different objects in the incoming objdefs and the local database.
- `"base_manifest"`: the objects that belonged to the older version of the object set. This is how
  mooR can report deletion candidates. Without a base manifest, absence from the incoming objdefs is
  not treated as deletion.
- `"include_unchanged"`: include `"clean"` objects in the report.

The remaining base metadata options are for update tools that remember the older version they last
installed. A **base hash** is a short fingerprint of that older version of an object attribute,
property, verb, or metadata entry. With base hashes, mooR can tell the difference between:

- a clean patch, where local state still matches the old version and the incoming objdef has the
  only change
- a conflict, where local state changed and the incoming objdef changed too

Those options are:

- `"base_metadata"`: true to read recorded base hashes from entity metadata.
- `"base_metadata_prefix"`: prefix for base hash metadata keys, defaulting to `"base_"`.
- `"write_base_metadata"`: for `apply_objdef_changes`, true to record the accepted version's base
  hashes after the whole apply succeeds.

`preview_objdef_changes` is wizard-only.

### `apply_objdef_changes`

Use `apply_objdef_changes` when you have already previewed an objdef update and are ready to apply
it.

```moo
map apply_objdef_changes(list definitions, map|list resolutions [, map options])
```

The builtin reparses the objdefs and recomputes the preview in the current transaction before it
changes anything. If the new preview has graph diagnostics, unsafe targets, missing resolutions, or
stale resolutions, the result has `"ok" -> false` and the database is not changed.

Clean creates and clean patches are applied automatically. Conflicts need explicit resolutions:

```moo
result = apply_objdef_changes({definition}, {
  {{"property_value", #10, "title"}, "incoming"}
}, ["base_metadata" -> 1]);
```

Resolution values are:

- `"incoming"`: use the value from the objdef for a conflict.
- `"local"`: keep the current database value for a conflict.
- `"delete"`: delete a deletion candidate from `base_manifest`.
- `"keep"`: keep a deletion candidate.

Structured resolution keys are written as an alist, as shown above, because map keys must be scalar
values.

When `"write_base_metadata"` is true, `apply_objdef_changes` records base hashes for the version
that was actually accepted. A later preview can then use `"base_metadata"` to distinguish a clean
package update from a local edit. Failed apply attempts do not update base hashes.

`apply_objdef_changes` is wizard-only.

## `load_object`

Use `load_object` when you want to apply one objdef now. It creates or updates one object and
returns the object it loaded.

```moo
obj load_object(list object_lines [, map options] [, obj|int object_spec])
```

`object_lines` is a list of strings containing exactly one object definition. If you have a string
instead of a list of lines, split it into lines before calling `load_object`.

The optional `options` map has two supported entries:

| Option        | Type         | Meaning                                                    |
| ------------- | ------------ | ---------------------------------------------------------- |
| `constants`   | Map or alist | Names available while parsing object references and code.  |
| `diagnostics` | Map          | Controls compiler diagnostic rendering for parse failures. |

A **constant** is a readable name for a value used inside objdef text. The most common use is naming
objects so the objdef does not have to contain the local object number everywhere.

```moo
new_obj = load_object(definition, [
    `constants -> [
        `ROOM -> #10,
        `OWNER -> #3
    ]
]);
```

The optional third argument tells mooR where to put the object:

| Value     | Meaning                                                       |
| --------- | ------------------------------------------------------------- |
| Omitted   | Use the object number written in the objdef.                  |
| `0`       | Create a new numbered object using the next available number. |
| `1`       | Create an anonymous object.                                   |
| `2`       | Create a UUID-based object.                                   |
| Object ID | Load into that existing object.                               |

Examples:

```moo
// Use the object number from the objdef.
obj = load_object(definition);

// Make a copy with a new object number.
copy = load_object(dump_object($widget), [], 0);

// Replace an existing object with the supplied definition.
load_object(definition, [], $widget);
```

`load_object` is wizard-only. It is also immediate: it does not ask which changes are safe, and it
does not return a review report. If you are loading an update from outside the running database,
call `preview_objdef_changes` first and show the result to a wizard or package tool.

## `reload_object`

Use `reload_object` when you want the final object to match the supplied objdef exactly. It replaces
an existing object and removes properties or verbs that are not present in the new definition.

```moo
obj reload_object(list object_lines [, map constants] [, obj target])
```

- `object_lines`: a list of strings containing the objdef text for one object.
- `constants`: optional map or alist of constant substitutions available during parsing and
  compilation.
- `target`: optional object to replace. When omitted, mooR uses the object ID from the objdef.

`reload_object` is wizard-only and returns the loaded object ID.

## Reviewing Before Loading

`preview_objdef_changes` is the review step. It compares incoming objdef text with the current
database and returns a report without changing anything.

Use it when:

- the objdef came from another database
- the objdef is a package update
- the object number already exists locally
- you want to check whether local edits would be overwritten

Then use `load_object` or `reload_object` only after the update tool or wizard has decided what to
apply.

```moo
cl = preview_objdef_changes({definition}, [
    `constants -> constants
]);

if (cl["ok"])
    load_object(definition, [`constants -> constants]);
else
    player:tell("This update needs review.");
endif
```

## Verb Names During Loading

Verbs are matched by their complete set of names. A verb named `"look l"` and a verb named
`"look l examine"` are different verb definitions, even though both include `"look"`.

If you want to add or remove a verb alias, make that change deliberately in the database and then
dump the object again. Do not rely on `load_object` to guess whether a changed name list means
"rename this verb" or "create another verb."

## Error Handling

`load_object` raises errors when it cannot parse or apply the definition:

```moo
try
    obj = load_object(definition);
    player:tell("Loaded ", tostr(obj));
except error (E_INVARG)
    player:tell("Invalid object definition.");
except error (E_PERM)
    player:tell("Only wizards can load objdefs.");
except error (ANY)
    player:tell("Load failed: ", error[2]);
endtry
```
