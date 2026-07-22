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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
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

    test(
      'refreshSelectedObject preserves selected property and verb keys',
      () async {
        final api = _FakeObjectBrowserApi();
        final controller = ObjectBrowserController(
          api: api,
          authToken: 'token',
        );

        await controller.load();
        controller.selectProperty(
          controller.properties.firstWhere(
            (prop) => prop.name == 'description',
          ),
        );
        expect(controller.selectedProperty?.name, 'description');

        await controller.refreshSelectedObject();
        expect(controller.selectedProperty?.name, 'description');

        controller.selectVerb(
          controller.verbs.firstWhere((verb) => verb.names.first == 'look'),
        );
        expect(controller.selectedVerb?.names.first, 'look');

        await controller.refreshSelectedObject();
        expect(controller.selectedVerb?.names.first, 'look');
      },
    );
  });
}

class _FakeObjectBrowserApi extends MoorHttpApi {
  _FakeObjectBrowserApi() : super(Uri(scheme: 'http', host: 'example.com'));

  @override
  Future<moor_rpc.ListObjectsReply> listObjects({
    required String authToken,
  }) async {
    return moor_rpc.ListObjectsReplyObjectBuilder(
      objects: [
        moor_rpc.ObjectInfoObjectBuilder(
          obj: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          name: moor_common.SymbolObjectBuilder(value: 'Wizard'),
          parent: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 0),
          ),
          owner: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          location: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          flags: 0,
          verbsCount: 1,
          propertiesCount: 1,
        ),
      ],
    ).toBytes().toListObjectsReply();
  }

  @override
  Future<moor_rpc.PropertiesReply> getProperties({
    required String authToken,
    required String objectCurie,
    bool inherited = true,
  }) async {
    return moor_rpc.PropertiesReplyObjectBuilder(
      properties: [
        moor_common.PropInfoObjectBuilder(
          name: moor_common.SymbolObjectBuilder(value: 'description'),
          definer: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          location: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          owner: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          r: true,
          w: true,
          chown: false,
        ),
      ],
    ).toBytes().toPropertiesReply();
  }

  @override
  Future<moor_rpc.VerbsReply> getVerbs({
    required String authToken,
    required String objectCurie,
    bool inherited = true,
  }) async {
    return moor_rpc.VerbsReplyObjectBuilder(
      verbs: [
        moor_common.VerbInfoObjectBuilder(
          names: [moor_common.SymbolObjectBuilder(value: 'look')],
          location: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          owner: moor_common.ObjObjectBuilder(
            objType: moor_common.ObjUnionTypeId.ObjId,
            obj: moor_common.ObjIdObjectBuilder(id: 1),
          ),
          r: true,
          w: true,
          x: true,
          d: false,
          argSpec: [
            moor_common.SymbolObjectBuilder(value: 'none'),
            moor_common.SymbolObjectBuilder(value: 'none'),
            moor_common.SymbolObjectBuilder(value: 'none'),
          ],
        ),
      ],
    ).toBytes().toVerbsReply();
  }
}

extension on List<int> {
  moor_rpc.ListObjectsReply toListObjectsReply() {
    return moor_rpc.ListObjectsReply(this);
  }

  moor_rpc.PropertiesReply toPropertiesReply() {
    return moor_rpc.PropertiesReply(this);
  }

  moor_rpc.VerbsReply toVerbsReply() {
    return moor_rpc.VerbsReply(this);
  }
}
