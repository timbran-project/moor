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

//! End-to-end tests for automatic post-checkpoint compaction, against a real on-disk `TxDB`.
//!
//! The unit tests around `AutoCompactionConfig::decide` cover the arithmetic, and the ones in
//! `checkpoint.rs` cover the wiring with a spy. Neither shows that the two halves agree about a
//! real database: that the live-bytes figure the checkpoint scan produces, compared against the
//! disk figure the engine reports, actually classifies a bloated database as bloated and a healthy
//! one as healthy — and that compacting then reclaims what was predicted.
//!
//! The failure this guards against is a measurement mismatch, and it is not hypothetical: the
//! first version of this compared live *bytes* against `disk_space()`, and these tests are what
//! caught that fjall's lz4 compression of deeper levels makes that ratio meaningless. At identical
//! redundancy the byte ratio read 0.04 for repetitive values and 7.03 for random ones. The signal
//! is now rows against rows.

use moor_common::{
    model::{ObjectKind, PropFlag, TaskPermissions, WorldStateSource},
    util::BitEnum,
};
use moor_db::{
    AutoCompactionConfig, CompactionDecision, Database, DatabaseConfig, TableConfig, TxDB,
};
use moor_var::{Obj, SYSTEM_OBJECT, Symbol, v_str};

fn perms() -> TaskPermissions {
    TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
}

/// A database whose property memtables flush often.
///
/// The default 512 MiB memtable coalesces rewrites in memory, so a small test never gets superseded
/// versions onto disk at all — the redundancy sits in the journal and the tables stay at live size.
/// A production database flushes constantly and does accumulate them. Shrinking the memtable here
/// reproduces that in a few megabytes instead of a few hundred.
fn flushing_config() -> DatabaseConfig {
    let small = Some(TableConfig {
        max_memtable_size: Some(256 * 1024),
    });
    DatabaseConfig {
        object_propvalues: small.clone(),
        object_propflags: small,
        ..DatabaseConfig::default()
    }
}

/// 64 KiB of pseudorandom printable bytes.
///
/// Deliberately incompressible: with repetitive values lz4 shrinks the deeper levels so far that
/// byte-based measurements stop resembling anything, which is the trap this file exists to document.
fn big_value(seed: u64) -> String {
    let len = 64 * 1024;
    let mut s = String::with_capacity(len);
    let mut x = seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1;
    while s.len() < len {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        s.push(char::from(33 + (x % 90) as u8));
    }
    s
}

/// Logical size of the live property rows, as the yardstick for "compacted down to live size".
fn live_property_bytes(db: &TxDB) -> u64 {
    let snapshot = db.create_snapshot().unwrap();
    snapshot.begin_full_scan().unwrap();
    let bytes = snapshot.full_scan_live_property_bytes().unwrap();
    snapshot.end_full_scan();
    bytes
}

/// What a checkpoint measures: live property rows from a prefetching scan, against the rows the
/// engine actually stores.
fn measure(db: &TxDB) -> (u64, u64) {
    let snapshot = db.create_snapshot().unwrap();
    snapshot.begin_full_scan().unwrap();
    let live = snapshot
        .full_scan_live_property_rows()
        .expect("fjall snapshots count live property rows during a full scan");
    snapshot.end_full_scan();
    drop(snapshot);
    (live, db.stored_property_rows().unwrap())
}

/// Create `count` objects each holding one large property value.
fn populate(db: &TxDB, count: usize) -> Vec<Obj> {
    let mut tx = db.new_world_state().unwrap();
    let mut objects = Vec::new();
    for i in 0..count {
        let obj = tx
            .create_object(
                &perms(),
                &Obj::mk_id(-1),
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        tx.define_property(
            &perms(),
            &obj,
            &obj,
            Symbol::mk("payload"),
            &SYSTEM_OBJECT,
            BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
            Some(v_str(&big_value(i as u64))),
        )
        .unwrap();
        objects.push(obj);
    }
    tx.commit().unwrap();
    objects
}

/// A database that has only ever been written once has little dead space, and must not be
/// compacted on every checkpoint. This is the false-positive direction, and it is the one that
/// would quietly cost a full table rewrite every twelve minutes in production.
#[test]
fn a_freshly_written_database_is_not_classified_as_bloated() {
    let dir = tempfile::tempdir().unwrap();
    let (db, _) = TxDB::try_open(Some(dir.path()), flushing_config()).unwrap();
    populate(&db, 40);
    db.wait_for_persistence().unwrap();

    let (live, stored) = measure(&db);

    // Judge on the ratio alone, with the size floor lifted, so this is a statement about the
    // measurement and not about the row threshold hiding the answer.
    let config = AutoCompactionConfig {
        after_checkpoint: true,
        min_amplification: 2.0,
        min_stored_rows: 0,
    };
    let decision = config.decide(live, stored);

    assert!(
        matches!(decision, CompactionDecision::BelowThreshold { .. }),
        "a write-once database should not look bloated: live={live} stored={stored} -> {decision:?}"
    );
}

/// Rewriting every property value several times leaves the superseded versions on disk. That is
/// exactly the situation the findings described, and the decision must catch it and the compaction
/// must then actually reclaim the space.
#[test]
fn repeated_rewrites_are_detected_and_reclaimed() {
    let dir = tempfile::tempdir().unwrap();
    let (db, _) = TxDB::try_open(Some(dir.path()), flushing_config()).unwrap();
    let objects = populate(&db, 40);

    // Overwrite every value repeatedly. Each pass supersedes the last, and nothing removes the
    // old versions.
    for pass in 1..=6u64 {
        let mut tx = db.new_world_state().unwrap();
        for (i, obj) in objects.iter().enumerate() {
            tx.update_property(
                &perms(),
                obj,
                Symbol::mk("payload"),
                &v_str(&big_value(1000 + pass * 100 + i as u64)),
            )
            .unwrap();
        }
        tx.commit().unwrap();
    }
    db.wait_for_persistence().unwrap();

    let disk_before = db.disk_bytes().unwrap();
    let (live, stored_before) = measure(&db);
    assert!(
        stored_before > live,
        "the engine should be holding superseded rows: live={live} stored={stored_before}"
    );

    let config = AutoCompactionConfig {
        after_checkpoint: true,
        min_amplification: 2.0,
        min_stored_rows: 0,
    };
    let decision = config.decide(live, stored_before);
    assert!(
        matches!(decision, CompactionDecision::Compact { .. }),
        "six rewrites of every value should read as amplified: \
         live={live} stored={stored_before} -> {decision:?}"
    );

    // And the predicted dead space is really reclaimable.
    let results = db.major_compact().expect("fjall supports major compaction");
    for r in &results {
        assert!(
            r.error.is_none(),
            "compaction of {} failed: {:?}",
            r.relation,
            r.error
        );
    }
    let reclaimed: u64 = results.iter().map(|r| r.bytes_reclaimed()).sum();

    // Judge on table bytes, not `disk_bytes()`: the latter includes write-ahead journals, which
    // compaction does not touch and which dominate a small database.
    let propvalues = results
        .iter()
        .find(|r| r.relation == "object_propvalues")
        .expect("object_propvalues is a relation");

    assert!(
        reclaimed > 0,
        "compaction should reclaim the superseded versions (journals+tables before={disk_before})"
    );
    // Down to live size, not merely smaller. A partial reclaim is the symptom of compacting
    // without first rotating the memtable to advance fjall's GC watermark, and `< before/2` is too
    // weak to tell the two apart — see the table on `Relations::major_compact_all`.
    let live_table_bytes = live_property_bytes(&db);
    assert!(
        propvalues.bytes_after < live_table_bytes * 2,
        "compaction should reclaim essentially all superseded versions, leaving about the live \
         size ({live_table_bytes}), but {} -> {} remains",
        propvalues.bytes_before,
        propvalues.bytes_after
    );

    // After compaction the same measurement should no longer call for another pass — otherwise the
    // automatic path would compact on every single checkpoint forever.
    let (live_after, stored_after) = measure(&db);
    let second = config.decide(live_after, stored_after);
    assert!(
        matches!(
            second,
            CompactionDecision::BelowThreshold { .. } | CompactionDecision::TooSmall { .. }
        ),
        "a just-compacted database should not immediately ask to be compacted again: \
         live={live_after} stored={stored_after} -> {second:?}"
    );
}

/// With moor's real configuration — a 512 MiB memtable — recently-written data sits unflushed, and
/// `major_compact()` alone rewrites nothing at all: fjall only compacts what is in tables, and only
/// discards versions below a GC watermark that is advanced from the memtable-rotation path.
/// `Relations::major_compact_all` therefore rotates first. Without that, this test measured every
/// relation at 0 bytes before and after, and `db_compact()` was a silent no-op.
#[test]
fn compaction_reclaims_under_the_default_large_memtable() {
    let dir = tempfile::tempdir().unwrap();
    // Deliberately the shipping default, not `flushing_config()`.
    let (db, _) = TxDB::try_open(Some(dir.path()), DatabaseConfig::default()).unwrap();
    let objects = populate(&db, 40);

    for pass in 1..=4u64 {
        let mut tx = db.new_world_state().unwrap();
        for (i, obj) in objects.iter().enumerate() {
            tx.update_property(
                &perms(),
                obj,
                Symbol::mk("payload"),
                &v_str(&big_value(5000 + pass * 100 + i as u64)),
            )
            .unwrap();
        }
        tx.commit().unwrap();
    }
    db.wait_for_persistence().unwrap();

    let results = db.major_compact().expect("fjall supports major compaction");
    let propvalues = results
        .iter()
        .find(|r| r.relation == "object_propvalues")
        .expect("object_propvalues is a relation");

    // The point: after compaction the property data is in tables, at about its live size. A
    // no-op would leave this at zero.
    let live = live_property_bytes(&db);
    assert!(
        propvalues.bytes_after > 0,
        "compaction should have flushed and rewritten the property tables, not skipped them"
    );
    assert!(
        propvalues.bytes_after < live * 2,
        "property tables should end up near live size ({live}), got {}",
        propvalues.bytes_after
    );
}

/// The data must survive compaction. `major_compact` rewrites every table; a bug there would be
/// silent and catastrophic, so read the values back.
#[test]
fn compaction_preserves_every_property_value() {
    let dir = tempfile::tempdir().unwrap();
    let (db, _) = TxDB::try_open(Some(dir.path()), flushing_config()).unwrap();
    let objects = populate(&db, 12);

    let mut tx = db.new_world_state().unwrap();
    for (i, obj) in objects.iter().enumerate() {
        tx.update_property(
            &perms(),
            obj,
            Symbol::mk("payload"),
            &v_str(&big_value(9000 + i as u64)),
        )
        .unwrap();
    }
    tx.commit().unwrap();
    db.wait_for_persistence().unwrap();

    let expected: Vec<_> = {
        let tx = db.new_world_state().unwrap();
        objects
            .iter()
            .map(|obj| {
                tx.retrieve_property(&perms(), obj, Symbol::mk("payload"))
                    .unwrap()
            })
            .collect()
    };

    db.major_compact().expect("fjall supports major compaction");

    let tx = db.new_world_state().unwrap();
    for (obj, want) in objects.iter().zip(expected.iter()) {
        let got = tx
            .retrieve_property(&perms(), obj, Symbol::mk("payload"))
            .unwrap();
        assert_eq!(
            &got, want,
            "property value for {obj} changed across compaction"
        );
    }
}
