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
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/ws_client.dart';

class SessionConnectionController extends ChangeNotifier {
  final LoginSession session;
  final String mode;
  final void Function(String message) onSystemMessage;
  final void Function(NarrativeItem item) onNarrativeItem;
  final void Function(DockItem item) onPresentationUpsert;
  final void Function(String id) onPresentationRemove;
  final void Function(InputPromptRequest request) onInputPromptRequest;
  final void Function(String status)? onStatusChanged;

  MoorWsClient? _ws;
  String _status = 'disconnected';

  SessionConnectionController({
    required this.session,
    required this.mode,
    required this.onSystemMessage,
    required this.onNarrativeItem,
    required this.onPresentationUpsert,
    required this.onPresentationRemove,
    required this.onInputPromptRequest,
    this.onStatusChanged,
  });

  String get status => _status;

  Future<void> connect() async {
    _setStatus('connecting');

    final ws = MoorWsClient(
      session: session,
      onSystemMessage: onSystemMessage,
      onNarrativeItem: onNarrativeItem,
      onPresentationUpsert: onPresentationUpsert,
      onPresentationRemove: onPresentationRemove,
      onInputPromptRequest: onInputPromptRequest,
      onConnectionStatusChanged: _handleStatusChanged,
    );
    _ws = ws;

    try {
      final connected = await ws.connect(mode: mode);
      if (!connected) {
        _setStatus('error');
      }
    } on Object catch (e) {
      onSystemMessage('WS connect failed: $e');
      _setStatus('error');
    }
  }

  void sendText(String message) {
    _ws?.sendText(message);
  }

  void close() {
    _ws?.close();
  }

  void _handleStatusChanged(String status) {
    _setStatus(status);
    onStatusChanged?.call(status);
  }

  void _setStatus(String status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }
}
