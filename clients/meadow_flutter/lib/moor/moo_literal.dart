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
import 'package:meadow_flutter/moor/flatbuffers_util.dart';

String escapeMooString(String s) {
  // Match Meadow web behavior: escape backslash and double quote.
  // Preserve newlines in the literal as actual newlines (server-side parser
  // should accept it); if this turns out to be wrong, we can switch to \n.
  return s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

String symbolToLiteral(moor_common.Symbol? sym) {
  final v = sym?.value;
  if (v == null || v.isEmpty) {
    return "'";
  }
  return "'$v";
}

String objToLiteral(moor_common.Obj? obj) {
  final curie = objToCurie(obj);
  if (curie == null) {
    return '#0';
  }
  // curie is like "oid:2" in this codebase; for MOO literal, use "#2".
  if (curie.startsWith('oid:')) {
    return '#${curie.substring('oid:'.length)}';
  }
  return '#0';
}

String errorCodeToLiteral(moor_common.ErrorCode c) {
  switch (c.value) {
    case 0:
      return 'E_NONE';
    case 1:
      return 'E_TYPE';
    case 2:
      return 'E_DIV';
    case 3:
      return 'E_PERM';
    case 4:
      return 'E_PROPNF';
    case 5:
      return 'E_VERBNF';
    case 6:
      return 'E_VARNF';
    case 7:
      return 'E_INVIND';
    case 8:
      return 'E_RECMOVE';
    case 9:
      return 'E_MAXREC';
    case 10:
      return 'E_RANGE';
    case 11:
      return 'E_ARGS';
    case 12:
      return 'E_NACC';
    case 13:
      return 'E_INVARG';
    case 14:
      return 'E_QUOTA';
    case 15:
      return 'E_FLOAT';
    case 16:
      return 'E_FILE';
    case 17:
      return 'E_EXEC';
    case 18:
      return 'E_INTRPT';
    case 255:
      return 'E_CUSTOM';
    default:
      return 'E_NONE';
  }
}

bool isSupportedMooLiteralVar(moor_var.Var? v) {
  final t = v?.variantType?.value;
  return t == moor_var.VarUnionTypeId.VarNone.value ||
      t == moor_var.VarUnionTypeId.VarBool.value ||
      t == moor_var.VarUnionTypeId.VarInt.value ||
      t == moor_var.VarUnionTypeId.VarFloat.value ||
      t == moor_var.VarUnionTypeId.VarStr.value ||
      t == moor_var.VarUnionTypeId.VarObj.value ||
      t == moor_var.VarUnionTypeId.VarErr.value ||
      t == moor_var.VarUnionTypeId.VarList.value ||
      t == moor_var.VarUnionTypeId.VarMap.value ||
      t == moor_var.VarUnionTypeId.VarSym.value;
}

String varToMooLiteral(moor_var.Var? v, {int depth = 0}) {
  if (v == null) return 'none';
  if (depth > 32) return 'none';

  switch (v.variantType?.value) {
    case 1: // VarNone
      return 'none';
    case 2: // VarBool
      final b = v.variant as moor_var.VarBool?;
      return (b?.value ?? false) ? 'true' : 'false';
    case 3: // VarInt
      final i = v.variant as moor_var.VarInt?;
      return '${i?.value ?? 0}';
    case 4: // VarFloat
      final f = v.variant as moor_var.VarFloat?;
      return '${f?.value ?? 0.0}';
    case 5: // VarStr
      final s = v.variant as moor_var.VarStr?;
      final text = s?.value ?? '';
      return '"${escapeMooString(text)}"';
    case 6: // VarObj
      final o = v.variant as moor_var.VarObj?;
      return objToLiteral(o?.obj);
    case 7: // VarErr
      final e = v.variant as moor_var.VarErr?;
      final err = e?.error;
      if (err == null) return 'E_NONE';
      if (err.errType.value == moor_common.ErrorCode.ErrCustom.value) {
        final custom = err.customSymbol;
        if (custom != null &&
            custom.value != null &&
            custom.value!.isNotEmpty) {
          return custom.value!;
        }
        return 'E_CUSTOM';
      }
      return errorCodeToLiteral(err.errType);
    case 8: // VarList
      final l = v.variant as moor_var.VarList?;
      final els = l?.elements ?? const <moor_var.Var>[];
      final items = <String>[];
      for (final it in els) {
        items.add(varToMooLiteral(it, depth: depth + 1));
      }
      return '{${items.join(', ')}}';
    case 9: // VarMap
      final m = v.variant as moor_var.VarMap?;
      final pairs = m?.pairs ?? const <moor_var.VarMapPair>[];
      final items = <String>[];
      for (final p in pairs) {
        items.add(
          '${varToMooLiteral(p.key, depth: depth + 1)} -> ${varToMooLiteral(p.value, depth: depth + 1)}',
        );
      }
      return '[${items.join(', ')}]';
    case 10: // VarSym
      final s = v.variant as moor_var.VarSym?;
      return symbolToLiteral(s?.symbol);
    default:
      return 'none';
  }
}
