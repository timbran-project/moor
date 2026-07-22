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
    as common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meta/meta.dart';

@immutable
class MoorErr implements Comparable<MoorErr> {
  final common.ErrorCode code;
  final String? message;
  final MoorVar? extra;

  const MoorErr(this.code, {this.message, this.extra});

  factory MoorErr.fromFlatBuffer(fbs.VarErr v) {
    final err = v.error;
    if (err == null) return const MoorErr(common.ErrorCode.E_NONE);
    final val = err.value;
    return MoorErr(
      err.errType,
      message: err.msg,
      extra: val != null ? MoorVar.fromFlatBuffer(val) : null,
    );
  }

  String toLiteral() {
    switch (code.value) {
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

  fbs.VarErrObjectBuilder toVarErrBuilder() {
    return fbs.VarErrObjectBuilder(
      error: common.ErrorObjectBuilder(
        errType: code,
        msg: message,
        value: extra?.toVarBuilder(),
      ),
    );
  }

  fbs.VarObjectBuilder toVarBuilder() {
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarErr,
      variant: toVarErrBuilder(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorErr &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message &&
          extra == other.extra;

  @override
  int get hashCode => Object.hash(code, message, extra);

  @override
  int compareTo(MoorErr other) {
    final cmp = code.value.compareTo(other.code.value);
    if (cmp != 0) return cmp;
    if (message != null && other.message != null) {
      final msgCmp = message!.compareTo(other.message!);
      if (msgCmp != 0) return msgCmp;
    }
    return 0;
  }
}
