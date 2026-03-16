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
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/moor/account_profile_controller.dart';
import 'package:meadow_flutter/moor/age_decrypt.dart';
import 'package:meadow_flutter/moor/args.dart';
import 'package:meadow_flutter/moor/content_renderer.dart';
import 'package:meadow_flutter/moor/debug_panel_controller.dart';
import 'package:meadow_flutter/moor/editor_session_controller.dart';
import 'package:meadow_flutter/moor/editor_sessions.dart';
import 'package:meadow_flutter/moor/event_log_encryption.dart';
import 'package:meadow_flutter/moor/event_log_keystore.dart';
import 'package:meadow_flutter/moor/history_encryption_controller.dart';
import 'package:meadow_flutter/moor/history_export_controller.dart';
import 'package:meadow_flutter/moor/history_loader.dart';
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/input_prompt.dart';
import 'package:meadow_flutter/moor/input_prompt_controller.dart';
import 'package:meadow_flutter/moor/inspect.dart';
import 'package:meadow_flutter/moor/inspect_controller.dart';
import 'package:meadow_flutter/moor/models.dart';
import 'package:meadow_flutter/moor/narrative_feed_controller.dart';
import 'package:meadow_flutter/moor/oauth2_pending_flow_store.dart';
import 'package:meadow_flutter/moor/oauth2_pkce.dart';
import 'package:meadow_flutter/moor/object_browser_controller.dart';
import 'package:meadow_flutter/moor/presentations.dart';
import 'package:meadow_flutter/moor/room_look_controller.dart';
import 'package:meadow_flutter/moor/session_bootstrap.dart';
import 'package:meadow_flutter/moor/session_connection_controller.dart';
import 'package:meadow_flutter/moor/session_view_controller.dart';
import 'package:meadow_flutter/moor/trusted_external_domains.dart';
import 'package:meadow_flutter/moor/types/moor_var.dart';
import 'package:meadow_flutter/moor/types/moor_var_ext.dart';
import 'package:meadow_flutter/moor/verb_palette.dart';
import 'package:meadow_flutter/moor/web_navigation_stub.dart'
    if (dart.library.js_interop) 'package:meadow_flutter/moor/web_navigation_web.dart';
import 'package:meadow_flutter/theme/app_theme.dart';
import 'package:meadow_flutter/widgets/account_sheet.dart';
import 'package:meadow_flutter/widgets/input_prompt_composer.dart';
import 'package:meadow_flutter/widgets/object_browser_sheet.dart';
import 'package:meadow_flutter/widgets/session_app_bar_actions.dart';
import 'package:meadow_flutter/widgets/session_command_controller.dart';
import 'package:meadow_flutter/widgets/session_command_input_bar.dart';
import 'package:meadow_flutter/widgets/session_dialogs.dart';
import 'package:meadow_flutter/widgets/session_dock_item_card.dart';
import 'package:meadow_flutter/widgets/session_editor_dock.dart';
import 'package:meadow_flutter/widgets/session_editor_presenter.dart';
import 'package:meadow_flutter/widgets/session_narrative_list.dart';
import 'package:meadow_flutter/widgets/session_settings_sheet.dart';
import 'package:meadow_flutter/widgets/verb_palette_bar.dart';
import 'package:url_launcher/url_launcher.dart';

void main(List<String> args) {
  final launchArgs = parseLaunchArgs(args);
  runApp(MeadowApp(launchArgs: launchArgs));
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
}

const _webDefaultServer = String.fromEnvironment('MOOR_DEFAULT_SERVER');

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
            title: 'The Timbran',
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
  bool _oauth2AutoExchangePending = false;
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
      _baseUrlCtrl.text = _webDefaultServer.trim().isNotEmpty
          ? _webDefaultServer.trim()
          : Uri.base.origin;
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
    unawaited(_restorePendingOAuth2Flow());

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

  Future<void> _restorePendingOAuth2Flow() async {
    debugPrint('[oauth-debug] restore begin');
    final pending = await OAuth2PendingFlowStore.load();
    if (!mounted) {
      debugPrint('[oauth-debug] restore aborted unmounted');
      return;
    }
    if (pending != null) {
      _oauth2CodeVerifier = pending.codeVerifier;
      debugPrint(
        '[oauth-debug] restore verifier hit len=${pending.codeVerifier.length}',
      );
      if (_baseUrlCtrl.text.trim().isEmpty ||
          _baseUrlCtrl.text.trim() == 'http://localhost:8080') {
        _baseUrlCtrl.text = pending.baseUrl;
        debugPrint('[oauth-debug] restore base url ${pending.baseUrl}');
      }
    } else {
      debugPrint('[oauth-debug] restore verifier miss');
    }
    _consumeOAuth2Callback();
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

  void _consumeOAuth2Callback() {
    final callbackUri = widget.launchArgs.callbackUri ?? Uri.base;
    debugPrint(
      '[oauth-debug] consume callback source='
      '${widget.launchArgs.callbackUri != null ? 'launch-arg' : 'uri-base'} '
      'uri=$callbackUri',
    );
    final q = callbackUri.queryParameters;
    final handoff = q['handoff_code']?.trim();
    if (handoff != null && handoff.isNotEmpty) {
      _handoffCodeCtrl.text = handoff;
      _oauth2AutoExchangePending = true;
      debugPrint(
        '[oauth-debug] consume callback handoff len=${handoff.length} auto=true',
      );
    }
    final err = q['error']?.trim();
    if (err != null && err.isNotEmpty) {
      final details = q['details']?.trim();
      setState(() {
        _error = details == null || details.isEmpty
            ? 'OAuth2 error: $err'
            : 'OAuth2 error: $err ($details)';
      });
      return;
    }
    if (_oauth2AutoExchangePending &&
        _handoffCodeCtrl.text.trim().isNotEmpty &&
        (_oauth2CodeVerifier?.isNotEmpty ?? false)) {
      debugPrint('[oauth-debug] auto exchange scheduled');
      _oauth2AutoExchangePending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_exchangeOAuth2HandoffCode());
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
    String? loginPassword,
  }) async {
    if (!mounted) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          session: session,
          mode: mode,
          initialMooTitle: _mooTitle,
          loginPassword: loginPassword,
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
      _oauth2AutoExchangePending = false;
    });

    try {
      final api = MoorHttpApi(baseUri);
      final pkce = await generatePkcePair();
      _oauth2CodeVerifier = pkce.codeVerifier;
      debugPrint(
        '[oauth-debug] oauth start provider=$provider base=$baseUri redirect=${_oauth2RedirectUri()} verifier_len=${pkce.codeVerifier.length}',
      );
      await OAuth2PendingFlowStore.save(
        OAuth2PendingFlow(
          baseUrl: baseUri.toString(),
          codeVerifier: pkce.codeVerifier,
          redirectUri: _oauth2RedirectUri(),
        ),
      );
      final start = await api.oauth2AppStart(
        provider: provider,
        redirectUri: _oauth2RedirectUri(),
        codeChallenge: pkce.codeChallenge,
        codeChallengeMethod: pkce.codeChallengeMethod,
        intent: 'connect',
      );
      if (kIsWeb) {
        await navigateSameTab(start.authUrl.toString());
      } else {
        await launchUrl(start.authUrl, mode: LaunchMode.externalApplication);
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

  Future<void> _startOAuth2Login(String provider) async {
    await _startOAuth2ProofBound(provider);
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
    final verifier = await _resolveOAuth2CodeVerifier();
    debugPrint(
      '[oauth-debug] exchange requested handoff_len=${handoff.length} '
      'verifier_present=${verifier != null && verifier.isNotEmpty}',
    );
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
        await OAuth2PendingFlowStore.clear();
        _oauth2CodeVerifier = null;
        _oauth2IdentityCode = null;
        _oauth2Identity = null;
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

  Future<String?> _resolveOAuth2CodeVerifier() async {
    final current = _oauth2CodeVerifier?.trim();
    if (current != null && current.isNotEmpty) {
      debugPrint(
        '[oauth-debug] verifier resolve hit memory len=${current.length}',
      );
      return current;
    }
    debugPrint('[oauth-debug] verifier resolve memory miss');
    final pending = await OAuth2PendingFlowStore.load();
    final restored = pending?.codeVerifier.trim();
    if (restored == null || restored.isEmpty) {
      debugPrint('[oauth-debug] verifier resolve prefs miss');
      return null;
    }
    _oauth2CodeVerifier = restored;
    debugPrint(
      '[oauth-debug] verifier resolve prefs hit len=${restored.length}',
    );
    final currentBaseUrl = _baseUrlCtrl.text.trim();
    if (currentBaseUrl.isEmpty || currentBaseUrl == 'http://localhost:8080') {
      _baseUrlCtrl.text = pending!.baseUrl;
      debugPrint(
        '[oauth-debug] verifier resolve restored base ${pending.baseUrl}',
      );
    }
    return restored;
  }

  Future<void> _submitOAuth2AccountChoice() async {
    final baseUri = _parseBaseUri();
    if (baseUri == null) {
      setState(() {
        _error = 'Invalid base URL';
      });
      return;
    }
    final verifier = await _resolveOAuth2CodeVerifier();
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
      await OAuth2PendingFlowStore.clear();
      _oauth2CodeVerifier = null;
      _oauth2IdentityCode = null;
      _oauth2Identity = null;

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
      await _navigateToSession(
        session: session,
        mode: _mode,
        loginPassword: _mode == 'create' ? pass : null,
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

  Color _oauthProviderBackground(
    String provider,
    ColorScheme colorScheme,
  ) {
    switch (provider.toLowerCase()) {
      case 'discord':
        return const Color(0xFF5865F2);
      case 'github':
        return const Color(0xFF24292E);
      case 'google':
        return Colors.white;
      default:
        return colorScheme.surfaceContainerHighest;
    }
  }

  Color _oauthProviderForeground(
    String provider,
    ColorScheme colorScheme,
  ) {
    switch (provider.toLowerCase()) {
      case 'google':
        return const Color(0xFF202124);
      default:
        return provider.toLowerCase() == 'custom'
            ? colorScheme.onSurface
            : Colors.white;
    }
  }

  Widget _buildWelcomeCard(BuildContext context, WelcomeMessage? welcome) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final panelColor = Color.alphaBlend(
      colorScheme.primary.withValues(alpha: 0.05),
      colorScheme.surfaceContainerLow,
    );
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 160),
            child: _loadingWelcome
                ? Text(
                    'Loading welcome message...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Comic Mono',
                    ),
                  )
                : (welcome == null || welcome.lines.isEmpty)
                ? Text(
                    '(no welcome message)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'Comic Mono',
                    ),
                  )
                : ContentRenderer(
                    content: welcome.lines,
                    contentType: welcome.contentType,
                    isStale: false,
                    onLinkTap: _handleWelcomeLinkTap,
                    monospace: false,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthProviderButton(BuildContext context, String provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background = _oauthProviderBackground(provider, colorScheme);
    final foreground = _oauthProviderForeground(provider, colorScheme);
    final label = _mode == 'connect'
        ? 'Sign in with $provider'
        : 'Continue with $provider';
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _oauth2Busy ? null : () => _startOAuth2Login(provider),
        child: Text(label),
      ),
    );
  }

  Widget _buildBaseUrlCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connection',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Web Host Base URL',
                hintText: 'http://localhost:8080',
              ),
              onSubmitted: (_) => _loadWelcome(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOAuthAccountChoiceCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Complete OAuth2 account setup (${_oauth2Identity!.provider})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'oauth2_create', label: Text('Create')),
                ButtonSegment(value: 'oauth2_connect', label: Text('Link')),
              ],
              selected: {_oauth2AccountMode},
              onSelectionChanged: (s) {
                setState(() {
                  _oauth2AccountMode = s.first;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_oauth2AccountMode == 'oauth2_create')
              TextField(
                controller: _oauthCreateNameCtrl,
                decoration: const InputDecoration(labelText: 'Player name'),
              )
            else ...[
              TextField(
                controller: _oauthLinkUserCtrl,
                decoration: const InputDecoration(
                  labelText: 'Existing username/email',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _oauthLinkPassCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Existing password',
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _oauth2Busy ? null : _submitOAuth2AccountChoice,
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
    );
  }

  Widget _buildAuthCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCreate = _mode == 'create';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'connect', label: Text('Sign In')),
                ButtonSegment(value: 'create', label: Text('Create Account')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() {
                  _mode = s.first;
                });
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            if (_oauth2Enabled && _oauth2Providers.isNotEmpty) ...[
              for (final provider in _oauth2Providers) ...[
                _buildOAuthProviderButton(context, provider),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        isCreate
                            ? 'or create with username'
                            : 'or continue with username',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
              ),
            ],
            TextField(
              controller: _userCtrl,
              decoration: InputDecoration(
                labelText: isCreate ? 'Player Name' : 'Username',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => _loggingIn ? null : _login(),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _loggingIn ? null : _login,
              child: Text(
                _loggingIn
                    ? (isCreate ? 'Creating...' : 'Signing in...')
                    : (isCreate ? 'Create Account' : 'Sign In'),
              ),
            ),
            if (_oauth2Enabled && _oauth2Providers.isNotEmpty) ...[
              const SizedBox(height: 18),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: const Text('OAuth handoff'),
                subtitle: const Text(
                  'Use this only if provider login does not return here automatically.',
                ),
                children: [
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
                      const SizedBox(width: 10),
                      FilledButton.tonal(
                        onPressed: _oauth2Busy
                            ? null
                            : _exchangeOAuth2HandoffCode,
                        child: Text(_oauth2Busy ? 'Working...' : 'Exchange'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final welcome = _welcome;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Title(
      title: _mooTitle,
      color: colorScheme.primary,
      child: Scaffold(
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
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.alphaBlend(
                  colorScheme.primary.withValues(alpha: 0.08),
                  colorScheme.surface,
                ),
                colorScheme.surface,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!kIsWeb) ...[
                            _buildBaseUrlCard(context),
                            const SizedBox(height: 18),
                          ],
                          _buildWelcomeCard(context, welcome),
                          const SizedBox(height: 24),
                          _buildAuthCard(context),
                          if (_oauth2IdentityCode != null &&
                              _oauth2Identity != null) ...[
                            const SizedBox(height: 18),
                            _buildOAuthAccountChoiceCard(context),
                          ],
                          SizedBox(
                            height: constraints.maxHeight > 720 ? 32 : 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  final LoginSession session;
  final String mode; // "connect" | "create"
  final String initialMooTitle;
  final SessionScreenBehavior behavior;
  final SessionScreenControllers? controllers;

  /// The login password, passed only on "create" so that encryption can be
  /// set up automatically without prompting the user a second time.
  final String? loginPassword;

  const SessionScreen({
    super.key,
    required this.session,
    required this.mode,
    required this.initialMooTitle,
    this.behavior = const SessionScreenBehavior(),
    this.controllers,
    this.loginPassword,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

@immutable
class SessionScreenBehavior {
  final bool autoConnect;
  final bool autoInitEncryption;
  final bool autoRefreshVerbSuggestions;
  final bool autoRefreshMooTitle;

  const SessionScreenBehavior({
    this.autoConnect = true,
    this.autoInitEncryption = true,
    this.autoRefreshVerbSuggestions = true,
    this.autoRefreshMooTitle = true,
  });

  const SessionScreenBehavior.testing()
    : autoConnect = false,
      autoInitEncryption = false,
      autoRefreshVerbSuggestions = false,
      autoRefreshMooTitle = false;
}

class SessionScreenControllers {
  final PresentationStore? presentations;
  final NarrativeFeedController? narrativeFeedController;
  final EditorSessionController? editorSessionController;
  final DebugPanelController? debugPanelController;
  final SessionViewController? sessionViewController;
  final InputPromptController? inputPromptController;
  final SessionConnectionController? sessionConnectionController;
  final SessionEditorPresenter? editorPresenter;

  const SessionScreenControllers({
    this.presentations,
    this.narrativeFeedController,
    this.editorSessionController,
    this.debugPanelController,
    this.sessionViewController,
    this.inputPromptController,
    this.sessionConnectionController,
    this.editorPresenter,
  });
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

  late final PresentationStore _presentations =
      widget.controllers?.presentations ?? PresentationStore();
  final GlobalKey _listKey = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  late final NarrativeFeedController _narrativeFeedController =
      widget.controllers?.narrativeFeedController ?? NarrativeFeedController();

  double _splitRatio = 0.64;

  late final EditorSessionController _editorSessionController =
      widget.controllers?.editorSessionController ?? EditorSessionController();
  late final DebugPanelController _debugPanelController =
      widget.controllers?.debugPanelController ?? DebugPanelController();
  late final HistoryEncryptionController _historyEncryptionController =
      HistoryEncryptionController(
        getLocalIdentity: EventLogKeyStore.getIdentity,
        setLocalIdentity: EventLogKeyStore.setIdentity,
        removeLocalIdentity: EventLogKeyStore.removeIdentity,
        getBackendPubkey: ({required authToken}) => MoorHttpApi(
          widget.session.baseUri,
        ).getEventLogPubkey(authToken: authToken),
        setBackendPubkey: ({required authToken, required publicKey}) =>
            MoorHttpApi(widget.session.baseUri).setEventLogPubkey(
              authToken: authToken,
              publicKey: publicKey,
            ),
        deriveKeyBytes: EventLogEncryption.deriveKeyBytes,
        identityFromDerivedBytes: EventLogEncryption.identityFromDerivedBytes,
        publicKeyFromDerivedBytes: EventLogEncryption.publicKeyFromDerivedBytes,
      );
  late final HistoryExportController _historyExportController =
      HistoryExportController();
  late final AccountProfileController _accountProfileController =
      AccountProfileController(
        api: MoorHttpApi(widget.session.baseUri),
      );
  late final RoomLookController _roomLookController = RoomLookController();
  late final SessionConnectionController _sessionConnectionController =
      widget.controllers?.sessionConnectionController ??
      SessionConnectionController(
        session: widget.session,
        mode: widget.mode,
        onSystemMessage: _appendSystem,
        onNarrativeItem: _appendItem,
        onPresentationUpsert: _presentations.upsert,
        onPresentationRemove: _presentations.remove,
        onInputPromptRequest: _handleInputPromptRequest,
        onStatusChanged: _handleConnectionStatusChanged,
      );
  late final SessionEditorPresenter _editorPresenter =
      widget.controllers?.editorPresenter ??
      SessionEditorPresenter(
        baseUri: widget.session.baseUri,
        authToken: widget.session.authToken,
      );
  bool get _canUseObjectBrowser =>
      (widget.session.playerFlags & ((1 << 1) | (1 << 2))) != 0;
  late final SessionViewController _sessionViewController =
      widget.controllers?.sessionViewController ?? SessionViewController();
  late final InputPromptController _inputPromptController =
      widget.controllers?.inputPromptController ?? InputPromptController();
  late final SessionBootstrapService _sessionBootstrapService =
      SessionBootstrapService(
        api: MoorHttpApi(widget.session.baseUri),
      );

  int _idSeq = 0;
  String _mooTitle = 'mooR';

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
    _debugPanelController.addListener(_onDebugPanelChanged);
    _editorSessionController.addListener(_onEditorSessionsChanged);
    _historyEncryptionController.addListener(_onHistoryEncryptionChanged);
    _inputPromptController.addListener(_onInputPromptChanged);
    _narrativeFeedController.addListener(_onNarrativeFeedChanged);
    _roomLookController.addListener(_onRoomLookChanged);
    _sessionViewController.addListener(_onSessionViewChanged);
    _sessionConnectionController.addListener(_onSessionConnectionChanged);
    if (widget.behavior.autoConnect) {
      _sessionConnectionController.connect();
    }
    if (widget.behavior.autoInitEncryption) {
      _initEncryption();
    }
    if (widget.behavior.autoRefreshVerbSuggestions) {
      _refreshVerbSuggestions();
    }
    if (widget.behavior.autoRefreshMooTitle) {
      _refreshMooTitle();
    }
  }

  @override
  void dispose() {
    _promptFocus.dispose();
    _promptCtrl.dispose();
    _commandController
      ..removeListener(_onCommandControllerChanged)
      ..dispose();
    _debugPanelController.removeListener(_onDebugPanelChanged);
    _editorSessionController.removeListener(_onEditorSessionsChanged);
    _historyEncryptionController
      ..removeListener(_onHistoryEncryptionChanged)
      ..dispose();
    _accountProfileController.dispose();
    _historyExportController.dispose();
    _inputPromptController.removeListener(_onInputPromptChanged);
    _narrativeFeedController.removeListener(_onNarrativeFeedChanged);
    _roomLookController
      ..removeListener(_onRoomLookChanged)
      ..dispose();
    _sessionViewController.removeListener(_onSessionViewChanged);
    _sessionConnectionController.removeListener(_onSessionConnectionChanged);
    if (widget.controllers?.sessionConnectionController == null) {
      _sessionConnectionController.close();
    }
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    _presentations.removeListener(_onPresentationsChanged);
    if (widget.controllers?.presentations == null) {
      _presentations.dispose();
    }
    if (widget.controllers?.debugPanelController == null) {
      _debugPanelController.dispose();
    }
    if (widget.controllers?.editorSessionController == null) {
      _editorSessionController.dispose();
    }
    if (widget.controllers?.inputPromptController == null) {
      _inputPromptController.dispose();
    }
    if (widget.controllers?.narrativeFeedController == null) {
      _narrativeFeedController.dispose();
    }
    if (widget.controllers?.sessionViewController == null) {
      _sessionViewController.dispose();
    }
    super.dispose();
  }

  void _onCommandControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onDebugPanelChanged() {
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

  void _onHistoryEncryptionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onNarrativeFeedChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onInputPromptChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onRoomLookChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _onSessionViewChanged() {
    if (!mounted) {
      return;
    }
    _roomLookController.handlePresentationsChanged(
      _presentations,
      roomHudEnabled: _sessionViewController.roomHudEnabled,
    );
    setState(() {});
  }

  void _onSessionConnectionChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _refreshMooTitle() async {
    try {
      final title = await _sessionBootstrapService.fetchMooTitle(
        authToken: widget.session.authToken,
      );
      final normalizedTitle = normalizeMooTitle(title);
      if (!mounted) return;
      if (normalizedTitle == null) return;
      setState(() {
        _mooTitle = normalizedTitle;
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
    _roomLookController.handlePresentationsChanged(
      _presentations,
      roomHudEnabled: _sessionViewController.roomHudEnabled,
    );
    _syncEditorSessionsFromPresentations();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  void _syncEditorSessionsFromPresentations() {
    _editorSessionController.syncFromPresentations(
      _presentations,
      onSystemMessage: _appendSystem,
    );
    _editorPresenter.pruneSessions(_editorSessionController.sessions);
  }

  Future<void> _closeEditorSession(EditorSession s) async {
    await _dismissPresentationById(s.presentationId);

    if (!mounted) return;
    setState(() {
      _editorPresenter.removePresentationId(s.presentationId);
      _editorSessionController.removePresentationId(s.presentationId);
    });

    // Also remove from local presentation store so we don't reopen it if the
    // backend is slow to send Unpresent.
    _presentations.remove(s.presentationId);
  }

  Future<void> _dismissPresentationById(String presentationId) async {
    if (presentationId == DebugPanelController.panelId) {
      _debugPanelController.hide(_presentations);
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

  bool _loadingMoreHistory = false;

  void _onScroll() {
    _updateRoomLookLatch();

    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels <= 50 && !_loadingMoreHistory) {
      unawaited(_loadMoreHistory());
    }
  }

  void _updateRoomLookLatch() {
    _roomLookController.updateLatch(
      roomHudEnabled: _sessionViewController.roomHudEnabled,
      tracker: _narrativeFeedController.tracker,
      listKey: _listKey,
      messageKeys: _messageKeys,
    );
  }

  void _handleConnectionStatusChanged(String status) {
    if (!mounted) {
      return;
    }
    if (status == 'connected') {
      _historyEncryptionController.markWsConnected();
      if (_historyEncryptionController.shouldLoadHistoryOnConnect()) {
        unawaited(_loadInitialHistory());
      }
      return;
    }
    if (status == 'disconnected') {
      if (_inputPromptController.hasActivePrompt) {
        _clearInputPrompt();
      }
      _historyEncryptionController.markWsDisconnectedAndShouldResyncHistory();
    }
  }

  Future<void> _initEncryption() async {
    await _historyEncryptionController.init(
      playerOid: widget.session.playerCurie,
      authToken: widget.session.authToken,
      promptForPassword: _promptHistoryPassword,
      promptForSetup: () async {
        // On account creation, auto-setup using the login password.
        if (widget.mode == 'create' && widget.loginPassword != null) {
          return widget.loginPassword;
        }
        return _promptHistorySetup();
      },
      loadInitialHistory: _loadInitialHistory,
      onSystemMessage: _appendSystem,
    );
  }

  Future<void> _setupEncryption(String password) async {
    await _historyEncryptionController.setup(
      playerOid: widget.session.playerCurie,
      authToken: widget.session.authToken,
      password: password,
      loadInitialHistory: _loadInitialHistory,
      onSystemMessage: _appendSystem,
    );
  }

  Future<void> _unlockEncryption(String password) async {
    await _historyEncryptionController.unlock(
      playerOid: widget.session.playerCurie,
      password: password,
      loadInitialHistory: _loadInitialHistory,
      onSystemMessage: _appendSystem,
    );
  }

  Future<void> _loadInitialHistory() async {
    if (!_historyEncryptionController.beginHistoryLoad()) {
      debugPrint('[history] beginHistoryLoad returned false, skipping');
      return;
    }

    final playerOid = widget.session.playerCurie;
    final identity = await EventLogKeyStore.getIdentity(playerOid);
    if (identity == null || identity.trim().isEmpty) {
      debugPrint('[history] no local identity for $playerOid');
      _historyEncryptionController.finishHistoryLoad();
      return;
    }
    debugPrint(
      '[history] identity present for $playerOid '
      '(${identity.length > 20 ? '${identity.substring(0, 20)}...' : identity})',
    );

    if (!mounted) return;
    try {
      _narrativeFeedController.setHistoryBoundaryNow();
      _appendSystem('Loading history...');
      final api = MoorHttpApi(widget.session.baseUri);
      final events = await api.fetchHistory(
        authToken: widget.session.authToken,
        sinceSeconds: 86400,
        limit: 100,
      );
      debugPrint('[history] fetched ${events.length} encrypted events');
      final items = await loadHistoricalNarrativeItems(
        events: events,
        identity: identity,
        tracker: _narrativeFeedController.tracker,
        decryptEvent: decryptEventBlobAge,
        newId: _newId,
      );
      debugPrint(
        '[history] decrypted ${items.length} items '
        'from ${events.length} events',
      );

      if (!mounted) return;
      final added = _narrativeFeedController.prependHistoricalItems(items);
      _historyEncryptionController.completeHistoryLoad();
      _appendSystem('History loaded ($added events)');
    } on Object catch (e, st) {
      debugPrint('[history] load failed: $e\n$st');
      _appendSystem('History load failed: $e');
    } finally {
      _historyEncryptionController.finishHistoryLoad();
    }
  }

  Future<void> _loadMoreHistory() async {
    final cursor = _narrativeFeedController.earliestHistoryEventId;
    if (cursor == null || _loadingMoreHistory) return;

    final playerOid = widget.session.playerCurie;
    final identity = await EventLogKeyStore.getIdentity(playerOid);
    if (identity == null || identity.trim().isEmpty) return;

    _loadingMoreHistory = true;
    try {
      final api = MoorHttpApi(widget.session.baseUri);
      final events = await api.fetchHistory(
        authToken: widget.session.authToken,
        untilEvent: cursor,
        limit: 50,
      );
      if (events.isEmpty || !mounted) return;

      // Remember scroll position before prepending.
      final scrollBefore = _scrollCtrl.hasClients
          ? _scrollCtrl.position.pixels
          : 0.0;
      final extentBefore = _scrollCtrl.hasClients
          ? _scrollCtrl.position.maxScrollExtent
          : 0.0;

      final items = await loadHistoricalNarrativeItems(
        events: events,
        identity: identity,
        tracker: _narrativeFeedController.tracker,
        decryptEvent: decryptEventBlobAge,
        newId: _newId,
      );
      if (items.isEmpty || !mounted) return;
      _narrativeFeedController.prependHistoricalItems(items);

      // Restore scroll position after the layout updates.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final extentAfter = _scrollCtrl.position.maxScrollExtent;
        final delta = extentAfter - extentBefore;
        if (delta > 0) {
          _scrollCtrl.jumpTo(scrollBefore + delta);
        }
      });
    } on Object catch (e) {
      _appendSystem('Load more history failed: $e');
    } finally {
      _loadingMoreHistory = false;
    }
  }

  Future<void> _forgetLocalEncryptionKey() async {
    await _historyEncryptionController.forgetLocalKey(
      playerOid: widget.session.playerCurie,
      onSystemMessage: _appendSystem,
    );
  }

  Future<UnlockPromptResult?> _promptHistoryPassword() async {
    final result = await showEncryptionUnlockDialog(
      context,
      systemTitle: _mooTitle,
    );
    if (result == null) return null;
    return switch (result.action) {
      EncryptionUnlockAction.unlock =>
        UnlockWithPassword(result.password!),
      EncryptionUnlockAction.forgotPassword =>
        UnlockForgotPassword(),
    };
  }

  Future<String?> _promptHistorySetup() async {
    final result = await showEncryptionSetupDialog(
      context,
      systemTitle: _mooTitle,
    );
    return result?.password;
  }

  Future<void> _showAccountSheet() async {
    await _accountProfileController.load(
      authToken: widget.session.authToken,
      playerCurie: widget.session.playerCurie,
      onStatus: _appendSystem,
    );
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return AccountSheet(
          playerCurie: widget.session.playerCurie,
          profileController: _accountProfileController,
          historyEncryptionController: _historyEncryptionController,
          historyExportController: _historyExportController,
          onPickProfilePicture: () {
            unawaited(_pickProfilePicture());
          },
          onEditDescription: () {
            unawaited(_editProfileDescription());
          },
          onPronounsChanged: (value) {
            unawaited(_updatePronouns(value));
          },
          onSetupEncryption: () {
            unawaited(_promptAndSetupEncryption());
          },
          onUnlockEncryption: () {
            unawaited(_promptAndUnlockEncryption());
          },
          onForgetLocalKey: () {
            unawaited(_forgetLocalEncryptionKey());
          },
          onExportHistory: () {
            unawaited(_exportHistory());
          },
          onDeleteHistory: () {
            unawaited(_confirmDeleteHistory());
          },
          onLogout: () {
            Navigator.of(context).pop();
            unawaited(_logout());
          },
        );
      },
    );
  }

  Future<void> _showObjectBrowser() async {
    if (!_canUseObjectBrowser) {
      return;
    }
    final controller = ObjectBrowserController(
      api: MoorHttpApi(widget.session.baseUri),
      authToken: widget.session.authToken,
      initialObjectCurie: widget.session.playerCurie,
    );
    final presenter = SessionEditorPresenter(
      baseUri: widget.session.baseUri,
      authToken: widget.session.authToken,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ObjectBrowserSheet(
          controller: controller,
          editorPresenter: presenter,
          currentPlayerCurie: widget.session.playerCurie,
          currentPlayerFlags: widget.session.playerFlags,
        ),
      ),
    );
  }

  Future<void> _promptAndSetupEncryption() async {
    final result = await showEncryptionSetupDialog(
      context,
      systemTitle: _mooTitle,
    );
    if (!mounted || result == null) return;
    await _setupEncryption(result.password);
  }

  Future<void> _promptAndUnlockEncryption() async {
    final result = await showEncryptionUnlockDialog(
      context,
      systemTitle: _mooTitle,
    );
    if (!mounted || result == null) return;
    switch (result.action) {
      case EncryptionUnlockAction.unlock:
        await _unlockEncryption(result.password!);
      case EncryptionUnlockAction.forgotPassword:
        await _forgetLocalEncryptionKey();
        _appendSystem(
          'History encryption reset — old history is no longer accessible',
        );
        await _promptAndSetupEncryption();
    }
  }

  Future<void> _editProfileDescription() async {
    final next = await showTextPromptDialog(
      context,
      title: 'Profile Description',
      confirmLabel: 'Save',
      labelText: 'Description',
      hintText: 'Tell people about your character',
      initialValue: _accountProfileController.playerDescription ?? '',
      minLines: 4,
      maxLines: 8,
    );
    if (!mounted || next == null) {
      return;
    }
    final ok = await _accountProfileController.updateDescription(
      authToken: widget.session.authToken,
      playerCurie: widget.session.playerCurie,
      description: next,
      onStatus: _appendSystem,
    );
    _showUserMessage(
      ok ? 'Profile description saved' : 'Profile description save failed',
    );
  }

  Future<void> _updatePronouns(String value) async {
    final ok = await _accountProfileController.updatePronouns(
      authToken: widget.session.authToken,
      playerCurie: widget.session.playerCurie,
      pronouns: value,
      onStatus: _appendSystem,
    );
    _showUserMessage(ok ? 'Pronouns saved' : 'Pronouns save failed');
  }

  Future<void> _pickProfilePicture() async {
    const imageGroup = XTypeGroup(
      label: 'images',
      extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp'],
      mimeTypes: <String>[
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      ],
    );
    XFile? selected;
    try {
      selected = await openFile(
        acceptedTypeGroups: <XTypeGroup>[imageGroup],
      );
    } on PlatformException catch (e) {
      const message =
          'Profile picture picker unavailable. Restart the Linux app and try again.';
      _appendSystem('$message ($e)');
      _showUserMessage(message);
      return;
    } on Object catch (e) {
      const message = 'Profile picture picker failed.';
      _appendSystem('$message $e');
      _showUserMessage(message);
      return;
    }
    if (selected == null) {
      return;
    }
    final bytes = await selected.readAsBytes();
    if (!mounted) {
      return;
    }
    final cropped = await showProfilePictureCropDialog(
      context,
      imageBytes: bytes,
    );
    if (!mounted || cropped == null || cropped.isEmpty) {
      return;
    }
    const contentType = 'image/png';
    final ok = await _accountProfileController.uploadProfilePicture(
      authToken: widget.session.authToken,
      playerCurie: widget.session.playerCurie,
      contentType: contentType,
      data: cropped,
      onStatus: _appendSystem,
    );
    _showUserMessage(
      ok ? 'Profile picture saved' : 'Profile picture save failed',
    );
  }

  Future<void> _exportHistory() async {
    final identity = await EventLogKeyStore.getIdentity(
      widget.session.playerCurie,
    );
    if (identity == null || identity.trim().isEmpty) {
      _appendSystem('History export unavailable: unlock encryption first');
      return;
    }
    await _historyExportController.exportAll(
      api: MoorHttpApi(widget.session.baseUri),
      authToken: widget.session.authToken,
      ageIdentity: identity,
      systemTitle: _mooTitle,
      playerOid: widget.session.playerCurie,
      decryptEvent: decryptEventBlobAge,
      saveFile: _saveHistoryExport,
      onStatus: _appendSystem,
    );
  }

  Future<void> _saveHistoryExport({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'json',
          extensions: <String>['json'],
          mimeTypes: <String>['application/json'],
        ),
      ],
    );
    if (location == null) {
      _appendSystem('History export canceled');
      return;
    }
    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
  }

  Future<void> _confirmDeleteHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete All History'),
          content: const Text(
            'This permanently deletes your event history from the server. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      final success = await MoorHttpApi(widget.session.baseUri)
          .deleteEventLogHistory(
            authToken: widget.session.authToken,
          );
      _appendSystem(
        success ? 'Event history deleted' : 'Event history delete failed',
      );
    } on Object catch (e) {
      _appendSystem('Event history delete failed: $e');
    }
  }

  void _showUserMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  void _appendSystem(String m) {
    _debugPanelController.appendLine(m, _presentations);
  }

  void _appendNarrativeText(String text, {String contentType = 'text/plain'}) {
    _appendItemFromText(text, contentType: contentType);
  }

  void _toggleDebugPanel() {
    _debugPanelController.toggle(_presentations);
  }

  void _appendItemFromText(String text, {required String contentType}) {
    final appended = _narrativeFeedController.appendNarrativeText(
      text,
      newId: _newId,
      contentType: contentType,
    );
    if (!appended) {
      return;
    }
    _announceNarrativeText(
      _plainTextForAnnouncement(
        text,
        contentType: contentType,
      ),
    );
    _scheduleScrollToBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  void _appendItem(NarrativeItem it) {
    // Drop WebSocket events that overlap with already-loaded history.
    if (_narrativeFeedController.isHistoricalDuplicate(it.timestamp)) {
      return;
    }
    final appended = _narrativeFeedController.appendItem(it);
    if (!appended) {
      return;
    }
    _announceNarrativeText(_announcementTextForNarrativeItem(it));
    _scheduleScrollToBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateRoomLookLatch());
  }

  void _announceNarrativeText(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty || !mounted) {
      return;
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      normalized,
      Directionality.of(context),
    );
  }

  String _announcementTextForNarrativeItem(NarrativeItem item) {
    final ttsText = item.metadata?.ttsText;
    if (ttsText != null && ttsText.trim().isNotEmpty) {
      return ttsText;
    }
    return _plainTextForAnnouncement(
      item.content.join('\n'),
      contentType: item.contentType,
    );
  }

  String _plainTextForAnnouncement(
    String text, {
    required String contentType,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    switch (contentType) {
      case 'text/html':
        return (html_parser.parseFragment(trimmed).text ?? '').trim();
      default:
        return trimmed;
    }
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollCtrl.hasClients) {
        return;
      }

      // Narrative groups such as inset cards can grow over more than one
      // layout pass, so chase the bottom for a couple of frames.
      for (var i = 0; i < 3; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scrollCtrl.hasClients) {
          return;
        }
        final position = _scrollCtrl.position;
        final target = position.maxScrollExtent;
        if ((position.pixels - target).abs() <= 1) {
          break;
        }
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _handleInputPromptRequest(InputPromptRequest request) {
    final md = request.metadata;
    _inputPromptController.handleRequest(request);
    _promptCtrl.text = _inputPromptController.initialValue;
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
    _inputPromptController.clear();
    _promptCtrl.clear();
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
    _sessionConnectionController.sendText(v);
    _clearInputPrompt();
  }

  void _send() {
    final commandsSent = _commandController.consumeCommandsToSend();
    if (commandsSent.isEmpty) {
      return;
    }

    for (final cmd in commandsSent) {
      _sessionConnectionController.sendText(cmd);
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
      _sessionConnectionController.sendText(cmd);
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
      var shouldOpen = await TrustedExternalDomainsStore.isTrusted(url);
      if (!shouldOpen) {
        if (!mounted) return;
        final decision = await showExternalLinkDialog(context, url: url);
        if (!mounted || decision == null) {
          return;
        }
        if (decision.trustDomain) {
          final hostname = TrustedExternalDomainsStore.hostnameFor(url);
          if (hostname != null) {
            await TrustedExternalDomainsStore.addDomain(hostname);
          }
        }
        shouldOpen = true;
      }
      if (!shouldOpen) {
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
    await showInspectSheet(
      context,
      data: inspectData,
      monospaceNarrative: _sessionViewController.monospaceNarrative,
      onRunAction: _runInspectAction,
      onLinkTap: _handleLinkTap,
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
        _sessionConnectionController.sendText(commandToSend);
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
    return showTextPromptDialog(
      context,
      title: action.inputPrompt ?? action.label,
      confirmLabel: 'OK',
      hintText: action.inputPlaceholder ?? 'Enter text',
    );
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

    try {
      final result = await _sessionBootstrapService.loadVerbSuggestions(
        authToken: authToken,
        playerCurie: player,
      );

      if (!mounted) return;
      _commandController.updateVerbSuggestions(
        suggestionsAvailable: result.suggestionsAvailable,
        serverPlaceholderText: result.serverPlaceholderText,
        paletteVerbs: result.paletteVerbs,
      );

      if (result.debugMessage != null) {
        _appendSystem(result.debugMessage!);
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
          initialSettings: _sessionViewController.settings(
            verbSuggestionsAvailable:
                _commandController.verbSuggestionsAvailable,
            themeMode: _ThemeScope.of(context).mode,
          ),
          onSettingsChanged: _sessionViewController.applySettings,
          onThemeModeChanged: (mode) {
            _ThemeScope.of(context).mode = mode;
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    _sessionConnectionController.close();
    _presentations.clear();
    setState(() {
      _editorSessionController.clear();
      _narrativeFeedController.clear();
      _editorPresenter.clear();
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
            final suppressRoomKey = _roomLookController.suppressedRoomKey(
              roomHudEnabled: _sessionViewController.roomHudEnabled,
            );

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
              if (!_sessionViewController.roomHudEnabled) {
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
                      monospaceNarrative:
                          _sessionViewController.monospaceNarrative,
                      onDismissPresentation: _dismissPresentationById,
                      onInspect: _showInspectSheet,
                      onSendCommand: (cmd) {
                        _sessionConnectionController.sendText(cmd);
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
                                items: _narrativeFeedController.items,
                                monospaceNarrative:
                                    _sessionViewController.monospaceNarrative,
                                showNarrativeMeta:
                                    _sessionViewController.showNarrativeMeta,
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
                                      monospaceNarrative: _sessionViewController
                                          .monospaceNarrative,
                                      onDismissPresentation:
                                          _dismissPresentationById,
                                      onInspect: _showInspectSheet,
                                      onSendCommand: (cmd) {
                                        _sessionConnectionController.sendText(
                                          cmd,
                                        );
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
                      visible:
                          _sessionViewController.verbPaletteEnabled &&
                          !_inputPromptController.hasActivePrompt,
                      verbs: _commandController.paletteVerbs,
                      onSelect: _selectPaletteVerb,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _inputPromptController.current != null
                      ? InputPromptComposer(
                          request: _inputPromptController.current!,
                          controller: _promptCtrl,
                          focusNode: _promptFocus,
                          monospaceNarrative:
                              _sessionViewController.monospaceNarrative,
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

  @override
  Widget build(BuildContext context) {
    return Title(
      title: _mooTitle,
      color: Theme.of(context).colorScheme.primary,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('$_mooTitle (${_sessionConnectionController.status})'),
          actions: [
            SessionAppBarActions(
              debugPanelVisible: _debugPanelController.visible,
              onToggleDebugPanel: _toggleDebugPanel,
              onShowAccount: () {
                unawaited(_showAccountSheet());
              },
              onShowObjectBrowser: _canUseObjectBrowser
                  ? () {
                      unawaited(_showObjectBrowser());
                    }
                  : null,
              onShowSettings: () {
                unawaited(_showSettingsSheet());
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
                      onOpenFullscreen: (session) async {
                        if (!mounted) return;
                        await _editorPresenter.openFullscreen(context, session);
                      },
                      paneBuilder: _editorPresenter.paneForSession,
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
                    onOpenFullscreen: (session) async {
                      if (!mounted) return;
                      await _editorPresenter.openFullscreen(context, session);
                    },
                    paneBuilder: _editorPresenter.paneForSession,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
