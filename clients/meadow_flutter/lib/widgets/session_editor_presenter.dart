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

import 'package:flutter/material.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/widgets/property_editor.dart';
import 'package:meadow_flutter/widgets/verb_editor.dart';

class SessionEditorPresenter {
  final Uri baseUri;
  final String authToken;

  final Map<String, Widget> _paneCache = <String, Widget>{};

  SessionEditorPresenter({
    required this.baseUri,
    required this.authToken,
  });

  @visibleForTesting
  int get cachedPaneCount => _paneCache.length;

  void pruneSessions(List<EditorSession> sessions) {
    final nextPids = sessions.map((session) => session.presentationId).toSet();
    final toRemove = _paneCache.keys
        .where((presentationId) => !nextPids.contains(presentationId))
        .toList();
    for (final presentationId in toRemove) {
      _paneCache.remove(presentationId);
    }
  }

  void removePresentationId(String presentationId) {
    _paneCache.remove(presentationId);
  }

  void clear() {
    _paneCache.clear();
  }

  Widget paneForSession(EditorSession session) {
    return _paneCache.putIfAbsent(session.presentationId, () {
      return switch (session) {
        VerbEditorSession(:final objectCurie, :final verbName) =>
          VerbEditorPane(
            key: ValueKey(session.presentationId),
            baseUri: baseUri,
            authToken: authToken,
            objectCurie: objectCurie,
            verbName: verbName,
          ),
        PropertyEditorSession(:final objectCurie, :final propertyName) =>
          PropertyEditorPane(
            key: ValueKey(session.presentationId),
            baseUri: baseUri,
            authToken: authToken,
            objectCurie: objectCurie,
            propertyName: propertyName,
          ),
      };
    });
  }

  Future<void> openFullscreen(BuildContext context, EditorSession session) {
    final child = switch (session) {
      VerbEditorSession(:final objectCurie, :final verbName) => VerbEditorPane(
        key: ValueKey('fullscreen:${session.presentationId}'),
        baseUri: baseUri,
        authToken: authToken,
        objectCurie: objectCurie,
        verbName: verbName,
      ),
      PropertyEditorSession(:final objectCurie, :final propertyName) =>
        PropertyEditorPane(
          key: ValueKey('fullscreen:${session.presentationId}'),
          baseUri: baseUri,
          authToken: authToken,
          objectCurie: objectCurie,
          propertyName: propertyName,
        ),
    };

    final screen = switch (session) {
      VerbEditorSession() => VerbEditorScreen(
        title: session.title,
        child: child,
      ),
      PropertyEditorSession() => PropertyEditorScreen(
        title: session.title,
        child: child,
      ),
    };

    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => screen,
      ),
    );
  }
}
