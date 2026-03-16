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
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const _kdfSaltPrefix = 'moor-event-log-v1-';

// int moor_argon2id_hash(
//     const uint8_t *pwd, uint32_t pwdlen,
//     const uint8_t *salt, uint32_t saltlen,
//     uint32_t t_cost, uint32_t m_cost, uint32_t parallelism,
//     uint8_t *out, uint32_t hashlen)
typedef _Argon2idHashNative = Int32 Function(
  Pointer<Uint8> pwd, Uint32 pwdlen,
  Pointer<Uint8> salt, Uint32 saltlen,
  Uint32 tCost, Uint32 mCost, Uint32 parallelism,
  Pointer<Uint8> out, Uint32 hashlen,
);
typedef _Argon2idHash = int Function(
  Pointer<Uint8> pwd, int pwdlen,
  Pointer<Uint8> salt, int saltlen,
  int tCost, int mCost, int parallelism,
  Pointer<Uint8> out, int hashlen,
);

DynamicLibrary _loadArgon2Lib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libmoor_argon2.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.executable();
  }
  if (Platform.isLinux) {
    // In Flutter debug/release the library is next to the executable or in lib/.
    final exe = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exe/lib/libmoor_argon2.so',
      '$exe/libmoor_argon2.so',
      './libmoor_argon2.so',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) {
        return DynamicLibrary.open(path);
      }
    }
    // Last resort: let the system linker find it.
    return DynamicLibrary.open('libmoor_argon2.so');
  }
  throw UnsupportedError('Unsupported platform for argon2 FFI');
}

final _Argon2idHash _argon2idHash = _loadArgon2Lib()
    .lookup<NativeFunction<_Argon2idHashNative>>('moor_argon2id_hash')
    .asFunction<_Argon2idHash>();

Future<Uint8List> deriveEventLogKeyBytesImpl({
  required String password,
  required String identifier,
}) async {
  final pwdBytes = utf8.encode(password);
  final saltBytes = utf8.encode('$_kdfSaltPrefix$identifier');
  const hashLen = 32;

  final pwdPtr = calloc<Uint8>(pwdBytes.length);
  final saltPtr = calloc<Uint8>(saltBytes.length);
  final outPtr = calloc<Uint8>(hashLen);

  try {
    pwdPtr.asTypedList(pwdBytes.length).setAll(0, pwdBytes);
    saltPtr.asTypedList(saltBytes.length).setAll(0, saltBytes);

    final rc = _argon2idHash(
      pwdPtr, pwdBytes.length,
      saltPtr, saltBytes.length,
      3, // iterations
      65536, // memory in KiB (64 MiB)
      4, // parallelism
      outPtr, hashLen,
    );
    if (rc != 0) {
      throw StateError('argon2id_hash_raw failed with error code $rc');
    }
    return Uint8List.fromList(outPtr.asTypedList(hashLen));
  } finally {
    calloc
      ..free(pwdPtr)
      ..free(saltPtr)
      ..free(outPtr);
  }
}
