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
import 'package:meadow_flutter/moor/ansi_to_restricted_html.dart';
import 'package:meadow_flutter/moor/djot/djot.dart';
import 'package:meadow_flutter/moor/html_sanitize.dart';

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
  'Noto Sans Mono',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Consolas',
  'Menlo',
  'Courier New',
  ..._emojiFontFallback,
];

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
    // Make output selectable for copy/paste. HtmlWidget supports SelectionArea.
    if (!monospace) {
      return SelectionArea(child: child);
    }
    return DefaultTextStyle.merge(
      style: const TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: _monospaceFontFallback,
      ),
      child: SelectionArea(child: child),
    );
  }

  Widget _buildInner(BuildContext context, String joined) {
    // Some backend output can be mislabeled as HTML but still contain ANSI SGR
    // sequences; detect ESC and force it through the ANSI->HTML path first.
    if (contentType != 'text/x-uri' && containsAnsiEscapeCodes(joined)) {
      final html = sanitizeRestrictedHtml(ansiToRestrictedHtml(joined));
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
          final sanitized = sanitizeRestrictedHtml(joined);
          return _HtmlBlock(
            html: sanitized,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/djot':
        {
          final html = renderDjotToRestrictedHtml(joined);
          return _HtmlBlock(
            html: html,
            isStale: isStale,
            onLinkTap: onLinkTap,
          );
        }
      case 'text/traceback':
        {
          return _Preformatted(text: joined);
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
  const _Preformatted({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: SelectableText(
        text,
        style: DefaultTextStyle.of(context).style,
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
    return HtmlWidget(
      html,
      textStyle: DefaultTextStyle.of(context).style,
      customWidgetBuilder: (element) {
        if (element.localName != 'pre') {
          return null;
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(
            element.text,
            style: DefaultTextStyle.of(context).style,
          ),
        );
      },
      customStylesBuilder: (element) {
        final tag = element.localName;
        if (tag == null) return null;
        switch (tag) {
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
          case 'pre':
            return {
              // Preserve explicit newlines but wrap long lines instead of
              // overflowing horizontally.
              'white-space': 'pre-wrap',
              'overflow-wrap': 'anywhere',
              'word-break': 'break-word',
            };
          case 'code':
            return {
              // Some sources emit very long code-like tokens/identifiers.
              // Allow wrapping in narrative/panel views.
              'overflow-wrap': 'anywhere',
              'word-break': 'break-word',
            };
          case 'table':
            return {'border-collapse': 'collapse', 'margin': '6px 0'};
          case 'td':
          case 'th':
            return {'border': '1px solid #B8C2BE', 'padding': '4px 6px'};
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
    final spans = _buildSpans(context, text);
    return SelectableText.rich(
      TextSpan(children: spans),
      style: DefaultTextStyle.of(context).style,
    );
  }

  List<InlineSpan> _buildSpans(BuildContext context, String input) {
    // Similar behavior to Meadow plain renderer: linkify http/https and moo://,
    // and make ObjIds copyable.
    final matches = <_TokenMatch>[];

    final urlRe = RegExp(
      r'''(https?://[^\s<>"')\]\u201C\u201D\u2018\u2019]+|moo://[^\s<>"')\]\u201C\u201D\u2018\u2019]+)''',
    );
    final uuObjIdRe = RegExp(r'#?[\da-fA-F]{6}-[\da-fA-F]{10}');
    final objIdRe = RegExp(r'#\d+(?![0-9a-fA-F]*-[0-9a-fA-F])');

    for (final m in urlRe.allMatches(input)) {
      matches.add(_TokenMatch(m.start, m.end, _TokenKind.link, m.group(0)!));
    }
    for (final m in uuObjIdRe.allMatches(input)) {
      matches.add(_TokenMatch(m.start, m.end, _TokenKind.uuobjid, m.group(0)!));
    }
    for (final m in objIdRe.allMatches(input)) {
      matches.add(_TokenMatch(m.start, m.end, _TokenKind.objid, m.group(0)!));
    }

    matches.sort((a, b) => a.start.compareTo(b.start));

    // Drop overlaps (prefer the earlier match; good enough for spike).
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
      out.add(_spanForToken(context, m));
      pos = m.end;
    }
    if (pos < input.length) {
      out.add(TextSpan(text: input.substring(pos)));
    }
    return out;
  }

  InlineSpan _spanForToken(BuildContext context, _TokenMatch m) {
    switch (m.kind) {
      case _TokenKind.link:
        {
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
        }
      case _TokenKind.objid:
      case _TokenKind.uuobjid:
        {
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
  }

  String _cleanupDetectedUrl(String url) {
    return url.replaceAll(RegExp(r'[.,;:!?]+$'), '');
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
