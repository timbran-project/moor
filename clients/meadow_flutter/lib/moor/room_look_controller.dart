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

import 'package:flutter/material.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';
import 'package:meadow_flutter/moor/presentations.dart';

class RoomLookController extends ChangeNotifier {
  String? _currentRoomLookKey;
  String? _currentRoomLookMessageId;
  bool _isDockLatched = false;

  String? get currentRoomLookKey => _currentRoomLookKey;
  String? get currentRoomLookMessageId => _currentRoomLookMessageId;
  bool get isDockLatched => _isDockLatched;

  String? suppressedRoomKey({required bool roomHudEnabled}) {
    if (!roomHudEnabled || _isDockLatched) {
      return null;
    }
    return _currentRoomLookKey;
  }

  void handlePresentationsChanged(
    PresentationStore presentations, {
    required bool roomHudEnabled,
  }) {
    final nextKey = _computeCurrentRoomLookKey(
      presentations,
      roomHudEnabled: roomHudEnabled,
    );
    if (nextKey == _currentRoomLookKey) {
      return;
    }
    _currentRoomLookKey = nextKey;
    _currentRoomLookMessageId = null;
    _isDockLatched = false;
    notifyListeners();
  }

  void updateLatch({
    required bool roomHudEnabled,
    required NarrativeTracker tracker,
    required GlobalKey listKey,
    required Map<String, GlobalKey> messageKeys,
  }) {
    if (!roomHudEnabled) {
      return;
    }
    final roomKey = _currentRoomLookKey;
    if (roomKey == null) {
      return;
    }

    final msgId = tracker.latestLookMessageIdForRoom(roomKey);
    if (msgId == null) {
      return;
    }

    if (msgId != _currentRoomLookMessageId) {
      _currentRoomLookMessageId = msgId;
      _isDockLatched = false;
      notifyListeners();
      return;
    }

    if (_isDockLatched) {
      return;
    }

    final targetKey = messageKeys[msgId];
    final targetCtx = targetKey?.currentContext;
    final listCtx = listKey.currentContext;
    if (targetCtx == null || listCtx == null) {
      return;
    }

    final targetBox = targetCtx.findRenderObject();
    final listBox = listCtx.findRenderObject();
    if (targetBox is! RenderBox || listBox is! RenderBox) {
      return;
    }
    if (!targetBox.attached || !listBox.attached) {
      return;
    }
    if (!targetBox.hasSize || !listBox.hasSize) {
      return;
    }

    double targetTop;
    double listTop;
    try {
      targetTop = targetBox.localToGlobal(Offset.zero).dy;
      listTop = listBox.localToGlobal(Offset.zero).dy;
    } on Object {
      return;
    }
    final listBottom = listTop + listBox.size.height;
    const epsilon = 1.0;
    final isVisible =
        targetTop >= (listTop - epsilon) && targetTop < (listBottom + epsilon);
    if (isVisible) {
      return;
    }
    _isDockLatched = true;
    notifyListeners();
  }

  String? _computeCurrentRoomLookKey(
    PresentationStore presentations, {
    required bool roomHudEnabled,
  }) {
    if (!roomHudEnabled) {
      return null;
    }
    final tops = presentations.byTarget('top');
    for (final item in tops) {
      if (item.id == 'room-look') {
        return getRoomLookKeyFromDockItem(item);
      }
    }
    return null;
  }
}
