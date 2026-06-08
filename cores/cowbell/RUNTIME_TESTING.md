# Cowbell Runtime Behaviour Testing

Cowbell currently has three different testing pressures mixed together:

- Unit-style `test_` verbs run by `moorc --run-tests`.
- `.moot` expectation files, which are good at checking expression/output snapshots but are not a great fit for broad runtime behaviour.
- Runtime scenarios that need a loaded MOO, a scheduler, connection/session state, command input, and narrative output.

This document describes the missing runtime behaviour / integration layer. The goal is to test the Cowbell core as a running system without adding test-only dependencies to `web-host`, `telnet-host`, or other production host crates.

## Existing Surfaces

`make test` in this directory compiles `src/` through `moorc`, dumps `gen.objdir`, and runs every `test_` verb:

```sh
cargo run -p moorc -- \
  --use-boolean-returns true \
  --use-symbols-in-builtins true \
  --custom-errors true \
  --use-uuobjids true \
  --anonymous-objects true \
  --src-objdef-dir src \
  --out-objdef-dir ./gen.objdir \
  --test-wizard=2 \
  --test-programmer=6 \
  --test-player=4 \
  --run-tests true
```

`../benches/Makefile` uses the same basic pattern for long-running, filtered `test_` verbs:

```sh
cargo run --release -p moorc -- \
  --src-objdef-dir src \
  --out-objdef-dir ./gen.objdir \
  --test-wizard=2 \
  --run-tests true \
  --test-filter "#668:test_combat_stress" \
  --test-timeout "$((DURATION + 60))" \
  --test-args "{...}"
```

That pattern is useful for headless scenarios where the scheduler must run, but it still bypasses the player/session/client event path.

The repo also already has useful runtime primitives outside the production hosts:

- `moorc` can import objdefs, create a temporary DB, start the scheduler, run unit verbs, run `.moot` files, accumulate failures, and exit non-zero.
- `moor-daemon` can import objdefs into a temporary data directory and expose daemon RPC/pubsub endpoints.
- `rpc-async-client::task_client::TaskClient` can attach a session to the daemon, invoke verbs, wait for task completion, and receive session events such as narrative output, input requests, disconnects, player switches, and connection option changes.

Those surfaces are enough for a CI-friendly harness crate or tool without making `web-host` or `telnet-host` know about Cowbell tests.

## Test Classes

### A. Headless Runtime Integration

Use this when the behaviour needs a loaded Cowbell database and a running scheduler, but does not need to simulate a player typing commands or receiving event output.

This class should run inside a temporary MOO through `moorc` or a small wrapper around the same scheduler setup. It should submit verbs directly and inspect return values or database state.

Good fits:

- Scheduler behaviour: delayed tasks, periodic tasks, cancellation, sweeps, persistence boundaries.
- Rule/relation/reaction internals: fact assertion, rule evaluation, threshold checks, mutation effects, event-trigger dispatch when output is not the assertion target.
- Capability and permission flows that can be expressed as direct verb calls.
- Object graph state changes: create, destroy, move, parent/child changes, relation cleanup.
- Data model helpers that need real objects, anonymous objects, or a transaction-backed DB.
- LLM/task framework lifecycle checks that can use fake data and do not call external APIs.

Avoid using this class for:

- Command parser behaviour.
- `player`-dependent `dobj`/`iobj` matching from a text command.
- Connection hooks such as `user_connected`, reconnect, and disconnect semantics.
- Narrative event delivery, perspective rendering as observed by different recipients, input prompts, or client options.

### B. Mock-Player Session Scenarios

Use this when the behaviour is defined by an attached client/player session: command text goes in, session events and task results come out.

This class should bring up a daemon with Cowbell loaded, attach one or more synthetic sessions through the daemon RPC/pubsub API, submit command input or direct session-scoped verb calls, and assert on task results plus emitted session events.

Good fits:

- Login and connection lifecycle: create/connect/reconnect/disconnect, quiet reconnect, `last_connected`, `last_disconnected`, and welcome/setup paths.
- Command dispatch: `do_command`, parser errors, ambiguous matches, command environment rules, feature object dispatch.
- Movement: `go`, `home`, passages, open/closed exits, room `enterfunc`/`exitfunc`, room look emission.
- Social events: `say`, `emote`, `whisper`, gestures, perspective-specific rendering for actor and observers.
- Inventory and object interactions: `look`, `take`, `drop`, `put`, containers, wearables, sittables.
- Messaging: DM/mail command flows and notification delivery.
- Builder/programmer/wizard commands where the user-facing command contract matters.
- Rich event output: narrative event kind, audience filtering, content types, presentation events, input requests, and connection options.

Avoid using this class for:

- Pure helper logic that can be covered by `test_` verbs.
- Slow stress tests better expressed as filtered `moorc` tests or benchmarks.
- Web rendering details. The harness should assert daemon/session events, not Meadow or browser DOM.

## Proposed Harness Shape

Add a dedicated test support tool or crate under the workspace, for example:

```text
crates/testing/runtime-harness/
```

or, if a binary is preferred:

```text
tools/cowbell-runtime-test/
```

The harness should have no dependency on `web-host` or `telnet-host`. It should depend on lower-level workspace crates only:

- `moor-daemon` or shared daemon startup code for a real daemon process, or `assert_cmd`/`std::process::Command` to spawn `moor-daemon`.
- `rpc-async-client` for task/session RPC.
- `moor-var`, `moor-common`, and schema/rpc crates for values and event decoding.
- `tempfile` for isolated DB/socket directories.
- `tokio` for async session orchestration.

The harness should provide two runners.

### Headless Runner

Initial implementation can reuse the existing `moorc` pattern:

```text
compile Cowbell objdefs -> temp DB -> start scheduler -> run named scenario verbs -> summarize failures
```

This could be done by extending `moorc` with a clearer scenario-file option, but it does not need to happen first. Cowbell already has a `runtime-headless` Makefile target that overlays `tests/headless/` onto a temporary copy of `src/`, then runs dedicated scenario objects by topic. Keeping those scenario objects outside `src/` means the ordinary `make test` target does not see or run these `test_` verbs.

```make
runtime-headless:
	rsync -a src/ $(HEADLESS_SRC_DIRECTORY)/
	rsync -a tests/headless/ $(HEADLESS_SRC_DIRECTORY)/
	cat tests/headless/headless_constants.moo >> $(HEADLESS_SRC_DIRECTORY)/constants.moo
	rm -f $(HEADLESS_SRC_DIRECTORY)/headless_constants.moo
	for filter in $(HEADLESS_FILTERS); do \
	  cargo run -p moorc -- $(OPTIONS) \
	    --src-objdef-dir $(HEADLESS_SRC_DIRECTORY) \
	    --out-objdef-dir $(OUTPUT_DIRECTORY)/gen.objdir \
	    --test-wizard=2 \
	    --test-programmer=6 \
	    --test-player=4 \
	    --run-tests true \
	    --test-filter "$$filter" \
	    --test-timeout $(HEADLESS_TIMEOUT); \
	done
```

The default filters are the headless-only scenario objects from `tests/headless/`: `#90000` for boot, `#90001` for scheduler, `#90002` for objects, `#90003` for relations, `#90004` for rules, `#90005` for capabilities, and `#90006` for event rendering. Longer term, more headless runtime scenarios should stay in dedicated scenario objects or scenario directories so public prototypes do not accumulate hundreds of test verbs.

### Session Runner

The session runner should exercise the same daemon/session path that production hosts use, without starting a production host:

```text
compile Cowbell objdefs
start moor-daemon with:
  - temp data dir
  - objdef import path
  - ipc:// endpoints inside the temp dir
  - Cowbell feature flags
attach one or more TaskClient sessions
run scenario steps:
  - invoke system/login/session verbs
  - submit command strings through the daemon command path
  - collect task completion and session events
assert expected return values, narrative event kinds, rendered text, audience, and state
shutdown daemon and delete temp dir
```

The session runner should model a player as:

- `player`: the Cowbell object under test, usually `$test_player` or a fresh player created by the scenario.
- `auth_token`: a test token minted or loaded by the scenario.
- `session`: the daemon client id/token plus pubsub subscription.
- `events`: an ordered queue of `SessionEvent` values from `TaskClient`.

The first useful API surface would be small:

```rust
let mut moo = CowbellRuntime::start().await?;
let alice = moo.attach_test_player("#4").await?;
alice.command("look").await?.expect_narrative_contains("...");
alice.command("say Hello").await?;
bob.expect_narrative_contains("Alice says");
alice.expect_narrative_contains("You say");
moo.shutdown().await?;
```

This is intentionally not a browser or telnet script. It is a daemon-level protocol test.

## Scenario Matrix

| Area | Scenario | Class | Why |
| --- | --- | --- | --- |
| Boot/import | Cowbell imports with modern feature flags and expected sysobj globals | Headless | Compile/import invariant; no player I/O needed |
| Boot/runtime | Daemon starts from imported Cowbell DB and accepts an RPC session | Mock-player | Proves real runtime endpoints and attach path |
| Login | Existing player connects and runs `user_connected` setup | Mock-player | Connection hooks and emitted room look are session-visible |
| Login | Reconnect within quiet period updates state without spam | Mock-player | Requires connection count/history semantics and output checks |
| Command parser | Unknown command gives programmer traceback or friendly fallback by role | Mock-player | Text command input and player permissions are the contract |
| Command parser | Ambiguous dobj/iobj chooses viable command verb candidate | Mock-player | Depends on `parse_command`, environment, and feature dispatch |
| Look/events | `look` on room/object emits structured event/plain fallback | Mock-player | Assertion target is emitted narrative |
| Movement | `go`/`home` moves player and fires exit/enter hooks | Mock-player | Requires command text, location changes, and room output |
| Movement | Open/closed passage denies/allows traversal | Mock-player | User-visible command result plus state |
| Social | `say`/`emote` render first-person and observer perspectives | Mock-player | Needs at least two sessions and event delivery |
| Social | Whisper/private event reaches only target and actor | Mock-player | Audience filtering is the behaviour under test |
| Inventory | `take`, `drop`, `put` move objects and announce correctly | Mock-player | Command matching, object state, and narrative output all matter |
| Containers | Open/closed container gates `get from`/`put in` | Mock-player | User command contract and state transitions |
| Wearables | `wear`/`remove` update worn state and look/inventory rendering | Mock-player | Player-facing output and state |
| Sittables | Seat occupancy limits and `stand` cleanup | Mock-player | Command flow plus shared object state |
| Messaging | DM command sends private notification and stores history | Mock-player | Multi-session delivery is central |
| Mail | Send/open/take mail flows through mailbox | Mock-player | User command flow plus persistent object state |
| Builder commands | `@create`, `@dig`, `@describe`, `@rename` happy paths | Mock-player | Feature command syntax is the contract |
| Builder commands | Unauthorized player gets clear denial | Mock-player | Permission and emitted denial are user-visible |
| Programming commands | `eval`, `@verb`, `@property`, `@chmod` smoke paths | Mock-player | Command parser and permission checks matter |
| Capabilities | Issue, grant, merge, revoke, and deny invalid capability | Headless | Direct verb calls can assert authority boundaries |
| Object model | Create/destroy/moveto/parent changes preserve invariants | Headless | State transitions are enough; no session output required |
| Relations | Assert/retract/select/query with isolated fixtures | Headless | Database-backed logic, no player output |
| Rules | Parse/evaluate rule expressions and facts | Headless | Direct assertion on solutions is better than command text |
| Reactions | Trigger reaction effects and threshold effects | Headless first, mock-player when output is expected | Split data mutation from user-visible event effects |
| Scheduler | Schedule, cancel, sweep, and timeout behaviours | Headless | Scheduler lifecycle is the core behaviour |
| Event system | Substitution, perspective rendering, message bags | Headless for pure rendering, mock-player for delivery | Render functions can be unit/headless; delivery needs sessions |
| Help | Topic lookup and role-filtered command help | Mock-player | The command/output contract matters |
| LLM objects | Agent/task lifecycle with fake responses | Headless | Avoid external network; assert local state |
| LLM room observer | Observer reacts to room narrative event | Mock-player optional | Only use session runner if event delivery is the assertion |

## Initial Scenarios

Start with four scenarios that cover the harness shape without making it large.

### 1. Headless Boot Smoke

Purpose: prove Cowbell imports, scheduler starts, and core globals exist.

Steps:

1. Import `src/` with the same feature flags as `make test`.
2. Start scheduler.
3. Invoke a scenario verb that asserts `$sysobj`, `$root`, `$player`, `$room`, `$event`, `$sub`, `$match`, `$scheduler`, `$relation`, and `$rule_engine` are valid objects.
4. Assert no unexpected persistent object growth unless the scenario deliberately creates fixtures.

Implemented as `#90000:test_headless_boot_smoke` in `tests/headless/headless_boot_scenarios.moo`.

### 2. Headless Scheduler Smoke

Purpose: prove delayed tasks can run in a temporary runtime without player interaction.

Steps:

1. Create an anonymous fixture object.
2. Schedule a short-delay callback.
3. Wait for completion through scheduler notifications or a polling scenario verb.
4. Assert the callback mutated only fixture state.
5. Clean up fixture state.

Implemented as `#90001:test_headless_scheduler_callback` in `tests/headless/headless_scheduler_scenarios.moo`.

### 3. Session Look/Movement Smoke

Purpose: prove the daemon/session path can attach a mock player, submit commands, and collect narrative events.

Steps:

1. Start daemon from Cowbell objdefs in a temp data dir.
2. Attach a session for `$test_player`.
3. Submit `look`.
4. Assert at least one narrative event contains the current room description or structured look output.
5. Submit a simple movement command through a known passage.
6. Assert player location changed and room enter/exit output was emitted.

### 4. Two-Player Social Smoke

Purpose: prove multi-session audience and perspective rendering.

Steps:

1. Attach two players in the same room.
2. Have Alice submit `say Hello`.
3. Assert Alice sees first-person wording.
4. Assert Bob sees third-person wording.
5. Assert unrelated sessions do not receive private-only events in later variants.

## CI Flow

Use separate targets so local development can run cheap checks while CI can opt into runtime scenarios.

Suggested targets:

```make
test:
	# existing unit-style test_ verb suite

runtime-headless:
	# compile Cowbell and run the dedicated headless runtime scenario object

runtime-session:
	# compile Cowbell, start daemon, run mock-player scenarios

runtime-test: runtime-headless runtime-session
```

CI order:

1. `make test`
2. `make runtime-headless`
3. `make runtime-session`

Runtime session tests should use only local IPC endpoints under a temp directory:

```text
ipc://$TMPDIR/moor-rpc.sock
ipc://$TMPDIR/moor-events.sock
ipc://$TMPDIR/moor-workers-response.sock
ipc://$TMPDIR/moor-workers-request.sock
```

This avoids port collisions and avoids CURVE setup for local CI. TCP/CURVE can have its own daemon-level test elsewhere if needed.

Each runner should:

- Use a fresh temp DB.
- Use deterministic test players/fixtures.
- Print a tabled summary of failed scenarios.
- Emit enough captured event context to debug failures.
- Exit `1` on any failed scenario.
- Kill/shutdown the daemon on timeout.
- Keep per-scenario timeouts short by default, with opt-in longer stress tests.

## Migration Guidance

Keep these boundaries explicit:

- Pure deterministic helper logic stays as `test_` verbs near the object being tested.
- Runtime state-machine checks without client I/O become headless runtime scenarios.
- Anything whose contract is command text, connection state, or emitted session events becomes a mock-player scenario.
- `.moot` stays available for narrow language/runtime expectation checks, but it should not be the main Cowbell behaviour harness.

As existing tests are revisited, move integration-like `test_` verbs out of public prototypes when they crowd the namespace or rely on shared world state. Prefer dedicated scenario objects or scenario files that the runtime harness can load and invoke by name.

## Open Implementation Questions

- Whether to expose daemon startup as a library helper or spawn `moor-daemon` as a child process. Spawning is closer to production and keeps the first harness simpler.
- Whether mock-player scenarios should use direct `TaskClient::invoke_verb` for command submission or a new `TaskClient::command` helper that wraps the daemon command message path.
- How to mint test auth tokens for fresh players without depending on production login commands for every scenario.
- Whether scenario definitions should be Rust tests, MOO scenario verbs, or a small declarative scenario format. The first pass should use Rust tests plus a small fluent API because assertions over session events are easier there.
- How aggressively to assert exact narrative text versus event kind/content fragments. Exact text is useful for smoke scenarios but brittle for broader behaviour tests.
