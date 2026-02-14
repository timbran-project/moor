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

import 'dart:async';
import 'dart:typed_data';

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/flatbuffers_util.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/room_snapshot.dart';
import 'package:meadow_flutter/moor/var_decode.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MoorWsClient {
  final LoginSession session;
  final void Function(String message) onSystemMessage;
  final void Function(NarrativeItem item) onNarrativeItem;
  final void Function(DockItem p) onPresentationUpsert;
  final void Function(String id) onPresentationRemove;
  final void Function({required String clientId, required String clientToken})?
  onCredentialsUpdated;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _keepalive;

  // Server heartbeat request marker (single byte 0x02); client replies with 0x01.
  static const int _heartbeatRequest = 0x02;
  static final Uint8List _heartbeatResponse = Uint8List.fromList([0x01]);

  // Application keepalive marker: a single 0x00 byte (not a valid FlatBuffer).
  static final Uint8List _keepaliveMarker = Uint8List.fromList([0x00]);

  MoorWsClient({
    required this.session,
    required this.onSystemMessage,
    required this.onNarrativeItem,
    required this.onPresentationUpsert,
    required this.onPresentationRemove,
    this.onCredentialsUpdated,
  });

  bool get isConnected => _channel != null;

  Future<void> connect({required String mode}) async {
    if (_channel != null) {
      return;
    }

    final wsBase = _wsBaseUri(session.baseUri);
    final wsUrl = wsBase.replace(path: '/ws/attach/$mode');
    final protocols = <String>[
      'moor',
      'paseto.${session.authToken}',
    ];

    if (session.isInitialAttach) {
      protocols.add('initial_attach.true');
    }
    if (session.clientId != null && session.clientToken != null) {
      protocols
        ..add('client_id.${session.clientId}')
        ..add('client_token.${session.clientToken}');
    }

    onSystemMessage('Connecting WebSocket: $wsUrl');
    final channel = WebSocketChannel.connect(wsUrl, protocols: protocols);
    _channel = channel;

    // Keepalive to prevent proxy idle timeouts (Meadow uses 45s).
    _keepalive = Timer.periodic(const Duration(seconds: 45), (_) {
      try {
        _channel?.sink.add(_keepaliveMarker);
      } on Object catch (_) {
        // Best-effort.
      }
    });

    _sub = channel.stream.listen(
      _handleMessage,
      onError: (Object err) {
        onSystemMessage('WebSocket error: $err');
      },
      onDone: () {
        onSystemMessage('WebSocket closed');
        close();
      },
      cancelOnError: false,
    );
  }

  void sendText(String message) {
    final ch = _channel;
    if (ch == null) {
      onSystemMessage('Not connected');
      return;
    }
    ch.sink.add(message);
  }

  void close() {
    _keepalive?.cancel();
    _keepalive = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } on Object catch (_) {
      // ignore
    }
    _channel = null;
  }

  Uri _wsBaseUri(Uri httpBase) {
    final isSecure = httpBase.scheme == 'https';
    return httpBase.replace(
      scheme: isSecure ? 'wss' : 'ws',
    );
  }

  void _handleMessage(dynamic msg) {
    Uint8List data;
    if (msg is Uint8List) {
      data = msg;
    } else if (msg is List<int>) {
      data = Uint8List.fromList(msg);
    } else {
      // Meadow expects binary; server may send text only for debugging.
      onSystemMessage('WS non-binary message: $msg');
      return;
    }

    if (data.length == 1 && data[0] == _heartbeatRequest) {
      try {
        _channel?.sink.add(_heartbeatResponse);
      } on Object catch (_) {
        // ignore
      }
      return;
    }

    // KEEPALIVE_MARKER echoes shouldn't happen; ignore.
    if (data.length == 1 && data[0] == 0x00) {
      return;
    }

    try {
      final ev = moor_rpc.ClientEvent(data);
      _dispatchClientEvent(ev);
    } on Object catch (e) {
      onSystemMessage('WS decode failed: $e');
    }
  }

  void _dispatchClientEvent(moor_rpc.ClientEvent ev) {
    final type = ev.eventType?.value ?? 0;

    if (type == moor_rpc.ClientEventUnionTypeId.SystemMessageEvent.value) {
      final sys = ev.event as moor_rpc.SystemMessageEvent?;
      final msg = sys?.message;
      if (msg != null && msg.isNotEmpty) {
        onSystemMessage(msg);
      }
      return;
    }

    if (type == moor_rpc.ClientEventUnionTypeId.CredentialsUpdatedEvent.value) {
      final creds = ev.event as moor_rpc.CredentialsUpdatedEvent?;
      final clientToken = creds?.clientToken?.token;
      final clientIdBytes = creds?.clientId?.data;
      if (clientToken == null ||
          clientIdBytes == null ||
          clientIdBytes.length != 16) {
        onSystemMessage('WS: CredentialsUpdatedEvent missing fields');
        return;
      }
      final hex = clientIdBytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final clientId =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      onSystemMessage('WS: updated session credentials (client_id=$clientId)');
      onCredentialsUpdated?.call(clientId: clientId, clientToken: clientToken);
      return;
    }

    if (type == moor_rpc.ClientEventUnionTypeId.NarrativeEventMessage.value) {
      final m = ev.event as moor_rpc.NarrativeEventMessage?;
      final evt = m?.event;
      if (evt == null) {
        return;
      }

      final ts = DateTime.fromMillisecondsSinceEpoch(
        (evt.timestamp / 1000000).toInt(),
        isUtc: true,
      ).toLocal();
      final e = evt.event;
      if (e == null) {
        return;
      }

      if (e.eventType?.value ==
          moor_common.EventUnionTypeId.NotifyEvent.value) {
        final notify = e.event as moor_common.NotifyEvent?;
        if (notify == null) {
          return;
        }
        final content = decodeVarAsLines(notify.value);
        if (content.isEmpty) return;

        final ct = normalizeContentType(notify.contentType?.value);

        String? presentationHint;
        final eventMetadata = <String, Object?>{};
        final md = notify.metadata;
        if (md != null) {
          for (final m in md) {
            final k = m.key?.value;
            if (k == null || k.isEmpty) continue;
            final v = decodeVarLoose(m.value);
            eventMetadata[k] = v;
            if (presentationHint == null &&
                (k == 'presentation_hint' || k == 'presentationHint') &&
                v is String) {
              presentationHint = v;
            }
          }
        }

        onNarrativeItem(
          NarrativeItem(
            id: _newId(),
            timestamp: ts,
            content: content,
            contentType: ct,
            noNewline: notify.noNewline,
            presentationHint: presentationHint,
            eventMetadata: eventMetadata.isEmpty ? null : eventMetadata,
          ),
        );
      }

      if (e.eventType?.value ==
          moor_common.EventUnionTypeId.PresentEvent.value) {
        final present = e.event as moor_common.PresentEvent?;
        final pres = present?.presentation;
        if (pres == null) {
          return;
        }

        final model = presentationFromFb(pres);
        if (model != null) {
          onPresentationUpsert(model);
        }

        onNarrativeItem(
          NarrativeItem(
            id: _newId(),
            timestamp: ts,
            content: [pres.content ?? ''],
            contentType: normalizeContentType(pres.contentType),
            noNewline: false,
            presentationHint: null,
            eventMetadata: null,
          ),
        );
      }

      if (e.eventType?.value ==
          moor_common.EventUnionTypeId.UnpresentEvent.value) {
        final unpresent = e.event as moor_common.UnpresentEvent?;
        final id = unpresent?.presentationId;
        if (id != null && id.isNotEmpty) {
          onPresentationRemove(id);
          onSystemMessage('Presentation dismissed: $id');
        }
      }

      if (e.eventType?.value ==
          moor_common.EventUnionTypeId.TracebackEvent.value) {
        onNarrativeItem(
          NarrativeItem(
            id: _newId(),
            timestamp: ts,
            content: const ['[traceback]'],
            contentType: 'text/traceback',
            noNewline: false,
            presentationHint: null,
            eventMetadata: null,
          ),
        );
      }

      if (e.eventType?.value == moor_common.EventUnionTypeId.DataEvent.value) {
        final data = e.event as moor_common.DataEvent?;
        final domain = data?.domain?.value;
        final kind = data?.kind?.value;
        if (domain == 'state' && kind == 'room_snapshot') {
          final decoded = decodeVarLoose(data?.payload);
          final snap = roomSnapshotFromPayload(decoded);
          if (snap != null) {
            final attrs = <String, String>{
              'kind': 'room_look',
              'title': snap.title,
            };
            if (snap.room != null) {
              attrs['room'] = snap.room!.curie;
            }
            onPresentationUpsert(
              RoomSnapshotDockItem(
                id: 'room-look',
                target: 'top',
                attrs: attrs,
                snapshot: snap,
              ),
            );
          }
        }
      }

      return;
    }

    // Other event types are expected but not implemented in the spike.
  }

  int _idSeq = 0;
  String _newId() {
    _idSeq += 1;
    return 'n$_idSeq';
  }
}
