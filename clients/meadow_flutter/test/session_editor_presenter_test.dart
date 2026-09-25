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
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  group('SessionEditorPresenter', () {
    testWidgets(
      'preserves an edited pane across presentation updates and tabs',
      (
        WidgetTester tester,
      ) async {
        final presenter = SessionEditorPresenter(
          baseUri: Uri.parse('http://localhost:8080'),
          authToken: 'token',
        );
        const session = PropertyEditorSession(
          id: 'prop-1',
          title: 'Edit oid:1.name',
          presentationId: 'prop-1',
          objectCurie: 'oid:1',
          propertyName: 'name',
          isValueEditor: false,
        );

        const updated = PropertyEditorSession(
          id: 'prop-1',
          title: 'Updated editor title',
          presentationId: 'prop-1',
          objectCurie: 'oid:1',
          propertyName: 'name',
          isValueEditor: false,
        );
        const other = VerbEditorSession(
          id: 'verb-1',
          title: 'Edit oid:2:look_self',
          presentationId: 'verb-1',
          objectCurie: 'oid:2',
          verbName: 'look_self',
        );

        Widget dock(List<EditorSession> sessions, int activeIndex) =>
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  height: 400,
                  child: SessionEditorDock(
                    sessions: sessions,
                    activeIndex: activeIndex,
                    onSelectIndex: (_) {},
                    onCloseSession: (_) async {},
                    onOpenFullscreen: (_) async {},
                    paneBuilder: presenter.paneForSession,
                  ),
                ),
              ),
            );

        await tester.pumpWidget(dock(<EditorSession>[session, other], 0));
        await tester.pumpAndSettle();
        final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
        editor.controller!.codeLines = CodeLines.fromText('unsaved edit');
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          editor.controller!.codeLines.asString(TextLineBreak.lf, false),
          'unsaved edit',
        );

        await tester.pumpWidget(dock(<EditorSession>[updated, other], 1));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(dock(<EditorSession>[updated, other], 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widget<CodeEditor>(find.byType(CodeEditor))
              .controller!
              .codeLines
              .asString(TextLineBreak.lf, false),
          'unsaved edit',
        );

        presenter.pruneSessions(<EditorSession>[other]);
        await tester.pumpWidget(dock(<EditorSession>[other], 0));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(dock(<EditorSession>[session, other], 0));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widget<CodeEditor>(find.byType(CodeEditor))
              .controller!
              .codeLines
              .asString(TextLineBreak.lf, false),
          isEmpty,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

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

      final stalePane = presenter.paneForSession(stale);
      final keptPane = presenter.paneForSession(keep);
      presenter.pruneSessions(<EditorSession>[keep]);

      expect(presenter.cachedPaneCount, equals(1));
      expect(identical(presenter.paneForSession(keep), keptPane), isTrue);
      expect(identical(presenter.paneForSession(stale), stalePane), isFalse);
    });
  });
}
