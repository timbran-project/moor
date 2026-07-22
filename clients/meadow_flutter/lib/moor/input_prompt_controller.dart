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

import 'package:flutter/foundation.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';

class InputPromptController extends ChangeNotifier {
  InputPromptRequest? _current;

  InputPromptRequest? get current => _current;
  bool get hasActivePrompt => _current != null;
  String get initialValue => _current?.metadata.defaultValue?.toString() ?? '';

  bool handleRequest(InputPromptRequest request) {
    final didChange =
        _current?.requestId != request.requestId ||
        _current?.metadata.defaultValue != request.metadata.defaultValue ||
        _current?.metadata.inputType != request.metadata.inputType;
    _current = request;
    if (didChange) {
      notifyListeners();
    }
    return didChange;
  }

  bool clear() {
    if (_current == null) {
      return false;
    }
    _current = null;
    notifyListeners();
    return true;
  }
}
