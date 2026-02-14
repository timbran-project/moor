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
import 'package:meadow_flutter/moor/args.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/ws_client.dart';
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
          builder: (_) => SessionScreen(session: session, mode: _mode),
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
  MoorWsClient? _ws;
  String _status = 'disconnected';

  static const int _maxCommandHistory = 500;

  // Command history: 0 = current input, 1 = most recent command, etc.
  final List<String> _commandHistory = [];
  final Map<int, String> _historyBuffer = {};
  int _historyOffset = 0;

  @override
  void initState() {
    super.initState();
    _connectWs();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _ws?.close();
    super.dispose();
  }

  Future<void> _connectWs() async {
    setState(() {
      _status = 'connecting';
    });

    final ws = MoorWsClient(
      session: widget.session,
      onSystemMessage: _appendSystem,
      onNarrativeItem: _appendItem,
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

  void _appendSystem(String m) {
    _appendItem(
      NarrativeItem(
        timestamp: DateTime.now(),
        content: ['[system] $m'],
        contentType: 'text/plain',
        noNewline: false,
      ),
    );
  }

  void _appendItem(NarrativeItem it) {
    setState(() {
      _items.add(it);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.session.playerCurie} ($_status)'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: _items.length,
              itemBuilder: (context, idx) {
                final it = _items[idx];
                final ts = it.timestamp.toIso8601String().split('T').last;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            ts,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            it.contentType,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Theme.of(context).colorScheme.outline,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
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
