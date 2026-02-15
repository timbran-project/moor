// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meta/meta.dart';

@immutable
class ObjectRef {
  final MoorObj obj;

  const ObjectRef(this.obj);

  static ObjectRef? fromCurie(String curie) {
    final parsed = MoorObj.parse(curie);
    if (parsed == null) {
      return null;
    }
    return ObjectRef(parsed);
  }

  String get curie => obj.toCurie();

  @override
  String toString() => curie;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectRef &&
          runtimeType == other.runtimeType &&
          obj == other.obj;

  @override
  int get hashCode => obj.hashCode;
}

ObjectRef? objectRefFromDynamic(Object? value) {
  if (value == null) return null;

  if (value is ObjectRef) return value;
  if (value is MoorObj) return ObjectRef(value);
  if (value is MoorVar) {
    final obj = (value as MoorVar).asObj();
    if (obj != null) return ObjectRef(obj);
    return null;
  }

  if (value is int) {
    return ObjectRef(MoorObjId(value));
  }

  if (value is String) {
    return ObjectRef.fromCurie(value);
  }

  if (value is Map) {
    // Meadow/web established shape: { oid: N } / { uuid: "..."}
    final oid = value['oid'];
    if (oid is int) return ObjectRef(MoorObjId(oid));

    final uuid = value['uuid'];
    if (uuid is String) {
      return ObjectRef.fromCurie('uuid:$uuid');
    }
  }

  return null;
}

String? objectRefToCurie(Object? value) => objectRefFromDynamic(value)?.curie;
