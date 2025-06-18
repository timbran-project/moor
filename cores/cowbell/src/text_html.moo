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

  verb test_text_html_basic (this none this) owner: HACKER flags: "rxd"
    "Test basic TEXT_HTML functionality";
    p_elem = $text_html:mk_element("p", {}, "Hello World");
    typeof(p_elem) != FLYWEIGHT && raise(E_ASSERT, "mk_element should return flyweight");
    "Test rendering single element";
    rendered = p_elem:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    length(rendered) == 1 || raise(E_ASSERT, "Should be single HTML string");
    "<p>Hello World</p>" in rendered[1] || raise(E_ASSERT, "Should contain p element");
    "Test element with attributes";
    div_elem = $text_html:mk_element("div", {"class", "test", "id", "main"}, "Content");
    div_rendered = div_elem:render();
    "class=\"test\"" in div_rendered[1] || raise(E_ASSERT, "Should contain class attribute: " + toliteral(div_rendered[1]));
    "id=\"main\"" in div_rendered[1] || raise(E_ASSERT, "Should contain id attribute");
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

  verb test_xml_structure_validation (this none this) owner: HACKER flags: "rxd"
    "Test that generated HTML is valid XML";
    title = $title:mk("Test Title");
    block = $block:mk("Test content");
    title_html = title:compose(player, 'text_html, $nothing);
    block_html = block:compose(player, 'text_html, $nothing);
    combined = $text_html:mk():append_element(title_html):append_element(block_html);
    rendered = combined:render();
    "Try to parse the generated HTML as XML";
    try
      wrapped = "<root>" + rendered[1] + "</root>";
      parsed = xml_parse(wrapped);
      typeof(parsed) == LIST || raise(E_ASSERT, "Should parse as valid XML");
      length(parsed) >= 1 || raise(E_ASSERT, "Should have root element");
    except (ANY)
      raise(E_ASSERT, "Generated HTML should be valid XML: " + toliteral(rendered[1]));
    endtry
  endverb

  verb test_nested_flyweights (this none this) owner: HACKER flags: "rxd"
    "Test composition with nested flyweight content";
    title = $title:mk("Page Title");
    block = $block:mk("First line", "Second line");
    "Test combining title and block in HTML";
    html_content = $text_html:mk();
    title_html = title:compose(player, 'text_html, $nothing);
    block_html = block:compose(player, 'text_html, $nothing);
    combined = html_content:append_element(title_html):append_element(block_html);
    rendered = combined:render();
    typeof(rendered) == LIST && length(rendered) == 1 || raise(E_ASSERT, "Should be single HTML string");
    html_string = rendered[1];
    "<em>Page Title</em>" in html_string || raise(E_ASSERT, "Should contain title em tag");
    "<p>First line</p>" in html_string || raise(E_ASSERT, "Should contain first paragraph");
    "<p>Second line</p>" in html_string || raise(E_ASSERT, "Should contain second paragraph");
  endverb

  verb test_block_composition (this none this) owner: HACKER flags: "rxd"
    "Test BLOCK composition with different content types";
    block = $block:mk("Line 1", "Line 2", "Line 3");
    "Test text_plain composition";
    plain_content = block:compose(player, 'text_plain, $nothing);
    typeof(plain_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    length(plain_content) == 3 || raise(E_ASSERT, "Should have 3 lines");
    "Test HTML composition";
    html_content = block:compose(player, 'text_html, $nothing);
    typeof(html_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    html_rendered = html_content:render();
    typeof(html_rendered) == LIST && length(html_rendered) == 1 || raise(E_ASSERT, "Should be single HTML string");
    "Verify all lines are in separate p tags";
    html_string = html_rendered[1];
    "<p>Line 1</p>" in html_string || raise(E_ASSERT, "Should contain Line 1 in p tag");
    "<p>Line 2</p>" in html_string || raise(E_ASSERT, "Should contain Line 2 in p tag");
    "<p>Line 3</p>" in html_string || raise(E_ASSERT, "Should contain Line 3 in p tag");
    "Test markdown composition";
    md_content = block:compose(player, 'text_markdown, $nothing);
    typeof(md_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    md_rendered = md_content:render();
    typeof(md_rendered) == LIST || raise(E_ASSERT, "Should be list");
  endverb

  verb test_content_composition (this none this) owner: HACKER flags: "rxd"
    "Test combining different content elements";
    html_content = $text_html:mk();
    p1 = {"p", {}, "First paragraph"};
    p2 = {"p", {}, "Second paragraph"};
    combined = html_content:append_element(p1):append_element(p2);
    length(combined) == 2 || raise(E_ASSERT, "Should have 2 elements");
    rendered = combined:render();
    typeof(rendered) == LIST && length(rendered) == 1 || raise(E_ASSERT, "Should be single HTML string");
    "<p>First paragraph</p>" in rendered[1] || raise(E_ASSERT, "Should contain first paragraph");
    "<p>Second paragraph</p>" in rendered[1] || raise(E_ASSERT, "Should contain second paragraph");
  endverb
endobject
