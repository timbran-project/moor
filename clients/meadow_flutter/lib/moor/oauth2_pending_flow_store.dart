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
import 'package:shared_preferences/shared_preferences.dart';

class OAuth2PendingFlow {
  final String baseUrl;
  final String codeVerifier;
  final String redirectUri;

  const OAuth2PendingFlow({
    required this.baseUrl,
    required this.codeVerifier,
    required this.redirectUri,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'base_url': baseUrl,
    'code_verifier': codeVerifier,
    'redirect_uri': redirectUri,
  };

  static OAuth2PendingFlow? fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return null;
    }
    final baseUrl = value['base_url'];
    final codeVerifier = value['code_verifier'];
    final redirectUri = value['redirect_uri'];
    if (baseUrl is! String ||
        baseUrl.trim().isEmpty ||
        codeVerifier is! String ||
        codeVerifier.trim().isEmpty ||
        redirectUri is! String ||
        redirectUri.trim().isEmpty) {
      return null;
    }
    return OAuth2PendingFlow(
      baseUrl: baseUrl.trim(),
      codeVerifier: codeVerifier.trim(),
      redirectUri: redirectUri.trim(),
    );
  }
}

class OAuth2PendingFlowStore {
  static const _prefsKey = 'moor-oauth2-pending-flow';

  static Future<void> save(OAuth2PendingFlow flow) async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint(
      '[oauth-debug] pending save base=${flow.baseUrl} redirect=${flow.redirectUri} verifier_len=${flow.codeVerifier.length}',
    );
    await prefs.setString(_prefsKey, jsonEncode(flow.toJson()));
  }

  static Future<OAuth2PendingFlow?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        debugPrint('[oauth-debug] pending load miss');
        return null;
      }
      final flow = OAuth2PendingFlow.fromJson(jsonDecode(raw));
      debugPrint(
        flow == null
            ? '[oauth-debug] pending load invalid payload'
            : '[oauth-debug] pending load hit base=${flow.baseUrl} redirect=${flow.redirectUri} verifier_len=${flow.codeVerifier.length}',
      );
      return flow;
    } on Object {
      debugPrint('[oauth-debug] pending load exception');
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    debugPrint('[oauth-debug] pending clear');
    await prefs.remove(_prefsKey);
  }
}
