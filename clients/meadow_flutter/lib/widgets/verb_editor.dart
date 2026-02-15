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
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/moo_syntax.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/github.dart';

class VerbEditorPane extends StatefulWidget {
  final Uri baseUri;
  final String authToken;
  final String objectCurie;
  final String verbName;

  const VerbEditorPane({
    super.key,
    required this.baseUri,
    required this.authToken,
    required this.objectCurie,
    required this.verbName,
  });

  @override
  State<VerbEditorPane> createState() => _VerbEditorPaneState();
}

class _VerbEditorPaneState extends State<VerbEditorPane> {
  late final CodeLineEditingController _ctrl =
      CodeLineEditingController.fromText('');
  late final CodeScrollController _scrollCtrl = CodeScrollController(
    verticalScroller: ScrollController(),
    horizontalScroller: ScrollController(),
  );
  bool _loading = true;
  bool _compiling = false;
  String? _compileResult;
  String? _error;
  String _lastCompiled = '';

  late final _codeTheme = CodeHighlightTheme(
    languages: <String, CodeHighlightThemeMode>{
      'moo': CodeHighlightThemeMode(mode: langMoo),
    },
    theme: githubTheme,
  );

  static const _monoFallback = <String>[
    'Ubuntu Mono',
    'DejaVu Sans Mono',
    'Liberation Mono',
    'monospace',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.verticalScroller.dispose();
    _scrollCtrl.horizontalScroller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _compileResult = null;
    });
    try {
      final api = MoorHttpApi(widget.baseUri);
      final v = await api.getVerbCode(
        authToken: widget.authToken,
        objectCurie: widget.objectCurie,
        verbName: widget.verbName,
      );
      final code = v.code ?? const <String>[];
      if (!mounted) return;
      setState(() {
        _ctrl.codeLines = CodeLines.fromText(code.join('\n'));
        _lastCompiled = code.join('\n');
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _currentText() => _ctrl.codeLines.asString(TextLineBreak.lf, false);

  bool get _hasUnsavedChanges => _currentText() != _lastCompiled;

  String _formatCompileFailure(moor_rpc.VerbProgramResponse resp) {
    if (resp.responseType?.value !=
        moor_rpc.VerbProgramResponseUnionTypeId.VerbProgramFailure.value) {
      return 'Compile failed';
    }
    final failure = resp.response as moor_rpc.VerbProgramFailure?;
    final err = failure?.error;
    if (err == null) return 'Compile failed';

    if (err.errorType?.value ==
        moor_rpc.VerbProgramErrorUnionTypeId.VerbCompilationError.value) {
      final ce = err.error as moor_rpc.VerbCompilationError?;
      final compileError = ce?.error;
      if (compileError == null) return 'Compilation error';

      if (compileError.errorType?.value ==
          moor_common.CompileErrorUnionTypeId.ParseError.value) {
        final pe = compileError.error as moor_common.ParseError?;
        final msg = pe?.message ?? 'Parse error';
        final pos = pe?.errorPosition;
        final line = pos?.line;
        final col = pos?.col;
        if (line != null && col != null) {
          return '$msg (line $line, col $col)';
        }
        return msg;
      }

      return compileError.toString();
    }

    return err.toString();
  }

  Future<void> _compile() async {
    if (_compiling) return;
    setState(() {
      _compiling = true;
      _compileResult = null;
    });
    try {
      final api = MoorHttpApi(widget.baseUri);
      final resp = await api.compileVerb(
        authToken: widget.authToken,
        objectCurie: widget.objectCurie,
        verbName: widget.verbName,
        code: _currentText(),
      );

      if (!mounted) return;
      if (resp.responseType?.value ==
          moor_rpc.VerbProgramResponseUnionTypeId.VerbProgramSuccess.value) {
        setState(() {
          _lastCompiled = _currentText();
          _compileResult = 'Compiled';
        });
      } else {
        setState(() {
          _compileResult = _formatCompileFailure(resp);
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _compileResult = 'Compile failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _compiling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compileLabel = _compiling
        ? 'Compiling...'
        : _hasUnsavedChanges
        ? 'Compile*'
        : 'Compile';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: (_loading || _compiling) ? null : _compile,
                child: Text(compileLabel),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _loading ? null : _load,
                child: const Text('Reload'),
              ),
              const Spacer(),
              if (_hasUnsavedChanges)
                Text(
                  'unsaved',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (_compileResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                _compileResult!,
                style: TextStyle(
                  color: _compileResult == 'Compiled'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: CodeEditor(
              controller: _ctrl,
              scrollController: _scrollCtrl,
              style: CodeEditorStyle(
                fontFamily: 'Ubuntu Mono',
                fontFamilyFallback: _monoFallback,
                codeTheme: _codeTheme,
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return Row(
                      children: [
                        DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                        ),
                        DefaultCodeChunkIndicator(
                          width: 20,
                          controller: chunkController,
                          notifier: notifier,
                        ),
                      ],
                    );
                  },
            ),
          ),
        ],
      ),
    );
  }
}

class VerbEditorScreen extends StatelessWidget {
  final String title;
  final Widget child;

  const VerbEditorScreen({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: child,
    );
  }
}
