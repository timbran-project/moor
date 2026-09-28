// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later
object FORMAT [
  import_export_id -> "format",
  import_export_hierarchy -> {"format"}
]
  name: "Format Objects"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  property annotation (owner: HACKER, flags: "r") = FORMAT_ANNOTATION;
  property block (owner: HACKER, flags: "r") = FORMAT_BLOCK;
  property code (owner: HACKER, flags: "r") = FORMAT_CODE;
  property deflist (owner: HACKER, flags: "r") = FORMAT_DEFLIST;
  property link (owner: HACKER, flags: "r") = FORMAT_LINK;
  property list (owner: HACKER, flags: "r") = FORMAT_LIST;
  property paragraph (owner: ARCH_WIZARD, flags: "r") = FORMAT_PARAGRAPH;
  property table (owner: HACKER, flags: "r") = FORMAT_TABLE;
  property title (owner: HACKER, flags: "r") = FORMAT_TITLE;

  override description (owner: HACKER, flags: "rc") = "Container for formatting objects like block, list, table, and title.";
  method result owner: HACKER
    "An unannotated fragment needs no envelope. Annotated fragments carry their own table.";
    const {content, annotations} = args;
    return length(annotations) ? ["content" -> content, "annotations" -> annotations] | content;
  endmethod

  method unpack owner: HACKER
    "Return a fragment body and its occurrence table.";
    const {fragment} = args;
    return typeof(fragment) == TYPE_MAP ? {fragment["content"], fragment["annotations"]} | {fragment, []};
  endmethod

  method merge_annotations owner: HACKER
    "Bound retained metadata. Unlisted anchors remain readable but inert.";
    let {table, additions} = args;
    for id in (mapkeys(additions))
      const descriptor = additions[id];
      if (length(table) >= 512)
        break;
      endif
      table[id] = descriptor;
    endfor
    return table;
  endmethod

  method compose_parts owner: HACKER
    "Compose children independently and collect their body/table pairs without shared state.";
    const {parts, render_for, content_type, ?event = false} = args;
    let bodies = {};
    let annotations = [];
    for part in (parts)
      const composed = `part:compose(render_for, content_type, event) ! E_VERBNF => tostr(part)';
      const {body, table} = this:unpack(composed);
      bodies = {@bodies, body};
      annotations = this:merge_annotations(annotations, table);
    endfor
    return {bodies, annotations};
  endmethod
endobject
