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
    current_task_scheduler_client, with_current_transaction, with_loader_interface,
};
use crate::vm::builtins::BfRet::Ret;
use crate::vm::builtins::{
    BfCallState, BfErr, BfRet, BuiltinFunction, DiagnosticOutput, parse_diagnostic_options,
    world_state_bf_err,
};
use moor_common::builtins::offset_for_builtin;
use moor_common::model::{ObjectKind, obj_flags_string, prop_flags_string};
use moor_compiler::{
    CompileOptions, DiagnosticRenderOptions, ObjDefParseError, ObjFileContext, format_compile_error,
};
use moor_objdef::{
    ChangelistChange, ChangelistObject, ConflictEntity, ConflictMode, Constants, Entity,
    ObjDefLoaderOptions, ObjDefSource, ObjdefLoaderError,
};
use moor_var::{
    E_ARGS, E_INVARG, E_TYPE, Sequence, Symbol, Var, Variant, v_empty_map, v_list, v_map, v_obj,
    v_str, v_sym,
};
use std::{
    collections::{BTreeSet, HashMap},
    sync::LazyLock,
};

static OBJECT_FLAGS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("object_flags"));
static BUILTIN_PROPS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("builtin_props"));
static PARENTAGE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("parentage"));
static PROPERTY_DEF_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("property_def"));
static PROPERTY_VALUE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("property_value"));
static PROPERTY_FLAG_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("property_flag"));
static VERB_DEF_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("verb_def"));
static VERB_PROGRAM_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("verb_program"));
static DRY_RUN_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("dry_run"));
static CONFLICT_MODE_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("conflict_mode"));
static CONSTANTS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("constants"));
static OVERRIDES_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("overrides"));
static RETURN_CONFLICTS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("return_conflicts"));
static DIAGNOSTICS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("diagnostics"));
static LOCAL_CONSTANTS_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("local_constants"));
static BASE_MANIFEST_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("base_manifest"));
static BASE_METADATA_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("base_metadata"));
static BASE_METADATA_PREFIX_SYM: LazyLock<Symbol> =
    LazyLock::new(|| Symbol::mk("base_metadata_prefix"));
static INCLUDE_UNCHANGED_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("include_unchanged"));
static CLOBBER_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("clobber"));
static SKIP_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("skip"));
static DETECT_SYM: LazyLock<Symbol> = LazyLock::new(|| Symbol::mk("detect"));

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
        for (key, value) in options_map.iter() {
            let key_sym = key.as_symbol().map_err(BfErr::ErrValue)?;
            if key_sym == *CONSTANTS_SYM {
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

    // Use the task scheduler client to request the dump from the scheduler.
    // The scheduler already returns string Vars, so there is no reason to bounce
    // through an intermediate Vec<String> here.
    let lines = current_task_scheduler_client()
        .dump_object(obj, use_constants)
        .map_err(|e| BfErr::ErrValue(E_INVARG.msg(format!("Failed to dump object: {e}"))))?;
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

    let source = match bf_args.args[0].variant() {
        Variant::Str(_) => bf_args.args[0].as_string().unwrap().to_string(),
        Variant::List(lines_list) => {
            let mut lines = Vec::new();
            for line_val in lines_list.iter() {
                let Some(line_str) = line_val.as_string() else {
                    return Err(BfErr::ErrValue(E_TYPE.msg(
                        "parse_objdef_constants() requires a string or list of strings",
                    )));
                };
                lines.push(line_str.to_string());
            }
            lines.join("\n")
        }
        _ => {
            return Err(BfErr::ErrValue(E_TYPE.msg(
                "parse_objdef_constants() requires a string or list of strings",
            )));
        }
    };

    let mut context = ObjFileContext::new();
    let compile_options = CompileOptions::default();
    if let Err(err) =
        moor_compiler::compile_object_definitions(&source, &compile_options, &mut context)
    {
        let diagnostic_options = DiagnosticRenderOptions::default();
        match err {
            ObjDefParseError::ParseError(compile_error) => {
                let formatted =
                    format_compile_error(&compile_error, Some(&source), diagnostic_options);
                return Err(BfErr::ErrValue(E_INVARG.msg(formatted.join("\n"))));
            }
            ObjDefParseError::VerbCompileError(compile_error, verb_source) => {
                let formatted = format_compile_error(
                    &compile_error,
                    Some(verb_source.as_str()),
                    diagnostic_options,
                );
                return Err(BfErr::ErrValue(E_INVARG.msg(formatted.join("\n"))));
            }
            other => {
                return Err(BfErr::ErrValue(E_INVARG.msg(other.to_string())));
            }
        }
    }

    let constants = context
        .constants()
        .iter()
        .map(|(name, value)| (v_sym(*name), value.clone()))
        .collect::<Vec<_>>();

    Ok(Ret(v_map(&constants)))
}

fn objdef_text_from_value(value: &Var, builtin_name: &str) -> Result<String, BfErr> {
    match value.variant() {
        Variant::Str(_) => Ok(value.as_string().unwrap().to_string()),
        Variant::List(lines) => {
            let mut output = Vec::with_capacity(lines.len());
            for line in lines.iter() {
                let Some(line) = line.as_string() else {
                    return Err(BfErr::ErrValue(E_TYPE.msg(format!(
                        "{builtin_name}() requires strings or lists of strings"
                    ))));
                };
                output.push(line.to_string());
            }
            Ok(output.join("\n"))
        }
        _ => Err(BfErr::ErrValue(E_TYPE.msg(format!(
            "{builtin_name}() requires strings or lists of strings"
        )))),
    }
}

fn objdef_sources_from_value(value: &Var, builtin_name: &str) -> Result<Vec<ObjDefSource>, BfErr> {
    let Some(definitions) = value.as_list() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg(format!("{builtin_name}() first argument must be a list")),
        ));
    };

    let mut sources = Vec::with_capacity(definitions.len());
    for (idx, definition) in definitions.iter().enumerate() {
        let contents = objdef_text_from_value(&definition, builtin_name)?;
        sources.push(ObjDefSource::new(
            format!("<definition:{}>", idx + 1),
            contents,
        ));
    }
    Ok(sources)
}

/// Convert a MOO entity specification to an internal Entity enum.
/// Entity specs can be:
/// - `object_flags / "object_flags"
/// - `builtin_props / "builtin_props"
/// - `parentage / "parentage"
/// - {`property_def, propname} / {"property_def", propname}
/// - {`property_value, propname} / {"property_value", propname}
/// - {`property_flag, propname} / {"property_flag", propname}
/// - {`verb_def, {name1, name2, ...}} / {"verb_def", {name1, name2, ...}}
/// - {`verb_program, {name1, name2, ...}} / {"verb_program", {name1, name2, ...}}
fn moo_entity_to_entity(_bf_args: &mut BfCallState<'_>, moo_entity: &Var) -> Result<Entity, BfErr> {
    match moo_entity.variant() {
        Variant::Str(_) | Variant::Sym(_) => {
            let sym = moo_entity.as_symbol().map_err(BfErr::ErrValue)?;
            if sym == *OBJECT_FLAGS_SYM {
                Ok(Entity::ObjectFlags)
            } else if sym == *BUILTIN_PROPS_SYM {
                Ok(Entity::BuiltinProps)
            } else if sym == *PARENTAGE_SYM {
                Ok(Entity::Parentage)
            } else {
                Err(BfErr::ErrValue(E_INVARG.msg("Invalid entity type")))
            }
        }
        Variant::List(l) => {
            if l.len() != 2 {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("Entity specification must be {type, specifier}"),
                ));
            }
            let entity_type = l.index(0).map_err(BfErr::ErrValue)?;
            let specifier = l.index(1).map_err(BfErr::ErrValue)?;

            let type_sym = entity_type.as_symbol().map_err(BfErr::ErrValue)?;

            if type_sym == *PROPERTY_DEF_SYM {
                let prop_name = specifier.as_symbol().map_err(BfErr::ErrValue)?;
                Ok(Entity::PropertyDef(prop_name))
            } else if type_sym == *PROPERTY_VALUE_SYM {
                let prop_name = specifier.as_symbol().map_err(BfErr::ErrValue)?;
                Ok(Entity::PropertyValue(prop_name))
            } else if type_sym == *PROPERTY_FLAG_SYM {
                let prop_name = specifier.as_symbol().map_err(BfErr::ErrValue)?;
                Ok(Entity::PropertyFlag(prop_name))
            } else if type_sym == *VERB_DEF_SYM {
                let Some(names_list) = specifier.as_list() else {
                    return Err(BfErr::ErrValue(E_TYPE.msg("Verb names must be a list")));
                };
                let mut names = Vec::new();
                for name_var in names_list.iter() {
                    let name = name_var.as_symbol().map_err(BfErr::ErrValue)?;
                    names.push(name);
                }
                Ok(Entity::VerbDef(names))
            } else if type_sym == *VERB_PROGRAM_SYM {
                let Some(names_list) = specifier.as_list() else {
                    return Err(BfErr::ErrValue(E_TYPE.msg("Verb names must be a list")));
                };
                let mut names = Vec::new();
                for name_var in names_list.iter() {
                    let name = name_var.as_symbol().map_err(BfErr::ErrValue)?;
                    names.push(name);
                }
                Ok(Entity::VerbProgram(names))
            } else {
                Err(BfErr::ErrValue(E_INVARG.msg("Invalid entity type")))
            }
        }
        _ => Err(BfErr::ErrValue(
            E_TYPE.msg("Entity must be string/symbol or {type, specifier}"),
        )),
    }
}

/// Convert an internal ConflictEntity back to MOO format for return values.
fn conflict_entity_to_moo(bf_args: &mut BfCallState<'_>, conflict: &ConflictEntity) -> Var {
    let use_symbols = bf_args.config.use_symbols_in_builtins && bf_args.config.symbol_type;
    let sym_or_str = |sym: Symbol| {
        if use_symbols {
            v_sym(sym)
        } else {
            v_str(&sym.as_string())
        }
    };

    match conflict {
        ConflictEntity::ObjectFlags(flags) => v_list(&[
            sym_or_str(*OBJECT_FLAGS_SYM),
            v_str(&obj_flags_string(*flags)),
        ]),
        ConflictEntity::BuiltinProps(prop, value) => {
            v_list(&[sym_or_str(*BUILTIN_PROPS_SYM), v_sym(*prop), value.clone()])
        }
        ConflictEntity::Parentage(parent) => v_list(&[sym_or_str(*PARENTAGE_SYM), v_obj(*parent)]),
        ConflictEntity::PropertyDef(prop, _def) => {
            v_list(&[sym_or_str(*PROPERTY_DEF_SYM), v_sym(*prop)])
        }
        ConflictEntity::PropertyValue(prop, value) => {
            v_list(&[sym_or_str(*PROPERTY_VALUE_SYM), v_sym(*prop), value.clone()])
        }
        ConflictEntity::PropertyFlag(prop, flags) => v_list(&[
            sym_or_str(*PROPERTY_FLAG_SYM),
            v_sym(*prop),
            v_str(&prop_flags_string(*flags)),
        ]),
        ConflictEntity::VerbDef(names, _def) => {
            let name_vars = names.iter().map(|n| v_sym(*n)).collect::<Vec<_>>();
            v_list(&[sym_or_str(*VERB_DEF_SYM), v_list(&name_vars)])
        }
        ConflictEntity::VerbProgram(names, _program) => {
            let name_vars = names.iter().map(|n| v_sym(*n)).collect::<Vec<_>>();
            v_list(&[sym_or_str(*VERB_PROGRAM_SYM), v_list(&name_vars)])
        }
    }
}

/// Parse object kind specification from the third argument
fn parse_object_kind_spec(
    bf_args: &BfCallState<'_>,
    arg: &Var,
) -> Result<Option<ObjectKind>, BfErr> {
    match arg.variant() {
        Variant::Int(0) => Ok(Some(ObjectKind::NextObjid)),
        Variant::Int(1) => {
            if !bf_args.config.anonymous_objects {
                return Err(BfErr::ErrValue(E_INVARG.msg(
                    "Anonymous objects not available (anonymous_objects feature is disabled)",
                )));
            }
            Ok(Some(ObjectKind::Anonymous))
        }
        Variant::Int(2) => {
            if !bf_args.config.use_uuobjids {
                return Err(BfErr::ErrValue(
                    E_INVARG.msg("UUID objects not available (use_uuobjids is false)"),
                ));
            }
            Ok(Some(ObjectKind::UuObjId))
        }
        Variant::Int(_) => Err(BfErr::ErrValue(E_INVARG.msg(
            "load_object() object_spec must be 0 (NextObjid), 1 (Anonymous), 2 (UuObjId), or an object ID",
        ))),
        Variant::Obj(obj) => Ok(Some(ObjectKind::Objid(obj))),
        _ => Err(BfErr::ErrValue(E_TYPE.msg(
            "load_object() third argument must be an integer (0, 1, 2) or an object ID",
        ))),
    }
}

/// Parse a single override/removal pair: {obj, entity}
fn parse_obj_entity_pair(
    bf_args: &mut BfCallState<'_>,
    pair: &Var,
    pair_type: &str,
) -> Result<(moor_var::Obj, Entity), BfErr> {
    let Some(pair_list) = pair.as_list() else {
        return Err(BfErr::ErrValue(E_TYPE.msg(format!(
            "{pair_type} must be a list of {{obj, entity}} pairs"
        ))));
    };

    if pair_list.len() != 2 {
        return Err(BfErr::ErrValue(E_ARGS.msg(format!(
            "{pair_type} pairs must have exactly 2 elements: {{obj, entity}}"
        ))));
    }

    let obj_var = pair_list.index(0).map_err(BfErr::ErrValue)?;
    let Some(obj) = obj_var.as_object() else {
        return Err(BfErr::ErrValue(
            E_TYPE.msg(format!("{pair_type} object must be an object")),
        ));
    };

    let entity_var = pair_list.index(1).map_err(BfErr::ErrValue)?;
    let entity = moo_entity_to_entity(bf_args, &entity_var)?;

    Ok((obj, entity))
}

/// Parse conflict mode from symbol
fn parse_conflict_mode(mode_sym: Symbol) -> Result<(ConflictMode, bool, bool), BfErr> {
    if mode_sym == *CLOBBER_SYM {
        Ok((ConflictMode::Clobber, false, false))
    } else if mode_sym == *SKIP_SYM {
        Ok((ConflictMode::Skip, false, false))
    } else if mode_sym == *DETECT_SYM {
        // "detect" mode is essentially dry_run + return_conflicts
        Ok((ConflictMode::Clobber, true, true))
    } else {
        Err(BfErr::ErrValue(
            E_INVARG.msg("conflict_mode must be `clobber, `skip, or `detect"),
        ))
    }
}

/// Format load result for return to MOO code
fn format_load_result(
    bf_args: &mut BfCallState<'_>,
    result: &moor_objdef::ObjDefLoaderResults,
    return_conflicts: bool,
) -> Result<Var, BfErr> {
    if !return_conflicts {
        // Return simple object ID (backward compatibility)
        if result.loaded_objects.is_empty() {
            return Err(BfErr::ErrValue(E_INVARG.msg("No objects were loaded")));
        }
        return Ok(v_obj(result.loaded_objects[0]));
    }

    // Return detailed result: {success, conflicts, loaded_objects}
    let conflicts: Vec<_> = result
        .conflicts
        .iter()
        .map(|(obj, conflict)| v_list(&[v_obj(*obj), conflict_entity_to_moo(bf_args, conflict)]))
        .collect();

    let loaded_objects: Vec<_> = result
        .loaded_objects
        .iter()
        .map(|obj| v_obj(*obj))
        .collect();

    Ok(v_list(&[
        bf_args.v_bool(result.commit),
        v_list(&conflicts),
        v_list(&loaded_objects),
    ]))
}

fn parse_changelist_options(
    bf_args: &mut BfCallState<'_>,
    options_value: Option<&Var>,
) -> Result<moor_objdef::ChangelistOptions, BfErr> {
    let Some(options_value) = options_value else {
        return Ok(moor_objdef::ChangelistOptions::default());
    };
    let options_map = bf_args.map_or_alist_to_map(options_value)?;
    let mut options = moor_objdef::ChangelistOptions {
        base_metadata_prefix: "base_".to_string(),
        ..moor_objdef::ChangelistOptions::default()
    };

    for (key, value) in options_map.iter() {
        let key_sym = key.as_symbol().map_err(BfErr::ErrValue)?;

        if key_sym == *CONSTANTS_SYM {
            options.constants = Some(Constants::Map(bf_args.map_or_alist_to_map(&value)?));
            continue;
        }

        if key_sym == *LOCAL_CONSTANTS_SYM {
            let constants = bf_args.map_or_alist_to_map(&value)?;
            let mut local_constants = HashMap::new();
            for (constant, value) in constants.iter() {
                let constant = constant.as_symbol().map_err(BfErr::ErrValue)?;
                local_constants.insert(constant, value.clone());
            }
            options.local_constants = local_constants;
            continue;
        }

        if key_sym == *BASE_MANIFEST_SYM {
            let Some(objects) = value.as_list() else {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("base_manifest must be a list of objects"),
                ));
            };
            let mut base_manifest = BTreeSet::new();
            for object in objects.iter() {
                let Some(object) = object.as_object() else {
                    return Err(BfErr::ErrValue(
                        E_TYPE.msg("base_manifest must be a list of objects"),
                    ));
                };
                base_manifest.insert(object);
            }
            options.base_manifest = base_manifest;
            continue;
        }

        if key_sym == *BASE_METADATA_SYM {
            options.base_metadata = value.is_true();
            continue;
        }

        if key_sym == *BASE_METADATA_PREFIX_SYM {
            let Some(prefix) = value.as_string() else {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("base_metadata_prefix must be a string"),
                ));
            };
            options.base_metadata_prefix = prefix.to_string();
            continue;
        }

        if key_sym == *INCLUDE_UNCHANGED_SYM {
            options.include_unchanged = value.is_true();
            continue;
        }

        return Err(BfErr::ErrValue(E_INVARG.with_msg(|| {
            format!("unknown objdef_changelist() option: {key_sym}")
        })));
    }

    Ok(options)
}

fn changelist_change_to_moo(change: &ChangelistChange) -> Var {
    let mut pairs = vec![
        (v_str("key"), v_list(&change.key)),
        (v_str("kind"), v_str(change.kind)),
        (v_str("object"), v_obj(change.object)),
        (v_str("automatic"), v_bool_from(change.automatic)),
        (v_str("conflict"), v_bool_from(change.conflict)),
    ];
    if let Some(name) = change.name {
        pairs.push((v_str("name"), v_str(&name.as_string())));
    }
    if let Some(base_hash) = &change.base_hash {
        pairs.push((v_str("base_hash"), v_str(base_hash)));
    }
    if let Some(local_hash) = &change.local_hash {
        pairs.push((v_str("local_hash"), v_str(local_hash)));
    }
    if let Some(incoming_hash) = &change.incoming_hash {
        pairs.push((v_str("incoming_hash"), v_str(incoming_hash)));
    }
    v_map(&pairs)
}

fn changelist_object_to_moo(object: &ChangelistObject) -> Var {
    let mut pairs = vec![
        (v_str("object"), v_obj(object.object)),
        (v_str("status"), v_str(object.status.as_str())),
        (v_str("automatic"), v_bool_from(object.automatic)),
        (
            v_str("changes"),
            v_list(
                &object
                    .changes
                    .iter()
                    .map(changelist_change_to_moo)
                    .collect::<Vec<_>>(),
            ),
        ),
    ];
    if let Some(label) = &object.label {
        pairs.push((v_str("label"), v_str(label)));
    }
    v_map(&pairs)
}

fn v_bool_from(value: bool) -> Var {
    moor_var::v_bool(value)
}

fn changelist_to_moo(changelist: &moor_objdef::ObjDefChangelist) -> Var {
    let objects = changelist
        .objects
        .iter()
        .map(changelist_object_to_moo)
        .collect::<Vec<_>>();
    let conflicts = changelist
        .conflicts
        .iter()
        .map(changelist_change_to_moo)
        .collect::<Vec<_>>();
    let diagnostics = changelist
        .diagnostics
        .iter()
        .map(|diagnostic| {
            let mut pairs = vec![
                (v_str("kind"), v_str(diagnostic.kind)),
                (v_str("message"), v_str(&diagnostic.message)),
            ];
            if let Some(object) = diagnostic.object {
                pairs.push((v_str("object"), v_obj(object)));
            }
            if let Some(constant) = diagnostic.constant {
                pairs.push((v_str("constant"), v_str(&constant.as_string())));
            }
            v_map(&pairs)
        })
        .collect::<Vec<_>>();

    v_map(&[
        (v_str("ok"), v_bool_from(changelist.ok)),
        (v_str("objects"), v_list(&objects)),
        (v_str("conflicts"), v_list(&conflicts)),
        (v_str("diagnostics"), v_list(&diagnostics)),
    ])
}

fn invalid_objdef_changelist_to_moo(error: ObjdefLoaderError) -> Var {
    v_map(&[
        (v_str("ok"), v_bool_from(false)),
        (v_str("objects"), v_list(&[])),
        (v_str("conflicts"), v_list(&[])),
        (
            v_str("diagnostics"),
            v_list(&[v_map(&[
                (v_str("kind"), v_str("invalid")),
                (v_str("source"), v_str(error.source())),
                (v_str("message"), v_str(&error.to_string())),
            ])]),
        ),
    ])
}

/// Usage: `map objdef_changelist(list definitions [, map options])`
/// Returns a read-only summary of create, patch, unsafe, conflict, and delete-candidate changes.
/// Wizard-only.
fn bf_objdef_changelist(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() || bf_args.args.len() > 2 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("objdef_changelist() requires 1 to 2 arguments"),
        ));
    }

    let sources = objdef_sources_from_value(&bf_args.args[0], "objdef_changelist")?;
    let options_value = bf_args.args.iter_ref().nth(1).cloned();
    let options = parse_changelist_options(bf_args, options_value.as_ref())?;

    bf_args.require_wizard_or_builtin_call()?;

    let compile_options = bf_args.config.compile_options();
    let permissions = bf_args.task_permissions();
    let changelist_result = with_current_transaction(|world_state| {
        moor_objdef::analyze_objdef_changelist(
            world_state,
            &permissions,
            &compile_options,
            sources,
            options,
        )
    });

    let changelist = match changelist_result {
        Ok(changelist) => changelist_to_moo(&changelist),
        Err(error) => invalid_objdef_changelist_to_moo(error),
    };

    Ok(Ret(changelist))
}

/// Usage: `obj|list load_object(list object_lines [, map options] [, obj|int object_spec])`
/// Creates an object from objdef format. object_spec: 0=next ID, 1=anonymous, 2=UUID,
/// #N=specific ID, omitted=use objdef's ID. Options: `dry_run, `conflict_mode, `constants.
/// Wizard-only.
fn bf_load_object(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() || bf_args.args.len() > 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("load_object() requires 1-3 arguments"),
        ));
    }

    let Some(lines_list) = bf_args.args[0].as_list() else {
        return Err(BfErr::ErrValue(E_TYPE.msg(
            "load_object() requires a list of strings as the first argument",
        )));
    };

    // Convert list of values to list of strings, joining with newlines
    let mut lines = Vec::new();
    for line_val in lines_list.iter() {
        let Some(line_str) = line_val.as_string() else {
            return Err(BfErr::ErrValue(
                E_TYPE.msg("load_object() requires a list of strings"),
            ));
        };
        lines.push(line_str.to_string());
    }
    let object_definition = lines.join("\n");

    // Parse options map (second argument)
    let options_map = if bf_args.args.len() >= 2 {
        bf_args.map_or_alist_to_map(&bf_args.args[1])?
    } else {
        v_empty_map().as_map().unwrap().clone()
    };

    // Parse the object specification (third argument)
    let object_kind = if bf_args.args.len() == 3 {
        parse_object_kind_spec(bf_args, &bf_args.args[2])?
    } else {
        None
    };

    // Extract options from the map using symbol constants
    let mut dry_run = false;
    let mut conflict_mode = ConflictMode::Clobber;
    let mut constants: Option<Constants> = None;
    let mut overrides = Vec::new();
    let mut return_conflicts = false;
    let mut diagnostic_options = DiagnosticRenderOptions::default();

    for (key, value) in options_map.iter() {
        let key_sym = key.as_symbol().map_err(BfErr::ErrValue)?;

        if key_sym == *DRY_RUN_SYM {
            dry_run = value.is_true();
            continue;
        }

        if key_sym == *CONFLICT_MODE_SYM {
            let mode_sym = value.as_symbol().map_err(BfErr::ErrValue)?;
            let (mode, dr, rc) = parse_conflict_mode(mode_sym)?;
            conflict_mode = mode;
            if dr {
                dry_run = true;
            }
            if rc {
                return_conflicts = true;
            }
            continue;
        }

        if key_sym == *CONSTANTS_SYM {
            let const_map = bf_args.map_or_alist_to_map(&value)?;
            constants = Some(Constants::Map(const_map));
            continue;
        }

        if key_sym == *OVERRIDES_SYM {
            let Some(overrides_list) = value.as_list() else {
                return Err(BfErr::ErrValue(
                    E_TYPE.msg("overrides must be a list of {obj, entity} pairs"),
                ));
            };
            for override_pair in overrides_list.iter() {
                let (obj, entity) = parse_obj_entity_pair(bf_args, &override_pair, "overrides")?;
                overrides.push((obj, entity));
            }
            continue;
        }

        if key_sym == *RETURN_CONFLICTS_SYM {
            return_conflicts = value.is_true();
            continue;
        }

        if key_sym == *DIAGNOSTICS_SYM {
            // Parse diagnostic options from a map with "verbosity" and "output_mode" fields
            let Some(diag_map) = value.as_map() else {
                return Err(BfErr::ErrValue(E_TYPE.msg("diagnostics must be a map")));
            };

            let mut verbosity = None;
            let mut output_mode = None;

            for (k, v) in diag_map.iter() {
                let Some(key_str) = k.as_string() else {
                    continue;
                };

                if key_str == "verbosity" {
                    verbosity = v.as_integer();
                } else if key_str == "output_mode" {
                    output_mode = v.as_integer();
                }
            }

            let diagnostic_output = parse_diagnostic_options(verbosity, output_mode)?;
            // obj_load only uses formatted output
            diagnostic_options = match diagnostic_output {
                DiagnosticOutput::Formatted(options) => options,
                DiagnosticOutput::Structured => DiagnosticRenderOptions::default(),
            };
            continue;
        }
    }

    // Check permissions: wizard only (object creation with arbitrary properties/verbs)
    bf_args.require_wizard_or_builtin_call()?;

    // Create options object for the loader
    let loader_options = ObjDefLoaderOptions {
        dry_run,
        conflict_mode,
        object_kind,
        constants: constants.clone(),
        overrides,
        validate_parent_changes: true, // Individual loads should validate parent changes
    };

    // Get the compile options from the config
    let compile_options = bf_args.config.compile_options();

    let loader_result: Result<_, ObjdefLoaderError> = with_loader_interface(|loader| {
        let mut object_loader = moor_objdef::ObjectDefinitionLoader::new(loader);
        object_loader.load_single_object(&object_definition, compile_options, loader_options)
    });

    let result = match loader_result {
        Ok(results) => results,
        Err(e) => {
            if let Some((_, compile_error, verb_source)) = e.compile_error() {
                let source_to_use = if !verb_source.is_empty() {
                    Some(verb_source)
                } else {
                    Some(object_definition.as_str())
                };
                let formatted =
                    format_compile_error(compile_error, source_to_use, diagnostic_options);
                let message = formatted.join("\n");
                return Err(BfErr::ErrValue(E_INVARG.msg(message)));
            }

            return Err(BfErr::ErrValue(
                E_INVARG.msg(format!("Failed to load object: {e}")),
            ));
        }
    };

    // Format and return the result
    let return_value = format_load_result(bf_args, &result, return_conflicts)?;
    Ok(Ret(return_value))
}

/// Usage: `obj reload_object(list object_lines [, map constants] [, obj target])`
/// Replaces an existing object with a new definition from objdef format. Properties
/// and verbs not in the new definition are deleted. Wizard-only.
/// If target is omitted, uses the object ID encoded in the objdef definition.
/// constants may be a map or alist of constant substitutions.
fn bf_reload_object(bf_args: &mut BfCallState<'_>) -> Result<BfRet, BfErr> {
    if bf_args.args.is_empty() || bf_args.args.len() > 3 {
        return Err(BfErr::ErrValue(
            E_ARGS.msg("reload_object() requires 1-3 arguments"),
        ));
    }

    let Some(lines_list) = bf_args.args[0].as_list() else {
        return Err(BfErr::ErrValue(E_TYPE.msg(
            "reload_object() requires a list of strings as the first argument",
        )));
    };

    // Convert list of values to list of strings, joining with newlines
    let mut lines = Vec::new();
    for line_val in lines_list.iter() {
        let Some(line_str) = line_val.as_string() else {
            return Err(BfErr::ErrValue(
                E_TYPE.msg("reload_object() requires a list of strings"),
            ));
        };
        lines.push(line_str.to_string());
    }
    let object_definition = lines.join("\n");

    // Parse constants map (second argument)
    let constants = if bf_args.args.len() >= 2 {
        let Ok(const_map) = bf_args.map_or_alist_to_map(&bf_args.args[1]) else {
            return Err(BfErr::ErrValue(E_TYPE.with_msg( ||
                format!("invalid second argument for reload_object(); was {}, should be map or alist of constant substitutions",
                         bf_args.args[1].type_code().to_literal())
            )));
        };
        Some(Constants::Map(const_map))
    } else {
        None
    };

    // Parse target object (third argument)
    let target_obj = if bf_args.args.len() == 3 {
        let Some(obj) = bf_args.args[2].as_object() else {
            return Err(BfErr::ErrValue(
                E_TYPE.msg("reload_object() target must be an object"),
            ));
        };

        // Verify the target object exists
        if !with_current_transaction(|world_state| world_state.valid(&obj))
            .map_err(world_state_bf_err)?
        {
            return Err(BfErr::ErrValue(
                E_INVARG.msg("reload_object() target object does not exist"),
            ));
        }

        Some(obj)
    } else {
        None
    };

    // Check permissions: wizard only
    bf_args.require_wizard_or_builtin_call()?;

    // Use the current task's transaction via loader interface
    let result = match with_loader_interface(|loader| {
        let mut object_loader = moor_objdef::ObjectDefinitionLoader::new(loader);

        // Reload the object with the provided constants and target
        object_loader.reload_single_object(&object_definition, constants, target_obj)
    }) {
        Ok(result) => result,
        Err(e) => {
            return Err(BfErr::ErrValue(
                E_INVARG.with_msg(|| format!("failed to load object: {e}")),
            ));
        }
    };

    // Return the loaded object ID (should be exactly one)
    if result.loaded_objects.is_empty() {
        return Err(BfErr::ErrValue(E_INVARG.msg("No objects were loaded")));
    }

    Ok(Ret(v_obj(result.loaded_objects[0])))
}

pub(crate) fn register_bf_obj_load(builtins: &mut [BuiltinFunction]) {
    builtins[offset_for_builtin("dump_object")] = bf_dump_object;
    builtins[offset_for_builtin("load_object")] = bf_load_object;
    builtins[offset_for_builtin("reload_object")] = bf_reload_object;
    builtins[offset_for_builtin("parse_objdef_constants")] = bf_parse_objdef_constants;
    builtins[offset_for_builtin("objdef_changelist")] = bf_objdef_changelist;
}
