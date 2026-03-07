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

class SessionEditorDock extends StatelessWidget {
  final List<EditorSession> sessions;
  final int activeIndex;
  final ValueChanged<int> onSelectIndex;
  final Future<void> Function(EditorSession session) onCloseSession;
  final Future<void> Function(EditorSession session) onOpenFullscreen;
  final Widget Function(EditorSession session) paneBuilder;

  const SessionEditorDock({
    super.key,
    required this.sessions,
    required this.activeIndex,
    required this.onSelectIndex,
    required this.onCloseSession,
    required this.onOpenFullscreen,
    required this.paneBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }

    final safeActiveIndex = (activeIndex >= 0 && activeIndex < sessions.length)
        ? activeIndex
        : 0;
    final active = sessions[safeActiveIndex];

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 10, 12, 10),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < sessions.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(
                                sessions[i].title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: i == safeActiveIndex,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                onSelectIndex(i);
                              },
                              onDeleted: () async {
                                await onCloseSession(sessions[i]);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: () async {
                    await onOpenFullscreen(active);
                  },
                  icon: const Icon(Icons.open_in_full),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () async {
                    await onCloseSession(active);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: IndexedStack(
              index: safeActiveIndex,
              children: [
                for (final session in sessions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: paneBuilder(session),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
