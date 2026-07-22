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
import 'package:meadow_flutter/moor/editor_session_controller.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/presentations.dart';

void main() {
  group('EditorSessionController', () {
    test('maps editor presentations into typed sessions', () {
      final store = PresentationStore();
      addTearDown(store.dispose);
      store
        ..upsert(
          const PresentationModel(
            id: 'verb-1',
            target: 'verb-editor',
            contentType: 'text/plain',
            content: '',
            attrs: <String, String>{
              'object': 'oid:1',
              'verb': 'look_self',
            },
          ),
        )
        ..upsert(
          const PresentationModel(
            id: 'prop-1',
            target: 'property-editor',
            contentType: 'text/plain',
            content: '',
            attrs: <String, String>{
              'object': 'oid:2',
              'property': 'name',
            },
          ),
        );

      final sessions = deriveEditorSessionsFromPresentations(store);

      expect(sessions, hasLength(2));
      expect(sessions.first, isA<VerbEditorSession>());
      expect(
        (sessions.first as VerbEditorSession).objectCurie,
        equals('oid:1'),
      );
      expect(sessions.last, isA<PropertyEditorSession>());
      expect(
        (sessions.last as PropertyEditorSession).propertyName,
        equals('name'),
      );
    });

    test('ignores invalid object refs and reports them', () {
      final store = PresentationStore();
      addTearDown(store.dispose);
      store.upsert(
        const PresentationModel(
          id: 'verb-1',
          target: 'verb-editor',
          contentType: 'text/plain',
          content: '',
          attrs: <String, String>{
            'object': 'bogus',
            'verb': 'look_self',
          },
        ),
      );
      final messages = <String>[];

      final sessions = deriveEditorSessionsFromPresentations(
        store,
        onSystemMessage: messages.add,
      );

      expect(sessions, isEmpty);
      expect(messages, contains('verb-editor: invalid object=bogus'));
    });

    test('sync keeps newest new editor active', () {
      final store = PresentationStore();
      addTearDown(store.dispose);
      final controller = EditorSessionController();
      addTearDown(controller.dispose);

      store.upsert(
        const PresentationModel(
          id: 'verb-1',
          target: 'verb-editor',
          contentType: 'text/plain',
          content: '',
          attrs: <String, String>{
            'object': 'oid:1',
            'verb': 'look_self',
          },
        ),
      );
      controller.syncFromPresentations(store);
      expect(controller.sessions, hasLength(1));
      expect(controller.activeIndex, equals(0));

      store.upsert(
        const PresentationModel(
          id: 'prop-1',
          target: 'property-editor',
          contentType: 'text/plain',
          content: '',
          attrs: <String, String>{
            'object': 'oid:2',
            'property': 'name',
          },
        ),
      );
      controller.syncFromPresentations(store);

      expect(controller.sessions, hasLength(2));
      expect(controller.activeIndex, equals(1));
      expect(
        controller.sessions[controller.activeIndex].presentationId,
        equals('prop-1'),
      );
    });

    test('removePresentationId clamps active index', () {
      final store = PresentationStore();
      addTearDown(store.dispose);
      final controller = EditorSessionController();
      addTearDown(controller.dispose);
      store
        ..upsert(
          const PresentationModel(
            id: 'verb-1',
            target: 'verb-editor',
            contentType: 'text/plain',
            content: '',
            attrs: <String, String>{
              'object': 'oid:1',
              'verb': 'look_self',
            },
          ),
        )
        ..upsert(
          const PresentationModel(
            id: 'prop-1',
            target: 'property-editor',
            contentType: 'text/plain',
            content: '',
            attrs: <String, String>{
              'object': 'oid:2',
              'property': 'name',
            },
          ),
        );
      controller
        ..syncFromPresentations(store)
        ..selectIndex(1)
        ..removePresentationId('prop-1');

      expect(controller.sessions, hasLength(1));
      expect(controller.activeIndex, equals(0));
      expect(controller.sessions.first.presentationId, equals('verb-1'));
    });
  });
}
