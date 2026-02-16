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
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/room_snapshot.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MoorWsClient {
  final LoginSession session;
  final void Function(String message) onSystemMessage;
  final void Function(NarrativeItem item) onNarrativeItem;
  final void Function(DockItem p) onPresentationUpsert;
  final void Function(String id) onPresentationRemove;
  final void Function(InputPromptRequest request)? onInputPromptRequest;
  final void Function({required String clientId, required String clientToken})?
  onCredentialsUpdated;
  final void Function(String status)? onConnectionStatusChanged;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _keepalive;
  Timer? _reconnectTimer;
  bool _closing = false;
  bool _connecting = false;
  String? _connectMode;
  String? _clientId;
  String? _clientToken;

  static const Duration _keepaliveInterval = Duration(seconds: 45);
  static const Duration _reconnectDelay = Duration(seconds: 3);

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
    this.onInputPromptRequest,
    this.onCredentialsUpdated,
    this.onConnectionStatusChanged,
  }) {
    _clientId = session.clientId;
    _clientToken = session.clientToken;
  }

  bool get isConnected => _channel != null;

  Future<bool> connect({required String mode, bool force = false}) async {
    _connectMode = mode;

    if (_connecting) {
      return false;
    }

    if (_channel != null && !force) {
      return true;
    }

    if (_channel != null) {
      _teardownChannel(closeSink: true);
    }

    _closing = false;
    _setConnectionStatus('connecting');
    _cancelReconnect();
    _connecting = true;

    final wsUrl = _wsAttachUri(session.baseUri, mode: mode);
    final protocols = <String>[
      'moor',
      'paseto.${session.authToken}',
    ];

    if (session.isInitialAttach) {
      protocols.add('initial_attach.true');
    }
    if (_clientId != null && _clientToken != null) {
      protocols
        ..add('client_id.$_clientId')
        ..add('client_token.$_clientToken');
    }

    final validatedProtocols = _validatedWebSocketProtocols(protocols);
    if (validatedProtocols == null) {
      onSystemMessage(
        'WebSocket protocol contains invalid characters; cannot connect from web. '
        'See earlier system message for details.',
      );
      _setConnectionStatus('error');
      _connecting = false;
      return false;
    }

    onSystemMessage('Connecting WebSocket: $wsUrl');
    onSystemMessage(
      'WebSocket protocols: ${validatedProtocols.map(_redactProtocol).join(', ')}',
    );

    final channel = WebSocketChannel.connect(
      wsUrl,
      protocols: validatedProtocols,
    );

    try {
      await channel.ready;
    } on Object catch (e) {
      onSystemMessage(
        'WebSocket connect failed: $e (url=$wsUrl protocols=${validatedProtocols.map(_redactProtocol).join(', ')})',
      );
      try {
        await channel.sink.close();
      } on Object catch (_) {
        // ignore
      }
      _setConnectionStatus('error');
      _connecting = false;
      _scheduleReconnect();
      return false;
    }

    _channel = channel;
    _setConnectionStatus('connected');
    _connecting = false;

    // Keepalive to prevent proxy idle timeouts (Meadow uses 45s).
    _keepalive = Timer.periodic(_keepaliveInterval, (_) {
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
        _handleDisconnect();
      },
      onDone: () {
        onSystemMessage('WebSocket closed');
        _handleDisconnect();
      },
      cancelOnError: false,
    );

    return true;
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
    _closing = true;
    _connecting = false;
    _cancelReconnect();
    _setConnectionStatus('disconnected');
    _teardownChannel(closeSink: true);
  }

  void _setConnectionStatus(String status) {
    onConnectionStatusChanged?.call(status);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect() {
    if (_closing) return;
    final mode = _connectMode;
    if (mode == null) return;
    if (_reconnectTimer != null) return;
    _setConnectionStatus('connecting');
    _reconnectTimer = Timer(_reconnectDelay, () async {
      _reconnectTimer = null;
      if (_closing) return;
      await connect(mode: mode, force: true);
    });
  }

  void _handleDisconnect() {
    if (_channel == null && _sub == null) return;
    _teardownChannel(closeSink: false);
    if (_closing) {
      _setConnectionStatus('disconnected');
      return;
    }
    _setConnectionStatus('disconnected');
    _scheduleReconnect();
  }

  void _teardownChannel({required bool closeSink}) {
    _keepalive?.cancel();
    _keepalive = null;
    _sub?.cancel();
    _sub = null;
    try {
      if (closeSink) {
        _channel?.sink.close();
      }
    } on Object catch (_) {
      // ignore
    }
    _channel = null;
  }

  Uri _wsAttachUri(Uri httpBase, {required String mode}) {
    final isSecure = httpBase.scheme == 'https';
    // Build from components so we never inherit query/fragment (e.g. `?#`),
    // which browsers reject for WebSocket URLs.
    return Uri(
      scheme: isSecure ? 'wss' : 'ws',
      userInfo: httpBase.userInfo,
      host: httpBase.host,
      port: httpBase.hasPort ? httpBase.port : null,
      path: '/ws/attach/$mode',
    );
  }

  /// Browsers strictly validate `Sec-WebSocket-Protocol` values (must be an
  /// HTTP token per RFC 7230). Native clients are looser, so validate here to
  /// produce a useful error message instead of a generic JS `SyntaxError`.
  ///
  /// Returns `null` when validation fails.
  List<String>? _validatedWebSocketProtocols(List<String> raw) {
    final out = <String>[];
    for (final p0 in raw) {
      final p = p0.trim();
      if (p.isEmpty) {
        onSystemMessage('WebSocket protocol invalid: empty/whitespace entry');
        return null;
      }
      // RFC 7230 tchar: ! # $ % & ' * + - . ^ _ ` | ~ digits alpha
      final ok = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(p);
      if (!ok) {
        final bad = p.runes
            .where(
              (r) => !RegExp(
                r"[!#$%&'*+\-.^_`|~0-9A-Za-z]",
              ).hasMatch(String.fromCharCode(r)),
            )
            .map((r) => '0x${r.toRadixString(16)}')
            .take(8)
            .join(', ');
        onSystemMessage(
          'WebSocket protocol invalid: "$p" (first bad chars: $bad)',
        );
        return null;
      }
      out.add(p);
    }

    // Browser requires unique protocols.
    final seen = <String>{};
    for (final p in out) {
      if (!seen.add(p)) {
        onSystemMessage('WebSocket protocol invalid: duplicate "$p"');
        return null;
      }
    }
    return out;
  }

  String _redactProtocol(String p) {
    String redactTail(String s) {
      if (s.length <= 20) return s;
      return '${s.substring(0, 12)}...${s.substring(s.length - 4)}';
    }

    if (p.startsWith('paseto.')) {
      final t = p.substring('paseto.'.length);
      return 'paseto.(len=${t.length} ${redactTail(t)})';
    }
    if (p.startsWith('client_token.')) {
      final t = p.substring('client_token.'.length);
      return 'client_token.(len=${t.length} ${redactTail(t)})';
    }
    if (p.startsWith('client_id.')) {
      final t = p.substring('client_id.'.length);
      return 'client_id.($t)';
    }
    return p;
  }

  String? _uuidBytesToHex(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
      _clientId = clientId;
      _clientToken = clientToken;
      onSystemMessage('WS: updated session credentials (client_id=$clientId)');
      onCredentialsUpdated?.call(clientId: clientId, clientToken: clientToken);
      return;
    }

    if (type == moor_rpc.ClientEventUnionTypeId.RequestInputEvent.value) {
      final req = ev.event as moor_rpc.RequestInputEvent?;
      final reqId = _uuidBytesToHex(req?.requestId?.data);
      if (reqId == null || reqId.isEmpty) {
        onSystemMessage('WS: RequestInputEvent missing request id');
        return;
      }

      final raw = <String, MoorVar>{};
      final metadata = req?.metadata;
      if (metadata != null) {
        for (final pair in metadata) {
          final key = pair.key?.value;
          final value = pair.value;
          if (key == null || key.isEmpty || value == null) {
            continue;
          }
          raw[key] = MoorVar.fromFlatBuffer(value);
        }
      }

      onInputPromptRequest?.call(
        InputPromptRequest(
          requestId: reqId,
          metadata: parseInputPromptMetadata(raw),
        ),
      );
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
      final eventId = _uuidBytesToHex(evt.eventId?.data);
      final e = evt.event;
      if (e == null) {
        return;
      }

      if (e.eventType?.value ==
          moor_common.EventUnionTypeId.NotifyEvent.value) {
        final notify = e.event as moor_common.NotifyEvent?;
        if (notify == null || notify.value == null) {
          return;
        }
        final content = MoorVar.fromFlatBuffer(notify.value!).asLines();
        if (content.isEmpty) return;

        final ct = normalizeContentType(notify.contentType?.value);

        String? presentationHint;
        String? groupId;
        final eventMetadata = <String, Object?>{};
        final md = notify.metadata;
        if (md != null) {
          for (final m in md) {
            if (m.key == null || m.value == null) continue;
            final k = m.key?.value;
            if (k == null || k.isEmpty) continue;
            final v = MoorVar.fromFlatBuffer(m.value!);
            eventMetadata[k] = v.value;
            if (presentationHint == null &&
                (k == 'presentation_hint' || k == 'presentationHint')) {
              presentationHint = v.toKey();
            }
            if (groupId == null && k == 'group_id') {
              groupId = v.toKey();
            }
          }
        }
        if (eventId != null) {
          eventMetadata['eventId'] = eventId;
          eventMetadata['event_id'] = eventId;
        }

        onNarrativeItem(
          NarrativeItem(
            id: _newId(),
            timestamp: ts,
            content: content,
            contentType: ct,
            noNewline: notify.noNewline,
            presentationHint: presentationHint,
            groupId: groupId,
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
          final target = model.target;
          if (target == 'verb-editor' ||
              target == 'property-editor' ||
              target == 'property-value-editor' ||
              target == 'text-editor') {
            onSystemMessage(
              'Presentation: id=${model.id} target=$target attrs=${model.attrs}',
            );
          }
          onPresentationUpsert(model);
        }
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
            groupId: null,
            eventMetadata: null,
          ),
        );
      }

      if (e.eventType?.value == moor_common.EventUnionTypeId.DataEvent.value) {
        final data = e.event as moor_common.DataEvent?;
        final domain = data?.domain?.value;
        final kind = data?.kind?.value;
        if (domain == 'state' && kind == 'room_snapshot') {
          final payload = data?.payload;
          if (payload != null) {
            final decoded = MoorVar.fromFlatBuffer(payload);
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
