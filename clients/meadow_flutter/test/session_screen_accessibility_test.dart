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
import 'package:meadow_flutter/main.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/input_prompt_controller.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';

void main() {
  group('SessionScreen accessibility', () {
    testWidgets('switches between command input and active prompt accessibly', (
      WidgetTester tester,
    ) async {
      final promptController = InputPromptController();
      addTearDown(promptController.dispose);

      await tester.pumpWidget(
        _wrap(
          child: SessionScreen(
            session: _session,
            mode: 'connect',
            initialMooTitle: 'mooR',
            behavior: const SessionScreenBehavior.testing(),
            controllers: SessionScreenControllers(
              inputPromptController: promptController,
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);

      promptController.handleRequest(
        const InputPromptRequest(
          requestId: 'prompt-1',
          metadata: InputPromptMetadata(
            inputType: 'text',
            prompt: 'Name your companion',
            ttsPrompt: null,
            choices: <String>[],
            min: null,
            max: null,
            defaultValue: 'Rover',
            placeholder: 'Companion name',
            rows: null,
            alternativeLabel: null,
            alternativePlaceholder: null,
            acceptContentTypes: <String>[],
            maxFileSize: null,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Command'), findsNothing);
      expect(find.text('Name your companion'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      promptController.clear();
      await tester.pump();

      expect(find.text('Command'), findsOneWidget);
    });

    testWidgets('renders right dock presentations inside session shell', (
      WidgetTester tester,
    ) async {
      final presentations = PresentationStore();
      addTearDown(presentations.dispose);

      await tester.pumpWidget(
        _wrap(
          child: SessionScreen(
            session: _session,
            mode: 'connect',
            initialMooTitle: 'mooR',
            behavior: const SessionScreenBehavior.testing(),
            controllers: SessionScreenControllers(
              presentations: presentations,
            ),
          ),
        ),
      );

      presentations.upsert(
        const PresentationModel(
          id: 'debug-panel',
          target: 'right',
          contentType: 'text/plain',
          content: 'Recent debug output',
          attrs: <String, String>{
            'title': 'Debug panel',
            'kind': 'debug_output',
          },
        ),
      );
      await tester.pump();

      expect(find.text('Debug panel'), findsOneWidget);
      expect(find.text('Recent debug output'), findsOneWidget);
      expect(find.byTooltip('Close panel'), findsOneWidget);
    });

    testWidgets('renders top dock presentations inside session shell', (
      WidgetTester tester,
    ) async {
      final presentations = PresentationStore();
      addTearDown(presentations.dispose);

      await tester.pumpWidget(
        _wrap(
          child: SessionScreen(
            session: _session,
            mode: 'connect',
            initialMooTitle: 'mooR',
            behavior: const SessionScreenBehavior.testing(),
            controllers: SessionScreenControllers(
              presentations: presentations,
            ),
          ),
        ),
      );

      presentations.upsert(
        const PresentationModel(
          id: 'top-panel',
          target: 'top',
          contentType: 'text/plain',
          content: 'Top dock content',
          attrs: <String, String>{'title': 'Top panel'},
        ),
      );
      await tester.pump();

      expect(find.text('Top panel'), findsOneWidget);
      expect(find.text('Top dock content'), findsOneWidget);
    });

    testWidgets('renders editor dock in wide layouts from presentations', (
      WidgetTester tester,
    ) async {
      final presentations = PresentationStore();
      addTearDown(presentations.dispose);

      await tester.pumpWidget(
        _wrap(
          child: SessionScreen(
            session: _session,
            mode: 'connect',
            initialMooTitle: 'mooR',
            behavior: const SessionScreenBehavior.testing(),
            controllers: SessionScreenControllers(
              presentations: presentations,
              editorPresenter: _fakeEditorPresenter(),
            ),
          ),
        ),
      );

      presentations.upsert(
        const PresentationModel(
          id: 'edit-1',
          target: 'verb-editor',
          contentType: 'text/plain',
          content: '',
          attrs: <String, String>{
            'object': 'oid:1',
            'verb': 'look_self',
            'title': 'Edit look_self',
          },
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Editor dock'), findsOneWidget);
      expect(find.text('Edit look_self'), findsOneWidget);
      expect(find.text('Editor pane: Edit look_self'), findsOneWidget);
    });

    testWidgets('renders editor dock in compact layouts from presentations', (
      WidgetTester tester,
    ) async {
      final presentations = PresentationStore();
      addTearDown(presentations.dispose);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(700, 900));

      await tester.pumpWidget(
        _wrap(
          child: SessionScreen(
            session: _session,
            mode: 'connect',
            initialMooTitle: 'mooR',
            behavior: const SessionScreenBehavior.testing(),
            controllers: SessionScreenControllers(
              presentations: presentations,
              editorPresenter: _fakeEditorPresenter(),
            ),
          ),
        ),
      );

      presentations.upsert(
        const PresentationModel(
          id: 'edit-compact',
          target: 'verb-editor',
          contentType: 'text/plain',
          content: '',
          attrs: <String, String>{
            'object': 'oid:1',
            'verb': 'look_self',
            'title': 'Edit look_self',
          },
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Editor dock'), findsOneWidget);
      expect(find.text('Editor pane: Edit look_self'), findsOneWidget);
      expect(find.text('Command'), findsOneWidget);
    });
  });
}

Widget _wrap({required Widget child}) {
  return MaterialApp(
    home: child,
  );
}

SessionEditorPresenter _fakeEditorPresenter() {
  return SessionEditorPresenter(
    baseUri: _session.baseUri,
    authToken: _session.authToken,
    paneFactory:
        (
          EditorSession session, {
          required Key key,
          required Uri baseUri,
          required String authToken,
        }) {
          return Semantics(
            key: key,
            container: true,
            label: 'Editor pane: ${session.title}',
            child: Center(
              child: Text('Editor pane: ${session.title}'),
            ),
          );
        },
  );
}

final _session = LoginSession(
  baseUri: Uri(scheme: 'http', host: 'localhost', port: 8080),
  authToken: 'token',
  playerCurie: 'oid:1',
  playerFlags: 0,
  clientToken: null,
  clientId: null,
  isInitialAttach: true,
);
