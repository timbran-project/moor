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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/widgets/session_dialogs.dart';

void main() {
  test('buildHistoryEncryptionStatusText summarizes key availability', () {
    expect(
      buildHistoryEncryptionStatusText(
        playerOid: 'oid:1',
        backendHasPubkey: true,
        hasLocalKey: false,
      ),
      equals('player: oid:1\nbackend pubkey: yes\nlocal key: no'),
    );
  });
}
