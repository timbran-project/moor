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

use crate::{import_export_hierarchy, import_export_id};
use moor_common::model::{
    HasUuid, Named, ObjFlag, PropFlag, ValSet,
    loader::{
        SnapshotExportMetadata, SnapshotExportObject, SnapshotExportSession, SnapshotInterface,
    },
};
use moor_compiler::{ObjPropDef, ObjPropOverride, ObjVerbDef, ObjectDefinition};
#[cfg(test)]
use moor_var::Symbol;
use moor_var::{NOTHING, Obj, Var};
use std::{
    collections::{HashMap, HashSet},
    fs::{File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use thiserror::Error;
use tracing::info;
#[cfg(test)]
use tracing::warn;

#[derive(Error, Debug)]
pub enum ObjectDumpError {
    #[error("Worldstate error: {0}")]
    WorldState(#[from] moor_common::model::WorldStateError),

    #[error("Failed to decompile verb {obj}:{verb_name}: {reason}")]
    DecompileError {
        obj: Obj,
        verb_name: String,
        reason: String,
    },

    #[error("Failed to unparse verb {obj}:{verb_name}: {reason}")]
    UnparseError {
        obj: Obj,
        verb_name: String,
        reason: String,
    },

    #[error(
        "Cannot dump object {obj}: verb {verb_index} has an empty name; repair it with set_verb_info({obj}, {verb_index}, ...) before retrying the checkpoint"
    )]
    EmptyVerbName { obj: Obj, verb_index: usize },

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct ObjectDumpStats {
    pub objects: usize,
    pub regular_objects: usize,
    pub anonymous_objects: usize,
    pub verbs: usize,
    pub properties: usize,
    pub overrides: usize,
    pub metadata_elapsed: Duration,
    pub write_elapsed: Duration,
}

#[cfg(test)]
fn collect_object_definitions(
    loader: &dyn SnapshotInterface,
) -> Result<Vec<ObjectDefinition>, ObjectDumpError> {
    let mut export = loader.begin_export(&[])?;
    let mut object_defs = Vec::with_capacity(export.object_count());
    let started = Instant::now();

    while let Some(object) = export.next_object()? {
        let index = object_defs.len();
        if index % 100 == 0 {
            info!(
                completed = index,
                total = export.object_count(),
                object = %object.oid,
                elapsed = ?started.elapsed(),
                "Collecting object definitions"
            );
        }
        object_defs.push(collect_export_object(object)?);
    }

    info!(
        objects = object_defs.len(),
        elapsed = ?started.elapsed(),
        "Collected object definitions with sequential snapshot scans"
    );
    Ok(object_defs)
}

#[cfg(test)]
fn collect_object_definitions_with_point_reads(
    loader: &dyn SnapshotInterface,
) -> Result<Vec<ObjectDefinition>, ObjectDumpError> {
    let mut object_defs = vec![];

    let export = loader.begin_export(&[])?;
    let object_ids = export
        .metadata()
        .iter()
        .map(|metadata| metadata.oid)
        .collect::<Vec<_>>();
    drop(export);

    let mut num_verbdefs = 0;
    let mut num_propdefs = 0;
    let mut num_propoverrides = 0;
    let started = Instant::now();
    let num_objects = object_ids.len();

    for (index, o) in object_ids.iter().enumerate() {
        if index % 100 == 0 {
            info!(
                completed = index,
                total = num_objects,
                object = %o,
                elapsed = ?started.elapsed(),
                "Collecting object definitions"
            );
        }

        let object_started = Instant::now();
        let (verbdefs, propdefs, overrides, od) = collect_object(loader, o)?;
        let object_elapsed = object_started.elapsed();
        if object_elapsed >= Duration::from_secs(5) {
            warn!(
                object = %o,
                elapsed = ?object_elapsed,
                "Object definition collection is taking longer than expected"
            );
        }
        object_defs.push(od);
        num_verbdefs += verbdefs;
        num_propdefs += propdefs;
        num_propoverrides += overrides;
    }

    info!(
        "Scanned {} objects, {} verbs, {} properties, {} overrides",
        object_defs.len(),
        num_verbdefs,
        num_propdefs,
        num_propoverrides
    );
    Ok(object_defs)
}

fn collect_export_object(
    object: SnapshotExportObject,
) -> Result<ObjectDefinition, ObjectDumpError> {
    let mut definition = ObjectDefinition {
        oid: object.oid,
        name: object.name,
        parent: object.parent,
        owner: object.owner,
        location: object.location,
        flags: object.flags,
        metadata: object.metadata,
        verbs: Vec::with_capacity(object.verbs.len()),
        property_definitions: Vec::new(),
        property_overrides: Vec::new(),
    };

    for verb in object.verbs {
        definition.verbs.push(ObjVerbDef {
            names: verb.names,
            argspec: verb.argspec,
            owner: verb.owner,
            flags: verb.flags,
            program: verb.program,
            metadata: verb.metadata,
        });
    }

    for property in object.properties {
        let name = property.definition.name();
        if property.definition.definer() == object.oid {
            let Some(perms) = property.permissions else {
                return Err(moor_common::model::WorldStateError::DatabaseError(format!(
                    "Canonical property permissions not found on definer {} for property {}",
                    object.oid,
                    property.definition.uuid()
                ))
                .into());
            };
            definition.property_definitions.push(ObjPropDef {
                name,
                perms,
                value: property.value,
                metadata: property.metadata,
            });
        } else {
            definition.property_overrides.push(ObjPropOverride {
                name,
                perms_update: property.permissions,
                value: property.value,
                metadata: property.metadata,
            });
        }
    }

    definition
        .property_definitions
        .sort_by_key(|property| property.name.as_arc_str());
    definition
        .property_overrides
        .sort_by_key(|property| property.name.as_arc_str());
    Ok(definition)
}

pub fn collect_object(
    loader: &dyn SnapshotInterface,
    o: &Obj,
) -> Result<(usize, usize, usize, ObjectDefinition), ObjectDumpError> {
    let mut num_verbdefs = 0;
    let mut num_propdefs = 0;
    let mut num_propoverrides = 0;

    let obj_attrs = loader.get_object(o)?;

    let mut od = ObjectDefinition {
        oid: *o,
        name: obj_attrs.name().unwrap_or("".to_string()),
        parent: obj_attrs.parent().unwrap_or(NOTHING),
        owner: obj_attrs.owner().unwrap_or(NOTHING),
        location: obj_attrs.location().unwrap_or(NOTHING),
        flags: obj_attrs.flags(),
        metadata: loader.get_object_metadata(o)?,
        verbs: vec![],
        property_definitions: vec![],
        property_overrides: vec![],
    };

    let verbs = loader.get_object_verbs(o)?;
    for v in verbs.iter() {
        let binary = loader.get_verb_program(o, v.uuid())?;
        let ov = ObjVerbDef {
            names: v.names().to_vec(),
            argspec: v.args(),
            owner: v.owner(),
            flags: v.flags(),
            program: binary,
            metadata: loader.get_verb_metadata(o, v.uuid())?,
        };
        od.verbs.push(ov);
        num_verbdefs += 1;
    }

    let propdefs = loader.get_all_property_values(o)?;
    for (p, (value, perms)) in propdefs.iter() {
        if p.definer().eq(o) {
            let pd = ObjPropDef {
                name: p.name(),
                perms: perms.clone(),
                value: value.clone(),
                metadata: loader.get_property_metadata(o, p.uuid())?,
            };
            od.property_definitions.push(pd);
            num_propdefs += 1;
        } else {
            // We only need do a perms update if the perms actually different from the definer's
            // So let's resolve the property to its parent and see if it's different
            let mut perms_update = Some(perms.clone());
            let mut override_value = value.clone();

            if let Ok((definer_value, definer_perms)) =
                loader.get_property_value(&p.definer(), p.uuid())
            {
                if perms.eq(&definer_perms)
                    || definer_perms.flags().contains(PropFlag::Chown)
                        && perms.owner() == obj_attrs.owner().unwrap_or(NOTHING)
                {
                    perms_update = None;
                }

                if value.eq(&definer_value) {
                    override_value = None;
                }
            }

            let metadata = loader.get_property_metadata(o, p.uuid())?;

            // Just inheriting? Move on unless local metadata needs preserving.
            if perms_update.is_none() && override_value.is_none() && metadata.is_empty() {
                continue;
            }

            let ps = ObjPropOverride {
                name: p.name(),
                perms_update,
                value: override_value,
                metadata,
            };
            od.property_overrides.push(ps);
            num_propoverrides += 1;
        }
    }

    // Alphabetize properties. Verbs should remain in their original order.
    od.property_definitions.sort_by_key(|a| a.name.as_arc_str());
    od.property_overrides.sort_by_key(|a| a.name.as_arc_str());
    Ok((num_verbdefs, num_propdefs, num_propoverrides, od))
}

/// Extract the object->constant name mapping from object definitions.
/// This is used when dumping individual objects with constant substitution.
#[cfg(test)]
fn extract_index_names(object_defs: &[ObjectDefinition]) -> HashMap<Obj, String> {
    let (index_names, _file_names) = extract_object_constants(object_defs);
    index_names
}

struct ObjectExportIdentity {
    oid: Obj,
    parent: Obj,
    export_id: Option<String>,
    hierarchy: Vec<String>,
}

impl ObjectExportIdentity {
    #[cfg(test)]
    fn from_definition(definition: &ObjectDefinition) -> Self {
        Self {
            oid: definition.oid,
            parent: definition.parent,
            export_id: metadata_string(definition, import_export_id()),
            hierarchy: extract_hierarchy_path(definition),
        }
    }

    fn from_metadata(metadata: &SnapshotExportMetadata) -> Self {
        let export_id = metadata
            .values
            .iter()
            .find(|(key, _)| *key == import_export_id())
            .and_then(|(_, value)| string_or_symbol_to_string(value));
        let hierarchy = metadata
            .values
            .iter()
            .find(|(key, _)| *key == import_export_hierarchy())
            .map(|(_, value)| hierarchy_path_from_value(value))
            .unwrap_or_default();
        Self {
            oid: metadata.oid,
            parent: metadata.parent,
            export_id,
            hierarchy,
        }
    }
}

/// Extract constant names and file names from objects' import_export_id metadata.
/// Skips objects where:
/// - The import_export_id is not unique across all objects
/// - The import_export_id equals the parent's import_export_id (inherited without override)
#[cfg(test)]
fn extract_object_constants(
    object_defs: &[ObjectDefinition],
) -> (HashMap<Obj, String>, HashMap<Obj, String>) {
    let identities = object_defs
        .iter()
        .map(ObjectExportIdentity::from_definition)
        .collect::<Vec<_>>();
    extract_object_constants_from_identities(&identities)
}

fn extract_object_constants_from_identities(
    identities: &[ObjectExportIdentity],
) -> (HashMap<Obj, String>, HashMap<Obj, String>) {
    let mut index_names = HashMap::new();
    let mut file_names = HashMap::new();

    // First pass: collect all import_export_id values.
    let mut id_values: HashMap<Obj, String> = HashMap::new();
    for identity in identities {
        if let Some(id) = &identity.export_id {
            id_values.insert(identity.oid, id.clone());
        }
    }

    // Count occurrences of each value to detect duplicates
    let mut value_counts: HashMap<&str, Vec<Obj>> = HashMap::new();
    for (oid, id_str) in &id_values {
        value_counts.entry(id_str.as_str()).or_default().push(*oid);
    }

    // Log duplicates
    for (id_str, objects) in &value_counts {
        if objects.len() > 1 {
            tracing::warn!(
                "Duplicate import_export_id '{}' on objects {:?}, skipping constant generation",
                id_str,
                objects
            );
        }
    }

    // Second pass: only include unique, non-inherited values
    for identity in identities {
        let Some(id_str) = id_values.get(&identity.oid) else {
            continue;
        };

        // Skip if not unique
        if value_counts
            .get(id_str.as_str())
            .map(|v| v.len())
            .unwrap_or(0)
            > 1
        {
            continue;
        }

        // Skip if same as parent's import_export_id (inherited without meaningful override)
        if identity.parent != NOTHING
            && id_values
                .get(&identity.parent)
                .is_some_and(|parent_id| parent_id == id_str)
        {
            tracing::debug!(
                "Skipping {} - import_export_id '{}' inherited from parent {}",
                identity.oid,
                id_str,
                identity.parent
            );
            continue;
        }

        let constant_name = id_str.to_ascii_uppercase();
        let file_name = id_str.to_lowercase();
        index_names.insert(identity.oid, constant_name);
        file_names.insert(identity.oid, file_name);
    }

    (index_names, file_names)
}

/// Extract hierarchy path from an object's import_export_hierarchy metadata.
/// Returns a vector of path components, or empty vector if no hierarchy is set
#[cfg(test)]
fn extract_hierarchy_path(od: &ObjectDefinition) -> Vec<String> {
    let import_export_hierarchy_sym = import_export_hierarchy();
    let Some(value) = metadata_value(od, import_export_hierarchy_sym) else {
        return Vec::new();
    };

    hierarchy_path_from_value(value)
}

fn hierarchy_path_from_value(value: &Var) -> Vec<String> {
    if let Some(list) = value.as_list() {
        return list
            .iter()
            .filter_map(|value| string_or_symbol_to_string(&value))
            .collect();
    }
    if let Some(s) = string_or_symbol_to_string(value) {
        return vec![s];
    }

    Vec::new()
}

#[cfg(test)]
fn metadata_string(od: &ObjectDefinition, key: Symbol) -> Option<String> {
    metadata_value(od, key).and_then(string_or_symbol_to_string)
}

#[cfg(test)]
fn metadata_value(od: &ObjectDefinition, key: Symbol) -> Option<&Var> {
    od.metadata
        .iter()
        .find(|(metadata_key, _)| *metadata_key == key)
        .map(|(_, value)| value)
}

fn string_or_symbol_to_string(value: &Var) -> Option<String> {
    if let Some(s) = value.as_string() {
        return Some(s.to_string());
    }
    value
        .as_symbol()
        .ok()
        .map(|sym| sym.as_arc_str().to_string())
}

fn collect_snapshot_identities(export: &dyn SnapshotExportSession) -> Vec<ObjectExportIdentity> {
    export
        .metadata()
        .iter()
        .map(ObjectExportIdentity::from_metadata)
        .collect()
}

/// Collect constant substitutions without retaining every object definition.
pub fn collect_index_names(
    loader: &dyn SnapshotInterface,
) -> Result<HashMap<Obj, String>, ObjectDumpError> {
    let export = loader.begin_export(&[import_export_id(), import_export_hierarchy()])?;
    let identities = collect_snapshot_identities(export.as_ref());
    Ok(extract_object_constants_from_identities(&identities).0)
}

fn regular_object_file_name(
    object: &ObjectDefinition,
    file_names: &HashMap<Obj, String>,
) -> String {
    if let Some(name) = file_names.get(&object.oid) {
        return format!("{name}.moo");
    }

    let prefix = if object.flags.contains(ObjFlag::User) {
        "player"
    } else {
        "object"
    };
    format!("{}_{}.moo", prefix, object.oid.as_u64())
}

struct ObjectDumpSink<'a> {
    directory_path: &'a Path,
    index_names: &'a HashMap<Obj, String>,
    file_names: &'a HashMap<Obj, String>,
    hierarchies: &'a HashMap<Obj, Vec<String>>,
    directories: HashMap<Vec<String>, PathBuf>,
    written_anonymous_hierarchies: HashSet<Vec<String>>,
}

impl<'a> ObjectDumpSink<'a> {
    fn new(
        directory_path: &'a Path,
        index_names: &'a HashMap<Obj, String>,
        file_names: &'a HashMap<Obj, String>,
        hierarchies: &'a HashMap<Obj, Vec<String>>,
    ) -> Result<Self, ObjectDumpError> {
        std::fs::create_dir_all(directory_path)?;
        crate::write::generate_constants_file(index_names, hierarchies, directory_path)?;
        let mut directories = HashMap::new();
        directories.insert(Vec::new(), directory_path.to_path_buf());
        Ok(Self {
            directory_path,
            index_names,
            file_names,
            hierarchies,
            directories,
            written_anonymous_hierarchies: HashSet::new(),
        })
    }

    fn target_directory(&mut self, hierarchy: &[String]) -> Result<PathBuf, ObjectDumpError> {
        if let Some(path) = self.directories.get(hierarchy) {
            return Ok(path.clone());
        }
        let mut path = self.directory_path.to_path_buf();
        for component in hierarchy {
            path.push(component);
        }
        std::fs::create_dir_all(&path)?;
        self.directories.insert(hierarchy.to_vec(), path.clone());
        Ok(path)
    }

    fn write_object(&mut self, object: &ObjectDefinition) -> Result<(), ObjectDumpError> {
        crate::write::validate_verb_names(object)?;
        self.write_validated_object(object)
    }

    fn write_validated_object(&mut self, object: &ObjectDefinition) -> Result<(), ObjectDumpError> {
        let hierarchy = self
            .hierarchies
            .get(&object.oid)
            .cloned()
            .unwrap_or_default();
        let target_dir = self.target_directory(&hierarchy)?;
        if !object.oid.is_anonymous() {
            let path = target_dir.join(regular_object_file_name(object, self.file_names));
            let mut file = File::create(path)?;
            return crate::write::write_validated_dump_object(self.index_names, object, &mut file);
        }

        let anonymous_path = target_dir.join("_anonymous_objects.moo");
        let first_in_hierarchy = self.written_anonymous_hierarchies.insert(hierarchy);
        let mut file = if first_in_hierarchy {
            File::create(anonymous_path)?
        } else {
            OpenOptions::new().append(true).open(anonymous_path)?
        };
        if !first_in_hierarchy {
            writeln!(file)?;
        }
        crate::write::write_validated_dump_object(self.index_names, object, &mut file)
    }
}

/// Export one stable snapshot without retaining all property and verb payloads in memory.
///
/// The preliminary pass retains only object naming and hierarchy data. The write pass releases each
/// complete object definition after its output file has been written.
pub fn dump_snapshot_object_definitions(
    loader: &dyn SnapshotInterface,
    directory_path: &Path,
) -> Result<ObjectDumpStats, ObjectDumpError> {
    let metadata_started = Instant::now();
    let mut export = loader.begin_export(&[import_export_id(), import_export_hierarchy()])?;
    let identities = collect_snapshot_identities(export.as_ref());
    let metadata_elapsed = metadata_started.elapsed();

    let (index_names, file_names) = extract_object_constants_from_identities(&identities);
    let hierarchies = identities
        .iter()
        .map(|identity| (identity.oid, identity.hierarchy.clone()))
        .collect::<HashMap<_, _>>();

    let mut sink = ObjectDumpSink::new(directory_path, &index_names, &file_names, &hierarchies)?;

    let started = Instant::now();
    let mut regular_count = 0;
    let mut anonymous_count = 0;
    let mut verb_count = 0;
    let mut property_count = 0;
    let mut override_count = 0;

    while let Some(object) = export.next_object()? {
        let definition = collect_export_object(object)?;
        sink.write_object(&definition)?;

        verb_count += definition.verbs.len();
        property_count += definition.property_definitions.len();
        override_count += definition.property_overrides.len();

        if definition.oid.is_anonymous() {
            anonymous_count += 1;
        } else {
            regular_count += 1;
        }
        let completed = regular_count + anonymous_count;
        if completed % 100 == 0 {
            info!(
                completed,
                total = export.object_count(),
                elapsed = ?started.elapsed(),
                "Writing object definitions"
            );
        }
    }

    info!(
        regular_count,
        anonymous_count,
        verb_count,
        property_count,
        override_count,
        elapsed = ?started.elapsed(),
        "Wrote object definitions from snapshot"
    );
    Ok(ObjectDumpStats {
        objects: regular_count + anonymous_count,
        regular_objects: regular_count,
        anonymous_objects: anonymous_count,
        verbs: verb_count,
        properties: property_count,
        overrides: override_count,
        metadata_elapsed,
        write_elapsed: started.elapsed(),
    })
}

#[cfg(test)]
pub(crate) fn dump_object_definitions(
    object_defs: &[ObjectDefinition],
    directory_path: &Path,
) -> Result<(), ObjectDumpError> {
    for object in object_defs {
        crate::write::validate_verb_names(object)?;
    }

    // Extract constant names and file names
    let (index_names, file_names) = extract_object_constants(object_defs);

    // Extract hierarchies for all objects
    let hierarchies: HashMap<Obj, Vec<String>> = object_defs
        .iter()
        .map(|od| (od.oid, extract_hierarchy_path(od)))
        .collect();

    let regular_count = object_defs
        .iter()
        .filter(|object| !object.oid.is_anonymous())
        .count();
    let anonymous_count = object_defs.len() - regular_count;
    let mut sink = ObjectDumpSink::new(directory_path, &index_names, &file_names, &hierarchies)?;
    for object in object_defs {
        sink.write_validated_object(object)?;
    }

    info!(
        "Dumped {} regular objects and {} anonymous objects",
        regular_count, anonymous_count
    );
    Ok(())
}

pub fn dump_object(
    index_names: &HashMap<Obj, String>,
    o: &ObjectDefinition,
) -> Result<Vec<Var>, ObjectDumpError> {
    Ok(crate::write::collect_dump_object_lines(index_names, o)?.lines)
}

#[cfg(test)]
mod tests {
    use super::{
        collect_object_definitions, dump_object_definitions, dump_snapshot_object_definitions,
    };
    use crate::ObjectDefinitionLoader;
    use moor_common::{
        model::{CommitResult, ObjectKind, PropAttrs, PropFlag, TaskPermissions, WorldStateSource},
        util::BitEnum,
    };
    use moor_compiler::{CompileOptions, parse_literal_value, to_literal};
    use moor_db::{Database, DatabaseConfig, TxDB};
    use moor_textdump::{TextdumpImportOptions, textdump_load};
    use moor_var::{Obj, SYSTEM_OBJECT, Symbol, v_int, v_list, v_obj, v_str};
    use semver::Version;
    use std::{
        collections::BTreeMap,
        path::{Path, PathBuf},
        sync::Arc,
    };

    fn read_directory_tree(root: &Path) -> BTreeMap<PathBuf, Vec<u8>> {
        fn read(root: &Path, directory: &Path, files: &mut BTreeMap<PathBuf, Vec<u8>>) {
            for entry in std::fs::read_dir(directory).unwrap() {
                let path = entry.unwrap().path();
                if path.is_dir() {
                    read(root, &path, files);
                } else {
                    files.insert(
                        path.strip_prefix(root).unwrap().to_path_buf(),
                        std::fs::read(path).unwrap(),
                    );
                }
            }
        }

        let mut files = BTreeMap::new();
        read(root, root, &mut files);
        files
    }

    fn system_permissions() -> TaskPermissions {
        TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
    }

    #[test]
    fn objdef_metadata_load_dump_round_trip() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        {
            let mut loader = db.loader_client().unwrap();
            let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
            let spec = r#"
                object #42 [ package -> "core" ]
                    name: "Metadata Test"
                    owner: #42
                    parent: #-1
                    location: #-1

                    property version (owner: #42, flags: "rc") [ revision -> 7 ] = "1.0";

                    verb "look" (this none none) owner: #42 flags: "rxd" [ modified_by -> #42 ]
                        return "ok";
                    endverb
                endobject"#;

            parser
                .load_single_object(spec, CompileOptions::default(), Default::default())
                .unwrap();
            assert!(matches!(loader.commit(), Ok(CommitResult::Success { .. })));
        }

        let snapshot = db.create_snapshot().unwrap();
        let object_defs = collect_object_definitions(snapshot.as_ref()).unwrap();
        let index_names = super::extract_index_names(&object_defs);
        let object_def = object_defs
            .iter()
            .find(|def| def.oid == Obj::mk_id(42))
            .unwrap();
        let lines = super::dump_object(&index_names, object_def).unwrap();
        let text = lines
            .iter()
            .map(|line| line.as_string().unwrap().to_string())
            .collect::<Vec<_>>()
            .join("\n");

        assert!(text.contains("object #42 [\n  package -> \"core\"\n]"));
        assert!(text.contains(r#"property version (owner: #42, flags: "rc") [ revision -> 7 ]"#));
        assert!(text.contains(r#"verb look (this none none) owner: #42 flags: "rxd" ["#));
        assert!(text.contains("modified_by -> #42"));

        let collected_dir = tempfile::tempdir().unwrap();
        let streamed_dir = tempfile::tempdir().unwrap();
        let point_read_definitions =
            super::collect_object_definitions_with_point_reads(snapshot.as_ref()).unwrap();
        dump_object_definitions(&point_read_definitions, collected_dir.path()).unwrap();
        assert_eq!(
            dump_snapshot_object_definitions(snapshot.as_ref(), streamed_dir.path())
                .unwrap()
                .objects,
            object_defs.len()
        );
        assert_eq!(
            read_directory_tree(collected_dir.path()),
            read_directory_tree(streamed_dir.path())
        );
    }

    #[test]
    fn streaming_dump_preserves_explicit_inherited_overrides() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);
        let child;

        {
            let mut tx = db.new_world_state().unwrap();
            tx.create_object(
                &system_permissions(),
                &Obj::mk_id(-1),
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::NextObjid,
            )
            .unwrap();
            child = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            for name in ["changed", "unchanged", "permissions", "metadata", "cleared"] {
                tx.define_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    Symbol::mk(name),
                    &SYSTEM_OBJECT,
                    BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
                    Some(v_int(1)),
                )
                .unwrap();
            }
            tx.update_property(
                &system_permissions(),
                &child,
                Symbol::mk("changed"),
                &v_int(2),
            )
            .unwrap();
            tx.update_property(
                &system_permissions(),
                &child,
                Symbol::mk("unchanged"),
                &v_int(1),
            )
            .unwrap();
            tx.set_property_info(
                &system_permissions(),
                &child,
                Symbol::mk("permissions"),
                PropAttrs {
                    flags: Some(BitEnum::new_with(PropFlag::Read)),
                    ..PropAttrs::default()
                },
            )
            .unwrap();
            tx.set_property_metadata(
                &system_permissions(),
                &child,
                Symbol::mk("metadata"),
                Symbol::mk("source"),
                v_str("child"),
            )
            .unwrap();
            tx.update_property(
                &system_permissions(),
                &child,
                Symbol::mk("cleared"),
                &v_int(2),
            )
            .unwrap();
            tx.clear_property(&system_permissions(), &child, Symbol::mk("cleared"))
                .unwrap();
            tx.commit().unwrap();
        }

        let snapshot = db.create_snapshot().unwrap();
        let definitions = collect_object_definitions(snapshot.as_ref()).unwrap();
        let child_definition = definitions
            .iter()
            .find(|definition| definition.oid == child)
            .unwrap();
        let mut override_names = child_definition
            .property_overrides
            .iter()
            .map(|property| property.name.as_string())
            .collect::<Vec<_>>();
        override_names.sort_unstable();
        assert_eq!(
            override_names,
            ["changed", "cleared", "metadata", "permissions", "unchanged"]
        );

        let cleared = child_definition
            .property_overrides
            .iter()
            .find(|property| property.name == Symbol::mk("cleared"))
            .unwrap();
        assert!(cleared.value.is_none());
        assert!(cleared.perms_update.is_some());

        let metadata = child_definition
            .property_overrides
            .iter()
            .find(|property| property.name == Symbol::mk("metadata"))
            .unwrap();
        assert!(metadata.value.is_none());
        assert!(metadata.perms_update.is_none());
        assert_eq!(metadata.metadata, [(Symbol::mk("source"), v_str("child"))]);

        let streamed_dir = tempfile::tempdir().unwrap();
        dump_snapshot_object_definitions(snapshot.as_ref(), streamed_dir.path()).unwrap();

        let child = std::fs::read_to_string(streamed_dir.path().join("object_1.moo")).unwrap();
        assert!(child.contains("override changed"));
        assert!(child.contains("override unchanged"));
        assert!(child.contains("override permissions"));
        assert!(child.contains("override metadata"));
        assert!(child.contains("override cleared"));
    }

    #[test]
    fn streaming_dump_ignores_stale_property_rows() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);
        let (old_parent, new_parent, child);

        {
            let mut tx = db.new_world_state().unwrap();
            let system = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1),
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system, SYSTEM_OBJECT);
            old_parent = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            new_parent = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            child = tx
                .create_object(
                    &system_permissions(),
                    &old_parent,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();

            tx.define_property(
                &system_permissions(),
                &old_parent,
                &old_parent,
                Symbol::mk("old_parent_property"),
                &SYSTEM_OBJECT,
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
                Some(v_int(1)),
            )
            .unwrap();
            tx.update_property(
                &system_permissions(),
                &child,
                Symbol::mk("old_parent_property"),
                &v_int(2),
            )
            .unwrap();

            tx.define_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                Symbol::mk("deleted_property"),
                &SYSTEM_OBJECT,
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
                Some(v_int(3)),
            )
            .unwrap();
            tx.update_property(
                &system_permissions(),
                &child,
                Symbol::mk("deleted_property"),
                &v_int(4),
            )
            .unwrap();
            tx.commit().unwrap();
        }

        {
            let mut tx = db.new_world_state().unwrap();
            tx.change_parent(&system_permissions(), &child, &new_parent)
                .unwrap();
            tx.delete_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("deleted_property"),
            )
            .unwrap();
            tx.commit().unwrap();
        }

        let snapshot = db.create_snapshot().unwrap();
        let definitions = collect_object_definitions(snapshot.as_ref()).unwrap();
        let child_definition = definitions
            .iter()
            .find(|definition| definition.oid == child)
            .unwrap();
        assert_eq!(child_definition.parent, new_parent);
        assert!(child_definition.property_definitions.is_empty());
        assert!(child_definition.property_overrides.is_empty());
    }

    #[test]
    fn snapshot_merge_handles_non_numeric_fjall_object_order() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);
        let one = Obj::mk_id(1);
        let two_fifty_six = Obj::mk_id(256);

        {
            let mut tx = db.new_world_state().unwrap();
            let system = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1),
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system, SYSTEM_OBJECT);
            tx.create_object(
                &system_permissions(),
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::Objid(one),
            )
            .unwrap();
            tx.create_object(
                &system_permissions(),
                &one,
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::Objid(two_fifty_six),
            )
            .unwrap();
            for (object, name) in [(one, "one"), (two_fifty_six, "two_fifty_six")] {
                tx.set_object_metadata(
                    &system_permissions(),
                    &object,
                    Symbol::mk("import_export_id"),
                    v_str(name),
                )
                .unwrap();
            }
            tx.set_object_metadata(
                &system_permissions(),
                &one,
                Symbol::mk("marker"),
                v_str("one"),
            )
            .unwrap();
            tx.commit().unwrap();
        }

        let snapshot = db.create_snapshot().unwrap();
        let mut export = snapshot
            .begin_export(&[Symbol::mk("import_export_id")])
            .unwrap();
        assert!(export.metadata().iter().any(|metadata| {
            metadata.oid == one
                && metadata
                    .values
                    .iter()
                    .any(|(_, value)| value.as_string() == Some("one"))
        }));
        assert!(export.metadata().iter().any(|metadata| {
            metadata.oid == two_fifty_six
                && metadata
                    .values
                    .iter()
                    .any(|(_, value)| value.as_string() == Some("two_fifty_six"))
        }));

        let mut saw_one = false;
        let mut saw_two_fifty_six = false;
        while let Some(object) = export.next_object().unwrap() {
            if object.oid == one {
                saw_one = object
                    .metadata
                    .iter()
                    .any(|(key, value)| *key == Symbol::mk("marker") && value == &v_str("one"));
            }
            if object.oid == two_fifty_six {
                saw_two_fifty_six = object.parent == one;
            }
        }
        assert!(saw_one);
        assert!(saw_two_fifty_six);
    }

    #[test]
    fn object_metadata_controls_export_naming() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        {
            let mut tx = db.new_world_state().unwrap();
            let system_obj = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1),
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system_obj, SYSTEM_OBJECT);

            tx.define_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id"),
                &SYSTEM_OBJECT,
                BitEnum::new_with(PropFlag::Read),
                Some(v_str("legacy_name")),
            )
            .unwrap();
            tx.set_object_metadata(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id"),
                v_str("metadata_name"),
            )
            .unwrap();
            tx.commit().unwrap();
        }

        let snapshot = db.create_snapshot().unwrap();
        let object_defs = collect_object_definitions(snapshot.as_ref()).unwrap();
        let index_names = super::extract_index_names(&object_defs);
        assert_eq!(
            index_names.get(&SYSTEM_OBJECT).map(String::as_str),
            Some("METADATA_NAME")
        );
    }

    #[test]
    fn object_metadata_is_multiline_with_import_export_id_first() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        {
            let mut loader = db.loader_client().unwrap();
            let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
            let spec = r#"
                object #42 [
                    import_export_id -> "sub_utils",
                    import_export_hierarchy -> {"events"}
                ]
                    name: "Sub Utils"
                    owner: #42
                    parent: #-1
                    location: #-1
                endobject"#;

            parser
                .load_single_object(spec, CompileOptions::default(), Default::default())
                .unwrap();
            assert!(matches!(loader.commit(), Ok(CommitResult::Success { .. })));
        }

        let snapshot = db.create_snapshot().unwrap();
        let object_defs = collect_object_definitions(snapshot.as_ref()).unwrap();
        let index_names = super::extract_index_names(&object_defs);
        let object_def = object_defs
            .iter()
            .find(|def| def.oid == Obj::mk_id(42))
            .unwrap();
        let lines = super::dump_object(&index_names, object_def).unwrap();
        let text = lines
            .iter()
            .map(|line| line.as_string().unwrap().to_string())
            .collect::<Vec<_>>()
            .join("\n");

        let id_pos = text.find("import_export_id -> \"sub_utils\"").unwrap();
        let hierarchy_pos = text
            .find("import_export_hierarchy -> {\"events\"}")
            .unwrap();
        assert!(id_pos < hierarchy_pos);
        assert!(text.contains("object SUB_UTILS [\n  import_export_id -> \"sub_utils\",\n"));
    }

    /// 1. Load from a classical textdump
    /// 2. Dump to a objdef dump
    /// 3. Load objdef dump
    /// 4. Some basic verification
    #[test]
    fn load_textdump_dump_objdef_restore_objdef() {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let jhcore = manifest_dir.join("../../cores/JHCore-DEV-2.db");

        let tmpdir = tempfile::tempdir().unwrap();
        let tmpdir_path = tmpdir.path();
        {
            let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
            let db = Arc::new(db);
            let mut loader_client = db.clone().loader_client().unwrap();

            textdump_load(
                loader_client.as_mut(),
                jhcore,
                Version::new(0, 1, 0),
                CompileOptions::default(),
                TextdumpImportOptions::default(),
            )
            .unwrap();
            assert!(matches!(
                loader_client.commit(),
                Ok(CommitResult::Success { .. })
            ));

            // Make a tmpdir & dump objdefs into it
            let snapshot = db.clone().create_snapshot().unwrap();
            dump_snapshot_object_definitions(snapshot.as_ref(), tmpdir_path).unwrap();
        }

        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        // Now load
        let mut loader = db.loader_client().unwrap();
        let mut defloader = ObjectDefinitionLoader::new(loader.as_mut());
        let options = crate::ObjDefLoaderOptions {
            dry_run: false,
            conflict_mode: crate::ConflictMode::Clobber,
            object_kind: None,
            constants: None,
            overrides: vec![],
            validate_parent_changes: false,
        };
        defloader
            .load_objdef_directory(CompileOptions::default(), tmpdir_path, options)
            .unwrap();

        // Round trip worked, so we'll just leave it at that for now. A more anal retentive test
        // would go look at known objects and props etc and compare.
    }

    /// Test lambda objdef serialization by creating lambdas and doing a round-trip
    #[test]
    fn test_lambda_objdef_serialization() {
        let tmpdir = tempfile::tempdir().unwrap();
        let tmpdir_path = tmpdir.path();

        // Create database with lambda properties
        let (db1, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db1 = Arc::new(db1);

        {
            let mut tx = db1.new_world_state().unwrap();

            // Create the system object first
            let system_obj = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1), // parent: nothing
                    &SYSTEM_OBJECT,  // owner: self
                    BitEnum::new(),  // flags: none
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system_obj, SYSTEM_OBJECT);

            tx.set_object_metadata(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id"),
                v_str("sysobj"),
            )
            .unwrap();

            let simple_lambda = parse_literal_value("{x} => x + 1").unwrap();
            let captured_lambda =
                parse_literal_value("{x} => x + base with captured [{base: 42}]").unwrap();

            // Define lambda properties
            tx.define_property(
                &system_permissions(),                               // perms
                &SYSTEM_OBJECT,                                      // definer
                &SYSTEM_OBJECT,                                      // location
                Symbol::mk("simple_lambda"),                         // pname
                &SYSTEM_OBJECT,                                      // owner
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write, // prop_flags
                Some(simple_lambda.clone()),                         // initial_value
            )
            .unwrap();

            tx.define_property(
                &system_permissions(),                               // perms
                &SYSTEM_OBJECT,                                      // definer
                &SYSTEM_OBJECT,                                      // location
                Symbol::mk("captured_lambda"),                       // pname
                &SYSTEM_OBJECT,                                      // owner
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write, // prop_flags
                Some(captured_lambda.clone()),                       // initial_value
            )
            .unwrap();

            tx.commit().unwrap();
        }

        // Force database checkpoint to ensure data is persisted
        db1.checkpoint().unwrap();

        // Dump to objdef format
        {
            let snapshot = db1.create_snapshot().unwrap();
            dump_snapshot_object_definitions(snapshot.as_ref(), tmpdir_path).unwrap();
        }

        // Read the generated objdef file to verify lambda syntax
        let system_file = tmpdir_path.join("sysobj.moo");
        assert!(system_file.exists(), "System object file should be created");

        let content = std::fs::read_to_string(&system_file).unwrap();

        // Verify lambda syntax appears in the file with correct format
        assert!(
            content.contains("simple_lambda"),
            "Should contain simple_lambda property"
        );
        assert!(
            content.contains("captured_lambda"),
            "Should contain captured_lambda property"
        );
        assert!(content.contains("=>"), "Should contain lambda arrow syntax");
        assert!(
            content.contains("{x} => x + 1"),
            "Should contain correct lambda syntax"
        );

        // Verify the new variable name mapping format in captured environments
        assert!(
            content.contains("with captured"),
            "Should contain captured environment metadata"
        );
        assert!(
            content.contains("base: 42"),
            "Should contain the captured variable name and value"
        );

        // Load objdef back into new database - should now work with literal_lambda support
        let (db2, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db2 = Arc::new(db2);

        {
            let mut loader = db2.loader_client().unwrap();
            let mut defloader = ObjectDefinitionLoader::new(loader.as_mut());
            let options = crate::ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: crate::ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: false,
            };
            defloader
                .load_objdef_directory(CompileOptions::default(), tmpdir_path, options)
                .unwrap();
            assert!(matches!(loader.commit(), Ok(CommitResult::Success { .. })));
        }

        // Verify lambdas were loaded correctly
        {
            let tx = db2.new_world_state().unwrap();

            let simple_prop = tx
                .retrieve_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    Symbol::mk("simple_lambda"),
                )
                .unwrap();
            assert!(
                simple_prop.as_lambda().is_some(),
                "Simple lambda should be loaded as lambda"
            );
            assert!(to_literal(&simple_prop).contains("x + 1"));

            let captured_prop = tx
                .retrieve_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    Symbol::mk("captured_lambda"),
                )
                .unwrap();
            assert!(
                captured_prop.as_lambda().is_some(),
                "Captured lambda should be loaded as lambda"
            );

            if let Some(lambda) = captured_prop.as_lambda() {
                let captures = lambda
                    .0
                    .captured_env
                    .iter()
                    .flatten()
                    .filter(|value| !value.is_none())
                    .cloned()
                    .collect::<Vec<_>>();
                assert_eq!(captures, vec![v_int(42)]);
            }
        }
    }

    /// Test that import_export_id metadata can be inferred for first dump naming
    #[test]
    fn test_import_export_id_auto_creation() {
        let tmpdir = tempfile::tempdir().unwrap();
        let tmpdir_path = tmpdir.path();

        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        // Create a simple hierarchy: #0 (system) -> #1 (parent) -> #2 (child)
        {
            let mut tx = db.new_world_state().unwrap();

            // Create system object
            let system_obj = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1),
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system_obj, SYSTEM_OBJECT);

            // Create parent object
            let parent_obj = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(parent_obj, Obj::mk_id(1));

            // Create child object
            let child_obj = tx
                .create_object(
                    &system_permissions(),
                    &parent_obj,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(child_obj, Obj::mk_id(2));

            // Add a property to system object that references parent (so parent gets a constant)
            tx.define_property(
                &system_permissions(),
                &SYSTEM_OBJECT,
                &SYSTEM_OBJECT,
                Symbol::mk("parent_ref"),
                &SYSTEM_OBJECT,
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write,
                Some(v_obj(parent_obj)),
            )
            .unwrap();

            tx.commit().unwrap();
        }

        // Dump to objdef
        {
            let snapshot = db.create_snapshot().unwrap();
            dump_snapshot_object_definitions(snapshot.as_ref(), tmpdir_path).unwrap();
        }
    }

    #[test]
    fn legacy_naming_properties_are_normalized_on_import() {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);
        let mut loader = db.loader_client().unwrap();
        let mut defloader = ObjectDefinitionLoader::new(loader.as_mut());
        defloader
            .load_single_object(
                r#"
                object #0
                    name: "System"
                    owner: #0
                    parent: #-1
                    location: #-1
                    property import_export_id (owner: #0, flags: "r") = "sysobj";
                    property import_export_hierarchy (owner: #0, flags: "r") = {"core"};
                endobject
                "#,
                CompileOptions::default(),
                Default::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let tx = db.new_world_state().unwrap();
        let export_id = tx
            .get_object_metadata(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id"),
            )
            .unwrap()
            .unwrap();
        assert_eq!(export_id.as_string(), Some("sysobj"));
        let hierarchy = tx
            .get_object_metadata(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_hierarchy"),
            )
            .unwrap()
            .unwrap();
        assert_eq!(hierarchy.as_list().unwrap().len(), 1);
        assert!(
            tx.get_property_info(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id")
            )
            .is_err()
        );
    }

    /// Test anonymous object objdef round-trip: create anonymous objects, dump them, reload, and verify
    #[test]
    fn test_anonymous_object_objdef_roundtrip() {
        let tmpdir = tempfile::tempdir().unwrap();
        let tmpdir_path = tmpdir.path();

        // Create database with anonymous objects and properties
        let (db1, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db1 = Arc::new(db1);

        let anon_obj1;
        let anon_obj2;
        {
            let mut tx = db1.new_world_state().unwrap();

            // Create the system object first
            let system_obj = tx
                .create_object(
                    &system_permissions(),
                    &Obj::mk_id(-1), // parent: nothing
                    &SYSTEM_OBJECT,  // owner: self
                    BitEnum::new(),  // flags: none
                    ObjectKind::NextObjid,
                )
                .unwrap();
            assert_eq!(system_obj, SYSTEM_OBJECT);

            // Add import_export_id so the object gets a file during dump
            tx.set_object_metadata(
                &system_permissions(),
                &SYSTEM_OBJECT,
                Symbol::mk("import_export_id"),
                v_str("sysobj"),
            )
            .unwrap();

            // Create anonymous objects
            anon_obj1 = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT, // parent: system
                    &SYSTEM_OBJECT, // owner: system
                    BitEnum::new(), // flags: none
                    ObjectKind::Anonymous,
                )
                .unwrap();

            anon_obj2 = tx
                .create_object(
                    &system_permissions(),
                    &SYSTEM_OBJECT, // parent: system
                    &SYSTEM_OBJECT, // owner: system
                    BitEnum::new(), // flags: none
                    ObjectKind::Anonymous,
                )
                .unwrap();

            // Verify they are anonymous
            assert!(anon_obj1.is_anonymous());
            assert!(anon_obj2.is_anonymous());
            assert_ne!(anon_obj1, anon_obj2);

            // Add properties that reference anonymous objects
            tx.define_property(
                &system_permissions(),                               // perms
                &SYSTEM_OBJECT,                                      // definer
                &SYSTEM_OBJECT,                                      // location
                Symbol::mk("anon_ref1"),                             // pname
                &SYSTEM_OBJECT,                                      // owner
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write, // prop_flags
                Some(v_obj(anon_obj1)),                              // initial_value
            )
            .unwrap();

            tx.define_property(
                &system_permissions(),                                          // perms
                &SYSTEM_OBJECT,                                                 // definer
                &SYSTEM_OBJECT,                                                 // location
                Symbol::mk("anon_list"),                                        // pname
                &SYSTEM_OBJECT,                                                 // owner
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write,            // prop_flags
                Some(v_list(&[v_obj(anon_obj1), v_obj(anon_obj2), v_int(42)])), // list with anon refs
            )
            .unwrap();

            // Add a property to the anonymous object itself
            tx.define_property(
                &system_permissions(),                               // perms
                &anon_obj1,                                          // definer
                &anon_obj1,                                          // location
                Symbol::mk("anon_prop"),                             // pname
                &SYSTEM_OBJECT,                                      // owner
                BitEnum::new_with(PropFlag::Read) | PropFlag::Write, // prop_flags
                Some(v_str("anonymous object property")),            // initial_value
            )
            .unwrap();

            tx.commit().unwrap();
        }

        // Force database checkpoint to ensure data is persisted
        db1.checkpoint().unwrap();

        // Dump to objdef format
        {
            let snapshot = db1.create_snapshot().unwrap();
            dump_snapshot_object_definitions(snapshot.as_ref(), tmpdir_path).unwrap();
        }

        // Verify _anonymous_objects.moo file was created
        let anon_file = tmpdir_path.join("_anonymous_objects.moo");
        assert!(
            anon_file.exists(),
            "_anonymous_objects.moo file should be created"
        );

        // Read and verify anonymous object syntax in the file
        let anon_content = std::fs::read_to_string(&anon_file).unwrap();
        assert!(
            anon_content.contains("#anon_"),
            "Should contain anonymous object syntax"
        );
        assert!(
            anon_content.contains("object #anon_"),
            "Should contain object definitions"
        );
        assert!(
            anon_content.contains("anon_prop"),
            "Should contain anonymous object properties"
        );

        // Verify system object file contains references to anonymous objects
        let system_file = tmpdir_path.join("sysobj.moo");
        assert!(system_file.exists(), "System object file should be created");

        let system_content = std::fs::read_to_string(&system_file).unwrap();
        println!("System file content after fix:\n{system_content}");

        assert!(
            system_content.contains("anon_ref1"),
            "Should contain anon_ref1 property"
        );
        assert!(
            system_content.contains("anon_list"),
            "Should contain anon_list property"
        );

        // The system file should contain direct anonymous object references since they don't get constants
        assert!(
            system_content.contains("#anon_"),
            "Should contain direct anonymous object references"
        );

        // Verify constants.moo file exists but doesn't contain anonymous object constants
        let constants_file = tmpdir_path.join("constants.moo");
        assert!(
            constants_file.exists(),
            "constants.moo file should be created"
        );

        let constants_content = std::fs::read_to_string(&constants_file).unwrap();

        // Constants file should NOT contain anonymous object constants (they shouldn't have constants)
        assert!(
            !constants_content.contains("#anon_"),
            "constants.moo should not define anonymous object constants"
        );

        // Load objdef back into new database
        let (db2, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db2 = Arc::new(db2);

        {
            let mut loader = db2.loader_client().unwrap();
            let mut defloader = ObjectDefinitionLoader::new(loader.as_mut());
            let options = crate::ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: crate::ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: false,
            };
            defloader
                .load_objdef_directory(CompileOptions::default(), tmpdir_path, options)
                .unwrap();
            assert!(matches!(loader.commit(), Ok(CommitResult::Success { .. })));
        }

        // Verify anonymous objects were loaded correctly
        {
            let tx = db2.new_world_state().unwrap();

            // Get the anonymous object reference from system object property
            let anon_ref_prop = tx
                .retrieve_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    Symbol::mk("anon_ref1"),
                )
                .unwrap();
            let loaded_anon_obj1 = anon_ref_prop.as_object().unwrap();
            assert!(
                loaded_anon_obj1.is_anonymous(),
                "Loaded object should be anonymous"
            );

            // Get the list with anonymous objects
            let anon_list_prop = tx
                .retrieve_property(
                    &system_permissions(),
                    &SYSTEM_OBJECT,
                    Symbol::mk("anon_list"),
                )
                .unwrap();
            let list = anon_list_prop.as_list().unwrap();
            assert_eq!(list.len(), 3, "List should have 3 elements");

            let list_anon_obj1 = list.iter().next().unwrap().as_object().unwrap();
            let list_anon_obj2 = list.iter().nth(1).unwrap().as_object().unwrap();
            assert!(
                list_anon_obj1.is_anonymous(),
                "First list object should be anonymous"
            );
            assert!(
                list_anon_obj2.is_anonymous(),
                "Second list object should be anonymous"
            );
            assert_ne!(
                list_anon_obj1, list_anon_obj2,
                "Anonymous objects should be different"
            );

            // Verify the property on the anonymous object itself
            let anon_prop = tx
                .retrieve_property(
                    &system_permissions(),
                    &loaded_anon_obj1,
                    Symbol::mk("anon_prop"),
                )
                .unwrap();
            assert_eq!(
                anon_prop.as_string().unwrap(),
                "anonymous object property",
                "Anonymous object property should be preserved"
            );

            // Verify anonymous objects are valid and functional
            assert!(
                tx.valid(&loaded_anon_obj1).unwrap(),
                "Anonymous object should be valid"
            );
            assert_eq!(
                tx.parent_of(&system_permissions(), &loaded_anon_obj1)
                    .unwrap(),
                SYSTEM_OBJECT,
                "Anonymous object parent should be preserved"
            );
            assert_eq!(
                tx.owner_of(&loaded_anon_obj1).unwrap(),
                SYSTEM_OBJECT,
                "Anonymous object owner should be preserved"
            );
        }
    }
}
