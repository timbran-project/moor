# MOO programming style

This guide applies to Snore Core, a LambdaCore fork for mooR. It defines the required style for all
retained code. `make check-style` checks explicit local bindings, initial docstrings, and
assignments inside conditions. It does not establish behavioral correctness or permission safety.

Use the [mooR book source](../../book/src/SUMMARY.md) as the language and runtime reference. The
[design notes](docs/design.md) explain the core's scope.

## General rules

- Write readable code with explicit contracts.
- Prefer early returns and shallow control flow.
- Prefer short-circuit guards for validation, early returns, and conditional single actions.
- Handle invalid inputs and denied operations before the main operation.
- Use current mooR facilities where they simplify the implementation.
- Keep helpers small and give each helper one purpose.
- Preserve useful MOO idioms, including destructuring and object hooks.
- Remove dead code and historical implementation commentary from rewritten bodies.
- Keep core attribution in `LICENSE.md`. Do not add per-file copyright headers to objdef sources;
  export and rebuild do not preserve them.

## Layout and names

Use two spaces for each indentation level in objdef and verb bodies. Keep ordinary source lines
within 100 columns where practical. Split long expressions at argument or collection boundaries.

Use `snake_case` for variables, properties, methods, and files. Use uppercase objdef constants for
object references. Keep established player command spellings and aliases where the contract retains
them. Local `const` bindings use `snake_case`.

Prefix internal methods with `_` and test methods with `test_`. An underscore is a naming
convention, not an access restriction. Authorization must exist in code or permissions.

## Variables and arguments

Declare local bindings explicitly. Use `const` for bindings that do not change and `let` for mutable
bindings. Keep each binding in the smallest useful scope. Avoid verb-wide implicit variables and
assignments inside conditions. Loop and exception bindings use their language syntax.

Destructure arguments at the start of a method, after its docstring:

```moo
const {recipient, text, ?urgent = false} = args;
```

Use `let` destructuring for bindings that need reassignment. Specify optional defaults deliberately.
Do not hide incompatible argument shapes behind an unrestricted `@rest` parameter.

Keep counts and indexes separate from predicates:

```moo
const message_count = length(messages);
const has_messages = message_count > 0;
let delivered_count = 0;
```

## Values and collections

Use `true` and `false` for flags and predicates. Use integers for counts and indexes. Keep object
references as object values. Do not replace every historical `0` or `1` without checking its
contract. Check builtin option types too. `match` and `rmatch` currently require integer case flags;
convert boolean options to 0/1 at that boundary. R23 in the
[runtime findings](../../docs/modern-lambda-runtime-findings.md) records the mismatch.

MOO lists use braces and start at index 1. Maps use brackets and associate keys with values.

```moo
const recipients = {sender, recipient};
const message = ['sender -> sender, 'text -> text, 'unread -> true];
```

Use lists for ordered sequences and maps for records with named fields. Small tuples are suitable
for short, documented interfaces. Avoid long positional records and parallel lists of related
fields.

Use symbols for fixed field names and identifiers. Use strings for user text. Do not assume that
conversion to symbols preserves a user-facing name-matching contract.

MOO string equality is case insensitive. Use `strcmp()` for case-sensitive comparison. Define
normalization, alias collisions, and prefix ambiguity at each name-matching boundary.

Use a comprehension for a simple transformation or filter:

```moo
const unread = {message for message in (messages) if message['unread]};
```

Use a loop for effects, complex conditions, or early termination. Prefer an existing builtin to a
duplicate MOO algorithm after checking its semantics. Do not introduce flyweights.

Anonymous objects need a reason for mutable object behavior. Ordinary records do not need an object
merely to hold data.

Use `fromliteral()` to parse data literals without executing code. Use `toliteral()` for literal
output. Do not substitute `eval()` for data parsing. Keep error diagnostics and prefix parsing in
the core wrapper when its interface requires them.

## Object identity and lifecycle

Use traditional object numbers for core objects and UUID identifiers for user-created objects.
Assign core identities explicitly in objdef sources. Keep UUID creation enabled for runtime
creation.

Treat user object identifiers as opaque values. Do not convert them to integers or use arithmetic on
them. Numeric-range scans cannot enumerate user objects. Use object enumeration facilities
appropriate to the operation. An identifier's representation does not establish its owner's
authority.

Use objdef constants and `$sysobj` names for core references. Keep required runtime identities and
sentinels explicit. Do not scatter literal core object numbers through verb bodies.

Use `$recycler` for the core's creation and recycling interface. Do not add pooled-object reuse.
Lifecycle methods must preserve their authorization, cleanup, and retained quota contracts.

## Control flow and helpers

Prefer short-circuit evaluation for guards and short conditional actions. The reference is
[Julia's short-circuit evaluation guidance](https://docs.julialang.org/en/v1/manual/control-flow/#Short-Circuit-Evaluation).
Apply that control-flow idiom with MOO syntax and truth-value rules.

Use `condition || raise(...)` to require a condition. Use `condition && return ...` for an early
exit. Use `condition && action(...)` for a conditional single action. These are preferred forms, not
merely abbreviations that are acceptable in exceptional cases.

```moo
valid(recipient) || raise(E_INVARG, "Recipient does not exist.");
length(messages) == 0 && return {};
urgent && recipient:tell("You have urgent mail.");
```

`&&` evaluates its right operand only when the left operand is true. `||` evaluates its right
operand only when the left operand is false. This permits dependent checks in evaluation order:

```moo
(typeof(limit) == TYPE_INT && limit > 0) || raise(E_INVARG, "Limit must be a positive integer.");
```

MOO gives `&&` and `||` equal precedence and evaluates them left to right. Thus `a || b && c` means
`(a || b) && c`. Preserve that grouping when rewriting an expression; Julia and Rust use different
precedence. Use a separate access guard before returning a computed value. See the
[operator precedence reference](../../book/src/the-moo-programming-language/moo-language-expressions.md#parentheses-and-operator-precedence).

Keep each guard focused on one condition and consequence. Compound predicates are appropriate when
they express one requirement. Name a complex predicate or split distinct requirements into
successive guards. Use `if`/`elseif`/`else` for branches with several statements. Avoid nested
ternaries and chains of unrelated effects.

Use local functions for helpers that belong to one verb. Use lambdas for short callbacks. Separate
public methods represent reusable behavior or a deliberate object interface.

### Callback interfaces

Accept closures where callers need reusable selection or transformation behavior. Keep simple
one-off transformations as comprehensions. Use separate method names when a callback changes an
established argument contract. `$list_utils` provides `map`, `filter`, `reduce`, `find_index`,
`any`, `all`, and `sort_by`; its existing object/verb mapping interfaces remain available.

Reduce task permissions to `caller_perms()` before invoking an untrusted callback. A lambda inherits
the invoking activation's authority and context. Its `this` is the utility object, so callers must
capture target objects explicitly. A callback must not acquire the utility verb owner's authority.

Document argument order, empty-input results, evaluation order, and early termination. A sort key
callback runs once per item, before sorting. Propagate callback exceptions. New callback methods
must not add implicit suspension; callback code can still suspend or fork and commit the
transaction.

Statement-bodied callbacks need explicit returns on this runtime. R17 and R18 in the
[runtime findings](../../docs/modern-lambda-runtime-findings.md) describe unresolved local-function
capture and fallthrough failures. Do not treat those failures as intended language semantics.

## Methods and commands

Use objdef `method` declarations for callable methods:

```moo
method has_messages owner: HACKER
  "Return whether this mailbox contains messages.";
  return length(this.messages) > 0;
endmethod
```

This example assumes a mailbox with a `messages` property. A `method` declaration uses argspec
`this none this` and defaults to `rxd`. Keep `d` enabled in new and rewritten code. Explain any
explicit permission flags that differ from the default.

Command verbs use meaningful object and preposition specifications. Use `rd` for commands that do
not require public method calls. Any `x` flag needs a reason in the dispatch or public API contract.
Keep command parsing and user messages separate from reusable operations.

Retained hooks, command aliases, return values, and error behavior are interfaces. Change them
deliberately, with corresponding caller and regression updates.

Command scope hooks run with player authority. Preserve the order supplied by `match_environment`
and `match_scope_for`; ordinals and ambiguous candidates depend on that order. Keep command
providers separate from visible objects. Add no automatic suspension between matching and dispatch.
Document any intentional suspension in a custom hook as a transaction boundary.

## Player classes and world policy

The hierarchy separates the in-world `$player` foundation from a default descendant with
out-of-world utilities. Examples include teleporting, `@who`, and `@audit`. Speech and emotes remain
in-world interactions. Their social purpose does not put them in the utility layer.

Classify commands by behavior rather than the `@` prefix alone. Alternative descendants can supply
game-specific commands and movement rules. The mail-capable game branch derives from
`$mail_recipient_class`, alongside `$default_player`. Shared refusals, spurns, and their help belong
with mail support so that social controls remain available without utility commands.

Keep role command bodies in the builder, programmer, and wizard feature objects. Install those packs
by default on `$builder`, `$prog`, and `$wiz`, respectively. Descendants inherit earlier role packs.
Keep their supporting methods and state on the corresponding player classes. Feature installation
requires that support class; it does not grant programmer or wizard permission.

Keep programmer and wizard flag checks in command bodies. `$wiz_utils:set_programmer` reparents into
`$prog` when needed, preserving existing `$prog` descendants and explicit feature choices. Direct
server-flag assignment does not change ancestry. `$wiz_utils:set_player` explicitly enables the
programmer flag for a `$prog` descendant, as in LambdaCore.

Do not assume that every player inherits from the default utility class. Keep session and output
contracts usable by alternative `$player` descendants. Separate command entry points from supporting
methods, and document the authority of both.

Keep privileged role checks independent of inheritance. Command placement alone does not enforce
movement restrictions. Include room commands, feature dispatch, and direct method calls in the
authorization review.

## Documentation

Start each method with a brief string-literal docstring. State its purpose and result. Add argument,
error, authority, and transaction details where the contract needs them.

Command docstrings state usage and behavior. Help text must describe the implemented command and
supported clients. Comments explain intent or a non-obvious constraint.

```moo
"Find an exact player name. Return $nothing when no player matches.";
```

Do not repeat the code in comments or preserve a history of previous implementations. Avoid praise
and performance claims without measurements.

## Errors

Raise exceptions for failed method operations. Document normal absence results separately. Use an
existing error code where it fits. Use a custom error for a distinct condition that callers need to
handle.

Catch expected errors at command boundaries and translate them into useful output. Preserve
diagnostics for unexpected errors. Do not turn every exception into an ordinary failure message.

Use `try`/`except` for handling that needs several statements. An error-catching expression is
suitable for a narrow, documented fallback. Catch specific errors rather than `ANY` by default.

Broadcast delivery can isolate a broken recipient. Such handling must preserve diagnostics and avoid
hiding failures in the shared operation. Expected denials and unexpected defects need different
paths.

## Permissions

Document the caller, effective principal, target, and permitted operation for privileged methods.
Check authorization before privileged effects. Object ownership and verb ownership are separate
facts.

An ordinary verb activation starts with its verb owner's permissions. `player` identifies task
context and is not sufficient proof of authority. Use `caller_perms()` and the operation's actual
authorization contract.

`set_task_perms()` changes the current activation. Non-wizard code cannot use it to acquire
arbitrary authority. A later call to a wizard-owned verb creates another privileged activation.
Permission reduction does not sandbox the entire call tree.

Keep privileged work small. Reduce authority to the required principal where practical. A trusted
wizard helper can attach narrow grants after authorization. The current runtime does not
automatically propagate those grants through ordinary verb calls.

An internal-name prefix and a `caller == this` guard do not establish every permission contract.
Inherited behavior and calls into user-owned objects need particular care. Check property and verb
flags as part of each interface.

The
[runtime permission reference](../../book/src/the-moo-programming-language/task-permissions-and-capability-grants.md)
defines the available grants. A core-wide capability-object design remains a separate decision.

## Transactions and performance

mooR has much larger tick budgets than traditional LambdaMOO configurations. Frequent suspensions
from old core code are often unnecessary. Review inherited tick thresholds and suspend frequency
against the configured budget and measured work. Do not preserve a suspension merely because the
original loop used one.

**Every `suspend()` is a transaction commit boundary, including `suspend(0)`.** Suspension publishes
the current transaction's changes, and execution resumes in a new transaction. It is not merely a
scheduler yield or a tick-budget reset. A later error cannot roll back changes from an earlier
committed transaction.

Keep updates that must be atomic within one transaction. Place necessary suspensions between
complete units of work, with a defined intermediate state. Do not suspend between related mutations
that must succeed together.

The builtin `suspend_if_needed()` also commits when its threshold triggers a suspension. A helper
that can suspend has the same effect on its caller's transaction. Do not hide such helpers inside
operations that promise atomic behavior.

`fork` also commits the parent transaction before dispatching the child; the parent then resumes in
a new transaction. Keep related mutations complete before calling a helper that forks. Ordinary
notification output is buffered until commit and discarded on rollback.

Document operations that read input, suspend, commit, or call helpers that cross transaction
boundaries. After resumption, reread relevant state and revalidate authority, object validity, and
other assumptions. Local variables can retain values from the previous transaction.

Long operations still need bounded work and deliberate commit points. Use measured batch sizes and
the configured tick and time limits. Larger budgets do not justify unlimited loops or arbitrarily
long transactions.

Keep external effects and retry behavior explicit. A caught error does not itself undo earlier
mutations. Arrange validation and mutation so that expected errors leave a defined state.

Keep frequently mutated state with its player, session, room, or service instance. Avoid shared
bookkeeping on every command. A single large map can concentrate writes and increase conflicts.

Measure retained workflows before claiming a performance improvement. Include concurrent activity,
response time, transaction retries, and persistence costs where relevant.

## Output and retained features

Use ordinary text output. Structured output is deferred. Do not bypass the core output interface in
ways that circumvent gagging or private delivery.

Leave long-output paging and word wrapping to clients. Do not add core pager buffers, continuation
prompts, page-length controls, or terminal-width wrapping. Preserve meaningful line breaks in
paragraphs, lists, and preformatted text. The `page` private-message command is separate from output
paging.

For a login prompt without a line break, use `notify(player, text, false, true)`. Do not toggle
binary input mode to control output formatting.

Mail, news, private messaging, gagging, and guests remain part of the core. Their internal
implementations can change, but their retained behavior needs tests and updated help. Old FTP, HTTP,
and Gopher services do not belong in this core.

## Tests

Give each `test_` method one clear contract. Use isolated fixtures and explicit cleanup. Anonymous
fixtures are suitable only where they have the required object semantics.

Keep pure method tests near their implementations. Keep runtime-only fixtures under `tests/`. Use
temporary databases for scenarios that need a running core. Test denied operations as well as
successful operations.

Session scenarios cover command parsing, login, output delivery, private messaging, gagging, and
guest lifecycle. Long-output scenarios must preserve content without core pager prompts or automatic
word wrapping. Concurrent scenarios cover shared state and transaction boundaries. Import success
alone does not establish correct runtime behavior.

Place test entry points and test principals on numbered core or fixture objects. Create UUID user
objects within scenarios to cover runtime creation, matching, ownership, and cleanup. The current
`moorc` scan does not discover test methods on UUID objects. A successful run with no discovered
tests is not evidence that this core passes its tests.
