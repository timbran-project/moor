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
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

void main() {
  group('MoorVar', () {
    test('Round-trip scalars', () {
      final vars = [
        moorNoneVar,
        const MoorVar(true),
        const MoorVar(false),
        const MoorVar(42),
        const MoorVar(3.14),
        const MoorVar('hello world'),
      ];

      for (final v in vars) {
        final bytes = v.toBytes();
        final decoded = MoorVar.fromBytes(bytes);
        expect(decoded, equals(v));
        expect(decoded.value, equals(v.value));
      }
    });

    test('Round-trip MoorObj', () {
      final vars = [
        const MoorVar(MoorObjId(0)),
        const MoorVar(MoorObjId(-1)),
        MoorVar(MoorUuObjId(BigInt.from(123456789))),
      ];

      for (final v in vars) {
        final bytes = v.toBytes();
        final decoded = MoorVar.fromBytes(bytes);
        expect(decoded, equals(v));
      }
    });

    test('Round-trip MoorSym', () {
      const v = MoorVar(MoorSym('test_symbol'));
      final bytes = v.toBytes();
      final decoded = MoorVar.fromBytes(bytes);
      expect(decoded, equals(v));
      expect(decoded.asSym()?.name, equals('test_symbol'));
    });

    test('Round-trip MoorList', () {
      final v = MoorVar(
        MoorList(const [
          MoorVar(1),
          MoorVar('two'),
          MoorVar(MoorSym('three')),
        ]),
      );
      final bytes = v.toBytes();
      final decoded = MoorVar.fromBytes(bytes);
      expect(decoded, equals(v));
      expect(decoded.asList()?.elements.length, equals(3));
    });

    test('Round-trip MoorMap', () {
      final v = MoorVar(
        MoorMap({
          const MoorVar('a'): const MoorVar(1),
          const MoorVar(MoorSym('b')): const MoorVar('two'),
        }),
      );
      final bytes = v.toBytes();
      final decoded = MoorVar.fromBytes(bytes);
      expect(decoded, equals(v));
      expect(decoded.asMap()?.pairs.length, equals(2));
    });

    test('Truthiness', () {
      expect(moorNoneVar.isTruthy, isFalse);
      expect(const MoorVar(0).isTruthy, isFalse);
      expect(const MoorVar(1).isTruthy, isTrue);
      expect(const MoorVar('').isTruthy, isFalse);
      expect(const MoorVar('non-empty').isTruthy, isTrue);
      expect(MoorVar(MoorList(const [])).isTruthy, isFalse);
      expect(MoorVar(MoorList(const [MoorVar(1)])).isTruthy, isTrue);
    });

    test('ToLiteral', () {
      expect(moorNoneVar.toLiteral(), equals('none'));
      expect(const MoorVar(42).toLiteral(), equals('42'));
      expect(const MoorVar('hello').toLiteral(), equals('"hello"'));
      expect(const MoorVar(MoorSym('sym')).toLiteral(), equals(':sym'));
      expect(const MoorVar(MoorObjId(0)).toLiteral(), equals('#0'));
      expect(
        MoorVar(MoorList(const [MoorVar(1), MoorVar(2)])).toLiteral(),
        equals('{1, 2}'),
      );
    });

    test('Curie parsing', () {
      expect(MoorObj.parse('oid:123'), equals(const MoorObjId(123)));
      expect(MoorObj.parse('#123'), equals(const MoorObjId(123)));
      expect(MoorObj.parse('123'), equals(const MoorObjId(123)));

      const uuidCurie = 'uuid:048D05-1234567890';
      final parsedUuid = MoorObj.parse(uuidCurie);
      expect(parsedUuid, isA<MoorUuObjId>());
      expect(parsedUuid?.toCurie(), equals(uuidCurie));

      expect(
        MoorObj.parse('anonymous:12345'),
        equals(MoorAnonymousObjId(BigInt.from(12345))),
      );
    });

    test('toKey coercion', () {
      expect(const MoorVar('plain').toKey(), equals('plain'));
      expect(const MoorVar(MoorSym('symbol')).toKey(), equals('symbol'));
      expect(const MoorVar(42).toKey(), equals('42'));
    });

    test('Null tolerance', () {
      // Create a dummy Var with null variant manually
      final builder = fb.Builder()
        ..startTable(2)
        ..addUint8(0, fbs.VarUnionTypeId.VarInt.value);
      // Offset 1 (variant) is left as null
      final offset = builder.endTable();
      builder.finish(offset);
      final bytes = builder.buffer.sublist(
        builder.buffer.length - builder.offset,
      );

      // Should return moorNoneVar instead of crashing
      final decoded = MoorVar.fromBytes(bytes);
      expect(decoded.isNone(), isTrue);
    });
  });
}
