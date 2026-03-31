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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/session_view_controller.dart';

void main() {
  group('SessionViewController', () {
    test('builds current settings snapshot', () {
      final controller = SessionViewController();
      addTearDown(controller.dispose);

      final settings = controller.settings(
        verbSuggestionsAvailable: true,
        themeMode: ThemeMode.dark,
      );

      expect(settings.roomHudEnabled, isTrue);
      expect(settings.showNarrativeMeta, isFalse);
      expect(settings.verbPaletteEnabled, isTrue);
      expect(settings.monospaceNarrative, isFalse);
      expect(settings.verbSuggestionsAvailable, isTrue);
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('applySettings updates flags and notifies listeners once', () {
      final controller = SessionViewController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller
        ..addListener(() {
          notifications += 1;
        })
        ..applySettings(
          const SessionViewSettings(
            roomHudEnabled: false,
            showNarrativeMeta: true,
            verbPaletteEnabled: false,
            monospaceNarrative: true,
            echoCommands: true,
            verbSuggestionsAvailable: false,
            themeMode: ThemeMode.light,
          ),
        );

      expect(controller.roomHudEnabled, isFalse);
      expect(controller.showNarrativeMeta, isTrue);
      expect(controller.verbPaletteEnabled, isFalse);
      expect(controller.monospaceNarrative, isTrue);
      expect(notifications, equals(1));
    });
  });
}
