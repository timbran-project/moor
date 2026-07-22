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

/// Result from the unlock prompt: either a password, a request to reset
/// (forgot password), or null/skip.
sealed class UnlockPromptResult {}

class UnlockWithPassword extends UnlockPromptResult {
  final String password;
  UnlockWithPassword(this.password);
}

class UnlockForgotPassword extends UnlockPromptResult {}

typedef GetLocalIdentity = Future<String?> Function(String playerOid);
typedef SetLocalIdentity =
    Future<void> Function({
      required String playerOid,
      required String ageIdentity,
    });
typedef RemoveLocalIdentity = Future<void> Function(String playerOid);
typedef GetBackendPubkey =
    Future<String?> Function({required String authToken});
typedef SetBackendPubkey =
    Future<void> Function({
      required String authToken,
      required String publicKey,
    });
typedef DeriveKeyBytes =
    Future<Uint8List> Function({
      required String password,
      required String identifier,
    });
typedef IdentityFromDerivedBytes = String Function(Uint8List derived);
typedef PublicKeyFromDerivedBytes = Future<String> Function(Uint8List derived);

class HistoryEncryptionController extends ChangeNotifier {
  final GetLocalIdentity _getLocalIdentity;
  final SetLocalIdentity _setLocalIdentity;
  final RemoveLocalIdentity _removeLocalIdentity;
  final GetBackendPubkey _getBackendPubkey;
  final SetBackendPubkey _setBackendPubkey;
  final DeriveKeyBytes _deriveKeyBytes;
  final IdentityFromDerivedBytes _identityFromDerivedBytes;
  final PublicKeyFromDerivedBytes _publicKeyFromDerivedBytes;

  bool _backendHasPubkey = false;
  bool _hasLocalKey = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  bool _wasWsConnected = false;

  HistoryEncryptionController({
    required GetLocalIdentity getLocalIdentity,
    required SetLocalIdentity setLocalIdentity,
    required RemoveLocalIdentity removeLocalIdentity,
    required GetBackendPubkey getBackendPubkey,
    required SetBackendPubkey setBackendPubkey,
    required DeriveKeyBytes deriveKeyBytes,
    required IdentityFromDerivedBytes identityFromDerivedBytes,
    required PublicKeyFromDerivedBytes publicKeyFromDerivedBytes,
  }) : _getLocalIdentity = getLocalIdentity,
       _setLocalIdentity = setLocalIdentity,
       _removeLocalIdentity = removeLocalIdentity,
       _getBackendPubkey = getBackendPubkey,
       _setBackendPubkey = setBackendPubkey,
       _deriveKeyBytes = deriveKeyBytes,
       _identityFromDerivedBytes = identityFromDerivedBytes,
       _publicKeyFromDerivedBytes = publicKeyFromDerivedBytes;

  bool get backendHasPubkey => _backendHasPubkey;
  bool get hasLocalKey => _hasLocalKey;
  bool get historyLoaded => _historyLoaded;
  bool get historyLoading => _historyLoading;

  Future<void> init({
    required String playerOid,
    required String authToken,
    required Future<UnlockPromptResult?> Function() promptForPassword,
    required Future<String?> Function() promptForSetup,
    required Future<void> Function() loadInitialHistory,
    required void Function(String message) onSystemMessage,
  }) async {
    final localIdentity = await _getLocalIdentity(playerOid);
    final hasLocal = localIdentity != null && localIdentity.trim().isNotEmpty;

    String? backendPubkey;
    try {
      backendPubkey = await _getBackendPubkey(authToken: authToken);
    } on Object catch (e) {
      onSystemMessage('History encryption check failed: $e');
      return;
    }

    _backendHasPubkey =
        backendPubkey != null && backendPubkey.trim().isNotEmpty;
    _hasLocalKey = hasLocal;
    debugPrint(
      '[encryption] init: playerOid=$playerOid '
      'backendHasPubkey=$_backendHasPubkey hasLocalKey=$_hasLocalKey',
    );
    notifyListeners();

    if (hasLocal && !_backendHasPubkey) {
      await _removeLocalIdentity(playerOid);
      onSystemMessage(
        'History encryption: backend missing pubkey, clearing local key',
      );
      _hasLocalKey = false;
      notifyListeners();
    }

    if (!_backendHasPubkey && !_hasLocalKey) {
      final setupPassword = await promptForSetup();
      if (setupPassword == null || setupPassword.isEmpty) {
        onSystemMessage('History encryption skipped');
        return;
      }
      await setup(
        playerOid: playerOid,
        authToken: authToken,
        password: setupPassword,
        loadInitialHistory: loadInitialHistory,
        onSystemMessage: onSystemMessage,
      );
      return;
    }

    if (_backendHasPubkey && !_hasLocalKey) {
      final result = await promptForPassword();
      switch (result) {
        case UnlockWithPassword(:final password):
          await unlock(
            playerOid: playerOid,
            password: password,
            loadInitialHistory: loadInitialHistory,
            onSystemMessage: onSystemMessage,
          );
        case UnlockForgotPassword():
          // Clear the server-side key so the user can set up fresh.
          await _removeLocalIdentity(playerOid);
          _backendHasPubkey = false;
          _hasLocalKey = false;
          notifyListeners();
          onSystemMessage(
            'History encryption reset — old history is no longer accessible',
          );
          // Prompt for new setup.
          final setupPassword = await promptForSetup();
          if (setupPassword == null || setupPassword.isEmpty) {
            return;
          }
          await setup(
            playerOid: playerOid,
            authToken: authToken,
            password: setupPassword,
            loadInitialHistory: loadInitialHistory,
            onSystemMessage: onSystemMessage,
          );
        case null:
          onSystemMessage('History encryption locked (no password provided)');
      }
      return;
    }

    if (_backendHasPubkey && _hasLocalKey) {
      onSystemMessage('History encryption unlocked');
      await loadInitialHistory();
    }
  }

  Future<void> setup({
    required String playerOid,
    required String authToken,
    required String password,
    required Future<void> Function() loadInitialHistory,
    required void Function(String message) onSystemMessage,
  }) async {
    try {
      onSystemMessage('Setting up history encryption...');
      final derived = await _deriveKeyBytes(
        password: password,
        identifier: playerOid,
      );
      debugPrint(
        '[encryption] derived ${derived.length} bytes: '
        '${derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      final identity = _identityFromDerivedBytes(derived);
      final pubkey = await _publicKeyFromDerivedBytes(derived);
      debugPrint(
        '[encryption] setup: pubkey=${pubkey.length > 20 ? '${pubkey.substring(0, 20)}...' : pubkey} '
        'identity=${identity.length > 20 ? '${identity.substring(0, 20)}...' : identity}',
      );
      await _setBackendPubkey(authToken: authToken, publicKey: pubkey);
      await _setLocalIdentity(playerOid: playerOid, ageIdentity: identity);
      onSystemMessage('History encryption set');
      _backendHasPubkey = true;
      _hasLocalKey = true;
      notifyListeners();
      await loadInitialHistory();
    } on Object catch (e, st) {
      debugPrint('[encryption] setup failed: $e\n$st');
      onSystemMessage('History encryption setup failed: $e');
    }
  }

  Future<void> unlock({
    required String playerOid,
    required String password,
    required Future<void> Function() loadInitialHistory,
    required void Function(String message) onSystemMessage,
  }) async {
    try {
      onSystemMessage('Unlocking history encryption...');
      final derived = await _deriveKeyBytes(
        password: password,
        identifier: playerOid,
      );
      debugPrint(
        '[encryption] derived ${derived.length} bytes: '
        '${derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      final identity = _identityFromDerivedBytes(derived);
      debugPrint(
        '[encryption] unlock: playerOid=$playerOid '
        'identity=${identity.length > 20 ? '${identity.substring(0, 20)}...' : identity}',
      );
      await _setLocalIdentity(playerOid: playerOid, ageIdentity: identity);
      _hasLocalKey = true;
      notifyListeners();
      onSystemMessage('History encryption unlocked');
      await loadInitialHistory();
    } on Object catch (e, st) {
      debugPrint('[encryption] unlock failed: $e\n$st');
      onSystemMessage('History encryption unlock failed: $e');
    }
  }

  Future<void> forgetLocalKey({
    required String playerOid,
    required void Function(String message) onSystemMessage,
  }) async {
    await _removeLocalIdentity(playerOid);
    _hasLocalKey = false;
    notifyListeners();
    onSystemMessage('History encryption: forgot local key');
  }

  bool shouldLoadHistoryOnConnect() {
    return _hasLocalKey && !_historyLoaded && !_historyLoading;
  }

  void markWsConnected() {
    _wasWsConnected = true;
  }

  bool markWsDisconnectedAndShouldResyncHistory() {
    final shouldResync = _wasWsConnected && _hasLocalKey && _historyLoaded;
    _wasWsConnected = false;
    if (shouldResync) {
      _historyLoaded = false;
      notifyListeners();
    }
    return shouldResync;
  }

  bool beginHistoryLoad() {
    if (_historyLoading || _historyLoaded) {
      return false;
    }
    _historyLoading = true;
    notifyListeners();
    return true;
  }

  void completeHistoryLoad() {
    _historyLoaded = true;
    notifyListeners();
  }

  void finishHistoryLoad() {
    _historyLoading = false;
    notifyListeners();
  }
}
