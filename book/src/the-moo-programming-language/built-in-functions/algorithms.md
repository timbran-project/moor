# Structured Data Matching and Pathfinding

These mooR extensions provide kernel-side algorithms for structured MOO values. They are intended
for cases where MOO code would otherwise spend a large amount of time walking nested lists, maps, or
list-backed data structures in tight loops. Two kinds of algorithms are provided: pattern matching
for structured data, and pathfinding for tile-based maps.

## Pattern matching for structured data

Suppose your world stores exits as records like `{'exit, #10, 'north, #20}`. To find every exit
leaving room #10, you might write something like this:

```moo
found = {};
for rec in (exit_records)
  if (rec[2] == #10)
    found = {@found, rec};
  endif
endfor
```

That works for a handful of records. But when the list grows long, or the record shape gets more
complicated, the per-record check slows down and the code to pick apart each record gets harder to
read.

The `term_*` builtins make that per-record check faster and simpler. You still loop over the list in
MOO, but instead of pulling each record apart by hand, you write a pattern that describes what you
are looking for and let the server do the structural comparison at kernel speed.

You can think of them as pattern matching for structured data, similar to how
[`match()`](regex.md#match) searches for a regex pattern in a string — but they work on lists and
maps instead of on text, and the "captures" are named placeholders rather than numbered groups.

A **pattern** is a MOO value with "holes" in it. Each hole is a placeholder, written as a two-item
list:

```moo
{'var, 'Name}
```

This means "any value goes here — call it `Name`". A **term** is just the MOO value you want to
check against the pattern. When the structure matches, every hole gets filled in and you receive a
map of the filled-in values.

For example, this pattern:

```moo
{'edge, {'var, 'From}, {'var, 'To}}
```

matches this value:

```moo
{'edge, #10, #11}
```

and produces this binding map:

```moo
['From -> #10, 'To -> #11]
```

The server does not know what your records mean. A list like `{'edge, #10, #11}` might mean "there
is an edge from `#10` to `#11`", and a map like `["action" -> "property_write", "object" -> #123]`
might mean "write a property on `#123`" — but the server only sees lists, maps, symbols, strings,
objects, and numbers. It matches structure, not meaning.

Common uses for these functions include:

- Searching a list of records for ones that match a particular shape.
- Checking whether a rule or policy matches the current situation.
- Matching event or command descriptions.
- Filling in an action structure from values that were matched.

For example, a builder tool might store exits as `{'exit, from, direction, to}` records, then ask
for all exits whose `from` value is the current room. A policy helper might match a validated
request and then fill in an action structure from the values that were matched.

Only lists and map values are searched recursively. Map keys are treated as fixed keys, not
placeholders.

These builtins do not inspect world state, object ownership, task permissions, or call MOO verbs.

## `term_unify`

```moo
MAP | BOOL term_unify(ANY pattern, ANY value [, MAP bindings [, MAP options]])
```

Compares a pattern with a value and fills in placeholders when the surrounding structure matches.
Placeholders in the pattern are represented as:

```moo
{'var, 'Name}
```

On success, `term_unify()` returns a bindings map keyed by placeholder symbol. On ordinary mismatch,
it returns false.

```moo
term_unify({'edge, {'var, 'From}, {'var, 'To}}, {'edge, #10, #11})
=> ['From -> #10, 'To -> #11]
```

Repeated variables must match the same value:

```moo
term_unify({'edge, {'var, 'From}, {'var, 'From}}, {'edge, #10, #11})
=> 0
```

Existing bindings are respected:

```moo
term_unify({'edge, {'var, 'From}, {'var, 'To}},
           {'edge, #10, #11},
           ['From -> #10])
=> ['From -> #10, 'To -> #11]
```

Lists are compared item by item and must have equal length. Maps must have the same keys; values
under those keys are compared recursively. Non-placeholder values compare with normal MOO equality.

Malformed variable markers, such as `{'var}`, `{'var, 'A, 'B}`, or `{'var, "A"}`, raise `E_INVARG`.

MOO symbols compare case-insensitively, so `'From` and `'from` are the same variable identifier.
Initial capitals are only a naming convention.

## `term_substitute`

```moo
ANY term_substitute(ANY template, MAP bindings [, MAP options])
```

Returns a copy of a structured value with every `{'var, name}` placeholder replaced by the
corresponding binding.

If `term_unify()` is "match a pattern against a value and pull values out", then `term_substitute()`
is the reverse: "push values into a template". You might match a request with `term_unify()`, then
build a response with `term_substitute()`.

```moo
term_substitute({"property_write", {'var, 'Target}, "description"},
                ['Target -> #123])
=> {"property_write", #123, "description"}
```

By default, unbound variables raise `E_INVARG`. To leave unbound markers in place, pass
`['unbound -> 'leave]`:

```moo
term_substitute({"property_write", {'var, 'Missing}},
                [],
                ['unbound -> 'leave])
=> {"property_write", {'var, 'Missing}}
```

## Options

Both functions accept these options:

```moo
[
  'max_depth -> 64,
  'max_bindings -> 256
]
```

`term_substitute()` also accepts:

```moo
['unbound -> 'raise]  "default"
['unbound -> 'leave]
```

`max_depth` limits recursive traversal. `max_bindings` limits the number of variables that may be
present in the binding set.

## Pathfinding with `astar`

The `astar()` function is separate from the `term_*` functions above. It can be used to find the
shortest walkable path between two points on a flat list that represents a two-dimensional tile grid
— like a game map. You might use it to route an NPC around walls in a dungeon, or find a walkable
route across an overworld. Writing a pathfinder in MOO is possible but slow for large maps;
`astar()` does the search at kernel speed.

```moo
LIST astar(INT width, INT height,
           INT start_x, INT start_y,
           INT goal_x, INT goal_y,
           LIST tile_map, LIST solid_tiles)
```

Returns a list of `{x, y}` waypoints from the start to the goal, excluding the start position. If no
path exists, it returns `{}`.

### The tile map

The map is a flat list of tile IDs, laid out left-to-right, top-to-bottom. Think of it as reading
the grid row by row, like lines of text:

```moo
tile_map = {
  1, 1, 2,
  1, 3, 1
}
```

For a width of 3, that represents this 3-by-2 grid:

```text
(0,0)=1  (1,0)=1  (2,0)=2
(0,1)=1  (1,1)=3  (2,1)=1
```

Coordinates are zero-based: `(0, 0)` is the top-left tile, `(width-1, height-1)` is the
bottom-right.

To look up the tile at position `(x, y)` in the list, use:

```moo
index = y * width + x + 1
```

The `+ 1` accounts for MOO lists being one-based.

### Walkable and solid tiles

Each tile has an integer ID. You tell `astar()` which IDs are impassable by passing them in
`solid_tiles`. Any tile whose ID is in that list is treated as a wall; everything else is walkable.
Extra entries in `tile_map` past `width * height` are ignored. Missing entries are treated as
walkable.

### Movement

Movement is 8-directional (including diagonals). Diagonal moves are only allowed when both adjacent
cardinal tiles are also walkable, so paths cannot cut through the corner of a wall:

```text
.  .  .
X  .  .          X = solid
.  .  .
```

Moving diagonally from `(0, 0)` to `(1, 1)` might look open — the destination is floor — but the
adjacent tile `(0, 1)` is solid, so the diagonal is blocked. You would have to step to `(1, 0)`
first, then down to `(1, 1)`.

Without that restriction, the path would cut through the corner of the wall tile.

### Example

A 3-by-3 open grid with start at `(0, 0)` and goal at `(2, 2)`:

```moo
astar(3, 3,
      0, 0,
      2, 2,
      {
        1, 1, 1,
        1, 1, 1,
        1, 1, 1
      },
      {9})
=> {{1, 1}, {2, 2}}
```

The path reaches the goal in two diagonal steps. Diagonal moves cost the same as cardinal moves, so
this is a shortest valid path.

### Notes

The exact path is deterministic for a given map, but callers should treat any shortest valid path as
acceptable. If the goal tile is solid, or no route reaches it, the function returns `{}`. Invalid
dimensions or out-of-bounds start/goal coordinates raise `E_INVARG`.
