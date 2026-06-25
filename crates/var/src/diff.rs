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

use crate::{
    Associative, Flyweight, List, Map, Symbol, Var, Variant, v_bool, v_int, v_list_iter, v_str,
};
use std::cmp::Ordering;

const DEFAULT_MAX_DEPTH: usize = 8;
const DEFAULT_MAX_CHANGES: usize = 128;
const DEFAULT_MAX_LCS_CELLS: usize = 16_384;

#[derive(Debug, Clone)]
pub struct ValueDiffOptions {
    pub max_depth: usize,
    pub max_changes: usize,
    pub max_lcs_cells: usize,
    pub include_values: bool,
}

impl Default for ValueDiffOptions {
    fn default() -> Self {
        Self {
            max_depth: DEFAULT_MAX_DEPTH,
            max_changes: DEFAULT_MAX_CHANGES,
            max_lcs_cells: DEFAULT_MAX_LCS_CELLS,
            include_values: false,
        }
    }
}

pub fn value_diff(left: &Var, right: &Var, options: &ValueDiffOptions) -> Var {
    DiffBuilder { options }.diff(left, right, 0)
}

pub fn value_diff3(base: &Var, local: &Var, incoming: &Var, options: &ValueDiffOptions) -> Var {
    if local == incoming {
        return map(vec![
            ("ok", v_bool(true)),
            ("kind", v_str("resolved")),
            ("conflict", v_bool(false)),
            ("resolution", v_str("same")),
            ("value", local.clone()),
            ("diff", value_diff(base, local, options)),
        ]);
    }

    if base == local {
        return map(vec![
            ("ok", v_bool(true)),
            ("kind", v_str("resolved")),
            ("conflict", v_bool(false)),
            ("resolution", v_str("incoming")),
            ("value", incoming.clone()),
            ("diff", value_diff(base, incoming, options)),
        ]);
    }

    if base == incoming {
        return map(vec![
            ("ok", v_bool(true)),
            ("kind", v_str("resolved")),
            ("conflict", v_bool(false)),
            ("resolution", v_str("local")),
            ("value", local.clone()),
            ("diff", value_diff(base, local, options)),
        ]);
    }

    map(vec![
        ("ok", v_bool(false)),
        ("kind", v_str("conflict")),
        ("conflict", v_bool(true)),
        ("resolution", v_str("manual")),
        ("local_diff", value_diff(base, local, options)),
        ("incoming_diff", value_diff(base, incoming, options)),
    ])
}

struct DiffBuilder<'a> {
    options: &'a ValueDiffOptions,
}

impl DiffBuilder<'_> {
    fn diff(&self, left: &Var, right: &Var, depth: usize) -> Var {
        if left == right {
            return unchanged();
        }

        if depth >= self.options.max_depth {
            return self.replace(left, right, true);
        }

        match (left.variant(), right.variant()) {
            (Variant::List(left), Variant::List(right)) => self.diff_list(left, right, depth),
            (Variant::Map(left), Variant::Map(right)) => self.diff_map(left, right, depth),
            (Variant::Flyweight(left), Variant::Flyweight(right)) => {
                self.diff_flyweight(left, right, depth)
            }
            _ => self.replace(left, right, false),
        }
    }

    fn replace(&self, left: &Var, right: &Var, truncated: bool) -> Var {
        let mut pairs = vec![
            ("equal", v_bool(false)),
            ("kind", v_str("replace")),
            ("old_type", type_name(left)),
            ("new_type", type_name(right)),
            ("truncated", v_bool(truncated)),
        ];
        if self.options.include_values && is_inline_value(left) && is_inline_value(right) {
            pairs.push(("old", left.clone()));
            pairs.push(("new", right.clone()));
        }
        map(pairs)
    }

    fn diff_list(&self, left: &List, right: &List, depth: usize) -> Var {
        let left_len = left.len();
        let right_len = right.len();
        let left_values = left.iter_ref().collect::<Vec<_>>();
        let right_values = right.iter_ref().collect::<Vec<_>>();

        let mut prefix = 0;
        while prefix < left_len && prefix < right_len && left_values[prefix] == right_values[prefix]
        {
            prefix += 1;
        }

        let mut suffix = 0;
        while suffix + prefix < left_len
            && suffix + prefix < right_len
            && left_values[left_len - 1 - suffix] == right_values[right_len - 1 - suffix]
        {
            suffix += 1;
        }

        let left_mid = &left_values[prefix..left_len - suffix];
        let right_mid = &right_values[prefix..right_len - suffix];

        let (changes, truncated) = if left_mid.len() == right_mid.len() {
            self.diff_equal_len_list_middle(left_mid, right_mid, prefix, depth)
        } else if left_mid.len() * right_mid.len() <= self.options.max_lcs_cells {
            self.diff_lcs_list_middle(left_mid, right_mid, prefix, depth)
        } else {
            (
                vec![map(vec![
                    ("op", v_str("replace_range")),
                    ("old_start", v_int((prefix + 1) as i64)),
                    ("old_len", v_int(left_mid.len() as i64)),
                    ("new_start", v_int((prefix + 1) as i64)),
                    ("new_len", v_int(right_mid.len() as i64)),
                ])],
                false,
            )
        };

        map(vec![
            ("equal", v_bool(false)),
            ("kind", v_str("list")),
            ("old_len", v_int(left_len as i64)),
            ("new_len", v_int(right_len as i64)),
            ("truncated", v_bool(truncated)),
            ("changes", v_list_iter(changes)),
        ])
    }

    fn diff_equal_len_list_middle(
        &self,
        left: &[&Var],
        right: &[&Var],
        offset: usize,
        depth: usize,
    ) -> (Vec<Var>, bool) {
        let mut changes = Vec::new();
        let mut truncated = false;
        for (idx, (left, right)) in left.iter().zip(right.iter()).enumerate() {
            if left == right {
                continue;
            }
            if changes.len() >= self.options.max_changes {
                truncated = true;
                break;
            }
            changes.push(map(vec![
                ("op", v_str("change")),
                ("index", v_int((offset + idx + 1) as i64)),
                ("diff", self.diff(left, right, depth + 1)),
            ]));
        }
        (changes, truncated)
    }

    fn diff_lcs_list_middle(
        &self,
        left: &[&Var],
        right: &[&Var],
        offset: usize,
        depth: usize,
    ) -> (Vec<Var>, bool) {
        let table = lcs_table(left, right);
        let mut changes = Vec::new();
        let mut truncated = false;
        let mut i = 0;
        let mut j = 0;

        while i < left.len() || j < right.len() {
            if changes.len() >= self.options.max_changes {
                truncated = true;
                break;
            }

            if i < left.len() && j < right.len() && left[i] == right[j] {
                i += 1;
                j += 1;
            } else if j < right.len() && (i == left.len() || table[i][j + 1] >= table[i + 1][j]) {
                changes.push(map(vec![
                    ("op", v_str("add")),
                    ("index", v_int((offset + j + 1) as i64)),
                    ("value", maybe_value(right[j], self.options.include_values)),
                ]));
                j += 1;
            } else if i < left.len() {
                changes.push(map(vec![
                    ("op", v_str("remove")),
                    ("index", v_int((offset + i + 1) as i64)),
                    ("value", maybe_value(left[i], self.options.include_values)),
                ]));
                i += 1;
            }
        }

        if !truncated {
            changes = compact_remove_add_pairs(changes, self, depth);
        }
        (changes, truncated)
    }

    fn diff_map(&self, left: &Map, right: &Map, depth: usize) -> Var {
        let mut changes = Vec::new();
        let mut truncated = false;
        let mut left_iter = left.iter_ref().peekable();
        let mut right_iter = right.iter_ref().peekable();

        while left_iter.peek().is_some() || right_iter.peek().is_some() {
            if changes.len() >= self.options.max_changes {
                truncated = true;
                break;
            }

            match (left_iter.peek(), right_iter.peek()) {
                (Some((left_key, left_value)), Some((right_key, right_value))) => {
                    match left_key.cmp(right_key) {
                        Ordering::Equal => {
                            if left_value != right_value {
                                changes.push(map(vec![
                                    ("op", v_str("change")),
                                    ("key", (*left_key).clone()),
                                    ("diff", self.diff(left_value, right_value, depth + 1)),
                                ]));
                            }
                            left_iter.next();
                            right_iter.next();
                        }
                        Ordering::Less => {
                            changes.push(map(vec![
                                ("op", v_str("remove")),
                                ("key", (*left_key).clone()),
                                (
                                    "value",
                                    maybe_value(left_value, self.options.include_values),
                                ),
                            ]));
                            left_iter.next();
                        }
                        Ordering::Greater => {
                            changes.push(map(vec![
                                ("op", v_str("add")),
                                ("key", (*right_key).clone()),
                                (
                                    "value",
                                    maybe_value(right_value, self.options.include_values),
                                ),
                            ]));
                            right_iter.next();
                        }
                    }
                }
                (Some((left_key, left_value)), None) => {
                    changes.push(map(vec![
                        ("op", v_str("remove")),
                        ("key", (*left_key).clone()),
                        (
                            "value",
                            maybe_value(left_value, self.options.include_values),
                        ),
                    ]));
                    left_iter.next();
                }
                (None, Some((right_key, right_value))) => {
                    changes.push(map(vec![
                        ("op", v_str("add")),
                        ("key", (*right_key).clone()),
                        (
                            "value",
                            maybe_value(right_value, self.options.include_values),
                        ),
                    ]));
                    right_iter.next();
                }
                (None, None) => break,
            }
        }

        map(vec![
            ("equal", v_bool(false)),
            ("kind", v_str("map")),
            ("old_len", v_int(left.len() as i64)),
            ("new_len", v_int(right.len() as i64)),
            ("truncated", v_bool(truncated)),
            ("changes", v_list_iter(changes)),
        ])
    }

    fn diff_flyweight(&self, left: &Flyweight, right: &Flyweight, depth: usize) -> Var {
        let mut changes = Vec::new();
        let mut truncated = false;

        if left.delegate() != right.delegate() {
            changes.push(map(vec![
                ("op", v_str("change")),
                ("field", v_str("delegate")),
                ("old", Var::mk_object(*left.delegate())),
                ("new", Var::mk_object(*right.delegate())),
            ]));
        }

        let (slot_changes, slots_truncated) =
            self.diff_slots(left.slots_storage(), right.slots_storage(), depth);
        truncated |= slots_truncated;
        if !slot_changes.is_empty() {
            changes.push(map(vec![
                ("op", v_str("change")),
                ("field", v_str("slots")),
                ("changes", v_list_iter(slot_changes)),
            ]));
        }

        if left.contents() != right.contents() {
            let left_contents = Var::from_list(left.contents().clone());
            let right_contents = Var::from_list(right.contents().clone());
            changes.push(map(vec![
                ("op", v_str("change")),
                ("field", v_str("contents")),
                (
                    "diff",
                    self.diff(&left_contents, &right_contents, depth + 1),
                ),
            ]));
        }

        if changes.len() > self.options.max_changes {
            changes.truncate(self.options.max_changes);
            truncated = true;
        }

        map(vec![
            ("equal", v_bool(false)),
            ("kind", v_str("flyweight")),
            ("truncated", v_bool(truncated)),
            ("changes", v_list_iter(changes)),
        ])
    }

    fn diff_slots(
        &self,
        left: &[(Symbol, Var)],
        right: &[(Symbol, Var)],
        depth: usize,
    ) -> (Vec<Var>, bool) {
        let mut changes = Vec::new();
        let mut truncated = false;
        let mut i = 0;
        let mut j = 0;

        while i < left.len() || j < right.len() {
            if changes.len() >= self.options.max_changes {
                truncated = true;
                break;
            }

            match (left.get(i), right.get(j)) {
                (Some((left_key, left_value)), Some((right_key, right_value))) => {
                    match left_key.cmp(right_key) {
                        Ordering::Equal => {
                            if left_value != right_value {
                                changes.push(map(vec![
                                    ("op", v_str("change")),
                                    ("key", Var::mk_symbol(*left_key)),
                                    ("diff", self.diff(left_value, right_value, depth + 1)),
                                ]));
                            }
                            i += 1;
                            j += 1;
                        }
                        Ordering::Less => {
                            changes.push(map(vec![
                                ("op", v_str("remove")),
                                ("key", Var::mk_symbol(*left_key)),
                                (
                                    "value",
                                    maybe_value(left_value, self.options.include_values),
                                ),
                            ]));
                            i += 1;
                        }
                        Ordering::Greater => {
                            changes.push(map(vec![
                                ("op", v_str("add")),
                                ("key", Var::mk_symbol(*right_key)),
                                (
                                    "value",
                                    maybe_value(right_value, self.options.include_values),
                                ),
                            ]));
                            j += 1;
                        }
                    }
                }
                (Some((left_key, left_value)), None) => {
                    changes.push(map(vec![
                        ("op", v_str("remove")),
                        ("key", Var::mk_symbol(*left_key)),
                        (
                            "value",
                            maybe_value(left_value, self.options.include_values),
                        ),
                    ]));
                    i += 1;
                }
                (None, Some((right_key, right_value))) => {
                    changes.push(map(vec![
                        ("op", v_str("add")),
                        ("key", Var::mk_symbol(*right_key)),
                        (
                            "value",
                            maybe_value(right_value, self.options.include_values),
                        ),
                    ]));
                    j += 1;
                }
                (None, None) => break,
            }
        }

        (changes, truncated)
    }
}

fn unchanged() -> Var {
    map(vec![
        ("equal", v_bool(true)),
        ("kind", v_str("unchanged")),
        ("truncated", v_bool(false)),
        ("changes", Var::mk_empty_list()),
    ])
}

fn type_name(value: &Var) -> Var {
    v_str(value.type_code().to_literal())
}

fn is_inline_value(value: &Var) -> bool {
    matches!(
        value.variant(),
        Variant::None
            | Variant::Bool(_)
            | Variant::Int(_)
            | Variant::Float(_)
            | Variant::Obj(_)
            | Variant::Sym(_)
            | Variant::Err(_)
    )
}

fn maybe_value(value: &Var, include_values: bool) -> Var {
    if include_values && is_inline_value(value) {
        return value.clone();
    }
    map(vec![("type", type_name(value))])
}

fn map(pairs: Vec<(&'static str, Var)>) -> Var {
    let pairs = pairs
        .into_iter()
        .map(|(key, value)| (v_str(key), value))
        .collect::<Vec<_>>();
    Var::mk_map(&pairs)
}

fn lcs_table(left: &[&Var], right: &[&Var]) -> Vec<Vec<usize>> {
    let mut table = vec![vec![0; right.len() + 1]; left.len() + 1];
    for i in (0..left.len()).rev() {
        for j in (0..right.len()).rev() {
            table[i][j] = if left[i] == right[j] {
                table[i + 1][j + 1] + 1
            } else {
                table[i + 1][j].max(table[i][j + 1])
            };
        }
    }
    table
}

fn compact_remove_add_pairs(
    changes: Vec<Var>,
    builder: &DiffBuilder<'_>,
    depth: usize,
) -> Vec<Var> {
    let mut compacted = Vec::with_capacity(changes.len());
    let mut iter = changes.into_iter().peekable();

    while let Some(change) = iter.next() {
        let Some(next) = iter.peek() else {
            compacted.push(change);
            break;
        };

        if change
            .get(&v_str("op"), crate::IndexMode::ZeroBased)
            .ok()
            .as_ref()
            == Some(&v_str("remove"))
            && next
                .get(&v_str("op"), crate::IndexMode::ZeroBased)
                .ok()
                .as_ref()
                == Some(&v_str("add"))
        {
            let old_value = change
                .get(&v_str("value"), crate::IndexMode::ZeroBased)
                .ok();
            let new_value = next.get(&v_str("value"), crate::IndexMode::ZeroBased).ok();
            let old_index = change
                .get(&v_str("index"), crate::IndexMode::ZeroBased)
                .ok();
            if let (Some(old), Some(new), Some(index)) = (old_value, new_value, old_index)
                && builder.options.include_values
                && old != new
            {
                let next = iter.next().unwrap();
                let new_value = next
                    .get(&v_str("value"), crate::IndexMode::ZeroBased)
                    .unwrap();
                compacted.push(map(vec![
                    ("op", v_str("change")),
                    ("index", index),
                    ("diff", builder.diff(&old, &new_value, depth + 1)),
                ]));
                continue;
            }
        }

        compacted.push(change);
    }

    compacted
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{v_int, v_map, v_str};

    #[test]
    fn equal_values_have_no_changes() {
        let diff = value_diff(&v_int(1), &v_int(1), &ValueDiffOptions::default());
        assert_eq!(
            diff.get(&v_str("equal"), crate::IndexMode::ZeroBased)
                .unwrap(),
            v_bool(true)
        );
    }

    #[test]
    fn map_diff_is_deterministic() {
        let left = v_map(&[(v_str("b"), v_int(2)), (v_str("a"), v_int(1))]);
        let right = v_map(&[(v_str("a"), v_int(10)), (v_str("c"), v_int(3))]);
        let diff_a = value_diff(&left, &right, &ValueDiffOptions::default());
        let diff_b = value_diff(&left, &right, &ValueDiffOptions::default());
        assert_eq!(diff_a, diff_b);
    }

    #[test]
    fn list_diff_reports_insertions() {
        let left = Var::mk_list(&[v_int(1), v_int(3)]);
        let right = Var::mk_list(&[v_int(1), v_int(2), v_int(3)]);
        let diff = value_diff(&left, &right, &ValueDiffOptions::default());
        let changes = diff
            .get(&v_str("changes"), crate::IndexMode::ZeroBased)
            .unwrap();
        assert_eq!(changes.len().unwrap(), 1);
    }

    #[test]
    fn diff3_selects_incoming_when_local_unchanged() {
        let base = v_int(1);
        let local = v_int(1);
        let incoming = v_int(2);
        let diff = value_diff3(&base, &local, &incoming, &ValueDiffOptions::default());
        assert_eq!(
            diff.get(&v_str("resolution"), crate::IndexMode::ZeroBased)
                .unwrap(),
            v_str("incoming")
        );
    }
}
