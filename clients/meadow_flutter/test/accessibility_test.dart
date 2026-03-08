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

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/main.dart';
import 'package:meadow_flutter/moor/account_profile_controller.dart';
import 'package:meadow_flutter/moor/args.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/history_encryption_controller.dart';
import 'package:meadow_flutter/moor/history_export_controller.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/link_preview.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_metadata.dart';
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/room_snapshot.dart';
import 'package:meadow_flutter/moor/session_view_controller.dart';
import 'package:meadow_flutter/widgets/account_sheet.dart';
import 'package:meadow_flutter/widgets/command_controller.dart';
import 'package:meadow_flutter/widgets/input_prompt_composer.dart';
import 'package:meadow_flutter/widgets/room_snapshot_widget.dart';
import 'package:meadow_flutter/widgets/session_app_bar_actions.dart';
import 'package:meadow_flutter/widgets/session_command_input_bar.dart';
import 'package:meadow_flutter/widgets/session_dialogs.dart';
import 'package:meadow_flutter/widgets/session_dock_item_card.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_narrative_list.dart';
import 'package:meadow_flutter/widgets/session_settings_sheet.dart';

void main() {
  group('Accessibility', () {
    testWidgets('login screen exposes labeled form controls', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MeadowApp(launchArgs: parseLaunchArgs(const [])),
        );
        await tester.pump();

        expect(find.byTooltip('Reload welcome'), findsOneWidget);
        expect(find.text('Sign In'), findsWidgets);
        expect(find.text('Create Account'), findsOneWidget);

        _expectLabeledTextField(
          tester.getSemantics(find.byType(EditableText).at(0)),
          'Web Host Base URL',
        );
        _expectLabeledTextField(
          tester.getSemantics(find.byType(EditableText).at(1)),
          'Username',
        );
        _expectLabeledTextField(
          tester.getSemantics(find.byType(EditableText).at(2)),
          'Password',
        );
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(FilledButton, 'Sign In')),
          'Sign In',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('session command bar exposes command field and send button', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = CommandEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      try {
        await tester.pumpWidget(
          _wrap(
            child: SessionCommandInputBar(
              controller: controller,
              focusNode: focusNode,
              verbPill: null,
              verbPillPlaceholder: null,
              serverPlaceholderText: 'Try "look"',
              onSend: () {},
            ),
          ),
        );

        _expectLabeledTextField(
          tester.getSemantics(find.byType(EditableText)),
          'Command',
        );
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(FilledButton, 'Send')),
          'Send',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('input prompt composer exposes prompt controls accessibly', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = TextEditingController(text: 'hello');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      try {
        await tester.pumpWidget(
          _wrap(
            child: InputPromptComposer(
              request: const InputPromptRequest(
                requestId: 'prompt-1',
                metadata: InputPromptMetadata(
                  inputType: 'yes_no_alternative_all',
                  prompt: 'Choose an answer',
                  ttsPrompt: null,
                  choices: <String>[],
                  min: null,
                  max: null,
                  defaultValue: 'hello',
                  placeholder: 'Alternative',
                  rows: null,
                  alternativeLabel: 'Alternative response',
                  alternativePlaceholder: 'Type something else',
                  acceptContentTypes: <String>[],
                  maxFileSize: null,
                ),
              ),
              controller: controller,
              focusNode: focusNode,
              monospaceNarrative: false,
              onLinkTap: null,
              onSubmit: (_) {},
            ),
          ),
        );

        for (final label in <String>[
          'Yes',
          'No',
          'All',
          'Alternative response',
          'Submit',
          'Cancel',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        _expectTextFieldSemantics(
          tester.getSemantics(find.byType(EditableText).first),
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('session app bar actions expose accessible controls and menu', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: SessionAppBarActions(
              debugPanelVisible: false,
              onToggleDebugPanel: () {},
              onShowAccount: () {},
              onShowSettings: () {},
            ),
          ),
        );

        expect(find.byTooltip('Show debug panel'), findsOneWidget);
        expect(find.byTooltip('Account'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('account sheet exposes profile and encryption controls', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        final profileController = AccountProfileController(
          api: MoorHttpApi(Uri(scheme: 'http', host: 'localhost')),
        );
        final encryptionController = HistoryEncryptionController(
          getLocalIdentity: (_) async => null,
          setLocalIdentity:
              ({required playerOid, required ageIdentity}) async {},
          removeLocalIdentity: (_) async {},
          getBackendPubkey: ({required authToken}) async => null,
          setBackendPubkey: ({required authToken, required publicKey}) async {},
          deriveKeyBytes: ({required password, required identifier}) async =>
              Uint8List(0),
          identityFromDerivedBytes: (_) => '',
          publicKeyFromDerivedBytes: (_) async => '',
        );
        final exportController = HistoryExportController();
        addTearDown(profileController.dispose);
        addTearDown(encryptionController.dispose);
        addTearDown(exportController.dispose);

        await tester.pumpWidget(
          _wrap(
            child: AccountSheet(
              playerCurie: 'oid:1',
              profileController: profileController,
              historyEncryptionController: encryptionController,
              historyExportController: exportController,
              onPickProfilePicture: () {},
              onEditDescription: () {},
              onPronounsChanged: (_) {},
              onSetupEncryption: () {},
              onUnlockEncryption: () {},
              onForgetLocalKey: () {},
              onExportHistory: () {},
              onDeleteHistory: () {},
              onLogout: () {},
            ),
          ),
        );

        expect(find.text('Account'), findsOneWidget);
        expect(find.text('Profile Picture'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Security'), findsOneWidget);
        expect(find.text('Upload Picture'), findsOneWidget);
        expect(find.text('Add Description'), findsOneWidget);
        expect(find.text('Set Up Encryption'), findsOneWidget);
        expect(find.text('Logout'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('settings sheet exposes all toggles and theme choices', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: SessionSettingsSheet(
              initialSettings: const SessionViewSettings(
                roomHudEnabled: true,
                showNarrativeMeta: false,
                verbPaletteEnabled: true,
                monospaceNarrative: false,
                verbSuggestionsAvailable: true,
                themeMode: ThemeMode.dark,
              ),
              onSettingsChanged: (_) {},
              onThemeModeChanged: (_) {},
            ),
          ),
        );

        for (final label in <String>[
          'Room HUD',
          'Timestamps',
          'Monospace output',
          'Verb palette',
          'Light',
          'Dark',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.byType(SwitchListTile), findsNWidgets(4));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('narrative inset groups expose semantic container labels', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      final scrollController = ScrollController();
      final messageKeys = <String, GlobalKey>{};
      addTearDown(scrollController.dispose);

      try {
        await tester.pumpWidget(
          _wrap(
            child: SizedBox(
              height: 300,
              child: SessionNarrativeList(
                items: <NarrativeItem>[
                  NarrativeItem(
                    id: '1',
                    timestamp: DateTime.parse('2026-03-07T12:00:00Z'),
                    content: const <String>['An inset message'],
                    contentType: 'text/plain',
                    noNewline: false,
                    presentationHint: 'inset',
                    groupId: 'room-1',
                    metadata: null,
                  ),
                  NarrativeItem(
                    id: '2',
                    timestamp: DateTime.parse('2026-03-07T12:00:01Z'),
                    content: const <String>['Continues the inset'],
                    contentType: 'text/plain',
                    noNewline: false,
                    presentationHint: 'inset',
                    groupId: 'room-1',
                    metadata: null,
                  ),
                ],
                monospaceNarrative: false,
                showNarrativeMeta: false,
                playerCurie: 'oid:1',
                scrollController: scrollController,
                listKey: GlobalKey(),
                messageKeys: messageKeys,
                onLinkTap: null,
              ),
            ),
          ),
        );

        expect(find.bySemanticsLabel('Inset'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('history encryption dialog exposes status and actions', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: Builder(
              builder: (context) {
                return FilledButton(
                  onPressed: () {
                    showHistoryEncryptionDialog(
                      context,
                      playerOid: 'oid:1',
                      backendHasPubkey: false,
                      hasLocalKey: false,
                    );
                  },
                  child: const Text('Open dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();

        expect(find.text('History Encryption'), findsOneWidget);
        expect(find.textContaining('player: oid:1'), findsOneWidget);
        expect(find.textContaining('backend pubkey: no'), findsOneWidget);
        expect(find.textContaining('local key: no'), findsOneWidget);
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(FilledButton, 'Setup')),
          'Setup',
        );
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(TextButton, 'Close')),
          'Close',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'inspect sheet exposes title, description, and action buttons',
      (
        WidgetTester tester,
      ) async {
        final handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _wrap(
              child: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () {
                      showInspectSheet(
                        context,
                        data: const InspectData(
                          title: 'Ancient Door',
                          description: 'A heavy oak door with iron bands.',
                          actions: <InspectAction>[
                            InspectAction(
                              label: 'Open',
                              kind: 'command',
                              command: 'open door',
                              verb: null,
                              target: null,
                              args: <String>[],
                              inputType: null,
                              inputPrompt: null,
                              inputPlaceholder: null,
                              resultMode: null,
                              panelTarget: null,
                              panelId: null,
                              panelTitle: null,
                            ),
                            InspectAction(
                              label: 'Knock',
                              kind: 'command',
                              command: 'knock door',
                              verb: null,
                              target: null,
                              args: <String>[],
                              inputType: null,
                              inputPrompt: null,
                              inputPlaceholder: null,
                              resultMode: null,
                              panelTarget: null,
                              panelId: null,
                              panelTitle: null,
                            ),
                          ],
                        ),
                        monospaceNarrative: false,
                        onRunAction: (_) async {},
                        onLinkTap: (_) async {},
                      );
                    },
                    child: const Text('Open inspect'),
                  );
                },
              ),
            ),
          );

          await tester.tap(find.text('Open inspect'));
          await tester.pumpAndSettle();

          expect(find.text('Ancient Door'), findsOneWidget);
          expect(
            find.text('A heavy oak door with iron bands.'),
            findsOneWidget,
          );
          _expectButtonSemantics(
            tester.getSemantics(find.widgetWithText(FilledButton, 'Open')),
            'Open',
          );
          _expectButtonSemantics(
            tester.getSemantics(find.widgetWithText(FilledButton, 'Knock')),
            'Knock',
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('editor dock exposes tabs and window controls accessibly', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: SizedBox(
              height: 240,
              child: SessionEditorDock(
                sessions: const <EditorSession>[
                  VerbEditorSession(
                    id: 'verb-1',
                    title: 'Edit look_self',
                    presentationId: 'edit-1',
                    objectCurie: 'oid:1',
                    verbName: 'look_self',
                  ),
                  PropertyEditorSession(
                    id: 'prop-1',
                    title: 'Edit name',
                    presentationId: 'edit-2',
                    objectCurie: 'oid:1',
                    propertyName: 'name',
                    isValueEditor: false,
                  ),
                ],
                activeIndex: 0,
                onSelectIndex: (_) {},
                onCloseSession: (_) async {},
                onOpenFullscreen: (_) async {},
                paneBuilder: (session) => Center(child: Text(session.title)),
              ),
            ),
          ),
        );

        expect(
          tester.getSemantics(find.byType(SessionEditorDock)).label,
          contains('Editor dock'),
        );
        expect(find.text('Edit look_self'), findsNWidgets(2));
        expect(find.text('Edit name'), findsOneWidget);
        expect(find.byTooltip('Fullscreen'), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('room snapshot exposes inspect and action controls', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: SessionDockItemCard(
              item: RoomSnapshotDockItem(
                id: 'room-look',
                target: 'top',
                attrs: const <String, String>{},
                snapshot: RoomSnapshot(
                  title: 'Town Square',
                  description: 'A busy plaza.',
                  room: ObjectRef.fromCurie('oid:10'),
                  exits: const <String>['north'],
                  actions: const <RoomSnapshotAction>[
                    RoomSnapshotAction(label: 'Wave', command: 'wave'),
                  ],
                  things: <RoomSnapshotThing>[
                    RoomSnapshotThing(
                      name: 'Lantern',
                      object: ObjectRef.fromCurie('oid:11')!,
                    ),
                  ],
                  actors: <RoomSnapshotActor>[
                    RoomSnapshotActor(
                      name: 'Guide',
                      status: 'awake',
                      object: ObjectRef.fromCurie('oid:12')!,
                    ),
                  ],
                ),
              ),
              monospaceNarrative: false,
              onDismissPresentation: (_) async {},
              onInspect: (_) async {},
              onSendCommand: (_) {},
              onLinkTap: null,
            ),
          ),
        );

        expect(
          tester.getSemantics(find.byType(RoomSnapshotWidget)).label,
          contains('Room snapshot: Town Square'),
        );
        expect(find.text('Town Square'), findsOneWidget);
        expect(find.byTooltip('Inspect room'), findsOneWidget);
        expect(find.text('Exits'), findsOneWidget);
        expect(find.text('Things'), findsOneWidget);
        expect(find.text('Players'), findsOneWidget);
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(FilledButton, 'north')),
          'north',
        );
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(FilledButton, 'Wave')),
          'Wave',
        );
        _expectButtonSemantics(
          tester.getSemantics(find.widgetWithText(OutlinedButton, 'Lantern')),
          'Lantern',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('presentation panels expose close controls and content', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _wrap(
            child: SessionDockItemCard(
              item: const PresentationModel(
                id: 'debug-panel',
                target: 'right',
                contentType: 'text/plain',
                content: 'Recent debug output',
                attrs: <String, String>{
                  'title': 'Debug panel',
                  'kind': 'debug_output',
                },
              ),
              monospaceNarrative: false,
              onDismissPresentation: (_) async {},
              onInspect: (_) async {},
              onSendCommand: (_) {},
              onLinkTap: null,
            ),
          ),
        );

        expect(find.text('Debug panel'), findsOneWidget);
        expect(find.text('Recent debug output'), findsOneWidget);
        expect(find.byTooltip('Close panel'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('narrative link previews expose accessible cards', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      final scrollController = ScrollController();
      final messageKeys = <String, GlobalKey>{};
      addTearDown(scrollController.dispose);

      try {
        await tester.pumpWidget(
          _wrap(
            child: SizedBox(
              height: 300,
              child: SessionNarrativeList(
                items: <NarrativeItem>[
                  NarrativeItem(
                    id: 'preview-1',
                    timestamp: DateTime.parse('2026-03-07T12:00:00Z'),
                    content: const <String>['https://example.com/post'],
                    contentType: 'text/x-uri',
                    noNewline: false,
                    presentationHint: null,
                    groupId: null,
                    metadata: const NarrativeMetadata(
                      raw: <String, Object?>{},
                      eventId: 'evt-1',
                      presentationHint: null,
                      groupId: null,
                      actorCurie: null,
                      actorName: null,
                      verb: null,
                      content: null,
                      thumbnail: null,
                      linkPreview: LinkPreviewData(
                        url: 'https://example.com/post',
                        title: 'Example post',
                        description: 'A concise description',
                        image: null,
                        siteName: 'Example',
                      ),
                    ),
                  ),
                ],
                monospaceNarrative: false,
                showNarrativeMeta: false,
                playerCurie: 'oid:1',
                scrollController: scrollController,
                listKey: GlobalKey(),
                messageKeys: messageKeys,
                onLinkTap: null,
              ),
            ),
          ),
        );

        expect(find.text('Example post'), findsOneWidget);
        expect(find.text('A concise description'), findsOneWidget);
        expect(find.text('Example'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Link preview: Example post from Example'),
          findsOneWidget,
        );
      } finally {
        handle.dispose();
      }
    });
  });
}

Widget _wrap({required Widget child}) {
  return MaterialApp(
    home: Scaffold(
      body: child,
    ),
  );
}

void _expectButtonSemantics(SemanticsNode semantics, String label) {
  expect(semantics.label, contains(label));
  expect(semantics.flagsCollection.isButton, isTrue);
}

void _expectLabeledTextField(SemanticsNode semantics, String label) {
  expect(semantics.label, contains(label));
  _expectTextFieldSemantics(semantics);
}

void _expectTextFieldSemantics(SemanticsNode semantics) {
  expect(semantics.flagsCollection.isTextField, isTrue);
}
