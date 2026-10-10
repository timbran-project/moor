object FORMAT_DEFLIST [
  import_export_id -> "FORMAT_DEFLIST",
  import_export_hierarchy -> {"format"}
]
  name: "Definition List Flyweight Delegate"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description (owner: ARCH_WIZARD, flags: "rc") = "Flyweight delegate for definition lists (key-value pairs) in events.";

  method mk owner: ARCH_WIZARD
    "Create deflist flyweight from a list of {term, definition} pairs.";
    "Preserves order (unlike maps which sort alphabetically).";
    {items} = args;
    typeof(items) != TYPE_LIST && raise(E_TYPE, "Items must be a list of {term, definition} pairs");
    return toflyweight(this, ['items -> items]);
  endmethod

  method compose owner: ARCH_WIZARD
    "Compose definition list into appropriate format.";
    "Items is a list of {term, definition} pairs.";
    {render_for, content_type, event} = args;
    items = {};
    let annotations = [];
    for raw_pair in (this.items)
      const {pair_parts, pair_annotations} = $format:compose_parts(raw_pair, @args);
      items = {@items, pair_parts};
      annotations = $format:merge_annotations(annotations, pair_annotations);
    endfor
    if (!items || length(items) == 0)
      if (content_type == 'text_html)
        return <$html, {"p", {}, {"(empty)"}}>;
      else
        return "(empty)";
      endif
    endif
    if (content_type == 'text_html)
      "Build HTML definition list";
      dl_children = {};
      for pair in (items)
        {term, defn} = pair;
        defn_content = defn;
        dl_children = {@dl_children, <$html, {"dt", {}, {term}}>};
        dl_children = {@dl_children, <$html, {"dd", {}, {defn_content}}>};
      endfor
      return $format:result(<$html, {"dl", {}, dl_children}>, annotations);
    elseif (content_type == 'text_djot)
      "Djot definition list syntax";
      result = {};
      for pair in (items)
        {term, defn} = pair;
        defn_str = defn;
        result = {@result, ": " + tostr(term)};
        result = {@result, ""};
        "Indent each line of definition";
        for line in (defn_str:split("\n"))
          result = {@result, "  " + line};
        endfor
        result = {@result, ""};
      endfor
      return $format:result(result:join("\n"), annotations);
    endif
    "Plain text - aligned label: value";
    "Calculate max label width";
    max_width = 0;
    for pair in (items)
      {term, defn} = pair;
      term_len = length(tostr(term));
      if (term_len > max_width)
        max_width = term_len;
      endif
    endfor
    result = {};
    for pair in (items)
      {term, defn} = pair;
      defn_str = defn;
      label = $str_proto:pad_right(tostr(term) + ":", max_width + 1);
      result = {@result, label + " " + defn_str};
    endfor
    return $format:result(result:join("\n"), annotations);
  endmethod
endobject
