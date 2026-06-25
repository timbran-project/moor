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

//! Database apply path for parsed objdef definitions.
//!
//! This module owns the mutating side of objdef import: creating placeholder objects, applying
//! attributes and metadata, defining properties and verbs, and resolving conflicts according to
//! loader options. It intentionally consumes parsed sets from `set.rs` for directory import so that
//! parsing, constants resolution, duplicate detection, and proposed graph construction have one
//! shared implementation.
//!
//! Use `ObjDefSet` when code needs to inspect an incoming objdef set without changing the database.
//! Use `ObjectDefinitionLoader` when code is ready to apply an objdef set or single definition to a
//! `LoaderInterface`.

use crate::{ObjDefSet, ObjDefSource, ObjdefLoaderError, set::apply_constants};
use moor_common::{
    model::{
        HasUuid, Named, ObjAttrs, ObjFlag, ObjectKind, PropDef, PropFlag, ValSet, VerbDef,
        WorldStateError, loader::LoaderInterface,
    },
    util::BitEnum,
};
use moor_compiler::{CompileOptions, ObjFileContext, ObjectDefinition, compile_object_definitions};
use moor_var::{NOTHING, Obj, Symbol, Var, program::ProgramType};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    time::Instant,
};
use tracing::info;

/// Constants supplied to objdef parsing.
///
/// Directory imports usually read constants from `constants.moo`. Builtins and future changelist
/// code may instead provide a pre-parsed map. In both cases constants are loaded into the same
/// `ObjFileContext` used for object definitions.
#[derive(Clone)]
pub enum Constants {
    /// Pre-parsed constants map
    Map(moor_var::Map),
    /// MOO file content containing constant definitions to parse
    FileContent(String),
}

/// Applies parsed objdef definitions to a database loader.
///
/// The loader is stateful for one import operation. It stores the parsed object definitions,
/// creates placeholder objects first, and then applies the remaining object state in phases so
/// parent/location/owner references can resolve across the incoming set. Conflict records are
/// accumulated as each phase compares incoming state with existing database state.
pub struct ObjectDefinitionLoader<'a> {
    object_definitions: HashMap<Obj, (String, ObjectDefinition)>,
    parsed_constants: HashMap<Symbol, Var>,
    loader: &'a mut dyn LoaderInterface,
    // Track conflicts as we go
    conflicts: Vec<(Obj, ConflictEntity)>,
}

/// How to handle an existing database entity that differs from the incoming objdef.
///
/// Conflicts can arise from object flags, parent/location/owner attributes, defined properties,
/// property overrides, verb definitions, or verb programs.
#[derive(Debug, Clone, Copy)]
pub enum ConflictMode {
    /// Indiscriminately overwrite the existing entity with the new value.
    Clobber,
    /// Skip all conflicts entirely and only add new verbs and properties that do not conflict.
    Skip,
}

/// Entity classes that can be selectively overridden during conflict handling.
#[derive(Debug, Clone, PartialEq)]
pub enum Entity {
    ObjectFlags,
    BuiltinProps,
    Parentage,
    PropertyDef(Symbol),
    PropertyValue(Symbol),
    PropertyFlag(Symbol),
    VerbDef(Vec<Symbol>),
    VerbProgram(Vec<Symbol>),
}

/// Options controlling objdef apply behavior.
pub struct ObjDefLoaderOptions {
    /// True if we're running in "dry-run" mode where we test, and collect conflicts.
    pub dry_run: bool,
    /// How to handle conflicts.
    pub conflict_mode: ConflictMode,
    /// How to allocate the object ID. If None, uses the ID from the objdef file (default).
    /// Can be NextObjid (0), Anonymous (1), UuObjId (2), or Objid(#123) for a specific ID.
    pub object_kind: Option<ObjectKind>,
    /// Optional constants for compilation (either as a map or as file content to parse)
    pub constants: Option<Constants>,
    /// The set of entities for which we will allow overriding and treat as if their specific
    /// ConflictMode was "Clobber"
    pub overrides: Vec<(Obj, Entity)>,
    /// If true, validate parent changes for cycles, invalid parents, and descendant property conflicts.
    /// Should be true for individual load_object() calls, false for bulk operations (textdump, objdef directory import).
    pub validate_parent_changes: bool,
    /// If true, remove local direct properties and verbs that are absent from the incoming object
    /// definition before applying incoming entities.
    pub remove_absent_entities: bool,
}

impl Default for ObjDefLoaderOptions {
    fn default() -> Self {
        Self {
            dry_run: false,
            conflict_mode: ConflictMode::Clobber,
            object_kind: None,
            constants: None,
            overrides: vec![],
            validate_parent_changes: false,
            remove_absent_entities: false,
        }
    }
}

#[derive(Debug, Clone)]
pub enum ConflictEntity {
    ObjectFlags(BitEnum<ObjFlag>),
    BuiltinProps(Symbol, Var),
    Parentage(Obj),
    PropertyDef(Symbol, PropDef),
    PropertyValue(Symbol, Var),
    PropertyFlag(Symbol, BitEnum<PropFlag>),
    VerbDef(Vec<Symbol>, VerbDef),
    VerbProgram(Vec<Symbol>, ProgramType),
}

/// Result summary from directory, single-object, or reload apply.
///
/// Conflict entries identify the object and incoming entity that differed from existing state.
#[derive(Debug)]
pub struct ObjDefLoaderResults {
    /// True if the caller should commit the transaction, otherwise it should be rolled back, either
    /// because we have a critical error, or the loader was run in dry-run mode.
    pub commit: bool,
    /// The set of conflicts discovered during loading, and handled using ConflictMode above
    pub conflicts: Vec<(Obj, ConflictEntity)>,
    pub loaded_objects: Vec<Obj>,
    pub num_loaded_verbs: usize,
    pub num_loaded_property_definitions: usize,
    pub num_loaded_property_overrides: usize,
}

enum AttributeKind {
    Parent,
    Location,
    Owner,
}

impl<'a> ObjectDefinitionLoader<'a> {
    /// Create a loader that applies objdefs through the supplied database loader interface.
    pub fn new(loader: &'a mut dyn LoaderInterface) -> Self {
        Self {
            object_definitions: HashMap::new(),
            parsed_constants: HashMap::new(),
            loader,
            conflicts: Vec::new(),
        }
    }

    fn definition_counts(&self) -> (usize, usize, usize) {
        let verbs = self
            .object_definitions
            .values()
            .map(|(_, d)| d.verbs.len())
            .sum();
        let property_defs = self
            .object_definitions
            .values()
            .map(|(_, d)| d.property_definitions.len())
            .sum();
        let property_overrides = self
            .object_definitions
            .values()
            .map(|(_, d)| d.property_overrides.len())
            .sum();
        (verbs, property_defs, property_overrides)
    }

    /// Check if an entity should be overridden regardless of conflict mode
    fn should_override(&self, obj: &Obj, entity: &Entity, options: &ObjDefLoaderOptions) -> bool {
        options.overrides.contains(&(*obj, entity.clone()))
    }

    /// Determine the effective conflict mode for a given entity
    fn effective_conflict_mode(
        &self,
        obj: &Obj,
        entity: &Entity,
        options: &ObjDefLoaderOptions,
    ) -> ConflictMode {
        if self.should_override(obj, entity, options) {
            ConflictMode::Clobber
        } else {
            options.conflict_mode
        }
    }

    /// Check if we should proceed with an operation based on conflict detection
    /// Returns (should_proceed, conflict_option)
    fn check_conflict<T: Clone + PartialEq>(
        &self,
        obj: &Obj,
        entity: Entity,
        current_value: Option<T>,
        new_value: &T,
        conflict_entity_fn: impl FnOnce(T) -> ConflictEntity,
        options: &ObjDefLoaderOptions,
    ) -> (bool, Option<(Obj, ConflictEntity)>) {
        // If there's no current value, no conflict
        let Some(current) = current_value else {
            return (true, None);
        };

        // If values are the same, no conflict
        if &current == new_value {
            return (true, None);
        }

        // We have a conflict - create conflict record
        let conflict = conflict_entity_fn(current.clone());
        let conflict_record = (*obj, conflict);

        // Determine how to handle the conflict
        let should_proceed = match self.effective_conflict_mode(obj, &entity, options) {
            ConflictMode::Clobber => true, // Proceed with overwrite
            ConflictMode::Skip => false,   // Skip this operation
        };

        (should_proceed, Some(conflict_record))
    }

    /// Recursively collect all .moo files in a directory tree
    fn collect_moo_files_recursive(path: &Path) -> std::io::Result<Vec<PathBuf>> {
        let mut files = Vec::new();

        if path.is_dir() {
            for entry in std::fs::read_dir(path)? {
                let entry = entry?;
                let entry_path = entry.path();

                if entry_path.is_dir() {
                    // Recursively collect files from subdirectories
                    files.extend(Self::collect_moo_files_recursive(&entry_path)?);
                } else if entry_path.is_file()
                    && entry_path
                        .extension()
                        .map(|ext| ext == "moo")
                        .unwrap_or(false)
                {
                    files.push(entry_path);
                }
            }
        }

        Ok(files)
    }

    /// Load an objdef directory into the database.
    ///
    /// This reads `constants.moo` from the directory root when present, reads every other `.moo`
    /// file recursively, parses all sources through `ObjDefSet`, then applies the parsed graph in
    /// loader phases. Existing public import behavior is preserved, but parsing/staging is shared
    /// with read-only objdef-set analysis.
    pub fn load_objdef_directory(
        &mut self,
        compile_options: CompileOptions,
        dirpath: &Path,
        options: ObjDefLoaderOptions,
    ) -> Result<ObjDefLoaderResults, ObjdefLoaderError> {
        let compilation_started_at = Instant::now();
        // Check that the directory exists
        if !dirpath.exists() {
            return Err(ObjdefLoaderError::DirectoryNotFound(dirpath.to_path_buf()));
        }

        // Verb compilation options
        let mut compile_options = compile_options.clone();
        compile_options.call_unsupported_builtins = true;

        // Recursively collect all .moo files
        let filenames = Self::collect_moo_files_recursive(dirpath)
            .expect("Unable to recursively read import directory");

        let mut sources = Vec::new();
        let constants_file = filenames
            .iter()
            .find(|f| f.file_name().unwrap() == "constants.moo" && f.parent().unwrap() == dirpath);

        if let Some(constants_file) = constants_file {
            let constants_file_contents = std::fs::read_to_string(constants_file)
                .map_err(|e| ObjdefLoaderError::ObjectFileReadError(constants_file.clone(), e))?;
            sources.push(ObjDefSource::from_path(
                constants_file.to_path_buf(),
                constants_file_contents,
            ));
        }

        for object_file in filenames {
            if object_file.extension().unwrap() != "moo"
                || object_file.file_name().unwrap() == "constants.moo"
            {
                continue;
            }

            let object_file_contents = std::fs::read_to_string(object_file.clone())
                .map_err(|e| ObjdefLoaderError::ObjectFileReadError(object_file.clone(), e))?;
            sources.push(ObjDefSource::from_path(object_file, object_file_contents));
        }

        let objdef_set = ObjDefSet::parse_sources(&compile_options, Some(dirpath), None, sources)?;
        let constant_count = objdef_set.constants().len();
        self.stage_objdef_set(objdef_set)?;

        info!(
            directory = %dirpath.display(),
            object_count = self.object_definitions.len(),
            constant_count,
            elapsed_ms = compilation_started_at.elapsed().as_secs_f64() * 1000.0,
            "Compiled object definition directory"
        );

        let (num_loaded_verbs, num_loaded_property_definitions, num_loaded_property_overrides) =
            self.definition_counts();

        info!(
            "Created {} objects. Adjusting inheritance, location, and ownership attributes...",
            self.object_definitions.len()
        );
        self.apply_attributes(&options)?;
        self.apply_object_metadata()?;
        if options.remove_absent_entities {
            self.remove_absent_entities()?;
        }
        info!("Defining {} properties...", num_loaded_property_definitions);
        self.define_properties(&options)?;
        info!(
            "Overriding {} property values...",
            num_loaded_property_overrides
        );
        self.set_properties(&options)?;
        info!("Defining and compiling {} verbs...", num_loaded_verbs);
        self.define_verbs(&options)?;

        // Auto-create import_export_id metadata if we loaded using the heuristic
        self.create_import_export_ids_if_needed()?;

        Ok(ObjDefLoaderResults {
            commit: !options.dry_run,
            conflicts: self.conflicts.clone(),
            loaded_objects: self.object_definitions.keys().cloned().collect(),
            num_loaded_verbs,
            num_loaded_property_definitions,
            num_loaded_property_overrides,
        })
    }

    /// Load an in-memory objdef source set into the database.
    ///
    /// This is the mutating counterpart to read-only objdef change preview. It parses all sources
    /// through `ObjDefSet`, creates placeholders for incoming objects, and applies the staged graph
    /// with the same phased loader used by directory import.
    pub fn load_objdef_sources<I>(
        &mut self,
        compile_options: CompileOptions,
        sources: I,
        options: ObjDefLoaderOptions,
    ) -> Result<ObjDefLoaderResults, ObjdefLoaderError>
    where
        I: IntoIterator<Item = ObjDefSource>,
    {
        let objdef_set =
            ObjDefSet::parse_sources(&compile_options, None, options.constants.as_ref(), sources)?;
        self.stage_objdef_set(objdef_set)?;

        let (num_loaded_verbs, num_loaded_property_definitions, num_loaded_property_overrides) =
            self.definition_counts();

        self.apply_attributes(&options)?;
        self.apply_object_metadata()?;
        if options.remove_absent_entities {
            self.remove_absent_entities()?;
        }
        self.define_properties(&options)?;
        self.set_properties(&options)?;
        self.define_verbs(&options)?;
        self.create_import_export_ids_if_needed()?;

        Ok(ObjDefLoaderResults {
            commit: !options.dry_run,
            conflicts: self.conflicts.clone(),
            loaded_objects: self.object_definitions.keys().cloned().collect(),
            num_loaded_verbs,
            num_loaded_property_definitions,
            num_loaded_property_overrides,
        })
    }

    #[cfg(test)]
    fn parse_objects(
        &mut self,
        path: &Path,
        context: &mut ObjFileContext,
        object_file_contents: &str,
        compile_options: &CompileOptions,
    ) -> Result<(), ObjdefLoaderError> {
        context.set_base_path(path);
        let path_str = path.to_string_lossy().into_owned();
        let compiled_defs =
            compile_object_definitions(object_file_contents, compile_options, context).map_err(
                |e| ObjdefLoaderError::ObjectDefParseError(path_str.clone(), Box::new(e)),
            )?;

        for compiled_def in compiled_defs {
            let oid = compiled_def.oid;

            self.object_definitions
                .insert(oid, (path_str.clone(), compiled_def));
        }
        self.parsed_constants = context.constants().clone();
        self.create_placeholder_objects()?;
        Ok(())
    }

    /// Attach a parsed objdef set to this loader and create placeholder objects.
    ///
    /// Placeholder creation keeps the existing import algorithm intact: all incoming objects exist
    /// before attributes, properties, and verbs are applied, so references inside the set can resolve
    /// during later phases.
    fn stage_objdef_set(&mut self, objdef_set: ObjDefSet) -> Result<(), ObjdefLoaderError> {
        let (object_definitions, constants) = objdef_set.into_parts();
        self.object_definitions = object_definitions;
        self.create_placeholder_objects()?;
        self.parsed_constants = constants;
        Ok(())
    }

    fn create_placeholder_objects(&mut self) -> Result<(), ObjdefLoaderError> {
        for (oid, (path, compiled_def)) in &self.object_definitions {
            self.loader
                .create_object(
                    ObjectKind::Objid(*oid),
                    &ObjAttrs::new(
                        NOTHING,
                        NOTHING,
                        NOTHING,
                        compiled_def.flags,
                        &compiled_def.name,
                    ),
                )
                .map_err(|wse| ObjdefLoaderError::CouldNotCreateObject(path.clone(), *oid, wse))?;
        }
        Ok(())
    }

    pub fn apply_attributes(
        &mut self,
        options: &ObjDefLoaderOptions,
    ) -> Result<(), ObjdefLoaderError> {
        // First phase: collect all conflicts
        let mut attribute_actions: Vec<(Obj, AttributeKind, Obj, String)> = Vec::new();

        for (obj, (path, def)) in &self.object_definitions {
            // Check if object already exists
            let existing_attrs = self
                .loader
                .get_existing_object(obj)
                .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(path.clone(), e))?;

            if let Some(existing) = existing_attrs {
                // Check parent conflict (always check if existing parent differs)
                if existing.parent() != Some(def.parent) {
                    let (should_proceed, conflict) = self.check_conflict(
                        obj,
                        Entity::Parentage,
                        existing.parent(),
                        &def.parent,
                        ConflictEntity::Parentage,
                        options,
                    );
                    if let Some(conflict) = conflict {
                        self.conflicts.push(conflict);
                    }
                    if should_proceed {
                        attribute_actions.push((
                            *obj,
                            AttributeKind::Parent,
                            def.parent,
                            path.clone(),
                        ));
                    }
                }

                // Check location conflict
                if def.location != NOTHING {
                    let (should_proceed, conflict) = self.check_conflict(
                        obj,
                        Entity::BuiltinProps,
                        existing.location(),
                        &def.location,
                        |current| {
                            ConflictEntity::BuiltinProps(
                                Symbol::mk("location"),
                                moor_var::v_obj(current),
                            )
                        },
                        options,
                    );
                    if let Some(conflict) = conflict {
                        self.conflicts.push(conflict);
                    }
                    if should_proceed {
                        attribute_actions.push((
                            *obj,
                            AttributeKind::Location,
                            def.location,
                            path.clone(),
                        ));
                    }
                }

                // Check owner conflict
                if def.owner != NOTHING {
                    let (should_proceed, conflict) = self.check_conflict(
                        obj,
                        Entity::BuiltinProps,
                        existing.owner(),
                        &def.owner,
                        |current| {
                            ConflictEntity::BuiltinProps(
                                Symbol::mk("owner"),
                                moor_var::v_obj(current),
                            )
                        },
                        options,
                    );
                    if let Some(conflict) = conflict {
                        self.conflicts.push(conflict);
                    }
                    if should_proceed {
                        attribute_actions.push((
                            *obj,
                            AttributeKind::Owner,
                            def.owner,
                            path.clone(),
                        ));
                    }
                }

                // Check flags conflict
                let (should_proceed, conflict) = self.check_conflict(
                    obj,
                    Entity::ObjectFlags,
                    Some(existing.flags()),
                    &def.flags,
                    ConflictEntity::ObjectFlags,
                    options,
                );
                if let Some(conflict) = conflict {
                    self.conflicts.push(conflict);
                }
                if should_proceed {
                    self.loader
                        .update_object_flags(obj, def.flags)
                        .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(path.clone(), e))?;
                } else {
                    // In Skip mode, restore the original flags (since object was created with empty flags)
                    self.loader
                        .update_object_flags(obj, existing.flags())
                        .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(path.clone(), e))?;
                }
            } else {
                // Object doesn't exist yet, add all non-nothing attributes
                if def.parent != NOTHING {
                    attribute_actions.push((*obj, AttributeKind::Parent, def.parent, path.clone()));
                }
                if def.location != NOTHING {
                    attribute_actions.push((
                        *obj,
                        AttributeKind::Location,
                        def.location,
                        path.clone(),
                    ));
                }
                if def.owner != NOTHING {
                    attribute_actions.push((*obj, AttributeKind::Owner, def.owner, path.clone()));
                }
            }
        }

        // Second phase: apply all the actions
        for (obj, kind, value, path) in attribute_actions {
            match kind {
                AttributeKind::Parent => {
                    self.loader
                        .set_object_parent(&obj, &value, options.validate_parent_changes)
                        .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(path.clone(), e))?;
                }
                AttributeKind::Location => {
                    self.loader.set_object_location(&obj, &value).map_err(|e| {
                        ObjdefLoaderError::CouldNotSetObjectLocation(path.clone(), e)
                    })?;
                }
                AttributeKind::Owner => {
                    self.loader
                        .set_object_owner(&obj, &value)
                        .map_err(|e| ObjdefLoaderError::CouldNotSetObjectOwner(path.clone(), e))?;
                }
            }
        }
        Ok(())
    }

    fn apply_object_metadata(&mut self) -> Result<(), ObjdefLoaderError> {
        for (obj, (path, def)) in &self.object_definitions {
            for (key, value) in &def.metadata {
                self.loader
                    .set_object_metadata(obj, *key, value.clone())
                    .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(path.clone(), e))?;
            }
        }
        Ok(())
    }

    fn remove_absent_entities(&mut self) -> Result<(), ObjdefLoaderError> {
        for (obj, (path, def)) in &self.object_definitions {
            let incoming_properties = def
                .property_definitions
                .iter()
                .map(|prop| prop.name)
                .collect::<std::collections::HashSet<_>>();
            let existing_properties = self.loader.get_existing_properties(obj).map_err(|e| {
                ObjdefLoaderError::CouldNotDefineProperty(path.clone(), *obj, String::new(), e)
            })?;
            for prop in existing_properties.iter() {
                if incoming_properties.contains(&prop.name()) {
                    continue;
                }
                self.loader.delete_property(obj, prop.name()).map_err(|e| {
                    ObjdefLoaderError::CouldNotDefineProperty(
                        path.clone(),
                        *obj,
                        prop.name().as_arc_str().to_string(),
                        e,
                    )
                })?;
            }

            let incoming_verbs = def
                .verbs
                .iter()
                .map(|verb| verb.names.clone())
                .collect::<Vec<_>>();
            let existing_verbs = self.loader.get_existing_verbs(obj).map_err(|e| {
                ObjdefLoaderError::CouldNotDefineVerb(path.clone(), *obj, vec![], e)
            })?;
            for verb in existing_verbs.iter() {
                if incoming_verbs.iter().any(|names| names == verb.names()) {
                    continue;
                }
                self.loader.remove_verb(obj, verb.uuid()).map_err(|e| {
                    ObjdefLoaderError::CouldNotDefineVerb(path.clone(), *obj, vec![], e)
                })?;
            }
        }
        Ok(())
    }

    pub fn define_verbs(&mut self, options: &ObjDefLoaderOptions) -> Result<(), ObjdefLoaderError> {
        // First phase: collect conflicts and determine actions
        let mut verb_actions = Vec::new();

        for (obj, (path, def)) in &self.object_definitions {
            for v in &def.verbs {
                // Check if verb already exists
                let existing_verb = self
                    .loader
                    .get_existing_verb_by_names(obj, &v.names)
                    .map_err(|wse| {
                        ObjdefLoaderError::CouldNotDefineVerb(
                            path.clone(),
                            *obj,
                            v.names.clone(),
                            wse,
                        )
                    })?;

                if let Some((existing_uuid, existing_verbdef)) = existing_verb {
                    // Verb exists - check for conflicts in both metadata and program
                    // Create a comparable VerbDef for metadata comparison
                    let new_verbdef = VerbDef::new(
                        existing_uuid, // Use existing UUID for fair comparison
                        *obj,          // location
                        v.owner,       // owner
                        &v.names,      // names
                        v.flags,       // flags
                        v.argspec,     // args
                    );

                    // Check for metadata conflicts
                    let (should_proceed_metadata, conflict_metadata) = self.check_conflict(
                        obj,
                        Entity::VerbDef(v.names.clone()),
                        Some(existing_verbdef.clone()),
                        &new_verbdef,
                        |current| ConflictEntity::VerbDef(v.names.clone(), current),
                        options,
                    );

                    // Also check if the program changed
                    let existing_program = self
                        .loader
                        .get_verb_program(obj, existing_uuid)
                        .map_err(|wse| {
                            ObjdefLoaderError::CouldNotDefineVerb(
                                path.clone(),
                                *obj,
                                v.names.clone(),
                                wse,
                            )
                        })?;

                    let program_changed = existing_program != v.program;

                    // Determine final conflict and proceed status
                    let mut should_proceed = should_proceed_metadata;
                    if let Some(conflict) = conflict_metadata {
                        self.conflicts.push(conflict);
                    } else if program_changed {
                        // Metadata matches but program differs - still a conflict
                        let conflict =
                            ConflictEntity::VerbDef(v.names.clone(), existing_verbdef.clone());
                        self.conflicts.push((*obj, conflict));

                        // Apply conflict mode to program-only changes
                        should_proceed = match self.effective_conflict_mode(
                            obj,
                            &Entity::VerbDef(v.names.clone()),
                            options,
                        ) {
                            ConflictMode::Clobber => true,
                            ConflictMode::Skip => false,
                        };
                    }

                    if should_proceed {
                        // Use update_verb for existing verbs in Clobber mode
                        self.loader
                            .update_verb(
                                obj,
                                existing_uuid,
                                &v.names,
                                &v.owner,
                                v.flags,
                                v.argspec,
                                v.program.clone(),
                            )
                            .map_err(|wse| {
                                ObjdefLoaderError::CouldNotDefineVerb(
                                    path.clone(),
                                    *obj,
                                    v.names.clone(),
                                    wse,
                                )
                            })?;
                        for (key, value) in &v.metadata {
                            self.loader
                                .set_verb_metadata(obj, existing_uuid, *key, value.clone())
                                .map_err(|wse| {
                                    ObjdefLoaderError::CouldNotDefineVerb(
                                        path.clone(),
                                        *obj,
                                        v.names.clone(),
                                        wse,
                                    )
                                })?;
                        }
                    }
                } else {
                    // Verb doesn't exist, add it
                    verb_actions.push((*obj, v.clone(), path.clone()));
                }
            }
        }

        // Second phase: apply all the verb actions
        for (obj, verb, path) in verb_actions {
            self.loader
                .add_verb(
                    &obj,
                    &verb.names,
                    &verb.owner,
                    verb.flags,
                    verb.argspec,
                    verb.program.clone(),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotDefineVerb(
                        path.clone(),
                        obj,
                        verb.names.clone(),
                        wse,
                    )
                })?;
            let Some((uuid, _)) = self
                .loader
                .get_existing_verb_by_names(&obj, &verb.names)
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotDefineVerb(
                        path.clone(),
                        obj,
                        verb.names.clone(),
                        wse,
                    )
                })?
            else {
                return Err(ObjdefLoaderError::CouldNotDefineVerb(
                    path.clone(),
                    obj,
                    verb.names.clone(),
                    WorldStateError::VerbNotFound(obj, verb.names[0].to_string()),
                ));
            };
            for (key, value) in &verb.metadata {
                self.loader
                    .set_verb_metadata(&obj, uuid, *key, value.clone())
                    .map_err(|wse| {
                        ObjdefLoaderError::CouldNotDefineVerb(
                            path.clone(),
                            obj,
                            verb.names.clone(),
                            wse,
                        )
                    })?;
            }
        }
        Ok(())
    }
    pub fn define_properties(
        &mut self,
        options: &ObjDefLoaderOptions,
    ) -> Result<(), ObjdefLoaderError> {
        // Track actions as either create or update
        let mut create_actions = Vec::new();
        let mut update_actions = Vec::new();

        for (obj, (path, def)) in &self.object_definitions {
            for pd in &def.property_definitions {
                // Check if property already exists
                let existing_value = self
                    .loader
                    .get_existing_property_value(obj, pd.name)
                    .map_err(|wse| {
                        ObjdefLoaderError::CouldNotDefineProperty(
                            path.clone(),
                            *obj,
                            pd.name.as_arc_str().to_string(),
                            wse,
                        )
                    })?;

                if let Some((existing_val, existing_perms)) = existing_value {
                    // Property exists - check for conflicts
                    let mut should_proceed = true;

                    // Check value conflict if we're defining a value
                    if let Some(new_value) = &pd.value {
                        let (proceed_value, conflict) = self.check_conflict(
                            obj,
                            Entity::PropertyValue(pd.name),
                            Some(existing_val.clone()),
                            new_value,
                            |current| ConflictEntity::PropertyValue(pd.name, current),
                            options,
                        );
                        if let Some(conflict) = conflict {
                            self.conflicts.push(conflict);
                        }
                        should_proceed &= proceed_value;
                    }

                    // Check permissions conflict
                    let (proceed_perms, conflict) = self.check_conflict(
                        obj,
                        Entity::PropertyFlag(pd.name),
                        Some(existing_perms.flags()),
                        &pd.perms.flags(),
                        |current| ConflictEntity::PropertyFlag(pd.name, current),
                        options,
                    );
                    if let Some(conflict) = conflict {
                        self.conflicts.push(conflict);
                    }
                    should_proceed &= proceed_perms;

                    if should_proceed {
                        // Property exists and we should proceed (Clobber mode) - use update
                        update_actions.push((*obj, pd.clone(), path.clone()));
                    }
                } else {
                    // Property doesn't exist, define it
                    create_actions.push((*obj, pd.clone(), path.clone()));
                }
            }
        }

        // Apply create actions using define_property
        for (obj, prop_def, path) in create_actions {
            self.loader
                .define_property(
                    &obj,
                    &obj,
                    prop_def.name,
                    &prop_def.perms.owner(),
                    prop_def.perms.flags(),
                    prop_def.value.clone(),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotDefineProperty(
                        path.clone(),
                        obj,
                        prop_def.name.as_arc_str().to_string(),
                        wse,
                    )
                })?;
            self.apply_property_metadata(&path, &obj, prop_def.name, &prop_def.metadata)?;
        }

        // Apply update actions using set_property
        for (obj, prop_def, path) in update_actions {
            self.loader
                .set_property(
                    &obj,
                    prop_def.name,
                    Some(prop_def.perms.owner()),
                    Some(prop_def.perms.flags()),
                    prop_def.value.clone(),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotDefineProperty(
                        path.clone(),
                        obj,
                        prop_def.name.as_arc_str().to_string(),
                        wse,
                    )
                })?;
            self.apply_property_metadata(&path, &obj, prop_def.name, &prop_def.metadata)?;
        }

        Ok(())
    }

    fn apply_property_metadata(
        &mut self,
        path: &str,
        obj: &Obj,
        propname: Symbol,
        metadata: &[(Symbol, Var)],
    ) -> Result<(), ObjdefLoaderError> {
        for (key, value) in metadata {
            self.loader
                .set_property_metadata(obj, propname, *key, value.clone())
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotDefineProperty(
                        path.to_string(),
                        *obj,
                        propname.as_arc_str().to_string(),
                        wse,
                    )
                })?;
        }
        Ok(())
    }

    fn set_properties(&mut self, options: &ObjDefLoaderOptions) -> Result<(), ObjdefLoaderError> {
        // First phase: collect conflicts and determine actions
        let mut override_actions = Vec::new();

        for (obj, (path, def)) in &self.object_definitions {
            for pv in &def.property_overrides {
                // Check existing property value for conflicts
                let existing_value = self
                    .loader
                    .get_existing_property_value(obj, pv.name)
                    .map_err(|wse| {
                        ObjdefLoaderError::CouldNotOverrideProperty(
                            path.clone(),
                            *obj,
                            pv.name.as_arc_str().to_string(),
                            wse,
                        )
                    })?;

                let mut should_proceed = true;

                if let Some((existing_val, existing_perms)) = existing_value {
                    // Check value conflict if we're setting a new value
                    if let Some(new_value) = &pv.value {
                        let (proceed_value, conflict) = self.check_conflict(
                            obj,
                            Entity::PropertyValue(pv.name),
                            Some(existing_val),
                            new_value,
                            |current| ConflictEntity::PropertyValue(pv.name, current),
                            options,
                        );
                        if let Some(conflict) = conflict {
                            self.conflicts.push(conflict);
                        }
                        should_proceed &= proceed_value;
                    }

                    // Check permissions conflict if we're updating permissions
                    if let Some(pu) = &pv.perms_update {
                        let (proceed_perms, conflict) = self.check_conflict(
                            obj,
                            Entity::PropertyFlag(pv.name),
                            Some(existing_perms.flags()),
                            &pu.flags(),
                            |current| ConflictEntity::PropertyFlag(pv.name, current),
                            options,
                        );
                        if let Some(conflict) = conflict {
                            self.conflicts.push(conflict);
                        }
                        should_proceed &= proceed_perms;
                    }
                }

                if should_proceed {
                    override_actions.push((*obj, pv.clone(), path.clone()));
                }
            }
        }

        // Second phase: apply all the override actions
        for (obj, prop_override, path) in override_actions {
            let pu = &prop_override.perms_update;
            self.loader
                .set_property(
                    &obj,
                    prop_override.name,
                    pu.as_ref().map(|p| p.owner()),
                    pu.as_ref().map(|p| p.flags()),
                    prop_override.value.clone(),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotOverrideProperty(
                        path.clone(),
                        obj,
                        prop_override.name.as_arc_str().to_string(),
                        wse,
                    )
                })?;
            self.apply_property_metadata(&path, &obj, prop_override.name, &prop_override.metadata)?;
        }
        Ok(())
    }

    /// Load one object definition from a string.
    ///
    /// This is the scalar import path used by `load_object()`. It accepts exactly one object
    /// definition, optionally uses caller-supplied constants, and applies conflict handling according
    /// to `options`.
    pub fn load_single_object(
        &mut self,
        object_definition: &str,
        compile_options: CompileOptions,
        options: ObjDefLoaderOptions,
    ) -> Result<ObjDefLoaderResults, ObjdefLoaderError> {
        let start_time = Instant::now();
        let source_name = "<string>".to_string();

        // Create a fresh context for this single object
        let mut context = ObjFileContext::new();

        // Parse constants if provided
        if let Some(constants) = &options.constants {
            apply_constants(constants, &mut context, &source_name)?;
        }

        // Parse the object definition
        let compiled_defs =
            compile_object_definitions(object_definition, &compile_options, &mut context).map_err(
                |e| ObjdefLoaderError::ObjectDefParseError(source_name.clone(), Box::new(e)),
            )?;

        // Ensure we got exactly one object
        if compiled_defs.len() != 1 {
            return Err(ObjdefLoaderError::SingleObjectExpected(
                source_name,
                compiled_defs.len(),
            ));
        }

        let compiled_def = compiled_defs.into_iter().next().unwrap();

        // Determine the ObjectKind to use for creation
        let object_kind = match &options.object_kind {
            None => ObjectKind::Objid(compiled_def.oid), // Use the ID from objdef file (default)
            Some(kind) => kind.clone(), // Use specified kind (NextObjid, UuObjId, Anonymous, or specific Objid)
        };

        // Extract the expected object ID for conflict detection (only valid for Objid kind)
        let expected_oid = match object_kind {
            ObjectKind::Objid(id) => Some(id),
            _ => None,
        };

        // Check if object already exists (only for specific Objid)
        let existing_obj = if let Some(obj_id) = expected_oid {
            self.loader
                .get_existing_object(&obj_id)
                .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(source_name.clone(), e))?
        } else {
            None
        };

        // Only create the object if it doesn't exist
        let oid = if existing_obj.is_none() {
            self.loader
                .create_object(
                    object_kind,
                    &ObjAttrs::new(
                        NOTHING,
                        NOTHING,
                        NOTHING,
                        compiled_def.flags,
                        &compiled_def.name,
                    ),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotCreateObject(
                        source_name.clone(),
                        expected_oid.unwrap_or(NOTHING),
                        wse,
                    )
                })?
        } else {
            // Object exists, use its ID
            expected_oid.unwrap()
        };

        // Store the definition for processing
        self.object_definitions
            .insert(oid, (source_name.clone(), compiled_def));

        // Use the conflict-aware methods instead of inline logic
        self.apply_attributes(&options)?;
        self.apply_object_metadata()?;
        if options.remove_absent_entities {
            self.remove_absent_entities()?;
        }
        self.define_properties(&options)?;
        self.set_properties(&options)?;
        self.define_verbs(&options)?;

        let (num_loaded_verbs, num_loaded_property_definitions, num_loaded_property_overrides) =
            self.definition_counts();

        info!(
            "Loaded single object {} in {} ms",
            oid,
            start_time.elapsed().as_millis()
        );

        Ok(ObjDefLoaderResults {
            commit: !options.dry_run,
            conflicts: self.conflicts.clone(),
            loaded_objects: vec![oid],
            num_loaded_verbs,
            num_loaded_property_definitions,
            num_loaded_property_overrides,
        })
    }

    /// Replace one existing object with the contents of an objdef.
    ///
    /// Existing verbs and locally defined properties that are absent from the incoming definition
    /// are deleted. Flags, attributes, properties, and verbs from the incoming definition are then
    /// applied in clobber mode. If `target_obj` is supplied, the incoming object ID is treated as the
    /// source identity but the mutation is applied to `target_obj`.
    ///
    /// # Arguments
    /// * `object_definition` - The MOO object definition string
    /// * `constants` - Optional constants (either as a map or as file content to parse)
    /// * `target_obj` - Optional target object ID. If None, uses the ID from the objdef
    pub fn reload_single_object(
        &mut self,
        object_definition: &str,
        constants: Option<Constants>,
        target_obj: Option<Obj>,
    ) -> Result<ObjDefLoaderResults, ObjdefLoaderError> {
        let start_time = Instant::now();
        let source_name = "<reload>".to_string();

        // Create a fresh context for this object
        let mut context = ObjFileContext::new();

        // Parse constants if provided
        if let Some(constants) = &constants {
            apply_constants(constants, &mut context, &source_name)?;
        }

        // Parse the object definition
        let compile_opts = CompileOptions::default();
        let compiled_defs =
            compile_object_definitions(object_definition, &compile_opts, &mut context).map_err(
                |e| ObjdefLoaderError::ObjectDefParseError(source_name.clone(), Box::new(e)),
            )?;

        // Ensure we got exactly one object
        if compiled_defs.len() != 1 {
            return Err(ObjdefLoaderError::SingleObjectExpected(
                source_name,
                compiled_defs.len(),
            ));
        }

        let compiled_def = compiled_defs.into_iter().next().unwrap();

        // Determine the target object ID
        let target_oid = target_obj.unwrap_or(compiled_def.oid);

        // Check if object exists
        let existing_obj = self
            .loader
            .get_existing_object(&target_oid)
            .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(source_name.clone(), e))?;

        // If object exists, we need to selectively delete things not in the objdef
        if existing_obj.is_some() {
            // Get all existing verbs
            let existing_verbs = self.loader.get_existing_verbs(&target_oid).map_err(|e| {
                ObjdefLoaderError::CouldNotDefineVerb(source_name.clone(), target_oid, vec![], e)
            })?;

            // Build set of verb names that should exist (from objdef)
            let mut objdef_verb_names = std::collections::HashSet::new();
            for verb in &compiled_def.verbs {
                for name in &verb.names {
                    objdef_verb_names.insert(*name);
                }
            }

            // Delete verbs that exist but aren't in the objdef
            for verb_def in existing_verbs.iter() {
                let has_matching_name = verb_def
                    .names()
                    .iter()
                    .any(|name| objdef_verb_names.contains(name));

                if !has_matching_name {
                    self.loader
                        .remove_verb(&target_oid, verb_def.uuid())
                        .map_err(|e| {
                            ObjdefLoaderError::CouldNotDefineVerb(
                                source_name.clone(),
                                target_oid,
                                verb_def.names().to_vec(),
                                e,
                            )
                        })?;
                }
            }

            // Get all existing properties
            let existing_props = self
                .loader
                .get_existing_properties(&target_oid)
                .map_err(|e| {
                    ObjdefLoaderError::CouldNotDefineProperty(
                        source_name.clone(),
                        target_oid,
                        String::new(),
                        e,
                    )
                })?;

            // Build set of property names that should exist (from objdef)
            let mut objdef_prop_names = std::collections::HashSet::new();
            for prop_def in &compiled_def.property_definitions {
                objdef_prop_names.insert(prop_def.name);
            }

            // Delete properties defined on this object that aren't in the objdef
            for prop_def in existing_props.iter() {
                if prop_def.definer() == target_oid && !objdef_prop_names.contains(&prop_def.name())
                {
                    self.loader
                        .delete_property(&target_oid, prop_def.name())
                        .map_err(|e| {
                            ObjdefLoaderError::CouldNotDefineProperty(
                                source_name.clone(),
                                target_oid,
                                prop_def.name().as_arc_str().to_string(),
                                e,
                            )
                        })?;
                }
            }

            // Update the object name
            self.loader
                .set_object_name(&target_oid, compiled_def.name.clone())
                .map_err(|e| ObjdefLoaderError::CouldNotSetObjectParent(source_name.clone(), e))?;
        } else {
            // Object doesn't exist, create it
            self.loader
                .create_object(
                    ObjectKind::Objid(target_oid),
                    &ObjAttrs::new(
                        NOTHING,
                        NOTHING,
                        NOTHING,
                        compiled_def.flags,
                        &compiled_def.name,
                    ),
                )
                .map_err(|e| {
                    ObjdefLoaderError::CouldNotCreateObject(source_name.clone(), target_oid, e)
                })?;
        }

        // Store the definition for processing
        self.object_definitions
            .insert(target_oid, (source_name.clone(), compiled_def));

        // Apply all attributes, properties, and verbs using existing conflict-aware methods
        // Force Clobber mode and validation for reload operations
        let apply_options = ObjDefLoaderOptions {
            dry_run: false,
            conflict_mode: ConflictMode::Clobber,
            object_kind: None,
            constants: None,
            overrides: vec![],
            validate_parent_changes: true,
            remove_absent_entities: false,
        };

        self.apply_attributes(&apply_options)?;
        self.apply_object_metadata()?;
        self.define_properties(&apply_options)?;
        self.set_properties(&apply_options)?;
        self.define_verbs(&apply_options)?;

        let (num_loaded_verbs, num_loaded_property_definitions, num_loaded_property_overrides) =
            self.definition_counts();

        info!(
            "Reloaded object {} in {} ms",
            target_oid,
            start_time.elapsed().as_millis()
        );

        Ok(ObjDefLoaderResults {
            commit: true,
            conflicts: vec![], // No conflicts in reload mode - we deleted everything first
            loaded_objects: vec![target_oid],
            num_loaded_verbs,
            num_loaded_property_definitions,
            num_loaded_property_overrides,
        })
    }

    /// Create import_export_id metadata for all loaded objects if they don't already exist.
    /// This is called after loading using the #0 heuristic to establish stable IDs for future dumps.
    fn create_import_export_ids_if_needed(&mut self) -> Result<(), ObjdefLoaderError> {
        use moor_var::v_string;

        let import_export_id_sym = crate::import_export_id();

        // Check if ANY objects already have import_export_id metadata or legacy property.
        let any_have_id = self.object_definitions.values().any(|(_, def)| {
            def.metadata
                .iter()
                .any(|(key, _)| *key == import_export_id_sym)
                || def
                    .property_definitions
                    .iter()
                    .any(|pd| pd.name == import_export_id_sym)
                || def
                    .property_overrides
                    .iter()
                    .any(|po| po.name == import_export_id_sym)
        });

        // If any object has it, assume the import has explicit naming and do not infer IDs.
        if any_have_id {
            return Ok(());
        }

        // Extract the constant names from the context (these come from constants.moo).
        for (name, value) in self.parsed_constants.iter() {
            let Some(obj) = value.as_object() else {
                continue;
            };
            if !self.object_definitions.contains_key(&obj) {
                continue;
            }
            self.loader
                .set_object_metadata(
                    &obj,
                    import_export_id_sym,
                    v_string(name.to_string().to_lowercase()),
                )
                .map_err(|wse| {
                    ObjdefLoaderError::CouldNotSetObjectMetadata(
                        "<import_export_id>".to_string(),
                        obj,
                        "import_export_id".to_string(),
                        wse,
                    )
                })?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::{ConflictMode, ObjDefLoaderOptions, ObjdefLoaderError, ObjectDefinitionLoader};
    use moor_common::model::{HasUuid, Named, TaskPermissions, WorldStateSource};
    use moor_common::util::BitEnum;
    use moor_compiler::{CompileOptions, ObjFileContext};
    use moor_db::{Database, DatabaseConfig, TxDB};
    use moor_var::{Obj, SYSTEM_OBJECT, Symbol, v_str};
    use std::{fs, path::Path, sync::Arc};

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

    #[test]
    fn directory_import_uses_shared_set_constants_path() {
        let tmpdir = tempfile::tempdir().unwrap();
        let import_dir = tmpdir.path().join("import");
        fs::create_dir(&import_dir).unwrap();
        fs::write(import_dir.join("constants.moo"), "define ROOT = #1;").unwrap();
        fs::write(
            import_dir.join("root.moo"),
            r#"
            object ROOT
                name: "Root"
                owner: #-1
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: true
            endobject
            "#,
        )
        .unwrap();

        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut object_loader = ObjectDefinitionLoader::new(loader.as_mut());
        object_loader
            .load_objdef_directory(
                CompileOptions::default(),
                &import_dir,
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let tx = db.new_world_state().unwrap();
        assert_eq!(
            tx.name_of(&system_permissions(), &Obj::mk_id(1)).unwrap(),
            "Root"
        );
        assert_eq!(
            tx.get_object_metadata(
                &system_permissions(),
                &Obj::mk_id(1),
                Symbol::mk("import_export_id")
            )
            .unwrap()
            .unwrap()
            .as_string(),
            Some("root")
        );
    }

    #[test]
    fn directory_import_detects_existing_object_conflicts() {
        let tmpdir = tempfile::tempdir().unwrap();
        let import_dir = tmpdir.path().join("import");
        fs::create_dir(&import_dir).unwrap();

        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        parser
            .load_single_object(
                r#"
                object #10
                    name: "Existing"
                    owner: #0
                    parent: #-1
                    location: #-1
                    wizard: false
                    programmer: false
                    player: false
                    fertile: false
                    readable: false
                endobject
                "#,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        fs::write(
            import_dir.join("object_10.moo"),
            r#"
            object #10
                name: "Existing"
                owner: #0
                parent: #-1
                location: #-1
                wizard: true
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject
            "#,
        )
        .unwrap();

        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let results = parser
            .load_objdef_directory(
                CompileOptions::default(),
                &import_dir,
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        assert_eq!(results.conflicts.len(), 1);
        assert!(matches!(
            results.conflicts[0].1,
            crate::ConflictEntity::ObjectFlags(_)
        ));
        loader.commit().unwrap();

        let ws = db.new_world_state().unwrap();
        let flags = ws.flags_of(&Obj::mk_id(10)).unwrap();
        assert!(flags.contains(moor_common::model::ObjFlag::Wizard));
    }

    #[test]
    fn test_load_single_object() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();

        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());

        let spec = r#"
                object #42
                    name: "Single Test Object"
                    owner: #0
                    parent: #-1
                    location: #-1
                    wizard: false
                    programmer: false
                    player: false
                    fertile: true
                    readable: true

                    property test_prop (owner: #42, flags: "rc") = "test value";

                    verb "test_verb" (this none none) owner: #42 flags: "rxd"
                        return "tested";
                    endverb
                endobject"#;

        let options = ObjDefLoaderOptions::default();
        let results = parser
            .load_single_object(spec, CompileOptions::default(), options)
            .unwrap();
        assert_eq!(results.loaded_objects.len(), 1);
        assert!(results.commit);
        loader.commit().unwrap();

        let oid = results.loaded_objects[0];
        assert_eq!(oid, Obj::mk_id(42));

        // Verify the object was created correctly
        let tx = db.new_world_state().unwrap();
        let name = tx.name_of(&system_permissions(), &oid).unwrap();
        let prop_value = tx
            .retrieve_property(&system_permissions(), &oid, Symbol::mk("test_prop"))
            .unwrap();

        assert_eq!(name, "Single Test Object");
        assert_eq!(prop_value, v_str("test value"));
    }

    #[test]
    fn test_load_single_object_multiple_objects_fails() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());
        let mut loader = db.loader_client().unwrap();

        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());

        let spec = r#"
                object #1
                    name: "Object One"
                    owner: #0
                    parent: #-1
                    location: #-1
                    wizard: false
                    programmer: false
                    player: false
                    fertile: true
                    readable: true
                endobject

                object #2
                    name: "Object Two"
                    owner: #0
                    parent: #-1
                    location: #-1
                    wizard: false
                    programmer: false
                    player: false
                    fertile: true
                    readable: true
                endobject"#;

        let options = ObjDefLoaderOptions::default();
        let result = parser.load_single_object(spec, CompileOptions::default(), options);
        assert!(result.is_err());

        match result.unwrap_err() {
            ObjdefLoaderError::SingleObjectExpected(_, count) => {
                assert_eq!(count, 2);
            }
            _ => panic!("Expected SingleObjectExpected error"),
        }
    }

    #[test]
    fn test_clobber_mode_detects_flags_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create initial object with wizard=false
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #50
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Now load same object with wizard=true (conflict)
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let conflicting_spec = r#"
            object #50
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: true
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        let results = parser
            .load_single_object(
                conflicting_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();

        // Should detect conflict in flags
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one flags conflict"
        );

        // Verify conflict is for object flags
        match &results.conflicts[0].1 {
            crate::ConflictEntity::ObjectFlags(_) => {}
            other => panic!("Expected ObjectFlags conflict, got {other:?}"),
        }

        loader.commit().unwrap();

        // Verify flags were actually updated (Clobber mode)
        let ws = db.new_world_state().unwrap();
        let flags = ws.flags_of(&Obj::mk_id(50)).unwrap();
        assert!(
            flags.contains(moor_common::model::ObjFlag::Wizard),
            "Wizard flag should be set after clobber"
        );
    }

    #[test]
    fn test_skip_mode_preserves_existing_flags() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create initial object with wizard=true
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #51
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: true
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Now load with wizard=false in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let conflicting_spec = r#"
            object #51
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        let results = parser
            .load_single_object(
                conflicting_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one flags conflict"
        );

        loader.commit().unwrap();

        // Verify flags were NOT updated (Skip mode)
        let ws = db.new_world_state().unwrap();
        let flags = ws.flags_of(&Obj::mk_id(51)).unwrap();
        assert!(
            flags.contains(moor_common::model::ObjFlag::Wizard),
            "Wizard flag should still be true after skip"
        );
    }

    #[test]
    fn test_clobber_works_for_parent() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create parent objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let parents_spec = r#"
            object #1
                name: "Parent One"
                owner: #0
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject
            object #2
                name: "Parent Two"
                owner: #0
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        parser
            .load_single_object(
                parents_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap_err(); // This should fail because we're loading 2 objects with load_single_object

        // Create parents properly
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        parser
            .parse_objects(
                mock_path,
                &mut context,
                parents_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create child object with parent=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #53
                name: "Child Object"
                owner: #0
                parent: #1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial parent is #1
        let ws = db.new_world_state().unwrap();
        let parent = ws
            .parent_of(&system_permissions(), &Obj::mk_id(53))
            .unwrap();
        assert_eq!(parent, Obj::mk_id(1), "Initial parent should be #1");

        // Now load with parent=#2 (clobber mode)
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #53
                name: "Child Object"
                owner: #0
                parent: #2
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: false
            endobject"#;

        parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify parent was updated to #2
        let ws = db.new_world_state().unwrap();
        let parent = ws
            .parent_of(&system_permissions(), &Obj::mk_id(53))
            .unwrap();
        assert_eq!(
            parent,
            Obj::mk_id(2),
            "Parent should be updated to #2 in clobber mode"
        );
    }

    #[test]
    fn test_clobber_works_for_location() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create location objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let locations_spec = r#"
            object #1
                name: "Location One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Location Two"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                locations_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create object with location=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #54
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial location
        let ws = db.new_world_state().unwrap();
        let location = ws
            .location_of(&system_permissions(), &Obj::mk_id(54))
            .unwrap();
        assert_eq!(location, Obj::mk_id(1), "Initial location should be #1");

        // Now load with location=#2
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #54
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #2
            endobject"#;
        parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify location was updated to #2
        let ws = db.new_world_state().unwrap();
        let location = ws
            .location_of(&system_permissions(), &Obj::mk_id(54))
            .unwrap();
        assert_eq!(
            location,
            Obj::mk_id(2),
            "Location should be updated to #2 in clobber mode"
        );
    }

    #[test]
    fn test_clobber_works_for_owner() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create owner objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let owners_spec = r#"
            object #1
                name: "Owner One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Owner Two"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                owners_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create object with owner=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #55
                name: "Test Object"
                owner: #1
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial owner
        let ws = db.new_world_state().unwrap();
        let owner = ws.owner_of(&Obj::mk_id(55)).unwrap();
        assert_eq!(owner, Obj::mk_id(1), "Initial owner should be #1");

        // Now load with owner=#2
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #55
                name: "Test Object"
                owner: #2
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify owner was updated to #2
        let ws = db.new_world_state().unwrap();
        let owner = ws.owner_of(&Obj::mk_id(55)).unwrap();
        assert_eq!(
            owner,
            Obj::mk_id(2),
            "Owner should be updated to #2 in clobber mode"
        );
    }

    #[test]
    fn test_clobber_works_for_property_values() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create object with property = "initial"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #56
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                property test_prop (owner: #56, flags: "rc") = "initial value";
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial property value
        let ws = db.new_world_state().unwrap();
        let prop_value = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(56),
                Symbol::mk("test_prop"),
            )
            .unwrap();
        assert_eq!(
            prop_value,
            v_str("initial value"),
            "Initial property value should be 'initial value'"
        );

        // Now load with property = "updated"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #56
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                property test_prop (owner: #56, flags: "rc") = "updated value";
            endobject"#;
        parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify property value was updated
        let ws = db.new_world_state().unwrap();
        let prop_value = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(56),
                Symbol::mk("test_prop"),
            )
            .unwrap();
        assert_eq!(
            prop_value,
            v_str("updated value"),
            "Property value should be updated to 'updated value' in clobber mode"
        );
    }

    #[test]
    fn test_clobber_works_for_verbs() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create object with verb returning "initial"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #58
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                verb "test_verb" (this none none) owner: #58 flags: "rxd"
                    return "initial";
                endverb
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let ws = db.new_world_state().unwrap();
        let initial_verbdef = ws
            .get_verb(
                &system_permissions(),
                &Obj::mk_id(58),
                Symbol::mk("test_verb"),
            )
            .unwrap();
        let (initial_program, _) = ws
            .retrieve_verb(
                &system_permissions(),
                &Obj::mk_id(58),
                initial_verbdef.uuid(),
            )
            .unwrap();

        // Now load with verb returning "updated"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #58
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                verb "test_verb" (this none none) owner: #58 flags: "rxd"
                    return "updated";
                endverb
            endobject"#;
        parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        let ws = db.new_world_state().unwrap();
        let updated_verbdef = ws
            .get_verb(
                &system_permissions(),
                &Obj::mk_id(58),
                Symbol::mk("test_verb"),
            )
            .unwrap();
        let (updated_program, _) = ws
            .retrieve_verb(
                &system_permissions(),
                &Obj::mk_id(58),
                updated_verbdef.uuid(),
            )
            .unwrap();

        assert_eq!(
            initial_verbdef.names(),
            updated_verbdef.names(),
            "Verb name should be same"
        );
        assert_eq!(
            updated_verbdef.owner(),
            Obj::mk_id(58),
            "Verb owner should be correct"
        );
        assert_ne!(
            initial_program, updated_program,
            "Verb program should change in clobber mode"
        );
    }

    #[test]
    fn test_skip_mode_preserves_existing_parent() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create parent objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let parents_spec = r#"
            object #1
                name: "Parent One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Parent Two"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                parents_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create child object with parent=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #60
                name: "Child Object"
                owner: #0
                parent: #1
                location: #-1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial parent is #1
        let ws = db.new_world_state().unwrap();
        let parent = ws
            .parent_of(&system_permissions(), &Obj::mk_id(60))
            .unwrap();
        assert_eq!(parent, Obj::mk_id(1), "Initial parent should be #1");

        // Now load with parent=#2 in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #60
                name: "Child Object"
                owner: #0
                parent: #2
                location: #-1
            endobject"#;
        let results = parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one parent conflict"
        );

        loader.commit().unwrap();

        // Verify parent was NOT updated (Skip mode)
        let ws = db.new_world_state().unwrap();
        let parent = ws
            .parent_of(&system_permissions(), &Obj::mk_id(60))
            .unwrap();
        assert_eq!(
            parent,
            Obj::mk_id(1),
            "Parent should still be #1 after skip"
        );
    }

    #[test]
    fn test_skip_mode_preserves_existing_location() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create location objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let locations_spec = r#"
            object #1
                name: "Location One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Location Two"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                locations_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create object with location=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #61
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial location
        let ws = db.new_world_state().unwrap();
        let location = ws
            .location_of(&system_permissions(), &Obj::mk_id(61))
            .unwrap();
        assert_eq!(location, Obj::mk_id(1), "Initial location should be #1");

        // Now load with location=#2 in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #61
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #2
            endobject"#;
        let results = parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one location conflict"
        );

        loader.commit().unwrap();

        // Verify location was NOT updated (Skip mode)
        let ws = db.new_world_state().unwrap();
        let location = ws
            .location_of(&system_permissions(), &Obj::mk_id(61))
            .unwrap();
        assert_eq!(
            location,
            Obj::mk_id(1),
            "Location should still be #1 after skip"
        );
    }

    #[test]
    fn test_skip_mode_preserves_existing_owner() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create owner objects first
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let owners_spec = r#"
            object #1
                name: "Owner One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Owner Two"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                owners_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Create object with owner=#1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #62
                name: "Test Object"
                owner: #1
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial owner
        let ws = db.new_world_state().unwrap();
        let owner = ws.owner_of(&Obj::mk_id(62)).unwrap();
        assert_eq!(owner, Obj::mk_id(1), "Initial owner should be #1");

        // Now load with owner=#2 in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #62
                name: "Test Object"
                owner: #2
                parent: #-1
                location: #-1
            endobject"#;
        let results = parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one owner conflict"
        );

        loader.commit().unwrap();

        // Verify owner was NOT updated (Skip mode)
        let ws = db.new_world_state().unwrap();
        let owner = ws.owner_of(&Obj::mk_id(62)).unwrap();
        assert_eq!(owner, Obj::mk_id(1), "Owner should still be #1 after skip");
    }

    #[test]
    fn test_skip_mode_preserves_existing_property_values() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create object with property = "initial"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #63
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                property test_prop (owner: #63, flags: "rc") = "initial value";
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial property value
        let ws = db.new_world_state().unwrap();
        let prop_value = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(63),
                Symbol::mk("test_prop"),
            )
            .unwrap();
        assert_eq!(
            prop_value,
            v_str("initial value"),
            "Initial property value should be 'initial value'"
        );

        // Now load with property = "updated" in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #63
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                property test_prop (owner: #63, flags: "rc") = "updated value";
            endobject"#;
        let results = parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one property value conflict"
        );

        loader.commit().unwrap();

        // Verify property value was NOT updated (Skip mode)
        let ws = db.new_world_state().unwrap();
        let prop_value = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(63),
                Symbol::mk("test_prop"),
            )
            .unwrap();
        assert_eq!(
            prop_value,
            v_str("initial value"),
            "Property value should still be 'initial value' after skip"
        );
    }

    #[test]
    fn test_skip_mode_preserves_existing_verbs() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create object with verb returning "initial"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #64
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                verb "test_verb" (this none none) owner: #64 flags: "rxd"
                    return "initial";
                endverb
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Get initial verb
        let ws = db.new_world_state().unwrap();
        let initial_verbdef = ws
            .get_verb(
                &system_permissions(),
                &Obj::mk_id(64),
                Symbol::mk("test_verb"),
            )
            .unwrap();
        let initial_uuid = initial_verbdef.uuid();

        // Now load with verb returning "updated" in Skip mode
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let updated_spec = r#"
            object #64
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                verb "test_verb" (this none none) owner: #64 flags: "rxd"
                    return "updated";
                endverb
            endobject"#;
        let results = parser
            .load_single_object(
                updated_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions {
                    conflict_mode: ConflictMode::Skip,
                    ..ObjDefLoaderOptions::default()
                },
            )
            .unwrap();

        // Should detect conflict
        assert_eq!(
            results.conflicts.len(),
            1,
            "Should detect one verb conflict"
        );

        loader.commit().unwrap();

        // Verify verb was NOT updated (Skip mode) - UUID should be unchanged
        let ws = db.new_world_state().unwrap();
        let final_verbdef = ws
            .get_verb(
                &system_permissions(),
                &Obj::mk_id(64),
                Symbol::mk("test_verb"),
            )
            .unwrap();
        assert_eq!(
            final_verbdef.uuid(),
            initial_uuid,
            "Verb UUID should be unchanged in skip mode"
        );
    }

    #[test]
    fn test_reject_parent_cycle() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create #1 with parent #-1 and #2 with parent #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let initial_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Object Two"
                owner: #0
                parent: #1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                initial_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Now try to change #1's parent to #2, creating a cycle: #1 → #2 → #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let cycle_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #2
                location: #-1
            endobject"#;

        let result = parser.load_single_object(
            cycle_spec,
            CompileOptions::default(),
            ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: true,
                remove_absent_entities: false,
            },
        );

        // Should fail with a cycle detection error
        assert!(result.is_err(), "Loading object with cycle should fail");
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                // Verify it's a cycle error from WorldStateError
                assert!(
                    matches!(e, moor_common::model::WorldStateError::RecursiveMove(_, _)),
                    "Expected RecursiveMove error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }
    }

    #[test]
    fn test_reject_invalid_parent() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Try to set #1's parent to #999 which doesn't exist
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let invalid_parent_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #999
                location: #-1
            endobject"#;

        let result = parser.load_single_object(
            invalid_parent_spec,
            CompileOptions::default(),
            ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: true,
                remove_absent_entities: false,
            },
        );

        // Should fail with invalid parent error
        assert!(
            result.is_err(),
            "Loading object with invalid parent should fail"
        );
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                // Verify it's an invalid parent error
                assert!(
                    matches!(e, moor_common::model::WorldStateError::ObjectNotFound(_)),
                    "Expected ObjectNotFound error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }

        // But NOTHING (#-1) should be allowed
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let nothing_parent_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;

        let result = parser.load_single_object(
            nothing_parent_spec,
            CompileOptions::default(),
            ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: true,
                remove_absent_entities: false,
            },
        );

        // Should succeed
        assert!(
            result.is_ok(),
            "Loading object with NOTHING parent should succeed"
        );
    }

    #[test]
    fn test_reload_single_object_basic() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create initial object with some verbs and properties
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #100
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false

                property old_prop (owner: #100, flags: "rc") = "old value";
                property keep_prop (owner: #100, flags: "rc") = "will be removed";

                verb "old_verb" (this none none) owner: #100 flags: "rxd"
                    return "old";
                endverb

                verb "keep_verb" (this none none) owner: #100 flags: "rxd"
                    return "will be removed";
                endverb
            endobject"#;

        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Verify initial state
        let ws = db.new_world_state().unwrap();
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("old_prop")
            )
            .is_ok()
        );
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("keep_prop")
            )
            .is_ok()
        );
        assert!(
            ws.get_verb(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("old_verb")
            )
            .is_ok()
        );
        assert!(
            ws.get_verb(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("keep_verb")
            )
            .is_ok()
        );

        // Now reload with different verbs and properties
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let reload_spec = r#"
            object #100
                name: "Test Object"
                owner: #0
                parent: #-1
                location: #-1
                wizard: true
                programmer: false
                player: false

                property new_prop (owner: #100, flags: "rc") = "new value";
                property old_prop (owner: #100, flags: "rc") = "updated value";

                verb "new_verb" (this none none) owner: #100 flags: "rxd"
                    return "new";
                endverb

                verb "old_verb" (this none none) owner: #100 flags: "rxd"
                    return "updated";
                endverb
            endobject"#;

        let results = parser
            .reload_single_object(reload_spec, None, None)
            .unwrap();

        assert_eq!(results.loaded_objects.len(), 1);
        assert_eq!(results.loaded_objects[0], Obj::mk_id(100));
        assert_eq!(results.conflicts.len(), 0); // No conflicts in reload mode
        loader.commit().unwrap();

        // Verify final state
        let ws = db.new_world_state().unwrap();

        // New property should exist
        let new_prop = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("new_prop"),
            )
            .unwrap();
        assert_eq!(new_prop, v_str("new value"));

        // Old property should be updated
        let old_prop = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("old_prop"),
            )
            .unwrap();
        assert_eq!(old_prop, v_str("updated value"));

        // keep_prop should be GONE
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("keep_prop")
            )
            .is_err()
        );

        // new_verb should exist
        assert!(
            ws.get_verb(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("new_verb")
            )
            .is_ok()
        );

        // old_verb should exist
        assert!(
            ws.get_verb(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("old_verb")
            )
            .is_ok()
        );

        // keep_verb should be GONE
        assert!(
            ws.get_verb(
                &system_permissions(),
                &Obj::mk_id(100),
                Symbol::mk("keep_verb")
            )
            .is_err()
        );

        // Wizard flag should be updated
        let flags = ws.flags_of(&Obj::mk_id(100)).unwrap();
        assert!(flags.contains(moor_common::model::ObjFlag::Wizard));
    }

    #[test]
    fn test_reload_with_target_override() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create object #200
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #200
                name: "Initial Object"
                owner: #0
                parent: #-1
                location: #-1
                property old_prop (owner: #200, flags: "rc") = "old";
            endobject"#;

        parser
            .load_single_object(
                initial_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Reload object #200 with objdef that says #999, but override to target #200
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let reload_spec = r#"
            object #999
                name: "Reloaded Object"
                owner: #0
                parent: #-1
                location: #-1
                property new_prop (owner: #999, flags: "rc") = "new";
            endobject"#;

        let results = parser
            .reload_single_object(reload_spec, None, Some(Obj::mk_id(200)))
            .unwrap();

        assert_eq!(results.loaded_objects[0], Obj::mk_id(200)); // Should use target override
        loader.commit().unwrap();

        // Verify #200 was updated
        let ws = db.new_world_state().unwrap();
        let name = ws.name_of(&system_permissions(), &Obj::mk_id(200)).unwrap();
        assert_eq!(name, "Reloaded Object");

        // old_prop should be gone, new_prop should exist
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(200),
                Symbol::mk("old_prop")
            )
            .is_err()
        );
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(200),
                Symbol::mk("new_prop")
            )
            .is_ok()
        );

        // #999 should NOT exist
        assert!(!ws.valid(&Obj::mk_id(999)).unwrap());
    }

    #[test]
    fn test_reload_creates_object_if_not_exists() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Reload a non-existent object - should create it
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let reload_spec = r#"
            object #300
                name: "New Object"
                owner: #0
                parent: #-1
                location: #-1
                property test_prop (owner: #300, flags: "rc") = "test";
            endobject"#;

        let results = parser
            .reload_single_object(reload_spec, None, None)
            .unwrap();

        assert_eq!(results.loaded_objects[0], Obj::mk_id(300));
        loader.commit().unwrap();

        // Verify object was created
        let ws = db.new_world_state().unwrap();
        assert!(ws.valid(&Obj::mk_id(300)).unwrap());
        let name = ws.name_of(&system_permissions(), &Obj::mk_id(300)).unwrap();
        assert_eq!(name, "New Object");
    }

    #[test]
    fn test_reload_preserves_inherited_properties() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create parent with a property
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let parent_spec = r#"
            object #400
                name: "Parent"
                owner: #0
                parent: #-1
                location: #-1
                property inherited_prop (owner: #400, flags: "rc") = "from parent";
            endobject"#;

        parser
            .load_single_object(
                parent_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Create child with its own property
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let child_spec = r#"
            object #401
                name: "Child"
                owner: #0
                parent: #400
                location: #-1
                property own_prop (owner: #401, flags: "rc") = "own value";
            endobject"#;

        parser
            .load_single_object(
                child_spec,
                CompileOptions::default(),
                ObjDefLoaderOptions::default(),
            )
            .unwrap();
        loader.commit().unwrap();

        // Reload child with different own property
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let reload_spec = r#"
            object #401
                name: "Child"
                owner: #0
                parent: #400
                location: #-1
                property new_own_prop (owner: #401, flags: "rc") = "new own value";
            endobject"#;

        parser
            .reload_single_object(reload_spec, None, None)
            .unwrap();
        loader.commit().unwrap();

        // Verify inherited property still accessible, old own property gone, new own property exists
        let ws = db.new_world_state().unwrap();

        // Inherited property should still be accessible
        let inherited = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(401),
                Symbol::mk("inherited_prop"),
            )
            .unwrap();
        assert_eq!(inherited, v_str("from parent"));

        // Old own property should be gone
        assert!(
            ws.retrieve_property(
                &system_permissions(),
                &Obj::mk_id(401),
                Symbol::mk("own_prop")
            )
            .is_err()
        );

        // New own property should exist
        let new_own = ws
            .retrieve_property(
                &system_permissions(),
                &Obj::mk_id(401),
                Symbol::mk("new_own_prop"),
            )
            .unwrap();
        assert_eq!(new_own, v_str("new own value"));
    }

    #[test]
    fn test_reload_reject_parent_cycle() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create #1 with parent #-1 and #2 with parent #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let initial_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #2
                name: "Object Two"
                owner: #0
                parent: #1
                location: #-1
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                initial_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        loader.commit().unwrap();

        // Now try to reload #1 with parent #2, creating a cycle: #1 → #2 → #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let cycle_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #2
                location: #-1
            endobject"#;

        let result = parser.reload_single_object(cycle_spec, None, None);

        // Should fail with a cycle detection error
        assert!(result.is_err(), "Reloading object with cycle should fail");
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                assert!(
                    matches!(e, moor_common::model::WorldStateError::RecursiveMove(_, _)),
                    "Expected RecursiveMove error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }
    }

    #[test]
    fn test_reload_reject_invalid_parent() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create #1
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let initial_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #-1
                location: #-1
            endobject"#;
        parser
            .reload_single_object(initial_spec, None, None)
            .unwrap();
        loader.commit().unwrap();

        // Try to reload #1 with parent #999 which doesn't exist
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let invalid_parent_spec = r#"
            object #1
                name: "Object One"
                owner: #0
                parent: #999
                location: #-1
            endobject"#;

        let result = parser.reload_single_object(invalid_parent_spec, None, None);

        // Should fail with invalid parent error
        assert!(
            result.is_err(),
            "Reloading object with invalid parent should fail"
        );
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                assert!(
                    matches!(e, moor_common::model::WorldStateError::ObjectNotFound(_)),
                    "Expected ObjectNotFound error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }
    }

    #[test]
    fn test_reload_reject_descendant_property_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create hierarchy: #10 (no prop "bar"), #20 (defines prop "bar")
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let parents_spec = r#"
            object #10
                name: "Parent Without Bar"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #20
                name: "Parent With Bar"
                owner: #0
                parent: #-1
                location: #-1
                property bar (owner: #20, flags: "rc") = "from parent 20";
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                parents_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        parser.define_properties(&options).unwrap();
        loader.commit().unwrap();

        // Create #50 with parent #10, and #51 as child of #50 defining property "bar"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let children_spec = r#"
            object #50
                name: "Middle Object"
                owner: #0
                parent: #10
                location: #-1
            endobject
            object #51
                name: "Child With Bar"
                owner: #0
                parent: #50
                location: #-1
                property bar (owner: #51, flags: "rc") = "from child 51";
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                children_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        parser.define_properties(&options).unwrap();
        loader.commit().unwrap();

        // Now try to reload #50 with parent #20
        // This should fail because #51 (descendant of #50) defines "bar"
        // and #20 (new parent ancestor) also defines "bar"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let conflict_spec = r#"
            object #50
                name: "Middle Object"
                owner: #0
                parent: #20
                location: #-1
            endobject"#;

        let result = parser.reload_single_object(conflict_spec, None, None);

        // Should fail with property name conflict error
        assert!(
            result.is_err(),
            "Reloading object with descendant property conflict should fail"
        );
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                assert!(
                    matches!(
                        e,
                        moor_common::model::WorldStateError::ChparentPropertyNameConflict(_, _, _)
                    ),
                    "Expected ChparentPropertyNameConflict error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }
    }

    #[test]
    fn test_reject_descendant_property_conflict() {
        let tmpdir = tempfile::tempdir().unwrap();
        let db = test_db(tmpdir.path());

        // Create hierarchy: #10 (no prop "bar"), #20 (defines prop "bar")
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let mock_path = Path::new("test.moo");
        let parents_spec = r#"
            object #10
                name: "Parent Without Bar"
                owner: #0
                parent: #-1
                location: #-1
            endobject
            object #20
                name: "Parent With Bar"
                owner: #0
                parent: #-1
                location: #-1
                property bar (owner: #20, flags: "rc") = "from parent 20";
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                parents_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        parser.define_properties(&options).unwrap();
        loader.commit().unwrap();

        // Create #50 with parent #10, and #51 as child of #50 defining property "bar"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let mut context = ObjFileContext::new();
        let children_spec = r#"
            object #50
                name: "Middle Object"
                owner: #0
                parent: #10
                location: #-1
            endobject
            object #51
                name: "Child With Bar"
                owner: #0
                parent: #50
                location: #-1
                property bar (owner: #51, flags: "rc") = "from child 51";
            endobject"#;
        parser
            .parse_objects(
                mock_path,
                &mut context,
                children_spec,
                &CompileOptions::default(),
            )
            .unwrap();
        let options = ObjDefLoaderOptions::default();
        parser.apply_attributes(&options).unwrap();
        parser.define_properties(&options).unwrap();
        loader.commit().unwrap();

        // Now try to change #50's parent to #20
        // This should fail because #51 (descendant of #50) defines "bar"
        // and #20 (new parent ancestor) also defines "bar"
        let mut loader = db.loader_client().unwrap();
        let mut parser = ObjectDefinitionLoader::new(loader.as_mut());
        let conflict_spec = r#"
            object #50
                name: "Middle Object"
                owner: #0
                parent: #20
                location: #-1
            endobject"#;

        let result = parser.load_single_object(
            conflict_spec,
            CompileOptions::default(),
            ObjDefLoaderOptions {
                dry_run: false,
                conflict_mode: ConflictMode::Clobber,
                object_kind: None,
                constants: None,
                overrides: vec![],
                validate_parent_changes: true,
                remove_absent_entities: false,
            },
        );

        // Should fail with property name conflict error
        assert!(
            result.is_err(),
            "Loading object with descendant property conflict should fail"
        );
        match result.unwrap_err() {
            ObjdefLoaderError::CouldNotSetObjectParent(_, e) => {
                // Verify it's a property name conflict error
                assert!(
                    matches!(
                        e,
                        moor_common::model::WorldStateError::ChparentPropertyNameConflict(_, _, _)
                    ),
                    "Expected ChparentPropertyNameConflict error, got {e:?}"
                );
            }
            other => panic!("Expected CouldNotSetObjectParent error, got {other:?}"),
        }
    }
}
