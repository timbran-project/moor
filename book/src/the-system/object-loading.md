# Loading and Updating Individual Objects

Use `dump_object()` to export one object. Use `load_object()` to create or merge an object, or
`reload_object()` to replace an existing definition. These functions receive objdef text in memory.
They do not read files, fetch URLs, or watch source directories.

For a complete initial database import, see
[Starting a MOO from objdef Source](bootstrapping-from-source.md). For reviewed program updates, use
the review APIs described below.

## Dump an object

```moo
definition = dump_object(#123);
definition = dump_object(#123, ["constants" -> true]);
```

The result is a list of source lines. The optional `constants` boolean selects symbolic object
names. The dump includes pending changes in the calling task. It does not create a separate database
snapshot. A client can save the returned lines as a `.moo` file.

Dumps preserve explicit local values, clear states, local permissions, and metadata independently.
An inherited property remains inherited even when its current value equals an explicit local value
elsewhere.

### Clear Property Values

The `clear` clause removes a property's local value so it inherits from its parent. It follows any
permissions and metadata, without an equals sign:

```objdef
override description (owner: #3, flags: "rw") [note -> "updated"] clear;
```

The same clause works in a `property` declaration. During a merge, declarations without a value or a
`clear` clause preserve the existing value. A new property without a value starts clear.

`clear` remains a valid constant, property name, and identifier in verb code. An assignment such as
`override description = clear;` still refers to a constant named `clear`.

Exports use the clause for clear values, so merging an export also restores those clear values.
Older importers cannot read this clause. The new importer still accepts existing objdef files.

## Direct import options

```text
obj load_object(str-or-list source [, map options])
obj reload_object(str-or-list source [, map options])
```

Both functions require wizard authority or an explicit builtin grant. Each source must define
exactly one object. Both return the affected object address. Source can be a string or a list of
strings.

| Option       | Meaning                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------- |
| `constants`  | Map of constant substitutions. Defaults to empty.                                            |
| `target`     | Explicit target address. Defaults to the source address. Reload requires an existing target. |
| `allocation` | Load only: `source`, `next`, `anonymous`, or `uuid`. Defaults to `source`.                   |

`target` requires `allocation: source`. Anonymous and UUID allocation require their runtime
features. Unknown options, duplicate normalized keys, invalid values, and unsupported combinations
fail before writing. The old third argument and conflict controls are removed. Use
`preview_objdef_changes()` for review.

```moo
loaded = load_object(definition);
loaded = load_object(definition, ["target" -> #456]);
created = load_object(template, ["allocation" -> "next"]);
created = load_object(template, ["allocation" -> "anonymous"]);
created = load_object(template, ["allocation" -> "uuid"]);
replaced = reload_object(definition, ["target" -> #456, "constants" -> constants]);
```

A target override changes the declaration address only. It does not rewrite object references in
programs, values, owners, or metadata. Source self-references that require relocation are rejected.
Bind those references explicitly to the intended target before importing.

## Merge and replacement

`load_object()` applies supplied declarations. Omitted attributes, properties, verbs, and ordinary
metadata entries remain unchanged. Explicit default values still apply: `readable: false` clears the
flag, and `location: #-1` clears the location. Case-only string changes remain meaningful.

A verb matches an existing declaration only when its alias list and argument specification match
exactly. The merge preserves that definition's UUID and lookup position. New declarations append in
source order. An overlapping alias alone does not identify an existing declaration. Ambiguous or
duplicate matches fail.

`reload_object()` replaces the definition of an existing object. It removes absent local properties,
ordinary metadata, and inherited local overrides. It recreates verbs in source order. Missing
attributes receive creation defaults: empty name, `NOTHING` references, and unset flags. Inherited
property definitions remain available through the selected parent.

During replacement, a property declaration without a value restores a clear local value. During
merge, clearing requires the explicit `clear` clause described above.

The reserved `objdef_base` metadata key is ignored in direct input. Merge preserves existing
tracking on surviving definitions. Replacement invalidates tracking for removed or recreated
definitions. Direct import never acknowledges incoming source as an accepted baseline.

## Constants and failures

```moo
constants = parse_objdef_constants(constants_source);
loaded = load_object(definition, ["constants" -> constants]);
```

Constants and programs use the runtime's configured language features. Memory source labels do not
authorize filesystem includes. Source is limited to 16 MiB.

Parsing and option errors raise `E_INVARG` or `E_TYPE` before mutation. If an import fails after a
write begins, the entire task transaction rolls back. A MOO `try` block cannot retain a partial
import. Transaction conflicts retry through the normal runtime mechanism.

The [Meadow object browser](../web-client/authoring-tools.md#exporting-and-reloading-objdef-files)
uses replacement for uploaded definitions. The [moor-emh tool](moor-emh-tool.md#object-importexport)
can import local files while the regular server is stopped.

## Read-only program review

`preview_objdef_changes(sources, request [, choices])` compares existing verb programs without
changing content or baseline metadata. It requires wizard authority or an explicit builtin grant,
plus permission to read the selected definitions.

Each source unit has a diagnostic `label` and `text`. Text can be a string or a list of lines.
Labels grant no filesystem access. Source input is limited to 4,096 units and 16 MiB in total.
Reports contain at most 8,192 program rows.

```moo
sources = {["label" -> "login.moo", "text" -> incoming_lines]};
request = ["schema" -> 1, "operation" -> "update",
           "objects" -> {$login}, "fields" -> {"program"}];
report = preview_objdef_changes(sources, request);
```

`objects` explicitly selects installation-local object addresses. Optional `constants` supplies
constant substitutions. Source export identities must match live identities when supplied. Ambiguous
verb declarations remain unsupported. Unknown keys and duplicate normalized keys fail.

Each row contains an opaque `id`, target `object`, verb `names`, source label, and field name. It
also contains `base`, `live`, and `incoming` fingerprints, classification, eligibility, allowed
choices, default action, and blockers. An empty base list means that the baseline is unknown.
Classifications are `unchanged`, `upstream`, `local`, `converged`, `conflict`, and `unbased`.
Unbased updates require adoption. An `adopt` request inspects source-derived baseline enrollment.
Neither operation writes during preview.

Optional `details` selects row IDs whose live and incoming program text the report includes. Detail
selection does not change review evidence. Clients must compare returned evidence with the saved
review before showing newly read text under an old approval.

The report's `evidence` binds the source, scope, compilation options, target identities, authority,
live programs, and baselines. Evidence grants no permission. Property and definition fields remain
unmanaged; diagnostics identify unsupported declarations and fields.

Choices are a map from row ID to a map containing `choice`. Supported values are `incoming`,
`local`, `edited`, and `defer`. Adoption permits only `incoming` and `defer`. An edited choice also
contains `program`, a string or list of lines. Preview compiles the draft and returns `validation`
rows with a fingerprint and validation token, or compiler diagnostics with result-pane coordinates.
Drafts remain separate from incoming source. Changing draft text invalidates its validation token.

Program baselines use the metadata key `objdef_base`, with `schema` and `program` entries. The
schema is `objdef-v1:program:sha256`. Its fingerprint uses decompiled program structure and separate
typed literals, encoded with CBOR and hashed with SHA-256. Layout is ignored. String case, literal
types, execution order, finite floating-point bits, and installed object references remain
significant. Symbols use Unicode case-folded names. Map entries sort by encoded key; flyweight slots
sort by folded name. Captured lambda values and non-finite floats are unsupported.

These rules describe content equality, not behavioral equivalence. A hash cannot recover old source.
Unknown baseline schemas block updates until explicit re-adoption. Automatic eligibility requires
administrator-owned objects and verbs whose content and metadata are not publicly writable.
