object PROG
  name: "Generic Programmer"
  parent: BUILDER
  location: FIRST_ROOM
  owner: WIZ
  wizard: true
  programmer: true
  fertile: true
  readable: true

  verb eval (any any any) owner: ARCH_WIZARD flags: "rxd"
    if (player != caller)
      raise(E_PERMS);
    endif
    set_task_perms(player);
    answer = eval("return " + argstr + ";");
    if (answer[1])
      result_event = $event:mk_eval_result(player, "=> ", toliteral(answer[2]));
    else
      result_event = $event:mk_eval_error(player, $block:mk(@answer[2]));
    endif
    player:tell(result_event);
  endverb

  verb "@edit" (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Edit a verb on an object using the presentation system.";
    "Usage: @edit <object>:<verb> [info]";
    "Examples: @edit #1:look_self, @edit player:tell, @edit $match:match_object info";
    if (player != caller)
      raise(E_PERMS);
    endif
    set_task_perms(player);
    "Check for usage errors";
    if (!argstr)
      player:tell($event:mk_error(player, "Usage: " + verb + " <object>:<verb> [info]"));
      return;
    endif
    "Parse arguments - check for 'info' mode";
    args_list = argstr:split(" ");
    verbref_string = args_list[1];
    "Parse the verb reference";
    parsed = verbref_string:parse_verbref();
    if (!parsed)
      player:tell($event:mk_error(player, "Invalid verb reference format. Use 'object:verb'"));
      return;
    endif
    {object_str, verb_name} = parsed;
    "Match the object";
    target_obj = $match:match_object(object_str, player);
    if (typeof(target_obj) == ERR)
      if (target_obj == E_INVARG("No object found matching '" + object_str + "'"))
        player:tell($event:mk_error(player, "I don't see '" + object_str + "' here."));
      else
        player:tell($event:mk_error(player, "Error matching object: " + tostr(target_obj)));
      endif
      return;
    endif
    "Find and retrieve the verb code";
    try
      "Find where the verb is actually defined";
      verb_location = target_obj:find_verb_definer(verb_name);
      if (verb_location == #-1)
        player:tell($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + " or its ancestors."));
        return;
      endif
      "Get verb information for editor";
      verb_info_data = verb_info(verb_location, verb_name);
      {verb_owner, verb_flags, verb_names} = verb_info_data;
      "Open the editor";
      player:present_editor(verb_location, verb_name);
      player:tell($event:mk_info(player, "Opened verb editor for " + tostr(target_obj) + ":" + tostr(verb_name)));
    except (E_VERBNF)
      player:tell($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + "."));
      return;
    endtry
  endverb

  verb present_editor (this none this) owner: ARCH_WIZARD flags: "rxd"
    if (caller != this)
      raise(E_PERM);
    endif
    {verb_location, verb_name} = args;
    editor_id = "edit-" + tostr(verb_location) + "-" + verb_name;
    editor_title = "Edit " + verb_name + " on " + tostr(verb_location);
    obj_str = tostr(verb_location);
    if (obj_str[1] == "#")
      object_curie = "oid:" + obj_str[2..$];
    elseif (obj_str[1] == "$")
      object_curie = "sysobj:" + obj_str[2..$];
    else
      object_curie = obj_str;
    endif
    present(player, editor_id, "text/plain", "verb-editor", "", {{"object", object_curie}, {"verb", verb_name}, {"title", editor_title}});
  endverb
endobject