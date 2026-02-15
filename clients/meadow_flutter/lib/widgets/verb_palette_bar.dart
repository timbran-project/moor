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
import 'package:flutter/services.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';

class VerbPaletteBar extends StatefulWidget {
  final bool visible;
  final List<PaletteVerb> verbs;
  final void Function(PaletteVerb v) onSelect;

  const VerbPaletteBar({
    super.key,
    required this.visible,
    required this.verbs,
    required this.onSelect,
  });

  @override
  State<VerbPaletteBar> createState() => _VerbPaletteBarState();
}

class _VerbPaletteBarState extends State<VerbPaletteBar> {
  final _focusNode = FocusNode(debugLabel: 'verb-palette');
  final _ctrl = ScrollController();
  final _itemKeys = <GlobalKey>[];
  bool _canScroll = false;
  bool _atStart = true;
  bool _atEnd = true;
  bool _hasFocus = false;
  int? _selectedIndex;

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
    _focusNode
      ..unfocus()
      ..dispose();
    _ctrl
      ..removeListener(_recomputeEdges)
      ..dispose();
    super.dispose();
  }

  void _syncKeysAndSelection() {
    final needed = widget.verbs.length;
    if (_itemKeys.length != needed) {
      _itemKeys
        ..clear()
        ..addAll(List.generate(needed, (_) => GlobalKey()));
    }
    final sel = _selectedIndex;
    if (sel != null && sel >= needed) {
      _selectedIndex = needed > 0 ? needed - 1 : null;
    }
  }

  void _ensureSelectedVisible() {
    if (!mounted) return;
    final sel = _selectedIndex;
    if (sel == null) return;
    if (sel < 0 || sel >= _itemKeys.length) return;
    final ctx = _itemKeys[sel].currentContext;
    if (ctx == null) return;
    // Keep the currently selected chip in view when using keyboard navigation.
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
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

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    final isPress = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isPress) return KeyEventResult.ignored;
    if (!_hasFocus) return KeyEventResult.ignored;
    if (widget.verbs.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        final current = _selectedIndex ?? 0;
        _selectedIndex = (current - 1).clamp(0, widget.verbs.length - 1);
      });
      _ensureSelectedVisible();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        final current = _selectedIndex ?? 0;
        _selectedIndex = (current + 1).clamp(0, widget.verbs.length - 1);
      });
      _ensureSelectedVisible();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final idx = _selectedIndex ?? 0;
      final v = widget.verbs[idx];
      widget.onSelect(v);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    _syncKeysAndSelection();

    final fadeColor = Theme.of(context).scaffoldBackgroundColor;
    final cs = Theme.of(context).colorScheme;

    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: const <PointerDeviceKind>{
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
    );

    final verbs = widget.verbs;
    final selectedIndex = _hasFocus ? (_selectedIndex ?? 0) : null;

    return SizedBox(
      height: 38,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        onFocusChange: (v) {
          if (!mounted) return;
          setState(() {
            _hasFocus = v;
            if (!v) {
              _selectedIndex = null;
            } else {
              _selectedIndex ??= 0;
            }
          });
          if (v) {
            _ensureSelectedVisible();
          }
        },
        child: Semantics(
          container: true,
          focusable: true,
          focused: _hasFocus,
          label: 'Verb palette',
          value: (verbs.isEmpty || selectedIndex == null)
              ? 'empty'
              : '${verbs[selectedIndex].label}, ${selectedIndex + 1} of ${verbs.length}',
          hint:
              'Use left and right arrow keys to choose a verb. Press enter to select. Tab to move to the command input.',
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!mounted) return;
              if (!_focusNode.hasFocus) {
                FocusScope.of(context).requestFocus(_focusNode);
              }
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _hasFocus ? cs.primary : cs.outlineVariant,
                  width: _hasFocus ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  ScrollConfiguration(
                    behavior: scrollBehavior,
                    child: Listener(
                      onPointerSignal: (event) {
                        if (!mounted) return;
                        if (event is! PointerScrollEvent) return;
                        if (!_ctrl.hasClients) return;
                        final next = (_ctrl.offset + event.scrollDelta.dy)
                            .clamp(
                              0.0,
                              _ctrl.position.maxScrollExtent,
                            );
                        _ctrl.jumpTo(next);
                      },
                      child: ExcludeFocus(
                        // Only the palette container is a focus stop.
                        child: ListView.separated(
                          controller: _ctrl,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: verbs.length,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final v = verbs[index];
                            final selected = selectedIndex == index;
                            return Align(
                              key: _itemKeys[index],
                              alignment: Alignment.centerLeft,
                              child: _VerbChip(
                                label: v.label,
                                selected: selected,
                                onPressed: () {
                                  if (!mounted) return;
                                  FocusScope.of(
                                    context,
                                  ).requestFocus(_focusNode);
                                  setState(() {
                                    _selectedIndex = index;
                                  });
                                  widget.onSelect(v);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (_canScroll && !_atStart)
                    IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 22,
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
                          width: 22,
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
                          padding: const EdgeInsets.only(right: 10, bottom: 2),
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
            ),
          ),
        ),
      ),
    );
  }
}

class _VerbChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _VerbChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final bg = selected ? cs.primaryContainer : cs.surfaceContainerHighest;

    // Intentionally not focusable. The palette itself is the single focus stop;
    // arrow keys change selection.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      descendantsAreFocusable: false,
      descendantsAreTraversable: false,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onPressed,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onPressed,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: bg,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? cs.primary : cs.outlineVariant,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
