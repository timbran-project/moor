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

import 'package:bech32/bech32.dart';
import 'package:cryptography/cryptography.dart';

import 'package:meadow_flutter/moor/event_log_kdf.dart';

/// Event-log crypto helpers matching Meadow web:
/// - Argon2id derives 32 bytes using salt "moor-event-log-v1-$identifier"
/// - Derived bytes are encoded as AGE-SECRET-KEY-1... (bech32 hrp "age-secret-key-")
/// - Public key is X25519 basepoint multiplication encoded as age1... (bech32 hrp "age")
class EventLogEncryption {
  static Future<Uint8List> deriveKeyBytes({
    required String password,
    required String identifier,
  }) async {
    return deriveEventLogKeyBytes(password: password, identifier: identifier);
  }

  static String identityFromDerivedBytes(Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'expected 32');
    }
    final words = _convertBits(bytes, from: 8, to: 5, pad: true);
    final encoded = bech32.encode(Bech32('age-secret-key-', words));
    return encoded.toUpperCase();
  }

  static Future<String> publicKeyFromDerivedBytes(Uint8List bytes) async {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'expected 32');
    }

    final keyPair = await X25519().newKeyPairFromSeed(bytes);
    final pub = await keyPair.extractPublicKey();
    final pubBytes = Uint8List.fromList(pub.bytes);

    final words = _convertBits(pubBytes, from: 8, to: 5, pad: true);
    // Age recipients are bech32 with hrp "age", and are typically lowercase.
    return bech32.encode(Bech32('age', words));
  }

  static List<int> _convertBits(
    List<int> data, {
    required int from,
    required int to,
    required bool pad,
  }) {
    var acc = 0;
    var bits = 0;
    final ret = <int>[];
    final maxv = (1 << to) - 1;
    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw ArgumentError('invalid value $value for $from-bit input');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        ret.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        ret.add((acc << (to - bits)) & maxv);
      }
    } else if (bits >= from) {
      throw ArgumentError('illegal zero padding');
    } else if (((acc << (to - bits)) & maxv) != 0) {
      throw ArgumentError('non-zero padding');
    }

    return ret;
  }
}
