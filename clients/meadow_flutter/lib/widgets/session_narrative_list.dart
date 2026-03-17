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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/widgets/link_preview_card.dart';

class SessionNarrativeList extends StatelessWidget {
  final List<NarrativeItem> items;
  final bool monospaceNarrative;
  final bool showNarrativeMeta;
  final String playerCurie;
  final ScrollController scrollController;
  final GlobalKey listKey;
  final Map<String, GlobalKey> messageKeys;
  final LinkTapHandler? onLinkTap;
  final bool isLoadingMore;

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
    this.isLoadingMore = false,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _groupNarrativeItems(items);
    // Reserve index 0 for a loading indicator when fetching older history.
    final hasLoadingHeader = isLoadingMore;
    final offset = hasLoadingHeader ? 1 : 0;
    return SelectionArea(
      child: Semantics(
        container: true,
        liveRegion: true,
        readOnly: true,
        label: 'Narrative output',
        child: ListView.builder(
          key: listKey,
          controller: scrollController,
          itemCount: groups.length + offset,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemBuilder: (context, idx) {
            if (hasLoadingHeader && idx == 0) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final group = groups[idx - offset];
            final first = group.first;
            final cs = Theme.of(context).colorScheme;

            Widget buildMessage(NarrativeItem item) {
              final key = messageKeys.putIfAbsent(item.id, GlobalKey.new);
              final ts = item.timestamp.toIso8601String().split('T').last;
              final content = ContentRenderer(
                content: item.content,
                contentType: item.contentType,
                isStale: false,
                onLinkTap: onLinkTap,
                monospace: monospaceNarrative,
              );
              return Semantics(
                container: true,
                readOnly: true,
                label: _semanticTextForNarrativeItem(item),
                child: Container(
                  key: key,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showNarrativeMeta) ...[
                        Row(
                          children: [
                            Text(
                              ts,
                              style: TextStyle(
                                fontFamily: 'Comic Mono',
                                color: cs.outline,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              item.contentType,
                              style: TextStyle(
                                fontFamily: 'Comic Mono',
                                color: cs.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      if (item.metadata?.thumbnail case final thumbnail?)
                        _NarrativeThumbnailLayout(
                          thumbnail: thumbnail.data,
                          content: content,
                        )
                      else
                        content,
                      if (item.metadata?.linkPreview case final preview?)
                        LinkPreviewCard(
                          preview: preview,
                          onTap: onLinkTap,
                        ),
                    ],
                  ),
                ),
              );
            }

            final hint = first.presentationHint;
            final isInset = hint == 'inset';
            final isHintGroup =
                hint != null &&
                first.groupId != null &&
                group.every(
                  (m) =>
                      m.presentationHint == hint && m.groupId == first.groupId,
                );

            final inner = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in group) buildMessage(item),
              ],
            );

            if (!isInset) {
              return RepaintBoundary(child: inner);
            }

            if (group.length == 1 && !isHintGroup) {
              return inner;
            }

            return RepaintBoundary(
              child: Padding(
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
              ),
            );
          },
        ),
      ),
    );
  }
}

String _semanticTextForNarrativeItem(NarrativeItem item) {
  final ttsText = item.metadata?.ttsText;
  if (ttsText != null && ttsText.trim().isNotEmpty) {
    return ttsText.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  final joined = item.content.join('\n').trim();
  if (joined.isEmpty) {
    return item.contentType;
  }

  if (item.contentType == 'text/html') {
    final text = html_parser.parseFragment(joined).text ?? '';
    return text.trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  return joined.replaceAll(RegExp(r'\s+'), ' ');
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

class _NarrativeThumbnailLayout extends StatelessWidget {
  final Uint8List thumbnail;
  final Widget content;

  const _NarrativeThumbnailLayout({
    required this.thumbnail,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final image = ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.only(
              left: compact ? 0 : 14,
              right: compact ? 0 : 6,
              bottom: compact ? 8 : 0,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: compact ? 116 : 128,
                height: compact ? 116 : 128,
                child: Image.memory(
                  thumbnail,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              image,
              content,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            image,
          ],
        );
      },
    );
  }
}
