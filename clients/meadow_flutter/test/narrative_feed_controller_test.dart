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
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_feed_controller.dart';
import 'package:meadow_flutter/moor/narrative_metadata.dart';

void main() {
  group('NarrativeFeedController', () {
    test('appendItem ignores duplicate event ids', () {
      final controller = NarrativeFeedController();
      addTearDown(controller.dispose);
      final first = _item(
        id: 'a',
        text: 'one',
        eventId: 'evt-1',
      );
      final duplicate = _item(
        id: 'b',
        text: 'two',
        eventId: 'evt-1',
      );

      expect(controller.appendItem(first), isTrue);
      expect(controller.appendItem(duplicate), isFalse);
      expect(controller.items, hasLength(1));
    });

    test('prependHistoricalItems keeps only unseen items', () {
      final controller = NarrativeFeedController();
      addTearDown(controller.dispose);
      final existing = _item(
        id: 'live',
        text: 'live',
        eventId: 'evt-live',
      );
      controller.appendItem(existing);

      final added = controller.prependHistoricalItems(<NarrativeItem>[
        _item(id: 'old-1', text: 'old-1', eventId: 'evt-old-1'),
        _item(id: 'dup', text: 'dup', eventId: 'evt-live'),
        _item(id: 'old-2', text: 'old-2', eventId: 'evt-old-2'),
      ]);

      expect(added, equals(2));
      expect(controller.items.map((item) => item.id).toList(), <String>[
        'old-1',
        'old-2',
        'live',
      ]);
    });
  });
}

NarrativeItem _item({
  required String id,
  required String text,
  required String eventId,
}) {
  return NarrativeItem(
    id: id,
    timestamp: DateTime.parse('2026-03-07T12:00:00Z'),
    content: <String>[text],
    contentType: 'text/plain',
    noNewline: false,
    presentationHint: null,
    groupId: null,
    metadata: NarrativeMetadata(
      raw: <String, Object?>{'eventId': eventId},
      eventId: eventId,
      presentationHint: null,
      groupId: null,
      actorCurie: null,
      actorName: null,
      verb: null,
      content: null,
      thumbnail: null,
      linkPreview: null,
    ),
  );
}
