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
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/object_browser_controller.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';

class ObjectBrowserSheet extends StatefulWidget {
  final ObjectBrowserController controller;
  final SessionEditorPresenter editorPresenter;
  final String currentPlayerCurie;
  final int currentPlayerFlags;

  const ObjectBrowserSheet({
    super.key,
    required this.controller,
    required this.editorPresenter,
    required this.currentPlayerCurie,
    required this.currentPlayerFlags,
  });

  @override
  State<ObjectBrowserSheet> createState() => _ObjectBrowserSheetState();
}

class _ObjectBrowserSheetState extends State<ObjectBrowserSheet> {
  static const _splitterHeight = 14.0;
  static const _minTopHeight = 220.0;
  static const _minBottomHeight = 180.0;

  double _topPaneFraction = 0.62;
  late final ScrollController _objectsScrollController = ScrollController();
  late final ScrollController _propertiesScrollController = ScrollController();
  late final ScrollController _verbsScrollController = ScrollController();

  MoorHttpApi get _api => MoorHttpApi(widget.editorPresenter.baseUri);
  bool get _isWizard => (widget.currentPlayerFlags & (1 << 2)) != 0;

  bool _canEditOwner(String ownerCurie) {
    return _isWizard || ownerCurie == widget.currentPlayerCurie;
  }

  bool _canEditVerbMetadata(BrowserVerbEntry verb) {
    final selectedObjectCurie = widget.controller.selectedObject?.objectCurie;
    if (selectedObjectCurie == null ||
        verb.locationCurie != selectedObjectCurie) {
      return false;
    }
    return _canEditOwner(verb.ownerCurie);
  }

  bool _canAddMembers(BrowserObjectEntry object) {
    return _canEditOwner(object.ownerCurie);
  }

  bool _canDeleteProperty(BrowserPropertyEntry property) {
    final selectedObjectCurie = widget.controller.selectedObject?.objectCurie;
    if (selectedObjectCurie == null ||
        property.definerCurie != selectedObjectCurie) {
      return false;
    }
    return _canEditOwner(property.ownerCurie);
  }

  bool _canDeleteVerb(BrowserVerbEntry verb) {
    return _canEditVerbMetadata(verb);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.load();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    widget.controller.dispose();
    _objectsScrollController.dispose();
    _propertiesScrollController.dispose();
    _verbsScrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _updateTopPaneFraction(double dy, double totalHeight) {
    final usableHeight = totalHeight - _splitterHeight;
    if (usableHeight <= (_minTopHeight + _minBottomHeight)) {
      return;
    }
    final nextTopHeight = (_topPaneFraction * usableHeight) + dy;
    final clampedTopHeight = nextTopHeight.clamp(
      _minTopHeight,
      usableHeight - _minBottomHeight,
    );
    setState(() {
      _topPaneFraction = clampedTopHeight / usableHeight;
    });
  }

  String _formatObjectLabel(BrowserObjectEntry entry) {
    final title = entry.name.trim();
    final objectRef = _formatObjectRef(entry.objectCurie);
    if (title.isEmpty) {
      return objectRef;
    }
    return '$title  $objectRef';
  }

  String _formatObjectRef(String curie) {
    return MoorObj.parse(curie)?.toLiteral() ?? curie;
  }

  String _formatFlags(int flags) {
    final parts = <String>[];
    if ((flags & (1 << 0)) != 0) parts.add('u');
    if ((flags & (1 << 1)) != 0) parts.add('p');
    if ((flags & (1 << 2)) != 0) parts.add('w');
    if ((flags & (1 << 4)) != 0) parts.add('r');
    if ((flags & (1 << 5)) != 0) parts.add('W');
    if ((flags & (1 << 7)) != 0) parts.add('f');
    return parts.join();
  }

  bool _flagEnabled(int flags, int bit) => (flags & (1 << bit)) != 0;

  String _normalizeObjectExpr(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return MoorObj.parse(trimmed)?.toLiteral() ?? trimmed;
  }

  String _escapeMooString(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }

  MoorVar? _mapLookup(MoorVar value, String key) {
    final map = value.asMap();
    if (map == null) {
      return null;
    }
    for (final entry in map.pairs.entries) {
      if (entry.key.toKey() == key) {
        return entry.value;
      }
    }
    return null;
  }

  String? _evalErrorMessage(MoorVar value) {
    final error = _mapLookup(value, 'error');
    if (error == null) {
      return null;
    }
    final msg = _mapLookup(error, 'msg')?.asString();
    if (msg != null && msg.isNotEmpty) {
      return msg;
    }
    return error.asString();
  }

  Future<MoorVar> _runEval(String expression) async {
    final result = await _api.performEval(
      authToken: widget.editorPresenter.authToken,
      expression: expression,
    );
    final errorMessage = _evalErrorMessage(result);
    if (errorMessage != null && errorMessage.isNotEmpty) {
      throw Exception(errorMessage);
    }
    return result;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  Future<void> _showEditObjectDialog(BrowserObjectEntry object) async {
    final nameController = TextEditingController(text: object.name);
    final ownerController = TextEditingController(
      text: _formatObjectRef(object.ownerCurie),
    );
    var user = _flagEnabled(object.flags, 0);
    var programmer = _flagEnabled(object.flags, 1);
    var wizard = _flagEnabled(object.flags, 2);
    var readable = _flagEnabled(object.flags, 4);
    var writable = _flagEnabled(object.flags, 5);
    var fertile = _flagEnabled(object.flags, 7);
    var saving = false;
    String? errorText;
    final canEditObject = _canEditOwner(object.ownerCurie);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canEditObject) {
                setDialogState(() {
                  errorText =
                      'Only the owner or a wizard can edit this object.';
                });
                return;
              }
              final objectExpr = _normalizeObjectExpr(object.objectCurie);
              final ownerExpr = _normalizeObjectExpr(ownerController.text);
              if (_isWizard && ownerExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Owner cannot be empty.';
                });
                return;
              }
              final assignments = <String>[];
              final trimmedName = nameController.text.trim();
              if (trimmedName != object.name.trim()) {
                assignments.add(
                  '$objectExpr.name = "${_escapeMooString(trimmedName)}"',
                );
              }
              if (_isWizard &&
                  ownerExpr != _formatObjectRef(object.ownerCurie)) {
                assignments.add('$objectExpr.owner = $ownerExpr');
              }
              if (programmer != _flagEnabled(object.flags, 1)) {
                assignments.add(
                  '$objectExpr.programmer = ${programmer ? 1 : 0}',
                );
              }
              if (wizard != _flagEnabled(object.flags, 2)) {
                assignments.add('$objectExpr.wizard = ${wizard ? 1 : 0}');
              }
              if (readable != _flagEnabled(object.flags, 4)) {
                assignments.add('$objectExpr.r = ${readable ? 1 : 0}');
              }
              if (writable != _flagEnabled(object.flags, 5)) {
                assignments.add('$objectExpr.w = ${writable ? 1 : 0}');
              }
              if (fertile != _flagEnabled(object.flags, 7)) {
                assignments.add('$objectExpr.f = ${fertile ? 1 : 0}');
              }
              if (assignments.isEmpty &&
                  user == _flagEnabled(object.flags, 0)) {
                Navigator.of(dialogContext).pop();
                return;
              }

              setDialogState(() {
                saving = true;
                errorText = null;
              });
              try {
                if (user != _flagEnabled(object.flags, 0)) {
                  await _runEval(
                    'return set_player_flag($objectExpr, ${user ? 1 : 0});',
                  );
                }
                if (assignments.isNotEmpty) {
                  await _runEval('${assignments.join('; ')}; return 1;');
                }
                await widget.controller.load();
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Object metadata updated');
              } on Object catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text('Edit ${_formatObjectRef(object.objectCurie)}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        enabled: !saving && canEditObject,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_isWizard) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: ownerController,
                          enabled: !saving && canEditObject,
                          decoration: const InputDecoration(
                            labelText: 'Owner (wizard only)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Flags',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Player'),
                        value: user,
                        onChanged: saving || !canEditObject || !_isWizard
                            ? null
                            : (value) =>
                                  setDialogState(() => user = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Programmer'),
                        value: programmer,
                        onChanged: saving || !canEditObject || !_isWizard
                            ? null
                            : (value) => setDialogState(
                                () => programmer = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Wizard'),
                        value: wizard,
                        onChanged: saving || !canEditObject || !_isWizard
                            ? null
                            : (value) =>
                                  setDialogState(() => wizard = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Readable'),
                        value: readable,
                        onChanged: saving || !canEditObject
                            ? null
                            : (value) => setDialogState(
                                () => readable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Writable'),
                        value: writable,
                        onChanged: saving || !canEditObject
                            ? null
                            : (value) => setDialogState(
                                () => writable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Fertile'),
                        value: fertile,
                        onChanged: saving || !canEditObject
                            ? null
                            : (value) => setDialogState(
                                () => fertile = value ?? false,
                              ),
                      ),
                      if (!canEditObject) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Only the owner or a wizard can edit this object.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || !canEditObject ? null : submit,
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    ownerController.dispose();
  }

  Future<void> _showEditPropertyDialog(BrowserPropertyEntry property) async {
    final ownerController = TextEditingController(
      text: _formatObjectRef(property.ownerCurie),
    );
    var readable = property.readable;
    var writable = property.writable;
    var chown = property.chown;
    var saving = false;
    String? errorText;
    final canEditProperty = _canEditOwner(property.ownerCurie);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canEditProperty) {
                setDialogState(() {
                  errorText =
                      'Only the property owner or a wizard can edit this property.';
                });
                return;
              }
              final ownerExpr = _normalizeObjectExpr(ownerController.text);
              if (ownerExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Owner cannot be empty.';
                });
                return;
              }
              final perms = [
                if (readable) 'r',
                if (writable) 'w',
                if (chown) 'c',
              ].join();
              setDialogState(() {
                saving = true;
                errorText = null;
              });
              try {
                final objectExpr = _normalizeObjectExpr(property.definerCurie);
                await _runEval(
                  'return set_property_info($objectExpr, \'${property.name}, {$ownerExpr, "$perms"});',
                );
                await widget.controller.refreshSelectedObject();
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Property metadata updated');
              } on Object catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text('Edit property ${property.name}'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: ownerController,
                        enabled: !saving && canEditProperty,
                        decoration: const InputDecoration(
                          labelText: 'Owner (MOO expression)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Permissions',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Readable'),
                        value: readable,
                        onChanged: saving || !canEditProperty
                            ? null
                            : (value) => setDialogState(
                                () => readable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Writable'),
                        value: writable,
                        onChanged: saving || !canEditProperty
                            ? null
                            : (value) => setDialogState(
                                () => writable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Chown'),
                        value: chown,
                        onChanged: saving || !canEditProperty
                            ? null
                            : (value) =>
                                  setDialogState(() => chown = value ?? false),
                      ),
                      if (!canEditProperty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Only the property owner or a wizard can edit this property.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || !canEditProperty ? null : submit,
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    ownerController.dispose();
  }

  Future<void> _showEditVerbDialog(BrowserVerbEntry verb) async {
    final ownerController = TextEditingController(
      text: _formatObjectRef(verb.ownerCurie),
    );
    final namesController = TextEditingController(text: verb.names.join(' '));
    const dobjOptions = <String>['none', 'any', 'this'];
    const iobjOptions = <String>['none', 'any', 'this'];
    const prepOptions = <String>[
      'none',
      'any',
      'with',
      'using',
      'at',
      'to',
      'in front of',
      'in',
      'on top of',
      'on',
      'onto',
      'upon',
      'out of',
      'from inside',
      'from',
      'over',
      'through',
      'under',
      'underneath',
      'beneath',
      'behind',
      'beside',
      'for',
      'is',
      'as',
      'off of',
      'off',
    ];
    var selectedDobj = dobjOptions.contains(verb.dobj) ? verb.dobj : 'none';
    var selectedPrep = prepOptions.contains(verb.prep) ? verb.prep : 'none';
    var selectedIobj = iobjOptions.contains(verb.iobj) ? verb.iobj : 'none';
    var readable = verb.readable;
    var writable = verb.writable;
    var executable = verb.executable;
    var debug = verb.debug;
    var saving = false;
    String? errorText;
    final canEditVerb = _canEditVerbMetadata(verb);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canEditVerb) {
                setDialogState(() {
                  errorText =
                      'Only the verb owner or a wizard can edit this verb.';
                });
                return;
              }
              final objectExpr = _normalizeObjectExpr(verb.locationCurie);
              final ownerExpr = _normalizeObjectExpr(ownerController.text);
              final names = namesController.text.trim();
              final dobj = selectedDobj;
              final prep = selectedPrep;
              final iobj = selectedIobj;
              if (ownerExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Owner cannot be empty.';
                });
                return;
              }
              if (names.isEmpty) {
                setDialogState(() {
                  errorText = 'Names cannot be empty.';
                });
                return;
              }

              final perms = [
                if (readable) 'r',
                if (writable) 'w',
                if (executable) 'x',
                if (debug) 'd',
              ].join();
              final originalNames = verb.names.join(' ');
              final statements = <String>[];
              if (ownerExpr != _formatObjectRef(verb.ownerCurie) ||
                  names != originalNames ||
                  readable != verb.readable ||
                  writable != verb.writable ||
                  executable != verb.executable ||
                  debug != verb.debug) {
                statements.add(
                  'set_verb_info($objectExpr, "${_escapeMooString(verb.names.first)}", {$ownerExpr, "$perms", "${_escapeMooString(names)}"})',
                );
              }
              if (dobj != verb.dobj || prep != verb.prep || iobj != verb.iobj) {
                statements.add(
                  'set_verb_args($objectExpr, "${_escapeMooString(verb.names.first)}", {"${_escapeMooString(dobj)}", "${_escapeMooString(prep)}", "${_escapeMooString(iobj)}"})',
                );
              }
              if (statements.isEmpty) {
                Navigator.of(dialogContext).pop();
                return;
              }

              setDialogState(() {
                saving = true;
                errorText = null;
              });
              try {
                await _runEval('${statements.join('; ')}; return 1;');
                await widget.controller.refreshSelectedObject();
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Verb metadata updated');
              } on Object catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text('Edit verb ${verb.names.join(' ')}'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: namesController,
                        enabled: !saving && canEditVerb,
                        decoration: const InputDecoration(
                          labelText: 'Names',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: ownerController,
                        enabled: !saving && canEditVerb,
                        decoration: const InputDecoration(
                          labelText: 'Owner (MOO expression)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Permissions',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Readable'),
                        value: readable,
                        onChanged: saving || !canEditVerb
                            ? null
                            : (value) => setDialogState(
                                () => readable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Writable'),
                        value: writable,
                        onChanged: saving || !canEditVerb
                            ? null
                            : (value) => setDialogState(
                                () => writable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Executable'),
                        value: executable,
                        onChanged: saving || !canEditVerb
                            ? null
                            : (value) => setDialogState(
                                () => executable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Debug'),
                        value: debug,
                        onChanged: saving || !canEditVerb
                            ? null
                            : (value) =>
                                  setDialogState(() => debug = value ?? false),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Argspec',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedDobj,
                              decoration: const InputDecoration(
                                labelText: 'Direct object',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in dobjOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canEditVerb
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedDobj = value;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedPrep,
                              decoration: const InputDecoration(
                                labelText: 'Preposition',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in prepOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canEditVerb
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedPrep = value;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedIobj,
                              decoration: const InputDecoration(
                                labelText: 'Indirect object',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in iobjOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canEditVerb
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedIobj = value;
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                      if (!canEditVerb) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Only the verb owner or a wizard can edit this verb.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || !canEditVerb ? null : submit,
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    ownerController.dispose();
    namesController.dispose();
  }

  Future<void> _showAddPropertyDialog() async {
    final object = widget.controller.selectedObject;
    if (object == null) {
      return;
    }
    final nameController = TextEditingController();
    final valueController = TextEditingController(text: '0');
    final ownerController = TextEditingController(
      text: _formatObjectRef(widget.currentPlayerCurie),
    );
    var readable = true;
    var writable = true;
    var chown = false;
    var saving = false;
    String? errorText;
    final canAdd = _canAddMembers(object);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canAdd) {
                setDialogState(() {
                  errorText =
                      'Only the owner or a wizard can add properties here.';
                });
                return;
              }
              final name = nameController.text.trim();
              if (name.isEmpty) {
                setDialogState(() {
                  errorText = 'Property name cannot be empty.';
                });
                return;
              }
              final valueExpr = valueController.text.trim();
              if (valueExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Value expression cannot be empty.';
                });
                return;
              }
              final ownerExpr = _isWizard
                  ? _normalizeObjectExpr(ownerController.text)
                  : _formatObjectRef(widget.currentPlayerCurie);
              if (ownerExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Owner cannot be empty.';
                });
                return;
              }
              final perms = [
                if (readable) 'r',
                if (writable) 'w',
                if (chown) 'c',
              ].join();

              setDialogState(() {
                saving = true;
                errorText = null;
              });
              try {
                final objectExpr = _normalizeObjectExpr(object.objectCurie);
                await _runEval(
                  'return add_property($objectExpr, "${_escapeMooString(name)}", $valueExpr, {$ownerExpr, "$perms"});',
                );
                final propertyKey =
                    '${object.objectCurie}:${nameController.text.trim()}';
                await widget.controller.refreshSelectedObjectWithSelection(
                  selectedPropertyKey: propertyKey,
                );
                final addedProperty = widget.controller.properties
                    .cast<BrowserPropertyEntry?>()
                    .firstWhere(
                      (entry) =>
                          entry?.name == name &&
                          entry?.definerCurie == object.objectCurie,
                      orElse: () => null,
                    );
                if (addedProperty != null) {
                  widget.controller.selectProperty(addedProperty);
                }
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Property "$name" added');
              } on Object catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text(
                'Add property to ${_formatObjectRef(object.objectCurie)}',
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        enabled: !saving && canAdd,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: valueController,
                        enabled: !saving && canAdd,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Initial value (MOO expression)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_isWizard) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: ownerController,
                          enabled: !saving && canAdd,
                          decoration: const InputDecoration(
                            labelText: 'Owner (wizard only)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Permissions',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Readable'),
                        value: readable,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) => setDialogState(
                                () => readable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Writable'),
                        value: writable,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) => setDialogState(
                                () => writable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Chown'),
                        value: chown,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) =>
                                  setDialogState(() => chown = value ?? false),
                      ),
                      if (!canAdd) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Only the owner or a wizard can add properties here.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || !canAdd ? null : submit,
                  child: Text(saving ? 'Adding…' : 'Add Property'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    valueController.dispose();
    ownerController.dispose();
  }

  Future<void> _showDeletePropertyDialog(BrowserPropertyEntry property) async {
    final canDelete = _canDeleteProperty(property);
    var deleting = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canDelete) {
                setDialogState(() {
                  errorText =
                      'Only local properties owned by you, or properties deleted as a wizard, can be removed.';
                });
                return;
              }
              setDialogState(() {
                deleting = true;
                errorText = null;
              });
              try {
                final objectExpr = _normalizeObjectExpr(property.definerCurie);
                await _runEval(
                  'return delete_property($objectExpr, "${_escapeMooString(property.name)}");',
                );
                widget.controller.closeSessionByPresentationId(
                  ObjectBrowserController.propertyPresentationId(property),
                );
                widget.controller.clearSelectedProperty();
                await widget.controller.refreshSelectedObjectWithSelection(
                  selectedVerbKey: widget.controller.selectedVerbKey,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Property "${property.name}" deleted');
              } on Object catch (e) {
                setDialogState(() {
                  deleting = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text('Delete property ${property.name}?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will remove ${property.name} from ${_formatObjectRef(property.definerCurie)}.',
                    ),
                    if (!canDelete) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Only local properties owned by you, or properties deleted as a wizard, can be removed.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: deleting || !canDelete ? null : submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: Text(deleting ? 'Deleting…' : 'Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddVerbDialog() async {
    final object = widget.controller.selectedObject;
    if (object == null) {
      return;
    }
    final namesController = TextEditingController();
    final ownerController = TextEditingController(
      text: _formatObjectRef(widget.currentPlayerCurie),
    );
    const dobjOptions = <String>['none', 'any', 'this'];
    const iobjOptions = <String>['none', 'any', 'this'];
    const prepOptions = <String>[
      'none',
      'any',
      'with',
      'using',
      'at',
      'to',
      'in front of',
      'in',
      'on top of',
      'on',
      'onto',
      'upon',
      'out of',
      'from inside',
      'from',
      'over',
      'through',
      'under',
      'underneath',
      'beneath',
      'behind',
      'beside',
      'for',
      'is',
      'as',
      'off of',
      'off',
    ];
    var selectedDobj = 'this';
    var selectedPrep = 'none';
    var selectedIobj = 'this';
    var readable = true;
    var writable = false;
    var executable = true;
    var debug = true;
    var saving = false;
    String? errorText;
    final canAdd = _canAddMembers(object);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canAdd) {
                setDialogState(() {
                  errorText = 'Only the owner or a wizard can add verbs here.';
                });
                return;
              }
              final names = namesController.text.trim();
              if (names.isEmpty) {
                setDialogState(() {
                  errorText = 'Verb names cannot be empty.';
                });
                return;
              }
              final ownerExpr = _isWizard
                  ? _normalizeObjectExpr(ownerController.text)
                  : _formatObjectRef(widget.currentPlayerCurie);
              if (ownerExpr.isEmpty) {
                setDialogState(() {
                  errorText = 'Owner cannot be empty.';
                });
                return;
              }
              final perms = [
                if (readable) 'r',
                if (writable) 'w',
                if (executable) 'x',
                if (debug) 'd',
              ].join();

              setDialogState(() {
                saving = true;
                errorText = null;
              });
              try {
                final objectExpr = _normalizeObjectExpr(object.objectCurie);
                await _runEval(
                  'return add_verb($objectExpr, {$ownerExpr, "$perms", "${_escapeMooString(names)}"}, {"${_escapeMooString(selectedDobj)}", "${_escapeMooString(selectedPrep)}", "${_escapeMooString(selectedIobj)}"});',
                );
                await widget.controller.refreshSelectedObject();
                final addedVerb = widget.controller.verbs
                    .cast<BrowserVerbEntry?>()
                    .firstWhere(
                      (entry) =>
                          entry != null &&
                          entry.locationCurie == object.objectCurie &&
                          entry.names.join(' ') == names,
                      orElse: () => null,
                    );
                if (addedVerb != null) {
                  widget.controller.selectVerb(addedVerb);
                }
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Verb "$names" added');
              } on Object catch (e) {
                setDialogState(() {
                  saving = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text(
                'Add verb to ${_formatObjectRef(object.objectCurie)}',
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: namesController,
                        enabled: !saving && canAdd,
                        decoration: const InputDecoration(
                          labelText: 'Names',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_isWizard) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: ownerController,
                          enabled: !saving && canAdd,
                          decoration: const InputDecoration(
                            labelText: 'Owner (wizard only)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Permissions',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Readable'),
                        value: readable,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) => setDialogState(
                                () => readable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Writable'),
                        value: writable,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) => setDialogState(
                                () => writable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Executable'),
                        value: executable,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) => setDialogState(
                                () => executable = value ?? false,
                              ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Debug'),
                        value: debug,
                        onChanged: saving || !canAdd
                            ? null
                            : (value) =>
                                  setDialogState(() => debug = value ?? false),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Argspec',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedDobj,
                              decoration: const InputDecoration(
                                labelText: 'Direct object',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in dobjOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canAdd
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedDobj = value;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedPrep,
                              decoration: const InputDecoration(
                                labelText: 'Preposition',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in prepOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canAdd
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedPrep = value;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedIobj,
                              decoration: const InputDecoration(
                                labelText: 'Indirect object',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final option in iobjOptions)
                                  DropdownMenuItem<String>(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: saving || !canAdd
                                  ? null
                                  : (value) {
                                      if (value == null) {
                                        return;
                                      }
                                      setDialogState(() {
                                        selectedIobj = value;
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                      if (!canAdd) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Only the owner or a wizard can add verbs here.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving || !canAdd ? null : submit,
                  child: Text(saving ? 'Adding…' : 'Add Verb'),
                ),
              ],
            );
          },
        );
      },
    );

    namesController.dispose();
    ownerController.dispose();
  }

  Future<void> _showDeleteVerbDialog(BrowserVerbEntry verb) async {
    final canDelete = _canDeleteVerb(verb);
    var deleting = false;
    String? errorText;
    final primaryName = verb.names.isEmpty ? '(unnamed)' : verb.names.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!canDelete) {
                setDialogState(() {
                  errorText =
                      'Only local verbs owned by you, or verbs deleted as a wizard, can be removed.';
                });
                return;
              }
              setDialogState(() {
                deleting = true;
                errorText = null;
              });
              try {
                final objectExpr = _normalizeObjectExpr(verb.locationCurie);
                await _runEval(
                  'return delete_verb($objectExpr, "${_escapeMooString(primaryName)}");',
                );
                widget.controller.closeSessionByPresentationId(
                  ObjectBrowserController.verbPresentationId(verb),
                );
                widget.controller.clearSelectedVerb();
                await widget.controller.refreshSelectedObjectWithSelection(
                  selectedPropertyKey: widget.controller.selectedPropertyKey,
                );
                if (!dialogContext.mounted) {
                  return;
                }
                Navigator.of(dialogContext).pop();
                _showSnackBar('Verb "$primaryName" deleted');
              } on Object catch (e) {
                setDialogState(() {
                  deleting = false;
                  errorText = '$e';
                });
              }
            }

            return AlertDialog(
              title: Text('Delete verb $primaryName?'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will remove $primaryName from ${_formatObjectRef(verb.locationCurie)}.',
                    ),
                    if (!canDelete) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Only local verbs owned by you, or verbs deleted as a wizard, can be removed.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: deleting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: deleting || !canDelete ? null : submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  child: Text(deleting ? 'Deleting…' : 'Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatPropertyFlags(BrowserPropertyEntry property) {
    final parts = <String>[];
    if (property.readable) parts.add('r');
    if (property.writable) parts.add('w');
    if (property.chown) parts.add('c');
    return parts.join();
  }

  String _formatVerbFlags(BrowserVerbEntry verb) {
    final parts = <String>[];
    if (verb.readable) parts.add('r');
    if (verb.writable) parts.add('w');
    if (verb.executable) parts.add('x');
    if (verb.debug) parts.add('d');
    return parts.join();
  }

  List<MapEntry<String, List<BrowserPropertyEntry>>> _groupedProperties() {
    final groups = <String, List<BrowserPropertyEntry>>{};
    for (final property in widget.controller.filteredProperties) {
      groups.putIfAbsent(property.definerCurie, () => <BrowserPropertyEntry>[]);
      groups[property.definerCurie]!.add(property);
    }
    return groups.entries.toList();
  }

  List<MapEntry<String, List<BrowserVerbEntry>>> _groupedVerbs() {
    final groups = <String, List<BrowserVerbEntry>>{};
    for (final verb in widget.controller.filteredVerbs) {
      groups.putIfAbsent(verb.locationCurie, () => <BrowserVerbEntry>[]);
      groups[verb.locationCurie]!.add(verb);
    }
    return groups.entries.toList();
  }

  Widget _buildPane({
    required String title,
    required int count,
    required Widget headerAction,
    required Widget filter,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useStackedHeader = constraints.maxWidth < 330;
                final titleRow = Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                );

                if (useStackedHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleRow,
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: headerAction,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: titleRow),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: headerAction,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: filter,
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildCountToggle({
    required bool active,
    required String activeTooltip,
    required String inactiveTooltip,
    required VoidCallback onPressed,
    required IconData activeIcon,
    required IconData inactiveIcon,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: active ? activeTooltip : inactiveTooltip,
      onPressed: onPressed,
      icon: Icon(active ? activeIcon : inactiveIcon),
    );
  }

  Widget _buildInheritedHeader(String objectCurie) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'from ${_formatObjectRef(objectCurie)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildObjectsPane() {
    final selected = widget.controller.selectedObject;
    return _buildPane(
      title: 'OBJECTS',
      count: widget.controller.filteredObjects.length,
      headerAction: const FilledButton.tonal(
        onPressed: null,
        child: Text('+ Add'),
      ),
      filter: TextField(
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Filter objects...',
          border: OutlineInputBorder(),
        ),
        onChanged: widget.controller.setObjectFilter,
      ),
      child: widget.controller.loadingObjects
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _objectsScrollController,
              itemCount: widget.controller.filteredObjects.length,
              itemBuilder: (context, index) {
                final theme = Theme.of(context);
                final entry = widget.controller.filteredObjects[index];
                final isSelected = entry.objectCurie == selected?.objectCurie;
                final flags = _formatFlags(entry.flags);
                return ListTile(
                  selected: isSelected,
                  selectedTileColor: isSelected
                      ? Color.lerp(
                          theme.colorScheme.surfaceContainerLow,
                          theme.colorScheme.primaryContainer,
                          0.55,
                        )
                      : null,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: Text(
                    _formatObjectLabel(entry),
                    style: const TextStyle(fontFamily: 'Comic Mono'),
                  ),
                  trailing: flags.isEmpty
                      ? null
                      : Text(
                          flags,
                          style: const TextStyle(fontFamily: 'Comic Mono'),
                        ),
                  onTap: () {
                    widget.controller.selectObject(entry);
                  },
                );
              },
            ),
    );
  }

  Widget _buildObjectsColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildObjectsPane()),
        const SizedBox(height: 12),
        _buildObjectInfoPanel(),
      ],
    );
  }

  Widget _buildPropertiesColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildPropertiesPane()),
        const SizedBox(height: 12),
        _buildPropertyInfoPanel(),
      ],
    );
  }

  Widget _buildPropertiesPane() {
    final grouped = _groupedProperties();
    final selectedObject = widget.controller.selectedObject;
    final canAdd = selectedObject != null && _canAddMembers(selectedObject);
    return _buildPane(
      title: 'PROPERTIES',
      count: widget.controller.filteredProperties.length,
      headerAction: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildCountToggle(
            active: widget.controller.showInheritedProperties,
            activeTooltip: 'Hide inherited properties',
            inactiveTooltip: 'Show inherited properties',
            onPressed: widget.controller.toggleInheritedProperties,
            activeIcon: Icons.account_tree,
            inactiveIcon: Icons.account_tree_outlined,
          ),
          FilledButton.tonal(
            onPressed: canAdd ? _showAddPropertyDialog : null,
            child: const Text('+ Add'),
          ),
        ],
      ),
      filter: TextField(
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Filter properties...',
          border: OutlineInputBorder(),
        ),
        onChanged: widget.controller.setPropertyFilter,
      ),
      child: selectedObject == null
          ? const Center(child: Text('Select an object'))
          : ListView(
              controller: _propertiesScrollController,
              children: [
                for (final group in grouped) ...[
                  if (group.key != selectedObject.objectCurie)
                    _buildInheritedHeader(group.key),
                  for (final property in group.value)
                    ListTile(
                      selectedTileColor:
                          ObjectBrowserController.propertyKey(property) ==
                              widget.controller.selectedPropertyKey
                          ? Color.lerp(
                              Theme.of(context).colorScheme.surfaceContainerLow,
                              Theme.of(context).colorScheme.primaryContainer,
                              0.55,
                            )
                          : null,
                      selected:
                          ObjectBrowserController.propertyKey(property) ==
                          widget.controller.selectedPropertyKey,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      title: Text(
                        property.name,
                        style: const TextStyle(fontFamily: 'Comic Mono'),
                      ),
                      trailing: Text(
                        _formatPropertyFlags(property),
                        style: const TextStyle(fontFamily: 'Comic Mono'),
                      ),
                      onTap: () {
                        widget.controller.selectProperty(property);
                      },
                    ),
                ],
              ],
            ),
    );
  }

  Widget _buildVerbsPane() {
    final grouped = _groupedVerbs();
    final selectedObject = widget.controller.selectedObject;
    final canAdd = selectedObject != null && _canAddMembers(selectedObject);
    return _buildPane(
      title: 'VERBS',
      count: widget.controller.filteredVerbs.length,
      headerAction: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildCountToggle(
            active: widget.controller.showInheritedVerbs,
            activeTooltip: 'Hide inherited verbs',
            inactiveTooltip: 'Show inherited verbs',
            onPressed: widget.controller.toggleInheritedVerbs,
            activeIcon: Icons.functions,
            inactiveIcon: Icons.functions_outlined,
          ),
          const FilledButton.tonal(
            onPressed: null,
            child: Text('Run Tests'),
          ),
          FilledButton.tonal(
            onPressed: canAdd ? _showAddVerbDialog : null,
            child: const Text('+ Add'),
          ),
        ],
      ),
      filter: TextField(
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Filter verbs...',
          border: OutlineInputBorder(),
        ),
        onChanged: widget.controller.setVerbFilter,
      ),
      child: selectedObject == null
          ? const Center(child: Text('Select an object'))
          : ListView(
              controller: _verbsScrollController,
              children: [
                for (final group in grouped) ...[
                  if (group.key != selectedObject.objectCurie)
                    _buildInheritedHeader(group.key),
                  for (final verb in group.value)
                    ListTile(
                      selectedTileColor:
                          ObjectBrowserController.verbKey(verb) ==
                              widget.controller.selectedVerbKey
                          ? Color.lerp(
                              Theme.of(context).colorScheme.surfaceContainerLow,
                              Theme.of(context).colorScheme.primaryContainer,
                              0.55,
                            )
                          : null,
                      selected:
                          ObjectBrowserController.verbKey(verb) ==
                          widget.controller.selectedVerbKey,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      title: Text(
                        verb.names.join(' '),
                        style: const TextStyle(fontFamily: 'Comic Mono'),
                      ),
                      trailing: Text(
                        _formatVerbFlags(verb),
                        style: const TextStyle(fontFamily: 'Comic Mono'),
                      ),
                      onTap: () {
                        widget.controller.selectVerb(verb);
                      },
                    ),
                ],
              ],
            ),
    );
  }

  Widget _buildVerbsColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildVerbsPane()),
        const SizedBox(height: 12),
        _buildVerbInfoPanel(),
      ],
    );
  }

  Widget _buildBrowserGrid() {
    return Row(
      children: [
        Expanded(child: _buildObjectsColumn()),
        const SizedBox(width: 12),
        Expanded(child: _buildPropertiesColumn()),
        const SizedBox(width: 12),
        Expanded(child: _buildVerbsColumn()),
      ],
    );
  }

  Widget _buildInfoChip(String label, String value) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFamily: 'Comic Mono',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: value,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontFamily: 'Comic Mono',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObjectInfoPanel() {
    final object = widget.controller.selectedObject;
    if (object == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatObjectLabel(object),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _canEditOwner(object.ownerCurie)
                      ? 'Edit object metadata'
                      : 'Only the owner or a wizard can edit this object',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canEditOwner(object.ownerCurie)
                      ? () {
                          _showEditObjectDialog(object);
                        }
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildInfoChip('Parent', _formatObjectRef(object.parentCurie)),
                _buildInfoChip('Owner', _formatObjectRef(object.ownerCurie)),
                _buildInfoChip(
                  'Location',
                  _formatObjectRef(object.locationCurie),
                ),
                _buildInfoChip('Flags', _formatFlags(object.flags)),
                _buildMetricChip('Props', '${object.propertiesCount}'),
                _buildMetricChip('Verbs', '${object.verbsCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyInfoPanel() {
    final property = widget.controller.selectedProperty;
    if (property == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    property.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Comic Mono',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _canEditOwner(property.ownerCurie)
                      ? 'Edit property metadata'
                      : 'Only the owner or a wizard can edit this property',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canEditOwner(property.ownerCurie)
                      ? () {
                          _showEditPropertyDialog(property);
                        }
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: _canDeleteProperty(property)
                      ? 'Delete property'
                      : 'Only local properties owned by you, or properties deleted as a wizard, can be removed',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canDeleteProperty(property)
                      ? () {
                          _showDeletePropertyDialog(property);
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildInfoChip(
                  'Definer',
                  _formatObjectRef(property.definerCurie),
                ),
                _buildInfoChip('Owner', _formatObjectRef(property.ownerCurie)),
                _buildInfoChip(
                  'Location',
                  _formatObjectRef(property.locationCurie),
                ),
                _buildInfoChip('Flags', _formatPropertyFlags(property)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerbInfoPanel() {
    final verb = widget.controller.selectedVerb;
    if (verb == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final names = verb.names.isEmpty ? '(unnamed)' : verb.names.join(' ');
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    names,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Comic Mono',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _canEditVerbMetadata(verb)
                      ? 'Edit verb metadata'
                      : 'Only local verbs owned by you, or verbs edited as a wizard, can be changed',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canEditVerbMetadata(verb)
                      ? () {
                          _showEditVerbDialog(verb);
                        }
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: _canDeleteVerb(verb)
                      ? 'Delete verb'
                      : 'Only local verbs owned by you, or verbs deleted as a wizard, can be removed',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canDeleteVerb(verb)
                      ? () {
                          _showDeleteVerbDialog(verb);
                        }
                      : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildInfoChip(
                  'Location',
                  _formatObjectRef(verb.locationCurie),
                ),
                _buildInfoChip('Owner', _formatObjectRef(verb.ownerCurie)),
                _buildInfoChip('Flags', _formatVerbFlags(verb)),
                _buildInfoChip(
                  'Args',
                  '${verb.dobj} ${verb.prep} ${verb.iobj}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowerPane(List<EditorSession> sessions) {
    return sessions.isEmpty
        ? Card(
            margin: EdgeInsets.zero,
            child: Center(
              child: Text(
                'Select a property or verb to open an editor.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        : SessionEditorDock(
            sessions: sessions,
            activeIndex: widget.controller.activeEditorIndex,
            onSelectIndex: widget.controller.selectSessionIndex,
            onCloseSession: (session) async {
              widget.controller.closeSession(session);
            },
            onOpenFullscreen: (session) {
              return widget.editorPresenter.openFullscreen(
                context,
                session,
              );
            },
            paneBuilder: widget.editorPresenter.paneForSession,
          );
  }

  Widget _buildHorizontalSplitter(double totalHeight) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          _updateTopPaneFraction(details.delta.dy, totalHeight);
        },
        child: SizedBox(
          height: _splitterHeight,
          child: Center(
            child: Container(
              width: 72,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBodyContent(List<EditorSession> sessions) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableHeight = constraints.maxHeight - _splitterHeight;
        if (usableHeight <= (_minTopHeight + _minBottomHeight)) {
          return Column(
            children: [
              Expanded(child: _buildBrowserGrid()),
              _buildHorizontalSplitter(constraints.maxHeight),
              Expanded(child: _buildLowerPane(sessions)),
            ],
          );
        }

        final topHeight = (_topPaneFraction * usableHeight).clamp(
          _minTopHeight,
          usableHeight - _minBottomHeight,
        );
        final bottomHeight = usableHeight - topHeight;
        return Column(
          children: [
            SizedBox(
              height: topHeight,
              child: _buildBrowserGrid(),
            ),
            _buildHorizontalSplitter(constraints.maxHeight),
            SizedBox(
              height: bottomHeight,
              child: _buildLowerPane(sessions),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.controller.editorSessions;
    widget.editorPresenter.pruneSessions(sessions);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Browser'),
        actions: [
          IconButton(
            tooltip: 'Close object browser',
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (widget.controller.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(widget.controller.error!)),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildBodyContent(sessions)),
          ],
        ),
      ),
    );
  }
}
