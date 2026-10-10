object FORMAT_TITLE [
  import_export_id -> "format_title",
  import_export_hierarchy -> {"format"}
]
  name: "Title Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description (owner: HACKER, flags: "rc") = "Flyweight delegate for title/heading content in events.";

  method mk owner: HACKER
    "Create a title flyweight. Args: (content) or (content, level)";
    {content, ?level = 3} = args;
    typeof(level) == TYPE_INT || raise(E_TYPE, "Level must be an integer");
    level >= 1 && level <= 6 || raise(E_INVARG, "Level must be between 1 and 6");
    return <this, .level = level, {content}>;
  endmethod

  method compose owner: HACKER
    "Compose a heading while preserving inline annotations.";
    const {render_for, content_type, event} = args;
    const {parts, annotations} = $format:compose_parts(flycontents(this), @args);
    const level = this.level;
    if (content_type == 'text_html)
      return $format:result(<$html, {"h" + tostr(level), {}, parts}>, annotations);
    endif
    const body = content_type == 'text_djot ? "#":repeat(level) + " " + parts:join("") + "\n\n" | parts:join("") + "\n";
    return $format:result(body, annotations);
  endmethod
endobject
