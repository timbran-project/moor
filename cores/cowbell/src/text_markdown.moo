object TEXT_MARKDOWN
  name: "Text Markdown Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for markdown content. Stores markdown elements and provides methods for combining and rendering.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, [is_block -> false], {@args}>;
  endverb

  verb mk_block (this none this) owner: HACKER flags: "rxd"
    "Create markdown content with block-level formatting (paragraph breaks between elements)";
    return <this, [is_block -> true], {@args}>;
  endverb

  verb append_to_content (this none this) owner: HACKER flags: "rxd"
    "Append this markdown content to another flyweight while preserving block structure if needed";
    {target_flyweight} = args;
    if (this.is_block)
      "For block-level content, append each element separately to preserve structure";
      for item in (this)
        if (typeof(item) == FLYWEIGHT && respond_to(item, "append_to_content"))
          target_flyweight = item:append_to_content(target_flyweight);
        else
          target_flyweight = target_flyweight:append_element(item);
        endif
      endfor
    else
      "For inline content, append all elements as a single unit";
      target_flyweight = target_flyweight:append_element(this);
    endif
    return target_flyweight;
  endverb

  verb append_element (this none this) owner: HACKER flags: "rxd"
    {element} = args;
    current_contents = {};
    for item in (this)
      current_contents = {@current_contents, item};
    endfor
    return <$text_markdown, [is_block -> this.is_block], {@current_contents, element}>;
  endverb

  verb append_elements (this none this) owner: HACKER flags: "rxd"
    {elements} = args;
    typeof(elements) != LIST && raise(E_TYPE, "Elements must be a list");
    return <this, [is_block -> this.is_block], {@this, @elements}>;
  endverb

  verb render (this none this) owner: HACKER flags: "rxd"
    "Convert to final markdown format";
    result = {};
    "First check if this content came from a block - if we have multiple top-level elements
     from different sources (like title + description), keep them separate";
    block_content = this.is_block;
    element_index = 1;
    while (element_index <= length(this))
      element = this[element_index];
      if (typeof(element) == STR)
        if (block_content && element_index > 1)
          "Keep block elements separate";
          result = {@result, element};
        else
          "Normal mode, append to paragraph";
          result = element:append_to_paragraph(@result);
        endif
      elseif (typeof(element) == FLYWEIGHT)
        rendered = element:render();
        if (typeof(rendered) == LIST)
          for item in (rendered)
            if (typeof(item) == STR)
              if (block_content && element_index > 1 && length(result) > 0)
                "Keep block elements separate";
                result = {@result, item};
              else
                "Normal mode, append to paragraph";
                result = item:append_to_paragraph(@result);
              endif
            else
              if (block_content && element_index > 1 && length(result) > 0)
                result = {@result, tostr(item)};
              else
                result = tostr(item):append_to_paragraph(@result);
              endif
            endif
          endfor
        else
          if (typeof(rendered) == STR)
            if (block_content && element_index > 1 && length(result) > 0)
              result = {@result, rendered};
            else
              result = rendered:append_to_paragraph(@result);
            endif
          else
            if (block_content && element_index > 1 && length(result) > 0)
              result = {@result, tostr(rendered)};
            else
              result = tostr(rendered):append_to_paragraph(@result);
            endif
          endif
        endif
      else
        if (block_content && element_index > 1 && length(result) > 0)
          result = {@result, tostr(element)};
        else
          result = tostr(element):append_to_paragraph(@result);
        endif
      endif
      element_index = element_index + 1;
    endwhile
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
