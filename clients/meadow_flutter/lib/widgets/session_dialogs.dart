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
import 'dart:ui' as ui;

import 'package:crop_image/crop_image.dart';
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
          style: const TextStyle(fontFamily: 'Comic Mono'),
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
  String? initialValue,
  bool obscureText = false,
  int minLines = 1,
  int maxLines = 1,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final focusNode = FocusNode();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            obscureText: obscureText,
            minLines: minLines,
            maxLines: maxLines,
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

Future<Uint8List?> showProfilePictureCropDialog(
  BuildContext context, {
  required Uint8List imageBytes,
}) async {
  final controller = CropController(
    aspectRatio: 1,
    defaultCrop: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
  );
  try {
    return await showDialog<Uint8List>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Crop Profile Picture'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CropImage(
                      controller: controller,
                      image: Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                      ),
                      paddingSize: 24,
                      alwaysMove: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Drag to position and use the handles to crop a square thumbnail.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final bitmap = await controller.croppedBitmap();
                final resized = await _resizeImageToSquarePng(
                  bitmap,
                  maxDimension: 512,
                );
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop(resized);
              },
              child: const Text('Use Picture'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<Uint8List?> _resizeImageToSquarePng(
  ui.Image image, {
  required int maxDimension,
}) async {
  final width = image.width;
  final height = image.height;
  final longestSide = width > height ? width : height;
  final scale = longestSide <= maxDimension ? 1.0 : maxDimension / longestSide;
  final targetWidth = (width * scale).round().clamp(1, maxDimension);
  final targetHeight = (height * scale).round().clamp(1, maxDimension);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
    paint,
  );
  final picture = recorder.endRecording();
  final resized = await picture.toImage(targetWidth, targetHeight);
  final data = await resized.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
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

class ExternalLinkDecision {
  final bool trustDomain;

  const ExternalLinkDecision({
    required this.trustDomain,
  });
}

Future<ExternalLinkDecision?> showExternalLinkDialog(
  BuildContext context, {
  required String url,
}) {
  var trustDomain = false;
  final uri = Uri.tryParse(url);
  final protocol = (uri?.scheme.isNotEmpty ?? false) ? '${uri!.scheme}://' : '';
  final hostname = uri?.host ?? url;
  final path = uri == null
      ? ''
      : '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}${uri.hasFragment ? '#${uri.fragment}' : ''}';

  return showDialog<ExternalLinkDecision>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('External Link'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: protocol,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      TextSpan(
                        text: hostname,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: path,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This link will take you to an external website. Make sure you trust this destination before proceeding.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: trustDomain,
                  onChanged: (value) {
                    setState(() {
                      trustDomain = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text("Don't ask again for $hostname"),
                ),
              ],
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
                  Navigator.of(context).pop(
                    ExternalLinkDecision(trustDomain: trustDomain),
                  );
                },
                child: const Text('Visit Site'),
              ),
            ],
          );
        },
      );
    },
  );
}
