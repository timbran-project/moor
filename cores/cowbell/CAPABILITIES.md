# Capability Security Guide

This core relies on cryptographically signed capability flyweights to delegate
authority without sharing passwords or granting builder status. This document
explains how to issue, store, and consume capabilities safely.

## Core Concepts

- **Capabilities are flyweights** returned by `$root:issue_capability()` with a
  `.token` slot containing a PASETO V4.Local token. Whoever holds the flyweight
  possesses the authority encoded in the token.
- **Tokens are signed with the server’s symmetric key**, so only wizard-owned
  verbs can mint them. Any attempt to call `paseto_make_local()` outside wizard
  perms will raise `E_PERM`.
- **Authorization is centralized in `$root:check_permissions_as(actor, ...)`**.
  Privileged verbs own themselves but call this helper with the actor they are
  authorizing. It determines whether that actor is a wizard, owns the target, or
  is acting through a capability flyweight. Always authorize before mutating
  sensitive state.
- **`challenge_for()` validates tokens** (signature, expiration, target binding,
  revocation, and capability subset) and returns `{delegate, run_as}` where
  `run_as` defaults to `$hacker`. Capability-consuming verbs should challenge
  tokens through this path instead of decoding them directly.

### Capability references

The flyweight is both the authority *and* the reference to the target object.
The `delegate` slot points at the real object (`cap.delegate == target`), so
verbs can accept either a raw object or a capability flyweight and treat them
interchangeably:

```moo
authority = room_arg;
actor = typeof(authority) == TYPE_FLYWEIGHT ? authority | player;
{actual_room, perms} = authority:check_permissions_as(actor, 'dig_from);
set_task_perms(perms);
```

Passing the flyweight therefore “carries” permission with it - scripts can hand a
player a capability, and the player can then pass that flyweight into privileged
verbs without ever knowing the underlying object number. Treat capability
flyweights like bearer credentials; discarding your copy only removes your local
access and does not invalidate copies held elsewhere.

## Issuing Capabilities

Use `$root:issue_capability(target_obj, cap_list, ?expiration, ?run_as, ?key)`
or delegate-specific wrappers (e.g., `$player:issue_capability`). Only two types
of callers can mint a token:

1. Wizards.
2. The owner of `target_obj`.

`run_as` may only be the caller or `player`, enforcing the “on behalf of me or
on behalf of the player” semantics. If omitted, the bearer will run as
`$hacker`. Tokens can carry optional expirations.

### Grant Buckets

`$root:grant_capability(target, caps, grantee, category)` issues a capability
and stores it in a property named `grants_<category>` on the grantee (e.g.,
`grants_area`). These properties are wizard-owned maps of `{target_obj -> cap}`.

`grantee:find_capability_for(target, category)` looks up the stored flyweight so
builder UX and tools can fetch the right capability without touching protected
properties directly.

`$root:revoke_capability(target, grantee, category)` removes the stored grant
and records the grant token id in `$root.revoked_capability_jtis`, so copied
bearer flyweights for that grant fail later challenge checks.

When a stored grant is replaced by a merged grant,
`$root:grant_capability()` also revokes the old token id. This prevents old
copies of the pre-merge grant from remaining usable after the grantee's stored
authority changes. Directly-issued capabilities that were never stored as grants
still need expiration or server key rotation for global invalidation.

## Consuming Capabilities

Every verb that requires delegated authority must follow this pattern:

```moo
actor = typeof(this) == TYPE_FLYWEIGHT ? this | caller_perms();
{target, perms} = this:check_permissions_as(actor, 'cap_symbol);
set_task_perms(perms);
"… privileged work …"
```

Command wrappers often use the connected player as the fallback actor while
still allowing a stored grant to substitute for the raw object:

```moo
cap = player:find_capability_for(target_obj, 'category);
authority = typeof(cap) == TYPE_FLYWEIGHT ? cap | target_obj;
actor = typeof(authority) == TYPE_FLYWEIGHT ? authority | player;
{target, perms} = authority:check_permissions_as(actor, 'cap_symbol);
set_task_perms(perms);
```

The important rule is that the object being challenged must be the flyweight
when capability authority is being used. Passing `caller_perms()` to
`check_permissions_as()` is only correct when you are deliberately checking
ambient owner/wizard authority; it will not prove that a caller holds a
capability.

This guarantees three facts:

1. Wizards bypass the capability path entirely.
2. Owners can always act on their objects.
3. Capability bearers must present a valid token before work begins.

Never mutate object state before the `check_permissions_as()` call. If you only
need to verify access (no mutation), still call `check_permissions_as()` and
ignore the returned `perms` object.

### Denying Access Nicely

When rejecting a request because the caller lacks a capability, use
`$grant_utils:format_denial(target, category, caps)` to explain which grant is
missing. Builder verbs such as `@dig` already follow this pattern.

## run_as Semantics

`run_as` controls the task perms returned by `check_permissions_as()`. Allowed
values are:

- `caller_perms()` at issuance time - delegates authority back to the issuer.
- `player` at issuance time - executes as the player active while the token is
  issued.
- `$hacker` (implicit default) – unprivileged execution.

Because `run_as` is embedded in the signed token, callers cannot forge higher
privileges. Be deliberate when issuing capabilities with `run_as != $hacker`,
and keep the scope of `cap_list` as narrow as possible.

## Testing and Auditing

- `$root:test_capabilities()`, `test_merge_capability()`, and
  `test_grant_capability()` exercise token issuance, validation, expiration,
  merging, and grant storage.
- `tests/headless/headless_capability_scenarios.moo` covers the broader
  integration surface: stored grants, non-owner capability use, command wrappers,
  setup capabilities, revocation, copied bearer denial, tamper resistance, and
  merge laundering regressions.
- When authoring new verbs, scan for wizard-owned verbs without a call to
  `check_permissions_as()` or an equivalent explicit authorization check. A
  wizard-owned mutator that only relies on `set_task_perms()` is probably a bug.

## Feature-layer audit

Capability use in the feature layer is currently narrow. The core capability
verbs and headless scenarios cover issuance, validation, stored grants,
revocation, tampering, setup capabilities, and a few command wrappers, but most
builder and programmer commands still rely on classic owner/wizard checks plus
`set_task_perms(player)`.

### Builder commands already using capabilities

These commands already look up stored grants or pass capability flyweights into
lower-level capability-aware verbs:

- `@grant` creates stored capability grants through `$root:grant_capability()`.
- `@build` uses an area `add_room` grant when creating rooms inside an area.
- `@dig` uses source-room `dig_from`, destination-room `dig_into`, and area
  `create_passage` authority.
- `@undig`, `@remove-exit`, and `@delete-passage` use source-room `dig_from`
  and area `remove_passage` authority.
- Passage editing paths such as `@describe` on a direction and `@set-passage`
  use source-room `dig_from` before updating passage flyweights.

These are the most mature capability surfaces. They should keep positive,
negative, revoked-grant, copied-token, and command-UX coverage in headless
tests.

### Builder commands still using owner/wizard checks

These commands mutate builder-visible world state but mostly require direct
ownership or wizard status:

- `@create` requires a fertile parent, ownership of the parent, or wizard
  status before creating a child object.
- `@recycle` and `@destroy` require ownership or wizard status before
  destroying an object.
- `@rename` requires ownership or wizard status before changing object names and
  aliases.
- `@describe` on an object and `@edit-description` require ownership or wizard
  status before changing object descriptions.
- `@integrate` requires ownership or wizard status before changing integrated
  descriptions.
- `@move` requires ownership or wizard status before moving an object.
- `@set-thumbnail` requires ownership or wizard status before changing
  thumbnail data.
- `@set-rule`, `@clear-rule`, `@add-reaction`, `@set-reaction`,
  `@enable-reaction`, and `@disable-reaction` require ownership or wizard status
  before changing rule or reaction properties.

These are plausible delegation candidates because they are builder operations
against ordinary world objects. Most should not invent new permission logic in
the command verb itself. Prefer making the underlying object verbs consume
capabilities consistently, then let the command wrapper resolve either the raw
object or a stored grant.

Likely capability names for this layer:

- `create_child` for `@create`.
- `recycle` for `@recycle` / `@destroy`.
- `set_name_aliases` for `@rename`.
- `set_description` for object `@describe` and `@edit-description`.
- `set_integrated_description` if integrated descriptions are meant to be
  separately delegatable from ordinary descriptions.
- `move` for `@move`.
- `set_thumbnail` for `@set-thumbnail`.
- A separate content-customization family for rules, reactions, and message
  properties, if those should be delegatable at all.

### Builder commands that are mostly introspection

Commands such as `@audit`, `@owned`, `@parent`, `@children`, `@descendants`,
`@parents`, `@ancestors`, `@messages`, `@rules`, `@reactions`, `@passage`, and
`@passage-info` primarily read and format state. They should continue to rely on
ordinary read permissions unless a specific private-read capability is designed.

### Programmer commands

`src/features/prog_features.moo` is effectively not capability-aware. It gates
commands on programmer status, then relies on normal MOO permission checks,
explicit owner/wizard checks, or builtin enforcement.

Surfaces that should probably remain classic programmer authority until a much
more deliberate code-edit capability model exists:

- `eval`
- `@verb`, `@rmverb`, `@program`, `@program#`, `@args`, `@chmod`
- `@property`, `@rmproperty`, `@clear-property`
- `@chparent`
- `@mvverb`, `@cpverb`
- `@kill-task`

The object-rename half of programmer `@rename` overlaps with builder `@rename`
and could share the same eventual `set_name_aliases` capability path. The
verb-rename half should remain tied to verb ownership or wizard status unless
the project intentionally adds a verb-edit capability model.

Programmer read-only tools such as `@show`, `@display`, `@list`, `@verbs`,
`@properties`, `@grep`, `@which`, `@browse`, and editor presentation helpers
should stay governed by existing read/debug permissions for now.

### Audit takeaways

The current capability system is not yet a general replacement for MOO
ownership. It is an explicit delegation layer used mainly for area/room building,
some object/player mutation helpers, setup-time player creation, and LLM/client
surfaces. The safest expansion path is to cap-enable small, existing object
mutation verbs first, then update feature commands to call those verbs through a
stored grant when present.

Avoid granting broad property-write or arbitrary-code capabilities as a shortcut.
Those would collapse too many unrelated authority boundaries into one token and
would make later runtime-level auth work harder to reason about.

## Best Practices

- **Least privilege**: issue capabilities with the minimal list of symbols and a
  reasonable expiration when possible.
- **Never share flyweights** outside trusted code paths; treat them like
  passwords. If you must transmit one (e.g., via mail), remember that anyone who
  sees it gains the encoded rights.
- **Revoke stored grants explicitly** with `$root:revoke_capability()` when
  removing delegated access. Deleting a local variable or inventory object is not
  a global revocation mechanism.
- **Document capability needs** on objects so admins know which grants to issue.
  All prototype verbs that rely on capabilities should have descriptive comments
  (see `src/root.moo` and `src/area.moo` for examples).

Following the above conventions keeps the capability system predictable,
auditable, and safe for builders and wizards alike.

## Background reading

- Mark S. Miller, *Capability-Based Financial Instruments* and the E-rights
  papers – foundational thinking on object-capability security.
- Norm Hardy, “The Confused Deputy” – classic motivation for why ambient
  authority (pure ACLs) causes privilege leaks.
- Jonathan Rees, “A Security Kernel Based on the Lambda Calculus” – describes
  capability passing in higher-level languages.

Capability-based security avoids the confused-deputy problem because authority
flows explicitly: you can only act on an object if someone hands you a reference
that already embodies the necessary rights. That fits MOO’s prototype model
well—passing a flyweight both identifies the target and carries its limited
authority—so builders can safely delegate without global ACL checks or
hard-to-reason-about privilege escalations.

## Runtime limitations to remember

- `set_task_perms()` affects only the *current* stack frame. Each capability
  consumer must call it explicitly; the interpreter does not propagate `run_as`
  to nested calls.
- The runtime has no built-in concept of capabilities. All validation and
  downgrading happens in core verbs, so consistency depends on following the
  documented patterns.
- Tokens are symmetrically encrypted; rotating the server key invalidates every
  outstanding capability unless you reissue them. Plan for that operationally.
- Stored-grant revocation uses a token-id denylist. This requires server-side
  state, so it only applies to token ids recorded during revoke/merge; old
  direct bearer tokens remain valid until expiration or key rotation.
- Flyweights are immutable and expose their metadata only via `flyslots()` /
  related helpers. Treat them as black boxes you hand around rather than data
  structures you modify in place.

These constraints explain why privileged verbs must call `check_permissions_as()`
or perform an equivalent explicit authorization check, then explicitly
`set_task_perms()` before doing privileged work. Without interpreter support,
discipline in userland code keeps the capability model safe.

## Credit

This implementation of capabilities mimics in some ways the implementation
of capabilities implemented by "Quantum-Vacuum" on ColdMUD using its "frobs"
(similar to mooR's flyweights) in the 90s. 
