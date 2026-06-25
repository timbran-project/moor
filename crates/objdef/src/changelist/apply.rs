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

use super::common::*;
use super::*;

/// Re-analyze and apply an objdef change set after validating caller-supplied resolutions.
pub fn apply_objdef_changes<I>(
    world_state: &dyn WorldState,
    loader: &mut dyn LoaderInterface,
    permissions: &TaskPermissions,
    compile_options: &CompileOptions,
    sources: I,
    options: ChangelistOptions,
    resolutions: Vec<(Vec<Var>, ApplyResolution)>,
) -> Result<ObjDefApplyResult, ObjdefLoaderError>
where
    I: IntoIterator<Item = ObjDefSource>,
{
    let sources = sources.into_iter().collect::<Vec<_>>();
    let changelist = analyze_preview_objdef_changes(
        world_state,
        permissions,
        compile_options,
        sources.clone(),
        options.clone(),
    )?;

    let diagnostics = validate_apply_resolutions(
        world_state,
        permissions,
        &changelist,
        resolutions.as_slice(),
    );
    if !diagnostics.is_empty() {
        return Ok(ObjDefApplyResult {
            ok: false,
            changelist,
            diagnostics,
            loader_results: None,
            deleted_objects: Vec::new(),
        });
    }

    let (overrides, delete_objects) = apply_plan(&changelist, resolutions.as_slice());
    let mut object_loader = ObjectDefinitionLoader::new(loader);
    let loader_results = object_loader.load_objdef_sources(
        compile_options.clone(),
        sources.clone(),
        ObjDefLoaderOptions {
            dry_run: false,
            conflict_mode: ConflictMode::Skip,
            object_kind: None,
            constants: options.constants.clone(),
            overrides,
            validate_parent_changes: true,
            remove_absent_entities: true,
            establish_base_metadata: false,
        },
    )?;

    if options.write_base_metadata {
        write_base_metadata(
            loader,
            compile_options,
            sources.as_slice(),
            &options,
            &changelist,
            resolutions.as_slice(),
        )?;
    }

    let mut deleted_objects = Vec::new();
    for obj in delete_objects {
        loader.recycle_object(&obj).map_err(|err| {
            ObjdefLoaderError::CouldNotCreateObject("<delete>".to_string(), obj, err)
        })?;
        deleted_objects.push(obj);
    }

    Ok(ObjDefApplyResult {
        ok: true,
        changelist,
        diagnostics: Vec::new(),
        loader_results: Some(loader_results),
        deleted_objects,
    })
}

fn validate_apply_resolutions(
    world_state: &dyn WorldState,
    permissions: &TaskPermissions,
    changelist: &ObjDefChangelist,
    resolutions: &[(Vec<Var>, ApplyResolution)],
) -> Vec<ChangelistDiagnostic> {
    let mut diagnostics = Vec::new();
    diagnostics.extend(changelist.diagnostics.iter().cloned());

    for object in &changelist.objects {
        if object.status == ChangelistStatus::UnsafeTarget {
            diagnostics.push(ChangelistDiagnostic {
                kind: "unsafe_target",
                object: Some(object.object),
                constant: None,
                message: format!("{} is not a proven safe update target", object.object),
            });
        }
    }

    let mut seen = BTreeSet::new();
    let mut supplied = BTreeMap::new();
    for (key, resolution) in resolutions {
        let key_string = key_debug(key);
        if !seen.insert(key_string.clone()) {
            diagnostics.push(ChangelistDiagnostic {
                kind: "duplicate_resolution",
                object: key_object(key),
                constant: None,
                message: format!("duplicate resolution for {key_string}"),
            });
            continue;
        }
        supplied.insert(key_string, (key, *resolution));
    }

    let required = required_resolution_keys(changelist);
    for change in &required {
        let key_string = key_debug(&change.key);
        let Some((_, resolution)) = supplied.get(&key_string) else {
            diagnostics.push(ChangelistDiagnostic {
                kind: "missing_resolution",
                object: Some(change.object),
                constant: None,
                message: format!("missing resolution for {key_string}"),
            });
            continue;
        };
        if !resolution_valid_for_change(change, *resolution) {
            diagnostics.push(ChangelistDiagnostic {
                kind: "nonsensical_resolution",
                object: Some(change.object),
                constant: None,
                message: format!("{resolution:?} is not valid for {key_string}"),
            });
        }
    }

    let required_keys = required
        .iter()
        .map(|change| key_debug(&change.key))
        .collect::<BTreeSet<_>>();
    for (key_string, (key, _)) in supplied {
        if required_keys.contains(&key_string) {
            continue;
        }
        diagnostics.push(ChangelistDiagnostic {
            kind: "stale_resolution",
            object: key_object(key),
            constant: None,
            message: format!("resolution no longer matches current changelist: {key_string}"),
        });
    }

    for object in changelist
        .objects
        .iter()
        .filter(|object| object.status == ChangelistStatus::DeleteCandidate)
    {
        let key = vec![str_key("delete_object"), v_obj(object.object)];
        let Some((_, ApplyResolution::Delete)) = resolutions
            .iter()
            .find(|(resolution_key, _)| *resolution_key == key)
        else {
            continue;
        };
        if let Ok(children) = world_state.children_of(permissions, &object.object)
            && !children.is_empty()
        {
            diagnostics.push(ChangelistDiagnostic {
                kind: "delete_not_empty",
                object: Some(object.object),
                constant: None,
                message: format!("{} has children and cannot be deleted", object.object),
            });
        }
        if let Ok(contents) = world_state.contents_of(permissions, &object.object)
            && !contents.is_empty()
        {
            diagnostics.push(ChangelistDiagnostic {
                kind: "delete_not_empty",
                object: Some(object.object),
                constant: None,
                message: format!("{} has contents and cannot be deleted", object.object),
            });
        }
    }

    diagnostics
}

fn required_resolution_keys(changelist: &ObjDefChangelist) -> Vec<&ChangelistChange> {
    let mut required = changelist.conflicts.iter().collect::<Vec<_>>();
    for object in &changelist.objects {
        if object.status != ChangelistStatus::DeleteCandidate {
            continue;
        }
        required.extend(object.changes.iter());
    }
    required
}

fn resolution_valid_for_change(change: &ChangelistChange, resolution: ApplyResolution) -> bool {
    match change.kind {
        "delete_object" => matches!(resolution, ApplyResolution::Delete | ApplyResolution::Keep),
        _ => matches!(
            resolution,
            ApplyResolution::Incoming | ApplyResolution::Local
        ),
    }
}

fn apply_plan(
    changelist: &ObjDefChangelist,
    resolutions: &[(Vec<Var>, ApplyResolution)],
) -> (Vec<(Obj, Entity)>, Vec<Obj>) {
    let resolution_map = resolutions
        .iter()
        .map(|(key, resolution)| (key_debug(key), *resolution))
        .collect::<BTreeMap<_, _>>();
    let mut overrides = Vec::new();
    let mut delete_objects = Vec::new();

    for object in &changelist.objects {
        for change in &object.changes {
            let resolution = resolution_map.get(&key_debug(&change.key)).copied();
            match (change.kind, resolution) {
                ("delete_object", Some(ApplyResolution::Delete)) => {
                    delete_objects.push(change.object);
                }
                ("delete_object", _) => {}
                (_, Some(ApplyResolution::Local)) => {}
                (_, Some(ApplyResolution::Incoming)) | (_, None) if change.automatic => {
                    if let Some(entity) = change_entity(change) {
                        overrides.push((change.object, entity));
                    }
                }
                (_, Some(ApplyResolution::Incoming)) => {
                    if let Some(entity) = change_entity(change) {
                        overrides.push((change.object, entity));
                    }
                }
                _ => {}
            }
        }
    }

    (overrides, delete_objects)
}

fn change_entity(change: &ChangelistChange) -> Option<Entity> {
    match change.kind {
        "object_flags" => Some(Entity::ObjectFlags),
        "object_parent" => Some(Entity::Parentage),
        "object_location" | "object_owner" | "object_name" => Some(Entity::BuiltinProps),
        "property_def" => change.name.map(Entity::PropertyDef),
        "property_value" => change.name.map(Entity::PropertyValue),
        "property_info" => change.name.map(Entity::PropertyFlag),
        "verb_def" | "verb_code" | "verb_metadata" => Some(Entity::VerbDef(verb_key_names(change))),
        _ => None,
    }
}

fn verb_key_names(change: &ChangelistChange) -> Vec<Symbol> {
    change.name.into_iter().collect()
}

fn key_debug(key: &[Var]) -> String {
    format!("{key:?}")
}

fn key_object(key: &[Var]) -> Option<Obj> {
    key.iter().find_map(Var::as_object)
}
