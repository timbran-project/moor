# Command Error Handling Audit

This audit covers command verbs on:

- `$player` (`src/player.moo`)
- `$prog_features` (`src/features/prog_features.moo`)
- `$admin_features` (`src/features/admin_features.moo`)
- `$builder_features` (`src/features/builder_features.moo`)
- `$social_features` (`src/features/social_features.moo`)

It also covers the utility objects those commands commonly delegate to:
`$prog_utils`, `$obj_utils`, `$match`, `$url_utils`, `$help_utils`,
`$grant_utils`, `$sub_utils`, `$property`, `$verb`, and nearby command helper
objects where the same pattern is relevant.

The point of this document is to describe how errors are currently formulated,
where broad defensive patterns occur, and which places are most likely to hide
real regressions behind empty output or generic messages.

## Pattern Taxonomy

### A. Entry-Point Reporting

The command catches an error at the player-facing boundary and reports it with
`inform_current($event:mk_error(...))`.

This is the pattern we want most command code to converge on, but it should be
paired with helpers that raise meaningful errors instead of pre-swallowing them.

Examples:

- `@rmverb`, `@args`, `@program`, `@which`, `@mvverb`, `@cpverb` in
  `$prog_features`.
- Most builder commands in `$builder_features`.
- Sudo commands in `$admin_features`.

### B. Inline Defaulting

The command or helper catches an expression inline and substitutes a sentinel:

```moo
value = `expr ! ANY => default';
```

This is reasonable for optional display cosmetics, such as names in a table,
but it is risky for structural operations, metadata lookup, command dispatch,
or authority checks.

High-risk examples:

- `$player:look` uses `$match:match_object(...) ! ANY => E_NONE`.
- `$prog_features:@show` property-list metadata used
  `$prog_utils:get_property_metadata(...) ! E_PERM => 0`, then skipped non
  flyweights.
- `$admin_features:@sudo` uses many `! ANY => {}` / `$nothing` defaults while
  constructing the sudo dispatch context.
- `$builder_features` uses inline defaults extensively while inspecting rooms,
  passages, rules, reactions, and message templates.

### C. Shape Guard Plus Skip

The command catches or defaults a value, checks the type, and silently skips the
entry:

```moo
metadata = `lookup(...) ! E_PERM => 0';
if (typeof(metadata) != TYPE_FLYWEIGHT)
  continue;
endif
```

This is the specific pattern that made `@show $player.` and `@show $player..`
look like they had no rows. It is appropriate only when malformed or
inaccessible entries are expected data, not when it can hide broken helper
contracts.

Common sites:

- `$prog_features:@show`, `$prog_features:@grep`.
- `$player:help`, command suggestions, ambient verb collection, travel/join
  matching, and assist suggestions.
- `$obj_utils:collect_ambient_verbs` and `$obj_utils:collect_targetable_verbs`.
- `$admin_features:@sudo-show`, `@sudo-who`, `@sudo-log`.
- `$builder_features:@audit`, parent/child traversal, passage searches.

### D. Broad `except ANY`

The command catches every exception and turns it into a generic player message.

This is acceptable only at the command boundary if the message includes enough
detail and no helper has already converted the real failure into a bogus value.
It is risky inside helper loops and inside command bodies around large blocks.

Examples:

- `$builder_features` uses broad `except e (ANY)` for nearly every mutating
  command.
- `$prog_features` uses broad catches around most programmer commands.
- `$player` uses broad catches around examine/help/gag/assist flows.
- `$admin_features:@sudo` catches parser and delegate-call failures, logs them,
  and reports a generic sudo failure.

### E. Silent Optional Cosmetic Fallback

Inline defaults are relatively safe when the value is purely decorative:

```moo
obj_name = `obj.name ! ANY => tostr(obj)';
```

These should be left alone unless they are mixed into control flow. They are
common across all five objects.

## Count Summary

These are grep-based counts from the current checkout. They are not semantic
proof of severity, but they show how widespread each style is. Command counts
are approximate because some player-facing commands are unquoted single-name
verbs while others are quoted alias groups.

| Object | Command verbs | Inline `! ANY =>` | Broad `except ANY` | `! E_PERM =>` | `continue;` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `$player` | 23 | 124 | 10 | 0 | 61 |
| `$prog_features` | 24 | 54 | 45 | 4 | 15 |
| `$admin_features` | 8 | 60 | 3 | 0 | 14 |
| `$builder_features` | 34 | 67 | 36 | 0 | 6 |
| `$social_features` | 20 | 5 | 0 | 0 | 3 |

## `$player`

`$player` mixes direct player commands, message/rendering helpers, and command
assist logic. It is the noisiest object because it uses command dispatch,
matching, help source aggregation, editor sessions, DM/mail delivery, travel,
and LLM-assisted suggestions.

### Commands

| Command | Current formulation | Defensive patterns | Risk |
| --- | --- | --- | --- |
| `look` | Match object/passage, then render object or passage; not-found/ambiguous reported directly. | `$match:match_object(...) ! ANY => E_NONE`; name/alias loops skip bad entries. | High: broad match failure can hide matcher regressions and collapse them into not-found behavior. |
| `inventory` | Renders carried item names as a list. | Cosmetic defaults for display names. | Low. |
| `who @who` | Match optional player, otherwise render connected players. | `last_connected` / `last_disconnected` defaulting; idle checks. | Low to medium; mostly display fallback. |
| `@pronouns` | Direct validation and preset lookup; reports unknown sets. | Type guard for pronoun flyweight. | Low. |
| `@password` | Validates old/new password paths and reports usage. | Type guard on password flyweight. | Low. |
| `put` | Reports that players are not containers. | No defensive helper work. | Low. |
| `examine x` | Match object, call `:examination()`, render owner/location/verbs. | Broad match catch; skips if examination is not a flyweight; cosmetic owner fallback. | Medium: helper contract failures become "could not examine." |
| `help what` | Aggregates help sources, object help, command context, and programmer docs. | Many `! ANY => 0` fallbacks, flyweight type guards, source loops that skip malformed topics. | High: broken help providers can disappear from output. |
| `dm pm tell page` | Match target player, create/deliver DM. | Delivery result defaults with `! ANY => E_NONE`. | Medium: delivery failures can be presented as ordinary status unless explicitly checked. |
| `reply` | Sends DM to last correspondent. | Delegates to DM path; target/message fallback behavior. | Medium. |
| `dms messages msgs mail` | Finds mailbox and renders message list. | Mailbox and message properties defaulted. | Medium. |
| `message` | Displays a single message. | Message/mailbox fallbacks. | Medium. |
| `@gag` | Match target and add gag entry. | Broad catch reports generic failure. | Medium. |
| `@ungag` | Match target and remove gag entry. | Broad catch reports generic failure. | Medium. |
| `@listgag listgag` | Renders gag list. | Type/shape skips. | Medium: malformed gag entries are silently ignored. |
| `walk go_to goto` | Resolve passage or nearby room, then travel. | `find_passage_by_direction(...) ! ANY => false`; `travel_from(...) ! ANY => false`; skips rooms with bad names/aliases. | High: real passage/travel errors can become "no route." |
| `join @join` | Match player and attempt travel toward their room. | `$match:match_player(...) ! ANY => $failed_match`; skips players with bad names. | Medium. |
| `home` | Attempts to travel home or reports why it cannot. | Area/name fallbacks and room placeholders. | Medium. |
| `@sethome` | Stores current room as home. | Mostly direct checks; room placeholders defaulted elsewhere. | Low. |
| `assist` | Builds LLM-backed command/help suggestions. | Heavy `! ANY =>`, JSON parse defaults, shape guards, and skipped candidates. | High: best-effort UX path but hides parser/context failures. |
| `stop` | Cancels current activity. | Activity description fallback. | Low. |
| Assist and suggestion helpers | Build command suggestions and LLM assistance. | Heavy `! ANY =>`, shape guards, and skips around pending assist maps, parse JSON, scope traversal, verb matching, passages, and topic suggestions. | High: these are intentionally best-effort, but they hide contract failures and make command parser regressions difficult to diagnose. |

### Delegates Used Heavily

- `$match`: object/player matching in `look`, `who`, `examine`, `help`, `dm`,
  `join`.
- `$obj_utils`: examination verb formatting and ambient/targetable verb
  collection.
- `$help_utils`: location help context and help display formatting.
- `$event` / `$format`: player-facing reporting.
- `$player_activity`: activity cancellation/status descriptions.

### Main Problem Shapes

- `look`, `help`, travel, and assist use broad defaulting in control flow.
- Help and assist loops silently skip malformed providers/topics/verbs.
- Direct display fallbacks are usually fine; structural defaults should be
  narrowed.

## `$prog_features`

`$prog_features` has the largest concentration of command-style error handling.
It often catches at the command boundary, which is good, but several helpers
and list renderers also catch internally and skip failed records.

### Commands

| Command | Current formulation | Defensive patterns | Risk |
| --- | --- | --- | --- |
| `@edit` | Match object/verb/property and launch editor. | Broad catches around edit target resolution and editor setup. | Medium. |
| `@browse` | Match and browse object/code. | Broad catch to generic match error. | Low to medium. |
| `@list` | Lists code or object state. | Broad catch; formatting helpers default. | Medium. |
| `@verb` | Adds verb after parsing target and args. | Broad catches for add/compile; prep validation via `$prog_utils`. | Medium. |
| `@rmverb` | Parses direct `object:verb`, resolves name, deletes. | Boundary catches distinguish match, verb, permission, and generic errors. | Low: one of the cleaner commands. |
| `@verbs` | Lists `verbs(target_obj)` as literal output. | Boundary catch only. | Low. |
| `@properties @props` | Lists `properties(target_obj)` as literal output. | Boundary catch only. | Low. |
| `@property` | Parses target, evaluates literal value, adds property. | Some parsing shortcuts; duplicate property special-case. | Medium. |
| `@rmproperty` | Parses direct property, optionally dry-run, deletes. | Boundary catches. | Low. |
| `@args` | Parses verb reference and edits/shows args. | Boundary catches; uses metadata helper. | Low to medium. |
| `@show @display` | Parses compound selectors, displays header and property/verb tables. | Per-selector broad catch; property metadata was caught as `E_PERM => 0` and skipped; rows now stringify symbol names. | High: table/list code still silently skips metadata failures. |
| `@chmod` | Parses selector, normalizes permission changes, applies metadata `set_perms`. | Boundary catches; explicit inherited-selector rejection. | Low to medium. |
| `@grep` | Searches verb code. | Many skip-on-shape guards; catches verb/code access failures and continues. | High: expected for a grep, but can hide broken metadata/listing APIs. |
| `@codepaste` | Reads paste content and emits code paste event. | Minimal defensive handling. | Low. |
| `@documentation @doc` | Parses object/verb/property/builtin docs. | Broad match catch; delegates heavily to `$help_utils`. | Medium. |
| `@rename` | Handles object rename and verb rename. | Boundary catches, string formatting defaults. | Low to medium. |
| `@ps @tasks` | Renders active/queued tasks. | Uses task structures directly; display fallbacks. | Low. |
| `@kill-task @kill` | Parses task id and kills task. | Boundary catches distinguish invalid/no/permission/generic. | Low. |
| `@chparent` | Changes parent with dry-run support. | Boundary catches. | Low. |
| `@program @program#` | Interactive and inline verb programming. | Many catch/report paths; `toint(...) ! ANY => 0`; broad read and compile catches. | Medium to high due to complex stateful flow. |
| `@clear-property` | Parses direct property and clears it. | Boundary catches. | Low. |
| `@which @where-defined` | Resolves verb definer. | Boundary catches. | Low. |
| `@mvverb` | Parses source/dest, copies code, deletes source. | Many boundary catches; dry-run/confirm gates. | Medium. |
| `@cpverb` | Parses source/dest, copies code. | Boundary catches and existing-verb checks. | Medium. |

### Utilities And Helpers

- `$prog_utils:parse_target_spec` is central for `@show`, `@chmod`,
  `@property`, `@rmproperty`, `@doc`, `@clear-property`, `@which`,
  `@mvverb`, and `@cpverb`.
- `$prog_utils:get_property_metadata` and `get_verb_metadata` are the main
  metadata boundary. These should raise typed errors and not be hidden by list
  renderers.
- `$prog_utils:eval_literal` returns `{success, value, remainder}` rather than
  raising; commands then branch manually.
- `$help_utils` handles documentation display and extraction.
- `$match` handles object resolution.

### Main Problem Shapes

- `@show` and `@grep` are the major skip-on-error list renderers.
- Several commands catch `ANY` around broad blocks and report `e[2]`, which is
  useful at the boundary but poor inside helpers.
- Parser and metadata helpers have mixed styles: some raise, some return
  sentinel tuples.

## `$admin_features`

`$admin_features` is mostly sudo delegation. It uses a lot of defaulting to keep
audit/status display resilient, but the same defaults are also used in sudo
dispatch setup.

### Commands

| Command | Current formulation | Defensive patterns | Risk |
| --- | --- | --- | --- |
| `@sudo-revoke` | Match target, remove delegate/allowlist entries, append audit log. | `dobj ! ANY => $nothing`, admin feature defaults, audit append swallowed. | Medium: audit append failure is silent. |
| `@sudo-allow` | Match target, parse allowlist specs, update allow map. | Skips malformed specs; `toobj(...) ! ANY => $nothing`; audit append swallowed. | Medium. |
| `@sudo-grant` | Match subject/delegate and grant delegation. | `dobj`/`iobj` defaulting, admin feature defaults, audit append swallowed. | Medium. |
| `@sudo` | Parse and dispatch a delegated command. | Heavy context defaulting; broad parse and dispatch catches; audit append swallowed; skips malformed features and verbs. | High: this is security-sensitive and has many silent fallbacks. |
| `@dump-database` | Calls `dump_database()` and reports success/failure. | Boundary `except ANY`. | Low. |
| `@sudo-show` | Shows configured sudo state and active tasks for target. | Skips malformed active entries; defaults map fields. | Medium. |
| `@sudo-who` | Lists active sudo and recent audit entries. | Skips malformed entries; defaults map fields. | Medium. |
| `@sudo-log` | Lists audit log entries. | `toint(...) ! ANY => 0`; skips malformed entries; defaults fields. | Medium. |

### Utilities And Helpers

- `$match:match_player` for target/delegate resolution.
- Internal `_append_log`, active sudo maps, and allowlist maps.
- `$help_utils:verb_help_from_hint` for help topics.

### Main Problem Shapes

- Audit logging failures are deliberately swallowed with `! ANY => 0`.
- Display commands skip malformed audit/active entries; acceptable for display,
  but it should log corruption.
- `@sudo` is the highest-risk command in this object because it mixes
  best-effort feature traversal, allowlist enforcement, delegated invocation,
  prompting, and audit logging.

## `$builder_features`

`$builder_features` is broad and mutable: creating, recycling, room building,
passages, movement, rules, reactions, messages, thumbnails, and prompt-driven
editing. It frequently catches `ANY` at the command boundary and uses many
inline fallbacks while inspecting world state.

### Commands

| Command | Current formulation | Defensive patterns | Risk |
| --- | --- | --- | --- |
| `@add-message` | Adds a message property/spec to an object. | Parses target via `$prog_utils`; broad catches; property existence and value handling are command-local. | Medium. |
| `@del-message` | Removes a message property/spec. | Parses target and catches broad failures. | Medium. |
| `@create` | Creates child object from a prototype and names it. | Broad catch; prototype/name display fallback. | Medium. |
| `@recycle @destroy` | Recycles a matched object. | Broad catch around destroy. | Medium. |
| `@grant` | Parses grant target/grantee/capability list and stores grant. | Broad catch; grant parsing/formatting delegated to `$grant_utils`. | Medium to high. |
| `@audit @owned` | Lists objects owned by a target. | Skips invalid/malformed object entries; display fallbacks. | Medium. |
| `@build` | Creates a room in an area. | Existing-room scan defaults names/contents; broad catch; capability lookup fallback. | High. |
| `@dig @tunnel` | Creates a passage between rooms. | Many passage/room slot defaults; conflict scans skip malformed passages; broad catch. | High. |
| `@undig @remove-exit @delete-passage` | Removes a matching passage. | Passage matching uses slot defaults and shape checks; broad catch. | High. |
| `@rename` | Renames an object. | Broad catch; old-name display fallback. | Medium. |
| `@describe` | Sets object or passage description. | Broad catch; compiles/decompiles substitution content with fallback. | Medium. |
| `@edit-description @edit-d` | Starts editor flow for description. | Broad catch; target/name display fallback. | Medium. |
| `@parent` | Displays/changes parent relationship. | Display fallbacks and broad catch. | Medium. |
| `@children @kids @descendants` | Displays child/descendant tree. | Skips invalid entries; display fallbacks; broad catch. | Medium. |
| `@integrate` | Integrates generated/temporary description into object. | Broad catch and display fallback. | Medium. |
| `@move` | Moves object to destination. | Broad catch; object/player/location defaults. | Medium. |
| `@edit` | Opens property/object editor. | Broad catch; delegates editor setup. | Medium. |
| `@set-message @setm` | Sets a message template property. | Broad catch; `$sub_utils` compile/decompile fallback. | Medium. |
| `@get-message @getm` | Reads a message template property. | Decompile fallback to literal; broad catch. | Medium. |
| `@set-rule` | Sets rule property. | Broad catch; rule parsing delegated. | Medium. |
| `@clear-rule` | Clears rule property. | Broad catch. | Medium. |
| `@show-rule` | Displays one rule property. | Broad catch and display fallback. | Medium. |
| `@messages @msg` | Lists message properties. | Property list helpers and decompile fallback; broad catch. | Medium. |
| `@rules` | Lists rule properties. | Broad catch and display fallback. | Medium. |
| `@reactions` | Lists reactions. | Broad catch; skips invalid reaction entries. | Medium. |
| `@add-reaction @set-reaction` | Adds or replaces a reaction. | Broad catch; reaction parsing/shape handling. | Medium. |
| `@enable-reaction` | Enables reaction. | Broad catch and reaction list shape handling. | Medium. |
| `@disable-reaction` | Disables reaction. | Broad catch and reaction list shape handling. | Medium. |
| `@parents @ancestors` | Displays ancestor chain. | Display fallbacks and broad catch. | Low to medium. |
| `@set-thumbnail @thumbnail` | Uploads/sets thumbnail. | Prompt/upload defaults; broad catch. | Medium. |
| `@passage @passage-info @pinfo` | Displays passage info. | Passage slot defaults. | Medium. |
| `@set-passage @setp` | Mutates passage fields. | Broad catch; string/list parsing and passage slot defaults. | Medium to high. |
| `#*` | Numeric/object reference command shortcut. | Delegates matching/display paths. | Medium. |
| `@show-reaction @showr` | Displays one reaction. | Broad catch and reaction shape handling. | Medium. |

### Utilities And Helpers

- `$prog_utils:parse_target_spec` for property/message/rule/reaction targets.
- `$match` for object/player matching.
- `$grant_utils` for grant formatting and parsing.
- `$sub_utils` for message template compile/decompile.
- Rule and reaction objects/utilities through rule/reaction properties.

### Main Problem Shapes

- Most mutating commands use command-boundary `except ANY`; that is tolerable
  if helpers raise typed messages, but helpers often default internally first.
- Passage and room commands are especially fallback-heavy because they scan
  existing world state and treat unreadable/malformed entries as non-matches.
- Message/rule/reaction commands often conflate "not configured" with "helper
  failed to read/decompile/parse."

## `$social_features`

`$social_features` is comparatively small and mostly event emission.

### Commands

| Command | Current formulation | Defensive patterns | Risk |
| --- | --- | --- | --- |
| `nod` | Optional target match, then social event. | Catches only `_match_social_target` `E_INVARG`; invalid location returns silently. | Low. |
| `wave` | Optional target match, then social event. | Same as `nod`. | Low. |
| `bow` | Optional target match, then social event. | Same as `nod`. | Low. |
| `bonk` | Requires target, handles self-target specially. | Catches only target-match `E_INVARG`; invalid location returns silently. | Low. |
| `oif` | Emits fixed say event. | Invalid location returns silently. | Low. |
| `smile` | Optional target match, then social event. | Same as `nod`. | Low. |
| `frown` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `laugh` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `dance` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `shrug` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `think` | Requires text and emits thought event. | Direct missing-text report; invalid location returns silently. | Low. |
| `ponder` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `applaud/clap` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `cheer` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `sigh` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `yawn` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `stretch` | Emits fixed social event. | Invalid location returns silently. | Low. |
| `|*` | Emits paste line event. | Minimal. | Low. |
| `http://* https://*` | Fetch URL preview then emit URL share. | `$url_utils:fetch_preview(url) ! ANY => false`; preview failures are silent. | Medium: acceptable user experience, poor observability. |
| `@paste paste` | Prompt for pasted content and emit paste event. | Prompt abort/type guard. | Low. |

### Utilities And Helpers

- `$url_utils:fetch_preview` catches HTTP errors and returns structured values
  or false.
- `$help_utils:verb_help_from_hint` for help lookup.
- `$match:match_object` in object-help lookup.

### Main Problem Shapes

- URL preview failures are hidden by design.
- Help-source lookup uses the same best-effort pattern as other help paths.

## Utility Object Notes

### `$prog_utils`

Current formulation:

- Raises for direct metadata lookup (`get_property_metadata`,
  `get_verb_metadata`) when runtime builtins fail.
- Returns sentinel tuples for `eval_literal`.
- Uses one inline `verb_code(...) ! ANY => false` in `grep_verb_code`.
- `get_verb_metadata` now handles string names against symbol-returning
  `verbs()` results.

Risk:

- Metadata helpers are good places to keep strict behavior, but callers often
  wrap them in inline catches and skip failures.
- `eval_literal`'s tuple-return style is fine if consistently documented, but
  it differs from the raising style.

### `$obj_utils`

Current formulation:

- `collect_ambient_verbs` and `collect_targetable_verbs` are best-effort
  scanners.
- They catch `o:examination()`, `ancestors`, `verbs`, and `verb_args`, then
  skip malformed entries.

Risk:

- This is appropriate for command suggestions, but it should not become the
  pattern for authoritative commands. It will hide symbol/string regressions,
  broken examination objects, or verb metadata failures.

### `$match`

Current formulation:

- Primarily raises match errors.
- Some branches catch `ANY` internally while trying parse alternatives.

Risk:

- Commands that catch `$match` broadly and convert to `$failed_match` lose the
  distinction between "not found" and "matcher broke."

### `$url_utils`

Current formulation:

- `fetch_preview` catches `ANY` and returns `false` for bad HTTP/url cases.

Risk:

- Good for optional previews; not good for any command where fetch failure is
  the requested operation.

### `$help_utils`

Current formulation:

- Formatting/extraction helpers use inline defaults for object/verb/property
  display and missing docs.

Risk:

- Help aggregators skip providers and malformed topics without surfacing which
  provider failed.

### `$property` and `$verb`

Current formulation:

- Metadata flyweights mostly call runtime builtins directly.
- `$property:value_string` catches `ANY` and returns `(error reading property)`.
- `$verb:code` catches `ANY` and returns `{}`.

Risk:

- Display helpers are fine to degrade. Mutating commands should not rely on
  these display methods for authoritative behavior.

## Recommended Consistent Pattern

### Command Boundary

Commands should have one top-level reporting boundary:

```moo
try
  this:_do_command(...);
except e (E_INVARG, E_PERM, E_VERBNF, E_PROPNF)
  player:inform_current($event:mk_error(player, tostr(e[2])));
except e (ANY)
  player:inform_current($event:mk_error(player, "Internal error: " + toliteral(e)));
endtry
```

The exact wording can vary, but the important rule is that helper failures
should arrive here with their meaning intact.

### Helper Methods

Helpers should generally raise typed errors:

- `E_INVARG` for invalid user input or malformed specs.
- `E_PERM` for authorization/access failures.
- `E_VERBNF` / `E_PROPNF` for missing verbs/properties.
- `E_TYPE` for broken helper contracts.

Avoid returning `0`, `false`, `{}`, or `$nothing` for internal failures unless
the helper's contract explicitly says it is a best-effort scanner.

### Display Scanners

Best-effort scanners may continue after known per-entry access failures, but
they should:

- Catch only expected errors, not `ANY`.
- Render a visible `(no access)` or `(error reading ...)` row when the entry is
  known but unreadable.
- Skip only entries that are genuinely optional or malformed external data.
- Consider logging unexpected shape violations.

### Inline Catch Rules

Allowed:

```moo
display_name = `obj.name ! ANY => tostr(obj)';
preview = `$url_utils:fetch_preview(url) ! ANY => false';
```

Discouraged:

```moo
metadata = `$prog_utils:get_property_metadata(obj, prop) ! E_PERM => 0';
typeof(metadata) != TYPE_FLYWEIGHT && continue;
```

Forbidden for security or mutating paths:

```moo
target = `$match:match_object(spec, player) ! ANY => $failed_match';
allowed = `some_authority_check(...) ! ANY => false';
```

## Priority Cleanup Targets

1. `$prog_features:@show`: replace metadata skip-on-`E_PERM` with explicit
   `(no access)` rows, and let unexpected metadata failures reach the command
   boundary.
2. `$prog_features:@grep`: decide whether it is best-effort search or strict
   programmer introspection; if best-effort, count/report skipped verbs.
3. `$player:look`, `walk`, and `join`: stop treating arbitrary matcher/travel
   failures as not-found.
4. `$player:help` and assist helpers: report provider/source failures in a
   debug/audit channel instead of silently dropping them.
5. `$admin_features:@sudo`: audit every `! ANY =>` fallback separately because
   this is security-sensitive. Audit-log append failures should be visible to
   wizards.
6. `$builder_features:@dig`, `@undig`, `@build`, and passage helpers: separate
   "no matching passage" from "passage object failed to inspect."
7. `$obj_utils` scanners: document them as best-effort and avoid reusing them
   for authoritative command behavior.

## Suggested Refactor Sequence

1. Add a small command reporting helper or convention doc for command-boundary
   catches.
2. Convert one command family at a time, starting with `$prog_features:@show`
   and `$prog_features:@grep`.
3. Move structural work into `_do_*` helpers that raise typed errors.
4. Replace inline `ANY` catches in structural paths with typed catches or no
   catch.
5. Leave cosmetic display defaults alone unless they influence control flow.
6. Add headless tests for each converted command/helper path before changing
   behavior.
