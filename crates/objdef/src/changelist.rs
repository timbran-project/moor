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

//! Objdef changelist analysis and apply support.
//!
//! This module compares incoming `ObjDefSet` values with the current database snapshot and can
//! apply accepted changes after re-running that analysis. Preview never mutates the database;
//! apply revalidates the current transaction before it changes anything.

use crate::{
    ConflictMode, Constants, Entity, ObjDefLoaderOptions, ObjDefLoaderResults, ObjDefSet,
    ObjDefSource, ObjdefLoaderError, ObjectDefinitionLoader, import_export_id,
};
use moor_common::model::{
    HasUuid, Named, PropPerms, TaskPermissions, ValSet, VerbDef, WorldState, WorldStateError,
    loader::LoaderInterface, prop_flags_string, verb_perms_string,
};
use moor_compiler::{CompileOptions, ObjectDefinition};
use moor_var::{NOTHING, Obj, SYSTEM_OBJECT, Symbol, Var, v_obj, v_str};
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
    /// Write base hash metadata after a successful apply.
    pub write_base_metadata: bool,
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

/// A caller-supplied decision for one non-automatic change.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ApplyResolution {
    Incoming,
    Local,
    Delete,
    Keep,
}

/// Non-mutating or mutating apply result.
#[derive(Debug)]
pub struct ObjDefApplyResult {
    pub ok: bool,
    pub changelist: ObjDefChangelist,
    pub diagnostics: Vec<ChangelistDiagnostic>,
    pub loader_results: Option<ObjDefLoaderResults>,
    pub deleted_objects: Vec<Obj>,
}

struct Analyzer<'a> {
    world_state: &'a dyn WorldState,
    permissions: &'a TaskPermissions,
    options: ChangelistOptions,
}

mod analyze;
mod apply;
mod base_metadata;
mod common;

#[cfg(test)]
mod tests;

pub use analyze::analyze_preview_objdef_changes;
pub use apply::apply_objdef_changes;
pub use base_metadata::{establish_base_metadata, write_base_metadata};
