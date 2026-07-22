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

String normalizeContentType(String? raw, {String fallback = 'text/plain'}) {
  if (raw == null) {
    return fallback;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  // Handle values like "text/html; charset=utf-8".
  final semi = trimmed.indexOf(';');
  var base = (semi >= 0 ? trimmed.substring(0, semi) : trimmed)
      .trim()
      .toLowerCase();
  if (base.isEmpty) {
    return fallback;
  }

  // mooR sometimes encodes content types as Symbols, and Symbols don't allow
  // '/'. In that case the server uses '_' separators (e.g. "text_html").
  // Normalize to the slash form expected by the client renderers.
  if (base.startsWith('text_')) {
    base = switch (base) {
      'text_plain' => 'text/plain',
      'text_html' => 'text/html',
      'text_djot' => 'text/djot',
      'text_traceback' => 'text/traceback',
      'text_x_uri' => 'text/x-uri',
      _ => base,
    };
  }

  return base;
}
