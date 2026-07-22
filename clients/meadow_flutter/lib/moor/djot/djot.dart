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

import 'package:meadow_flutter/moor/html_sanitize.dart';
import 'package:meadow_flutter/moor/moo_code_highlight.dart';

String renderDjotToRestrictedHtml(String input) {
  final doc = _parseBlocks(input);
  final html = doc.map((b) => b.toHtml()).join();
  return sanitizeRestrictedHtml(html);
}

// -----------------------------------------------------------------------------
// Blocks
// -----------------------------------------------------------------------------

sealed class _Block {
  String toHtml();
}

class _ParagraphBlock extends _Block {
  final List<_Inline> inlines;

  _ParagraphBlock(this.inlines);

  @override
  String toHtml() {
    final inner = inlines.map((n) => n.toHtml()).join();
    return '<p>$inner</p>';
  }
}

class _CodeBlock extends _Block {
  final String? info;
  final String content;

  _CodeBlock({required this.info, required this.content});

  @override
  String toHtml() {
    final normalized = normalizeMooFenceInfo(info);
    final cls = (normalized == null || normalized.isEmpty)
        ? ''
        : ' class="language-${_escapeAttr(normalized)}"';
    final body = (normalized == 'moo')
        ? highlightMooCodeToHtml(content)
        : _escapeHtml(content);
    return '<pre><code$cls>$body</code></pre>';
  }
}

class _HeadingBlock extends _Block {
  final int level; // 1-6
  final List<_Inline> inlines;

  _HeadingBlock({required this.level, required this.inlines});

  @override
  String toHtml() {
    final lvl = level.clamp(1, 6);
    final inner = inlines.map((n) => n.toHtml()).join();
    return '<h$lvl>$inner</h$lvl>';
  }
}

class _BlockQuoteBlock extends _Block {
  final List<_Block> children;
  _BlockQuoteBlock(this.children);

  @override
  String toHtml() {
    final inner = children.map((b) => b.toHtml()).join();
    return '<blockquote>$inner</blockquote>';
  }
}

enum _ListKind {
  unordered,
  ordered,
}

class _ListBlock extends _Block {
  final _ListKind kind;
  final List<List<_Block>> items;

  _ListBlock({required this.kind, required this.items});

  @override
  String toHtml() {
    final tag = kind == _ListKind.ordered ? 'ol' : 'ul';
    final li = items
        .map((blocks) => '<li>${blocks.map((b) => b.toHtml()).join()}</li>')
        .join();
    return '<$tag>$li</$tag>';
  }
}

class _TableBlock extends _Block {
  final List<List<List<_Inline>>> head;
  final List<List<List<_Inline>>> body;

  _TableBlock({required this.head, required this.body});

  @override
  String toHtml() {
    final headHtml = head.isEmpty
        ? ''
        : '<thead>${head.map((row) => _rowToHtml(row, cellTag: 'th')).join()}</thead>';
    final bodyHtml = body.isEmpty
        ? ''
        : '<tbody>${body.map((row) => _rowToHtml(row, cellTag: 'td')).join()}</tbody>';
    return '<table>$headHtml$bodyHtml</table>';
  }

  String _rowToHtml(List<List<_Inline>> row, {required String cellTag}) {
    final cells = row
        .map(
          (cell) =>
              '<$cellTag>${cell.map((n) => n.toHtml()).join()}</$cellTag>',
        )
        .join();
    return '<tr>$cells</tr>';
  }
}

List<_Block> _parseBlocks(String input) {
  // Normalize newlines.
  final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');

  final blocks = <_Block>[];
  final paraLines = <String>[];

  var inFence = false;
  var fenceMarker = '';
  String? fenceInfo;
  final fenceLines = <String>[];

  void flushParagraph() {
    if (paraLines.isEmpty) {
      return;
    }
    final paraText = paraLines.join('\n');
    paraLines.clear();
    blocks.add(_ParagraphBlock(_parseInline(paraText)));
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    if (inFence) {
      if (_isFenceClose(line, fenceMarker)) {
        blocks.add(
          _CodeBlock(
            info: fenceInfo,
            content: fenceLines.join('\n'),
          ),
        );
        fenceLines.clear();
        inFence = false;
        fenceMarker = '';
        fenceInfo = null;
        i++;
        continue;
      }
      fenceLines.add(line);
      i++;
      continue;
    }

    final open = _parseFenceOpen(line);
    if (open != null) {
      flushParagraph();
      inFence = true;
      fenceMarker = open.marker;
      fenceInfo = open.info;
      i++;
      continue;
    }

    final heading = _parseAtxHeading(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(heading);
      i++;
      continue;
    }

    final table = _parsePipeTable(lines, i);
    if (table != null) {
      flushParagraph();
      blocks.add(table.block);
      i = table.nextIndex;
      continue;
    }

    final quote = _parseBlockQuote(lines, i);
    if (quote != null) {
      flushParagraph();
      blocks.add(quote.block);
      i = quote.nextIndex;
      continue;
    }

    final list = _parseList(lines, i);
    if (list != null) {
      flushParagraph();
      blocks.add(list.block);
      i = list.nextIndex;
      continue;
    }

    if (line.trim().isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    paraLines.add(line);
    i++;
  }

  if (inFence) {
    // Unterminated fence: treat as code block anyway.
    blocks.add(
      _CodeBlock(
        info: fenceInfo,
        content: fenceLines.join('\n'),
      ),
    );
  } else {
    flushParagraph();
  }

  return blocks;
}

class _FenceOpen {
  final String marker;
  final String? info;
  _FenceOpen(this.marker, this.info);
}

_FenceOpen? _parseFenceOpen(String line) {
  // MVP: support backtick fences only.
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('```')) {
    return null;
  }

  var n = 0;
  while (n < trimmed.length && trimmed.codeUnitAt(n) == '`'.codeUnitAt(0)) {
    n++;
  }
  if (n < 3) {
    return null;
  }

  final marker = trimmed.substring(0, n);
  final rest = trimmed.substring(n).trim();
  return _FenceOpen(marker, rest.isEmpty ? null : rest);
}

_HeadingBlock? _parseAtxHeading(String line) {
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('#')) {
    return null;
  }

  var n = 0;
  while (n < trimmed.length && trimmed.codeUnitAt(n) == '#'.codeUnitAt(0)) {
    n++;
  }
  if (n == 0 || n > 6) {
    return null;
  }

  if (n >= trimmed.length) {
    return _HeadingBlock(level: n, inlines: const []);
  }

  // Djot requires at least one space after the # run for ATX headings.
  if (trimmed[n] != ' ') {
    return null;
  }

  final content = trimmed.substring(n + 1).trimRight();
  return _HeadingBlock(level: n, inlines: _parseInline(content));
}

bool _isFenceClose(String line, String marker) {
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith(marker)) {
    return false;
  }

  // Close line may have trailing spaces only.
  final rest = trimmed.substring(marker.length);
  return rest.trim().isEmpty;
}

// -----------------------------------------------------------------------------
// Inlines
// -----------------------------------------------------------------------------

sealed class _Inline {
  String toHtml();
}

class _TextInline extends _Inline {
  final String text;
  _TextInline(this.text);
  @override
  String toHtml() => _escapeHtml(text);
}

class _LineBreakInline extends _Inline {
  @override
  String toHtml() => '<br>';
}

class _CodeSpanInline extends _Inline {
  final String code;
  _CodeSpanInline(this.code);
  @override
  String toHtml() => '<code>${_escapeHtml(code)}</code>';
}

class _EmphInline extends _Inline {
  final List<_Inline> children;
  _EmphInline(this.children);
  @override
  String toHtml() => '<em>${children.map((c) => c.toHtml()).join()}</em>';
}

class _StrongInline extends _Inline {
  final List<_Inline> children;
  _StrongInline(this.children);
  @override
  String toHtml() =>
      '<strong>${children.map((c) => c.toHtml()).join()}</strong>';
}

class _LinkInline extends _Inline {
  final List<_Inline> label;
  final String url;
  _LinkInline(this.label, this.url);
  @override
  String toHtml() {
    final safe = isSafeUrl(url);
    if (!safe) {
      return label.map((c) => c.toHtml()).join();
    }
    final inner = label.map((c) => c.toHtml()).join();
    return '<a href="${_escapeAttr(url)}">$inner</a>';
  }
}

List<_Inline> _parseInline(String input) {
  final out = <_Inline>[];
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    out.add(_TextInline(buf.toString()));
    buf.clear();
  }

  var i = 0;
  while (i < input.length) {
    final ch = input[i];

    if (ch == '\n') {
      flushText();
      out.add(_LineBreakInline());
      i++;
      continue;
    }

    if (ch.codeUnitAt(0) == 0x5C) {
      // Escape next char literally.
      if (i + 1 < input.length) {
        buf.write(input[i + 1]);
        i += 2;
      } else {
        i++;
      }
      continue;
    }

    // Code spans: `code`
    if (ch == '`') {
      final end = input.indexOf('`', i + 1);
      if (end > i + 1) {
        flushText();
        out.add(_CodeSpanInline(input.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }

    // Links: [label](url)
    if (ch == '[') {
      final close = _findMatching(input, i, '[', ']');
      if (close != null &&
          close + 1 < input.length &&
          input[close + 1] == '(') {
        final urlClose = _findMatching(input, close + 1, '(', ')');
        if (urlClose != null) {
          final labelText = input.substring(i + 1, close);
          final url = input.substring(close + 2, urlClose).trim();
          flushText();
          out.add(_LinkInline(_parseInline(labelText), url));
          i = urlClose + 1;
          continue;
        }
      }
    }

    // Strong: **text** or __text__
    if (i + 1 < input.length &&
        (input.startsWith('**', i) || input.startsWith('__', i))) {
      final delim = input.substring(i, i + 2);
      final end = input.indexOf(delim, i + 2);
      if (end > i + 2) {
        flushText();
        final inner = input.substring(i + 2, end);
        out.add(_StrongInline(_parseInline(inner)));
        i = end + 2;
        continue;
      }
    }

    // Emphasis: *text* or _text_
    if (ch == '*' || ch == '_') {
      final end = input.indexOf(ch, i + 1);
      if (end > i + 1) {
        flushText();
        final inner = input.substring(i + 1, end);
        out.add(_EmphInline(_parseInline(inner)));
        i = end + 1;
        continue;
      }
    }

    buf.write(ch);
    i++;
  }

  flushText();
  return out;
}

int? _findMatching(String input, int start, String open, String close) {
  // MVP: non-nesting.
  final idx = input.indexOf(close, start + 1);
  return idx < 0 ? null : idx;
}

// -----------------------------------------------------------------------------
// Block helpers
// -----------------------------------------------------------------------------

class _ParsedBlock<T extends _Block> {
  final T block;
  final int nextIndex;
  _ParsedBlock(this.block, this.nextIndex);
}

_ParsedBlock<_BlockQuoteBlock>? _parseBlockQuote(
  List<String> lines,
  int start,
) {
  if (start >= lines.length) return null;
  if (!lines[start].trimLeft().startsWith('>')) return null;

  final inner = <String>[];
  var i = start;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (!trimmed.startsWith('>')) {
      break;
    }
    var rest = trimmed.substring(1);
    if (rest.startsWith(' ')) {
      rest = rest.substring(1);
    }
    inner.add(rest);
    i++;
  }

  final children = _parseBlocks(inner.join('\n'));
  return _ParsedBlock(_BlockQuoteBlock(children), i);
}

class _ListMarker {
  final _ListKind kind;
  final int? startNumber;
  final int markerEnd;

  _ListMarker({
    required this.kind,
    required this.startNumber,
    required this.markerEnd,
  });
}

_ParsedBlock<_ListBlock>? _parseList(List<String> lines, int start) {
  final first = _parseListMarker(lines[start]);
  if (first == null) return null;

  final kind = first.kind;
  final items = <List<_Block>>[];

  var i = start;
  while (i < lines.length) {
    final marker = _parseListMarker(lines[i]);
    if (marker == null || marker.kind != kind) {
      break;
    }

    final itemLines = <String>[
      lines[i].substring(marker.markerEnd).trimLeft(),
    ];
    i++;

    // Collect following indented lines as part of the item (MVP, single-level).
    while (i < lines.length) {
      final l = lines[i];
      if (l.trim().isEmpty) {
        itemLines.add('');
        i++;
        continue;
      }
      if (_parseListMarker(l) != null) {
        break;
      }
      if (l.startsWith('  ') || l.startsWith('\t')) {
        itemLines.add(l.trimLeft());
        i++;
        continue;
      }
      break;
    }

    final itemBlocks = _parseBlocks(itemLines.join('\n'));
    items.add(itemBlocks.isEmpty ? [_ParagraphBlock(const [])] : itemBlocks);

    // Allow a single blank line between items.
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
  }

  if (items.isEmpty) return null;
  return _ParsedBlock(_ListBlock(kind: kind, items: items), i);
}

_ListMarker? _parseListMarker(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('- ') ||
      trimmed.startsWith('* ') ||
      trimmed.startsWith('+ ')) {
    return _ListMarker(
      kind: _ListKind.unordered,
      startNumber: null,
      markerEnd: line.indexOf(trimmed) + 2,
    );
  }

  final m = RegExp(r'^(\d+)\.\s+').firstMatch(trimmed);
  if (m != null) {
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    final end = line.indexOf(trimmed) + m.group(0)!.length;
    return _ListMarker(kind: _ListKind.ordered, startNumber: n, markerEnd: end);
  }

  return null;
}

class _ParsedTable {
  final _TableBlock block;
  final int nextIndex;
  _ParsedTable(this.block, this.nextIndex);
}

_ParsedTable? _parsePipeTable(List<String> lines, int start) {
  if (start + 1 >= lines.length) return null;
  final headerLine = lines[start].trim();
  final sepLine = lines[start + 1].trim();
  if (!_looksLikePipeRow(headerLine) || !_looksLikePipeSep(sepLine)) {
    return null;
  }

  final headRow = _splitPipeRow(headerLine).map(_parseInline).toList();
  final head = <List<List<_Inline>>>[headRow];

  final body = <List<List<_Inline>>>[];
  var i = start + 2;
  while (i < lines.length) {
    final rowLine = lines[i].trim();
    if (rowLine.isEmpty) {
      break;
    }
    if (!_looksLikePipeRow(rowLine)) {
      break;
    }
    body.add(_splitPipeRow(rowLine).map(_parseInline).toList());
    i++;
  }

  return _ParsedTable(_TableBlock(head: head, body: body), i);
}

bool _looksLikePipeRow(String line) {
  // MVP: a pipe table row must contain at least one '|' and not be a fence.
  if (line.startsWith('```')) return false;
  return line.contains('|');
}

bool _looksLikePipeSep(String line) {
  // MVP: separator row contains pipes and dashes (optionally colons/spaces).
  if (!line.contains('|')) return false;
  final stripped = line.replaceAll('|', '').replaceAll(' ', '');
  if (stripped.isEmpty) return false;
  for (final r in stripped.runes) {
    final c = String.fromCharCode(r);
    if (c != '-' && c != ':') return false;
  }
  return true;
}

List<String> _splitPipeRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => c.trim()).toList();
}

String _escapeHtml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _escapeAttr(String s) => _escapeHtml(s);
