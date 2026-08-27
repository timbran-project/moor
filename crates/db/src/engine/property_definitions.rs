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

//! Property-definition changes sent to ordered persistence consumers.

use moor_common::model::{HasUuid, PropDef, PropDefs, ValSet};
use moor_var::Obj;
use uuid::Uuid;

use crate::tx::{OpType, RelationIndex, WorkingSet};

/// A change to the authoritative property-definition set.
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) enum PropertyDefinitionChange {
    Remove(Uuid),
    Upsert(PropDef),
}

pub(crate) fn collect_property_definition_changes(
    definitions: &dyn RelationIndex<Obj, PropDefs>,
    working_set: &WorkingSet<Obj, PropDefs>,
) -> Vec<PropertyDefinitionChange> {
    if working_set.is_empty() {
        return Vec::new();
    }

    let mut changes = Vec::new();
    // Remove every old definition first. Object renumbering can move one UUID
    // between two property-definition tuples in the same transaction.
    for object in working_set.tuples_ref().keys() {
        if let Some(entry) = definitions.index_lookup(object) {
            changes.extend(
                entry
                    .value
                    .iter()
                    .map(|definition| PropertyDefinitionChange::Remove(definition.uuid())),
            );
        }
    }

    for operation in working_set.tuples_ref().values() {
        let definitions = match &operation.operation {
            OpType::Insert(definitions) | OpType::Update(definitions) => definitions,
            OpType::Delete => continue,
        };
        changes.extend(definitions.iter().map(PropertyDefinitionChange::Upsert));
    }
    changes
}
