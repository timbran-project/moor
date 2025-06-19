object TEXT_PLAIN
  name: "Text Plain Content Flyweight Delegate"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for plain text content. Stores text elements as a list and provides methods for combining and rendering them.";

  verb mk (this none this) owner: HACKER flags: "rxd"
    return <this, [is_block -> false], {@args}>;
  endverb

  verb mk_block (this none this) owner: HACKER flags: "rxd"
    "Create plain text content with block-level formatting (separate elements)";
    return <this, [is_block -> true], {@args}>;
  endverb

  verb append_to_content (this none this) owner: HACKER flags: "rxd"
    "Append this plain text content to another flyweight while preserving block structure if needed";
    {target_flyweight} = args;
    if (this.is_block)
      "Block content forces target to become block to preserve structure";
      if (!target_flyweight.is_block)
        "Convert inline target to block by extracting its elements";
        target_elements = {};
        for existing_element in (target_flyweight)
          target_elements = {@target_elements, existing_element};
        endfor
        target_flyweight = $text_plain:mk_block(@target_elements);
      endif
      "Now append each element separately to preserve structure";
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
    return <$text_plain, [is_block -> this.is_block], {@current_contents, element}>;
  endverb

  verb append_elements (this none this) owner: HACKER flags: "rxd"
    {elements} = args;
    typeof(elements) != LIST && raise(E_TYPE, "Elements must be a list");
    return <this, [is_block -> this.is_block], {@this, @elements}>;
  endverb

  verb render (this none this) owner: HACKER flags: "rxd"
    "Convert to final text format - for text_plain, return elements as separate strings";
    result = {};
    if (this.is_block)
      "For block content, keep elements separate";
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
    else
      "For inline content, join elements into single string";
      text_parts = {};
      for element in (this)
        if (typeof(element) == STR)
          text_parts = {@text_parts, element};
        elseif (typeof(element) == FLYWEIGHT)
          rendered = element:render();
          if (typeof(rendered) == LIST)
            for item in (rendered)
              text_parts = {@text_parts, tostr(item)};
            endfor
          else
            text_parts = {@text_parts, tostr(rendered)};
          endif
        else
          text_parts = {@text_parts, tostr(element)};
        endif
      endfor
      result = {text_parts:join("")};
    endif
    return result;
  endverb

  verb test_text_content (this none this) owner: HACKER flags: "rxd"
    content = this:mk("Root Prototype", " slams ", "Generic Room", " in ", "The First Room");
    typeof(content) != FLYWEIGHT && raise(E_ASSERT, "mk should return flyweight");
    rendered = content:render();
    typeof(rendered) != LIST && raise(E_ASSERT, "Rendered should be list");
    length(rendered) != 1 && raise(E_ASSERT, "Regular content should join into a single element");
    rendered[1] != "Root Prototype slams Generic Room in The First Room" && raise(E_ASSERT, "Content should be joined properly");
    "Test block content";
    block_content = this:mk_block("Block 1", "Block 2");
    typeof(block_content) != FLYWEIGHT && raise(E_ASSERT, "mk_block should return flyweight");
    block_content.is_block || raise(E_ASSERT, "mk_block should set is_block to true");
    block_rendered = block_content:render();
    typeof(block_rendered) != LIST && raise(E_ASSERT, "Block rendered should be list");
    length(block_rendered) != 2 && raise(E_ASSERT, "Block content should have separate elements");
    block_rendered[1] != "Block 1" && raise(E_ASSERT, "First block element should be 'Block 1'");
    block_rendered[2] != "Block 2" && raise(E_ASSERT, "Second block element should be 'Block 2'");
  endverb
endobject
