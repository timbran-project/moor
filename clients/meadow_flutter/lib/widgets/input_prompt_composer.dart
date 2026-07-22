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
import 'package:flutter/services.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';

class InputPromptComposer extends StatelessWidget {
  final InputPromptRequest request;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool monospaceNarrative;
  final LinkTapHandler? onLinkTap;
  final ValueChanged<String> onSubmit;

  const InputPromptComposer({
    super.key,
    required this.request,
    required this.controller,
    required this.focusNode,
    required this.monospaceNarrative,
    required this.onLinkTap,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final md = request.metadata;
    final type = md.inputType ?? 'text';
    final promptText = (md.prompt?.trim().isNotEmpty ?? false)
        ? md.prompt!.trim()
        : 'Input required';
    final cs = Theme.of(context).colorScheme;
    final promptBorder = Color.lerp(cs.error, Colors.amber, 0.45) ?? cs.error;
    final promptSurface =
        Color.lerp(cs.errorContainer, cs.surfaceContainerHighest, 0.72) ??
        cs.surfaceContainerHighest;

    Widget promptHeader() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ContentRenderer(
          content: [promptText],
          contentType: 'text/plain',
          isStale: false,
          onLinkTap: onLinkTap,
          monospace: monospaceNarrative,
        ),
      );
    }

    Widget body;
    if (type == 'yes_no') {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          promptHeader(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                autofocus: true,
                onPressed: () => onSubmit('yes'),
                child: const Text('Yes'),
              ),
              FilledButton.tonal(
                onPressed: () => onSubmit('no'),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => onSubmit('@abort'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    } else if (type == 'confirmation') {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          promptHeader(),
          FilledButton(
            autofocus: true,
            onPressed: () => onSubmit('ok'),
            child: const Text('OK'),
          ),
        ],
      );
    } else if (type == 'choice' && md.choices.isNotEmpty) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          promptHeader(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in md.choices)
                FilledButton.tonal(
                  autofocus: choice == md.choices.first,
                  onPressed: () => onSubmit(choice),
                  child: Text(choice),
                ),
              TextButton(
                onPressed: () => onSubmit('@abort'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    } else {
      final isMultiline = type == 'text_area';
      final isAlt =
          type == 'yes_no_alternative' || type == 'yes_no_alternative_all';

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          promptHeader(),
          if (isAlt) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  autofocus: true,
                  onPressed: () => onSubmit('yes'),
                  child: const Text('Yes'),
                ),
                FilledButton.tonal(
                  onPressed: () => onSubmit('no'),
                  child: const Text('No'),
                ),
                if (type == 'yes_no_alternative_all')
                  FilledButton.tonal(
                    onPressed: () => onSubmit('all'),
                    child: const Text('All'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: isMultiline
                      ? TextInputType.multiline
                      : (type == 'number'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text),
                  minLines: isMultiline ? (md.rows ?? 3) : 1,
                  maxLines: isMultiline ? (md.rows ?? 3) : 1,
                  decoration: InputDecoration(
                    labelText: isAlt
                        ? (md.alternativeLabel ?? 'Alternative response')
                        : 'Response',
                    hintText: isAlt
                        ? (md.alternativePlaceholder ?? md.placeholder)
                        : md.placeholder,
                  ),
                  onSubmitted: (_) => onSubmit(controller.text),
                  inputFormatters: type == 'number'
                      ? <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(
                            RegExp('[-0-9.]'),
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => onSubmit(controller.text),
                child: const Text('Submit'),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => onSubmit('@abort'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: promptSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: promptBorder,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: promptBorder.withValues(alpha: 0.22),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: body,
    );
  }
}
