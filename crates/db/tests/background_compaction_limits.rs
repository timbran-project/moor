//! Where fjall's background compaction reclaims dead space, and where it does not.
//!
//! These tests pin down *why* moor needs an explicit `major_compact()` when fjall already runs a
//! default `Leveled` strategy in the background. The honest answer is that background compaction
//! is usually sufficient, and the first version of this probe was wrong to suggest otherwise.
//!
//! Leveled compaction chooses work by comparing `level_size` against `level_target_size`; dead
//! space is not an input to that decision at all. lsm-tree says so itself, in `leveled::choose`:
//!
//! ```text
//! TODO(weak-tombstone-rewrite): incorporate `Table::weak_tombstone_count` and
//! `Table::weak_tombstone_reclaimable` when computing level scores so rewrite
//! decisions can prioritize tables that would free the most reclaimable values.
//! ```
//!
//! So dedup happens as a *byproduct* of merges that were triggered for size reasons. Under
//! continuous write churn that is plenty: L0 keeps crossing `l0_threshold` (4), merges keep
//! firing, and amplification stays near the ~1.1x the strategy advertises. That case is the
//! control test below, and it needs no help.
//!
//! The gap is a keyspace that has *settled*. With the default 64 MiB `target_size` and an
//! `l0_threshold` of 4, L1's target is 256 MiB and L2's is 2.56 GiB. A tree sitting below its
//! level targets scores under 1.0 and `choose` returns `DoNothing` — no matter how much of it is
//! superseded. Supersede a few large values and stop writing, and nothing ever revisits them.
//! That is the reported scenario exactly: a 575 MiB table, untouched, holding data that a recycle
//! had already replaced, and a secret that was supposed to be gone.

use fjall::{Database, KeyspaceCreateOptions};

fn value(seed: u64, len: usize) -> Vec<u8> {
    // Incompressible, so on-disk size tracks logical size.
    let mut s = seed.wrapping_mul(0x9E37_79B9_7F4A_7C15) | 1;
    (0..len)
        .map(|_| {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            b'!' + (s % 90) as u8
        })
        .collect()
}

fn live_logical(ks: &fjall::Keyspace) -> u64 {
    ks.iter()
        .map(|e| {
            let (k, v) = e.into_inner().unwrap();
            (k.len() + v.len()) as u64
        })
        .sum()
}

fn settle(ks: &fjall::Keyspace) {
    settle_for(ks, 40);
}

fn settle_for(ks: &fjall::Keyspace, ticks: u32) {
    ks.rotate_memtable_and_wait().unwrap();
    for _ in 0..ticks {
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
}

/// The motivating scenario, in miniature: a database that has settled, then a handful of large
/// values are superseded — exactly the `#340` recycle. Nothing else is written afterwards, so
/// there is no ongoing churn to drag a compaction along.
#[test]
fn a_settled_keyspace_does_not_reclaim_a_large_supersede_on_its_own() {
    let dir = tempfile::tempdir().unwrap();
    let db = Database::builder(dir.path()).open().unwrap();

    // Deliberately small target sizes, so that "settled below the level target" is reachable in a
    // test. This makes reclamation *easier* to trigger than moor's real config, not harder:
    // moor's effective L1 target is 256 MiB.
    let ks = db
        .keyspace("props", || {
            KeyspaceCreateOptions::default().max_memtable_size(256 * 1024)
        })
        .unwrap();

    // A small stable population of ordinary rows...
    for k in 0..200u64 {
        ks.insert(k.to_be_bytes(), value(k, 1024)).unwrap();
    }
    // ...plus a few big ones, standing in for #340's two 47 MB properties.
    for k in 900..910u64 {
        ks.insert(k.to_be_bytes(), value(k, 512 * 1024)).unwrap();
    }
    settle(&ks);

    let before = ks.disk_space();

    // Now supersede the big rows, as recycling an object does. This is the only write.
    for k in 900..910u64 {
        ks.remove(k.to_be_bytes()).unwrap();
    }
    settle(&ks);

    // Is it merely slow rather than uninterested? Rotate repeatedly — that is the path which
    // advances the GC watermark — and give the worker several more seconds. Checked once at 30s of
    // extra waiting with byte-identical results (5453757), so this is a structural refusal to
    // compact, not a race being read too early.
    for _ in 0..4 {
        settle_for(&ks, 20);
    }

    let live = live_logical(&ks);
    let after_background = ks.disk_space();
    ks.major_compact().unwrap();
    let after_major = ks.disk_space();

    println!(
        "settled: before={before} live={live} after_background={after_background} \
         after_major={after_major}"
    );
    println!(
        "background amplification = {:.2}x, post-major = {:.2}x",
        after_background as f64 / live.max(1) as f64,
        after_major as f64 / live.max(1) as f64
    );

    assert!(
        after_background > live * 2,
        "background compaction reclaimed the supersede on its own (amplification {:.2}x) — \
         major_compact() would be unnecessary for this case",
        after_background as f64 / live.max(1) as f64
    );
    assert!(
        after_major < after_background / 2,
        "major_compact() did not reclaim what background compaction left \
         ({after_background} -> {after_major})"
    );
}

/// Control: with continuous churn, L0 fills past `l0_threshold` repeatedly and the resulting
/// merges dedup as a byproduct. This is the case where background compaction is sufficient, and
/// it is why the naive version of this probe was misleading.
#[test]
fn continuous_churn_is_reclaimed_by_background_compaction_alone() {
    let dir = tempfile::tempdir().unwrap();
    let db = Database::builder(dir.path()).open().unwrap();
    let ks = db
        .keyspace("props", || {
            KeyspaceCreateOptions::default().max_memtable_size(1024 * 1024)
        })
        .unwrap();

    for round in 0..6u64 {
        for k in 0..2000u64 {
            ks.insert(k.to_be_bytes(), value(round * 1_000_000 + k, 4096))
                .unwrap();
        }
    }
    settle(&ks);

    let live = live_logical(&ks);
    let after_background = ks.disk_space();
    println!(
        "churn: live={live} after_background={after_background} byte-amplification={:.2}x",
        after_background as f64 / live as f64
    );

    // The row ratio is what actually drives the automatic decision, so it is the number that must
    // stay below the default `min_amplification` of 2.0 for a healthy database. Otherwise moor
    // would force a blocking full rewrite after every checkpoint on a database that background
    // compaction is already keeping in good shape.
    let live_rows = ks.iter().count() as u64;
    let stored_rows = ks.approximate_len() as u64;
    let row_amplification = stored_rows as f64 / live_rows as f64;
    println!(
        "churn: live_rows={live_rows} stored_rows={stored_rows} \
         row-amplification={row_amplification:.2}x"
    );

    assert!(
        row_amplification < 2.0,
        "a healthy, continuously-churning keyspace reads {row_amplification:.2}x in row terms, \
         at or above the default min_amplification of 2.0 — the automatic trigger would fire on \
         databases that need no help"
    );
}
