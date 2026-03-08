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
import 'package:meadow_flutter/moor/args.dart';

void main() {
  group('parseLaunchArgs', () {
    test('captures protocol callback uri arguments', () {
      final parsed = parseLaunchArgs(const <String>[
        'moor://oauth/callback?handoff_code=abc123',
      ]);

      expect(parsed.callbackUri, isNotNull);
      expect(parsed.callbackUri?.scheme, 'moor');
      expect(parsed.callbackUri?.queryParameters['handoff_code'], 'abc123');
    });

    test('still parses normal flag arguments', () {
      final parsed = parseLaunchArgs(const <String>[
        '--server=https://timbran.org',
        '--username=archwizard',
        '--password=potrzebie',
        '--mode=connect',
        '--login',
      ]);

      expect(parsed.server, 'https://timbran.org');
      expect(parsed.username, 'archwizard');
      expect(parsed.password, 'potrzebie');
      expect(parsed.mode, 'connect');
      expect(parsed.login, isTrue);
      expect(parsed.callbackUri, isNull);
    });
  });
}
