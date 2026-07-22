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

String? normalizeMooFenceInfo(String? info) {
  if (info == null) return null;
  final trimmed = info.trim().toLowerCase();
  if (trimmed.isEmpty) return null;
  if (trimmed == 'moocode') return 'moo';
  return trimmed;
}

bool isMooLanguage(String? info) => normalizeMooFenceInfo(info) == 'moo';

String highlightMooCodeToHtml(String code) {
  final out = StringBuffer();
  var i = 0;
  while (i < code.length) {
    final lineEnd = code.indexOf('\n', i);
    final end = lineEnd == -1 ? code.length : lineEnd;
    final line = code.substring(i, end);
    out.write(_highlightMooLine(line));
    if (lineEnd != -1) {
      out.write('\n');
      i = lineEnd + 1;
    } else {
      i = code.length;
    }
  }
  return out.toString();
}

String _highlightMooLine(String line) {
  final commentPos = line.indexOf('//');
  String codePart;
  String? commentPart;
  if (commentPos >= 0) {
    codePart = line.substring(0, commentPos);
    commentPart = line.substring(commentPos);
  } else {
    codePart = line;
  }

  final tokenRe = RegExp(
    r'''("(?:\\.|[^"\\])*"|#[+-]?\d+|\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\b(?:if|elseif|else|endif|while|endwhile|for|endfor|try|except|endtry|finally|fork|endfork|begin|end|return|break|continue|pass|raise|let|const|global|fn|endfn|any|in|true|false)\b)''',
  );
  final buf = StringBuffer();
  var last = 0;
  for (final m in tokenRe.allMatches(codePart)) {
    if (m.start > last) {
      buf.write(_escapeHtml(codePart.substring(last, m.start)));
    }
    final tok = m.group(0)!;
    final cls = _mooTokenClass(tok);
    if (cls == null) {
      buf.write(_escapeHtml(tok));
    } else {
      buf.write('<span class="$cls">${_escapeHtml(tok)}</span>');
    }
    last = m.end;
  }
  if (last < codePart.length) {
    buf.write(_escapeHtml(codePart.substring(last)));
  }

  if (commentPart != null) {
    buf.write('<span class="moo-comment">${_escapeHtml(commentPart)}</span>');
  }
  return buf.toString();
}

String? _mooTokenClass(String token) {
  if (token.startsWith('"')) return 'moo-string';
  if (token.startsWith('#')) return 'moo-number';
  if (RegExp(r'^\d').hasMatch(token)) return 'moo-number';
  return 'moo-keyword';
}

String _escapeHtml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
