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

import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_err.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meta/meta.dart';

/// Sentinel for MOO "none" value.
@immutable
class MoorNone {
  const MoorNone();
  @override
  String toString() => 'none';
  @override
  bool operator ==(Object other) => other is MoorNone;
  @override
  int get hashCode => 0;
}

const MoorVar moorNoneVar = MoorVar(MoorNone());

/// Zero-cost extension type providing a consistent OO interface for MOO values
/// while keeping scalars as native Dart types (int, double, bool, String).
/// Corresponds to `crates/var/src/variant.rs` struct `Var`.
extension type const MoorVar(Object value) {
  /// Decodes a FlatBuffer [fbs.Var] into a [MoorVar].
  factory MoorVar.fromFlatBuffer(fbs.Var v) {
    final type = v.variantType?.value;
    final variant = v.variant;
    if (type == null || variant == null) return moorNoneVar;
    if (type == fbs.VarUnionTypeId.VarNone.value) {
      return moorNoneVar;
    } else if (type == fbs.VarUnionTypeId.VarBool.value) {
      return MoorVar((variant as fbs.VarBool).value);
    } else if (type == fbs.VarUnionTypeId.VarInt.value) {
      return MoorVar((variant as fbs.VarInt).value);
    } else if (type == fbs.VarUnionTypeId.VarFloat.value) {
      return MoorVar((variant as fbs.VarFloat).value);
    } else if (type == fbs.VarUnionTypeId.VarStr.value) {
      return MoorVar((variant as fbs.VarStr).value ?? '');
    } else if (type == fbs.VarUnionTypeId.VarObj.value) {
      return MoorVar(MoorObj.fromFlatBuffer(variant as fbs.VarObj));
    } else if (type == fbs.VarUnionTypeId.VarErr.value) {
      return MoorVar(MoorErr.fromFlatBuffer(variant as fbs.VarErr));
    } else if (type == fbs.VarUnionTypeId.VarList.value) {
      return MoorVar(MoorList.fromFlatBuffer(variant as fbs.VarList));
    } else if (type == fbs.VarUnionTypeId.VarMap.value) {
      return MoorVar(MoorMap.fromFlatBuffer(variant as fbs.VarMap));
    } else if (type == fbs.VarUnionTypeId.VarSym.value) {
      return MoorVar(MoorSym((variant as fbs.VarSym).symbol?.value ?? ''));
    } else {
      return moorNoneVar;
    }
  }

  /// Convenience factory to decode a standalone FlatBuffer byte list.
  factory MoorVar.fromBytes(List<int> bytes) {
    return MoorVar.fromFlatBuffer(fbs.Var(bytes));
  }

  // Strict accessors (non-coercive, returns null if type doesn't match)
  int? asInt() => value is int ? value as int : null;
  double? asFloat() => value is double ? value as double : null;
  bool? asBool() => value is bool ? value as bool : null;
  String? asString() => value is String ? value as String : null;
  MoorObj? asObj() => value is MoorObj ? value as MoorObj : null;
  MoorList? asList() => value is MoorList ? value as MoorList : null;
  MoorMap? asMap() => value is MoorMap ? value as MoorMap : null;
  MoorSym? asSym() => value is MoorSym ? value as MoorSym : null;
  MoorErr? asErr() => value is MoorErr ? value as MoorErr : null;

  bool isNone() => value is MoorNone;

  /// Returns a string representation suitable for use as a Map key.
  /// If it's a Symbol, returns its name. If it's a String, returns the string.
  /// Otherwise returns toLiteral().
  String toKey() {
    final v = value;
    if (v is String) return v;
    if (v is MoorSym) return v.name;
    return toLiteral();
  }

  /// Returns true if this value evaluates to true in MOO conditions.
  bool get isTruthy {
    final v = value;
    if (v is MoorNone) return false;
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is double) return v != 0.0;
    if (v is String) return v.isNotEmpty;
    if (v is MoorObj) return v.isTruthy;
    if (v is MoorList) return v.elements.isNotEmpty;
    if (v is MoorMap) return v.pairs.isNotEmpty;
    if (v is MoorSym) return true;
    if (v is MoorErr) return false;
    return true;
  }

  /// Human-readable representation (MOO literal syntax).
  String toLiteral() {
    final v = value;
    if (v is MoorNone) return 'none';
    if (v is bool) return v ? 'true' : 'false';
    if (v is int) return v.toString();
    if (v is double) return v.toString();
    if (v is String) {
      return '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    }
    if (v is MoorObj) return v.toLiteral();
    if (v is MoorSym) return v.toLiteral();
    if (v is MoorList) return v.toLiteral();
    if (v is MoorMap) return v.toLiteral();
    if (v is MoorErr) return v.toLiteral();
    return v.toString();
  }

  /// Serializes this value into a FlatBufferBuilder offset.
  int pack(fb.Builder builder) => toVarBuilder().getOrCreateOffset(builder);

  /// Serializes this value into a FlatBuffer VarObjectBuilder.
  fbs.VarObjectBuilder toVarBuilder() {
    final v = value;
    if (v is MoorNone) {
      return fbs.VarObjectBuilder(
        variantType: fbs.VarUnionTypeId.VarNone,
        variant: fbs.VarNoneObjectBuilder(),
      );
    }
    if (v is bool) {
      return fbs.VarObjectBuilder(
        variantType: fbs.VarUnionTypeId.VarBool,
        variant: fbs.VarBoolObjectBuilder(value: v),
      );
    }
    if (v is int) {
      return fbs.VarObjectBuilder(
        variantType: fbs.VarUnionTypeId.VarInt,
        variant: fbs.VarIntObjectBuilder(value: v),
      );
    }
    if (v is double) {
      return fbs.VarObjectBuilder(
        variantType: fbs.VarUnionTypeId.VarFloat,
        variant: fbs.VarFloatObjectBuilder(value: v),
      );
    }
    if (v is String) {
      return fbs.VarObjectBuilder(
        variantType: fbs.VarUnionTypeId.VarStr,
        variant: fbs.VarStrObjectBuilder(value: v),
      );
    }
    if (v is MoorObj) {
      return v.toVarBuilder();
    }
    if (v is MoorSym) {
      return v.toVarBuilder();
    }
    if (v is MoorList) {
      return v.toVarBuilder();
    }
    if (v is MoorMap) {
      return v.toVarBuilder();
    }
    if (v is MoorErr) {
      return v.toVarBuilder();
    }

    // Default to none if unknown
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarNone,
      variant: fbs.VarNoneObjectBuilder(),
    );
  }

  /// Convenience method to serialize this variable to a standalone FlatBuffer.
  List<int> toBytes() => toVarBuilder().toBytes();

  /// Comparison logic mirroring Rust's `Var::cmp_slow`.
  int compareTo(MoorVar other) {
    final v1 = value;
    final v2 = other.value;

    if (v1 == v2) return 0;

    // Handle cross-type numeric comparison (int vs double)
    if (v1 is num && v2 is num) {
      return v1.toDouble().compareTo(v2.toDouble());
    }

    final t1 = _typeOrder();
    final t2 = other._typeOrder();
    if (t1 != t2) return t1.compareTo(t2);

    // Same types, handle specific logic
    if (v1 is String && v2 is String) {
      return v1.toLowerCase().compareTo(v2.toLowerCase());
    }
    if (v1 is MoorObj && v2 is MoorObj) return v1.compareTo(v2);
    if (v1 is MoorSym && v2 is MoorSym) return v1.compareTo(v2);
    if (v1 is MoorList && v2 is MoorList) return v1.compareTo(v2);
    if (v1 is MoorMap && v2 is MoorMap) return v1.compareTo(v2);
    if (v1 is MoorErr && v2 is MoorErr) return v1.compareTo(v2);

    if (v1 is Comparable && v2 is Comparable) return v1.compareTo(v2);

    return 0;
  }

  int _typeOrder() {
    final v = value;
    if (v is MoorNone) return 0;
    if (v is bool) return 1;
    if (v is int) return 2;
    if (v is double) return 3;
    if (v is MoorObj) return 4;
    if (v is String) return 5;
    if (v is MoorSym) return 6;
    if (v is MoorErr) return 7;
    if (v is MoorList) return 8;
    if (v is MoorMap) return 9;
    return 10;
  }
}
