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

class SessionAppBarActions extends StatelessWidget {
  final bool debugPanelVisible;
  final VoidCallback onToggleDebugPanel;
  final VoidCallback onShowSettings;
  final VoidCallback onShowAccount;

  const SessionAppBarActions({
    super.key,
    required this.debugPanelVisible,
    required this.onToggleDebugPanel,
    required this.onShowSettings,
    required this.onShowAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onToggleDebugPanel,
          tooltip: debugPanelVisible ? 'Hide debug panel' : 'Show debug panel',
          icon: Icon(
            debugPanelVisible ? Icons.bug_report : Icons.bug_report_outlined,
          ),
        ),
        IconButton(
          onPressed: onShowAccount,
          tooltip: 'Account',
          icon: const Icon(Icons.account_circle_outlined),
        ),
        IconButton(
          onPressed: onShowSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}
