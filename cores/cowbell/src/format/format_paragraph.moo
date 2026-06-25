object FORMAT_PARAGRAPH [
  import_export_id -> "format_paragraph",
  import_export_hierarchy -> {"format"}
]
  name: "Paragraph Content Flyweight Delegate"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  method mk owner: ARCH_WIZARD
    "Create a paragraph from mixed content (strings, links, etc).";
    "Args: list of parts OR variable args of parts.";
    "Example: $format.paragraph:mk({\"Text \", $format.link:cmd(\"go north\", \"north\"), \".\"})";
    "Example: $format.paragraph:mk(\"Simple text paragraph\")";
    if (length(args) == 1 && typeof(args[1]) == TYPE_LIST)
      parts = args[1];
    else
      parts = args;
    endif
    return <this, {@parts}>;
  endmethod

  method compose owner: ARCH_WIZARD
    "Compose paragraph content for the given content type.";
    "Returns <p> for HTML (block-level), concatenated string for text.";
    {render_for, content_type, event} = args;
    parts = flycontents(this);
    if (content_type == 'text_html)
      "Build HTML paragraph with mixed content";
      html_parts = {};
      for part in (parts)
        if (typeof(part) == TYPE_FLYWEIGHT)
          html_parts = {@html_parts, part:compose(render_for, content_type, event)};
        else
          html_parts = {@html_parts, tostr(part)};
        endif
      endfor
      return <$html, {"p", {}, html_parts}>;
    endif
    "Djot or plain text: concatenate as string";
    result = "";
    for part in (parts)
      if (typeof(part) == TYPE_FLYWEIGHT)
        result = result + part:compose(render_for, content_type, event);
      else
        result = result + tostr(part);
      endif
    endfor
    return result;
  endmethod
endobject
