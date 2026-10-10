object FORMAT_TEXT [
  import_export_id -> "format_text",
  import_export_hierarchy -> {"format"}
]
  name: "Literal Text"
  parent: ROOT
  owner: HACKER
  readable: true

  method mk owner: HACKER
    "Render literal text without interpreting it as markup.";
    const {text} = args;
    typeof(text) == TYPE_STR || raise(E_TYPE);
    return <this, {text}>;
  endmethod

  method compose owner: HACKER
    const {render_for, content_type, event} = args;
    const {text} = flycontents(this);
    return content_type == 'text_djot ? this:escape_djot(text) | text;
  endmethod

  method escape_djot owner: HACKER
    "Escape literal text for Djot, including table delimiters and attribute syntax.";
    const {text} = args;
    let escaped = "";
    for i in [1..length(text)]
      const ch = text[i];
      const punctuation = index("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", ch);
      escaped = escaped + (punctuation ? "\\" | "") + ch;
    endfor
    return escaped;
  endmethod
endobject
