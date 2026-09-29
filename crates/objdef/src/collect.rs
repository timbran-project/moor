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

//! Permission-checked object definitions from the caller's current transaction.

use crate::dump::collect_export_object;
use moor_common::model::{
    HasUuid, Named, PropDefs, TaskPermissions, ValSet, WorldState, WorldStateError,
    loader::{SnapshotExportObject, SnapshotExportVerb},
};
use moor_compiler::ObjectDefinition;
use moor_var::Obj;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, thiserror::Error)]
pub enum ObjectCollectionError {
    #[error("duplicate object in collection: {0}")]
    DuplicateObject(Obj),
    #[error("inheritance cycle at {0}")]
    InheritanceCycle(Obj),
    #[error("could not collect {object}: {source}")]
    Read {
        object: Obj,
        #[source]
        source: WorldStateError,
    },
}

/// Collect selected definitions without writing or allocating database objects.
///
/// Reads observe pending changes in the supplied transaction and require access to object
/// metadata, property values, and verb source. Ancestors are consulted for inherited property
/// definitions but are not added to the output. No export identities are required. Explicit local
/// values, permissions, and metadata are preserved, even when equal to inherited state. Results
/// are sorted by object address and property name, with verbs kept in lookup order.
pub fn collect_object_definitions(
    world: &dyn WorldState,
    permissions: &TaskPermissions,
    objects: &[Obj],
) -> Result<Vec<ObjectDefinition>, ObjectCollectionError> {
    let mut scope = BTreeSet::new();
    for object in objects {
        if !scope.insert(*object) {
            return Err(ObjectCollectionError::DuplicateObject(*object));
        }
    }
    let mut ancestry = BTreeMap::<Obj, (Obj, PropDefs)>::new();
    let mut definitions = Vec::with_capacity(scope.len());
    for object in scope {
        let read_error = |source| ObjectCollectionError::Read { object, source };
        let mut record = collect_attributes(world, permissions, object).map_err(read_error)?;
        let mut ancestor = object;
        let mut seen = BTreeSet::new();
        while !ancestor.is_nothing() {
            if !seen.insert(ancestor) {
                return Err(ObjectCollectionError::InheritanceCycle(ancestor));
            }
            if let std::collections::btree_map::Entry::Vacant(entry) = ancestry.entry(ancestor) {
                let parent = world
                    .parent_of(permissions, &ancestor)
                    .map_err(read_error)?;
                let properties = world
                    .properties(permissions, &ancestor)
                    .map_err(read_error)?;
                entry.insert((parent, properties));
            }
            let (parent, properties) = &ancestry[&ancestor];
            for property in properties.iter() {
                let state = world
                    .snapshot_property(permissions, &object, property.uuid())
                    .map_err(read_error)?;
                if state.definition.definer() != ancestor {
                    return Err(read_error(WorldStateError::DatabaseError(format!(
                        "Property {} on {object} has an unexpected definer",
                        property.uuid()
                    ))));
                }
                if ancestor == object
                    || state.value.is_some()
                    || state.permissions.is_some()
                    || !state.metadata.is_empty()
                {
                    record.properties.push(state);
                }
            }
            ancestor = *parent;
        }
        definitions.push(collect_export_object(record).map_err(read_error)?);
    }
    Ok(definitions)
}

fn collect_attributes(
    world: &dyn WorldState,
    permissions: &TaskPermissions,
    object: Obj,
) -> Result<SnapshotExportObject, WorldStateError> {
    // Metadata enumeration checks object readability and validity before other attributes.
    let metadata = world.object_metadata(permissions, &object)?;
    let mut record = SnapshotExportObject {
        oid: object,
        name: world.name_of(permissions, &object)?,
        parent: world.parent_of(permissions, &object)?,
        owner: world.owner_of(&object)?,
        location: world.location_of(permissions, &object)?,
        flags: world.flags_of(&object)?,
        metadata,
        verbs: Vec::new(),
        properties: Vec::new(),
    };
    for verb in world.verbs(permissions, &object)?.iter() {
        let (program, verb) = world.retrieve_verb(permissions, &object, verb.uuid())?;
        record.verbs.push(SnapshotExportVerb {
            names: verb.names().to_vec(),
            argspec: verb.args(),
            owner: verb.owner(),
            flags: verb.flags(),
            program,
            metadata: world.verb_metadata(permissions, &object, verb.uuid())?,
        });
    }
    Ok(record)
}
