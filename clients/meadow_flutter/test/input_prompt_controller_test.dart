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
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/input_prompt_controller.dart';

void main() {
  group('InputPromptController', () {
    test('stores active request and exposes initial value', () {
      final controller = InputPromptController();
      addTearDown(controller.dispose);
      const request = InputPromptRequest(
        requestId: 'req-1',
        metadata: InputPromptMetadata(
          inputType: 'text',
          prompt: 'Prompt',
          ttsPrompt: null,
          choices: <String>[],
          min: null,
          max: null,
          defaultValue: 'hello',
          placeholder: null,
          rows: null,
          alternativeLabel: null,
          alternativePlaceholder: null,
          acceptContentTypes: <String>[],
          maxFileSize: null,
        ),
      );

      expect(controller.handleRequest(request), isTrue);
      expect(controller.current, same(request));
      expect(controller.hasActivePrompt, isTrue);
      expect(controller.initialValue, equals('hello'));
    });

    test('clear removes active request', () {
      final controller = InputPromptController();
      addTearDown(controller.dispose);
      controller.handleRequest(
        const InputPromptRequest(
          requestId: 'req-1',
          metadata: InputPromptMetadata(
            inputType: 'text',
            prompt: null,
            ttsPrompt: null,
            choices: <String>[],
            min: null,
            max: null,
            defaultValue: null,
            placeholder: null,
            rows: null,
            alternativeLabel: null,
            alternativePlaceholder: null,
            acceptContentTypes: <String>[],
            maxFileSize: null,
          ),
        ),
      );

      expect(controller.clear(), isTrue);
      expect(controller.current, isNull);
      expect(controller.hasActivePrompt, isFalse);
      expect(controller.clear(), isFalse);
    });
  });
}
