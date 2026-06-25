# Structural Value Diffs

Sometimes a program needs to know more than whether two values are equal. It needs to know _how_
they are different.

For example, suppose an object property used to contain this list:

```
{"north", "south", "east"}
```

and now it contains this list:

```
{"north", "south", "west"}
```

A normal equality check can only answer one question:

```
old == new   =>   false
```

A diff answers the next question: what changed? In this case, item 3 changed from `"east"` to
`"west"`.

The word _structural_ means that mooR looks inside lists, maps, and flyweights instead of treating
the whole value as one big blob. If two maps differ in one key, `value_diff()` reports that key. If
two lists differ in one position, it reports that position. If two flyweights differ in a slot, it
reports the slot.

The diff format is ordinary MOO data: maps, lists, strings, numbers, booleans, and the values being
compared when requested. Result maps use string keys.

## Why Use This?

Use `value_diff()` when your program wants to explain a change to another program or to a person.

Common uses include:

- Showing a builder what changed in a property value after an edit.
- Checking whether an imported package would change an existing object.
- Recording a compact explanation of a value change in metadata or logs.
- Building editor tools that can highlight changed parts of lists, maps, or flyweights.

Use `value_diff3()` when you have a stored base value and two edited versions of it. This is the
same situation version-control tools handle when they compare a base file, your edited file, and
someone else's edited file.

For example:

```
base      = ["title" -> "Old title", "count" -> 1];
local     = ["title" -> "My title",  "count" -> 1];
incoming  = ["title" -> "Old title", "count" -> 2];
```

Here, `local` changed `"title"` and `incoming` changed `"count"`. A future merge tool might be able
to combine those changes. The current `value_diff3()` builtin is more conservative: it automatically
resolves only the simple cases where one side did not change, or both sides changed to the same
value. When both sides changed differently, it reports a manual conflict and gives you the two diffs
to inspect.

## `value_diff`

```
map value_diff(any old, any new [, map options])
```

Returns a bounded structural diff from `old` to `new`.

Here is a small example:

```
diff = value_diff({"north", "south", "east"},
                  {"north", "south", "west"});

diff["equal"]                       =>   false
diff["kind"]                        =>   "list"
diff["changes"][1]["index"]         =>   3
diff["changes"][1]["diff"]["kind"]  =>   "replace"
```

That result says: the values are not equal, they are both lists, and the first reported change is at
list index 3. The nested diff says that the old item should be replaced by the new item.

If the values are equal, the result is:

```
[
  "equal" -> true,
  "kind" -> "unchanged",
  "truncated" -> false,
  "changes" -> {}
]
```

If the values differ, `"equal"` is false and `"kind"` describes the structural case:

- `"replace"`: the values have different types, or recursion stopped at the configured depth.
- `"list"`: both values are lists.
- `"map"`: both values are maps.
- `"flyweight"`: both values are flyweights.

### List Diffs

List diffs trim identical prefixes and suffixes before comparing the middle. Same-length changed
regions are reported as per-index changes. Different-length regions use an LCS pass when the region
is small enough, otherwise the region is reported as one range replacement.

```
diff = value_diff({1, 2, 3}, {1, 2, 4});
diff["kind"]                         =>   "list"
diff["old_len"]                      =>   3
diff["new_len"]                      =>   3
diff["changes"][1]["op"]             =>   "change"
diff["changes"][1]["index"]          =>   3
diff["changes"][1]["diff"]["kind"]   =>   "replace"
```

List change entries use these shapes:

```
["op" -> "change", "index" -> index, "diff" -> nested_diff]
["op" -> "add", "index" -> index, "value" -> value_or_type_summary]
["op" -> "remove", "index" -> index, "value" -> value_or_type_summary]
["op" -> "replace_range", "old_start" -> old_start, "old_len" -> old_len,
 "new_start" -> new_start, "new_len" -> new_len]
```

Indexes are MOO list indexes: the first item is index 1.

### Map Diffs

Map diffs compare map entries in deterministic key order. Each change is an add, remove, or nested
change at a key.

```
diff = value_diff(["title" -> "Old", "count" -> 1],
                  ["title" -> "New", "count" -> 1]);

diff["kind"]                         =>   "map"
diff["changes"][1]["op"]             =>   "change"
diff["changes"][1]["key"]            =>   "title"
diff["changes"][1]["diff"]["kind"]   =>   "replace"
```

Map change entries use these shapes:

```
["op" -> "change", "key" -> key, "diff" -> nested_diff]
["op" -> "add", "key" -> key, "value" -> value_or_type_summary]
["op" -> "remove", "key" -> key, "value" -> value_or_type_summary]
```

### Flyweight Diffs

Flyweight diffs compare the delegate, slots, and contents. Slot changes are reported by symbol key.
Contents are compared as a list.

The top-level flyweight result has `"kind" -> "flyweight"` and a `"changes"` list. Each change has
an `"op"` key and either a `"field"` key for delegate, slots, or contents, or a nested `"diff"` /
`"changes"` value for the field.

### Replacement Diffs

Replacement diffs include the old and new type names:

```
diff = value_diff(1, "one");

diff["kind"]       =>   "replace"
diff["old_type"]   =>   "int"
diff["new_type"]   =>   "str"
```

If `include_values` is true, replacement, add, and remove entries include the compared value when it
is a small atom: none, boolean, integer, float, object, symbol, or error. Strings, binaries, lists,
maps, flyweights, and lambdas are summarized by type instead of copied into the diff.

```
diff = value_diff(1, 2, ["include_values" -> true]);

diff["old"]   =>   1
diff["new"]   =>   2
```

## `value_diff3`

```
map value_diff3(any base, any local, any incoming [, map options])
```

Performs a conservative three-way comparison using the same structural diff engine. It does not try
to merge overlapping edits. Instead, it identifies the cases that can be resolved without looking
inside the edit:

- `local == incoming`: both sides made the same change.
- `base == local`: only `incoming` changed.
- `base == incoming`: only `local` changed.

For resolved cases, the result is:

```
[
  "ok" -> true,
  "kind" -> "resolved",
  "conflict" -> false,
  "resolution" -> "same" | "incoming" | "local",
  "value" -> resolved_value,
  "diff" -> diff_from_base_to_resolved_value
]
```

Example:

```
diff = value_diff3({1, 2}, {1, 2}, {1, 3});

diff["ok"]           =>   true
diff["resolution"]   =>   "incoming"
diff["value"]        =>   {1, 3}
```

If both sides changed differently, the result is a manual conflict:

```
[
  "ok" -> false,
  "kind" -> "conflict",
  "conflict" -> true,
  "resolution" -> "manual",
  "local_diff" -> value_diff(base, local, options),
  "incoming_diff" -> value_diff(base, incoming, options)
]
```

This shape is useful for commit-time checks: code can accept resolved cases directly and show
`local_diff` / `incoming_diff` to a user or tool when a manual decision is required.

## Options

Both functions accept the same optional map:

```
[
  "max_depth" -> int,
  "max_changes" -> int,
  "max_lcs_cells" -> int,
  "include_values" -> truthy_value
]
```

- `"max_depth"` limits recursive comparison depth. The default is 8. It must be non-negative.
- `"max_changes"` limits the number of changes reported inside one structural node. The default is
  128. It must be positive.
- `"max_lcs_cells"` bounds the dynamic-programming work used for list insert/delete matching. The
  default is 16384. It must be non-negative.
- `"include_values"` controls whether small atom values are copied into add/remove/replace entries.
  It is false by default.

Unknown option keys raise `E_INVARG`. Non-map options, non-string/non-symbol option keys, and
non-integer numeric options raise `E_TYPE`. Out-of-range numeric options raise `E_RANGE`.

## Practical Use

Use `value_hash()` when all you need is a stable fingerprint. Use `value_diff()` when you need to
explain what changed. Use `value_diff3()` when comparing a stored base value with two edited values
and you need to separate simple auto-resolution from manual conflicts.
