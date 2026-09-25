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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart' as fbs;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart'
    as moor_var;
import 'package:meadow_flutter/moor/history_loader.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';

void main() {
  test(
    'loads narrative, drops duplicate, failed decryption, and MCP spool',
    () async {
      final tracker = NarrativeTracker();
      final messages = <String>[
        'welcome',
        'welcome',
        r'#$# edit #1:look',
        'secret edit body',
        '.',
        'after spool',
      ];
      final events = <EncryptedHistoricalEvent>[
        for (var i = 0; i < messages.length; i++)
          EncryptedHistoricalEvent(
            encryptedBlob: _notifyBytes(messages[i], i == 1 ? 0 : i),
            isHistorical: true,
          ),
        EncryptedHistoricalEvent(
          encryptedBlob: Uint8List.fromList([255]),
          isHistorical: true,
        ),
      ];
      var ids = 0;
      final items = await loadHistoricalNarrativeItems(
        events: events,
        identity: 'identity',
        tracker: tracker,
        decryptEvent: (blob, identity) async {
          expect(identity, 'identity');
          if (blob.length == 1) {
            throw StateError('cannot decrypt');
          }
          return blob;
        },
        newId: (_) => 'h${++ids}',
      );

      expect(items.map((item) => item.content.join()), [
        'welcome',
        'after spool',
      ]);
      expect(items.map((item) => item.id), ['h1', 'h6']);
    },
  );

  test(
    'loadHistoricalNarrativeItems returns empty list for empty history',
    () async {
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
    },
  );
}

Uint8List _notifyBytes(String text, int eventId) {
  return fbs.NarrativeEventObjectBuilder(
    eventId: fbs.UuidObjectBuilder(data: [...List<int>.filled(15, 0), eventId]),
    timestamp: 1000000000,
    event: fbs.EventObjectBuilder(
      eventType: fbs.EventUnionTypeId.NotifyEvent,
      event: fbs.NotifyEventObjectBuilder(
        value: moor_var.VarObjectBuilder(
          variantType: moor_var.VarUnionTypeId.VarStr,
          variant: moor_var.VarStrObjectBuilder(value: text),
        ),
      ),
    ),
  ).toBytes();
}
