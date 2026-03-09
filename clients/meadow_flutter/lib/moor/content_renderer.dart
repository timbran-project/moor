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
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:meadow_flutter/moor/ansi_to_restricted_html.dart';
import 'package:meadow_flutter/moor/djot/djot.dart';
import 'package:meadow_flutter/moor/html_sanitize.dart';
import 'package:meadow_flutter/moor/moo_code_highlight.dart';

typedef LinkTapHandler = void Function(String url);

const _emojiFontFallback = <String>[
  'Noto Color Emoji', // Linux
  'Segoe UI Emoji', // Windows
  'Apple Color Emoji', // macOS
  'Noto Emoji',
  'Symbola',
];

// When rendering monospace, keep monospace fallbacks first to avoid breaking
// spacing, and only then fall back to emoji fonts.
const _monospaceFontFallback = <String>[
  'Comic Mono',
  'Noto Sans Mono',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Consolas',
  'Menlo',
  'Courier New',
  ..._emojiFontFallback,
];

final _urlRe = RegExp(
  r'''(https?://[^\s<>"')\]\u201C\u201D\u2018\u2019]+|moo://[^\s<>"')\]\u201C\u201D\u2018\u2019]+)''',
);
final _uuObjIdRe = RegExp(r'#?[\da-fA-F]{6}-[\da-fA-F]{10}');
final _objIdRe = RegExp(r'#\d+(?![0-9a-fA-F]*-[0-9a-fA-F])');

class ContentRenderer extends StatelessWidget {
  final List<String> content;
  final String contentType;
  final bool isStale;
  final LinkTapHandler? onLinkTap;
  final bool monospace;

  const ContentRenderer({
    super.key,
    required this.content,
    required this.contentType,
    required this.isStale,
    required this.onLinkTap,
    required this.monospace,
  });

  @override
  Widget build(BuildContext context) {
    final joined = content.join('\n');
    final child = _buildInner(context, joined);
    final hasSelectionContainer = SelectionContainer.maybeOf(context) != null;

    var wrapped = child;
    if (!hasSelectionContainer) {
      // Make output selectable for copy/paste. HtmlWidget supports SelectionArea.
      wrapped = SelectionArea(child: wrapped);
    }
    if (!monospace) {
      return wrapped;
    }
    return DefaultTextStyle.merge(
      style: const TextStyle(
        fontFamily: 'Comic Mono',
        fontFamilyFallback: _monospaceFontFallback,
      ),
      child: wrapped,
    );
  }

  Widget _buildInner(BuildContext context, String joined) {
    // Some backend output can be mislabeled as HTML but still contain ANSI SGR
    // sequences; detect ESC and force it through the ANSI->HTML path first.
    if (contentType != 'text/x-uri' && containsAnsiEscapeCodes(joined)) {
      final html = _linkifyBareUrlsInHtml(
        sanitizeRestrictedHtml(ansiToRestrictedHtml(joined)),
      );
      if (contentType == 'text/traceback') {
        return _PreformattedHtml(
          html: html,
          isStale: isStale,
          onLinkTap: onLinkTap,
        );
      }
      return _HtmlBlock(
        html: html,
        isStale: isStale,
        onLinkTap: onLinkTap,
      );
    }

    switch (contentType) {
      case 'text/html':
        {
          final highlighted = _highlightMooCodeBlocksInHtml(joined);
          final sanitized = _linkifyBareUrlsInHtml(
            sanitizeRestrictedHtml(highlighted),
          );
          return _HtmlBlock(
            html: sanitized,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/djot':
        {
          final html = _linkifyBareUrlsInHtml(
            renderDjotToRestrictedHtml(joined),
          );
          return _HtmlBlock(
            html: html,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/traceback':
        {
          return _Preformatted(
            text: joined,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/x-uri':
        {
          // For the spike: show as a link instead of embedding a webview.
          return _PlainTextBlock(
            text: joined.trim(),
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/plain':
      default:
        {
          return _PlainTextBlock(
            text: joined,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
    }
  }
}

class _Preformatted extends StatelessWidget {
  final String text;
  final bool isStale;
  final LinkTapHandler? onLinkTap;

  const _Preformatted({
    required this.text,
    required this.isStale,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = DefaultTextStyle.of(context).style.merge(
      const TextStyle(
        fontFamily: 'Comic Mono',
        fontFamilyFallback: _monospaceFontFallback,
      ),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SelectableText.rich(
        TextSpan(
          children: _buildLinkifiedSpans(
            context,
            text,
            isStale: isStale,
            onLinkTap: onLinkTap,
          ),
        ),
        style: textStyle,
      ),
    );
  }
}

class _PreformattedHtml extends StatelessWidget {
  final String html;
  final bool isStale;
  final LinkTapHandler? onLinkTap;

  const _PreformattedHtml({
    required this.html,
    required this.isStale,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: _HtmlBlock(
        html: html,
        isStale: isStale,
        onLinkTap: onLinkTap,
      ),
    );
  }
}

class _PreformattedCodeBlock extends StatelessWidget {
  final dom.Element element;

  const _PreformattedCodeBlock({
    required this.element,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style.merge(
      const TextStyle(
        fontFamily: 'Comic Mono',
        fontFamilyFallback: _monospaceFontFallback,
      ),
    );

    final code = element.querySelector('code');
    final classes =
        code?.classes.map((c) => c.toLowerCase()).toList() ?? const <String>[];
    final hasLanguageClass = classes.any((c) => c.startsWith('language-'));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: hasLanguageClass
          ? SelectableText.rich(
              TextSpan(
                style: base,
                children: _inlineSpansFromNode(
                  code ?? element,
                  base: base,
                  colorScheme: cs,
                ),
              ),
            )
          : SelectableText(
              element.text,
              style: base,
            ),
    );
  }
}

List<InlineSpan> _inlineSpansFromNode(
  dom.Node node, {
  required TextStyle base,
  required ColorScheme colorScheme,
}) {
  if (node is dom.Text) {
    return <InlineSpan>[TextSpan(text: node.data)];
  }
  if (node is! dom.Element) {
    return const <InlineSpan>[];
  }

  final nodeStyle = base.merge(_styleForMooClass(node, colorScheme));
  final children = <InlineSpan>[];
  for (final child in node.nodes) {
    children.addAll(
      _inlineSpansFromNode(
        child,
        base: nodeStyle,
        colorScheme: colorScheme,
      ),
    );
  }
  return <InlineSpan>[TextSpan(style: nodeStyle, children: children)];
}

TextStyle? _styleForMooClass(dom.Element node, ColorScheme cs) {
  if (node.classes.contains('moo-keyword')) {
    return TextStyle(
      color: Color.lerp(cs.primary, Colors.indigo, 0.4),
      fontWeight: FontWeight.w700,
    );
  }
  if (node.classes.contains('moo-string')) {
    return TextStyle(color: Color.lerp(cs.tertiary, Colors.teal, 0.4));
  }
  if (node.classes.contains('moo-number')) {
    return TextStyle(color: Color.lerp(cs.secondary, Colors.orange, 0.5));
  }
  if (node.classes.contains('moo-comment')) {
    return TextStyle(
      color: cs.outline,
      fontStyle: FontStyle.italic,
    );
  }
  return null;
}

class _HtmlBlock extends StatelessWidget {
  final String html;
  final bool isStale;
  final LinkTapHandler? onLinkTap;

  const _HtmlBlock({
    required this.html,
    required this.isStale,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tableBorder = _cssColor(
      Color.lerp(cs.outlineVariant, cs.outline, 0.35) ?? cs.outlineVariant,
    );
    final tableSurface = _cssColor(
      Color.lerp(cs.surfaceContainerLow, cs.surface, 0.15) ??
          cs.surfaceContainerLow,
    );
    final tableHeaderSurface = _cssColor(
      Color.lerp(cs.surfaceContainerHigh, cs.surfaceContainerHighest, 0.35) ??
          cs.surfaceContainerHigh,
    );
    final tableCardColor =
        Color.lerp(cs.surfaceContainerLow, cs.surface, 0.15) ??
        cs.surfaceContainerLow;
    final tableCardBorder =
        Color.lerp(cs.outlineVariant, cs.outline, 0.35) ?? cs.outlineVariant;

    return HtmlWidget(
      html,
      textStyle: DefaultTextStyle.of(context).style,
      customWidgetBuilder: (element) {
        if (element.localName == 'pre') {
          return _PreformattedCodeBlock(element: element);
        }
        if (element.localName == 'dl') {
          return _DefinitionListBlock(
            element: element,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
        if (element.localName == 'table') {
          final cardRadius = BorderRadius.circular(6);
          final cardBorderColor = tableCardBorder;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: tableCardColor,
              borderRadius: cardRadius,
              border: Border.all(color: cardBorderColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: HtmlWidget(
              element.outerHtml,
              textStyle: DefaultTextStyle.of(context).style,
              customStylesBuilder: (inner) {
                final tag = inner.localName;
                if (tag == null) return null;
                switch (tag) {
                  case 'table':
                    return {
                      'border-collapse': 'separate',
                      'border-spacing': '0',
                      'margin': '0',
                      'width': '100%',
                      'background': tableSurface,
                    };
                  case 'thead':
                    return {'background': tableHeaderSurface};
                  case 'tr':
                    return {'background': tableSurface};
                  case 'td':
                    final row = inner.parent;
                    final section = row?.parent;
                    final rowCells =
                        row?.children
                            .where(
                              (c) => c.localName == 'td' || c.localName == 'th',
                            )
                            .toList() ??
                        const <dom.Element>[];
                    final isLastCell =
                        rowCells.isNotEmpty && identical(rowCells.last, inner);
                    final sectionRows =
                        section?.children
                            .where((c) => c.localName == 'tr')
                            .toList() ??
                        const <dom.Element>[];
                    final isLastRow =
                        sectionRows.isNotEmpty &&
                        identical(sectionRows.last, row);
                    return {
                      'padding': '8px 12px',
                      'text-align': 'left',
                      if (!isLastCell) 'border-right': '1px solid $tableBorder',
                      if (!isLastRow) 'border-bottom': '1px solid $tableBorder',
                    };
                  case 'th':
                    final row = inner.parent;
                    final rowCells =
                        row?.children
                            .where(
                              (c) => c.localName == 'td' || c.localName == 'th',
                            )
                            .toList() ??
                        const <dom.Element>[];
                    final isLastCell =
                        rowCells.isNotEmpty && identical(rowCells.last, inner);
                    return {
                      'padding': '8px 12px',
                      'text-align': 'left',
                      'font-weight': '700',
                      'border-bottom': '1px solid $tableBorder',
                      if (!isLastCell) 'border-right': '1px solid $tableBorder',
                    };
                  default:
                    return null;
                }
              },
              onTapUrl: (url) {
                if (url.isEmpty) {
                  return true;
                }
                if (isStale && url.startsWith('moo://')) {
                  return true;
                }
                onLinkTap?.call(url);
                return true;
              },
            ),
          );
        }
        return null;
      },
      customStylesBuilder: (element) {
        final tag = element.localName;
        if (tag == null) return null;
        final parent = element.parent;
        if (tag == 'span') {
          if (element.classes.contains('moo-keyword')) {
            return {'color': '#7b3fcf', 'font-weight': '700'};
          }
          if (element.classes.contains('moo-string')) {
            return {'color': '#0b7f6f'};
          }
          if (element.classes.contains('moo-number')) {
            return {'color': '#b34a0b'};
          }
          if (element.classes.contains('moo-comment')) {
            return {'color': '#5f6f69', 'font-style': 'italic'};
          }
        }
        switch (tag) {
          case 'a':
            return {
              'color': _cssColor(cs.primary),
              'text-decoration': 'underline',
            };
          case 'h1':
            return {
              'font-weight': '700',
              'font-size': '22px',
              'margin': '8px 0 4px 0',
            };
          case 'h2':
            return {
              'font-weight': '700',
              'font-size': '20px',
              'margin': '8px 0 4px 0',
            };
          case 'h3':
            return {
              'font-weight': '700',
              'font-size': '18px',
              'margin': '8px 0 4px 0',
            };
          case 'h4':
            return {
              'font-weight': '700',
              'font-size': '16px',
              'margin': '8px 0 4px 0',
            };
          case 'h5':
            return {
              'font-weight': '700',
              'font-size': '14px',
              'margin': '8px 0 4px 0',
            };
          case 'h6':
            return {
              'font-weight': '700',
              'font-size': '13px',
              'margin': '8px 0 4px 0',
            };
          case 'blockquote':
            return {
              'border-left': '3px solid #9AA6A1',
              'padding-left': '10px',
              'margin': '6px 0',
            };
          case 'dl':
            return {'margin': '4px 0'};
          case 'dt':
            return {
              'margin': '6px 0 1px 0',
              'font-weight': '700',
            };
          case 'dd':
            return {
              'margin': '0 0 4px 10px',
            };
          case 'pre':
            return {
              // Preserve explicit newlines but wrap long lines instead of
              // overflowing horizontally.
              'white-space': 'pre-wrap',
              'overflow-wrap': 'anywhere',
              'word-break': 'break-word',
              'font-family': 'Comic Mono',
            };
          case 'code':
            final parentIsPre = parent != null && parent.localName == 'pre';
            return {
              if (parentIsPre) ...{
                'display': 'block',
                'white-space': 'pre-wrap',
                'font-family': 'Comic Mono',
              } else ...{
                // Some sources emit very long code-like tokens/identifiers.
                // Allow wrapping in narrative/panel views.
                'overflow-wrap': 'anywhere',
                'word-break': 'break-word',
                'font-family': 'Comic Mono',
              },
            };
          case 'table':
            return {
              'border-collapse': 'separate',
              'border-spacing': '0',
              'margin': '8px 0',
              'border': '1px solid $tableBorder',
              'border-radius': '12px',
              'overflow': 'hidden',
              'background': tableSurface,
            };
          case 'thead':
            return {'background': tableHeaderSurface};
          case 'tr':
            return {'background': tableSurface};
          case 'td':
            final row = element.parent;
            final section = row?.parent;
            final rowCells =
                row?.children
                    .where((c) => c.localName == 'td' || c.localName == 'th')
                    .toList() ??
                const <dom.Element>[];
            final isFirstCell =
                rowCells.isNotEmpty && identical(rowCells.first, element);
            final isLastCell =
                rowCells.isNotEmpty && identical(rowCells.last, element);
            final sectionRows =
                section?.children.where((c) => c.localName == 'tr').toList() ??
                const <dom.Element>[];
            final isLastRowInSection =
                sectionRows.isNotEmpty && identical(sectionRows.last, row);
            return {
              'border-top': '1px solid $tableBorder',
              'border-left': '1px solid $tableBorder',
              'padding': '7px 10px',
              if (isLastRowInSection && isFirstCell)
                'border-bottom-left-radius': '12px',
              if (isLastRowInSection && isLastCell)
                'border-bottom-right-radius': '12px',
            };
          case 'th':
            final row = element.parent;
            final rowCells =
                row?.children
                    .where((c) => c.localName == 'td' || c.localName == 'th')
                    .toList() ??
                const <dom.Element>[];
            final isFirstCell =
                rowCells.isNotEmpty && identical(rowCells.first, element);
            final isLastCell =
                rowCells.isNotEmpty && identical(rowCells.last, element);
            return {
              'border-top': '1px solid $tableBorder',
              'border-left': '1px solid $tableBorder',
              'padding': '8px 10px',
              'font-weight': '700',
              if (isFirstCell) 'border-top-left-radius': '12px',
              if (isLastCell) 'border-top-right-radius': '12px',
            };
          default:
            return null;
        }
      },
      onTapUrl: (url) {
        if (url.isEmpty) {
          return true;
        }
        if (isStale && url.startsWith('moo://')) {
          return true;
        }
        onLinkTap?.call(url);
        return true;
      },
    );
  }
}

String _cssColor(Color color) {
  final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
  return '#${hex.substring(2)}';
}

String _highlightMooCodeBlocksInHtml(String input) {
  final fragment = html_parser.parseFragment(input);

  void walk(dom.Node node) {
    if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'code') {
        final classes = node.classes.map((c) => c.toLowerCase()).toList();
        String? langClass;
        for (final c in classes) {
          if (c.startsWith('language-')) {
            langClass = c;
            break;
          }
        }
        final lang = langClass?.substring('language-'.length);
        if (isMooLanguage(lang)) {
          final codeText = node.text;
          final highlighted = html_parser.parseFragment(
            highlightMooCodeToHtml(codeText),
          );
          node.nodes
            ..clear()
            ..addAll(highlighted.nodes);
          node.classes.removeWhere(
            (c) => c.toLowerCase() == 'language-moocode',
          );
          if (!node.classes.any((c) => c.toLowerCase() == 'language-moo')) {
            node.classes.add('language-moo');
          }
        }
      }
      for (final child in node.nodes.toList()) {
        walk(child);
      }
      return;
    }
    for (final child in node.nodes.toList()) {
      walk(child);
    }
  }

  for (final node in fragment.nodes.toList()) {
    walk(node);
  }
  return fragment.outerHtml;
}

class _PlainTextBlock extends StatelessWidget {
  final String text;
  final bool isStale;
  final LinkTapHandler? onLinkTap;

  const _PlainTextBlock({
    required this.text,
    required this.isStale,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _buildLinkifiedSpans(
      context,
      text,
      isStale: isStale,
      onLinkTap: onLinkTap,
    );
    return SelectableText.rich(
      TextSpan(children: spans),
      style: DefaultTextStyle.of(context).style,
    );
  }
}

List<InlineSpan> _buildLinkifiedSpans(
  BuildContext context,
  String input, {
  required bool isStale,
  required LinkTapHandler? onLinkTap,
}) {
  final matches = <_TokenMatch>[];

  for (final m in _urlRe.allMatches(input)) {
    matches.add(_TokenMatch(m.start, m.end, _TokenKind.link, m.group(0)!));
  }
  for (final m in _uuObjIdRe.allMatches(input)) {
    matches.add(_TokenMatch(m.start, m.end, _TokenKind.uuobjid, m.group(0)!));
  }
  for (final m in _objIdRe.allMatches(input)) {
    matches.add(_TokenMatch(m.start, m.end, _TokenKind.objid, m.group(0)!));
  }

  matches.sort((a, b) => a.start.compareTo(b.start));

  final filtered = <_TokenMatch>[];
  var cursor = 0;
  for (final m in matches) {
    if (m.start < cursor) {
      continue;
    }
    filtered.add(m);
    cursor = m.end;
  }

  final out = <InlineSpan>[];
  var pos = 0;
  for (final m in filtered) {
    if (m.start > pos) {
      out.add(TextSpan(text: input.substring(pos, m.start)));
    }
    out.add(
      _spanForToken(
        context,
        m,
        isStale: isStale,
        onLinkTap: onLinkTap,
      ),
    );
    pos = m.end;
  }
  if (pos < input.length) {
    out.add(TextSpan(text: input.substring(pos)));
  }
  return out;
}

InlineSpan _spanForToken(
  BuildContext context,
  _TokenMatch m, {
  required bool isStale,
  required LinkTapHandler? onLinkTap,
}) {
  switch (m.kind) {
    case _TokenKind.link:
      final url = _cleanupDetectedUrl(m.text);
      final trailing = m.text.substring(url.length);
      final linkSpan = TextSpan(
        text: url,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (isStale && url.startsWith('moo://')) {
              return;
            }
            onLinkTap?.call(url);
          },
      );
      if (trailing.isEmpty) {
        return linkSpan;
      }
      return TextSpan(
        children: [
          linkSpan,
          TextSpan(text: trailing),
        ],
      );
    case _TokenKind.objid:
    case _TokenKind.uuobjid:
      final v = m.text;
      return TextSpan(
        text: v,
        style: TextStyle(
          color: Theme.of(context).colorScheme.secondary,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            await Clipboard.setData(ClipboardData(text: v));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard')),
            );
          },
      );
  }
}

String _cleanupDetectedUrl(String url) {
  return url.replaceAll(RegExp(r'[.,;:!?]+$'), '');
}

String _linkifyBareUrlsInHtml(String html) {
  final parsed = html_parser.parseFragment('<div>$html</div>');
  if (parsed.children.isEmpty) {
    return html;
  }
  final root = parsed.children.first;
  _linkifyBareUrlsInNode(root);
  return root.innerHtml;
}

@visibleForTesting
String linkifyBareUrlsInHtmlForTest(String html) =>
    _linkifyBareUrlsInHtml(html);

void _linkifyBareUrlsInNode(dom.Node node) {
  if (node is dom.Text) {
    final text = node.data;
    final matches = _urlRe.allMatches(text).toList();
    if (matches.isEmpty) {
      return;
    }

    final replacementNodes = <dom.Node>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        replacementNodes.add(dom.Text(text.substring(cursor, match.start)));
      }

      final rawUrl = match.group(0)!;
      final url = _cleanupDetectedUrl(rawUrl);
      final trailing = rawUrl.substring(url.length);
      if (isSafeUrl(url)) {
        replacementNodes.add(
          dom.Element.tag('a')
            ..attributes['href'] = url
            ..text = url,
        );
        if (trailing.isNotEmpty) {
          replacementNodes.add(dom.Text(trailing));
        }
      } else {
        replacementNodes.add(dom.Text(rawUrl));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      replacementNodes.add(dom.Text(text.substring(cursor)));
    }

    final parent = node.parent;
    if (parent == null) {
      return;
    }
    final index = parent.nodes.indexOf(node);
    parent.nodes.removeAt(index);
    parent.nodes.insertAll(index, replacementNodes);
    return;
  }

  if (node is dom.Element) {
    final tag = node.localName?.toLowerCase();
    if (tag == 'a' || tag == 'pre' || tag == 'code') {
      return;
    }
  }

  for (final child in node.nodes.toList()) {
    _linkifyBareUrlsInNode(child);
  }
}

class _DefinitionListBlock extends StatelessWidget {
  final dom.Element element;
  final bool isStale;
  final LinkTapHandler? onLinkTap;

  const _DefinitionListBlock({
    required this.element,
    required this.isStale,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[];
    String? pendingTermHtml;
    for (final child in element.children) {
      final tag = child.localName?.toLowerCase();
      if (tag == 'dt') {
        pendingTermHtml = child.innerHtml.trim();
        continue;
      }
      if (tag == 'dd') {
        rows.add((pendingTermHtml ?? '', child.innerHtml.trim()));
        pendingTermHtml = null;
      }
    }
    if (rows.isEmpty) {
      return HtmlWidget(
        element.outerHtml,
        textStyle: DefaultTextStyle.of(context).style,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final labelStyle = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    );
    final valueStyle = DefaultTextStyle.of(context).style;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (termHtml, valueHtml) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: HtmlWidget(
                        termHtml,
                        textStyle: labelStyle,
                        customStylesBuilder: (inner) {
                          final tag = inner.localName?.toLowerCase();
                          if (tag == 'p') return {'margin': '0'};
                          return null;
                        },
                        onTapUrl: (url) {
                          if (url.isEmpty) {
                            return true;
                          }
                          if (isStale && url.startsWith('moo://')) {
                            return true;
                          }
                          onLinkTap?.call(url);
                          return true;
                        },
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: cs.outlineVariant,
                  ),
                  Expanded(
                    child: HtmlWidget(
                      valueHtml,
                      textStyle: valueStyle,
                      customStylesBuilder: (inner) {
                        final tag = inner.localName?.toLowerCase();
                        if (tag == 'p') return {'margin': '0'};
                        return null;
                      },
                      onTapUrl: (url) {
                        if (url.isEmpty) {
                          return true;
                        }
                        if (isStale && url.startsWith('moo://')) {
                          return true;
                        }
                        onLinkTap?.call(url);
                        return true;
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _TokenKind {
  link,
  objid,
  uuobjid,
}

class _TokenMatch {
  final int start;
  final int end;
  final _TokenKind kind;
  final String text;

  _TokenMatch(this.start, this.end, this.kind, this.text);
}
