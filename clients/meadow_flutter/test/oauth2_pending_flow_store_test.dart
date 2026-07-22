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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/oauth2_pending_flow_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OAuth2PendingFlowStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
    });

    test('round trips a pending flow', () async {
      const flow = OAuth2PendingFlow(
        baseUrl: 'https://timbran.org',
        codeVerifier: 'pkce-verifier',
        redirectUri: 'moor://oauth/callback',
      );

      await OAuth2PendingFlowStore.save(flow);
      final loaded = await OAuth2PendingFlowStore.load();

      expect(loaded?.baseUrl, flow.baseUrl);
      expect(loaded?.codeVerifier, flow.codeVerifier);
      expect(loaded?.redirectUri, flow.redirectUri);
    });

    test('returns null for invalid stored payloads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'moor-oauth2-pending-flow': jsonEncode(<String, Object?>{
          'version': 1,
          'base_url': 'https://timbran.org',
        }),
      });

      expect(await OAuth2PendingFlowStore.load(), isNull);
    });

    test('clears the pending flow', () async {
      const flow = OAuth2PendingFlow(
        baseUrl: 'https://timbran.org',
        codeVerifier: 'pkce-verifier',
        redirectUri: 'moor://oauth/callback',
      );

      await OAuth2PendingFlowStore.save(flow);
      await OAuth2PendingFlowStore.clear();

      expect(await OAuth2PendingFlowStore.load(), isNull);
    });
  });
}
