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

import 'package:meadow_flutter/moor/event_log_kdf_native.dart'
    if (dart.library.js_interop) 'package:meadow_flutter/moor/event_log_kdf_web.dart';

/// Derive the 32-byte event-log key bytes from user password + identifier.
///
/// Must remain compatible across platforms (native + web) because the derived
/// identity is used to decrypt the same backend history.
Future<Uint8List> deriveEventLogKeyBytes({
  required String password,
  required String identifier,
}) {
  return deriveEventLogKeyBytesImpl(password: password, identifier: identifier);
}
