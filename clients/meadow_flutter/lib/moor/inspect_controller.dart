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

import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';

typedef InspectVerbInvoker =
    Future<InspectVerbResponse> Function({
      required String objectCurie,
      required String verbName,
      Uint8List? argsVarBytes,
    });

class InspectVerbResponse {
  final MoorVar result;
  final List<String> outputLines;
  final List<int> eventTypes;

  const InspectVerbResponse({
    required this.result,
    required this.outputLines,
    required this.eventTypes,
  });
}

class InspectActionRunResult {
  final bool canceled;
  final String? commandToSend;
  final List<String> narrativeLines;
  final PresentationModel? panelPresentation;

  const InspectActionRunResult({
    required this.canceled,
    required this.commandToSend,
    required this.narrativeLines,
    required this.panelPresentation,
  });

  const InspectActionRunResult.canceled()
    : canceled = true,
      commandToSend = null,
      narrativeLines = const <String>[],
      panelPresentation = null;

  const InspectActionRunResult.noop()
    : canceled = false,
      commandToSend = null,
      narrativeLines = const <String>[],
      panelPresentation = null;
}

class InspectController {
  final InspectVerbInvoker _invokeVerb;
  final String Function(String prefix) _newId;

  const InspectController({
    required InspectVerbInvoker invokeVerb,
    required String Function(String prefix) newId,
  }) : _invokeVerb = invokeVerb,
       _newId = newId;

  Future<InspectData?> loadInspectData(
    String objectCurie, {
    void Function(String message)? onDebug,
  }) async {
    final response = await _invokeVerb(
      objectCurie: objectCurie,
      verbName: 'inspection',
    );
    final inspectData = parseInspectData(response.result);
    if (inspectData == null) {
      return null;
    }
    for (final action in inspectData.actions) {
      onDebug?.call(
        '[inspect] action metadata: ${describeInspectAction(action)}',
      );
    }
    return inspectData;
  }

  Future<InspectActionRunResult> runAction(
    InspectAction action, {
    required Future<String?> Function(InspectAction action) promptForInput,
    void Function(String message)? onDebug,
  }) async {
    onDebug?.call('[inspect] run action: ${describeInspectAction(action)}');

    String? inputValue;
    if (action.inputType == 'text') {
      inputValue = await promptForInput(action);
      if (inputValue == null) {
        onDebug?.call('[inspect] action canceled: ${action.label}');
        return const InspectActionRunResult.canceled();
      }
    }

    if (action.kind == 'command' || action.command != null) {
      var command = action.command ?? '';
      if (inputValue != null) {
        command = command.contains('{input}')
            ? command.replaceAll('{input}', inputValue)
            : '$command $inputValue'.trim();
      }
      if (command.trim().isEmpty) {
        return const InspectActionRunResult.noop();
      }
      onDebug?.call(
        '[inspect] sending command action over websocket: $command',
      );
      return InspectActionRunResult(
        canceled: false,
        commandToSend: command,
        narrativeLines: const <String>[],
        panelPresentation: null,
      );
    }

    final verb = action.verb;
    final target = action.target;
    if (verb == null || target == null) {
      return const InspectActionRunResult.noop();
    }

    final args = <String>[...action.args];
    if (inputValue != null) {
      args.add(inputValue);
    }
    final response = await _invokeVerb(
      objectCurie: target,
      verbName: verb,
      argsVarBytes: buildInspectInvokeArgs(args),
    );
    onDebug?.call(
      '[inspect] invoke completed: '
      'resultPresent=${!response.result.isNone()} '
      'outputEvents=${response.eventTypes.length} '
      'eventTypes=${response.eventTypes}',
    );

    final outputLines = response.outputLines;
    if (action.resultMode == 'panel' && outputLines.isNotEmpty) {
      final panelTarget = mapInspectPanelTarget(action.panelTarget);
      final panelId = action.panelId ?? _newId('inspect-action-');
      final panelTitle = action.panelTitle ?? action.label;
      onDebug?.call(
        '[inspect] routing action output to panel: '
        'target=$panelTarget id=$panelId title=$panelTitle '
        'lines=${outputLines.length}',
      );
      return InspectActionRunResult(
        canceled: false,
        commandToSend: null,
        narrativeLines: const <String>[],
        panelPresentation: PresentationModel(
          id: panelId,
          target: panelTarget,
          contentType: 'text/plain',
          content: outputLines.join('\n'),
          attrs: <String, String>{
            'title': panelTitle,
            'kind': 'action_output',
            'source': 'inspect_action',
          },
        ),
      );
    }

    if (action.resultMode == 'panel' && outputLines.isEmpty) {
      onDebug?.call('[inspect] panel requested but invoke output had no lines');
    }

    return InspectActionRunResult(
      canceled: false,
      commandToSend: null,
      narrativeLines: outputLines.isNotEmpty
          ? outputLines
          : <String>['Action ran: ${action.label}'],
      panelPresentation: null,
    );
  }
}

String describeInspectAction(InspectAction action) {
  return 'label=${action.label} '
      'kind=${action.kind ?? "-"} '
      'command=${action.command ?? "-"} '
      'verb=${action.verb ?? "-"} '
      'target=${action.target ?? "-"} '
      'args=${action.args} '
      'inputType=${action.inputType ?? "-"} '
      'inputPrompt=${action.inputPrompt ?? "-"} '
      'inputPlaceholder=${action.inputPlaceholder ?? "-"} '
      'resultMode=${action.resultMode ?? "-"} '
      'panelTarget=${action.panelTarget ?? "-"} '
      'panelId=${action.panelId ?? "-"} '
      'panelTitle=${action.panelTitle ?? "-"}';
}

String mapInspectPanelTarget(String? target) {
  final normalized = (target ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'top':
    case 'left':
    case 'right':
    case 'bottom':
      return normalized;
    case 'tools':
    case 'status':
    case 'inventory':
    case 'navigation':
    case 'communication':
    case 'help':
      return 'top';
    default:
      return 'top';
  }
}

Uint8List? buildInspectInvokeArgs(List<String> args) {
  if (args.isEmpty) {
    return null;
  }
  final packed = <MoorVar>[];
  for (final arg in args) {
    final ref = ObjectRef.fromCurie(arg);
    if (ref != null) {
      packed.add(MoorVar(ref.obj));
    } else {
      packed.add(MoorVar(arg));
    }
  }
  return Uint8List.fromList(MoorList(packed).toVar().toBytes());
}
