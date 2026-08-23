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

//! Builtin functions for map operations and manipulation.

use crate::vm::builtins::{BfCallState, BfErr, BfRet, BuiltinFunction};
use moor_compiler::offset_for_builtin;
use moor_var::{
    Associative, E_ARGS, E_RANGE, E_TYPE, IndexMode, List, Map, Var, Variant, v_list, v_map,
};

fn merge_maps(left: &Var, right: &Map) -> Result<Var, BfErr> {
    let mut result = left.clone();
    for (key, value) in right.iter_ref() {
        result = result
            .set_owned(key, value, IndexMode::ZeroBased)
            .map_err(BfErr::ErrValue)?;
    }
    Ok(result)
}

fn intersect_maps(left: &Map, right: &Map) -> Result<Var, BfErr> {
    let mut pairs = Vec::with_capacity(left.len().min(right.len()));
    for (key, value) in left.iter_ref() {
        if right.contains_key(key, false).map_err(BfErr::ErrValue)? {
            pairs.push((key.clone(), value.clone()));
        }
    }
    Ok(v_map(&pairs))
}

fn remove_map_keys(left: &Var, keys: &Var) -> Result<Var, BfErr> {
    let mut result = left.clone();

    if let Some(keys) = keys.as_list() {
        for key in keys.iter_ref() {
            if matches!(key.variant(), Variant::Map(_) | Variant::List(_)) {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("mapdifference keys must be scalar values"),
                ));
            }
            (result, _) = result.remove_owned(key, false).map_err(BfErr::ErrValue)?;
        }
        return Ok(result);
    }

    if let Some(keys) = keys.as_map() {
        for (key, _) in keys.iter_ref() {
            (result, _) = result.remove_owned(key, false).map_err(BfErr::ErrValue)?;
        }
        return Ok(result);
    }

    Err(BfErr::ErrValue(
        E_TYPE.msg("mapdifference second argument must be a list or map"),
    ))
}

fn map_contains(left: &Map, wanted: &Map, default: Option<&Var>) -> Result<bool, BfErr> {
    for (key, wanted_value) in wanted.iter_ref() {
        let present = left.contains_key(key, false).map_err(BfErr::ErrValue)?;
        if !present {
            if default != Some(wanted_value) {
                return Ok(false);
            }
            continue;
        }

        let actual = left.get(key).map_err(BfErr::ErrValue)?;
        if actual != *wanted_value {
            return Ok(false);
        }
    }
    Ok(true)
}

fn project_map(source: &Map, keys: &List) -> Result<Var, BfErr> {
    let mut pairs = Vec::with_capacity(keys.len().min(source.len()));
    for key in keys.iter_ref() {
        if matches!(key.variant(), Variant::Map(_) | Variant::List(_)) {
            return Err(BfErr::ErrValue(
                E_TYPE.msg("mapproject keys must be scalar values"),
            ));
        }

        if !source.contains_key(key, false).map_err(BfErr::ErrValue)? {
            continue;
        }
        pairs.push((key.clone(), source.get(key).map_err(BfErr::ErrValue)?));
    }
    Ok(v_map(&pairs))
}

/// Usage: `map mapdelete(map m, any key)`
/// Returns a copy of map with the entry for key removed. Raises E_RANGE if key is not found.
/// Keys must be scalar values (not lists or maps).
fn bf_mapdelete(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(E_ARGS.msg("mapdelete() takes 2 arguments")));
    }

    let Some(m) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapdelete first argument must be a map"),
        ));
    };

    if matches!(
        bf_args.args[1].variant(),
        Variant::Map(_) | Variant::List(_)
    ) {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapdelete second argument must be a scalar"),
        ));
    }

    let (nm, Some(_)) = m.remove_key(&bf_args.args[1]) else {
        return Err(BfErr::ErrValue(E_RANGE.msg("mapdelete key not found")));
    };

    Ok(BfRet::Ret(nm))
}

/// Usage: `list mapkeys(map m)`
/// Returns a list of all keys in the map. Maps are ordered, so the keys are returned
/// in the order they appear in the map.
fn bf_mapkeys(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(E_ARGS.msg("mapkeys() takes 1 argument")));
    }

    let Some(m) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapkeys first argument must be a map"),
        ));
    };

    let keys: Vec<Var> = m.iter_ref().map(|(k, _)| k.clone()).collect();

    Ok(BfRet::Ret(v_list(&keys)))
}

/// Usage: `list mapvalues(map m [, any key, ...])`
/// Returns a list of values from the map. If no keys are specified, returns all values
/// in iteration order. If keys are specified, returns only the values for those keys,
/// in the order the keys were given.
fn bf_mapvalues(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("mapvalues() requires at least 1 argument"),
        ));
    }

    let Some(m) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapvalues first argument must be a map"),
        ));
    };

    let values: Vec<Var> = if bf_args.args.len() == 1 {
        // No keys specified - return all values
        m.iter_ref().map(|(_, v)| v.clone()).collect()
    } else {
        // Keys specified - return values for those keys in order
        let mut result = Vec::with_capacity(bf_args.args.len() - 1);
        for key in bf_args.args.iter().skip(1) {
            let value = m.get(&key).map_err(BfErr::ErrValue)?;
            result.push(value);
        }
        result
    };

    Ok(BfRet::Ret(v_list(&values)))
}

/// Usage: `bool maphaskey(map m, any key)`
/// Returns true (1) if the map contains the specified key, false (0) otherwise.
/// More efficient than `!(key in mapkeys(m))` for maps with many keys.
fn bf_maphaskey(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(E_ARGS.msg("maphaskey() takes 2 arguments")));
    }

    let Some(m) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("maphaskey first argument must be a map"),
        ));
    };

    if matches!(
        bf_args.args[1].variant(),
        Variant::Map(_) | Variant::List(_)
    ) {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("maphaskey second argument must be a scalar"),
        ));
    }

    let contains = m
        .contains_key(&bf_args.args[1], false)
        .map_err(BfErr::ErrValue)?;
    Ok(BfRet::Ret(bf_args.v_bool(contains)))
}

/// Usage: `map mapmerge(map left, map right)`
/// Returns a right-biased union of two maps.
fn bf_mapmerge(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(E_ARGS.msg("mapmerge() takes 2 arguments")));
    }

    let Some(right) = bf_args.args[1].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapmerge second argument must be a map"),
        ));
    };
    if bf_args.args[0].as_map().is_none() {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapmerge first argument must be a map"),
        ));
    }

    Ok(BfRet::Ret(merge_maps(&bf_args.args[0], right)?))
}

/// Usage: `map mapintersection(map left, map right)`
/// Returns entries from `left` whose keys also occur in `right`.
fn bf_mapintersection(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("mapintersection() takes 2 arguments"),
        ));
    }

    let Some(left) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapintersection first argument must be a map"),
        ));
    };
    let Some(right) = bf_args.args[1].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapintersection second argument must be a map"),
        ));
    };

    Ok(BfRet::Ret(intersect_maps(left, right)?))
}

/// Usage: `map mapdifference(map source, list|map keys)`
/// Returns `source` without the keys supplied by the second argument.
fn bf_mapdifference(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("mapdifference() takes 2 arguments"),
        ));
    }
    if bf_args.args[0].as_map().is_none() {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapdifference first argument must be a map"),
        ));
    }

    Ok(BfRet::Ret(remove_map_keys(
        &bf_args.args[0],
        &bf_args.args[1],
    )?))
}

/// Usage: `bool mapcontains(map source, map wanted [, any default])`
/// Tests whether `source` contains every key-value pair in `wanted`.
fn bf_mapcontains(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if !(2..=3).contains(&bf_args.args.len()) {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("mapcontains() takes 2 or 3 arguments"),
        ));
    }

    let Some(source) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapcontains first argument must be a map"),
        ));
    };
    let Some(wanted) = bf_args.args[1].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapcontains second argument must be a map"),
        ));
    };
    let default = (bf_args.args.len() == 3).then(|| &bf_args.args[2]);
    let contains = map_contains(source, wanted, default)?;

    Ok(BfRet::Ret(bf_args.v_bool(contains)))
}

/// Usage: `map mapproject(map source, list keys)`
/// Returns entries from `source` whose keys occur in `keys`.
fn bf_mapproject(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("mapproject() takes 2 arguments"),
        ));
    }

    let Some(source) = bf_args.args[0].as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapproject first argument must be a map"),
        ));
    };
    let Some(keys) = bf_args.args[1].as_list() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("mapproject second argument must be a list"),
        ));
    };

    Ok(BfRet::Ret(project_map(source, keys)?))
}

pub(crate) fn register_bf_maps(builtins: &mut [BuiltinFunction]) {
    builtins[offset_for_builtin("mapdelete")] = bf_mapdelete;
    builtins[offset_for_builtin("mapkeys")] = bf_mapkeys;
    builtins[offset_for_builtin("mapvalues")] = bf_mapvalues;
    builtins[offset_for_builtin("maphaskey")] = bf_maphaskey;
    builtins[offset_for_builtin("mapmerge")] = bf_mapmerge;
    builtins[offset_for_builtin("mapintersection")] = bf_mapintersection;
    builtins[offset_for_builtin("mapdifference")] = bf_mapdifference;
    builtins[offset_for_builtin("mapcontains")] = bf_mapcontains;
    builtins[offset_for_builtin("mapproject")] = bf_mapproject;
}

#[cfg(test)]
mod tests {
    use moor_var::{v_int, v_str};

    use super::*;

    fn sample_map() -> Var {
        v_map(&[
            (v_str("a"), v_int(1)),
            (v_str("b"), v_int(2)),
            (v_str("c"), v_int(3)),
        ])
    }

    #[test]
    fn mapmerge_uses_values_from_right_map() {
        let left = sample_map();
        let right = v_map(&[(v_str("b"), v_int(20)), (v_str("d"), v_int(4))]);

        let result = merge_maps(&left, right.as_map().unwrap()).unwrap();

        assert_eq!(
            result,
            v_map(&[
                (v_str("a"), v_int(1)),
                (v_str("b"), v_int(20)),
                (v_str("c"), v_int(3)),
                (v_str("d"), v_int(4)),
            ])
        );
        assert_eq!(left, sample_map());
    }

    #[test]
    fn mapintersection_keeps_left_values_for_shared_keys() {
        let left = sample_map();
        let right = v_map(&[(v_str("b"), v_int(200)), (v_str("d"), v_int(4))]);

        let result = intersect_maps(left.as_map().unwrap(), right.as_map().unwrap()).unwrap();

        assert_eq!(result, v_map(&[(v_str("b"), v_int(2))]));
    }

    #[test]
    fn mapdifference_accepts_a_key_list_or_map() {
        let source = sample_map();
        let list_keys = v_list(&[v_str("a"), v_str("missing")]);
        let map_keys = v_map(&[(v_str("b"), v_int(0))]);

        assert_eq!(
            remove_map_keys(&source, &list_keys).unwrap(),
            v_map(&[(v_str("b"), v_int(2)), (v_str("c"), v_int(3))])
        );
        assert_eq!(
            remove_map_keys(&source, &map_keys).unwrap(),
            v_map(&[(v_str("a"), v_int(1)), (v_str("c"), v_int(3))])
        );
    }

    #[test]
    fn mapcontains_can_substitute_a_default_for_missing_keys() {
        let source = v_map(&[(v_str("a"), v_int(1))]);
        let present = v_map(&[(v_str("a"), v_int(1))]);
        let missing_zero = v_map(&[(v_str("b"), v_int(0))]);
        let missing_one = v_map(&[(v_str("b"), v_int(1))]);

        assert!(map_contains(source.as_map().unwrap(), present.as_map().unwrap(), None).unwrap());
        assert!(
            !map_contains(
                source.as_map().unwrap(),
                missing_zero.as_map().unwrap(),
                None
            )
            .unwrap()
        );
        assert!(
            map_contains(
                source.as_map().unwrap(),
                missing_zero.as_map().unwrap(),
                Some(&v_int(0))
            )
            .unwrap()
        );
        assert!(
            !map_contains(
                source.as_map().unwrap(),
                missing_one.as_map().unwrap(),
                Some(&v_int(0))
            )
            .unwrap()
        );
    }

    #[test]
    fn mapproject_ignores_missing_and_duplicate_keys() {
        let source = sample_map();
        let keys = v_list(&[v_str("c"), v_str("missing"), v_str("a"), v_str("c")]);

        let result = project_map(source.as_map().unwrap(), keys.as_list().unwrap()).unwrap();

        assert_eq!(
            result,
            v_map(&[(v_str("a"), v_int(1)), (v_str("c"), v_int(3))])
        );
    }
}
