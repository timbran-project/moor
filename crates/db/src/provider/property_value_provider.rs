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

//! Storage for `object_propvalues`, which keeps each property value as a chain of records.
//!
//! A property's records are keyed by the property and a record version. The chain is one full
//! record, followed by list-append records. Reads rebuild the value from the whole chain. The
//! batch writer owns the chains and allocates record versions, so this provider does not write.

use super::{
    Provider,
    batch_writer::{BatchOp, BatchOpSource, BatchOpType},
    property_value_store::{
        PROPERTY_VALUE_CHAIN_LIMITS, PropertyValueChain, PropertyValueScan,
        prepare_property_value_working_set, property_value_record_bounds,
        reconstruct_property_value,
    },
};
use crate::{
    ObjAndUUIDHolder, db_counters,
    tx::{Error, HashRelationIndex, RelationIndex, Timestamp, WorkingSet},
};
use ahash::AHashMap;
use moor_common::model::WorldStateTimerOp;
use moor_var::Var;

pub(crate) type SeededPropertyValueIndex = (
    Box<dyn RelationIndex<ObjAndUUIDHolder, Var>>,
    Timestamp,
    AHashMap<ObjAndUUIDHolder, PropertyValueChain>,
);

#[derive(Clone)]
pub(crate) struct PropertyValueProvider {
    relation_name: &'static str,
    fjall_keyspace: fjall::Keyspace,
}

impl PropertyValueProvider {
    pub fn new(relation_name: &'static str, fjall_keyspace: fjall::Keyspace) -> Self {
        Self {
            relation_name,
            fjall_keyspace,
        }
    }

    pub fn partition(&self) -> &fjall::Keyspace {
        &self.fjall_keyspace
    }

    /// Consume a published working set into record-chain operations for the batch writer.
    pub(crate) fn encode_property_value_working_set(
        &self,
        working_set: WorkingSet<ObjAndUUIDHolder, Var>,
    ) -> Vec<BatchOp> {
        prepare_property_value_working_set(working_set)
            .into_iter()
            .map(|prepared| {
                let object = prepared.property.obj();
                let uuid = prepared.property.uuid();
                BatchOp {
                    partition: self.fjall_keyspace.clone(),
                    op_type: BatchOpType::PropertyValue(prepared),
                    source: BatchOpSource::Property {
                        relation: self.relation_name,
                        object,
                        uuid,
                    },
                }
            })
            .collect()
    }

    /// Rebuild every property value, along with the chain state the batch writer continues from.
    pub(crate) fn seeded_property_value_index(&self) -> Result<SeededPropertyValueIndex, Error> {
        let mut index = HashRelationIndex::new();
        let mut chains = AHashMap::new();
        let mut max_timestamp = Timestamp(0);
        for entry in PropertyValueScan::new(self.fjall_keyspace.iter(), PROPERTY_VALUE_CHAIN_LIMITS)
        {
            let (property, reconstructed) =
                entry.map_err(|error| Error::RetrievalFailure(error.to_string()))?;
            max_timestamp = max_timestamp.max(reconstructed.logical_timestamp);
            chains.insert(property.clone(), reconstructed.chain);
            index.insert_entry(
                reconstructed.logical_timestamp,
                property,
                reconstructed.value,
            );
        }
        index.set_provider_fully_loaded(true);
        Ok((Box::new(index), max_timestamp, chains))
    }
}

impl Provider<ObjAndUUIDHolder, Var> for PropertyValueProvider {
    fn get(&self, domain: &ObjAndUUIDHolder) -> Result<Option<(Timestamp, Var)>, Error> {
        let _t = db_counters()
            .timers_hot
            .start(WorldStateTimerOp::ProviderTupleLoad);
        let (start, end) = property_value_record_bounds(domain);
        let reconstructed = reconstruct_property_value(
            self.fjall_keyspace.range(start..=end),
            PROPERTY_VALUE_CHAIN_LIMITS,
        )
        .map_err(|error| Error::RetrievalFailure(error.to_string()))?;
        let Some((property, reconstructed)) = reconstructed else {
            return Ok(None);
        };
        if property != *domain {
            return Err(Error::RetrievalFailure(format!(
                "property-value range for {domain} returned records for {property}"
            )));
        }
        Ok(Some((reconstructed.logical_timestamp, reconstructed.value)))
    }

    fn put(&self, _timestamp: Timestamp, domain: &ObjAndUUIDHolder, _: &Var) -> Result<(), Error> {
        Err(Error::StorageFailure(format!(
            "property value {domain} must be written through the batch writer"
        )))
    }

    fn del(&self, _timestamp: Timestamp, domain: &ObjAndUUIDHolder) -> Result<(), Error> {
        Err(Error::StorageFailure(format!(
            "property value {domain} must be deleted through the batch writer"
        )))
    }

    fn scan<F>(&self, predicate: &F) -> Result<Vec<(Timestamp, ObjAndUUIDHolder, Var)>, Error>
    where
        F: Fn(&ObjAndUUIDHolder, &Var) -> bool,
    {
        let mut result = Vec::new();
        for entry in PropertyValueScan::new(self.fjall_keyspace.iter(), PROPERTY_VALUE_CHAIN_LIMITS)
        {
            let (property, reconstructed) =
                entry.map_err(|error| Error::RetrievalFailure(error.to_string()))?;
            if predicate(&property, &reconstructed.value) {
                result.push((
                    reconstructed.logical_timestamp,
                    property,
                    reconstructed.value,
                ));
            }
        }
        Ok(result)
    }

    fn stop(&self) -> Result<(), Error> {
        Ok(())
    }
}
