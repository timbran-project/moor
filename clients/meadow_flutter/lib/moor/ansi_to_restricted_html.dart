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

import 'dart:convert';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;

bool containsAnsiEscapeCodes(String s) => s.contains('\x1B');

/// Convert SGR ANSI escape sequences to a restricted subset of HTML.
///
/// This is intended for feeding into `sanitizeRestrictedHtml(...)` and then
/// `HtmlWidget`.
String ansiToRestrictedHtml(String input) {
  const esc = HtmlEscape(HtmlEscapeMode.element);

  final out = StringBuffer(
    '<div style="margin:0; white-space: pre-wrap; overflow-wrap: anywhere; word-break: break-word">',
  );
  final parser = ansi.AnsiParser(input);
  for (final m in parser.matches) {
    final entity = m.entity;
    if (entity is! ansi.Text) continue;
    final text = entity.string;
    if (text.isEmpty) continue;

    final safeText = esc.convert(text);
    final style = _sgrStateToCss(m.state);
    out.write(
      style.isEmpty ? safeText : '<span style="$style">$safeText</span>',
    );
  }
  out.write('</div>');
  return out.toString();
}

String _sgrStateToCss(ansi.SgrState<void> s) {
  final css = <String>[];

  final fg = s.foreground;
  if (fg != null) {
    css.add('color: ${_colorToCss(fg)}');
  }

  final bg = s.background;
  if (bg != null) {
    css.add('background-color: ${_colorToCss(bg)}');
  }

  if (s.isBold) css.add('font-weight: bold');
  if (s.isItalicized) css.add('font-style: italic');
  if (s.isSinglyUnderlined || s.isDoublyUnderlined) {
    css.add('text-decoration: underline');
  }
  if (s.isCrossedOut) {
    css.add('text-decoration: line-through');
  }

  // Map "negative"/"concealed"/blink/etc" later if needed.
  return css.join(';');
}

String _colorToCss(ansi.Color c) {
  final rgb = _colorToRgb(c);
  return 'rgb(${rgb.$1},${rgb.$2},${rgb.$3})';
}

(int, int, int) _colorToRgb(ansi.Color c) {
  return switch (c) {
    ansi.ColorRgb(:final r, :final g, :final b) => (r, g, b),
    ansi.Color256(:final index) => _xterm256ToRgb(index),
    ansi.Color16(:final color) => _xterm16ToRgb(color.index),
  };
}

(int, int, int) _xterm16ToRgb(int idx) {
  // Standard xterm-ish 16-color palette (approx). Good enough for narrative.
  // 0..7 normal, 8..15 bright.
  const table = <(int, int, int)>[
    (0, 0, 0), // black
    (205, 0, 0), // red
    (0, 205, 0), // green
    (205, 205, 0), // yellow
    (0, 0, 238), // blue
    (205, 0, 205), // magenta
    (0, 205, 205), // cyan
    (229, 229, 229), // white
    (127, 127, 127), // bright black
    (255, 0, 0), // bright red
    (0, 255, 0), // bright green
    (255, 255, 0), // bright yellow
    (92, 92, 255), // bright blue
    (255, 0, 255), // bright magenta
    (0, 255, 255), // bright cyan
    (255, 255, 255), // bright white
  ];
  final i = idx.clamp(0, 15);
  return table[i];
}

(int, int, int) _xterm256ToRgb(int idx) {
  final i = idx.clamp(0, 255);
  if (i < 16) {
    return _xterm16ToRgb(i);
  }
  if (i >= 232) {
    final level = 8 + (i - 232) * 10;
    return (level, level, level);
  }

  // 6x6x6 cube.
  const steps = <int>[0, 95, 135, 175, 215, 255];
  final n = i - 16;
  final r = n ~/ 36;
  final g = (n % 36) ~/ 6;
  final b = n % 6;
  return (steps[r], steps[g], steps[b]);
}
