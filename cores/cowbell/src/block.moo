object BLOCK
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb append_to_content (this none this) owner: HACKER flags: "rxd"
    "Append this block to a content flyweight while preserving block structure";
    {target_flyweight} = args;
    "Just append our content to the target flyweight";
    typeof(target_flyweight) != FLYWEIGHT && raise(E_TYPE, "Target must be a flyweight");
    target_flyweight = target_flyweight:append_element(this);
    return target_flyweight;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    result = {};
    for line_no in [1..length(this)]
      content = this[line_no];
      if (typeof(content) == STR)
        result = {@result, content};
      elseif (typeof(content) == FLYWEIGHT)
        result = {@result, content:compose(@args)};
      else
        raise(E_TYPE);
      endif
    endfor
    if (content_type == 'text_html)
      return <$html, {"p", {}, result}>;
    else
      return result;
    endif
  endverb
endobject