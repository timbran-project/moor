object PROG_FEATURES
  name: "Programmer Features"
  parent: BUILDER_FEATURES
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Provides programming verbs (@edit, @list, @verb, etc.) for programmers. Inherits from and extends builder features.";
  override import_export_hierarchy = {"features"};
  override import_export_id = "prog_features";

  verb eval (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <expression> -- Evaluate a MOO expression.";
    this:_challenge_command_perms();
    set_task_perms(player);
    try
      answer = eval("return " + argstr + ";", ['me -> player, 'here -> player.location], 1, 2);
      if (answer[1])
        result = answer[2];
        "Format the result";
        {result_type, result_content} = this:_format_eval_result(result);
        if (result_type == 'deflist)
          "Object result - show as definition list";
          result_event = $event:mk_eval_result(player, result_content):with_presentation_hint('inset):with_group('eval);
        else
          "Simple result - show in code block with =>";
          code = $format.code:mk("=> " + result_content, 'moo);
          result_event = $event:mk_eval_result(player, code):with_group('eval);
        endif
      else
        error_content = answer[2];
        error_text = error_content:join("\n");
        result_event = $event:mk_eval_error(player, $format.code:mk(error_text)):with_group('eval);
      endif
    except id (ANY)
      traceback = {"Eval failed: " + toliteral(id[2]) + ":"};
      for tb in (id[4])
        traceback = {@traceback, tostr("... called from ", tb[4], ":", tb[2], tb[4] != tb[1] ? tostr(" (this == ", tb[1], ")") | "", ", line ", tb[6])};
      endfor
      traceback = {@traceback, "(End of traceback)"};
      result_event = $event:mk_eval_exception(player, $format.code:mk(traceback)):with_group('eval);
    endtry
    player:inform_current(result_event);
  endverb

  verb _do_check_verb_exists (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to check verb exists with elevated permissions";
    caller == this || raise(E_PERM);
    {verb_location, verb_name} = args;
    "This will raise E_VERBNF if verb doesn't exist";
    $prog_utils:get_verb_metadata(verb_location, verb_name);
    return true;
  endverb

  verb "@edit" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> or <object>.<property> -- Edit a verb or property.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@edit OBJECT:VERB\n@edit OBJECT.PROPERTY")));
      return;
    endif
    target_string = argstr:trim();
    "Determine if this is a verb or property reference";
    if (":" in target_string)
      "Verb reference";
      parsed = target_string:parse_verbref();
      if (!parsed)
        player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb'"));
        return;
      endif
      {object_str, verb_name} = parsed;
      "Match the object";
      try
        target_obj = $match:match_object(object_str, player);
      except e (E_INVARG)
        player:tell($event:mk_error(player, "I don't see '" + object_str + "' here."));
        return;
      except e (ANY)
        player:tell($event:mk_error(player, "Error matching object: " + e[2]));
        return;
      endtry
      "Find and retrieve the verb code";
      try
        "Find where the verb is actually defined";
        verb_location = target_obj:find_verb_definer(verb_name);
        if (verb_location == #-1)
          player:inform_current($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + " or its ancestors."));
          return;
        endif
        "Check verb exists with elevated permissions";
        this:_do_check_verb_exists(verb_location, verb_name);
        "Open the editor";
        this:present_verb_editor(verb_location, verb_name);
        player:inform_current($event:mk_info(player, "Opened verb editor for " + tostr(target_obj) + ":" + tostr(verb_name)));
      except (E_VERBNF)
        player:inform_current($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + "."));
        return;
      endtry
    elseif ("." in target_string)
      "Property reference";
      parts = target_string:split(".");
      if (length(parts) != 2)
        player:inform_current($event:mk_error(player, "Invalid property reference format. Use 'object.property'"));
        return;
      endif
      {object_str, prop_name} = parts;
      "Match the object";
      try
        target_obj = $match:match_object(object_str, player);
      except e (E_INVARG)
        player:tell($event:mk_error(player, "I don't see '" + object_str + "' here."));
        return;
      except e (ANY)
        player:tell($event:mk_error(player, "Error matching object: " + e[2]));
        return;
      endtry
      "Check property exists and open editor";
      if (!target_obj:check_property_exists(prop_name))
        player:inform_current($event:mk_error(player, "Property '" + prop_name + "' not found on " + target_obj.name + "."));
        return;
      endif
      "Open the property editor";
      this:present_property_editor(target_obj, prop_name);
      player:inform_current($event:mk_info(player, "Opened property editor for " + tostr(target_obj) + "." + prop_name));
    else
      player:inform_current($event:mk_error(player, "Invalid reference. Use 'object:verb' or 'object.property'"));
    endif
  endverb

  verb "@browse" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Browse an object in the object browser.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@browse OBJECT")));
      return;
    endif
    target_string = argstr:trim();
    "Match the object";
    try
      target_obj = $match:match_object(target_string, player);
    except e (E_INVARG)
      player:tell($event:mk_error(player, "I don't see '" + target_string + "' here."));
      return;
    except e (ANY)
      player:tell($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Open the browser";
    this:present_object_browser(target_obj);
    player:inform_current($event:mk_info(player, "Opened object browser for " + tostr(target_obj)));
  endverb

  verb present_verb_editor (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    {verb_location, verb_name} = args;
    editor_id = "edit-" + tostr(verb_location) + "-" + verb_name;
    editor_title = "Edit " + verb_name + " on " + tostr(verb_location);
    object_curie = $url_utils:to_curie_str(verb_location);
    present(player, editor_id, "text/plain", "verb-editor", "", {{"object", object_curie}, {"verb", verb_name}, {"title", editor_title}});
  endverb

  verb present_object_browser (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    {target_obj} = args;
    browser_id = "browse-" + tostr(target_obj);
    browser_title = "Browse " + tostr(target_obj);
    object_curie = $url_utils:to_curie_str(target_obj);
    present(player, browser_id, "text/plain", "object-browser", "", {{"object", object_curie}, {"title", browser_title}});
  endverb

  verb present_text_editor (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Present the text editor for editing freeform content.";
    "Args: {target_obj, verb_name, ?curried_args, ?initial_content, ?opts}";
    "opts is a map with optional keys: content_type, title, description, text_mode";
    "  content_type: 'text_plain (default) or 'text_djot";
    "  title: editor window title";
    "  description: explanatory blurb shown to user";
    "  text_mode: 'list (default) sends {line1, line2, ...}, 'string sends single string";
    "On save, the verb is called as: target_obj:verb_name(...curried_args, content)";
    "  where content is either a list of strings or a single string based on text_mode";
    caller == this || raise(E_PERM);
    {target_obj, verb_name, ?curried_args = {}, ?initial_content = {}, ?opts = []} = args;
    "Extract options with defaults";
    content_type = opts['content_type] || 'text_plain;
    title = opts['title] || "";
    description = opts['description] || "";
    text_mode = opts['text_mode] || 'list;
    object_curie = $url_utils:to_curie_str(target_obj);
    editor_id = "text-edit-" + tostr(target_obj) + "-" + verb_name;
    editor_title = title || "Edit text for " + tostr(target_obj);
    "Convert content to string for presentation";
    if (typeof(initial_content) == LIST)
      content_str = initial_content:join("\n");
    else
      content_str = tostr(initial_content);
    endif
    "Convert curried args to JSON for attribute";
    args_json = toliteral(curried_args);
    "Convert content type and text mode symbols to strings";
    ct_str = content_type == 'text_djot ? "text/djot" | "text/plain";
    mode_str = text_mode == 'string ? "string" | "list";
    attrs = {{"object", object_curie}, {"verb", verb_name}, {"args", args_json}, {"content_type", ct_str}, {"title", editor_title}, {"text_mode", mode_str}};
    if (description)
      attrs = {@attrs, {"description", description}};
    endif
    present(player, editor_id, ct_str, "text-editor", content_str, attrs);
  endverb

  verb _do_get_verb_listing (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get verb listing with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {verb_location, verb_name, show_all_parens} = args;
    metadata = $prog_utils:get_verb_metadata(verb_location, verb_name);
    code_lines = verb_code(verb_location, verb_name, show_all_parens, true);
    return {metadata:verb_owner(), metadata:flags(), metadata:dobj(), metadata:prep(), metadata:iobj(), code_lines};
  endverb

  verb "@list" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> -- List verb code.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT:VERB [with parentheses] [without numbers]")));
      return;
    endif
    "Parse options from argstr";
    args_lower = argstr:lowercase();
    show_all_parens = index(args_lower, "with parentheses");
    hide_numbers = index(args_lower, "without numbers");
    "Extract verbref by removing option keywords";
    verbref_string = argstr;
    verbref_string = verbref_string:replace_all(" with parentheses", "");
    verbref_string = verbref_string:replace_all(" without numbers", "");
    verbref_string = verbref_string:trim();
    "Parse the verb reference";
    parsed = verbref_string:parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb'"));
      return;
    endif
    {object_str, verb_name} = parsed;
    "Match the object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Find and retrieve the verb code";
    try
      verb_location = target_obj:find_verb_definer(verb_name);
      if (verb_location == #-1)
        player:inform_current($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + " or its ancestors."));
        return;
      endif
      "Get verb metadata and code via helper with elevated permissions";
      listing_data = this:_do_get_verb_listing(verb_location, verb_name, show_all_parens);
      {verb_owner, verb_flags, dobj, prep, iobj, code_lines} = listing_data;
      "Build metadata table";
      verb_signature = tostr(verb_location) + ":" + tostr(verb_name);
      args_spec = dobj + " " + prep + " " + iobj;
      headers = {"Verb", "Args", "Owner", "Flags"};
      row = {verb_signature, args_spec, tostr(verb_owner), verb_flags};
      metadata_table = $format.table:mk(headers, {row});
      "Add line numbers if requested";
      if (!hide_numbers)
        code_lines = $prog_utils:format_line_numbers(code_lines);
      endif
      "Format as code block";
      formatted_code = $format.code:mk(code_lines, 'moo);
      "Combine table and code";
      content = $format.block:mk(metadata_table, formatted_code);
      "Create and send listing event";
      listing_event = $event:mk_program_listing(player, "", content);
      player:inform_current(listing_event);
    except (E_VERBNF)
      player:inform_current($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + "."));
    endtry
  endverb

  verb _do_add_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to add verb with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_info, verb_args} = args;
    add_verb(target_obj, verb_info, verb_args);
  endverb

  verb "@verb" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb-names> -- Add a new verb to an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT:VERB-NAME(S) [DOBJ [PREP [IOBJ [PERMISSIONS [OWNER]]]]]")));
      return;
    endif
    "Parse the arguments";
    words = argstr:words();
    if (length(words) < 1)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT:VERB-NAME(S) [DOBJ [PREP [IOBJ [PERMISSIONS [OWNER]]]]]")));
      return;
    endif
    "Parse object:verb-name(s)";
    parsed = words[1]:parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name(s)'"));
      return;
    endif
    {object_str, verb_names} = parsed;
    "Match the object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Parse optional arguments with defaults";
    dobj = length(words) >= 2 ? words[2] | "none";
    prep = length(words) >= 3 ? words[3] | "none";
    iobj = length(words) >= 4 ? words[4] | "none";
    permissions = length(words) >= 5 ? words[5] | "rxd";
    verb_owner = length(words) >= 6 ? $match:match_object(words[6], player) | player;
    "Validate dobj and iobj";
    if (!(dobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Direct object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!(iobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Indirect object must be 'none', 'this', or 'any'"));
      return;
    endif
    "Validate preposition";
    if (!$prog_utils:is_valid_prep(prep))
      player:inform_current($event:mk_error(player, "Invalid preposition: '" + prep + "'. Use 'none', 'any', or a valid preposition."));
      return;
    endif
    "Validate permissions if provided";
    if (length(words) >= 5)
      for i in [1..length(permissions)]
        char = permissions[i];
        if (!(char in {"r", "w", "x", "d"}))
          player:inform_current($event:mk_error(player, "Permissions must be subset of 'rwxd'"));
          return;
        endif
      endfor
    endif
    "Check owner permission";
    if (verb_owner != player && !player.wizard)
      player:inform_current($event:mk_error(player, "Only wizards can create verbs with other owners"));
      return;
    endif
    "Add the verb via helper with elevated permissions";
    this:_do_add_verb(target_obj, {verb_owner, permissions, verb_names}, {dobj, prep, iobj});
    player:inform_current($event:mk_info(player, "Verb " + tostr(target_obj) + ":" + verb_names + " added."));
  endverb

  verb _do_delete_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to delete verb with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_name} = args;
    delete_verb(target_obj, verb_name);
  endverb

  verb "@rmverb" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> -- Remove a verb from an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name"));
      return;
    endif
    "Parse the verb reference";
    parsed = argstr:trim():parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name'"));
      return;
    endif
    {object_str, verb_name} = parsed;
    "Match the object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Delete the verb via helper with elevated permissions";
    this:_do_delete_verb(target_obj, verb_name);
    player:inform_current($event:mk_info(player, "Verb " + tostr(target_obj) + ":" + verb_name + " removed."));
  endverb

  verb _do_set_verb_args (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set verb args with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_name, new_args} = args;
    set_verb_args(target_obj, verb_name, new_args);
  endverb

  verb _do_get_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get verb list with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj} = args;
    return verbs(target_obj);
  endverb

  verb "@verbs" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- List all verbs on an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT")));
      return;
    endif
    "Match the object";
    try
      target_obj = $match:match_object(argstr:trim(), player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + argstr + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Get verbs list with elevated permissions";
    verb_list = this:_do_get_verbs(target_obj);
    "Format as MOO literal";
    code_text = ";verbs(" + tostr(target_obj) + ") => " + toliteral(verb_list);
    formatted_code = $format.code:mk(code_text, 'moo);
    listing_event = $event:mk_eval_result(player, "", formatted_code);
    player:inform_current(listing_event);
  endverb

  verb _do_get_properties (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get properties list with elevated permissions";
    set_task_perms(caller_perms());
    {target_obj} = args;
    return properties(target_obj);
  endverb

  verb "@properties @props" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- List all properties on an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT")));
      return;
    endif
    "Match the object";
    try
      target_obj = $match:match_object(argstr:trim(), player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + argstr + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Get properties list with elevated permissions";
    prop_list = this:_do_get_properties(target_obj);
    "Format as MOO literal";
    code_text = ";properties(" + tostr(target_obj) + ") => " + toliteral(prop_list);
    formatted_code = $format.code:mk(code_text, 'moo);
    listing_event = $event:mk_eval_result(player, "", formatted_code);
    player:inform_current(listing_event);
  endverb

  verb "@prop*erty" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<property> -- Add a property to an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@property OBJECT.PROP-NAME [VALUE [PERMS [OWNER]]]")));
      return;
    endif
    target_spec = args[1];
    "Parse property reference";
    parsed = $prog_utils:parse_target_spec(target_spec);
    "Check for valid property reference";
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Usage: @property <object>.<prop-name> [<initial-value> [<perms> [<owner>]]]"));
      return;
    endif
    selector = parsed['selectors][1];
    if (selector['kind] != 'property || !selector['item_name])
      player:inform_current($event:mk_error(player, "Usage: @property <object>.<prop-name> [<initial-value> [<perms> [<owner>]]]"));
      return;
    endif
    object_str = parsed['object_str];
    prop_name = selector['item_name];
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    "Get initial value and remaining args";
    value = 0;
    perms = "rw";
    owner = player;
    if (length(args) > 1)
      "Get remainder after target spec";
      offset = index(argstr, target_spec) + length(target_spec);
      remainder = argstr[offset..length(argstr)]:trim();
      if (remainder)
        "Try to evaluate a literal from the start of remainder";
        eval_result = $prog_utils:eval_literal(remainder);
        if (eval_result[1])
          value = eval_result[2];
          remainder = eval_result[3]:trim();
        endif
        "If there's still something left, try to parse perms and owner";
        if (remainder)
          remaining_words = remainder:words();
          if (length(remaining_words) > 0)
            "Check if first word looks like perms (short string of r, w, c)";
            maybe_perms = remaining_words[1];
            if (length(maybe_perms) <= 3 && match(maybe_perms, "^[rwc]+$"))
              perms = maybe_perms;
              if (length(remaining_words) > 1)
                "Try to match owner";
                try
                  owner = $match:match_object(remaining_words[2], player);
                  if (!valid(owner) || typeof(owner) != OBJ)
                    player:inform_current($event:mk_error(player, "Invalid owner object"));
                    return;
                  endif
                except e (ANY)
                  player:inform_current($event:mk_error(player, "Could not match owner: " + tostr(e[2])));
                  return;
                endtry
              endif
            else
              "First remaining word doesn't look like valid perms";
              player:inform_current($event:mk_error(player, "Invalid permissions string: " + maybe_perms + ". Must be combination of r, w, c."));
              return;
            endif
          endif
        endif
      endif
    endif
    "Try to add the property";
    try
      add_property(target_obj, prop_name, value, {owner, perms});
      player:inform_current($event:mk_info(player, "Property " + tostr(target_obj) + "." + prop_name + " added with initial value " + toliteral(value) + " and permissions " + perms + "."));
    except e (E_INVARG)
      if (index(tostr(e[2]), "already exists"))
        player:inform_current($event:mk_error(player, "Property " + prop_name + " already exists on " + tostr(target_obj) + "."));
      else
        player:inform_current($event:mk_error(player, "Error adding property: " + tostr(e[2])));
      endif
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error adding property: " + tostr(e[2])));
    endtry
  endverb

  verb "@rmprop*erty" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<property> -- Remove a property from an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@rmproperty OBJECT.PROP-NAME")));
      return;
    endif
    target_spec = argstr:trim();
    "Parse property reference";
    parsed = $prog_utils:parse_target_spec(target_spec);
    "Check for valid property reference";
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Usage: @rmproperty <object>.<prop-name>"));
      return;
    endif
    selector = parsed['selectors][1];
    if (selector['kind] != 'property || !selector['item_name])
      player:inform_current($event:mk_error(player, "Usage: @rmproperty <object>.<prop-name>"));
      return;
    endif
    object_str = parsed['object_str];
    prop_name = selector['item_name];
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    "Check property exists";
    if (!(prop_name in properties(target_obj)))
      player:inform_current($event:mk_error(player, "Property " + prop_name + " not found on " + tostr(target_obj) + "."));
      return;
    endif
    "Try to delete the property";
    try
      delete_property(target_obj, prop_name);
      player:inform_current($event:mk_info(player, "Property " + tostr(target_obj) + "." + prop_name + " deleted."));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error deleting property: " + tostr(e[2])));
    endtry
  endverb

  verb "@args" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> -- Show or change verb argument specifications.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT:VERB-NAME [DOBJ [PREP [IOBJ]]]")));
      return;
    endif
    "Parse the arguments";
    words = argstr:words();
    "Parse object:verb-name";
    parsed = words[1]:parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name'"));
      return;
    endif
    {object_str, verb_name} = parsed;
    "Match the object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
      return;
    endtry
    "Get current args from metadata";
    metadata = $prog_utils:get_verb_metadata(target_obj, verb_name);
    current_dobj = metadata:dobj();
    current_prep = metadata:prep();
    current_iobj = metadata:iobj();
    "If only object:verb given, show current args";
    if (length(words) == 1)
      obj_display = tostr(target_obj.name, " (", target_obj, ")");
      title = $format.title:mk(obj_display + ":" + verb_name);
      args_line = $format.code:mk(current_dobj + " " + current_prep + " " + current_iobj);
      content = $format.block:mk(title, args_line);
      player:inform_current($event:mk_info(player, content));
      return {current_dobj, current_prep, current_iobj};
    endif
    "Parse new args, using current values as defaults";
    new_dobj = length(words) >= 2 ? words[2] | current_dobj;
    new_prep = length(words) >= 3 ? words[3] | current_prep;
    new_iobj = length(words) >= 4 ? words[4] | current_iobj;
    "Validate dobj and iobj";
    if (!(new_dobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Direct object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!(new_iobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Indirect object must be 'none', 'this', or 'any'"));
      return;
    endif
    "Set the new args via helper with elevated permissions";
    this:_do_set_verb_args(target_obj, verb_name, {new_dobj, new_prep, new_iobj});
    player:inform_current($event:mk_info(player, "Verb args updated: " + tostr(target_obj) + ":" + verb_name + " " + new_dobj + " " + new_prep + " " + new_iobj));
  endverb

  verb _do_get_property_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get property metadata with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    return $prog_utils:get_property_metadata(target_obj, prop_name);
  endverb

  verb _do_get_property_value (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get property value with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    return target_obj.(prop_name);
  endverb

  verb "@sh*ow @d*isplay" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>[selectors] -- Display object information.";
    "Syntax:";
    "  @show obj         Summary with counts and hints";
    "  @show obj.        Local properties";
    "  @show obj..       All properties (including inherited)";
    "  @show obj.name    Specific property";
    "  @show obj:        Local verbs";
    "  @show obj::       All verbs (including inherited)";
    "  @show obj:name    Specific verb";
    "  @show obj.:       Local properties and verbs";
    "  @show obj..::     All properties and verbs";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      usage = {verb + " <object>[.<prop>|..|:<verb>|::]"};
      usage = {@usage, ""};
      usage = {@usage, "Examples:"};
      usage = {@usage, "  " + verb + " #1       Show summary with counts"};
      usage = {@usage, "  " + verb + " #1.      Show local properties"};
      usage = {@usage, "  " + verb + " #1..     Show all properties (+ inherited)"};
      usage = {@usage, "  " + verb + " #1:      Show local verbs"};
      usage = {@usage, "  " + verb + " #1::     Show all verbs (+ inherited)"};
      usage = {@usage, "  " + verb + " #1.name  Show specific property"};
      usage = {@usage, "  " + verb + " #1:tell  Show specific verb"};
      usage = {@usage, "  " + verb + " #1.:     Show local props + local verbs"};
      usage = {@usage, "  " + verb + " #1..::   Show all props + all verbs"};
      player:inform_current($event:mk_error(player, $format.code:mk(usage:join("\n"))));
      return;
    endif
    spec = argstr:trim();
    parsed = $prog_utils:parse_target_spec(spec);
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid specification. Use @show for usage."));
      return;
    endif
    "Match the target object";
    object_str = parsed['object_str];
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + e[2]));
      return;
    endtry
    "Dispatch based on type";
    if (parsed['type] == 'object)
      "Plain object - show summary with counts and hints";
      this:_display_summary(target_obj);
      return;
    endif
    "Compound type - always show header first, then process selectors";
    this:_display_header(target_obj);
    selectors = parsed['selectors];
    for selector in (selectors)
      kind = selector['kind];
      inherited = selector['inherited];
      item_name = selector['item_name];
      if (kind == 'property)
        if (item_name)
          "Specific property";
          if (inherited)
            this:_display_inherited_property(target_obj, item_name);
          else
            this:_display_property(target_obj, item_name);
          endif
        else
          "All properties";
          this:_display_all_properties(target_obj, inherited);
        endif
      elseif (kind == 'verb)
        if (item_name)
          "Specific verb";
          if (inherited)
            this:_display_inherited_verb(target_obj, item_name);
          else
            this:_display_verb(target_obj, item_name);
          endif
        else
          "All verbs";
          this:_display_all_verbs(target_obj, inherited);
        endif
      endif
    endfor
  endverb

  verb _display_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    metadata = $prog_utils:get_property_metadata(target_obj, prop_name);
    prop_value = metadata:is_clear() ? "(clear)" | toliteral(this:_do_get_property_value(target_obj, prop_name));
    "Truncate long values";
    if (length(prop_value) > 50)
      prop_value = prop_value[1..47] + "...";
    endif
    "Format owner as Name (#num)";
    prop_owner = metadata:owner();
    owner_str = valid(prop_owner) ? `prop_owner.name ! ANY => "???"' + " (" + tostr(prop_owner) + ")" | tostr(prop_owner);
    headers = {"Property", "Owner", "Flags", "Value"};
    row = {"." + prop_name, owner_str, metadata:perms(), prop_value};
    table = $format.table:mk(headers, {row});
    player:inform_current($event:mk_info(player, table));
  endverb

  verb _display_inherited_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    "Find where property is defined";
    current = target_obj;
    definer = #-1;
    while (valid(current))
      if (prop_name in this:_do_get_properties(current))
        definer = current;
        break;
      endif
      current = `parent(current) ! ANY => #-1';
    endwhile
    if (definer == #-1)
      raise(E_PROPNF, "Property not found: " + prop_name);
    endif
    this:_display_property(definer, prop_name);
  endverb

  verb _display_all_properties (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, include_inherited} = args;
    rows = {};
    if (include_inherited)
      "Include Definer column for inherited properties";
      headers = {"Property", "Definer", "Owner", "Flags", "Value"};
      seen = {};
      current = target_obj;
      while (valid(current))
        props = this:_do_get_properties(current);
        for prop_name in (props)
          if (prop_name in seen)
            continue;
          endif
          seen = {@seen, prop_name};
          "Skip properties we can't access";
          metadata = `$prog_utils:get_property_metadata(current, prop_name) ! E_PERM => 0';
          if (typeof(metadata) != FLYWEIGHT)
            continue;
          endif
          prop_value = metadata:is_clear() ? "(clear)" | toliteral(`this:_do_get_property_value(current, prop_name) ! E_PERM => "(no access)"');
          if (length(prop_value) > 50)
            prop_value = prop_value[1..47] + "...";
          endif
          "Format definer as Name (#num)";
          definer_str = `current.name ! ANY => "???"' + " (" + tostr(current) + ")";
          "Format owner as Name (#num)";
          prop_owner = metadata:owner();
          owner_str = valid(prop_owner) ? `prop_owner.name ! ANY => "???"' + " (" + tostr(prop_owner) + ")" | tostr(prop_owner);
          rows = {@rows, {"." + prop_name, definer_str, owner_str, metadata:perms(), prop_value}};
        endfor
        current = `parent(current) ! ANY => #-1';
      endwhile
    else
      "No Definer column for local-only";
      headers = {"Property", "Owner", "Flags", "Value"};
      props = this:_do_get_properties(target_obj);
      for prop_name in (props)
        "Skip properties we can't access";
        metadata = `$prog_utils:get_property_metadata(target_obj, prop_name) ! E_PERM => 0';
        if (typeof(metadata) != FLYWEIGHT)
          continue;
        endif
        prop_value = metadata:is_clear() ? "(clear)" | toliteral(`this:_do_get_property_value(target_obj, prop_name) ! E_PERM => "(no access)"');
        if (length(prop_value) > 50)
          prop_value = prop_value[1..47] + "...";
        endif
        "Format owner as Name (#num)";
        prop_owner = metadata:owner();
        owner_str = valid(prop_owner) ? `prop_owner.name ! ANY => "???"' + " (" + tostr(prop_owner) + ")" | tostr(prop_owner);
        rows = {@rows, {"." + prop_name, owner_str, metadata:perms(), prop_value}};
      endfor
    endif
    if (!rows)
      player:inform_current($event:mk_info(player, "No properties found."));
      return;
    endif
    table = $format.table:mk(headers, rows);
    player:inform_current($event:mk_info(player, table));
  endverb

  verb _display_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_name} = args;
    verb_location = target_obj:find_verb_definer(verb_name);
    if (verb_location == #-1)
      raise(E_VERBNF, "Verb not found: " + verb_name);
    endif
    verb_info_data = this:_do_get_verb_listing(verb_location, verb_name, false);
    {verb_owner, verb_flags, dobj, prep, iobj, code_lines} = verb_info_data;
    "Format owner as Name (#num)";
    owner_str = valid(verb_owner) ? `verb_owner.name ! ANY => "???"' + " (" + tostr(verb_owner) + ")" | tostr(verb_owner);
    headers = {"Verb", "Owner", "Flags", "Args"};
    args_spec = dobj + " " + prep + " " + iobj;
    verb_spec = tostr(verb_location) + ":" + verb_name;
    row = {verb_spec, owner_str, verb_flags, args_spec};
    table = $format.table:mk(headers, {row});
    player:inform_current($event:mk_info(player, table));
  endverb

  verb _display_inherited_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_name} = args;
    verb_location = target_obj:find_verb_definer(verb_name);
    if (verb_location == #-1)
      raise(E_VERBNF, "Verb not found: " + verb_name);
    endif
    this:_display_verb(verb_location, verb_name);
  endverb

  verb _display_all_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, include_inherited} = args;
    rows = {};
    if (include_inherited)
      "Include Definer column for inherited verbs";
      headers = {"Verb", "Definer", "Owner", "Flags", "Args"};
      seen = {};
      current = target_obj;
      while (valid(current))
        verbs_metadata = $prog_utils:get_verbs_metadata(current);
        for metadata in (verbs_metadata)
          verb_name = metadata:name();
          if (verb_name in seen)
            continue;
          endif
          seen = {@seen, verb_name};
          args_spec = metadata:args_spec();
          "Format definer as Name (#num)";
          definer_str = `current.name ! ANY => "???"' + " (" + tostr(current) + ")";
          "Format owner as Name (#num)";
          verb_owner = metadata:verb_owner();
          owner_str = valid(verb_owner) ? `verb_owner.name ! ANY => "???"' + " (" + tostr(verb_owner) + ")" | tostr(verb_owner);
          rows = {@rows, {":" + verb_name, definer_str, owner_str, metadata:flags(), args_spec}};
        endfor
        current = `parent(current) ! ANY => #-1';
      endwhile
    else
      "No Definer column for local-only";
      headers = {"Verb", "Owner", "Flags", "Args"};
      verbs_metadata = $prog_utils:get_verbs_metadata(target_obj);
      for metadata in (verbs_metadata)
        verb_name = metadata:name();
        args_spec = metadata:args_spec();
        "Format owner as Name (#num)";
        verb_owner = metadata:verb_owner();
        owner_str = valid(verb_owner) ? `verb_owner.name ! ANY => "???"' + " (" + tostr(verb_owner) + ")" | tostr(verb_owner);
        rows = {@rows, {":" + verb_name, owner_str, metadata:flags(), args_spec}};
      endfor
    endif
    if (!rows)
      player:inform_current($event:mk_info(player, "No verbs found."));
      return;
    endif
    table = $format.table:mk(headers, rows);
    player:inform_current($event:mk_info(player, table));
  endverb

  verb _display_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj} = args;
    "Show object header info as definition list, then all properties and verbs";
    obj_name = `target_obj.name ! ANY => "(no name)"';
    obj_owner = `target_obj.owner ! ANY => #-1';
    obj_parent = `parent(target_obj) ! ANY => #-1';
    obj_location = `target_obj.location ! ANY => #-1';
    "Build deflist items";
    items = {{"Object", tostr(target_obj)}};
    items = {@items, {"Name", obj_name}};
    owner_str = valid(obj_owner) ? `obj_owner.name ! ANY => "???"' + " (" + tostr(obj_owner) + ")" | "???";
    items = {@items, {"Owner", owner_str}};
    parent_str = valid(obj_parent) ? `obj_parent.name ! ANY => "???"' + " (" + tostr(obj_parent) + ")" | "(none)";
    items = {@items, {"Parent", parent_str}};
    loc_str = valid(obj_location) ? `obj_location.name ! ANY => "???"' + " (" + tostr(obj_location) + ")" | "nowhere";
    items = {@items, {"Location", loc_str}};
    deflist = $format.deflist:mk(items);
    player:inform_current($event:mk_info(player, deflist));
    "Show properties (including inherited)";
    this:_display_all_properties(target_obj, true);
    "Show verbs (including inherited)";
    this:_display_all_verbs(target_obj, true);
  endverb

  verb _challenge_command_perms (this none this) owner: HACKER flags: "rxd"
    player.programmer || raise(E_PERM);
  endverb

  verb "@chmod" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <target> [<perms>] -- Show or change permissions.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@chmod OBJECT[.PROPERTY|:VERB] [PERMISSIONS]")));
      return;
    endif
    "Parse arguments";
    words = argstr:words();
    target_spec = words[1];
    perms_str = length(words) >= 2 ? words[2] | "";
    show_only = length(words) == 1;
    "Parse the target specification";
    parsed = $prog_utils:parse_target_spec(target_spec);
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid target reference. Use 'object', 'object.property', or 'object:verb'"));
      return;
    endif
    object_str = parsed['object_str];
    "Extract type and item_name from new format";
    if (parsed['type] == 'object)
      type = 'object;
      item_name = "";
    else
      "Compound type - get first selector";
      selector = parsed['selectors][1];
      type = selector['kind];
      item_name = selector['item_name];
      "If no item name, treat as object";
      if (!item_name)
        type = 'object;
      endif
      "Check for inherited - not supported";
      if (selector['inherited])
        player:inform_current($event:mk_error(player, "@chmod only works on direct object properties and verbs, not inherited ones."));
        return;
      endif
    endif
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + e[2]));
      return;
    endtry
    "Dispatch based on type";
    if (type == 'property)
      try
        metadata = $prog_utils:get_property_metadata(target_obj, item_name);
        current_perms = metadata:perms();
        current_owner = metadata:owner();
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error getting property metadata: " + e[2]));
        return;
      endtry
      if (show_only)
        obj_display = tostr(target_obj.name, " (", target_obj, ")");
        title = $format.title:mk(obj_display + "." + item_name);
        perms_line = $format.code:mk(current_perms || "(none)");
        content = $format.block:mk(title, perms_line);
        player:inform_current($event:mk_info(player, content));
        return current_perms;
      endif
      "Validate property permissions";
      for i in [1..length(perms_str)]
        char = perms_str[i];
        if (!(char in {"r", "w", "c", ""}))
          player:inform_current($event:mk_error(player, "Property permissions must be subset of 'rwc' (or empty to clear)"));
          return;
        endif
      endfor
      try
        metadata:set_perms(current_owner, perms_str);
        player:inform_current($event:mk_info(player, "Property ." + item_name + " permissions set to " + (perms_str == "" ? "(cleared)" | perms_str) + " on " + tostr(target_obj) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error setting property permissions: " + e[2]));
      endtry
    elseif (type == 'verb)
      try
        metadata = $prog_utils:get_verb_metadata(target_obj, item_name);
        current_perms = metadata:flags();
        current_owner = metadata:verb_owner();
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error getting verb metadata: " + e[2]));
        return;
      endtry
      if (show_only)
        obj_display = tostr(target_obj.name, " (", target_obj, ")");
        title = $format.title:mk(obj_display + ":" + item_name);
        perms_line = $format.code:mk(current_perms || "(none)");
        content = $format.block:mk(title, perms_line);
        player:inform_current($event:mk_info(player, content));
        return current_perms;
      endif
      "Validate verb permissions";
      for i in [1..length(perms_str)]
        char = perms_str[i];
        if (!(char in {"r", "w", "x", "d", ""}))
          player:inform_current($event:mk_error(player, "Verb permissions must be subset of 'rwxd' (or empty to clear)"));
          return;
        endif
      endfor
      try
        metadata:set_perms(current_owner, perms_str);
        player:inform_current($event:mk_info(player, "Verb :" + item_name + " permissions set to " + (perms_str == "" ? "(cleared)" | perms_str) + " on " + tostr(target_obj) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error setting verb permissions: " + e[2]));
      endtry
    elseif (type == 'object)
      "Get current object flags";
      current_flags = target_obj.f;
      current_perms = "";
      if (current_flags % 2 == 1)
        current_perms = current_perms + "r";
      endif
      if (current_flags / 2 % 2 == 1)
        current_perms = current_perms + "w";
      endif
      if (show_only)
        obj_display = tostr(target_obj.name, " (", target_obj, ")");
        title = $format.title:mk(obj_display);
        perms_line = $format.code:mk(current_perms || "(none)");
        content = $format.block:mk(title, perms_line);
        player:inform_current($event:mk_info(player, content));
        return current_perms;
      endif
      "Object flags: only r and w are allowed";
      for i in [1..length(perms_str)]
        char = perms_str[i];
        if (!(char in {"r", "w", ""}))
          player:inform_current($event:mk_error(player, "Object permissions must be subset of 'rw' (or empty to clear)"));
          return;
        endif
      endfor
      if (perms_str == "")
        target_obj.f = 0;
      else
        flags = 0;
        if (index(perms_str, "r"))
          flags = flags + 1;
        endif
        if (index(perms_str, "w"))
          flags = flags + 2;
        endif
        target_obj.f = flags;
      endif
      player:inform_current($event:mk_info(player, "Object " + tostr(target_obj) + " permissions set to " + (perms_str == "" ? "(cleared)" | perms_str) + "."));
    else
      player:inform_current($event:mk_error(player, "Invalid reference type"));
    endif
  endverb

  verb _do_grep_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "UI wrapper around prog_utils:grep_object - adds owner metadata for display";
    "Returns matches with owner information added for formatting";
    caller == this || raise(E_PERM);
    {pattern, search_obj, casematters} = args;
    "Get base matches from prog_utils (returns {obj, verb_name, line_num, matching_line})";
    base_matches = $prog_utils:grep_object(pattern, search_obj, casematters);
    "Add owner metadata to each match for display";
    display_matches = {};
    "Build lookup map of verb metadata for efficient access";
    verb_metadata_map = [];
    for match in (base_matches)
      {o, verb_name, line_num, matching_line} = match;
      obj_key = tostr(o);
      if (!(obj_key in mapkeys(verb_metadata_map)))
        "First time seeing this object - build metadata map for it";
        verbs_metadata = $prog_utils:get_verbs_metadata(o);
        obj_metadata_map = [];
        for metadata in (verbs_metadata)
          obj_metadata_map[metadata:name()] = metadata;
        endfor
        verb_metadata_map[obj_key] = obj_metadata_map;
      endif
      "Look up verb metadata by name";
      obj_metadata_map = verb_metadata_map[obj_key];
      if (verb_name in mapkeys(obj_metadata_map))
        metadata = obj_metadata_map[verb_name];
        verb_owner = metadata:verb_owner();
        owner_name = valid(verb_owner) ? verb_owner.name | "Recycled";
        "Append owner info to match for display";
        display_matches = {@display_matches, {o, verb_name, owner_name, tostr(verb_owner), line_num, matching_line}};
      endif
    endfor
    return display_matches;
  endverb

  verb _do_get_available_objects (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get list of objects available for searching";
    caller == this || raise(E_PERM);
    "Get all objects with wizard permissions";
    all_objects = objects();
    "Filter to objects readable by caller";
    perms = caller_perms();
    if (perms.wizard)
      return all_objects;
    endif
    available = {};
    for o in (all_objects)
      "Object is available if caller owns it or it has read flag";
      if (o.owner == perms || o.r)
        available = {@available, o};
      endif
    endfor
    return available;
  endverb

  verb "@grep" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <pattern> [<object>] -- Search verb code for a pattern.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " PATTERN [OBJECT]")));
      return;
    endif
    "Parse arguments: pattern and optional object";
    words = argstr:words();
    if (!words)
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " PATTERN [OBJECT]")));
      return;
    endif
    pattern = words[1];
    casematters = false;
    search_objects = {};
    "Determine what to search";
    if (length(words) >= 2)
      "User specified an object to search";
      target_str = words[2];
      try
        target_obj = $match:match_object(target_str, player);
        search_objects = {target_obj};
      except (ANY)
        player:inform_current($event:mk_error(player, "Could not find object: " + target_str));
        return;
      endtry
    else
      "No target specified - search all available objects";
      search_objects = this:_do_get_available_objects();
    endif
    "Inform user we're starting";
    player:inform_current($event:mk_info(player, "Searching for \"" + pattern + "\" in " + tostr(length(search_objects)) + " objects..."));
    "Search all selected objects and collect matches";
    all_matches = {};
    obj_count = 0;
    for o in (search_objects)
      obj_count = obj_count + 1;
      if (obj_count % 3 == 0)
        suspend_if_needed();
      endif
      matches = this:_do_grep_object(pattern, o, casematters);
      all_matches = {@all_matches, @matches};
    endfor
    "Format and display results";
    if (!all_matches)
      player:inform_current($event:mk_info(player, "No matches found."));
      return;
    endif
    "Build table rows";
    headers = {"Verb", "Line", "Owner", "Code"};
    rows = {};
    row_count = 0;
    for match in (all_matches)
      row_count = row_count + 1;
      if (row_count % 5 == 0)
        suspend_if_needed();
      endif
      {o, verb_name, owner_name, owner_id, line_num, code_snippet} = match;
      verb_ref = toliteral(o) + ":" + verb_name;
      owner_str = owner_name + " (" + owner_id + ")";
      code_cell = $format.code:mk(code_snippet, 'moo);
      rows = {@rows, {verb_ref, tostr(line_num), owner_str, code_cell}};
    endfor
    suspend_if_needed();
    "Create and send table";
    result_table = $format.table:mk(headers, rows);
    summary = tostr("Found ", length(all_matches), " match", length(all_matches) != 1 ? "es" | "", " for \"", pattern, "\"");
    content = $format.block:mk(summary, result_table);
    player:inform_current($event:mk_info(player, content));
  endverb

  verb "@codep*aste" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: -- Paste MOO code with syntax highlighting to the room.";
    this:_challenge_command_perms();
    if (!valid(player.location))
      return;
    endif
    content = player:read_multiline("Enter MOO code to paste");
    if (content == "@abort" || typeof(content) != STR)
      player:inform_current($event:mk_info(player, "Code paste aborted."));
      return;
    endif
    lines = content:split("\n");
    if (length(lines) > 50)
      player:inform_current($event:mk_error(player, "Code paste is greater than 50 lines, too long."));
      return;
    endif
    title = $format.title:mk({$sub:nc(), " ", $sub:self_alt("codepaste", "codepastes")}, 4);
    code = $format.code:mk(content, 'moo);
    event = $event:mk_paste(player, title, code):with_presentation_hint('inset):with_group('paste);
    player.location:announce(event);
  endverb

  verb "@doc*umentation" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Display developer documentation.";
    "this:_challenge_command_perms();\n    set_task_perms(player);";
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@doc OBJECT\n@doc OBJECT:VERB\n@doc OBJECT.PROPERTY")));
      return;
    endif
    target_spec = argstr:trim();
    "Parse the target specification";
    parsed = $prog_utils:parse_target_spec(target_spec);
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid format. Use 'object', 'object:verb', or 'object.property'"));
      return;
    endif
    object_str = parsed['object_str];
    "Extract type and item_name from new format";
    if (parsed['type] == 'object)
      type = 'object;
      item_name = "";
    else
      "Compound type - get first selector";
      selector = parsed['selectors][1];
      type = selector['kind];
      item_name = selector['item_name];
      "If no item name specified, treat as object";
      if (!item_name)
        type = 'object;
      endif
    endif
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    "Dispatch based on type";
    if (type == 'object)
      "Get object documentation";
      obj_display = `target_obj:display_name() ! E_VERBNF => target_obj.name';
      doc_text = $help_utils:get_object_documentation(target_obj);
      title = "Documentation for " + obj_display + " (" + toliteral(target_obj) + ")";
      content = $help_utils:format_documentation_display(title, doc_text);
      player:inform_current($event:mk_info(player, content):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_presentation_hint('inset));
    elseif (type == 'verb)
      "Find where the verb is actually defined";
      verb_location = target_obj:find_verb_definer(item_name);
      if (verb_location == #-1)
        player:inform_current($event:mk_error(player, "Verb '" + tostr(item_name) + "' not found on " + tostr(target_obj) + " or its ancestors."));
        return;
      endif
      "Get verb documentation";
      verb_obj_display = `verb_location:display_name() ! E_VERBNF => verb_location.name';
      doc_text = $help_utils:extract_verb_documentation(verb_location, item_name);
      title = "Documentation for " + verb_obj_display + " (" + toliteral(verb_location) + "):" + tostr(item_name);
      content = $help_utils:format_documentation_display(title, $format.code:mk(doc_text));
      player:inform_current($event:mk_info(player, content):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_presentation_hint('inset));
    elseif (type == 'property)
      "Check if property exists";
      if (!(item_name in properties(target_obj)))
        player:inform_current($event:mk_error(player, "Property '" + item_name + "' not found on " + tostr(target_obj) + "."));
        return;
      endif
      "Get property documentation";
      obj_display = `target_obj:display_name() ! E_VERBNF => target_obj.name';
      doc_text = $help_utils:property_documentation(target_obj, item_name);
      title = "Documentation for " + obj_display + " (" + toliteral(target_obj) + ")." + item_name;
      content = $help_utils:format_documentation_display(title, $format.code:mk(doc_text));
      player:inform_current($event:mk_info(player, content):with_metadata('preferred_content_types, {'text_djot, 'text_plain}):with_presentation_hint('inset));
    else
      player:inform_current($event:mk_error(player, "Invalid reference type"));
    endif
  endverb

  verb "@rename" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Rename an object or verb. Usage: @rename <object> to <name[:aliases]> or @rename <object>:<verb> to <new-verb-name>";
    caller != player && raise(E_PERM);
    player.programmer || raise(E_PERM, "Programmer features required.");
    set_task_perms(player);
    "Check for verb rename syntax (colon in dobjstr)";
    if (dobjstr && ":" in dobjstr)
      "Verb rename - validate args";
      if (!argstr || (prepstr && prepstr != "to") || !iobjstr)
        player:inform_current($event:mk_error(player, $format.code:mk("@rename OBJECT:VERB to NEW-VERB-NAME")));
        return;
      endif
      try
        "Parse object:verb";
        parsed = dobjstr:parse_verbref();
        if (!parsed)
          player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb'"));
          return;
        endif
        {object_str, verb_name} = parsed;
        "Match the object";
        target_obj = $match:match_object(object_str, player);
        typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
        !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
        "Check verb exists";
        info = `verb_info(target_obj, verb_name) ! E_VERBNF => 0';
        if (!info)
          player:inform_current($event:mk_error(player, "Verb '" + verb_name + "' not found on " + tostr(target_obj) + "."));
          return;
        endif
        {verb_owner, verb_perms, old_names} = info;
        "Check permissions - must be owner or wizard";
        if (!player.wizard && verb_owner != player)
          raise(E_PERM, "You do not have permission to rename " + tostr(target_obj) + ":" + verb_name + ".");
        endif
        "Get new verb name(s) - spaces separate multiple names";
        new_names = iobjstr:trim();
        !new_names && raise(E_INVARG, "Verb name cannot be blank.");
        "Set the new verb name";
        set_verb_info(target_obj, verb_name, {verb_owner, verb_perms, new_names});
        message = "Renamed verb " + tostr(target_obj) + ":" + verb_name + " to \"" + new_names + "\".";
        player:inform_current($event:mk_info(player, message));
        return 1;
      except e (ANY)
        message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
        player:inform_current($event:mk_error(player, message));
        return 0;
      endtry
    endif
    "Object rename - check for valid usage";
    if (!argstr || !dobjstr || (prepstr && prepstr != "to") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@rename OBJECT to NAME[:ALIASES]\n@rename OBJECT:VERB to NEW-VERB-NAME")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to rename " + tostr(target_obj) + ".");
      endif
      parsed = $str_proto:parse_name_aliases(iobjstr);
      new_name = parsed[1];
      new_aliases = parsed[2];
      !new_name && raise(E_INVARG, "Object name cannot be blank.");
      old_name = `target_obj.name ! ANY => "(no name)"';
      this:_do_rename_object(target_obj, new_name, new_aliases);
      message = "Renamed \"" + old_name + "\" (" + tostr(target_obj) + ") to \"" + new_name + "\".";
      if (new_aliases)
        alias_str = new_aliases:join(", ");
        message = message + " Aliases: " + alias_str + ".";
      endif
      player:inform_current($event:mk_info(player, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for programmer commands.";
    {for_player, ?topic = ""} = args;
    "Main overview topic";
    overview = $help:mk("programming", "Programmer commands", "Commands for examining and modifying code:\n\n`@list`, `@verb`, `@rmverb`, `@verbs`, `@properties`, `@property`, `@rmproperty`, `@args`, `@show`, `@chmod`, `@grep`, `@doc`, `@edit`, `@browse`, `@codepaste`, `eval`\n\nUse `help <command>` for details on each command.", {"prog", "code", "verbs"}, 'programming, {"building"});
    "Comprehensive @show help";
    show_help_text = "@show <object>[selectors] -- Display object information.\n\n";
    show_help_text = show_help_text + "**Selectors:**\n";
    show_help_text = show_help_text + "  `.`   Local properties only\n";
    show_help_text = show_help_text + "  `..`  All properties (including inherited)\n";
    show_help_text = show_help_text + "  `:`   Local verbs only\n";
    show_help_text = show_help_text + "  `::`  All verbs (including inherited)\n\n";
    show_help_text = show_help_text + "**Examples:**\n";
    show_help_text = show_help_text + "  `@show #1`       Show summary with counts and hints\n";
    show_help_text = show_help_text + "  `@show #1.`      Show local properties\n";
    show_help_text = show_help_text + "  `@show #1..`     Show all properties (+ inherited)\n";
    show_help_text = show_help_text + "  `@show #1:`      Show local verbs\n";
    show_help_text = show_help_text + "  `@show #1::`     Show all verbs (+ inherited)\n";
    show_help_text = show_help_text + "  `@show #1.name`  Show specific property\n";
    show_help_text = show_help_text + "  `@show #1:tell`  Show specific verb\n";
    show_help_text = show_help_text + "  `@show #1.:`     Show local props + local verbs\n";
    show_help_text = show_help_text + "  `@show #1..:`    Show all props + local verbs\n";
    show_help_text = show_help_text + "  `@show #1.::` Show local props + all verbs\n";
    show_help_text = show_help_text + "  `@show #1..::`   Show all props + all verbs\n\n";
    show_help_text = show_help_text + "Alias: `@display`";
    show_topic = $help:mk("@show", "@show - Display object info", show_help_text, {"@display", "show", "display"}, 'programming);
    "If asking for all topics, just return overview";
    topic == "" && return {overview};
    "Check if topic matches overview";
    overview:matches(topic) && return overview;
    "Check if topic matches @show";
    show_topic:matches(topic) && return show_topic;
    "Try to generate help from verb HINT tags";
    verb_help = `$help_utils:verb_help_from_hint(this, topic, 'programming) ! ANY => 0';
    typeof(verb_help) != INT && return verb_help;
    return 0;
  endverb

  verb _format_eval_result (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format an eval result. Returns {type, content} where type is 'simple or 'deflist.";
    "For simple values, content is a string. For objects, content is a deflist flyweight.";
    {result} = args;
    if (typeof(result) == OBJ)
      "Format object as definition list";
      obj_str = tostr(result);
      if (valid(result))
        name = `result.name ! ANY => "(no name)"';
        owner = `result.owner ! ANY => #-1';
        owner_str = valid(owner) ? owner.name + " (" + tostr(owner) + ")" | "???";
        loc = `result.location ! ANY => #-1';
        loc_str = valid(loc) ? loc.name + " (" + tostr(loc) + ")" | "nowhere";
        items = {{"Object", obj_str}, {"Name", name}, {"Owner", owner_str}, {"Location", loc_str}};
        return {'deflist, $format.deflist:mk(items)};
      else
        return {'simple, obj_str + " (invalid)"};
      endif
    endif
    "For non-objects, just use toliteral";
    return {'simple, toliteral(result)};
  endverb

  verb _display_summary (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display object summary with counts and usage hints.";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj} = args;
    "Get object info";
    obj_name = `target_obj.name ! ANY => "(no name)"';
    obj_owner = `target_obj.owner ! ANY => #-1';
    obj_parent = `parent(target_obj) ! ANY => #-1';
    obj_location = `target_obj.location ! ANY => #-1';
    "Count local properties and verbs";
    local_props = this:_do_get_properties(target_obj);
    local_verbs = this:_do_get_verbs(target_obj);
    local_prop_count = length(local_props);
    local_verb_count = length(local_verbs);
    "Count inherited (walk up parent chain)";
    inherited_prop_count = 0;
    inherited_verb_count = 0;
    current = `parent(target_obj) ! ANY => #-1';
    while (valid(current))
      inherited_prop_count = inherited_prop_count + length(`properties(current) ! ANY => {}');
      inherited_verb_count = inherited_verb_count + length(`verbs(current) ! ANY => {}');
      current = `parent(current) ! ANY => #-1';
    endwhile
    "Build single deflist with all info - wrap object refs in djot backticks";
    obj_ref = tostr(target_obj);
    items = {{"Object", "`" + obj_ref + "`"}};
    items = {@items, {"Name", obj_name}};
    owner_str = valid(obj_owner) ? `obj_owner.name ! ANY => "???"' + " (`" + tostr(obj_owner) + "`)" | "???";
    items = {@items, {"Owner", owner_str}};
    parent_str = valid(obj_parent) ? `obj_parent.name ! ANY => "???"' + " (`" + tostr(obj_parent) + "`)" | "(none)";
    items = {@items, {"Parent", parent_str}};
    loc_str = valid(obj_location) ? `obj_location.name ! ANY => "???"' + " (`" + tostr(obj_location) + "`)" | "nowhere";
    items = {@items, {"Location", loc_str}};
    "Add counts to same deflist";
    prop_summary = tostr(local_prop_count) + " local";
    if (inherited_prop_count > 0)
      prop_summary = prop_summary + ", " + tostr(inherited_prop_count) + " inherited";
    endif
    verb_summary = tostr(local_verb_count) + " local";
    if (inherited_verb_count > 0)
      verb_summary = verb_summary + ", " + tostr(inherited_verb_count) + " inherited";
    endif
    items = {@items, {"Properties", prop_summary}};
    items = {@items, {"Verbs", verb_summary}};
    deflist = $format.deflist:mk(items);
    "Build concise usage hint with djot code formatting";
    hint = "Try: `@show " + obj_ref + ".:` (local) or `" + obj_ref + "..::` (all). See `@show` for syntax.";
    "Combine and display with djot content type";
    content = $format.block:mk(deflist, hint);
    event = $event:mk_info(player, content);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    player:inform_current(event);
  endverb

  verb _display_header (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display object header info only (no counts/hints).";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj} = args;
    "Get object info";
    obj_name = `target_obj.name ! ANY => "(no name)"';
    obj_owner = `target_obj.owner ! ANY => #-1';
    obj_parent = `parent(target_obj) ! ANY => #-1';
    obj_location = `target_obj.location ! ANY => #-1';
    "Build deflist with object info - wrap object refs in djot backticks";
    obj_ref = tostr(target_obj);
    items = {{"Object", "`" + obj_ref + "`"}};
    items = {@items, {"Name", obj_name}};
    owner_str = valid(obj_owner) ? `obj_owner.name ! ANY => "???"' + " (`" + tostr(obj_owner) + "`)" | "???";
    items = {@items, {"Owner", owner_str}};
    parent_str = valid(obj_parent) ? `obj_parent.name ! ANY => "???"' + " (`" + tostr(obj_parent) + "`)" | "(none)";
    items = {@items, {"Parent", parent_str}};
    loc_str = valid(obj_location) ? `obj_location.name ! ANY => "???"' + " (`" + tostr(obj_location) + "`)" | "nowhere";
    items = {@items, {"Location", loc_str}};
    deflist = $format.deflist:mk(items);
    event = $event:mk_info(player, deflist);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    player:inform_current(event);
  endverb
endobject
