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

//! Builtin fingerprints of programs stored before version 7.
//!
//! Those fingerprints hash each used builtin's id, name, declared argument counts and
//! types, and flags. Declarations have since changed for builtins whose stored ids and
//! meaning did not, so an old program is checked against the declarations it was built
//! with: the frozen table, then each set of earlier declarations in turn.

use std::collections::HashMap;
use std::sync::LazyLock;

use super::{BUILTINS, BuiltinId, fnv::Fnv, legacy_table::FROZEN_TABLE};

#[derive(Clone, Copy)]
pub(super) enum LegacyArgType {
    Any,
    AnyNum,
    /// A `VarType` code, as hashed.
    Typed(u8),
}

/// An argument count, bounded or unbounded.
#[derive(Clone, Copy)]
pub(super) enum LegacyCount {
    Q(usize),
    U,
}

/// One builtin as a version 6 fingerprint saw it.
#[derive(Clone, Copy)]
pub(super) struct LegacyDeclaration {
    pub(super) id: u16,
    pub(super) name: &'static str,
    pub(super) min: LegacyCount,
    pub(super) max: LegacyCount,
    pub(super) types: &'static [LegacyArgType],
    pub(super) implemented: bool,
    pub(super) exposed: bool,
}

/// An earlier declaration of a builtin: its argument counts and types.
struct EarlierDeclaration {
    name: &'static str,
    min: LegacyCount,
    max: LegacyCount,
    types: &'static [LegacyArgType],
}

use LegacyArgType::{Any, AnyNum, Typed};
use LegacyCount::Q;

/// Declarations replaced since database format 3.0.0, newest change first. Programs stored
/// before a change were fingerprinted with the declarations of that change and of every
/// later one, so each step back adds its declarations to those already applied.
const EARLIER_DECLARATIONS: &[&[EarlierDeclaration]] = &[
    // Before 772f14ffa (2026-10-24).
    &[EarlierDeclaration {
        name: "emit_data",
        min: Q(4),
        max: Q(4),
        types: &[Typed(1), Typed(16), Typed(16), Any],
    }],
    // Before 9052ddc4b (2026-10-14).
    &[
        EarlierDeclaration {
            name: "complex_matches",
            min: Q(2),
            max: Q(3),
            types: &[Typed(2), Typed(4), Typed(0)],
        },
        EarlierDeclaration {
            name: "parse_command",
            min: Q(2),
            max: Q(3),
            types: &[Typed(2), Typed(4), Typed(14)],
        },
    ],
    // Before de56f7063 (2026-10-09).
    &[
        EarlierDeclaration {
            name: "load_object",
            min: Q(1),
            max: Q(3),
            types: &[Typed(4), Typed(1), Typed(10)],
        },
        EarlierDeclaration {
            name: "reload_object",
            min: Q(1),
            max: Q(3),
            types: &[Typed(4), Typed(10), Typed(1)],
        },
    ],
];

static FROZEN_BY_ID: LazyLock<HashMap<u16, LegacyDeclaration>> =
    LazyLock::new(|| FROZEN_TABLE.iter().map(|d| (d.id, *d)).collect());

/// Whether `expected` is a version 6 fingerprint of a program calling `ids`, and each of
/// those ids still names the same builtin.
pub fn legacy_builtin_signature_matches<I>(ids: I, expected: u64) -> bool
where
    I: IntoIterator<Item = BuiltinId>,
{
    let mut ids: Vec<BuiltinId> = ids.into_iter().collect();
    ids.sort_by_key(|id| id.0);
    ids.dedup();
    let mut declarations = Vec::with_capacity(ids.len());
    for id in &ids {
        let Some(declaration) = FROZEN_BY_ID.get(&id.0) else {
            return false;
        };
        let still_named = BUILTINS
            .name_of(*id)
            .is_some_and(|name| name.as_str() == declaration.name);
        if !still_named {
            return false;
        }
        declarations.push(*declaration);
    }
    if legacy_signature(&declarations) == expected {
        return true;
    }
    for change in EARLIER_DECLARATIONS {
        let mut changed = false;
        for earlier in *change {
            for declaration in declarations.iter_mut().filter(|d| d.name == earlier.name) {
                declaration.min = earlier.min;
                declaration.max = earlier.max;
                declaration.types = earlier.types;
                changed = true;
            }
        }
        if changed && legacy_signature(&declarations) == expected {
            return true;
        }
    }
    false
}

/// The version 6 fingerprint, over declarations sorted by id.
fn legacy_signature(declarations: &[LegacyDeclaration]) -> u64 {
    let mut hash = Fnv::new();
    for declaration in declarations {
        hash.u16(declaration.id);
        hash.str(declaration.name);
        hash.str(&format!("bf_{}", declaration.name));
        for count in [declaration.min, declaration.max] {
            match count {
                LegacyCount::Q(value) => {
                    hash.u8(0);
                    hash.u64(value as u64);
                }
                LegacyCount::U => hash.u8(1),
            }
        }
        hash.u64(declaration.types.len() as u64);
        for arg_type in declaration.types {
            match arg_type {
                Any => hash.u8(0),
                AnyNum => hash.u8(1),
                Typed(code) => {
                    hash.u8(2);
                    hash.u8(*code);
                }
            }
        }
        hash.u8(declaration.implemented as u8);
        hash.u8(declaration.exposed as u8);
    }
    hash.finish()
}
