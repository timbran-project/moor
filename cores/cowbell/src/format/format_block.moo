object FORMAT_BLOCK
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for multiline block content in events. Used to compose paragraphs and structured text that can be rendered to both plain text and HTML.";
  override import_export_hierarchy = {"format"};
  override import_export_id = "format_block";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb append_to_content (this none this) owner: HACKER flags: "rxd"
    "Append this block to a content flyweight while preserving block structure";
    {target_flyweight} = args;
    "Just append our content to the target flyweight";
    typeof(target_flyweight) == FLYWEIGHT || raise(E_TYPE, "Target must be a flyweight");
    target_flyweight = target_flyweight:append_element(this);
    return target_flyweight;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    result = {};
    contents = flycontents(this);
    for line_no in [1..length(contents)]
      content = contents[line_no];
      composed = content:compose(@args);
      if (content_type == 'text_html && typeof(composed) == STR)
        "Wrap bare text in paragraph tags for HTML";
        result = {@result, <$html, {"p", {}, {composed}}>};
      else
        result = {@result, composed};
      endif
    endfor
    if (content_type == 'text_html)
      return <$html, {"div", {}, result}>;
    endif
    "For text formats, collect string elements";
    text_lines = {};
    for element in (result)
      if (typeof(element) == STR)
        text_lines = {@text_lines, element};
      elseif (typeof(element) == LIST)
        "Flatten nested lists";
        for nested in (element)
          typeof(nested) == STR && (text_lines = {@text_lines, nested});
        endfor
      endif
    endfor
    "Join lines: empty strings become blank lines (double newline for djot paragraphs)";
    output = "";
    for i in [1..length(text_lines)]
      line = text_lines[i];
      if (i > 1)
        output = output + "\n";
      endif
      output = output + line;
    endfor
    return output;
  endverb
endobject