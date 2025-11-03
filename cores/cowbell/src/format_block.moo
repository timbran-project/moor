object FORMAT_BLOCK
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for multiline block content in events. Used to compose paragraphs and structured text that can be rendered to both plain text and HTML.";
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
    for line_no in [1..length(this)]
      content = this[line_no];
      composed = content:compose(@args);
      if (content_type == 'text_html && typeof(composed) == STR)
        "Wrap bare text in paragraph tags for HTML";
        result = {@result, <$html, {"p", {}, {composed}}>};
      else
        result = {@result, composed};
      endif
    endfor
    content_type == 'text_html && return <$html, {"div", {}, result}>;
    return result;
  endverb
endobject