# Structured Term Builtins

This note describes the mooR builtin surface for structural matching, bounded rule queries, and
structural substitution over ordinary MOO values. These builtins are generic runtime helpers, not a
Cowbell-only feature.

The motivating use cases are MOO code that currently performs repeated structural matching,
recursive rule walks, binding merges, and template instantiation in MOO:

- rule engines over list-backed facts,
- relation-like tuple stores,
- policy helpers that derive action structures from validated facts.

The builtins must remain pure over caller-supplied values. They must not know about Cowbell
capability names, builder concepts, rooms, areas, or rule-engine verb naming conventions.

## Core Concepts

A term is any MOO value. Lists and map values are traversed recursively. Map keys are fixed keys,
not placeholders.

A variable marker is a two-item list:

```moo
{'var, 'Name}
```

The first element is the literal symbol `'var`; the second element is the variable identifier.
Bindings are maps keyed by the variable identifier:

```moo
['From -> #10, 'To -> #11]
```

The identifier is a symbol in v1. Malformed variable markers, such as `{'var}`, `{'var, 'A, 'B}`, or
`{'var, "A"}`, raise `E_INVARG`.

MOO string and symbol comparisons are case-insensitive. Initial-capitalized variable names are only
a readability convention; `'From` and `'from` are the same variable identifier.

## Builtins

### `term_unify(pattern, value[, bindings[, options]])`

Matches one pattern against exactly one supplied value.

```moo
term_unify({'edge, {'var, 'From}, {'var, 'To}}, {'edge, #10, #11})
=> ['From -> #10, 'To -> #11]
```

An ordinary mismatch returns false:

```moo
term_unify({'edge, {'var, 'From}, {'var, 'From}}, {'edge, #10, #11})
=> 0
```

Initial bindings are respected:

```moo
term_unify({'edge, {'var, 'From}, {'var, 'To}},
           {'edge, #10, #11},
           ['From -> #10])
=> ['From -> #10, 'To -> #11]
```

This is the binding-extension primitive for code that already has one candidate value. It is
separate from `term_query()`, which searches a list of facts and optional rules and always returns a
list of solutions.

### `term_query(query, facts[, rules[, bindings[, options]]])`

Searches caller-supplied facts and optional positive rules for every way to satisfy one query.

For search over explicit facts, pass a list of facts:

```moo
term_query({'edge, {'var, 'From}, {'var, 'To}},
           {{'edge, #10, #11}})
=> {['From -> #10, 'To -> #11]}
```

An ordinary mismatch returns an empty list:

```moo
term_query({'edge, {'var, 'From}, {'var, 'From}},
           {{'edge, #10, #11}})
=> {}
```

Initial bindings are respected:

```moo
term_query({'edge, {'var, 'From}, {'var, 'To}},
           {{'edge, #10, #11}},
           {},
           ['From -> #10])
=> {['From -> #10, 'To -> #11]}
```

Facts may be ground or partially ground. Variables inside facts are fresh for each attempted match
and are not returned as output variables.

Rules have shape `{head, body}`. The head is one term. The body is a list of positive terms:

```moo
{
  {'reachable, {'var, 'A}, {'var, 'B}},
  {
    {'edge, {'var, 'A}, {'var, 'B}}
  }
}
```

Recursive rules are allowed and bounded:

```moo
rules = {
  {
    {'reachable, {'var, 'A}, {'var, 'B}},
    {
      {'edge, {'var, 'A}, {'var, 'B}}
    }
  },
  {
    {'reachable, {'var, 'A}, {'var, 'B}},
    {
      {'edge, {'var, 'A}, {'var, 'C}},
      {'reachable, {'var, 'C}, {'var, 'B}}
    }
  }
};

term_query({'reachable, #1, {'var, 'Where}},
           {
             {'edge, #1, #2},
             {'edge, #2, #3},
             {'edge, #3, #4}
           },
           rules)
=> {['Where -> #2], ['Where -> #3], ['Where -> #4]}
```

The v1 rule language is intentionally small:

- Positive Horn-style clauses only.
- No negation.
- No aggregation.
- No cuts.
- No arithmetic or comparison predicates.
- No implicit fact providers.
- No MOO callbacks.
- No world access or permission checks.

Every variable in a rule head must also appear in that rule's positive body. Use facts for base
cases.

Results are deterministic: facts are tried in fact-list order, rules are tried in rule-list order,
and the first occurrence of a duplicate result is kept when dedupe is enabled.

### `term_substitute(template, bindings[, options])`

Returns a copy of `template` with all variable markers replaced by their bound values.

```moo
term_substitute({"property_write", {'var, 'Target}, "description"},
                ['Target -> #123])
=> {"property_write", #123, "description"}
```

Substitution is recursive through lists and map values. Ground values are returned unchanged.
Unbound variables raise `E_INVARG` by default. Callers may explicitly leave unbound markers in
place:

```moo
term_substitute({"property_write", {'var, 'Missing}},
                [],
                ['unbound -> 'leave])
=> {"property_write", {'var, 'Missing}}
```

This is structural substitution. It is separate from the string `substitute()` builtin.

## Options

`term_unify()` and `term_substitute()` accept:

```moo
[
  'max_depth -> 64,
  'max_bindings -> 256
]
```

`term_substitute()` also accepts:

```moo
[
  'unbound -> 'raise
]
```

For `term_substitute()`, `'unbound -> 'leave` preserves unbound variable markers instead of raising.

`term_query()` accepts:

```moo
[
  'max_depth -> 32,
  'max_bindings -> 256,
  'max_solutions -> 256,
  'max_steps -> 10000,
  'dedupe -> true
]
```

## Security Requirements

The builtin surface is deliberately small:

- It operates on supplied MOO values only.
- It is pure over those supplied values.
- It does not call arbitrary MOO verbs.
- It does not inspect current task permissions, caller permissions, object ownership, object flags,
  property permissions, verb permissions, or world state.
- It does not perform object lookups or name resolution.
- It does not know about Cowbell capability names.
- It does not install task permissions or runtime grants.
- It has deterministic limits for recursive structures, result count, and total search work.
- Malformed inputs raise. Ordinary `term_unify()` mismatch returns false; ordinary `term_query()`
  mismatch returns no solutions.

Runtime grant construction must remain explicit. A successful query does not itself install task
permissions. A user-space caller must still construct the grant values and call the relevant runtime
operation explicitly.
