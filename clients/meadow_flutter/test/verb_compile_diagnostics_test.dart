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

import 'package:flutter_test/flutter_test.dart';
import 'package:meadow_flutter/fbs/moor_rpc_moor_common_generated.dart'
    as moor_common;
import 'package:meadow_flutter/fbs/moor_rpc_moor_rpc_generated.dart'
    as moor_rpc;
import 'package:meadow_flutter/moor/verb_compile_diagnostics.dart';

void main() {
  group('verb compile diagnostics', () {
    test('parses structured parse errors', () {
      final response = moor_rpc.VerbProgramResponse(
        moor_rpc.VerbProgramResponseObjectBuilder(
          responseType:
              moor_rpc.VerbProgramResponseUnionTypeId.VerbProgramFailure,
          response: moor_rpc.VerbProgramFailureObjectBuilder(
            error: moor_rpc.VerbProgramErrorObjectBuilder(
              errorType:
                  moor_rpc.VerbProgramErrorUnionTypeId.VerbCompilationError,
              error: moor_rpc.VerbCompilationErrorObjectBuilder(
                error: moor_common.CompileErrorObjectBuilder(
                  errorType: moor_common.CompileErrorUnionTypeId.ParseError,
                  error: moor_common.ParseErrorObjectBuilder(
                    errorPosition: moor_common.CompileContextObjectBuilder(
                      line: 7,
                      col: 13,
                    ),
                    endLine: 7,
                    endCol: 16,
                    hasEnd: true,
                    message: 'Unexpected token',
                    spanStart: 84,
                    spanEnd: 87,
                    hasSpan: true,
                    context: 'if (foo bar)',
                    expectedTokens: const <String>['then', ';'],
                    notes: const <String>['Check the preceding expression.'],
                  ),
                ),
              ),
            ),
          ),
        ).toBytes(),
      );

      final diagnostics = parseVerbCompileDiagnostics(response);

      expect(diagnostics, hasLength(1));
      expect(diagnostics.first.type, 'parse');
      expect(diagnostics.first.message, 'Unexpected token');
      expect(diagnostics.first.line, 7);
      expect(diagnostics.first.column, 13);
      expect(diagnostics.first.endLine, 7);
      expect(diagnostics.first.endColumn, 16);
      expect(diagnostics.first.spanStart, 84);
      expect(diagnostics.first.spanEnd, 87);
      expect(diagnostics.first.contextLine, 'if (foo bar)');
      expect(diagnostics.first.expectedTokens, <String>['then', ';']);
      expect(
        diagnostics.first.notes,
        <String>['Check the preceding expression.'],
      );
      expect(
        summarizeVerbCompileDiagnostics(diagnostics),
        'Unexpected token (line 7, col 13)',
      );
    });

    test('falls back to generic error text for non-parse failures', () {
      final response = moor_rpc.VerbProgramResponse(
        moor_rpc.VerbProgramResponseObjectBuilder(
          responseType:
              moor_rpc.VerbProgramResponseUnionTypeId.VerbProgramFailure,
          response: moor_rpc.VerbProgramFailureObjectBuilder(
            error: moor_rpc.VerbProgramErrorObjectBuilder(
              errorType: moor_rpc.VerbProgramErrorUnionTypeId.NoVerbToProgram,
              error: moor_rpc.NoVerbToProgramObjectBuilder(),
            ),
          ),
        ).toBytes(),
      );

      final diagnostics = parseVerbCompileDiagnostics(response);

      expect(diagnostics, hasLength(1));
      expect(diagnostics.first.type, 'other');
      expect(diagnostics.first.message, contains('NoVerbToProgram'));
    });
  });
}
