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
import 'package:meadow_flutter/moor/types/moor_str.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';

class InspectAction {
  final String label;
  final String? kind;
  final String? command;
  final String? verb;
  final String? target;
  final List<String> args;
  final String? inputType;
  final String? inputPrompt;
  final String? inputPlaceholder;
  final String? resultMode;
  final String? panelTarget;
  final String? panelId;
  final String? panelTitle;

  const InspectAction({
    required this.label,
    required this.kind,
    required this.command,
    required this.verb,
    required this.target,
    required this.args,
    required this.inputType,
    required this.inputPrompt,
    required this.inputPlaceholder,
    required this.resultMode,
    required this.panelTarget,
    required this.panelId,
    required this.panelTitle,
  });
}

class InspectData {
  final String title;
  final String description;
  final List<InspectAction> actions;

  const InspectData({
    required this.title,
    required this.description,
    required this.actions,
  });
}

InspectData? parseInspectData(MoorVar decoded) {
  final map = decoded.asMap();
  if (map == null) {
    return null;
  }

  final title = _mapValue(map, 'title')?.coerceText() ?? '';
  final description = _mapValue(map, 'description')?.coerceText() ?? '';
  if (title.isEmpty && description.isEmpty) {
    return null;
  }

  final actions = <InspectAction>[];
  final actionList = _mapValue(map, 'actions')?.asList();
  if (actionList != null) {
    for (final v in actionList.elements) {
      final actionMap = v.asMap();
      if (actionMap == null) continue;

      final label =
          _mapValueAny(actionMap, const ['label'])?.coerceText() ?? '';
      if (label.isEmpty) continue;

      final kind = _nonEmpty(
        _mapValueAny(actionMap, const ['kind'])?.coerceText(),
      );
      final command = _nonEmpty(
        _mapValueAny(actionMap, const ['command'])?.coerceText(),
      );
      final verb = _nonEmpty(
        _mapValueAny(actionMap, const ['verb'])?.coerceText(),
      );
      final target = _nonEmpty(
        _mapValueAny(actionMap, const ['target'])?.coerceText(),
      );
      final inputType = _nonEmpty(
        _mapValueAny(actionMap, const [
          'input_type',
          'inputType',
        ])?.coerceText(),
      );
      final inputPrompt = _nonEmpty(
        _mapValueAny(actionMap, const [
          'input_prompt',
          'inputPrompt',
        ])?.coerceText(),
      );
      final inputPlaceholder = _nonEmpty(
        _mapValueAny(
          actionMap,
          const ['input_placeholder', 'inputPlaceholder'],
        )?.coerceText(),
      );
      final resultMode = _nonEmpty(
        _mapValueAny(actionMap, const [
          'result_mode',
          'resultMode',
        ])?.coerceText(),
      );
      final panelTarget = _nonEmpty(
        _mapValueAny(actionMap, const [
          'panel_target',
          'panelTarget',
        ])?.coerceText(),
      );
      final panelId = _nonEmpty(
        _mapValueAny(actionMap, const ['panel_id', 'panelId'])?.coerceText(),
      );
      final panelTitle = _nonEmpty(
        _mapValueAny(actionMap, const [
          'panel_title',
          'panelTitle',
        ])?.coerceText(),
      );

      final args = <String>[];
      final argsList = _mapValueAny(actionMap, const ['args'])?.asList();
      if (argsList != null) {
        for (final arg in argsList.elements) {
          final text = arg.coerceText();
          if (text.isNotEmpty) {
            args.add(text);
          }
        }
      }

      actions.add(
        InspectAction(
          label: label,
          kind: kind,
          command: command,
          verb: verb,
          target: target,
          args: args,
          inputType: inputType,
          inputPrompt: inputPrompt,
          inputPlaceholder: inputPlaceholder,
          resultMode: resultMode,
          panelTarget: panelTarget,
          panelId: panelId,
          panelTitle: panelTitle,
        ),
      );
    }
  }

  return InspectData(
    title: title,
    description: description,
    actions: actions,
  );
}

MoorVar? _mapValue(MoorMap map, String key) {
  return map.pairs[MoorVar(MoorSym(key))] ?? map.pairs[MoorVar(key)];
}

MoorVar? _mapValueAny(MoorMap map, List<String> keys) {
  for (final k in keys) {
    final v = _mapValue(map, k);
    if (v != null) {
      return v;
    }
  }
  return null;
}

String? _nonEmpty(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value;
}
