// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object FORMAT_LINK [
  import_export_id -> "format_link",
  import_export_hierarchy -> {"format"}
]
  name: "Link Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description (owner: HACKER, flags: "rc") = "External URLs and inline formatted content.";

  method external owner: HACKER
    "Create an external link that opens a URL in a new tab.";
    "Args: (url) or (url, label)";
    {url, ?label = false} = args;
    typeof(url) == TYPE_STR || raise(E_TYPE, "URL must be a string");
    label = label ? label | url;
    return <this, .link_type = 'external, .url = url, .label = label>;
  endmethod

  method compose owner: HACKER
    "Render link for the given content type.";
    {render_for, content_type, event} = args;
    if (this.link_type == 'inline)
      return this:_compose_inline(@args);
    endif
    if (content_type == 'text_html)
      return this:to_html();
    endif
    if (content_type == 'text_djot)
      return this:to_djot();
    endif
    return this.label;
  endmethod

  method to_djot owner: HACKER
    "Render an external URL with an escaped Djot label.";
    return "[" + $format.annotation:escape_djot(this.label) + "](" + this.url + "){.external}";
  endmethod

  method to_html owner: HACKER
    "Render an external URL as an escaped HTML anchor.";
    return <$html, {"a", {"href", this.url, "class", "external", "target", "_blank"}, {this.label}}>;
  endmethod

  method inline owner: HACKER
    "Create inline content mixing text and links.";
    "Args: list of strings and link flyweights to be composed inline.";
    "Example: $format.link:inline({'Exits: ', $format.annotation:command('north'), ', ', $format.annotation:command('south')})";
    {parts} = args;
    typeof(parts) == TYPE_LIST || raise(E_TYPE, "Parts must be a list");
    return <this, .link_type = 'inline, {@parts}>;
  endmethod

  method _compose_inline owner: HACKER
    "Compose inline fragments while preserving their occurrence tables.";
    const {render_for, content_type, event} = args;
    const {parts, annotations} = $format:compose_parts(flycontents(this), @args);
    const body = content_type == 'text_html ? <$html, {"span", {}, parts}> | parts:join("");
    return $format:result(body, annotations);
  endmethod

  method ambient_passage owner: HACKER
    "Create an ambient passage description with a exit command annotation.";
    "Args: {description, direction, room}. The link retains its originating room.";
    const {description, direction, room} = args;
    typeof(description) == TYPE_STR || raise(E_TYPE, "Description must be a string");
    typeof(direction) == TYPE_STR || raise(E_TYPE, "Direction must be a string");
    "Find the direction in the description";
    idx = index(description, direction);
    if (idx == 0)
      "Direction not found in description - append link at end";
      parts = {description, " (", $format.annotation:exit(room, direction), ")"};
    else
      "Split description around direction and insert link";
      before = description[1..idx - 1];
      "Get the actual text that matched (preserve original case)";
      matched = description[idx..idx + length(direction) - 1];
      after = description[idx + length(direction)..length(description)];
      parts = {before, $format.annotation:exit(room, direction, matched), after};
    endif
    return <this, .link_type = 'inline, {@parts}>;
  endmethod

  verb linkify_direction (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Replace a direction word in a description with a exit command annotation.";
    "Args: (description, direction, room, ?lowercase=false) - returns inline flyweight or original string.";
    const {description, direction, room, ?lowercase = false} = args;
    typeof(description) == TYPE_STR || return description;
    typeof(direction) == TYPE_STR || return description;
    "Find the direction word in the description (case-insensitive)";
    pos = index(description, direction);
    !pos && return lowercase ? description:initial_lowercase() | description;
    "Split and create inline with link";
    before = pos > 1 ? description[1..pos - 1] | "";
    if (lowercase && length(before) > 0)
      before = before:initial_lowercase();
    endif
    after = pos + length(direction) <= length(description) ? description[pos + length(direction)..length(description)] | "";
    "Cowbell supplies both the invocation and the passage descriptor.";
    link = $format.annotation:exit(room, direction);
    return this:inline({before, link, after});
  endverb
endobject
