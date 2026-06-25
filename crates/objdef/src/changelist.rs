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

//! Read-only objdef changelist analysis.
//!
//! This module compares an incoming `ObjDefSet` with the current database snapshot and produces a
//! bounded report. It does not create placeholders, mutate objects, or reuse `load_object()` as a
//! comparison mechanism. Later apply code should re-run this analysis before making changes.

use crate::{Constants, ObjDefSet, ObjDefSource, ObjdefLoaderError, import_export_id};
use moor_common::model::{
    HasUuid, Named, PropPerms, TaskPermissions, ValSet, VerbDef, WorldState, WorldStateError,
    prop_flags_string, verb_perms_string,
};
use moor_compiler::{CompileOptions, ObjectDefinition};
use moor_var::{NOTHING, Obj, SYSTEM_OBJECT, Symbol, Var, v_obj};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// Options for read-only objdef changelist analysis.
#[derive(Clone, Default)]
pub struct ChangelistOptions {
    /// Constants supplied with the incoming definitions.
    pub constants: Option<Constants>,
    /// Local constants used to detect symbolic identity drift.
    pub local_constants: HashMap<Symbol, Var>,
    /// Previously imported objects. Objects in this set but absent from incoming definitions are
    /// reported as delete candidates.
    pub base_manifest: BTreeSet<Obj>,
    /// Compare against recorded base hashes stored in entity metadata.
    pub base_metadata: bool,
    /// Prefix for base hash metadata keys.
    pub base_metadata_prefix: String,
    /// Include clean objects in the returned report.
    pub include_unchanged: bool,
}

/// Top-level read-only changelist result.
#[derive(Debug, Clone)]
pub struct ObjDefChangelist {
    pub ok: bool,
    pub objects: Vec<ChangelistObject>,
    pub conflicts: Vec<ChangelistChange>,
    pub diagnostics: Vec<ChangelistDiagnostic>,
}

/// Per-object changelist status.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ChangelistStatus {
    Create,
    Clean,
    Patch,
    UnsafeTarget,
    Conflict,
    DeleteCandidate,
}

impl ChangelistStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Create => "create",
            Self::Clean => "clean",
            Self::Patch => "patch",
            Self::UnsafeTarget => "unsafe_target",
            Self::Conflict => "conflict",
            Self::DeleteCandidate => "delete_candidate",
        }
    }
}

/// One object entry in a changelist.
#[derive(Debug, Clone)]
pub struct ChangelistObject {
    pub object: Obj,
    pub status: ChangelistStatus,
    pub automatic: bool,
    pub label: Option<String>,
    pub changes: Vec<ChangelistChange>,
}

/// One changed entity inside an object.
#[derive(Debug, Clone)]
pub struct ChangelistChange {
    pub key: Vec<Var>,
    pub kind: &'static str,
    pub object: Obj,
    pub name: Option<Symbol>,
    pub automatic: bool,
    pub conflict: bool,
    pub base_hash: Option<String>,
    pub local_hash: Option<String>,
    pub incoming_hash: Option<String>,
}

/// Non-fatal diagnostic reported by changelist analysis.
#[derive(Debug, Clone)]
pub struct ChangelistDiagnostic {
    pub kind: &'static str,
    pub object: Option<Obj>,
    pub constant: Option<Symbol>,
    pub message: String,
}

struct Analyzer<'a> {
    world_state: &'a dyn WorldState,
    permissions: &'a TaskPermissions,
    options: ChangelistOptions,
}

/// Parse incoming objdefs and compare them with the current world state without mutating it.
pub fn analyze_objdef_changelist<I>(
    world_state: &dyn WorldState,
    permissions: &TaskPermissions,
    compile_options: &CompileOptions,
    sources: I,
    options: ChangelistOptions,
) -> Result<ObjDefChangelist, ObjdefLoaderError>
where
    I: IntoIterator<Item = ObjDefSource>,
{
    let objdef_set =
        ObjDefSet::parse_sources(compile_options, None, options.constants.as_ref(), sources)?;
    Ok(Analyzer {
        world_state,
        permissions,
        options,
    }
    .analyze(objdef_set))
}

impl Analyzer<'_> {
    fn analyze(&self, objdef_set: ObjDefSet) -> ObjDefChangelist {
        let mut objects = Vec::new();
        let mut conflicts = Vec::new();
        let mut diagnostics = self.constant_diagnostics(objdef_set.constants());
        diagnostics.extend(self.graph_diagnostics(&objdef_set));
        let mut incoming_objects = BTreeSet::new();

        let mut definitions = objdef_set
            .graph()
            .object_definitions()
            .iter()
            .collect::<Vec<_>>();
        definitions.sort_by_key(|(obj, _)| **obj);

        for (obj, (_, definition)) in definitions {
            incoming_objects.insert(*obj);
            let label = objdef_set
                .graph()
                .identity(obj)
                .and_then(|identity| identity.constant)
                .map(|constant| constant.as_string());

            let entry = match self.world_state.valid(obj) {
                Ok(false) => ChangelistObject {
                    object: *obj,
                    status: ChangelistStatus::Create,
                    automatic: true,
                    label,
                    changes: Vec::new(),
                },
                Ok(true) => self.analyze_existing_object(*obj, definition, label),
                Err(err) => {
                    diagnostics.push(world_diagnostic("valid", Some(*obj), err));
                    ChangelistObject {
                        object: *obj,
                        status: ChangelistStatus::UnsafeTarget,
                        automatic: false,
                        label,
                        changes: Vec::new(),
                    }
                }
            };

            if entry.status != ChangelistStatus::Clean || self.options.include_unchanged {
                conflicts.extend(
                    entry
                        .changes
                        .iter()
                        .filter(|change| change.conflict)
                        .cloned(),
                );
                objects.push(entry);
            }
        }

        for obj in self.options.base_manifest.iter() {
            if incoming_objects.contains(obj) {
                continue;
            }
            match self.world_state.valid(obj) {
                Ok(true) => objects.push(ChangelistObject {
                    object: *obj,
                    status: ChangelistStatus::DeleteCandidate,
                    automatic: false,
                    label: None,
                    changes: vec![ChangelistChange {
                        key: vec![str_key("delete_object"), v_obj(*obj)],
                        kind: "delete_object",
                        object: *obj,
                        name: None,
                        automatic: false,
                        conflict: false,
                        base_hash: None,
                        local_hash: None,
                        incoming_hash: None,
                    }],
                }),
                Ok(false) => {}
                Err(err) => diagnostics.push(world_diagnostic("valid", Some(*obj), err)),
            }
        }

        let ok = diagnostics.is_empty()
            && objects.iter().all(|object| {
                matches!(
                    object.status,
                    ChangelistStatus::Create | ChangelistStatus::Clean | ChangelistStatus::Patch
                )
            });

        ObjDefChangelist {
            ok,
            objects,
            conflicts,
            diagnostics,
        }
    }

    fn graph_diagnostics(&self, objdef_set: &ObjDefSet) -> Vec<ChangelistDiagnostic> {
        let graph = ProposedGraphView::new(self, objdef_set);
        let mut diagnostics = Vec::new();

        diagnostics.extend(graph.reference_diagnostics());
        diagnostics.extend(graph.parent_cycle_diagnostics());
        diagnostics.extend(graph.property_override_diagnostics());
        diagnostics.extend(graph.parent_property_conflict_diagnostics());

        diagnostics
    }

    fn analyze_existing_object(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        label: Option<String>,
    ) -> ChangelistObject {
        if !self.has_base_evidence(obj, definition) {
            return ChangelistObject {
                object: obj,
                status: ChangelistStatus::UnsafeTarget,
                automatic: false,
                label,
                changes: Vec::new(),
            };
        }

        let mut changes = Vec::new();
        self.compare_attrs(obj, definition, &mut changes);
        self.compare_object_metadata(obj, definition, &mut changes);
        self.compare_property_definitions(obj, definition, &mut changes);
        self.compare_property_overrides(obj, definition, &mut changes);
        self.compare_verbs(obj, definition, &mut changes);

        let status = if changes.iter().any(|change| change.conflict) {
            ChangelistStatus::Conflict
        } else if changes.is_empty() {
            ChangelistStatus::Clean
        } else {
            ChangelistStatus::Patch
        };

        ChangelistObject {
            object: obj,
            status,
            automatic: matches!(status, ChangelistStatus::Clean | ChangelistStatus::Patch),
            label,
            changes,
        }
    }

    fn has_base_evidence(&self, obj: Obj, definition: &ObjectDefinition) -> bool {
        if !self.options.base_manifest.is_empty() && self.options.base_manifest.contains(&obj) {
            return true;
        }
        if !self.options.local_constants.is_empty() {
            for (constant, incoming_value) in self.incoming_constant_matches(obj, definition) {
                if self.options.local_constants.get(&constant) == Some(&incoming_value) {
                    return true;
                }
            }
        }
        if let Some(incoming_id) = metadata_value(&definition.metadata, import_export_id())
            && self
                .world_state
                .get_object_metadata(self.permissions, &obj, import_export_id())
                .ok()
                .flatten()
                .as_ref()
                == Some(&incoming_id)
        {
            return true;
        }
        false
    }

    fn incoming_constant_matches(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
    ) -> Vec<(Symbol, Var)> {
        let mut matches = Vec::new();
        for (constant, value) in self.options.local_constants.iter() {
            if value == &v_obj(obj) {
                matches.push((*constant, value.clone()));
            }
        }
        if let Some(import_export_id) = metadata_value(&definition.metadata, import_export_id()) {
            let Some(id) = import_export_id.as_string() else {
                return matches;
            };
            let constant = Symbol::mk(&id.to_uppercase());
            matches.push((constant, v_obj(obj)));
        }
        matches
    }

    fn constant_diagnostics(
        &self,
        incoming_constants: &HashMap<Symbol, Var>,
    ) -> Vec<ChangelistDiagnostic> {
        let mut diagnostics = Vec::new();
        for (constant, incoming) in incoming_constants {
            let Some(local) = self.options.local_constants.get(constant) else {
                continue;
            };
            if incoming == local {
                continue;
            }
            diagnostics.push(ChangelistDiagnostic {
                kind: "constant_drift",
                object: incoming.as_object(),
                constant: Some(*constant),
                message: format!(
                    "{constant} resolves to {incoming:?} incoming and {local:?} local"
                ),
            });
        }
        diagnostics
    }

    fn compare_attrs(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        changes: &mut Vec<ChangelistChange>,
    ) {
        let local = match (
            self.world_state.name_of(self.permissions, &obj),
            self.world_state.parent_of(self.permissions, &obj),
            self.world_state.owner_of(&obj),
            self.world_state.location_of(self.permissions, &obj),
            self.world_state.flags_of(&obj),
        ) {
            (Ok(name), Ok(parent), Ok(owner), Ok(location), Ok(flags)) => {
                attrs_summary(&name, parent, owner, location, flags.to_u16())
            }
            _ => return,
        };
        let incoming = attrs_summary(
            &definition.name,
            definition.parent,
            definition.owner,
            definition.location,
            definition.flags.to_u16(),
        );
        self.add_entity_change_if_needed(
            changes,
            "object_attrs",
            obj,
            None,
            Some(local),
            incoming,
            self.object_base_hash(obj, "attrs_hash"),
        );
    }

    fn compare_object_metadata(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        changes: &mut Vec<ChangelistChange>,
    ) {
        let local = match self.world_state.object_metadata(self.permissions, &obj) {
            Ok(metadata) => {
                metadata_summary(metadata, Some(self.options.base_metadata_prefix.as_str()))
            }
            Err(_) => return,
        };
        let incoming = metadata_summary(definition.metadata.clone(), None);
        self.add_entity_change_if_needed(
            changes,
            "object_metadata",
            obj,
            None,
            Some(local),
            incoming,
            self.object_base_hash(obj, "metadata_hash"),
        );
    }

    fn compare_property_definitions(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        changes: &mut Vec<ChangelistChange>,
    ) {
        for prop in &definition.property_definitions {
            let local_info = self
                .world_state
                .get_property_info(self.permissions, &obj, prop.name)
                .ok()
                .map(|(_, perms)| prop_perms_summary(&perms));
            let incoming_info = prop_perms_summary(&prop.perms);
            self.add_entity_change_if_needed(
                changes,
                "property_def",
                obj,
                Some(prop.name),
                local_info,
                incoming_info,
                self.property_base_hash(obj, prop.name, "info_hash"),
            );

            if let Some(incoming_value) = &prop.value {
                let local_value = self
                    .world_state
                    .retrieve_property(self.permissions, &obj, prop.name)
                    .ok()
                    .map(|value| format!("{value:?}"));
                self.add_entity_change_if_needed(
                    changes,
                    "property_value",
                    obj,
                    Some(prop.name),
                    local_value,
                    format!("{incoming_value:?}"),
                    self.property_base_hash(obj, prop.name, "value_hash"),
                );
            }

            let incoming_metadata = metadata_summary(prop.metadata.clone(), None);
            let local_metadata = self
                .world_state
                .property_metadata(self.permissions, &obj, prop.name)
                .ok()
                .map(|metadata| {
                    metadata_summary(metadata, Some(self.options.base_metadata_prefix.as_str()))
                });
            self.add_entity_change_if_needed(
                changes,
                "property_metadata",
                obj,
                Some(prop.name),
                local_metadata,
                incoming_metadata,
                self.property_base_hash(obj, prop.name, "metadata_hash"),
            );
        }
    }

    fn compare_property_overrides(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        changes: &mut Vec<ChangelistChange>,
    ) {
        for prop in &definition.property_overrides {
            if let Some(incoming_value) = &prop.value {
                let local_value = self
                    .world_state
                    .retrieve_property(self.permissions, &obj, prop.name)
                    .ok()
                    .map(|value| format!("{value:?}"));
                self.add_entity_change_if_needed(
                    changes,
                    "property_value",
                    obj,
                    Some(prop.name),
                    local_value,
                    format!("{incoming_value:?}"),
                    self.property_base_hash(obj, prop.name, "value_hash"),
                );
            }
            if let Some(incoming_perms) = &prop.perms_update {
                let local_info = self
                    .world_state
                    .get_property_info(self.permissions, &obj, prop.name)
                    .ok()
                    .map(|(_, perms)| prop_perms_summary(&perms));
                self.add_entity_change_if_needed(
                    changes,
                    "property_info",
                    obj,
                    Some(prop.name),
                    local_info,
                    prop_perms_summary(incoming_perms),
                    self.property_base_hash(obj, prop.name, "info_hash"),
                );
            }
        }
    }

    fn compare_verbs(
        &self,
        obj: Obj,
        definition: &ObjectDefinition,
        changes: &mut Vec<ChangelistChange>,
    ) {
        for verb in &definition.verbs {
            let Some(primary_name) = verb.names.first().copied() else {
                continue;
            };
            let local_verb = self
                .world_state
                .get_verb(self.permissions, &obj, primary_name)
                .ok();
            let local_def = local_verb.as_ref().map(verb_summary);
            let incoming_def = format!(
                "names={:?};owner={};flags={};args={:?}",
                verb.names,
                verb.owner,
                verb_perms_string(verb.flags),
                verb.argspec
            );
            self.add_entity_change_if_needed(
                changes,
                "verb_def",
                obj,
                Some(primary_name),
                local_def,
                incoming_def,
                self.verb_base_hash(obj, local_verb.as_ref(), "info_hash"),
            );

            let local_program = local_verb.as_ref().and_then(|verbdef| {
                self.world_state
                    .retrieve_verb(self.permissions, &obj, verbdef.uuid())
                    .ok()
                    .map(|(program, _)| format!("{program:?}"))
            });
            self.add_entity_change_if_needed(
                changes,
                "verb_code",
                obj,
                Some(primary_name),
                local_program,
                format!("{:?}", verb.program),
                self.verb_base_hash(obj, local_verb.as_ref(), "code_hash"),
            );

            let local_metadata = local_verb.as_ref().and_then(|verbdef| {
                self.world_state
                    .verb_metadata(self.permissions, &obj, verbdef.uuid())
                    .ok()
                    .map(|metadata| {
                        metadata_summary(metadata, Some(self.options.base_metadata_prefix.as_str()))
                    })
            });
            self.add_entity_change_if_needed(
                changes,
                "verb_metadata",
                obj,
                Some(primary_name),
                local_metadata,
                metadata_summary(verb.metadata.clone(), None),
                self.verb_base_hash(obj, local_verb.as_ref(), "metadata_hash"),
            );
        }
    }

    fn add_entity_change_if_needed(
        &self,
        changes: &mut Vec<ChangelistChange>,
        kind: &'static str,
        obj: Obj,
        name: Option<Symbol>,
        local: Option<String>,
        incoming: String,
        base_hash: Option<String>,
    ) {
        let local_hash = local.as_ref().map(|value| stable_hash(kind, value));
        let incoming_hash = stable_hash(kind, &incoming);
        if local_hash.as_deref() == Some(incoming_hash.as_str()) {
            return;
        }

        let conflict = self.options.base_metadata
            && base_hash.is_some()
            && local_hash.is_some()
            && base_hash != local_hash
            && base_hash.as_deref() != Some(incoming_hash.as_str());

        let mut key = vec![str_key(kind), v_obj(obj)];
        if let Some(name) = name {
            key.push(str_key(&name.as_string()));
        }

        changes.push(ChangelistChange {
            key,
            kind,
            object: obj,
            name,
            automatic: !conflict,
            conflict,
            base_hash,
            local_hash,
            incoming_hash: Some(incoming_hash),
        });
    }

    fn object_base_hash(&self, obj: Obj, suffix: &str) -> Option<String> {
        if !self.options.base_metadata {
            return None;
        }
        let key = Symbol::mk(&format!("{}{}", self.options.base_metadata_prefix, suffix));
        self.world_state
            .get_object_metadata(self.permissions, &obj, key)
            .ok()
            .flatten()
            .and_then(|value| value.as_string().map(ToOwned::to_owned))
    }

    fn property_base_hash(&self, obj: Obj, prop: Symbol, suffix: &str) -> Option<String> {
        if !self.options.base_metadata {
            return None;
        }
        let key = Symbol::mk(&format!("{}{}", self.options.base_metadata_prefix, suffix));
        self.world_state
            .get_property_metadata(self.permissions, &obj, prop, key)
            .ok()
            .flatten()
            .and_then(|value| value.as_string().map(ToOwned::to_owned))
    }

    fn verb_base_hash(&self, obj: Obj, verb: Option<&VerbDef>, suffix: &str) -> Option<String> {
        if !self.options.base_metadata {
            return None;
        }
        let verb = verb?;
        let key = Symbol::mk(&format!("{}{}", self.options.base_metadata_prefix, suffix));
        self.world_state
            .get_verb_metadata(self.permissions, &obj, verb.uuid(), key)
            .ok()
            .flatten()
            .and_then(|value| value.as_string().map(ToOwned::to_owned))
    }
}

struct ProposedGraphView<'a, 'b> {
    analyzer: &'a Analyzer<'b>,
    definitions: &'a HashMap<Obj, (String, ObjectDefinition)>,
    nodes: BTreeSet<Obj>,
}

impl<'a, 'b> ProposedGraphView<'a, 'b> {
    fn new(analyzer: &'a Analyzer<'b>, objdef_set: &'a ObjDefSet) -> Self {
        let definitions = objdef_set.graph().object_definitions();
        let mut nodes = definitions.keys().copied().collect::<BTreeSet<_>>();

        for obj in definitions.keys() {
            if analyzer.world_state.valid(obj).ok() != Some(true) {
                continue;
            }
            if let Ok(descendants) =
                analyzer
                    .world_state
                    .descendants_of(analyzer.permissions, obj, false)
            {
                nodes.extend(descendants.iter());
            }
        }

        Self {
            analyzer,
            definitions,
            nodes,
        }
    }

    fn reference_diagnostics(&self) -> Vec<ChangelistDiagnostic> {
        let mut diagnostics = Vec::new();
        for (obj, (_, definition)) in self.definitions {
            for (field, target) in [
                ("parent", definition.parent),
                ("location", definition.location),
                ("owner", definition.owner),
            ] {
                if self.object_exists_in_proposed_graph(target) {
                    continue;
                }
                diagnostics.push(ChangelistDiagnostic {
                    kind: "invalid_reference",
                    object: Some(*obj),
                    constant: None,
                    message: format!("{obj} has invalid {field} reference {target}"),
                });
            }
        }
        diagnostics
    }

    fn parent_cycle_diagnostics(&self) -> Vec<ChangelistDiagnostic> {
        let mut diagnostics = Vec::new();
        let mut reported = BTreeSet::new();

        for obj in self.definitions.keys() {
            let mut path = Vec::new();
            let mut seen = BTreeMap::new();
            let mut current = *obj;

            while !current.is_nothing() {
                if let Some(cycle_start) = seen.insert(current, path.len()) {
                    let cycle = path[cycle_start..]
                        .iter()
                        .map(ToString::to_string)
                        .collect::<Vec<_>>()
                        .join(" -> ");
                    if reported.insert(current) {
                        diagnostics.push(ChangelistDiagnostic {
                            kind: "parent_cycle",
                            object: Some(*obj),
                            constant: None,
                            message: format!("incoming parent graph contains a cycle: {cycle}"),
                        });
                    }
                    break;
                }

                path.push(current);
                let Some(parent) = self.effective_parent(current) else {
                    break;
                };
                current = parent;
            }
        }

        diagnostics
    }

    fn property_override_diagnostics(&self) -> Vec<ChangelistDiagnostic> {
        let mut diagnostics = Vec::new();
        for (obj, (_, definition)) in self.definitions {
            for prop in &definition.property_overrides {
                if self.ancestor_defines_property(*obj, prop.name) {
                    continue;
                }
                diagnostics.push(ChangelistDiagnostic {
                    kind: "missing_property_definition",
                    object: Some(*obj),
                    constant: None,
                    message: format!(
                        "{obj} overrides property {} but no effective ancestor defines it",
                        prop.name
                    ),
                });
            }
        }
        diagnostics
    }

    fn parent_property_conflict_diagnostics(&self) -> Vec<ChangelistDiagnostic> {
        let mut diagnostics = Vec::new();

        for (obj, (_, definition)) in self.definitions {
            if definition.parent.is_nothing() {
                continue;
            }
            let current_parent = self
                .analyzer
                .world_state
                .valid(obj)
                .ok()
                .filter(|valid| *valid)
                .and_then(|_| {
                    self.analyzer
                        .world_state
                        .parent_of(self.analyzer.permissions, obj)
                        .ok()
                });
            if current_parent == Some(definition.parent) {
                continue;
            }

            let descendant_props = self.subtree_property_names(*obj);
            if descendant_props.is_empty() {
                continue;
            }
            let ancestor_props = self.ancestor_property_names(definition.parent, true);
            for prop in descendant_props.intersection(&ancestor_props) {
                diagnostics.push(ChangelistDiagnostic {
                    kind: "parent_property_conflict",
                    object: Some(*obj),
                    constant: None,
                    message: format!(
                        "changing {obj}'s parent to {} would make property {prop} defined both on the subtree and on the new parent chain",
                        definition.parent
                    ),
                });
            }
        }

        diagnostics
    }

    fn object_exists_in_proposed_graph(&self, obj: Obj) -> bool {
        obj == NOTHING
            || obj == SYSTEM_OBJECT
            || self.definitions.contains_key(&obj)
            || self.analyzer.world_state.valid(&obj).ok() == Some(true)
    }

    fn effective_parent(&self, obj: Obj) -> Option<Obj> {
        if let Some((_, definition)) = self.definitions.get(&obj) {
            return Some(definition.parent);
        }
        if self.analyzer.world_state.valid(&obj).ok()? {
            return self
                .analyzer
                .world_state
                .parent_of(self.analyzer.permissions, &obj)
                .ok();
        }
        None
    }

    fn ancestor_defines_property(&self, obj: Obj, prop: Symbol) -> bool {
        let Some(mut current) = self.effective_parent(obj) else {
            return false;
        };

        while !current.is_nothing() {
            if self.direct_property_names(current).contains(&prop) {
                return true;
            }
            let Some(parent) = self.effective_parent(current) else {
                return false;
            };
            current = parent;
        }

        false
    }

    fn subtree_property_names(&self, root: Obj) -> BTreeSet<Symbol> {
        let mut props = BTreeSet::new();
        for obj in self.proposed_descendants(root, true) {
            props.extend(self.direct_property_names(obj));
        }
        props
    }

    fn ancestor_property_names(&self, root: Obj, include_self: bool) -> BTreeSet<Symbol> {
        let mut props = BTreeSet::new();
        let mut current = if include_self {
            root
        } else {
            match self.effective_parent(root) {
                Some(parent) => parent,
                None => return props,
            }
        };
        let mut seen = BTreeSet::new();

        while !current.is_nothing() && seen.insert(current) {
            props.extend(self.direct_property_names(current));
            let Some(parent) = self.effective_parent(current) else {
                break;
            };
            current = parent;
        }

        props
    }

    fn direct_property_names(&self, obj: Obj) -> BTreeSet<Symbol> {
        if let Some((_, definition)) = self.definitions.get(&obj) {
            return definition
                .property_definitions
                .iter()
                .map(|prop| prop.name)
                .collect();
        }

        self.analyzer
            .world_state
            .properties(self.analyzer.permissions, &obj)
            .ok()
            .map(|props| props.iter().map(|prop| prop.name()).collect())
            .unwrap_or_default()
    }

    fn proposed_descendants(&self, root: Obj, include_self: bool) -> BTreeSet<Obj> {
        let mut descendants = BTreeSet::new();
        if include_self {
            descendants.insert(root);
        }

        let mut stack = vec![root];
        while let Some(parent) = stack.pop() {
            for child in self.nodes.iter().copied() {
                if descendants.contains(&child) {
                    continue;
                }
                if self.effective_parent(child) == Some(parent) {
                    descendants.insert(child);
                    stack.push(child);
                }
            }
        }

        descendants
    }
}

fn attrs_summary(name: &str, parent: Obj, owner: Obj, location: Obj, flags: u16) -> String {
    format!("name={name:?};parent={parent};owner={owner};location={location};flags={flags}")
}

fn prop_perms_summary(perms: &PropPerms) -> String {
    format!(
        "owner={};flags={}",
        perms.owner(),
        prop_flags_string(perms.flags())
    )
}

fn verb_summary(verb: &VerbDef) -> String {
    format!(
        "names={:?};owner={};flags={};args={:?}",
        verb.names(),
        verb.owner(),
        verb_perms_string(verb.flags()),
        verb.args()
    )
}

fn metadata_summary(metadata: Vec<(Symbol, Var)>, ignore_prefix: Option<&str>) -> String {
    let mut ordered = BTreeMap::new();
    for (key, value) in metadata {
        if let Some(prefix) = ignore_prefix
            && key.as_string().starts_with(prefix)
        {
            continue;
        }
        ordered.insert(key.as_string(), format!("{value:?}"));
    }
    format!("{ordered:?}")
}

fn metadata_value(metadata: &[(Symbol, Var)], key: Symbol) -> Option<Var> {
    metadata
        .iter()
        .find_map(|(metadata_key, value)| (*metadata_key == key).then(|| value.clone()))
}

fn stable_hash(kind: &str, value: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(kind.as_bytes());
    hasher.update([0]);
    hasher.update(value.as_bytes());
    let digest = hasher.finalize();
    let mut output = String::with_capacity("sha256:".len() + digest.len() * 2);
    output.push_str("sha256:");
    for byte in digest {
        output.push_str(&format!("{byte:02x}"));
    }
    output
}

fn str_key(value: &str) -> Var {
    moor_var::v_str(value)
}

fn world_diagnostic(
    kind: &'static str,
    object: Option<Obj>,
    error: WorldStateError,
) -> ChangelistDiagnostic {
    ChangelistDiagnostic {
        kind,
        object,
        constant: None,
        message: error.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{ObjDefLoaderOptions, ObjectDefinitionLoader};
    use moor_common::{
        model::{TaskPermissions, WorldStateSource},
        util::BitEnum,
    };
    use moor_db::{Database, DatabaseConfig, TxDB};
    use moor_var::{SYSTEM_OBJECT, v_str};
    use std::{path::Path, sync::Arc};

    fn test_db(path: &Path) -> Arc<TxDB> {
        Arc::new(
            TxDB::try_open(Some(path), DatabaseConfig::default())
                .unwrap()
                .0,
        )
    }

    fn system_permissions() -> TaskPermissions {
        TaskPermissions::new(SYSTEM_OBJECT, BitEnum::new())
    }

    fn analyze(
        db: &TxDB,
        source: &str,
        options: ChangelistOptions,
    ) -> Result<ObjDefChangelist, ObjdefLoaderError> {
        let ws = db.new_world_state().unwrap();
        analyze_objdef_changelist(
            ws.as_ref(),
            &system_permissions(),
            &CompileOptions::default(),
            [ObjDefSource::new("test.moo", source)],
            options,
        )
    }

    #[test]
    fn fresh_object_is_create() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Fresh"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(result.ok);
        assert_eq!(result.objects[0].status, ChangelistStatus::Create);
    }

    #[test]
    fn existing_object_without_base_evidence_is_unsafe() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #10
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10
                name: "Incoming"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert_eq!(result.objects[0].status, ChangelistStatus::UnsafeTarget);
    }

    #[test]
    fn matching_import_export_id_allows_patch() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #10 [import_export_id -> "thing"]
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                    property title (owner: #10, flags: "rc") = "old";
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing"]
                name: "Local"
                owner: #0
                parent: #-1
                location: #-1
                property title (owner: #10, flags: "rc") = "new";
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(result.ok);
        assert_eq!(result.objects[0].status, ChangelistStatus::Patch);
        assert!(
            result.objects[0]
                .changes
                .iter()
                .any(|change| change.kind == "property_value")
        );
    }

    #[test]
    fn include_unchanged_reports_clean_existing_object() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        let source = r#"
                object #10
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                    property title (owner: #10, flags: "rc") = "same";
                endobject
                "#;
        obj_loader
            .load_single_object(
                source,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            source,
            ChangelistOptions {
                base_manifest: BTreeSet::from([Obj::mk_id(10)]),
                include_unchanged: true,
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(result.ok);
        assert_eq!(
            result.objects[0].status,
            ChangelistStatus::Clean,
            "{:?}",
            result.objects[0].changes
        );
        assert!(result.objects[0].changes.is_empty());
    }

    #[test]
    fn base_manifest_reports_delete_candidate() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #11 [import_export_id -> "old"]
                    name: "Old"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10
                name: "Incoming"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            ChangelistOptions {
                base_manifest: BTreeSet::from([Obj::mk_id(11)]),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(result.objects.iter().any(|object| {
            object.object == Obj::mk_id(11) && object.status == ChangelistStatus::DeleteCandidate
        }));
    }

    #[test]
    fn constant_drift_is_diagnostic() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            define THING = #10;
            object #10
                name: "Fresh"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            ChangelistOptions {
                local_constants: HashMap::from([(Symbol::mk("THING"), v_obj(Obj::mk_id(20)))]),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert_eq!(result.diagnostics[0].kind, "constant_drift");
    }

    #[test]
    fn base_metadata_property_value_drift_becomes_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        let base_hash = stable_hash("property_value", &format!("{:?}", v_str("base")));
        let initial_spec = format!(
            r#"
                object #10 [import_export_id -> "thing"]
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                    property title (owner: #10, flags: "rc") [base_value_hash -> "{base_hash}"] = "local";
                endobject
                "#
        );
        obj_loader
            .load_single_object(
                &initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing"]
                name: "Local"
                owner: #0
                parent: #-1
                location: #-1
                property title (owner: #10, flags: "rc") = "incoming";
            endobject
            "#,
            ChangelistOptions {
                base_metadata: true,
                base_metadata_prefix: "base_".to_string(),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert_eq!(result.objects[0].status, ChangelistStatus::Conflict);
        assert!(
            result
                .conflicts
                .iter()
                .any(|change| change.kind == "property_value")
        );
    }

    #[test]
    fn base_metadata_property_definition_drift_becomes_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #10 [import_export_id -> "thing"]
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                    property title (owner: #10, flags: "rc") [base_info_hash -> "sha256:base"] = "same";
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing"]
                name: "Local"
                owner: #0
                parent: #-1
                location: #-1
                property title (owner: #10, flags: "r") = "same";
            endobject
            "#,
            ChangelistOptions {
                base_metadata: true,
                base_metadata_prefix: "base_".to_string(),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .conflicts
                .iter()
                .any(|change| change.kind == "property_def")
        );
    }

    #[test]
    fn base_metadata_object_metadata_drift_becomes_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #10 [import_export_id -> "thing", revision -> "local", base_metadata_hash -> "sha256:base"]
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing", revision -> "incoming"]
                name: "Local"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            ChangelistOptions {
                base_metadata: true,
                base_metadata_prefix: "base_".to_string(),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .conflicts
                .iter()
                .any(|change| change.kind == "object_metadata")
        );
    }

    #[test]
    fn base_metadata_parent_change_drift_becomes_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #20
                    name: "Old Parent"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        obj_loader
            .load_single_object(
                r#"
                object #30
                    name: "New Parent"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        obj_loader
            .load_single_object(
                r#"
                object #10 [import_export_id -> "thing", base_attrs_hash -> "sha256:base"]
                    name: "Local"
                    owner: #0
                    parent: #20
                    location: #-1
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing"]
                name: "Local"
                owner: #0
                parent: #30
                location: #-1
            endobject
            "#,
            ChangelistOptions {
                base_metadata: true,
                base_metadata_prefix: "base_".to_string(),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .conflicts
                .iter()
                .any(|change| change.kind == "object_attrs")
        );
    }

    #[test]
    fn base_metadata_verb_code_drift_becomes_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        obj_loader
            .load_single_object(
                r#"
                object #10 [import_export_id -> "thing"]
                    name: "Local"
                    owner: #0
                    parent: #-1
                    location: #-1
                    verb "look" (this none none) owner: #10 flags: "rxd" [base_code_hash -> "sha256:base"]
                        return "local";
                    endverb
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #10 [import_export_id -> "thing"]
                name: "Local"
                owner: #0
                parent: #-1
                location: #-1
                verb "look" (this none none) owner: #10 flags: "rxd"
                    return "incoming";
                endverb
            endobject
            "#,
            ChangelistOptions {
                base_metadata: true,
                base_metadata_prefix: "base_".to_string(),
                ..ChangelistOptions::default()
            },
        )
        .unwrap();

        assert!(!result.ok);
        assert_eq!(result.objects[0].status, ChangelistStatus::Conflict);
        assert!(
            result
                .conflicts
                .iter()
                .any(|change| change.kind == "verb_code")
        );
    }

    #[test]
    fn graph_allows_multi_object_create_with_incoming_parent() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #11
                name: "Child"
                owner: #0
                parent: #10
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(result.ok, "{:?}", result.diagnostics);
        assert_eq!(result.objects.len(), 2);
        assert!(
            result
                .objects
                .iter()
                .all(|object| object.status == ChangelistStatus::Create)
        );
    }

    #[test]
    fn graph_allows_property_override_from_incoming_ancestor() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
                property title (owner: #10, flags: "rc") = "parent";
            endobject
            object #11
                name: "Child"
                owner: #0
                parent: #10
                location: #-1
                override title = "child";
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(result.ok, "{:?}", result.diagnostics);
    }

    #[test]
    fn graph_rejects_incoming_parent_cycle() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "A"
                owner: #0
                parent: #11
                location: #-1
            endobject
            object #11
                name: "B"
                owner: #0
                parent: #10
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == "parent_cycle"),
            "{:?}",
            result.diagnostics
        );
    }

    #[test]
    fn graph_reports_invalid_object_reference() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Orphan"
                owner: #0
                parent: #999
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == "invalid_reference"),
            "{:?}",
            result.diagnostics
        );
    }

    #[test]
    fn graph_reports_missing_property_definition_for_override() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #11
                name: "Child"
                owner: #0
                parent: #10
                location: #-1
                override missing = "child";
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == "missing_property_definition"),
            "{:?}",
            result.diagnostics
        );
    }

    #[test]
    fn graph_reports_property_definition_conflict_with_incoming_ancestor() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let result = analyze(
            &db,
            r#"
            object #10
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
                property title (owner: #10, flags: "rc") = "parent";
            endobject
            object #11
                name: "Child"
                owner: #0
                parent: #10
                location: #-1
                property title (owner: #11, flags: "rc") = "child";
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == "parent_property_conflict"),
            "{:?}",
            result.diagnostics
        );
    }

    #[test]
    fn graph_reports_parent_change_descendant_property_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        for source in [
            r#"
            object #10
                name: "Parent Without Bar"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            "#,
            r#"
            object #20
                name: "Parent With Bar"
                owner: #0
                parent: #-1
                location: #-1
                property bar (owner: #20, flags: "rc") = "from parent 20";
            endobject
            "#,
            r#"
            object #50 [import_export_id -> "middle"]
                name: "Middle Object"
                owner: #0
                parent: #10
                location: #-1
            endobject
            "#,
            r#"
            object #51
                name: "Child With Bar"
                owner: #0
                parent: #50
                location: #-1
                property bar (owner: #51, flags: "rc") = "from child 51";
            endobject
            "#,
        ] {
            obj_loader
                .load_single_object(
                    source,
                    CompileOptions::default(),
                    ObjDefLoaderOptions::default(),
                )
                .unwrap();
        }
        loader.commit().unwrap();

        let result = analyze(
            &db,
            r#"
            object #50 [import_export_id -> "middle"]
                name: "Middle Object"
                owner: #0
                parent: #20
                location: #-1
            endobject
            "#,
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(!result.ok);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == "parent_property_conflict"),
            "{:?}",
            result.diagnostics
        );
    }

    #[test]
    fn graph_handles_case_scalar_load_cannot_model() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let child = r#"
            object #11
                name: "Child"
                owner: #0
                parent: #10
                location: #-1
            endobject
            "#;

        let mut loader = db.loader_client().unwrap();
        let mut obj_loader = ObjectDefinitionLoader::new(loader.as_mut());
        let scalar_result = obj_loader.load_single_object(
            child,
            CompileOptions::default(),
            ObjDefLoaderOptions {
                validate_parent_changes: true,
                ..ObjDefLoaderOptions::default()
            },
        );
        assert!(scalar_result.is_err());

        let result = analyze(
            &db,
            &format!(
                r#"
            object #10
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            {child}
            "#
            ),
            ChangelistOptions::default(),
        )
        .unwrap();

        assert!(result.ok, "{:?}", result.diagnostics);
    }
}
