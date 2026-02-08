object PROG_FEATURES
  name: "Programmer Features"
  parent: BUILDER_FEATURES
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  property help_source (owner: ARCH_WIZARD, flags: "rc") = PROG_HELP_TOPICS;

  override description = "Provides programmer commands (@show, @program, @grep, @chmod, @move, @which, @clear-property) for object and code management.";
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
      traceback = {"Eval failed: " + toliteral(id[1]) + " " + toliteral(id[2]) + ":"};
      for tb in (id[4])
        target = toliteral(tb[4]) + ":";
        if (tb[4] == #-1)
          target = "builtin function ";
        endif
        traceback = {@traceback, tostr("... called from ", target, tb[2], tb[4] != tb[1] ? tostr(" (this == ", tb[1], ")") | "", ", line ", tb[6])};
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
        player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
        return;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
        return;
      endtry
      "Find and retrieve the verb code";
      try
        verb_name = this:_do_resolve_verb_name(target_obj, verb_name);
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
      parsed = $prog_utils:parse_target_spec(target_string);
      if (!parsed || parsed['type] != 'compound)
        player:inform_current($event:mk_error(player, "Invalid property reference format. Use 'object.property'"));
        return;
      endif
      selectors = parsed['selectors];
      if (length(selectors) != 1)
        player:inform_current($event:mk_error(player, "Invalid property reference format. Use 'object.property'"));
        return;
      endif
      selector = selectors[1];
      if (selector['kind] != 'property || !selector['item_name] || selector['inherited])
        player:inform_current($event:mk_error(player, "Invalid property reference format. Use 'object.property'"));
        return;
      endif
      object_str = parsed['object_str];
      prop_name = selector['item_name];
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
      "Check property exists and open editor";
      if (!target_obj:check_property_exists(prop_name))
        player:inform_current($event:mk_error(player, "Property '" + prop_name + "' not found on " + target_obj.name + "."));
        return;
      endif
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
    try
      target_obj = this:_resolve_object_ref(target_string, player, "object");
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, tostr(e[2])));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
      return;
    endtry
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
    if (typeof(initial_content) == TYPE_LIST)
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
    "Parse options from argstr (suffix flags only)";
    verbref_string = argstr:trim();
    show_all_parens = 0;
    hide_numbers = 0;
    while (1)
      lowered = verbref_string:lowercase();
      changed = 0;
      opt = " with parentheses";
      opt_len = length(opt);
      if (length(verbref_string) > opt_len && lowered[length(lowered) - opt_len + 1..$] == opt)
        show_all_parens = 1;
        verbref_string = verbref_string[1..length(verbref_string) - opt_len]:trim();
        changed = 1;
      endif
      opt = " without numbers";
      opt_len = length(opt);
      if (length(verbref_string) > opt_len && lowered[length(lowered) - opt_len + 1..$] == opt)
        hide_numbers = 1;
        verbref_string = verbref_string[1..length(verbref_string) - opt_len]:trim();
        changed = 1;
      endif
      if (!changed)
        break;
      endif
    endwhile
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
      player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
      return;
    endtry
    "Find and retrieve the verb code";
    try
      verb_name = this:_do_resolve_verb_name(target_obj, verb_name);
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
      player:inform_current($event:mk_error(player, $format.code:mk(verb + " OBJECT:VERB-NAME(S) [DOBJ [PREP [IOBJ [PERMISSIONS [OWNER]]]]]\nHint: quote names that contain spaces or look like args.")));
      return;
    endif
    "Parse the arguments";
    colon = index(argstr, ":");
    if (!colon)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name(s)'"));
      return;
    endif
    object_token = argstr[1..colon - 1]:trim();
    remainder = argstr[colon + 1..length(argstr)]:trim();
    if (!remainder)
      player:inform_current($event:mk_error(player, "Verb name required. Use 'object:verb-name(s)'"));
      return;
    endif
    verb_tokens = remainder:words();
    if (!verb_tokens)
      player:inform_current($event:mk_error(player, "Verb name required. Use 'object:verb-name(s)'"));
      return;
    endif
    parsed = (object_token + ":" + verb_tokens[1]):parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name(s)'"));
      return;
    endif
    {object_str, first_verb_name} = parsed;
    verb_tokens[1] = first_verb_name;
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
    "Parse optional arguments with defaults";
    dobj = "none";
    prep = "none";
    iobj = "none";
    permissions = "rxd";
    verb_owner = player;
    perms_set = 0;
    cursor = length(verb_tokens);
    fn is_perm_string(s)
      if (!s)
        return false;
      endif
      for i in [1..length(s)]
        if (!(s[i] in {"r", "w", "x", "d"}))
          return false;
        endif
      endfor
      return true;
    endfn
    if (cursor >= 2)
      maybe_perms = verb_tokens[cursor - 1];
      maybe_owner = verb_tokens[cursor];
      if (is_perm_string(maybe_perms))
        try
          verb_owner = $match:match_object(maybe_owner, player);
          permissions = maybe_perms;
          perms_set = 1;
          cursor = cursor - 2;
        except e (ANY)
          "Not an owner token; leave for verb names";
        endtry
      endif
    endif
    if (!perms_set && cursor >= 1 && is_perm_string(verb_tokens[cursor]))
      permissions = verb_tokens[cursor];
      perms_set = 1;
      cursor = cursor - 1;
    endif
    if (cursor >= 1 && verb_tokens[cursor] in {"none", "this", "any"})
      iobj = verb_tokens[cursor];
      cursor = cursor - 1;
    endif
    if (cursor >= 1 && $prog_utils:is_valid_prep(verb_tokens[cursor]))
      prep = verb_tokens[cursor];
      cursor = cursor - 1;
    endif
    if (cursor >= 1 && verb_tokens[cursor] in {"none", "this", "any"})
      dobj = verb_tokens[cursor];
      cursor = cursor - 1;
    endif
    if (cursor < 1)
      player:inform_current($event:mk_error(player, "Verb name required. If names resemble args, quote the verb names."));
      return;
    endif
    verb_names = verb_tokens[1..cursor]:join(" ");
    if (!(dobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Direct object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!(iobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Indirect object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!$prog_utils:is_valid_prep(prep))
      player:inform_current($event:mk_error(player, "Invalid preposition: '" + prep + "'. Use 'none', 'any', or a valid preposition."));
      return;
    endif
    for i in [1..length(permissions)]
      char = permissions[i];
      if (!(char in {"r", "w", "x", "d"}))
        player:inform_current($event:mk_error(player, "Permissions must be subset of 'rwxd'"));
        return;
      endif
    endfor
    if (verb_owner != player && !player.wizard)
      player:inform_current($event:mk_error(player, "Only wizards can create verbs with other owners"));
      return;
    endif
    try
      this:_do_add_verb(target_obj, {verb_owner, permissions, verb_names}, {dobj, prep, iobj});
      player:inform_current($event:mk_info(player, "Verb " + tostr(target_obj) + ":" + verb_names + " added."));
    except e (E_PERM)
      player:inform_current($event:mk_error(player, "Permission denied."));
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "Unable to add verb: " + tostr(e[2])));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error adding verb: " + tostr(e[2])));
    endtry
  endverb

  verb _do_delete_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to delete verb with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_name} = args;
    delete_verb(target_obj, verb_name);
  endverb

  verb "@rmverb" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> [--dry-run] -- Remove a verb from an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name [--dry-run]"));
      return;
    endif
    raw = argstr:trim();
    dry_run = 0;
    if (index(raw, "--dry-run"))
      dry_run = 1;
      raw = raw:replace_all(" --dry-run", "");
      raw = raw:replace_all("--dry-run", "");
      raw = raw:trim();
    endif
    spec = raw;
    parsed = $prog_utils:parse_target_spec(spec);
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name'"));
      return;
    endif
    selectors = parsed['selectors];
    if (length(selectors) != 1)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name'"));
      return;
    endif
    selector = selectors[1];
    if (selector['kind] != 'verb || !selector['item_name] || selector['inherited])
      player:inform_current($event:mk_error(player, "Use a direct verb reference: object:verb-name"));
      return;
    endif
    object_str = parsed['object_str];
    verb_name = selector['item_name];
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
      return;
    endtry
    try
      verb_name = this:_do_resolve_verb_name(target_obj, verb_name);
      if (dry_run)
        player:inform_current($event:mk_info(player, "Dry-run: would remove verb " + tostr(target_obj) + ":" + verb_name));
        return;
      endif
      this:_do_delete_verb(target_obj, verb_name);
      player:inform_current($event:mk_info(player, "Verb " + tostr(target_obj) + ":" + verb_name + " removed."));
    except e (E_VERBNF)
      player:inform_current($event:mk_error(player, "Verb '" + verb_name + "' not found on " + tostr(target_obj) + "."));
    except e (E_PERM)
      player:inform_current($event:mk_error(player, "Permission denied."));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error removing verb: " + tostr(e[2])));
    endtry
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
    "HINT: <object>.<property> [value [perms [owner]]] -- Add a property to an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    "Parse and validate arguments";
    !argstr && return player:inform_current($event:mk_error(player, "Usage: @property OBJECT.PROP-NAME [VALUE [PERMS [OWNER]]]"));
    parsed = $prog_utils:parse_target_spec(args[1]);
    !parsed || parsed['type] != 'compound && return player:inform_current($event:mk_error(player, "Usage: @property <object>.<prop-name>"));
    selector = parsed['selectors][1];
    selector['kind] != 'property || !selector['item_name] && return player:inform_current($event:mk_error(player, "Usage: @property <object>.<prop-name>"));
    prop_name = selector['item_name];
    target_obj = $match:match_object(parsed['object_str], player);
    "Parse optional value, perms, owner";
    value = 0;
    perms = "rc";
    owner = player;
    if (length(args) > 1)
      offset = index(argstr, args[1]) + length(args[1]);
      remainder = argstr[offset..$]:trim();
      if (remainder)
        "Try to evaluate initial value";
        eval_result = $prog_utils:eval_literal(remainder);
        if (eval_result[1])
          value = eval_result[2];
          remainder = eval_result[3]:trim();
        endif
        "Parse remaining words for perms and owner";
        remaining_words = remainder:words();
        if (length(remaining_words) > 0)
          maybe_perms = remaining_words[1];
          !match(maybe_perms, "^[rwc]*$") && return player:inform_current($event:mk_error(player, "Invalid permissions: " + maybe_perms + ". Use r, w, c (or empty for none)."));
          perms = maybe_perms;
          if (length(remaining_words) > 1)
            owner = $match:match_object(remaining_words[2], player);
          endif
        endif
      endif
    endif
    "Add the property";
    try
      add_property(target_obj, prop_name, value, {owner, perms});
      "Format flags description";
      flag_parts = {};
      index(perms, "r") && (flag_parts = {@flag_parts, "r=read"});
      index(perms, "w") && (flag_parts = {@flag_parts, "w=write"});
      index(perms, "c") && (flag_parts = {@flag_parts, "c=chown"});
      flags_desc = flag_parts ? flag_parts:join(", ") | "(none)";
      description = tostr(target_obj) + "." + prop_name + " = " + toliteral(value);
      player:inform_current($event:mk_info(player, "Added `" + description + "` with flags: " + flags_desc):as_djot():as_inset());
    except e (E_INVARG)
      if (index(tostr(e[2]), "Duplicate"))
        return player:inform_current($event:mk_error(player, "Property `" + prop_name + "` already exists on " + tostr(target_obj) + "."):as_djot():as_inset());
      endif
      raise(e[1], e[2]);
    endtry
  endverb

  verb "@rmprop*erty" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<property> [--dry-run] -- Remove a property from an object.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@rmproperty OBJECT.PROP-NAME [--dry-run]")));
      return;
    endif
    raw = argstr:trim();
    dry_run = 0;
    if (index(raw, "--dry-run"))
      dry_run = 1;
      raw = raw:replace_all(" --dry-run", "");
      raw = raw:replace_all("--dry-run", "");
      raw = raw:trim();
    endif
    target_spec = raw;
    parsed = $prog_utils:parse_target_spec(target_spec);
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
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    if (!(prop_name in properties(target_obj)))
      player:inform_current($event:mk_error(player, "Property " + prop_name + " not found on " + tostr(target_obj) + "."));
      return;
    endif
    if (dry_run)
      player:inform_current($event:mk_info(player, "Dry-run: would delete property " + tostr(target_obj) + "." + prop_name));
      return;
    endif
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
    input = argstr:trim();
    words = input:words();
    if (!words)
      player:inform_current($event:mk_error(player, "Invalid verb reference format. Use 'object:verb-name'"));
      return;
    endif
    target_spec = words[1];
    parsed = target_spec:parse_verbref();
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
    verb_name = this:_do_resolve_verb_name(target_obj, verb_name);
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
    if (!(new_dobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Direct object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!(new_iobj in {"none", "this", "any"}))
      player:inform_current($event:mk_error(player, "Indirect object must be 'none', 'this', or 'any'"));
      return;
    endif
    if (!$prog_utils:is_valid_prep(new_prep))
      player:inform_current($event:mk_error(player, "Invalid preposition: '" + new_prep + "'. Use 'none', 'any', or a valid preposition."));
      return;
    endif
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
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    "Dispatch based on type";
    if (parsed['type] == 'object)
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
      try
        if (kind == 'property)
          if (item_name)
            if (inherited)
              this:_display_inherited_property(target_obj, item_name);
            else
              this:_display_property(target_obj, item_name);
            endif
          else
            this:_display_all_properties(target_obj, inherited);
          endif
        elseif (kind == 'verb)
          if (item_name)
            if (inherited)
              this:_display_inherited_verb(target_obj, item_name);
            else
              this:_display_verb(target_obj, item_name);
            endif
          else
            this:_display_all_verbs(target_obj, inherited);
          endif
        endif
      except e (ANY)
        message = "Error displaying selector.";
        if (typeof(e) == TYPE_LIST && length(e) >= 2 && typeof(e[2]) == TYPE_STR)
          message = message + " " + e[2];
        endif
        player:inform_current($event:mk_error(player, message));
      endtry
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
          if (typeof(metadata) != TYPE_FLYWEIGHT)
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
        if (typeof(metadata) != TYPE_FLYWEIGHT)
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
      player:inform_current($event:mk_error(player, $format.code:mk("@chmod OBJECT[.PROPERTY|:VERB] [PERMISSIONS]\nPERMISSIONS: rwx... | +rwx... | -rwx...")));
      return;
    endif
    "Parse target and optional permissions from the end of the command.";
    spec = argstr:trim();
    words = spec:words();
    target_spec = spec;
    perms_spec = "";
    show_only = 1;
    if (length(words) >= 2)
      maybe_perms = words[$];
      if (match(maybe_perms, "^[+-]?[rwxcd]*$"))
        perms_spec = maybe_perms;
        target_spec = words[1..$ - 1]:join(" "):trim();
        show_only = 0;
        if (!target_spec)
          player:inform_current($event:mk_error(player, $format.code:mk("@chmod OBJECT[.PROPERTY|:VERB] [PERMISSIONS]")));
          return;
        endif
      endif
    endif
    "Parse the target specification";
    parsed = $prog_utils:parse_target_spec(target_spec);
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid target reference. Use 'object', 'object.property', or 'object:verb'"));
      return;
    endif
    object_str = parsed['object_str];
    "Extract type and item_name from parsed format";
    if (parsed['type] == 'object)
      type = 'object;
      item_name = "";
    else
      selector = parsed['selectors][1];
      type = selector['kind];
      item_name = selector['item_name];
      if (!item_name)
        type = 'object;
      endif
      if (selector['inherited])
        player:inform_current($event:mk_error(player, "@chmod only works on direct object properties and verbs, not inherited ones."));
        return;
      endif
    endif
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    fn normalize_perms(current_perms, spec_text, allowed_chars)
      op = "set";
      payload = spec_text;
      if (length(spec_text) >= 1 && (spec_text[1] == "+" || spec_text[1] == "-"))
        op = spec_text[1] == "+" ? "add" | "remove";
        payload = length(spec_text) > 1 ? spec_text[2..$] | "";
      endif
      for i in [1..length(payload)]
        ch = payload[i];
        if (!index(allowed_chars, ch))
          return {0, ch};
        endif
      endfor
      new_perms = "";
      for i in [1..length(allowed_chars)]
        ch = allowed_chars[i];
        keep = 0;
        if (op == "set")
          keep = index(payload, ch);
        elseif (op == "add")
          keep = index(current_perms, ch) || index(payload, ch);
        else
          keep = index(current_perms, ch) && !index(payload, ch);
        endif
        if (keep)
          new_perms = new_perms + ch;
        endif
      endfor
      return {1, new_perms, op};
    endfn
    "Dispatch based on type";
    if (type == 'property)
      try
        metadata = $prog_utils:get_property_metadata(target_obj, item_name);
        current_perms = metadata:perms();
        current_owner = metadata:owner();
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error getting property metadata: " + tostr(e[2])));
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
      normalized = normalize_perms(current_perms, perms_spec, "rwc");
      if (!normalized[1])
        player:inform_current($event:mk_error(player, "Property permissions must use only 'rwc'."));
        return;
      endif
      new_perms = normalized[2];
      try
        metadata:set_perms(current_owner, new_perms);
        player:inform_current($event:mk_info(player, "Property ." + item_name + " permissions set to " + (new_perms == "" ? "(cleared)" | new_perms) + " on " + tostr(target_obj) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error setting property permissions: " + tostr(e[2])));
      endtry
    elseif (type == 'verb)
      try
        metadata = $prog_utils:get_verb_metadata(target_obj, item_name);
        current_perms = metadata:flags();
        current_owner = metadata:verb_owner();
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error getting verb metadata: " + tostr(e[2])));
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
      normalized = normalize_perms(current_perms, perms_spec, "rwxd");
      if (!normalized[1])
        player:inform_current($event:mk_error(player, "Verb permissions must use only 'rwxd'."));
        return;
      endif
      new_perms = normalized[2];
      try
        metadata:set_perms(current_owner, new_perms);
        player:inform_current($event:mk_info(player, "Verb :" + item_name + " permissions set to " + (new_perms == "" ? "(cleared)" | new_perms) + " on " + tostr(target_obj) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error setting verb permissions: " + tostr(e[2])));
      endtry
    elseif (type == 'object)
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
      normalized = normalize_perms(current_perms, perms_spec, "rw");
      if (!normalized[1])
        player:inform_current($event:mk_error(player, "Object permissions must use only 'rw'."));
        return;
      endif
      new_perms = normalized[2];
      flags = 0;
      if (index(new_perms, "r"))
        flags = flags + 1;
      endif
      if (index(new_perms, "w"))
        flags = flags + 2;
      endif
      target_obj.f = flags;
      player:inform_current($event:mk_info(player, "Object " + tostr(target_obj) + " permissions set to " + (new_perms == "" ? "(cleared)" | new_perms) + "."));
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
    "HINT: [options] <pattern> [<object>] -- Search verb code for a pattern.";
    this:_challenge_command_perms();
    set_task_perms(player);
    start_time = ftime();
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@grep [--regex] [--case-sensitive|-s|-i] [--owner OBJECT] [--limit N] PATTERN [OBJECT]")));
      return;
    endif
    input = argstr:trim();
    if (!input)
      player:inform_current($event:mk_error(player, $format.code:mk("@grep [options] PATTERN [OBJECT]")));
      return;
    endif
    tokens = input:words();
    idx = 1;
    casematters = 0;
    use_regex = 0;
    owner_filter = 0;
    limit = 0;
    while (idx <= length(tokens))
      tok = tokens[idx];
      if (tok == "-i")
        casematters = 0;
        idx = idx + 1;
        continue;
      elseif (tok == "-s" || tok == "--case-sensitive")
        casematters = 1;
        idx = idx + 1;
        continue;
      elseif (tok == "-r" || tok == "--regex")
        use_regex = 1;
        idx = idx + 1;
        continue;
      elseif (tok == "--owner")
        if (idx == length(tokens))
          player:inform_current($event:mk_error(player, "--owner requires an object reference."));
          return;
        endif
        owner_tok = tokens[idx + 1];
        try
          owner_filter = $match:match_object(owner_tok, player);
        except e (ANY)
          player:inform_current($event:mk_error(player, "Could not resolve owner: " + tostr(e[2])));
          return;
        endtry
        idx = idx + 2;
        continue;
      elseif (tok == "--limit")
        if (idx == length(tokens))
          player:inform_current($event:mk_error(player, "--limit requires a positive integer."));
          return;
        endif
        limit_tok = tokens[idx + 1];
        limit = `toint(limit_tok) ! ANY => 0';
        if (limit <= 0)
          player:inform_current($event:mk_error(player, "--limit requires a positive integer."));
          return;
        endif
        idx = idx + 2;
        continue;
      endif
      break;
    endwhile
    if (idx > length(tokens))
      player:inform_current($event:mk_error(player, "Missing pattern."));
      return;
    endif
    pattern = tokens[idx..$]:join(" "):trim();
    search_objects = this:_do_get_available_objects();
    if (length(tokens[idx..$]) >= 2)
      possible_target = tokens[$];
      try
        target_obj = $match:match_object(possible_target, player);
        pattern = tokens[idx..$ - 1]:join(" "):trim();
        if (!pattern)
          player:inform_current($event:mk_error(player, "Missing pattern before target object."));
          return;
        endif
        search_objects = {target_obj};
      except e (ANY)
        "No explicit target object; treat full remainder as pattern.";
      endtry
    endif
    player:inform_current($event:mk_info(player, "Searching for \"" + pattern + "\" in " + tostr(length(search_objects)) + " objects..."));
    all_matches = {};
    obj_count = 0;
    if (!use_regex)
      for o in (search_objects)
        obj_count = obj_count + 1;
        if (obj_count % 3 == 0)
          suspend_if_needed();
        endif
        matches = this:_do_grep_object(pattern, o, casematters);
        if (owner_filter)
          filtered = {};
          for m in (matches)
            if (toobj(m[4]) == owner_filter)
              filtered = {@filtered, m};
            endif
          endfor
          matches = filtered;
        endif
        all_matches = {@all_matches, @matches};
        if (limit && length(all_matches) >= limit)
          all_matches = all_matches[1..limit];
          break;
        endif
      endfor
    else
      if (!casematters)
        pattern_cmp = pattern:lowercase();
      else
        pattern_cmp = pattern;
      endif
      for o in (search_objects)
        obj_count = obj_count + 1;
        if (obj_count % 2 == 0)
          suspend_if_needed();
        endif
        metadata_list = $prog_utils:get_verbs_metadata(o);
        for md in (metadata_list)
          vname = md:name();
          vowner = md:verb_owner();
          if (owner_filter && vowner != owner_filter)
            continue;
          endif
          lines = `verb_code(o, vname, 1, 1) ! ANY => {}';
          for line_num in [1..length(lines)]
            line = lines[line_num];
            hay = casematters ? line | line:lowercase();
            ok = `match(hay, pattern_cmp) ! ANY => 0';
            if (!ok)
              continue;
            endif
            owner_name = valid(vowner) ? vowner.name | "Recycled";
            all_matches = {@all_matches, {o, vname, owner_name, tostr(vowner), line_num, line}};
            if (limit && length(all_matches) >= limit)
              break;
            endif
          endfor
          if (limit && length(all_matches) >= limit)
            break;
          endif
        endfor
        if (limit && length(all_matches) >= limit)
          break;
        endif
      endfor
    endif
    if (!all_matches)
      elapsed = ftime() - start_time;
      player:inform_current($event:mk_info(player, "No matches found."));
      player:inform_current($event:mk_info(player, tostr("Time: ", elapsed, "s")));
      return;
    endif
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
    result_table = $format.table:mk(headers, rows);
    summary = tostr("Found ", length(all_matches), " match", length(all_matches) != 1 ? "es" | "", " for \"", pattern, "\"");
    if (owner_filter)
      summary = summary + " owner=" + tostr(owner_filter);
    endif
    if (limit)
      summary = summary + " (limit " + tostr(limit) + ")";
    endif
    content = $format.block:mk(summary, result_table);
    elapsed = ftime() - start_time;
    player:inform_current($event:mk_info(player, content));
    player:inform_current($event:mk_info(player, tostr("Time: ", elapsed, "s")));
  endverb

  verb "@codep*aste" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: -- Paste MOO code with syntax highlighting to the room.";
    this:_challenge_command_perms();
    if (!valid(player.location))
      return;
    endif
    content = player:read_multiline("Enter MOO code to paste");
    if (content == "@abort" || typeof(content) != TYPE_STR)
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
    "HINT: <object|builtin> -- Display developer documentation.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@doc OBJECT\n@doc OBJECT:VERB\n@doc OBJECT.PROPERTY\n@doc BUILTIN_FUNCTION")));
      return;
    endif
    target_spec = argstr:trim();
    "Check if this might be a builtin function name";
    if (index(target_spec, ":") == 0 && index(target_spec, ".") == 0 && index(target_spec, "#") == 0 && index(target_spec, "$") == 0)
      try
        func_name = tosym(target_spec);
        doc_lines = function_help(func_name);
        title = "Builtin Function: `" + target_spec + "`";
        doc_text = doc_lines:join("\n");
        for fn_info in (function_info())
          if (fn_info[1] == target_spec)
            min_args = fn_info[2];
            max_args = fn_info[3];
            sig_info = "Arguments: " + tostr(min_args) + (max_args == -1 ? "+" | (max_args == min_args ? "" | "-" + tostr(max_args)));
            doc_text = sig_info + "\n\n" + doc_text;
            break;
          endif
        endfor
        content = $help_utils:format_documentation_display(title, $format.code:mk(doc_text));
        player:inform_current($event:mk_info(player, content):as_djot():as_inset());
        return;
      except e (E_INVARG)
        "Not a builtin function - continue to object parsing.";
      endtry
    endif
    parsed = $prog_utils:parse_target_spec(target_spec);
    if (!parsed)
      if (!this:suggest_doc_topic('builtin, target_spec))
        player:inform_current($event:mk_error(player, "Invalid format. Use `object`, `object:verb`, `object.property`, or `builtin_function`"):as_djot());
      endif
      return;
    endif
    object_str = parsed['object_str];
    if (parsed['type] == 'object)
      type = 'object;
      item_name = "";
    else
      selectors = parsed['selectors];
      if (length(selectors) != 1)
        player:inform_current($event:mk_error(player, "Use exactly one selector: object:verb or object.property"));
        return;
      endif
      selector = selectors[1];
      type = selector['kind];
      item_name = selector['item_name];
      if (!item_name)
        player:inform_current($event:mk_error(player, "Use object:verb or object.property (selector name required)."));
        return;
      endif
    endif
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      if (!this:suggest_doc_topic('object, target_spec))
        player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      endif
      return;
    endtry
    "Dispatch based on type";
    if (type == 'object)
      obj_display = `target_obj:display_name() ! E_VERBNF => target_obj.name';
      doc_text = $help_utils:get_object_documentation(target_obj);
      title = "Documentation for " + obj_display + " (`" + toliteral(target_obj) + "`)";
      content = $help_utils:format_documentation_display(title, doc_text);
      player:inform_current($event:mk_info(player, content):as_djot():as_inset());
    elseif (type == 'verb)
      verb_location = target_obj:find_verb_definer(item_name);
      if (verb_location == #-1)
        if (!this:suggest_doc_topic('verb, target_spec, target_obj, item_name))
          player:inform_current($event:mk_error(player, "Verb `" + tostr(item_name) + "` not found on `" + tostr(target_obj) + "` or its ancestors."):as_djot());
        endif
        return;
      endif
      verb_obj_display = `verb_location:display_name() ! E_VERBNF => verb_location.name';
      doc_text = $help_utils:extract_verb_documentation(verb_location, item_name);
      title = "Documentation for " + verb_obj_display + " (`" + toliteral(verb_location) + ":" + tostr(item_name) + "`)";
      content = $help_utils:format_documentation_display(title, $format.code:mk(doc_text));
      player:inform_current($event:mk_info(player, content):as_djot():as_inset());
    elseif (type == 'property)
      if (!(item_name in properties(target_obj)))
        if (!this:suggest_doc_topic('property, target_spec, target_obj, item_name))
          player:inform_current($event:mk_error(player, "Property `" + item_name + "` not found on `" + tostr(target_obj) + "`."):as_djot());
        endif
        return;
      endif
      obj_display = `target_obj:display_name() ! E_VERBNF => target_obj.name';
      doc_text = $help_utils:property_documentation(target_obj, item_name);
      title = "Documentation for " + obj_display + " (`" + toliteral(target_obj) + "." + item_name + "`)";
      content = $help_utils:format_documentation_display(title, $format.code:mk(doc_text));
      player:inform_current($event:mk_info(player, content):as_djot():as_inset());
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
        typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
        !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
        "Check verb exists";
        verb_name = this:_do_resolve_verb_name(target_obj, verb_name);
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
        message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
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
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for programmer commands.";
    {for_player, ?topic = ""} = args;
    source = `this.help_source ! ANY => $nothing';
    if (valid(source) && respond_to(source, 'help_topics))
      source_result = `source:help_topics(for_player, topic) ! ANY => 0';
      if (typeof(source_result) != TYPE_INT)
        return source_result;
      endif
    endif
    if (topic != "")
      verb_help = `$help_utils:verb_help_from_hint(this, topic, 'programming) ! ANY => 0';
      typeof(verb_help) != TYPE_INT && return verb_help;
      return 0;
    endif
    return {};
  endverb

  verb _format_eval_result (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format an eval result. Returns {type, content} where type is 'simple or 'deflist.";
    "For simple values, content is a string. For objects, content is a deflist flyweight.";
    {result} = args;
    if (typeof(result) == TYPE_OBJ)
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

  verb suggest_doc_topic (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Suggest @doc targets when lookup fails, using LLM.";
    "Args: failure_type ('object, 'verb, 'property, 'builtin), target_spec, ?target_obj, ?item_name";
    "Returns true if handled (placeholder sent), false if LLM not available.";
    {failure_type, target_spec, ?target_obj = #-1, ?item_name = ""} = args;
    "Check if LLM is available";
    llm_client = $player.suggestions_llm_client;
    if (typeof(llm_client) != TYPE_OBJ || !valid(llm_client))
      return false;
    endif
    "Capture current connection BEFORE forking";
    all_conns = connections();
    if (!all_conns || length(all_conns) == 0)
      return false;
    endif
    current_conn = all_conns[1][1];
    "Get display name for target_obj - find sysref name (e.g. #13 -> '$str_proto')";
    obj_display = target_spec;
    if (valid(target_obj))
      obj_display = tostr(target_obj);
      for prop in (properties(#0))
        val = `#0.(prop) ! ANY => 0';
        if (val == target_obj)
          obj_display = "$" + prop;
          break;
        endif
      endfor
    endif
    "Build error message based on failure type";
    if (failure_type == 'object)
      error_msg = "Could not find object: `" + target_spec + "`";
    elseif (failure_type == 'verb)
      error_msg = "Verb `" + item_name + "` not found on `" + obj_display + "`.";
    elseif (failure_type == 'builtin)
      error_msg = "`" + target_spec + "` is not a recognized builtin function or object.";
    else
      error_msg = "Property `" + item_name + "` not found on `" + obj_display + "`.";
    endif
    "Send immediate placeholder with rewritable event";
    rewrite_id = uuid();
    placeholder = $event:mk_error(player, error_msg + " (Finding suggestions...)"):with_rewritable(rewrite_id, 30, error_msg):with_presentation_hint('processing):with_audience('utility);
    player:inform_current(placeholder);
    "Fork the LLM query so we return immediately";
    fork (0)
      "Build context based on failure type";
      prompt = "You help programmers find documentation in a MOO (text-based virtual world). ";
      prompt = prompt + "A programmer tried '@doc " + target_spec + "' but it failed.\n\n";
      if (failure_type == 'builtin)
        "Builtin function not found - provide list of builtins";
        prompt = prompt + "They tried to look up a builtin function.\n\n";
        prompt = prompt + "AVAILABLE BUILTIN FUNCTIONS:\n";
        builtin_names = {};
        for fn_info in (function_info())
          builtin_names = {@builtin_names, fn_info[1]};
        endfor
        prompt = prompt + builtin_names:join(", ") + "\n\n";
      elseif (failure_type == 'object)
        "Object not found - provide list of sysref objects if they used $ prefix";
        if (target_spec[1] == "$")
          prompt = prompt + "They tried to look up a system object starting with '$'.\n\n";
          prompt = prompt + "AVAILABLE SYSTEM OBJECTS ($name format):\n";
          "Get all properties on #0 that point to valid objects";
          sysrefs = {};
          for prop in (properties(#0))
            val = `#0.(prop) ! ANY => 0';
            if (typeof(val) == TYPE_OBJ && valid(val))
              sysrefs = {@sysrefs, "$" + prop};
            endif
          endfor
          prompt = prompt + sysrefs:join(", ") + "\n\n";
        else
          prompt = prompt + "They tried to look up an object but it wasn't found.\n";
          prompt = prompt + "Suggest they use an object number (#123) or system object ($name).\n";
          prompt = prompt + "They might also have meant a builtin function.\n\n";
          prompt = prompt + "AVAILABLE BUILTIN FUNCTIONS:\n";
          builtin_names = {};
          for fn_info in (function_info())
            builtin_names = {@builtin_names, fn_info[1]};
          endfor
          prompt = prompt + builtin_names:join(", ") + "\n\n";
        endif
      elseif (failure_type == 'verb)
        "Verb not found - provide list of verbs on the object";
        prompt = prompt + "They tried to look up verb '" + item_name + "' on " + obj_display + ".\n\n";
        prompt = prompt + "VERBS ON " + obj_display + ":\n";
        verb_list = `verbs(target_obj) ! ANY => {}';
        if (length(verb_list) > 50)
          verb_list = verb_list[1..50];
          prompt = prompt + verb_list:join(", ") + " ... (and more)\n\n";
        else
          prompt = prompt + verb_list:join(", ") + "\n\n";
        endif
        "Also check ancestors for inherited verbs";
        inherited = {};
        for anc in (`ancestors(target_obj) ! ANY => {}')
          for v in (`verbs(anc) ! ANY => {}')
            if (!(v in verb_list) && !(v in inherited) && length(inherited) < 20)
              inherited = {@inherited, v};
            endif
          endfor
        endfor
        if (length(inherited) > 0)
          prompt = prompt + "INHERITED VERBS (from ancestors):\n";
          prompt = prompt + inherited:join(", ") + "\n\n";
        endif
      else
        "Property not found - provide list of properties on the object";
        prompt = prompt + "They tried to look up property '" + item_name + "' on " + obj_display + ".\n\n";
        prompt = prompt + "PROPERTIES ON " + obj_display + ":\n";
        prop_list = `properties(target_obj) ! ANY => {}';
        if (length(prop_list) > 50)
          prop_list = prop_list[1..50];
          prompt = prompt + prop_list:join(", ") + " ... (and more)\n\n";
        else
          prompt = prompt + prop_list:join(", ") + "\n\n";
        endif
      endif
      prompt = prompt + "INSTRUCTIONS:\n";
      prompt = prompt + "1. Suggest 1-3 likely matches based on what they typed\n";
      if (failure_type == 'verb)
        prompt = prompt + "2. Format suggestions as '@doc " + obj_display + ":VERBNAME'\n";
      elseif (failure_type == 'property)
        prompt = prompt + "2. Format suggestions as '@doc " + obj_display + ".PROPNAME'\n";
      elseif (failure_type == 'builtin)
        prompt = prompt + "2. Format suggestions as '@doc FUNCTION_NAME'\n";
      else
        prompt = prompt + "2. Format suggestions as '@doc <target>'\n";
      endif
      prompt = prompt + "3. Keep response under 60 words\n";
      prompt = prompt + "4. Format for djot (like markdown)\n";
      "Call LLM and rewrite the placeholder";
      try
        response = llm_client:simple_query(prompt);
        if (typeof(response) == TYPE_STR && length(response) > 0)
          result_event = $event:mk_info(player, $format.block:mk(error_msg + "\n", response)):as_djot():as_inset();
          player:rewrite_event(rewrite_id, result_event, current_conn);
        else
          player:rewrite_event(rewrite_id, error_msg, current_conn);
        endif
      except e (ANY)
        player:rewrite_event(rewrite_id, error_msg, current_conn);
      endtry
    endfork
    return true;
  endverb

  verb _do_resolve_verb_name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Resolve space-separated verb names to a single verb name.";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, verb_spec} = args;
    verb_spec = verb_spec:trim();
    if (!verb_spec)
      raise(E_INVARG, "Verb name cannot be blank.");
    endif
    if (!index(verb_spec, " "))
      return verb_spec;
    endif
    "Try each space-separated name and ensure they refer to one verb";
    names = verb_spec:words();
    found_info = 0;
    found_name = "";
    for name in (names)
      info = `verb_info(target_obj, name) ! E_VERBNF => 0';
      if (!info)
        continue;
      endif
      if (!found_info)
        found_info = info;
        found_name = name;
      elseif (info[3] != found_info[3])
        raise(E_INVARG, "Verb name list refers to multiple verbs; use a single name.");
      endif
    endfor
    if (!found_info)
      raise(E_VERBNF, "Verb not found: " + verb_spec);
    endif
    return found_name;
  endverb

  verb "@ps @tasks" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Show active and queued tasks.";
    this:_challenge_command_perms();
    set_task_perms(player);
    active = active_tasks();
    queued = queued_tasks();
    now = time();
    blocks = {};
    "Active tasks section";
    if (length(active) > 0)
      active_rows = {};
      for task in (active)
        {task_id, task_player, start_info} = task;
        if (typeof(start_info) == TYPE_LIST && length(start_info) >= 1)
          task_type = tostr(start_info[1]);
          task_detail = length(start_info) >= 2 ? tostr(start_info[2]) | "";
        else
          task_type = tostr(start_info);
          task_detail = "";
        endif
        active_rows = {@active_rows, {tostr(task_id), tostr(task_player), task_type, task_detail}};
      endfor
      active_table = $format.table:mk({"ID", "Player", "Type", "Start info"}, active_rows);
      blocks = {@blocks, $format.title:mk("Active Tasks", 3), active_table};
    else
      blocks = {@blocks, $format.title:mk("Active Tasks", 3), "(none)"};
    endif
    "Queued/suspended tasks section";
    if (length(queued) > 0)
      queued_rows = {};
      for task in (queued)
        "Format: {task_id, start_time, 0, 0, programmer, verb_loc, verb_name, line, this}";
        task_id = task[1];
        resume_time = task[2];
        programmer = task[5];
        verb_loc = task[6];
        verb_name = task[7];
        line_num = task[8];
        "Calculate time until resume";
        delta = resume_time - now;
        if (delta > 0)
          if (delta < 60)
            time_str = "in " + tostr(delta) + "s";
          elseif (delta < 3600)
            time_str = "in " + tostr(delta / 60) + "m";
          else
            time_str = "in " + tostr(delta / 3600) + "h";
          endif
        elseif (delta == 0)
          time_str = "now";
        else
          time_str = "ready";
        endif
        verb_str = tostr(verb_loc) + ":" + verb_name;
        if (line_num)
          verb_str = verb_str + " (line " + tostr(line_num) + ")";
        endif
        queued_rows = {@queued_rows, {tostr(task_id), tostr(programmer), time_str, verb_str}};
      endfor
      queued_table = $format.table:mk({"ID", "Owner", "Resume", "Verb"}, queued_rows);
      blocks = {@blocks, $format.title:mk("Queued Tasks", 3), queued_table};
    else
      blocks = {@blocks, $format.title:mk("Queued Tasks", 3), "(none)"};
    endif
    summary = tostr(length(active)) + " active, " + tostr(length(queued)) + " queued";
    blocks = {@blocks, "", summary};
    output = $format.block:mk(@blocks);
    player:inform_current($event:mk_info(player, output));
  endverb

  verb "@kill-task @kill" (any any any) owner: ARCH_WIZARD flags: "rd"
    "USAGE: @kill <task-id> -- Kill a task by ID.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: @kill <task-id>"));
      return;
    endif
    task_id = tonum(argstr:trim());
    if (!task_id)
      player:inform_current($event:mk_error(player, "Invalid task ID: " + argstr));
      return;
    endif
    try
      kill_task(task_id);
      player:inform_current($event:mk_info(player, "Killed task " + tostr(task_id) + "."));
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "No such task: " + tostr(task_id)));
    except e (E_PERM)
      player:inform_current($event:mk_error(player, "Permission denied: you don't own task " + tostr(task_id) + "."));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error killing task: " + tostr(e[2])));
    endtry
  endverb

  verb "@chparent" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Change an object's parent.";
    "Usage: @chparent <object> to <new-parent> [--dry-run]";
    caller != player && raise(E_PERM);
    player.programmer || raise(E_PERM, "Programmer features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@chparent <object> to <new-parent> [--dry-run]")));
      return;
    endif
    dry_run = argstr && index(argstr, "--dry-run") != 0;
    new_parent_spec = iobjstr:trim();
    if (dry_run)
      new_parent_spec = new_parent_spec:replace_all(" --dry-run", "");
      new_parent_spec = new_parent_spec:replace_all("--dry-run", "");
      new_parent_spec = new_parent_spec:trim();
    endif
    try
      target = $match:match_object(dobjstr, player);
      typeof(target) != TYPE_OBJ && raise(E_INVARG, "Target is not an object.");
      !valid(target) && raise(E_INVARG, "Target object no longer exists.");
      new_parent = $match:match_object(new_parent_spec, player);
      typeof(new_parent) != TYPE_OBJ && raise(E_INVARG, "New parent is not an object.");
      !valid(new_parent) && raise(E_INVARG, "New parent object no longer exists.");
      old_parent = parent(target);
      old_name = valid(old_parent) ? tostr(old_parent.name, " (", old_parent, ")") | "(none)";
      new_name = tostr(new_parent.name, " (", new_parent, ")");
      if (dry_run)
        player:inform_current($event:mk_info(player, tostr("Dry-run: would change parent of ", target.name, " (", target, ") from ", old_name, " to ", new_name)));
        return target;
      endif
      chparent(target, new_parent);
      message = tostr("Changed parent of ", target.name, " (", target, ") from ", old_name, " to ", new_name);
      player:inform_current($event:mk_info(player, message));
      return target;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb _find_verb_by_argspec (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find a verb matching name and argspec, return its 1-based index or 0.";
    caller == this || raise(E_PERM);
    {target_obj, verb_name, req_dobj, req_prep, req_iobj} = args;
    verb_list = verbs(target_obj);
    for i in [1..length(verb_list)]
      try
        info = verb_info(target_obj, i);
        names = info[3]:split(" ");
        matched = false;
        for n in (names)
          if (n == verb_name)
            matched = true;
            break;
          endif
        endfor
        if (!matched)
          continue;
        endif
        {dobj, prep, iobj} = verb_args(target_obj, i);
        if (dobj == req_dobj && prep == req_prep && iobj == req_iobj)
          return i;
        endif
      except (ANY)
        continue;
      endtry
    endfor
    return 0;
  endverb

  verb "@program @program#" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> [<dobj> <prep> <iobj>] -- Program a verb via line input.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@program OBJECT:VERB [DOBJ PREP IOBJ]\n@program# OBJECT:VERB-NUMBER\n@program OBJECT:VERB = CODE_LINE")));
      return;
    endif
    input = argstr:trim();
    "Inline one-line mode: @program OBJ:VERB = CODE";
    eq_pos = index(input, " = ");
    inline_code = "";
    if (eq_pos)
      inline_code = input[eq_pos + 3..$]:trim();
      input = input[1..eq_pos - 1]:trim();
      if (!inline_code)
        player:inform_current($event:mk_error(player, "Inline mode requires code after '='."));
        return;
      endif
    endif
    "Parse the verb reference";
    words = input:words();
    if (!words)
      player:inform_current($event:mk_error(player, "Invalid format. Use 'object:verb' or 'object:number'."));
      return;
    endif
    parsed = words[1]:parse_verbref();
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid format. Use 'object:verb' or 'object:number'."));
      return;
    endif
    {object_str, verb_spec} = parsed;
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
    "Determine verb descriptor based on which command was used";
    if (verb == "@program#")
      verb_num = `toint(verb_spec) ! ANY => 0';
      if (verb_num < 1)
        player:inform_current($event:mk_error(player, "Invalid verb number: " + verb_spec));
        return;
      endif
      verb_desc = verb_num;
      try
        info = verb_info(target_obj, verb_num);
        display_name = info[3]:split(" ")[1];
      except (E_VERBNF)
        player:inform_current($event:mk_error(player, "No verb #" + tostr(verb_num) + " on " + target_obj.name + "."));
        return;
      except (E_PERM)
        player:inform_current($event:mk_error(player, "Permission denied."));
        return;
      endtry
    elseif (length(words) >= 4)
      req_dobj = words[2];
      req_prep = words[3];
      req_iobj = words[4];
      if (!(req_dobj in {"none", "this", "any"}))
        player:inform_current($event:mk_error(player, "Direct object must be 'none', 'this', or 'any'"));
        return;
      endif
      if (!(req_iobj in {"none", "this", "any"}))
        player:inform_current($event:mk_error(player, "Indirect object must be 'none', 'this', or 'any'"));
        return;
      endif
      if (!$prog_utils:is_valid_prep(req_prep))
        player:inform_current($event:mk_error(player, "Invalid preposition: '" + req_prep + "'. Use 'none', 'any', or a valid preposition."));
        return;
      endif
      verb_desc = this:_find_verb_by_argspec(target_obj, verb_spec, req_dobj, req_prep, req_iobj);
      if (!verb_desc)
        player:inform_current($event:mk_error(player, "No verb '" + verb_spec + "' with args " + req_dobj + " " + req_prep + " " + req_iobj + " on " + target_obj.name + "."));
        return;
      endif
      display_name = verb_spec;
    else
      try
        verb_spec = this:_do_resolve_verb_name(target_obj, verb_spec);
      except (E_VERBNF)
        player:inform_current($event:mk_error(player, "Verb '" + verb_spec + "' not found on " + target_obj.name + "."));
        return;
      endtry
      try
        verb_info(target_obj, verb_spec);
      except (E_VERBNF)
        player:inform_current($event:mk_error(player, "Verb '" + verb_spec + "' not found on " + target_obj.name + "."));
        return;
      endtry
      verb_desc = verb_spec;
      display_name = verb_spec;
    endif
    if (inline_code)
      try
        errors = set_verb_code(target_obj, verb_desc, {inline_code}, 2, 1);
        if (!errors)
          player:inform_current($event:mk_info(player, "1 line programmed."));
        else
          player:inform_current($event:mk_error(player, $format.code:mk(errors:join("\n"))));
        endif
      except e (E_PERM)
        player:inform_current($event:mk_error(player, "Permission denied."));
      except e (ANY)
        player:inform_current($event:mk_error(player, tostr(e[1]) + ": " + tostr(e[2])));
      endtry
      return;
    endif
    "Enter line-reading mode";
    player:inform_current($event:mk_info(player, "Now programming " + tostr(target_obj) + ":" + display_name + ".  Use \".\" to finish, \"@abort\" to cancel."));
    lines = {};
    try
      while (1)
        line = read();
        if (line == ".")
          break;
        elseif (line == "@abort")
          player:inform_current($event:mk_info(player, "Programming aborted."));
          return;
        elseif (length(line) >= 1 && line[1] == ".")
          line = line[2..$];
        endif
        lines = {@lines, line};
      endwhile
    except e (ANY)
      player:inform_current($event:mk_error(player, "Read error: " + tostr(e[2])));
      return;
    endtry
    "Compile and install";
    try
      errors = set_verb_code(target_obj, verb_desc, lines, 2, 1);
      if (!errors)
        count = length(lines);
        player:inform_current($event:mk_info(player, tostr(count) + " line" + (count != 1 ? "s" | "") + " programmed."));
      else
        error_text = errors:join("\n");
        player:inform_current($event:mk_error(player, $format.code:mk(error_text)));
      endif
    except e (E_PERM)
      player:inform_current($event:mk_error(player, "Permission denied."));
    except e (ANY)
      player:inform_current($event:mk_error(player, tostr(e[1]) + ": " + tostr(e[2])));
    endtry
  endverb

  verb "@clear-p*roperty" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<property> -- Clear an overridden inherited property to inherit parent value.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@clear-property OBJECT.PROPERTY")));
      return;
    endif
    spec = argstr:trim();
    parsed = $prog_utils:parse_target_spec(spec);
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Usage: @clear-property OBJECT.PROPERTY"));
      return;
    endif
    selectors = parsed['selectors];
    if (length(selectors) != 1)
      player:inform_current($event:mk_error(player, "Usage: @clear-property OBJECT.PROPERTY"));
      return;
    endif
    selector = selectors[1];
    if (selector['kind] != 'property || !selector['item_name] || selector['inherited])
      player:inform_current($event:mk_error(player, "Use a direct property reference: object.property"));
      return;
    endif
    object_str = parsed['object_str];
    prop_name = selector['item_name];
    try
      target_obj = $match:match_object(object_str, player);
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + tostr(e[2])));
      return;
    endtry
    try
      clear_property(target_obj, prop_name);
      player:inform_current($event:mk_info(player, "Property " + tostr(target_obj) + "." + prop_name + " now inherits from its parent value."));
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, "Property " + tostr(target_obj) + "." + prop_name + " cannot be cleared this way."));
    except e (E_PROPNF)
      player:inform_current($event:mk_error(player, "Property " + prop_name + " not found on " + tostr(target_obj) + "."));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error clearing property: " + tostr(e[2])));
    endtry
  endverb

  verb "@which @where-defined" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>:<verb> -- Show where a verb is defined and its metadata.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@which OBJECT:VERB")));
      return;
    endif
    spec = argstr:trim();
    parsed = $prog_utils:parse_target_spec(spec);
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Usage: @which OBJECT:VERB"));
      return;
    endif
    selectors = parsed['selectors];
    if (length(selectors) != 1)
      player:inform_current($event:mk_error(player, "Usage: @which OBJECT:VERB"));
      return;
    endif
    selector = selectors[1];
    if (selector['kind] != 'verb || !selector['item_name])
      player:inform_current($event:mk_error(player, "Usage: @which OBJECT:VERB"));
      return;
    endif
    object_str = parsed['object_str];
    verb_name = selector['item_name];
    try
      target_obj = this:_resolve_object_ref(object_str, player, "object");
    except e (E_INVARG)
      player:inform_current($event:mk_error(player, tostr(e[2])));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
      return;
    endtry
    try
      resolved = this:_do_resolve_verb_name(target_obj, verb_name);
      definer = target_obj:find_verb_definer(resolved);
      if (definer == #-1)
        player:inform_current($event:mk_error(player, "Verb '" + resolved + "' not found on " + tostr(target_obj) + " or ancestors."));
        return;
      endif
      listing = this:_do_get_verb_listing(definer, resolved, 0);
      {verb_owner, verb_flags, dobj, prep, iobj, code_lines} = listing;
      headers = {"Target", "Resolved", "Defined on", "Owner", "Flags", "Args", "Lines"};
      argspec = dobj + " " + prep + " " + iobj;
      row = {tostr(target_obj), resolved, tostr(definer), tostr(verb_owner), verb_flags, argspec, tostr(length(code_lines))};
      table = $format.table:mk(headers, {row});
      player:inform_current($event:mk_info(player, table));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error resolving verb: " + tostr(e[2])));
    endtry
  endverb

  verb "@mvverb" (any at any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <src-obj>:<verb> to <dest-obj>[:<new-verb>] [--dry-run|--confirm] -- Move a verb.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr || !dobjstr || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@mvverb SRC_OBJ:VERB to DEST_OBJ[:NEW_VERB] --confirm\n@mvverb SRC_OBJ:VERB to DEST_OBJ[:NEW_VERB] --dry-run")));
      return;
    endif
    dry_run = index(argstr, "--dry-run") != 0;
    confirm = index(argstr, "--confirm") != 0;
    if (!dry_run && !confirm)
      player:inform_current($event:mk_error(player, "Refusing to move without confirmation. Add --confirm (or use --dry-run)."));
      return;
    endif
    src_spec = dobjstr:trim();
    dst_spec = iobjstr:trim();
    dst_spec = dst_spec:replace_all(" --dry-run", "");
    dst_spec = dst_spec:replace_all("--dry-run", "");
    dst_spec = dst_spec:replace_all(" --confirm", "");
    dst_spec = dst_spec:replace_all("--confirm", "");
    dst_spec = dst_spec:trim();
    parsed = $prog_utils:parse_target_spec(src_spec);
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Source must be OBJECT:VERB"));
      return;
    endif
    selectors = parsed['selectors];
    if (length(selectors) != 1 || selectors[1]['kind] != 'verb || !selectors[1]['item_name])
      player:inform_current($event:mk_error(player, "Source must be OBJECT:VERB"));
      return;
    endif
    src_obj_str = parsed['object_str];
    src_name = selectors[1]['item_name];
    try
      src_obj = $match:match_object(src_obj_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find source object: " + tostr(e[2])));
      return;
    endtry
    if (":" in dst_spec)
      parsed_dst = dst_spec:parse_verbref();
      if (!parsed_dst)
        player:inform_current($event:mk_error(player, "Destination must be OBJECT or OBJECT:NEW_VERB"));
        return;
      endif
      {dst_obj_str, dst_name} = parsed_dst;
    else
      dst_obj_str = dst_spec;
      dst_name = src_name;
    endif
    try
      src_name = this:_do_resolve_verb_name(src_obj, src_name);
      dst_obj = $match:match_object(dst_obj_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Resolution failed: " + tostr(e[2])));
      return;
    endtry
    if (!dst_name)
      dst_name = src_name;
    endif
    if (dry_run)
      player:inform_current($event:mk_info(player, "Dry-run: would move " + tostr(src_obj) + ":" + src_name + " -> " + tostr(dst_obj) + ":" + dst_name));
      return;
    endif
    existing = `verb_info(dst_obj, dst_name) ! E_VERBNF => 0';
    if (existing)
      player:inform_current($event:mk_error(player, "Destination already has verb: " + tostr(dst_obj) + ":" + dst_name));
      return;
    endif
    src_definer = src_obj:find_verb_definer(src_name);
    if (src_definer == #-1)
      player:inform_current($event:mk_error(player, "Source verb not found: " + src_name));
      return;
    endif
    listing = this:_do_get_verb_listing(src_definer, src_name, 1);
    {src_owner, src_flags, src_dobj, src_prep, src_iobj, src_code} = listing;
    new_owner = player.wizard ? src_owner | player;
    try
      this:_do_add_verb(dst_obj, {new_owner, src_flags, dst_name}, {src_dobj, src_prep, src_iobj});
      compile_errors = set_verb_code(dst_obj, dst_name, src_code, 2, 1);
      if (compile_errors)
        this:_do_delete_verb(dst_obj, dst_name);
        player:inform_current($event:mk_error(player, "Move copy step failed:\n" + compile_errors:join("\n")));
        return;
      endif
      this:_do_delete_verb(src_definer, src_name);
      player:inform_current($event:mk_info(player, "Moved " + tostr(src_obj) + ":" + src_name + " -> " + tostr(dst_obj) + ":" + dst_name));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Move failed: " + tostr(e[2])));
    endtry
  endverb

  verb "@cpverb" (any at any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <src-obj>:<verb> to <dest-obj>[:<new-verb>] -- Copy a verb.";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@cpverb SRC_OBJ:VERB to DEST_OBJ[:NEW_VERB]")));
      return;
    endif
    src_spec = dobjstr:trim();
    dst_spec = iobjstr:trim();
    parsed = $prog_utils:parse_target_spec(src_spec);
    if (!parsed || parsed['type] != 'compound)
      player:inform_current($event:mk_error(player, "Source must be OBJECT:VERB"));
      return;
    endif
    selectors = parsed['selectors];
    if (length(selectors) != 1 || selectors[1]['kind] != 'verb || !selectors[1]['item_name])
      player:inform_current($event:mk_error(player, "Source must be OBJECT:VERB"));
      return;
    endif
    src_obj_str = parsed['object_str];
    src_name = selectors[1]['item_name];
    try
      src_obj = $match:match_object(src_obj_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find source object: " + tostr(e[2])));
      return;
    endtry
    try
      src_name = this:_do_resolve_verb_name(src_obj, src_name);
      src_definer = src_obj:find_verb_definer(src_name);
      if (src_definer == #-1)
        player:inform_current($event:mk_error(player, "Source verb not found: " + src_name));
        return;
      endif
      listing = this:_do_get_verb_listing(src_definer, src_name, 1);
      {src_owner, src_flags, src_dobj, src_prep, src_iobj, src_code} = listing;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error reading source verb: " + tostr(e[2])));
      return;
    endtry
    if (":" in dst_spec)
      parsed_dst = dst_spec:parse_verbref();
      if (!parsed_dst)
        player:inform_current($event:mk_error(player, "Destination must be OBJECT or OBJECT:NEW_VERB"));
        return;
      endif
      {dst_obj_str, dst_name} = parsed_dst;
    else
      dst_obj_str = dst_spec;
      dst_name = src_name;
    endif
    try
      dst_obj = $match:match_object(dst_obj_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find destination object: " + tostr(e[2])));
      return;
    endtry
    if (!dst_name)
      dst_name = src_name;
    endif
    existing = `verb_info(dst_obj, dst_name) ! E_VERBNF => 0';
    if (existing)
      player:inform_current($event:mk_error(player, "Destination already has verb: " + tostr(dst_obj) + ":" + dst_name));
      return;
    endif
    new_owner = player.wizard ? src_owner | player;
    try
      this:_do_add_verb(dst_obj, {new_owner, src_flags, dst_name}, {src_dobj, src_prep, src_iobj});
      compile_errors = set_verb_code(dst_obj, dst_name, src_code, 2, 1);
      if (compile_errors)
        this:_do_delete_verb(dst_obj, dst_name);
        player:inform_current($event:mk_error(player, "Copy failed to compile:\n" + compile_errors:join("\n")));
        return;
      endif
      msg = "Copied " + tostr(src_obj) + ":" + src_name + " -> " + tostr(dst_obj) + ":" + dst_name;
      msg = msg + " (flags " + src_flags + ", args " + src_dobj + " " + src_prep + " " + src_iobj + ")";
      player:inform_current($event:mk_info(player, msg));
    except e (ANY)
      player:inform_current($event:mk_error(player, "Copy failed: " + tostr(e[2])));
    endtry
  endverb

  verb _resolve_object_ref (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper: resolve object references with better ambiguity diagnostics.";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {ref_string, ?context = player, ?label = "object"} = args;
    typeof(ref_string) == TYPE_STR || raise(E_TYPE, "Object reference must be a string.");
    ref = ref_string:trim();
    ref || raise(E_INVARG, "Empty " + label + " reference.");
    if (ref[1] in {"#", "$", "@"} || ref in {"me", "player", "here"})
      return $match:match_object(ref, context);
    endif
    if (!valid(context))
      context = player;
    endif
    scope = {};
    scope = {@scope, @context.contents};
    if (valid(context.location))
      scope = {@scope, @context.location.contents};
    endif
    if (!scope)
      return $match:match_object(ref, context);
    endif
    result = $match:resolve_in_scope(ref, scope, ['fuzzy_threshold -> 0.5]);
    if (result == $failed_match)
      raise(E_INVARG, "No " + label + " found matching '" + ref + "'.");
    endif
    if (result == $ambiguous_match)
      candidates = this:_matching_candidates(ref, context);
      if (!candidates)
        raise(E_INVARG, "Ambiguous " + label + " reference '" + ref + "'.");
      endif
      formatted = {};
      max_show = 8;
      count = 0;
      for o in (candidates)
        count = count + 1;
        if (count > max_show)
          break;
        endif
        formatted = {@formatted, tostr(o.name, " (", o, ")")};
      endfor
      suffix = length(candidates) > max_show ? " ..." | "";
      msg = "Ambiguous " + label + " '" + ref + "'. Candidates: " + formatted:join(", ") + suffix;
      raise(E_INVARG, msg);
    endif
    return result;
  endverb

  verb _matching_candidates (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper: list likely candidate objects for a plain-name token in context.";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {token, ?context = player} = args;
    typeof(token) == TYPE_STR || return {};
    valid(context) || return {};
    needle = token:trim():lowercase();
    !needle && return {};
    scope = {};
    scope = {@scope, @context.contents};
    if (valid(context.location))
      scope = {@scope, @context.location.contents};
    endif
    candidates = {};
    seen = [];
    for o in (scope)
      if (!(o in mapkeys(seen)))
        seen[o] = 1;
      else
        continue;
      endif
      names = {o.name};
      aliases = `o.aliases ! ANY => {}';
      if (typeof(aliases) == TYPE_LIST)
        names = {@names, @aliases};
      endif
      matched = 0;
      for n in (names)
        if (typeof(n) == TYPE_STR)
          lower = n:lowercase();
          if (index(lower, needle) || index(needle, lower))
            matched = 1;
            break;
          endif
        endif
      endfor
      if (matched)
        candidates = {@candidates, o};
      endif
    endfor
    return candidates;
  endverb
endobject