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

import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

class InputPromptMetadata {
  final String? inputType;
  final String? prompt;
  final String? ttsPrompt;
  final List<String> choices;
  final num? min;
  final num? max;
  final Object? defaultValue;
  final String? placeholder;
  final int? rows;
  final String? alternativeLabel;
  final String? alternativePlaceholder;
  final List<String> acceptContentTypes;
  final int? maxFileSize;

  const InputPromptMetadata({
    required this.inputType,
    required this.prompt,
    required this.ttsPrompt,
    required this.choices,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.placeholder,
    required this.rows,
    required this.alternativeLabel,
    required this.alternativePlaceholder,
    required this.acceptContentTypes,
    required this.maxFileSize,
  });
}

class InputPromptRequest {
  final String requestId;
  final InputPromptMetadata metadata;

  const InputPromptRequest({
    required this.requestId,
    required this.metadata,
  });
}

InputPromptMetadata parseInputPromptMetadata(Map<String, MoorVar> metadata) {
  final choices = <String>[];
  final acceptContentTypes = <String>[];
  num? min;
  num? max;
  Object? defaultValue;
  String? inputType;
  String? prompt;
  String? ttsPrompt;
  String? placeholder;
  int? rows;
  String? alternativeLabel;
  String? alternativePlaceholder;
  int? maxFileSize;

  for (final entry in metadata.entries) {
    final key = entry.key;
    final value = entry.value;
    switch (key) {
      case 'input_type':
        inputType = value.asString();
      case 'prompt':
        prompt = value.asString();
      case 'tts_prompt':
        ttsPrompt = value.asString();
      case 'choices':
        final list = value.asList();
        if (list != null) {
          for (final v in list.elements) {
            final s = v.asString();
            if (s != null && s.isNotEmpty) {
              choices.add(s);
            }
          }
        }
      case 'min':
        min = value.asInt() ?? value.asFloat();
      case 'max':
        max = value.asInt() ?? value.asFloat();
      case 'default':
        defaultValue = value.value;
      case 'placeholder':
        placeholder = value.asString();
      case 'rows':
        rows = value.asInt();
      case 'alternative_label':
        alternativeLabel = value.asString();
      case 'alternative_placeholder':
        alternativePlaceholder = value.asString();
      case 'accept_content_types':
        final list = value.asList();
        if (list != null) {
          for (final v in list.elements) {
            final s = v.asString();
            if (s != null && s.isNotEmpty) {
              acceptContentTypes.add(s);
            }
          }
        }
      case 'max_file_size':
        maxFileSize = value.asInt();
      case 'metadata':
        final map = value.asMap();
        if (map != null) {
          for (final pair in map.pairs.entries) {
            final k = pair.key.toKey();
            if (k == 'tts_prompt') {
              ttsPrompt = pair.value.coerceText();
            }
          }
        } else {
          final list = value.asList();
          if (list != null) {
            for (final pair in list.elements) {
              final e = pair.asList();
              if (e == null || e.elements.length != 2) continue;
              final k = e.elements[0].toKey();
              if (k == 'tts_prompt') {
                ttsPrompt = e.elements[1].coerceText();
              }
            }
          }
        }
    }
  }

  return InputPromptMetadata(
    inputType: inputType,
    prompt: prompt,
    ttsPrompt: ttsPrompt,
    choices: choices,
    min: min,
    max: max,
    defaultValue: defaultValue,
    placeholder: placeholder,
    rows: rows,
    alternativeLabel: alternativeLabel,
    alternativePlaceholder: alternativePlaceholder,
    acceptContentTypes: acceptContentTypes,
    maxFileSize: maxFileSize,
  );
}
