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

import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meta/meta.dart';

@immutable
class MoorSym implements Comparable<MoorSym> {
  final String name;

  const MoorSym(this.name);

  String toLiteral() => ':$name';

  fbs.VarSymObjectBuilder toVarSymBuilder() {
    return fbs.VarSymObjectBuilder(
      symbol: common.SymbolObjectBuilder(value: name),
    );
  }

  fbs.VarObjectBuilder toVarBuilder() {
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarSym,
      variant: toVarSymBuilder(),
    );
  }

  MoorVar toVar() => MoorVar(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorSym &&
          runtimeType == other.runtimeType &&
          name.toLowerCase() == other.name.toLowerCase();

  @override
  int get hashCode => name.toLowerCase().hashCode;

  @override
  int compareTo(MoorSym other) =>
      name.toLowerCase().compareTo(other.name.toLowerCase());
}
