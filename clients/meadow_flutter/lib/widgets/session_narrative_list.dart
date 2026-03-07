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
import 'package:meadow_flutter/moor/models.dart';

class SessionNarrativeList extends StatelessWidget {
  final List<NarrativeItem> items;
  final bool monospaceNarrative;
  final bool showNarrativeMeta;
  final String playerCurie;
  final ScrollController scrollController;
  final GlobalKey listKey;
  final Map<String, GlobalKey> messageKeys;
  final LinkTapHandler? onLinkTap;

  const SessionNarrativeList({
    super.key,
    required this.items,
    required this.monospaceNarrative,
    required this.showNarrativeMeta,
    required this.playerCurie,
    required this.scrollController,
    required this.listKey,
    required this.messageKeys,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupNarrativeItems(items);
    return SelectionArea(
      child: ListView.builder(
        key: listKey,
        controller: scrollController,
        itemCount: groups.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, idx) {
          final group = groups[idx];
          final first = group.first;
          final cs = Theme.of(context).colorScheme;

          Widget buildMessage(NarrativeItem item) {
            final key = messageKeys.putIfAbsent(item.id, GlobalKey.new);
            final ts = item.timestamp.toIso8601String().split('T').last;
            return Container(
              key: key,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showNarrativeMeta) ...[
                    Row(
                      children: [
                        Text(
                          ts,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: cs.outline,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.contentType,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: cs.outline,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  ContentRenderer(
                    content: item.content,
                    contentType: item.contentType,
                    isStale: false,
                    onLinkTap: onLinkTap,
                    monospace: monospaceNarrative,
                  ),
                ],
              ),
            );
          }

          final hint = first.presentationHint;
          final isInset = hint == 'inset';
          final isHintGroup =
              hint != null &&
              first.groupId != null &&
              group.every(
                (m) => m.presentationHint == hint && m.groupId == first.groupId,
              );

          final inner = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in group) buildMessage(item),
            ],
          );

          if (!isInset) {
            return inner;
          }

          if (group.length == 1 && !isHintGroup) {
            return inner;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Semantics(
              container: true,
              label: 'Inset',
              child: Card(
                elevation: 0,
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: cs.primary,
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: inner,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _sameActor(NarrativeItem a, NarrativeItem b) {
  final actorA = a.metadata?.actorCurie;
  final actorB = b.metadata?.actorCurie;
  if (actorA == null || actorB == null) {
    return true;
  }
  return actorA == actorB;
}

List<List<NarrativeItem>> _groupNarrativeItems(List<NarrativeItem> items) {
  if (items.isEmpty) {
    return const <List<NarrativeItem>>[];
  }

  final grouped = <List<NarrativeItem>>[];
  var current = <NarrativeItem>[];

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    current.add(item);

    final next = (i + 1) < items.length ? items[i + 1] : null;
    final sameHintGroup =
        item.presentationHint != null &&
        next?.presentationHint == item.presentationHint &&
        item.groupId != null &&
        item.groupId == next?.groupId &&
        next != null &&
        _sameActor(item, next);
    final shouldContinueGroup = item.noNewline || sameHintGroup;

    if (!shouldContinueGroup || i == items.length - 1) {
      grouped.add(current);
      current = <NarrativeItem>[];
    }
  }

  return grouped;
}
