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

use byteview::ByteView;
use fjall::{Readable, Slice};
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

use crate::{
    AnonymousObjectMetadata, EntityMetadataKey, ObjAndUUIDHolder, StringHolder,
    provider::fjall_provider::{FjallCodec, decode_fjall_value},
    tx::{EncodeFor, Error, Timestamp},
};
use moor_common::{
    model::{
        HasUuid, ObjAttrs, ObjSet, ObjectRef, PropDef, PropDefs, PropFlag, PropPerms, ValSet,
        VerbDefs, WorldStateError,
        loader::{
            SnapshotExport, SnapshotExportMetadata, SnapshotExportObject, SnapshotExportProperty,
            SnapshotExportVerb, SnapshotInterface,
        },
    },
    util::BitEnum,
};
use moor_var::{NOTHING, Obj, Symbol, Var, program::ProgramType};

/// A snapshot-based implementation of LoaderInterface for read-only database access
pub struct FjallSnapshotLoader {
    pub snapshot: fjall::Snapshot,
    pub object_location_keyspace: fjall::Keyspace,
    pub object_flags_keyspace: fjall::Keyspace,
    pub object_parent_keyspace: fjall::Keyspace,
    pub object_owner_keyspace: fjall::Keyspace,
    pub object_name_keyspace: fjall::Keyspace,
    pub object_verbdefs_keyspace: fjall::Keyspace,
    pub object_verbs_keyspace: fjall::Keyspace,
    pub object_propdefs_keyspace: fjall::Keyspace,
    pub object_propvalues_keyspace: fjall::Keyspace,
    pub object_propflags_keyspace: fjall::Keyspace,
    pub entity_metadata_keyspace: fjall::Keyspace,
    pub anonymous_object_metadata_keyspace: fjall::Keyspace,
}

struct FjallSnapshotExport<'a> {
    loader: &'a FjallSnapshotLoader,
    objects: Vec<Obj>,
    next_object: usize,
    flags: HashMap<Obj, BitEnum<moor_common::model::ObjFlag>>,
    owners: HashMap<Obj, Obj>,
    parents: HashMap<Obj, Obj>,
    locations: HashMap<Obj, Obj>,
    names: HashMap<Obj, StringHolder>,
    verbdefs: HashMap<Obj, VerbDefs>,
    propdefs: HashMap<Obj, PropDefs>,
}

impl SnapshotInterface for FjallSnapshotLoader {
    fn start_export(&self) -> Result<Option<Box<dyn SnapshotExport + '_>>, WorldStateError> {
        Ok(Some(Box::new(FjallSnapshotExport::new(self)?)))
    }

    fn collect_export_metadata(
        &self,
        keys: &[Symbol],
    ) -> Result<Option<Vec<SnapshotExportMetadata>>, WorldStateError> {
        let mut objects = self.get_objects()?.iter().collect::<Vec<_>>();
        objects.sort_unstable();
        let parents = self.scan_object_relation(&self.object_parent_keyspace)?;
        let propdefs = self.scan_object_relation(&self.object_propdefs_keyspace)?;
        let keys = keys.iter().copied().collect::<HashSet<_>>();
        let mut records = Vec::with_capacity(objects.len());

        for oid in objects {
            let mut values = self.scan_object_metadata_keys(oid, &keys)?;
            let definitions = visible_property_definitions(oid, &parents, &propdefs);
            for key in &keys {
                if values.iter().any(|(stored_key, _)| stored_key == key) {
                    continue;
                }
                let Some(definition) = definitions
                    .iter()
                    .find(|definition| definition.name() == *key)
                else {
                    continue;
                };
                let holder = ObjAndUUIDHolder::new(&oid, definition.uuid());
                let Some(value) = self.get_from_snapshot::<ObjAndUUIDHolder, Var>(
                    &self.object_propvalues_keyspace,
                    &holder,
                )?
                else {
                    continue;
                };
                if definition.definer() != oid {
                    let definer = ObjAndUUIDHolder::new(&definition.definer(), definition.uuid());
                    let definer_value = self.get_from_snapshot::<ObjAndUUIDHolder, Var>(
                        &self.object_propvalues_keyspace,
                        &definer,
                    )?;
                    if definer_value.as_ref() == Some(&value) {
                        continue;
                    }
                }
                values.push((*key, value));
            }
            values.sort_by_key(|(key, _)| key.as_string());
            records.push(SnapshotExportMetadata {
                oid,
                parent: parents.get(&oid).copied().unwrap_or(NOTHING),
                values,
            });
        }

        Ok(Some(records))
    }

    fn get_objects(&self) -> Result<ObjSet, WorldStateError> {
        // Scan all objects by iterating through the object_flags keyspace
        let mut objects = Vec::new();

        for entry in self.snapshot.iter(&self.object_flags_keyspace) {
            let (key, _value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let obj = FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                WorldStateError::DatabaseError("Failed to decode object ID".to_string())
            })?;
            objects.push(obj);
        }

        Ok(ObjSet::from_iter(objects))
    }

    fn get_players(&self) -> Result<ObjSet, WorldStateError> {
        // Scan object flags to find objects with the Player flag
        let mut players = Vec::new();

        for entry in self.snapshot.iter(&self.object_flags_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let obj = FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                WorldStateError::DatabaseError("Failed to decode object ID".to_string())
            })?;

            let (_ts, flags) = self
                .decode::<BitEnum<moor_common::model::ObjFlag>>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            if flags.contains(moor_common::model::ObjFlag::User) {
                players.push(obj);
            }
        }

        Ok(ObjSet::from_iter(players))
    }

    fn get_object(&self, objid: &Obj) -> Result<ObjAttrs, WorldStateError> {
        Ok(ObjAttrs::new(
            self.get_object_owner(objid)?,
            self.get_object_parent(objid)?,
            self.get_object_location(objid)?,
            self.get_object_flags(objid)?,
            &self.get_object_name(objid)?,
        ))
    }

    fn get_object_verbs(&self, objid: &Obj) -> Result<VerbDefs, WorldStateError> {
        self.get_verbs(objid)
    }

    fn get_verb_program(&self, objid: &Obj, uuid: Uuid) -> Result<ProgramType, WorldStateError> {
        self.get_verb_program_internal(objid, uuid)
    }

    fn get_object_properties(&self, objid: &Obj) -> Result<PropDefs, WorldStateError> {
        self.get_properties(objid)
    }

    fn get_property_value(
        &self,
        obj: &Obj,
        uuid: Uuid,
    ) -> Result<(Option<Var>, PropPerms), WorldStateError> {
        self.retrieve_property(obj, uuid)
    }

    fn get_object_metadata(&self, objid: &Obj) -> Result<Vec<(Symbol, Var)>, WorldStateError> {
        self.metadata_scan(|metadata_key| metadata_key.is_object_key_for(*objid))
    }

    fn get_property_metadata(
        &self,
        objid: &Obj,
        uuid: Uuid,
    ) -> Result<Vec<(Symbol, Var)>, WorldStateError> {
        self.metadata_scan(|metadata_key| metadata_key.is_property_key_for(*objid, uuid))
    }

    fn get_verb_metadata(
        &self,
        objid: &Obj,
        uuid: Uuid,
    ) -> Result<Vec<(Symbol, Var)>, WorldStateError> {
        self.metadata_scan(|metadata_key| metadata_key.is_verb_key_for(*objid, uuid))
    }

    #[allow(clippy::type_complexity)]
    fn get_all_property_values(
        &self,
        this: &Obj,
    ) -> Result<Vec<(PropDef, (Option<Var>, PropPerms))>, WorldStateError> {
        // First get the entire inheritance hierarchy
        let hierarchy = self.get_ancestors(this, true).map_err(|e| {
            WorldStateError::DatabaseError(format!("Failed to get ancestors for {this}: {e}"))
        })?;

        // Now get the property definitions for each of those objects, but only for the props which
        // are defined by that object.
        let mut properties = vec![];
        for obj in hierarchy.iter() {
            // Continue through entire hierarchy, including negative ID objects (system objects)
            // This matches the working implementation behavior
            let obj_propdefs = self.get_properties(&obj).map_err(|e| {
                WorldStateError::DatabaseError(format!(
                    "Failed to get properties for {obj} (in hierarchy of {this}): {e}"
                ))
            })?;
            for p in obj_propdefs.iter() {
                if p.definer() != obj {
                    continue;
                }
                // Only include properties that actually exist on this object
                // (have permissions defined, which indicates the property was properly set up)
                match self.retrieve_property(this, p.uuid()) {
                    Ok(value) => properties.push((p.clone(), value)),
                    Err(WorldStateError::PropertyNotFound(_, _)) => {
                        // Property definition exists but property not set on this object - skip it
                        continue;
                    }
                    Err(e) => {
                        return Err(WorldStateError::DatabaseError(format!(
                            "Failed to retrieve property {} on {} (defined by {}): {}",
                            p.name(),
                            this,
                            obj,
                            e
                        )));
                    }
                }
            }
        }
        Ok(properties)
    }

    fn get_anonymous_object_metadata(
        &self,
        objid: &Obj,
    ) -> Result<Option<Box<dyn std::any::Any + Send>>, WorldStateError> {
        let metadata = self.get_from_snapshot::<Obj, AnonymousObjectMetadata>(
            &self.anonymous_object_metadata_keyspace,
            objid,
        )?;
        Ok(metadata.map(|m| Box::new(m) as Box<dyn std::any::Any + Send>))
    }

    fn scan_anonymous_object_references(&self) -> Result<Vec<(Obj, Vec<Obj>)>, WorldStateError> {
        let mut references = Vec::new();

        // Scan all property values for anonymous object references
        for entry in self.snapshot.iter(&self.object_propvalues_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            // Decode the key to get the object and property UUID
            let key_holder: ObjAndUUIDHolder =
                FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                    WorldStateError::DatabaseError("Failed to decode property key".to_string())
                })?;

            // Decode the value to get the property value
            let (_ts, prop_value) = self
                .decode::<Var>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            // Extract anonymous object references from the property value
            let anon_refs = self.extract_anonymous_refs(&prop_value);

            if !anon_refs.is_empty() {
                references.push((key_holder.obj(), anon_refs));
            }
        }

        // Metadata values can contain anonymous object references too. The metadata key itself
        // is not a root; otherwise metadata attached to an anonymous object would keep that object
        // alive solely by existing.
        for entry in self.snapshot.iter(&self.entity_metadata_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            let metadata_key: EntityMetadataKey =
                FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                    WorldStateError::DatabaseError("Failed to decode metadata key".to_string())
                })?;

            let (_ts, metadata_value) = self
                .decode::<Var>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            let anon_refs = self.extract_anonymous_refs(&metadata_value);
            if !anon_refs.is_empty() {
                references.push((metadata_key.obj(), anon_refs));
            }
        }

        Ok(references)
    }
}

impl<'a> FjallSnapshotExport<'a> {
    fn new(loader: &'a FjallSnapshotLoader) -> Result<Self, WorldStateError> {
        let flags = loader.scan_object_relation(&loader.object_flags_keyspace)?;
        let mut objects = flags.keys().copied().collect::<Vec<_>>();
        objects.sort_unstable();

        Ok(Self {
            loader,
            objects,
            next_object: 0,
            flags,
            owners: loader.scan_object_relation(&loader.object_owner_keyspace)?,
            parents: loader.scan_object_relation(&loader.object_parent_keyspace)?,
            locations: loader.scan_object_relation(&loader.object_location_keyspace)?,
            names: loader.scan_object_relation(&loader.object_name_keyspace)?,
            verbdefs: loader.scan_object_relation(&loader.object_verbdefs_keyspace)?,
            propdefs: loader.scan_object_relation(&loader.object_propdefs_keyspace)?,
        })
    }

    fn visible_property_definitions(&self, object: Obj) -> Result<Vec<PropDef>, WorldStateError> {
        Ok(visible_property_definitions(
            object,
            &self.parents,
            &self.propdefs,
        ))
    }
}

fn visible_property_definitions(
    object: Obj,
    parents: &HashMap<Obj, Obj>,
    propdefs: &HashMap<Obj, PropDefs>,
) -> Vec<PropDef> {
    let mut definitions = Vec::new();
    let mut current = object;

    loop {
        if let Some(current_propdefs) = propdefs.get(&current) {
            definitions.extend(
                current_propdefs
                    .iter()
                    .filter(|definition| definition.definer() == current),
            );
        }

        let Some(parent) = parents.get(&current).copied() else {
            break;
        };
        if parent == current || parent.is_nothing() {
            break;
        }
        current = parent;
    }

    definitions
}

impl SnapshotExport for FjallSnapshotExport<'_> {
    fn object_count(&self) -> usize {
        self.objects.len()
    }

    fn next_object(&mut self) -> Result<Option<SnapshotExportObject>, WorldStateError> {
        let Some(oid) = self.objects.get(self.next_object).copied() else {
            return Ok(None);
        };
        self.next_object += 1;

        let flags = self.flags.remove(&oid).unwrap_or_default();
        let owner = self.owners.remove(&oid).unwrap_or(NOTHING);
        let parent = self.parents.get(&oid).copied().unwrap_or(NOTHING);
        let location = self.locations.remove(&oid).unwrap_or(NOTHING);
        let name = self
            .names
            .remove(&oid)
            .ok_or(WorldStateError::ObjectNotFound(ObjectRef::Id(oid)))?;
        let attributes = ObjAttrs::new(owner, parent, location, flags, &name.0);

        let mut programs = self
            .loader
            .scan_object_uuid_relation(&self.loader.object_verbs_keyspace, oid)?;
        let (mut metadata, mut property_metadata, mut verb_metadata) =
            self.loader.scan_object_metadata(oid)?;
        let verbdefs = self.verbdefs.remove(&oid).unwrap_or_else(VerbDefs::empty);
        let mut verbs = Vec::with_capacity(verbdefs.len());
        for definition in verbdefs.iter() {
            let uuid = definition.uuid();
            let program = programs
                .remove(&uuid)
                .ok_or_else(|| WorldStateError::VerbNotFound(oid, uuid.to_string()))?;
            let mut entity_metadata = verb_metadata.remove(&uuid).unwrap_or_default();
            entity_metadata.sort_by_key(|(key, _)| key.as_string());
            verbs.push(SnapshotExportVerb {
                definition: definition.clone(),
                program,
                metadata: entity_metadata,
            });
        }

        let mut values: HashMap<Uuid, Var> = self
            .loader
            .scan_object_uuid_relation(&self.loader.object_propvalues_keyspace, oid)?;
        let mut permissions: HashMap<Uuid, PropPerms> = self
            .loader
            .scan_object_uuid_relation(&self.loader.object_propflags_keyspace, oid)?;
        let definitions = self.visible_property_definitions(oid)?;
        let mut properties = Vec::with_capacity(definitions.len());
        for definition in definitions {
            let uuid = definition.uuid();
            let mut value = values.remove(&uuid);
            let mut permission = permissions.remove(&uuid);
            let mut entity_metadata = property_metadata.remove(&uuid).unwrap_or_default();
            entity_metadata.sort_by_key(|(key, _)| key.as_string());

            if definition.definer() != oid {
                if let Some(local_value) = &value {
                    let definer = ObjAndUUIDHolder::new(&definition.definer(), uuid);
                    let definer_value = self.loader.get_from_snapshot::<ObjAndUUIDHolder, Var>(
                        &self.loader.object_propvalues_keyspace,
                        &definer,
                    )?;
                    if definer_value.as_ref() == Some(local_value) {
                        value = None;
                    }
                }
                if let Some(local_permission) = &permission {
                    let definer = ObjAndUUIDHolder::new(&definition.definer(), uuid);
                    let definer_permission = self
                        .loader
                        .get_from_snapshot::<ObjAndUUIDHolder, PropPerms>(
                            &self.loader.object_propflags_keyspace,
                            &definer,
                        )?;
                    if definer_permission.as_ref().is_some_and(|canonical| {
                        local_permission == canonical
                            || canonical.flags().contains(PropFlag::Chown)
                                && local_permission.owner() == owner
                    }) {
                        permission = None;
                    }
                }
            }

            if definition.definer() != oid
                && value.is_none()
                && permission.is_none()
                && entity_metadata.is_empty()
            {
                continue;
            }
            if definition.definer() == oid && permission.is_none() {
                return Err(WorldStateError::DatabaseError(format!(
                    "Canonical property permissions not found on definer {oid} for property {uuid}"
                )));
            }

            properties.push(SnapshotExportProperty {
                definition,
                value,
                permissions: permission,
                metadata: entity_metadata,
            });
        }

        metadata.sort_by_key(|(key, _)| key.as_string());
        Ok(Some(SnapshotExportObject {
            oid,
            attributes,
            metadata,
            verbs,
            properties,
        }))
    }
}

impl FjallSnapshotLoader {
    fn scan_object_relation<Codomain>(
        &self,
        keyspace: &fjall::Keyspace,
    ) -> Result<HashMap<Obj, Codomain>, WorldStateError>
    where
        FjallCodec: EncodeFor<Codomain, Stored = ByteView>,
    {
        let mut values = HashMap::new();
        for entry in self.snapshot.iter(keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let object = <FjallCodec as EncodeFor<Obj>>::decode(&FjallCodec, ByteView::from(key))
                .map_err(|_| {
                WorldStateError::DatabaseError("Failed to decode object ID".to_string())
            })?;
            let (_timestamp, value) = self
                .decode::<Codomain>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            values.insert(object, value);
        }
        Ok(values)
    }

    fn scan_object_uuid_relation<Codomain>(
        &self,
        keyspace: &fjall::Keyspace,
        object: Obj,
    ) -> Result<HashMap<Uuid, Codomain>, WorldStateError>
    where
        FjallCodec: EncodeFor<Codomain, Stored = ByteView>,
    {
        let prefix = <FjallCodec as EncodeFor<Obj>>::encode(&FjallCodec, &object)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let mut values = HashMap::new();
        for entry in self.snapshot.prefix(keyspace, prefix) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let holder = <FjallCodec as EncodeFor<ObjAndUUIDHolder>>::decode(
                &FjallCodec,
                ByteView::from(key),
            )
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let (_timestamp, value) = self
                .decode::<Codomain>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            values.insert(holder.uuid(), value);
        }
        Ok(values)
    }

    #[allow(clippy::type_complexity)]
    fn scan_object_metadata(
        &self,
        object: Obj,
    ) -> Result<
        (
            Vec<(Symbol, Var)>,
            HashMap<Uuid, Vec<(Symbol, Var)>>,
            HashMap<Uuid, Vec<(Symbol, Var)>>,
        ),
        WorldStateError,
    > {
        let prefix = <FjallCodec as EncodeFor<Obj>>::encode(&FjallCodec, &object)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let mut object_values = Vec::new();
        let mut property_values: HashMap<Uuid, Vec<(Symbol, Var)>> = HashMap::new();
        let mut verb_values: HashMap<Uuid, Vec<(Symbol, Var)>> = HashMap::new();

        for entry in self.snapshot.prefix(&self.entity_metadata_keyspace, prefix) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let metadata_key: EntityMetadataKey = FjallCodec
                .decode(ByteView::from(key))
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let (_timestamp, value) = self
                .decode(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let entry = (metadata_key.key(), value);

            if metadata_key.is_object() {
                object_values.push(entry);
            } else if metadata_key.is_property() {
                property_values
                    .entry(metadata_key.uuid().expect("property metadata UUID"))
                    .or_default()
                    .push(entry);
            } else if metadata_key.is_verb() {
                verb_values
                    .entry(metadata_key.uuid().expect("verb metadata UUID"))
                    .or_default()
                    .push(entry);
            }
        }

        Ok((object_values, property_values, verb_values))
    }

    fn scan_object_metadata_keys(
        &self,
        object: Obj,
        keys: &HashSet<Symbol>,
    ) -> Result<Vec<(Symbol, Var)>, WorldStateError> {
        let prefix = <FjallCodec as EncodeFor<Obj>>::encode(&FjallCodec, &object)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let mut values = Vec::new();

        for entry in self.snapshot.prefix(&self.entity_metadata_keyspace, prefix) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let metadata_key: EntityMetadataKey = FjallCodec
                .decode(ByteView::from(key))
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            if !metadata_key.is_object() || !keys.contains(&metadata_key.key()) {
                continue;
            }

            let (_timestamp, value) = self
                .decode(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            values.push((metadata_key.key(), value));
        }

        Ok(values)
    }

    /// Helper method to decode a value from a snapshot using FjallCodec
    fn decode<Codomain>(&self, user_value: Slice) -> Result<(Timestamp, Codomain), Error>
    where
        FjallCodec: EncodeFor<Codomain, Stored = ByteView>,
    {
        decode_fjall_value(user_value)
    }

    /// Helper method to get a value from a snapshot using FjallCodec
    fn get_from_snapshot<Domain, Codomain>(
        &self,
        keyspace: &fjall::Keyspace,
        domain: &Domain,
    ) -> Result<Option<Codomain>, WorldStateError>
    where
        FjallCodec: EncodeFor<Domain, Stored = ByteView> + EncodeFor<Codomain, Stored = ByteView>,
    {
        let key = FjallCodec
            .encode(domain)
            .map_err(|_| WorldStateError::DatabaseError("Failed to encode domain".to_string()))?;

        let result_opt = self
            .snapshot
            .get(keyspace, key)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let Some(result) = result_opt else {
            return Ok(None);
        };

        let (_ts, codomain) = self
            .decode::<Codomain>(result)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        Ok(Some(codomain))
    }

    // Individual getter methods for each keyspace
    fn get_object_owner(&self, objid: &Obj) -> Result<Obj, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, Obj>(&self.object_owner_keyspace, objid)?
            .unwrap_or(NOTHING))
    }

    fn get_object_parent(&self, objid: &Obj) -> Result<Obj, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, Obj>(&self.object_parent_keyspace, objid)?
            .unwrap_or(NOTHING))
    }

    fn get_object_location(&self, objid: &Obj) -> Result<Obj, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, Obj>(&self.object_location_keyspace, objid)?
            .unwrap_or(NOTHING))
    }

    fn get_object_flags(
        &self,
        objid: &Obj,
    ) -> Result<BitEnum<moor_common::model::ObjFlag>, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, BitEnum<moor_common::model::ObjFlag>>(
                &self.object_flags_keyspace,
                objid,
            )?
            .unwrap_or_default())
    }

    fn get_object_name(&self, objid: &Obj) -> Result<String, WorldStateError> {
        let name_holder = self
            .get_from_snapshot::<Obj, StringHolder>(&self.object_name_keyspace, objid)?
            .ok_or(WorldStateError::ObjectNotFound(ObjectRef::Id(*objid)))?;
        Ok(name_holder.0)
    }

    fn get_verbs(&self, objid: &Obj) -> Result<VerbDefs, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, VerbDefs>(&self.object_verbdefs_keyspace, objid)?
            .unwrap_or(VerbDefs::empty()))
    }

    fn get_verb_program_internal(
        &self,
        objid: &Obj,
        uuid: Uuid,
    ) -> Result<ProgramType, WorldStateError> {
        let key = ObjAndUUIDHolder::new(objid, uuid);
        self.get_from_snapshot::<ObjAndUUIDHolder, ProgramType>(&self.object_verbs_keyspace, &key)?
            .ok_or_else(|| WorldStateError::VerbNotFound(*objid, uuid.to_string()))
    }

    fn get_properties(&self, objid: &Obj) -> Result<PropDefs, WorldStateError> {
        Ok(self
            .get_from_snapshot::<Obj, PropDefs>(&self.object_propdefs_keyspace, objid)?
            .unwrap_or_else(PropDefs::empty))
    }

    fn retrieve_property(
        &self,
        obj: &Obj,
        uuid: Uuid,
    ) -> Result<(Option<Var>, PropPerms), WorldStateError> {
        let key = ObjAndUUIDHolder::new(obj, uuid);

        // Get property value
        let value = self
            .get_from_snapshot::<ObjAndUUIDHolder, Var>(&self.object_propvalues_keyspace, &key)?;

        // Get property permissions - if not found, this property doesn't exist on this object
        let Some(perms) = self.get_from_snapshot::<ObjAndUUIDHolder, PropPerms>(
            &self.object_propflags_keyspace,
            &key,
        )?
        else {
            return Err(WorldStateError::PropertyNotFound(*obj, uuid.to_string()));
        };

        Ok((value, perms))
    }

    fn metadata_scan<F>(&self, predicate: F) -> Result<Vec<(Symbol, Var)>, WorldStateError>
    where
        F: Fn(&EntityMetadataKey) -> bool,
    {
        let mut values = Vec::new();

        for entry in self.snapshot.iter(&self.entity_metadata_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;

            let metadata_key: EntityMetadataKey =
                FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                    WorldStateError::DatabaseError("Failed to decode metadata key".to_string())
                })?;

            if !predicate(&metadata_key) {
                continue;
            }

            let (_ts, metadata_value) = self
                .decode::<Var>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            values.push((metadata_key.key(), metadata_value));
        }

        values.sort_by_key(|(key, _)| key.as_string());
        Ok(values)
    }

    /// Get the ancestor hierarchy for an object (including the object itself if include_self is true)
    fn get_ancestors(&self, obj: &Obj, include_self: bool) -> Result<ObjSet, WorldStateError> {
        let mut ancestors = Vec::new();
        let mut current = *obj;

        if include_self {
            ancestors.push(current);
        }

        // Walk up the parent chain
        while let Some(parent) =
            self.get_from_snapshot::<Obj, Obj>(&self.object_parent_keyspace, &current)?
        {
            if parent == current {
                // Avoid infinite loops in case of self-parenting
                break;
            }
            // Stop at NOTHING - don't add system objects to hierarchy
            if parent.is_nothing() {
                break;
            }
            ancestors.push(parent);
            current = parent;
        }

        Ok(ObjSet::from_iter(ancestors))
    }
}

impl FjallSnapshotLoader {
    /// Helper method to extract anonymous object references from a Var
    fn extract_anonymous_refs(&self, var: &Var) -> Vec<Obj> {
        let mut refs = Vec::new();
        Self::extract_anonymous_refs_recursive(var, &mut refs);
        refs
    }

    /// Recursively extract anonymous object references from a Var
    fn extract_anonymous_refs_recursive(var: &Var, refs: &mut Vec<Obj>) {
        match var.variant() {
            moor_var::Variant::Obj(obj) if obj.is_anonymous() => {
                refs.push(obj);
            }
            moor_var::Variant::List(list) => {
                for item in list.iter() {
                    Self::extract_anonymous_refs_recursive(&item, refs);
                }
            }
            moor_var::Variant::Map(map) => {
                for (key, value) in map.iter() {
                    Self::extract_anonymous_refs_recursive(&key, refs);
                    Self::extract_anonymous_refs_recursive(&value, refs);
                }
            }
            moor_var::Variant::Flyweight(flyweight) => {
                // Check delegate
                let delegate = flyweight.delegate();
                if delegate.is_anonymous() {
                    refs.push(*delegate);
                }

                // Check slots (Symbol -> Var pairs)
                for (_symbol, slot_value) in flyweight.slots_storage().iter() {
                    Self::extract_anonymous_refs_recursive(slot_value, refs);
                }

                // Check contents (List)
                for item in flyweight.contents().iter() {
                    Self::extract_anonymous_refs_recursive(&item, refs);
                }
            }
            moor_var::Variant::Err(error) => {
                // Check the error's optional value field
                if let Some(error_value) = error.value() {
                    Self::extract_anonymous_refs_recursive(error_value, refs);
                }
            }
            moor_var::Variant::Lambda(lambda) => {
                // Check captured environment (stack frames)
                for frame in lambda.0.captured_env.iter() {
                    for var in frame.iter() {
                        Self::extract_anonymous_refs_recursive(var, refs);
                    }
                }
            }
            _ => {} // Other types (None, Bool, Int, Float, Str, Sym, Binary) don't contain object references
        }
    }
}
