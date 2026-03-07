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
import 'package:meadow_flutter/moor/session_bootstrap.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';

void main() {
  group('SessionBootstrap', () {
    test('normalizeMooTitle trims non-empty titles', () {
      expect(normalizeMooTitle('  mooR  '), equals('mooR'));
      expect(normalizeMooTitle('   '), isNull);
      expect(normalizeMooTitle(null), isNull);
    });

    test(
      'buildSessionVerbSuggestionsResultFromSuggestions sorts @ verbs last',
      () {
        final result = buildSessionVerbSuggestionsResultFromSuggestions(
          const <VerbSuggestion>[
            VerbSuggestion(
              verb: '@admin',
              hint: 'admin hint',
              placeholderText: null,
            ),
            VerbSuggestion(
              verb: 'look',
              hint: null,
              placeholderText: 'look around',
            ),
          ],
          suggestionsAvailable: true,
          decodedLiteral: '{...}',
          decodedWasNone: false,
        );

        expect(result.suggestionsAvailable, isTrue);
        expect(result.serverPlaceholderText, equals('look around'));
        expect(result.paletteVerbs.map((verb) => verb.verb).toList(), <String>[
          'look',
          '@admin',
        ]);
        expect(result.debugMessage, isNull);
      },
    );
  });
}
