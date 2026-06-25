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

/// Write accepted base hash metadata for an applied objdef set.
///
/// Incoming definitions are stamped as the new base by default. A conflict resolved as `Local`
/// stamps the local hash recorded by the recomputed changelist, because that is the value left in
/// the database after apply.
pub fn write_base_metadata(
    loader: &mut dyn LoaderInterface,
    compile_options: &CompileOptions,
    sources: &[ObjDefSource],
    options: &ChangelistOptions,
    changelist: &ObjDefChangelist,
    resolutions: &[(Vec<Var>, ApplyResolution)],
) -> Result<(), ObjdefLoaderError> {
    let objdef_set = ObjDefSet::parse_sources(
        compile_options,
        None,
        options.constants.as_ref(),
        sources.iter().cloned(),
    )?;
    for (obj, (path, definition)) in objdef_set.graph().object_definitions() {
        write_definition_base_metadata(
            loader,
            path,
            *obj,
            definition,
            &options.base_metadata_prefix,
        )?;
    }

    let resolution_map = resolutions
        .iter()
        .map(|(key, resolution)| (key_debug(key), *resolution))
        .collect::<BTreeMap<_, _>>();
    for object in &changelist.objects {
        for change in &object.changes {
            if resolution_map.get(&key_debug(&change.key)) != Some(&ApplyResolution::Local) {
                continue;
            }
            let Some(hash) = change.local_hash.as_deref() else {
                continue;
            };
            write_change_base_hash(loader, change, &options.base_metadata_prefix, hash)?;
        }
    }

    Ok(())
}

fn write_definition_base_metadata(
    loader: &mut dyn LoaderInterface,
    path: &str,
    obj: Obj,
    definition: &ObjectDefinition,
    prefix: &str,
) -> Result<(), ObjdefLoaderError> {
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "name_hash",
        &stable_hash("object_name", &format!("{:?}", definition.name)),
    )?;
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "parent_hash",
        &stable_hash("object_parent", &definition.parent.to_string()),
    )?;
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "owner_hash",
        &stable_hash("object_owner", &definition.owner.to_string()),
    )?;
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "location_hash",
        &stable_hash("object_location", &definition.location.to_string()),
    )?;
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "flags_hash",
        &stable_hash("object_flags", &definition.flags.to_u16().to_string()),
    )?;
    write_object_base_hash(
        loader,
        path,
        obj,
        prefix,
        "metadata_hash",
        &stable_hash(
            "object_metadata",
            &metadata_summary(definition.metadata.clone(), None),
        ),
    )?;

    for prop in &definition.property_definitions {
        write_property_base_hash(
            loader,
            path,
            obj,
            prop.name,
            prefix,
            "info_hash",
            &stable_hash("property_def", &prop_perms_summary(&prop.perms)),
        )?;
        if let Some(value) = &prop.value {
            write_property_base_hash(
                loader,
                path,
                obj,
                prop.name,
                prefix,
                "value_hash",
                &stable_hash("property_value", &format!("{value:?}")),
            )?;
        }
        write_property_base_hash(
            loader,
            path,
            obj,
            prop.name,
            prefix,
            "metadata_hash",
            &stable_hash(
                "property_metadata",
                &metadata_summary(prop.metadata.clone(), None),
            ),
        )?;
    }

    for prop in &definition.property_overrides {
        if let Some(value) = &prop.value {
            write_property_base_hash(
                loader,
                path,
                obj,
                prop.name,
                prefix,
                "value_hash",
                &stable_hash("property_value", &format!("{value:?}")),
            )?;
        }
        if let Some(perms) = &prop.perms_update {
            write_property_base_hash(
                loader,
                path,
                obj,
                prop.name,
                prefix,
                "info_hash",
                &stable_hash("property_info", &prop_perms_summary(perms)),
            )?;
        }
        write_property_base_hash(
            loader,
            path,
            obj,
            prop.name,
            prefix,
            "metadata_hash",
            &stable_hash(
                "property_metadata",
                &metadata_summary(prop.metadata.clone(), None),
            ),
        )?;
    }

    for verb in &definition.verbs {
        let Some((uuid, _)) = loader
            .get_existing_verb_by_names(&obj, &verb.names)
            .map_err(|err| {
                ObjdefLoaderError::CouldNotDefineVerb(
                    path.to_string(),
                    obj,
                    verb.names.clone(),
                    err,
                )
            })?
        else {
            continue;
        };
        let info = format!(
            "names={:?};owner={};flags={};args={:?}",
            verb.names,
            verb.owner,
            verb_perms_string(verb.flags),
            verb.argspec
        );
        write_verb_base_hash(
            loader,
            path,
            obj,
            uuid,
            prefix,
            "info_hash",
            &stable_hash("verb_def", &info),
        )?;
        write_verb_base_hash(
            loader,
            path,
            obj,
            uuid,
            prefix,
            "code_hash",
            &stable_hash("verb_code", &format!("{:?}", verb.program)),
        )?;
        write_verb_base_hash(
            loader,
            path,
            obj,
            uuid,
            prefix,
            "metadata_hash",
            &stable_hash(
                "verb_metadata",
                &metadata_summary(verb.metadata.clone(), None),
            ),
        )?;
    }

    Ok(())
}

fn write_change_base_hash(
    loader: &mut dyn LoaderInterface,
    change: &ChangelistChange,
    prefix: &str,
    hash: &str,
) -> Result<(), ObjdefLoaderError> {
    let Some(suffix) = base_hash_suffix(change.kind) else {
        return Ok(());
    };
    match change.kind {
        "object_name" | "object_parent" | "object_owner" | "object_location" | "object_flags"
        | "object_metadata" => write_object_base_hash(
            loader,
            "<base_metadata>",
            change.object,
            prefix,
            suffix,
            hash,
        ),
        "property_def" | "property_value" | "property_info" | "property_metadata" => {
            let Some(name) = change.name else {
                return Ok(());
            };
            write_property_base_hash(
                loader,
                "<base_metadata>",
                change.object,
                name,
                prefix,
                suffix,
                hash,
            )
        }
        "verb_def" | "verb_code" | "verb_metadata" => {
            let Some(name) = change.name else {
                return Ok(());
            };
            let Some((uuid, _)) = loader
                .get_existing_verb_by_names(&change.object, &[name])
                .map_err(|err| {
                    ObjdefLoaderError::CouldNotDefineVerb(
                        "<base_metadata>".to_string(),
                        change.object,
                        vec![name],
                        err,
                    )
                })?
            else {
                return Ok(());
            };
            write_verb_base_hash(
                loader,
                "<base_metadata>",
                change.object,
                uuid,
                prefix,
                suffix,
                hash,
            )
        }
        _ => Ok(()),
    }
}

fn base_hash_suffix(kind: &str) -> Option<&'static str> {
    match kind {
        "object_name" => Some("name_hash"),
        "object_parent" => Some("parent_hash"),
        "object_owner" => Some("owner_hash"),
        "object_location" => Some("location_hash"),
        "object_flags" => Some("flags_hash"),
        "object_metadata" => Some("metadata_hash"),
        "property_def" | "property_info" | "verb_def" => Some("info_hash"),
        "property_value" => Some("value_hash"),
        "verb_code" => Some("code_hash"),
        "property_metadata" | "verb_metadata" => Some("metadata_hash"),
        _ => None,
    }
}

fn base_hash_key(prefix: &str, suffix: &str) -> Symbol {
    Symbol::mk(&format!("{prefix}{suffix}"))
}

fn write_object_base_hash(
    loader: &mut dyn LoaderInterface,
    path: &str,
    obj: Obj,
    prefix: &str,
    suffix: &str,
    hash: &str,
) -> Result<(), ObjdefLoaderError> {
    loader
        .set_object_metadata(&obj, base_hash_key(prefix, suffix), v_str(hash))
        .map_err(|err| {
            ObjdefLoaderError::CouldNotSetObjectMetadata(
                path.to_string(),
                obj,
                suffix.to_string(),
                err,
            )
        })
}

fn write_property_base_hash(
    loader: &mut dyn LoaderInterface,
    path: &str,
    obj: Obj,
    prop: Symbol,
    prefix: &str,
    suffix: &str,
    hash: &str,
) -> Result<(), ObjdefLoaderError> {
    loader
        .set_property_metadata(&obj, prop, base_hash_key(prefix, suffix), v_str(hash))
        .map_err(|err| {
            ObjdefLoaderError::CouldNotDefineProperty(
                path.to_string(),
                obj,
                prop.as_arc_str().to_string(),
                err,
            )
        })
}

fn write_verb_base_hash(
    loader: &mut dyn LoaderInterface,
    path: &str,
    obj: Obj,
    uuid: uuid::Uuid,
    prefix: &str,
    suffix: &str,
    hash: &str,
) -> Result<(), ObjdefLoaderError> {
    loader
        .set_verb_metadata(&obj, uuid, base_hash_key(prefix, suffix), v_str(hash))
        .map_err(|err| ObjdefLoaderError::CouldNotDefineVerb(path.to_string(), obj, vec![], err))
}
