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
  final bool speechBubblesEnabled;
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
    required this.speechBubblesEnabled,
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

          Widget buildMessage(int localIdx, NarrativeItem item) {
            final key = messageKeys.putIfAbsent(item.id, GlobalKey.new);
            final prev = localIdx > 0 ? group[localIdx - 1] : null;
            final next = localIdx < group.length - 1
                ? group[localIdx + 1]
                : null;
            final hasPrevFromSameActor =
                prev != null && _sameBubbleRun(prev, item);
            final hasNextFromSameActor =
                next != null && _sameBubbleRun(item, next);
            final isGroupedBubbleMessage =
                hasPrevFromSameActor || hasNextFromSameActor;
            final ts = item.timestamp.toIso8601String().split('T').last;
            return Container(
              key: key,
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isGroupedBubbleMessage ? 0 : 4,
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
                  if (speechBubblesEnabled &&
                      item.presentationHint == 'speech_bubble')
                    _SpeechBubbleMessage(
                      item: item,
                      colorScheme: cs,
                      playerCurie: playerCurie,
                      monospaceNarrative: monospaceNarrative,
                      onLinkTap: onLinkTap,
                      hasPrevFromSameActor: hasPrevFromSameActor,
                      hasNextFromSameActor: hasNextFromSameActor,
                    )
                  else if (speechBubblesEnabled &&
                      item.presentationHint == 'thought_bubble')
                    _ThoughtBubbleMessage(
                      item: item,
                      colorScheme: cs,
                      playerCurie: playerCurie,
                      monospaceNarrative: monospaceNarrative,
                      onLinkTap: onLinkTap,
                    )
                  else
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
              for (var i = 0; i < group.length; i++) buildMessage(i, group[i]),
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

class _SpeechBubbleMessage extends StatelessWidget {
  final NarrativeItem item;
  final ColorScheme colorScheme;
  final String playerCurie;
  final bool monospaceNarrative;
  final LinkTapHandler? onLinkTap;
  final bool hasPrevFromSameActor;
  final bool hasNextFromSameActor;

  const _SpeechBubbleMessage({
    required this.item,
    required this.colorScheme,
    required this.playerCurie,
    required this.monospaceNarrative,
    required this.onLinkTap,
    required this.hasPrevFromSameActor,
    required this.hasNextFromSameActor,
  });

  @override
  Widget build(BuildContext context) {
    final actorCurie = item.metadata?.actorCurie;
    final isSelf =
        actorCurie != null &&
        actorCurie.toLowerCase() == playerCurie.toLowerCase();
    final actorLabel = isSelf
        ? 'You'
        : (item.metadata?.actorName ?? actorCurie ?? 'Unknown');
    final semanticSpeech = item.metadata?.content;
    final bubbleContent = (semanticSpeech != null && semanticSpeech.isNotEmpty)
        ? <String>[semanticSpeech]
        : (item.content.isNotEmpty
              ? item.content
              : <String>[_speechContent(item)]);
    final bubbleContentType =
        (semanticSpeech != null && semanticSpeech.isNotEmpty)
        ? 'text/djot'
        : item.contentType;

    final bubbleColor = isSelf
        ? Color.lerp(colorScheme.primaryContainer, colorScheme.primary, 0.12) ??
              colorScheme.primaryContainer
        : colorScheme.secondaryContainer;
    final bubbleTextColor = isSelf
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSecondaryContainer;
    final rowAlign = isSelf ? MainAxisAlignment.end : MainAxisAlignment.start;
    final showActorLabel = !hasNextFromSameActor;
    final showTail = !hasNextFromSameActor;
    final actorText = Text(
      actorLabel,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: colorScheme.outline,
        fontWeight: FontWeight.w700,
      ),
    );
    final bubbleBody = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(hasPrevFromSameActor ? 9 : 14),
            topRight: Radius.circular(hasPrevFromSameActor ? 9 : 14),
            bottomLeft: Radius.circular(
              isSelf ? 14 : (hasNextFromSameActor ? 9 : 4),
            ),
            bottomRight: Radius.circular(
              isSelf ? (hasNextFromSameActor ? 9 : 4) : 14,
            ),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: bubbleTextColor,
            fontSize: 14,
          ),
          child: ContentRenderer(
            content: bubbleContent,
            contentType: bubbleContentType,
            isStale: false,
            onLinkTap: onLinkTap,
            monospace: monospaceNarrative,
          ),
        ),
      ),
    );
    final bubbleWithTail = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isSelf
          ? <Widget>[
              bubbleBody,
              if (showTail)
                CustomPaint(
                  size: const Size(8, 10),
                  painter: _SpeechBubbleTailPainter(
                    color: bubbleColor,
                    isSelf: isSelf,
                  ),
                ),
            ]
          : <Widget>[
              if (showTail)
                CustomPaint(
                  size: const Size(8, 10),
                  painter: _SpeechBubbleTailPainter(
                    color: bubbleColor,
                    isSelf: isSelf,
                  ),
                ),
              bubbleBody,
            ],
    );

    final verticalPadding = hasPrevFromSameActor || hasNextFromSameActor
        ? 0.0
        : 5.0;
    final reserveActorGutter = hasPrevFromSameActor || hasNextFromSameActor;
    final actorGutterWidth = ((actorLabel.length * 8) + 8)
        .clamp(56, 180)
        .toDouble();
    final actorGutter = SizedBox(
      width: actorGutterWidth,
      child: showActorLabel ? actorText : null,
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: verticalPadding),
      child: Row(
        mainAxisAlignment: rowAlign,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isSelf
            ? <Widget>[
                bubbleWithTail,
                if (showActorLabel || reserveActorGutter)
                  const SizedBox(width: 2),
                if (showActorLabel || reserveActorGutter) actorGutter,
              ]
            : <Widget>[
                if (showActorLabel || reserveActorGutter) actorGutter,
                if (showActorLabel || reserveActorGutter)
                  const SizedBox(width: 2),
                bubbleWithTail,
              ],
      ),
    );
  }
}

class _ThoughtBubbleMessage extends StatelessWidget {
  final NarrativeItem item;
  final ColorScheme colorScheme;
  final String playerCurie;
  final bool monospaceNarrative;
  final LinkTapHandler? onLinkTap;

  const _ThoughtBubbleMessage({
    required this.item,
    required this.colorScheme,
    required this.playerCurie,
    required this.monospaceNarrative,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final actorCurie = item.metadata?.actorCurie;
    final isSelf =
        actorCurie != null &&
        actorCurie.toLowerCase() == playerCurie.toLowerCase();
    final actorLabel = item.metadata?.actorName ?? actorCurie ?? 'Unknown';
    final semanticThought = item.metadata?.content;
    final bubbleContent =
        (semanticThought != null && semanticThought.isNotEmpty)
        ? <String>[semanticThought]
        : (item.content.isNotEmpty
              ? item.content
              : <String>[_speechContent(item)]);
    final bubbleContentType =
        (semanticThought != null && semanticThought.isNotEmpty)
        ? 'text/djot'
        : item.contentType;

    final bubbleColor = isSelf
        ? Color.lerp(colorScheme.primaryContainer, colorScheme.primary, 0.08) ??
              colorScheme.primaryContainer
        : Color.lerp(
                colorScheme.tertiaryContainer,
                colorScheme.surfaceContainerHigh,
                0.25,
              ) ??
              colorScheme.tertiaryContainer;
    final bubbleTextColor = isSelf
        ? colorScheme.onPrimaryContainer
        : colorScheme.onTertiaryContainer;
    final rowAlign = isSelf ? MainAxisAlignment.end : MainAxisAlignment.start;

    final nameText = Flexible(
      child: Text(
        actorLabel,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.outline,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final bubbleBody = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                Color.lerp(bubbleColor, colorScheme.outline, 0.25) ??
                colorScheme.outline,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: bubbleTextColor,
            fontSize: 14,
          ),
          child: ContentRenderer(
            content: bubbleContent,
            contentType: bubbleContentType,
            isStale: false,
            onLinkTap: onLinkTap,
            monospace: monospaceNarrative,
          ),
        ),
      ),
    );

    final thoughtDots = CustomPaint(
      size: const Size(16, 18),
      painter: _ThoughtBubbleDotsPainter(
        color: bubbleColor,
        isSelf: isSelf,
      ),
    );
    final bubbleWithDots = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isSelf
          ? <Widget>[bubbleBody, thoughtDots]
          : <Widget>[thoughtDots, bubbleBody],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: rowAlign,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isSelf
            ? <Widget>[bubbleWithDots, const SizedBox(width: 5), nameText]
            : <Widget>[nameText, const SizedBox(width: 5), bubbleWithDots],
      ),
    );
  }
}

String _speechContent(NarrativeItem item) {
  final content = item.metadata?.content;
  if (content != null && content.isNotEmpty) {
    return content;
  }
  return item.content.join('\n');
}

bool _sameActor(NarrativeItem a, NarrativeItem b) {
  final actorA = a.metadata?.actorCurie;
  final actorB = b.metadata?.actorCurie;
  if (actorA == null || actorB == null) {
    return true;
  }
  return actorA == actorB;
}

bool _isBubbleHint(String? hint) {
  return hint == 'speech_bubble' || hint == 'thought_bubble';
}

bool _sameBubbleRun(NarrativeItem a, NarrativeItem b) {
  final hint = a.presentationHint;
  if (!_isBubbleHint(hint) || hint != b.presentationHint) {
    return false;
  }
  final actorA = a.metadata?.actorCurie ?? a.metadata?.actorName;
  final actorB = b.metadata?.actorCurie ?? b.metadata?.actorName;
  if (actorA == null || actorB == null) {
    return false;
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
    final sameBubbleRun = next != null && _sameBubbleRun(item, next);
    final shouldContinueGroup =
        item.noNewline || sameHintGroup || sameBubbleRun;

    if (!shouldContinueGroup || i == items.length - 1) {
      grouped.add(current);
      current = <NarrativeItem>[];
    }
  }

  return grouped;
}

class _SpeechBubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isSelf;

  const _SpeechBubbleTailPainter({
    required this.color,
    required this.isSelf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isSelf) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isSelf != isSelf;
  }
}

class _ThoughtBubbleDotsPainter extends CustomPainter {
  final Color color;
  final bool isSelf;

  const _ThoughtBubbleDotsPainter({
    required this.color,
    required this.isSelf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final x = isSelf ? size.width - 1 : 1.0;
    final align = isSelf ? -1.0 : 1.0;

    canvas
      ..drawCircle(Offset(x, size.height - 5), 1.8, paint)
      ..drawCircle(Offset(x + 5 * align, size.height - 9), 2.8, paint)
      ..drawCircle(Offset(x + 11 * align, size.height - 13), 4.3, paint);
  }

  @override
  bool shouldRepaint(covariant _ThoughtBubbleDotsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isSelf != isSelf;
  }
}
