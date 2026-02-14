import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/djot/djot.dart';

void main() {
  test('atx heading', () {
    final html = renderDjotToRestrictedHtml('### Help');
    expect(html, contains('<h3>Help</h3>'));
  });

  test('paragraph + emphasis/strong', () {
    final html = renderDjotToRestrictedHtml('hello *a* **b** _c_ __d__');
    expect(html, contains('<p>'));
    expect(html, contains('<em>a</em>'));
    expect(html, contains('<strong>b</strong>'));
    expect(html, contains('<em>c</em>'));
    expect(html, contains('<strong>d</strong>'));
  });

  test('link', () {
    final html = renderDjotToRestrictedHtml('[x](https://example.com)');
    expect(html, contains('<a href="https://example.com">x</a>'));
  });

  test('code span', () {
    final html = renderDjotToRestrictedHtml('`<tag>`');
    expect(html, contains('<code>&lt;tag&gt;</code>'));
  });

  test('fenced code block', () {
    final html = renderDjotToRestrictedHtml('```moo\nreturn 1;\n```');
    expect(html, contains('<pre><code'));
    expect(html, contains('language-moo'));
    expect(html, contains('return 1;'));
  });

  test('blockquote', () {
    final html = renderDjotToRestrictedHtml('> hello\n> *world*');
    expect(html, contains('<blockquote>'));
    expect(html, contains('<p>hello<br><em>world</em></p>'));
  });

  test('unordered list', () {
    final html = renderDjotToRestrictedHtml('- a\n- *b*');
    expect(html, contains('<ul>'));
    expect(html, contains('<li><p>a</p></li>'));
    expect(html, contains('<li><p><em>b</em></p></li>'));
  });

  test('pipe table', () {
    final html = renderDjotToRestrictedHtml(
      '| a | b |\n|---|---|\n| 1 | *2* |',
    );
    expect(html, contains('<table>'));
    expect(html, contains('<thead>'));
    expect(html, contains('<th>a</th>'));
    expect(html, contains('<th>b</th>'));
    expect(html, contains('<tbody>'));
    expect(html, contains('<td>1</td>'));
    expect(html, contains('<td><em>2</em></td>'));
  });
}
