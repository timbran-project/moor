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

use crate::{Constants, ObjdefLoaderError};
use moor_compiler::{CompileOptions, ObjFileContext, ObjectDefinition, compile_object_definitions};
use moor_var::{Obj, Symbol, Var};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

#[derive(Debug, Clone)]
/// One objdef input unit with a stable diagnostic label.
///
/// `path` is optional because callers may supply objdefs from memory rather than from a directory.
/// When present, it is used for include path resolution and for diagnostics. When absent, `label`
/// is used only as a diagnostic/base-path stand-in.
pub struct ObjDefSource {
    /// Human-readable source name for parse errors and duplicate diagnostics.
    pub label: String,
    /// Raw objdef text.
    pub contents: String,
    /// Filesystem path, when the source came from disk.
    pub path: Option<PathBuf>,
}

impl ObjDefSource {
    /// Build an in-memory objdef source.
    pub fn new(label: impl Into<String>, contents: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            contents: contents.into(),
            path: None,
        }
    }

    /// Build an objdef source read from a concrete path.
    pub fn from_path(path: PathBuf, contents: String) -> Self {
        Self {
            label: path.to_string_lossy().into_owned(),
            contents,
            path: Some(path),
        }
    }

    fn base_path_source(&self) -> &Path {
        self.path
            .as_deref()
            .unwrap_or_else(|| Path::new(self.label.as_str()))
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
pub struct ObjDefSet {
    graph: ProposedObjectGraph,
    constants: HashMap<Symbol, Var>,
}

impl ObjDefSet {
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
            apply_constants(constants, &mut context, "<constants>")?;
        }

        let mut object_definitions: HashMap<Obj, (String, ObjectDefinition)> = HashMap::new();
        for source in sources {
            context.set_base_path(source.base_path_source());
            let compiled_defs =
                compile_object_definitions(&source.contents, compile_options, &mut context)
                    .map_err(|e| {
                        ObjdefLoaderError::ObjectDefParseError(source.label.clone(), Box::new(e))
                    })?;

            for compiled_def in compiled_defs {
                let oid = compiled_def.oid;
                if let Some((first_source, _)) = object_definitions.get(&oid) {
                    return Err(ObjdefLoaderError::DuplicateObjectDefinition(
                        source.label.clone(),
                        oid,
                        first_source.clone(),
                    ));
                }
                object_definitions.insert(oid, (source.label.clone(), compiled_def));
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
        })
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

pub(crate) fn apply_constants(
    constants: &Constants,
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
            let compile_opts = CompileOptions::default();
            compile_object_definitions(content, &compile_opts, context).map_err(|e| {
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
}
