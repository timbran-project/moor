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

import 'dart:typed_data';

class WelcomeMessage {
  final List<String> lines;
  final String contentType;

  const WelcomeMessage({
    required this.lines,
    required this.contentType,
  });
}

class LoginSession {
  final Uri baseUri;
  final String authToken;
  final String playerCurie;
  final int playerFlags;
  final String? clientToken;
  final String? clientId;
  final bool isInitialAttach;

  const LoginSession({
    required this.baseUri,
    required this.authToken,
    required this.playerCurie,
    required this.playerFlags,
    required this.clientToken,
    required this.clientId,
    required this.isInitialAttach,
  });
}

class NarrativeItem {
  final String id;
  final DateTime timestamp;
  final List<String> content;
  final String contentType;
  final bool noNewline;
  final String? presentationHint;
  final Map<String, Object?>? eventMetadata;

  const NarrativeItem({
    required this.id,
    required this.timestamp,
    required this.content,
    required this.contentType,
    required this.noNewline,
    required this.presentationHint,
    required this.eventMetadata,
  });
}

class EncryptedHistoricalEvent {
  final Uint8List encryptedBlob;
  final bool isHistorical;

  const EncryptedHistoricalEvent({
    required this.encryptedBlob,
    required this.isHistorical,
  });
}
