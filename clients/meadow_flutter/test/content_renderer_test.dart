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
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';

void main() {
  group('ContentRenderer', () {
    test('linkifies bare URLs in html fragments', () {
      final html = linkifyBareUrlsInHtmlForTest(
        '<p>Visit https://example.com please</p>',
      );

      expect(
        html,
        contains('<a href="https://example.com">https://example.com</a>'),
      );
    });

    test('linkifies bare URLs in root html text', () {
      final html = linkifyBareUrlsInHtmlForTest(
        'You share: http://www.google.com/',
      );

      expect(
        html,
        contains(
          'You share: <a href="http://www.google.com/">http://www.google.com/</a>',
        ),
      );
    });

    test('does not linkify bare URLs inside code blocks', () {
      final html = linkifyBareUrlsInHtmlForTest(
        '<p>Visit https://example.com please</p> '
        '<pre>https://example.com/code</pre> '
        '<code>https://example.com/inline</code>',
      );

      expect(
        html,
        contains('<a href="https://example.com">https://example.com</a>'),
      );
      expect(html, contains('<pre>https://example.com/code</pre>'));
      expect(html, contains('<code>https://example.com/inline</code>'));
    });

    testWidgets('linkifies bare URLs in traceback content', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ContentRenderer(
            content: const ['traceback: see https://example.com/details'],
            contentType: 'text/traceback',
            isStale: false,
            onLinkTap: (_) {},
            monospace: false,
          ),
        ),
      );

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      final rootSpan = selectable.textSpan!;
      expect(rootSpan.toPlainText(), contains('https://example.com/details'));

      final children = rootSpan.children!;
      final linkSpan = children.whereType<TextSpan>().firstWhere(
        (span) => span.text == 'https://example.com/details',
      );
      expect(linkSpan.recognizer, isNotNull);
    });
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: child,
    ),
  );
}
