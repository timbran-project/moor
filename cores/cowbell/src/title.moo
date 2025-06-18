object TITLE
  name: "Title Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb mk (this none this) owner: HACKER flags: "rxd"
    length(args) != 1 && raise(E_INVARG, "Title must have one argument");
    return <this, {@args}>;
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    {render_for, content_type, event} = args;
    result = {};
    for content in (this)
      if (typeof(content) == STR)
        result = {@result, content};
      elseif (typeof(content) == FLYWEIGHT)
        result = {@result, content:compose(@args)};
      else
        raise(E_TYPE);
      endif
    endfor
    title_text = result:join(" ");
    "Return appropriate content flyweight based on content type";
    if (content_type == 'text_plain)
      return $text_plain:mk(title_text);
    elseif (content_type == 'text_markdown || content_type == 'text_djot)
      return $text_markdown:mk("*" + title_text + "*");
    elseif (content_type == 'text_html)
      em_element = {"em", {}, title_text};
      return $text_html:mk(em_element);
    else
      return $text_plain:mk(title_text);
    endif
  endverb

  verb test_title_render (this none this) owner: HACKER flags: "rxd"
    title = this:mk("Important Title");
    "Test text_plain composition";
    plain_result = title:compose(player, 'text_plain, $nothing);
    typeof(plain_result) != FLYWEIGHT && raise(E_ASSERT, "plain should be flyweight: " + toliteral(plain_result));
    plain_rendered = plain_result:render();
    typeof(plain_rendered) != LIST && raise(E_ASSERT, "plain render should be list");
    "Test markdown composition";
    md_result = title:compose(player, 'text_markdown, $nothing);
    typeof(md_result) != FLYWEIGHT && raise(E_ASSERT, "markdown should be flyweight: " + toliteral(md_result));
    md_rendered = md_result:render();
    typeof(md_rendered) != LIST && raise(E_ASSERT, "markdown render should be list");
    "Test HTML composition";
    html_result = title:compose(player, 'text_html, $nothing);
    typeof(html_result) != FLYWEIGHT && raise(E_ASSERT, "html should be flyweight: " + toliteral(html_result));
    html_rendered = html_result:render();
    typeof(html_rendered) != LIST && raise(E_ASSERT, "html render should be list");
    "Test that empty titles are rejected";
    `this:mk() ! E_INVARG => false' && raise(E_ASSERT, "Should reject empty titles");
  endverb

  verb test_title_with_flyweight (this none this) owner: HACKER flags: "rxd"
    "Test title containing a SUB flyweight like in LOOK events";
    sub_flyweight = $sub:dc();
    title = this:mk(sub_flyweight);
    typeof(title) != FLYWEIGHT && raise(E_ASSERT, "Title should be flyweight: " + toliteral(title));
    "Create a mock event for testing";
    mock_event = $event:mk_look(player, "test content"):with_dobj($first_room);
    "Test plain text composition";
    plain_result = title:compose(player, 'text_plain, mock_event);
    typeof(plain_result) != FLYWEIGHT && raise(E_ASSERT, "Plain result should be flyweight: " + toliteral(plain_result));
    "Test HTML composition";
    html_result = title:compose(player, 'text_html, mock_event);
    typeof(html_result) != FLYWEIGHT && raise(E_ASSERT, "HTML result should be flyweight: " + toliteral(html_result));
  endverb

  verb test_error_handling (this none this) owner: HACKER flags: "rxd"
    "Test empty title rejection";
    try
      $title:mk();
      raise(E_ASSERT, "Should reject empty titles");
    except (E_INVARG)
      "Expected error";
    endtry

    "Test invalid title args";
    try
      $title:mk("a", "b");
      raise(E_ASSERT, "Should reject multiple title args");
    except (E_INVARG)
      "Expected error";
    endtry
    "Test invalid HTML element";
    try
      $text_html:mk_element(123, {}, "content");
      raise(E_ASSERT, "Should reject non-string tag names");
    except (E_TYPE)
      "Expected error";
    endtry
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
endobject
