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
import 'package:meadow_flutter/moor/debug_panel_controller.dart';
import 'package:meadow_flutter/moor/presentations.dart';

void main() {
  test('DebugPanelController toggles panel presentation and appends lines', () {
    final store = PresentationStore();
    addTearDown(store.dispose);
    final controller = DebugPanelController(
      now: () => DateTime.parse('2026-03-07T12:00:00Z'),
    );
    addTearDown(controller.dispose);

    controller
      ..toggle(store)
      ..appendLine('hello', store);

    expect(controller.visible, isTrue);
    final side = store.byTarget('right');
    expect(side, hasLength(1));
    expect((side.first as PresentationModel).content, contains('hello'));

    controller.hide(store);

    expect(controller.visible, isFalse);
    expect(store.byTarget('right'), isEmpty);
  });
}
