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

import 'package:flutter/foundation.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/room_snapshot.dart';

sealed class DockItem {
  String get id;
  String get target;
}

class PresentationModel implements DockItem {
  @override
  final String id;
  @override
  final String target;
  final String contentType;
  final String content;
  final Map<String, String> attrs;

  const PresentationModel({
    required this.id,
    required this.target,
    required this.contentType,
    required this.content,
    required this.attrs,
  });
}

class RoomSnapshotDockItem implements DockItem {
  @override
  final String id;
  @override
  final String target;
  final Map<String, String> attrs;
  final RoomSnapshot snapshot;

  const RoomSnapshotDockItem({
    required this.id,
    required this.target,
    required this.attrs,
    required this.snapshot,
  });
}

String normalizeDockTarget(String target) {
  final t = target.trim().toLowerCase();
  switch (t) {
    case 'tools':
    case 'inventory':
      return 'right';
    default:
      return t;
  }
}

PresentationModel? presentationFromFb(moor_common.Presentation? p) {
  if (p == null) return null;
  final id = p.id?.trim();
  if (id == null || id.isEmpty) return null;

  final attrs = <String, String>{};
  final a = p.attributes;
  if (a != null) {
    for (final el in a) {
      final k = el.key?.trim();
      final v = el.value?.trim();
      if (k == null || k.isEmpty || v == null) continue;
      attrs[k] = v;
    }
  }

  return PresentationModel(
    id: id,
    target: normalizeDockTarget(p.target ?? ''),
    contentType: (p.contentType ?? 'text/plain').trim(),
    content: p.content ?? '',
    attrs: attrs,
  );
}

String? extractRoomLookKey(List<Object?> candidates) {
  for (final c in candidates) {
    final k = objectRefToCurie(c);
    if (k != null) return k;
  }
  return null;
}

String? getRoomLookKeyFromDockItem(DockItem p) {
  if (p is RoomSnapshotDockItem) {
    return p.snapshot.room?.curie;
  }
  if (p is PresentationModel) {
    final kind = (p.attrs['kind'] ?? '').toLowerCase();
    if (kind != 'room_look' && kind != 'room-look') return null;
    return extractRoomLookKey([
      p.attrs['room'],
      p.attrs['object'],
      p.attrs['target'],
      p.attrs['dobj'],
      p.attrs['this_obj'],
      p.attrs['this'],
    ]);
  }
  return null;
}

String? getRoomLookKeyFromNarrative({
  required String? presentationHint,
  required Map<String, Object?>? eventMetadata,
}) {
  if (presentationHint != 'inset') return null;
  if (eventMetadata == null) return null;
  final verb = eventMetadata['verb'];
  if (verb is! String || verb != 'look') return null;
  return extractRoomLookKey([
    eventMetadata['lookRoom'],
    eventMetadata['look_room'],
    eventMetadata['dobj'],
    eventMetadata['thisObj'],
    eventMetadata['this_obj'],
  ]);
}

class PresentationStore extends ChangeNotifier {
  final Map<String, DockItem> _byId = <String, DockItem>{};

  Map<String, DockItem> snapshot() => Map.unmodifiable(_byId);

  List<DockItem> byTarget(String target) {
    final out = <DockItem>[];
    for (final p in _byId.values) {
      if (p.target == target) {
        out.add(p);
      }
    }
    return out;
  }

  void upsert(DockItem p) {
    final existing = _byId[p.id];
    if (existing != null && _sameDockItem(existing, p)) {
      return;
    }
    _byId[p.id] = p;
    notifyListeners();
  }

  void remove(String id) {
    if (_byId.remove(id) != null) {
      notifyListeners();
    }
  }

  void clear() {
    if (_byId.isEmpty) return;
    _byId.clear();
    notifyListeners();
  }

  bool _sameDockItem(DockItem a, DockItem b) {
    if (a.runtimeType != b.runtimeType ||
        a.id != b.id ||
        a.target != b.target) {
      return false;
    }

    if (a is PresentationModel && b is PresentationModel) {
      return a.contentType == b.contentType &&
          a.content == b.content &&
          mapEquals(a.attrs, b.attrs);
    }

    if (a is RoomSnapshotDockItem && b is RoomSnapshotDockItem) {
      return mapEquals(a.attrs, b.attrs) &&
          _sameRoomSnapshot(a.snapshot, b.snapshot);
    }

    return false;
  }

  bool _sameRoomSnapshot(RoomSnapshot a, RoomSnapshot b) {
    return a.title == b.title &&
        a.description == b.description &&
        a.room == b.room &&
        listEquals(a.exits, b.exits) &&
        listEquals(
          a.actions.map((it) => '${it.label}\u0000${it.command}').toList(),
          b.actions.map((it) => '${it.label}\u0000${it.command}').toList(),
        ) &&
        listEquals(
          a.things.map((it) => '${it.name}\u0000${it.object}').toList(),
          b.things.map((it) => '${it.name}\u0000${it.object}').toList(),
        ) &&
        listEquals(
          a.actors
              .map((it) => '${it.name}\u0000${it.status}\u0000${it.object}')
              .toList(),
          b.actors
              .map((it) => '${it.name}\u0000${it.status}\u0000${it.object}')
              .toList(),
        );
  }
}
