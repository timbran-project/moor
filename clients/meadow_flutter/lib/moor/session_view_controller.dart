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

@immutable
class SessionViewSettings {
  final bool roomHudEnabled;
  final bool showNarrativeMeta;
  final bool verbPaletteEnabled;
  final bool monospaceNarrative;
  final bool verbSuggestionsAvailable;
  final ThemeMode themeMode;

  const SessionViewSettings({
    required this.roomHudEnabled,
    required this.showNarrativeMeta,
    required this.verbPaletteEnabled,
    required this.monospaceNarrative,
    required this.verbSuggestionsAvailable,
    required this.themeMode,
  });

  SessionViewSettings copyWith({
    bool? roomHudEnabled,
    bool? showNarrativeMeta,
    bool? verbPaletteEnabled,
    bool? monospaceNarrative,
    bool? verbSuggestionsAvailable,
    ThemeMode? themeMode,
  }) {
    return SessionViewSettings(
      roomHudEnabled: roomHudEnabled ?? this.roomHudEnabled,
      showNarrativeMeta: showNarrativeMeta ?? this.showNarrativeMeta,
      verbPaletteEnabled: verbPaletteEnabled ?? this.verbPaletteEnabled,
      monospaceNarrative: monospaceNarrative ?? this.monospaceNarrative,
      verbSuggestionsAvailable:
          verbSuggestionsAvailable ?? this.verbSuggestionsAvailable,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SessionViewController extends ChangeNotifier {
  bool _roomHudEnabled = true;
  bool _showNarrativeMeta = false;
  bool _verbPaletteEnabled = true;
  bool _monospaceNarrative = false;

  bool get roomHudEnabled => _roomHudEnabled;
  bool get showNarrativeMeta => _showNarrativeMeta;
  bool get verbPaletteEnabled => _verbPaletteEnabled;
  bool get monospaceNarrative => _monospaceNarrative;

  SessionViewSettings settings({
    required bool verbSuggestionsAvailable,
    required ThemeMode themeMode,
  }) {
    return SessionViewSettings(
      roomHudEnabled: roomHudEnabled,
      showNarrativeMeta: showNarrativeMeta,
      verbPaletteEnabled: verbPaletteEnabled,
      monospaceNarrative: monospaceNarrative,
      verbSuggestionsAvailable: verbSuggestionsAvailable,
      themeMode: themeMode,
    );
  }

  void applySettings(SessionViewSettings settings) {
    final didChange =
        _roomHudEnabled != settings.roomHudEnabled ||
        _showNarrativeMeta != settings.showNarrativeMeta ||
        _verbPaletteEnabled != settings.verbPaletteEnabled ||
        _monospaceNarrative != settings.monospaceNarrative;
    if (!didChange) {
      return;
    }

    _roomHudEnabled = settings.roomHudEnabled;
    _showNarrativeMeta = settings.showNarrativeMeta;
    _verbPaletteEnabled = settings.verbPaletteEnabled;
    _monospaceNarrative = settings.monospaceNarrative;
    notifyListeners();
  }
}
