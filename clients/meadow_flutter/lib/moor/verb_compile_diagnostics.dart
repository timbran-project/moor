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

import 'package:flutter/foundation.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;

@immutable
class VerbCompileDiagnostic {
  final String type;
  final String message;
  final int? line;
  final int? column;
  final int? endLine;
  final int? endColumn;
  final int? spanStart;
  final int? spanEnd;
  final String? contextLine;
  final List<String> expectedTokens;
  final List<String> notes;

  const VerbCompileDiagnostic({
    required this.type,
    required this.message,
    this.line,
    this.column,
    this.endLine,
    this.endColumn,
    this.spanStart,
    this.spanEnd,
    this.contextLine,
    this.expectedTokens = const <String>[],
    this.notes = const <String>[],
  });

  bool get hasLocation => line != null && column != null;
}

List<VerbCompileDiagnostic> parseVerbCompileDiagnostics(
  moor_rpc.VerbProgramResponse response,
) {
  if (response.responseType?.value !=
      moor_rpc.VerbProgramResponseUnionTypeId.VerbProgramFailure.value) {
    return const <VerbCompileDiagnostic>[];
  }

  final failure = response.response as moor_rpc.VerbProgramFailure?;
  final programError = failure?.error;
  if (programError == null) {
    return const <VerbCompileDiagnostic>[
      VerbCompileDiagnostic(type: 'other', message: 'Compile failed'),
    ];
  }

  if (programError.errorType?.value !=
      moor_rpc.VerbProgramErrorUnionTypeId.VerbCompilationError.value) {
    return <VerbCompileDiagnostic>[
      VerbCompileDiagnostic(type: 'other', message: programError.toString()),
    ];
  }

  final compilation = programError.error as moor_rpc.VerbCompilationError?;
  final compileError = compilation?.error;
  if (compileError == null) {
    return const <VerbCompileDiagnostic>[
      VerbCompileDiagnostic(type: 'other', message: 'Compilation error'),
    ];
  }

  if (compileError.errorType?.value ==
      moor_common.CompileErrorUnionTypeId.ParseError.value) {
    final parseError = compileError.error as moor_common.ParseError?;
    if (parseError == null) {
      return const <VerbCompileDiagnostic>[
        VerbCompileDiagnostic(type: 'other', message: 'Parse error'),
      ];
    }

    final position = parseError.errorPosition;
    return <VerbCompileDiagnostic>[
      VerbCompileDiagnostic(
        type: 'parse',
        message: parseError.message ?? 'Parse error',
        line: position?.line,
        column: position?.col,
        endLine: parseError.hasEnd ? parseError.endLine : null,
        endColumn: parseError.hasEnd ? parseError.endCol : null,
        spanStart: parseError.hasSpan ? parseError.spanStart : null,
        spanEnd: parseError.hasSpan ? parseError.spanEnd : null,
        contextLine: parseError.context,
        expectedTokens: parseError.expectedTokens ?? const <String>[],
        notes: parseError.notes ?? const <String>[],
      ),
    ];
  }

  return <VerbCompileDiagnostic>[
    VerbCompileDiagnostic(
      type: 'other',
      message: compileError.toString(),
    ),
  ];
}

String summarizeVerbCompileDiagnostics(
  List<VerbCompileDiagnostic> diagnostics,
) {
  if (diagnostics.isEmpty) {
    return 'Compile failed';
  }
  final first = diagnostics.first;
  if (first.hasLocation) {
    return '${first.message} (line ${first.line}, col ${first.column})';
  }
  return first.message;
}

String formatVerbCompileDiagnostic(VerbCompileDiagnostic diagnostic) {
  final lines = <String>[diagnostic.message];
  if (diagnostic.hasLocation) {
    lines.add('Line ${diagnostic.line}, column ${diagnostic.column}');
  }
  if (diagnostic.contextLine != null && diagnostic.contextLine!.isNotEmpty) {
    lines.add(diagnostic.contextLine!.trimRight());
  }
  if (diagnostic.expectedTokens.isNotEmpty) {
    lines.add('Expected: ${diagnostic.expectedTokens.join(', ')}');
  }
  lines.addAll(diagnostic.notes);
  return lines.join('\n');
}
