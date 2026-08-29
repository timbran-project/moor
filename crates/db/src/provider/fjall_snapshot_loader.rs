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

use ahash::AHashMap;
use byteview::ByteView;
use fjall::{Readable, Slice};
use parking_lot::RwLock;
use uuid::Uuid;

use crate::{
    AnonymousObjectMetadata, EntityMetadataKey, ObjAndUUIDHolder, StringHolder,
    provider::fjall_provider::{FjallCodec, decode_fjall_value},
    tx::{EncodeFor, Error, Timestamp},
};
use moor_common::{
    model::{
        HasUuid, ObjAttrs, ObjSet, ObjectRef, PropDef, PropDefs, PropPerms, ValSet, VerbDefs,
        WorldStateError, loader::SnapshotInterface,
    },
    util::BitEnum,
};
use moor_var::{NOTHING, Obj, Symbol, Var, program::ProgramType};

/// Buffers built by a single sequential pass over the property keyspaces, holding everything a
/// whole-database walk needs so that per-object work becomes map lookups instead of random point
/// lookups into the LSM tree.
///
/// A full export of ~7.7k objects otherwise issues ~756k random point lookups (two per candidate
/// property, on every object in the inheritance chain) to emit ~47k rows, because
/// `ObjAndUUIDHolder` sorts by uuid before obj and an object's property rows are therefore
/// scattered across the keyspace. Seven of eight of those lookups miss and are discarded.
///
/// This is sound because a `fjall::Snapshot` is immutable: nothing can change underneath the
/// buffers while they are alive.
///
/// The gain comes from turning random I/O into sequential I/O, so it scales with how much of the
/// keyspace is *not* in fjall's block cache. On a small core that is already resident the win is
/// modest (~2x measured on JHCore); on a large database where each point lookup costs a disk seek
/// it is the difference the finding describes.
///
/// Cost: every property value is resident for the duration of the scan, on top of the
/// `ObjectDefinition`s being accumulated — so peak memory during collection is roughly the
/// property data twice. The buffers are released as soon as collection finishes, before anything
/// is written out.
#[derive(Default)]
pub(crate) struct FullScanCache {
    /// `object_propvalues`, bucketed by holding object.
    values: AHashMap<Obj, AHashMap<Uuid, Var>>,
    /// `object_propflags`, bucketed by holding object. Presence here is what makes a property
    /// "present on this object" — see `retrieve_property`.
    perms: AHashMap<Obj, AHashMap<Uuid, PropPerms>>,
    /// Memoized `object_propdefs`. Ancestors repeat ~5x across the chains of a real database.
    propdefs: AHashMap<Obj, PropDefs>,
    /// Memoized `object_parent`, for the ancestor walk.
    parents: AHashMap<Obj, Option<Obj>>,
    /// Encoded size of every live row read from the two property keyspaces.
    ///
    /// Free to collect here, because the scan already touches exactly the live rows and nothing
    /// else. Reported for observability — it goes in the checkpoint manifest — but deliberately
    /// *not* used to decide compaction: it is uncompressed logical size, whereas
    /// `Keyspace::disk_space()` is lz4-compressed physical size plus journals, so the ratio of the
    /// two measures compressibility at least as much as it measures dead space. See
    /// `property_live_rows`.
    property_live_bytes: u64,
    /// Number of live rows read from the two property keyspaces.
    ///
    /// This is the dead-space signal. Compared against `Keyspace::approximate_len()`, which sums
    /// per-table item counts and so counts every superseded version and tombstone, it gives a
    /// version-amplification ratio in consistent units — rows over rows — and is therefore
    /// unaffected by how well the values happen to compress.
    property_live_rows: u64,
}

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
    /// Present only between `begin_full_scan` and `end_full_scan`.
    pub(crate) full_scan: RwLock<Option<FullScanCache>>,
}

impl SnapshotInterface for FjallSnapshotLoader {
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

    fn begin_full_scan(&self) -> Result<(), WorldStateError> {
        let cache = self.build_full_scan_cache()?;
        *self.full_scan.write() = Some(cache);
        Ok(())
    }

    fn end_full_scan(&self) {
        *self.full_scan.write() = None;
    }

    fn full_scan_live_property_bytes(&self) -> Option<u64> {
        self.full_scan
            .read()
            .as_ref()
            .map(|cache| cache.property_live_bytes)
    }

    fn full_scan_live_property_rows(&self) -> Option<u64> {
        self.full_scan
            .read()
            .as_ref()
            .map(|cache| cache.property_live_rows)
    }
}

impl FjallSnapshotLoader {
    /// Sequentially read the property value and permission keyspaces once, bucketing both by
    /// holding object, and seed the propdef/parent memos from the objects seen.
    fn build_full_scan_cache(&self) -> Result<FullScanCache, WorldStateError> {
        let mut cache = FullScanCache::default();

        // `object_propvalues`: one sequential pass. This is the same iteration pattern
        // `scan_anonymous_object_references` already uses over the same keyspace.
        let mut value_rows = 0usize;
        for entry in self.snapshot.iter(&self.object_propvalues_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache.property_live_bytes += (key.len() + value.len()) as u64;
            let holder: ObjAndUUIDHolder =
                FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                    WorldStateError::DatabaseError(
                        "Failed to decode property value key".to_string(),
                    )
                })?;
            let (_ts, var) = self
                .decode::<Var>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache
                .values
                .entry(holder.obj())
                .or_default()
                .insert(holder.uuid(), var);
            value_rows += 1;
        }

        // `object_propflags`: one sequential pass.
        let mut perm_rows = 0usize;
        for entry in self.snapshot.iter(&self.object_propflags_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache.property_live_bytes += (key.len() + value.len()) as u64;
            let holder: ObjAndUUIDHolder =
                FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                    WorldStateError::DatabaseError(
                        "Failed to decode property flags key".to_string(),
                    )
                })?;
            let (_ts, perms) = self
                .decode::<PropPerms>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache
                .perms
                .entry(holder.obj())
                .or_default()
                .insert(holder.uuid(), perms);
            perm_rows += 1;
        }

        // `object_propdefs` and `object_parent` are keyed by Obj alone, so they are already
        // compact; read them sequentially too rather than re-looking-up per ancestor visit.
        for entry in self.snapshot.iter(&self.object_propdefs_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let obj: Obj = FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                WorldStateError::DatabaseError("Failed to decode propdefs key".to_string())
            })?;
            let (_ts, propdefs) = self
                .decode::<PropDefs>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache.propdefs.insert(obj, propdefs);
        }

        for entry in self.snapshot.iter(&self.object_parent_keyspace) {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            let obj: Obj = FjallCodec.decode(ByteView::from(key)).map_err(|_| {
                WorldStateError::DatabaseError("Failed to decode parent key".to_string())
            })?;
            let (_ts, parent) = self
                .decode::<Obj>(value)
                .map_err(|e| WorldStateError::DatabaseError(e.to_string()))?;
            cache.parents.insert(obj, Some(parent));
        }

        cache.property_live_rows = (value_rows + perm_rows) as u64;

        tracing::info!(
            propvalue_rows = value_rows,
            propflag_rows = perm_rows,
            objects_with_propdefs = cache.propdefs.len(),
            objects_with_parents = cache.parents.len(),
            property_live_bytes = cache.property_live_bytes,
            property_live_rows = cache.property_live_rows,
            "Prefetched property keyspaces for full snapshot scan"
        );

        Ok(cache)
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
        Ok(self.parent_of(objid)?.unwrap_or(NOTHING))
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
        if let Some(cache) = self.full_scan.read().as_ref() {
            return Ok(cache
                .propdefs
                .get(objid)
                .cloned()
                .unwrap_or_else(PropDefs::empty));
        }

        Ok(self
            .get_from_snapshot::<Obj, PropDefs>(&self.object_propdefs_keyspace, objid)?
            .unwrap_or_else(PropDefs::empty))
    }

    fn retrieve_property(
        &self,
        obj: &Obj,
        uuid: Uuid,
    ) -> Result<(Option<Var>, PropPerms), WorldStateError> {
        if let Some(cache) = self.full_scan.read().as_ref() {
            // Absence from `perms` means the property is not on this object, exactly as a missing
            // propflags row does below.
            let Some(perms) = cache.perms.get(obj).and_then(|by_uuid| by_uuid.get(&uuid)) else {
                return Err(WorldStateError::PropertyNotFound(*obj, uuid.to_string()));
            };
            let value = cache
                .values
                .get(obj)
                .and_then(|by_uuid| by_uuid.get(&uuid))
                .cloned();
            return Ok((value, perms.clone()));
        }

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
        while let Some(parent) = self.parent_of(&current)? {
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

    /// One step up the parent chain, served from the full-scan memo when one is active.
    fn parent_of(&self, obj: &Obj) -> Result<Option<Obj>, WorldStateError> {
        if let Some(cache) = self.full_scan.read().as_ref() {
            return Ok(cache.parents.get(obj).copied().flatten());
        }
        self.get_from_snapshot::<Obj, Obj>(&self.object_parent_keyspace, obj)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{Database as _, DatabaseConfig, TxDB};
    use moor_common::{
        model::{ObjectKind, PropFlag, TaskPermissions, WorldStateSource},
        util::BitEnum,
    };
    use moor_var::{SYSTEM_OBJECT, v_int, v_str};
    use std::sync::Arc;

    fn perms() -> TaskPermissions {
        TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
    }

    /// Build a small database with a four-deep inheritance chain, properties defined at several
    /// levels, values overridden on some descendants and left clear on others, and one property
    /// cleared back to inherited. That mix is what exercises the `PropertyNotFound` path the
    /// prefetch has to reproduce exactly.
    fn fixture() -> Arc<TxDB> {
        let (db, _) = TxDB::try_open(None, DatabaseConfig::default()).unwrap();
        let db = Arc::new(db);

        let mut tx = db.new_world_state().unwrap();
        let root = tx
            .create_object(
                &perms(),
                &Obj::mk_id(-1),
                &SYSTEM_OBJECT,
                BitEnum::new(),
                ObjectKind::NextObjid,
            )
            .unwrap();
        let mut chain = vec![root];
        for depth in 0..3 {
            let parent = *chain.last().unwrap();
            let child = tx
                .create_object(
                    &perms(),
                    &parent,
                    &SYSTEM_OBJECT,
                    BitEnum::new(),
                    ObjectKind::NextObjid,
                )
                .unwrap();
            // A property defined at each level of the chain.
            tx.define_property(
                &perms(),
                &parent,
                &parent,
                Symbol::mk(&format!("at_depth_{depth}")),
                &SYSTEM_OBJECT,
                BitEnum::new_with(PropFlag::Read),
                Some(v_int(depth as i64)),
            )
            .unwrap();
            chain.push(child);
        }

        // Override one inherited value deep in the chain, and clear another so it falls back to
        // the definer's value (leaving a propflags row but no propvalues row).
        let deepest = *chain.last().unwrap();
        tx.update_property(&perms(), &deepest, Symbol::mk("at_depth_0"), &v_str("mine"))
            .unwrap();
        tx.update_property(&perms(), &deepest, Symbol::mk("at_depth_1"), &v_int(99))
            .unwrap();
        tx.clear_property(&perms(), &deepest, Symbol::mk("at_depth_1"))
            .unwrap();

        // A sibling branch, so not every object shares the same chain.
        tx.create_object(
            &perms(),
            &root,
            &SYSTEM_OBJECT,
            BitEnum::new(),
            ObjectKind::NextObjid,
        )
        .unwrap();

        tx.commit().unwrap();
        db
    }

    /// The prefetched full-scan path must be indistinguishable from the point-lookup path. This is
    /// the whole correctness claim of the optimization, so assert it value-for-value.
    #[test]
    fn full_scan_prefetch_matches_point_lookups() {
        let db = fixture();
        let snapshot = db.create_snapshot().unwrap();

        let objects: Vec<Obj> = snapshot.get_objects().unwrap().iter().collect();
        assert!(objects.len() >= 5, "fixture should have several objects");

        // Baseline: read everything through the ordinary random-point-lookup path.
        let mut baseline = Vec::new();
        for obj in &objects {
            let values = snapshot.get_all_property_values(obj).unwrap();
            baseline.push((
                *obj,
                snapshot.get_object(obj).unwrap().parent(),
                snapshot.get_object_properties(obj).unwrap().len(),
                values
                    .iter()
                    .map(|(p, (value, perms))| {
                        (p.name(), p.definer(), value.clone(), perms.clone())
                    })
                    .collect::<Vec<_>>(),
            ));
        }

        // Now the same reads with the prefetch buffers active.
        snapshot.begin_full_scan().unwrap();
        for (obj, parent, propdef_count, expected) in &baseline {
            assert_eq!(
                snapshot.get_object(obj).unwrap().parent(),
                *parent,
                "parent differs for {obj} under full scan"
            );
            assert_eq!(
                snapshot.get_object_properties(obj).unwrap().len(),
                *propdef_count,
                "propdef count differs for {obj} under full scan"
            );

            let actual: Vec<_> = snapshot
                .get_all_property_values(obj)
                .unwrap()
                .iter()
                .map(|(p, (value, perms))| (p.name(), p.definer(), value.clone(), perms.clone()))
                .collect();
            assert_eq!(
                &actual, expected,
                "property values differ for {obj} under full scan"
            );
        }
        snapshot.end_full_scan();

        // And identical again once the buffers are released.
        for (obj, _, _, expected) in &baseline {
            let actual: Vec<_> = snapshot
                .get_all_property_values(obj)
                .unwrap()
                .iter()
                .map(|(p, (value, perms))| (p.name(), p.definer(), value.clone(), perms.clone()))
                .collect();
            assert_eq!(
                &actual, expected,
                "property values differ for {obj} after full scan"
            );
        }
    }

    /// A cleared property keeps its propflags row but loses its propvalues row. The prefetch must
    /// still report the property as present, with a `None` value — not skip it as not-found.
    #[test]
    fn full_scan_reports_cleared_property_as_present_with_no_value() {
        let db = fixture();
        let snapshot = db.create_snapshot().unwrap();
        let objects: Vec<Obj> = snapshot.get_objects().unwrap().iter().collect();

        snapshot.begin_full_scan().unwrap();
        let mut saw_cleared = false;
        for obj in &objects {
            for (p, (value, _perms)) in snapshot.get_all_property_values(obj).unwrap() {
                if p.name() == Symbol::mk("at_depth_1") && p.definer() != *obj && value.is_none() {
                    saw_cleared = true;
                }
            }
        }
        snapshot.end_full_scan();

        assert!(
            saw_cleared,
            "expected a cleared inherited property to appear with no value"
        );
    }

    /// The live-property-bytes figure drives automatic compaction, so it must actually be measured
    /// and must only be available while the scan is in progress. A silently-zero measurement would
    /// disable auto-compaction without any error.
    #[test]
    fn full_scan_measures_live_property_bytes_only_while_scanning() {
        let db = fixture();
        let snapshot = db.create_snapshot().unwrap();

        assert_eq!(
            snapshot.full_scan_live_property_bytes(),
            None,
            "no measurement should be available outside a full scan"
        );

        snapshot.begin_full_scan().unwrap();
        let measured = snapshot.full_scan_live_property_bytes();
        snapshot.end_full_scan();

        let measured = measured.expect("a prefetching snapshot must report live bytes");
        assert!(
            measured > 0,
            "live property bytes should be non-zero for a database with properties"
        );

        assert_eq!(
            snapshot.full_scan_live_property_bytes(),
            None,
            "the measurement should not outlive the scan buffers"
        );
    }

    /// The measurement has to track the actual volume of property data, not just be non-zero:
    /// it is one half of the amplification ratio that decides whether to rewrite the database.
    #[test]
    fn live_property_bytes_grows_with_stored_property_data() {
        let baseline = {
            let db = fixture();
            let snapshot = db.create_snapshot().unwrap();
            snapshot.begin_full_scan().unwrap();
            let bytes = snapshot.full_scan_live_property_bytes().unwrap();
            snapshot.end_full_scan();
            bytes
        };

        // Same fixture, plus one large property value.
        let db = fixture();
        let mut tx = db.new_world_state().unwrap();
        let big = v_str(&"x".repeat(256 * 1024));
        tx.define_property(
            &perms(),
            &SYSTEM_OBJECT,
            &SYSTEM_OBJECT,
            Symbol::mk("bulky"),
            &SYSTEM_OBJECT,
            BitEnum::new_with(PropFlag::Read),
            Some(big),
        )
        .unwrap();
        tx.commit().unwrap();

        let snapshot = db.create_snapshot().unwrap();
        snapshot.begin_full_scan().unwrap();
        let grown = snapshot.full_scan_live_property_bytes().unwrap();
        snapshot.end_full_scan();

        assert!(
            grown >= baseline + 256 * 1024,
            "adding a 256 KiB property value should be reflected in the live-bytes measurement \
             (baseline={baseline}, grown={grown})"
        );
    }
}
