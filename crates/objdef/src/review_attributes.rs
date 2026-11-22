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

//! Parent and location changes for installed objects.
//!
//! Where an object is, is mostly world state: players and things move in play. So a location is
//! reviewed only when source moved the object and it is still where it was last accepted, and a
//! player's never is; a class of players can be.
//!
//! A parent change drops every property the object inherited from its old ancestors and does
//! not inherit from its new ones, from the object and all of its descendants. A row that would
//! drop a value someone set is refused, unless the same review defines that property on the
//! object itself, which restores it.

use super::{BASE_KEY, ChangeRow, ChangeTarget, ReviewError, classify, digest, inspection, record};
use moor_common::model::{ObjFlag, TaskPermissions, ValSet, WorldState, WorldStateError};
use moor_compiler::ObjectDefinition;
use moor_var::{Associative, NOTHING, Obj, Symbol, Var, v_bool, v_list, v_map, v_obj, v_str};
use std::collections::BTreeSet;

/// The attributes reviews can change on an installed object.
pub(super) const NAMES: [&str; 2] = ["parent", "location"];

pub(super) fn member_key(object: Obj, name: &str) -> String {
    format!("{object}/attribute/{name}")
}

pub(super) struct Context<'a> {
    pub world: &'a dyn WorldState,
    pub permissions: &'a TaskPermissions,
    pub object: Obj,
    pub trusted: bool,
    pub identity_matches: bool,
    pub local: &'a ObjectDefinition,
    pub incoming: &'a ObjectDefinition,
}

/// The names of the properties defined on `start` and its ancestors.
fn inherited(
    world: &dyn WorldState,
    permissions: &TaskPermissions,
    start: Obj,
) -> Result<BTreeSet<Symbol>, ReviewError> {
    let mut names = BTreeSet::new();
    let mut object = start;
    let mut visited = BTreeSet::new();
    while object != NOTHING && visited.insert(object) && world.valid(&object)? {
        for property in world.properties(permissions, &object)?.iter() {
            names.insert(property.name());
        }
        object = world.parent_of(permissions, &object)?;
    }
    Ok(names)
}

impl Context<'_> {
    /// The properties the object stops inheriting if its parent becomes `parent`.
    pub fn removed_by(&self, parent: Obj) -> Result<BTreeSet<Symbol>, ReviewError> {
        let old = inherited(self.world, self.permissions, self.local.parent)?;
        let new = inherited(self.world, self.permissions, parent)?;
        Ok(old.difference(&new).copied().collect())
    }

    /// A row for `name` when the incoming value differs from the live one.
    pub fn analyze(
        &self,
        label: &str,
        name: &'static str,
        guards: &mut Vec<Var>,
    ) -> Result<Option<(ChangeRow, Var)>, ReviewError> {
        let (live, incoming) = match name {
            "parent" => (self.local.parent, self.incoming.parent),
            _ => (self.local.location, self.incoming.location),
        };
        if live == incoming {
            return Ok(None);
        }
        let member = member_key(self.object, name);
        let id = format!("attribute/{member}");
        let live_hash = digest(&v_obj(live))?;
        let incoming_hash = digest(&v_obj(incoming))?;
        let base = inspection::baseline_hash(Some(self.local), "attribute", name);
        let classification = classify(base.as_deref(), &live_hash, &incoming_hash);
        if name == "location" && (classification != "upstream" || self.is_player_instance()?) {
            return Ok(None);
        }
        let mut blockers = Vec::new();
        if !self.trusted {
            blockers.push(v_str("untrusted_target_authority"));
        }
        if !self.identity_matches {
            blockers.push(v_str("object_identity_mismatch"));
        }
        let invalid = if name == "parent" {
            "invalid_object_parent"
        } else {
            "invalid_object_location"
        };
        if incoming != NOTHING && !self.world.valid(&incoming)? {
            blockers.push(v_str(invalid));
        } else if incoming == self.object
            || (incoming != NOTHING && self.encloses(name, incoming)?)
        {
            // An object cannot become its own ancestor, or contain its own container.
            blockers.push(v_str(invalid));
        }
        let mut removed = BTreeSet::new();
        let mut losses = Vec::new();
        let mut descendants = Vec::new();
        if name == "parent" && blockers.is_empty() {
            removed = self.removed_by(incoming)?;
            let restored: BTreeSet<_> = self
                .incoming
                .property_definitions
                .iter()
                .map(|property| property.name)
                .collect();
            let affected = self
                .world
                .descendants_of(self.permissions, &self.object, true)?;
            if affected.len() > super::MAX_ROWS {
                return Err("a parent change affects more than 8192 objects"
                    .to_owned()
                    .into());
            }
            for target in affected.iter() {
                descendants.push(v_obj(target));
                for property in &removed {
                    if !self
                        .world
                        .is_property_clear(self.permissions, &target, *property)?
                        && !(target == self.object && restored.contains(property))
                    {
                        losses.push(v_list(&[v_obj(target), v_str(property.as_str())]));
                    }
                }
            }
            if !losses.is_empty() {
                blockers.push(v_str("reparent_drops_property_values"));
            }
        }
        guards.push(v_list(&[
            v_str(&id),
            v_obj(live),
            base.as_ref()
                .map(|hash| v_str(hash))
                .unwrap_or_else(|| v_list(&[])),
            v_list(&descendants),
            v_list(&losses),
        ]));
        let eligible = blockers.is_empty();
        let default = if eligible && classification == "upstream" {
            "incoming"
        } else {
            "defer"
        };
        let choices = if eligible {
            vec![v_str("incoming"), v_str("local"), v_str("defer")]
        } else {
            vec![v_str("defer")]
        };
        let report = record(&[
            ("id", v_str(&id)),
            ("object", v_obj(self.object)),
            ("field", v_str("attribute")),
            ("name", v_str(name)),
            ("names", v_list(&[v_str(name)])),
            (
                "operation",
                v_str(if name == "parent" {
                    "set_parent"
                } else {
                    "move_object"
                }),
            ),
            ("classification", v_str(classification)),
            ("source", v_str(label)),
            (
                "base",
                base.as_ref()
                    .map(|hash| v_str(hash))
                    .unwrap_or_else(|| v_list(&[])),
            ),
            ("live", v_str(&live_hash)),
            ("incoming", v_str(&incoming_hash)),
            ("live_value", v_obj(live)),
            ("incoming_value", v_obj(incoming)),
            ("eligible", v_bool(eligible)),
            ("blockers", v_list(&blockers)),
            ("default", v_str(default)),
            ("choices", v_list(&choices)),
            ("live_present", v_bool(true)),
            ("incoming_present", v_bool(true)),
            (
                "removes",
                v_list(
                    &removed
                        .iter()
                        .map(|property| v_str(property.as_str()))
                        .collect::<Vec<_>>(),
                ),
            ),
            ("losses", v_list(&losses)),
        ]);
        Ok(Some((
            ChangeRow {
                id,
                member,
                object: self.object,
                eligible,
                target: ChangeTarget::Attribute {
                    name,
                    value: incoming,
                    removed,
                    apply: true,
                },
                incoming: None,
                incoming_hash,
                incoming_source: None,
                live_hash,
                default,
                pending: true,
            },
            report,
        )))
    }

    /// Whether the object is a player rather than a class of players: it has the player flag and
    /// no children.
    fn is_player_instance(&self) -> Result<bool, ReviewError> {
        Ok(self.world.flags_of(&self.object)?.contains(ObjFlag::User)
            && self
                .world
                .children_of(self.permissions, &self.object)?
                .is_empty())
    }

    /// Whether `target` is already the object's descendant (for a parent) or inside it (for a
    /// location), so the change would make a cycle.
    fn encloses(&self, name: &str, target: Obj) -> Result<bool, ReviewError> {
        let mut current = target;
        let mut visited = BTreeSet::new();
        while current != NOTHING && visited.insert(current) && self.world.valid(&current)? {
            if current == self.object {
                return Ok(true);
            }
            current = if name == "parent" {
                self.world.parent_of(self.permissions, &current)?
            } else {
                self.world.location_of(self.permissions, &current)?
            };
        }
        Ok(false)
    }
}

/// Change the attribute when `apply` is set, then record `hash` as its accepted value.
pub(super) fn write(
    world: &mut dyn WorldState,
    permissions: &TaskPermissions,
    object: Obj,
    name: &str,
    value: Obj,
    apply: bool,
    hash: &str,
) -> Result<(), WorldStateError> {
    if apply {
        match name {
            "parent" => world.change_parent(permissions, &object, &value)?,
            _ => world.move_object(permissions, &object, &value)?,
        }
    }
    let baseline = world
        .get_object_metadata(permissions, &object, Symbol::mk(BASE_KEY))?
        .unwrap_or_else(|| {
            record(&[
                ("schema", v_str(inspection::FIELD_SCHEMA)),
                ("property", v_map(&[])),
                ("attribute", v_map(&[])),
            ])
        });
    let map = baseline
        .as_map()
        .ok_or_else(|| WorldStateError::DatabaseError("invalid field baseline".into()))?;
    if map
        .get(&v_str("schema"))
        .ok()
        .and_then(|schema| schema.as_string().map(str::to_owned))
        .as_deref()
        != Some(inspection::FIELD_SCHEMA)
    {
        return Err(WorldStateError::DatabaseError(
            "unsupported field baseline schema".into(),
        ));
    }
    let attributes = map.get(&v_str("attribute")).unwrap_or_else(|_| v_map(&[]));
    let attributes = attributes
        .as_map()
        .ok_or_else(|| WorldStateError::DatabaseError("invalid attribute baselines".into()))?
        .set(&v_str(name), &v_str(hash))
        .map_err(|error| WorldStateError::DatabaseError(error.to_string()))?;
    let baseline = map
        .set(&v_str("attribute"), &attributes)
        .map_err(|error| WorldStateError::DatabaseError(error.to_string()))?;
    world.set_object_metadata(permissions, &object, Symbol::mk(BASE_KEY), baseline)
}
