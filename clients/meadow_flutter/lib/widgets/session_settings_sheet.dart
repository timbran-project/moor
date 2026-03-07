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

class SessionSettingsSheet extends StatefulWidget {
  final SessionViewSettings initialSettings;
  final ValueChanged<SessionViewSettings> onSettingsChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const SessionSettingsSheet({
    super.key,
    required this.initialSettings,
    required this.onSettingsChanged,
    required this.onThemeModeChanged,
  });

  @override
  State<SessionSettingsSheet> createState() => _SessionSettingsSheetState();
}

class _SessionSettingsSheetState extends State<SessionSettingsSheet> {
  late SessionViewSettings _settings = widget.initialSettings;

  void _update(SessionViewSettings next) {
    setState(() {
      _settings = next;
    });
    widget.onSettingsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Settings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _settings.roomHudEnabled,
              title: const Text('Room HUD'),
              subtitle: const Text('Show room description when scrolled out'),
              onChanged: (value) {
                _update(_settings.copyWith(roomHudEnabled: value));
              },
            ),
            SwitchListTile(
              value: _settings.showNarrativeMeta,
              title: const Text('Timestamps'),
              subtitle: const Text('Show timestamp and content type per line'),
              onChanged: (value) {
                _update(_settings.copyWith(showNarrativeMeta: value));
              },
            ),
            SwitchListTile(
              value: _settings.monospaceNarrative,
              title: const Text('Monospace output'),
              subtitle: const Text(
                'Render narrative/panels in monospace (better alignment)',
              ),
              onChanged: (value) {
                _update(_settings.copyWith(monospaceNarrative: value));
              },
            ),
            SwitchListTile(
              value: _settings.verbPaletteEnabled,
              title: const Text('Verb palette'),
              subtitle: Text(
                _settings.verbSuggestionsAvailable
                    ? 'Show quick verbs (server)'
                    : 'Show quick verbs (fallback)',
              ),
              onChanged: (value) {
                _update(_settings.copyWith(verbPaletteEnabled: value));
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Theme',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.light,
                  label: Text('Light'),
                ),
                ButtonSegment<ThemeMode>(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                ),
              ],
              selected: {_settings.themeMode},
              onSelectionChanged: (selection) {
                final next = selection.first;
                _update(_settings.copyWith(themeMode: next));
                widget.onThemeModeChanged(next);
              },
            ),
          ],
        ),
      ),
    );
  }
}
