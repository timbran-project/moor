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
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/inspect.dart';

enum HistoryEncryptionAction {
  setup,
  unlock,
  forget,
}

String buildHistoryEncryptionStatusText({
  required String playerOid,
  required bool backendHasPubkey,
  required bool hasLocalKey,
}) {
  return 'player: $playerOid\n'
      'backend pubkey: ${backendHasPubkey ? "yes" : "no"}\n'
      'local key: ${hasLocalKey ? "yes" : "no"}';
}

Future<HistoryEncryptionAction?> showHistoryEncryptionDialog(
  BuildContext context, {
  required String playerOid,
  required bool backendHasPubkey,
  required bool hasLocalKey,
}) {
  return showDialog<HistoryEncryptionAction>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('History Encryption'),
        content: SelectableText(
          buildHistoryEncryptionStatusText(
            playerOid: playerOid,
            backendHasPubkey: backendHasPubkey,
            hasLocalKey: hasLocalKey,
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          if (!backendHasPubkey)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(HistoryEncryptionAction.setup);
              },
              child: const Text('Setup'),
            ),
          if (backendHasPubkey && !hasLocalKey)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(HistoryEncryptionAction.unlock);
              },
              child: const Text('Unlock'),
            ),
          if (hasLocalKey)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(HistoryEncryptionAction.forget);
              },
              child: const Text('Forget Local Key'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<String?> showTextPromptDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? labelText,
  String? hintText,
  bool obscureText = false,
}) async {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  try {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            obscureText: obscureText,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
            ),
            onSubmitted: (_) {
              final text = controller.text.trim();
              Navigator.of(context).pop(text.isEmpty ? null : text);
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                Navigator.of(context).pop(text.isEmpty ? null : text);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
    focusNode.dispose();
  }
}

Future<void> showInspectSheet(
  BuildContext context, {
  required InspectData data,
  required bool monospaceNarrative,
  required Future<void> Function(InspectAction action) onRunAction,
  required Future<void> Function(String url) onLinkTap,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (data.description.trim().isNotEmpty)
                  ContentRenderer(
                    content: [data.description],
                    contentType: 'text/plain',
                    isStale: false,
                    onLinkTap: onLinkTap,
                    monospace: monospaceNarrative,
                  ),
                if (data.actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in data.actions)
                        FilledButton.tonal(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            await onRunAction(action);
                          },
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
