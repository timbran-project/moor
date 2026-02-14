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

import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart'
    as moor_var;
import 'package:meadow_flutter/moor/flatbuffers_util.dart';
import 'package:meadow_flutter/moor/object_ref.dart';

Object? decodeVarLoose(moor_var.Var? v) {
  if (v == null) return null;
  final t = v.variantType?.value ?? 0;

  if (t == moor_var.VarUnionTypeId.VarNone.value) return null;

  if (t == moor_var.VarUnionTypeId.VarBool.value) {
    final vb = v.variant as moor_var.VarBool?;
    return vb?.value;
  }

  if (t == moor_var.VarUnionTypeId.VarInt.value) {
    final vi = v.variant as moor_var.VarInt?;
    return vi?.value;
  }

  if (t == moor_var.VarUnionTypeId.VarFloat.value) {
    final vf = v.variant as moor_var.VarFloat?;
    return vf?.value;
  }

  if (t == moor_var.VarUnionTypeId.VarStr.value) {
    final vs = v.variant as moor_var.VarStr?;
    return vs?.value;
  }

  if (t == moor_var.VarUnionTypeId.VarSym.value) {
    final sym = v.variant as moor_var.VarSym?;
    return sym?.symbol?.value;
  }

  if (t == moor_var.VarUnionTypeId.VarObj.value) {
    final vo = v.variant as moor_var.VarObj?;
    final curie = objToCurie(vo?.obj);
    return curie == null ? null : ObjectRef(curie);
  }

  if (t == moor_var.VarUnionTypeId.VarList.value) {
    final vl = v.variant as moor_var.VarList?;
    final els = vl?.elements;
    if (els == null) return const <Object?>[];
    return els.map(decodeVarLoose).toList();
  }

  if (t == moor_var.VarUnionTypeId.VarMap.value) {
    final vm = v.variant as moor_var.VarMap?;
    final pairs = vm?.pairs;
    if (pairs == null) return const <String, Object?>{};
    final out = <String, Object?>{};
    for (final p in pairs) {
      final key = decodeVarLoose(p.key);
      if (key is! String) {
        continue;
      }
      out[key] = decodeVarLoose(p.value);
    }
    return out;
  }

  // Everything else is ignored for this spike.
  return null;
}
