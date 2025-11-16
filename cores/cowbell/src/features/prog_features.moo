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

  verb _do_grep_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns {line_number, truncated_line} or 0 if no match";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {pattern, object, vname, casematters} = args;
    "Try to get verb code - may fail due to permissions or non-existent verb";
    vc = `verb_code(object, vname) ! ANY';
    if (typeof(vc) == ERR)
      return 0;
    endif
    "Quick check: does pattern exist anywhere in the verb code?";
    "This optimization from LambdaCore is much faster than checking line by line";
    suspend_if_needed();
    if (!index(tostr(@vc), pattern, casematters))
      return 0;
    endif
    suspend_if_needed();
    "Pattern exists somewhere, find which line";
    line_count = 0;
    for line in (vc)
      line_count = line_count + 1;
      if (line_count % 10 == 0)
        suspend_if_needed();
      endif
      if (match_pos = index(line, pattern, casematters))
        "Found the pattern - truncate and center around it";
        max_len = 50;
        line_len = length(line);
        if (line_len <= max_len)
          return {line_count, line};
        endif
        "Calculate window centered on the match";
        pattern_len = length(pattern);
        "Try to center the pattern in the window";
        start_pos = max(1, match_pos - (max_len - pattern_len) / 2);
        end_pos = min(line_len, start_pos + max_len - 1);
        "Adjust start if end hit the limit";
        if (end_pos == line_len && end_pos - start_pos < max_len - 1)
          start_pos = max(1, end_pos - max_len + 1);
        endif
        truncated = line[start_pos..end_pos];
        "Add ellipsis indicators";
        if (start_pos > 1)
          truncated = "..." + truncated;
        endif
        if (end_pos < line_len)
          truncated = truncated + "...";
        endif
        return {line_count, truncated};
      endif
    endfor
    return 0;
  endverb

  verb _do_grep_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to search all verbs on an object with elevated permissions";
    "Returns list of matches: {{obj, verb_name, owner_name, owner_id, line_num, matching_line}, ...}";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {pattern, search_obj, casematters} = args;
    if (!valid(search_obj))
      return {};
    endif
    matches = {};
    verb_count = 0;
    "Get all verbs on this object";
    verb_list = `verbs(search_obj) ! ANY => {}';
    if (typeof(verb_list) != LIST)
      return {};
    endif
    "Search each verb";
    for vnum in [1..length(verb_list)]
      verb_count = verb_count + 1;
      if (verb_count % 5 == 0)
        suspend_if_needed();
      endif
      verb_name = verb_list[vnum];
      match_result = this:_do_grep_verb_code(pattern, search_obj, vnum, casematters);
      if (typeof(match_result) == LIST)
        "Found a match - get verb metadata";
        {line_num, matching_line} = match_result;
        verb_info_data = `verb_info(search_obj, vnum) ! ANY';
        if (typeof(verb_info_data) == LIST)
          {verb_owner, verb_flags, verb_names} = verb_info_data;
          owner_name = valid(verb_owner) ? verb_owner.name | "Recycled";
          "Add to matches list";
          matches = {@matches, {search_obj, verb_name, owner_name, tostr(verb_owner), line_num, matching_line}};
        endif
      endif
    endfor
    return matches;
  endverb

  verb "@grep" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Search verb code across objects for a text pattern";
    "Usage: @grep <pattern> [object]";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <pattern> [object]"));
      return;
    endif
    "Parse arguments: pattern and optional object";
    words = argstr:words();
    if (!words)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <pattern> [object]"));
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
      "No target specified - search all objects using objects() builtin";
      search_objects = objects();
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
    "Paste MOO code with syntax highlighting to the room";
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
    event = $event:mk_paste(player, title, code):with_presentation_hint('inset);
    player.location:announce(event);
  endverb
endobject