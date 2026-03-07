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
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/widgets/room_snapshot_widget.dart';

class SessionDockItemCard extends StatelessWidget {
  final DockItem item;
  final bool monospaceNarrative;
  final Future<void> Function(String presentationId) onDismissPresentation;
  final Future<void> Function(String objectCurie) onInspect;
  final ValueChanged<String> onSendCommand;
  final LinkTapHandler? onLinkTap;

  const SessionDockItemCard({
    super.key,
    required this.item,
    required this.monospaceNarrative,
    required this.onDismissPresentation,
    required this.onInspect,
    required this.onSendCommand,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final panelTitle = item is PresentationModel
        ? ((((item as PresentationModel).attrs['title'] ?? '')
                  .trim()
                  .isNotEmpty)
              ? (item as PresentationModel).attrs['title']!
              : item.id)
        : item.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        container: true,
        label: item is RoomSnapshotDockItem
            ? 'Dock panel: room snapshot'
            : 'Dock panel: $panelTitle',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: switch (item) {
            RoomSnapshotDockItem(:final snapshot) => RoomSnapshotWidget(
              snapshot: snapshot,
              onCommand: onSendCommand,
              onInspect: (obj) => onInspect(obj.curie),
            ),
            PresentationModel() => _PresentationCardBody(
              presentation: item as PresentationModel,
              monospaceNarrative: monospaceNarrative,
              onDismissPresentation: onDismissPresentation,
              onLinkTap: onLinkTap,
            ),
          },
        ),
      ),
    );
  }
}

class _PresentationCardBody extends StatelessWidget {
  final PresentationModel presentation;
  final bool monospaceNarrative;
  final Future<void> Function(String presentationId) onDismissPresentation;
  final LinkTapHandler? onLinkTap;

  const _PresentationCardBody({
    required this.presentation,
    required this.monospaceNarrative,
    required this.onDismissPresentation,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                (presentation.attrs['title'] ?? '').trim().isNotEmpty
                    ? presentation.attrs['title']!
                    : presentation.id,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Close panel',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await onDismissPresentation(presentation.id);
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ContentRenderer(
          content: [presentation.content],
          contentType: normalizeContentType(presentation.contentType),
          isStale: false,
          onLinkTap: onLinkTap,
          monospace:
              presentation.attrs['kind'] == 'debug_output' ||
              monospaceNarrative,
        ),
      ],
    );
  }
}
