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

import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';

class SessionVerbSuggestionsResult {
  final bool suggestionsAvailable;
  final String? serverPlaceholderText;
  final List<PaletteVerb> paletteVerbs;
  final String? debugMessage;

  const SessionVerbSuggestionsResult({
    required this.suggestionsAvailable,
    required this.serverPlaceholderText,
    required this.paletteVerbs,
    required this.debugMessage,
  });
}

class SessionBootstrapService {
  final MoorHttpApi api;

  SessionBootstrapService({
    required this.api,
  });

  Future<String?> fetchMooTitle({required String authToken}) {
    return api.fetchMooTitle(authToken: authToken);
  }

  Future<SessionVerbSuggestionsResult> loadVerbSuggestions({
    required String authToken,
    required String playerCurie,
  }) async {
    final success = await api.invokeVerb(
      authToken: authToken,
      objectCurie: playerCurie,
      verbName: 'verb_suggestions',
    );
    final decoded = success.result != null
        ? MoorVar.fromFlatBuffer(success.result!)
        : moorNoneVar;
    return buildSessionVerbSuggestionsResult(decoded);
  }
}

SessionVerbSuggestionsResult buildSessionVerbSuggestionsResult(
  MoorVar decoded,
) {
  final suggestions = parseVerbSuggestions(decoded);
  return buildSessionVerbSuggestionsResultFromSuggestions(
    suggestions,
    suggestionsAvailable: decoded.asList() != null,
    decodedLiteral: decoded.toLiteral(),
    decodedWasNone: decoded.isNone(),
  );
}

SessionVerbSuggestionsResult buildSessionVerbSuggestionsResultFromSuggestions(
  List<VerbSuggestion> suggestions, {
  required bool suggestionsAvailable,
  required String decodedLiteral,
  required bool decodedWasNone,
}) {
  final placeholder = suggestions
      .where((suggestion) => suggestion.placeholderText != null)
      .firstOrNull;

  final verbs = <PaletteVerb>[
    for (final suggestion in suggestions) suggestionToPaletteVerb(suggestion),
  ]..sort((a, b) {
      final aIsAt = a.verb.startsWith('@');
      final bIsAt = b.verb.startsWith('@');
      if (aIsAt == bIsAt) return 0;
      return aIsAt ? 1 : -1;
    });

  return SessionVerbSuggestionsResult(
    suggestionsAvailable: suggestionsAvailable,
    serverPlaceholderText: placeholder?.placeholderText,
    paletteVerbs: verbs,
    debugMessage: !decodedWasNone && suggestions.isEmpty
        ? 'verb_suggestions returned no suggestions (decoded=$decodedLiteral)'
        : null,
  );
}

String? normalizeMooTitle(String? title) {
  if (title == null) {
    return null;
  }
  final trimmed = title.trim();
  return trimmed.isEmpty ? null : trimmed;
}
