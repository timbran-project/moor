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

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_metadata.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

typedef HistoryDecryptor =
    Future<Uint8List> Function(Uint8List encryptedBlob, String identity);
typedef NarrativeIdGenerator = String Function(String prefix);

Future<List<NarrativeItem>> loadHistoricalNarrativeItems({
  required List<EncryptedHistoricalEvent> events,
  required String identity,
  required NarrativeTracker tracker,
  required HistoryDecryptor decryptEvent,
  required NarrativeIdGenerator newId,
}) async {
  final items = <NarrativeItem>[];
  final batchEventIds = <String>{};
  final batchDedupKeys = <String>{};

  for (final event in events) {
    final decrypted = await decryptEvent(event.encryptedBlob, identity);
    final parsed = parseHistoricalNarrativeEnvelope(decrypted, newId: newId);
    if (parsed == null) {
      continue;
    }
    final alreadySeen = tracker.batchContains(
      item: parsed,
      batchEventIds: batchEventIds,
      batchDedupKeys: batchDedupKeys,
    );
    if (alreadySeen) {
      continue;
    }
    tracker.rememberBatch(
      parsed,
      batchEventIds: batchEventIds,
      batchDedupKeys: batchDedupKeys,
    );
    items.add(parsed);
  }

  return items;
}

NarrativeItem? parseHistoricalNarrativeEnvelope(
  Uint8List bytes, {
  required NarrativeIdGenerator newId,
}) {
  final evt = moor_common.NarrativeEvent(bytes);
  final e = evt.event;
  if (e == null) {
    return null;
  }
  final eventId = _uuidBytesToHex(evt.eventId?.data);

  final timestamp = DateTime.fromMillisecondsSinceEpoch(
    (evt.timestamp / 1000000).toInt(),
    isUtc: true,
  ).toLocal();

  final eventType = e.eventType?.value ?? 0;
  if (eventType == moor_common.EventUnionTypeId.NotifyEvent.value) {
    final notify = e.event as moor_common.NotifyEvent?;
    if (notify == null || notify.value == null) {
      return null;
    }
    final moorValue = MoorVar.fromFlatBuffer(notify.value!);
    final lines = moorValue.asLines();
    if (lines.isEmpty) {
      return null;
    }
    final metadata = parseNarrativeMetadata(
      metadataPairs: notify.metadata,
      eventId: eventId,
    );
    return NarrativeItem(
      id: newId('h'),
      timestamp: timestamp,
      content: lines,
      contentType: normalizeContentType(notify.contentType?.value),
      noNewline: notify.noNewline,
      presentationHint: metadata.presentationHint,
      groupId: metadata.groupId,
      metadata: metadata,
    );
  }

  if (eventType == moor_common.EventUnionTypeId.PresentEvent.value) {
    final present = e.event as moor_common.PresentEvent?;
    final presentation = present?.presentation;
    if (presentation == null) {
      return null;
    }
    final content = presentation.content ?? '';
    if (content.isEmpty) {
      return null;
    }
    return NarrativeItem(
      id: newId('h'),
      timestamp: timestamp,
      content: <String>[content],
      contentType: normalizeContentType(presentation.contentType),
      noNewline: false,
      presentationHint: null,
      groupId: null,
      metadata: null,
    );
  }

  if (eventType == moor_common.EventUnionTypeId.TracebackEvent.value) {
    final traceback = e.event as moor_common.TracebackEvent?;
    final backtrace = traceback?.exception?.backtrace;
    if (backtrace == null) {
      return null;
    }
    final lines = <String>[];
    for (final entry in backtrace) {
      final parsed = MoorVar.fromFlatBuffer(entry).asLines();
      if (parsed.isNotEmpty) {
        lines.addAll(parsed);
      }
    }
    if (lines.isEmpty) {
      return null;
    }
    return NarrativeItem(
      id: newId('h'),
      timestamp: timestamp,
      content: <String>[lines.join('\n')],
      contentType: 'text/traceback',
      noNewline: false,
      presentationHint: null,
      groupId: null,
      metadata: null,
    );
  }

  return null;
}

String? _uuidBytesToHex(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
