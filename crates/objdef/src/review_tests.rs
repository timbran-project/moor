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
