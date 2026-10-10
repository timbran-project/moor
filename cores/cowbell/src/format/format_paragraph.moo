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
    "Example: $format.paragraph:mk({\"Text \", $format.annotation:command(\"go north\", \"north\"), \".\"})";
    "Example: $format.paragraph:mk(\"Simple text paragraph\")";
    if (length(args) == 1 && typeof(args[1]) == TYPE_LIST)
      parts = args[1];
    else
      parts = args;
    endif
    return <this, {@parts}>;
  endmethod

  method inline owner: ARCH_WIZARD
    "Group adjacent inline fragments without adding a paragraph boundary.";
    return <this, .inline = true, {@args}>;
  endmethod

  method compose owner: ARCH_WIZARD
    "Compose paragraph children while preserving their annotations.";
    const {render_for, content_type, event} = args;
    const {parts, annotations} = $format:compose_parts(flycontents(this), @args);
    const body = content_type == 'text_html ? <$html, {`this.inline ! E_PROPNF => false' ? "span" | "p", {}, parts}> | parts:join("");
    return $format:result(body, annotations);
  endmethod
endobject
