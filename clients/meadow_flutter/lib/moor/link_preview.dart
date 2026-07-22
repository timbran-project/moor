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

import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';
import 'package:meta/meta.dart';

@immutable
class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? image;
  final String? siteName;

  const LinkPreviewData({
    required this.url,
    required this.title,
    required this.description,
    required this.image,
    required this.siteName,
  });
}

@immutable
class NarrativeThumbnailData {
  final String contentType;
  final Uint8List data;

  const NarrativeThumbnailData({
    required this.contentType,
    required this.data,
  });
}

LinkPreviewData? parseLinkPreviewData(Object? value) {
  final map = _asStringMap(value);
  if (map == null) {
    return null;
  }

  final url = _nonEmpty(map['url']);
  if (url == null) {
    return null;
  }

  return LinkPreviewData(
    url: url,
    title: _nonEmpty(map['title']),
    description: _nonEmpty(map['description']),
    image: _nonEmpty(map['image']),
    siteName: _nonEmpty(map['site_name']) ?? _nonEmpty(map['siteName']),
  );
}

NarrativeThumbnailData? parseNarrativeThumbnailData(Object? value) {
  if (value == null) {
    return null;
  }
  final list = MoorVar(value).asList();
  if (list == null || list.elements.length != 2) {
    return null;
  }
  final contentType = _nonEmpty(list.elements[0].value);
  final bytes = list.elements[1].asBinary();
  if (contentType == null || bytes == null || bytes.isEmpty) {
    return null;
  }
  return NarrativeThumbnailData(
    contentType: contentType,
    data: bytes,
  );
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  final moorMap = MoorVar(value).asMap();
  if (moorMap == null) {
    return null;
  }

  final out = <String, Object?>{};
  for (final entry in moorMap.pairs.entries) {
    final key =
        entry.key.asString() ??
        (entry.key.value is MoorSym ? (entry.key.value as MoorSym).name : null);
    if (key == null || key.trim().isEmpty) {
      continue;
    }
    out[key] = entry.value.value;
  }
  return out;
}

String? _nonEmpty(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value is String ? value.trim() : MoorVar(value).coerceText();
  return text.isEmpty ? null : text;
}
