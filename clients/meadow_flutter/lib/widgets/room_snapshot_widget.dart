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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/room_snapshot.dart';

class RoomSnapshotWidget extends StatelessWidget {
  final RoomSnapshot snapshot;
  final void Function(String command) onCommand;
  final void Function(ObjectRef object) onInspect;

  const RoomSnapshotWidget({
    super.key,
    required this.snapshot,
    required this.onCommand,
    required this.onInspect,
  });

  ButtonStyle _chipButtonStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      foregroundColor: WidgetStatePropertyAll(cs.onSurface),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chipStyle = _chipButtonStyle(context);
    final exits = snapshot.exits.toList()..sort();
    final actors = snapshot.actors.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final things = snapshot.things.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final actions = snapshot.actions.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

    Widget railRow(String label, List<Widget> chips) {
      if (chips.isEmpty) {
        return const SizedBox.shrink();
      }
      return Semantics(
        container: true,
        label: '$label actions',
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ChipRail(chips: chips),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Room snapshot: ${snapshot.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (snapshot.room != null)
                IconButton(
                  tooltip: 'Inspect room',
                  onPressed: () => onInspect(snapshot.room!),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.info_outline),
                ),
            ],
          ),
          if (snapshot.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(snapshot.description),
            ),
          railRow(
            'Exits',
            [
              for (final e in exits)
                FilledButton.tonal(
                  style: chipStyle,
                  onPressed: () => onCommand('go $e'),
                  child: Text(e),
                ),
            ],
          ),
          railRow(
            'Things',
            [
              for (final a in actions)
                FilledButton(
                  style: chipStyle,
                  onPressed: () => onCommand(a.command),
                  child: Text(a.label),
                ),
              for (final t in things)
                OutlinedButton(
                  style: chipStyle,
                  onPressed: () => onInspect(t.object),
                  child: Text(t.name),
                ),
            ],
          ),
          railRow(
            'Players',
            [
              for (final a in actors)
                OutlinedButton.icon(
                  style: chipStyle,
                  onPressed: () => onInspect(a.object),
                  icon: const Icon(Icons.person_outline, size: 16),
                  label: Text(
                    a.status.isNotEmpty && a.status != 'awake'
                        ? '${a.name} (${a.status})'
                        : a.name,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipRail extends StatefulWidget {
  final List<Widget> chips;

  const _ChipRail({
    required this.chips,
  });

  @override
  State<_ChipRail> createState() => _ChipRailState();
}

class _ChipRailState extends State<_ChipRail> {
  final _ctrl = ScrollController();
  bool _canScroll = false;
  bool _atStart = true;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_recomputeEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _recomputeEdges();
    });
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_recomputeEdges)
      ..dispose();
    super.dispose();
  }

  void _recomputeEdges() {
    if (!mounted) return;
    if (!_ctrl.hasClients) return;
    final pos = _ctrl.position;
    final canScroll = pos.maxScrollExtent > 0;
    final atStart = !canScroll || pos.pixels <= 0.5;
    final atEnd = !canScroll || (pos.maxScrollExtent - pos.pixels) <= 0.5;
    if (canScroll == _canScroll && atStart == _atStart && atEnd == _atEnd) {
      return;
    }
    setState(() {
      _canScroll = canScroll;
      _atStart = atStart;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fadeColor = Theme.of(context).cardColor;
    const railHeight = 34.0;

    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: const <PointerDeviceKind>{
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
    );

    return SizedBox(
      height: railHeight,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: scrollBehavior,
            child: Listener(
              onPointerSignal: (event) {
                if (!mounted) return;
                if (event is! PointerScrollEvent) return;
                if (!_ctrl.hasClients) return;
                // Map vertical wheel to horizontal motion for desktop mice.
                final next = (_ctrl.offset + event.scrollDelta.dy).clamp(
                  0.0,
                  _ctrl.position.maxScrollExtent,
                );
                _ctrl.jumpTo(next);
              },
              child: ListView.separated(
                controller: _ctrl,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.chips.length,
                padding: const EdgeInsets.only(right: 8),
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) => Align(
                  alignment: Alignment.centerLeft,
                  child: widget.chips[index],
                ),
              ),
            ),
          ),
          if (_canScroll && !_atStart)
            IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        fadeColor,
                        fadeColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_canScroll && !_atEnd)
            IgnorePointer(
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 18,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        fadeColor,
                        fadeColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_canScroll)
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 2),
                  child: Icon(
                    Icons.swipe_left_alt,
                    size: 14,
                    color: cs.outline.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
