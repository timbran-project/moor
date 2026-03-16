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

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart'
    as moor_var;
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/types/moor_obj.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

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

        outLines = MoorVar.fromFlatBuffer(notify.value!).asLines();
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

    final authToken = resp.headers['x-moor-auth-token']?.trim();
    if (authToken == null || authToken.isEmpty) {
      throw Exception('auth: missing X-Moor-Auth-Token');
    }
    final clientToken = resp.headers['x-moor-client-token']?.trim();
    final clientId = resp.headers['x-moor-client-id']?.trim();

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
    final playerObj = login.player;
    if (playerObj == null) {
      throw Exception('auth: missing player object');
    }
    final moorObj = MoorObj.tryFromObjFlatBuffer(playerObj);
    if (moorObj == null) {
      throw Exception('auth: unsupported player object type');
    }
    final playerCurie = moorObj.toCurie();

    final flags = login.playerFlags;

    return LoginSession(
      baseUri: baseUri,
      authToken: authToken,
      playerCurie: playerCurie,
      playerFlags: flags,
      clientToken: clientToken,
      clientId: clientId,
      // New login starts a fresh WS attach. Reconnects should use client creds.
      isInitialAttach: true,
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

  Future<String?> fetchSystemPropertyText({
    required List<String> objectPath,
    required String propertyName,
    String? authToken,
  }) async {
    final path = [
      ...objectPath,
      propertyName,
    ].map(Uri.encodeComponent).join('/');
    final uri = _resolve('/v1/system_property/$path');
    final headers = <String, String>{
      'Accept': 'application/x-flatbuffers',
    };
    if (authToken != null && authToken.isNotEmpty) {
      headers['X-Moor-Auth-Token'] = authToken;
    }

    final resp = await http.get(uri, headers: headers);
    if (resp.statusCode == 404) {
      return null;
    }
    if (resp.statusCode == 401) {
      throw Exception('system property: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'system property http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }
    if (resp.bodyBytes.isEmpty) return null;

    final reply = _parseClientSuccess(
      resp.bodyBytes,
      context: 'system property',
    );
    final replyType = reply.replyType?.value ?? 0;

    MoorVar? value;
    if (replyType ==
        moor_rpc.DaemonToClientReplyUnionTypeId.SysPropValue.value) {
      final sysProp = reply.reply as moor_rpc.SysPropValue?;
      final v = sysProp?.value;
      if (v != null) {
        value = MoorVar.fromFlatBuffer(v);
      }
    } else if (replyType ==
        moor_rpc
            .DaemonToClientReplyUnionTypeId
            .SystemHandlerResponseReply
            .value) {
      final handler = reply.reply as moor_rpc.SystemHandlerResponseReply?;
      if (handler?.responseType?.value ==
          moor_rpc
              .SystemHandlerResponseUnionTypeId
              .SystemHandlerSuccess
              .value) {
        final success = handler?.response as moor_rpc.SystemHandlerSuccess?;
        final v = success?.result;
        if (v != null) {
          value = MoorVar.fromFlatBuffer(v);
        }
      }
    } else {
      throw Exception('system property: unexpected reply type $replyType');
    }

    if (value == null) {
      return null;
    }
    final text = value.coerceText();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<String?> fetchMooTitle({String? authToken}) {
    return fetchSystemPropertyText(
      objectPath: const ['login'],
      propertyName: 'moo_title',
      authToken: authToken,
    );
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

  Future<moor_rpc.VerbsReply> getVerbs({
    required String authToken,
    required String objectCurie,
    bool inherited = true,
  }) async {
    final uri = _resolve('/v1/verbs/$objectCurie').replace(
      queryParameters: inherited ? const {'inherited': 'true'} : null,
    );
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('verbs: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception('verbs http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'verbs');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType != moor_rpc.DaemonToClientReplyUnionTypeId.VerbsReply.value) {
      throw Exception('verbs: unexpected reply type $replyType');
    }
    final value = reply.reply as moor_rpc.VerbsReply?;
    if (value == null) {
      throw Exception('verbs: missing VerbsReply');
    }
    return value;
  }

  Uint8List _emptyArgsVarBytes() {
    // Equivalent to Meadow web's MoorVar.buildEmptyList().
    return moor_var.VarObjectBuilder(
      variantType: moor_var.VarUnionTypeId.VarList,
      variant: moor_var.VarListObjectBuilder(elements: const []),
    ).toBytes();
  }

  Future<moor_rpc.VerbCallSuccess> invokeVerb({
    required String authToken,
    required String objectCurie,
    required String verbName,
    Uint8List? argsVarBytes,
  }) async {
    final uri = _resolve(
      '/v1/verbs/$objectCurie/${Uri.encodeComponent(verbName)}/invoke',
    );

    final resp = await http.post(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
        'Content-Type': 'application/x-flatbuffers',
      },
      body: argsVarBytes ?? _emptyArgsVarBytes(),
    );

    if (resp.statusCode == 401) {
      throw Exception('invoke verb: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'invoke verb http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    // Unlike most /v1 endpoints, /invoke returns a raw VerbCallResponse buffer
    // (see clients/web-sdk/src/verb.ts:parseVerbCallSuccessFromBytes).
    final verbCall = moor_rpc.VerbCallResponse(resp.bodyBytes);
    final response = verbCall.response;
    if (response == null) {
      throw Exception('invoke verb: missing VerbCallResponse');
    }
    if (verbCall.responseType?.value !=
        moor_rpc.VerbCallResponseUnionTypeId.VerbCallSuccess.value) {
      throw Exception('invoke verb: failed ($response)');
    }

    final success = response as moor_rpc.VerbCallSuccess?;
    if (success == null) {
      throw Exception('invoke verb: missing VerbCallSuccess');
    }
    return success;
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

  Future<moor_rpc.PropertiesReply> getProperties({
    required String authToken,
    required String objectCurie,
    bool inherited = true,
  }) async {
    final uri = _resolve('/v1/properties/$objectCurie').replace(
      queryParameters: inherited ? const {'inherited': 'true'} : null,
    );
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('properties: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'properties http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'properties');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.PropertiesReply.value) {
      throw Exception('properties: unexpected reply type $replyType');
    }
    final value = reply.reply as moor_rpc.PropertiesReply?;
    if (value == null) {
      throw Exception('properties: missing PropertiesReply');
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

  Future<moor_rpc.ListObjectsReply> listObjects({
    required String authToken,
  }) async {
    final uri = _resolve('/v1/objects');
    final resp = await http.get(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
      },
    );
    if (resp.statusCode == 401) {
      throw Exception('objects: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception('objects http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'objects');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType !=
        moor_rpc.DaemonToClientReplyUnionTypeId.ListObjectsReply.value) {
      throw Exception('objects: unexpected reply type $replyType');
    }
    final value = reply.reply as moor_rpc.ListObjectsReply?;
    if (value == null) {
      throw Exception('objects: missing ListObjectsReply');
    }
    return value;
  }

  Future<MoorVar> performEval({
    required String authToken,
    required String expression,
  }) async {
    final uri = _resolve('/v1/eval');
    final resp = await http.post(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/x-flatbuffers',
        'Content-Type': 'text/plain',
      },
      body: expression,
    );
    if (resp.statusCode == 401) {
      throw Exception('eval: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception('eval http ${resp.statusCode}: ${resp.reasonPhrase}');
    }

    final reply = _parseClientSuccess(resp.bodyBytes, context: 'eval');
    final replyType = reply.replyType?.value ?? 0;
    if (replyType != moor_rpc.DaemonToClientReplyUnionTypeId.EvalResult.value) {
      throw Exception('eval: unexpected reply type $replyType');
    }

    final evalResult = reply.reply as moor_rpc.EvalResult?;
    if (evalResult == null) {
      throw Exception('eval: missing EvalResult');
    }
    final result = evalResult.result;
    if (result == null) {
      throw Exception('eval: missing EvalResult.result');
    }
    return MoorVar.fromFlatBuffer(result);
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
    debugPrint('[history] GET $uri');
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

    debugPrint(
      '[history] response: ${resp.statusCode}, '
      '${resp.bodyBytes.length} bytes, '
      '${events.length} events in flatbuffer',
    );

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

  Future<bool> deleteEventLogHistory({
    required String authToken,
  }) async {
    final uri = _resolve('/v1/event-log/history');
    final resp = await http.delete(
      uri,
      headers: {
        'X-Moor-Auth-Token': authToken,
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 401) {
      throw Exception('event-log history delete: unauthorized');
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'event-log history delete http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('event-log history delete: invalid json');
    }
    return decoded['success'] == true;
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

class OAuth2Config {
  final bool enabled;
  final List<String> providers;

  const OAuth2Config({
    required this.enabled,
    required this.providers,
  });
}

class OAuth2AppStartResponse {
  final Uri authUrl;

  const OAuth2AppStartResponse({
    required this.authUrl,
  });
}

class OAuth2AuthorizeResponse {
  final Uri authUrl;
  final String? state;

  const OAuth2AuthorizeResponse({
    required this.authUrl,
    required this.state,
  });
}

sealed class OAuth2AppExchangeResult {
  const OAuth2AppExchangeResult();
}

class OAuth2AppAuthSession extends OAuth2AppExchangeResult {
  final String authToken;
  final String playerCurie;
  final int playerFlags;
  final String? clientToken;
  final String? clientId;

  const OAuth2AppAuthSession({
    required this.authToken,
    required this.playerCurie,
    required this.playerFlags,
    required this.clientToken,
    required this.clientId,
  });
}

class OAuth2AppIdentity extends OAuth2AppExchangeResult {
  final String identityCode;
  final String provider;
  final String? email;
  final String? name;
  final String? username;

  const OAuth2AppIdentity({
    required this.identityCode,
    required this.provider,
    required this.email,
    required this.name,
    required this.username,
  });
}

class OAuth2LoginResult {
  final bool success;
  final String? authToken;
  final String? playerCurie;
  final int? playerFlags;
  final String? clientToken;
  final String? clientId;
  final String? error;

  const OAuth2LoginResult({
    required this.success,
    required this.authToken,
    required this.playerCurie,
    required this.playerFlags,
    required this.clientToken,
    required this.clientId,
    required this.error,
  });
}

class OAuth2BrowserIdentity {
  final String oauth2Code;
  final String provider;
  final String? email;
  final String? name;
  final String? username;

  const OAuth2BrowserIdentity({
    required this.oauth2Code,
    required this.provider,
    required this.email,
    required this.name,
    required this.username,
  });
}

class OAuth2AuthCodeExchangeResult {
  final String authToken;
  final String playerCurie;
  final int playerFlags;
  final String? clientToken;
  final String? clientId;

  const OAuth2AuthCodeExchangeResult({
    required this.authToken,
    required this.playerCurie,
    required this.playerFlags,
    required this.clientToken,
    required this.clientId,
  });
}

extension MoorHttpApiOAuth2 on MoorHttpApi {
  Future<OAuth2AuthorizeResponse> oauth2Authorize({
    required String provider,
  }) async {
    final uri = _resolve('/auth/oauth2/$provider/authorize');
    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode != 200) {
      throw Exception(
        'oauth2 authorize http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 authorize: invalid json');
    }
    final authUrl = decoded['auth_url'];
    if (authUrl is! String || authUrl.trim().isEmpty) {
      throw Exception('oauth2 authorize: missing auth_url');
    }
    final uriParsed = Uri.tryParse(authUrl.trim());
    if (uriParsed == null) {
      throw Exception('oauth2 authorize: bad auth_url');
    }
    final state = decoded['state'];
    return OAuth2AuthorizeResponse(
      authUrl: uriParsed,
      state: state is String && state.trim().isNotEmpty ? state.trim() : null,
    );
  }

  Future<OAuth2Config> fetchOAuth2Config() async {
    final uri = _resolve('/v1/oauth2/config');
    final resp = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
      },
    );

    if (resp.statusCode == 404) {
      return const OAuth2Config(enabled: false, providers: <String>[]);
    }
    if (resp.statusCode != 200) {
      throw Exception(
        'oauth2 config http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 config: invalid json');
    }

    final enabled = decoded['enabled'] == true;
    final providersRaw = decoded['providers'];
    final providers = <String>[];
    if (providersRaw is List) {
      for (final p in providersRaw) {
        if (p is String && p.trim().isNotEmpty) {
          providers.add(p.trim());
        }
      }
    }

    return OAuth2Config(enabled: enabled, providers: providers);
  }

  Future<OAuth2AppStartResponse> oauth2AppStart({
    required String provider,
    required String redirectUri,
    required String codeChallenge,
    required String codeChallengeMethod,
    String? intent,
  }) async {
    final uri = _resolve('/auth/oauth2/$provider/app/start');
    final payload = <String, Object?>{
      'redirect_uri': redirectUri,
      'code_challenge': codeChallenge,
      'code_challenge_method': codeChallengeMethod,
      if (intent != null && intent.isNotEmpty) 'intent': intent,
    };
    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['error'] is String) {
          throw Exception('oauth2 app/start: ${decoded['error']}');
        }
      } on FormatException {
        // Fall through to generic HTTP error.
      }
      throw Exception(
        'oauth2 app/start http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 app/start: invalid json');
    }
    final authUrl = decoded['auth_url'];
    if (authUrl is! String || authUrl.trim().isEmpty) {
      throw Exception('oauth2 app/start: missing auth_url');
    }
    final uriParsed = Uri.tryParse(authUrl.trim());
    if (uriParsed == null) {
      throw Exception('oauth2 app/start: bad auth_url');
    }
    return OAuth2AppStartResponse(authUrl: uriParsed);
  }

  Future<OAuth2AppExchangeResult> oauth2AppExchange({
    required String handoffCode,
    required String codeVerifier,
  }) async {
    final uri = _resolve('/auth/oauth2/app/exchange');
    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'handoff_code': handoffCode,
        'code_verifier': codeVerifier,
      }),
    );

    if (resp.statusCode != 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] is String) {
        throw Exception('oauth2 app/exchange: ${decoded['error']}');
      }
      throw Exception(
        'oauth2 app/exchange http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 app/exchange: invalid json');
    }
    final type = decoded['type'];
    if (type == 'auth_session') {
      final token = decoded['auth_token'];
      final player = decoded['player'];
      final flags = decoded['player_flags'];
      if (token is! String || player is! String || flags is! int) {
        throw Exception('oauth2 app/exchange: invalid auth_session');
      }
      return OAuth2AppAuthSession(
        authToken: token,
        playerCurie: player,
        playerFlags: flags,
        clientToken: decoded['client_token'] as String?,
        clientId: decoded['client_id'] as String?,
      );
    }
    if (type == 'identity') {
      final identityCode = decoded['identity_code'];
      final provider = decoded['provider'];
      if (identityCode is! String || provider is! String) {
        throw Exception('oauth2 app/exchange: invalid identity');
      }
      return OAuth2AppIdentity(
        identityCode: identityCode,
        provider: provider,
        email: decoded['email'] as String?,
        name: decoded['name'] as String?,
        username: decoded['username'] as String?,
      );
    }
    throw Exception('oauth2 app/exchange: unknown response type');
  }

  Future<OAuth2LoginResult> oauth2AppAccountChoice({
    required String mode,
    required String identityCode,
    required String codeVerifier,
    String? playerName,
    String? existingEmail,
    String? existingPassword,
  }) async {
    final uri = _resolve('/auth/oauth2/app/account');
    final payload = <String, Object?>{
      'mode': mode,
      'identity_code': identityCode,
      'code_verifier': codeVerifier,
      if (playerName != null && playerName.isNotEmpty)
        'player_name': playerName,
      if (existingEmail != null && existingEmail.isNotEmpty)
        'existing_email': existingEmail,
      if (existingPassword != null && existingPassword.isNotEmpty)
        'existing_password': existingPassword,
    };

    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200 && resp.statusCode != 401) {
      throw Exception(
        'oauth2 app/account http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 app/account: invalid json');
    }

    final success = decoded['success'] == true;
    final flagsRaw = decoded['player_flags'];
    final flags = flagsRaw is int ? flagsRaw : int.tryParse('$flagsRaw');
    return OAuth2LoginResult(
      success: success,
      authToken: decoded['auth_token'] as String?,
      playerCurie: decoded['player'] as String?,
      playerFlags: flags,
      clientToken: decoded['client_token'] as String?,
      clientId: decoded['client_id'] as String?,
      error: decoded['error'] as String?,
    );
  }

  Future<OAuth2AuthCodeExchangeResult> oauth2ExchangeAuthCode({
    required String code,
  }) async {
    final uri = _resolve('/auth/oauth2/exchange');
    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, Object?>{
        'code': code,
      }),
    );

    if (resp.statusCode != 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['error'] is String) {
        throw Exception('oauth2 exchange: ${decoded['error']}');
      }
      throw Exception(
        'oauth2 exchange http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 exchange: invalid json');
    }
    final authToken = decoded['auth_token'];
    final player = decoded['player'];
    final flags = decoded['player_flags'];
    if (authToken is! String || player is! String || flags is! int) {
      throw Exception('oauth2 exchange: invalid payload');
    }
    return OAuth2AuthCodeExchangeResult(
      authToken: authToken,
      playerCurie: player,
      playerFlags: flags,
      clientToken: decoded['client_token'] as String?,
      clientId: decoded['client_id'] as String?,
    );
  }

  Future<OAuth2LoginResult> oauth2BrowserAccountChoice({
    required String mode,
    required String oauth2Code,
    String? playerName,
    String? existingEmail,
    String? existingPassword,
  }) async {
    final uri = _resolve('/auth/oauth2/account');
    final payload = <String, Object?>{
      'mode': mode,
      'oauth2_code': oauth2Code,
      if (playerName != null && playerName.isNotEmpty)
        'player_name': playerName,
      if (existingEmail != null && existingEmail.isNotEmpty)
        'existing_email': existingEmail,
      if (existingPassword != null && existingPassword.isNotEmpty)
        'existing_password': existingPassword,
    };

    final resp = await http.post(
      uri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200 && resp.statusCode != 401) {
      throw Exception(
        'oauth2 account http ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('oauth2 account: invalid json');
    }

    final success = decoded['success'] == true;
    final flagsRaw = decoded['player_flags'];
    final flags = flagsRaw is int ? flagsRaw : int.tryParse('$flagsRaw');
    return OAuth2LoginResult(
      success: success,
      authToken: decoded['auth_token'] as String?,
      playerCurie: decoded['player'] as String?,
      playerFlags: flags,
      clientToken: decoded['client_token'] as String?,
      clientId: decoded['client_id'] as String?,
      error: decoded['error'] as String?,
    );
  }
}
