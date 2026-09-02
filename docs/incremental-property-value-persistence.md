# Bounded Property Append Log

Status: implemented

Date: 2026-09-02

## Decision

mooR reduces large-list write amplification with a bounded append log for property values.

The first implementation supports validated appends to top-level lists. All other updates store a
complete `Var` value.

Each property has one ordered record chain in the `object_propvalues` keyspace. The chain starts
with a complete value and contains a limited number of append records.

The design has no separate head keyspace. It also has no record UUIDs or background materializer.

The ordered database writer creates a new complete record when a chain reaches its limit. A
dedicated encoder performs this infrequent complete serialization.

This change does not merge concurrent appends. The existing serializable transaction rules remain
unchanged.

## Problem

mooR stores each property value as one serialized `Var`. A small append to a large list therefore
serializes and writes the complete list.

One observed property had an encoded size of approximately 9.67 MB. Thirteen updates increased the
encoded size by only 832 bytes.

Those updates sent approximately 126 MB to Fjall. Each update spent between 1.2 and 2.0 seconds in
encoding.

Each Fjall commit then took between 0.8 and 1.1 seconds. The complete values also entered the Fjall
journal, memtables, table files, and compaction work.

The runtime list operation is not the main source of this cost. `List` uses `imbl::Vector`, which
shares the unchanged tree nodes.

The cost starts when `encode_db_var` visits every list element. Fjall key-value separation cannot
remove this serialization or journal cost.

## Scope

The first implementation has these properties:

- MOO programs continue to read and write ordinary `Var` values.
- Only a top-level list append can use an append record.
- A replacement, insertion, or other mutation stores a complete value.
- A chain has a fixed record-count limit and a fixed delta-byte limit.
- Startup, snapshot export, and point reads use one reconstruction implementation.
- The logical property timestamp remains available after restart.
- The database format changes without a compatibility reader.

The first implementation does not change these areas:

- Nested list updates
- Map, string, binary, or flyweight updates
- Concurrent append conflict rules
- The MOO language or builtin set
- Fjall compaction policy
- Runtime paging of cold property values

## Why the Serialization Hook Is Too Late

`BatchValue::encode` receives the final value, a transaction timestamp, and a Planus builder. It
does not receive the base value or the database key.

An append record needs both the base value and the final value. The encoder must prove that the base
list is a prefix of the final list.

`WorkingSet` still contains the base index and the proposed update.
`FjallProvider::encode_working_set` currently consumes the final tuples and discards access to that
base index.

The property provider must classify the mutation before that information disappears. The generic
relation path can remain unchanged.

## Mutation Classification

The existing `OP_HINT_LIST_APPEND` flag identifies a candidate. The flag is not proof of an append.

The classifier accepts an append only when all these conditions are true:

1. The operation updates an existing value.
2. The final value has the append hint.
3. The base and final values are lists.
4. The final list is longer than the base list.
5. The classifier proves that the complete base list is a prefix of the final list.
6. The comparison stays within a fixed work budget.

The classifier uses shared `imbl::Vector` chunks to prove equality. Pointer-equal chunks need no
element comparison.

The classifier compares the elements at changed chunk boundaries. If the proof exceeds its work
budget, the operation becomes a complete replacement.

The hint can only select a candidate. An incorrect hint cannot create an incorrect append record.

The classifier extracts the appended suffix after it proves the prefix. The existing encoder pool
serializes only this suffix.

## Physical Format

The new format reuses the `object_propvalues` keyspace. Each physical key has this form:

```text
<ObjAndUUIDHolder bytes><record version, big endian>
```

`ObjAndUUIDHolder` has a fixed-size byte representation. The suffix keeps all records for one
property adjacent and orders them by record version.

Each value has a small versioned envelope:

```text
PropertyValueRecord {
    format_version
    logical_timestamp
    kind
    payload
}
```

The `kind` field selects one of these payloads:

```text
Full {
    encoded_var
}

ListAppend {
    encoded_suffix
}
```

`Full` uses the current database encoding for `Var`. `ListAppend` contains an encoded list of the
new elements.

The record key contains a monotonic storage-record version. The record envelope contains the logical
tuple timestamp.

The writer restores the next record version from the largest persisted key during startup. The
record version therefore does not collide when the runtime publication counter restarts.

These values are different. Recovery must not derive the tuple timestamp from the publication
version.

## Chain Rules

The visible records for one property form one chain. The first visible record must be `Full`.

Zero or more `ListAppend` records can follow the complete record. Their key order defines append
order.

Two limits control each chain:

- The maximum number of append records
- The maximum sum of encoded append bytes

The database permits 64 records in one chain. Thus, a chain contains one `Full` record and at most
63 `ListAppend` records.

The encoded append payloads can contain at most 4 MiB. The writer creates a complete record before
the next append exceeds either limit.

The ordered writer keeps a small chain index for active property values. The index stores the active
record versions and append bytes. The record count comes from the version list.

Most properties have one `Full` record. Their chain-index entry therefore stores one version and no
append allocation.

Startup builds this index during the property-value scan. The scan already visits every active
property value.

## Write Path

### Complete Value

An insertion or replacement uses this sequence:

1. An encoder serializes the complete final value.
2. The ordered writer inserts a new `Full` record at the next record version.
3. The same Fjall batch removes all previous records for that property.
4. The writer updates its chain index after a successful commit.

Fjall snapshots that predate the batch continue to see the old records. The database can reclaim
those versions after the snapshots expire.

### Append Within the Limits

A validated append uses this sequence:

1. An encoder serializes the suffix.
2. The ordered writer reads the chain metadata from its in-memory index.
3. The writer inserts one `ListAppend` record at the next record version.
4. The writer updates its chain index after a successful commit.

The Fjall batch also contains every other relation update from the transaction. The transaction
therefore keeps its existing atomic commit boundary.

### Append at a Chain Limit

The append encoder retains a cheap clone of the final `Var`. The persistent list shares its
unchanged nodes, so this clone does not copy the full list.

If an append reaches a chain limit, the ordered writer sends that final value to one rollup encoder.
The writer then waits for the encoded complete value.

The rollup encoder is separate from the normal result channel. This separation prevents a deadlock
when normal encoders fill the writer queue.

The writer commits the complete record and removes the previous chain in one Fjall batch. This
foreground rollup replaces a background materializer and its stale-result protocol.

The rollup blocks publication persistence for one complete encode at a predictable interval. It does
not run on a MOO task thread.

### Delete

A property deletion removes every active record for that property in the transaction Fjall batch.
The writer removes the chain-index entry after a successful commit.

The chain limits bound the number of remove operations.

## Cost Model

Let `N` be the maximum number of appends between complete records. Let `F` be the encoded complete
value size, and let `D` be the average encoded suffix size.

The approximate encoded bytes per append are `D + F / N`. The current format encodes approximately
`F + D` bytes for every append.

For a 9.67 MB value and `N = 64`, the amortized complete-value component is approximately 151 KB per
append. Ordinary appends still encode only their suffix.

The rollup transaction inserts one complete record and removes at most `N` old records. The remove
operations contain small keys and Fjall tombstones.

A point read processes one complete record and at most `N - 1` suffix records. A complete database
scan reads the same bytes in property-key order.

The chain index uses one record version for a complete property. A property with deltas uses at most
`N` record versions plus counters.

The benchmarks report rollup latency, amortized bytes, and read cost. The chain index stores one
`u64` for each visible record and one byte counter for each active property.

## Measured Result

The write benchmark used one list with 1,024 strings. Each string contained 9,472 bytes. The base
list therefore contained 9,699,328 string bytes.

The benchmark applied 70 one-string appends. All 70 updates passed the append classifier. The run
produced these results:

- The classifier used 204 microseconds per append.
- The normal database encoder used 16.5 microseconds per transaction.
- The Fjall commit used 25.5 microseconds per transaction.
- The append records used 669,611 bytes in total.
- One foreground rollup encoded 10,340,775 bytes in 13.9 milliseconds.
- The total encoded property data was approximately 157 KB per append.
- The writer reported no backpressure.

Without append records, the 70 updates encode approximately 679 MB of complete values. The bounded
chain encoded approximately 11.0 MB, including the rollup.

The export benchmark used a 9.7 MB value with 63 append records. Snapshot reconstruction and export
used 2.58 milliseconds at the median and 2.84 milliseconds at p95.

## Read and Recovery Path

A property prefix scan returns its visible records in record-version order. Reconstruction uses this
sequence:

1. Decode the first record as a complete `Var`.
2. Apply each list suffix in key order.
3. Use the logical timestamp from the last record.
4. Reject an invalid first record, record kind, suffix, or chain length.

Reconstruction applies at most the configured number of append records. Recovery work is therefore
bounded for each property.

The database must provide one `PropertyValueStore` decoder. These callers use that decoder:

- Initial database loading
- `FjallSnapshotLoader` point reads
- Snapshot export scans
- Database diagnostics that inspect property values

No caller can decode the `object_propvalues` keyspace as one key and one `Var` after this change.

The complete database load can group adjacent property records in one sequential scan. It does not
need one Fjall range scan for each property.

## Transaction Isolation

This storage format is below transaction conflict detection. It does not change the logical update
that the transaction publishes.

Two transactions that append to the same list still conflict under the current rules. One
transaction retries.

Automatic append merging is unsafe for generic MOO code. A transaction can read the old list and
make another write that depends on that value.

The persistence layer receives accepted transactions in publication order. It assigns record
versions in the same order.

## Atomicity and Errors

Each mutation and its chain cleanup use one cross-keyspace Fjall batch with the other transaction
operations. A crash exposes either the old chain or the new chain.

The writer changes its in-memory chain index only after Fjall accepts the batch. A failed commit
leaves the old index unchanged.

Startup rejects these states:

- A chain without an initial `Full` record
- An append payload that is not a list suffix
- More records or bytes than the hard format limits permit
- A malformed logical timestamp
- An unknown record format or kind

These states indicate database corruption or a writer defect. Recovery must not silently skip the
property.

## Database Format

This change is a breaking database-format change. The implementation increments the major format
version in `fjall_format.rs`.

The implementation does not add a dual reader or an in-place conversion. Existing databases must use
an object-definition export and import across this change.

Golden-byte tests cover the record envelope and key encoding. Those tests define the format
contract.

## Metrics and Diagnostics

The implementation records these metrics:

- Append candidates
- Accepted append records
- Rejected candidates by reason
- Complete replacements
- Foreground rollups
- Encoded complete bytes
- Encoded suffix bytes
- Rollup encoding time
- Reconstruction time and record count

The existing slow-encoding warning remains useful for complete replacements and rollups. The
benchmark reports the suffix bytes and foreground rollups.

## Implementation Phases

### Phase 1: Classifier and Measurements (complete)

This phase added the classifier without a storage-format change. It counted accepted candidates and
their suffix sizes but continued to encode complete values.

The `bench-string-history` workload includes these cases:

- Append one short string to a large list.
- Append several strings in one transaction.
- Replace one element in a large list.
- Append after a list reconstruction without shared chunks.

This phase established the classifier hit rate and its comparison cost.

### Phase 2: Record Codec and Reconstruction (complete)

This phase added the new key and value codecs. It also added the shared reconstruction code and
corruption tests.

The tests use fresh temporary databases. The implementation does not contain an old-format reader.

### Phase 3: Prepared Property Mutations (complete)

This phase added a property-specific prepared operation. Generic relation operations did not change.

The prepared append carries these values:

```text
property key
logical timestamp
encoded suffix
final Var
```

The complete operation carries an encoded `Var`. The delete operation carries only the property key.

### Phase 4: Ordered Writer and Rollup (complete)

This phase added the chain index and the rollup encoder. One logical property operation now expands
into the required Fjall operations.

The writer preserves publication order while it waits for a rollup. A queue-saturation test covers
the separate rollup channel.

### Phase 5: Loader and Export Integration (complete)

This phase routed startup, point reads, and exports through `PropertyValueStore`. It removed direct
one-record decoding for `object_propvalues`.

The database tests cover restart, point reads, exports, replacement, deletion, and corruption. The
final verification also includes the objdef and Cowbell tests.

## Acceptance Criteria

The implementation is useful only if it meets these requirements:

1. Append encoding time depends on suffix size, not the complete list size.
2. Fjall bytes for ordinary appends depend on suffix size and record overhead.
3. A rollup occurs before either chain limit is exceeded.
4. Recovery applies a bounded number of records for each property.
5. Startup and export reconstruct identical values and timestamps.
6. Concurrent append conflict tests keep their current results.
7. Crash tests never expose a partial chain replacement.
8. The benchmark reports complete-encode, append-encode, commit, and rollup costs separately.

The target benchmark uses a list near 10 MB and appends one short string. Ordinary append cost must
stay approximately constant as the base list grows.

The amortized cost includes one complete rollup per chain interval. The benchmark must report this
cost instead of hiding it.

## Cost and Risk

This design still adds a special storage format for one relation and one mutation type. That is the
main maintenance cost.

The design also changes every direct property-value reader. A missed reader can produce incomplete
exports or incorrect recovery.

The bounded chain needs no head record, UUID allocation, asynchronous materializer, stale-result
check, or cleanup queue.

The foreground rollup produces a periodic latency spike in persistence. A larger chain interval
reduces rollup frequency but increases recovery work.

This tradeoff is measurable. The implementation must choose the limits from benchmark data and must
expose the rollup cost.

## Decision Gate

Phase 1 is small and does not change the database format. Its measurements determine if the storage
work continues.

When common appends pass the fast classifier without a complete prefix scan, continue after Phase 1.

When ordinary write cost stays independent of the base-list size, continue after the prototype.

If the classifier rarely succeeds, property sharding remains the lower-complexity solution. If it
succeeds, the bounded log directly removes the measured amplification.
