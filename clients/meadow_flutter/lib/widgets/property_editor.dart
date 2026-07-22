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
import 'package:meadow_flutter/moor/http_api.dart';
import 'package:meadow_flutter/moor/moo_literal.dart';
import 'package:meadow_flutter/moor/moo_syntax.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/github.dart';

class PropertyEditorPane extends StatefulWidget {
  final Uri baseUri;
  final String authToken;
  final String objectCurie;
  final String propertyName;

  const PropertyEditorPane({
    super.key,
    required this.baseUri,
    required this.authToken,
    required this.objectCurie,
    required this.propertyName,
  });

  @override
  State<PropertyEditorPane> createState() => _PropertyEditorPaneState();
}

class _PropertyEditorPaneState extends State<PropertyEditorPane> {
  late final CodeLineEditingController _ctrl =
      CodeLineEditingController.fromText('');
  late final CodeScrollController _scrollCtrl = CodeScrollController(
    verticalScroller: ScrollController(),
    horizontalScroller: ScrollController(),
  );
  late final FocusNode _focusNode = FocusNode();

  bool _loading = true;
  bool _saving = false;
  bool _supported = true;
  String? _saveResult;
  String? _error;
  String _lastSaved = '';

  late final _codeTheme = CodeHighlightTheme(
    languages: <String, CodeHighlightThemeMode>{
      'moo': CodeHighlightThemeMode(mode: langMoo),
    },
    theme: githubTheme,
  );

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
      _saveResult = null;
    });
    try {
      final api = MoorHttpApi(widget.baseUri);
      final v = await api.getProperty(
        authToken: widget.authToken,
        objectCurie: widget.objectCurie,
        propertyName: widget.propertyName,
      );
      final literal = varToMooLiteral(v.value);
      final supported = isSupportedMooLiteralVar(v.value);
      if (!mounted) return;
      setState(() {
        _supported = supported;
        _ctrl.codeLines = CodeLines.fromText(literal);
        _lastSaved = literal;
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

  bool get _hasUnsavedChanges => _currentText() != _lastSaved;

  Future<void> _save() async {
    if (_saving || !_supported) return;
    setState(() {
      _saving = true;
      _saveResult = null;
    });
    try {
      final api = MoorHttpApi(widget.baseUri);
      await api.updateProperty(
        authToken: widget.authToken,
        objectCurie: widget.objectCurie,
        propertyName: widget.propertyName,
        valueLiteral: _currentText(),
      );
      if (!mounted) return;
      setState(() {
        _lastSaved = _currentText();
        _saveResult = 'Saved';
      });
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saveResult = 'Save failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saveLabel = _saving
        ? 'Saving...'
        : _hasUnsavedChanges
        ? 'Save*'
        : 'Save';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: (_loading || _saving || !_supported) ? null : _save,
                child: Text(saveLabel),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _loading ? null : _load,
                child: const Text('Reload'),
              ),
              const Spacer(),
              if (!_supported)
                Text(
                  'unsupported',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontFamily: 'Comic Mono',
                  ),
                )
              else if (_hasUnsavedChanges)
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
          if (_saveResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                _saveResult!,
                style: TextStyle(
                  color: _saveResult == 'Saved'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                  fontFamily: 'Comic Mono',
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: CodeEditor(
              controller: _ctrl,
              scrollController: _scrollCtrl,
              focusNode: _focusNode,
              readOnly: !_supported,
              showCursorWhenReadOnly: false,
              style: CodeEditorStyle(
                fontFamily: 'Comic Mono',
                fontFamilyFallback: _monoFallback,
                codeTheme: _codeTheme,
              ),
              indicatorBuilder:
                  (context, editingController, chunkController, notifier) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
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

class PropertyEditorScreen extends StatelessWidget {
  final String title;
  final Widget child;

  const PropertyEditorScreen({
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
