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

/// A command input controller that can render an inline "verb pill" chip at the
/// start of the field.
///
/// The pill is represented in the underlying string as a single sentinel
/// character (U+FFFC, object replacement) so selection/caret math stays simple.
class CommandEditingController extends TextEditingController {
  static const String _pillSentinel = '\uFFFC';

  String? verbPill;
  String? verbPillPlaceholder;
  String? ghostCompletion;
  Color placeholderColor = Colors.grey;

  VoidCallback? onPillCleared;
  VoidCallback? onPillSelected;

  bool _mutating = false;

  CommandEditingController() {
    addListener(_onChanged);
  }

  @override
  void dispose() {
    removeListener(_onChanged);
    super.dispose();
  }

  bool get hasVerbPill => verbPill != null && verbPill!.isNotEmpty;

  /// Returns the user's typed command, excluding the pill sentinel.
  String get commandText {
    final t = text;
    if (!hasVerbPill) return t;
    if (t.startsWith(_pillSentinel)) return t.substring(1);
    return t;
  }

  void setVerbPill({required String verb, String? placeholder}) {
    if (verb.isEmpty) return;
    _mutate(() {
      verbPill = verb;
      verbPillPlaceholder = placeholder;

      // Ensure sentinel exists at the start.
      if (!text.startsWith(_pillSentinel)) {
        final old = value;
        final oldText = old.text;
        final oldSel = old.selection;
        final newText = '$_pillSentinel$oldText';
        final shift = oldText.isEmpty ? 1 : 1;
        final newSel = oldSel.isValid
            ? TextSelection(
                baseOffset: (oldSel.baseOffset + shift).clamp(
                  1,
                  newText.length,
                ),
                extentOffset: (oldSel.extentOffset + shift).clamp(
                  1,
                  newText.length,
                ),
              )
            : TextSelection.collapsed(offset: newText.length);
        value = old.copyWith(text: newText, selection: newSel);
      }
      // Snap caret to after the pill if it somehow ended up before it.
      _snapCollapsedSelectionAfterPill();
    });
    onPillSelected?.call();
  }

  void promoteLeadingTokenToPill({required String verb, String? placeholder}) {
    final cmd = commandText;
    if (cmd.contains('\n')) return;

    var i = 0;
    while (i < cmd.length && cmd.codeUnitAt(i) <= 0x20) {
      i++;
    }
    var j = i;
    while (j < cmd.length && cmd.codeUnitAt(j) > 0x20) {
      j++;
    }
    var remainder = cmd.substring(j);
    remainder = remainder.replaceFirst(RegExp(r'^[ \t]+'), '');

    _mutate(() {
      verbPill = verb;
      verbPillPlaceholder = placeholder;
      ghostCompletion = null;
      value = TextEditingValue(
        text: '$_pillSentinel$remainder',
        selection: TextSelection.collapsed(offset: 1 + remainder.length),
      );
    });
    onPillSelected?.call();
  }

  void clearVerbPill() {
    if (!hasVerbPill) return;
    _mutate(() {
      verbPill = null;
      verbPillPlaceholder = null;
      ghostCompletion = null;
      if (text.startsWith(_pillSentinel)) {
        final old = value;
        final newText = old.text.substring(1);
        final oldSel = old.selection;
        final newSel = oldSel.isValid
            ? TextSelection(
                baseOffset: (oldSel.baseOffset - 1).clamp(0, newText.length),
                extentOffset: (oldSel.extentOffset - 1).clamp(
                  0,
                  newText.length,
                ),
              )
            : TextSelection.collapsed(offset: newText.length);
        value = old.copyWith(text: newText, selection: newSel);
      }
    });
    onPillCleared?.call();
  }

  void clearCommandTextKeepPill() {
    if (!hasVerbPill) {
      clear();
      return;
    }
    _mutate(() {
      value = const TextEditingValue(
        text: _pillSentinel,
        selection: TextSelection.collapsed(offset: 1),
      );
    });
  }

  /// If the caret is right after the pill, delete the pill instead of text.
  bool handleBackspaceAtPillBoundary() {
    if (!hasVerbPill) return false;
    final sel = selection;
    if (!sel.isValid || !sel.isCollapsed) return false;
    if (!text.startsWith(_pillSentinel)) return false;
    if (sel.baseOffset != 1) return false;
    clearVerbPill();
    return true;
  }

  void _mutate(void Function() f) {
    if (_mutating) {
      f();
      return;
    }
    _mutating = true;
    try {
      f();
    } finally {
      _mutating = false;
    }
  }

  void _snapCollapsedSelectionAfterPill() {
    if (!hasVerbPill) return;
    final sel = selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    if (sel.baseOffset <= 0) {
      value = value.copyWith(
        selection: const TextSelection.collapsed(offset: 1),
      );
    }
  }

  void _onChanged() {
    if (_mutating) return;

    // If the sentinel went missing (user deleted it), treat that as pill cleared.
    if (hasVerbPill && !text.startsWith(_pillSentinel)) {
      verbPill = null;
      verbPillPlaceholder = null;
      ghostCompletion = null;
      onPillCleared?.call();
      return;
    }

    // If sentinel exists without an active pill, remove it.
    if (!hasVerbPill && text.startsWith(_pillSentinel)) {
      _mutate(() {
        final old = value;
        final newText = old.text.substring(1);
        final oldSel = old.selection;
        final newSel = oldSel.isValid
            ? TextSelection(
                baseOffset: (oldSel.baseOffset - 1).clamp(0, newText.length),
                extentOffset: (oldSel.extentOffset - 1).clamp(
                  0,
                  newText.length,
                ),
              )
            : TextSelection.collapsed(offset: newText.length);
        value = old.copyWith(text: newText, selection: newSel);
      });
      return;
    }

    _snapCollapsedSelectionAfterPill();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final composing = value.composing;
    final hasComposing = composing.isValid && !composing.isCollapsed;
    final showGhostNoPill =
        !hasVerbPill &&
        (ghostCompletion?.isNotEmpty ?? false) &&
        selection.isValid &&
        selection.isCollapsed &&
        selection.baseOffset == text.length &&
        !hasComposing;

    if (!hasVerbPill || !text.startsWith(_pillSentinel)) {
      if (!showGhostNoPill) {
        return super.buildTextSpan(
          context: context,
          style: style,
          withComposing: withComposing,
        );
      }
      return TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: text, style: baseStyle),
          TextSpan(
            text: ghostCompletion,
            style: baseStyle.copyWith(color: placeholderColor),
          ),
        ],
      );
    }

    final remainder = text.substring(1);
    final showPlaceholder =
        remainder.isEmpty && (verbPillPlaceholder?.isNotEmpty ?? false);
    final showGhost =
        remainder.isNotEmpty &&
        (ghostCompletion?.isNotEmpty ?? false) &&
        selection.isValid &&
        selection.isCollapsed &&
        selection.baseOffset == text.length &&
        !hasComposing;

    final children = <InlineSpan>[
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            label: 'Verb ${verbPill!}',
            hint: 'Press delete to clear',
            button: true,
            child: Transform.translate(
              // Chips tend to sit a bit low compared to text; nudge upward.
              offset: const Offset(0, -1),
              child: InputChip(
                label: Text(
                  verbPill!,
                  style: baseStyle.copyWith(
                    fontSize: (baseStyle.fontSize ?? 14) * 0.92,
                    height: 1.05,
                  ),
                ),
                onDeleted: clearVerbPill,
                deleteIcon: const Icon(Icons.close, size: 16),
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ),
      TextSpan(text: remainder, style: baseStyle),
    ];

    if (showPlaceholder) {
      children.add(
        TextSpan(
          text: verbPillPlaceholder,
          style: baseStyle.copyWith(color: placeholderColor),
        ),
      );
    }

    if (showGhost) {
      children.add(
        TextSpan(
          text: ghostCompletion,
          style: baseStyle.copyWith(color: placeholderColor),
        ),
      );
    }

    return TextSpan(style: baseStyle, children: children);
  }
}
