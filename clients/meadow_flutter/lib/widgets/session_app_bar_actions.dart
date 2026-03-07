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

enum SessionAccountAction {
  historyEncryption,
  logout,
}

class SessionAppBarActions extends StatelessWidget {
  final bool debugPanelVisible;
  final String playerCurie;
  final VoidCallback onToggleDebugPanel;
  final VoidCallback onShowSettings;
  final ValueChanged<SessionAccountAction> onSelectAccountAction;

  const SessionAppBarActions({
    super.key,
    required this.debugPanelVisible,
    required this.playerCurie,
    required this.onToggleDebugPanel,
    required this.onShowSettings,
    required this.onSelectAccountAction,
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
          onPressed: onShowSettings,
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined),
        ),
        PopupMenuButton<SessionAccountAction>(
          tooltip: 'Account',
          icon: const Icon(Icons.account_circle_outlined),
          onSelected: onSelectAccountAction,
          itemBuilder: (context) {
            return [
              PopupMenuItem<SessionAccountAction>(
                enabled: false,
                child: Text(
                  playerCurie,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<SessionAccountAction>(
                value: SessionAccountAction.historyEncryption,
                child: Text('History encryption'),
              ),
              const PopupMenuItem<SessionAccountAction>(
                value: SessionAccountAction.logout,
                child: Text('Logout'),
              ),
            ];
          },
        ),
      ],
    );
  }
}
