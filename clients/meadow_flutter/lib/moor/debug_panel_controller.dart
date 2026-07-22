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
import 'package:meadow_flutter/moor/presentations.dart';

typedef DebugTimestampProvider = DateTime Function();

class DebugPanelController extends ChangeNotifier {
  static const String panelId = 'local-debug-panel';
  static const int _maxLines = 500;

  final DebugTimestampProvider _now;
  final List<String> _lines = <String>[];
  bool _visible = false;

  DebugPanelController({DebugTimestampProvider? now})
    : _now = now ?? DateTime.now;

  bool get visible => _visible;
  List<String> get lines => List<String>.unmodifiable(_lines);

  void appendLine(String line, PresentationStore presentations) {
    final ts = _now().toIso8601String().split('T').last;
    _lines.add('[$ts] $line');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    _syncPresentation(presentations);
  }

  void toggle(PresentationStore presentations) {
    _visible = !_visible;
    notifyListeners();
    _syncPresentation(presentations);
  }

  void hide(PresentationStore presentations) {
    if (!_visible) {
      presentations.remove(panelId);
      return;
    }
    _visible = false;
    notifyListeners();
    presentations.remove(panelId);
  }

  void _syncPresentation(PresentationStore presentations) {
    if (!_visible) {
      presentations.remove(panelId);
      return;
    }
    final content = _lines.isEmpty ? '(debug output)' : _lines.join('\n');
    presentations.upsert(
      PresentationModel(
        id: panelId,
        target: 'right',
        contentType: 'text/plain',
        content: content,
        attrs: const <String, String>{
          'title': 'Debug',
          'source': 'local_debug',
          'kind': 'debug_output',
        },
      ),
    );
  }
}
