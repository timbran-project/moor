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

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent storage for event-log age identities.
///
/// Mirrors Meadow web's localStorage key names for clarity.
class EventLogKeyStore {
  static String _keyForPlayer(String playerOid) =>
      'moor_event_log_identity_$playerOid';

  static Future<String?> getIdentity(String playerOid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyForPlayer(playerOid));
  }

  static Future<void> setIdentity({
    required String playerOid,
    required String ageIdentity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForPlayer(playerOid), ageIdentity);
  }

  static Future<void> removeIdentity(String playerOid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForPlayer(playerOid));
  }
}
