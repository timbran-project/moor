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
import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:cryptography/cryptography.dart';

const int _chunkSize = 64 * 1024;
const int _aeadOverhead = 16;
const int _chunkSizeWithOverhead = _chunkSize + _aeadOverhead;

class _Stanza {
  final List<String> args;
  final Uint8List body;
  const _Stanza(this.args, this.body);
}

class _ParsedAgeHeader {
  final List<_Stanza> stanzas;
  final Uint8List headerNoMac;
  final Uint8List mac;
  final int headerSize;

  const _ParsedAgeHeader({
    required this.stanzas,
    required this.headerNoMac,
    required this.mac,
    required this.headerSize,
  });
}

/// Decrypt an age-encrypted blob using an X25519 identity string
/// (`AGE-SECRET-KEY-1...`).
Future<Uint8List> decryptEventBlobAge(
  Uint8List encrypted,
  String ageIdentity,
) async {
  final header = _parseHeader(encrypted);
  final fileKey = await _unwrapFileKey(header.stanzas, ageIdentity);
  if (fileKey == null) {
    throw Exception('age: no identity matched any recipient');
  }

  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final hmacKey = await hkdf.deriveKey(
    secretKey: SecretKey(fileKey),
    info: utf8.encode('header'),
  );
  final macCalc = await Hmac.sha256().calculateMac(
    header.headerNoMac,
    secretKey: hmacKey,
  );
  if (!_constantTimeEquals(header.mac, Uint8List.fromList(macCalc.bytes))) {
    throw Exception('age: invalid header HMAC');
  }

  final bodyOffset = header.headerSize;
  if (encrypted.length < bodyOffset + 16) {
    throw Exception('age: truncated payload');
  }
  final payloadNonce = encrypted.sublist(bodyOffset, bodyOffset + 16);
  final payloadCipher = encrypted.sublist(bodyOffset + 16);

  final streamKey = await hkdf.deriveKey(
    secretKey: SecretKey(fileKey),
    nonce: payloadNonce,
    info: utf8.encode('payload'),
  );
  final streamKeyBytes = Uint8List.fromList(await streamKey.extractBytes());
  return _decryptStream(payloadCipher, streamKeyBytes);
}

_ParsedAgeHeader _parseHeader(Uint8List bytes) {
  var pos = 0;

  int indexOfNewline(int start) {
    for (var i = start; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        return i;
      }
    }
    return -1;
  }

  String readLine() {
    final nl = indexOfNewline(pos);
    if (nl < 0) {
      throw Exception('age: invalid header (missing newline)');
    }
    final raw = bytes.sublist(pos, nl);
    pos = nl + 1;
    var s = ascii.decode(raw, allowInvalid: false);
    if (s.endsWith('\r')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  final versionLine = readLine();
  if (versionLine != 'age-encryption.org/v1') {
    throw Exception('age: invalid version line');
  }

  final stanzas = <_Stanza>[];
  for (;;) {
    final lineStart = pos;
    final line = readLine();
    if (line.startsWith('-> ')) {
      final parts = line.split(' ');
      if (parts.length < 3 || parts[0] != '->') {
        throw Exception('age: invalid stanza');
      }
      final args = parts.sublist(1);
      final bodyParts = <Uint8List>[];
      for (;;) {
        final bodyLine = readLine();
        final decoded = _base64NoPadDecode(bodyLine);
        if (decoded.length > 48) {
          throw Exception('age: invalid stanza body');
        }
        bodyParts.add(decoded);
        if (decoded.length < 48) {
          break;
        }
      }
      final body = Uint8List.fromList(bodyParts.expand((b) => b).toList());
      stanzas.add(_Stanza(args, body));
      continue;
    }

    if (!line.startsWith('--- ')) {
      throw Exception('age: invalid header (missing MAC)');
    }

    final mac = _base64NoPadDecode(line.substring(4));
    final headerNoMac = bytes.sublist(0, lineStart + 3);
    final headerSize = pos;
    return _ParsedAgeHeader(
      stanzas: stanzas,
      headerNoMac: Uint8List.fromList(headerNoMac),
      mac: mac,
      headerSize: headerSize,
    );
  }
}

Future<Uint8List?> _unwrapFileKey(
  List<_Stanza> stanzas,
  String identity,
) async {
  final scalar = _decodeAgeSecretKey(identity);
  final algorithm = X25519();
  final keyPair = await algorithm.newKeyPairFromSeed(scalar);
  final recipientPub = await keyPair.extractPublicKey();

  for (final s in stanzas) {
    if (s.args.isEmpty || s.args[0] != 'X25519') {
      continue;
    }
    if (s.args.length != 2) {
      throw Exception('age: invalid X25519 stanza');
    }
    final share = _base64NoPadDecode(s.args[1]);
    if (share.length != 32) {
      throw Exception('age: invalid X25519 stanza');
    }

    final secret = await algorithm.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        share,
        type: KeyPairType.x25519,
      ),
    );
    final secretBytes = Uint8List.fromList(await secret.extractBytes());

    final recipientBytes = Uint8List.fromList(recipientPub.bytes);
    final salt = Uint8List(share.length + recipientBytes.length)
      ..setAll(0, share)
      ..setAll(share.length, recipientBytes);

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(secretBytes),
      nonce: salt,
      info: utf8.encode('age-encryption.org/v1/X25519'),
    );
    final keyBytes = Uint8List.fromList(await key.extractBytes());

    final fileKey = await _decryptFileKey(s.body, keyBytes);
    if (fileKey != null) {
      return fileKey;
    }
  }
  return null;
}

Future<Uint8List?> _decryptFileKey(Uint8List body, Uint8List key) async {
  if (body.length != 32) {
    throw Exception('age: invalid stanza body length');
  }
  final algo = Chacha20.poly1305Aead();
  final nonce = Uint8List(12);
  try {
    final clear = await algo.decrypt(
      SecretBox(
        body.sublist(0, body.length - 16),
        nonce: nonce,
        mac: Mac(body.sublist(body.length - 16)),
      ),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(clear);
  } on Object {
    return null;
  }
}

Future<Uint8List> _decryptStream(Uint8List ciphertext, Uint8List key) async {
  final algo = Chacha20.poly1305Aead();
  if (ciphertext.length < _aeadOverhead) {
    throw Exception('age: ciphertext too small');
  }

  final out = BytesBuilder(copy: false);
  final nonceBase = Uint8List(12);

  void incNonce() {
    for (var i = nonceBase.length - 2; i >= 0; i--) {
      nonceBase[i] = (nonceBase[i] + 1) & 0xFF;
      if (nonceBase[i] != 0) {
        break;
      }
    }
  }

  var offset = 0;
  var firstChunk = true;
  while (offset < ciphertext.length) {
    final remaining = ciphertext.length - offset;
    final isLast = remaining <= _chunkSizeWithOverhead;
    final chunkLen = isLast ? remaining : _chunkSizeWithOverhead;

    if (!isLast && chunkLen != _chunkSizeWithOverhead) {
      throw Exception('age: invalid chunk size');
    }
    if (isLast && !firstChunk && chunkLen <= _aeadOverhead) {
      throw Exception('age: invalid final chunk size');
    }

    final chunk = ciphertext.sublist(offset, offset + chunkLen);
    final nonce = Uint8List.fromList(nonceBase);
    if (isLast) {
      nonce[11] = 1;
    }

    final clear = await algo.decrypt(
      SecretBox(
        chunk.sublist(0, chunk.length - 16),
        nonce: nonce,
        mac: Mac(chunk.sublist(chunk.length - 16)),
      ),
      secretKey: SecretKey(key),
    );

    if (!firstChunk && isLast && clear.isEmpty) {
      throw Exception('age: final chunk is empty');
    }

    out.add(clear);
    offset += chunkLen;

    if (!isLast) {
      incNonce();
      firstChunk = false;
    } else {
      break;
    }
  }

  return out.takeBytes();
}

Uint8List _decodeAgeSecretKey(String identity) {
  if (!identity.startsWith('AGE-SECRET-KEY-1')) {
    throw Exception('age: invalid identity prefix');
  }
  final decoded = bech32.decode(identity);
  if (decoded.hrp.toLowerCase() != 'age-secret-key-') {
    throw Exception('age: invalid identity hrp');
  }
  final bytes = _convertBits(decoded.data, from: 5, to: 8, pad: false);
  if (bytes.length != 32) {
    throw Exception('age: invalid identity length');
  }
  return Uint8List.fromList(bytes);
}

Uint8List _base64NoPadDecode(String s) {
  final cleaned = s.trim();
  if (cleaned.isEmpty) {
    return Uint8List(0);
  }
  var padded = cleaned;
  final mod = padded.length % 4;
  if (mod != 0) {
    padded = padded + ('=' * (4 - mod));
  }
  return Uint8List.fromList(base64.decode(padded));
}

List<int> _convertBits(
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
      throw Exception('age: invalid bech32 value');
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
  } else {
    if (bits >= from) {
      throw Exception('age: illegal padding');
    }
    if (((acc << (to - bits)) & maxv) != 0) {
      throw Exception('age: non-zero padding');
    }
  }

  return ret;
}

bool _constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var acc = 0;
  for (var i = 0; i < a.length; i++) {
    acc |= a[i] ^ b[i];
  }
  return acc == 0;
}
