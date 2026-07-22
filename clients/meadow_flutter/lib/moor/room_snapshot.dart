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
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

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

RoomSnapshot? roomSnapshotFromPayload(MoorVar payload) {
  final snapshot = payload.asMap();
  if (snapshot == null) return null;

  MoorVar? get(String key) =>
      snapshot.pairs[MoorVar(MoorSym(key))] ?? snapshot.pairs[MoorVar(key)];

  final title = get('title')?.coerceText() ?? 'Room';
  final description = get('description')?.coerceText() ?? '';
  final room = objectRefFromDynamic(get('room'));

  final exits = <String>{};
  final exitsRaw = get('exits')?.asList();
  if (exitsRaw != null) {
    for (final e in exitsRaw.elements) {
      final label = e.coerceText();
      if (label.isNotEmpty) exits.add(label);
    }
  }

  final ambientPassages = get('ambient_passages')?.asList();
  if (ambientPassages != null) {
    for (final entry in ambientPassages.elements) {
      final list = entry.asList();
      if (list != null && list.elements.length >= 3) {
        final label = list.elements[2].coerceText();
        if (label.isNotEmpty) exits.add(label);
      }
    }
  }

  final actions = <RoomSnapshotAction>[];
  final actionsRaw = get('actions')?.asList();
  if (actionsRaw != null) {
    for (final entry in actionsRaw.elements) {
      final list = entry.asList();
      if (list == null || list.elements.isEmpty) continue;
      final command =
          (list.elements.length > 1 ? list.elements[1] : moorNoneVar)
              .coerceText();
      final label = (list.elements.length > 2 ? list.elements[2] : moorNoneVar)
          .coerceText();
      var resolvedCommand = command;
      var resolvedLabel = label;
      if (resolvedCommand.isEmpty || resolvedLabel.isEmpty) {
        resolvedCommand = list.elements[0].coerceText();
        resolvedLabel =
            (list.elements.length > 1 ? list.elements[1] : moorNoneVar)
                .coerceText();
      }
      if (resolvedCommand.isEmpty || resolvedLabel.isEmpty) continue;
      actions.add(
        RoomSnapshotAction(label: resolvedLabel, command: resolvedCommand),
      );
    }
  }

  final things = <RoomSnapshotThing>[];
  final thingsRaw = get('things')?.asList();
  if (thingsRaw != null) {
    for (final entry in thingsRaw.elements) {
      final thingMap = entry.asMap();
      if (thingMap == null) continue;
      MoorVar? getT(String k) =>
          thingMap.pairs[MoorVar(MoorSym(k))] ?? thingMap.pairs[MoorVar(k)];

      final name = (getT('name') ?? moorNoneVar).coerceText();
      if (name.isEmpty) continue;
      final obj = objectRefFromDynamic(getT('object'));
      if (obj == null) continue;
      things.add(RoomSnapshotThing(name: name, object: obj));
    }
  }

  final actors = <RoomSnapshotActor>[];
  final actorsRaw = get('actors')?.asList();
  if (actorsRaw != null) {
    for (final entry in actorsRaw.elements) {
      final actorMap = entry.asMap();
      if (actorMap == null) continue;
      MoorVar? getA(String k) =>
          actorMap.pairs[MoorVar(MoorSym(k))] ?? actorMap.pairs[MoorVar(k)];

      final name = (getA('name') ?? moorNoneVar).coerceText();
      if (name.isEmpty) continue;
      final status = (getA('status') ?? moorNoneVar).coerceText();
      final obj = objectRefFromDynamic(getA('object'));
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
