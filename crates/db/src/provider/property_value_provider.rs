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
//! Seeding rebuilds every chain, and keeps the chains for the batch writer to continue from.

use super::{
    Provider, RelationStorage,
    batch_writer::{BatchOp, BatchOpSource, BatchOpType},
    property_value_store::{
        PROPERTY_VALUE_CHAIN_LIMITS, PropertyValueChain, PropertyValueScan,
        prepare_property_value_working_set, property_value_record_bounds,
        reconstruct_property_value,
    },
};
use crate::{
    PropertyKey, db_counters,
    tx::{Error, RelationIndex, Timestamp, WorkingSet},
};
use ahash::AHashMap;
use moor_common::model::WorldStateTimerOp;
use moor_var::Var;
use std::sync::{Arc, Mutex};

type PropertyValueChains = AHashMap<PropertyKey, PropertyValueChain>;

#[derive(Clone)]
pub(crate) struct PropertyValueProvider {
    relation_name: &'static str,
    fjall_keyspace: fjall::Keyspace,
    /// The chains the last seed rebuilt, until the batch writer takes them.
    seeded_chains: Arc<Mutex<PropertyValueChains>>,
}

impl PropertyValueProvider {
    pub fn new(relation_name: &'static str, fjall_keyspace: fjall::Keyspace) -> Self {
        Self {
            relation_name,
            fjall_keyspace,
            seeded_chains: Arc::default(),
        }
    }

    /// Take the chains the last seed rebuilt, for the batch writer to continue from.
    pub(crate) fn take_seeded_chains(&self) -> PropertyValueChains {
        std::mem::take(&mut self.seeded_chains.lock().unwrap())
    }

    pub fn partition(&self) -> &fjall::Keyspace {
        &self.fjall_keyspace
    }
}

impl RelationStorage<PropertyKey, Var> for PropertyValueProvider {
    /// Consume a published working set into record-chain operations for the batch writer.
    fn encode_working_set(
        &self,
        working_set: WorkingSet<PropertyKey, Var>,
    ) -> Result<Vec<BatchOp>, Error> {
        Ok(prepare_property_value_working_set(working_set)
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
            .collect())
    }
}

impl Provider<PropertyKey, Var> for PropertyValueProvider {
    fn get(&self, domain: &PropertyKey) -> Result<Option<(Timestamp, Var)>, Error> {
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

    fn put(&self, _timestamp: Timestamp, domain: &PropertyKey, _: &Var) -> Result<(), Error> {
        Err(Error::StorageFailure(format!(
            "property value {domain} must be written through the batch writer"
        )))
    }

    fn del(&self, _timestamp: Timestamp, domain: &PropertyKey) -> Result<(), Error> {
        Err(Error::StorageFailure(format!(
            "property value {domain} must be deleted through the batch writer"
        )))
    }

    fn scan<F>(&self, predicate: &F) -> Result<Vec<(Timestamp, PropertyKey, Var)>, Error>
    where
        F: Fn(&PropertyKey, &Var) -> bool,
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

    /// Rebuild every property value, and keep the chains for the batch writer.
    fn seed(&self, index: &mut dyn RelationIndex<PropertyKey, Var>) -> Result<Timestamp, Error> {
        let mut chains = PropertyValueChains::new();
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
        *self.seeded_chains.lock().unwrap() = chains;
        Ok(max_timestamp)
    }
}
