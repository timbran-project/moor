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

//! Parsing and staging model for sets of objdef sources.
//!
//! This module one or more objdef texts, plus optional constants, into a proposed object graph that
//! later code can either inspect or apply.
//! Directory import uses before handing the graph to `ObjectDefinitionLoader`.
//!
//! Keep parsing, constants resolution, duplicate detection, and incoming identity derivation here.
//! Keep database effects in `load.rs`.

use crate::{
    Constants, ObjdefLoaderError,
    package::{CONSTANTS_FILE, PACKAGE_FILE, SourceDirectory, package_key},
};
use moor_compiler::{
    CompileOptions, ObjFileContext, ObjectDefinition, PackageDeclaration,
    compile_object_definitions,
};
use moor_var::{Obj, Symbol, Var, v_map, v_str};
use std::{
    collections::{HashMap, HashSet},
    path::{Path, PathBuf},
};

#[derive(Debug, Clone)]
/// One objdef input unit with a stable diagnostic label.
///
/// `path` is optional because callers may supply objdefs from memory rather than from a directory.
/// When present, it is used for include path resolution and for diagnostics. When absent, `label`
/// is used only for diagnostics and grants no filesystem access.
pub struct ObjDefSource {
    /// Human-readable source name for parse errors and duplicate diagnostics.
    pub label: String,
    /// Raw objdef text.
    pub contents: String,
    /// Filesystem path, when the source came from disk.
    pub path: Option<PathBuf>,
    /// For an in-memory source, the package whose files it belongs to, which decides what its
    /// bare constant names mean and is recorded on its objects. A source from disk takes its
    /// package from its directory instead.
    pub package: Option<String>,
}

impl ObjDefSource {
    /// Build an in-memory objdef source.
    pub fn new(label: impl Into<String>, contents: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            contents: contents.into(),
            path: None,
            package: None,
        }
    }

    /// Build an objdef source read from a concrete path.
    pub fn from_path(path: PathBuf, contents: String) -> Self {
        Self {
            label: path.to_string_lossy().into_owned(),
            contents,
            path: Some(path),
            package: None,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
/// Stable incoming identity discovered while parsing an objdef set.
///
/// Constants are the symbolic names from `constants.moo` or supplied constants. `import_export_id`
/// is the stable exported metadata used by mooR's objdef dump format. Both are diagnostic identity
/// layers; object IDs are still interpreted literally in this phase.
pub struct ObjDefIdentity {
    /// Constant name that resolves to the object, when one exists in the incoming constants.
    pub constant: Option<Symbol>,
    /// `import_export_id` metadata value declared on the object, when present.
    pub import_export_id: Option<String>,
}

#[derive(Clone)]
/// Parsed incoming object graph before any database mutation.
///
/// The graph owns compiled object definitions keyed by their literal object IDs, plus identity
/// metadata derived from constants and `import_export_id`. It is the common input for both directory
/// import apply and future changelist analysis.
pub struct ProposedObjectGraph {
    object_definitions: HashMap<Obj, (String, ObjectDefinition)>,
    identities: HashMap<Obj, ObjDefIdentity>,
}

impl ProposedObjectGraph {
    /// Compiled object definitions keyed by the object ID named in the objdef text.
    pub fn object_definitions(&self) -> &HashMap<Obj, (String, ObjectDefinition)> {
        &self.object_definitions
    }

    /// Incoming identity metadata for one object, if any was discovered.
    pub fn identity(&self, obj: &Obj) -> Option<&ObjDefIdentity> {
        self.identities.get(obj)
    }

    /// All discovered incoming identities keyed by object ID.
    pub fn identities(&self) -> &HashMap<Obj, ObjDefIdentity> {
        &self.identities
    }
}

/// Parsed objdef set plus constants produced while parsing it.
///
/// `ObjDefSet` is read-only with respect to the database. It validates constants, parses all sources
/// through one `ObjFileContext`, detects duplicate object IDs, and derives incoming identity
/// metadata. Applying the result is a separate loader concern.
#[derive(Clone)]
pub struct ObjDefSet {
    graph: ProposedObjectGraph,
    constants: HashMap<Symbol, Var>,
    /// Declarations of the packages the set was read from, in import order.
    packages: Vec<PackageDeclaration>,
    /// Names of the plain directories read beside packages in a world.
    plain_directories: Vec<String>,
}

impl ObjDefSet {
    /// Read a bulk source directory with the same constants and include rules as import.
    ///
    /// A directory with a `package.moo` is read as that package: its constants are qualified by
    /// the package's name and its objects carry package metadata. A directory of packages, as
    /// export writes a world built from them, is read as all of them. Any other directory is read
    /// exactly as before.
    pub fn read_directory(
        compile_options: &CompileOptions,
        directory: &Path,
    ) -> Result<Self, ObjdefLoaderError> {
        if let Some(members) = crate::package::world_members(directory)? {
            return Self::read_directories(compile_options, &members);
        }
        Self::read_directory_with_constants(compile_options, directory, None, false)
    }

    /// Read several source directories as one world. Directories without a package come first,
    /// in the order given, then packages, each after those it depends on. Every directory's
    /// constants are read before any objects, so an object in one directory can name an object in
    /// any other, as a world exported from a database whose objects were put into packages
    /// does. An object defined twice is refused.
    pub fn read_directories(
        compile_options: &CompileOptions,
        directories: &[PathBuf],
    ) -> Result<Self, ObjdefLoaderError> {
        if let [directory] = directories {
            return Self::read_directory(compile_options, directory);
        }
        let sources = directories
            .iter()
            .map(|path| {
                Ok(SourceDirectory {
                    path: path.clone(),
                    declaration: crate::package::read_declaration(path)?,
                })
            })
            .collect::<Result<Vec<_>, ObjdefLoaderError>>()?;
        let ordered = crate::package::order(sources)?;

        // First every directory's constants, noting which are its own.
        let mut all: HashMap<Symbol, Var> = HashMap::new();
        let mut own = Vec::with_capacity(ordered.len());
        for source in &ordered {
            let set = Self::read_directory_with_constants(
                compile_options,
                &source.path,
                Some(&constants_value(&all, |_| true)),
                true,
            )?;
            own.push(
                set.constants
                    .keys()
                    .filter(|name| !all.contains_key(*name))
                    .copied()
                    .collect::<HashSet<_>>(),
            );
            all = set.constants;
        }

        // Then each directory's objects, with every other directory's constants in scope; its
        // own it defines again as it reads them.
        let mut merged: Option<Self> = None;
        let mut plain_directories = Vec::new();
        for (source, own) in ordered.iter().zip(own) {
            if source.declaration.is_none()
                && let Some(name) = source.path.file_name()
            {
                plain_directories.push(name.to_string_lossy().into_owned());
            }
            let others = constants_value(&all, |name| !own.contains(name));
            let set = Self::read_directory_with_constants(
                compile_options,
                &source.path,
                Some(&others),
                false,
            )?;
            merged = Some(match merged {
                None => set,
                Some(earlier) => earlier.merge(set)?,
            });
        }
        let mut merged = merged
            .ok_or_else(|| ObjdefLoaderError::InvalidPackage("no source directories".into()))?;
        merged.plain_directories = plain_directories;
        Ok(merged)
    }

    /// Add a later directory's set to this one. Constants already include the earlier ones, since
    /// the later set was read with them in scope.
    fn merge(mut self, later: Self) -> Result<Self, ObjdefLoaderError> {
        for (oid, (label, definition)) in later.graph.object_definitions {
            if let Some((first, _)) = self.graph.object_definitions.get(&oid) {
                return Err(ObjdefLoaderError::DuplicateObjectDefinition(
                    label,
                    oid,
                    first.clone(),
                ));
            }
            self.graph
                .object_definitions
                .insert(oid, (label, definition));
        }
        self.constants = later.constants;
        self.packages.extend(later.packages);
        self.graph.identities = derive_identities(&self.graph.object_definitions, &self.constants);
        Ok(self)
    }

    /// Read one directory, with `constants` already defined. With `constants_only`, only its
    /// `package.moo` or `constants.moo` is read.
    fn read_directory_with_constants(
        compile_options: &CompileOptions,
        directory: &Path,
        constants: Option<&Constants>,
        constants_only: bool,
    ) -> Result<Self, ObjdefLoaderError> {
        fn collect(path: &Path, files: &mut Vec<PathBuf>) -> std::io::Result<()> {
            for entry in std::fs::read_dir(path)? {
                let path = entry?.path();
                if path.is_dir() {
                    collect(&path, files)?;
                } else if path.is_file() && path.extension().is_some_and(|ext| ext == "moo") {
                    files.push(path);
                }
            }
            Ok(())
        }
        if !directory.is_dir() {
            return Err(ObjdefLoaderError::DirectoryNotFound(
                directory.to_path_buf(),
            ));
        }
        let mut files = Vec::new();
        collect(directory, &mut files)
            .map_err(|e| ObjdefLoaderError::ObjectFileReadError(directory.to_path_buf(), e))?;
        files.sort();
        // The declaration and constants come first: package.moo for a package, constants.moo
        // for a plain directory. Reading the declaration also refuses a directory with both.
        let declaration = crate::package::read_declaration(directory)?;
        let first = if declaration.is_some() {
            PACKAGE_FILE
        } else {
            CONSTANTS_FILE
        };
        let first = directory.join(first);
        files.retain(|path| !constants_only && *path != first);
        if first.is_file() {
            files.insert(0, first);
        }
        let sources = files
            .into_iter()
            .map(|path| {
                let text = std::fs::read_to_string(&path)
                    .map_err(|e| ObjdefLoaderError::ObjectFileReadError(path.clone(), e))?;
                Ok(ObjDefSource::from_path(path, text))
            })
            .collect::<Result<Vec<_>, ObjdefLoaderError>>()?;
        let mut options = compile_options.clone();
        options.call_unsupported_builtins = true;
        Self::parse_sources(&options, Some(directory), constants, sources)
    }

    /// Read deployment source, optionally preparing baselines from separate upstream history.
    /// Git preparation uses local history only and never modifies the working tree.
    pub fn read_directory_with_baseline(
        compile_options: &CompileOptions,
        directory: &Path,
        git_upstream: Option<&str>,
        baseline_directory: Option<&Path>,
    ) -> Result<Self, ObjdefLoaderError> {
        if git_upstream.is_some() && baseline_directory.is_some() {
            return Err(ObjdefLoaderError::InvalidBaseline(
                "choose either --git-upstream or --baseline-objdef-dir".into(),
            ));
        }
        let baseline = if let Some(upstream) = git_upstream {
            let (base, provenance) =
                crate::git_baseline::prepare(directory, upstream, compile_options)
                    .map_err(|e| ObjdefLoaderError::InvalidBaseline(format!("{e:#}")))?;
            Some((base, Some(provenance)))
        } else if let Some(path) = baseline_directory {
            Some((Self::read_directory(compile_options, path)?, None))
        } else {
            None
        };
        let local = Self::read_directory(compile_options, directory)?;
        match baseline {
            Some((base, provenance)) => local.with_baseline(&base, provenance),
            None => Ok(local),
        }
    }

    /// Derive program, property, and attribute baselines from separately identified source.
    /// Unmatched local declarations have no baseline. Object relocation is not inferred.
    pub fn with_baseline(
        mut self,
        baseline: &Self,
        provenance: Option<Var>,
    ) -> Result<Self, ObjdefLoaderError> {
        use crate::{
            fingerprint::{PROGRAM_SCHEMA, program_fingerprint},
            review::{BASE_KEY, record},
        };
        use moor_var::v_str;
        if provenance.as_ref().is_some_and(|v| v.as_map().is_none()) {
            return Err(ObjdefLoaderError::InvalidBaseline(
                "source provenance must be a map".into(),
            ));
        }
        let key = Symbol::mk(BASE_KEY);
        for (oid, (label, local)) in &mut self.graph.object_definitions {
            let identity = self.graph.identities.get(oid).cloned().unwrap_or_default();
            if let Some(id) = &identity.import_export_id {
                let candidates = baseline
                    .graph
                    .identities
                    .iter()
                    .filter(|(_, identity)| identity.import_export_id.as_ref() == Some(id))
                    .map(|(oid, _)| oid)
                    .collect::<Vec<_>>();
                if candidates.len() > 1
                    || candidates.first().is_some_and(|base_oid| *base_oid != oid)
                {
                    return Err(ObjdefLoaderError::InvalidBaseline(format!(
                        "{label}: object identity {id} is ambiguous or has moved; explicit rebinding is required"
                    )));
                }
            }
            let base = baseline
                .graph
                .object_definitions
                .get(oid)
                .map(|(_, definition)| definition);
            if base.is_some() {
                let base_identity = baseline.graph.identity(oid).cloned().unwrap_or_default();
                if identity.import_export_id != base_identity.import_export_id {
                    return Err(ObjdefLoaderError::InvalidBaseline(format!(
                        "{label}: object {oid} has a different identity in the baseline"
                    )));
                }
            }
            local
                .metadata
                .retain(|(metadata_key, _)| *metadata_key != key);
            if let Some(base) = base {
                local.metadata.push((
                    key,
                    crate::review::inspection::baseline(base, &baseline.graph, provenance.as_ref()),
                ));
            }
            for (index, verb) in local.verbs.iter().enumerate() {
                if local.verbs[..index]
                    .iter()
                    .any(|other| other.names == verb.names && other.argspec == verb.argspec)
                {
                    return Err(ObjdefLoaderError::InvalidBaseline(format!(
                        "{label}: ambiguous local verb declaration"
                    )));
                }
            }
            for verb in &mut local.verbs {
                verb.metadata
                    .retain(|(metadata_key, _)| *metadata_key != key);
                let Some(base) = base else {
                    continue;
                };
                let candidates = base
                    .verbs
                    .iter()
                    .filter(|candidate| {
                        candidate.names == verb.names && candidate.argspec == verb.argspec
                    })
                    .collect::<Vec<_>>();
                if candidates.len() > 1 {
                    return Err(ObjdefLoaderError::InvalidBaseline(format!(
                        "{label}: ambiguous verb declaration in baseline binding"
                    )));
                }
                let Some(base_verb) = candidates.first() else {
                    continue;
                };
                let hash = program_fingerprint(&base_verb.program)
                    .map_err(ObjdefLoaderError::InvalidBaseline)?;
                let mut fields = vec![("schema", v_str(PROGRAM_SCHEMA)), ("program", v_str(&hash))];
                if let Some(source) = &provenance {
                    fields.push(("source", source.clone()));
                }
                verb.metadata.push((key, record(&fields)));
            }
        }
        Ok(self)
    }

    /// Parse objdef sources into a proposed graph without mutating the database.
    ///
    /// `root_path` is the include security boundary for filesystem-backed source sets. `constants`
    /// are applied before `sources`, so callers can supply constants without manufacturing a
    /// `constants.moo` source. Sources may also contain `define` declarations; all definitions share
    /// one context so constants work across files the same way they do in directory import.
    pub fn parse_sources<I>(
        compile_options: &CompileOptions,
        root_path: Option<&Path>,
        constants: Option<&Constants>,
        sources: I,
    ) -> Result<Self, ObjdefLoaderError>
    where
        I: IntoIterator<Item = ObjDefSource>,
    {
        let mut context = ObjFileContext::new();
        if let Some(root_path) = root_path {
            context.set_root_path(root_path);
        }

        if let Some(constants) = constants {
            apply_constants(constants, compile_options, &mut context, "<constants>")?;
        }

        let mut object_definitions: HashMap<Obj, (String, ObjectDefinition)> = HashMap::new();
        let mut memory_bytes = 0usize;
        let mut memory_units = 0usize;
        for source in sources {
            if source.path.is_none() {
                memory_units += 1;
                memory_bytes = memory_bytes.saturating_add(source.contents.len());
                if memory_units > 4096 || memory_bytes > 16 * 1024 * 1024 {
                    return Err(ObjdefLoaderError::InputLimit("4096 units or 16 MiB".into()));
                }
            }
            match source.path.as_deref() {
                Some(path) => context.set_base_path(path),
                None => {
                    context.clear_base_path();
                    context.set_namespace(source.package.as_deref());
                }
            }
            let compiled_defs = compile_normalized_object_definitions(
                &source.contents,
                compile_options,
                &mut context,
            )
            .map_err(|e| {
                ObjdefLoaderError::ObjectDefParseError(source.label.clone(), Box::new(e))
            })?;

            for mut compiled_def in compiled_defs {
                let oid = compiled_def.oid;
                if source.path.is_none()
                    && let Some(package) = &source.package
                {
                    compiled_def
                        .metadata
                        .retain(|(name, _)| *name != package_key());
                    compiled_def.metadata.push((package_key(), v_str(package)));
                }
                if let Some((first_source, _)) = object_definitions.get(&oid) {
                    return Err(ObjdefLoaderError::DuplicateObjectDefinition(
                        source.label.clone(),
                        oid,
                        first_source.clone(),
                    ));
                }
                object_definitions.insert(oid, (source.label.clone(), compiled_def));
                if source.path.is_none() && object_definitions.len() > 32768 {
                    return Err(ObjdefLoaderError::InputLimit(
                        "32768 object declarations".into(),
                    ));
                }
            }
        }

        let packages = context
            .declaration()
            .cloned()
            .into_iter()
            .collect::<Vec<_>>();
        if let Some(package) = packages.first() {
            let key = package_key();
            for (_, definition) in object_definitions.values_mut() {
                definition.metadata.retain(|(name, _)| *name != key);
                definition.metadata.push((key, v_str(&package.name)));
            }
        }
        let constants = context.constants().clone();
        let identities = derive_identities(&object_definitions, &constants);
        Ok(Self {
            graph: ProposedObjectGraph {
                object_definitions,
                identities,
            },
            constants,
            packages,
            plain_directories: vec![],
        })
    }

    /// Declarations of the packages the set was read from, in import order.
    pub fn packages(&self) -> &[PackageDeclaration] {
        &self.packages
    }

    /// Names of the plain directories read beside packages, such as `cowbell` in a test world.
    pub fn plain_directories(&self) -> &[String] {
        &self.plain_directories
    }

    /// Proposed graph built from the incoming sources.
    pub fn graph(&self) -> &ProposedObjectGraph {
        &self.graph
    }

    /// Constants accumulated while parsing the set.
    pub fn constants(&self) -> &HashMap<Symbol, Var> {
        &self.constants
    }

    pub(crate) fn into_parts(
        self,
    ) -> (
        HashMap<Obj, (String, ObjectDefinition)>,
        HashMap<Symbol, Var>,
    ) {
        (self.graph.object_definitions, self.constants)
    }
}

pub(crate) fn normalize_legacy_naming_properties(definition: &mut ObjectDefinition) {
    for key in [crate::import_export_id(), crate::import_export_hierarchy()] {
        let has_metadata = definition
            .metadata
            .iter()
            .any(|(metadata_key, _)| *metadata_key == key);
        let mut legacy_value = None;

        definition.property_definitions = std::mem::take(&mut definition.property_definitions)
            .into_iter()
            .filter_map(|property| {
                if property.name != key {
                    return Some(property);
                }
                if legacy_value.is_none() {
                    legacy_value = property.value;
                }
                None
            })
            .collect();
        definition.property_overrides = std::mem::take(&mut definition.property_overrides)
            .into_iter()
            .filter_map(|property| {
                if property.name != key {
                    return Some(property);
                }
                if property.value.is_some() {
                    legacy_value = property.value;
                }
                None
            })
            .collect();

        if !has_metadata && let Some(value) = legacy_value {
            definition.metadata.push((key, value));
        }
    }
}

pub(crate) fn compile_normalized_object_definitions(
    source: &str,
    compile_options: &CompileOptions,
    context: &mut ObjFileContext,
) -> Result<Vec<ObjectDefinition>, moor_compiler::ObjDefParseError> {
    let mut definitions = compile_object_definitions(source, compile_options, context)?;
    definitions
        .iter_mut()
        .for_each(normalize_legacy_naming_properties);
    Ok(definitions)
}

pub(crate) fn apply_constants(
    constants: &Constants,
    compile_options: &CompileOptions,
    context: &mut ObjFileContext,
    source_name: &str,
) -> Result<(), ObjdefLoaderError> {
    match constants {
        Constants::Map(map) => {
            for (key, value) in map.iter() {
                let key_symbol = key.as_symbol().map_err(|_| {
                    ObjdefLoaderError::ObjectDefParseError(
                        source_name.to_string(),
                        Box::new(moor_compiler::ObjDefParseError::ConstantNotFound(format!(
                            "Constants map key must be string or symbol, got: {key:?}"
                        ))),
                    )
                })?;
                add_constant_checked(context, key_symbol, value.clone(), source_name)?;
            }
        }
        Constants::FileContent(content) => {
            compile_object_definitions(content, compile_options, context).map_err(|e| {
                ObjdefLoaderError::ObjectDefParseError(source_name.to_string(), Box::new(e))
            })?;
        }
    }
    Ok(())
}

fn add_constant_checked(
    context: &mut ObjFileContext,
    name: Symbol,
    value: Var,
    source_name: &str,
) -> Result<(), ObjdefLoaderError> {
    if let Some(existing) = context.constants().get(&name) {
        return Err(ObjdefLoaderError::ObjectDefParseError(
            source_name.to_string(),
            Box::new(moor_compiler::ObjDefParseError::DuplicateConstant(
                name.to_string(),
                format!("{existing:?}"),
            )),
        ));
    }
    for (existing_name, existing_value) in context.constants().iter() {
        if *existing_value == value {
            return Err(ObjdefLoaderError::ObjectDefParseError(
                source_name.to_string(),
                Box::new(moor_compiler::ObjDefParseError::DuplicateConstant(
                    format!("{name} = {value:?}"),
                    format!("conflicts with {existing_name} = {existing_value:?}"),
                )),
            ));
        }
    }
    context.add_constant(name, value);
    Ok(())
}

fn derive_identities(
    object_definitions: &HashMap<Obj, (String, ObjectDefinition)>,
    constants: &HashMap<Symbol, Var>,
) -> HashMap<Obj, ObjDefIdentity> {
    let mut identities = HashMap::<Obj, ObjDefIdentity>::new();
    for (name, value) in constants {
        let Some(obj) = value.as_object() else {
            continue;
        };
        if object_definitions.contains_key(&obj) {
            identities.entry(obj).or_default().constant = Some(*name);
        }
    }

    let import_export_id = crate::import_export_id();
    for (obj, (_, definition)) in object_definitions {
        let import_export_id = definition.metadata.iter().find_map(|(key, value)| {
            if *key != import_export_id {
                return None;
            }
            value.as_string().map(str::to_string)
        });
        if let Some(import_export_id) = import_export_id {
            identities.entry(*obj).or_default().import_export_id = Some(import_export_id);
        }
    }
    identities
}

/// Constants for reading a directory: those of `constants` whose names pass `keep`.
fn constants_value(constants: &HashMap<Symbol, Var>, keep: impl Fn(&Symbol) -> bool) -> Constants {
    let entries = constants
        .iter()
        .filter(|(name, _)| keep(name))
        .map(|(name, value)| (v_str(name.as_str()), value.clone()))
        .collect::<Vec<_>>();
    Constants::Map(v_map(&entries).as_map().unwrap().clone())
}

#[cfg(test)]
mod tests {
    use crate::{Constants, ObjDefSet, ObjDefSource, ObjdefLoaderError};
    use moor_compiler::CompileOptions;
    use moor_var::{Obj, Symbol, v_map, v_obj, v_sym};

    #[test]
    fn parses_in_memory_sources_with_constants_and_identity() {
        let constants = ObjDefSource::new("constants.moo", "define ROOT = #1;");
        let object = ObjDefSource::new(
            "root.moo",
            r#"
            object ROOT [
                import_export_id -> "root"
            ]
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
        );

        let set =
            ObjDefSet::parse_sources(&CompileOptions::default(), None, None, [constants, object])
                .unwrap();
        let graph = set.graph();
        assert_eq!(graph.object_definitions().len(), 1);
        assert!(graph.object_definitions().contains_key(&Obj::mk_id(1)));
        assert_eq!(
            set.constants()
                .get(&Symbol::mk("ROOT"))
                .and_then(|v| v.as_object()),
            Some(Obj::mk_id(1))
        );

        let identity = graph.identity(&Obj::mk_id(1)).unwrap();
        assert_eq!(identity.constant, Some(Symbol::mk("ROOT")));
        assert_eq!(identity.import_export_id.as_deref(), Some("root"));
    }

    #[test]
    fn normalizes_legacy_naming_properties_before_staging() {
        let object = ObjDefSource::new(
            "root.moo",
            r#"
            object #1
                name: "Root"
                owner: #1
                parent: #-1
                location: #-1
                property import_export_id (owner: #1, flags: "r") = "root";
                property import_export_hierarchy (owner: #1, flags: "r") = {"core"};
            endobject
            "#,
        );

        let set =
            ObjDefSet::parse_sources(&CompileOptions::default(), None, None, [object]).unwrap();
        let (_, definition) = set
            .graph()
            .object_definitions()
            .get(&Obj::mk_id(1))
            .unwrap();
        assert!(definition.property_definitions.is_empty());
        assert!(definition.property_overrides.is_empty());
        assert!(definition.metadata.iter().any(|(key, value)| {
            *key == Symbol::mk("import_export_id") && value.as_string() == Some("root")
        }));
        assert_eq!(
            set.graph()
                .identity(&Obj::mk_id(1))
                .unwrap()
                .import_export_id
                .as_deref(),
            Some("root")
        );
    }

    #[test]
    fn reports_duplicate_object_ids_with_source_labels() {
        let first = ObjDefSource::new(
            "first.moo",
            r#"
            object #1
                name: "First"
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
        );
        let second = ObjDefSource::new(
            "second.moo",
            r#"
            object #1
                name: "Second"
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
        );

        let err =
            match ObjDefSet::parse_sources(&CompileOptions::default(), None, None, [first, second])
            {
                Ok(_) => panic!("expected duplicate object diagnostic"),
                Err(err) => err,
            };
        match err {
            ObjdefLoaderError::DuplicateObjectDefinition(source, obj, first_source) => {
                assert_eq!(source, "second.moo");
                assert_eq!(obj, Obj::mk_id(1));
                assert_eq!(first_source, "first.moo");
            }
            other => panic!("expected duplicate object diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn parses_multiple_objects_from_one_source() {
        let source = ObjDefSource::new(
            "bundle.moo",
            r#"
            object #1
                name: "First"
                owner: #-1
                parent: #-1
                location: #-1
                wizard: false
                programmer: false
                player: false
                fertile: false
                readable: true
            endobject

            object #2
                name: "Second"
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
        );

        let set =
            ObjDefSet::parse_sources(&CompileOptions::default(), None, None, [source]).unwrap();
        assert_eq!(set.graph().object_definitions().len(), 2);
        assert!(
            set.graph()
                .object_definitions()
                .contains_key(&Obj::mk_id(1))
        );
        assert!(
            set.graph()
                .object_definitions()
                .contains_key(&Obj::mk_id(2))
        );
    }

    #[test]
    fn reports_malformed_source_label() {
        let source = ObjDefSource::new("bad.moo", "not an objdef");

        let err = match ObjDefSet::parse_sources(&CompileOptions::default(), None, None, [source]) {
            Ok(_) => panic!("expected parse diagnostic"),
            Err(err) => err,
        };
        match err {
            ObjdefLoaderError::ObjectDefParseError(source, _) => {
                assert_eq!(source, "bad.moo");
            }
            other => panic!("expected parse diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn rejects_conflicting_constant_map_values() {
        let constants = v_map(&[
            (v_sym("FIRST"), v_obj(Obj::mk_id(1))),
            (v_sym("ALSO_FIRST"), v_obj(Obj::mk_id(1))),
        ]);
        let err = match ObjDefSet::parse_sources(
            &CompileOptions::default(),
            None,
            Some(&Constants::Map(constants.as_map().unwrap().clone())),
            Vec::<ObjDefSource>::new(),
        ) {
            Ok(_) => panic!("expected duplicate constant diagnostic"),
            Err(err) => err,
        };
        match err {
            ObjdefLoaderError::ObjectDefParseError(_, parse_error) => {
                assert!(matches!(
                    parse_error.as_ref(),
                    moor_compiler::ObjDefParseError::DuplicateConstant(_, _)
                ));
            }
            other => panic!("expected duplicate constant diagnostic, got {other:?}"),
        }
    }
    #[test]
    fn memory_labels_never_authorize_includes() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("secret"), "private").unwrap();
        for binary in [false, true] {
            let macro_name = if binary { "include_bin" } else { "include" };
            let text = format!(
                "object #1 property secret (owner: #1, flags: \"r\") = {macro_name}!(\"secret\"); endobject"
            );
            let label = dir.path().join("input.moo").to_string_lossy().into_owned();
            let error = ObjDefSet::parse_sources(
                &CompileOptions::default(),
                Some(dir.path()),
                None,
                [ObjDefSource::new(label, text)],
            )
            .err()
            .expect("memory include must fail");
            assert!(
                error.to_string().contains("file-based compilation context"),
                "{error}"
            );
        }
    }

    #[test]
    fn memory_source_does_not_inherit_previous_file_authority() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("secret"), "private").unwrap();
        let disk =
            ObjDefSource::from_path(dir.path().join("constants.moo"), "define ROOT = #1;".into());
        let memory = ObjDefSource::new(
            "next.moo",
            "object ROOT property secret (owner: ROOT, flags: \"r\") = include!(\"secret\"); endobject",
        );
        let error = ObjDefSet::parse_sources(
            &CompileOptions::default(),
            Some(dir.path()),
            None,
            [disk, memory],
        )
        .err()
        .expect("memory source must clear include context");
        assert!(
            error.to_string().contains("file-based compilation context"),
            "{error}"
        );
    }

    #[test]
    fn constants_use_the_configured_compilation_profile() {
        let options = CompileOptions {
            bool_type: false,
            ..CompileOptions::default()
        };
        let source = "object #1 verb test (this none this) owner: #1 flags: \"rxd\"\nreturn true;\nendverb\nendobject";
        let error = ObjDefSet::parse_sources(
            &options,
            None,
            Some(&Constants::FileContent(source.into())),
            Vec::<ObjDefSource>::new(),
        )
        .err()
        .expect("constants must use caller compile options");
        assert!(error.compile_error().is_some(), "{error}");
    }

    fn write(directory: &std::path::Path, name: &str, contents: &str) {
        std::fs::create_dir_all(directory).unwrap();
        std::fs::write(directory.join(name), contents).unwrap();
    }

    fn object(constant: &str, id: &str, parent: &str) -> String {
        format!(
            r#"object {constant} [
                import_export_id -> "{id}"
            ]
                name: "{id}"
                owner: #-1
                parent: {parent}
                location: #-1
                readable: true
            endobject
            "#
        )
    }

    #[test]
    fn packages_read_in_dependency_order_with_qualified_constants() {
        let root = tempfile::tempdir().unwrap();
        let core = root.path().join("core");
        let minecraft = root.path().join("minecraft");
        write(
            &core,
            "package.moo",
            r#"package "core" [objdef_version -> 2];
            define ROOT = #1;
            define THING = #8;"#,
        );
        write(&core, "root.moo", &object("ROOT", "root", "#-1"));
        write(&core, "thing.moo", &object("THING", "thing", "ROOT"));
        write(
            &minecraft,
            "package.moo",
            r#"package "minecraft" [objdef_version -> 2, depends -> {"core"}];
            define REGION = #6006;"#,
        );
        write(
            &minecraft,
            "region.moo",
            &object("REGION", "region", "core::THING"),
        );

        let set = ObjDefSet::read_directories(
            &CompileOptions::default(),
            &[minecraft.clone(), core.clone()],
        )
        .unwrap();
        let names = set
            .packages()
            .iter()
            .map(|p| p.name.as_str())
            .collect::<Vec<_>>();
        assert_eq!(names, ["core", "minecraft"]);
        let definitions = set.graph().object_definitions();
        let (_, region) = &definitions[&Obj::mk_id(6006)];
        assert_eq!(region.parent, Obj::mk_id(8));
        let package = region
            .metadata
            .iter()
            .find(|(key, _)| *key == crate::package::package_key())
            .map(|(_, value)| value.clone());
        assert_eq!(package, Some(moor_var::v_str("minecraft")));
        assert!(
            set.constants().contains_key(&Symbol::mk("core::THING"))
                && set
                    .constants()
                    .contains_key(&Symbol::mk("minecraft::REGION"))
        );
    }

    #[test]
    fn package_mistakes_are_refused() {
        let root = tempfile::tempdir().unwrap();
        let read = |dirs: &[std::path::PathBuf]| {
            ObjDefSet::read_directories(&CompileOptions::default(), dirs)
        };

        let both = root.path().join("both");
        write(
            &both,
            "package.moo",
            r#"package "both" [objdef_version -> 2];"#,
        );
        write(&both, "constants.moo", "define ROOT = #1;");
        assert!(matches!(
            read(&[both]),
            Err(ObjdefLoaderError::InvalidPackage(_))
        ));

        let future = root.path().join("future");
        write(
            &future,
            "package.moo",
            r#"package "future" [objdef_version -> 99];"#,
        );
        assert!(matches!(
            read(&[future]),
            Err(ObjdefLoaderError::InvalidPackage(_))
        ));

        let first = root.path().join("first");
        let second = root.path().join("second");
        write(
            &first,
            "package.moo",
            r#"package "first" [objdef_version -> 2]; define A = #1;"#,
        );
        write(&first, "a.moo", &object("A", "a", "#-1"));
        write(
            &second,
            "package.moo",
            r#"package "second" [objdef_version -> 2]; define B = #2;"#,
        );
        write(&second, "b.moo", &object("first::A", "b", "#-1"));
        assert!(
            matches!(
                read(&[first.clone(), second.clone()]),
                Err(ObjdefLoaderError::DuplicateObjectDefinition(..))
            ),
            "an object defined in two packages is refused"
        );
    }

    #[test]
    fn a_missing_directory_is_reported_by_name() {
        let root = tempfile::tempdir().unwrap();
        let missing = root.path().join("missing-base");
        let Err(error) = ObjDefSet::read_directory(&CompileOptions::default(), &missing) else {
            panic!("a missing directory was read");
        };
        assert!(
            matches!(&error, ObjdefLoaderError::DirectoryNotFound(path) if path == &missing),
            "{error}"
        );
        assert!(error.to_string().contains("missing-base"), "{error}");
    }

    #[test]
    fn a_plain_directory_reads_as_before() {
        let root = tempfile::tempdir().unwrap();
        let plain = root.path().join("plain");
        write(&plain, "constants.moo", "define ROOT = #1;");
        write(&plain, "root.moo", &object("ROOT", "root", "#-1"));
        let set = ObjDefSet::read_directories(&CompileOptions::default(), &[plain]).unwrap();
        assert!(set.packages().is_empty());
        let (_, root_object) = &set.graph().object_definitions()[&Obj::mk_id(1)];
        assert!(
            !root_object
                .metadata
                .iter()
                .any(|(key, _)| *key == crate::package::package_key())
        );
        assert!(set.constants().contains_key(&Symbol::mk("ROOT")));
    }
}
