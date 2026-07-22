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
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/presentations.dart';

class EditorSessionController extends ChangeNotifier {
  final List<EditorSession> _sessions = <EditorSession>[];
  int _activeIndex = 0;

  List<EditorSession> get sessions =>
      List<EditorSession>.unmodifiable(_sessions);
  int get activeIndex => _activeIndex;

  void syncFromPresentations(
    PresentationStore presentations, {
    void Function(String message)? onSystemMessage,
  }) {
    final wasEmpty = _sessions.isEmpty;
    final oldPids = _sessions.map((session) => session.presentationId).toSet();
    final nextSessions = deriveEditorSessionsFromPresentations(
      presentations,
      onSystemMessage: onSystemMessage,
    );

    final didChange =
        nextSessions.length != _sessions.length ||
        !_sameStringList(
          nextSessions.map((session) => session.presentationId).toList(),
          _sessions.map((session) => session.presentationId).toList(),
        );
    if (!didChange) {
      return;
    }

    final nextPids = nextSessions
        .map((session) => session.presentationId)
        .toSet();
    final newPids = nextPids.difference(oldPids);

    _sessions
      ..clear()
      ..addAll(nextSessions);

    if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.isEmpty ? 0 : _sessions.length - 1;
    }
    if (_activeIndex < 0) {
      _activeIndex = 0;
    }
    if (wasEmpty && _sessions.isNotEmpty) {
      _activeIndex = _sessions.length - 1;
    }
    if (newPids.isNotEmpty) {
      final lastNewIdx = _sessions.lastIndexWhere(
        (session) => newPids.contains(session.presentationId),
      );
      if (lastNewIdx >= 0) {
        _activeIndex = lastNewIdx;
      }
    }

    notifyListeners();
  }

  void selectIndex(int index) {
    if (index < 0 || index >= _sessions.length || index == _activeIndex) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
  }

  void removePresentationId(String presentationId) {
    final idx = _sessions.indexWhere(
      (session) => session.presentationId == presentationId,
    );
    if (idx < 0) {
      return;
    }
    _sessions.removeAt(idx);
    if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.isEmpty ? 0 : _sessions.length - 1;
    }
    notifyListeners();
  }

  void clear() {
    if (_sessions.isEmpty && _activeIndex == 0) {
      return;
    }
    _sessions.clear();
    _activeIndex = 0;
    notifyListeners();
  }
}

List<EditorSession> deriveEditorSessionsFromPresentations(
  PresentationStore presentations, {
  void Function(String message)? onSystemMessage,
}) {
  final sessions = <EditorSession>[];

  for (final item in presentations.byTarget('verb-editor')) {
    if (item is! PresentationModel) {
      continue;
    }
    final pid = item.id;
    final rawObject = item.attrs['object'] ?? item.attrs['objectCurie'];
    final rawVerb = item.attrs['verb'] ?? item.attrs['verbName'];
    if (rawObject == null || rawVerb == null) {
      continue;
    }
    final objectCurie = objectRefToCurie(rawObject);
    if (objectCurie == null) {
      onSystemMessage?.call('verb-editor: invalid object=$rawObject');
      continue;
    }
    final title = (item.attrs['title']?.trim().isNotEmpty ?? false)
        ? item.attrs['title']!
        : 'Edit $objectCurie:$rawVerb';
    sessions.add(
      VerbEditorSession(
        id: pid,
        title: title,
        presentationId: pid,
        objectCurie: objectCurie,
        verbName: rawVerb,
      ),
    );
  }

  for (final item in presentations.byTarget('property-editor')) {
    final session = _propertySessionFromPresentation(
      item,
      isValueEditor: false,
      onSystemMessage: onSystemMessage,
    );
    if (session != null) {
      sessions.add(session);
    }
  }

  for (final item in presentations.byTarget('property-value-editor')) {
    final session = _propertySessionFromPresentation(
      item,
      isValueEditor: true,
      onSystemMessage: onSystemMessage,
    );
    if (session != null) {
      sessions.add(session);
    }
  }

  return sessions;
}

PropertyEditorSession? _propertySessionFromPresentation(
  DockItem item, {
  required bool isValueEditor,
  void Function(String message)? onSystemMessage,
}) {
  if (item is! PresentationModel) {
    return null;
  }
  final pid = item.id;
  final rawObject = item.attrs['object'] ?? item.attrs['objectCurie'];
  final rawProperty = item.attrs['property'] ?? item.attrs['propertyName'];
  if (rawObject == null || rawProperty == null) {
    return null;
  }
  final objectCurie = objectRefToCurie(rawObject);
  if (objectCurie == null) {
    final targetName = isValueEditor
        ? 'property-value-editor'
        : 'property-editor';
    onSystemMessage?.call('$targetName: invalid object=$rawObject');
    return null;
  }
  final title = (item.attrs['title']?.trim().isNotEmpty ?? false)
      ? item.attrs['title']!
      : 'Edit $objectCurie.$rawProperty';
  return PropertyEditorSession(
    id: pid,
    title: title,
    presentationId: pid,
    objectCurie: objectCurie,
    propertyName: rawProperty,
    isValueEditor: isValueEditor,
  );
}

bool _sameStringList(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
