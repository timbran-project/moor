object CONTENT_TESTS
  name: "Content Architecture Unit Tests"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Comprehensive unit tests for the flyweight-based content architecture.";

  verb test_text_plain_basic (this none this) owner: HACKER flags: "rxd"
    "Test basic TEXT_PLAIN functionality";
    content = $text_plain:mk("Hello", "World");
    typeof(content) != FLYWEIGHT && raise(E_ASSERT, "mk should return flyweight");
    length(content) != 2 && raise(E_ASSERT, "Should have 2 elements");
    "Test append_element";
    content2 = content:append_element("!");
    length(content2) != 3 && raise(E_ASSERT, "Should have 3 elements after append");
    "Test rendering";
    rendered = content2:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    length(rendered) == 3 && rendered[1] == "Hello" && rendered[2] == "World" && rendered[3] == "!" || raise(E_ASSERT, "Content wrong: " + toliteral(rendered));
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

  verb test_title_composition (this none this) owner: HACKER flags: "rxd"
    "Test TITLE composition with different content types";
    title = $title:mk("Important Title");
    "Test text_plain composition";
    plain_content = title:compose(player, 'text_plain, $nothing);
    typeof(plain_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    plain_rendered = plain_content:render();
    "Important Title" in plain_rendered[1] || raise(E_ASSERT, "Should contain title text");
    "Test HTML composition";
    html_content = title:compose(player, 'text_html, $nothing);
    typeof(html_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    html_rendered = html_content:render();
    typeof(html_rendered) == LIST && length(html_rendered) == 1 || raise(E_ASSERT, "Should be single HTML string");
    "<em>Important Title</em>" in html_rendered[1] || raise(E_ASSERT, "Should contain em tag");
    "Test markdown composition";
    md_content = title:compose(player, 'text_markdown, $nothing);
    typeof(md_content) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    md_rendered = md_content:render();
    "*Important Title*" in md_rendered[1] || raise(E_ASSERT, "Should contain markdown emphasis");
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

  verb test_content_type_isolation (this none this) owner: HACKER flags: "rxd"
    "Test that different content types don't interfere with each other";
    block = $block:mk("Same content");
    plain_result = block:compose(player, 'text_plain, $nothing);
    html_result = block:compose(player, 'text_html, $nothing);
    md_result = block:compose(player, 'text_markdown, $nothing);
    "Verify they're all different flyweight types";
    typeof(plain_result) == FLYWEIGHT || raise(E_ASSERT, "Plain should be flyweight");
    typeof(html_result) == FLYWEIGHT || raise(E_ASSERT, "HTML should be flyweight");
    typeof(md_result) == FLYWEIGHT || raise(E_ASSERT, "Markdown should be flyweight");
    "Verify they render differently";
    plain_rendered = plain_result:render();
    html_rendered = html_result:render();
    md_rendered = md_result:render();
    plain_rendered[1] != html_rendered[1] || raise(E_ASSERT, "Plain and HTML should be different");
    plain_rendered[1] != md_rendered[1] || raise(E_ASSERT, "Plain and markdown should be different");
    html_rendered[1] != md_rendered[1] || raise(E_ASSERT, "HTML and markdown should be different");
  endverb

  verb test_error_handling (this none this) owner: HACKER flags: "rxd"
    "Test proper error handling";
    "Test empty title rejection";
    `$title:mk() ! E_INVARG => false' || raise(E_ASSERT, "Should reject empty titles");
    "Test invalid title args";
    `$title:mk("a", "b") ! E_INVARG => false' || raise(E_ASSERT, "Should reject multiple title args");
    "Test invalid HTML element";
    try
      $text_html:mk_element(123, {}, "content");
      raise(E_ASSERT, "Should reject non-string tag names");
    except (E_TYPE)
      "Expected error";
    endtry
  endverb

  verb test_title_block_render (this none this) owner: HACKER flags: "rxd"
    "Test BLOCK with title flyweight and string";
    title = $title:mk("Room Title");
    block = $block:mk(title, "Description text");
    plain_rendered = block:compose(player, 'text_plain, $nothing):render();
    typeof(plain_rendered) == LIST || raise(E_ASSERT, "Plain should produce list: " + toliteral(plain_rendered));
    length(plain_rendered) >= 2 || raise(E_ASSERT, "Plain should have at least 2 elements: " + toliteral(plain_rendered));
    md_rendered = block:compose(player, 'text_markdown, $nothing):render();
    typeof(md_rendered) == LIST || raise(E_ASSERT, "Markdown should produce list: " + toliteral(md_rendered));
    length(md_rendered) >= 2 || raise(E_ASSERT, "Markdown should have at least 2 elements: " + toliteral(md_rendered));
    "Check that we don't have everything joined into one element";
    title_and_desc_joined = false;
    for item in (md_rendered)
      if ("Room Title" in item && "Description text" in item)
        title_and_desc_joined = true;
      endif
    endfor
    !title_and_desc_joined || raise(E_ASSERT, "Title and description should be separate elements, got: " + toliteral(md_rendered));
  endverb
endobject
