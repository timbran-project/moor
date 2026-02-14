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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/age_decrypt.dart';
import 'package:meadow_flutter/moor/args.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/content_type.dart';
import 'package:meadow_flutter/moor/event_log_encryption.dart';
import 'package:meadow_flutter/moor/event_log_keystore.dart';
import 'package:meadow_flutter/moor/flatbuffers_util.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/ws_client.dart';
import 'package:meadow_flutter/widgets/room_snapshot_widget.dart';
import 'package:url_launcher/url_launcher.dart';

void main(List<String> args) {
  final launchArgs = parseLaunchArgs(args);
  runApp(MeadowApp(launchArgs: launchArgs));
}

class MeadowApp extends StatelessWidget {
  final LaunchArgs launchArgs;

  const MeadowApp({
    super.key,
    required this.launchArgs,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meadow (Flutter Spike)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B3B2E)),
        useMaterial3: true,
      ),
      home: LoginScreen(launchArgs: launchArgs),
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
  WelcomeMessage? _welcome;
  String? _error;
  bool _loadingWelcome = false;
  bool _loggingIn = false;

  @override
  void initState() {
    super.initState();

    final a = widget.launchArgs;
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
    // Normalize: strip path/query/fragment.
    return u.replace(path: '', query: '', fragment: '');
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
      final msg = await api.fetchWelcomeMessage();
      if (!mounted) return;
      setState(() {
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
        title: const Text('Meadow (Flutter Spike)'),
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

  const SessionScreen({
    super.key,
    required this.session,
    required this.mode,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final FocusNode _inputFocus = FocusNode(onKeyEvent: _handleCommandKey);

  final _items = <NarrativeItem>[];
  final _presentations = PresentationStore();
  final GlobalKey _listKey = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};

  String? _currentRoomLookKey;
  String? _currentRoomLookMessageId;
  bool _isCurrentRoomLookDockLatched = false;
  final _latestLookMessageIdByRoom = <String, String>{};

  bool _roomHudEnabled = true;
  bool _showNarrativeMeta = true;

  int _idSeq = 0;
  MoorWsClient? _ws;
  String _status = 'disconnected';

  static const int _maxCommandHistory = 500;

  bool _eventLogBackendHasPubkey = false;
  bool _eventLogHasLocalKey = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;

  // Command history: 0 = current input, 1 = most recent command, etc.
  final List<String> _commandHistory = [];
  final Map<int, String> _historyBuffer = {};
  int _historyOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _presentations.addListener(_onPresentationsChanged);
    _connectWs();
    _initEncryption();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _presentations
      ..removeListener(_onPresentationsChanged)
      ..dispose();
    _ws?.close();
    super.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
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

    final targetTop = targetBox.localToGlobal(Offset.zero).dy;
    final listTop = listBox.localToGlobal(Offset.zero).dy;
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
    );
    _ws = ws;

    try {
      await ws.connect(mode: widget.mode);
      if (!mounted) return;
      setState(() {
        _status = 'connected';
      });
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
      for (final ev in events) {
        final decrypted = await decryptEventBlobAge(ev.encryptedBlob, identity);
        final parsed = _parseNarrativeEnvelope(decrypted);
        if (parsed == null) {
          continue;
        }
        items.add(parsed);
      }

      if (!mounted) return;
      setState(() {
        _items.insertAll(0, items);
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

    final ts = DateTime.fromMillisecondsSinceEpoch(
      (evt.timestamp / 1000000).toInt(),
      isUtc: true,
    ).toLocal();

    final eventType = e.eventType?.value ?? 0;
    if (eventType == moor_common.EventUnionTypeId.NotifyEvent.value) {
      final notify = e.event as moor_common.NotifyEvent?;
      if (notify == null) {
        return null;
      }
      final lines = decodeVarAsLines(notify.value);
      if (lines.isEmpty) return null;
      final ct = normalizeContentType(notify.contentType?.value);
      return NarrativeItem(
        id: _newId('h'),
        timestamp: ts,
        content: lines,
        contentType: ct,
        noNewline: notify.noNewline,
        presentationHint: null,
        eventMetadata: null,
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
        eventMetadata: null,
      );
    }

    if (eventType == moor_common.EventUnionTypeId.TracebackEvent.value) {
      final tb = e.event as moor_common.TracebackEvent?;
      final ex = tb?.exception;
      final bt = ex?.backtrace;
      if (bt == null) return null;
      final lines = <String>[];
      for (final v in bt) {
        final s = decodeVarAsLines(v);
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
        eventMetadata: null,
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
    _appendItem(
      NarrativeItem(
        id: _newId('s'),
        timestamp: DateTime.now(),
        content: ['[system] $m'],
        contentType: 'text/plain',
        noNewline: false,
        presentationHint: null,
        eventMetadata: null,
      ),
    );
  }

  void _appendItem(NarrativeItem it) {
    final roomKey = getRoomLookKeyFromNarrative(
      presentationHint: it.presentationHint,
      eventMetadata: it.eventMetadata,
    );
    if (roomKey != null) {
      _latestLookMessageIdByRoom[roomKey] = it.id;
    }

    setState(() {
      _items.add(it);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  void _send() {
    final input = _inputCtrl.text;
    if (input.trim().isEmpty) {
      return;
    }

    final commandsSent = <String>[];
    for (final line in input.split('\n')) {
      final cmd = line.trim();
      if (cmd.isEmpty) continue;
      commandsSent.add(cmd);
      _ws?.sendText(cmd);
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
    _inputCtrl.clear();

    // Keep focus in the input field after sending (desktop UX).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
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

    final currentText = _inputCtrl.text;
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

    return KeyEventResult.ignored;
  }

  Future<void> _handleLinkTap(String url) async {
    if (url.startsWith('moo://cmd/')) {
      final cmd = Uri.decodeComponent(url.substring('moo://cmd/'.length));
      _ws?.sendText(cmd);
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
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('${widget.session.playerCurie} ($_status)'),
        actions: [
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
      body: Column(
        children: [
          AnimatedBuilder(
            animation: _presentations,
            builder: (context, _) {
              final currentRoomKey = _roomHudEnabled
                  ? _currentRoomLookKey
                  : null;
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
                    for (final p in filtered)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: switch (p) {
                            RoomSnapshotDockItem(:final snapshot) =>
                              RoomSnapshotWidget(
                                snapshot: snapshot,
                                onCommand: (cmd) {
                                  _ws?.sendText(cmd);
                                },
                                onInspect: (obj) {
                                  _appendSystem('inspect: ${obj.curie}');
                                },
                              ),
                            PresentationModel() => ContentRenderer(
                              content: [p.content],
                              contentType: normalizeContentType(p.contentType),
                              isStale: false,
                              onLinkTap: _handleLinkTap,
                            ),
                          },
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  key: _listKey,
                  controller: _scrollCtrl,
                  itemCount: _items.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, idx) {
                    final it = _items[idx];
                    final key = _messageKeys.putIfAbsent(it.id, GlobalKey.new);
                    final ts = it.timestamp.toIso8601String().split('T').last;
                    return Container(
                      key: key,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_showNarrativeMeta) ...[
                            Row(
                              children: [
                                Text(
                                  ts,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  it.contentType,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                          ],
                          ContentRenderer(
                            content: it.content,
                            contentType: it.contentType,
                            isStale: false,
                            onLinkTap: _handleLinkTap,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    autofocus: true,
                    focusNode: _inputFocus,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Command',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AccountAction {
  historyEncryption,
  logout,
}
