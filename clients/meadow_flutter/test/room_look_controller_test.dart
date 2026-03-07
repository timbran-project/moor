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
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/room_look_controller.dart';

void main() {
  test('RoomLookController tracks current room-look presentation key', () {
    final store = PresentationStore();
    addTearDown(store.dispose);
    final controller = RoomLookController();
    addTearDown(controller.dispose);

    store.upsert(
      const PresentationModel(
        id: 'room-look',
        target: 'top',
        contentType: 'text/plain',
        content: 'room',
        attrs: <String, String>{
          'kind': 'room_look',
          'room': 'oid:42',
        },
      ),
    );

    controller.handlePresentationsChanged(store, roomHudEnabled: true);

    expect(controller.currentRoomLookKey, equals('oid:42'));
    expect(
      controller.suppressedRoomKey(roomHudEnabled: true),
      equals('oid:42'),
    );
  });
}
