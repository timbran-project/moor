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
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists login credentials so the app can restore the session on restart.
/// Credentials are cleared on explicit logout.
class SessionStore {
  static const _keyBaseUrl = 'moor_session_base_url';
  static const _keyAuthToken = 'moor_session_auth_token';
  static const _keyPlayerCurie = 'moor_session_player_curie';
  static const _keyPlayerFlags = 'moor_session_player_flags';

  static Future<void> save(LoginSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, session.baseUri.toString());
    await prefs.setString(_keyAuthToken, session.authToken);
    await prefs.setString(_keyPlayerCurie, session.playerCurie);
    await prefs.setInt(_keyPlayerFlags, session.playerFlags);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyAuthToken);
    await prefs.remove(_keyPlayerCurie);
    await prefs.remove(_keyPlayerFlags);
  }

  /// Try to restore a saved session. Validates the auth token with the server
  /// before returning. Returns null if no session is stored or the token has
  /// expired.
  static Future<LoginSession?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_keyBaseUrl);
    final authToken = prefs.getString(_keyAuthToken);
    final playerCurie = prefs.getString(_keyPlayerCurie);
    final playerFlags = prefs.getInt(_keyPlayerFlags);

    if (baseUrl == null ||
        authToken == null ||
        playerCurie == null ||
        playerFlags == null) {
      return null;
    }

    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return null;

    // Validate the token is still good.
    try {
      final api = MoorHttpApi(baseUri);
      final valid = await api.validateAuthToken(authToken: authToken);
      if (!valid) {
        debugPrint('[session] stored auth token is no longer valid');
        await clear();
        return null;
      }
    } on Object catch (e) {
      debugPrint('[session] token validation failed: $e');
      await clear();
      return null;
    }

    return LoginSession(
      baseUri: baseUri,
      authToken: authToken,
      playerCurie: playerCurie,
      playerFlags: playerFlags,
      clientToken: null,
      clientId: null,
      isInitialAttach: false,
    );
  }
}
