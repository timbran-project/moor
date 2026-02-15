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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:argon2/argon2.dart';

const _kdfSaltPrefix = 'moor-event-log-v1-';

Future<Uint8List> deriveEventLogKeyBytesImpl({
  required String password,
  required String identifier,
}) async {
  return Isolate.run(() {
    final salt = utf8.encode('$_kdfSaltPrefix$identifier');
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      Uint8List.fromList(salt),
      memory: 65536, // 64 MiB (memory blocks are 1KiB each)
      lanes: 4,
      // iterations defaults to 3 in argon2 package.
    );

    final gen = Argon2BytesGenerator()..init(params);
    final out = Uint8List(32);
    gen.generateBytesFromString(password, out);
    return out;
  });
}
