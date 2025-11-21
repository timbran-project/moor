object OBJ_UTILS
  name: "Object Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Core object utilities for introspection and formatting. Provides common functionality for displaying object information, verb signatures, and other object-related utilities.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "obj_utils";

  verb format_verb_signature (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format a verb signature into user-friendly text. Returns a formatted string.";
    "Args: {verb_name, dobj, prep, iobj, ?object_name}";
    "If object_name is provided, uses it for 'this' placeholders. Otherwise uses <something>.";
    set_task_perms(caller_perms());
    {verb_name, dobj, prep, iobj, ?object_name = "<something>"} = args;
    verb_sig = verb_name;
    "Add dobj: use object name for 'this', placeholder for 'any'";
    if (dobj == "any")
      verb_sig = verb_sig + " <anything>";
    elseif (dobj == "this")
      verb_sig = verb_sig + " " + object_name;
    endif
    "Add iobj if there's a preposition: use object name for 'this', placeholder for 'any'";
    if (prep != "none")
      verb_sig = verb_sig + " " + prep;
      if (iobj == "any")
        verb_sig = verb_sig + " <anything>";
      elseif (iobj == "this")
        verb_sig = verb_sig + " " + object_name;
      endif
    endif
    return verb_sig;
  endverb

  verb format_verb_signatures (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format multiple verb signatures from examination data. Returns a list of formatted strings.";
    "Args: {verb_list, ?object_name}";
    "verb_list should be from examination().verbs, where each item is {name, definer, dobj, prep, iobj}";
    set_task_perms(caller_perms());
    {verb_list, ?object_name = "<thing>"} = args;
    typeof(verb_list) != LIST && return {};
    verb_sigs = {};
    for verb_info in (verb_list)
      {verb_name, definer, dobj, prep, iobj} = verb_info;
      sig = this:format_verb_signature(verb_name, dobj, prep, iobj, object_name);
      verb_sigs = {@verb_sigs, sig};
    endfor
    return verb_sigs;
  endverb

  verb is_targetable_verb (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if a verb targets specific objects (has dobj or iobj as 'this').";
    "A targetable verb requires you to specify an object. Ambient verbs do not.";
    "Args: {dobj, prep, iobj}";
    set_task_perms(caller_perms());
    {dobj, prep, iobj} = args;
    "Targetable if either dobj or iobj is 'this'";
    return (dobj == "this" || iobj == "this");
  endverb

  verb collect_targetable_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Collect targetable verbs from a list of objects.";
    "Returns list of maps: {object_ref, object_name, verbs}";
    "Args: {objects_list}";
    set_task_perms(caller_perms());
    {obj_list} = args;
    typeof(obj_list) != LIST && return {};
    result = {};
    seen_objects = [];
    caller_obj = `caller ! E_INVIND => #-1';
    for o in (obj_list)
      if (!valid(o))
        continue;
      endif
      "Skip the player themselves";
      if (o == caller_obj)
        continue;
      endif
      "Skip if we've already processed this object";
      if (maphaskey(seen_objects, tostr(o)))
        continue;
      endif
      seen_objects[tostr(o)] = true;
      "Get examination data";
      exam = `o:examination() ! ANY => false';
      if (typeof(exam) != FLYWEIGHT || !exam.verbs)
        continue;
      endif
      "Filter for targetable verbs only";
      targetable_sigs = {};
      for verb_info in (exam.verbs)
        {verb_name, definer, dobj, prep, iobj} = verb_info;
        if (this:is_targetable_verb(dobj, prep, iobj))
          sig = this:format_verb_signature(verb_name, dobj, prep, iobj, exam.name);
          targetable_sigs = {@targetable_sigs, sig};
        endif
      endfor
      if (targetable_sigs && length(targetable_sigs) > 0)
        entry = ["object" -> tostr(o), "object_name" -> exam.name, "verbs" -> targetable_sigs];
        result = listappend(result, entry);
      endif
    endfor
    return result;
  endverb

  verb collect_ambient_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Collect ambient verbs from a list of objects.";
    "Ambient verbs don't target specific objects. Returns list of maps: {verb, from_object, from_name}";
    "Args: {objects_list}";
    set_task_perms(caller_perms());
    {obj_list} = args;
    typeof(obj_list) != LIST && return {};
    result = {};
    seen = [];
    for o in (obj_list)
      if (!valid(o))
        continue;
      endif
      "Get object display name for tracking source";
      obj_name = `o:display_name() ! ANY => tostr(o)';
      "Walk inheritance chain to collect all verbs";
      ancestor_chain = `ancestors(o) ! ANY => {}';
      for definer in ({o, @ancestor_chain})
        if (!valid(definer))
          continue;
        endif
        "Get verbs defined at this level";
        all_verbs = `verbs(definer) ! ANY => {}';
        for verb_name in (all_verbs)
          "Get verb signature";
          verb_sig = `verb_args(definer, verb_name) ! ANY => false';
          if (typeof(verb_sig) != LIST || length(verb_sig) < 3)
            continue;
          endif
          {dobj, prep, iobj} = verb_sig;
          "Include ambient verbs (those that don't require 'this' as dobj/iobj)";
          if (!this:is_targetable_verb(dobj, prep, iobj))
            "Skip if we've already seen this verb";
            if (!maphaskey(seen, verb_name))
              seen[verb_name] = true;
              entry = ["verb" -> verb_name, "from_object" -> o, "from_name" -> obj_name];
              result = listappend(result, entry);
            endif
          endif
        endfor
      endfor
    endfor
    return result;
  endverb

  verb validate_and_compile_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Compile a template string into a $sub flyweight list. Returns {success, result}.";
    "If success is true, result is the compiled list.";
    "If success is false, result is the error message.";
    {template_string} = args;
    typeof(template_string) != STR && raise(E_TYPE, "template_string must be string");
    try
      compiled = $sub_utils:compile(template_string);
      return {true, compiled};
    except e (ANY)
      error_msg = length(e) > 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      return {false, error_msg};
    endtry
  endverb

  verb check_message_property_writable (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if a player can write to a message property on an object.";
    "Returns {writable, error_msg} where writable is true/false.";
    {target_obj, prop_name, player} = args;
    typeof(target_obj) != OBJ && raise(E_TYPE, "target_obj must be object");
    typeof(prop_name) != STR && raise(E_TYPE, "prop_name must be string");
    typeof(player) != OBJ && raise(E_TYPE, "player must be object");
    "Check property exists";
    if (!(prop_name in target_obj:all_properties()))
      return {false, "Property '" + prop_name + "' does not exist on " + tostr(target_obj) + "."};
    endif
    "Get property metadata to check permissions";
    try
      metadata = $prog_utils:get_property_metadata(target_obj, prop_name);
      owner = metadata:owner();
      perms = metadata:perms();
      "Check if player owns it or is wizard";
      if (player.wizard || owner == player)
        "Check if w permission is set";
        if (index(perms, "w"))
          return {true, ""};
        else
          return {false, "Property '" + prop_name + "' is not writable."};
        endif
      else
        return {false, "You do not have permission to modify property '" + prop_name + "' on " + tostr(target_obj) + "."};
      endif
    except e (ANY)
      return {false, "Error checking property: " + toliteral(e)};
    endtry
  endverb

  verb set_compiled_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set a compiled message property with elevated permissions.";
    "Args: {target_obj, prop_name, compiled_list, player}";
    {target_obj, prop_name, compiled_list, player} = args;
    set_task_perms(player);
    target_obj.(prop_name) = compiled_list;
  endverb

  verb message_properties (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return list of readable message properties (ending with _msg) on an object.";
    "Args: {target_obj}";
    "Returns: list of {property_name, current_value}";
    set_task_perms(caller_perms());
    {target_obj} = args;
    !valid(target_obj) && return {};
    result = {};
    all_props = target_obj:all_properties();
    typeof(all_props) != LIST && return {};
    for prop_name in (all_props)
      "Check if property ends with _msg";
      if (prop_name:ends_with("_msg"))
        prop_value = target_obj.(prop_name);
        result = {@result, {prop_name, prop_value}};
      endif
    endfor
    return result;
  endverb

endobject