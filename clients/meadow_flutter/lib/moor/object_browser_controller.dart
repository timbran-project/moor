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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';

class BrowserObjectEntry {
  final String objectCurie;
  final String name;
  final String parentCurie;
  final String ownerCurie;
  final int flags;
  final String locationCurie;
  final int verbsCount;
  final int propertiesCount;

  const BrowserObjectEntry({
    required this.objectCurie,
    required this.name,
    required this.parentCurie,
    required this.ownerCurie,
    required this.flags,
    required this.locationCurie,
    required this.verbsCount,
    required this.propertiesCount,
  });
}

class BrowserPropertyEntry {
  final String name;
  final String definerCurie;
  final String locationCurie;
  final String ownerCurie;
  final bool readable;
  final bool writable;
  final bool chown;

  const BrowserPropertyEntry({
    required this.name,
    required this.definerCurie,
    required this.locationCurie,
    required this.ownerCurie,
    required this.readable,
    required this.writable,
    required this.chown,
  });
}

class BrowserVerbEntry {
  final List<String> names;
  final String locationCurie;
  final String ownerCurie;
  final bool readable;
  final bool writable;
  final bool executable;
  final bool debug;
  final String dobj;
  final String prep;
  final String iobj;
  final int indexInLocation;

  const BrowserVerbEntry({
    required this.names,
    required this.locationCurie,
    required this.ownerCurie,
    required this.readable,
    required this.writable,
    required this.executable,
    required this.debug,
    required this.dobj,
    required this.prep,
    required this.iobj,
    required this.indexInLocation,
  });
}

class ObjectBrowserController extends ChangeNotifier {
  final MoorHttpApi api;
  final String authToken;
  final String? initialObjectCurie;

  bool _loadingObjects = false;
  bool _loadingMembers = false;
  String? _error;
  String _objectFilter = '';
  String _propertyFilter = '';
  String _verbFilter = '';
  bool _showInheritedProperties = true;
  bool _showInheritedVerbs = true;

  List<BrowserObjectEntry> _objects = const <BrowserObjectEntry>[];
  List<BrowserPropertyEntry> _properties = const <BrowserPropertyEntry>[];
  List<BrowserVerbEntry> _verbs = const <BrowserVerbEntry>[];
  BrowserObjectEntry? _selectedObject;
  String? _selectedPropertyKey;
  String? _selectedVerbKey;
  List<EditorSession> _editorSessions = const <EditorSession>[];
  int _activeEditorIndex = 0;

  ObjectBrowserController({
    required this.api,
    required this.authToken,
    this.initialObjectCurie,
  });

  bool get loadingObjects => _loadingObjects;
  bool get loadingMembers => _loadingMembers;
  String? get error => _error;
  String get objectFilter => _objectFilter;
  String get propertyFilter => _propertyFilter;
  String get verbFilter => _verbFilter;
  bool get showInheritedProperties => _showInheritedProperties;
  bool get showInheritedVerbs => _showInheritedVerbs;
  List<BrowserObjectEntry> get objects => _objects;
  List<BrowserPropertyEntry> get properties => _properties;
  List<BrowserVerbEntry> get verbs => _verbs;
  BrowserObjectEntry? get selectedObject => _selectedObject;
  String? get selectedPropertyKey => _selectedPropertyKey;
  String? get selectedVerbKey => _selectedVerbKey;
  BrowserPropertyEntry? get selectedProperty {
    final key = _selectedPropertyKey;
    if (key == null) {
      return null;
    }
    for (final property in _properties) {
      if (propertyKey(property) == key) {
        return property;
      }
    }
    return null;
  }

  BrowserVerbEntry? get selectedVerb {
    final key = _selectedVerbKey;
    if (key == null) {
      return null;
    }
    for (final verb in _verbs) {
      if (verbKey(verb) == key) {
        return verb;
      }
    }
    return null;
  }

  List<EditorSession> get editorSessions => _editorSessions;
  int get activeEditorIndex => _activeEditorIndex;

  List<BrowserObjectEntry> get filteredObjects {
    final needle = _objectFilter.trim().toLowerCase();
    if (needle.isEmpty) {
      return _objects;
    }
    return _objects.where((entry) {
      return entry.objectCurie.toLowerCase().contains(needle) ||
          entry.name.toLowerCase().contains(needle);
    }).toList();
  }

  List<BrowserPropertyEntry> get filteredProperties {
    final needle = _propertyFilter.trim().toLowerCase();
    final selected = _selectedObject?.objectCurie;
    return _properties.where((entry) {
      if (!_showInheritedProperties &&
          selected != null &&
          entry.definerCurie != selected) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      return entry.name.toLowerCase().contains(needle) ||
          entry.definerCurie.toLowerCase().contains(needle);
    }).toList();
  }

  List<BrowserVerbEntry> get filteredVerbs {
    final needle = _verbFilter.trim().toLowerCase();
    final selected = _selectedObject?.objectCurie;
    return _verbs.where((entry) {
      if (!_showInheritedVerbs &&
          selected != null &&
          entry.locationCurie != selected) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      return entry.names.any((name) => name.toLowerCase().contains(needle)) ||
          entry.locationCurie.toLowerCase().contains(needle);
    }).toList();
  }

  Future<void> load() async {
    _loadingObjects = true;
    _error = null;
    notifyListeners();
    try {
      final reply = await api.listObjects(authToken: authToken);
      final nextObjects = <BrowserObjectEntry>[
        for (final object in reply.objects ?? const <moor_rpc.ObjectInfo>[])
          if (_toObjectEntry(object) case final entry?) entry,
      ]..sort((a, b) => a.objectCurie.compareTo(b.objectCurie));

      _objects = nextObjects;
      final target = _resolveInitialSelection(nextObjects);
      final preserveSelection =
          target != null &&
          _selectedObject != null &&
          target.objectCurie == _selectedObject!.objectCurie;
      _loadingObjects = false;
      notifyListeners();
      if (target != null) {
        await _loadMembersForSelection(
          target,
          selectedPropertyKey: preserveSelection ? _selectedPropertyKey : null,
          selectedVerbKey: preserveSelection ? _selectedVerbKey : null,
        );
      }
    } on Object catch (e) {
      _loadingObjects = false;
      _error = '$e';
      notifyListeners();
    }
  }

  Future<void> selectObject(BrowserObjectEntry entry) async {
    _selectedObject = entry;
    await _loadMembersForSelection(
      entry,
      selectedPropertyKey: null,
      selectedVerbKey: null,
    );
  }

  Future<void> refreshSelectedObject() async {
    await refreshSelectedObjectWithSelection(
      selectedPropertyKey: _selectedPropertyKey,
      selectedVerbKey: _selectedVerbKey,
    );
  }

  Future<void> refreshSelectedObjectWithSelection({
    String? selectedPropertyKey,
    String? selectedVerbKey,
  }) async {
    final entry = _selectedObject;
    if (entry == null) {
      return;
    }
    await _loadMembersForSelection(
      entry,
      selectedPropertyKey: selectedPropertyKey,
      selectedVerbKey: selectedVerbKey,
    );
  }

  void setObjectFilter(String value) {
    if (value == _objectFilter) {
      return;
    }
    _objectFilter = value;
    notifyListeners();
  }

  void setPropertyFilter(String value) {
    if (value == _propertyFilter) {
      return;
    }
    _propertyFilter = value;
    notifyListeners();
  }

  void setVerbFilter(String value) {
    if (value == _verbFilter) {
      return;
    }
    _verbFilter = value;
    notifyListeners();
  }

  void toggleInheritedProperties() {
    _showInheritedProperties = !_showInheritedProperties;
    notifyListeners();
  }

  void toggleInheritedVerbs() {
    _showInheritedVerbs = !_showInheritedVerbs;
    notifyListeners();
  }

  void selectProperty(BrowserPropertyEntry entry) {
    _selectedPropertyKey = propertyKey(entry);
    _selectedVerbKey = null;
    final session = PropertyEditorSession(
      id: propertyPresentationId(entry),
      title: entry.name,
      presentationId: propertyPresentationId(entry),
      objectCurie: entry.definerCurie,
      propertyName: entry.name,
      isValueEditor: false,
    );
    _upsertSession(session);
  }

  void selectVerb(BrowserVerbEntry entry) {
    _selectedPropertyKey = null;
    _selectedVerbKey = verbKey(entry);
    final primaryName = entry.names.isEmpty ? '(unnamed)' : entry.names.first;
    final session = VerbEditorSession(
      id: verbPresentationId(entry),
      title: primaryName,
      presentationId: verbPresentationId(entry),
      objectCurie: entry.locationCurie,
      verbName: primaryName,
    );
    _upsertSession(session);
  }

  void clearSelectedProperty() {
    _selectedPropertyKey = null;
    notifyListeners();
  }

  void clearSelectedVerb() {
    _selectedVerbKey = null;
    notifyListeners();
  }

  void closeSession(EditorSession session) {
    final index = _editorSessions.indexWhere(
      (item) => item.presentationId == session.presentationId,
    );
    if (index < 0) {
      return;
    }
    final next = [..._editorSessions]..removeAt(index);
    _editorSessions = next;
    if (_activeEditorIndex >= next.length) {
      _activeEditorIndex = next.isEmpty ? 0 : next.length - 1;
    }
    notifyListeners();
  }

  void selectSessionIndex(int index) {
    if (index < 0 || index >= _editorSessions.length) {
      return;
    }
    _activeEditorIndex = index;
    notifyListeners();
  }

  static String propertyKey(BrowserPropertyEntry entry) {
    return '${entry.definerCurie}:${entry.name}';
  }

  static String propertyPresentationId(BrowserPropertyEntry entry) {
    return 'object-browser:property:${entry.definerCurie}:${entry.name}';
  }

  static String verbKey(BrowserVerbEntry entry) {
    return '${entry.locationCurie}:${entry.indexInLocation}';
  }

  static String verbPresentationId(BrowserVerbEntry entry) {
    return 'object-browser:verb:${entry.locationCurie}:${entry.indexInLocation}';
  }

  void closeSessionByPresentationId(String presentationId) {
    final session = _editorSessions.cast<EditorSession?>().firstWhere(
      (item) => item?.presentationId == presentationId,
      orElse: () => null,
    );
    if (session == null) {
      return;
    }
    closeSession(session);
  }

  BrowserObjectEntry? _resolveInitialSelection(
    List<BrowserObjectEntry> entries,
  ) {
    if (entries.isEmpty) {
      return null;
    }
    if (_selectedObject != null) {
      for (final entry in entries) {
        if (entry.objectCurie == _selectedObject!.objectCurie) {
          return entry;
        }
      }
    }
    if (initialObjectCurie != null) {
      for (final entry in entries) {
        if (entry.objectCurie == initialObjectCurie) {
          return entry;
        }
      }
    }
    return entries.first;
  }

  BrowserObjectEntry? _toObjectEntry(moor_rpc.ObjectInfo object) {
    final obj = _objToCurie(object.obj);
    if (obj.isEmpty) {
      return null;
    }
    return BrowserObjectEntry(
      objectCurie: obj,
      name: object.name?.value ?? '',
      parentCurie: _objToCurie(object.parent),
      ownerCurie: _objToCurie(object.owner),
      flags: object.flags,
      locationCurie: _objToCurie(object.location),
      verbsCount: object.verbsCount,
      propertiesCount: object.propertiesCount,
    );
  }

  BrowserPropertyEntry _toPropertyEntry(moor_common.PropInfo prop) {
    return BrowserPropertyEntry(
      name: prop.name?.value ?? '',
      definerCurie: _objToCurie(prop.definer),
      locationCurie: _objToCurie(prop.location),
      ownerCurie: _objToCurie(prop.owner),
      readable: prop.r,
      writable: prop.w,
      chown: prop.chown,
    );
  }

  List<BrowserVerbEntry> _buildVerbEntries(List<moor_common.VerbInfo> verbs) {
    final locationIndices = <String, int>{};
    return [
      for (final verb in verbs)
        (() {
          final locationCurie = _objToCurie(verb.location);
          final indexInLocation = locationIndices[locationCurie] ?? 0;
          locationIndices[locationCurie] = indexInLocation + 1;
          final argSpec = verb.argSpec ?? const <moor_common.Symbol>[];
          return BrowserVerbEntry(
            names: [
              for (final name in verb.names ?? const <moor_common.Symbol>[])
                name.value ?? '',
            ],
            locationCurie: locationCurie,
            ownerCurie: _objToCurie(verb.owner),
            readable: verb.r,
            writable: verb.w,
            executable: verb.x,
            debug: verb.d,
            dobj: argSpec.isNotEmpty ? (argSpec[0].value ?? 'none') : 'none',
            prep: argSpec.length > 1 ? (argSpec[1].value ?? 'none') : 'none',
            iobj: argSpec.length > 2 ? (argSpec[2].value ?? 'none') : 'none',
            indexInLocation: indexInLocation,
          );
        })(),
    ];
  }

  String _objToCurie(moor_common.Obj? object) {
    if (object == null) {
      return '';
    }
    final moorObj = MoorObj.tryFromObjFlatBuffer(object);
    if (moorObj == null || moorObj is MoorAnonymousObjId) {
      return '';
    }
    return moorObj.toCurie();
  }

  void _upsertSession(EditorSession session) {
    final existing = _editorSessions.indexWhere(
      (item) => item.presentationId == session.presentationId,
    );
    if (existing >= 0) {
      _activeEditorIndex = existing;
      notifyListeners();
      return;
    }
    _editorSessions = [..._editorSessions, session];
    _activeEditorIndex = _editorSessions.length - 1;
    notifyListeners();
  }

  Future<void> _loadMembersForSelection(
    BrowserObjectEntry entry, {
    required String? selectedPropertyKey,
    required String? selectedVerbKey,
  }) async {
    _selectedObject = entry;
    _selectedPropertyKey = selectedPropertyKey;
    _selectedVerbKey = selectedVerbKey;
    _loadingMembers = true;
    _error = null;
    notifyListeners();

    try {
      final propsReply = await api.getProperties(
        authToken: authToken,
        objectCurie: entry.objectCurie,
      );
      final verbsReply = await api.getVerbs(
        authToken: authToken,
        objectCurie: entry.objectCurie,
      );

      _properties = [
        for (final prop
            in propsReply.properties ?? const <moor_common.PropInfo>[])
          _toPropertyEntry(prop),
      ];
      _verbs = _buildVerbEntries(
        verbsReply.verbs ?? const <moor_common.VerbInfo>[],
      );

      if (_selectedPropertyKey != null &&
          !_properties.any(
            (prop) => propertyKey(prop) == _selectedPropertyKey,
          )) {
        _selectedPropertyKey = null;
      }
      if (_selectedVerbKey != null &&
          !_verbs.any((verb) => verbKey(verb) == _selectedVerbKey)) {
        _selectedVerbKey = null;
      }

      _loadingMembers = false;
      notifyListeners();
    } on Object catch (e) {
      _loadingMembers = false;
      _error = '$e';
      notifyListeners();
    }
  }
}
