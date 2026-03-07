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

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/link_preview.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

class NarrativeMetadata {
  final Map<String, Object?> raw;
  final String? eventId;
  final String? presentationHint;
  final String? groupId;
  final String? actorCurie;
  final String? actorName;
  final String? verb;
  final String? content;
  final NarrativeThumbnailData? thumbnail;
  final LinkPreviewData? linkPreview;

  const NarrativeMetadata({
    required this.raw,
    required this.eventId,
    required this.presentationHint,
    required this.groupId,
    required this.actorCurie,
    required this.actorName,
    required this.verb,
    required this.content,
    required this.thumbnail,
    required this.linkPreview,
  });

  Object? value(String key) => raw[key];

  String? text(List<String> keys) {
    for (final key in keys) {
      final t = _toMetadataText(raw[key]);
      if (t != null) return t;
    }
    return null;
  }
}

String? _toMetadataText(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
  if (value is MoorSym) {
    final t = value.name.trim();
    return t.isEmpty ? null : t;
  }
  if (value is bool || value is num) {
    return value.toString();
  }
  return null;
}

NarrativeMetadata parseNarrativeMetadata({
  required List<moor_common.EventMetadata>? metadataPairs,
  required String? eventId,
}) {
  final raw = <String, Object?>{};
  if (metadataPairs != null) {
    for (final m in metadataPairs) {
      final key = m.key?.value;
      final value = m.value;
      if (key == null || key.isEmpty || value == null) {
        continue;
      }
      raw[key] = MoorVar.fromFlatBuffer(value).value;
    }
  }
  if (eventId != null) {
    raw['eventId'] = eventId;
    raw['event_id'] = eventId;
  }

  String? textFor(List<String> keys) {
    for (final key in keys) {
      final t = _toMetadataText(raw[key]);
      if (t != null) return t;
    }
    return null;
  }

  String? actorNameFromRaw() {
    final direct =
        textFor(const ['actor_name', 'actorName']) ??
        textFor(const ['this_name', 'thisName']);
    if (direct != null) return direct;

    final actorVal = raw['actor'];
    if (actorVal == null) return null;
    final actor = MoorVar(actorVal).asMap();
    if (actor == null) return null;
    MoorVar? get(String k) =>
        actor.pairs[MoorVar(MoorSym(k))] ?? actor.pairs[MoorVar(k)];
    final name = get('name')?.coerceText();
    if (name != null && name.isNotEmpty) return name;
    return null;
  }

  String? curieFromValue(Object? value) {
    if (value == null) return null;

    final mv = MoorVar(value);
    final obj = mv.asObj();
    if (obj != null) return obj.toCurie();

    final map = mv.asMap();
    if (map != null) {
      MoorVar? get(String k) =>
          map.pairs[MoorVar(MoorSym(k))] ?? map.pairs[MoorVar(k)];

      final oidObj = get('oid')?.asObj();
      if (oidObj != null) return oidObj.toCurie();
      final oidInt = get('oid')?.asInt();
      if (oidInt != null) return 'oid:$oidInt';
      final uuid = get('uuid')?.asString();
      if (uuid != null && uuid.isNotEmpty) return 'uuid:$uuid';
    }

    if (value is int) return 'oid:$value';
    if (value is String) {
      final s = value.trim();
      if (s.startsWith('oid:') || s.startsWith('uuid:')) return s;
      if (s.startsWith('#')) {
        final n = int.tryParse(s.substring(1));
        if (n != null) return 'oid:$n';
      }
      final parsed = MoorObj.parse(s);
      if (parsed != null) return parsed.toCurie();
    }

    return null;
  }

  final actorCurie =
      curieFromValue(raw['actor']) ??
      curieFromValue(raw['this_obj']) ??
      curieFromValue(raw['thisObj']) ??
      curieFromValue(raw['dobj']) ??
      curieFromValue(raw['iobj']);

  final contentVal = raw['content'];
  final content = contentVal == null
      ? null
      : (_toMetadataText(contentVal) ?? MoorVar(contentVal).coerceText());
  final thumbnail =
      parseNarrativeThumbnailData(raw['thumbnail']) ??
      parseNarrativeThumbnailData(raw['image_thumbnail']);
  final linkPreview =
      parseLinkPreviewData(raw['link_preview']) ??
      parseLinkPreviewData(raw['linkPreview']);

  return NarrativeMetadata(
    raw: raw,
    eventId: eventId ?? textFor(const ['eventId', 'event_id']),
    presentationHint: textFor(const [
      'presentation_hint',
      'presentationHint',
    ])?.toLowerCase(),
    groupId: textFor(const ['group_id', 'groupId']),
    actorCurie: actorCurie,
    actorName: actorNameFromRaw(),
    verb: textFor(const ['verb']),
    content: (content?.isEmpty ?? true) ? null : content,
    thumbnail: thumbnail,
    linkPreview: linkPreview,
  );
}
