# Objdef Changelist Analysis

This page sketches a facility separate from `load_object()`.

The `load_object()` cleanup should make single-object import less dangerous and less overloaded.
This proposal is about a higher-level runtime service for analyzing an incoming set of objdefs as a
proposed change to the live object database.

## Motivation

Object update is usually graph-shaped, not object-shaped. A change that looks like "update this
object" may depend on related changes to parents, children, property definitions, overrides, verb
code, metadata, or references stored in values.

The current objdef directory loader already reflects this. It parses a set of object definitions,
creates placeholder objects first, records the definitions in an internal map, and then applies
attributes, metadata, properties, overrides, and verbs in phases. That is already a graph import
model, even if the current public MOO builtin surface mostly exposes single-object operations.

The question is whether mooR should expose a runtime-mediated analysis layer that can be used by MOO
code to build package/update workflows without making Rust own package management.

## Identity Model

The first version should be identity-preserving, but it should prefer stable objdef constants when
they are available.

Object IDs in objdef text are the object IDs being analyzed, created, or patched:

```text
incoming #10 -> database #10
incoming #11 -> database #11
```

If both the incoming objdef set and the local database have equivalent constants, the changelist
should use those constants as the primary identity vocabulary for comparison and diagnostics:

```text
incoming WIZARD -> local WIZARD
incoming GENERIC_THING -> local GENERIC_THING
```

The concrete object IDs are still the objects being patched or created. Constants do not imply
general remapping or cloning. They provide a stable name layer so analysis can detect drift before
it becomes a mysterious object-ID mismatch.

For objdefs produced by mooR export, this identity layer is already part of the format. Export
derives `constants.moo` from object `import_export_id` metadata, and object references are emitted
through that index when a stable name is available. Changelist analysis should treat that exported
constant set as the normal source of symbolic identity. Hand-authored objdefs or objdefs from older
tooling may still only provide raw object IDs; in that case the analyzer can compare by object ID,
but it has less evidence that an existing target object is the intended package object.

Fresh import is just the case where those objects do not exist yet:

```text
incoming #10 does not exist -> changelist says "create #10"
incoming #11 does not exist -> changelist says "create #11"
```

Updating a live database is the case where those objects already exist:

```text
incoming #10 exists -> changelist says "patch #10"
incoming #11 exists -> changelist says "patch #11"
```

An existing object is not, by itself, proof that the incoming definition is safe to patch. If `#10`
exists locally but there is no matching constant, base fingerprint, or base manifest evidence that
`#10` belongs to the imported package/core, the analyzer should report that as an unsafe target or
non-automatic conflict. The first version should prefer rejection over silently treating an
unrelated local object as the old package object.

There is no general source-to-target remapping in this model. References in objdef text are
interpreted literally. If incoming `#11` has parent `#10`, the proposed change is "set `#11`'s
parent to `#10`." If `#10` is also present in the same changelist, validation should consider
`#10`'s proposed incoming state. If `#10` is not present, validation should consider the current
database state of `#10`.

When constants are available on both sides, analysis should also report the constant names for
objects and references. If an incoming constant resolves to a different object than the local
constant of the same name, that should be a diagnostic before apply. The first version can reject
that case rather than trying to repair it.

Cloning a package under new object IDs, importing numbered objdefs into UUID space, or assigning
package-local symbolic IDs are separate problems. They may need a future remapping facility, but
they should not be part of the first changelist design.

## Changelist

"Changelist" is borrowed from Perforce-style systems. In this context it means a proposed set of
object graph changes, not a committed mutation.

A changelist is the result of analyzing:

- an incoming objdef set
- optional base fingerprint metadata on the corresponding database objects
- optional base manifest metadata for the previously imported object set
- the current transaction's view of the database

The changelist should answer:

- Which objects would be created?
- Which existing objects would be patched?
- Which existing objects are deletion candidates, when a base manifest makes that knowable?
- Which object attrs would change?
- Which property definitions, property values, property info, verbs, and metadata would change?
- Which changes are clean because local state still matches the recorded base?
- Which changes conflict because both local and incoming state changed?
- Which incoming definitions are invalid against the proposed object graph?

It should not contain the entire imported object state. It is a report/review value, not the import
payload.

## Layering

Rust should own:

- parsing objdef sets
- building an internal proposed object graph for the duration of analysis/apply
- computing fingerprints
- computing bounded diffs for values, metadata, and verb source when the caller asks for review
  details
- comparing incoming, local, and recorded base state
- validating inheritance, property definitions, and property overrides against the proposed graph
- producing structured diagnostics
- applying approved changes atomically inside the current task transaction, if an apply builtin is
  added

MOO code should own:

- package names and revisions
- dependency policy
- user interface and review workflow
- deciding how to resolve conflicts
- deciding whether to apply, reject, retry, or ask a wizard

This keeps package management in MOO code while still letting the runtime provide the graph-aware
analysis that MOO code cannot easily reconstruct from single-object imports.

## Transaction Model

mooR tasks already run inside a database transaction. That matters.

The intended use is:

```moo
cl = preview_objdef_changes(definitions, options);
resolutions = $package_manager:choose_resolutions(cl);
result = apply_objdef_changes(definitions, resolutions, options);
```

When both calls happen in one task, analysis and apply see one transaction snapshot. No other task
can mutate the baseline between analysis and apply from this task's point of view. If another task
commits a conflicting write before this task commits, the normal serializable transaction machinery
should detect that at commit time.

That same-task path is useful, but it should not be the only expected workflow. A real package
manager may present the changelist to a user, suspend for input, store it for later, or hand review
off to another task. In every delayed path the returned changelist is advisory only. Apply must
reparse and revalidate against the current transaction before mutating anything, and supplied
resolutions must match the recomputed conflict keys rather than the caller's stale copy of the
report.

## Proposed Public Shape

Names are placeholders.

```moo
cl = preview_objdef_changes(definitions [, options]);
result = apply_objdef_changes(definitions, resolutions [, options]);
```

Both builtins should be wizard-only in the first version. The facility is intended for core/package
maintenance and can create or patch authority-bearing object graph state. A narrower unprivileged
mode can be designed later after the semantics have settled.

`definitions` is a list of objdef texts. Each element could be either a string or a list of lines.
The MOO API should not be phrased as loading a filesystem directory; MOO code or external tooling
can gather the texts from files, packages, properties, or another source.

`options` may include:

```moo
[
  "constants" -> constants,
  "local_constants" -> local_constants,
  "base_metadata" -> true,
  "base_metadata_prefix" -> "base_",
  "write_base_metadata" -> false,
  "base_manifest" -> {#1, #2, #3, #10, #11, #12},
  "include_unchanged" -> false
]
```

If `local_constants` is omitted, the runtime may derive it from the local equivalent of
`constants.moo` when the core has one. The exact derivation mechanism is an implementation detail,
but the user-facing goal is that changelist diagnostics prefer stable names over raw object IDs when
both are available.

## Base Manifest

Deletion cannot be inferred from absence in the incoming objdef set alone.

If an object exists locally but is absent from the incoming definitions, that could mean:

- upstream deleted it
- upstream never owned it
- the export is partial
- the package split or moved it
- the local site added it
- object identity drifted

So deletion candidates require a base manifest: the set of objects that belonged to the previously
imported package or core revision.

With a base manifest:

```text
base manifest:     #1 #2 #3 #10 #11 #12
incoming objdefs:  #1 #2 #3 #10 #12
current database:  #1 #2 #3 #10 #11 #12 #9000
```

The analyzer can report `#11` as a deletion candidate because it was present in the base manifest,
is absent from the incoming objdefs, and still exists locally.

Without a base manifest, the analyzer must not treat absence from the incoming objdefs as deletion.

Deletion candidates are always non-automatic. They must be called out in the changelist and require
explicit resolution before apply.

`resolutions` should be a compact policy input, not a modified copy of the changelist:

```moo
[
  ["property_value", #10, "description"] -> "incoming",
  ["verb_code", #10, {"look"}] -> "local",
  ["parent", #11] -> "incoming"
]
```

Clean changes should not need explicit resolutions. `resolutions` is only required for conflicts or
other changes that the analysis marks as non-automatic. Object deletion is always non-automatic and
must be covered by an explicit resolution.

## Changelist Value

The changelist returned to MOO should be a bounded summary map. It should not contain full property
values, full verb programs, or a full copy of every object definition unless an explicit diagnostic
option asks for more detail.

Example shape:

```moo
[
  "ok" -> false,
  "objects" -> [
    #10 -> [
      "status" -> "conflict",
      "changes" -> {
        "attrs",
        "property_values",
        "verb_code"
      }
    ],
    #11 -> [
      "status" -> "delete_candidate",
      "automatic" -> false
    ],
    #12 -> [
      "status" -> "create"
    ]
  ],
  "conflicts" -> {
    [
      "key" -> {"property_value", #10, "description"},
      "kind" -> "property_value",
      "object" -> #10,
      "name" -> "description",
      "base_hash" -> "sha256:...",
      "local_hash" -> "sha256:...",
      "incoming_hash" -> "sha256:..."
    ]
  },
  "diagnostics" -> {}
]
```

Each object should appear at most once in `"objects"`. A conflict, deletion candidate, invalid
definition, or clean patch is an object status plus detail records, not duplicate object entries.
The exact container types need to be legal MOO values and stable across installations; examples in
this document use strings for keys because symbols may be disabled.

The exact representation should use strings or symbols depending on whether symbols are enabled in
the installation. This follows the metadata API constraint: symbol keys are not universally
available.

Changelists may include bounded display fields for review tools:

```moo
[
  "kind" -> "verb_code",
  "object" -> #10,
  "object_label" -> "$generic_thing",
  "entity_label" -> "look this none this",
  "summary" -> "verb code changed: $generic_thing:look this none this",
  "base_hash" -> "sha256:...",
  "local_hash" -> "sha256:...",
  "incoming_hash" -> "sha256:..."
]
```

These fields are advisory. Stable machine fields and hashes remain authoritative. Display fields
should be short labels or summaries, not full verb code or long property values.

## Supporting Diff Builtin

Changelist analysis can identify that a field changed, but package UI code will still need a way to
show the change. MOO code should not have to implement structural diffs over arbitrary `Var` values,
metadata maps, property values, or decompiled verb source.

The runtime probably needs a separate bounded diff builtin, rather than making `preview_objdef_changes()`
return full before/after bodies by default. Names are placeholders:

```moo
diff = value_diff(base, changed [, options]);
diff3 = value_diff3(base, local, incoming [, options]);
```

This builtin should be a review aid, not an apply plan. It should return a bounded structured value
that can drive package-manager UI:

```moo
[
  "ok" -> true,
  "truncated" -> false,
  "kind" -> "map",
  "summary" -> "2 changed, 1 added",
  "changes" -> {
    ["changed", "description", "sha256:...", "sha256:..."],
    ["added", "aliases", "sha256:..."]
  }
]
```

For strings and decompiled verb source, the same builtin could return line-oriented hunks when
requested. For lists and maps, it should return structural additions, removals, and changed entries.
For large or opaque values, it should fall back to type, size, and hash summaries. Options should
set limits such as maximum entries, maximum string bytes, whether to include text hunks, and whether
to include small scalar values inline.

This is also useful outside objdef package management, so it should not be hidden as an
objdef-specific diagnostic format. The changelist result can include hashes and stable conflict
keys; review code can call the diff builtin lazily for the conflicts the user opens.

## Conflict Keys And Fingerprints

Conflict keys are the bridge between analysis and apply. They need to be compact, deterministic, and
recomputable from the incoming definitions plus the current database state.

The first version should define a closed set of conflict key kinds, probably including:

- `object_attrs`: object flags and builtin attrs such as parent, location, owner, and name
- `object_metadata`: object metadata by key
- `property_def`: property definition by defining object and property name
- `property_value`: property value override by object and property name
- `property_info`: property owner/permission changes by object and property name
- `property_metadata`: property metadata by object, property name, and metadata key
- `verb_def`: verb names, owner, flags, and argspec
- `verb_code`: verb program
- `verb_metadata`: verb metadata by verb identity and metadata key
- `delete_object`: deletion candidate from a base manifest

Verb identity is the least obvious case. A key based only on the name list is not stable across
rename, alias, or argspec changes. The design should either require stable verb metadata for
package-managed verbs, or define a deterministic structural key such as
`{object, canonical names, argspec}` and treat renames as delete-plus-create. This should be settled
before exposing the MOO API.

Fingerprints must be canonical. They should hash runtime-significant state, not presentation. In
particular:

- base fingerprint metadata must be excluded from the fingerprint it records
- advisory display labels and summaries must be excluded
- metadata maps need deterministic key ordering
- property and verb collections need deterministic ordering
- values should be hashed through the same canonical `Var` representation used by the metadata hash
  builtins, or through an explicitly documented objdef canonical form
- verb code needs a chosen representation: compiled program, canonical unparsed source, or both

If the first implementation cannot make one of these hashes stable, it should omit that fingerprint
or mark the corresponding comparison as diagnostic-only rather than treating it as conflict
authority.

## Proposed Graph Validation

The runtime analysis should validate the incoming set as a proposed graph, not as isolated objects.

For each object in the incoming set:

- If its parent is also in the incoming set, validate against the proposed incoming state of that
  parent.
- If its parent is not in the incoming set, validate against the current database state of that
  parent.
- Property definitions should be checked against the proposed ancestor chain.
- Property overrides should be checked against the proposed ancestor chain.
- Parent changes should be checked for cycles and descendant conflicts in the proposed graph.

This is the main reason a changelist facility is useful. A sequence of `load_object()` calls can be
transactional, but each call still sees only one object at a time unless MOO code reconstructs the
whole incoming graph itself.

## Internal Representation

During analysis, Rust needs a richer internal structure than the MOO changelist value:

- parsed object definitions
- compiled verb programs
- object IDs from the objdefs
- proposed parent/location/owner edges
- fingerprints for attrs, properties, verbs, metadata
- source spans for diagnostics

This internal structure can be rebuilt from `definitions` for each builtin call. That avoids
inventing a new MOO-visible opaque graph value or task-local handle.

The tradeoff is that `apply_objdef_changes()` reparses and reanalyzes. That is simpler and safer
than trusting a large MOO map as an executable plan.

This should be a new set-oriented analyzer/apply path, not a loop around the existing scalar
`load_object()` behavior. The directory loader already has the right rough shape: parse the full
set, create placeholders or proposed object records, then apply attrs, metadata, property
definitions, overrides, and verbs in phases. The changelist path should share those parser,
comparison, validation, and apply primitives, but it needs to preserve the whole proposed graph
during analysis.

## Reference Interpretation

References in objdef text should be interpreted literally in the first version, with constants used
as a diagnostic and comparison layer when available.

If an imported property value contains `#10`, it means database object `#10`. If `#10` is also in
the incoming set, analysis may use the proposed incoming state of `#10` for graph validation, but
the object identity is still `#10`.

If the same reference came from a constant such as `GENERIC_THING`, the changelist should preserve
that fact in diagnostics where possible:

```moo
[
  "object" -> #10,
  "constant" -> "GENERIC_THING"
]
```

That makes drift visible. For example, if incoming `GENERIC_THING` points at `#10` but local
`GENERIC_THING` points at `#42`, the changelist should report the mismatch instead of silently
comparing unrelated objects.

This deliberately avoids fresh-object remapping. A later facility may support cloning or relocation,
but that would require explicit rules for:

- assigning new object IDs
- rewriting object refs in attrs, values, and metadata
- rewriting object literals in compiled verb programs, if possible
- deciding what to do with refs outside the imported set

Those are not needed for the Cowbell/core-update changelist model and should stay out of the first
version.

## Apply Semantics

`apply_objdef_changes()` should not trust a previously returned changelist as authority. It
should:

- parse the incoming objdef set again
- recompute the relevant analysis in the current transaction
- verify that supplied resolutions match current conflict keys
- reject missing, stale, or nonsensical resolutions
- apply clean changes automatically
- apply conflicted or otherwise non-automatic changes only when covered by `resolutions`
- delete objects only when a base manifest identified them as deletion candidates and `resolutions`
  explicitly approved them
- reject or require explicit handling for deletion candidates with children, contents, package-owned
  descendants, or other relationships that would make deletion cascade or strand live state
- update base fingerprint metadata after successful apply, if requested

The apply operation should be all-or-nothing inside the current task transaction. If it raises an
error, the caller can let the task roll back or catch the error and decide what to do.

## Relationship To `load_object()`

This proposal should not block cleanup of `load_object()`.

`load_object()` should still become a simpler import primitive with one primary meaning. It is the
scalar case: load one objdef as one fresh object or under a clearly defined policy.

Objdef changelist analysis is a different facility:

- it operates on a set
- it analyzes proposed changes to the same object identities named by the objdefs
- it produces reviewable change records
- it is designed for package/update tooling in MOO code

The two APIs can share parser, fingerprint, and loader internals without sharing user-facing
semantics.

## Phased Implementation Plan

Each phase should leave the tree in a useful state with tests that exercise the new behavior without
requiring later phases to exist.

### Phase 1: Canonical Diff And Fingerprint Primitives

Deliverables:

- add a reusable internal representation for bounded value diffs
- add `value_diff(value_a, value_b [, options])`
- add `value_diff3(base, local, incoming [, options])`
- define truncation options for maximum entries, string bytes, and optional text hunks
- make the diff code reuse the same canonical value handling as `value_hash()` where possible
- use the existing workspace `diffy` dependency for line-oriented string and verb-source hunks
- document the new builtins in the builtin list and object packaging/reference docs

Minimum behavior:

- scalar equality reports no changes
- scalar inequality reports type, size where meaningful, and hashes
- strings can return line-oriented hunks when requested
- lists report changed, added, and removed indexes up to the configured limit
- maps report changed, added, and removed keys in deterministic order
- large values set `"truncated" -> true` instead of returning unbounded payloads

Implementation notes:

- `diffy` is already a workspace dependency used by `moor-mcp-host` for objdef patch application. It
  provides Myers-style text patches, hunk/line types, patch apply, and merge support. That is the
  right dependency for string and decompiled verb-source hunks.
- `diffy` is not a structural MOO value diff. Lists, maps, flyweights, object references, errors,
  symbols, and other `Var` cases still need runtime-owned comparison code so ordering, limits, and
  hash summaries match MOO semantics.
- The transitive `diff` crate currently arrives through `pretty_assertions`; it should not drive the
  runtime builtin unless a later review shows a concrete advantage over `diffy`.

Tests:

- unit tests for deterministic scalar, list, map, string, and truncation diffs
- builtin tests for argument validation and returned shape
- regression test that equal maps with different construction order produce the same diff result
- run `cargo test -p moor-kernel value_diff`
- run `cargo test -p moor-var value_hash` if shared canonicalization code moves

### Phase 2: Objdef Set Parser And Proposed Graph Model

This phase should be a refactor of the existing objdef import internals, not a parallel
implementation. The public import behavior should stay the same, but the parser, constants
resolution, full-set staging, and proposed graph construction should have one shared code path that
both the existing directory import and later changelist analysis use.

Deliverables:

- factor the directory loader's parse/full-set staging into reusable objdef-set analysis code
- update the existing directory import path to use the shared objdef-set/proposed-graph core for
  parsing, constants, and staging, while preserving its current apply behavior
- accept a list of objdef texts plus optional constants without depending on filesystem directory
  layout
- build an internal proposed graph containing object IDs, attrs, metadata, property definitions,
  property overrides, verbs, and source labels/spans where available
- derive incoming symbolic identity from supplied constants and exported `import_export_id` metadata
- detect duplicate incoming object IDs and duplicate/conflicting constants before comparison

Minimum behavior:

- parsing a multi-object list produces the same object definitions as importing the equivalent
  directory
- importing an objdef directory through the existing API produces the same database changes as
  before this refactor
- constants from `constants.moo`-style input resolve exactly as they do for current objdef import
- invalid objdef text produces structured diagnostics with source index or label
- the new in-memory analysis entry point does not mutate the database

Tests:

- parser tests for multi-object input with constants
- compatibility tests proving the existing directory import still imports the same fixture output
- diagnostics tests for duplicate object IDs, constant drift, and malformed object text
- round-trip fixture test using a small exported objdef directory converted to in-memory definitions
- run `cargo test -p moor-compiler objdef`
- run `cargo test -p moor-objdef objdef`

### Phase 3: Read-Only `preview_objdef_changes()`

Deliverables:

- add wizard-only `preview_objdef_changes(definitions [, options])`
- compute create, patch, unsafe-target, invalid, conflict, and delete-candidate statuses
- define the first stable conflict key set
- compute canonical hashes for object attrs, metadata, property definitions, property values,
  property metadata, verb definitions, verb code, and verb metadata where supported
- support `base_manifest`, `base_metadata`, `base_metadata_prefix`, `constants`, `local_constants`,
  and `include_unchanged`
- return bounded MOO values only; no full verb programs or large property values by default

Minimum behavior:

- fresh objects are reported as creates
- existing objects with matching base evidence are reported as clean or patch
- existing objects without base evidence are rejected or marked unsafe
- local-only objects from `base_manifest` are reported as non-automatic delete candidates
- local and incoming edits against the same changed base become conflicts
- diagnostics prefer constants when incoming and local constants agree

Tests:

- builtin tests for wizard-only access and argument validation
- create/patch/no-op tests against a small in-memory database
- unsafe-target test where `#10` exists with no matching base evidence
- base manifest deletion candidate test
- conflict tests for property value, property definition, metadata, verb code, and parent change
- constant drift test where incoming and local names resolve to different objects
- run `cargo test -p moor-kernel preview_objdef_changes`
- run `cargo test -p moor-objdef conflict`

### Phase 4: Graph Validation Against Proposed State

Deliverables:

- validate parent, location, owner, property definitions, and property overrides against the
  proposed graph instead of one object at a time
- detect parent cycles introduced by the incoming set
- detect descendant/property conflicts caused by parent changes
- report graph validation failures as diagnostics in `preview_objdef_changes()`

Minimum behavior:

- a child can refer to a parent created or patched in the same changelist
- a property override can target a property definition introduced by an incoming ancestor
- a parent cycle fully contained in the incoming set is rejected before apply
- a parent change that would invalidate existing descendant property state is non-automatic or
  rejected

Tests:

- multi-object create with parent and child in the same definitions list
- incoming ancestor property definition plus child override
- incoming parent cycle rejection
- parent change descendant conflict regression
- comparison test showing the same scenario cannot be modeled correctly by repeated scalar
  `load_object()` calls
- run `cargo test -p moor-objdef graph`
- run `cargo test -p moor-kernel preview_objdef_changes`

### Phase 5: `apply_objdef_changes()`

Phase 5 should turn the read-only changelist into a mutating operation, but it should not make
Rust own package policy. The apply builtin should re-run analysis, reject unsafe situations, and
apply only changes that are either clean or covered by precise resolutions.

Deliverables:

- add wizard-only `apply_objdef_changes(definitions, resolutions [, options])`
- reparse and reanalyze in the current transaction before mutating
- verify supplied resolutions against recomputed conflict keys
- apply clean creates and patches automatically
- apply conflicted or non-automatic changes only when covered by valid resolutions
- reject stale, missing, duplicate, and nonsensical resolutions
- optionally update runtime-owned base fingerprint metadata after successful apply
- keep the operation all-or-nothing inside the task transaction

Apply should classify the recomputed changelist before any mutation:

- **Hard blockers**: graph diagnostics, invalid objdef text, unsafe targets, malformed resolutions,
  duplicate resolutions, stale resolutions, and nonsensical resolutions. These reject the apply.
- **Automatic changes**: clean creates and clean patches. These require no resolution.
- **Resolved non-automatic changes**: conflicts and deletion candidates. These require an exact
  resolution keyed to the recomputed changelist.

Graph diagnostics from Phase 4 are not resolvable in Phase 5. If the incoming set contains an
invalid reference, parent cycle, missing inherited property definition for an override, or
parent-change property conflict, apply must reject without mutating the database.

`resolutions` should be a map or alist keyed by stable entity keys. The keys should be fine-grained
enough to map to apply primitives:

```moo
[
  {"object_name", #10} -> "incoming",
  {"object_parent", #10} -> "incoming",
  {"object_owner", #10} -> "local",
  {"object_location", #10} -> "incoming",
  {"object_flags", #10} -> "incoming",
  {"object_metadata", #10} -> "incoming",
  {"property_def", #10, "description"} -> "incoming",
  {"property_value", #10, "description"} -> "local",
  {"property_info", #10, "description"} -> "incoming",
  {"property_metadata", #10, "description"} -> "incoming",
  {"verb_def", #10, {"look", "l"}} -> "incoming",
  {"verb_code", #10, {"look", "l"}} -> "incoming",
  {"verb_metadata", #10, {"look", "l"}} -> "incoming",
  {"delete_object", #12} -> "keep"
]
```

Resolution values are kind-specific:

- ordinary conflict keys accept `"incoming"` or `"local"`
- deletion candidate keys accept `"delete"` or `"keep"`
- clean automatic changes should not appear in `resolutions`
- unsafe targets and diagnostics are not resolvable

Apply should reject extra resolution keys, duplicate keys, missing required keys, or resolution
values that do not make sense for the key kind. This keeps the resolution input a compact policy
decision rather than a second copy of the changelist.

The return value should be a structured result map. Argument-shape errors and permission failures
can still raise normal MOO errors, but stale or rejected apply attempts should return a non-mutating
result:

```moo
[
  "ok" -> false,
  "applied" -> {},
  "diagnostics" -> {
    ["stale_resolution", {"property_value", #10, "description"}, "resolution no longer matches current changelist"]
  },
  "changelist" -> cl
]
```

On success, the result should include the applied objects and enough summary counts for callers to
log what happened. It should not include full object bodies or verb programs.

Deletion should stay conservative in the first apply version. An object may be deleted only when it
is a deletion candidate from `base_manifest` and has an explicit `"delete"` resolution. Apply should
reject deletion when the object has children or contents. Package-owned descendant deletion policy
can be designed later.

Base fingerprint metadata writeback should be opt-in through `"write_base_metadata"`. If enabled,
runtime-owned base hash metadata is written only after the full apply succeeds. Failed apply must
not update base metadata.

Initial objdef import into a new database should establish the same runtime-owned base hash metadata
for the accepted imported definitions. That gives the first later package/core update a real base to
compare against instead of treating the imported objects as unproven local state.

Minimum behavior:

- clean apply mutates the database to match incoming definitions
- rejected apply leaves the database unchanged
- stale resolutions are rejected after the local object changes
- graph diagnostics and unsafe targets reject apply without consulting resolutions
- deletion requires both a base manifest candidate and explicit resolution
- deletion with children or contents is rejected

Tests:

- clean create and patch apply tests
- conflict apply with `"incoming"` and `"local"` resolutions
- missing/stale/nonsensical resolution rejection tests
- duplicate and extra resolution key rejection tests
- graph diagnostic and unsafe-target hard-blocker tests
- all-or-nothing rollback test with one valid and one invalid change
- opt-in base fingerprint metadata update test
- deletion candidate approval, keep, and deletion safety tests
- transaction conflict test if the existing test harness can force concurrent commits
- run `cargo test -p moor-kernel apply_objdef_changes`
- run `cargo test -p moor-objdef apply`

### Phase 6: Package Workflow Fixtures And Documentation

Deliverables:

- add a small package/core fixture with base, local-edited, and incoming-updated objdef sets
- add MOO-level examples that call `preview_objdef_changes()`, inspect conflicts, call `value_diff()`,
  build resolutions, and call `apply_objdef_changes()`
- document the runtime/package-manager responsibility split
- document the base metadata keys owned by the runtime, if that convention survives implementation
- update `load_object()` docs to point package/update workflows at changelists instead

Minimum behavior:

- fixture demonstrates clean update, local-only edit, incoming-only edit, conflict, creation, and
  deletion candidate
- docs show delayed-review apply as advisory and same-task apply as an optimization
- examples avoid depending on filesystem paths

Tests:

- fixture integration test that runs the whole analyze/review/apply path
- docs examples compiled or exercised through the existing MOO test harness where practical
- import/export round-trip after apply
- run `cargo test -p moot objdef`
- run `cargo test -p moor-kernel objdef`
- run `cargo test -p moor-objdef objdef`

## Open Questions

- What is the smallest conflict key format that remains stable across analysis and apply?
- What exact resolution values should be accepted for each conflict kind?
- Which parts of base fingerprint metadata are runtime-owned conventions versus package-manager
  conventions?
- What bounded diff shape should `value_diff()` / `value_diff3()` return for strings, lists, maps,
  and opaque values?

## Recommendation

Treat changelist analysis as a separate proposal from `load_object()`.

The first useful version is probably:

- identity-preserving only
- `preview_objdef_changes(definitions [, options])`
- `apply_objdef_changes(definitions, resolutions [, options])`
- no target map
- no fresh-object remapping
- no opaque graph handle
- no full object bodies in the returned value
- separate bounded value/source diff builtin for review UI
- wizard-only builtins
- no package management policy in Rust
- apply implemented as a reparse/revalidate/apply operation
- `resolutions` used as the MOO policy input for conflicts and other non-automatic changes

That gives MOO package code a graph-aware review primitive without committing mooR to a full runtime
package manager.
