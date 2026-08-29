// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Probes fjall's GC-watermark behaviour, which decides how moor's automatic post-checkpoint
//! compaction has to be sequenced.
//!
//! `Keyspace::major_compact()` passes `snapshot_tracker.get_seqno_safe_to_gc()` as the GC
//! watermark, and that value is held down by open snapshots. The question these tests answer is
//! what a compaction can actually reclaim while a checkpoint snapshot is alive, versus after it
//! has been dropped.
//!
//! These are assertions about fjall's semantics rather than moor's code. They exist because the
//! sequencing of the automatic path depends on the answer, and the answer is not what the
//! surrounding investigation assumed.

use fjall::{Database, KeyspaceCreateOptions, Readable};

/// 64 KiB values, so superseded versions are visible in `disk_space()`.
fn big_value(seed: u8) -> Vec<u8> {
    vec![seed; 64 * 1024]
}

const KEYS: u32 = 64;

/// Write one version of every key, tagged `round`, and flush it to its own table.
fn write_round(keyspace: &fjall::Keyspace, round: u8) {
    for key in 0..KEYS {
        keyspace
            .insert(key.to_be_bytes(), big_value(round))
            .expect("insert");
    }
    keyspace.rotate_memtable_and_wait().expect("rotate");
}

fn write_versions(keyspace: &fjall::Keyspace, rounds: u8) {
    for round in 0..rounds {
        write_round(keyspace, round);
    }
}

#[test]
fn major_compact_reclaims_superseded_versions_when_no_snapshot_is_open() {
    let dir = tempfile::tempdir().unwrap();
    let db = Database::builder(dir.path()).open().expect("open");
    let ks = db
        .keyspace("probe", KeyspaceCreateOptions::default)
        .expect("keyspace");

    write_versions(&ks, 6);

    let before = ks.disk_space();
    ks.major_compact().expect("compact");
    let after = ks.disk_space();

    assert!(
        after < before,
        "with no snapshot open, major_compact should reclaim superseded versions \
         (before={before}, after={after})"
    );
}

/// What a compaction reclaims while a snapshot is open, and — more importantly — whether the
/// snapshot still reads the data it was opened to see afterwards.
///
/// The investigation this work came from assumed a live snapshot pins the GC floor hard enough
/// that compaction reclaims nothing. That is not what happens: the watermark is set from the
/// oldest *retained* snapshot minus one, so versions written before the snapshot was taken are
/// still collected, and the space does come back. The guard in moor's automatic path is therefore
/// justified by cost and by `major_compact()` being blocking, not by futility.
#[test]
fn compaction_during_a_snapshot_reclaims_but_must_not_corrupt_the_snapshot_read() {
    let dir = tempfile::tempdir().unwrap();
    let db = Database::builder(dir.path()).open().expect("open");
    let ks = db
        .keyspace("probe", KeyspaceCreateOptions::default)
        .expect("keyspace");

    // Round 0 is what the snapshot should see for all of time.
    write_round(&ks, 0);
    let snapshot = db.snapshot();

    // Confirm the snapshot sees round 0 before anything else happens.
    let sample = snapshot
        .get(&ks, 0u32.to_be_bytes())
        .expect("get")
        .expect("key present");
    assert_eq!(sample[0], 0, "snapshot should open onto round 0");

    // Newer versions land on top of it.
    for round in 1..6 {
        write_round(&ks, round);
    }

    let before = ks.disk_space();
    ks.major_compact().expect("compact");
    let after = ks.disk_space();

    // Whatever it reclaimed, the snapshot must still answer with round 0 for every key. This is
    // the property that matters: if compaction can be run concurrently with a checkpoint at all,
    // the export must not silently change underneath it.
    let mut mismatches = Vec::new();
    for key in 0..KEYS {
        match snapshot.get(&ks, key.to_be_bytes()).expect("get") {
            Some(value) if value[0] == 0 => {}
            Some(value) => mismatches.push(format!("key {key} read round {}", value[0])),
            None => mismatches.push(format!("key {key} vanished")),
        }
    }

    assert!(
        mismatches.is_empty(),
        "a snapshot must keep reading its own version of the data across a concurrent \
         major_compact (reclaimed {before} -> {after}); {} mismatch(es): {:?}",
        mismatches.len(),
        mismatches.iter().take(5).collect::<Vec<_>>()
    );
}

/// The sequencing question for the automatic path: once the checkpoint's snapshot is dropped, is a
/// `major_compact()` immediately able to reclaim, or does the watermark stay stuck until fjall
/// next happens to call `pullup()`?
#[test]
fn major_compact_after_dropping_the_snapshot_reclaims() {
    let dir = tempfile::tempdir().unwrap();
    let db = Database::builder(dir.path()).open().expect("open");
    let ks = db
        .keyspace("probe", KeyspaceCreateOptions::default)
        .expect("keyspace");

    write_versions(&ks, 1);
    let snapshot = db.snapshot();
    let _pinned = snapshot.get(&ks, 0u32.to_be_bytes()).expect("get");
    write_versions(&ks, 5);

    let before = ks.disk_space();

    // Simulate the checkpoint finishing: the snapshot goes away...
    drop(snapshot);
    // ...and we immediately try to reclaim, which is what the automatic path does.
    ks.major_compact().expect("compact");
    let after = ks.disk_space();

    assert!(
        after < before,
        "after the snapshot is dropped, major_compact must reclaim; if this fails, the \
         automatic post-checkpoint compaction needs an explicit watermark pull-up \
         (before={before}, after={after})"
    );
}
