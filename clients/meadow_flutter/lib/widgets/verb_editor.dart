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
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/moo_syntax.dart';
import 'package:meadow_flutter/moor/verb_compile_diagnostics.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
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
  late final FocusNode _focusNode = FocusNode();
  bool _loading = true;
  bool _compiling = false;
  String? _error;
  String _lastCompiled = '';
  List<VerbCompileDiagnostic> _compileDiagnostics =
      const <VerbCompileDiagnostic>[];
  bool _compileSuccess = false;
  int _activeDiagnosticIndex = 0;

  static const _monoFallback = <String>[
    'Comic Mono',
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
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _compileSuccess = false;
      _compileDiagnostics = const <VerbCompileDiagnostic>[];
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

  CodeHighlightTheme _codeTheme(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return CodeHighlightTheme(
      languages: <String, CodeHighlightThemeMode>{
        'moo': CodeHighlightThemeMode(mode: langMoo),
      },
      theme: brightness == Brightness.dark ? atomOneDarkTheme : githubTheme,
    );
  }

  Set<int> _errorLineSet() {
    return {
      for (final diagnostic in _compileDiagnostics)
        if (diagnostic.line != null && diagnostic.line! > 0) diagnostic.line!,
    };
  }

  void _focusDiagnostic(
    VerbCompileDiagnostic diagnostic, {
    bool updateState = true,
  }) {
    final line = diagnostic.line;
    final column = diagnostic.column;
    if (line == null || column == null) {
      return;
    }
    final lineIndex = line - 1;
    if (lineIndex < 0 || lineIndex >= _ctrl.codeLines.length) {
      return;
    }
    final lineText = _ctrl.codeLines[lineIndex].text;
    final startOffset = column <= 0
        ? 0
        : column > lineText.length
        ? lineText.length
        : column - 1;
    var endOffset = startOffset + 1;
    if (diagnostic.endLine == line &&
        diagnostic.endColumn != null &&
        diagnostic.endColumn! > 0) {
      endOffset = diagnostic.endColumn! - 1;
    } else if (diagnostic.spanStart != null &&
        diagnostic.spanEnd != null &&
        diagnostic.spanEnd! > diagnostic.spanStart!) {
      final spanLength = diagnostic.spanEnd! - diagnostic.spanStart!;
      endOffset = startOffset + spanLength;
    } else if (diagnostic.contextLine != null) {
      final wordEnd = lineText.indexOf(' ', startOffset);
      endOffset = wordEnd == -1 ? lineText.length : wordEnd;
    }
    if (endOffset <= startOffset) {
      endOffset = startOffset < lineText.length ? startOffset + 1 : startOffset;
    }
    if (endOffset > lineText.length) {
      endOffset = lineText.length;
    }
    final selection = CodeLineSelection(
      baseIndex: lineIndex,
      baseOffset: startOffset,
      extentIndex: lineIndex,
      extentOffset: endOffset,
    );
    _ctrl.selection = selection;
    _ctrl.makePositionVisible(selection.start);
    if (updateState) {
      setState(() {
        _activeDiagnosticIndex = _compileDiagnostics.indexOf(diagnostic);
      });
    }
  }

  Future<void> _compile() async {
    if (_compiling) return;
    setState(() {
      _compiling = true;
      _compileSuccess = false;
      _compileDiagnostics = const <VerbCompileDiagnostic>[];
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
          _compileSuccess = true;
          _compileDiagnostics = const <VerbCompileDiagnostic>[];
        });
      } else {
        final diagnostics = parseVerbCompileDiagnostics(resp);
        setState(() {
          _compileSuccess = false;
          _compileDiagnostics = diagnostics;
          _activeDiagnosticIndex = 0;
        });
        if (diagnostics.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _focusDiagnostic(diagnostics.first, updateState: false);
          });
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _compileSuccess = false;
        _compileDiagnostics = <VerbCompileDiagnostic>[
          VerbCompileDiagnostic(type: 'other', message: 'Compile failed: $e'),
        ];
        _activeDiagnosticIndex = 0;
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
    final codeTheme = _codeTheme(context);
    final errorLines = _errorLineSet();
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
                    fontFamily: 'Comic Mono',
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
                  fontFamily: 'Comic Mono',
                ),
              ),
            ),
          if (_compileSuccess)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Compiled',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'Comic Mono',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (_compileDiagnostics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _VerbCompileDiagnosticsPanel(
                diagnostics: _compileDiagnostics,
                activeIndex: _activeDiagnosticIndex,
                onDismiss: () {
                  setState(() {
                    _compileDiagnostics = const <VerbCompileDiagnostic>[];
                    _activeDiagnosticIndex = 0;
                  });
                },
                onSelect: (index) {
                  _focusDiagnostic(_compileDiagnostics[index]);
                },
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: CodeEditor(
              controller: _ctrl,
              scrollController: _scrollCtrl,
              focusNode: _focusNode,
              style: CodeEditorStyle(
                fontFamily: 'Comic Mono',
                fontFamilyFallback: _monoFallback,
                codeTheme: codeTheme,
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DefaultCodeLineNumber(
                          controller: editingController,
                          notifier: notifier,
                          customLineIndex2Text: (lineIndex) {
                            final display = '${lineIndex + 1}';
                            if (errorLines.contains(lineIndex + 1)) {
                              return '$display!';
                            }
                            return display;
                          },
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

class _VerbCompileDiagnosticsPanel extends StatelessWidget {
  final List<VerbCompileDiagnostic> diagnostics;
  final int activeIndex;
  final VoidCallback onDismiss;
  final ValueChanged<int> onSelect;

  const _VerbCompileDiagnosticsPanel({
    required this.diagnostics,
    required this.activeIndex,
    required this.onDismiss,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
        border: Border.all(color: theme.colorScheme.error),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    diagnostics.length == 1
                        ? 'Compiler Error'
                        : 'Compiler Errors (${diagnostics.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss compiler errors',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < diagnostics.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _VerbCompileDiagnosticTile(
                diagnostic: diagnostics[i],
                selected: i == activeIndex,
                onTap: () => onSelect(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VerbCompileDiagnosticTile extends StatelessWidget {
  final VerbCompileDiagnostic diagnostic;
  final bool selected;
  final VoidCallback onTap;

  const _VerbCompileDiagnosticTile({
    required this.diagnostic,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onErrorContainer;
    return Material(
      color: selected
          ? theme.colorScheme.error.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      diagnostic.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (diagnostic.hasLocation)
                    Text(
                      'L${diagnostic.line}:C${diagnostic.column}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontFamily: 'Comic Mono',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
              if (diagnostic.contextLine != null &&
                  diagnostic.contextLine!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  diagnostic.contextLine!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontFamily: 'Comic Mono',
                  ),
                ),
              ],
              if (diagnostic.expectedTokens.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Expected: ${diagnostic.expectedTokens.join(', ')}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
              if (diagnostic.notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final note in diagnostic.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
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
