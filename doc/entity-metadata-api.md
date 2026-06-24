# Entity Metadata API

## Problem

mooR has stable introspection and mutation APIs for objects, properties, and verbs, but there is no
general place to attach auxiliary state to those entities.

Several higher-level systems want this shape of storage:

- source/package bookkeeping
- editor and tooling annotations
- modification metadata such as last editor and last edit time
- migration markers
- documentation links
- test or fixture ownership notes
- external integration identifiers

These should not be added to existing compatibility-shaped APIs such as `verb_info()` or
`property_info()`. Those functions return fixed tuples with LambdaMOO-style expectations, and
widening those tuples could break existing MOO code.

The proposed API adds a separate metadata layer: a string-or-symbol-keyed `Var` mapping attached to
objects, property entities, and verb entities.

## Goals

- Store arbitrary MOO values as metadata.
- Address metadata by string or symbol key.
- Keep metadata separate from object, property, and verb semantics.
- Avoid changing the return shape of `verb_info()`, `property_info()`, or other existing tuple APIs.
- Make metadata persistent and transactional with the rest of the object database.
- Include metadata in database snapshots and checkpoints by default.
- Attach property and verb metadata to the resolved database entity, not just to a source-level
  name.
- Keep the first version small enough to support user-space policy code.

## MOO Builtins

### Object Metadata

```moo
object_metadata(obj object) => map|list
object_metadata(obj object, str|sym key) => value|list
set_object_metadata(obj object, str|sym key, value) => list
clear_object_metadata(obj object, str|sym key) => list
```

Object metadata is keyed by `(object, key)`.

### Property Metadata

```moo
property_metadata(obj object, sym prop_name) => map|list
property_metadata(obj object, sym prop_name, str|sym key) => value|list
set_property_metadata(obj object, sym prop_name, str|sym key, value) => list
clear_property_metadata(obj object, sym prop_name, str|sym key) => list
```

The property name is resolved using the same object model rules used by `property_info()` and
property access. Internally, metadata should attach to the resolved property UUID and the holder
object where appropriate, rather than only to `(object, prop_name)`.

This matters because inherited properties are not identified by name alone. A property value or
permissions override on an object may refer to a property definition supplied by an ancestor. If the
parent chain later changes, the same property name may resolve to a different property definition.

### Verb Metadata

```moo
verb_metadata(obj object, str|int|sym verb_desc) => map|list
verb_metadata(obj object, str|int|sym verb_desc, str|sym key) => value|list
set_verb_metadata(obj object, str|int|sym verb_desc, str|sym key, value) => list
clear_verb_metadata(obj object, str|int|sym verb_desc, str|sym key) => list
```

The verb descriptor should follow the established verb builtin conventions: name, symbol, or 1-based
index where applicable. Internally, metadata should attach to the resolved verb UUID, not to the
textual descriptor used by the caller.

## Missing Values

Metadata lookup should treat absence as ordinary. A missing key should return the empty list,
matching the usual MOO convention for "not present" results.

Errors should still be raised when the target entity itself is invalid:

- invalid object: `E_INVARG`
- missing property: `E_PROPNF`
- missing verb: `E_VERBNF`
- invalid metadata key type: `E_TYPE`

## Metadata Keys

Symbols are optional in mooR. Some deployments do not enable symbol literals or symbol-valued
builtins, so metadata keys must support both strings and symbols.

The API should treat a symbol key and the equivalent string key as the same metadata key:

```moo
set_object_metadata(obj, "package_base", value);

// Equivalent when symbols are enabled:
set_object_metadata(obj, 'package_base, value);
```

Internally, the database should store a canonical key representation. A `Symbol` is a reasonable
internal representation because strings can be interned at the builtin boundary, but the public API
must not require callers to have the symbol type enabled.

When metadata is fetched without a key, the result should match the server's builtin compatibility
mode:

- if maps are enabled for builtin results, return a map
- otherwise, return an alist
- if symbols are enabled for builtin results, metadata keys may be returned as symbols
- otherwise, metadata keys should be returned as strings

Since ordinary MOO values do not include a distinct `none` value, every valid MOO value can be
stored as metadata. The empty list is only ambiguous if callers store `{}` as a metadata value and
also use single-key lookup to test presence. Callers that need to distinguish missing from stored
`{}` can fetch all metadata for the entity and test key membership.

## Permissions

Metadata permissions should follow the existing authority model for the entity being annotated.

Read rules:

- Object metadata: readable if the caller can read the object or controls it.
- Property metadata: readable if the caller can read the property info.
- Verb metadata: readable if the caller can read the verb info.

Write rules:

- Object metadata: writable by the object owner or a wizard.
- Property metadata: writable when the caller can perform the corresponding `set_property_info()`
  operation.
- Verb metadata: writable when the caller can perform the corresponding `set_verb_info()` operation.

This keeps metadata close to the authority model of the entity it annotates. Package or system-level
metadata that should not be user-editable can be written by a wizard-owned package manager object.

## Storage Model

The database should store metadata as side relations, not by widening existing object, property, or
verb records.

A single tagged-key relation is sufficient:

```rust
entity_metadata => EntityMetadataKey, Var
```

Conceptual key variants:

```rust
Object {
    obj: Obj,
    key: Symbol,
}

Property {
    holder: Obj,
    uuid: Uuid,
    key: Symbol,
}

Verb {
    location: Obj,
    uuid: Uuid,
    key: Symbol,
}
```

Separate relations for object, property, and verb metadata would also work, but a unified tagged key
keeps the API conceptually simple and makes future tooling easier to build around one metadata
plane.

Metadata should not be stored inline in the existing hot relations:

- `object_verbdefs`
- `object_verbs`
- `object_propdefs`
- `object_propvalues`
- `object_propflags`

Keeping metadata as a side relation avoids widening hot tuples and avoids changing
compatibility-shaped data structures.

## Lifecycle

Metadata should follow the entity it annotates.

- Recycling an object deletes object metadata, local verb metadata, and local property metadata for
  that object.
- Deleting a verb deletes metadata for that verb UUID.
- Deleting a property definition deletes metadata for that property definition and affected
  holder/override entries.
- Renumbering an object moves metadata to the new object identity.
- Metadata is not inherited.
- Metadata is not automatically copied when an object is cloned or loaded into a different object
  unless the caller explicitly asks for that behavior.
- Metadata is included in database snapshots and checkpoints by default.

## Anonymous Objects

Anonymous objects raise two separate questions:

1. Can metadata be attached to anonymous objects?
2. Do object references inside metadata keep anonymous objects alive?

Metadata should be attachable to anonymous objects. If an anonymous object is a valid object, object
metadata should work on it. Likewise, property and verb metadata should work for properties and
verbs whose holder or location is an anonymous object.

The harder question is garbage collection. mooR already treats anonymous objects as collectable
unless they are reachable. Metadata values are arbitrary `Var`s, so they may contain object
references inside lists, maps, flyweights, and other compound values.

There are two plausible policies:

- Metadata references count as GC references.
- Metadata references do not count as GC references.

The safer first version is that metadata references count as GC references. This prevents metadata
from containing dangling object references after an anonymous object is collected. It also matches
the normal expectation that if a database value stores an object reference, that reference
participates in reachability.

The cost is that metadata can become a hidden retention path. For example, a tooling annotation
could accidentally keep an anonymous object alive by storing it in metadata. That is usually
preferable to silently breaking metadata values, but it should be documented.

If this becomes a practical problem, a later API can add an explicit weak metadata convention or a
separate weak-reference value. The first version should avoid adding weak metadata semantics.

Garbage collection should also remove metadata attached to anonymous objects that are themselves
collected.

## Objdef and Export

Objdef dump and reimport should behave as a save/restore path. Metadata is database state, so
ordinary objdef export should preserve it by default.

This matters for checkpoints and database migration. A database exported to objdef and then
reimported should not silently lose package state, editor annotations, migration markers, or other
metadata attached to objects, properties, and verbs.

There is still a distinction between a save/restore export and a source/package export.
Source-oriented tooling may want to omit metadata so that local tooling state does not become part
of a shared package. That should be an explicit option, not the default save/restore behavior.

Possible API shapes:

```moo
dump_object(obj)                         // includes metadata
dump_object(obj, ["metadata" -> false])  // source-oriented export
```

Directory export should follow the same rule: checkpoint/export preserves metadata unless explicitly
told to omit it.

## Objdef Metadata Syntax

Objdef needs a literal form for metadata so dump/reimport can round-trip the metadata side relation.

The syntax should keep metadata physically close to the entity it annotates, without mixing
arbitrary metadata keys into the built-in declaration fields. Declarations may take an optional
metadata map after their normal header.

```moo
object THING [
  package -> "core",
  revision -> "2026.06.24"
]
  name: "Generic Thing"
  parent: ROOT
  owner: WIZARD

  property version (owner: WIZARD, flags: "rc") [
    package -> "core",
    revision -> "2026.06.24",
    value_hash -> "..."
  ] = "1.0";

  verb "look l" (this none none) owner: WIZARD flags: "rxd" [
    package -> "core",
    revision -> "2026.06.24",
    program_hash -> "..."
  ]
    player:tell(this.name);
  endverb
endobject
```

Short metadata maps may be written on one line:

```moo
property version (owner: WIZARD, flags: "rc") [package -> "core"] = "1.0";
```

Longer metadata maps should be written on multiple lines:

```moo
method honky owner: WIZARD flags: "rxd" [
  package -> "core",
  revision -> "2026.06.24",
  doc -> "Short note"
]
  player:tell("honk");
endmethod
```

Export should use the one-line form only when the complete declaration line can fit under 100
characters. Otherwise, export should use the multiline form with the opening `[` on the declaration
line and one `key -> value` entry per line.

Metadata keys may be bare identifiers, strings, or symbols:

```moo
package -> "core"
"external-id" -> "abc-123"
'package -> "core"
```

On import these keys should canonicalize the same way as builtin metadata keys. A bare identifier
key, equivalent string key, and equivalent symbol key refer to the same metadata entry.

Export should prefer bare identifiers when the key can be represented as a valid identifier.
Otherwise, export should use a quoted string key.

### Object Metadata

Object metadata appears on the object declaration:

```moo
object OBJECT_IDENTIFIER [metadata-map]
```

This attaches metadata to the object being defined.

### Property Metadata

Property metadata appears between the property info clause and the `=` value:

```moo
property PROP_NAME (owner: OWNER, flags: "FLAGS") [metadata-map] = VALUE;
```

The metadata applies to the property entity resolved after the object's properties and ancestry have
been established. For a property defined on this object, it attaches to that property definition.
For an inherited property override, it attaches to the resolved inherited property for this holder
object.

If the property name cannot be resolved during import, the objdef load should fail. Silent metadata
drops would break save/restore expectations.

### Verb Metadata

Verb metadata appears on the verb or method declaration after the built-in header fields:

```moo
verb "VERB_NAMES" (ARGSPEC) owner: OWNER flags: "FLAGS" [metadata-map]
method METHOD_NAME owner: OWNER flags: "FLAGS" [metadata-map]
```

Import attaches the metadata to the verb UUID created or updated by that declaration.

### Ordering

Export should prefer a stable ordering:

1. metadata maps attached to their declarations
2. metadata keys sorted by canonical key name within each map
3. one-line maps only when the full declaration line stays under 100 characters
4. multiline maps otherwise

This keeps diffs stable without requiring users to write metadata in a particular order.

### Values

Metadata values use normal objdef literal syntax. Supported values should match the literal values
accepted elsewhere in objdef:

- objects
- integers
- floats
- strings
- booleans
- symbols when symbols are enabled
- errors
- lists
- maps
- flyweights

Object references inside metadata values participate in anonymous-object reachability, as described
above.

## Example: Package Base Hashes

One intended use case is user-space package tracking. A package manager object could record that a
verb program matched a canonical package revision when it was installed:

```moo
set_verb_metadata($thing, "look", "package_base", [
    "package" -> "core",
    "revision" -> "2026.06.24",
    "program_hash" -> verb_hash($thing, "look")
]);
```

Later, package code can compare the recorded base hash to the current live hash and the incoming
package hash:

```moo
base = verb_metadata($thing, "look", "package_base");
local_hash = verb_hash($thing, "look");

if (base != {} && local_hash == base["program_hash"])
    "The local verb program still matches the accepted base.";
else
    "The local verb program changed since the accepted base.";
endif
```

This document does not define the package manager itself. Metadata only provides the durable
attachment point.

## Example: Verb Modification Metadata

Some existing cores encode verb metadata by appending comments or string literals to verb bodies.
jhcore-style verb bodies, for example, may carry modification date, modification user, or source
provenance in trailing comments after the executable code.

Entity metadata provides a cleaner representation:

```moo
set_verb_metadata($thing, "look", "modified_by", player);
set_verb_metadata($thing, "look", "modified_at", time());
set_verb_metadata($thing, "look", "editor", "web-client");
```

Objdef export can then preserve those fields without polluting the verb body:

```moo
verb "look" (this none none) owner: WIZARD flags: "rxd" [
  editor -> "web-client",
  modified_at -> 1782150937,
  modified_by -> #42
]
  player:tell(this.name);
endverb
```

This avoids making metadata part of executable source while still preserving it through
dump/reimport and checkpoint export. Import tooling for older cores could optionally recognize the
trailing-comment convention and populate verb metadata during an import, but that compatibility
parser should live outside the core metadata storage model.
