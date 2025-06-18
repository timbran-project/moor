object BLOCK
  name: "Multiline Block Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb append_to_flyweight (this none this) owner: HACKER flags: "rxd"
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
    "Return appropriate content flyweight based on content type";
    if (content_type == 'text_plain)
      return $text_plain:mk(@result);
    elseif (content_type == 'text_markdown || content_type == 'text_djot)
      "For markdown, pass elements but mark as block content";
      return $text_markdown:mk_block(@result);
    elseif (content_type == 'text_html)
      "For HTML, create paragraph elements";
      html_content = $text_html:mk();
      for line in (result)
        if (typeof(line) == FLYWEIGHT)
          "Extract the content from HTML flyweights to nest properly";
          line_content = {};
          for item in (line)
            line_content = {@line_content, item};
          endfor
          if (length(line_content) == 1)
            p_element = {"p", {}, line_content[1]};
          else
            p_element = {"p", {}, @line_content};
          endif
        else
          p_element = {"p", {}, line};
        endif
        html_content = html_content:append_element(p_element);
      endfor
      return html_content;
    else
      "Default to text_plain";
      return $text_plain:mk(@result);
    endif
  endverb

  verb test_multiline_render (this none this) owner: HACKER flags: "rxd"
    lines = this:mk("a", "b", "c");
    result = lines:compose(player, 'text_plain, $nothing);
    typeof(result) != FLYWEIGHT && raise(E_ASSERT, "compose should return flyweight: " + toliteral(result));
    length(result) != 3 && raise(E_ASSERT, "content wrong length: " + toliteral(result));
    rendered = result:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "render should return list: " + toliteral(rendered));
  endverb
endobject
