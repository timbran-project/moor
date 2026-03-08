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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/history_loader.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

typedef HistoryExportDecryptor =
    Future<Uint8List> Function(Uint8List encryptedBlob, String identity);
typedef HistoryExportSaver =
    Future<void> Function({
      required String suggestedName,
      required Uint8List bytes,
    });
typedef HistoryExportLogger = void Function(String message);

class HistoryExportController extends ChangeNotifier {
  bool _exporting = false;
  int _processed = 0;
  int? _total;

  bool get exporting => _exporting;
  int get processed => _processed;
  int? get total => _total;

  Future<void> exportAll({
    required MoorHttpApi api,
    required String authToken,
    required String ageIdentity,
    required String systemTitle,
    required String playerOid,
    required HistoryExportDecryptor decryptEvent,
    required HistoryExportSaver saveFile,
    required HistoryExportLogger onStatus,
  }) async {
    if (_exporting) {
      return;
    }
    _exporting = true;
    _processed = 0;
    _total = null;
    notifyListeners();

    try {
      final startedAt = DateTime.now();
      final encrypted = await _fetchAllHistory(
        api: api,
        authToken: authToken,
        identity: ageIdentity,
        decryptEvent: decryptEvent,
      );
      _total = encrypted.length;
      notifyListeners();

      final events = <Map<String, Object?>>[];
      for (var i = 0; i < encrypted.length; i++) {
        try {
          final decrypted = await decryptEvent(
            encrypted[i].encryptedBlob,
            ageIdentity,
          );
          final json = historicalEventToJson(decrypted);
          if (json != null) {
            events.add(json);
          }
        } on Object catch (e) {
          onStatus('History export: skipping unreadable event: $e');
        }
        _processed = i + 1;
        notifyListeners();
      }

      final finishedAt = DateTime.now();
      final oldestEvent = events.isEmpty ? null : events.last['timestamp'];
      final newestEvent = events.isEmpty ? null : events.first['timestamp'];
      final payload = <String, Object?>{
        'export_version': '1.0',
        'export_date': finishedAt.toUtc().toIso8601String(),
        'system_title': systemTitle,
        'player_oid': playerOid,
        'event_count': events.length,
        'time_range': <String, Object?>{
          'oldest_event': oldestEvent,
          'newest_event': newestEvent,
          'export_duration_ms': finishedAt.difference(startedAt).inMilliseconds,
        },
        'events': events,
      };
      final suggestedName = _suggestFilename(systemTitle, finishedAt);
      await saveFile(
        suggestedName: suggestedName,
        bytes: Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert(payload),
          ),
        ),
      );
      onStatus('History export saved as $suggestedName');
    } on Object catch (e) {
      onStatus('History export failed: $e');
    } finally {
      _exporting = false;
      notifyListeners();
    }
  }

  Future<List<EncryptedHistoricalEvent>> _fetchAllHistory({
    required MoorHttpApi api,
    required String authToken,
    required String identity,
    required HistoryExportDecryptor decryptEvent,
  }) async {
    final events = <EncryptedHistoricalEvent>[];
    final seenEventIds = <String>{};
    String? untilEvent;

    while (true) {
      final batch = await api.fetchHistory(
        authToken: authToken,
        sinceSeconds: untilEvent == null ? 315360000 : null,
        untilEvent: untilEvent,
        limit: 1000,
      );
      if (batch.isEmpty) {
        break;
      }

      String? oldestEventId;
      for (var i = 0; i < batch.length; i++) {
        final item = batch[i];
        try {
          final decrypted = await decryptEvent(item.encryptedBlob, identity);
          final parsed = parseHistoricalNarrativeEnvelope(
            decrypted,
            newId: (_) => 'export',
          );
          final eventId =
              parsed?.metadata?.eventId ?? _eventIdFromEnvelope(decrypted);
          if (i == 0 && eventId != null) {
            oldestEventId = eventId;
          }
          if (eventId == null || seenEventIds.add(eventId)) {
            events.add(item);
          }
        } on Object {
          events.add(item);
        }
      }

      if (batch.length < 1000 || oldestEventId == null) {
        break;
      }
      untilEvent = oldestEventId;
    }

    return events;
  }

  String _suggestFilename(String systemTitle, DateTime timestamp) {
    final slug = systemTitle
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'(^-+|-+$)'), '');
    final base = slug.isEmpty ? 'moor' : slug;
    final day = timestamp.toUtc().toIso8601String().split('T').first;
    return '$base-history-$day.json';
  }
}

Map<String, Object?>? historicalEventToJson(Uint8List bytes) {
  final envelope = moor_common.NarrativeEvent(bytes);
  final event = envelope.event;
  if (event == null) {
    return null;
  }

  final timestampMs = (envelope.timestamp / 1000000).toInt();
  final result = <String, Object?>{
    'event_id': _uuidBytesToHex(envelope.eventId?.data),
    'timestamp': DateTime.fromMillisecondsSinceEpoch(
      timestampMs,
      isUtc: true,
    ).toIso8601String(),
    'timestamp_ms': timestampMs,
  };

  final author = envelope.author;
  final authorCurie = author == null
      ? null
      : MoorVar.fromFlatBuffer(author).asObj()?.toCurie();
  if (authorCurie != null) {
    result['author_oid'] = authorCurie;
  }

  final eventType = event.eventType?.value ?? 0;
  if (eventType == moor_common.EventUnionTypeId.NotifyEvent.value) {
    final notify = event.event as moor_common.NotifyEvent?;
    final value = notify?.value;
    if (value == null) {
      return null;
    }
    result['type'] = 'notify';
    result['content'] = MoorVar.fromFlatBuffer(value).asLines();
    result['content_type'] = notify?.contentType ?? 'text/plain';
    result['no_newline'] = notify?.noNewline ?? false;
    return result;
  }

  if (eventType == moor_common.EventUnionTypeId.TracebackEvent.value) {
    final traceback = event.event as moor_common.TracebackEvent?;
    final backtrace = traceback?.exception?.backtrace ?? const [];
    result['type'] = 'traceback';
    result['backtrace'] = backtrace
        .map((entry) => MoorVar.fromFlatBuffer(entry).coerceText())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    return result;
  }

  if (eventType == moor_common.EventUnionTypeId.PresentEvent.value) {
    final present = event.event as moor_common.PresentEvent?;
    final presentation = presentationFromFb(present?.presentation);
    result['type'] = 'present';
    result['presentation'] = presentation == null
        ? null
        : <String, Object?>{
            'id': presentation.id,
            'target': presentation.target,
            'content_type': presentation.contentType,
            'content': presentation.content,
            'attrs': presentation.attrs,
          };
    return result;
  }

  if (eventType == moor_common.EventUnionTypeId.UnpresentEvent.value) {
    final unpresent = event.event as moor_common.UnpresentEvent?;
    result['type'] = 'unpresent';
    result['presentation_id'] = unpresent?.presentationId;
    return result;
  }

  result['type'] = 'unknown';
  return result;
}

String? _eventIdFromEnvelope(Uint8List bytes) {
  final envelope = moor_common.NarrativeEvent(bytes);
  return _uuidBytesToHex(envelope.eventId?.data);
}

String? _uuidBytesToHex(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
