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

import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_var.dart';

String escapeMooString(String s) {
  // Match Meadow web behavior: escape backslash and double quote.
  return s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

String varToMooLiteral(fbs.Var? v) {
  if (v == null) return 'none';
  return MoorVar.fromFlatBuffer(v).toLiteral();
}

bool isSupportedMooLiteralVar(fbs.Var? v) {
  if (v == null) return true;
  final t = v.variantType?.value;
  // Support everything except Binary, Flyweight, Lambda for now.
  return t != null && t > 0 && t <= 10;
}
