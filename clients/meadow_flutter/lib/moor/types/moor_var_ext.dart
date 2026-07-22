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

import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

extension MoorVarNarrativeExt on MoorVar {
  /// Strictly decode used for narrative output: only allow strings or list-of-strings.
  /// Mirroring legacy decodeVarAsLines.
  List<String> asLines() {
    final v = value;
    if (v is String) return [v];
    if (v is MoorList) {
      return v.elements.map((e) => e.asString()).whereType<String>().toList();
    }
    return const [];
  }

  /// Coerce to text for loose UI elements, mirroring legacy _coerceText.
  String coerceText() {
    final v = value;
    if (v is MoorNone) return '';
    if (v is String) return v.trim();
    if (v is num || v is bool) return v.toString();
    if (v is MoorList) {
      return v.elements
          .map((e) => e.coerceText())
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim();
    }
    return '';
  }
}
