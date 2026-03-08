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
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/object_browser_controller.dart';

void main() {
  group('ObjectBrowserController', () {
    test('reuses property editor sessions for the same property', () {
      final api = MoorHttpApi(Uri(scheme: 'http', host: 'example.com'));
      final controller = ObjectBrowserController(
        api: api,
        authToken: 'token',
      );

      const property = BrowserPropertyEntry(
        name: 'description',
        definerCurie: 'oid:1',
        locationCurie: 'oid:1',
        ownerCurie: 'oid:1',
        readable: true,
        writable: true,
        chown: false,
      );

      controller
        ..selectProperty(property)
        ..selectProperty(property);

      expect(controller.editorSessions, hasLength(1));
      expect(controller.activeEditorIndex, 0);
      expect(
        controller.selectedPropertyKey,
        ObjectBrowserController.propertyKey(property),
      );
      expect(controller.selectedVerbKey, isNull);
    });

    test('reuses verb editor sessions for the same verb slot', () {
      final api = MoorHttpApi(Uri(scheme: 'http', host: 'example.com'));
      final controller = ObjectBrowserController(
        api: api,
        authToken: 'token',
      );

      const verb = BrowserVerbEntry(
        names: ['look', 'glance'],
        locationCurie: 'oid:1',
        ownerCurie: 'oid:2',
        readable: true,
        writable: true,
        executable: true,
        debug: false,
        dobj: 'none',
        prep: 'none',
        iobj: 'none',
        indexInLocation: 0,
      );

      controller
        ..selectVerb(verb)
        ..selectVerb(verb);

      expect(controller.editorSessions, hasLength(1));
      expect(controller.activeEditorIndex, 0);
      expect(controller.selectedPropertyKey, isNull);
      expect(controller.selectedVerbKey, ObjectBrowserController.verbKey(verb));
    });

    test('closing the active session clamps the selected index', () {
      final api = MoorHttpApi(Uri(scheme: 'http', host: 'example.com'));
      final controller = ObjectBrowserController(
        api: api,
        authToken: 'token',
      );

      const firstVerb = BrowserVerbEntry(
        names: ['look'],
        locationCurie: 'oid:1',
        ownerCurie: 'oid:2',
        readable: true,
        writable: true,
        executable: true,
        debug: false,
        dobj: 'none',
        prep: 'none',
        iobj: 'none',
        indexInLocation: 0,
      );
      const secondVerb = BrowserVerbEntry(
        names: ['take'],
        locationCurie: 'oid:1',
        ownerCurie: 'oid:2',
        readable: true,
        writable: true,
        executable: true,
        debug: false,
        dobj: 'this',
        prep: 'from',
        iobj: 'any',
        indexInLocation: 1,
      );

      controller
        ..selectVerb(firstVerb)
        ..selectVerb(secondVerb);

      expect(controller.activeEditorIndex, 1);

      controller.closeSession(controller.editorSessions.last);

      expect(controller.editorSessions, hasLength(1));
      expect(controller.activeEditorIndex, 0);
    });
  });
}
