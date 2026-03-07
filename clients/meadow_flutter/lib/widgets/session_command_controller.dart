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
import 'package:flutter/services.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';
import 'package:meadow_flutter/widgets/command_controller.dart';

class SessionCommandController extends ChangeNotifier {
  static const int maxCommandHistory = 500;

  final CommandEditingController inputController;

  final List<String> _commandHistory = <String>[];
  final Map<int, String> _historyBuffer = <int, String>{};

  bool _verbPaletteEnabled;
  bool _verbSuggestionsAvailable = false;
  int _historyOffset = 0;
  String? _serverPlaceholderText;
  String? _verbPill;
  String? _verbPillPlaceholder;
  List<PaletteVerb> _paletteVerbs;

  VoidCallback? onPillCleared;
  VoidCallback? onPillSelected;

  SessionCommandController({
    CommandEditingController? inputController,
    bool verbPaletteEnabled = true,
    List<PaletteVerb> initialPaletteVerbs = paletteVerbsFallback,
  }) : inputController = inputController ?? CommandEditingController(),
       _paletteVerbs = List<PaletteVerb>.of(initialPaletteVerbs),
       _verbPaletteEnabled = verbPaletteEnabled {
    this.inputController
      ..onPillCleared = _handlePillCleared
      ..onPillSelected = _handlePillSelected;
    this.inputController.addListener(_updateVerbCompletionGhost);
  }

  List<PaletteVerb> get paletteVerbs => List<PaletteVerb>.unmodifiable(
    _paletteVerbs,
  );
  String? get serverPlaceholderText => _serverPlaceholderText;
  bool get verbPaletteEnabled => _verbPaletteEnabled;
  String? get verbPill => _verbPill;
  String? get verbPillPlaceholder => _verbPillPlaceholder;
  bool get verbSuggestionsAvailable => _verbSuggestionsAvailable;
  Color get placeholderColor => inputController.placeholderColor;

  set placeholderColor(Color color) {
    inputController.placeholderColor = color;
  }

  set verbPaletteEnabled(bool value) {
    if (value == _verbPaletteEnabled) {
      return;
    }
    _verbPaletteEnabled = value;
    _updateVerbCompletionGhost();
    notifyListeners();
  }

  @override
  void dispose() {
    inputController
      ..removeListener(_updateVerbCompletionGhost)
      ..dispose();
    super.dispose();
  }

  void selectPaletteVerb(PaletteVerb verb) {
    final changed = _setVerbPill(
      verb: verb.verb,
      placeholder: verb.placeholder,
    );
    inputController.setVerbPill(
      verb: verb.verb,
      placeholder: verb.placeholder,
    );
    if (changed) {
      notifyListeners();
    }
  }

  void updateVerbSuggestions({
    required bool suggestionsAvailable,
    required String? serverPlaceholderText,
    required List<PaletteVerb> paletteVerbs,
  }) {
    final nextPaletteVerbs = paletteVerbs.isNotEmpty
        ? List<PaletteVerb>.of(paletteVerbs)
        : List<PaletteVerb>.of(paletteVerbsFallback);
    final didChange =
        _verbSuggestionsAvailable != suggestionsAvailable ||
        _serverPlaceholderText != serverPlaceholderText ||
        !_samePaletteVerbList(_paletteVerbs, nextPaletteVerbs);
    _verbSuggestionsAvailable = suggestionsAvailable;
    _serverPlaceholderText = serverPlaceholderText;
    _paletteVerbs = nextPaletteVerbs;
    _updateVerbCompletionGhost();
    if (didChange) {
      notifyListeners();
    }
  }

  List<String> consumeCommandsToSend() {
    final input = inputController.commandText;
    if (input.trim().isEmpty && (_verbPill == null || _verbPill!.isEmpty)) {
      return const <String>[];
    }

    final commandsSent = <String>[];
    for (final line in input.split('\n')) {
      final cmd = line.trim();
      if (cmd.isEmpty) {
        continue;
      }
      commandsSent.add(_verbPill == null ? cmd : '${_verbPill!} $cmd');
    }
    if (commandsSent.isEmpty && _verbPill != null && _verbPill!.isNotEmpty) {
      commandsSent.add(_verbPill!);
    }
    if (commandsSent.isEmpty) {
      return const <String>[];
    }

    _commandHistory.addAll(commandsSent);
    if (_commandHistory.length > maxCommandHistory) {
      final start = _commandHistory.length - maxCommandHistory;
      _commandHistory.removeRange(0, start);
    }

    _historyBuffer.clear();
    _historyOffset = 0;
    final changed = _clearVerbPillState();
    inputController
      ..verbPill = null
      ..verbPillPlaceholder = null
      ..ghostCompletion = null
      ..clear();
    if (changed) {
      notifyListeners();
    }
    return commandsSent;
  }

  KeyEventResult handleKeyEvent(
    KeyEvent event, {
    required VoidCallback onSend,
  }) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final text = inputController.text;
    final sel = inputController.selection;
    final selStart = sel.isValid
        ? (sel.baseOffset < sel.extentOffset
              ? sel.baseOffset
              : sel.extentOffset)
        : -1;
    final selEnd = sel.isValid
        ? (sel.baseOffset > sel.extentOffset
              ? sel.baseOffset
              : sel.extentOffset)
        : -1;
    final isCollapsed = selStart >= 0 && selStart == selEnd;
    final isMultiline = text.contains('\n');
    final cursorAtEdge =
        selStart <= 0 || (isCollapsed && selStart >= text.length);

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!isMultiline || cursorAtEdge) {
        _navigateHistory(1);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (!isMultiline || cursorAtEdge) {
        _navigateHistory(-1);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (!shift) {
        onSend();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (!shift && promoteLeadingTokenToPill()) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (inputController.handleBackspaceAtPillBoundary()) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  bool promoteLeadingTokenToPill() {
    if (!_verbPaletteEnabled || _verbPill != null) {
      return false;
    }
    final cmd = inputController.commandText;
    if (cmd.contains('\n')) {
      return false;
    }
    final token = cmd.trim();
    if (token.isEmpty) {
      return false;
    }
    final suggestion = bestVerbCompletion(token);
    if (suggestion == null) {
      return false;
    }
    final changed = _setVerbPill(
      verb: suggestion.verb,
      placeholder: suggestion.placeholder,
    );
    inputController.promoteLeadingTokenToPill(
      verb: suggestion.verb,
      placeholder: suggestion.placeholder,
    );
    if (changed) {
      notifyListeners();
    }
    return true;
  }

  PaletteVerb? bestVerbCompletion(String token) {
    if (_paletteVerbs.isEmpty) {
      return null;
    }
    final lower = token.toLowerCase();
    for (final verb in _paletteVerbs) {
      if (verb.verb.toLowerCase() == lower) {
        return verb;
      }
    }
    for (final verb in _paletteVerbs) {
      if (verb.verb.toLowerCase().startsWith(lower) &&
          verb.verb.length > token.length) {
        return verb;
      }
    }
    return null;
  }

  void _handlePillCleared() {
    final changed = _clearVerbPillState();
    if (changed) {
      notifyListeners();
    }
    onPillCleared?.call();
  }

  void _handlePillSelected() {
    onPillSelected?.call();
  }

  bool _setVerbPill({
    required String verb,
    required String? placeholder,
  }) {
    if (_verbPill == verb && _verbPillPlaceholder == placeholder) {
      return false;
    }
    _verbPill = verb;
    _verbPillPlaceholder = placeholder;
    return true;
  }

  bool _clearVerbPillState() {
    final changed =
        _verbPill != null ||
        _verbPillPlaceholder != null ||
        inputController.ghostCompletion != null;
    _verbPill = null;
    _verbPillPlaceholder = null;
    return changed;
  }

  void _updateVerbCompletionGhost() {
    if (!_verbPaletteEnabled || _verbPill != null) {
      _setGhostCompletion(null);
      return;
    }

    final cmd = inputController.commandText;
    if (cmd.contains('\n')) {
      _setGhostCompletion(null);
      return;
    }

    if (cmd.trim().isEmpty || cmd.contains(' ') || cmd.contains('\t')) {
      _setGhostCompletion(null);
      return;
    }

    final sel = inputController.selection;
    final atEnd =
        sel.isValid &&
        sel.isCollapsed &&
        sel.baseOffset == inputController.text.length;
    if (!atEnd) {
      _setGhostCompletion(null);
      return;
    }

    final suggestion = bestVerbCompletion(cmd);
    final ghost = suggestion?.verb.substring(cmd.length);
    _setGhostCompletion(ghost);
  }

  void _setGhostCompletion(String? ghost) {
    if (ghost == inputController.ghostCompletion) {
      return;
    }
    inputController.ghostCompletion = ghost;
    notifyListeners();
  }

  void _navigateHistory(int delta) {
    if (_commandHistory.isEmpty) {
      return;
    }

    final canNavigate = delta > 0
        ? _historyOffset < _commandHistory.length
        : _historyOffset > 0;
    if (!canNavigate) {
      return;
    }

    final currentText = inputController.commandText;
    _historyBuffer[_historyOffset] = currentText;

    final nextOffset = (_historyOffset + delta).clamp(
      0,
      _commandHistory.length,
    );
    _historyOffset = nextOffset;

    String nextText;
    final buffered = _historyBuffer[nextOffset];
    if (buffered != null) {
      nextText = buffered;
    } else if (nextOffset == 0) {
      nextText = '';
    } else {
      final idx = _commandHistory.length - nextOffset;
      nextText = (idx >= 0 && idx < _commandHistory.length)
          ? _commandHistory[idx]
          : '';
    }

    inputController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  bool _samePaletteVerbList(List<PaletteVerb> a, List<PaletteVerb> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].verb != b[i].verb ||
          a[i].label != b[i].label ||
          a[i].placeholder != b[i].placeholder) {
        return false;
      }
    }
    return true;
  }
}
