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

class ObjectRef {
  final String curie;

  const ObjectRef(this.curie);

  @override
  String toString() => curie;
}

String? _stringToCurie(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  if (s.startsWith('#')) {
    final n = int.tryParse(s.substring(1));
    return n == null ? null : 'oid:$n';
  }

  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.tryParse(s);
    return n == null ? null : 'oid:$n';
  }

  // Already a CURIE from the server (or from our own tooling).
  if (s.contains(':')) {
    return s.toLowerCase();
  }

  return null;
}

ObjectRef? objectRefFromDynamic(Object? value) {
  if (value == null) return null;

  if (value is ObjectRef) return value;

  if (value is int) {
    return ObjectRef('oid:$value');
  }

  if (value is String) {
    final curie = _stringToCurie(value);
    return curie == null ? null : ObjectRef(curie);
  }

  if (value is Map) {
    // Meadow/web established shape: { oid: N } / { uuid: "..."} and sometimes nested.
    final oid = value['oid'];
    final nestedOid = objectRefFromDynamic(oid);
    if (nestedOid != null) return nestedOid;

    final uuid = value['uuid'];
    if (uuid is String) {
      final raw = uuid.trim();
      if (raw.isEmpty) return null;
      final curie = raw.contains(':')
          ? raw.toLowerCase()
          : 'uuid:${raw.toLowerCase()}';
      return ObjectRef(curie);
    }
    if (uuid is int) {
      return ObjectRef('uuid:$uuid');
    }
  }

  return null;
}

String? objectRefToCurie(Object? value) => objectRefFromDynamic(value)?.curie;
