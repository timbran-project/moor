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

//! Builtin functions for pure algorithms over supplied MOO values.
//!
//! These builtins operate on caller-provided values such as lists, maps,
//! symbols, and objects. They do not inspect world state or task permissions.

use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashSet};
use std::sync::LazyLock;

use ahash::HashMap;
use moor_compiler::offset_for_builtin;
use moor_var::{
    Associative, E_ARGS, E_INVARG, E_MAXREC, E_TYPE, Symbol, Var, Variant, v_empty_list, v_int,
    v_list, v_list_iter, v_map, v_sym,
};

use crate::vm::builtins::{BfCallState, BfErr, BfRet, BfRet::Ret, BuiltinFunction};

static VAR_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("var"));
static UNBOUND_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("unbound"));
static RAISE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("raise"));
static LEAVE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("leave"));
static MAX_DEPTH_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("max_depth"));
static MAX_BINDINGS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("max_bindings"));
static MAX_SOLUTIONS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("max_solutions"));
static MAX_STEPS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("max_steps"));
static DEDUPE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("dedupe"));
static NOT_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("not"));

const DEFAULT_TERM_MAX_DEPTH: usize = 64;
const DEFAULT_TERM_MAX_BINDINGS: usize = 256;
const DEFAULT_QUERY_MAX_DEPTH: usize = 32;
const DEFAULT_QUERY_MAX_SOLUTIONS: usize = 256;
const DEFAULT_QUERY_MAX_STEPS: usize = 10_000;
const INTERNAL_QUERY_VAR_PREFIX: &str = "__term_query:";

#[derive(Clone, Copy)]
struct TermOptions {
    unbound: UnboundMode,
    max_depth: usize,
    max_bindings: usize,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum UnboundMode {
    Raise,
    Leave,
}

impl Default for TermOptions {
    fn default() -> Self {
        Self {
            unbound: UnboundMode::Raise,
            max_depth: DEFAULT_TERM_MAX_DEPTH,
            max_bindings: DEFAULT_TERM_MAX_BINDINGS,
        }
    }
}

type TermBindings = HashMap<Symbol, Var>;

#[derive(Clone, Copy)]
struct QueryOptions {
    term: TermOptions,
    max_solutions: usize,
    max_steps: usize,
    dedupe: bool,
}

impl Default for QueryOptions {
    fn default() -> Self {
        Self {
            term: TermOptions {
                max_depth: DEFAULT_QUERY_MAX_DEPTH,
                ..TermOptions::default()
            },
            max_solutions: DEFAULT_QUERY_MAX_SOLUTIONS,
            max_steps: DEFAULT_QUERY_MAX_STEPS,
            dedupe: true,
        }
    }
}

#[derive(Clone, Debug)]
struct QueryRule {
    head: Var,
    body: Vec<Var>,
}

#[inline]
fn option_key_symbol(key: &Var) -> Result<Symbol, BfErr> {
    match key.variant() {
        Variant::Sym(sym) => Ok(sym),
        Variant::Str(s) => Ok(Symbol::mk(s.as_str())),
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg("term builtin option keys must be strings or symbols"),
        )),
    }
}

#[inline]
fn option_value_symbol(value: &Var, option_name: &str) -> Result<Symbol, BfErr> {
    match value.variant() {
        Variant::Sym(sym) => Ok(sym),
        Variant::Str(s) => Ok(Symbol::mk(s.as_str())),
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg(format!("{option_name} option must be a string or symbol")),
        )),
    }
}

fn positive_usize_option(value: &Var, option_name: &str) -> Result<usize, BfErr> {
    let Some(value) = value.as_integer() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg(format!("{option_name} option must be an integer")),
        ));
    };
    if value <= 0 {
        return Err(BfErr::ErrValue(
            E_INVARG.msg(format!("{option_name} option must be positive")),
        ));
    }
    Ok(value as usize)
}

fn parse_term_options(value: Option<&Var>) -> Result<TermOptions, BfErr> {
    let mut options = TermOptions::default();
    let Some(value) = value else {
        return Ok(options);
    };
    let Some(map) = value.as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("term builtin options must be a map"),
        ));
    };

    for (key, value) in map.iter_ref() {
        let key = option_key_symbol(key)?;
        if key == *UNBOUND_SYM {
            let mode = option_value_symbol(value, "unbound")?;
            if mode == *RAISE_SYM {
                options.unbound = UnboundMode::Raise;
            } else if mode == *LEAVE_SYM {
                options.unbound = UnboundMode::Leave;
            } else {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("unbound option must be 'raise or 'leave"),
                ));
            }
        } else if key == *MAX_DEPTH_SYM {
            options.max_depth = positive_usize_option(value, "max_depth")?;
        } else if key == *MAX_BINDINGS_SYM {
            options.max_bindings = positive_usize_option(value, "max_bindings")?;
        } else {
            return Err(BfErr::ErrValue(
                E_INVARG.msg(format!("unknown term builtin option: {key}")),
            ));
        }
    }

    Ok(options)
}

fn parse_query_options(value: Option<&Var>) -> Result<QueryOptions, BfErr> {
    let mut options = QueryOptions::default();
    let Some(value) = value else {
        return Ok(options);
    };
    let Some(map) = value.as_map() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("term_query() options must be a map"),
        ));
    };

    for (key, value) in map.iter_ref() {
        let key = option_key_symbol(key)?;
        if key == *MAX_DEPTH_SYM {
            options.term.max_depth = positive_usize_option(value, "max_depth")?;
        } else if key == *MAX_BINDINGS_SYM {
            options.term.max_bindings = positive_usize_option(value, "max_bindings")?;
        } else if key == *MAX_SOLUTIONS_SYM {
            options.max_solutions = positive_usize_option(value, "max_solutions")?;
        } else if key == *MAX_STEPS_SYM {
            options.max_steps = positive_usize_option(value, "max_steps")?;
        } else if key == *DEDUPE_SYM {
            options.dedupe = value.is_true();
        } else {
            return Err(BfErr::ErrValue(
                E_INVARG.msg(format!("unknown term_query() option: {key}")),
            ));
        }
    }

    Ok(options)
}

fn load_bindings(value: Option<&Var>, max_bindings: usize) -> Result<TermBindings, BfErr> {
    let mut bindings = TermBindings::default();
    let Some(value) = value else {
        return Ok(bindings);
    };
    let Some(map) = value.as_map() else {
        return Err(BfErr::ErrValue(E_TYPE.msg("term bindings must be a map")));
    };
    if map.len() > max_bindings {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("term bindings exceed max_bindings"),
        ));
    }

    for (key, value) in map.iter_ref() {
        let Variant::Sym(name) = key.variant() else {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("term binding keys must be symbols"),
            ));
        };
        bindings.insert(name, value.clone());
    }
    Ok(bindings)
}

fn bindings_to_var(bindings: TermBindings) -> Var {
    let pairs = bindings
        .into_iter()
        .map(|(name, value)| (v_sym(name), value))
        .collect::<Vec<_>>();
    v_map(&pairs)
}

fn variable_marker(term: &Var) -> Result<Option<Symbol>, BfErr> {
    let Variant::List(list) = term.variant() else {
        return Ok(None);
    };
    if list.is_empty() {
        return Ok(None);
    }
    let Variant::Sym(marker) = list[0].variant() else {
        return Ok(None);
    };
    if marker != *VAR_SYM {
        return Ok(None);
    }
    if list.len() != 2 {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("variable marker must have shape {'var, symbol}"),
        ));
    }
    let Variant::Sym(name) = list[1].variant() else {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("variable marker name must be a symbol"),
        ));
    };
    Ok(Some(name))
}

#[inline]
fn check_depth(depth: usize, options: &TermOptions) -> Result<(), BfErr> {
    if depth > options.max_depth {
        return Err(BfErr::ErrValue(
            E_MAXREC.msg("term recursion exceeded max_depth"),
        ));
    }
    Ok(())
}

fn bind_term_unify_variable(
    name: Symbol,
    datum: &Var,
    bindings: &mut TermBindings,
    options: &TermOptions,
) -> Result<bool, BfErr> {
    if let Some(bound) = bindings.get(&name) {
        return Ok(bound == datum);
    }
    if bindings.len() >= options.max_bindings {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("term_unify() exceeded max_bindings"),
        ));
    }
    bindings.insert(name, datum.clone());
    Ok(true)
}

fn term_unify_inner(
    pattern: &Var,
    datum: &Var,
    bindings: &mut TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<bool, BfErr> {
    check_depth(depth, options)?;

    if let Some(name) = variable_marker(pattern)? {
        return bind_term_unify_variable(name, datum, bindings, options);
    }

    match (pattern.variant(), datum.variant()) {
        (Variant::List(pattern_list), Variant::List(datum_list)) => {
            if pattern_list.len() != datum_list.len() {
                return Ok(false);
            }
            for (pattern_item, datum_item) in pattern_list.iter_ref().zip(datum_list.iter_ref()) {
                if !term_unify_inner(pattern_item, datum_item, bindings, options, depth + 1)? {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        (Variant::Map(pattern_map), Variant::Map(datum_map)) => {
            if pattern_map.len() != datum_map.len() {
                return Ok(false);
            }
            for (key, pattern_value) in pattern_map.iter_ref() {
                let datum_value = match datum_map.get(key) {
                    Ok(value) => value,
                    Err(_) => return Ok(false),
                };
                if !term_unify_inner(pattern_value, &datum_value, bindings, options, depth + 1)? {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        _ => Ok(pattern == datum),
    }
}

/// Usage: `map|bool term_unify(any pattern, any value [, map bindings [, map options]])`
///
/// Matches a pattern containing `{'var, symbol}` markers against exactly one value.
fn bf_term_unify(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 2 || bf_args.args.len() > 4 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("term_unify() takes 2 to 4 arguments"),
        ));
    }

    let options = parse_term_options(bf_args.args.iter_ref().nth(3))?;
    let mut bindings = load_bindings(bf_args.args.iter_ref().nth(2), options.max_bindings)?;
    let matched = term_unify_inner(
        &bf_args.args[0],
        &bf_args.args[1],
        &mut bindings,
        &options,
        0,
    )?;

    if matched {
        Ok(Ret(bindings_to_var(bindings)))
    } else {
        Ok(Ret(bf_args.v_bool(false)))
    }
}

fn term_substitute_inner(
    term: &Var,
    bindings: &TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<(Var, bool), BfErr> {
    check_depth(depth, options)?;

    if let Some(name) = variable_marker(term)? {
        if let Some(value) = bindings.get(&name) {
            return Ok((value.clone(), true));
        }
        return match options.unbound {
            UnboundMode::Raise => Err(BfErr::ErrValue(
                E_INVARG.msg(format!("unbound variable in term_substitute(): {name}")),
            )),
            UnboundMode::Leave => Ok((term.clone(), false)),
        };
    }

    match term.variant() {
        Variant::List(list) => {
            let mut changed_items = None::<Vec<Var>>;
            for (index, item) in list.iter_ref().enumerate() {
                let (new_item, changed) =
                    term_substitute_inner(item, bindings, options, depth + 1)?;
                if let Some(items) = changed_items.as_mut() {
                    items.push(new_item);
                } else if changed {
                    let mut items = Vec::with_capacity(list.len());
                    items.extend(list.iter_ref().take(index).cloned());
                    items.push(new_item);
                    changed_items = Some(items);
                }
            }
            if let Some(items) = changed_items {
                Ok((v_list(&items), true))
            } else {
                Ok((term.clone(), false))
            }
        }
        Variant::Map(map) => {
            let mut changed_pairs = None::<Vec<(Var, Var)>>;
            for (index, (key, value)) in map.iter_ref().enumerate() {
                let (new_value, value_changed) =
                    term_substitute_inner(value, bindings, options, depth + 1)?;
                if let Some(pairs) = changed_pairs.as_mut() {
                    pairs.push((key.clone(), new_value));
                } else if value_changed {
                    let mut pairs = Vec::with_capacity(map.len());
                    pairs.extend(
                        map.iter_ref()
                            .take(index)
                            .map(|(prev_key, prev_value)| (prev_key.clone(), prev_value.clone())),
                    );
                    pairs.push((key.clone(), new_value));
                    changed_pairs = Some(pairs);
                }
            }
            if let Some(pairs) = changed_pairs {
                Ok((v_map(&pairs), true))
            } else {
                Ok((term.clone(), false))
            }
        }
        _ => Ok((term.clone(), false)),
    }
}

/// Usage: `any term_substitute(any template, map bindings [, map options])`
///
/// Recursively replaces `{'var, symbol}` markers in a template using a bindings map.
fn bf_term_substitute(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 2 || bf_args.args.len() > 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("term_substitute() takes 2 or 3 arguments"),
        ));
    }

    let options = parse_term_options(bf_args.args.iter_ref().nth(2))?;
    let bindings = load_bindings(bf_args.args.iter_ref().nth(1), options.max_bindings)?;
    let (result, _) = term_substitute_inner(&bf_args.args[0], &bindings, &options, 0)?;
    Ok(Ret(result))
}

#[inline]
fn variable_term(name: Symbol) -> Var {
    v_list(&[v_sym(*VAR_SYM), v_sym(name)])
}

#[inline]
fn is_internal_query_var(name: Symbol) -> bool {
    name.as_str().starts_with(INTERNAL_QUERY_VAR_PREFIX)
}

fn collect_variables(term: &Var, variables: &mut Vec<Symbol>) -> Result<(), BfErr> {
    if let Some(name) = variable_marker(term)? {
        if !variables.contains(&name) {
            variables.push(name);
        }
        return Ok(());
    }

    match term.variant() {
        Variant::List(list) => {
            for item in list.iter_ref() {
                collect_variables(item, variables)?;
            }
        }
        Variant::Map(map) => {
            for (_, value) in map.iter_ref() {
                collect_variables(value, variables)?;
            }
        }
        _ => {}
    }

    Ok(())
}

fn body_term_is_negative(term: &Var) -> bool {
    let Variant::List(list) = term.variant() else {
        return false;
    };
    if list.is_empty() {
        return false;
    }
    matches!(list[0].variant(), Variant::Sym(name) if name == *NOT_SYM)
}

fn parse_query_rules(rules: &Var) -> Result<Vec<QueryRule>, BfErr> {
    let Some(rules) = rules.as_list() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("term_query() rules must be a list"),
        ));
    };

    let mut parsed = Vec::with_capacity(rules.len());
    for rule in rules.iter_ref() {
        let Variant::List(pair) = rule.variant() else {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("term_query() rules must have shape {head, body}"),
            ));
        };
        if pair.len() != 2 {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("term_query() rules must have shape {head, body}"),
            ));
        }

        let head = pair[0].clone();
        let Some(body_list) = pair[1].as_list() else {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("term_query() rule body must be a list of positive terms"),
            ));
        };

        let mut body = Vec::with_capacity(body_list.len());
        for term in body_list.iter_ref() {
            if body_term_is_negative(term) {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("term_query() v1 does not support negation"),
                ));
            }
            body.push(term.clone());
        }

        let mut head_vars = Vec::new();
        let mut body_vars = Vec::new();
        collect_variables(&head, &mut head_vars)?;
        for term in &body {
            collect_variables(term, &mut body_vars)?;
        }
        if head_vars
            .iter()
            .any(|head_var| !body_vars.contains(head_var))
        {
            return Err(BfErr::ErrValue(E_INVARG.msg(
                "term_query() rule head variables must also appear in the body",
            )));
        }

        parsed.push(QueryRule { head, body });
    }

    Ok(parsed)
}

fn resolve_top_variable(
    term: &Var,
    bindings: &TermBindings,
    options: &TermOptions,
) -> Result<Var, BfErr> {
    let mut current = term.clone();
    let mut seen = Vec::new();
    loop {
        let Some(name) = variable_marker(&current)? else {
            return Ok(current);
        };
        if seen.contains(&name) {
            return Ok(current);
        }
        seen.push(name);
        let Some(bound) = bindings.get(&name) else {
            return Ok(current);
        };
        if seen.len() > options.max_depth {
            return Err(BfErr::ErrValue(
                E_MAXREC.msg("term_query() variable resolution exceeded max_depth"),
            ));
        }
        current = bound.clone();
    }
}

fn bind_query_variable(
    name: Symbol,
    value: &Var,
    bindings: &mut TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<bool, BfErr> {
    let resolved = resolve_top_variable(value, bindings, options)?;
    if let Some(other_name) = variable_marker(&resolved)? {
        if other_name == name {
            return Ok(true);
        }
        if is_internal_query_var(other_name) && !is_internal_query_var(name) {
            return bind_query_variable(
                other_name,
                &variable_term(name),
                bindings,
                options,
                depth + 1,
            );
        }
    }

    if let Some(bound) = bindings.get(&name).cloned() {
        return term_query_match_inner(&bound, &resolved, bindings, options, depth + 1);
    }
    if bindings.len() >= options.max_bindings {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("term_query() exceeded max_bindings"),
        ));
    }
    bindings.insert(name, resolved);
    Ok(true)
}

fn term_query_match_inner(
    left: &Var,
    right: &Var,
    bindings: &mut TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<bool, BfErr> {
    check_depth(depth, options)?;

    let left = resolve_top_variable(left, bindings, options)?;
    let right = resolve_top_variable(right, bindings, options)?;

    if let Some(name) = variable_marker(&left)? {
        return bind_query_variable(name, &right, bindings, options, depth);
    }
    if let Some(name) = variable_marker(&right)? {
        return bind_query_variable(name, &left, bindings, options, depth);
    }

    match (left.variant(), right.variant()) {
        (Variant::List(left_list), Variant::List(right_list)) => {
            if left_list.len() != right_list.len() {
                return Ok(false);
            }
            for (left_item, right_item) in left_list.iter_ref().zip(right_list.iter_ref()) {
                if !term_query_match_inner(left_item, right_item, bindings, options, depth + 1)? {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        (Variant::Map(left_map), Variant::Map(right_map)) => {
            if left_map.len() != right_map.len() {
                return Ok(false);
            }
            for (key, left_value) in left_map.iter_ref() {
                let right_value = match right_map.get(key) {
                    Ok(value) => value,
                    Err(_) => return Ok(false),
                };
                if !term_query_match_inner(left_value, &right_value, bindings, options, depth + 1)?
                {
                    return Ok(false);
                }
            }
            Ok(true)
        }
        _ => Ok(left == right),
    }
}

fn resolve_query_term(
    term: &Var,
    bindings: &TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<Var, BfErr> {
    check_depth(depth, options)?;

    let resolved = resolve_top_variable(term, bindings, options)?;
    if variable_marker(&resolved)?.is_some() {
        return Ok(resolved);
    }

    match resolved.variant() {
        Variant::List(list) => {
            let mut changed_items = None::<Vec<Var>>;
            for (index, item) in list.iter_ref().enumerate() {
                let new_item = resolve_query_term(item, bindings, options, depth + 1)?;
                if let Some(items) = changed_items.as_mut() {
                    items.push(new_item);
                } else if new_item != *item {
                    let mut items = Vec::with_capacity(list.len());
                    items.extend(list.iter_ref().take(index).cloned());
                    items.push(new_item);
                    changed_items = Some(items);
                }
            }
            if let Some(items) = changed_items {
                Ok(v_list(&items))
            } else {
                Ok(resolved)
            }
        }
        Variant::Map(map) => {
            let mut changed_pairs = None::<Vec<(Var, Var)>>;
            for (index, (key, value)) in map.iter_ref().enumerate() {
                let new_value = resolve_query_term(value, bindings, options, depth + 1)?;
                if let Some(pairs) = changed_pairs.as_mut() {
                    pairs.push((key.clone(), new_value));
                } else if new_value != *value {
                    let mut pairs = Vec::with_capacity(map.len());
                    pairs.extend(
                        map.iter_ref()
                            .take(index)
                            .map(|(prev_key, prev_value)| (prev_key.clone(), prev_value.clone())),
                    );
                    pairs.push((key.clone(), new_value));
                    changed_pairs = Some(pairs);
                }
            }
            if let Some(pairs) = changed_pairs {
                Ok(v_map(&pairs))
            } else {
                Ok(resolved)
            }
        }
        _ => Ok(resolved),
    }
}

fn freshen_term(
    term: &Var,
    scope: usize,
    renames: &mut TermBindings,
    depth: usize,
    options: &TermOptions,
) -> Result<Var, BfErr> {
    check_depth(depth, options)?;

    if let Some(name) = variable_marker(term)? {
        if let Some(renamed) = renames.get(&name) {
            return Ok(renamed.clone());
        }
        let renamed_name = Symbol::mk(&format!(
            "{INTERNAL_QUERY_VAR_PREFIX}{scope}:{}",
            name.as_str()
        ));
        let renamed = variable_term(renamed_name);
        renames.insert(name, renamed.clone());
        return Ok(renamed);
    }

    match term.variant() {
        Variant::List(list) => {
            let mut changed_items = None::<Vec<Var>>;
            for (index, item) in list.iter_ref().enumerate() {
                let new_item = freshen_term(item, scope, renames, depth + 1, options)?;
                if let Some(items) = changed_items.as_mut() {
                    items.push(new_item);
                } else if new_item != *item {
                    let mut items = Vec::with_capacity(list.len());
                    items.extend(list.iter_ref().take(index).cloned());
                    items.push(new_item);
                    changed_items = Some(items);
                }
            }
            if let Some(items) = changed_items {
                Ok(v_list(&items))
            } else {
                Ok(term.clone())
            }
        }
        Variant::Map(map) => {
            let mut changed_pairs = None::<Vec<(Var, Var)>>;
            for (index, (key, value)) in map.iter_ref().enumerate() {
                let new_value = freshen_term(value, scope, renames, depth + 1, options)?;
                if let Some(pairs) = changed_pairs.as_mut() {
                    pairs.push((key.clone(), new_value));
                } else if new_value != *value {
                    let mut pairs = Vec::with_capacity(map.len());
                    pairs.extend(
                        map.iter_ref()
                            .take(index)
                            .map(|(prev_key, prev_value)| (prev_key.clone(), prev_value.clone())),
                    );
                    pairs.push((key.clone(), new_value));
                    changed_pairs = Some(pairs);
                }
            }
            if let Some(pairs) = changed_pairs {
                Ok(v_map(&pairs))
            } else {
                Ok(term.clone())
            }
        }
        _ => Ok(term.clone()),
    }
}

fn canonicalize_query_state_term(
    term: &Var,
    names: &mut TermBindings,
    options: &TermOptions,
    depth: usize,
) -> Result<Var, BfErr> {
    check_depth(depth, options)?;

    if let Some(name) = variable_marker(term)? {
        if !is_internal_query_var(name) {
            return Ok(term.clone());
        }
        if let Some(canonical) = names.get(&name) {
            return Ok(canonical.clone());
        }
        let canonical = variable_term(Symbol::mk(&format!("__term_query_state:{}", names.len())));
        names.insert(name, canonical.clone());
        return Ok(canonical);
    }

    match term.variant() {
        Variant::List(list) => {
            let mut items = Vec::with_capacity(list.len());
            for item in list.iter_ref() {
                items.push(canonicalize_query_state_term(
                    item,
                    names,
                    options,
                    depth + 1,
                )?);
            }
            Ok(v_list(&items))
        }
        Variant::Map(map) => {
            let mut pairs = Vec::with_capacity(map.len());
            for (key, value) in map.iter_ref() {
                pairs.push((
                    key.clone(),
                    canonicalize_query_state_term(value, names, options, depth + 1)?,
                ));
            }
            Ok(v_map(&pairs))
        }
        _ => Ok(term.clone()),
    }
}

struct QueryEngine<'a> {
    facts: Vec<Var>,
    rules: Vec<QueryRule>,
    public_variables: &'a [Symbol],
    options: QueryOptions,
    fresh_scope: usize,
    steps: usize,
    solutions: Vec<Var>,
    seen_solutions: HashSet<Var>,
    active_states: HashSet<Var>,
}

impl QueryEngine<'_> {
    fn fresh_scope(&mut self) -> usize {
        let scope = self.fresh_scope;
        self.fresh_scope += 1;
        scope
    }

    fn check_search_step(&mut self) -> Result<(), BfErr> {
        self.steps += 1;
        if self.steps > self.options.max_steps {
            return Err(BfErr::ErrValue(
                E_MAXREC.msg("term_query() exceeded max_steps"),
            ));
        }
        Ok(())
    }

    fn project_solution(&self, bindings: &TermBindings) -> Result<Var, BfErr> {
        let mut pairs = Vec::with_capacity(self.public_variables.len());
        for name in self.public_variables {
            let resolved =
                resolve_query_term(&variable_term(*name), bindings, &self.options.term, 0)?;
            if variable_marker(&resolved)?.is_none() {
                pairs.push((v_sym(*name), resolved));
            }
        }
        Ok(v_map(&pairs))
    }

    fn query_state_key(&self, goals: &[Var], bindings: &TermBindings) -> Result<Var, BfErr> {
        let mut names = TermBindings::default();
        let mut resolved_goals = Vec::with_capacity(goals.len());
        for goal in goals {
            let resolved = resolve_query_term(goal, bindings, &self.options.term, 0)?;
            resolved_goals.push(canonicalize_query_state_term(
                &resolved,
                &mut names,
                &self.options.term,
                0,
            )?);
        }
        Ok(v_list(&resolved_goals))
    }

    fn add_solution(&mut self, bindings: &TermBindings) -> Result<(), BfErr> {
        let solution = self.project_solution(bindings)?;
        if self.options.dedupe && !self.seen_solutions.insert(solution.clone()) {
            return Ok(());
        }
        self.solutions.push(solution);
        Ok(())
    }

    fn solve(
        &mut self,
        goals: Vec<Var>,
        bindings: TermBindings,
        depth: usize,
    ) -> Result<(), BfErr> {
        if self.solutions.len() >= self.options.max_solutions {
            return Ok(());
        }
        if depth > self.options.term.max_depth {
            return Err(BfErr::ErrValue(
                E_MAXREC.msg("term_query() exceeded max_depth"),
            ));
        }
        self.check_search_step()?;

        if goals.is_empty() {
            return self.add_solution(&bindings);
        }

        let state_key = if self.options.dedupe {
            Some(self.query_state_key(&goals, &bindings)?)
        } else {
            None
        };
        if let Some(key) = state_key.as_ref()
            && !self.active_states.insert(key.clone())
        {
            return Ok(());
        }

        let goal = &goals[0];
        let rest = goals[1..].to_vec();

        for fact_index in 0..self.facts.len() {
            if self.solutions.len() >= self.options.max_solutions {
                break;
            }
            self.check_search_step()?;

            let scope = self.fresh_scope();
            let mut renames = TermBindings::default();
            let fact = freshen_term(
                &self.facts[fact_index],
                scope,
                &mut renames,
                0,
                &self.options.term,
            )?;
            let mut candidate_bindings = bindings.clone();
            if term_query_match_inner(goal, &fact, &mut candidate_bindings, &self.options.term, 0)?
            {
                self.solve(rest.clone(), candidate_bindings, depth)?;
            }
        }

        for rule_index in 0..self.rules.len() {
            if self.solutions.len() >= self.options.max_solutions {
                break;
            }
            self.check_search_step()?;

            let scope = self.fresh_scope();
            let mut renames = TermBindings::default();
            let rule = self.rules[rule_index].clone();
            let head = freshen_term(&rule.head, scope, &mut renames, 0, &self.options.term)?;
            let mut body = Vec::with_capacity(rule.body.len() + rest.len());
            for term in &rule.body {
                body.push(freshen_term(
                    term,
                    scope,
                    &mut renames,
                    0,
                    &self.options.term,
                )?);
            }
            body.extend(rest.iter().cloned());

            let mut candidate_bindings = bindings.clone();
            if term_query_match_inner(goal, &head, &mut candidate_bindings, &self.options.term, 0)?
            {
                self.solve(body, candidate_bindings, depth + 1)?;
            }
        }

        if let Some(key) = state_key {
            self.active_states.remove(&key);
        }
        Ok(())
    }
}

/// Usage: `list term_query(any query, list facts [, list rules [, map bindings [, map options]]])`
///
/// Evaluates a bounded positive-Horn query over caller-supplied terms. Rules
/// have shape `{head, body}` and bodies contain positive terms only.
fn bf_term_query(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() < 2 || bf_args.args.len() > 5 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("term_query() takes 2 to 5 arguments"),
        ));
    }

    let Some(facts) = bf_args.args[1].as_list() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("term_query() facts must be a list"),
        ));
    };
    let facts = facts.iter_ref().cloned().collect::<Vec<_>>();
    let rules = if let Some(rules) = bf_args.args.iter_ref().nth(2) {
        parse_query_rules(rules)?
    } else {
        Vec::new()
    };
    let options = parse_query_options(bf_args.args.iter_ref().nth(4))?;
    let bindings = load_bindings(bf_args.args.iter_ref().nth(3), options.term.max_bindings)?;

    let mut public_variables = Vec::new();
    collect_variables(&bf_args.args[0], &mut public_variables)?;
    for name in bindings.keys() {
        if !public_variables.contains(name) {
            public_variables.push(*name);
        }
    }

    let mut engine = QueryEngine {
        facts,
        rules,
        public_variables: &public_variables,
        options,
        fresh_scope: 0,
        steps: 0,
        solutions: Vec::new(),
        seen_solutions: HashSet::new(),
        active_states: HashSet::new(),
    };
    engine.solve(vec![bf_args.args[0].clone()], bindings, 0)?;
    Ok(Ret(v_list(&engine.solutions)))
}

/// Usage: `list astar(int width, int height, int start_x, int start_y, int goal_x, int goal_y, list tile_map, list solid_tiles)`
///
/// A* pathfinding on a tile grid. Returns a list of `{x, y}` waypoints from
/// the start to the goal (excluding the start position), or an empty list if
/// no path exists.
///
/// Supports 8-directional movement (cardinal + diagonal). Diagonal moves are
/// only permitted when both adjacent cardinal tiles are passable (no corner-cutting).
///
/// `tile_map` is a flat list of tile IDs (1-based indexing, row-major).
/// `solid_tiles` is a list of tile IDs that are impassable.
///
/// Uses Chebyshev distance as the heuristic (diagonal cost = cardinal cost).
fn bf_astar(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 8 {
        return Err(BfErr::ErrValue(E_ARGS.msg("astar() takes 8 arguments")));
    }

    let width = match bf_args.args[0].variant() {
        Variant::Int(i) if i > 0 => i as usize,
        _ => {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("width must be a positive integer"),
            ));
        }
    };
    let height = match bf_args.args[1].variant() {
        Variant::Int(i) if i > 0 => i as usize,
        _ => {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("height must be a positive integer"),
            ));
        }
    };
    let start_x = match bf_args.args[2].variant() {
        Variant::Int(i) => i as i32,
        _ => return Err(BfErr::ErrValue(E_TYPE.msg("start_x must be an integer"))),
    };
    let start_y = match bf_args.args[3].variant() {
        Variant::Int(i) => i as i32,
        _ => return Err(BfErr::ErrValue(E_TYPE.msg("start_y must be an integer"))),
    };
    let goal_x = match bf_args.args[4].variant() {
        Variant::Int(i) => i as i32,
        _ => return Err(BfErr::ErrValue(E_TYPE.msg("goal_x must be an integer"))),
    };
    let goal_y = match bf_args.args[5].variant() {
        Variant::Int(i) => i as i32,
        _ => return Err(BfErr::ErrValue(E_TYPE.msg("goal_y must be an integer"))),
    };

    let tile_map_list = bf_args.args[6]
        .as_list()
        .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("tile_map must be a list")))?;
    let solid_tiles_list = bf_args.args[7]
        .as_list()
        .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("solid_tiles must be a list")))?;

    let w = width as i32;
    let h = height as i32;

    // Validate start/goal in bounds.
    if start_x < 0 || start_x >= w || start_y < 0 || start_y >= h {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("start position out of bounds"),
        ));
    }
    if goal_x < 0 || goal_x >= w || goal_y < 0 || goal_y >= h {
        return Err(BfErr::ErrValue(E_INVARG.msg("goal position out of bounds")));
    }

    // Build passability bitmap from tile_map and solid_tiles.
    // solid_tile_ids: collect into a set for fast lookup.
    let mut solid_ids = std::collections::HashSet::new();
    for item in solid_tiles_list.iter() {
        if let Variant::Int(id) = item.variant() {
            solid_ids.insert(id);
        }
    }

    // Build flat passability grid: true = passable.
    let grid_size = width * height;
    let mut passable = vec![true; grid_size];
    for (i, item) in tile_map_list.iter().enumerate() {
        if i >= grid_size {
            break;
        }
        if let Variant::Int(tile_id) = item.variant()
            && solid_ids.contains(&tile_id)
        {
            passable[i] = false;
        }
    }

    // Check goal is passable.
    if !passable[(goal_y as usize) * width + (goal_x as usize)] {
        return Ok(Ret(v_empty_list()));
    }

    // Already there.
    if start_x == goal_x && start_y == goal_y {
        return Ok(Ret(v_empty_list()));
    }

    let is_passable = |x: i32, y: i32| -> bool {
        x >= 0 && x < w && y >= 0 && y < h && passable[(y as usize) * width + (x as usize)]
    };

    // A* with binary heap (min-heap via Reverse).
    // Node: (f_score, g_score, x, y)
    let mut open: BinaryHeap<Reverse<(i32, i32, i32, i32)>> = BinaryHeap::new();
    let mut g_score = vec![i32::MAX; grid_size];
    let mut came_from = vec![u32::MAX; grid_size]; // flat index of parent

    let start_idx = (start_y as usize) * width + (start_x as usize);
    let goal_idx = (goal_y as usize) * width + (goal_x as usize);

    g_score[start_idx] = 0;
    let h0 = (goal_x - start_x).abs().max((goal_y - start_y).abs()); // Chebyshev
    open.push(Reverse((h0, 0, start_x, start_y)));

    // 8-directional neighbors.
    const DIRS: [(i32, i32); 8] = [
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (1, 0),
        (-1, 1),
        (0, 1),
        (1, 1),
    ];

    while let Some(Reverse((_f, g, cx, cy))) = open.pop() {
        let cidx = (cy as usize) * width + (cx as usize);

        // Skip stale entries.
        if g > g_score[cidx] {
            continue;
        }

        // Goal reached.
        if cidx == goal_idx {
            // Reconstruct path.
            let mut path = Vec::new();
            let mut idx = goal_idx;
            while idx != start_idx {
                let px = (idx % width) as i64;
                let py = (idx / width) as i64;
                path.push(v_list(&[v_int(px), v_int(py)]));
                idx = came_from[idx] as usize;
            }
            path.reverse();
            return Ok(Ret(v_list_iter(path)));
        }

        let ng = g + 1;

        for &(dx, dy) in &DIRS {
            let nx = cx + dx;
            let ny = cy + dy;

            if !is_passable(nx, ny) {
                continue;
            }

            // Diagonal corner-cutting check.
            if dx != 0 && dy != 0 && (!is_passable(cx + dx, cy) || !is_passable(cx, cy + dy)) {
                continue;
            }

            let nidx = (ny as usize) * width + (nx as usize);
            if ng < g_score[nidx] {
                g_score[nidx] = ng;
                came_from[nidx] = cidx as u32;
                let heuristic = (goal_x - nx).abs().max((goal_y - ny).abs());
                open.push(Reverse((ng + heuristic, ng, nx, ny)));
            }
        }
    }

    // No path found.
    Ok(Ret(v_empty_list()))
}

pub(crate) fn register_bf_algorithms(builtins: &mut [BuiltinFunction]) {
    builtins[offset_for_builtin("astar")] = bf_astar;
    builtins[offset_for_builtin("term_unify")] = bf_term_unify;
    builtins[offset_for_builtin("term_substitute")] = bf_term_substitute;
    builtins[offset_for_builtin("term_query")] = bf_term_query;
}

#[cfg(test)]
mod tests {
    use moor_var::{Associative, v_int, v_str};

    use super::*;

    fn var(name: &str) -> Var {
        v_list(&[v_sym("var"), v_sym(name)])
    }

    fn unify(pattern: Var, datum: Var) -> Result<Option<Var>, BfErr> {
        let options = TermOptions::default();
        let mut bindings = TermBindings::default();
        if term_unify_inner(&pattern, &datum, &mut bindings, &options, 0)? {
            Ok(Some(bindings_to_var(bindings)))
        } else {
            Ok(None)
        }
    }

    fn term(name: &str, values: &[Var]) -> Var {
        let mut items = Vec::with_capacity(values.len() + 1);
        items.push(v_sym(name));
        items.extend(values.iter().cloned());
        v_list(&items)
    }

    fn query(query: Var, facts: Vec<Var>, rules: Vec<Var>) -> Result<Var, BfErr> {
        query_with_bindings(query, facts, rules, TermBindings::default())
    }

    fn query_with_bindings(
        query: Var,
        facts: Vec<Var>,
        rules: Vec<Var>,
        bindings: TermBindings,
    ) -> Result<Var, BfErr> {
        let rule_list = v_list(&rules);
        let parsed_rules = parse_query_rules(&rule_list)?;
        let mut public_variables = Vec::new();
        collect_variables(&query, &mut public_variables)?;
        for name in bindings.keys() {
            if !public_variables.contains(name) {
                public_variables.push(*name);
            }
        }
        let mut engine = QueryEngine {
            facts,
            rules: parsed_rules,
            public_variables: &public_variables,
            options: QueryOptions::default(),
            fresh_scope: 0,
            steps: 0,
            solutions: Vec::new(),
            seen_solutions: HashSet::new(),
            active_states: HashSet::new(),
        };
        engine.solve(vec![query], bindings, 0)?;
        Ok(v_list(&engine.solutions))
    }

    #[test]
    fn term_unify_binds_nested_variables() {
        let result = unify(
            v_list(&[v_sym("edge"), var("From"), v_list(&[var("To"), v_int(9)])]),
            v_list(&[v_sym("edge"), v_int(10), v_list(&[v_int(11), v_int(9)])]),
        )
        .unwrap()
        .unwrap();
        let bindings = result.as_map().unwrap();
        assert_eq!(bindings.get(&v_sym("From")).unwrap(), v_int(10));
        assert_eq!(bindings.get(&v_sym("To")).unwrap(), v_int(11));
    }

    #[test]
    fn term_unify_repeated_variable_must_match() {
        assert!(
            unify(
                v_list(&[var("X"), v_list(&[var("x")])]),
                v_list(&[v_str("same"), v_list(&[v_str("SAME")])]),
            )
            .unwrap()
            .is_some()
        );
        assert!(
            unify(
                v_list(&[var("X"), v_list(&[var("x")])]),
                v_list(&[v_int(1), v_list(&[v_int(2)])]),
            )
            .unwrap()
            .is_none()
        );
    }

    #[test]
    fn term_unify_respects_existing_bindings() {
        let options = TermOptions::default();
        let mut bindings = TermBindings::default();
        bindings.insert(Symbol::mk("From"), v_int(10));
        let matched = term_unify_inner(
            &v_list(&[v_sym("edge"), var("from"), var("To")]),
            &v_list(&[v_sym("edge"), v_int(10), v_int(11)]),
            &mut bindings,
            &options,
            0,
        )
        .unwrap();
        assert!(matched);
        assert_eq!(bindings.get(&Symbol::mk("To")).unwrap(), &v_int(11));

        let mut bindings = TermBindings::default();
        bindings.insert(Symbol::mk("From"), v_int(12));
        let matched = term_unify_inner(
            &v_list(&[v_sym("edge"), var("from")]),
            &v_list(&[v_sym("edge"), v_int(10)]),
            &mut bindings,
            &options,
            0,
        )
        .unwrap();
        assert!(!matched);
    }

    #[test]
    fn term_unify_matches_map_values_by_exact_key_set() {
        let pattern = v_map(&[(v_sym("edge"), v_list(&[var("From"), var("To")]))]);
        let datum = v_map(&[(v_sym("EDGE"), v_list(&[v_int(1), v_int(2)]))]);
        let result = unify(pattern, datum).unwrap().unwrap();
        let bindings = result.as_map().unwrap();
        assert_eq!(bindings.get(&v_sym("from")).unwrap(), v_int(1));
        assert_eq!(bindings.get(&v_sym("to")).unwrap(), v_int(2));

        let pattern = v_map(&[(v_sym("edge"), var("X"))]);
        let datum = v_map(&[(v_sym("edge"), v_int(1)), (v_sym("extra"), v_int(2))]);
        assert!(unify(pattern, datum).unwrap().is_none());
    }

    #[test]
    fn term_unify_rejects_malformed_variable_marker() {
        let err = unify(v_list(&[v_sym("var"), v_str("X")]), v_int(1)).unwrap_err();
        assert!(matches!(err, BfErr::ErrValue(error) if error.err_type() == E_INVARG));
    }

    #[test]
    fn term_query_matches_nested_variables_in_one_fact() {
        let result = query(
            v_list(&[v_sym("edge"), var("From"), v_list(&[var("To"), v_int(9)])]),
            vec![v_list(&[
                v_sym("edge"),
                v_int(10),
                v_list(&[v_int(11), v_int(9)]),
            ])],
            vec![],
        )
        .unwrap();
        let bindings = result.as_list().unwrap()[0].as_map().unwrap();
        assert_eq!(bindings.get(&v_sym("From")).unwrap(), v_int(10));
        assert_eq!(bindings.get(&v_sym("To")).unwrap(), v_int(11));
    }

    #[test]
    fn term_query_repeated_variable_must_match() {
        assert_eq!(
            query(
                v_list(&[var("X"), v_list(&[var("x")])]),
                vec![v_list(&[v_str("same"), v_list(&[v_str("SAME")])])],
                vec![],
            )
            .unwrap(),
            v_list(&[v_map(&[(v_sym("X"), v_str("same"))])])
        );
        assert_eq!(
            query(
                v_list(&[var("X"), v_list(&[var("x")])]),
                vec![v_list(&[v_int(1), v_list(&[v_int(2)])])],
                vec![],
            )
            .unwrap(),
            v_empty_list()
        );
    }

    #[test]
    fn term_query_respects_existing_bindings() {
        let mut bindings = TermBindings::default();
        bindings.insert(Symbol::mk("From"), v_int(10));
        let result = query_with_bindings(
            v_list(&[v_sym("edge"), var("from"), var("To")]),
            vec![v_list(&[v_sym("edge"), v_int(10), v_int(11)])],
            vec![],
            bindings,
        )
        .unwrap();
        assert_eq!(
            result,
            v_list(&[v_map(&[
                (v_sym("from"), v_int(10)),
                (v_sym("To"), v_int(11)),
            ])])
        );

        let mut bindings = TermBindings::default();
        bindings.insert(Symbol::mk("From"), v_int(12));
        let result = query_with_bindings(
            v_list(&[v_sym("edge"), var("from")]),
            vec![v_list(&[v_sym("edge"), v_int(10)])],
            vec![],
            bindings,
        )
        .unwrap();
        assert_eq!(result, v_list(&[]));
    }

    #[test]
    fn term_query_matches_map_values_by_exact_key_set() {
        let result = query(
            v_map(&[(v_sym("edge"), v_list(&[var("From"), var("To")]))]),
            vec![v_map(&[(v_sym("EDGE"), v_list(&[v_int(1), v_int(2)]))])],
            vec![],
        )
        .unwrap();
        let bindings = result.as_list().unwrap()[0].as_map().unwrap();
        assert_eq!(bindings.get(&v_sym("from")).unwrap(), v_int(1));
        assert_eq!(bindings.get(&v_sym("to")).unwrap(), v_int(2));

        let pattern = v_map(&[(v_sym("edge"), var("X"))]);
        let datum = v_map(&[(v_sym("edge"), v_int(1)), (v_sym("extra"), v_int(2))]);
        assert_eq!(query(pattern, vec![datum], vec![]).unwrap(), v_empty_list());
    }

    #[test]
    fn term_query_rejects_malformed_variable_marker() {
        let err = query(v_list(&[v_sym("var"), v_str("X")]), vec![v_int(1)], vec![]).unwrap_err();
        assert!(matches!(err, BfErr::ErrValue(error) if error.err_type() == E_INVARG));
    }

    #[test]
    fn term_substitute_replaces_nested_variables() {
        let mut bindings = TermBindings::default();
        bindings.insert(Symbol::mk("Target"), v_int(123));
        let template = v_list(&[
            v_str("property_write"),
            var("target"),
            v_map(&[(v_sym("name"), var("Target"))]),
        ]);
        let (result, changed) =
            term_substitute_inner(&template, &bindings, &TermOptions::default(), 0).unwrap();
        assert!(changed);
        assert_eq!(
            result,
            v_list(&[
                v_str("property_write"),
                v_int(123),
                v_map(&[(v_sym("name"), v_int(123))])
            ])
        );
    }

    #[test]
    fn term_substitute_can_leave_unbound_variables() {
        let options = TermOptions {
            unbound: UnboundMode::Leave,
            ..TermOptions::default()
        };
        let template = v_list(&[v_int(1), var("Missing")]);
        let (result, changed) =
            term_substitute_inner(&template, &TermBindings::default(), &options, 0).unwrap();
        assert!(!changed);
        assert_eq!(result, template);
    }

    #[test]
    fn term_query_matches_facts_in_input_order() {
        let result = query(
            term("edge", &[v_int(1), var("To")]),
            vec![
                term("edge", &[v_int(1), v_int(2)]),
                term("edge", &[v_int(1), v_int(3)]),
                term("edge", &[v_int(2), v_int(4)]),
            ],
            vec![],
        )
        .unwrap();

        assert_eq!(
            result,
            v_list(&[
                v_map(&[(v_sym("To"), v_int(2))]),
                v_map(&[(v_sym("To"), v_int(3))])
            ])
        );
    }

    #[test]
    fn term_query_allows_recursive_positive_rules() {
        let reachable = |from: Var, to: Var| term("reachable", &[from, to]);
        let edge = |from: Var, to: Var| term("edge", &[from, to]);
        let facts = vec![
            edge(v_int(1), v_int(2)),
            edge(v_int(2), v_int(3)),
            edge(v_int(3), v_int(4)),
        ];
        let rules = vec![
            v_list(&[
                reachable(var("A"), var("B")),
                v_list(&[edge(var("A"), var("B"))]),
            ]),
            v_list(&[
                reachable(var("A"), var("B")),
                v_list(&[edge(var("A"), var("C")), reachable(var("C"), var("B"))]),
            ]),
        ];

        let result = query(reachable(v_int(1), var("Where")), facts, rules).unwrap();
        assert_eq!(
            result,
            v_list(&[
                v_map(&[(v_sym("Where"), v_int(2))]),
                v_map(&[(v_sym("Where"), v_int(3))]),
                v_map(&[(v_sym("Where"), v_int(4))]),
            ])
        );
    }

    #[test]
    fn term_query_dedupes_cyclic_recursive_solutions() {
        let reachable = |from: Var, to: Var| term("reachable", &[from, to]);
        let edge = |from: Var, to: Var| term("edge", &[from, to]);
        let facts = vec![edge(v_int(1), v_int(2)), edge(v_int(2), v_int(1))];
        let rules = vec![
            v_list(&[
                reachable(var("A"), var("B")),
                v_list(&[edge(var("A"), var("B"))]),
            ]),
            v_list(&[
                reachable(var("A"), var("B")),
                v_list(&[edge(var("A"), var("C")), reachable(var("C"), var("B"))]),
            ]),
        ];

        let result = query(reachable(v_int(1), var("Where")), facts, rules).unwrap();
        assert_eq!(
            result,
            v_list(&[
                v_map(&[(v_sym("Where"), v_int(2))]),
                v_map(&[(v_sym("Where"), v_int(1))]),
            ])
        );
    }

    #[test]
    fn term_query_rejects_unsafe_rules() {
        let rules = v_list(&[v_list(&[
            term("reachable", &[var("A"), var("B")]),
            v_list(&[term("edge", &[var("A"), var("C")])]),
        ])]);
        let err = parse_query_rules(&rules).unwrap_err();
        assert!(matches!(err, BfErr::ErrValue(error) if error.err_type() == E_INVARG));
    }

    #[test]
    fn term_query_rejects_negative_body_terms() {
        let rules = v_list(&[v_list(&[
            term("reachable", &[var("A"), var("B")]),
            v_list(&[term("not", &[term("blocked", &[var("A"), var("B")])])]),
        ])]);
        let err = parse_query_rules(&rules).unwrap_err();
        assert!(matches!(err, BfErr::ErrValue(error) if error.err_type() == E_INVARG));
    }
}
