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

typedef EditorPaneFactory =
    Widget Function(
      EditorSession session, {
      required Key key,
      required Uri baseUri,
      required String authToken,
    });

typedef EditorScreenFactory =
    Widget Function(EditorSession session, Widget child);

class SessionEditorPresenter {
  final Uri baseUri;
  final String authToken;
  final EditorPaneFactory _paneFactory;
  final EditorScreenFactory _screenFactory;

  final Map<String, Widget> _paneCache = <String, Widget>{};

  SessionEditorPresenter({
    required this.baseUri,
    required this.authToken,
    EditorPaneFactory? paneFactory,
    EditorScreenFactory? screenFactory,
  }) : _paneFactory = paneFactory ?? _defaultPaneFactory,
       _screenFactory = screenFactory ?? _defaultScreenFactory;

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
      return _paneFactory(
        session,
        key: ValueKey(session.presentationId),
        baseUri: baseUri,
        authToken: authToken,
      );
    });
  }

  Future<void> openFullscreen(BuildContext context, EditorSession session) {
    final child = _paneFactory(
      session,
      key: ValueKey('fullscreen:${session.presentationId}'),
      baseUri: baseUri,
      authToken: authToken,
    );
    final screen = _screenFactory(session, child);

    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => screen,
      ),
    );
  }

  static Widget _defaultPaneFactory(
    EditorSession session, {
    required Key key,
    required Uri baseUri,
    required String authToken,
  }) {
    return switch (session) {
      VerbEditorSession(:final objectCurie, :final verbName) => VerbEditorPane(
        key: key,
        baseUri: baseUri,
        authToken: authToken,
        objectCurie: objectCurie,
        verbName: verbName,
      ),
      PropertyEditorSession(:final objectCurie, :final propertyName) =>
        PropertyEditorPane(
          key: key,
          baseUri: baseUri,
          authToken: authToken,
          objectCurie: objectCurie,
          propertyName: propertyName,
        ),
    };
  }

  static Widget _defaultScreenFactory(EditorSession session, Widget child) {
    return switch (session) {
      VerbEditorSession() => VerbEditorScreen(
        title: session.title,
        child: child,
      ),
      PropertyEditorSession() => PropertyEditorScreen(
        title: session.title,
        child: child,
      ),
    };
  }
}
