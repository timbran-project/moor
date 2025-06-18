object TEXT_PLAIN
  name: "Text Plain Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for plain text content. Stores text elements as a list and provides methods for combining and rendering them.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb append_element (this none this) owner: HACKER flags: "rxd"
    {element} = args;
    current_contents = {};
    for item in (this)
      current_contents = {@current_contents, item};
    endfor
    return <$text_plain, {@current_contents, element}>;
  endverb

  verb append_elements (this none this) owner: HACKER flags: "rxd"
    {elements} = args;
    typeof(elements) != LIST && raise(E_TYPE, "Elements must be a list");
    return <this, {@this, @elements}>;
  endverb

  verb render (this none this) owner: HACKER flags: "rxd"
    "Convert to final text format - for text_plain, return elements as separate strings";
    result = {};
    for element in (this)
      if (typeof(element) == STR)
        result = {@result, element};
      elseif (typeof(element) == FLYWEIGHT)
        rendered = element:render();
        if (typeof(rendered) == LIST)
          for item in (rendered)
            result = {@result, item};
          endfor
        else
          result = {@result, rendered};
        endif
      else
        result = {@result, tostr(element)};
      endif
    endfor
    return result;
  endverb

  verb test_text_plain (this none this) owner: HACKER flags: "rxd"
    content = this:mk("Hello", "World");
    typeof(content) != FLYWEIGHT && raise(E_ASSERT, "mk should return flyweight");
    length(content) != 2 && raise(E_ASSERT, "Content should have 2 elements");
    content2 = content:append_element("!");
    length(content2) != 3 && raise(E_ASSERT, "Should have 3 elements after append");
    rendered = content2:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    length(rendered) != 3 && raise(E_ASSERT, "Should preserve 3 separate elements");
    rendered[1] != "Hello" && raise(E_ASSERT, "First element wrong: " + toliteral(rendered));
    rendered[2] != "World" && raise(E_ASSERT, "Second element wrong: " + toliteral(rendered));
    rendered[3] != "!" && raise(E_ASSERT, "Third element wrong: " + toliteral(rendered));
  endverb
endobject
