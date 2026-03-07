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
import 'package:meadow_flutter/moor/history_loader.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';

void main() {
  test('loadHistoricalNarrativeItems returns empty list for empty history', () async {
    final tracker = NarrativeTracker();

    var ids = 0;
    final items = await loadHistoricalNarrativeItems(
      events: const [],
      identity: 'identity',
      tracker: tracker,
      decryptEvent: (encryptedBlob, _) async => encryptedBlob,
      newId: (_) => 'h${++ids}',
    );

    expect(items, isEmpty);
  });
}
