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
import 'package:meadow_flutter/moor/object_browser_controller.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';

class ObjectBrowserSheet extends StatefulWidget {
  final ObjectBrowserController controller;
  final SessionEditorPresenter editorPresenter;

  const ObjectBrowserSheet({
    super.key,
    required this.controller,
    required this.editorPresenter,
  });

  @override
  State<ObjectBrowserSheet> createState() => _ObjectBrowserSheetState();
}

class _ObjectBrowserSheetState extends State<ObjectBrowserSheet> {
  static const _splitterHeight = 14.0;
  static const _minTopHeight = 220.0;
  static const _minBottomHeight = 180.0;

  double _topPaneFraction = 0.62;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
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
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            '$count',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: headerAction,
                  ),
                ),
              ],
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

  Widget _buildInheritedHeader(String objectCurie) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'from ${_formatObjectRef(objectCurie)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.surface,
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
              itemCount: widget.controller.filteredObjects.length,
              itemBuilder: (context, index) {
                final entry = widget.controller.filteredObjects[index];
                final isSelected = entry.objectCurie == selected?.objectCurie;
                final flags = _formatFlags(entry.flags);
                return ListTile(
                  selected: isSelected,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    _formatObjectLabel(entry),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  trailing: flags.isEmpty
                      ? null
                      : Text(
                          flags,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                  onTap: () {
                    widget.controller.selectObject(entry);
                  },
                );
              },
            ),
    );
  }

  Widget _buildPropertiesPane() {
    final grouped = _groupedProperties();
    final selectedObject = widget.controller.selectedObject;
    return _buildPane(
      title: 'PROPERTIES',
      count: widget.controller.filteredProperties.length,
      headerAction: const FilledButton.tonal(
        onPressed: null,
        child: Text('+ Add'),
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
              children: [
                for (final group in grouped) ...[
                  if (group.key != selectedObject.objectCurie)
                    _buildInheritedHeader(group.key),
                  for (final property in group.value)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        property.name,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: Text(
                        _formatPropertyFlags(property),
                        style: const TextStyle(fontFamily: 'monospace'),
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
    return _buildPane(
      title: 'VERBS',
      count: widget.controller.filteredVerbs.length,
      headerAction: const Wrap(
        spacing: 8,
        children: [
          FilledButton.tonal(
            onPressed: null,
            child: Text('Run Tests'),
          ),
          FilledButton.tonal(
            onPressed: null,
            child: Text('+ Add'),
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
              children: [
                for (final group in grouped) ...[
                  if (group.key != selectedObject.objectCurie)
                    _buildInheritedHeader(group.key),
                  for (final verb in group.value)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        verb.names.join(' '),
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: Text(
                        _formatVerbFlags(verb),
                        style: const TextStyle(fontFamily: 'monospace'),
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

  Widget _buildBrowserGrid() {
    return Row(
      children: [
        Expanded(child: _buildObjectsPane()),
        const SizedBox(width: 12),
        Expanded(child: _buildPropertiesPane()),
        const SizedBox(width: 12),
        Expanded(child: _buildVerbsPane()),
      ],
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
    if (sessions.isEmpty) {
      return _buildBrowserGrid();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final usableHeight = constraints.maxHeight - _splitterHeight;
        if (usableHeight <= (_minTopHeight + _minBottomHeight)) {
          return Column(
            children: [
              Expanded(child: _buildBrowserGrid()),
              _buildHorizontalSplitter(constraints.maxHeight),
              Expanded(
                child: SessionEditorDock(
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
                ),
              ),
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
              child: SessionEditorDock(
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
              ),
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
            tooltip: widget.controller.showInheritedProperties
                ? 'Hide inherited properties'
                : 'Show inherited properties',
            onPressed: widget.controller.toggleInheritedProperties,
            icon: Icon(
              widget.controller.showInheritedProperties
                  ? Icons.account_tree
                  : Icons.account_tree_outlined,
            ),
          ),
          IconButton(
            tooltip: widget.controller.showInheritedVerbs
                ? 'Hide inherited verbs'
                : 'Show inherited verbs',
            onPressed: widget.controller.toggleInheritedVerbs,
            icon: Icon(
              widget.controller.showInheritedVerbs
                  ? Icons.functions
                  : Icons.functions_outlined,
            ),
          ),
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
