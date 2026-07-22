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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';
import 'package:meadow_flutter/widgets/session_command_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionCommandController', () {
    test('consumeCommandsToSend prefixes verb pill and clears input state', () {
      final controller = SessionCommandController();
      addTearDown(controller.dispose);

      controller.selectPaletteVerb(
        const PaletteVerb(
          verb: 'look',
          label: 'Look',
          placeholder: 'What would you like to look at?',
        ),
      );
      controller.inputController.text =
          '${controller.inputController.text}self';

      final commands = controller.consumeCommandsToSend();

      expect(commands, equals(const <String>['look self']));
      expect(controller.verbPill, isNull);
      expect(controller.verbPillPlaceholder, isNull);
      expect(controller.inputController.commandText, isEmpty);
    });

    test('history navigation restores buffered draft text', () {
      final controller = SessionCommandController();
      addTearDown(controller.dispose);

      controller.inputController.text = 'look self';
      controller.consumeCommandsToSend();
      controller.inputController.text = 'say hello';
      controller.consumeCommandsToSend();
      controller.inputController.text = 'partial draft';

      controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowUp,
          physicalKey: PhysicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
        onSend: () {},
      );
      expect(controller.inputController.commandText, equals('say hello'));

      controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowUp,
          physicalKey: PhysicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
        onSend: () {},
      );
      expect(controller.inputController.commandText, equals('look self'));

      controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowDown,
          physicalKey: PhysicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
        onSend: () {},
      );
      expect(controller.inputController.commandText, equals('say hello'));

      controller.handleKeyEvent(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.arrowDown,
          physicalKey: PhysicalKeyboardKey.arrowDown,
          timeStamp: Duration.zero,
        ),
        onSend: () {},
      );
      expect(controller.inputController.commandText, equals('partial draft'));
    });

    test('promoteLeadingTokenToPill uses best matching suggestion', () {
      final controller = SessionCommandController(
        initialPaletteVerbs: const <PaletteVerb>[
          PaletteVerb(
            verb: 'examine',
            label: 'Exam',
            placeholder: 'What would you like to examine?',
          ),
        ],
      );
      addTearDown(controller.dispose);
      controller.inputController.text = 'exa';

      final promoted = controller.promoteLeadingTokenToPill();

      expect(promoted, isTrue);
      expect(controller.verbPill, equals('examine'));
      expect(controller.inputController.commandText, isEmpty);
    });
  });
}
