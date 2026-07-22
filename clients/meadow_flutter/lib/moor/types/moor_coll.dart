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

import 'package:collection/collection.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_var_generated.dart' as fbs;
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meta/meta.dart';

@immutable
class MoorList implements Comparable<MoorList> {
  final List<MoorVar> elements;

  MoorList(List<MoorVar> elements) : elements = List.unmodifiable(elements);

  factory MoorList.fromFlatBuffer(fbs.VarList list) {
    final els = list.elements;
    if (els == null) return MoorList(const []);
    return MoorList(els.map(MoorVar.fromFlatBuffer).toList());
  }

  String toLiteral() => '{${elements.map((e) => e.toLiteral()).join(', ')}}';

  fbs.VarListObjectBuilder toVarListBuilder() {
    return fbs.VarListObjectBuilder(
      elements: elements.map((e) => e.toVarBuilder()).toList(),
    );
  }

  fbs.VarObjectBuilder toVarBuilder() {
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarList,
      variant: toVarListBuilder(),
    );
  }

  MoorVar toVar() => MoorVar(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorList &&
          runtimeType == other.runtimeType &&
          const ListEquality<MoorVar>().equals(elements, other.elements);

  @override
  int get hashCode => const ListEquality<MoorVar>().hash(elements);

  @override
  int compareTo(MoorList other) {
    if (elements.length != other.elements.length) {
      return elements.length.compareTo(other.elements.length);
    }
    for (var i = 0; i < elements.length; i++) {
      final cmp = elements[i].compareTo(other.elements[i]);
      if (cmp != 0) return cmp;
    }
    return 0;
  }
}

@immutable
class MoorMap implements Comparable<MoorMap> {
  final Map<MoorVar, MoorVar> pairs;

  MoorMap(Map<MoorVar, MoorVar> pairs) : pairs = Map.unmodifiable(pairs);

  factory MoorMap.fromFlatBuffer(fbs.VarMap map) {
    final entries = map.pairs;
    if (entries == null) return MoorMap(const {});
    final out = <MoorVar, MoorVar>{};
    for (final entry in entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == null || value == null) continue;
      out[MoorVar.fromFlatBuffer(key)] = MoorVar.fromFlatBuffer(value);
    }
    return MoorMap(out);
  }

  String toLiteral() =>
      '[${pairs.entries.map((e) => '${e.key.toLiteral()} -> ${e.value.toLiteral()}').join(', ')}]';

  fbs.VarMapObjectBuilder toVarMapBuilder() {
    return fbs.VarMapObjectBuilder(
      pairs: pairs.entries.map((e) {
        return fbs.VarMapPairObjectBuilder(
          key: e.key.toVarBuilder(),
          value: e.value.toVarBuilder(),
        );
      }).toList(),
    );
  }

  fbs.VarObjectBuilder toVarBuilder() {
    return fbs.VarObjectBuilder(
      variantType: fbs.VarUnionTypeId.VarMap,
      variant: toVarMapBuilder(),
    );
  }

  MoorVar toVar() => MoorVar(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoorMap &&
          runtimeType == other.runtimeType &&
          const MapEquality<MoorVar, MoorVar>().equals(pairs, other.pairs);

  @override
  int get hashCode => const MapEquality<MoorVar, MoorVar>().hash(pairs);

  @override
  int compareTo(MoorMap other) {
    if (pairs.length != other.pairs.length) {
      return pairs.length.compareTo(other.pairs.length);
    }
    // Simple structural comparison of sorted keys/values
    final keys1 = pairs.keys.toList()..sort();
    final keys2 = other.pairs.keys.toList()..sort();
    for (var i = 0; i < keys1.length; i++) {
      final cmp = keys1[i].compareTo(keys2[i]);
      if (cmp != 0) return cmp;
      final valCmp = pairs[keys1[i]]!.compareTo(other.pairs[keys2[i]]!);
      if (valCmp != 0) return valCmp;
    }
    return 0;
  }
}
