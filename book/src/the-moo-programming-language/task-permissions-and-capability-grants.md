# Task Permissions and Capability Grants

Every MOO task runs with an effective permissions object. Most tasks begin with the permissions of
the owner of the verb being executed. MOO code can inspect the direct caller's permissions with
`caller_perms()` and, in limited cases, can change the current task permissions with
`set_task_perms()`.

mooR also supports an extension to `set_task_perms()` that lets trusted wizard code attach
operation-specific capability grants to the current task. These grants are additive: they allow
particular operations that the task's permissions object would not otherwise be allowed to perform.
They do not replace the normal owner, wizard, object flag, property flag, or verb flag model.

## Changing Task Permissions

The one-argument form matches the traditional MOO model:

```moo
set_task_perms(perms)
```

If the current task is running with wizard permissions, `perms` may be any object. Otherwise,
`perms` must be the current task permissions object itself. The change applies to later operations
in the current activation and remains in effect until the task ends or `set_task_perms()` is called
again.

Normal MOO verb calls still create a new activation whose permissions are determined by the verb
being called. In particular, changing task permissions in one activation does not automatically make
those permissions available inside a later called verb.

## Capability Grants

mooR adds a two-argument form:

```moo
set_task_perms(perms, grants)
```

The two-argument form is wizard-only. `grants` is a list of grant specifications. Each grant
specification is itself a list whose first element is a string naming the grant type.

For example:

```moo
set_task_perms(
    player,
    {
        {"property_read", secret_obj, "secret"},
        {"property_write", target_obj, "status"},
        {"verb_call", service_obj, "internal_lookup"},
        {"builtin_call", "server_log"}
    }
);
```

After this call, later operations in the same activation run as `player`, but with the listed
additional grants.

Capability grants are intended for wizard-owned helper verbs that have already made a higher-level
authorization decision. For example, a core may validate a token, policy record, or capability
object in a wizard-owned verb, then use `set_task_perms(player, grants)` so the rest of the helper
runs with the player's identity plus only the specific delegated rights it needs.

## Supported Grants

Object grants:

| Grant             | Shape                      | Meaning                                             |
| ----------------- | -------------------------- | --------------------------------------------------- |
| `object_read`     | `{"object_read", obj}`     | Satisfies object read permission checks for `obj`.  |
| `object_write`    | `{"object_write", obj}`    | Satisfies object write permission checks for `obj`. |
| `object_rename`   | `{"object_rename", obj}`   | Allows changing `obj.name`.                         |
| `object_move`     | `{"object_move", obj}`     | Allows moving `obj`.                                |
| `object_recycle`  | `{"object_recycle", obj}`  | Allows recycling `obj`.                             |
| `object_chparent` | `{"object_chparent", obj}` | Allows changing `obj`'s parent.                     |

Property grants:

| Grant             | Shape                              | Meaning                                  |
| ----------------- | ---------------------------------- | ---------------------------------------- |
| `property_read`   | `{"property_read", obj, "prop"}`   | Satisfies read checks for `obj.prop`.    |
| `property_write`  | `{"property_write", obj, "prop"}`  | Satisfies write checks for `obj.prop`.   |
| `property_define` | `{"property_define", obj}`         | Allows defining new properties on `obj`. |
| `property_delete` | `{"property_delete", obj, "prop"}` | Allows deleting `obj.prop`.              |

Verb grants:

| Grant          | Shape                           | Meaning                                                             |
| -------------- | ------------------------------- | ------------------------------------------------------------------- |
| `verb_read`    | `{"verb_read", obj, "verb"}`    | Satisfies read checks for the resolved verb.                        |
| `verb_write`   | `{"verb_write", obj, "verb"}`   | Satisfies write checks for the resolved verb.                       |
| `verb_add`     | `{"verb_add", obj}`             | Allows adding verbs to `obj`.                                       |
| `verb_program` | `{"verb_program", obj, "verb"}` | Satisfies code-writing authority for the resolved verb.             |
| `verb_call`    | `{"verb_call", obj, "verb"}`    | Allows calling the resolved verb, even if it is not public execute. |

Verb grants are resolved when `set_task_perms()` is called. The string in the grant is used as a
selector at that time, and the grant is then bound to the concrete verb definition that was found.
If the verb is later renamed, the grant continues to apply to that verb definition. If another verb
is later given the old name, the existing grant does not move to the new verb.

For `verb_call`, the selector is resolved using normal method dispatch. This matters for inherited
verbs and wildcard-style verb names: the grant is bound to the verb definition selected by dispatch
at grant creation time, not to the literal string forever.

Builtin grants:

| Grant          | Shape                           | Meaning                                                        |
| -------------- | ------------------------------- | -------------------------------------------------------------- |
| `builtin_call` | `{"builtin_call", "builtin"}`   | Allows the named builtin's own wizard or owner fallback checks. |

The builtin name must name a real builtin when `set_task_perms()` is called. A `builtin_call` grant
is scoped to that builtin only. For example, `{"builtin_call", "server_log"}` allows
`server_log()` to pass its wizard-only call check, but it does not make the task a wizard and does
not authorize `log_cache_stats()`.

For builtins that normally allow either the target object or a wizard, such as `notify(player, ...)`,
the matching `builtin_call` grant allows that builtin's call check for other targets. This is still
only a call-surface grant: lower-level object, property, verb, or database checks may require their
own grants.

`set_task_perms(perms, grants)` remains directly wizard-only. A `builtin_call` grant for
`set_task_perms` does not authorize non-wizard code to install arbitrary grant sets.

## Multiple Checks

Grants are narrow. They satisfy the corresponding permission check, but they do not imply every
other permission that a builtin might require.

For example, updating verb code requires both:

- permission to write the verb, such as verb ownership, wizard permissions, the verb's `w` bit, or a
  `verb_write` grant; and
- authority to program the verb, such as programmer permissions, wizard permissions, or a
  `verb_program` grant.

If the task has only `verb_program`, `set_verb_code()` may still fail because the verb write check
failed. This is intentional: a grant delegates only the operation named by the grant.

## Lifetime and Propagation

Capability grants are attached to the current task permissions. Calling `set_task_perms()` again
replaces the current permissions and grant set.

At present, capability grants do not propagate through ordinary MOO verb calls. If a granted
operation invokes another verb, such as `move()` calling `:accept`, `:exitfunc`, or `:enterfunc`,
the called verb runs with its normal activation permissions and does not automatically receive the
grant set from the caller.

The active permissions can be inspected with `task_perms()`, which returns a list whose first
element is the current permissions principal and whose remaining elements are the active capability
grants:

```moo
{#123, {"property_read", #456, 'secret}, {"builtin_call", 'server_log}}
```

`task_perms()` uses the same grant shapes as `set_task_perms()` where possible. Verb grants are
stored internally as bindings to resolved verb definitions, so `task_perms()` looks up the current
verb definition and returns its current names string, matching `verb_info()`. If a bound verb has
been deleted, that stale grant is omitted from the returned list.

## Error Behavior

The two-argument form can raise the same basic errors as other builtins:

- `E_PERM` if the caller is not running with wizard permissions.
- `E_TYPE` if the grants argument or one of its entries has the wrong type.
- `E_INVARG` if a grant has the wrong number of fields or uses an unsupported grant name.
- A verb lookup error, such as `E_VERBNF`, if a verb grant cannot be resolved when the grant is
  created.

Once grants are installed, later operations still raise their usual domain-specific errors if the
grant set does not authorize the operation being attempted.
