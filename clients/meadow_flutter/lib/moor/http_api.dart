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

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/flatbuffers_util.dart';
import 'package:meadow_flutter/moor/models.dart';

class MoorHttpApi {
  final Uri baseUri;

  const MoorHttpApi(this.baseUri);

  Uri _resolve(String path) {
    // Treat path as absolute-from-root.
    return baseUri.replace(path: path);
  }

  Future<WelcomeMessage> fetchWelcomeMessage() async {
    final uri = _resolve('/v1/invoke_welcome_message');
    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'welcome message http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final bytes = resp.bodyBytes;
    if (bytes.isEmpty) {
      return const WelcomeMessage(lines: [], contentType: 'text/plain');
    }

    final reply = _parseClientSuccess(bytes, context: 'welcome message');
    final replyType = reply.replyType?.value ?? 0;

    // DaemonToClientReplyUnionTypeId.VerbCallResponse is expected.
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.VerbCallResponse.value) {
      throw Exception('welcome message: unexpected reply type $replyType');
    }

    final verbCall = reply.reply as moor_rpc.VerbCallResponse?;
    if (verbCall == null) {
      throw Exception('welcome message: missing VerbCallResponse');
    }

    if (verbCall.responseType?.value !=
        moor_rpc.VerbCallResponseUnionTypeId.VerbCallSuccess.value) {
      throw Exception('welcome message: verb call failed');
    }

    final success = verbCall.response as moor_rpc.VerbCallSuccess?;
    if (success == null) {
      throw Exception('welcome message: missing VerbCallSuccess');
    }

    // Mirror Meadow web behavior: first NotifyEvent in the output determines
    // the welcome message and content type.
    var contentType = 'text/plain';
    var outLines = const <String>[];

    final output = success.output;
    if (output != null) {
      for (final evt in output) {
        final e = evt.event;
        if (e == null) {
          continue;
        }
        if (e.eventType?.value !=
            moor_common.EventUnionTypeId.NotifyEvent.value) {
          continue;
        }
        final notify = e.event as moor_common.NotifyEvent?;
        if (notify == null) {
          continue;
        }

        outLines = decodeVarAsLines(notify.value);
        contentType = normalizeContentType(notify.contentType?.value);
        break;
      }
    }

    return WelcomeMessage(lines: outLines, contentType: contentType);
  }

  Future<LoginSession> login({
    required String mode, // "connect" | "create"
    required String username,
    required String password,
  }) async {
    final uri = _resolve('/auth/$mode');
    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/x-flatbuffers',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'player': username.trim(),
        'password': password,
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('auth http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final authToken = resp.headers['x-moor-auth-token'];
    if (authToken == null || authToken.isEmpty) {
      throw Exception('auth: missing X-Moor-Auth-Token');
    }
    final clientToken = resp.headers['x-moor-client-token'];
    final clientId = resp.headers['x-moor-client-id'];

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'auth');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.LoginResult.value) {
      throw Exception('auth: unexpected reply type $replyType');
    }

    final login = reply.reply as moor_rpc.LoginResult?;
    if (login == null || !login.success) {
      throw Exception('auth: login failed');
    }
    final playerCurie = objToCurie(login.player);
    if (playerCurie == null) {
      throw Exception('auth: missing/unsupported player object');
    }

    final flags = login.playerFlags;

    return LoginSession(
      baseUri: baseUri,
      authToken: authToken,
      playerCurie: playerCurie,
      playerFlags: flags,
      clientToken: clientToken,
      clientId: clientId,
      // For the spike: treat missing client creds as a fresh attach.
      isInitialAttach: clientToken == null || clientId == null,
    );
  }

  Future<String?> getEventLogPubkey({required String authToken}) async {
    final uri = _resolve('/v1/event-log/pubkey');
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 401) {
      throw Exception('event log pubkey: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'event log pubkey http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('event log pubkey: invalid json');
    }
    final pk = decoded['public_key'];
    return pk is String ? pk : null;
  }

  Future<void> setEventLogPubkey({
    required String authToken,
    required String publicKey,
  }) async {
    final uri = _resolve('/v1/event-log/pubkey');
    final resp = await http.put(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'public_key': publicKey}),
    );
    if (resp.statusCode == 401) {
      throw Exception('event log pubkey: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'event log pubkey http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }
  }

  Future<void> dismissPresentation({
    required String authToken,
    required String presentationId,
  }) async {
    final uri = _resolve('/v1/presentations/$presentationId');
    final resp = await http.delete(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/json',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('dismiss presentation: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'dismiss presentation http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }
  }

  Future<moor_rpc.CurrentPresentations> listPresentations({
    required String authToken,
  }) async {
    final uri = _resolve('/v1/presentations');
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('presentations: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'presentations http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'presentations');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.CurrentPresentations.value) {
      throw Exception('presentations: unexpected reply type $replyType');
    }
    final current = reply.reply as moor_rpc.CurrentPresentations?;
    if (current == null) {
      throw Exception('presentations: missing CurrentPresentations');
    }
    return current;
  }

  Future<moor_rpc.VerbValue> getVerbCode({
    required String authToken,
    required String objectCurie,
    required String verbName,
  }) async {
    final uri = _resolve(
      '/v1/verbs/$objectCurie/${Uri.encodeComponent(verbName)}',
    );
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('verb code: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'verb code http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'verb code');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType != moor_rpc.DaemonToClientReplyUnionTypeId.VerbValue.value) {
      throw Exception('verb code: unexpected reply type $replyType');
    }
    final value = reply.reply as moor_rpc.VerbValue?;
    if (value == null) {
      throw Exception('verb code: missing VerbValue');
    }
    return value;
  }

  Future<moor_rpc.VerbProgramResponse> compileVerb({
    required String authToken,
    required String objectCurie,
    required String verbName,
    required String code,
  }) async {
    final uri = _resolve(
      '/v1/verbs/$objectCurie/${Uri.encodeComponent(verbName)}',
    );
    final resp = await http.post(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
        'Content-Type': 'text/plain',
      },
      body: code,
    );
    if (resp.statusCode == 401) {
      throw Exception('compile verb: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'compile verb http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'compile verb');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc
            .DaemonToClientReplyUnionTypeId
            .VerbProgramResponseReply
            .value) {
      throw Exception('compile verb: unexpected reply type $replyType');
    }
    final programReply = reply.reply as moor_rpc.VerbProgramResponseReply?;
    final response = programReply?.response;
    if (response == null) {
      throw Exception('compile verb: missing VerbProgramResponse');
    }
    return response;
  }

  Future<moor_rpc.PropertyValue> getProperty({
    required String authToken,
    required String objectCurie,
    required String propertyName,
  }) async {
    final uri = _resolve(
      '/v1/properties/$objectCurie/${Uri.encodeComponent(propertyName)}',
    );
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('property: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception('property http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'property');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.PropertyValue.value) {
      throw Exception('property: unexpected reply type $replyType');
    }
    final value = reply.reply as moor_rpc.PropertyValue?;
    if (value == null) {
      throw Exception('property: missing PropertyValue');
    }
    return value;
  }

  Future<moor_rpc.PropertyUpdated> updateProperty({
    required String authToken,
    required String objectCurie,
    required String propertyName,
    required String valueLiteral,
  }) async {
    final uri = _resolve(
      '/v1/properties/$objectCurie/${Uri.encodeComponent(propertyName)}',
    );
    final resp = await http.post(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
        'Content-Type': 'text/plain',
      },
      body: valueLiteral,
    );
    if (resp.statusCode == 401) {
      throw Exception('update property: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'update property http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final reply = _parseClientSuccess(
      resp.bodyBytes,
      context: 'update property',
    );
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.PropertyUpdated.value) {
      throw Exception('update property: unexpected reply type $replyType');
    }
    final updated = reply.reply as moor_rpc.PropertyUpdated?;
    if (updated == null) {
      throw Exception('update property: missing PropertyUpdated');
    }
    return updated;
  }

  Future<List<EncryptedHistoricalEvent>> fetchHistory({
    required String authToken,
    int? sinceSeconds,
    String? sinceEvent,
    String? untilEvent,
    int? limit,
  }) async {
    final params = <String, String>{};
    if (sinceSeconds != null) {
      params['since_seconds'] = sinceSeconds.toString();
    }
    if (sinceEvent != null) {
      params['since_event'] = sinceEvent;
    }
    if (untilEvent != null) {
      params['until_event'] = untilEvent;
    }
    if (limit != null) {
      params['limit'] = limit.toString();
    }

    final uri = _resolve('/v1/history').replace(queryParameters: params);
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );

    if (resp.statusCode == 401) {
      throw Exception('history: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception('history http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'history');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.HistoryResponseReply.value) {
      throw Exception('history: unexpected reply type $replyType');
    }

    final historyReply = reply.reply as moor_rpc.HistoryResponseReply?;
    final history = historyReply?.response;
    final events =
        history?.events ?? const <moor_rpc.HistoricalNarrativeEvent>[];

    final out = <EncryptedHistoricalEvent>[];
    for (final e in events) {
      final blob = e.encryptedBlob;
      if (blob == null || blob.isEmpty) continue;
      out.add(
        EncryptedHistoricalEvent(
          encryptedBlob: Uint8List.fromList(blob),
          isHistorical: e.isHistorical,
        ),
      );
    }
    return out;
  }

  moor_rpc.DaemonToClientReply _parseClientSuccess(
    Uint8List bytes, {
    required String context,
  }) {
    final replyResult = moor_rpc.ReplyResult(bytes);
    final resultType = replyResult.resultType?.value ?? 0;
    if (resultType != moor_rpc.ReplyResultUnionTypeId.ClientSuccess.value) {
      throw Exception('$context: expected ClientSuccess, got $resultType');
    }
    final cs = replyResult.result as moor_rpc.ClientSuccess?;
    final reply = cs?.reply;
    if (reply == null) {
      throw Exception('$context: missing daemon reply');
    }
    return reply;
  }
}
