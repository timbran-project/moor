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

use super::common::*;
use super::*;

/// Parse incoming objdefs and compare them with the current world state without mutating it.
pub fn analyze_preview_objdef_changes<I>(
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
        if let Ok(local) = self.world_state.name_of(self.permissions, &obj) {
            self.add_entity_change_if_needed(
                changes,
                "object_name",
                obj,
                None,
                Some(format!("{local:?}")),
                format!("{:?}", definition.name),
                self.object_base_hash(obj, "name_hash"),
            );
        }

        if let Ok(local) = self.world_state.parent_of(self.permissions, &obj) {
            self.add_entity_change_if_needed(
                changes,
                "object_parent",
                obj,
                None,
                Some(local.to_string()),
                definition.parent.to_string(),
                self.object_base_hash(obj, "parent_hash"),
            );
        }

        if let Ok(local) = self.world_state.owner_of(&obj) {
            self.add_entity_change_if_needed(
                changes,
                "object_owner",
                obj,
                None,
                Some(local.to_string()),
                definition.owner.to_string(),
                self.object_base_hash(obj, "owner_hash"),
            );
        }

        if let Ok(local) = self.world_state.location_of(self.permissions, &obj) {
            self.add_entity_change_if_needed(
                changes,
                "object_location",
                obj,
                None,
                Some(local.to_string()),
                definition.location.to_string(),
                self.object_base_hash(obj, "location_hash"),
            );
        }

        if let Ok(local) = self.world_state.flags_of(&obj) {
            self.add_entity_change_if_needed(
                changes,
                "object_flags",
                obj,
                None,
                Some(local.to_u16().to_string()),
                definition.flags.to_u16().to_string(),
                self.object_base_hash(obj, "flags_hash"),
            );
        }
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
