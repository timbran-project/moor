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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/history_encryption_controller.dart';

void main() {
  group('HistoryEncryptionController', () {
    test('clears stale local key when backend has no pubkey', () async {
      var removedPlayer = '';
      final controller = HistoryEncryptionController(
        getLocalIdentity: (_) async => 'identity',
        setLocalIdentity: ({required playerOid, required ageIdentity}) async {},
        removeLocalIdentity: (playerOid) async {
          removedPlayer = playerOid;
        },
        getBackendPubkey: ({required authToken}) async => null,
        setBackendPubkey: ({required authToken, required publicKey}) async {},
        deriveKeyBytes: ({required password, required identifier}) async =>
            Uint8List(0),
        identityFromDerivedBytes: (_) => '',
        publicKeyFromDerivedBytes: (_) async => '',
      );
      addTearDown(controller.dispose);
      final messages = <String>[];

      await controller.init(
        playerOid: 'oid:1',
        authToken: 'token',
        promptForPassword: () async => null,
        promptForSetup: () async => null,
        loadInitialHistory: () async {},
        onSystemMessage: messages.add,
      );

      expect(removedPlayer, equals('oid:1'));
      expect(controller.backendHasPubkey, isFalse);
      expect(controller.hasLocalKey, isFalse);
      expect(
        messages,
        contains(
          'History encryption: backend missing pubkey, clearing local key',
        ),
      );
    });

    test('unlock stores local key and loads history', () async {
      var setIdentityPlayer = '';
      var loadCalls = 0;
      final controller = HistoryEncryptionController(
        getLocalIdentity: (_) async => null,
        setLocalIdentity: ({required playerOid, required ageIdentity}) async {
          setIdentityPlayer = playerOid;
        },
        removeLocalIdentity: (_) async {},
        getBackendPubkey: ({required authToken}) async => 'pubkey',
        setBackendPubkey: ({required authToken, required publicKey}) async {},
        deriveKeyBytes: ({required password, required identifier}) async =>
            Uint8List.fromList(<int>[1, 2, 3]),
        identityFromDerivedBytes: (_) => 'identity',
        publicKeyFromDerivedBytes: (_) async => 'pubkey',
      );
      addTearDown(controller.dispose);

      await controller.unlock(
        playerOid: 'oid:1',
        password: 'secret',
        loadInitialHistory: () async {
          loadCalls += 1;
        },
        onSystemMessage: (_) {},
      );

      expect(setIdentityPlayer, equals('oid:1'));
      expect(controller.hasLocalKey, isTrue);
      expect(loadCalls, equals(1));
    });

    test('connection bookkeeping requests history resync after disconnect', () {
      final controller = HistoryEncryptionController(
        getLocalIdentity: (_) async => null,
        setLocalIdentity: ({required playerOid, required ageIdentity}) async {},
        removeLocalIdentity: (_) async {},
        getBackendPubkey: ({required authToken}) async => null,
        setBackendPubkey: ({required authToken, required publicKey}) async {},
        deriveKeyBytes: ({required password, required identifier}) async =>
            Uint8List(0),
        identityFromDerivedBytes: (_) => '',
        publicKeyFromDerivedBytes: (_) async => '',
      );
      addTearDown(controller.dispose);

      controller.markWsConnected();

      expect(controller.markWsDisconnectedAndShouldResyncHistory(), isFalse);
    });

    test(
      'resyncs history after disconnect when unlocked history was loaded',
      () async {
        final controller = HistoryEncryptionController(
          getLocalIdentity: (_) async => null,
          setLocalIdentity:
              ({required playerOid, required ageIdentity}) async {},
          removeLocalIdentity: (_) async {},
          getBackendPubkey: ({required authToken}) async => null,
          setBackendPubkey: ({required authToken, required publicKey}) async {},
          deriveKeyBytes: ({required password, required identifier}) async =>
              Uint8List.fromList(<int>[1]),
          identityFromDerivedBytes: (_) => 'identity',
          publicKeyFromDerivedBytes: (_) async => '',
        );
        addTearDown(controller.dispose);

        await controller.unlock(
          playerOid: 'oid:1',
          password: 'secret',
          loadInitialHistory: () async {
            expect(controller.beginHistoryLoad(), isTrue);
            controller
              ..completeHistoryLoad()
              ..finishHistoryLoad();
          },
          onSystemMessage: (_) {},
        );

        controller.markWsConnected();

        expect(controller.markWsDisconnectedAndShouldResyncHistory(), isTrue);
        expect(controller.historyLoaded, isFalse);
      },
    );
  });
}
