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

use fjall::KeyspaceCreateOptions;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DatabaseConfig {
    /// Per-table configurations
    pub object_location: Option<TableConfig>,
    pub object_contents: Option<TableConfig>,
    pub object_flags: Option<TableConfig>,
    pub object_parent: Option<TableConfig>,
    pub object_children: Option<TableConfig>,
    pub object_owner: Option<TableConfig>,
    pub object_name: Option<TableConfig>,
    pub object_verbdefs: Option<TableConfig>,
    pub object_verbs: Option<TableConfig>,
    pub object_propdefs: Option<TableConfig>,
    pub object_propvalues: Option<TableConfig>,
    pub object_propflags: Option<TableConfig>,
    pub entity_metadata: Option<TableConfig>,
    pub object_last_move: Option<TableConfig>,
    pub anonymous_object_metadata: Option<TableConfig>,

    /// When to major-compact automatically after a checkpoint.
    #[serde(default)]
    pub auto_compaction: AutoCompactionConfig,
}

/// Policy for automatic major compaction.
///
/// fjall does run a background `Leveled` compaction, and under continuous write churn it is
/// entirely sufficient — it holds amplification near the ~1.1x it advertises, and moor should not
/// interfere. The gap it does not cover is a keyspace that has *settled*.
///
/// Leveled compaction picks work by comparing a level's size against its target size; dead space is
/// not an input to that decision (lsm-tree carries a `TODO(weak-tombstone-rewrite)` about exactly
/// this). Dedup is therefore a byproduct of merges triggered for size reasons. With the default
/// 64 MiB table target, L1's target is 256 MiB — so a tree sitting below its level targets scores
/// under 1.0, `choose` returns `DoNothing`, and superseded data is never revisited however much of
/// it there is. Supersede a few large values and stop writing, and the bytes stay put.
///
/// That is the reported case: a 575 MiB table, untouched, holding data a recycle had replaced and a
/// secret that was meant to be gone. `crates/db/tests/background_compaction_limits.rs` measures both
/// halves — 26.4x amplification left in place when settled, 1.08x when churning.
///
/// A checkpoint is the moment to check, because it has just read every live row and so knows what
/// the data should weigh.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutoCompactionConfig {
    /// Whether to consider compacting after a checkpoint completes.
    pub after_checkpoint: bool,
    /// Compact only when stored property rows exceed live property rows by at least this factor.
    ///
    /// An LSM tree always holds somewhat more than its live rows, so this must be comfortably above
    /// 1.0 or every checkpoint would trigger a full rewrite. 2.0 means "half the rows on disk are
    /// superseded" — the situation the investigation found, where 575 MB of a 755 MB keyspace was a
    /// single superseded table.
    ///
    /// Rows rather than bytes: fjall compresses deeper levels with lz4, so a bytes-based ratio
    /// tracks how compressible the values are as much as how much dead space there is. Measured on
    /// a fixture at identical redundancy, the byte ratio read 0.04 for repetitive values and 7.03
    /// for random ones, while the row ratio correctly read ~7 for both.
    pub min_amplification: f64,
    /// Never compact a database with fewer stored property rows than this.
    ///
    /// Amplification ratios are noisy on a nearly-empty database, and rewriting one is pointless.
    pub min_stored_rows: u64,
}

impl Default for AutoCompactionConfig {
    fn default() -> Self {
        Self {
            after_checkpoint: true,
            min_amplification: 2.0,
            // Roughly a database with real content in it; the motivating case had ~90k.
            min_stored_rows: 50_000,
        }
    }
}

/// Why an automatic compaction was or was not run, so the decision is greppable in a log rather
/// than being a silent non-event.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CompactionDecision {
    /// Amplification is past the threshold on a database large enough to be worth rewriting.
    Compact { amplification_pct: u64 },
    /// Turned off by configuration.
    Disabled,
    /// The database is too small for the ratio to mean anything.
    TooSmall { stored_rows: u64, min_rows: u64 },
    /// Not enough dead space to justify the rewrite.
    BelowThreshold { amplification_pct: u64 },
    /// The live count is unknown or nonsensical, so no ratio can be formed.
    Unmeasurable,
}

impl AutoCompactionConfig {
    /// Decide whether to compact, given what the checkpoint just measured.
    ///
    /// `live_rows` is the number of live property rows the scan actually read; `stored_rows` is
    /// what the engine holds for the same keyspaces, superseded versions and tombstones included.
    /// The ratio is version amplification.
    ///
    /// Rows, not bytes. A bytes ratio was the obvious formulation and is wrong: fjall compresses
    /// deeper levels with lz4, so `disk_space()` is post-compression while a scan measures logical
    /// size, and the quotient of the two is dominated by compressibility. It also includes
    /// write-ahead journals. Rows over rows is a consistent unit.
    ///
    /// Amplification is reported in percent to keep the decision loggable and comparable without
    /// float formatting.
    pub fn decide(&self, live_rows: u64, stored_rows: u64) -> CompactionDecision {
        if !self.after_checkpoint {
            return CompactionDecision::Disabled;
        }
        if stored_rows < self.min_stored_rows {
            return CompactionDecision::TooSmall {
                stored_rows,
                min_rows: self.min_stored_rows,
            };
        }
        // A zero or absurd live measurement means the estimate is broken, not that everything on
        // disk is garbage. Refuse rather than trigger a full rewrite on bad arithmetic.
        if live_rows == 0 || live_rows > stored_rows {
            return CompactionDecision::Unmeasurable;
        }

        let amplification = stored_rows as f64 / live_rows as f64;
        #[expect(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "amplification is positive and bounded by stored_rows/live_rows"
        )]
        let amplification_pct = (amplification * 100.0) as u64;

        if amplification >= self.min_amplification {
            CompactionDecision::Compact { amplification_pct }
        } else {
            CompactionDecision::BelowThreshold { amplification_pct }
        }
    }
}

const LARGE_MEMTABLE_SIZE: u64 = 512 * 1024 * 1024; // 512 MiB

impl Default for DatabaseConfig {
    fn default() -> Self {
        Self {
            object_location: None,
            object_contents: None,
            object_flags: None,
            object_parent: None,
            object_children: None,
            object_owner: None,
            object_name: None,
            object_verbdefs: None,
            // Verbs and propvalues are hot tables under write pressure - larger memtables
            // reduce L0 segment accumulation and fjall backpressure stalls
            object_verbs: Some(TableConfig {
                max_memtable_size: Some(LARGE_MEMTABLE_SIZE),
            }),
            object_propdefs: None,
            object_propvalues: Some(TableConfig {
                max_memtable_size: Some(LARGE_MEMTABLE_SIZE),
            }),
            object_propflags: None,
            entity_metadata: None,
            object_last_move: None,
            anonymous_object_metadata: None,
            auto_compaction: AutoCompactionConfig::default(),
        }
    }
}

/// Per-table configuration.
#[derive(Clone, Default, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TableConfig {
    /// Various fjall keyspace creation options.
    /// Refer to the fjall documentation for more information.
    pub max_memtable_size: Option<u64>,
}

impl TableConfig {
    pub fn keyspace_options(&self) -> KeyspaceCreateOptions {
        let mut opts = KeyspaceCreateOptions::default();
        if let Some(max_memtable_size) = self.max_memtable_size {
            opts = opts.max_memtable_size(max_memtable_size);
        }
        opts
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> AutoCompactionConfig {
        AutoCompactionConfig::default()
    }

    /// The shape of the case that motivated this: most of what is stored is superseded.
    #[test]
    fn heavy_amplification_triggers_compaction() {
        let decision = config().decide(94_000, 566_000);
        assert_eq!(
            decision,
            CompactionDecision::Compact {
                amplification_pct: 602
            }
        );
    }

    /// A healthy tree must not be rewritten after every single checkpoint.
    #[test]
    fn ordinary_overhead_does_not_trigger_compaction() {
        // 1.25x is normal for an LSM tree and must be left alone.
        let decision = config().decide(400_000, 500_000);
        assert_eq!(
            decision,
            CompactionDecision::BelowThreshold {
                amplification_pct: 125
            }
        );
    }

    #[test]
    fn threshold_is_inclusive_at_the_configured_ratio() {
        // Exactly 2.0 should compact, so the boundary is not a silent no-op.
        assert_eq!(
            config().decide(100_000, 200_000),
            CompactionDecision::Compact {
                amplification_pct: 200
            }
        );
    }

    /// Ratios on a small database are noise; a fresh server should never be compacting.
    #[test]
    fn small_databases_are_left_alone_however_bad_the_ratio() {
        let cfg = config();
        let stored = 8_000; // 8x amplified, but trivially small
        assert_eq!(
            cfg.decide(1_000, stored),
            CompactionDecision::TooSmall {
                stored_rows: stored,
                min_rows: cfg.min_stored_rows,
            }
        );
    }

    #[test]
    fn disabled_config_never_compacts() {
        let cfg = AutoCompactionConfig {
            after_checkpoint: false,
            ..config()
        };
        assert_eq!(
            cfg.decide(100_000, 10_000_000),
            CompactionDecision::Disabled
        );
    }

    /// A broken live measurement must not be read as "everything stored is garbage".
    #[test]
    fn nonsensical_measurements_are_refused_rather_than_acted_on() {
        let cfg = config();
        assert_eq!(cfg.decide(0, 400_000), CompactionDecision::Unmeasurable);
        // More live rows than stored rows means the estimate is wrong.
        assert_eq!(
            cfg.decide(800_000, 400_000),
            CompactionDecision::Unmeasurable
        );
    }
}
