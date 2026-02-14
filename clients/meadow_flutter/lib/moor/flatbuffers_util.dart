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

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart'
    as moor_var;

String uuObjIdToString(BigInt packedValue) {
  // 62-bit packed: [autoincrement (16)] [rng (6)] [epoch_ms (40)]
  final autoincrement = ((packedValue >> 46) & BigInt.from(0xFFFF)).toInt();
  final rng = ((packedValue >> 40) & BigInt.from(0x3F)).toInt();
  final epochMs = packedValue & BigInt.from(0xFFFFFFFFFF);

  final firstGroup = ((autoincrement << 6) | rng)
      .toRadixString(16)
      .toUpperCase()
      .padLeft(6, '0');
  final secondGroup = epochMs.toRadixString(16).toUpperCase().padLeft(10, '0');
  return '$firstGroup-$secondGroup';
}

String? objToCurie(moor_common.Obj? obj) {
  if (obj == null) {
    return null;
  }

  // ObjUnionTypeId: NONE=0, ObjId=1, UuObjId=2, AnonymousObjId=3
  final objType = obj.objType?.value ?? 0;
  if (objType == 1) {
    final objId = obj.obj as moor_common.ObjId?;
    if (objId == null) {
      return null;
    }
    return 'oid:${objId.id}';
  }
  if (objType == 2) {
    final uuObj = obj.obj as moor_common.UuObjId?;
    if (uuObj == null) {
      return null;
    }
    final packed = BigInt.from(uuObj.packedValue);
    return 'uuid:${uuObjIdToString(packed)}';
  }

  // Anonymous objects cannot be used for operations; don't mint a CURIE.
  return null;
}

/// Strict decode used for narrative output: only allow strings or list-of-strings.
/// Anything else returns an empty list.
List<String> decodeVarAsLines(moor_var.Var? value) {
  if (value == null) {
    return const [];
  }

  final variantType = value.variantType?.value;
  if (variantType == moor_var.VarUnionTypeId.VarStr.value) {
    final v = value.variant as moor_var.VarStr?;
    final s = v?.value;
    if (s == null) {
      return const [];
    }
    return [s];
  }

  if (variantType == moor_var.VarUnionTypeId.VarList.value) {
    final list = value.variant as moor_var.VarList?;
    if (list == null) {
      return const [];
    }

    final out = <String>[];
    final elements = list.elements;
    if (elements == null) {
      return const [];
    }
    for (final el in elements) {
      if (el.variantType?.value != moor_var.VarUnionTypeId.VarStr.value) {
        continue;
      }
      final vs = el.variant as moor_var.VarStr?;
      final s = vs?.value;
      if (s == null) {
        continue;
      }
      out.add(s);
    }
    return out;
  }

  return const [];
}
