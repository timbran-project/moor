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

use super::*;
use crate::ObjectDefinitionLoader;
use moor_common::model::{CommitResult, VerbAttrs, WorldStateSource};
use moor_common::util::BitEnum;
use moor_db::{Database, DatabaseConfig, TxDB};
use moor_var::Obj;

const ROOT: Obj = Obj::mk_id(1);
const SOURCE: &str = r#"object #1 [import_export_id -> "review_root"]
owner: #1
wizard: true
verb test (this none this) owner: #1 flags: "rxd"
return "Base";
endverb
endobject"#;

fn database() -> TxDB {
    let db = TxDB::try_open(None, DatabaseConfig::default()).unwrap().0;
    let mut loader = db.loader_client().unwrap();
    ObjectDefinitionLoader::new(loader.as_mut())
        .load_single_object(SOURCE, Default::default(), Default::default())
        .unwrap();
    assert!(matches!(
        loader.commit().unwrap(),
        CommitResult::Success { .. }
    ));
    db
}
fn permissions() -> TaskPermissions {
    TaskPermissions::new(ROOT, BitEnum::new_with(ObjFlag::Wizard))
}
fn sources(text: &str) -> Var {
    v_list(&[record(&[
        ("label", v_str("root.moo")),
        ("text", v_str(text)),
    ])])
}
fn request(operation: &str) -> Var {
    record(&[
        ("schema", v_int(1)),
        ("operation", v_str(operation)),
        ("objects", v_list(&[v_obj(ROOT)])),
        ("fields", v_list(&[v_str("program")])),
    ])
}
fn get(value: &Var, name: &str) -> Var {
    value
        .as_map()
        .unwrap()
        .iter()
        .find(|(k, _)| k.as_string() == Some(name))
        .unwrap()
        .1
}
fn row(report: &Var) -> Var {
    get(report, "rows")
        .as_list()
        .unwrap()
        .iter()
        .next()
        .unwrap()
}
fn inspect(world: &dyn WorldState, source: &str, operation: &str, choices: Option<&Var>) -> Var {
    preview(
        world,
        &permissions(),
        &CompileOptions::default(),
        &sources(source),
        &request(operation),
        choices,
    )
    .unwrap()
}
fn stamp(world: &mut dyn WorldState) {
    let def = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    let (program, _) = world
        .retrieve_verb(&permissions(), &ROOT, def.uuid())
        .unwrap();
    world
        .set_verb_metadata(
            &permissions(),
            &ROOT,
            def.uuid(),
            Symbol::mk(BASE_KEY),
            record(&[
                ("schema", v_str(PROGRAM_SCHEMA)),
                ("program", v_str(&program_fingerprint(&program).unwrap())),
            ]),
        )
        .unwrap();
}

#[test]
fn all_content_classifications() {
    for (b, l, i, want) in [
        (Some("a"), "a", "a", "unchanged"),
        (Some("a"), "a", "b", "upstream"),
        (Some("a"), "b", "a", "local"),
        (Some("a"), "b", "b", "converged"),
        (Some("a"), "b", "c", "conflict"),
        (None, "a", "a", "unbased"),
    ] {
        assert_eq!(classify(b, l, i), want);
    }
}

#[test]
fn preview_and_drafts_commit_no_mutations() {
    let db = database();
    let world = db.new_world_state().unwrap();
    let report = inspect(world.as_ref(), SOURCE, "adopt", None);
    assert_eq!(get(&row(&report), "classification"), v_str("unbased"));
    let id = get(&row(&report), "id");
    let draft = v_map(&[(
        id.clone(),
        record(&[("choice", v_str("edited")), ("program", v_str("return 3;"))]),
    )]);
    assert!(
        preview(
            world.as_ref(),
            &permissions(),
            &CompileOptions::default(),
            &sources(SOURCE),
            &request("adopt"),
            Some(&draft)
        )
        .is_err()
    );
    assert!(matches!(
        world.commit().unwrap(),
        CommitResult::Success {
            mutations_made: false,
            ..
        }
    ));

    let mut world = db.new_world_state().unwrap();
    stamp(world.as_mut());
    world.commit().unwrap();
    let world = db.new_world_state().unwrap();
    let report = inspect(world.as_ref(), SOURCE, "update", Some(&draft));
    let validation = get(&report, "validation")
        .as_list()
        .unwrap()
        .iter()
        .next()
        .unwrap();
    assert!(get(&validation, "valid").is_true());
    let invalid = v_map(&[(
        id,
        record(&[("choice", v_str("edited")), ("program", v_str("return (;"))]),
    )]);
    let report = inspect(world.as_ref(), SOURCE, "update", Some(&invalid));
    let validation = get(&report, "validation")
        .as_list()
        .unwrap()
        .iter()
        .next()
        .unwrap();
    assert!(!get(&validation, "valid").is_true());
    assert_eq!(get(&validation, "pane"), v_str("result"));
    assert!(matches!(
        world.commit().unwrap(),
        CommitResult::Success {
            mutations_made: false,
            ..
        }
    ));
}

#[test]
fn evidence_changes_with_live_code_baseline_and_definition_attributes() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    stamp(world.as_mut());
    world.commit().unwrap();
    let mut world = db.new_world_state().unwrap();
    let first = inspect(world.as_ref(), SOURCE, "update", None);
    let def = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    world
        .update_verb_with_id(
            &permissions(),
            &ROOT,
            def.uuid(),
            VerbAttrs {
                definer: None,
                owner: None,
                names: None,
                flags: None,
                args_spec: None,
                program: Some(ProgramType::MooR(
                    compile("return 2;", Default::default()).unwrap(),
                )),
            },
        )
        .unwrap();
    let second = inspect(world.as_ref(), SOURCE, "update", None);
    assert_ne!(get(&first, "evidence"), get(&second, "evidence"));
    assert_eq!(get(&row(&second), "classification"), v_str("local"));
    stamp(world.as_mut());
    let third = inspect(world.as_ref(), SOURCE, "update", None);
    assert_ne!(get(&second, "evidence"), get(&third, "evidence"));
    world
        .update_verb_with_id(
            &permissions(),
            &ROOT,
            def.uuid(),
            VerbAttrs {
                definer: None,
                owner: None,
                names: None,
                flags: Some(moor_common::model::VerbFlag::rx()),
                args_spec: None,
                program: None,
            },
        )
        .unwrap();
    let fourth = inspect(world.as_ref(), SOURCE, "update", None);
    assert_ne!(get(&third, "evidence"), get(&fourth, "evidence"));
}

#[test]
fn details_preserve_evidence_and_unknown_options_fail() {
    let db = database();
    let world = db.new_world_state().unwrap();
    let report = inspect(world.as_ref(), SOURCE, "adopt", None);
    let mut req = request("adopt")
        .as_map()
        .unwrap()
        .iter()
        .collect::<Vec<_>>();
    req.push((v_str("details"), v_list(&[get(&row(&report), "id")])));
    let detailed = preview(
        world.as_ref(),
        &permissions(),
        &CompileOptions::default(),
        &sources(SOURCE),
        &v_map(&req),
        None,
    )
    .unwrap();
    assert_eq!(get(&report, "evidence"), get(&detailed, "evidence"));
    assert!(
        get(&row(&detailed), "live_text")
            .as_string()
            .unwrap()
            .contains("Base")
    );
    req.push((v_str("force"), v_bool(true)));
    assert!(
        preview(
            world.as_ref(),
            &permissions(),
            &CompileOptions::default(),
            &sources(SOURCE),
            &v_map(&req),
            None
        )
        .is_err()
    );
}

#[test]
fn forged_identity_and_unknown_schema_block_automatic_update() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    stamp(world.as_mut());
    let report = inspect(
        world.as_ref(),
        &SOURCE.replace("review_root", "different"),
        "update",
        None,
    );
    assert!(!get(&row(&report), "eligible").is_true());
    let def = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    world
        .set_verb_metadata(
            &permissions(),
            &ROOT,
            def.uuid(),
            Symbol::mk(BASE_KEY),
            record(&[("schema", v_str("future")), ("program", v_str("unknown"))]),
        )
        .unwrap();
    let report = inspect(world.as_ref(), SOURCE, "update", None);
    assert!(!get(&row(&report), "eligible").is_true());
    let report = inspect(world.as_ref(), SOURCE, "adopt", None);
    assert!(get(&row(&report), "eligible").is_true());
}

fn apply_report(
    world: &mut dyn WorldState,
    source: &str,
    operation: &str,
    report: &Var,
    choices: &Var,
) -> Result<Var, ApplyError> {
    apply(
        world,
        &permissions(),
        &CompileOptions::default(),
        &sources(source),
        &request(operation),
        &get(report, "evidence"),
        choices,
    )
}

fn live_program(world: &dyn WorldState) -> ProgramType {
    let definition = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    world
        .retrieve_verb(&permissions(), &ROOT, definition.uuid())
        .unwrap()
        .0
}

#[test]
fn adoption_keep_local_and_repeat_preserve_live_program() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    let original = program_fingerprint(&live_program(world.as_ref())).unwrap();
    let report = inspect(world.as_ref(), SOURCE, "adopt", None);
    apply_report(world.as_mut(), SOURCE, "adopt", &report, &v_map(&[])).unwrap();
    assert_eq!(
        program_fingerprint(&live_program(world.as_ref())).unwrap(),
        original
    );
    world.commit().unwrap();

    let incoming = SOURCE.replace("Base", "Upstream");
    let mut world = db.new_world_state().unwrap();
    let report = inspect(world.as_ref(), &incoming, "update", None);
    assert_eq!(get(&row(&report), "classification"), v_str("upstream"));
    let choice = v_map(&[(
        get(&row(&report), "id"),
        record(&[("choice", v_str("local"))]),
    )]);
    apply_report(world.as_mut(), &incoming, "update", &report, &choice).unwrap();
    world.commit().unwrap();
    let mut world = db.new_world_state().unwrap();
    assert_eq!(
        program_fingerprint(&live_program(world.as_ref())).unwrap(),
        original
    );
    let report = inspect(world.as_ref(), &incoming, "update", None);
    assert_eq!(get(&row(&report), "classification"), v_str("local"));
    apply_report(world.as_mut(), &incoming, "update", &report, &v_map(&[])).unwrap();
    assert!(matches!(
        world.commit().unwrap(),
        CommitResult::Success {
            mutations_made: false,
            ..
        }
    ));
}

#[test]
fn edited_choice_installs_result_but_accepts_incoming() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    stamp(world.as_mut());
    let definition = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    world
        .set_verb_metadata(
            &permissions(),
            &ROOT,
            definition.uuid(),
            Symbol::mk("unmanaged"),
            v_str("keep"),
        )
        .unwrap();
    let incoming = SOURCE.replace("Base", "Upstream");
    let report = inspect(world.as_ref(), &incoming, "update", None);
    let id = get(&row(&report), "id");
    let draft = record(&[
        ("choice", v_str("edited")),
        ("program", v_str("return \"Result\";")),
    ]);
    assert!(
        apply_report(
            world.as_mut(),
            &incoming,
            "update",
            &report,
            &v_map(&[(id.clone(), draft.clone())])
        )
        .is_err()
    );
    let validation = inspect(
        world.as_ref(),
        &incoming,
        "update",
        Some(&v_map(&[(id.clone(), draft)])),
    );
    let validation = get(&validation, "validation")
        .as_list()
        .unwrap()
        .iter()
        .next()
        .unwrap();
    let token = get(&validation, "validation");
    let choice = |source| {
        v_map(&[(
            id.clone(),
            record(&[
                ("choice", v_str("edited")),
                ("program", v_str(source)),
                ("validation", token.clone()),
            ]),
        )])
    };
    assert!(
        apply_report(
            world.as_mut(),
            &incoming,
            "update",
            &report,
            &choice("return \"Changed\";")
        )
        .is_err()
    );
    apply_report(
        world.as_mut(),
        &incoming,
        "update",
        &report,
        &choice("return \"Result\";"),
    )
    .unwrap();
    let updated = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    assert_eq!(updated.uuid(), definition.uuid());
    assert_eq!(updated.names(), definition.names());
    assert_eq!(updated.flags(), definition.flags());
    assert_eq!(updated.owner(), definition.owner());
    assert_eq!(
        world
            .get_verb_metadata(
                &permissions(),
                &ROOT,
                updated.uuid(),
                Symbol::mk("unmanaged")
            )
            .unwrap(),
        Some(v_str("keep"))
    );
    let next = inspect(world.as_ref(), &incoming, "update", None);
    assert_eq!(get(&row(&next), "classification"), v_str("local"));
    assert_eq!(get(&row(&next), "base"), get(&row(&report), "incoming"));
    assert_eq!(
        program_text(&live_program(world.as_ref())).unwrap(),
        v_str("return \"Result\";")
    );
    world.commit().unwrap();
}

#[test]
fn stale_evidence_and_unresolved_conflicts_write_nothing() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    stamp(world.as_mut());
    world.commit().unwrap();
    let world = db.new_world_state().unwrap();
    let source = SOURCE.replace("Base", "First");
    let report = inspect(world.as_ref(), &source, "update", None);
    world.commit().unwrap();
    let mut world = db.new_world_state().unwrap();
    assert!(
        apply_report(
            world.as_mut(),
            &SOURCE.replace("Base", "Other"),
            "update",
            &report,
            &v_map(&[])
        )
        .is_err()
    );
    assert!(matches!(
        world.commit().unwrap(),
        CommitResult::Success {
            mutations_made: false,
            ..
        }
    ));
    let mut world = db.new_world_state().unwrap();
    apply_report(world.as_mut(), &source, "update", &report, &v_map(&[])).unwrap();
    world.commit().unwrap();
    let mut world = db.new_world_state().unwrap();
    assert!(apply_report(world.as_mut(), &source, "update", &report, &v_map(&[])).is_err());
    // Establish an older baseline to model an independent local edit.
    let definition = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    world
        .set_verb_metadata(
            &permissions(),
            &ROOT,
            definition.uuid(),
            Symbol::mk(BASE_KEY),
            record(&[
                ("schema", v_str(PROGRAM_SCHEMA)),
                ("program", get(&row(&report), "base")),
            ]),
        )
        .unwrap();
    world.commit().unwrap();
    let source = SOURCE.replace("Base", "Second");
    let mut world = db.new_world_state().unwrap();
    let report = inspect(world.as_ref(), &source, "update", None);
    assert_eq!(get(&row(&report), "classification"), v_str("conflict"));
    assert!(apply_report(world.as_mut(), &source, "update", &report, &v_map(&[])).is_err());
    let choice = v_map(&[(
        get(&row(&report), "id"),
        record(&[("choice", v_str("defer"))]),
    )]);
    apply_report(world.as_mut(), &source, "update", &report, &choice).unwrap();
    assert!(matches!(
        world.commit().unwrap(),
        CommitResult::Success {
            mutations_made: false,
            ..
        }
    ));
}

#[test]
fn late_writer_failure_requires_rollback_of_program_and_baseline() {
    let db = database();
    let mut world = db.new_world_state().unwrap();
    let definition = world
        .get_verb(&permissions(), &ROOT, Symbol::mk("test"))
        .unwrap();
    let original = program_fingerprint(&live_program(world.as_ref())).unwrap();
    let actions = vec![
        ProgramAction {
            object: ROOT,
            uuid: definition.uuid(),
            program: Some(ProgramType::MooR(
                compile("return 9;", CompileOptions::default()).unwrap(),
            )),
            baseline: record(&[
                ("schema", v_str(PROGRAM_SCHEMA)),
                ("program", v_str("injected")),
            ]),
        },
        ProgramAction {
            object: ROOT,
            uuid: uuid::Uuid::nil(),
            program: None,
            baseline: v_int(0),
        },
    ];
    assert!(matches!(
        write_actions(world.as_mut(), &permissions(), actions),
        Err(ApplyError::Mutation(_))
    ));
    world.rollback().unwrap();
    let world = db.new_world_state().unwrap();
    assert_eq!(
        program_fingerprint(&live_program(world.as_ref())).unwrap(),
        original
    );
    assert_eq!(
        world
            .get_verb_metadata(
                &permissions(),
                &ROOT,
                definition.uuid(),
                Symbol::mk(BASE_KEY)
            )
            .unwrap(),
        None
    );
}

#[test]
fn bootstrap_derives_baselines_in_import_transaction() {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(directory.path().join("root.moo"), SOURCE).unwrap();
    let db = TxDB::try_open(None, DatabaseConfig::default()).unwrap().0;
    let mut loader = db.loader_client().unwrap();
    let mut import = ObjectDefinitionLoader::new(loader.as_mut());
    import
        .load_objdef_directory(
            CompileOptions::default(),
            directory.path(),
            Default::default(),
        )
        .unwrap();
    import.enroll_imported_programs().unwrap();
    loader.commit().unwrap();
    let world = db.new_world_state().unwrap();
    assert_eq!(
        get(
            &row(&inspect(world.as_ref(), SOURCE, "update", None)),
            "classification"
        ),
        v_str("unchanged")
    );
}

#[test]
fn baseline_survives_process_restart() {
    if let Ok(path) = std::env::var("MOOR_REVIEW_RESTART_DB") {
        let db = TxDB::try_open(Some(std::path::Path::new(&path)), DatabaseConfig::default())
            .unwrap()
            .0;
        if std::env::var("MOOR_REVIEW_RESTART_PHASE").unwrap() == "enroll" {
            let mut loader = db.loader_client().unwrap();
            ObjectDefinitionLoader::new(loader.as_mut())
                .load_single_object(SOURCE, Default::default(), Default::default())
                .unwrap();
            loader.commit().unwrap();
            let mut world = db.new_world_state().unwrap();
            let report = inspect(world.as_ref(), SOURCE, "adopt", None);
            apply_report(world.as_mut(), SOURCE, "adopt", &report, &v_map(&[])).unwrap();
            world.commit().unwrap();
            db.wait_for_persistence().unwrap();
        } else {
            let world = db.new_world_state().unwrap();
            assert_eq!(
                get(
                    &row(&inspect(world.as_ref(), SOURCE, "update", None)),
                    "classification"
                ),
                v_str("unchanged")
            );
        }
        return;
    }
    let directory = tempfile::tempdir().unwrap();
    for phase in ["enroll", "verify"] {
        let result = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "review::tests::baseline_survives_process_restart",
                "--exact",
            ])
            .env("MOOR_REVIEW_RESTART_DB", directory.path())
            .env("MOOR_REVIEW_RESTART_PHASE", phase)
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "{}{}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );
    }
}
