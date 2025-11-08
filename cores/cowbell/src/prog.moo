object PROG
  name: "Generic Programmer"
  parent: BUILDER
  location: FIRST_ROOM
  owner: WIZ
  wizard: true
  programmer: true
  readable: true

  override description = "Generic programmer character prototype with code evaluation and editing capabilities.";
  override import_export_id = "prog";

  verb eval (any any any) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    set_task_perms(player);
    answer = eval("return " + argstr + ";", 1, 2);
    if (answer[1])
      result_event = $event:mk_eval_result(player, "=> ", $format.code:mk(toliteral(answer[2]), 'moo));
    else
      error_content = answer[2];
      error_text = error_content:join("\n");
      result_event = $event:mk_eval_error(player, $format.code:mk(error_text));
    endif
    player:inform_current(result_event);
  endverb

  verb "@edit" (any any any) owner: HACKER flags: "rd"
    "Edit a verb on an object using the presentation system.";
    "Usage: @edit <object>:<verb> [info]";
    "Examples: @edit #1:look_self, @edit player:tell, @edit $match:match_object info";
    "Check for usage errors";
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>:<verb> [info]"));
      return;
    endif
    "Parse arguments - check for 'info' mode";
    args_list = argstr:split(" ");
    verbref_string = args_list[1];
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
      "Get verb information for editor";
      verb_info_data = verb_info(verb_location, verb_name);
      {verb_owner, verb_flags, verb_names} = verb_info_data;
      "Open the editor";
      player:present_editor(verb_location, verb_name);
      player:inform_current($event:mk_info(player, "Opened verb editor for " + tostr(target_obj) + ":" + tostr(verb_name)));
    except (E_VERBNF)
      player:inform_current($event:mk_error(player, "Verb '" + tostr(verb_name) + "' not found on " + target_obj.name + "."));
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