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

import 'package:shared_preferences/shared_preferences.dart';

class TrustedExternalDomainsStore {
  static const _prefsKey = 'moor-trusted-external-domains';

  static Future<List<String>> getDomains() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <String>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const <String>[];
      }
      final domains = decoded['domains'];
      if (domains is! List) {
        return const <String>[];
      }
      return domains.whereType<String>().map((it) => it.trim()).toList();
    } on Object {
      return const <String>[];
    }
  }

  static Future<bool> isTrusted(String url) async {
    final hostname = hostnameFor(url);
    if (hostname == null) {
      return false;
    }
    final domains = await getDomains();
    return domains.contains(hostname);
  }

  static Future<void> addDomain(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final domains = await getDomains();
    if (domains.contains(normalized)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'domains': <String>[...domains, normalized],
      }),
    );
  }

  static String? hostnameFor(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.trim().toLowerCase();
    if (host == null || host.isEmpty) {
      return null;
    }
    return host;
  }
}
