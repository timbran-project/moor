object TEXT_MARKDOWN
  name: "Text Markdown Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for markdown content. Stores markdown elements and provides methods for combining and rendering.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb mk_block (this none this) owner: HACKER flags: "rxd"
    "Create markdown content with block-level formatting (paragraph breaks between elements)";
    return <this, [is_block -> true], {@args}>;
  endverb

  verb append_element (this none this) owner: HACKER flags: "rxd"
    {element} = args;
    current_contents = {};
    for item in (this)
      current_contents = {@current_contents, item};
    endfor
    return <$text_markdown, {@current_contents, element}>;
  endverb

  verb append_elements (this none this) owner: HACKER flags: "rxd"
    {elements} = args;
    typeof(elements) != LIST && raise(E_TYPE, "Elements must be a list");
    return <this, {@this, @elements}>;
  endverb

  verb render (this none this) owner: HACKER flags: "rxd"
    "Convert to final markdown format";
    result = {};
    for element in (this)
      if (typeof(element) == STR)
        result = element:append_to_paragraph(@result);
      elseif (typeof(element) == FLYWEIGHT)
        rendered = element:render();
        if (typeof(rendered) == LIST)
          for item in (rendered)
            if (typeof(item) == STR)
              result = item:append_to_paragraph(@result);
            else
              result = tostr(item):append_to_paragraph(@result);
            endif
          endfor
        else
          if (typeof(rendered) == STR)
            result = rendered:append_to_paragraph(@result);
          else
            result = tostr(rendered):append_to_paragraph(@result);
          endif
        endif
      else
        result = tostr(element):append_to_paragraph(@result);
      endif
    endfor
    return result;
  endverb

  verb test_markdown_content (this none this) owner: HACKER flags: "rxd"
    content = this:mk("# Header", "Some text");
    typeof(content) != FLYWEIGHT && raise(E_ASSERT, "mk should return flyweight");
    length(content) != 2 && raise(E_ASSERT, "Content should have 2 elements");
    content2 = content:append_element("More text");
    length(content2) != 3 && raise(E_ASSERT, "Should have 3 elements after append");
    rendered = content2:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    typeof(rendered[1]) != STR && raise(E_ASSERT, "Should contain string");
  endverb
endobject
