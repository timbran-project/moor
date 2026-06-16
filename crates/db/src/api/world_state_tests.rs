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

use crate::{Database, DatabaseConfig, TxDB};
use moor_common::{
    model::{ObjAttrs, ObjFlag, ObjectKind, TaskPermissions, WorldStateError, WorldStateSource},
    util::BitEnum,
};
use moor_var::{NOTHING, Obj, SYSTEM_OBJECT};

const WIZARD: Obj = Obj::mk_id(2);
const OWNER: Obj = Obj::mk_id(3);
const OTHER: Obj = Obj::mk_id(4);

fn permissions(principal: Obj) -> TaskPermissions {
    TaskPermissions::new(principal, BitEnum::new())
}

fn test_db() -> TxDB {
    let db = TxDB::open(None, DatabaseConfig::default()).0;
    let mut loader = db.loader_client().unwrap();
    loader
        .create_object(
            ObjectKind::Objid(WIZARD),
            &ObjAttrs::new(WIZARD, NOTHING, NOTHING, ObjFlag::all_flags(), "Wizard"),
        )
        .unwrap();
    loader
        .create_object(
            ObjectKind::Objid(OWNER),
            &ObjAttrs::new(OWNER, NOTHING, NOTHING, BitEnum::new(), "Owner"),
        )
        .unwrap();
    loader
        .create_object(
            ObjectKind::Objid(OTHER),
            &ObjAttrs::new(OTHER, NOTHING, NOTHING, BitEnum::new(), "Other"),
        )
        .unwrap();
    loader
        .create_object(
            ObjectKind::Objid(SYSTEM_OBJECT),
            &ObjAttrs::new(OWNER, NOTHING, NOTHING, BitEnum::new(), "System"),
        )
        .unwrap();
    loader.commit().unwrap();
    db
}

#[test]
fn recycle_object_requires_owner_or_wizard_not_public_write() {
    let db = test_db();
    let mut tx = db.new_world_state().unwrap();
    let obj = tx
        .create_object(
            &permissions(WIZARD),
            &NOTHING,
            &OWNER,
            BitEnum::new_with(ObjFlag::Write),
            ObjectKind::NextObjid,
        )
        .unwrap();

    let err = tx.recycle_object(&permissions(OTHER), &obj).unwrap_err();
    assert!(matches!(err, WorldStateError::ObjectPermissionDenied));
    assert!(tx.valid(&obj).unwrap());

    tx.recycle_object(&permissions(OWNER), &obj).unwrap();
    assert!(!tx.valid(&obj).unwrap());
}

#[test]
fn renumber_object_requires_wizard_not_control_of_system_object() {
    let db = test_db();
    let mut tx = db.new_world_state().unwrap();
    let obj = tx
        .create_object(
            &permissions(WIZARD),
            &NOTHING,
            &OWNER,
            BitEnum::new(),
            ObjectKind::NextObjid,
        )
        .unwrap();

    let err = tx
        .renumber_object(
            &permissions(OWNER),
            &obj,
            Some(ObjectKind::Objid(Obj::mk_id(100))),
        )
        .unwrap_err();
    assert!(matches!(err, WorldStateError::ObjectPermissionDenied));
    assert!(tx.valid(&obj).unwrap());

    let new_obj = tx
        .renumber_object(
            &permissions(WIZARD),
            &obj,
            Some(ObjectKind::Objid(Obj::mk_id(100))),
        )
        .unwrap();
    assert_eq!(new_obj, Obj::mk_id(100));
}
