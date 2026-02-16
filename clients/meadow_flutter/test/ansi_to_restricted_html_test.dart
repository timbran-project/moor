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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/ansi_to_restricted_html.dart';

void main() {
  test('containsAnsiEscapeCodes detects ESC', () {
    expect(containsAnsiEscapeCodes('plain'), isFalse);
    expect(containsAnsiEscapeCodes('x\x1B[31my'), isTrue);
  });

  test('ansiToRestrictedHtml strips escapes and emits spans', () {
    const input = 'a \x1B[31mred\x1B[0m b';
    final html = ansiToRestrictedHtml(input);
    expect(html, contains('<div'));
    expect(html, contains('red'));
    expect(html, isNot(contains('\x1B')));
    expect(html, contains('<span'));
    expect(html, contains('color:'));
  });
}
