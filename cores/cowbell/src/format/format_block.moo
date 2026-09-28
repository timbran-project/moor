// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object FORMAT_BLOCK [
  import_export_id -> "format_block",
  import_export_hierarchy -> {"format"}
]
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description (owner: HACKER, flags: "rc") = "Flyweight delegate for multiline block content in events. Used to compose paragraphs and structured text that can be rendered to both plain text and HTML.";

  method mk owner: HACKER
    return <this, {@args}>;
  endmethod

  method append_to_content owner: HACKER
    "Append this block to a content flyweight while preserving block structure";
    {target_flyweight} = args;
    "Just append our content to the target flyweight";
    typeof(target_flyweight) == TYPE_FLYWEIGHT || raise(E_TYPE, "Target must be a flyweight");
    target_flyweight = target_flyweight:append_element(this);
    return target_flyweight;
  endmethod

  method compose owner: HACKER
    "Compose block children while preserving their annotations.";
    const {render_for, content_type, event} = args;
    const {parts, annotations} = $format:compose_parts(flycontents(this), @args);
    const body = content_type == 'text_html ? <$html, {"div", {}, parts}> | parts:join("\n");
    return $format:result(body, annotations);
  endmethod
endobject
