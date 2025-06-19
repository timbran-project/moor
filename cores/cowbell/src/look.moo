object LOOK
  name: "Object 'look' Flyweight Delegate"
  parent: ROOT
  owner: HACKER

  override description = "The $look flyweight delegate holds the attributes involved in looking at an object, and can be transformed into output events. It always has mandatory 'title and 'description slots, and then optional contents which are a series of integration descriptions.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    {what, @contents} = args;
    return <this, [what -> what, title -> what:name(), description -> what:description()], {@contents}>;
  endverb

  verb into_event (this none this) owner: HACKER flags: "rxd"
    "Three lines -- title, description, contents.";
    "Description is the item description but is also appended to with integrations. Objects with an :integrate_description verb are put there.";
    "The remainder go into the contents block.";
    "Title is the direct-object-capitalized";
    title = $title:mk($sub:dc());
    integrated_contents = {};
    contents = {};
    for o in (this)
      if (o == player)
        continue;
      endif
      integrated_description = `o:integrate_description() ! E_VERBNF => false';
      if (integrated_description)
        integrated_contents = {@integrated_contents, integrated_description};
      else
        contents = {@contents, `o:name() ! E_VERBNF => o.name'};
      endif
    endfor
    description = this.description;
    if (length(integrated_contents))
      description = description + " " + { ic + "." for ic in (integrated_contents) }:to_list();
    endif
    block_elements = {title, description};
    if (length(contents))
      block_elements = {@block_elements, "You see " + contents:english_list() + " here."};
    endif
    b = $block:mk(@block_elements);
    return $event:mk_look(player, b):with_dobj(this.what);
  endverb

  verb validate (this none this) owner: HACKER flags: "rxd"
    if (typeof(this) != FLYWEIGHT)
      return false;
    endif
    try
      this.what && this.title && this.description && return true;
    except (E_PROPNF)
      return false;
    endtry
    return true;
  endverb

  verb test_into_event (this none this) owner: HACKER flags: "rxd"
    look = this:mk($first_room, $thing);
    !look:validate() && raise(E_ASSERT, "Invalid $look: " + toliteral(look));
    event = look:into_event();
    event:validate() || raise(E_ASSERT, "Invalid event:" + toliteral(event));
    !(typeof(event) == FLYWEIGHT) && raise(E_ASSERT, "look event should be a flyweight");
    event.dobj != $first_room && raise(E_ASSERT, "look event dobj is wrong");
    content = event:transform_for(player, 'text_markdown);
    typeof(content) != LIST && raise(E_ASSERT, "Produced content is invalid: " + toliteral(content));
    length(content) != 3 && raise(E_ASSERT, "Produced content is wrong length: " + toliteral(content) + " from " + toliteral(event));
  endverb

  verb test_html_rendering (this none this) owner: HACKER flags: "rxd"
    "Test that look events render properly as HTML with <p> tags";
    look = this:mk($first_room, $thing);
    !look:validate() && raise(E_ASSERT, "Invalid $look: " + toliteral(look));
    event = look:into_event();
    !event:validate() && raise(E_ASSERT, "Invalid event");
    "Test HTML rendering";
    html_content = event:transform_for(player, 'text_html);
    typeof(html_content) != LIST && raise(E_ASSERT, "HTML content should be a list: " + toliteral(html_content));
    "Check that we have a single HTML string (block format)";
    length(html_content) != 1 && raise(E_ASSERT, "HTML content should be single string: " + toliteral(html_content));
    "Get the combined HTML string";
    html_string = html_content[1];
    typeof(html_string) != STR && raise(E_ASSERT, "HTML content should be string: " + toliteral(html_string));
    "Parse the HTML using xml_parse() and verify structure";
    try
      parsed = xml_parse(html_string);
      typeof(parsed) != LIST && raise(E_ASSERT, "Parsed HTML should be a list: " + toliteral(parsed));
      length(parsed) < 3 && raise(E_ASSERT, "Should have at least 3 <p> elements: " + toliteral(parsed));
      "Verify first element is <p> with <em> title";
      title_p = parsed[1];
      typeof(title_p) != LIST && raise(E_ASSERT, "Title element should be a list: " + toliteral(title_p));
      title_p[1] != "p" && raise(E_ASSERT, "First element should be <p>: " + toliteral(title_p));
      length(title_p) < 2 && raise(E_ASSERT, "Title <p> should have content: " + toliteral(title_p));
      title_em = title_p[2];
      typeof(title_em) != LIST && raise(E_ASSERT, "Title content should be <em>: " + toliteral(title_em));
      title_em[1] != "em" && raise(E_ASSERT, "Title should contain <em>: " + toliteral(title_em));
      "Verify second element is <p> with description";
      desc_p = parsed[2];
      typeof(desc_p) != LIST && raise(E_ASSERT, "Description element should be a list: " + toliteral(desc_p));
      desc_p[1] != "p" && raise(E_ASSERT, "Second element should be <p>: " + toliteral(desc_p));
      length(desc_p) < 2 && raise(E_ASSERT, "Description <p> should have content: " + toliteral(desc_p));
      "Verify third element is <p> with contents";
      contents_p = parsed[3];
      typeof(contents_p) != LIST && raise(E_ASSERT, "Contents element should be a list: " + toliteral(contents_p));
      contents_p[1] != "p" && raise(E_ASSERT, "Third element should be <p>: " + toliteral(contents_p));
      length(contents_p) < 2 && raise(E_ASSERT, "Contents <p> should have content: " + toliteral(contents_p));
    except (ANY)
      raise(E_ASSERT, "Failed to parse HTML result: " + toliteral(html_string));
    endtry
  endverb
endobject
