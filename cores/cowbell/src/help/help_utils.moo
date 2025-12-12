object HELP_UTILS
  name: "Help Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Help utilities for documentation extraction and lookup. Provides verbs for extracting verb docstrings, object documentation, and parsing help references.";
  override import_export_hierarchy = {"help"};
  override import_export_id = "help_utils";

  verb extract_verb_documentation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract documentation from a verb's code. Returns list of all comment lines (string literals ending with ;) from the start of the verb until the first non-comment line.";
    "Args: {verb_location, verb_name}";
    "Returns: documentation list (empty list if no comments found)";
    set_task_perms(caller_perms());
    {verb_location, verb_name} = args;
    "Get the verb code with line numbers";
    code_lines = `verb_code(verb_location, verb_name, false, true) ! ANY => {}';
    if (typeof(code_lines) != LIST || length(code_lines) == 0)
      return {};
    endif
    "Collect comment lines from the start of the verb";
    doc_lines = {};
    for line in (code_lines)
      "A comment line is a string literal: starts with \" and ends with \"; (or just ;)";
      line_trimmed = line:trim();
      if (line_trimmed && line_trimmed[1] == "\"" && (line_trimmed[length(line_trimmed)] == ";" || line_trimmed[length(line_trimmed)-1..length(line_trimmed)] == "\";"))
        "This is a comment line, add it";
        "Remove the quotes and semicolon";
        doc_line = line_trimmed[2..length(line_trimmed)-2];
        doc_lines = {@doc_lines, doc_line};
      else
        "Hit a non-comment line, stop collecting";
        break;
      endif
    endfor
    return doc_lines;
  endverb

  verb get_object_documentation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get documentation for an object. Returns the object_documentation property if it exists and is not 0, otherwise empty string.";
    "Args: {object}";
    "Returns: documentation content (string or list)";
    set_task_perms(caller_perms());
    {target} = args;
    if (!valid(target))
      return "";
    endif
    doc = `target.object_documentation ! E_PROPNF => 0';
    if (!doc || doc == 0)
      return "";
    endif
    return doc;
  endverb

  verb property_documentation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get documentation for a property. Looks for {prop_name}_prop_doc property on the object.";
    "Args: {object, property_name}";
    "Returns: documentation list (empty list if not found)";
    set_task_perms(caller_perms());
    {target, prop_name} = args;
    if (!valid(target))
      return {};
    endif
    doc_prop_name = prop_name + "_prop_doc";
    props = properties(target);
    if (!(doc_prop_name in props))
      return {};
    endif
    doc = `target.(doc_prop_name) ! E_PROPNF => 0';
    if (!doc || doc == 0)
      return {};
    endif
    "If doc is already a list, return it; if it's a string, wrap it";
    if (typeof(doc) == LIST)
      return doc;
    else
      return {doc};
    endif
  endverb

  verb format_documentation_display (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format documentation for display as a block. Takes title string and documentation, returns $format.block.";
    "Args: {title_string, documentation_text}";
    "Returns: formatted block flyweight";
    set_task_perms(caller_perms());
    {title, doc_text} = args;
    typeof(title) == STR || raise(E_TYPE("Documentation title must be a string, got " + toliteral(title)));
    if (!doc_text || doc_text == "" || (typeof(doc_text) == LIST && length(doc_text) == 0))
      return $format.block:mk(title, "(No documentation available)");
    endif
    "If doc_text is a list, join with newlines; otherwise use as-is";
    if (typeof(doc_text) == LIST)
      doc_text = doc_text:join("\n");
    endif
    return $format.block:mk(title, doc_text);
  endverb

  verb display_location_context (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display location, area, inventory, and nearby objects. Returns $format flyweight.";
    "Args: {player}";
    "Returns: $format.block with location context as formatted content";
    set_task_perms(caller_perms());
    {player_obj} = args;
    content = {};
    location = player_obj.location;
    area = location.location;
    location_name = `location:display_name() ! ANY => "somewhere"';
    location_desc = "You are in " + location_name;
    if (valid(area))
      area_name = `area:display_name() ! ANY => "somewhere"';
      location_desc = location_desc + " in " + area_name;
    endif
    content = {@content, location_desc};
    "Inventory";
    inventory = player_obj:contents();
    if (inventory && length(inventory) > 0)
      inv_names = {};
      for item in (inventory)
        inv_names = {@inv_names, `item:display_name() ! ANY => "something"'};
      endfor
      inv_str = inv_names:english_list();
      content = {@content, "You are carrying " + inv_str + "."};
    endif
    "Ways to go (exits)";
    if (valid(area) && respond_to(area, 'passages_from))
      passages = `area:passages_from(location) ! ANY => {}';
      if (passages && length(passages) > 0)
        exit_labels = {};
        for passage in (passages)
          is_open = `passage.is_open ! ANY => false';
          if (!is_open)
            continue;
          endif
          info = `passage:side_info_for(location) ! ANY => {}';
          if (length(info) == 0)
            continue;
          endif
          {label, description, ambient} = info;
          if (label)
            exit_labels = {@exit_labels, label};
          endif
        endfor
        if (exit_labels && length(exit_labels) > 0)
          ways_str = exit_labels:english_list();
          content = {@content, "You can go " + ways_str + "."};
        endif
      endif
    endif
    "Nearby objects (excluding location itself)";
    nearby = location:contents();
    nearby_items = {};
    for nearby_obj in (nearby)
      if (nearby_obj != player_obj && nearby_obj != location)
        nearby_items = {@nearby_items, nearby_obj};
      endif
    endfor
    if (nearby_items && length(nearby_items) > 0)
      nearby_names = {};
      for item in (nearby_items)
        nearby_names = {@nearby_names, `item:display_name() ! ANY => "something"'};
      endfor
      nearby_str = nearby_names:english_list();
      content = {@content, "Around you there is " + nearby_str + "."};
    endif
    return $format.block:mk(@content);
  endverb

  verb verb_help_from_hint (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Extract help topic from a verb's HINT tag.";
    "Args: (definer, verb_name, ?category) -> $help flyweight or 0";
    {definer, verb_name, ?category = 'command} = args;
    code = `verb_code(definer, verb_name) ! ANY => {}';
    if (!code || length(code) == 0)
      return 0;
    endif
    first_line = code[1]:trim();
    "Check if it's a string literal starting with HINT:";
    if (!first_line:starts_with("\"HINT:"))
      return 0;
    endif
    "Extract content between quotes";
    end_quote = rindex(first_line, "\"");
    if (end_quote <= 6)
      return 0;
    endif
    hint_content = first_line[7..end_quote - 1]:trim();
    "Parse hint: '<usage> -- <description>' or just '<description>'";
    dash_pos = index(hint_content, " -- ");
    if (dash_pos > 0)
      usage = hint_content[1..dash_pos - 1]:trim();
      description = hint_content[dash_pos + 4..$]:trim();
      content = "Usage: `" + verb_name + " " + usage + "`";
    else
      description = hint_content;
      content = "";
    endif
    return $help:mk(verb_name, description, content, {}, category, {});
  endverb

endobject
