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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/age_decrypt.dart';
import 'package:meadow_flutter/moor/args.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/event_log_encryption.dart';
import 'package:meadow_flutter/moor/event_log_keystore.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_metadata.dart';
import 'package:meadow_flutter/moor/object_ref.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/types/moor_coll.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';
import 'package:meadow_flutter/moor/ws_client.dart';
import 'package:meadow_flutter/theme/app_theme.dart';
import 'package:meadow_flutter/widgets/command_controller.dart';
import 'package:meadow_flutter/widgets/property_editor.dart';
import 'package:meadow_flutter/widgets/room_snapshot_widget.dart';
import 'package:meadow_flutter/widgets/verb_editor.dart';
import 'package:meadow_flutter/widgets/verb_palette_bar.dart';
import 'package:url_launcher/url_launcher.dart';

void main(List<String> args) {
  final launchArgs = parseLaunchArgs(args);
  runApp(MeadowApp(launchArgs: launchArgs));
}

class MeadowApp extends StatefulWidget {
  final LaunchArgs launchArgs;

  const MeadowApp({
    super.key,
    required this.launchArgs,
  });

  @override
  State<MeadowApp> createState() => _MeadowAppState();
}

class _ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;

  ThemeMode get mode => _mode;

  set mode(ThemeMode v) {
    if (v == _mode) return;
    _mode = v;
    notifyListeners();
  }
}

class _ThemeScope extends InheritedNotifier<_ThemeController> {
  const _ThemeScope({
    required super.notifier,
    required super.child,
  });

  static _ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeScope>();
    final ctrl = scope?.notifier;
    if (ctrl == null) {
      throw StateError('Theme scope not found');
    }
    return ctrl;
  }
}

class _MeadowAppState extends State<MeadowApp> {
  final _theme = _ThemeController();

  @override
  Widget build(BuildContext context) {
    return _ThemeScope(
      notifier: _theme,
      child: AnimatedBuilder(
        animation: _theme,
        builder: (context, _) {
          return MaterialApp(
            title: 'Meadow (Flutter Spike)',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _theme.mode,
            home: LoginScreen(launchArgs: widget.launchArgs),
          );
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final LaunchArgs launchArgs;

  const LoginScreen({
    super.key,
    required this.launchArgs,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _baseUrlCtrl = TextEditingController(text: 'http://localhost:8080');
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  String _mode = 'connect';
  String _mooTitle = 'mooR';
  WelcomeMessage? _welcome;
  String? _error;
  bool _loadingWelcome = false;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();

    final a = widget.launchArgs;
    // For web we strongly prefer same-origin (avoid CORS). If you serve this app
    // behind a reverse proxy (e.g. Vite), default to the current origin.
    if (kIsWeb && (a.server == null || a.server!.trim().isEmpty)) {
      _baseUrlCtrl.text = Uri.base.origin;
    }
    if (a.server != null && a.server!.trim().isNotEmpty) {
      _baseUrlCtrl.text = a.server!.trim();
    }
    if (a.username != null) {
      _userCtrl.text = a.username!;
    }
    if (a.password != null) {
      _passCtrl.text = a.password!;
    }
    if (a.mode != null) {
      _mode = a.mode!;
    }

    _loadWelcome();

    if (a.login) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Only auto-login if we have the core fields.
        if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
          return;
        }
        await _login();
      });
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Uri? _parseBaseUri() {
    final raw = _baseUrlCtrl.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    final u = Uri.tryParse(raw);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      return null;
    }
    // Normalize: only keep origin (no path/query/fragment). Using `Uri(...)`
    // avoids producing `?`/`#` suffixes for empty query/fragment, which can
    // later break browser WebSocket URL validation.
    return Uri(
      scheme: u.scheme,
      userInfo: u.userInfo,
      host: u.host,
      port: u.hasPort ? u.port : null,
    );
  }

  Future<void> _loadWelcome() async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _welcome = null;
        _error = 'Invalid base URL';
      });
      return;
    }

    setState(() {
      _loadingWelcome = true;
      _error = null;
    });
    try {
      final api = MoorHttpApi(baseUri);
      String? mooTitle;
      try {
        mooTitle = await api.fetchMooTitle();
      } on Object {
        // Keep default title when moo_title is unavailable.
      }
      final msg = await api.fetchWelcomeMessage();
      if (!mounted) return;
      setState(() {
        if (mooTitle != null && mooTitle.trim().isNotEmpty) {
          _mooTitle = mooTitle.trim();
        }
        _welcome = msg;
        _loadingWelcome = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _welcome = null;
        _loadingWelcome = false;
        _error = '$e';
      });
    }
  }

  Future<void> _login() async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _error = 'Invalid base URL';
      });
      return;
    }

    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() {
        _error = 'Missing username/password';
      });
      return;
    }

    setState(() {
      _loggingIn = true;
      _error = null;
    });

    try {
      final api = MoorHttpApi(baseUri);
      final session = await api.login(
        mode: _mode,
        username: user,
        password: pass,
      );
      if (!mounted) return;
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SessionScreen(
            session: session,
            mode: _mode,
            initialMooTitle: _mooTitle,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loggingIn = false;
        });
      }
    }
  }

  Future<void> _handleWelcomeLinkTap(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final u = Uri.tryParse(url);
      if (u == null) {
        setState(() {
          _error = 'Bad URL: $url';
        });
        return;
      }
      await launchUrl(u, mode: LaunchMode.externalApplication);
      return;
    }
    // Don’t execute moo:// links from the welcome screen in the spike.
    setState(() {
      _error = 'Unhandled link: $url';
    });
  }

  @override
  Widget build(BuildContext context) {
    final welcome = _welcome;

    return Scaffold(
      appBar: AppBar(
        title: Text(_mooTitle),
        actions: [
          IconButton(
            onPressed: _loadingWelcome ? null : _loadWelcome,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload welcome',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Web Host Base URL',
                hintText: 'http://localhost:8080',
              ),
              onSubmitted: (_) => _loadWelcome(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: _loadingWelcome
                      ? const Text(
                          'Loading welcome message...',
                          style: TextStyle(fontFamily: 'monospace'),
                        )
                      : (welcome == null || welcome.lines.isEmpty)
                      ? const Text(
                          '(no welcome message)',
                          style: TextStyle(fontFamily: 'monospace'),
                        )
                      : ContentRenderer(
                          content: welcome.lines,
                          contentType: welcome.contentType,
                          isStale: false,
                          onLinkTap: _handleWelcomeLinkTap,
                          monospace: false,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'connect', label: Text('Connect')),
                ButtonSegment(value: 'create', label: Text('Create')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() {
                  _mode = s.first;
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _loggingIn ? null : _login(),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _loggingIn ? null : _login,
              child: Text(_loggingIn ? 'Logging in...' : 'Login'),
            ),
          ],
        ),
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  final LoginSession session;
  final String mode; // "connect" | "create"
  final String initialMooTitle;

  const SessionScreen({
    super.key,
    required this.session,
    required this.mode,
    required this.initialMooTitle,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _inputCtrl = CommandEditingController();
  final _promptCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final FocusNode _inputFocus = FocusNode(onKeyEvent: _handleCommandKey);
  final _promptFocus = FocusNode();

  final _items = <NarrativeItem>[];
  final _presentations = PresentationStore();
  final GlobalKey _listKey = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  static const String _debugPanelId = 'local-debug-panel';
  final _debugLines = <String>[];
  bool _debugPanelVisible = false;

  String? _currentRoomLookKey;
  String? _currentRoomLookMessageId;
  bool _isCurrentRoomLookDockLatched = false;
  final _latestLookMessageIdByRoom = <String, String>{};

  bool _roomHudEnabled = true;
  bool _showNarrativeMeta = false;
  bool _verbPaletteEnabled = true;
  bool _monospaceNarrative = false;
  bool _speechBubblesEnabled = true;

  double _splitRatio = 0.64;

  final _editorSessions = <EditorSession>[];
  int _activeEditorIndex = 0;
  final Map<String, Widget> _editorPaneCache = <String, Widget>{};

  int _idSeq = 0;
  MoorWsClient? _ws;
  String _status = 'disconnected';
  String _mooTitle = 'mooR';

  static const int _maxCommandHistory = 500;

  bool _eventLogBackendHasPubkey = false;
  bool _eventLogHasLocalKey = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  bool _wasWsConnected = false;
  final Set<String> _seenNarrativeEventIds = <String>{};
  final Set<String> _seenNarrativeDedupKeys = <String>{};

  // Command history: 0 = current input, 1 = most recent command, etc.
  final List<String> _commandHistory = [];
  final Map<int, String> _historyBuffer = {};
  int _historyOffset = 0;

  String? _verbPill;
  String? _verbPillPlaceholder;
  String? _serverPlaceholderText;
  bool _verbSuggestionsAvailable = false;
  List<PaletteVerb> _paletteVerbs = paletteVerbsFallback;
  InputPromptRequest? _inputPrompt;

  @override
  void initState() {
    super.initState();
    _mooTitle = widget.initialMooTitle;
    _scrollCtrl.addListener(_onScroll);
    _presentations.addListener(_onPresentationsChanged);
    _inputCtrl.onPillCleared = () {
      if (!mounted) return;
      setState(() {
        _verbPill = null;
        _verbPillPlaceholder = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputFocus.requestFocus();
      });
    };
    _inputCtrl.onPillSelected = () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputFocus.requestFocus();
      });
    };
    _inputCtrl.addListener(_updateVerbCompletionGhost);
    _connectWs();
    _initEncryption();
    _refreshVerbSuggestions();
    _refreshMooTitle();
  }

  @override
  void dispose() {
    _promptFocus.dispose();
    _promptCtrl.dispose();
    _inputCtrl
      ..removeListener(_updateVerbCompletionGhost)
      ..dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _presentations
      ..removeListener(_onPresentationsChanged)
      ..dispose();
    _ws?.close();
    super.dispose();
  }

  Future<void> _refreshMooTitle() async {
    try {
      final api = MoorHttpApi(widget.session.baseUri);
      final title = await api.fetchMooTitle(
        authToken: widget.session.authToken,
      );
      if (!mounted) return;
      if (title == null || title.trim().isEmpty) return;
      setState(() {
        _mooTitle = title.trim();
      });
    } on Object {
      // Keep existing title when moo_title is unavailable.
    }
  }

  String _newId(String prefix) {
    _idSeq += 1;
    return '$prefix$_idSeq';
  }

  void _onPresentationsChanged() {
    final nextKey = _computeCurrentRoomLookKey();
    if (nextKey != _currentRoomLookKey) {
      setState(() {
        _currentRoomLookKey = nextKey;
        _currentRoomLookMessageId = null;
        _isCurrentRoomLookDockLatched = false;
      });
    }
    _syncEditorSessionsFromPresentations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  void _syncEditorSessionsFromPresentations() {
    if (!mounted) return;
    final wasEmpty = _editorSessions.isEmpty;
    final oldPids = _editorSessions.map((e) => e.presentationId).toSet();
    final wanted = <String, EditorSession>{};

    void addWanted(EditorSession s) {
      wanted[s.presentationId] = s;
    }

    for (final it in _presentations.byTarget('verb-editor')) {
      if (it is! PresentationModel) continue;
      final pid = it.id;
      final rawObject = it.attrs['object'] ?? it.attrs['objectCurie'];
      final rawVerb = it.attrs['verb'] ?? it.attrs['verbName'];
      if (rawObject == null || rawVerb == null) continue;
      final objectCurie = objectRefToCurie(rawObject);
      if (objectCurie == null) {
        _appendSystem('verb-editor: invalid object=$rawObject');
        continue;
      }
      final title = (it.attrs['title']?.toString().trim().isNotEmpty ?? false)
          ? it.attrs['title'].toString()
          : 'Edit $objectCurie:$rawVerb';
      addWanted(
        VerbEditorSession(
          id: pid,
          title: title,
          presentationId: pid,
          objectCurie: objectCurie,
          verbName: rawVerb,
        ),
      );
    }

    for (final it in _presentations.byTarget('property-editor')) {
      if (it is! PresentationModel) continue;
      final pid = it.id;
      final rawObject = it.attrs['object'] ?? it.attrs['objectCurie'];
      final rawProp = it.attrs['property'] ?? it.attrs['propertyName'];
      if (rawObject == null || rawProp == null) continue;
      final objectCurie = objectRefToCurie(rawObject);
      if (objectCurie == null) {
        _appendSystem('property-editor: invalid object=$rawObject');
        continue;
      }
      final title = (it.attrs['title']?.toString().trim().isNotEmpty ?? false)
          ? it.attrs['title'].toString()
          : 'Edit $objectCurie.$rawProp';
      addWanted(
        PropertyEditorSession(
          id: pid,
          title: title,
          presentationId: pid,
          objectCurie: objectCurie,
          propertyName: rawProp,
          isValueEditor: false,
        ),
      );
    }

    for (final it in _presentations.byTarget('property-value-editor')) {
      if (it is! PresentationModel) continue;
      final pid = it.id;
      final rawObject = it.attrs['object'] ?? it.attrs['objectCurie'];
      final rawProp = it.attrs['property'] ?? it.attrs['propertyName'];
      if (rawObject == null || rawProp == null) continue;
      final objectCurie = objectRefToCurie(rawObject);
      if (objectCurie == null) {
        _appendSystem('property-value-editor: invalid object=$rawObject');
        continue;
      }
      final title = (it.attrs['title']?.toString().trim().isNotEmpty ?? false)
          ? it.attrs['title'].toString()
          : 'Edit $objectCurie.$rawProp';
      addWanted(
        PropertyEditorSession(
          id: pid,
          title: title,
          presentationId: pid,
          objectCurie: objectCurie,
          propertyName: rawProp,
          isValueEditor: true,
        ),
      );
    }

    final existingByPid = <String, EditorSession>{
      for (final s in _editorSessions) s.presentationId: s,
    };
    final nextSessions = <EditorSession>[];

    for (final s in _editorSessions) {
      final keep = wanted[s.presentationId];
      if (keep == null) continue;
      // Keep existing instance to preserve widget state; title changes are rare
      // and not worth a hard refresh for the spike.
      nextSessions.add(existingByPid[s.presentationId]!);
      wanted.remove(s.presentationId);
    }
    if (wanted.isNotEmpty) {
      nextSessions.addAll(wanted.values);
    }

    final didChange =
        nextSessions.length != _editorSessions.length ||
        !_sameStringList(
          nextSessions.map((e) => e.presentationId).toList(),
          _editorSessions.map((e) => e.presentationId).toList(),
        );
    if (!didChange) return;

    final nextPids = nextSessions.map((e) => e.presentationId).toSet();
    final newPids = nextPids.difference(oldPids);
    final toRemove = _editorPaneCache.keys
        .where((pid) => !nextPids.contains(pid))
        .toList();
    for (final pid in toRemove) {
      _editorPaneCache.remove(pid);
    }

    setState(() {
      _editorSessions
        ..clear()
        ..addAll(nextSessions);
      if (_activeEditorIndex >= _editorSessions.length) {
        _activeEditorIndex = _editorSessions.isEmpty
            ? 0
            : _editorSessions.length - 1;
      }
      if (_activeEditorIndex < 0) _activeEditorIndex = 0;
      if (wasEmpty && _editorSessions.isNotEmpty) {
        // First editor opened: make the newest one active.
        _activeEditorIndex = _editorSessions.length - 1;
      }
      if (newPids.isNotEmpty) {
        final lastNewIdx = _editorSessions.lastIndexWhere(
          (s) => newPids.contains(s.presentationId),
        );
        if (lastNewIdx >= 0) {
          _activeEditorIndex = lastNewIdx;
        }
      }
    });
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _closeEditorSession(EditorSession s) async {
    await _dismissPresentationById(s.presentationId);

    if (!mounted) return;
    setState(() {
      _editorPaneCache.remove(s.presentationId);
      final idx = _editorSessions.indexWhere(
        (it) => it.presentationId == s.presentationId,
      );
      if (idx >= 0) {
        _editorSessions.removeAt(idx);
        if (_activeEditorIndex >= _editorSessions.length) {
          _activeEditorIndex = _editorSessions.isEmpty
              ? 0
              : _editorSessions.length - 1;
        }
      }
    });

    // Also remove from local presentation store so we don't reopen it if the
    // backend is slow to send Unpresent.
    _presentations.remove(s.presentationId);
  }

  Future<void> _dismissPresentationById(String presentationId) async {
    if (presentationId == _debugPanelId) {
      setState(() {
        _debugPanelVisible = false;
      });
      _presentations.remove(presentationId);
      return;
    }
    final authToken = widget.session.authToken;
    final baseUri = widget.session.baseUri;
    final api = MoorHttpApi(baseUri);
    try {
      await api.dismissPresentation(
        authToken: authToken,
        presentationId: presentationId,
      );
    } on Object catch (e) {
      _appendSystem('dismiss presentation failed: $e');
    }
    _presentations.remove(presentationId);
  }

  Future<void> _openEditorFullscreen(EditorSession s) async {
    final authToken = widget.session.authToken;
    final baseUri = widget.session.baseUri;
    final title = s.title;

    final child = switch (s) {
      VerbEditorSession(:final objectCurie, :final verbName) => VerbEditorPane(
        key: ValueKey('fullscreen:${s.presentationId}'),
        baseUri: baseUri,
        authToken: authToken,
        objectCurie: objectCurie,
        verbName: verbName,
      ),
      PropertyEditorSession(:final objectCurie, :final propertyName) =>
        PropertyEditorPane(
          key: ValueKey('fullscreen:${s.presentationId}'),
          baseUri: baseUri,
          authToken: authToken,
          objectCurie: objectCurie,
          propertyName: propertyName,
        ),
    };

    final screen = switch (s) {
      VerbEditorSession() => VerbEditorScreen(title: title, child: child),
      PropertyEditorSession() => PropertyEditorScreen(
        title: title,
        child: child,
      ),
    };
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => screen,
      ),
    );
  }

  void _onScroll() {
    _updateRoomLookLatch();
  }

  String? _computeCurrentRoomLookKey() {
    if (!_roomHudEnabled) {
      return null;
    }
    final tops = _presentations.byTarget('top');
    for (final p in tops) {
      if (p.id == 'room-look') {
        return getRoomLookKeyFromDockItem(p);
      }
    }
    return null;
  }

  void _updateRoomLookLatch() {
    if (!mounted) return;
    if (!_roomHudEnabled) return;
    final roomKey = _currentRoomLookKey;
    if (roomKey == null) return;

    final msgId = _latestLookMessageIdByRoom[roomKey];
    if (msgId == null) return;

    if (msgId != _currentRoomLookMessageId) {
      setState(() {
        _currentRoomLookMessageId = msgId;
        _isCurrentRoomLookDockLatched = false;
      });
      return;
    }

    if (_isCurrentRoomLookDockLatched) {
      return;
    }

    final targetKey = _messageKeys[msgId];
    final targetCtx = targetKey?.currentContext;
    final listCtx = _listKey.currentContext;
    if (targetCtx == null || listCtx == null) return;

    final targetBox = targetCtx.findRenderObject();
    final listBox = listCtx.findRenderObject();
    if (targetBox is! RenderBox || listBox is! RenderBox) return;
    if (!targetBox.attached || !listBox.attached) return;
    if (!targetBox.hasSize || !listBox.hasSize) return;

    double targetTop;
    double listTop;
    try {
      targetTop = targetBox.localToGlobal(Offset.zero).dy;
      listTop = listBox.localToGlobal(Offset.zero).dy;
    } on Object {
      // During rapid rebuilds/route transitions the render objects can be in a
      // transient state; skip latching until the next frame.
      return;
    }
    final listBottom = listTop + listBox.size.height;
    const epsilon = 1.0;
    final isVisible =
        targetTop >= (listTop - epsilon) && targetTop < (listBottom + epsilon);
    if (!isVisible) {
      setState(() {
        _isCurrentRoomLookDockLatched = true;
      });
    }
  }

  Future<void> _connectWs() async {
    setState(() {
      _status = 'connecting';
    });

    final ws = MoorWsClient(
      session: widget.session,
      onSystemMessage: _appendSystem,
      onNarrativeItem: _appendItem,
      onPresentationUpsert: _presentations.upsert,
      onPresentationRemove: _presentations.remove,
      onInputPromptRequest: _handleInputPromptRequest,
      onConnectionStatusChanged: (status) {
        if (!mounted) return;
        if (status == 'connected') {
          _wasWsConnected = true;
          if (_eventLogHasLocalKey && !_historyLoaded && !_historyLoading) {
            unawaited(_loadInitialHistory());
          }
        } else if (status == 'disconnected') {
          if (_inputPrompt != null) {
            _clearInputPrompt();
          }
          final shouldResyncHistory =
              _wasWsConnected && _eventLogHasLocalKey && _historyLoaded;
          _wasWsConnected = false;
          if (shouldResyncHistory) {
            setState(() {
              _historyLoaded = false;
            });
          }
        }
        setState(() {
          _status = status;
        });
      },
    );
    _ws = ws;

    try {
      final connected = await ws.connect(mode: widget.mode);
      if (!mounted) return;
      if (!connected) {
        setState(() {
          _status = 'error';
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      _appendSystem('WS connect failed: $e');
      setState(() {
        _status = 'error';
      });
    }
  }

  Future<void> _initEncryption() async {
    // Match Meadow web flow:
    // - check if backend has a pubkey
    // - check if we have a local age identity
    final playerOid = widget.session.playerCurie;
    final authToken = widget.session.authToken;
    final api = MoorHttpApi(widget.session.baseUri);

    final localIdentity = await EventLogKeyStore.getIdentity(playerOid);
    final hasLocal = localIdentity != null && localIdentity.trim().isNotEmpty;

    String? backendPubkey;
    try {
      backendPubkey = await api.getEventLogPubkey(authToken: authToken);
    } on Object catch (e) {
      _appendSystem('History encryption check failed: $e');
      return;
    }

    final backendHasPubkey =
        backendPubkey != null && backendPubkey.trim().isNotEmpty;
    if (!mounted) return;
    setState(() {
      _eventLogBackendHasPubkey = backendHasPubkey;
      _eventLogHasLocalKey = hasLocal;
    });

    if (hasLocal && !backendHasPubkey) {
      // Backend was reset; clear stale local identity.
      await EventLogKeyStore.removeIdentity(playerOid);
      _appendSystem(
        'History encryption: backend missing pubkey, clearing local key',
      );
      if (!mounted) return;
      setState(() {
        _eventLogHasLocalKey = false;
      });
    }

    if (!backendHasPubkey && !hasLocal) {
      // No key anywhere; user can set it up later from the session menu.
      return;
    }

    if (backendHasPubkey && !hasLocal) {
      final password = await _promptHistoryPassword();
      if (!mounted) return;
      if (password == null || password.isEmpty) {
        _appendSystem('History encryption locked (no password provided)');
        return;
      }
      await _unlockEncryption(password);
      if (!mounted) return;
      setState(() {
        _eventLogHasLocalKey = true;
      });
      return;
    }

    if (backendHasPubkey && hasLocal) {
      _appendSystem('History encryption unlocked');
      await _loadInitialHistory();
      return;
    }
  }

  Future<void> _setupEncryption(String password) async {
    final playerOid = widget.session.playerCurie;
    final authToken = widget.session.authToken;
    final api = MoorHttpApi(widget.session.baseUri);

    try {
      _appendSystem('Setting up history encryption...');
      final derived = await EventLogEncryption.deriveKeyBytes(
        password: password,
        identifier: playerOid,
      );
      final identity = EventLogEncryption.identityFromDerivedBytes(derived);
      final pubkey = await EventLogEncryption.publicKeyFromDerivedBytes(
        derived,
      );
      await api.setEventLogPubkey(authToken: authToken, publicKey: pubkey);
      await EventLogKeyStore.setIdentity(
        playerOid: playerOid,
        ageIdentity: identity,
      );
      _appendSystem('History encryption set');
      if (!mounted) return;
      setState(() {
        _eventLogBackendHasPubkey = true;
        _eventLogHasLocalKey = true;
      });
      await _loadInitialHistory();
    } on Object catch (e) {
      _appendSystem('History encryption setup failed: $e');
    }
  }

  Future<void> _unlockEncryption(String password) async {
    final playerOid = widget.session.playerCurie;
    try {
      _appendSystem('Unlocking history encryption...');
      final derived = await EventLogEncryption.deriveKeyBytes(
        password: password,
        identifier: playerOid,
      );
      final identity = EventLogEncryption.identityFromDerivedBytes(derived);
      await EventLogKeyStore.setIdentity(
        playerOid: playerOid,
        ageIdentity: identity,
      );
      _appendSystem('History encryption unlocked');
      await _loadInitialHistory();
    } on Object catch (e) {
      _appendSystem('History encryption unlock failed: $e');
    }
  }

  Future<void> _loadInitialHistory() async {
    if (_historyLoading || _historyLoaded) {
      return;
    }

    final playerOid = widget.session.playerCurie;
    final identity = await EventLogKeyStore.getIdentity(playerOid);
    if (identity == null || identity.trim().isEmpty) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _historyLoading = true;
    });

    try {
      _appendSystem('Loading history...');
      final api = MoorHttpApi(widget.session.baseUri);
      final events = await api.fetchHistory(
        authToken: widget.session.authToken,
        sinceSeconds: 86400,
        limit: 100,
      );

      final items = <NarrativeItem>[];
      final batchEventIds = <String>{};
      final batchDedupKeys = <String>{};
      for (final ev in events) {
        final decrypted = await decryptEventBlobAge(ev.encryptedBlob, identity);
        final parsed = _parseNarrativeEnvelope(decrypted);
        if (parsed == null) {
          continue;
        }
        final eventId = _narrativeEventId(parsed);
        final dedupKey = _narrativeDedupKey(parsed);
        final alreadySeen =
            (eventId != null &&
                (_seenNarrativeEventIds.contains(eventId) ||
                    batchEventIds.contains(eventId))) ||
            (dedupKey != null &&
                (_seenNarrativeDedupKeys.contains(dedupKey) ||
                    batchDedupKeys.contains(dedupKey)));
        if (alreadySeen) {
          continue;
        }
        if (eventId != null) {
          batchEventIds.add(eventId);
        }
        if (dedupKey != null) {
          batchDedupKeys.add(dedupKey);
        }
        items.add(parsed);
      }

      if (!mounted) return;
      setState(() {
        _items.insertAll(0, items);
        for (final item in items) {
          _rememberNarrativeIdentity(item);
        }
        _historyLoaded = true;
      });
      _appendSystem('History loaded (${items.length} events)');
    } on Object catch (e) {
      _appendSystem('History load failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  NarrativeItem? _parseNarrativeEnvelope(Uint8List bytes) {
    final evt = moor_common.NarrativeEvent(bytes);
    final e = evt.event;
    if (e == null) {
      return null;
    }
    final eventId = _uuidBytesToHex(evt.eventId?.data);

    final ts = DateTime.fromMillisecondsSinceEpoch(
      (evt.timestamp / 1000000).toInt(),
      isUtc: true,
    ).toLocal();

    final eventType = e.eventType?.value ?? 0;
    if (eventType == moor_common.EventUnionTypeId.NotifyEvent.value) {
      final notify = e.event as moor_common.NotifyEvent?;
      if (notify == null || notify.value == null) {
        return null;
      }
      final moorValue = MoorVar.fromFlatBuffer(notify.value!);
      final lines = moorValue.asLines();
      if (lines.isEmpty) return null;
      final ct = normalizeContentType(notify.contentType?.value);

      final metadata = parseNarrativeMetadata(
        metadataPairs: notify.metadata,
        eventId: eventId,
      );
      return NarrativeItem(
        id: _newId('h'),
        timestamp: ts,
        content: lines,
        contentType: ct,
        noNewline: notify.noNewline,
        presentationHint: metadata.presentationHint,
        groupId: metadata.groupId,
        metadata: metadata,
      );
    }

    if (eventType == moor_common.EventUnionTypeId.PresentEvent.value) {
      final present = e.event as moor_common.PresentEvent?;
      final p = present?.presentation;
      if (p == null) return null;
      final c = p.content ?? '';
      final content = c.isEmpty ? const <String>[] : <String>[c];
      if (content.isEmpty) return null;
      final ct = normalizeContentType(p.contentType);
      return NarrativeItem(
        id: _newId('h'),
        timestamp: ts,
        content: content,
        contentType: ct,
        noNewline: false,
        presentationHint: null,
        groupId: null,
        metadata: null,
      );
    }

    if (eventType == moor_common.EventUnionTypeId.TracebackEvent.value) {
      final tb = e.event as moor_common.TracebackEvent?;
      final ex = tb?.exception;
      final bt = ex?.backtrace;
      if (bt == null) return null;
      final lines = <String>[];
      for (final v in bt) {
        final s = MoorVar.fromFlatBuffer(v).asLines();
        if (s.isNotEmpty) {
          lines.addAll(s);
        }
      }
      if (lines.isEmpty) return null;
      return NarrativeItem(
        id: _newId('h'),
        timestamp: ts,
        content: [lines.join('\n')],
        contentType: 'text/traceback',
        noNewline: false,
        presentationHint: null,
        groupId: null,
        metadata: null,
      );
    }

    // Ignore unpresent/data for now.
    return null;
  }

  Future<void> _forgetLocalEncryptionKey() async {
    final playerOid = widget.session.playerCurie;
    await EventLogKeyStore.removeIdentity(playerOid);
    if (!mounted) return;
    setState(() {
      _eventLogHasLocalKey = false;
    });
    _appendSystem('History encryption: forgot local key');
  }

  Future<void> _showEncryptionMenu() async {
    final playerOid = widget.session.playerCurie;
    final backendHas = _eventLogBackendHasPubkey;
    final localHas = _eventLogHasLocalKey;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('History Encryption'),
          content: SelectableText(
            'player: $playerOid\nbackend pubkey: ${backendHas ? "yes" : "no"}\nlocal key: ${localHas ? "yes" : "no"}',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          actions: [
            if (!backendHas)
              FilledButton(
                onPressed: () => Navigator.of(context).pop('setup'),
                child: const Text('Setup'),
              ),
            if (backendHas && !localHas)
              FilledButton(
                onPressed: () => Navigator.of(context).pop('unlock'),
                child: const Text('Unlock'),
              ),
            if (localHas)
              TextButton(
                onPressed: () => Navigator.of(context).pop('forget'),
                child: const Text('Forget Local Key'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    switch (choice) {
      case 'setup':
        {
          final password = await _promptHistoryPassword();
          if (!mounted) return;
          if (password == null || password.isEmpty) return;
          await _setupEncryption(password);
        }
      case 'unlock':
        {
          final password = await _promptHistoryPassword();
          if (!mounted) return;
          if (password == null || password.isEmpty) return;
          await _unlockEncryption(password);
          if (!mounted) return;
          setState(() {
            _eventLogHasLocalKey = true;
          });
        }
      case 'forget':
        await _forgetLocalEncryptionKey();
      default:
        break;
    }
  }

  Future<String?> _promptHistoryPassword() async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    try {
      final res = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enter History Password'),
            content: TextField(
              controller: ctrl,
              focusNode: focus,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
              ),
              onSubmitted: (_) => Navigator.of(context).pop(ctrl.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(ctrl.text),
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      );
      return res;
    } finally {
      ctrl.dispose();
      focus.dispose();
    }
  }

  void _appendSystem(String m) {
    _appendDebugLine(m);
  }

  void _appendNarrativeText(String text, {String contentType = 'text/plain'}) {
    if (text.trim().isEmpty) {
      return;
    }
    _appendItem(
      NarrativeItem(
        id: _newId('local'),
        timestamp: DateTime.now(),
        content: [text],
        contentType: contentType,
        noNewline: false,
        presentationHint: null,
        groupId: null,
        metadata: null,
      ),
    );
  }

  void _ensureDebugPanel() {
    if (!_debugPanelVisible) return;
    final content = _debugLines.isEmpty
        ? '(debug output)'
        : _debugLines.join('\n');
    _presentations.upsert(
      PresentationModel(
        id: _debugPanelId,
        target: 'right',
        contentType: 'text/plain',
        content: content,
        attrs: const <String, String>{
          'title': 'Debug',
          'source': 'local_debug',
          'kind': 'debug_output',
        },
      ),
    );
  }

  void _appendDebugLine(String line) {
    final ts = DateTime.now().toIso8601String().split('T').last;
    _debugLines.add('[$ts] $line');
    const maxLines = 500;
    if (_debugLines.length > maxLines) {
      _debugLines.removeRange(0, _debugLines.length - maxLines);
    }
    _ensureDebugPanel();
  }

  void _toggleDebugPanel() {
    setState(() {
      _debugPanelVisible = !_debugPanelVisible;
    });
    if (_debugPanelVisible) {
      _ensureDebugPanel();
    } else {
      _presentations.remove(_debugPanelId);
    }
  }

  void _appendItem(NarrativeItem it) {
    final eventId = _narrativeEventId(it);
    final dedupKey = _narrativeDedupKey(it);
    if ((eventId != null && _seenNarrativeEventIds.contains(eventId)) ||
        (dedupKey != null && _seenNarrativeDedupKeys.contains(dedupKey))) {
      return;
    }

    final roomKey = getRoomLookKeyFromNarrative(
      presentationHint: it.presentationHint,
      eventMetadata: it.metadata?.raw,
    );
    if (roomKey != null) {
      _latestLookMessageIdByRoom[roomKey] = it.id;
    }

    setState(() {
      _items.add(it);
      _rememberNarrativeIdentity(it);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  String? _uuidBytesToHex(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? _narrativeEventId(NarrativeItem item) {
    return item.metadata?.eventId ??
        item.metadata?.text(const ['eventId', 'event_id']);
  }

  String? _narrativeDedupKey(NarrativeItem item) {
    final correlation = item.metadata?.text(
      const ['correlationId', 'correlation_id', 'deliveryId', 'delivery_id'],
    );
    if (correlation != null) {
      return 'corr:$correlation';
    }
    final eventId = _narrativeEventId(item);
    if (eventId != null) {
      return 'event:$eventId';
    }
    return null;
  }

  void _rememberNarrativeIdentity(NarrativeItem item) {
    final eventId = _narrativeEventId(item);
    if (eventId != null) {
      _seenNarrativeEventIds.add(eventId);
    }
    final dedupKey = _narrativeDedupKey(item);
    if (dedupKey != null) {
      _seenNarrativeDedupKeys.add(dedupKey);
    }
  }

  String? _actorCurie(NarrativeItem item) {
    return item.metadata?.actorCurie;
  }

  String? _actorName(NarrativeItem item) {
    return item.metadata?.actorName;
  }

  String _speechContent(NarrativeItem item) {
    final content = item.metadata?.content;
    if (content != null && content.isNotEmpty) {
      return content;
    }
    return item.content.join('\n');
  }

  Widget _buildSpeechBubbleMessage(
    BuildContext context,
    NarrativeItem item,
    ColorScheme cs,
  ) {
    final actorCurie = _actorCurie(item);
    final isSelf =
        actorCurie != null &&
        actorCurie.toLowerCase() == widget.session.playerCurie.toLowerCase();
    final actorLabel = isSelf ? 'You' : (_actorName(item) ?? actorCurie ?? 'Unknown');
    final semanticSpeech = item.metadata?.content;
    final bubbleContent = (semanticSpeech != null && semanticSpeech.isNotEmpty)
        ? <String>[semanticSpeech]
        : (item.content.isNotEmpty
              ? item.content
              : <String>[_speechContent(item)]);
    final bubbleContentType =
        (semanticSpeech != null && semanticSpeech.isNotEmpty)
        ? 'text/djot'
        : item.contentType;

    final bubbleColor = isSelf
        ? Color.lerp(cs.primaryContainer, cs.primary, 0.12) ??
              cs.primaryContainer
        : cs.secondaryContainer;
    final bubbleTextColor = isSelf
        ? cs.onPrimaryContainer
        : cs.onSecondaryContainer;
    final rowAlign = isSelf ? MainAxisAlignment.end : MainAxisAlignment.start;
    final nameText = Flexible(
      child: Text(
        actorLabel,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: cs.outline,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final bubbleBody = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isSelf ? 14 : 4),
            bottomRight: Radius.circular(isSelf ? 4 : 14),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: bubbleTextColor,
            fontSize: 14,
          ),
          child: ContentRenderer(
            content: bubbleContent,
            contentType: bubbleContentType,
            isStale: false,
            onLinkTap: _handleLinkTap,
            monospace: _monospaceNarrative,
          ),
        ),
      ),
    );
    final bubbleTail = CustomPaint(
      size: const Size(8, 10),
      painter: _SpeechBubbleTailPainter(
        color: bubbleColor,
        isSelf: isSelf,
      ),
    );
    final bubbleWithTail = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isSelf
          ? <Widget>[bubbleBody, bubbleTail]
          : <Widget>[bubbleTail, bubbleBody],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisAlignment: rowAlign,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isSelf
            ? <Widget>[bubbleWithTail, const SizedBox(width: 2), nameText]
            : <Widget>[nameText, const SizedBox(width: 2), bubbleWithTail],
      ),
    );
  }

  static bool _sameActor(NarrativeItem a, NarrativeItem b) {
    final ak = a.metadata?.actorCurie;
    final bk = b.metadata?.actorCurie;
    if (ak == null || bk == null) return true;
    return ak == bk;
  }

  static List<List<NarrativeItem>> _groupNarrativeItems(
    List<NarrativeItem> items,
  ) {
    if (items.isEmpty) return const <List<NarrativeItem>>[];

    final grouped = <List<NarrativeItem>>[];
    var current = <NarrativeItem>[];

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      current.add(it);

      final next = (i + 1) < items.length ? items[i + 1] : null;
      final sameHintGroup =
          it.presentationHint != null &&
          next?.presentationHint == it.presentationHint &&
          it.groupId != null &&
          it.groupId == next?.groupId &&
          next != null &&
          _sameActor(it, next);
      final shouldContinueGroup = it.noNewline || sameHintGroup;

      if (!shouldContinueGroup || i == items.length - 1) {
        grouped.add(current);
        current = <NarrativeItem>[];
      }
    }

    return grouped;
  }

  void _handleInputPromptRequest(InputPromptRequest request) {
    final md = request.metadata;
    final initial = md.defaultValue?.toString() ?? '';
    setState(() {
      _inputPrompt = request;
      _promptCtrl.text = initial;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.unfocus();
      _promptFocus.requestFocus();
      _appendSystem(
        'Input prompt requested: id=${request.requestId} type=${md.inputType ?? "text"}',
      );
    });
  }

  void _clearInputPrompt() {
    setState(() {
      _inputPrompt = null;
      _promptCtrl.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });
  }

  void _submitInputPromptValue(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      return;
    }
    _ws?.sendText(v);
    _clearInputPrompt();
  }

  Widget _buildInputPromptComposer(
    BuildContext context,
    InputPromptRequest req,
  ) {
    final md = req.metadata;
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
          onLinkTap: _handleLinkTap,
          monospace: _monospaceNarrative,
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
                onPressed: () => _submitInputPromptValue('yes'),
                child: const Text('Yes'),
              ),
              FilledButton.tonal(
                onPressed: () => _submitInputPromptValue('no'),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => _submitInputPromptValue('@abort'),
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
            onPressed: () => _submitInputPromptValue('ok'),
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
                  onPressed: () => _submitInputPromptValue(choice),
                  child: Text(choice),
                ),
              TextButton(
                onPressed: () => _submitInputPromptValue('@abort'),
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
                  onPressed: () => _submitInputPromptValue('yes'),
                  child: const Text('Yes'),
                ),
                FilledButton.tonal(
                  onPressed: () => _submitInputPromptValue('no'),
                  child: const Text('No'),
                ),
                if (type == 'yes_no_alternative_all')
                  FilledButton.tonal(
                    onPressed: () => _submitInputPromptValue('all'),
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
                  controller: _promptCtrl,
                  focusNode: _promptFocus,
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
                  onSubmitted: (_) => _submitInputPromptValue(_promptCtrl.text),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _submitInputPromptValue(_promptCtrl.text),
                child: const Text('Submit'),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => _submitInputPromptValue('@abort'),
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

  void _send() {
    final input = _inputCtrl.commandText;
    if (input.trim().isEmpty && (_verbPill == null || _verbPill!.isEmpty)) {
      return;
    }

    final commandsSent = <String>[];
    for (final line in input.split('\n')) {
      final cmd = line.trim();
      if (cmd.isEmpty) continue;
      final msg = _verbPill == null ? cmd : '${_verbPill!} $cmd';
      commandsSent.add(msg);
      _ws?.sendText(msg);
    }
    if (commandsSent.isEmpty && _verbPill != null && _verbPill!.isNotEmpty) {
      commandsSent.add(_verbPill!);
      _ws?.sendText(_verbPill!);
    }
    if (commandsSent.isEmpty) {
      return;
    }

    for (final cmd in commandsSent) {
      _commandHistory.add(cmd);
    }
    if (_commandHistory.length > _maxCommandHistory) {
      final start = _commandHistory.length - _maxCommandHistory;
      _commandHistory.removeRange(0, start);
    }

    _historyBuffer.clear();
    _historyOffset = 0;
    setState(() {
      _verbPill = null;
      _verbPillPlaceholder = null;
    });
    _inputCtrl
      ..verbPill = null
      ..verbPillPlaceholder = null
      ..ghostCompletion = null
      ..clear();

    // Keep focus in the input field after sending (desktop UX).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });

    _refreshVerbSuggestions();
  }

  PaletteVerb? _bestVerbCompletion(String token) {
    if (_paletteVerbs.isEmpty) return null;
    final lower = token.toLowerCase();
    for (final v in _paletteVerbs) {
      if (v.verb.toLowerCase() == lower) {
        return v;
      }
    }
    for (final v in _paletteVerbs) {
      if (v.verb.toLowerCase().startsWith(lower) &&
          v.verb.length > token.length) {
        return v;
      }
    }
    return null;
  }

  void _updateVerbCompletionGhost() {
    if (!mounted) return;
    if (!_verbPaletteEnabled || _verbPill != null) {
      if (_inputCtrl.ghostCompletion != null) {
        setState(() {
          _inputCtrl.ghostCompletion = null;
        });
      }
      return;
    }

    final cmd = _inputCtrl.commandText;
    if (cmd.contains('\n')) {
      if (_inputCtrl.ghostCompletion != null) {
        setState(() {
          _inputCtrl.ghostCompletion = null;
        });
      }
      return;
    }

    // Only when editing a single leading token (no args yet).
    if (cmd.trim().isEmpty || cmd.contains(' ') || cmd.contains('\t')) {
      if (_inputCtrl.ghostCompletion != null) {
        setState(() {
          _inputCtrl.ghostCompletion = null;
        });
      }
      return;
    }

    final sel = _inputCtrl.selection;
    final atEnd =
        sel.isValid &&
        sel.isCollapsed &&
        sel.baseOffset == _inputCtrl.text.length;
    if (!atEnd) {
      if (_inputCtrl.ghostCompletion != null) {
        setState(() {
          _inputCtrl.ghostCompletion = null;
        });
      }
      return;
    }

    final suggestion = _bestVerbCompletion(cmd);
    final ghost = suggestion?.verb.substring(cmd.length);
    if (ghost == _inputCtrl.ghostCompletion) return;
    setState(() {
      _inputCtrl.ghostCompletion = ghost;
    });
  }

  void _navigateHistory(int delta) {
    if (_commandHistory.isEmpty) {
      return;
    }

    final canNavigate = delta > 0
        ? _historyOffset < _commandHistory.length
        : _historyOffset > 0;
    if (!canNavigate) {
      return;
    }

    final currentText = _inputCtrl.commandText;
    _historyBuffer[_historyOffset] = currentText;

    final nextOffset = (_historyOffset + delta).clamp(
      0,
      _commandHistory.length,
    );
    _historyOffset = nextOffset;

    String nextText;
    final buffered = _historyBuffer[nextOffset];
    if (buffered != null) {
      nextText = buffered;
    } else if (nextOffset == 0) {
      nextText = '';
    } else {
      final idx = _commandHistory.length - nextOffset;
      nextText = (idx >= 0 && idx < _commandHistory.length)
          ? _commandHistory[idx]
          : '';
    }

    _inputCtrl.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  KeyEventResult _handleCommandKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final text = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    final selStart = sel.isValid
        ? (sel.baseOffset < sel.extentOffset
              ? sel.baseOffset
              : sel.extentOffset)
        : -1;
    final selEnd = sel.isValid
        ? (sel.baseOffset > sel.extentOffset
              ? sel.baseOffset
              : sel.extentOffset)
        : -1;
    final isCollapsed = selStart >= 0 && selStart == selEnd;
    final isMultiline = text.contains('\n');
    final cursorAtEdge =
        selStart <= 0 || (isCollapsed && selStart >= text.length);

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!isMultiline || cursorAtEdge) {
        _navigateHistory(1);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (!isMultiline || cursorAtEdge) {
        _navigateHistory(-1);
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (!shift) {
        _send();
        return KeyEventResult.handled;
      }
      // Shift+Enter: allow newline insertion.
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      if (!shift && _verbPaletteEnabled && _verbPill == null) {
        final cmd = _inputCtrl.commandText;
        if (!cmd.contains('\n')) {
          final token = cmd.trim();
          if (token.isEmpty) {
            return KeyEventResult.ignored;
          }
          final suggestion = _bestVerbCompletion(token);
          if (suggestion != null) {
            setState(() {
              _verbPill = suggestion.verb;
              _verbPillPlaceholder = suggestion.placeholder;
            });
            _inputCtrl.promoteLeadingTokenToPill(
              verb: suggestion.verb,
              placeholder: suggestion.placeholder,
            );
            return KeyEventResult.handled;
          }
        }
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_inputCtrl.handleBackspaceAtPillBoundary()) {
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Future<void> _handleLinkTap(String url) async {
    if (url.startsWith('moo://cmd/')) {
      final cmd = Uri.decodeComponent(url.substring('moo://cmd/'.length));
      _ws?.sendText(cmd);
      return;
    }
    if (url.startsWith('moo://inspect/')) {
      final curie = Uri.decodeComponent(url.substring('moo://inspect/'.length));
      await _showInspectSheet(curie);
      return;
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      final u = Uri.tryParse(url);
      if (u == null) {
        _appendSystem('Bad URL: $url');
        return;
      }
      final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
      if (!ok) {
        _appendSystem('Failed to open: $url');
      }
      return;
    }

    // Unknown or unhandled scheme: show it.
    _appendSystem('Unhandled link: $url');
  }

  Future<void> _showInspectSheet(String objectCurie) async {
    final api = MoorHttpApi(widget.session.baseUri);

    InspectData? inspectData;
    try {
      final success = await api.invokeVerb(
        authToken: widget.session.authToken,
        objectCurie: objectCurie,
        verbName: 'inspection',
      );
      final result = success.result;
      final decoded = result != null
          ? MoorVar.fromFlatBuffer(result)
          : moorNoneVar;
      inspectData = parseInspectData(decoded);
      if (inspectData == null) {
        _appendSystem('No inspect data available for $objectCurie');
        return;
      }
      for (final action in inspectData.actions) {
        _appendSystem(
          '[inspect] action metadata: '
          'label=${action.label} '
          'kind=${action.kind ?? "-"} '
          'command=${action.command ?? "-"} '
          'verb=${action.verb ?? "-"} '
          'target=${action.target ?? "-"} '
          'args=${action.args} '
          'resultMode=${action.resultMode ?? "-"} '
          'panelTarget=${action.panelTarget ?? "-"} '
          'panelId=${action.panelId ?? "-"} '
          'panelTitle=${action.panelTitle ?? "-"}',
        );
      }
    } on Object catch (e) {
      _appendSystem('Inspect failed: $e');
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final data = inspectData!;
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
                      onLinkTap: _handleLinkTap,
                      monospace: _monospaceNarrative,
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
                              await _runInspectAction(action);
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

  Future<void> _runInspectAction(InspectAction action) async {
    _appendSystem(
      '[inspect] run action: '
      'label=${action.label} '
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
      'panelTitle=${action.panelTitle ?? "-"}',
    );
    String? inputValue;
    if (action.inputType == 'text') {
      inputValue = await _promptInspectActionInput(action);
      if (inputValue == null) {
        _appendSystem('[inspect] action canceled: ${action.label}');
        return;
      }
    }
    if (action.kind == 'command' || action.command != null) {
      var command = action.command ?? '';
      if (inputValue != null) {
        command = command.contains('{input}')
            ? command.replaceAll('{input}', inputValue)
            : '$command $inputValue'.trim();
      }
      if (command.trim().isNotEmpty) {
        _appendSystem(
          '[inspect] sending command action over websocket: $command',
        );
        _ws?.sendText(command);
      }
      return;
    }

    final verb = action.verb;
    final target = action.target;
    if (verb == null || target == null) {
      return;
    }

    try {
      final api = MoorHttpApi(widget.session.baseUri);
      final args = [...action.args];
      if (inputValue != null) {
        args.add(inputValue);
      }
      final invokeArgs = _buildInspectInvokeArgs(args);
      final success = await api.invokeVerb(
        authToken: widget.session.authToken,
        objectCurie: target,
        verbName: verb,
        argsVarBytes: invokeArgs,
      );
      final eventTypes = success.output
          ?.map((evt) => evt.event?.eventType?.value ?? -1)
          .toList();
      _appendSystem(
        '[inspect] invoke completed: '
        'resultPresent=${success.result != null} '
        'outputEvents=${success.output?.length ?? 0} '
        'eventTypes=${eventTypes ?? const <int>[]}',
      );

      final outputLines = _extractInvokeOutputLines(success.output);
      if (action.resultMode == 'panel' && outputLines.isNotEmpty) {
        final panelTarget = _mapInspectPanelTarget(action.panelTarget);
        final panelId = action.panelId ?? _newId('inspect-action-');
        final panelTitle = action.panelTitle ?? action.label;
        _appendSystem(
          '[inspect] routing action output to panel: '
          'target=$panelTarget id=$panelId title=$panelTitle '
          'lines=${outputLines.length}',
        );
        _presentations.upsert(
          PresentationModel(
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
        return;
      }
      if (action.resultMode == 'panel' && outputLines.isEmpty) {
        _appendSystem(
          '[inspect] panel requested but invoke output had no lines',
        );
      }

      var emittedOutput = false;
      for (final line in outputLines) {
        _appendNarrativeText(line);
        emittedOutput = true;
      }
      if (!emittedOutput) {
        _appendNarrativeText('Action ran: ${action.label}');
      }
    } on Object catch (e) {
      _appendSystem('Action failed (${action.label}): $e');
    }
  }

  Future<String?> _promptInspectActionInput(InspectAction action) async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(action.inputPrompt ?? action.label),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: action.inputPlaceholder ?? 'Enter text',
            ),
            onSubmitted: (_) {
              final text = ctrl.text.trim();
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
                final text = ctrl.text.trim();
                Navigator.of(context).pop(text.isEmpty ? null : text);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return value;
  }

  List<String> _extractInvokeOutputLines(
    List<moor_common.NarrativeEvent>? output,
  ) {
    final lines = <String>[];
    if (output == null) return lines;
    for (final evt in output) {
      final e = evt.event;
      if (e == null) continue;
      final eventType = e.eventType?.value ?? 0;
      if (eventType == moor_common.EventUnionTypeId.NotifyEvent.value) {
        final notify = e.event as moor_common.NotifyEvent?;
        if (notify == null || notify.value == null) continue;
        lines.addAll(MoorVar.fromFlatBuffer(notify.value!).asLines());
      } else if (eventType ==
          moor_common.EventUnionTypeId.TracebackEvent.value) {
        final tb = e.event as moor_common.TracebackEvent?;
        final bt = tb?.exception?.backtrace;
        if (bt == null) continue;
        for (final entry in bt) {
          lines.addAll(MoorVar.fromFlatBuffer(entry).asLines());
        }
      }
    }
    return lines;
  }

  String _mapInspectPanelTarget(String? target) {
    final t = (target ?? '').trim().toLowerCase();
    switch (t) {
      case 'top':
      case 'left':
      case 'right':
      case 'bottom':
        return t;
      case 'tools':
      case 'status':
      case 'inventory':
      case 'navigation':
      case 'communication':
      case 'help':
        // Flutter spike currently renders top presentations for this UI lane.
        return 'top';
      default:
        return 'top';
    }
  }

  Uint8List? _buildInspectInvokeArgs(List<String> args) {
    if (args.isEmpty) return null;
    final packed = <MoorVar>[];
    for (final a in args) {
      final ref = ObjectRef.fromCurie(a);
      if (ref != null) {
        packed.add(MoorVar(ref.obj));
      } else {
        packed.add(MoorVar(a));
      }
    }
    return Uint8List.fromList(MoorList(packed).toVar().toBytes());
  }

  Future<void> _refreshVerbSuggestions() async {
    final authToken = widget.session.authToken;
    final player = widget.session.playerCurie;
    final api = MoorHttpApi(widget.session.baseUri);

    try {
      final success = await api.invokeVerb(
        authToken: authToken,
        objectCurie: player,
        verbName: 'verb_suggestions',
      );
      final result = success.result;
      final decoded = result != null
          ? MoorVar.fromFlatBuffer(result)
          : moorNoneVar;
      final suggestions = parseVerbSuggestions(decoded);
      final placeholder = suggestions
          .where((s) => s.placeholderText != null)
          .firstOrNull;

      final verbs = <PaletteVerb>[];
      for (final s in suggestions) {
        verbs.add(suggestionToPaletteVerb(s));
      }
      verbs.sort((a, b) {
        final aIsAt = a.verb.startsWith('@');
        final bIsAt = b.verb.startsWith('@');
        if (aIsAt == bIsAt) return 0;
        return aIsAt ? 1 : -1;
      });

      if (!mounted) return;
      setState(() {
        // "available" in Meadow web means the verb exists and returned a list,
        // even if it's empty.
        _verbSuggestionsAvailable = decoded.asList() != null;
        _serverPlaceholderText = placeholder?.placeholderText;
        _paletteVerbs = verbs.isNotEmpty ? verbs : paletteVerbsFallback;
      });

      if (!decoded.isNone() && suggestions.isEmpty) {
        _appendSystem(
          'verb_suggestions returned no suggestions (decoded=${decoded.toLiteral()})',
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      _appendSystem('verb_suggestions fetch failed: $e');
      setState(() {
        _verbSuggestionsAvailable = false;
        _serverPlaceholderText = null;
        _paletteVerbs = paletteVerbsFallback;
      });
    }
  }

  void _selectPaletteVerb(PaletteVerb v) {
    setState(() {
      _verbPill = v.verb;
      _verbPillPlaceholder = v.placeholder;
    });
    _inputCtrl.setVerbPill(verb: v.verb, placeholder: v.placeholder);
  }

  Future<void> _showSettingsSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        // Modal bottom sheets are separate routes; parent setState does not
        // automatically rebuild this subtree, so keep local state here.
        var roomHudEnabled = _roomHudEnabled;
        var showNarrativeMeta = _showNarrativeMeta;
        var verbPaletteEnabled = _verbPaletteEnabled;
        var monospaceNarrative = _monospaceNarrative;
        var speechBubblesEnabled = _speechBubblesEnabled;
        var themeMode = _ThemeScope.of(context).mode;

        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: roomHudEnabled,
                      title: const Text('Room HUD'),
                      subtitle: const Text(
                        'Show room description when scrolled out',
                      ),
                      onChanged: (v) {
                        modalSetState(() {
                          roomHudEnabled = v;
                        });
                        setState(() {
                          _roomHudEnabled = v;
                        });
                        _onPresentationsChanged();
                      },
                    ),
                    SwitchListTile(
                      value: showNarrativeMeta,
                      title: const Text('Timestamps'),
                      subtitle: const Text(
                        'Show timestamp and content type per line',
                      ),
                      onChanged: (v) {
                        modalSetState(() {
                          showNarrativeMeta = v;
                        });
                        setState(() {
                          _showNarrativeMeta = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: monospaceNarrative,
                      title: const Text('Monospace output'),
                      subtitle: const Text(
                        'Render narrative/panels in monospace (better alignment)',
                      ),
                      onChanged: (v) {
                        modalSetState(() {
                          monospaceNarrative = v;
                        });
                        setState(() {
                          _monospaceNarrative = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: speechBubblesEnabled,
                      title: const Text('Speech bubbles'),
                      subtitle: const Text(
                        'Render say/chat events as speech bubbles',
                      ),
                      onChanged: (v) {
                        modalSetState(() {
                          speechBubblesEnabled = v;
                        });
                        setState(() {
                          _speechBubblesEnabled = v;
                        });
                      },
                    ),
                    SwitchListTile(
                      value: verbPaletteEnabled,
                      title: const Text('Verb palette'),
                      subtitle: Text(
                        _verbSuggestionsAvailable
                            ? 'Show quick verbs (server)'
                            : 'Show quick verbs (fallback)',
                      ),
                      onChanged: (v) {
                        modalSetState(() {
                          verbPaletteEnabled = v;
                        });
                        setState(() {
                          _verbPaletteEnabled = v;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Theme',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (s) {
                        final next = s.first;
                        modalSetState(() {
                          themeMode = next;
                        });
                        _ThemeScope.of(context).mode = next;
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    _ws?.close();
    _ws = null;
    _presentations.clear();
    setState(() {
      _editorSessions.clear();
      _editorPaneCache.clear();
      _activeEditorIndex = 0;
    });
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _buildDockItemCard(BuildContext context, DockItem p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: switch (p) {
          RoomSnapshotDockItem(:final snapshot) => RoomSnapshotWidget(
            snapshot: snapshot,
            onCommand: (cmd) {
              _ws?.sendText(cmd);
            },
            onInspect: (obj) => _showInspectSheet(obj.curie),
          ),
          PresentationModel() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (p.attrs['title'] ?? '').trim().isNotEmpty
                          ? p.attrs['title']!
                          : p.id,
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close panel',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await _dismissPresentationById(p.id);
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ContentRenderer(
                content: [p.content],
                contentType: normalizeContentType(p.contentType),
                isStale: false,
                onLinkTap: _handleLinkTap,
                monospace:
                    p.attrs['kind'] == 'debug_output' || _monospaceNarrative,
              ),
            ],
          ),
        },
      ),
    );
  }

  Widget _buildLeftPane(BuildContext context) {
    // Keep controller styling/placeholder in sync with theme and pill state.
    _inputCtrl
      ..verbPill = _verbPill
      ..verbPillPlaceholder = _verbPillPlaceholder
      ..placeholderColor = Theme.of(context).colorScheme.outline.withValues(
        alpha: 0.75,
      );

    return Column(
      children: [
        AnimatedBuilder(
          animation: _presentations,
          builder: (context, _) {
            final currentRoomKey = _roomHudEnabled ? _currentRoomLookKey : null;
            final suppressRoomKey = (!_isCurrentRoomLookDockLatched)
                ? currentRoomKey
                : null;

            final top = _presentations.byTarget('top');
            final filtered = <DockItem>[];
            for (final p in top) {
              if (p.target != 'top') {
                filtered.add(p);
                continue;
              }
              final roomKey = getRoomLookKeyFromDockItem(p);
              if (roomKey == null) {
                filtered.add(p);
                continue;
              }
              if (!_roomHudEnabled) {
                // When disabled, remove room-look presentations entirely.
                continue;
              }
              if (suppressRoomKey != null && roomKey == suppressRoomKey) {
                continue;
              }
              filtered.add(p);
            }

            if (filtered.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in filtered) _buildDockItemCard(context, p),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Builder(
                                builder: (context) {
                                  final groups = _groupNarrativeItems(_items);
                                  return SelectionArea(
                                    child: ListView.builder(
                                      key: _listKey,
                                      controller: _scrollCtrl,
                                      itemCount: groups.length,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      itemBuilder: (context, idx) {
                                        final group = groups[idx];
                                        final first = group.first;
                                        final cs = Theme.of(
                                          context,
                                        ).colorScheme;

                                        Widget buildMessage(NarrativeItem it) {
                                          final key = _messageKeys.putIfAbsent(
                                            it.id,
                                            GlobalKey.new,
                                          );
                                          final ts = it.timestamp
                                              .toIso8601String()
                                              .split('T')
                                              .last;
                                          return Container(
                                            key: key,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (_showNarrativeMeta) ...[
                                                  Row(
                                                    children: [
                                                      Text(
                                                        ts,
                                                        style: TextStyle(
                                                          fontFamily:
                                                              'monospace',
                                                          color: cs.outline,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        it.contentType,
                                                        style: TextStyle(
                                                          fontFamily:
                                                              'monospace',
                                                          color: cs.outline,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                ],
                                                if (_speechBubblesEnabled &&
                                                    it.presentationHint ==
                                                        'speech_bubble')
                                                  _buildSpeechBubbleMessage(
                                                    context,
                                                    it,
                                                    cs,
                                                  )
                                                else
                                                  ContentRenderer(
                                                    content: it.content,
                                                    contentType: it.contentType,
                                                    isStale: false,
                                                    onLinkTap: _handleLinkTap,
                                                    monospace:
                                                        _monospaceNarrative,
                                                  ),
                                              ],
                                            ),
                                          );
                                        }

                                        final hint = first.presentationHint;
                                        final isInset = hint == 'inset';
                                        final isHintGroup =
                                            hint != null &&
                                            first.groupId != null &&
                                            group.every(
                                              (m) =>
                                                  m.presentationHint == hint &&
                                                  m.groupId == first.groupId,
                                            );

                                        final inner = Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            for (final it in group)
                                              buildMessage(it),
                                          ],
                                        );

                                        if (!isInset) {
                                          if (group.length == 1 &&
                                              !isHintGroup) {
                                            return inner;
                                          }
                                          return inner;
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Semantics(
                                            container: true,
                                            label: 'Inset',
                                            child: Card(
                                              elevation: 0,
                                              color: cs.surfaceContainerLow,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                  color: cs.primary,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 6,
                                                    ),
                                                child: inner,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _presentations,
                        builder: (context, _) {
                          final side = _presentations.byTarget('right');
                          if (side.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return SizedBox(
                            width: 330,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
                              child: ListView(
                                children: [
                                  for (final p in side)
                                    _buildDockItemCard(context, p),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: VerbPaletteBar(
                      visible: _verbPaletteEnabled && _inputPrompt == null,
                      verbs: _paletteVerbs,
                      onSelect: _selectPaletteVerb,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _inputPrompt != null
                      ? _buildInputPromptComposer(context, _inputPrompt!)
                      : Row(
                          children: [
                            Expanded(
                              child: FocusTraversalOrder(
                                order: const NumericFocusOrder(3),
                                child: TextField(
                                  controller: _inputCtrl,
                                  autofocus: true,
                                  focusNode: _inputFocus,
                                  keyboardType: TextInputType.multiline,
                                  minLines: 1,
                                  maxLines: 6,
                                  decoration: InputDecoration(
                                    labelText: 'Command',
                                    hintText: _verbPill != null
                                        ? _verbPillPlaceholder
                                        : _serverPlaceholderText,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(4),
                              child: FilledButton(
                                onPressed: _send,
                                child: const Text('Send'),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _editorPaneForSession(EditorSession s) {
    return _editorPaneCache.putIfAbsent(s.presentationId, () {
      final authToken = widget.session.authToken;
      final baseUri = widget.session.baseUri;
      return switch (s) {
        VerbEditorSession(:final objectCurie, :final verbName) =>
          VerbEditorPane(
            key: ValueKey(s.presentationId),
            baseUri: baseUri,
            authToken: authToken,
            objectCurie: objectCurie,
            verbName: verbName,
          ),
        PropertyEditorSession(:final objectCurie, :final propertyName) =>
          PropertyEditorPane(
            key: ValueKey(s.presentationId),
            baseUri: baseUri,
            authToken: authToken,
            objectCurie: objectCurie,
            propertyName: propertyName,
          ),
      };
    });
  }

  Widget _buildEditorDock(BuildContext context) {
    if (_editorSessions.isEmpty) return const SizedBox.shrink();

    final activeIdx =
        (_activeEditorIndex >= 0 && _activeEditorIndex < _editorSessions.length)
        ? _activeEditorIndex
        : 0;
    final active = _editorSessions[activeIdx];

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 10, 12, 10),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < _editorSessions.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InputChip(
                              label: Text(
                                _editorSessions[i].title,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected: i == activeIdx,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() {
                                  _activeEditorIndex = i;
                                });
                              },
                              onDeleted: () async {
                                await _closeEditorSession(_editorSessions[i]);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fullscreen',
                  onPressed: () async {
                    await _openEditorFullscreen(active);
                  },
                  icon: const Icon(Icons.open_in_full),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () async {
                    await _closeEditorSession(active);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: IndexedStack(
              index: activeIdx,
              children: [
                for (final s in _editorSessions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _editorPaneForSession(s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('$_mooTitle ($_status)'),
        actions: [
          IconButton(
            onPressed: _toggleDebugPanel,
            tooltip: _debugPanelVisible
                ? 'Hide debug panel'
                : 'Show debug panel',
            icon: Icon(
              _debugPanelVisible ? Icons.bug_report : Icons.bug_report_outlined,
            ),
          ),
          IconButton(
            onPressed: _showSettingsSheet,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
          ),
          PopupMenuButton<_AccountAction>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (a) async {
              switch (a) {
                case _AccountAction.historyEncryption:
                  await _showEncryptionMenu();
                case _AccountAction.logout:
                  await _logout();
              }
            },
            itemBuilder: (context) {
              return [
                PopupMenuItem<_AccountAction>(
                  enabled: false,
                  child: Text(
                    widget.session.playerCurie,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<_AccountAction>(
                  value: _AccountAction.historyEncryption,
                  child: Text('History encryption'),
                ),
                const PopupMenuItem<_AccountAction>(
                  value: _AccountAction.logout,
                  child: Text('Logout'),
                ),
              ];
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_editorSessions.isEmpty) {
            return _buildLeftPane(context);
          }

          final w = constraints.maxWidth;
          const minDock = 360.0;
          const minLeft = 520.0;
          const dividerW = 10.0;

          var leftW = w * _splitRatio;
          if (leftW < minLeft) leftW = minLeft;
          if (w - leftW - dividerW < minDock) {
            leftW = w - minDock - dividerW;
          }
          if (leftW < minLeft) leftW = minLeft;
          if (leftW > w - dividerW) leftW = w - dividerW;

          return Row(
            children: [
              SizedBox(
                width: leftW,
                child: _buildLeftPane(context),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) {
                    final currentLeft = w * _splitRatio;
                    final nextLeft = (currentLeft + d.delta.dx).clamp(
                      minLeft,
                      w - minDock - dividerW,
                    );
                    setState(() {
                      _splitRatio = nextLeft / w;
                    });
                  },
                  child: SizedBox(
                    width: dividerW,
                    child: Center(
                      child: Container(
                        width: 3,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildEditorDock(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SpeechBubbleTailPainter extends CustomPainter {
  final Color color;
  final bool isSelf;

  const _SpeechBubbleTailPainter({
    required this.color,
    required this.isSelf,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final path = Path();
    if (isSelf) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, 0);
    }
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _SpeechBubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isSelf != isSelf;
  }
}

enum _AccountAction {
  historyEncryption,
  logout,
}
