# Scheduled Tasks

mooR can run a verb for you later, once or on a cadence, without a task sitting in `suspend()`
between firings. These _native schedules_ live in the kernel's scheduler beside the suspended-task
queue, survive a server restart, and cost nothing while idle: a schedule that fires once an hour
consumes no task, no transaction and no memory beyond its own entry for the other 59 minutes and 59
seconds.

This chapter is for core authors replacing "heartbeat" loops — a wizard task that `suspend(1)`s
forever and calls everything registered on it — with something the server does for them.

## Why not a loop?

The traditional MOO answer to "do this every N seconds" is a forked task:

```moo
fork (0)
  while (1)
    this:tick();
    suspend(1);
  endwhile
endfork
```

That works, but every suspended task carries its entire VM state in the tasks database, every wake
is a transaction whether or not there is anything to do, and one such loop calling a hundred
consumers puts all hundred in one transaction: one conflict retries everything, one traceback aborts
everything, and the tick budget is shared. When the loop dies — a wizard `kill_task`s the wrong id,
or the retry limit is exhausted — nothing restarts it.

A native schedule inverts this. The kernel holds a deadline and a `(object, verb, args)` triple.
When the deadline passes, it starts a _fresh_ background task that calls the verb, exactly as `fork`
would have. Each firing is its own task with its own transaction and its own tick budget; a fault in
one leaves the others alone. The schedule is data, not a task, so it is restored from the tasks
database after a restart with its id and its deadline intact.

## The builtins

| Function                                                   | Purpose                                                          |
| ---------------------------------------------------------- | ---------------------------------------------------------------- |
| `schedule_at(obj, verb, when [, args] [, options])`        | Run `obj:verb(@args)` once at Unix time `when`. Returns an id.   |
| `schedule_every(obj, verb, interval [, args] [, options])` | Run `obj:verb(@args)` every `interval` seconds. Returns an id.   |
| `schedule_stop(id)`                                        | Cancel. Returns `true` if something was cancelled, else `false`. |
| `schedule_valid(id)`                                       | Whether the id refers to a schedule that will fire again.        |
| `schedule_info(id)`                                        | A map describing the schedule and its run history.               |
| `schedules([owner])`                                       | Live schedule ids the caller may see.                            |
| `schedules_for(obj)`                                       | Live schedule ids whose target is `obj`.                         |

The full argument-by-argument reference is in
[Built-in Functions: Server](../the-moo-programming-language/built-in-functions/server.md#schedule_at).

## A first schedule

```moo
// Ring the bell at the top of the next hour.
next_hour = (time() / 3600 + 1) * 3600;
this.bell_schedule = schedule_at(this, "ring", next_hour);
```

At `next_hour`, the scheduler starts a background task and calls `this:ring(elapsed)`. That trailing
argument is the number of real seconds since the schedule was last fired (a float; `0.0` the first
time) — see [pass_elapsed](#pass_elapsed) below. Inside `ring`, `player` is `this` (the target)
unless you said otherwise, `caller` is `player`, and the verb runs with its owner's permissions like
any other verb.

```moo
// Every minute, forever (or until stopped).
this.upkeep_schedule = schedule_every(this, "upkeep", 60);
```

Recurring deadlines are computed from the _previous deadline_, not from when the previous firing
finished, so a 60-second schedule fires at `t`, `t+60`, `t+120`, … regardless of how long each
`upkeep` took or whether it faulted.

## Schedule ids and transactions

A schedule id is an integer from its own id space; it is never a task id, so `kill_task` on one is
`E_INVARG` and `schedule_stop` on a task id is a quiet `false`.

Creation and cancellation are **buffered until your task commits**, with exactly the semantics of
`task_send()`:

- A schedule created in a task that rolls back — `rollback()`, an uncaught error, a conflict retry —
  never exists. The id you were handed simply never fires.
- `schedule_stop()` takes effect when your task commits.
- Within the creating task, `schedule_valid(id)` is already `true` and `schedule_stop(id)` already
  works, so code that creates-then-cancels in one transaction behaves sensibly.

Because the schedule is committed with your transaction, storing the id in a property in the same
transaction is safe: either both land or neither does.

## Stopping and stale ids

`schedule_stop(id)` **never raises for an id that no longer exists.** It returns `false`. A one-shot
that has already fired, a recurring schedule that retired itself, an id from before a database
reload — all `false`, none an error. This is deliberate: cancelling something that already happened
is an ordinary race, and the calling code should not need a `try` around it.

It does raise `E_PERM` if the schedule exists, is live, and you are neither its owner nor a wizard.

## Retirement

A schedule that will not fire again is _retired_. It keeps its entry (so `schedule_info()` can tell
you why) until the scheduler purges it, but `schedule_valid()` is `false` and it no longer appears
in `schedules()`/`schedules_for()`. The reasons, as reported in `retire_reason`:

| `retire_reason`     | Meaning                                                                        |
| ------------------- | ------------------------------------------------------------------------------ |
| `"one_shot_done"`   | A `schedule_at` fired and did not re-arm.                                      |
| `"returned_zero"`   | Under the adaptive protocol, the verb returned `0`.                            |
| `"negative_return"` | Under the adaptive protocol, the verb returned a negative number.              |
| `"max_faults"`      | The verb faulted `max_faults` times in a row.                                  |
| `"invalid_target"`  | The target was recycled or the verb no longer resolves when the deadline came. |

`schedule_stop()` does not retire; it removes the entry outright.

## Options

The optional fifth argument is a map. Keys may be strings or symbols; an unknown key is `E_INVARG`
at creation, so a typo cannot be silently ignored.

### `adaptive`

Enables the _return-value protocol_: the fired verb's return value sets the next delay.

| Verb returns        | Effect                                         |
| ------------------- | ---------------------------------------------- |
| positive number `n` | Fire again in `n` seconds (int or float).      |
| `0`                 | Retire (`"returned_zero"`).                    |
| negative number     | Retire (`"negative_return"`).                  |
| anything else       | One-shot: retire. Recurring: keep the cadence. |

Default: **on** for `schedule_at`, **off** for `schedule_every`. A one-shot that returns `0.5` is
therefore a self-rescheduling chain with no loop and no task between links:

```moo
// #219:lockup -- called by its own schedule.
if (this:customers_present())
  return 30;   // check again in half a minute
endif
this:lock_doors();
return 0;      // done
```

With `adaptive` on for a recurring schedule, a positive return overrides the next interval only;
after that firing the cadence resumes.

### `catchup`

What to do at restart when a deadline was missed while the server was down.

| Value    | Behaviour                                                                                        |
| -------- | ------------------------------------------------------------------------------------------------ |
| `"skip"` | Advance to the next future deadline on cadence; count the misses in `missed_count`. **Default.** |
| `"once"` | Fire once immediately, then resume the cadence.                                                  |
| `"all"`  | Fire once per missed interval. Use with care: a week of downtime is a lot of firings.            |

A one-shot with a past deadline always fires once (there is no cadence to skip along).

### `overlap`

What to do when a deadline arrives while the _previous_ firing of the same schedule is still
running.

| Value          | Behaviour                                                 |
| -------------- | --------------------------------------------------------- |
| `"skip"`       | Drop this firing; increment `overlap_count`. **Default.** |
| `"queue"`      | Run it as soon as the current firing finishes.            |
| `"concurrent"` | Start it anyway; two tasks now run the verb at once.      |

### `jitter`

Seconds (int or float, ≥ 0). Each deadline is offset by a uniformly random amount in
`[-jitter, +jitter]`, never earlier than one scheduler tick from now. Give every ambient schedule a
little jitter so a thousand "every 60 seconds" rooms do not all fire on the same tick.

### `max_faults`

Consecutive faults (uncaught error, tick/time limit, or failure to start) before the schedule
retires with `"max_faults"`. `0` means unlimited. Default `50`. A successful firing resets the
consecutive count; `fault_count` in `schedule_info()` is the lifetime total.

### `pass_elapsed`

Default **on**. Appends one float argument — real seconds since the schedule's previous firing, or
`0.0` on the first — after `args` (and after `state`, if any). Verbs that integrate over time
(decay, regeneration, cooling) should use it rather than assuming the nominal interval, because
`"skip"` catchup and scheduler load both stretch the real gap.

A verb that takes no arguments and does not want one should pass `["pass_elapsed" -> 0]`; an
unexpected argument is harmless to most verbs but confusing to read.

### `state`

An opaque MOO value appended to `args` on every firing (before `elapsed`). Limited to 4 KB
serialised; larger is `E_INVARG`. It is constant for the life of the schedule — this is for a cursor
or a key, not a mutable accumulator. Mutable state belongs on the target object.

### `persist`

Default **on**: the schedule is saved to the tasks database and restored after a restart. Pass
`["persist" -> 0]` for something that only makes sense within this server run (a debounce timer, a
one-off retry).

### `player`

The value of `player` inside the fired verb. Default: the target object. Set it when the verb
notifies `player` and the target is not a player — e.g. a room's ambient message that should reach a
particular character.

## Permissions

- The creating task's permissions (as seen by `task_perms()` at the moment of the call) become the
  schedule's **owner** and its **authority principal**. The verb must resolve _now_ under those
  permissions or creation is `E_INVARG`: better a loud failure at the call site than a quiet
  `"invalid_target"` retirement at three in the morning.
- The fired verb runs as its own owner, as every verb does. The authority principal governs only
  verb lookup at firing time and what `caller_perms()` reports inside the verb.
- `schedule_stop`, `schedule_info`: owner or wizard.
- `schedules()`: a wizard sees every live schedule; anyone else sees their own. With an `owner`
  argument, wizard or self only.
- `schedules_for(obj)`: anyone. Recycling an object and cancelling what targets it must work
  regardless of who created those schedules.

## Inspecting schedules

`schedule_info(id)` returns a string-keyed map. Times are float Unix seconds (`0.0` for "never");
durations are integer nanoseconds; absent optional values are `0`.

```
id, target, verb, args, owner, authority, kind ("at"|"every"), interval,
created_at, next_run, last_run,
run_count, fault_count, consecutive_faults, last_fault, missed_count, overlap_count,
last_duration_ns, mean_duration_ns, p99_duration_ns,
running_task (0 if idle), interval_clamped,
retired (bool), retire_reason (string, "" while live),
adaptive, catchup, overlap, jitter, max_faults (0 = unlimited), pass_elapsed, persist,
player, state
```

A wizard audit that flags anything firing more often than it should is a few lines:

```moo
for id in (schedules())
  info = schedule_info(id);
  if (info["kind"] == "every" && info["interval"] < 1.0)
    notify(player, tostr("Schedule ", id, " on ", info["target"], ":", info["verb"], " runs every ", info["interval"], "s"));
  endif
endfor
```

## What the kernel does and does not enforce

- **Sub-tick intervals are clamped**, not rejected. `schedule_every(x, "v", 0.001)` fires once per
  scheduler tick (10 ms by default) and `schedule_info()` reports `interval_clamped: true`. If your
  core wants a stricter floor — and for anything a player-facing verb can trigger, it should — put
  it in the core's wrapper, not here.
- **Firings are ordinary background tasks.** They get `bg_ticks`/`bg_seconds`, they appear in
  `queued_tasks()` while running, they can be `kill_task`ed (the schedule counts it as a fault), and
  their output goes to a background session for `player`.
- **A conflict retry is not a fault.** If the firing's transaction conflicts and is retried, the
  schedule sees one firing, not two, and `fault_count` is untouched.
- **Recycling the target** does not cancel schedules by itself: the next firing finds the target
  gone and retires with `"invalid_target"`. A core's `recycle` path should call `schedules_for(obj)`
  and `schedule_stop` each id so the retirement never has to happen.
- **Anonymous objects** referenced by a schedule's target, args or state are kept alive by the
  schedule (it is a GC root).

## Recipes

**Debounce.** Coalesce a burst of events into one handler run:

```moo
if (schedule_valid(this.flush_id))
  schedule_stop(this.flush_id);
endif
this.flush_id = schedule_at(this, "flush", ftime() + 2.0, {}, ["persist" -> 0]);
```

**Per-object upkeep with catch-up.** Let the verb integrate over `elapsed` so nothing depends on the
schedule being punctual:

```moo
// this:regenerate(elapsed)
{elapsed} = args;
this.hp = min(this.max_hp, this.hp + this.regen_per_second * elapsed);
```

**One driver per object, no double drive.** Store the id, and check it before creating another:

```moo
if (!schedule_valid(this.drive_id))
  this.drive_id = schedule_at(this, "drive", ftime());
endif
```

**Replacing a heartbeat registry.** Rather than one schedule per consumer, give each _class_ of
consumer a batch verb on one recurring schedule, and have that verb iterate its live instances with
`suspend_if_needed()` between them. One schedule, one entry in `schedules()`, and a faulting
instance can be caught per-iteration without losing the batch.
