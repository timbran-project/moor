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

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';

class NarrativeFeedController extends ChangeNotifier {
  final List<NarrativeItem> _items = <NarrativeItem>[];
  final NarrativeTracker _tracker = NarrativeTracker();

  List<NarrativeItem> get items => UnmodifiableListView<NarrativeItem>(_items);
  NarrativeTracker get tracker => _tracker;

  bool appendItem(NarrativeItem item) {
    if (_tracker.contains(item)) {
      return false;
    }
    _items.add(item);
    _tracker.remember(item);
    notifyListeners();
    return true;
  }

  bool appendNarrativeText(
    String text, {
    required String Function(String prefix) newId,
    String contentType = 'text/plain',
    DateTime Function()? now,
  }) {
    if (text.trim().isEmpty) {
      return false;
    }
    return appendItem(
      NarrativeItem(
        id: newId('local'),
        timestamp: (now ?? DateTime.now).call(),
        content: <String>[text],
        contentType: contentType,
        noNewline: false,
        presentationHint: null,
        groupId: null,
        metadata: null,
      ),
    );
  }

  int prependHistoricalItems(List<NarrativeItem> items) {
    if (items.isEmpty) {
      return 0;
    }

    final uniqueItems = <NarrativeItem>[];
    for (final item in items) {
      if (_tracker.contains(item)) {
        continue;
      }
      uniqueItems.add(item);
    }
    if (uniqueItems.isEmpty) {
      return 0;
    }

    _items.insertAll(0, uniqueItems);
    for (final item in uniqueItems) {
      _tracker.remember(item);
    }
    notifyListeners();
    return uniqueItems.length;
  }

  void clear() {
    if (_items.isEmpty) {
      return;
    }
    _items.clear();
    notifyListeners();
  }
}
