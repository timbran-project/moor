object PROG_FEATURES
  name: "Programmer Features"
  parent: BUILDER_FEATURES
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Provides programming verbs (@edit, @list, @verb, etc.) for programmers. Inherits from and extends builder features.";
  override import_export_id = "prog_features";

  verb eval (any any any) owner: ARCH_WIZARD flags: "rd"
    this:_challenge_command_perms();
    set_task_perms(player);
    answer = eval("return " + argstr + ";", 1, 2);
    if (answer[1])
      prefix = "=> ";
      code = $format.code:mk(toliteral(answer[2]), 'moo);
      content = $format.block:mk(prefix, code);
      result_event = $event:mk_eval_result(player, content);
    else
      error_content = answer[2];
      error_text = error_content:join("\n");
      result_event = $event:mk_eval_error(player, $format.code:mk(error_text));
    endif
    player:inform_current(result_event);
  endverb

  verb _do_check_verb_exists (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to check verb exists with elevated permissions";
    caller == this || raise(E_PERM);
    {verb_location, verb_name} = args;
    "This will raise E_VERBNF if verb doesn't exist";
    verb_info_data = verb_info(verb_location, verb_name);
    return true;
  endverb

  verb "@edit" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Edit a verb or property on an object using the presentation system.";
    "Usage: @edit <object>:<verb> or @edit <object>.<property>";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>:<verb> or <object>.<property>"));
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

  verb present_verb_editor (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    {verb_location, verb_name} = args;
    editor_id = "edit-" + tostr(verb_location) + "-" + verb_name;
    editor_title = "Edit " + verb_name + " on " + tostr(verb_location);
    object_curie = verb_location:to_curie_str();
    present(player, editor_id, "text/plain", "verb-editor", "", {{"object", object_curie}, {"verb", verb_name}, {"title", editor_title}});
  endverb

  verb _do_get_verb_listing (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get verb listing with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {verb_location, verb_name, show_all_parens} = args;
    verb_info_data = verb_info(verb_location, verb_name);
    {verb_owner, verb_flags, verb_names} = verb_info_data;
    verb_args_data = verb_args(verb_location, verb_name);
    {dobj, prep, iobj} = verb_args_data;
    code_lines = verb_code(verb_location, verb_name, show_all_parens, true);
    return {verb_owner, verb_flags, dobj, prep, iobj, code_lines};
  endverb

  verb "@list" (any any any) owner: ARCH_WIZARD flags: "rd"
    this:_challenge_command_perms();
    set_task_perms(player);
    "List verb code with optional formatting options";
    "Usage: @list <object>:<verb> [with parentheses] [without numbers]";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>:<verb> [with parentheses] [without numbers]"));
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
        num_lines = length(code_lines);
        num_width = length(tostr(num_lines));
        numbered_lines = {};
        for i in [1..num_lines]
          line_num_str = tostr(i);
          "Pad line number to align";
          padding = $str_proto:space(num_width - length(line_num_str), " ");
          numbered_lines = {@numbered_lines, padding + line_num_str + ":  " + code_lines[i]};
        endfor
        code_lines = numbered_lines;
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
    this:_challenge_command_perms();
    set_task_perms(player);
    "Add a new verb to an object";
    "Usage: @verb object:verb-name(s) [dobj [prep [iobj [permissions [owner]]]]]";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name(s) [dobj [prep [iobj [permissions [owner]]]]]"));
      return;
    endif
    "Parse the arguments";
    words = argstr:words();
    if (length(words) < 1)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name(s) [dobj [prep [iobj [permissions [owner]]]]]"));
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
    this:_challenge_command_perms();
    set_task_perms(player);
    "Remove a verb from an object";
    "Usage: @rmverb object:verb-name";
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
    this:_challenge_command_perms();
    set_task_perms(player);
    "List all verbs on an object";
    "Usage: @verbs <object>";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>"));
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
    this:_challenge_command_perms();
    set_task_perms(player);
    "List all properties on an object";
    "Usage: @properties <object>";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>"));
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

  verb "@args" (any any any) owner: ARCH_WIZARD flags: "rd"
    this:_challenge_command_perms();
    set_task_perms(player);
    "Change verb argument specifications";
    "Usage: @args object:verb-name dobj [prep [iobj]]";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name dobj [prep [iobj]]"));
      return;
    endif
    "Parse the arguments";
    words = argstr:words();
    if (length(words) < 2)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " object:verb-name dobj [prep [iobj]]"));
      return;
    endif
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
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
      return;
    endtry
    "Get current args";
    {current_dobj, current_prep, current_iobj} = verb_args(target_obj, verb_name);
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

  verb _do_get_property_info (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get property info with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    return property_info(target_obj, prop_name);
  endverb

  verb _do_get_property_value (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to get property value with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    return target_obj.(prop_name);
  endverb

  verb _do_is_clear_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to check if property is clear with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    return is_clear_property(target_obj, prop_name);
  endverb

  verb "@sh*ow @d*isplay" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Display detailed object/property/verb information";
    "Usage: @display <object>[.|,|:|;][property/verb]";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>[.|,|:|;][property/verb]"));
      return;
    endif
    spec = argstr:trim();
    "Parse the display specification";
    display_mode = 'object;
    target_spec = spec;
    item_name = "";
    "Check for property/verb specifiers";
    if ("." in spec)
      parts = spec:split(".");
      target_spec = parts[1];
      item_name = length(parts) > 1 ? parts[2] | "";
      display_mode = item_name ? 'property | 'all_properties;
    elseif ("," in spec)
      parts = spec:split(",");
      target_spec = parts[1];
      item_name = length(parts) > 1 ? parts[2] | "";
      display_mode = item_name ? 'inherited_property | 'all_inherited_properties;
    elseif (":" in spec)
      parts = spec:split(":");
      target_spec = parts[1];
      item_name = length(parts) > 1 ? parts[2] | "";
      display_mode = item_name ? 'verb | 'all_verbs;
    elseif (";" in spec)
      parts = spec:split(";");
      target_spec = parts[1];
      item_name = length(parts) > 1 ? parts[2] | "";
      display_mode = item_name ? 'inherited_verb | 'all_inherited_verbs;
    endif
    "Match the target object";
    target_obj = $match:match_object(target_spec, player);
    "Dispatch based on display mode";
    if (display_mode == 'property)
      this:_display_property(target_obj, item_name);
    elseif (display_mode == 'inherited_property)
      this:_display_inherited_property(target_obj, item_name);
    elseif (display_mode == 'all_properties)
      this:_display_all_properties(target_obj, false);
    elseif (display_mode == 'all_inherited_properties)
      this:_display_all_properties(target_obj, true);
    elseif (display_mode == 'verb)
      this:_display_verb(target_obj, item_name);
    elseif (display_mode == 'inherited_verb)
      this:_display_inherited_verb(target_obj, item_name);
    elseif (display_mode == 'all_verbs)
      this:_display_all_verbs(target_obj, false);
    elseif (display_mode == 'all_inherited_verbs)
      this:_display_all_verbs(target_obj, true);
    else
      this:_display_object(target_obj);
    endif
  endverb

  verb _display_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, prop_name} = args;
    prop_info = this:_do_get_property_info(target_obj, prop_name);
    {owner, perms} = prop_info;
    is_clear = this:_do_is_clear_property(target_obj, prop_name);
    prop_value = is_clear ? "(clear)" | toliteral(this:_do_get_property_value(target_obj, prop_name));
    "Truncate long values";
    if (length(prop_value) > 50)
      prop_value = prop_value[1..47] + "...";
    endif
    headers = {"Property", "Owner", "Flags", "Value"};
    row = {"." + prop_name, tostr(owner), perms, prop_value};
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
    headers = {"Property", "Owner", "Flags", "Value"};
    rows = {};
    if (include_inherited)
      "Collect properties from entire inheritance chain";
      seen = [];
      current = target_obj;
      while (valid(current))
        props = this:_do_get_properties(current);
        for prop_name in (props)
          if (prop_name in seen)
            continue;
          endif
          seen = {@seen, prop_name};
          prop_info = this:_do_get_property_info(current, prop_name);
          {owner, perms} = prop_info;
          is_clear = this:_do_is_clear_property(target_obj, prop_name);
          prop_value = is_clear ? "(clear)" | toliteral(this:_do_get_property_value(target_obj, prop_name));
          if (length(prop_value) > 50)
            prop_value = prop_value[1..47] + "...";
          endif
          definer_prefix = current == target_obj ? "" | tostr(current) + ":";
          rows = {@rows, {definer_prefix + "." + prop_name, tostr(owner), perms, prop_value}};
        endfor
        current = `parent(current) ! ANY => #-1';
      endwhile
    else
      "Just properties on this object";
      props = this:_do_get_properties(target_obj);
      for prop_name in (props)
        prop_info = this:_do_get_property_info(target_obj, prop_name);
        {owner, perms} = prop_info;
        is_clear = this:_do_is_clear_property(target_obj, prop_name);
        prop_value = is_clear ? "(clear)" | toliteral(this:_do_get_property_value(target_obj, prop_name));
        if (length(prop_value) > 50)
          prop_value = prop_value[1..47] + "...";
        endif
        rows = {@rows, {"." + prop_name, tostr(owner), perms, prop_value}};
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
    headers = {"Verb", "Owner", "Flags", "Args"};
    args_spec = dobj + " " + prep + " " + iobj;
    verb_spec = tostr(verb_location) + ":" + verb_name;
    row = {verb_spec, tostr(verb_owner), verb_flags, args_spec};
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
    headers = {"Verb", "Owner", "Flags", "Args"};
    rows = {};
    if (include_inherited)
      "Collect verbs from entire inheritance chain";
      seen = [];
      current = target_obj;
      while (valid(current))
        verb_list = this:_do_get_verbs(current);
        for verb_name in (verb_list)
          if (verb_name in seen)
            continue;
          endif
          seen = {@seen, verb_name};
          verb_info_data = verb_info(current, verb_name);
          {verb_owner, verb_flags, verb_names} = verb_info_data;
          verb_args_data = verb_args(current, verb_name);
          {dobj, prep, iobj} = verb_args_data;
          args_spec = dobj + " " + prep + " " + iobj;
          verb_spec = tostr(current) + ":" + verb_name;
          rows = {@rows, {verb_spec, tostr(verb_owner), verb_flags, args_spec}};
        endfor
        current = `parent(current) ! ANY => #-1';
      endwhile
    else
      "Just verbs on this object";
      verb_list = this:_do_get_verbs(target_obj);
      for verb_name in (verb_list)
        verb_info_data = verb_info(target_obj, verb_name);
        {verb_owner, verb_flags, verb_names} = verb_info_data;
        verb_args_data = verb_args(target_obj, verb_name);
        {dobj, prep, iobj} = verb_args_data;
        args_spec = dobj + " " + prep + " " + iobj;
        verb_spec = tostr(target_obj) + ":" + verb_name;
        rows = {@rows, {verb_spec, tostr(verb_owner), verb_flags, args_spec}};
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
    "Show object header info, then all properties and verbs";
    obj_name = target_obj.name;
    obj_owner = target_obj.owner;
    obj_parent = `parent(target_obj) ! ANY => #-1';
    obj_location = `target_obj.location ! ANY => #-1';
    info_lines = {tostr(target_obj) + " \"" + obj_name + "\"", "Owner: " + tostr(obj_owner), "Parent: " + tostr(obj_parent), "Location: " + tostr(obj_location)};
    info_block = $format.block:mk(@info_lines);
    player:inform_current($event:mk_info(player, info_block));
    "Show properties";
    this:_display_all_properties(target_obj, false);
    "Show verbs";
    this:_display_all_verbs(target_obj, false);
  endverb

  verb _challenge_command_perms (this none this) owner: HACKER flags: "rxd"
    player.programmer || raise(E_PERM);
  endverb
endobject