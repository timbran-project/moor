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

import 'package:meadow_flutter/moor/object_ref.dart';

String _coerceText(Object? value) {
  if (value == null) return '';
  if (value is String) return value.trim();
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    return value.map(_coerceText).where((s) => s.isNotEmpty).join(' ').trim();
  }
  return '';
}

Map<String, Object?>? _coerceMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    final out = <String, Object?>{};
    for (final e in value.entries) {
      final k = e.key;
      if (k is! String) continue;
      out[k] = e.value;
    }
    return out;
  }
  return null;
}

class RoomSnapshotActor {
  final String name;
  final String status;
  final ObjectRef object;

  const RoomSnapshotActor({
    required this.name,
    required this.status,
    required this.object,
  });
}

class RoomSnapshotThing {
  final String name;
  final ObjectRef object;

  const RoomSnapshotThing({
    required this.name,
    required this.object,
  });
}

class RoomSnapshotAction {
  final String label;
  final String command;

  const RoomSnapshotAction({
    required this.label,
    required this.command,
  });
}

class RoomSnapshot {
  final String title;
  final String description;
  final ObjectRef? room;
  final List<String> exits;
  final List<RoomSnapshotAction> actions;
  final List<RoomSnapshotThing> things;
  final List<RoomSnapshotActor> actors;

  const RoomSnapshot({
    required this.title,
    required this.description,
    required this.room,
    required this.exits,
    required this.actions,
    required this.things,
    required this.actors,
  });
}

RoomSnapshot? roomSnapshotFromPayload(Object? payload) {
  final snapshot = _coerceMap(payload);
  if (snapshot == null) return null;

  final rawTitle = _coerceText(snapshot['title']);
  final title = rawTitle.isNotEmpty ? rawTitle : 'Room';
  final description = _coerceText(snapshot['description']);
  final room = objectRefFromDynamic(snapshot['room']);

  final exits = <String>{};
  final exitsRaw = snapshot['exits'];
  if (exitsRaw is List) {
    for (final e in exitsRaw) {
      final label = _coerceText(e);
      if (label.isNotEmpty) exits.add(label);
    }
  }

  final ambientPassages = snapshot['ambient_passages'];
  if (ambientPassages is List) {
    for (final entry in ambientPassages) {
      if (entry is List && entry.length >= 3) {
        final label = _coerceText(entry[2]);
        if (label.isNotEmpty) exits.add(label);
      }
    }
  }

  final actions = <RoomSnapshotAction>[];
  final actionsRaw = snapshot['actions'];
  if (actionsRaw is List) {
    for (final entry in actionsRaw) {
      if (entry is! List || entry.isEmpty) continue;
      final command = _coerceText(entry.length > 1 ? entry[1] : null);
      final label = _coerceText(entry.length > 2 ? entry[2] : null);
      var resolvedCommand = command;
      var resolvedLabel = label;
      if (resolvedCommand.isEmpty || resolvedLabel.isEmpty) {
        resolvedCommand = _coerceText(entry[0]);
        resolvedLabel = _coerceText(entry.length > 1 ? entry[1] : null);
      }
      if (resolvedCommand.isEmpty || resolvedLabel.isEmpty) continue;
      actions.add(
        RoomSnapshotAction(label: resolvedLabel, command: resolvedCommand),
      );
    }
  }

  final things = <RoomSnapshotThing>[];
  final thingsRaw = snapshot['things'];
  if (thingsRaw is List) {
    for (final entry in thingsRaw) {
      final thing = _coerceMap(entry);
      if (thing == null) continue;
      final name = _coerceText(thing['name']);
      if (name.isEmpty) continue;
      final obj = objectRefFromDynamic(thing['object']);
      if (obj == null) continue;
      things.add(RoomSnapshotThing(name: name, object: obj));
    }
  }

  final actors = <RoomSnapshotActor>[];
  final actorsRaw = snapshot['actors'];
  if (actorsRaw is List) {
    for (final entry in actorsRaw) {
      final actor = _coerceMap(entry);
      if (actor == null) continue;
      final name = _coerceText(actor['name']);
      if (name.isEmpty) continue;
      final status = _coerceText(actor['status']);
      final obj = objectRefFromDynamic(actor['object']);
      if (obj == null) continue;
      actors.add(RoomSnapshotActor(name: name, status: status, object: obj));
    }
  }

  return RoomSnapshot(
    title: title,
    description: description,
    room: room,
    exits: exits.toList(),
    actions: actions,
    things: things,
    actors: actors,
  );
}
