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

import 'package:re_highlight/re_highlight.dart';

// Lightweight MOO language definition for re_highlight/re_editor.
//
// This is intentionally incomplete; it exists to provide basic readability
// (comments, strings, keywords, numbers, object refs, $-vars, symbols).
final langMoo = Mode(
  name: 'MOO',
  // Keep this permissive; we don’t want highlighting to bail on odd constructs.
  contains: <Mode>[
    // Block comments: /* ... */
    Mode(
      scope: 'comment',
      begin: r'/\*',
      end: r'\*/',
      contains: <Mode>[Mode(self: true)],
    ),
    // Line comments: // ...
    Mode(
      scope: 'comment',
      begin: '//',
      end: r'$',
    ),
    // Binary literal: b"..."
    Mode(
      scope: 'string',
      begin: 'b"',
      end: '"',
      illegal: r'\n',
      contains: <Mode>[BACKSLASH_ESCAPE],
    ),
    // Strings: "..."
    Mode(
      scope: 'string',
      begin: '"',
      end: '"',
      illegal: r'\n',
      contains: <Mode>[BACKSLASH_ESCAPE],
    ),
    // Symbols: 'foo
    Mode(
      className: 'symbol',
      begin: "'[a-zA-Z_][a-zA-Z0-9_]*",
    ),
    // System properties/verbs: $foo
    Mode(
      className: 'variable',
      begin: r'\$[a-zA-Z_][a-zA-Z0-9_]*',
    ),
    // Object refs: #123, #-1
    Mode(
      className: 'number',
      begin: r'#-?\d+',
    ),
    // Error constants: E_PERM, E_INVARG, ...
    Mode(
      className: 'built_in',
      begin: r'\bE_[A-Z_]+\b',
    ),
    // Type constants: INT, STR, LIST, ...
    Mode(
      className: 'type',
      begin: r'\b(INT|NUM|FLOAT|STR|ERR|OBJ|LIST|MAP|BOOL|FLYWEIGHT|SYM)\b',
    ),
    // Numeric literals (floats first).
    Mode(
      className: 'number',
      begin: r'\b\d*\.\d+([eE][-+]?\d+)?\b',
    ),
    Mode(
      className: 'number',
      begin: r'\b\d+([eE][-+]?\d+)?\b',
    ),
    // Keywords and built-in constants.
    Mode(
      className: 'keyword',
      begin:
          r'\b(if|elseif|else|endif|while|endwhile|for|endfor|try|except|endtry|finally|fork|endfork|begin|end|return|break|continue|pass|raise|let|const|global|fn|endfn|any|in|true|false)\b',
    ),
  ],
);
