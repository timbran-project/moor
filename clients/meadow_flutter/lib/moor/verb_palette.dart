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

class VerbSuggestion {
  final String verb;
  final String? hint;
  final String? placeholderText;

  const VerbSuggestion({
    required this.verb,
    required this.hint,
    required this.placeholderText,
  });
}

class PaletteVerb {
  final String verb;
  final String label;
  final String? placeholder;

  const PaletteVerb({
    required this.verb,
    required this.label,
    required this.placeholder,
  });
}

const paletteVerbsFallback = <PaletteVerb>[
  PaletteVerb(
    verb: 'say',
    label: 'Say',
    placeholder: 'What would you like to say?',
  ),
  PaletteVerb(
    verb: 'emote',
    label: 'Emote',
    placeholder: 'What are you doing?',
  ),
  PaletteVerb(
    verb: 'look',
    label: 'Look',
    placeholder: 'Where would you like to look?',
  ),
  PaletteVerb(
    verb: 'help',
    label: 'Help',
    placeholder: 'What do you need help with?',
  ),
  PaletteVerb(verb: 'inventory', label: 'Inv', placeholder: null),
  PaletteVerb(
    verb: 'get',
    label: 'Get',
    placeholder: 'What would you like to pick up?',
  ),
  PaletteVerb(
    verb: 'drop',
    label: 'Drop',
    placeholder: 'What would you like to drop?',
  ),
  PaletteVerb(
    verb: 'go',
    label: 'Go',
    placeholder: 'Where would you like to go?',
  ),
  PaletteVerb(
    verb: 'examine',
    label: 'Exam',
    placeholder: 'What would you like to examine?',
  ),
];

String _extractVerbName(String verbPattern) {
  // Meadow web: "l*ook" -> "look". We also take only the first token if the
  // server returns multiple patterns.
  final first = verbPattern.trim().split(RegExp(r'\s+')).first;
  return first.replaceAll('*', '');
}

String _extractVerbLabel(String verbPattern) {
  final base = _extractVerbName(verbPattern);
  final staticEntry = paletteVerbsFallback
      .where((v) => v.verb == base)
      .firstOrNull;
  if (staticEntry != null) {
    return staticEntry.label;
  }
  if (base.isEmpty) return '';
  return base[0].toUpperCase() + base.substring(1);
}

PaletteVerb suggestionToPaletteVerb(VerbSuggestion suggestion) {
  final verb = _extractVerbName(suggestion.verb);
  final staticEntry = paletteVerbsFallback
      .where((v) => v.verb == verb)
      .firstOrNull;
  final placeholder =
      (suggestion.hint != null && suggestion.hint!.trim().isNotEmpty)
      ? suggestion.hint
      : staticEntry?.placeholder;
  return PaletteVerb(
    verb: verb,
    label: _extractVerbLabel(suggestion.verb),
    placeholder: placeholder,
  );
}

List<VerbSuggestion> parseVerbSuggestionsLoose(Object? decoded) {
  if (decoded is! List) return const <VerbSuggestion>[];
  final out = <VerbSuggestion>[];
  for (final it in decoded) {
    if (it is! Map) continue;
    final verb = it['verb'];
    if (verb is! String || verb.trim().isEmpty) continue;
    final hint = it['hint'];
    final placeholderText = it['placeholder_text'];
    out.add(
      VerbSuggestion(
        verb: verb,
        hint: hint is String ? hint : null,
        placeholderText: placeholderText is String ? placeholderText : null,
      ),
    );
  }
  return out;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final v in this) {
      return v;
    }
    return null;
  }
}
