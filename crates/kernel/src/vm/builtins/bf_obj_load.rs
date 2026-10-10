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

use crate::task_context::{
    with_current_transaction, with_current_transaction_mut, with_loader_interface,
};
use crate::vm::builtins::BfRet::Ret;
use crate::vm::builtins::{BfCallState, BfErr, BfRet, BuiltinFunction, world_state_bf_err};
use moor_common::builtins::offset_for_builtin;
use moor_common::model::ObjectKind;
use moor_compiler::{DiagnosticRenderOptions, format_compile_error};
use moor_objdef::{Constants, ObjDefLoaderOptions};
use moor_var::{E_ARGS, E_INVARG, E_TYPE, Symbol, Var, Variant, v_list, v_map, v_obj, v_sym};
use std::sync::LazyLock;

static CONSTANTS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("constants"));

/// Decode bounded source before copying or joining caller-owned strings.
fn source_text(value: &Var) -> Result<String, BfErr> {
    const MAX_BYTES: usize = 16 * 1024 * 1024;
    if let Some(text) = value.as_string() {
        if text.len() > MAX_BYTES {
            return Err(BfErr::ErrValue(
                moor_var::E_QUOTA.msg("objdef source exceeds 16 MiB"),
            ));
        }
        return Ok(text.to_owned());
    }
    let lines = value.as_list().ok_or_else(|| {
        BfErr::ErrValue(E_TYPE.msg("objdef source must be a string or list of strings"))
    })?;
    let mut size = 0usize;
    for line in lines.iter() {
        let text = line
            .as_string()
            .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("objdef source lines must be strings")))?;
        size = size.saturating_add(text.len()).saturating_add(1);
        if size > MAX_BYTES {
            return Err(BfErr::ErrValue(
                moor_var::E_QUOTA.msg("objdef source exceeds 16 MiB"),
            ));
        }
    }
    Ok(lines
        .iter()
        .map(|v| v.as_string().unwrap().to_owned())
        .collect::<Vec<_>>()
        .join("\n"))
}

fn option_keys(options: &moor_var::Map, allowed: &[&str]) -> Result<(), BfErr> {
    let mut seen = std::collections::HashSet::new();
    for (key, _) in options.iter() {
        let name = key.as_symbol().map_err(BfErr::ErrValue)?.to_folded_case();
        if !allowed.contains(&name.as_str()) || !seen.insert(name) {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("unknown or duplicate objdef option"),
            ));
        }
    }
    Ok(())
}

/// Usage: `list dump_object(obj object [, map options])`
/// Returns the object definition as a list of strings in objdef format.
/// Options: `constants -> true` to use symbolic constant names. Wizard-only.
fn bf_dump_object(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() || bf_args.args.len() > 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("dump_object() takes 1 or 2 arguments"),
        ));
    }

    let Some(obj) = bf_args.args[0].as_object() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg("dump_object() first argument must be an object"),
        ));
    };

    // Parse options map (second argument)
    let mut use_constants = false;
    if bf_args.args.len() == 2 {
        let options_map = bf_args.map_or_alist_to_map(&bf_args.args[1])?;
        option_keys(&options_map, &["constants"])?;
        for (key, value) in options_map.iter() {
            let key_sym = key.as_symbol().map_err(BfErr::ErrValue)?;
            if key_sym == *CONSTANTS_SYM {
                if !matches!(value.variant(), Variant::Bool(_) | Variant::Int(0 | 1)) {
                    return Err(BfErr::ErrValue(E_TYPE.msg("constants must be a boolean")));
                }
                use_constants = value.is_true();
            }
        }
    }

    // Check that object is valid
    if !with_current_transaction(|world_state| world_state.valid(&obj))
        .map_err(world_state_bf_err)?
    {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("dump_object() argument must be a valid object"),
        ));
    }

    // Check permissions: wizard only (object dumps can expose properties owned by others)
    bf_args.require_wizard_or_builtin_call()?;

    let permissions = bf_args.task_permissions();
    let lines = with_current_transaction(|world| {
        let definitions = moor_objdef::collect_object_definitions(world, &permissions, &[obj])
            .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))?;
        let names = if use_constants {
            moor_objdef::collect_transaction_index_names(world, &permissions)
                .map_err(world_state_bf_err)?
        } else {
            std::collections::HashMap::new()
        };
        moor_objdef::dump_object(&names, &definitions[0])
            .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))
    })?;
    Ok(Ret(v_list(&lines)))
}

/// Usage: `map parse_objdef_constants(str|list lines)`
/// Parses constants from objdef content and returns a map of constant -> value.
/// Raises E_INVARG with a formatted error if parsing or compilation fails.
fn bf_parse_objdef_constants(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 1 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("parse_objdef_constants() requires 1 argument"),
        ));
    }

    let source = source_text(&bf_args.args[0])?;

    let compile_options = bf_args.config.compile_options();
    let set = moor_objdef::ObjDefSet::parse_sources(
        &compile_options,
        None,
        None,
        [moor_objdef::ObjDefSource::new("<constants>", &source)],
    )
    .map_err(|e| BfErr::ErrValue(E_INVARG.msg(e.to_string())))?;

    let constants = set
        .constants()
        .iter()
        .map(|(name, value)| (v_sym(*name), value.clone()))
        .collect::<Vec<_>>();

    Ok(Ret(v_map(&constants)))
}

/// Decode the shared direct-import options, rejecting removed conflict controls.
fn direct_options(bf_args: &BfCallState<'_>, reload: bool) -> Result<ObjDefLoaderOptions, BfErr> {
    let mut result = ObjDefLoaderOptions {
        validate_parent_changes: true,
        ..Default::default()
    };
    if bf_args.args.len() == 1 {
        return Ok(result);
    }
    let options = bf_args.args[1]
        .as_map()
        .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("objdef options must be a map")))?;
    option_keys(
        options,
        if reload {
            &["constants", "target"]
        } else {
            &["constants", "target", "allocation"]
        },
    )?;
    let mut target = None;
    let mut allocation = "source".to_string();
    for (key, value) in options.iter() {
        match key
            .as_symbol()
            .map_err(BfErr::ErrValue)?
            .to_folded_case()
            .as_str()
        {
            "constants" => {
                result.constants = Some(Constants::Map(
                    value
                        .as_map()
                        .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("constants must be a map")))?
                        .clone(),
                ))
            }
            "target" => {
                target = Some(
                    value
                        .as_object()
                        .ok_or_else(|| BfErr::ErrValue(E_TYPE.msg("target must be an object")))?,
                )
            }
            "allocation" => {
                allocation = value.as_symbol().map_err(BfErr::ErrValue)?.to_folded_case()
            }
            _ => unreachable!(),
        }
    }
    if target.is_some() && allocation != "source" {
        return Err(BfErr::ErrValue(
            E_INVARG.msg("target requires source allocation"),
        ));
    }
    result.object_kind = match allocation.as_str() {
        "source" => target.map(ObjectKind::Objid),
        "next" => Some(ObjectKind::NextObjid),
        "anonymous" if bf_args.config.anonymous_objects => Some(ObjectKind::Anonymous),
        "uuid" if bf_args.config.use_uuobjids => Some(ObjectKind::UuObjId),
        _ => {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("unknown or unavailable allocation kind"),
            ));
        }
    };
    Ok(result)
}

/// Usage: `obj load_object(str|list source [, map options])`
/// Create one object or merge supplied declarations into an existing object.
/// Omitted attributes and members survive. Options: constants, target, allocation.
/// Requires wizard authority or an explicit builtin grant. Returns the affected object.
fn bf_load_object(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    direct_import(bf_args, false)
}

/// Usage: `obj reload_object(str|list source [, map options])`
/// Replace an existing object's definition. Absent local members and ordinary metadata are removed.
/// Options: constants, target. The target defaults to the source address and must exist.
/// Requires wizard authority or an explicit builtin grant. Returns the affected object.
fn bf_reload_object(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    direct_import(bf_args, true)
}

/// Apply in the current transaction; permanent failures after mutation abort the entire task.
fn direct_import(bf_args: &mut BfCallState<'_>, reload: bool) -> Result<BfRet, BfErr> {
    if !(1..=2).contains(&bf_args.args.len()) {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("direct objdef imports take 1 or 2 arguments"),
        ));
    }
    bf_args.require_wizard_or_builtin_call()?;
    let source = source_text(&bf_args.args[0])?;
    let options = direct_options(bf_args, reload)?;
    let compile_options = bf_args.config.compile_options();
    let mut mutation_started = false;
    let result = with_loader_interface(|loader| {
        let mut loader = moor_objdef::ObjectDefinitionLoader::new(loader);
        let result = if reload {
            let target = match options.object_kind {
                Some(ObjectKind::Objid(obj)) => Some(obj),
                _ => None,
            };
            loader.reload_single_object(&source, compile_options, options.constants, target)
        } else {
            loader.load_single_object(&source, compile_options, options)
        };
        mutation_started = loader.mutation_started();
        result
    });
    match result {
        Ok(result) => Ok(Ret(v_obj(result.loaded_objects[0]))),
        Err(error) if error.is_retry() => Err(BfErr::Rollback),
        Err(error) if mutation_started => {
            tracing::warn!(error = %error, "objdef import failed; rolling back task");
            Ok(BfRet::VmInstr(
                crate::vm::vm_host::ExecutionResult::TaskRollback(false),
            ))
        }
        Err(error) => {
            let message = if let Some((_, compile_error, verb_source)) = error.compile_error() {
                let diagnostic_source = if verb_source.is_empty() {
                    &source
                } else {
                    verb_source
                };
                format_compile_error(
                    compile_error,
                    Some(diagnostic_source),
                    DiagnosticRenderOptions::default(),
                )
                .join("\n")
            } else {
                error.to_string()
            };
            Err(BfErr::ErrValue(E_INVARG.msg(message)))
        }
    }
}

/// Usage: `map preview_objdef_changes(list sources, map request [, map choices])`
/// Compare scoped verb programs and validate edited choices without writing.
/// Requires wizard authority or a builtin grant, plus access to the selected definitions.
fn bf_preview_objdef_changes(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if !(2..=3).contains(&bf_args.args.len()) {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("preview_objdef_changes() takes 2 or 3 arguments"),
        ));
    }
    bf_args.require_wizard_or_builtin_call()?;
    with_current_transaction(|world| {
        moor_objdef::review::preview(
            world,
            &bf_args.task_permissions(),
            &bf_args.config.compile_options(),
            &bf_args.args[0],
            &bf_args.args[1],
            (bf_args.args.len() == 3).then(|| &bf_args.args[2]),
        )
    })
    .map(Ret)
    .map_err(|error| match error {
        moor_objdef::review::ReviewError::World(error) => world_state_bf_err(error),
        moor_objdef::review::ReviewError::Parse(error) if error.is_retry() => BfErr::Rollback,
        other => {
            BfErr::ErrValue(E_INVARG.with_msg_and_value(|| other.to_string(), other.diagnostic()))
        }
    })
}

/// Usage: `map apply_objdef_changes(sources, request, evidence, choices)`
/// Revalidate original review evidence and apply supported programs and baselines atomically.
/// Permanent failures after the first write abort the whole task, even inside a MOO catch.
fn bf_apply_objdef_changes(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.len() != 4 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("apply_objdef_changes() takes 4 arguments"),
        ));
    }
    bf_args.require_wizard_or_builtin_call()?;
    match with_current_transaction_mut(|world| {
        moor_objdef::review::apply(
            world,
            &bf_args.task_permissions(),
            &bf_args.config.compile_options(),
            &bf_args.args[0],
            &bf_args.args[1],
            &bf_args.args[2],
            &bf_args.args[3],
        )
    }) {
        Ok(receipt) => Ok(Ret(receipt)),
        Err(moor_objdef::review::ApplyError::Mutation(
            moor_common::model::WorldStateError::RollbackRetry,
        )) => Err(BfErr::Rollback),
        Err(moor_objdef::review::ApplyError::Mutation(error)) => {
            tracing::warn!(%error,"objdef apply failed; rolling back task");
            Ok(BfRet::VmInstr(
                crate::vm::vm_host::ExecutionResult::TaskRollback(false),
            ))
        }
        Err(moor_objdef::review::ApplyError::Review(moor_objdef::review::ReviewError::World(
            error,
        ))) => Err(world_state_bf_err(error)),
        Err(moor_objdef::review::ApplyError::Review(moor_objdef::review::ReviewError::Parse(
            error,
        ))) if error.is_retry() => Err(BfErr::Rollback),
        Err(error) => Err(BfErr::ErrValue(E_INVARG.msg(error.to_string()))),
    }
}

pub(crate) fn register_bf_obj_load(builtins: &mut [BuiltinFunction]) {
    builtins[offset_for_builtin("apply_objdef_changes")] = bf_apply_objdef_changes;
    builtins[offset_for_builtin("preview_objdef_changes")] = bf_preview_objdef_changes;
    builtins[offset_for_builtin("dump_object")] = bf_dump_object;
    builtins[offset_for_builtin("load_object")] = bf_load_object;
    builtins[offset_for_builtin("reload_object")] = bf_reload_object;
    builtins[offset_for_builtin("parse_objdef_constants")] = bf_parse_objdef_constants;
}
