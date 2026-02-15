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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meta/meta.dart';

@immutable
sealed class MoorObj {
  const MoorObj();

  /// Create a MoorObj from a VarObj FlatBuffer definition.
  factory MoorObj.fromFlatBuffer(fbs.VarObj obj) {
    return tryFromFlatBuffer(obj) ?? const MoorObjId(-1);
  }

  /// Try to create a MoorObj from a VarObj FlatBuffer definition.
  static MoorObj? tryFromFlatBuffer(fbs.VarObj obj) {
    final inner = obj.obj;
    if (inner == null) return null;
    return tryFromObjFlatBuffer(inner);
  }

  /// Create a MoorObj from a raw Obj FlatBuffer definition.
  factory MoorObj.fromObjFlatBuffer(common.Obj inner) {
    return tryFromObjFlatBuffer(inner) ?? const MoorObjId(-1);
  }

  /// Try to create a MoorObj from a raw Obj FlatBuffer definition.
  static MoorObj? tryFromObjFlatBuffer(common.Obj inner) {
    final typeVal = inner.objType?.value;
    if (typeVal == common.ObjUnionTypeId.ObjId.value) {
      return MoorObjId((inner.obj as common.ObjId).id);
    } else if (typeVal == common.ObjUnionTypeId.UuObjId.value) {
      return MoorUuObjId(
        BigInt.from((inner.obj as common.UuObjId).packedValue),
      );
    } else if (typeVal == common.ObjUnionTypeId.AnonymousObjId.value) {
      return MoorAnonymousObjId(
        BigInt.from((inner.obj as common.AnonymousObjId).packedValue),
      );
    } else {
      return null;
    }
  }

  static MoorObj? parse(String s) {
    final raw = s.trim().toLowerCase();
    if (raw.isEmpty) return null;

    if (raw.startsWith('oid:')) {
      final id = int.tryParse(raw.substring(4));
      return id != null ? MoorObjId(id) : null;
    }

    if (raw.startsWith('uuid:')) {
      final parts = raw.substring(5).split('-');
      if (parts.length != 2) return null;
      try {
        final firstGroup = BigInt.parse(parts[0], radix: 16);
        final epochMs = BigInt.parse(parts[1], radix: 16);
        final autoincrement = (firstGroup >> 6) & BigInt.from(0xFFFF);
        final rng = firstGroup & BigInt.from(0x3F);

        // Pack: [autoincrement (16)] [rng (6)] [epoch_ms (40)]
        final packed =
            (autoincrement << 46) |
            (rng << 40) |
            (epochMs & BigInt.from(0xFFFFFFFFFF));
        return MoorUuObjId(packed);
      } on Object {
        return null;
      }
    }

    if (raw.startsWith('anonymous:')) {
      final val = BigInt.tryParse(raw.substring(10));
      return val != null ? MoorAnonymousObjId(val) : null;
    }

    // Legacy/heuristic parsing
    if (raw.startsWith('#')) {
      final stripped = raw.substring(1);
      if (stripped.contains('-')) {
        // Try parsing as uuid if it has a dash after #
        return parse('uuid:$stripped');
      }
      final n = int.tryParse(stripped);
      if (n != null) return MoorObjId(n);
    }

    final n = int.tryParse(raw);
    if (n != null) return MoorObjId(n);

    return null;
  }

  bool get isTruthy;
  String toLiteral();
  String toCurie();

  int pack(fb.Builder builder) => toVarBuilder().getOrCreateOffset(builder);

  fbs.VarObjectBuilder toVarBuilder() {
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarObj,
      variant: fbs.VarObjObjectBuilder(obj: toObjBuilder()),
    );
  }

  MoorVar toVar() => MoorVar(this);

  common.ObjObjectBuilder toObjBuilder();

  int compareTo(MoorObj other);
}

@immutable
class MoorObjId extends MoorObj {
  final int id;

  const MoorObjId(this.id);

  @override
  bool get isTruthy => id >= 0;

  @override
  String toLiteral() => '#$id';

  @override
  String toCurie() => 'oid:$id';

  @override
  common.ObjObjectBuilder toObjBuilder() {
    return common.ObjObjectBuilder(
      objType: common.ObjUnionTypeId.ObjId,
      obj: common.ObjIdObjectBuilder(id: id),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorObjId && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MoorObjId($id)';

  @override
  int compareTo(MoorObj other) {
    if (other is! MoorObjId) return -1;
    return id.compareTo(other.id);
  }
}

@immutable
class MoorUuObjId extends MoorObj {
  final BigInt packedValue;

  const MoorUuObjId(this.packedValue);

  @override
  bool get isTruthy => true;

  @override
  String toLiteral() => '#${_formatUuid()}';

  @override
  String toCurie() => 'uuid:${_formatUuid()}';

  String _formatUuid() {
    // 62-bit packed: [autoincrement (16)] [rng (6)] [epoch_ms (40)]
    final autoincrement = (packedValue >> 46) & BigInt.from(0xFFFF);
    final rng = (packedValue >> 40) & BigInt.from(0x3F);
    final epochMs = packedValue & BigInt.from(0xFFFFFFFFFF);

    final firstGroup = ((autoincrement << 6) | rng)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(6, '0');
    final secondGroup = epochMs
        .toRadixString(16)
        .toUpperCase()
        .padLeft(10, '0');
    return '$firstGroup-$secondGroup';
  }

  @override
  common.ObjObjectBuilder toObjBuilder() {
    return common.ObjObjectBuilder(
      objType: common.ObjUnionTypeId.UuObjId,
      // Use toSigned(64).toInt() to safely get a 64-bit integer bit-pattern for the wire.
      obj: common.UuObjIdObjectBuilder(
        packedValue: packedValue.toSigned(64).toInt(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorUuObjId &&
          runtimeType == other.runtimeType &&
          packedValue == other.packedValue;

  @override
  int get hashCode => packedValue.hashCode;

  @override
  String toString() => 'MoorUuObjId($packedValue)';

  @override
  int compareTo(MoorObj other) {
    if (other is MoorObjId) return 1;
    if (other is! MoorUuObjId) return -1;
    return packedValue.compareTo(other.packedValue);
  }
}

@immutable
class MoorAnonymousObjId extends MoorObj {
  final BigInt packedValue;

  const MoorAnonymousObjId(this.packedValue);

  @override
  bool get isTruthy => true;

  @override
  String toLiteral() => '*anonymous*';

  @override
  String toCurie() => 'anonymous:$packedValue';

  @override
  common.ObjObjectBuilder toObjBuilder() {
    return common.ObjObjectBuilder(
      objType: common.ObjUnionTypeId.AnonymousObjId,
      obj: common.AnonymousObjIdObjectBuilder(
        packedValue: packedValue.toInt(),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorAnonymousObjId &&
          runtimeType == other.runtimeType &&
          packedValue == other.packedValue;

  @override
  int get hashCode => packedValue.hashCode;

  @override
  String toString() => 'MoorAnonymousObjId($packedValue)';

  @override
  int compareTo(MoorObj other) {
    if (other is MoorObjId || other is MoorUuObjId) return 1;
    if (other is! MoorAnonymousObjId) return 0;
    return packedValue.compareTo(other.packedValue);
  }
}
