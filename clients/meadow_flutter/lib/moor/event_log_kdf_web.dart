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

import 'package:js/js_util.dart' as js_util;

const _kdfSaltPrefix = 'moor-event-log-v1-';

Future<Uint8List> deriveEventLogKeyBytesImpl({
  required String password,
  required String identifier,
}) async {
  final argon2 = js_util.getProperty<Object?>(js_util.globalThis, 'argon2');
  if (argon2 == null) {
    throw StateError(
      'argon2 JS runtime not found; ensure argon2-browser is loaded in web/index.html',
    );
  }
  final argon2Obj = argon2 as Object;

  // NOTE: These parameters must stay aligned with the native implementation
  // (argon2 package defaults) and Meadow web:
  // - type: Argon2id
  // - iterations: 3
  // - memory: 65536 KiB
  // - lanes/parallelism: 4
  // - output: 32 bytes
  final salt = '$_kdfSaltPrefix$identifier';
  final options = <String, Object?>{
    'pass': password,
    'salt': salt,
    'time': 3,
    'mem': 65536,
    'parallelism': 4,
    'hashLen': 32,
    // argon2-browser uses numeric enum values: 2 == Argon2id
    // https://github.com/antelle/argon2-browser
    'type': 2,
  };

  // Argon2 expects a plain JS object, not a Dart Map.
  final jsOptions = js_util.jsify(options);

  final promise = js_util.callMethod<Object>(argon2Obj, 'hash', <Object?>[
    jsOptions,
  ]);
  final result = await js_util.promiseToFuture<Object>(promise);

  // Meadow web uses `result.hash` (Uint8Array) directly. Prefer that, but
  // fall back to `hashHex` for resilience across argon2-browser variants.
  final hash = js_util.getProperty<Object?>(result, 'hash');
  if (hash is Uint8List) {
    return hash;
  }

  final hashHex = js_util.getProperty<Object?>(result, 'hashHex');
  if (hashHex is String && hashHex.length == 64) {
    return _hexToBytes(hashHex);
  }

  throw StateError(
    'argon2.hash returned invalid result (missing hash/hashHex)',
  );
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    final byteHex = hex.substring(i * 2, i * 2 + 2);
    bytes[i] = int.parse(byteHex, radix: 16);
  }
  return bytes;
}
