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
use std::cmp::Ordering;
use uuid::Uuid;

use crate::{
    EntityMetadataKey, ObjAndUUIDHolder, StringHolder,
    provider::fjall_provider::{FjallCodec, decode_fjall_value, split_fjall_value},
    tx::{EncodeFor, Error, Timestamp},
};
use moor_common::{
    model::{
        HasUuid, ObjAttrs, ObjSet, ObjectRef, PropDef, PropDefs, PropPerms, ValSet, VerbArgsSpec,
        VerbDefs, VerbFlag, WorldStateError,
        loader::{
            SnapshotExportMetadata, SnapshotExportObject, SnapshotExportProperty,
            SnapshotExportSession, SnapshotExportVerb, SnapshotInterface,
        },
    },
    util::BitEnum,
};
use moor_var::{NOTHING, Obj, Symbol, Var, program::ProgramType};
use planus::ReadAsRoot;

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
}

struct FjallSnapshotExportSession {
    metadata: Vec<SnapshotExportMetadata>,
    flags: ObjectRelationCursor<BitEnum<moor_common::model::ObjFlag>>,
    owners: ObjectRelationCursor<Obj>,
    parents: SortedObjectRelation<Obj>,
    locations: ObjectRelationCursor<Obj>,
    names: ObjectRelationCursor<StringHolder>,
    verbdefs: ObjectRelationCursor<Vec<SnapshotVerbDefinition>>,
    propdefs: SortedObjectRelation<PropDefs>,
    programs: ObjectUuidRelationCursor<ProgramType>,
    values: ObjectUuidRelationCursor<Var>,
    permissions: ObjectUuidRelationCursor<PropPerms>,
    entity_metadata: ObjectMetadataCursor,
}

struct SortedObjectRelation<T> {
    entries: Vec<(Obj, T)>,
}

impl<T> SortedObjectRelation<T> {
    fn get(&self, object: Obj) -> Option<&T> {
        self.entries
            .binary_search_by_key(&object, |(object, _)| *object)
            .ok()
            .map(|index| &self.entries[index].1)
    }
}

const OBJECT_KEY_BYTES: usize = std::mem::size_of::<Obj>();
type ObjectOrderKey = [u8; OBJECT_KEY_BYTES];

fn object_order_key(bytes: &[u8]) -> Result<ObjectOrderKey, WorldStateError> {
    bytes
        .get(..OBJECT_KEY_BYTES)
        .ok_or_else(|| WorldStateError::DatabaseError("Truncated object relation key".to_string()))?
        .try_into()
        .map_err(|_| WorldStateError::DatabaseError("Invalid object relation key".to_string()))
}

struct RelationCursor<K, V> {
    iter: fjall::Iter,
    pending: Option<(ObjectOrderKey, K, V)>,
    decode_value: fn(Slice) -> Result<V, Error>,
}

impl<K, V> RelationCursor<K, V>
where
    FjallCodec: EncodeFor<K, Stored = ByteView>,
{
    fn with_decoder(
        snapshot: &fjall::Snapshot,
        keyspace: &fjall::Keyspace,
        decode_value: fn(Slice) -> Result<V, Error>,
    ) -> Self {
        Self {
            iter: snapshot.iter(keyspace),
            pending: None,
            decode_value,
        }
    }

    fn next_entry(&mut self) -> Result<Option<(ObjectOrderKey, K, V)>, WorldStateError> {
        let Some(entry) = self.iter.next() else {
            return Ok(None);
        };
        let (key, value) = entry
            .into_inner()
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let order_key = object_order_key(key.as_ref())?;
        let key = <FjallCodec as EncodeFor<K>>::decode(&FjallCodec, ByteView::from(key))
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let value = (self.decode_value)(value)
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        Ok(Some((order_key, key, value)))
    }
}

impl<K, V> RelationCursor<K, V>
where
    FjallCodec: EncodeFor<K, Stored = ByteView> + EncodeFor<V, Stored = ByteView>,
{
    fn new(snapshot: &fjall::Snapshot, keyspace: &fjall::Keyspace) -> Self {
        Self::with_decoder(snapshot, keyspace, |value| {
            decode_fjall_value(value).map(|(_, value)| value)
        })
    }
}

type ObjectRelationCursor<T> = RelationCursor<Obj, T>;

impl<T> RelationCursor<Obj, T>
where
    FjallCodec: EncodeFor<Obj, Stored = ByteView>,
{
    fn next(&mut self) -> Result<Option<(ObjectOrderKey, Obj, T)>, WorldStateError> {
        if self.pending.is_some() {
            return Ok(self.pending.take());
        }
        self.next_entry()
    }

    fn take(&mut self, target: &ObjectOrderKey) -> Result<Option<T>, WorldStateError> {
        loop {
            if self.pending.is_none() {
                self.pending = self.next_entry()?;
            }
            let Some((order_key, _, _)) = self.pending.as_ref() else {
                return Ok(None);
            };
            match order_key.cmp(target) {
                Ordering::Less => self.pending = None,
                Ordering::Equal => {
                    return Ok(self.pending.take().map(|(_, _, value)| value));
                }
                Ordering::Greater => return Ok(None),
            }
        }
    }
}

type ObjectUuidRelationCursor<T> = RelationCursor<ObjAndUUIDHolder, T>;

impl<T> RelationCursor<ObjAndUUIDHolder, T>
where
    FjallCodec: EncodeFor<ObjAndUUIDHolder, Stored = ByteView>,
{
    fn take_object(&mut self, target: &ObjectOrderKey) -> Result<UuidValues<T>, WorldStateError> {
        let mut values = Vec::new();
        loop {
            if self.pending.is_none() {
                self.pending = self.next_entry()?;
            }
            let Some((order_key, _, _)) = self.pending.as_ref() else {
                break;
            };
            match order_key.cmp(target) {
                Ordering::Less => self.pending = None,
                Ordering::Equal => {
                    let (_, holder, value) = self.pending.take().expect("pending relation entry");
                    values.push((holder.uuid(), Some(value)));
                }
                Ordering::Greater => break,
            }
        }
        Ok(UuidValues(values))
    }
}

struct SnapshotVerbDefinition {
    uuid: Uuid,
    names: Vec<Symbol>,
    argspec: VerbArgsSpec,
    owner: Obj,
    flags: BitEnum<VerbFlag>,
}

fn decode_snapshot_verbdefs(value: Slice) -> Result<Vec<SnapshotVerbDefinition>, Error> {
    let (_timestamp, payload) = split_fjall_value(value)?;
    let definitions = moor_schema::common::VerbDefsRef::read_as_root(&payload)
        .map_err(|_| Error::EncodingFailure)?;
    definitions
        .verbs()
        .map_err(|_| Error::EncodingFailure)?
        .iter()
        .map(|definition| {
            let definition = definition.map_err(|_| Error::EncodingFailure)?;
            let uuid = definition
                .uuid()
                .map_err(|_| Error::EncodingFailure)
                .and_then(|uuid| {
                    moor_schema::convert::uuid_from_ref(uuid).map_err(|_| Error::EncodingFailure)
                })?;
            let owner = definition
                .owner()
                .map_err(|_| Error::EncodingFailure)
                .and_then(|owner| {
                    moor_schema::convert::obj_from_ref(owner).map_err(|_| Error::EncodingFailure)
                })?;
            let names = definition
                .names()
                .map_err(|_| Error::EncodingFailure)?
                .iter()
                .map(|name| {
                    let name = name.map_err(|_| Error::EncodingFailure)?;
                    moor_schema::convert::symbol_from_ref(name).map_err(|_| Error::EncodingFailure)
                })
                .collect::<Result<Vec<_>, Error>>()?;
            let flags = BitEnum::from_u16(definition.flags().map_err(|_| Error::EncodingFailure)?);
            let argspec = definition
                .args()
                .map_err(|_| Error::EncodingFailure)
                .and_then(|args| {
                    moor_schema::convert::verb_args_spec_from_ref(args)
                        .map_err(|_| Error::EncodingFailure)
                })?;
            Ok(SnapshotVerbDefinition {
                uuid,
                names,
                argspec,
                owner,
                flags,
            })
        })
        .collect()
}

struct UuidValues<T>(Vec<(Uuid, Option<T>)>);

impl<T> UuidValues<T> {
    fn take(&mut self, uuid: Uuid) -> Option<T> {
        let index = self.0.binary_search_by_key(&uuid, |(uuid, _)| *uuid).ok()?;
        self.0[index].1.take()
    }
}

struct ObjectMetadata {
    object: Vec<(Symbol, Var)>,
    properties: Vec<(Uuid, Vec<(Symbol, Var)>)>,
    verbs: Vec<(Uuid, Vec<(Symbol, Var)>)>,
}

struct SelectedObjectMetadata {
    order_key: ObjectOrderKey,
    object: Obj,
    values: Vec<(Symbol, Var)>,
}

struct ObjectMetadataCursor {
    iter: fjall::Iter,
    pending: Option<(ObjectOrderKey, EntityMetadataKey, Var)>,
}

impl ObjectMetadataCursor {
    fn new(snapshot: &fjall::Snapshot, keyspace: &fjall::Keyspace) -> Self {
        Self {
            iter: snapshot.iter(keyspace),
            pending: None,
        }
    }

    fn next_entry(
        &mut self,
    ) -> Result<Option<(ObjectOrderKey, EntityMetadataKey, Var)>, WorldStateError> {
        let Some(entry) = self.iter.next() else {
            return Ok(None);
        };
        let (key, value) = entry
            .into_inner()
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let order_key = object_order_key(key.as_ref())?;
        let key = FjallCodec
            .decode(ByteView::from(key))
            .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        let (_timestamp, value) =
            decode_fjall_value(value).map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
        Ok(Some((order_key, key, value)))
    }

    fn take_object(&mut self, target: &ObjectOrderKey) -> Result<ObjectMetadata, WorldStateError> {
        let mut object = Vec::new();
        let mut properties = Vec::<(Uuid, Vec<(Symbol, Var)>)>::new();
        let mut verbs = Vec::<(Uuid, Vec<(Symbol, Var)>)>::new();
        loop {
            if self.pending.is_none() {
                self.pending = self.next_entry()?;
            }
            let Some((order_key, _, _)) = self.pending.as_ref() else {
                break;
            };
            match order_key.cmp(target) {
                Ordering::Less => self.pending = None,
                Ordering::Greater => break,
                Ordering::Equal => {
                    let (_, key, value) = self.pending.take().expect("pending metadata entry");
                    let entry = (key.key(), value);
                    if key.is_object() {
                        object.push(entry);
                    } else if key.is_property() {
                        push_metadata_entry(
                            &mut properties,
                            key.uuid().expect("property UUID"),
                            entry,
                        );
                    } else if key.is_verb() {
                        push_metadata_entry(&mut verbs, key.uuid().expect("verb UUID"), entry);
                    }
                }
            }
        }
        properties.sort_by_key(|(uuid, _)| *uuid);
        verbs.sort_by_key(|(uuid, _)| *uuid);
        Ok(ObjectMetadata {
            object,
            properties,
            verbs,
        })
    }
}

fn push_metadata_entry(
    entries: &mut Vec<(Uuid, Vec<(Symbol, Var)>)>,
    uuid: Uuid,
    entry: (Symbol, Var),
) {
    if let Some((last_uuid, values)) = entries.last_mut()
        && *last_uuid == uuid
    {
        values.push(entry);
        return;
    }
    entries.push((uuid, vec![entry]));
}

fn take_metadata(entries: &mut [(Uuid, Vec<(Symbol, Var)>)], uuid: Uuid) -> Vec<(Symbol, Var)> {
    let Ok(index) = entries.binary_search_by_key(&uuid, |(uuid, _)| *uuid) else {
        return Vec::new();
    };
    std::mem::take(&mut entries[index].1)
}

impl SnapshotInterface for FjallSnapshotLoader {
    fn begin_export(
        &self,
        metadata_keys: &[Symbol],
    ) -> Result<Box<dyn SnapshotExportSession + '_>, WorldStateError> {
        Ok(Box::new(FjallSnapshotExportSession::new(
            self,
            metadata_keys,
        )?))
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
            let obj_propdefs = self.get_properties(&obj).map_err(|e| {
                WorldStateError::DatabaseError(format!(
                    "Failed to get properties for {obj} (in hierarchy of {this}): {e}"
                ))
            })?;
            for p in obj_propdefs.iter() {
                if p.definer() != obj {
                    continue;
                }
                match self.retrieve_property(this, p.uuid()) {
                    Ok(value) => properties.push((p.clone(), value)),
                    Err(WorldStateError::PropertyNotFound(_, _)) => continue,
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
}

impl FjallSnapshotLoader {
    fn collect_export_metadata(
        &self,
        keys: &[Symbol],
        parents: &SortedObjectRelation<Obj>,
    ) -> Result<Vec<SnapshotExportMetadata>, WorldStateError> {
        let objects = self.read_object_ids()?;
        let mut selected_metadata = self.read_selected_object_metadata(keys)?;
        let mut selected_index = 0;
        let mut records = Vec::with_capacity(objects.len());

        for (order_key, oid) in objects {
            while selected_metadata
                .get(selected_index)
                .is_some_and(|metadata| metadata.order_key < order_key)
            {
                selected_index += 1;
            }
            let mut values = if selected_metadata
                .get(selected_index)
                .is_some_and(|metadata| metadata.order_key == order_key)
            {
                let index = selected_index;
                selected_index += 1;
                debug_assert_eq!(selected_metadata[index].object, oid);
                std::mem::take(&mut selected_metadata[index].values)
            } else {
                Vec::new()
            };
            values.sort_by_key(|(key, _)| key.as_string());
            records.push(SnapshotExportMetadata {
                oid,
                parent: parents.get(oid).copied().unwrap_or(NOTHING),
                values,
            });
        }

        Ok(records)
    }

    fn read_selected_object_metadata(
        &self,
        keys: &[Symbol],
    ) -> Result<Vec<SelectedObjectMetadata>, WorldStateError> {
        let mut selected = Vec::<SelectedObjectMetadata>::new();
        for entry in self.snapshot.iter(&self.entity_metadata_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let order_key = object_order_key(key.as_ref())?;
            let metadata_key: EntityMetadataKey = FjallCodec
                .decode(ByteView::from(key))
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            if !metadata_key.is_object() || !keys.contains(&metadata_key.key()) {
                continue;
            }
            let (_timestamp, value) = self
                .decode(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            if let Some(metadata) = selected.last_mut()
                && metadata.order_key == order_key
            {
                debug_assert_eq!(metadata.object, metadata_key.obj());
                metadata.values.push((metadata_key.key(), value));
            } else {
                selected.push(SelectedObjectMetadata {
                    order_key,
                    object: metadata_key.obj(),
                    values: vec![(metadata_key.key(), value)],
                });
            }
        }
        Ok(selected)
    }

    fn read_object_ids(&self) -> Result<Vec<(ObjectOrderKey, Obj)>, WorldStateError> {
        self.snapshot
            .iter(&self.object_flags_keyspace)
            .map(|entry| {
                let (key, _) = entry
                    .into_inner()
                    .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
                let order_key = object_order_key(key.as_ref())?;
                let object = FjallCodec
                    .decode(ByteView::from(key))
                    .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
                Ok((order_key, object))
            })
            .collect()
    }
}

impl FjallSnapshotExportSession {
    fn new(
        loader: &FjallSnapshotLoader,
        metadata_keys: &[Symbol],
    ) -> Result<Self, WorldStateError> {
        let parents = loader.read_object_relation(&loader.object_parent_keyspace)?;
        let propdefs = loader.read_object_relation(&loader.object_propdefs_keyspace)?;
        let metadata = loader.collect_export_metadata(metadata_keys, &parents)?;

        Ok(Self {
            metadata,
            flags: ObjectRelationCursor::new(&loader.snapshot, &loader.object_flags_keyspace),
            owners: ObjectRelationCursor::new(&loader.snapshot, &loader.object_owner_keyspace),
            parents,
            locations: ObjectRelationCursor::new(
                &loader.snapshot,
                &loader.object_location_keyspace,
            ),
            names: ObjectRelationCursor::new(&loader.snapshot, &loader.object_name_keyspace),
            verbdefs: ObjectRelationCursor::with_decoder(
                &loader.snapshot,
                &loader.object_verbdefs_keyspace,
                decode_snapshot_verbdefs,
            ),
            propdefs,
            programs: ObjectUuidRelationCursor::new(
                &loader.snapshot,
                &loader.object_verbs_keyspace,
            ),
            values: ObjectUuidRelationCursor::new(
                &loader.snapshot,
                &loader.object_propvalues_keyspace,
            ),
            permissions: ObjectUuidRelationCursor::new(
                &loader.snapshot,
                &loader.object_propflags_keyspace,
            ),
            entity_metadata: ObjectMetadataCursor::new(
                &loader.snapshot,
                &loader.entity_metadata_keyspace,
            ),
        })
    }

    fn visible_property_definitions(&self, object: Obj) -> Vec<PropDef> {
        visible_property_definitions(object, &self.parents, &self.propdefs)
    }
}

fn visible_property_definitions(
    object: Obj,
    parents: &SortedObjectRelation<Obj>,
    propdefs: &SortedObjectRelation<PropDefs>,
) -> Vec<PropDef> {
    let mut definitions = Vec::new();
    let mut current = object;

    loop {
        if let Some(current_propdefs) = propdefs.get(current) {
            definitions.extend(
                current_propdefs
                    .iter()
                    .filter(|definition| definition.definer() == current),
            );
        }

        let Some(parent) = parents.get(current).copied() else {
            break;
        };
        if parent == current || parent.is_nothing() {
            break;
        }
        current = parent;
    }

    definitions
}

impl SnapshotExportSession for FjallSnapshotExportSession {
    fn metadata(&self) -> &[SnapshotExportMetadata] {
        &self.metadata
    }

    fn object_count(&self) -> usize {
        self.metadata.len()
    }

    fn next_object(&mut self) -> Result<Option<SnapshotExportObject>, WorldStateError> {
        let Some((order_key, oid, flags)) = self.flags.next()? else {
            return Ok(None);
        };

        let owner = self.owners.take(&order_key)?.unwrap_or(NOTHING);
        let parent = self.parents.get(oid).copied().unwrap_or(NOTHING);
        let location = self.locations.take(&order_key)?.unwrap_or(NOTHING);
        let name = self
            .names
            .take(&order_key)?
            .ok_or(WorldStateError::ObjectNotFound(ObjectRef::Id(oid)))?;

        let mut programs = self.programs.take_object(&order_key)?;
        let mut metadata = self.entity_metadata.take_object(&order_key)?;
        let verbdefs = self.verbdefs.take(&order_key)?.unwrap_or_default();
        let mut verbs = Vec::with_capacity(verbdefs.len());
        for definition in verbdefs {
            let uuid = definition.uuid;
            let program = programs
                .take(uuid)
                .ok_or_else(|| WorldStateError::VerbNotFound(oid, uuid.to_string()))?;
            let mut entity_metadata = take_metadata(&mut metadata.verbs, uuid);
            entity_metadata.sort_by_key(|(key, _)| key.as_string());
            verbs.push(SnapshotExportVerb {
                names: definition.names,
                argspec: definition.argspec,
                owner: definition.owner,
                flags: definition.flags,
                program,
                metadata: entity_metadata,
            });
        }

        let mut values = self.values.take_object(&order_key)?;
        let mut permissions = self.permissions.take_object(&order_key)?;
        let definitions = self.visible_property_definitions(oid);
        let mut properties = Vec::with_capacity(definitions.len());
        for definition in definitions {
            let uuid = definition.uuid();
            let value = values.take(uuid);
            let permission = permissions.take(uuid);
            let mut entity_metadata = take_metadata(&mut metadata.properties, uuid);
            entity_metadata.sort_by_key(|(key, _)| key.as_string());

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

        metadata.object.sort_by_key(|(key, _)| key.as_string());
        Ok(Some(SnapshotExportObject {
            oid,
            name: name.0,
            parent,
            owner,
            location,
            flags,
            metadata: metadata.object,
            verbs,
            properties,
        }))
    }
}

impl FjallSnapshotLoader {
    fn read_object_relation<Codomain>(
        &self,
        keyspace: &fjall::Keyspace,
    ) -> Result<SortedObjectRelation<Codomain>, WorldStateError>
    where
        FjallCodec: EncodeFor<Codomain, Stored = ByteView>,
    {
        let mut entries = Vec::new();
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
            entries.push((object, value));
        }
        entries.sort_unstable_by_key(|(object, _)| *object);
        Ok(SortedObjectRelation { entries })
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
