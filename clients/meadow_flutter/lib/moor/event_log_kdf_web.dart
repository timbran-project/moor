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

import 'dart:js_interop';
import 'dart:typed_data';

@JS('argon2')
external JSAny? get _argon2Raw;

@JS('argon2')
external JSArgon2 get _argon2;

@JS()
@staticInterop
extension type JSArgon2(JSObject _) implements JSObject {
  external JSPromise<JSArgon2Result> hash(JSArgon2Options options);
}

@JS()
@staticInterop
@anonymous
extension type JSArgon2Options._(JSObject _) implements JSObject {
  external factory JSArgon2Options({
    JSString pass,
    JSString salt,
    JSNumber time,
    JSNumber mem,
    JSNumber parallelism,
    JSNumber hashLen,
    JSNumber type,
  });
}

@JS()
@staticInterop
extension type JSArgon2Result(JSObject _) implements JSObject {
  external JSUint8Array? get hash;
  external JSString? get hashHex;
}

const _kdfSaltPrefix = 'moor-event-log-v1-';

Future<Uint8List> deriveEventLogKeyBytesImpl({
  required String password,
  required String identifier,
}) async {
  // Check if argon2 is defined on globalThis
  if (_argon2Raw == null) {
    throw StateError(
      'argon2 JS runtime not found; ensure argon2-browser is loaded in web/index.html',
    );
  }

  // NOTE: These parameters must stay aligned with the native implementation
  // (argon2 package defaults) and Meadow web:
  // - type: Argon2id
  // - iterations: 3
  // - memory: 65536 KiB
  // - lanes/parallelism: 4
  // - output: 32 bytes
  final salt = '$_kdfSaltPrefix$identifier';
  final options = JSArgon2Options(
    pass: password.toJS,
    salt: salt.toJS,
    time: 3.toJS,
    mem: 65536.toJS,
    parallelism: 4.toJS,
    hashLen: 32.toJS,
    // argon2-browser uses numeric enum values: 2 == Argon2id
    // https://github.com/antelle/argon2-browser
    type: 2.toJS,
  );

  final result = await _argon2.hash(options).toDart;

  // Meadow web uses `result.hash` (Uint8Array) directly. Prefer that, but
  // fall back to `hashHex` for resilience across argon2-browser variants.
  final hash = result.hash;
  if (hash != null) {
    return hash.toDart;
  }

  final hashHex = result.hashHex;
  if (hashHex != null) {
    final hexStr = hashHex.toDart;
    if (hexStr.length == 64) {
      return _hexToBytes(hexStr);
    }
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
