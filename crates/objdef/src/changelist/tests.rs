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

use super::common::stable_hash;
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
    analyze_preview_objdef_changes(
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
                object #10 [import_export_id -> "thing", base_parent_hash -> "sha256:base"]
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
            .any(|change| change.kind == "object_parent")
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
            remove_absent_entities: false,
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

#[test]
fn apply_clean_create_mutates_loader_transaction() {
    let tmpdir = tempfile::tempdir().unwrap();
    let db = test_db(tmpdir.path());
    let ws = db.new_world_state().unwrap();
    let mut loader = db.loader_client().unwrap();
    let result = apply_objdef_changes(
        ws.as_ref(),
        loader.as_mut(),
        &system_permissions(),
        &CompileOptions::default(),
        [ObjDefSource::new(
            "apply.moo",
            r#"
                object #10
                    name: "Fresh"
                    owner: #0
                    parent: #-1
                    location: #-1
                endobject
                "#,
        )],
        ChangelistOptions::default(),
        Vec::new(),
    )
    .unwrap();

    assert!(result.ok, "{:?}", result.diagnostics);
    loader.commit().unwrap();
    let ws = db.new_world_state().unwrap();
    assert!(ws.valid(&Obj::mk_id(10)).unwrap());
}

#[test]
fn apply_rejects_graph_diagnostic_without_mutation() {
    let tmpdir = tempfile::tempdir().unwrap();
    let db = test_db(tmpdir.path());
    let ws = db.new_world_state().unwrap();
    let mut loader = db.loader_client().unwrap();
    let result = apply_objdef_changes(
        ws.as_ref(),
        loader.as_mut(),
        &system_permissions(),
        &CompileOptions::default(),
        [ObjDefSource::new(
            "cycle.moo",
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
        )],
        ChangelistOptions::default(),
        Vec::new(),
    )
    .unwrap();

    assert!(!result.ok);
    assert!(
        result
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.kind == "parent_cycle")
    );
    loader.commit().unwrap();
    let ws = db.new_world_state().unwrap();
    assert!(!ws.valid(&Obj::mk_id(10)).unwrap());
    assert!(!ws.valid(&Obj::mk_id(11)).unwrap());
}
