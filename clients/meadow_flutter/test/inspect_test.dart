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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

void main() {
  test('parseInspectData parses title/description/actions', () {
    final actionMap = MoorMap({
      const MoorVar(MoorSym('label')): const MoorVar('Wave'),
      const MoorVar(MoorSym('kind')): const MoorVar('command'),
      const MoorVar(MoorSym('command')): const MoorVar('wave'),
    });
    final root = MoorVar(
      MoorMap({
        const MoorVar(MoorSym('title')): const MoorVar('A person'),
        const MoorVar(MoorSym('description')): const MoorVar('Looks friendly'),
        const MoorVar(MoorSym('actions')): MoorVar(
          MoorList([
            MoorVar(actionMap),
          ]),
        ),
      }),
    );

    final parsed = parseInspectData(root);
    expect(parsed, isNotNull);
    expect(parsed!.title, equals('A person'));
    expect(parsed.description, equals('Looks friendly'));
    expect(parsed.actions.length, equals(1));
    expect(parsed.actions.first.label, equals('Wave'));
    expect(parsed.actions.first.command, equals('wave'));
    expect(parsed.actions.first.inputType, isNull);
  });
}
