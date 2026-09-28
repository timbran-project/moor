<!-- Copyright (C) 2026 The mooR Authors -->
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

# Contextual suggestions

Suggestions are read-only queries over Cowbell's command environment. They do not execute commands,
run transfer policies, or predict whether an action will succeed. Meadow's inspector is the first
consumer; the request and response are independent of that UI.

## Request and response

Any object inherits this endpoint:

```moo
provider:suggestions(source, query, ?template = "", ?limit = 12)
```

`source` names a candidate source, `query` is the text being entered, and `template` optionally binds
the surrounding command. A template contains one `{input}` occupying a complete direct or indirect
object argument, for example `put {input} in #48` or `unlock #66 with {input}`. A request may return at
most 50 rows; query and template lengths are limited to 256 and 1024 characters respectively.

The authenticated task player supplies the viewing identity. Callers cannot request another
player's private inventory by changing the provider.

```text
{
  items: [{ id, label, value, detail }],
  more: boolean
}
```

`id` distinguishes choices; `label` is shown in the field; `value` is inserted into the command.
For object choices, `value` and `detail` contain the object reference. Duplicate names therefore
remain distinguishable and selecting one cannot resolve to a different object because of its name.
`more` asks the client to narrow the query; the endpoint does not return an unbounded catalog.

## Shared environmental search

`player:match_environment(command, context)` accepts these context keys:

| Key | Meaning |
| --- | --- |
| `'scope` | `"nearby"` (default), `"inventory"`, or `"contents"` |
| `'target` | The container for `contents`; the object to exclude for `inventory` |

The default retains the command scope: player, inventory, worn items, mailbox, and room-contributed
objects/aliases. Inventory narrows that scope to carried items. Contents expands into an explicitly
specified, reachable target through `target:match_scope_for(player, context)`.

Rooms and containers contribute through the same `match_scope_for` hook. Containers expose contents
only while reachable and open and when their existing general viewing rule permits it. `contents()`
and `look_self()` share that visibility check, including a reach/open recheck after authored rule
callbacks. Object names, aliases, and additional environmental aliases enter the shared ranking
step; repeated scope entries collapse to one row while retaining their aliases.

For command-name suggestions, query the player with source `"commands"`. This uses the existing
`verb_suggestions()` catalog, whose discovery walks `command_environment()`. The command strip
continues using that catalog's richer signature/hint metadata.

## Matching a known command

When a template is supplied, `$match:matching_suggestions`:

1. Parses the template once using `parse_command`, with a placeholder in its unfilled object slot.
2. Substitutes each scoped object into that slot in the parsed command map.
3. Calls `find_command_verb` against the player's existing command environment, including direct
   and indirect targets and inherited verb signatures.
4. Keeps candidates with a matching command verb. An ambiguous fixed argument is checked against
   each of its parser-provided candidates, as in normal command dispatch.

This checks verb names, prepositions, and direct/indirect argspecs without calling
`dispatch_command_verb`. It does not reveal the correct key by evaluating an unlock policy. Custom
room handlers outside normal verb matching need an authored candidate source if they want to offer
completion.

The shared ranker orders exact, prefix, word-prefix, and substring matches, case-insensitively.
It retains provider order within each rank and strips internal search keys from the response.

## Authoring sources

Objects can override `suggestion_candidates(source, query, template)` for domain-specific choices,
returning candidate maps with `id`, `label`, `value`, optional `detail`, and optional `keys` (aliases).
Use `pass(@args)` for the environmental sources. Keep providers side-effect-free and enforce viewing
rules before returning any candidate. The shared endpoint handles query validation, ranking,
deduplication, and response limits.

For object sources, extend environmental scope hooks instead of reconstructing visibility and
matching inside the provider. A source for non-object text, such as colors, can return labelled
string values directly.

An inspector action opts into suggestions through its input descriptor:

```moo
["id" -> "take_from", "label" -> "Take from", "command" -> "get {input} from " + tostr(this),
  "input" -> ["label" -> "What are you taking out?", "placeholder" -> "Find an item inside…",
    "suggestions" -> ["provider" -> $url_utils:to_curie_str(this), "source" -> "contents"]]]
```

Meadow supplies the action's command template with each request. Its reusable `SuggestionInput`
and `useSuggestions` components support debounced queries, immediate choices on focus, pointer
selection, arrow keys, Enter/Tab selection, and stale-response rejection. Selection fills the field;
submission remains a separate action through the existing command connection. Editing a selected
label clears its bound reference. Escape dismisses choices before dismissing the inspector.

The inspector refreshes suggestions on the same connection state revisions as inspection data.
There is no polling. Typed input remains usable if suggestions fail, and command execution always
rechecks current state and authority.
