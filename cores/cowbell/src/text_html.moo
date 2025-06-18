object TEXT_HTML
  name: "Text HTML Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for HTML content. Stores HTML elements as structured data and provides methods for combining and rendering to XML.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, {@args}>;
  endverb

  verb mk_element (this none this) owner: HACKER flags: "rxd"
    {tag, ?attrs = {}, @content} = args;
    typeof(tag) != STR && raise(E_TYPE, "Tag must be string");
    typeof(attrs) != LIST && typeof(attrs) != MAP && raise(E_TYPE, "Attrs must be list or map");
    "Convert attrs to proper format for to_xml: {tag, attributes_list, content...}";
    attributes_list = {};
    if (typeof(attrs) == LIST && length(attrs) > 0)
      "Convert flat attribute list to attribute pairs";
      i = 1;
    while (i <= length(attrs))
        if (i + 1 <= length(attrs))
          attributes_list = {@attributes_list, attrs[i], attrs[i + 1]};
          i = i + 2;
        else
          i = i + 1;
        endif
      endwhile
    elseif (typeof(attrs) == MAP && length(mapkeys(attrs)) > 0)
      "Convert map to flat attribute list";
      for key in (mapkeys(attrs))
        attributes_list = {@attributes_list, tostr(key), tostr(attrs[key])};
      endfor
    endif
    "Create element in proper format: {tag, attributes_list, content...}";
    element = {tag, attributes_list, @content};
    return <this, {element}>;
  endverb

  verb append_element (this none this) owner: HACKER flags: "rxd"
    {element} = args;
    current_contents = {};
    for item in (this)
      current_contents = {@current_contents, item};
    endfor
    return <$text_html, {@current_contents, element}>;
  endverb

  verb append_elements (this none this) owner: HACKER flags: "rxd"
    {elements} = args;
    typeof(elements) != LIST && raise(E_TYPE, "Elements must be a list");
    return <this, {@this, @elements}>;
  endverb

  verb render (this none this) owner: HACKER flags: "rxd"
    "Convert to final HTML string format using to_xml";
    result_parts = {};
    for element in (this)
      if (typeof(element) == STR)
        result_parts = {@result_parts, element};
      elseif (typeof(element) == LIST && length(element) >= 1 && typeof(element[1]) == STR)
        "This is structured HTML data like {\"p\", content}";
        "Need to render any flyweights within the list structure first";
        processed_element = this:process_list_content(element);
        rendered = to_xml(processed_element);
        result_parts = {@result_parts, rendered};
      elseif (typeof(element) == FLYWEIGHT)
        rendered = element:render();
        if (typeof(rendered) == LIST)
          for item in (rendered)
            result_parts = {@result_parts, item};
          endfor
        else
          result_parts = {@result_parts, rendered};
        endif
      else
        result_parts = {@result_parts, tostr(element)};
      endif
    endfor
    "For HTML, return as single joined string";
    return {result_parts:join("")};
  endverb

  verb process_list_content (this none this) owner: HACKER flags: "rxd"
    "Recursively process list content to handle nested flyweights";
    {element} = args;
    typeof(element) != LIST && return element;
    processed = {};
    for item in (element)
      if (typeof(item) == FLYWEIGHT)
        "For HTML flyweights, extract each content item individually";
        "This preserves the nested structure properly";
        for flyweight_item in (item)
          processed = {@processed, flyweight_item};
        endfor
      elseif (typeof(item) == LIST && length(item) >= 1 && typeof(item[1]) == STR)
        "This looks like a proper XML structure {tag, ...} - pass through as-is";
        processed = {@processed, item};
      elseif (typeof(item) == LIST)
        "Recursively process other nested lists";
        processed = {@processed, this:process_list_content(item)};
      else
        processed = {@processed, item};
      endif
    endfor
    return processed;
  endverb

  verb test_html_content (this none this) owner: HACKER flags: "rxd"
    "Test basic element creation";
    p_elem = this:mk_element("p", {}, "Hello World");
    typeof(p_elem) != FLYWEIGHT && raise(E_ASSERT, "mk_element should return flyweight");
    length(p_elem) != 1 && raise(E_ASSERT, "Should have 1 element");
    "Test element with attributes";
    div_elem = this:mk_element("div", {"class", "test", "id", "main"}, "Content");
    length(div_elem) != 1 && raise(E_ASSERT, "Div should have 1 element");
    "Test combining elements";
    combined = p_elem:append_element(div_elem[1]);
    length(combined) != 2 && raise(E_ASSERT, "Combined should have 2 elements");
    "Test rendering";
    rendered = combined:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    length(rendered) != 1 && raise(E_ASSERT, "Should be single HTML string");
    typeof(rendered[1]) != STR && raise(E_ASSERT, "Should be string");
    "Test that it contains expected HTML";
    html_string = rendered[1];
    "<p>Hello World</p>" in html_string || raise(E_ASSERT, "Should contain p element: " + toliteral(html_string));
  endverb
endobject
