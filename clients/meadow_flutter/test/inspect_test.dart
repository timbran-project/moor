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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/inspect_controller.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
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

  test('buildInspectInvokeArgs encodes object refs as object vars', () {
    final bytes = buildInspectInvokeArgs(const <String>['oid:1', 'hello']);

    expect(bytes, isNotNull);
    final decoded = MoorVar.fromBytes(bytes!);
    final list = decoded.asList();
    expect(list, isNotNull);
    expect(list!.elements.length, equals(2));
    expect(list.elements.first.asObj(), equals(const MoorObjId(1)));
    expect(list.elements.last.asString(), equals('hello'));
  });

  test('mapInspectPanelTarget normalizes side lanes to top', () {
    expect(mapInspectPanelTarget('right'), equals('right'));
    expect(mapInspectPanelTarget('inventory'), equals('top'));
    expect(mapInspectPanelTarget(null), equals('top'));
  });

  test(
    'InspectController returns panel presentation for panel-mode output',
    () async {
      final controller = InspectController(
        invokeVerb:
            ({
              required String objectCurie,
              required String verbName,
              Uint8List? argsVarBytes,
            }) async {
              return const InspectVerbResponse(
                result: moorNoneVar,
                outputLines: <String>['opened'],
                eventTypes: <int>[1],
              );
            },
        newId: (prefix) => '${prefix}1',
      );

      final result = await controller.runAction(
        const InspectAction(
          label: 'Open',
          kind: null,
          command: null,
          verb: 'open',
          target: 'oid:1',
          args: <String>[],
          inputType: null,
          inputPrompt: null,
          inputPlaceholder: null,
          resultMode: 'panel',
          panelTarget: 'inventory',
          panelId: null,
          panelTitle: null,
        ),
        promptForInput: (_) async => null,
      );

      expect(result.canceled, isFalse);
      expect(result.commandToSend, isNull);
      expect(result.narrativeLines, isEmpty);
      expect(result.panelPresentation, isA<PresentationModel>());
      expect(result.panelPresentation!.target, equals('top'));
      expect(result.panelPresentation!.content, equals('opened'));
    },
  );
}
