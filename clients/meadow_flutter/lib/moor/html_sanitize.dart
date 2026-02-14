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

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

// Mirrors clients/meadow/src/lib/djot-renderer.ts allowlists.
const Set<String> kAllowedTags = {
  'p',
  'br',
  'div',
  'span',
  'strong',
  'b',
  'em',
  'i',
  'u',
  's',
  'ul',
  'ol',
  'li',
  'dl',
  'dt',
  'dd',
  'a',
  'img',
  'pre',
  'code',
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'td',
  'th',
  'small',
  'sup',
  'sub',
};

const Set<String> kAllowedAttr = {
  'href',
  'src',
  'alt',
  'title',
  'class',
  'id',
  'target',
  'rel',
  'style',
  'width',
  'height',
  'data-url',
  'tabindex',
  'role',
  'data-objid',
  'data-uuobjid',
  'aria-label',
};

bool isSafeUrl(String? url) {
  if (url == null) {
    return false;
  }
  final u = url.trim();
  if (u.isEmpty) {
    return false;
  }

  final lower = u.toLowerCase();
  if (lower.startsWith('javascript:')) return false;
  if (lower.startsWith('data:')) return false;
  if (lower.startsWith('vbscript:')) return false;
  if (lower.startsWith('file:')) return false;

  if (lower.startsWith('moo://')) return true;

  // Allow relative references for in-app rendering, but we don't auto-open them.
  if (u.startsWith('/') ||
      u.startsWith('#') ||
      u.startsWith('?') ||
      u.startsWith('./') ||
      u.startsWith('../')) {
    return true;
  }

  final parsed = Uri.tryParse(u);
  if (parsed == null) return false;
  return parsed.scheme == 'http' || parsed.scheme == 'https';
}

String sanitizeRestrictedHtml(String input) {
  final fragment = html.parseFragment(input);
  _sanitizeNode(fragment);
  return fragment.outerHtml;
}

void _sanitizeNode(dom.Node node) {
  // Remove disallowed elements entirely, but keep their text content when reasonable.
  if (node is dom.Element) {
    final tag = node.localName?.toLowerCase();
    if (tag == null || !kAllowedTags.contains(tag)) {
      // Replace with its children (drops the tag wrapper).
      final parent = node.parent;
      if (parent != null) {
        final idx = parent.nodes.indexOf(node);
        parent.nodes.removeAt(idx);
        for (final child in node.nodes.toList()) {
          parent.nodes.insert(idx, child);
        }
      }
      return;
    }

    // Filter attributes.
    final attrs = node.attributes.keys.toList();
    for (final keyObj in attrs) {
      final key = keyObj.toString();
      final lk = key.toLowerCase();
      if (!kAllowedAttr.contains(lk)) {
        node.attributes.remove(key);
        continue;
      }

      if (lk == 'href' || lk == 'src') {
        final v = node.attributes[key];
        if (!isSafeUrl(v)) {
          node.attributes.remove(key);
        }
      }
    }
  }

  // Recurse.
  for (final child in node.nodes.toList()) {
    _sanitizeNode(child);
  }
}
