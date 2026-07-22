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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';

void main() {
  group('SessionEditorPresenter', () {
    test('reuses cached pane widgets for the same presentation', () {
      final presenter = SessionEditorPresenter(
        baseUri: Uri.parse('http://localhost:8080'),
        authToken: 'token',
      );
      const session = VerbEditorSession(
        id: 'verb-1',
        title: 'Edit oid:1:look_self',
        presentationId: 'verb-1',
        objectCurie: 'oid:1',
        verbName: 'look_self',
      );

      final first = presenter.paneForSession(session);
      final second = presenter.paneForSession(session);

      expect(identical(first, second), isTrue);
      expect(presenter.cachedPaneCount, equals(1));
    });

    test('pruneSessions removes stale cached panes', () {
      final presenter = SessionEditorPresenter(
        baseUri: Uri.parse('http://localhost:8080'),
        authToken: 'token',
      );
      const stale = VerbEditorSession(
        id: 'verb-1',
        title: 'Edit oid:1:look_self',
        presentationId: 'verb-1',
        objectCurie: 'oid:1',
        verbName: 'look_self',
      );
      const keep = PropertyEditorSession(
        id: 'prop-1',
        title: 'Edit oid:2.name',
        presentationId: 'prop-1',
        objectCurie: 'oid:2',
        propertyName: 'name',
        isValueEditor: false,
      );

      presenter
        ..paneForSession(stale)
        ..paneForSession(keep)
        ..pruneSessions(<EditorSession>[keep]);

      expect(presenter.cachedPaneCount, equals(1));
      expect(
        identical(
          presenter.paneForSession(keep),
          presenter.paneForSession(keep),
        ),
        isTrue,
      );
    });
  });
}
