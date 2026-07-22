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

import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';

class NarrativeTracker {
  final Set<String> _seenEventIds = <String>{};
  final Set<String> _seenDedupKeys = <String>{};
  final Map<String, String> _latestLookMessageIdByRoom = <String, String>{};

  bool contains(NarrativeItem item) {
    final eventId = eventIdOf(item);
    final dedupKey = dedupKeyOf(item);
    return (eventId != null && _seenEventIds.contains(eventId)) ||
        (dedupKey != null && _seenDedupKeys.contains(dedupKey));
  }

  void remember(NarrativeItem item) {
    final eventId = eventIdOf(item);
    if (eventId != null) {
      _seenEventIds.add(eventId);
    }

    final dedupKey = dedupKeyOf(item);
    if (dedupKey != null) {
      _seenDedupKeys.add(dedupKey);
    }

    final roomKey = getRoomLookKeyFromNarrative(
      presentationHint: item.presentationHint,
      eventMetadata: item.metadata?.raw,
    );
    if (roomKey != null) {
      _latestLookMessageIdByRoom[roomKey] = item.id;
    }
  }

  bool batchContains({
    required NarrativeItem item,
    required Set<String> batchEventIds,
    required Set<String> batchDedupKeys,
  }) {
    final eventId = eventIdOf(item);
    final dedupKey = dedupKeyOf(item);
    return (eventId != null &&
            (_seenEventIds.contains(eventId) ||
                batchEventIds.contains(eventId))) ||
        (dedupKey != null &&
            (_seenDedupKeys.contains(dedupKey) ||
                batchDedupKeys.contains(dedupKey)));
  }

  void rememberBatch(
    NarrativeItem item, {
    required Set<String> batchEventIds,
    required Set<String> batchDedupKeys,
  }) {
    final eventId = eventIdOf(item);
    if (eventId != null) {
      batchEventIds.add(eventId);
    }

    final dedupKey = dedupKeyOf(item);
    if (dedupKey != null) {
      batchDedupKeys.add(dedupKey);
    }
  }

  String? latestLookMessageIdForRoom(String roomKey) {
    return _latestLookMessageIdByRoom[roomKey];
  }

  String? eventIdOf(NarrativeItem item) {
    return item.metadata?.eventId ??
        item.metadata?.text(const ['eventId', 'event_id']);
  }

  String? dedupKeyOf(NarrativeItem item) {
    final correlation = item.metadata?.text(
      const ['correlationId', 'correlation_id', 'deliveryId', 'delivery_id'],
    );
    if (correlation != null) {
      return 'corr:$correlation';
    }

    final eventId = eventIdOf(item);
    if (eventId != null) {
      return 'event:$eventId';
    }

    return null;
  }
}
