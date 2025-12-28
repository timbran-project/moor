object FORMAT_PARAGRAPH
  name: "Paragraph Content Flyweight Delegate"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override import_export_hierarchy = {"format"};
  override import_export_id = "format_paragraph";

  verb mk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a paragraph from mixed content (strings, links, etc).";
    "Args: list of parts OR variable args of parts.";
    "Example: $format.paragraph:mk({\"Text \", $format.link:cmd(\"go north\", \"north\"), \".\"})";
    "Example: $format.paragraph:mk(\"Simple text paragraph\")";
    if (length(args) == 1 && typeof(args[1]) == LIST)
      parts = args[1];
    else
      parts = args;
    endif
    return <this, {@parts}>;
  endverb

  verb compose (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Compose paragraph content for the given content type.";
    "Returns <p> for HTML (block-level), concatenated string for text.";
    {render_for, content_type, event} = args;
    parts = flycontents(this);
    if (content_type == 'text_html)
      "Build HTML paragraph with mixed content";
      html_parts = {};
      for part in (parts)
        if (typeof(part) == FLYWEIGHT)
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
      if (typeof(part) == FLYWEIGHT)
        result = result + part:compose(render_for, content_type, event);
      else
        result = result + tostr(part);
      endif
    endfor
    return result;
  endverb
endobject
