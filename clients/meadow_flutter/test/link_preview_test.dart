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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/moor/link_preview.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

void main() {
  group('LinkPreviewData', () {
    test('parseLinkPreviewData decodes moor map payloads', () {
      final preview = parseLinkPreviewData(
        MoorMap(const <MoorVar, MoorVar>{
          MoorVar('url'): MoorVar('https://example.com/post'),
          MoorVar('title'): MoorVar('Example post'),
          MoorVar('description'): MoorVar('A concise description'),
          MoorVar('image'): MoorVar('https://example.com/cover.jpg'),
          MoorVar('site_name'): MoorVar('Example'),
        }),
      );

      expect(preview, isNotNull);
      expect(preview?.url, equals('https://example.com/post'));
      expect(preview?.title, equals('Example post'));
      expect(preview?.description, equals('A concise description'));
      expect(preview?.image, equals('https://example.com/cover.jpg'));
      expect(preview?.siteName, equals('Example'));
    });

    test('parseNarrativeThumbnailData decodes content type and bytes', () {
      final thumbnail = parseNarrativeThumbnailData(
        MoorList(<MoorVar>[
          const MoorVar('image/png'),
          MoorVar(Uint8List.fromList(<int>[1, 2, 3, 4])),
        ]),
      );

      expect(thumbnail, isNotNull);
      expect(thumbnail?.contentType, equals('image/png'));
      expect(thumbnail?.data, equals(<int>[1, 2, 3, 4]));
    });
  });
}
