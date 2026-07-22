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
import 'package:meadow_flutter/moor/account_profile_controller.dart';
import 'package:meadow_flutter/moor/history_encryption_controller.dart';
import 'package:meadow_flutter/moor/history_export_controller.dart';

class AccountSheet extends StatelessWidget {
  final String playerCurie;
  final AccountProfileController profileController;
  final HistoryEncryptionController historyEncryptionController;
  final HistoryExportController historyExportController;
  final VoidCallback onPickProfilePicture;
  final VoidCallback onEditDescription;
  final ValueChanged<String> onPronounsChanged;
  final VoidCallback onSetupEncryption;
  final VoidCallback onUnlockEncryption;
  final VoidCallback onForgetLocalKey;
  final VoidCallback onExportHistory;
  final VoidCallback onDeleteHistory;
  final VoidCallback onLogout;

  const AccountSheet({
    super.key,
    required this.playerCurie,
    required this.profileController,
    required this.historyEncryptionController,
    required this.historyExportController,
    required this.onPickProfilePicture,
    required this.onEditDescription,
    required this.onPronounsChanged,
    required this.onSetupEncryption,
    required this.onUnlockEncryption,
    required this.onForgetLocalKey,
    required this.onExportHistory,
    required this.onDeleteHistory,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        profileController,
        historyEncryptionController,
        historyExportController,
      ]),
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final backendHasPubkey = historyEncryptionController.backendHasPubkey;
        final hasLocalKey = historyEncryptionController.hasLocalKey;
        final profileBusy =
            profileController.loading || profileController.saving;
        final exportBusy = historyExportController.exporting;

        return SafeArea(
          child: Semantics(
            container: true,
            label: 'Account panel',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Account',
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      playerCurie,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AccountSection(
                      title: 'Profile Picture',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: _ProfileImagePreview(
                              picture: profileController.profilePicture,
                              loading:
                                  profileController.loading &&
                                  !profileController.loaded,
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: profileBusy
                                ? null
                                : onPickProfilePicture,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              profileController.profilePicture == null
                                  ? 'Upload Picture'
                                  : 'Change Picture',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AccountSection(
                      title: 'Description',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                            child: Text(
                              (profileController.playerDescription
                                          ?.trim()
                                          .isNotEmpty ??
                                      false)
                                  ? profileController.playerDescription!
                                  : 'No description set',
                              style: textTheme.bodyMedium?.copyWith(
                                color:
                                    (profileController.playerDescription
                                            ?.trim()
                                            .isNotEmpty ??
                                        false)
                                    ? null
                                    : colorScheme.outline,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            onPressed: profileBusy ? null : onEditDescription,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(
                              (profileController.playerDescription
                                          ?.trim()
                                          .isNotEmpty ??
                                      false)
                                  ? 'Edit Description'
                                  : 'Add Description',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (profileController.pronounsAvailable) ...[
                      const SizedBox(height: 12),
                      _AccountSection(
                        title: 'Pronouns',
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              profileController.currentPronouns ??
                              (profileController.availablePronounPresets.isEmpty
                                  ? null
                                  : profileController
                                        .availablePronounPresets
                                        .first),
                          decoration: const InputDecoration(
                            labelText: 'Select pronouns',
                          ),
                          items: [
                            for (final preset
                                in profileController.availablePronounPresets)
                              DropdownMenuItem<String>(
                                value: preset,
                                child: Text(preset),
                              ),
                          ],
                          onChanged: profileBusy
                              ? null
                              : (value) {
                                  if (value == null || value.isEmpty) {
                                    return;
                                  }
                                  onPronounsChanged(value);
                                },
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AccountSection(
                      title: 'Security',
                      trailing: _StatusChip(
                        label: backendHasPubkey
                            ? (hasLocalKey ? 'Unlocked' : 'Locked')
                            : 'Not Set Up',
                        color: backendHasPubkey && hasLocalKey
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            backendHasPubkey
                                ? (hasLocalKey
                                      ? 'History encryption is enabled and this device has the saved key.'
                                      : 'History encryption is enabled, but this device needs your password to unlock it.')
                                : 'History encryption is not set up yet.',
                            style: textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (!backendHasPubkey)
                                FilledButton.icon(
                                  onPressed: onSetupEncryption,
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Set Up Encryption'),
                                ),
                              if (backendHasPubkey && !hasLocalKey)
                                FilledButton.icon(
                                  onPressed: onUnlockEncryption,
                                  icon: const Icon(Icons.key_outlined),
                                  label: const Text('Unlock History'),
                                ),
                              if (hasLocalKey)
                                TextButton.icon(
                                  onPressed: onForgetLocalKey,
                                  icon: const Icon(Icons.key_off_outlined),
                                  label: const Text('Remove Saved Password'),
                                ),
                            ],
                          ),
                          if (backendHasPubkey) ...[
                            const SizedBox(height: 16),
                            Text(
                              'History Management',
                              style: textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            if (exportBusy) ...[
                              LinearProgressIndicator(
                                value:
                                    historyExportController.total == null ||
                                        historyExportController.total == 0
                                    ? null
                                    : historyExportController.processed /
                                          historyExportController.total!,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                historyExportController.total == null
                                    ? 'Preparing export...'
                                    : 'Exporting history ${historyExportController.processed} / ${historyExportController.total}',
                                style: textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: hasLocalKey && !exportBusy
                                      ? onExportHistory
                                      : null,
                                  icon: const Icon(Icons.download_outlined),
                                  label: const Text('Download All History'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: exportBusy
                                      ? null
                                      : onDeleteHistory,
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete All History'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _AccountSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: title,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileImagePreview extends StatelessWidget {
  final ProfilePictureData? picture;
  final bool loading;

  const _ProfileImagePreview({
    required this.picture,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const size = 128.0;
    if (loading) {
      return const SizedBox(
        width: size,
        height: size,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: picture == null
          ? Icon(
              Icons.account_circle_outlined,
              size: 72,
              color: colorScheme.outline,
            )
          : Image.memory(
              picture!.data,
              fit: BoxFit.cover,
              semanticLabel: 'Profile picture',
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
