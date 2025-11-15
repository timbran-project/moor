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
- **Authorization is centralized in `$root:check_permissions()`**. Privileged
  verbs own themselves but call this helper to determine whether the caller is
  a wizard, the object owner, or a capability bearer. Always call this helper
  before mutating sensitive state.
- **`challenge_for()` validates tokens** (signature, expiration, target binding,
  and capability subset) and returns `{delegate, run_as}` where `run_as` defaults
  to `$hacker`. Verbs never decode tokens manually.

### Capability references

The flyweight is both the authority *and* the reference to the target object.
The `delegate` slot points at the real object (`cap.delegate == target`), so
verbs can accept either a raw object or a capability flyweight and treat them
interchangeably:

```moo
actual_room = typeof(room_arg) == FLYWEIGHT ? room_arg.delegate | room_arg;
actual_room:check_permissions('dig_from);
```

Passing the flyweight therefore “carries” permission with it - scripts can hand a
player a capability, and the player can then pass that flyweight into privileged
verbs without ever knowing the underlying object number. Treat capability
flyweights like references you can hand around safely; discarding the flyweight
revokes the authority automatically.

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

## Consuming Capabilities

Every verb that requires delegated authority must follow this pattern:

```moo
{target, perms} = this:check_permissions('cap_symbol);
set_task_perms(perms);
"… privileged work …"
```

This guarantees three facts:

1. Wizards bypass the capability path entirely.
2. Owners can always act on their objects.
3. Capability bearers must present a valid token before work begins.

Never mutate object state before the `check_permissions()` call. If you only
need to verify access (no mutation), still call `check_permissions()` and ignore
the returned `perms` object.

### Denying Access Nicely

When rejecting a request because the caller lacks a capability, use
`$grant_utils:format_denial(target, category, caps)` to explain which grant is
missing. Builder verbs such as `@dig` already follow this pattern.

## run_as Semantics

`run_as` controls the task perms returned by `check_permissions()`. Allowed
values are:

- `caller_perms()` – delegates authority back to the issuer.
- `player` – executes as the player running the command.
- `$hacker` (implicit default) – unprivileged execution.

Because `run_as` is embedded in the signed token, callers cannot forge higher
privileges. Be deliberate when issuing capabilities with `run_as != $hacker`,
and keep the scope of `cap_list` as narrow as possible.

## Testing and Auditing

- `$root:test_capabilities()`, `test_merge_capability()`, and
  `test_grant_capability()` exercise token issuance, validation, expiration, and
  grant storage. Run them (via `make test`) when modifying capability logic.
- When authoring new verbs, scan for wizard-owned verbs without a call to
  `check_permissions()` - that’s almost always a bug.

## Best Practices

- **Least privilege**: issue capabilities with the minimal list of symbols and a
  reasonable expiration when possible.
- **Never share flyweights** outside trusted code paths; treat them like
  passwords. If you must transmit one (e.g., via mail), remember that anyone who
  sees it gains the encoded rights.
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
- Flyweights are immutable and expose their metadata only via `flyslots()` /
  related helpers. Treat them as black boxes you hand around rather than data
  structures you modify in place.

These constraints explain why we require every privileged verb to call
`check_permissions()` and explicitly `set_task_perms()`—without interpreter
support, discipline in userland code keeps the capability model safe.

## Credit

This implementation of capabilities mimics in some ways the implementation
of capabilities implemented by "Quantum-Vacuum" on ColdMUD using its "frobs"
(similar to mooR's flyweights) in the 90s. 
