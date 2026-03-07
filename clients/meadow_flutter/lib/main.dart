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
import 'package:meadow_flutter/moor/editor_session_controller.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/event_log_encryption.dart';
import 'package:meadow_flutter/moor/event_log_keystore.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/inspect_controller.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_metadata.dart';
import 'package:meadow_flutter/moor/narrative_tracker.dart';
import 'package:meadow_flutter/moor/oauth2_pkce.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';
import 'package:meadow_flutter/moor/ws_client.dart';
import 'package:meadow_flutter/theme/app_theme.dart';
import 'package:meadow_flutter/widgets/input_prompt_composer.dart';
import 'package:meadow_flutter/widgets/property_editor.dart';
import 'package:meadow_flutter/widgets/session_command_controller.dart';
import 'package:meadow_flutter/widgets/session_command_input_bar.dart';
import 'package:meadow_flutter/widgets/session_dock_item_card.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_narrative_list.dart';
import 'package:meadow_flutter/widgets/session_settings_sheet.dart';
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
  final _handoffCodeCtrl = TextEditingController();
  final _oauthCreateNameCtrl = TextEditingController();
  final _oauthLinkUserCtrl = TextEditingController();
  final _oauthLinkPassCtrl = TextEditingController();

  String _mode = 'connect';
  String _mooTitle = 'mooR';
  WelcomeMessage? _welcome;
  String? _error;
  bool _loadingWelcome = false;
  bool _loggingIn = false;
  bool _loadingOAuth2Config = false;
  bool _oauth2Busy = false;
  bool _oauth2Enabled = false;
  List<String> _oauth2Providers = const <String>[];
  String? _oauth2CodeVerifier;
  String? _oauth2IdentityCode;
  OAuth2AppIdentity? _oauth2Identity;
  String _oauth2AccountMode = 'oauth2_create';

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
    _consumeOAuth2CallbackFromUri();

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
    _handoffCodeCtrl.dispose();
    _oauthCreateNameCtrl.dispose();
    _oauthLinkUserCtrl.dispose();
    _oauthLinkPassCtrl.dispose();
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
      if (!_loadingOAuth2Config) {
        _loadingOAuth2Config = true;
        try {
          final oauthCfg = await api.fetchOAuth2Config();
          if (mounted) {
            setState(() {
              _oauth2Enabled = oauthCfg.enabled;
              _oauth2Providers = oauthCfg.providers;
            });
          }
        } on Object {
          if (mounted) {
            setState(() {
              _oauth2Enabled = false;
              _oauth2Providers = const <String>[];
            });
          }
        } finally {
          _loadingOAuth2Config = false;
        }
      }
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

  void _consumeOAuth2CallbackFromUri() {
    final q = Uri.base.queryParameters;
    final handoff = q['handoff_code']?.trim();
    if (handoff != null && handoff.isNotEmpty) {
      _handoffCodeCtrl.text = handoff;
    }
    final err = q['error']?.trim();
    if (err != null && err.isNotEmpty) {
      final details = q['details']?.trim();
      setState(() {
        _error = details == null || details.isEmpty
            ? 'OAuth2 error: $err'
            : 'OAuth2 error: $err ($details)';
      });
    }
  }

  String _oauth2RedirectUri() {
    if (kIsWeb) {
      final u = Uri.base;
      return Uri(
        scheme: u.scheme,
        userInfo: u.userInfo,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: u.path,
      ).toString();
    }
    return 'moor://oauth/callback';
  }

  Future<void> _navigateToSession({
    required LoginSession session,
    required String mode,
  }) async {
    if (!mounted) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          session: session,
          mode: mode,
          initialMooTitle: _mooTitle,
        ),
      ),
    );
  }

  Future<void> _startOAuth2ProofBound(String provider) async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _error = 'Invalid base URL';
      });
      return;
    }

    setState(() {
      _oauth2Busy = true;
      _error = null;
      _oauth2IdentityCode = null;
      _oauth2Identity = null;
      _oauth2AccountMode = 'oauth2_create';
      _handoffCodeCtrl.clear();
    });

    try {
      final api = MoorHttpApi(baseUri);
      final pkce = await generatePkcePair();
      final start = await api.oauth2AppStart(
        provider: provider,
        redirectUri: _oauth2RedirectUri(),
        codeChallenge: pkce.codeChallenge,
        codeChallengeMethod: pkce.codeChallengeMethod,
        intent: 'connect',
      );
      _oauth2CodeVerifier = pkce.codeVerifier;

      await launchUrl(start.authUrl, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _oauth2Busy = false;
        });
      }
    }
  }

  Future<void> _exchangeOAuth2HandoffCode() async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _error = 'Invalid base URL';
      });
      return;
    }
    final handoff = _handoffCodeCtrl.text.trim();
    final verifier = _oauth2CodeVerifier;
    if (handoff.isEmpty) {
      setState(() {
        _error = 'Missing handoff code';
      });
      return;
    }
    if (verifier == null || verifier.isEmpty) {
      setState(() {
        _error = 'OAuth2 session expired; start OAuth2 again';
      });
      return;
    }

    setState(() {
      _oauth2Busy = true;
      _error = null;
    });
    try {
      final api = MoorHttpApi(baseUri);
      final result = await api.oauth2AppExchange(
        handoffCode: handoff,
        codeVerifier: verifier,
      );

      if (result is OAuth2AppAuthSession) {
        final session = LoginSession(
          baseUri: baseUri,
          authToken: result.authToken,
          playerCurie: result.playerCurie,
          playerFlags: result.playerFlags,
          clientToken: result.clientToken,
          clientId: result.clientId,
          isInitialAttach: false,
        );
        await _navigateToSession(session: session, mode: 'connect');
        return;
      }

      if (result is OAuth2AppIdentity) {
        if (!mounted) return;
        setState(() {
          _oauth2IdentityCode = result.identityCode;
          _oauth2Identity = result;
          _oauthCreateNameCtrl.text = (result.name?.trim().isNotEmpty ?? false)
              ? result.name!.trim()
              : ((result.username?.trim().isNotEmpty ?? false)
                    ? result.username!.trim()
                    : '');
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _oauth2Busy = false;
        });
      }
    }
  }

  Future<void> _submitOAuth2AccountChoice() async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _error = 'Invalid base URL';
      });
      return;
    }
    final verifier = _oauth2CodeVerifier;
    final identityCode = _oauth2IdentityCode;
    if (verifier == null || verifier.isEmpty || identityCode == null) {
      setState(() {
        _error = 'OAuth2 identity flow expired; start again';
      });
      return;
    }

    final isCreate = _oauth2AccountMode == 'oauth2_create';
    final playerName = _oauthCreateNameCtrl.text.trim();
    final existingUser = _oauthLinkUserCtrl.text.trim();
    final existingPassword = _oauthLinkPassCtrl.text;

    if (isCreate && playerName.isEmpty) {
      setState(() {
        _error = 'Missing player name';
      });
      return;
    }
    if (!isCreate && (existingUser.isEmpty || existingPassword.isEmpty)) {
      setState(() {
        _error = 'Missing existing account credentials';
      });
      return;
    }

    setState(() {
      _oauth2Busy = true;
      _error = null;
    });
    try {
      final api = MoorHttpApi(baseUri);
      final result = await api.oauth2AppAccountChoice(
        mode: _oauth2AccountMode,
        identityCode: identityCode,
        codeVerifier: verifier,
        playerName: isCreate ? playerName : null,
        existingEmail: isCreate ? null : existingUser,
        existingPassword: isCreate ? null : existingPassword,
      );

      if (!result.success ||
          result.authToken == null ||
          result.playerCurie == null ||
          result.playerFlags == null) {
        throw Exception(result.error ?? 'OAuth2 account choice failed');
      }

      final session = LoginSession(
        baseUri: baseUri,
        authToken: result.authToken!,
        playerCurie: result.playerCurie!,
        playerFlags: result.playerFlags!,
        clientToken: result.clientToken,
        clientId: result.clientId,
        isInitialAttach: false,
      );
      await _navigateToSession(
        session: session,
        mode: isCreate ? 'create' : 'connect',
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _oauth2Busy = false;
        });
      }
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
            FilledButton(
              onPressed: _loggingIn ? null : _login,
              child: Text(_loggingIn ? 'Logging in...' : 'Login'),
            ),
            if (_oauth2Enabled && _oauth2Providers.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'OAuth2 login',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final provider in _oauth2Providers)
                    OutlinedButton(
                      onPressed: _oauth2Busy
                          ? null
                          : () => _startOAuth2ProofBound(provider),
                      child: Text('Continue with $provider'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'After provider login, paste handoff code if callback does not return here automatically.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _handoffCodeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Handoff code',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _oauth2Busy ? null : _exchangeOAuth2HandoffCode,
                    child: Text(_oauth2Busy ? 'Working...' : 'Exchange'),
                  ),
                ],
              ),
              if (_oauth2IdentityCode != null && _oauth2Identity != null) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Complete OAuth2 account setup (${_oauth2Identity!.provider})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'oauth2_create',
                              label: Text('Create'),
                            ),
                            ButtonSegment(
                              value: 'oauth2_connect',
                              label: Text('Link'),
                            ),
                          ],
                          selected: {_oauth2AccountMode},
                          onSelectionChanged: (s) {
                            setState(() {
                              _oauth2AccountMode = s.first;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        if (_oauth2AccountMode == 'oauth2_create')
                          TextField(
                            controller: _oauthCreateNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Player name',
                            ),
                          )
                        else ...[
                          TextField(
                            controller: _oauthLinkUserCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Existing username/email',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _oauthLinkPassCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Existing password',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _oauth2Busy
                              ? null
                              : _submitOAuth2AccountChoice,
                          child: Text(
                            _oauth2Busy
                                ? 'Working...'
                                : (_oauth2AccountMode == 'oauth2_create'
                                      ? 'Create account'
                                      : 'Link account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
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
  final _promptCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final SessionCommandController _commandController =
      SessionCommandController();
  late final InspectController _inspectController = InspectController(
    invokeVerb: _invokeInspectVerb,
    newId: _newId,
  );
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
  final _narrativeTracker = NarrativeTracker();

  bool _roomHudEnabled = true;
  bool _showNarrativeMeta = false;
  bool _verbPaletteEnabled = true;
  bool _monospaceNarrative = false;

  double _splitRatio = 0.64;

  late final EditorSessionController _editorSessionController =
      EditorSessionController();
  final Map<String, Widget> _editorPaneCache = <String, Widget>{};

  int _idSeq = 0;
  MoorWsClient? _ws;
  String _status = 'disconnected';
  String _mooTitle = 'mooR';

  bool _eventLogBackendHasPubkey = false;
  bool _eventLogHasLocalKey = false;
  bool _historyLoading = false;
  bool _historyLoaded = false;
  bool _wasWsConnected = false;
  InputPromptRequest? _inputPrompt;

  @override
  void initState() {
    super.initState();
    _mooTitle = widget.initialMooTitle;
    _scrollCtrl.addListener(_onScroll);
    _presentations.addListener(_onPresentationsChanged);
    _commandController.onPillCleared = () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputFocus.requestFocus();
      });
    };
    _commandController.onPillSelected = () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _inputFocus.requestFocus();
      });
    };
    _commandController.addListener(_onCommandControllerChanged);
    _editorSessionController.addListener(_onEditorSessionsChanged);
    _connectWs();
    _initEncryption();
    _refreshVerbSuggestions();
    _refreshMooTitle();
  }

  @override
  void dispose() {
    _promptFocus.dispose();
    _promptCtrl.dispose();
    _commandController
      ..removeListener(_onCommandControllerChanged)
      ..dispose();
    _editorSessionController
      ..removeListener(_onEditorSessionsChanged)
      ..dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _presentations
      ..removeListener(_onPresentationsChanged)
      ..dispose();
    _ws?.close();
    super.dispose();
  }

  void _onCommandControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onEditorSessionsChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
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
    _editorSessionController.syncFromPresentations(
      _presentations,
      onSystemMessage: _appendSystem,
    );
    final nextPids = _editorSessionController.sessions
        .map((session) => session.presentationId)
        .toSet();
    final toRemove = _editorPaneCache.keys
        .where((pid) => !nextPids.contains(pid))
        .toList();
    for (final pid in toRemove) {
      _editorPaneCache.remove(pid);
    }
  }

  Future<void> _closeEditorSession(EditorSession s) async {
    await _dismissPresentationById(s.presentationId);

    if (!mounted) return;
    setState(() {
      _editorPaneCache.remove(s.presentationId);
      _editorSessionController.removePresentationId(s.presentationId);
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

    final msgId = _narrativeTracker.latestLookMessageIdForRoom(roomKey);
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
        final alreadySeen = _narrativeTracker.batchContains(
          item: parsed,
          batchEventIds: batchEventIds,
          batchDedupKeys: batchDedupKeys,
        );
        if (alreadySeen) {
          continue;
        }
        _narrativeTracker.rememberBatch(
          parsed,
          batchEventIds: batchEventIds,
          batchDedupKeys: batchDedupKeys,
        );
        items.add(parsed);
      }

      if (!mounted) return;
      setState(() {
        _items.insertAll(0, items);
        for (final item in items) {
          _narrativeTracker.remember(item);
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
    if (_narrativeTracker.contains(it)) {
      return;
    }

    setState(() {
      _items.add(it);
      _narrativeTracker.remember(it);
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

  void _send() {
    final commandsSent = _commandController.consumeCommandsToSend();
    if (commandsSent.isEmpty) {
      return;
    }

    for (final cmd in commandsSent) {
      _ws?.sendText(cmd);
    }

    // Keep focus in the input field after sending (desktop UX).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });

    _refreshVerbSuggestions();
  }

  KeyEventResult _handleCommandKey(FocusNode node, KeyEvent event) {
    return _commandController.handleKeyEvent(event, onSend: _send);
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
    InspectData? inspectData;
    try {
      inspectData = await _inspectController.loadInspectData(
        objectCurie,
        onDebug: _appendSystem,
      );
      if (inspectData == null) {
        _appendSystem('No inspect data available for $objectCurie');
        return;
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
    try {
      final result = await _inspectController.runAction(
        action,
        promptForInput: _promptInspectActionInput,
        onDebug: _appendSystem,
      );
      if (result.canceled) {
        return;
      }
      final commandToSend = result.commandToSend;
      if (commandToSend != null && commandToSend.trim().isNotEmpty) {
        _ws?.sendText(commandToSend);
      }
      final panelPresentation = result.panelPresentation;
      if (panelPresentation != null) {
        _presentations.upsert(panelPresentation);
      }
      for (final line in result.narrativeLines) {
        _appendNarrativeText(line);
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

  Future<InspectVerbResponse> _invokeInspectVerb({
    required String objectCurie,
    required String verbName,
    Uint8List? argsVarBytes,
  }) async {
    final api = MoorHttpApi(widget.session.baseUri);
    final success = await api.invokeVerb(
      authToken: widget.session.authToken,
      objectCurie: objectCurie,
      verbName: verbName,
      argsVarBytes: argsVarBytes,
    );
    final result = success.result != null
        ? MoorVar.fromFlatBuffer(success.result!)
        : moorNoneVar;
    final eventTypes =
        success.output
            ?.map((evt) => evt.event?.eventType?.value ?? -1)
            .toList() ??
        const <int>[];
    return InspectVerbResponse(
      result: result,
      outputLines: _extractInvokeOutputLines(success.output),
      eventTypes: eventTypes,
    );
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
      _commandController.updateVerbSuggestions(
        // "available" in Meadow web means the verb exists and returned a list,
        // even if it's empty.
        suggestionsAvailable: decoded.asList() != null,
        serverPlaceholderText: placeholder?.placeholderText,
        paletteVerbs: verbs,
      );

      if (!decoded.isNone() && suggestions.isEmpty) {
        _appendSystem(
          'verb_suggestions returned no suggestions (decoded=${decoded.toLiteral()})',
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      _appendSystem('verb_suggestions fetch failed: $e');
      _commandController.updateVerbSuggestions(
        suggestionsAvailable: false,
        serverPlaceholderText: null,
        paletteVerbs: paletteVerbsFallback,
      );
    }
  }

  void _selectPaletteVerb(PaletteVerb v) {
    _commandController.selectPaletteVerb(v);
  }

  Future<void> _showSettingsSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SessionSettingsSheet(
          initialSettings: SessionViewSettings(
            roomHudEnabled: _roomHudEnabled,
            showNarrativeMeta: _showNarrativeMeta,
            verbPaletteEnabled: _verbPaletteEnabled,
            monospaceNarrative: _monospaceNarrative,
            verbSuggestionsAvailable:
                _commandController.verbSuggestionsAvailable,
            themeMode: _ThemeScope.of(context).mode,
          ),
          onSettingsChanged: (settings) {
            setState(() {
              _roomHudEnabled = settings.roomHudEnabled;
              _showNarrativeMeta = settings.showNarrativeMeta;
              _verbPaletteEnabled = settings.verbPaletteEnabled;
              _monospaceNarrative = settings.monospaceNarrative;
            });
            _onPresentationsChanged();
          },
          onThemeModeChanged: (mode) {
            _ThemeScope.of(context).mode = mode;
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
      _editorSessionController.clear();
      _editorPaneCache.clear();
    });
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _buildLeftPane(BuildContext context) {
    // Keep controller styling/placeholder in sync with theme and pill state.
    _commandController.placeholderColor = Theme.of(
      context,
    ).colorScheme.outline.withValues(alpha: 0.75);

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
                  for (final p in filtered)
                    SessionDockItemCard(
                      item: p,
                      monospaceNarrative: _monospaceNarrative,
                      onDismissPresentation: _dismissPresentationById,
                      onInspect: _showInspectSheet,
                      onSendCommand: (cmd) {
                        _ws?.sendText(cmd);
                      },
                      onLinkTap: _handleLinkTap,
                    ),
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
                              child: SessionNarrativeList(
                                items: _items,
                                monospaceNarrative: _monospaceNarrative,
                                showNarrativeMeta: _showNarrativeMeta,
                                playerCurie: widget.session.playerCurie,
                                scrollController: _scrollCtrl,
                                listKey: _listKey,
                                messageKeys: _messageKeys,
                                onLinkTap: _handleLinkTap,
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
                                    SessionDockItemCard(
                                      item: p,
                                      monospaceNarrative: _monospaceNarrative,
                                      onDismissPresentation:
                                          _dismissPresentationById,
                                      onInspect: _showInspectSheet,
                                      onSendCommand: (cmd) {
                                        _ws?.sendText(cmd);
                                      },
                                      onLinkTap: _handleLinkTap,
                                    ),
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
                      verbs: _commandController.paletteVerbs,
                      onSelect: _selectPaletteVerb,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _inputPrompt != null
                      ? InputPromptComposer(
                          request: _inputPrompt!,
                          controller: _promptCtrl,
                          focusNode: _promptFocus,
                          monospaceNarrative: _monospaceNarrative,
                          onLinkTap: _handleLinkTap,
                          onSubmit: _submitInputPromptValue,
                        )
                      : SessionCommandInputBar(
                          controller: _commandController.inputController,
                          focusNode: _inputFocus,
                          verbPill: _commandController.verbPill,
                          verbPillPlaceholder:
                              _commandController.verbPillPlaceholder,
                          serverPlaceholderText:
                              _commandController.serverPlaceholderText,
                          onSend: _send,
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
          final editorSessions = _editorSessionController.sessions;

          if (editorSessions.isEmpty) {
            return _buildLeftPane(context);
          }

          final w = constraints.maxWidth;
          const minDock = 360.0;
          const minLeft = 520.0;
          const dividerW = 10.0;
          const compactBreakpoint = minLeft + minDock + dividerW;

          if (w < compactBreakpoint) {
            final editorHeight = (constraints.maxHeight * 0.46).clamp(
              320.0,
              constraints.maxHeight - 180,
            );
            return Column(
              children: [
                Expanded(
                  child: _buildLeftPane(context),
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                SizedBox(
                  height: editorHeight,
                  child: SessionEditorDock(
                    sessions: editorSessions,
                    activeIndex: _editorSessionController.activeIndex,
                    onSelectIndex: _editorSessionController.selectIndex,
                    onCloseSession: _closeEditorSession,
                    onOpenFullscreen: _openEditorFullscreen,
                    paneBuilder: _editorPaneForSession,
                  ),
                ),
              ],
            );
          }

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
                child: SessionEditorDock(
                  sessions: editorSessions,
                  activeIndex: _editorSessionController.activeIndex,
                  onSelectIndex: _editorSessionController.selectIndex,
                  onCloseSession: _closeEditorSession,
                  onOpenFullscreen: _openEditorFullscreen,
                  paneBuilder: _editorPaneForSession,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _AccountAction {
  historyEncryption,
  logout,
}
