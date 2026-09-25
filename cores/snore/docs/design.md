# Design and compatibility

Snore Core forks LambdaCore through the lambda-moor port. Cowbell supplies examples of modern mooR
code and command matching. Snore keeps LambdaCore's familiar world and authoring model.

## Retained services

Rooms, exits, containers, notes, mail, news, private pages, whispers, gagging, guests, editors,
building, programming, quotas, and administrative logs remain. `$recycler:_create()` and
`$recycler:_recycle()` remain the creation and deletion interfaces.

Mailboxes store messages in per-instance lists. Player, site, registration, and caller-history
indexes use maps. The shared spelling dictionary uses a sorted list. Core utility methods retain
established names where they remain useful; callers must account for documented boolean results and
mooR value types.

## Identities and roles

Numbered objects are reserved for the core and test fixtures. New user objects use UUID identities.
Treat object IDs as opaque values: do not count objects by subtracting IDs or enumerate them through
numeric ranges. `src/constants.moo` assigns the shipped identities; test constants stay in the test
overlay.

The [player hierarchy](player-classes.md) separates in-world behavior from non-VR utilities. This is
not a separation between social and non-social features: speech, private messaging, and gagging
remain shared. The builder/programmer/wizard hierarchy provides support state; separate feature
packs provide its commands. Independent role composition across unrelated classes is deferred.

## Intentional changes

- Remove core FTP, HTTP, Gopher, and external mail-forwarding services. mooR hosts remain separate
  server components; this does not remove the runtime's web client support.
- Remove recycler pooling, orphan lists, and recurring pool repair. Recycling deletes an object;
  creation assigns a fresh identity.
- Remove output paging, volume-confirmation prompts, automatic wrapping, and `screen_width`.
  Preserve complete text lines and leave their display to clients.
- Replace generic database and big-list storage objects with maps and per-instance lists.
- Use boolean predicates, explicit lexical bindings, symbols, comprehensions, and suitable native
  functions. Numeric counts, indexes, and multi-valued status codes retain their types.
- Keep ordinary text notifications. Structured output, flyweights, and a new capability-object
  architecture are outside this core's scope.

## Runtime configuration

The Makefile and launcher enable booleans and boolean builtin results, symbols and symbol builtin
results, custom errors, lexical scopes, comprehensions, and UUID creation. Flyweights and rich
notifications are disabled. Keep import and runtime settings consistent.

The shipped task budgets are 800,000 foreground ticks and 500,000 background ticks. These budgets
reduce the need for inherited small-loop yields. They do not make long operations unlimited. Every
suspension and fork remains a [transaction boundary](transactions.md).

## Compatibility limits

Snore aims to preserve familiar workflows. It does not promise unchanged execution of every
LambdaMOO program. Tutorials that depend on numbered user objects, removed services, integer-valued
predicates, or exact LambdaMOO builtin behavior need adaptation.

Byte quotas are the supported policy. The retained object-count utility depends on the unresolved
native `ownership_quota` contract; selecting it does not provide working quota enforcement.
`reset_max_object()` is not used. Extracted cores can retain gaps and a high allocation mark.

OAuth identity claims use the verified host operation from the runtime authentication interface. Raw
login commands cannot assert an OAuth identity. Linking an identity requires the existing account
password. Update runtime hosts and core authentication methods together.

Some local-function and builtin compatibility issues remain in mooR. The
[runtime findings](../../../docs/modern-lambda-runtime-findings.md) distinguish reproduced failures,
source findings, accepted fixes, and deferred proposals. Those issues do not belong to the passing
core regression suite.

## Source layout

`src/` contains the shipped objdef world. `tests/fixtures/` overlays numbered test principals and
method tests. `tests/sessions/` and `tests/sessions-game/` exercise commands with mock sessions;
Python checks cover real TCP and extraction. `tools/session-runner/` supplies the core-local mock
session implementation. `tools/style-audit/` checks source conventions through mooR's parser.
