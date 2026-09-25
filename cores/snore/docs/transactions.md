# Transactions and maintenance

mooR uses snapshot isolation. A task can span several transactions. `suspend()`, including
`suspend(0)`, commits the current transaction. A blocking input read also ends that transaction.
`fork` commits before dispatching its child, and the parent continues in a new transaction.

Ordinary notification output is buffered until commit. A later error cannot undo an earlier commit.
Connection control and other host effects need their own handling. The core does not enable the
wizard-only property overwrite flag that bypasses ordinary write-conflict handling.

## Extension rules

Keep related changes within one transaction. After an input wait or yield, read current state and
check authority again. Local variables still contain values from the earlier transaction.

Custom movement, output, permission, forwarding, and lifecycle hooks can suspend or fork. The core
cannot promise atomic behavior across arbitrary replacements of those hooks. In particular:

- Creation and recycling hooks must not change ownership or quota policy during the operation.
  Recycler bookkeeping uses the owner and cached size associated with that lifecycle operation.
- A byte-quota measurement hook must not suspend within one owner's accounting update.
- Lock parsing uses shared scanner state. Matching hooks used during a parse must not suspend or
  reenter the parser.
- Collection callbacks run with caller permissions. A callback that suspends commits the caller's
  transaction even though the collection helper adds no suspension itself.

The [style guide](../STYLE_GUIDE.md) covers permission checks and transaction boundaries in code.

## Core boundaries

| Operation                      | Boundary and state handling                                                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Command matching               | No automatic yield between matching and dispatch. Custom scope hooks own any additional boundary.                                    |
| Movement and container changes | Standard hooks do not add budget yields within the state update. Descendant hooks can change that contract.                          |
| Creation and recycling         | Ownership lists and byte-quota records are maintained through the core interfaces. Task cleanup forks after deletion.                |
| Ownership transfer             | Optional suspension occurs before the transfer. The owner, `c` property owners, quota, and ownership lists change together.          |
| Recursive property changes     | Each object is a complete unit. Descendants can commit separately; the whole tree is not atomic.                                     |
| Mail storage                   | Standard remove, undo, renumber, sort, and keep operations add no suspension. Delivery stores messages before forking notifications. |
| Mail selection                 | Commands compare selected records after confirmation reads and reject changed or unreadable folders.                                 |
| Mail composition               | Input and delivery can commit. Buffer identity checks preserve edits and replacement sessions across those boundaries.               |
| News publication               | Resolve the selected messages before assigning edition membership. Notification follows the update.                                  |
| Editor input                   | Each buffer has a UUID token. After input, reacquire the session, check its token and authority, then insert.                        |
| Editor saves                   | Read the current target and permissions when saving. Descendant storage hooks remain responsible for their own boundaries.           |
| Password login                 | A password prompt installs a pending action. The next input task repeats authentication and admission checks.                        |
| OAuth claims                   | Creation, identity binding, and index changes add no suspension. A shared claim revision forces competing assignments to conflict.   |
| Guests                         | Availability is published after reset hooks succeed. A failed custom hook can leave a guest unavailable for administrator repair.    |
| Dictionary review              | Recheck authority and pending membership after each prompt. Preserve distinct submissions that arrive during review.                 |
| Reports and source searches    | May yield between complete output or scan units. Their results can span database versions.                                           |
| Housekeeping and idle checks   | Delays are intentional service waits. Recheck validity and connection state before the resulting action.                             |
| Site and registration pruning  | Read and update one current key without a budget yield inside its membership rewrite. Yield between keys.                            |
| Numeric and matrix work        | Long calculations can use budget-aware yields. Their local inputs remain snapshots, but the caller's transaction can commit.         |
| Core extraction                | Save explicit phases and checkpoints. Resume repeats unfinished work; completed transactions remain committed.                       |

Mail refile can copy messages successfully and then fail to remove the source; the command reports
that result. Timestamp-based unread tracking retains its existing equal-timestamp limits. Selection
comparison detects changed records, not a change followed by restoration of identical records.

## Byte quotas

`$quota_utils` defaults to `$byte_quota_utils`. Creation checks the allowance and the number of
unmeasured objects. Measurement caches native size estimates, and ownership transfer or recycling
adjusts the corresponding accounting.

`$byte_quota_utils:summarize_one_user(who[, age_seconds])` updates one owner's totals without an
explicit suspension. A negative age measures previously unmeasured objects. A large owner can
exhaust the task budget; the standard path does not publish partial totals to avoid that failure.

A wizard can run a bounded pass with `measurement_task([seconds])`, or schedule one daily worker
with `schedule_measurement_task()`. Repeated scheduling returns the existing worker. The worker runs
at 08:00 UTC initially, then waits a day after each pass. It commits between complete owners. Custom
daily-scan hooks run after the owner's summary.

Byte counts are estimates. `@measure` breakdowns distinguish native object estimates from property
and verb-source payloads; those figures must not be added together as an on-disk total. The
inherited overhead-estimate helper methods remain approximate interfaces.

## Index maintenance

Registration pruning visits existing map keys and preserves records with administrative reasons.
Site pruning has named and numeric entry points and retains active membership. Progress records
contain the last completed key, not a position in an alphabet scan. Repeating a pass is safe for the
standard methods; it starts a fresh key snapshot.

A wizard can schedule a single daily site-pruning worker with `$site_db:schedule_prune()`. Its
initial run is at 09:00 UTC. Resetting an active prune requires wizard authority. These services are
not started automatically by a fresh core.

## Core extraction

Run `make-core-database` only in an isolated disposable world. It removes world data, including UUID
objects. Selected UUID core objects receive numbered IDs; existing numbered core objects retain
their identities. Gaps and the allocation high-water mark remain.

If extraction stops, repair the cause and use `make-core-database resume` as the same wizard. Custom
hooks must tolerate repeated calls after a saved checkpoint. In-world `help make-core-database`
describes selection, reference repair, and export.

`make test-extraction` checks cancellation, authority, proxies, UUID ownership, deletion
checkpoints, server restart, and extracted export/reimport using disposable databases.
