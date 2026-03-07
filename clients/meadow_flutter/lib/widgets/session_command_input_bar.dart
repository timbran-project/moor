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
import 'package:meadow_flutter/widgets/command_controller.dart';

class SessionCommandInputBar extends StatelessWidget {
  final CommandEditingController controller;
  final FocusNode focusNode;
  final String? verbPill;
  final String? verbPillPlaceholder;
  final String? serverPlaceholderText;
  final VoidCallback onSend;

  const SessionCommandInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.verbPill,
    required this.verbPillPlaceholder,
    required this.serverPlaceholderText,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: TextField(
              controller: controller,
              autofocus: true,
              focusNode: focusNode,
              keyboardType: TextInputType.multiline,
              minLines: 1,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Command',
                hintText: verbPill != null
                    ? verbPillPlaceholder
                    : serverPlaceholderText,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FocusTraversalOrder(
          order: const NumericFocusOrder(4),
          child: FilledButton(
            onPressed: onSend,
            child: const Text('Send'),
          ),
        ),
      ],
    );
  }
}
