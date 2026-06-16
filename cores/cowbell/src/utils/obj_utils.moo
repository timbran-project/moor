object OBJ_UTILS
  name: "Object Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Core object utilities for introspection and formatting. Provides common functionality for displaying object information, verb signatures, and other object-related utilities.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "obj_utils";

  method format_verb_signature owner: ARCH_WIZARD
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
  endmethod

  method format_verb_signatures owner: ARCH_WIZARD
    "Format multiple verb signatures from examination data. Returns a list of formatted strings.";
    "Args: {verb_list, ?object_name}";
    "verb_list should be from examination().verbs, where each item is {name, definer, dobj, prep, iobj}";
    set_task_perms(caller_perms());
    {verb_list, ?object_name = "<thing>"} = args;
    typeof(verb_list) != TYPE_LIST && return {};
    verb_sigs = {};
    for verb_info in (verb_list)
      {verb_name, definer, dobj, prep, iobj} = verb_info;
      sig = this:format_verb_signature(verb_name, dobj, prep, iobj, object_name);
      verb_sigs = {@verb_sigs, sig};
    endfor
    return verb_sigs;
  endmethod

  method is_targetable_verb owner: ARCH_WIZARD
    "Check if a verb targets specific objects (has dobj or iobj as 'this').";
    "A targetable verb requires you to specify an object. Ambient verbs do not.";
    "Args: {dobj, prep, iobj}";
    set_task_perms(caller_perms());
    {dobj, prep, iobj} = args;
    "Targetable if either dobj or iobj is 'this'";
    return dobj == "this" || iobj == "this";
  endmethod

  method collect_targetable_verbs owner: ARCH_WIZARD
    "Best-effort scanner for targetable verbs used by help and command suggestions.";
    "Returns list of maps: {object_ref, object_name, verbs}";
    "Args: {objects_list}";
    "Do not use this for authoritative command, permission, or metadata decisions; use strict metadata helpers instead.";
    set_task_perms(caller_perms());
    {obj_list} = args;
    typeof(obj_list) != TYPE_LIST && return {};
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
      exam = o:examination();
      if (typeof(exam) != TYPE_FLYWEIGHT || !exam.verbs)
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
  endmethod

  method collect_ambient_verbs owner: ARCH_WIZARD
    "Best-effort scanner for ambient verbs used by help and command suggestions.";
    "Ambient verbs don't target specific objects. Returns list of maps: {verb, from_object, from_name}";
    "Args: {objects_list}";
    "Do not use this for authoritative command, permission, or metadata decisions; use strict metadata helpers instead.";
    set_task_perms(caller_perms());
    {obj_list} = args;
    typeof(obj_list) != TYPE_LIST && return {};
    result = {};
    seen = [];
    for o in (obj_list)
      if (!valid(o))
        continue;
      endif
      "Get object display name for tracking source";
      obj_name = `o:display_name() ! ANY => tostr(o)';
      "Walk inheritance chain to collect all verbs";
      ancestor_chain = ancestors(o);
      for definer in ({o, @ancestor_chain})
        if (!valid(definer))
          continue;
        endif
        "Get verbs defined at this level";
        all_verbs = `verbs(definer) ! ANY => {}';
        for verb_name in (all_verbs)
          "Get verb signature";
          verb_sig = `verb_args(definer, verb_name) ! ANY => {}';
          if (typeof(verb_sig) != TYPE_LIST || length(verb_sig) < 3)
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
  endmethod

  method validate_and_compile_template owner: ARCH_WIZARD
    "Compile a template string into a $sub flyweight list. Returns {success, result}.";
    "If success is true, result is the compiled list.";
    "If success is false, result is the error message.";
    {template_string} = args;
    typeof(template_string) != TYPE_STR && raise(E_TYPE, "template_string must be string");
    try
      compiled = $sub_utils:compile(template_string);
      return {true, compiled};
    except e (ANY)
      error_msg = length(e) > 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      return {false, error_msg};
    endtry
  endmethod

  method check_message_property_writable owner: ARCH_WIZARD
    "Check if a player can write to a message property on an object.";
    "Returns {writable, error_msg} where writable is true/false.";
    caller == $builder_features || raise(E_PERM);
    {target_obj, prop_name, who} = args;
    typeof(target_obj) != TYPE_OBJ && raise(E_TYPE, "target_obj must be object");
    typeof(prop_name) != TYPE_STR && raise(E_TYPE, "prop_name must be string");
    typeof(who) != TYPE_OBJ && raise(E_TYPE, "who must be object");
    set_task_perms(who);
    "Check property exists";
    prop_key = this:property_key(target_obj, prop_name);
    if (prop_key == E_PROPNF)
      return {false, "Property '" + prop_name + "' does not exist on " + tostr(target_obj) + "."};
    endif
    "Try to write with player's permissions to check if allowed";
    try
      old_value = target_obj.(prop_key);
      target_obj.(prop_key) = old_value;
      return {true, ""};
    except e (E_PERM)
      return {false, "You do not have permission to modify property '" + prop_name + "' on " + tostr(target_obj) + "."};
    except e (ANY)
      return {false, "Error checking property: " + toliteral(e)};
    endtry
  endmethod

  method set_compiled_message owner: ARCH_WIZARD
    "Set a compiled message property with elevated permissions.";
    "Args: {target_obj, prop_name, compiled_list, who}";
    (caller == $builder_features || isa(caller, $llm_wearable)) || raise(E_PERM);
    {target_obj, prop_name, compiled_list, who, ?grants = {}} = args;
    prop_key = this:property_key(target_obj, tostr(prop_name));
    prop_key == E_PROPNF && raise(E_PROPNF, "Property not found: " + tostr(prop_name));
    existing = target_obj.(prop_key);
    if (typeof(existing) == TYPE_OBJ && isa(existing, $msg_bag))
      set_task_perms(who, {@grants, {"property_write", existing, "entries"}});
      existing.entries = {compiled_list};
    elseif (typeof(existing) == TYPE_FLYWEIGHT && existing.delegate == $msg_bag)
      set_task_perms(who, {@grants, {"property_write", target_obj, prop_key}});
      target_obj.(prop_key) = $msg_bag:mk(compiled_list);
    else
      set_task_perms(who, {@grants, {"property_write", target_obj, prop_key}});
      target_obj.(prop_key) = compiled_list;
    endif
  endmethod

  method add_message_entry owner: ARCH_WIZARD
    "Append a compiled entry to a message bag property, creating the bag if needed.";
    (caller == $builder_features || isa(caller, $llm_wearable)) || raise(E_PERM);
    {target_obj, prop_name, compiled_entry, who} = args;
    prop_name = tostr(prop_name);
    prop_key = this:property_key(target_obj, prop_name);
    if (prop_key == E_PROPNF)
      set_task_perms(who, {{"property_define", target_obj}});
      add_property(target_obj, prop_name, $msg_bag:mk(compiled_entry), {who, "rc"});
      return;
    endif
    existing = target_obj.(prop_key);
    if ($msg_bag:is_msg_bag(existing))
      if (typeof(existing) == TYPE_OBJ)
        set_task_perms(who, {{"property_write", existing, "entries"}});
        existing:add(compiled_entry, true);
      else
        set_task_perms(who, {{"property_write", target_obj, prop_key}});
        target_obj.(prop_key) = existing:add(compiled_entry, true);
      endif
    else
      set_task_perms(who, {{"property_write", target_obj, prop_key}});
      target_obj.(prop_key) = $msg_bag:mk(compiled_entry);
    endif
  endmethod

  method remove_message_entry owner: ARCH_WIZARD
    "Remove an entry from a message bag property.";
    (caller == $builder_features || isa(caller, $llm_wearable)) || raise(E_PERM);
    {target_obj, prop_name, index, who} = args;
    prop_name = tostr(prop_name);
    prop_key = this:property_key(target_obj, prop_name);
    prop_key == E_PROPNF && raise(E_INVARG, "Message bag not found on " + tostr(target_obj) + "." + prop_name);
    existing = target_obj.(prop_key);
    if ($msg_bag:is_msg_bag(existing))
      if (typeof(existing) == TYPE_OBJ)
        set_task_perms(who, {{"property_write", existing, "entries"}});
        existing:remove(index, true);
      else
        set_task_perms(who, {{"property_write", target_obj, prop_key}});
        target_obj.(prop_key) = existing:remove(index, true);
      endif
    else
      raise(E_INVARG, "Message bag not found on " + tostr(target_obj) + "." + prop_name);
    endif
  endmethod

  method property_key owner: ARCH_WIZARD
    "Return the real property key matching a string property name, or E_PROPNF.";
    {target_obj, prop_name} = args;
    typeof(target_obj) != TYPE_OBJ && raise(E_TYPE, "target_obj must be object");
    typeof(prop_name) != TYPE_STR && raise(E_TYPE, "prop_name must be string");
    for existing_prop in (target_obj:all_properties())
      if (tostr(existing_prop) == prop_name)
        return existing_prop;
      endif
    endfor
    return E_PROPNF;
  endmethod

  method message_properties owner: ARCH_WIZARD
    "Return list of readable message properties (ending with _msg/_msgs/_msg_bag) on an object.";
    "Args: {target_obj, ?who, ?grant_reads}";
    "Returns: list of {property_name, current_value}";
    {target_obj, ?who = caller_perms(), ?grant_reads = false} = args;
    if (!grant_reads)
      set_task_perms(who);
    endif
    !valid(target_obj) && return {};
    result = {};
    msg_props = {};
    all_props = target_obj:all_properties();
    typeof(all_props) != TYPE_LIST && return {};
    for prop_name in (all_props)
      prop_text = tostr(prop_name);
      if (prop_text:ends_with("_msg") || prop_text:ends_with("_msgs") || prop_text:ends_with("_msg_bag"))
        msg_props = {@msg_props, prop_name};
      endif
    endfor
    if (grant_reads)
      grants = {};
      for prop_name in (msg_props)
        grants = {@grants, {"property_read", target_obj, prop_name}};
      endfor
      set_task_perms(who, grants);
    endif
    for prop_name in (msg_props)
      prop_value = target_obj.(prop_name);
      result = {@result, {prop_name, prop_value}};
    endfor
    return result;
  endmethod

  method rule_properties owner: ARCH_WIZARD
    "Return list of readable rule properties (ending with _rule) on an object.";
    "Args: {target_obj, ?who, ?grant_reads}";
    "Returns: list of {property_name, current_value}";
    {target_obj, ?who = caller_perms(), ?grant_reads = false} = args;
    if (!grant_reads)
      set_task_perms(who);
    endif
    !valid(target_obj) && return {};
    result = {};
    rule_props = {};
    all_props = target_obj:all_properties();
    typeof(all_props) != TYPE_LIST && return {};
    for prop_name in (all_props)
      if (tostr(prop_name):ends_with("_rule"))
        rule_props = {@rule_props, prop_name};
      endif
    endfor
    if (grant_reads)
      grants = {};
      for prop_name in (rule_props)
        grants = {@grants, {"property_read", target_obj, prop_name}};
      endfor
      set_task_perms(who, grants);
    endif
    for prop_name in (rule_props)
      prop_value = target_obj.(prop_name);
      result = {@result, {prop_name, prop_value}};
    endfor
    return result;
  endmethod

  method reaction_properties owner: ARCH_WIZARD
    "Return list of reaction properties (ending with _reaction) on an object.";
    "Args: {target_obj, ?who, ?grant_reads}";
    "Returns: list of {property_name, reaction_flyweight}";
    {target_obj, ?who = caller_perms(), ?grant_reads = false} = args;
    if (!grant_reads)
      set_task_perms(who);
    endif
    !valid(target_obj) && return {};
    result = {};
    reaction_props = {};
    all_props = target_obj:all_properties();
    typeof(all_props) != TYPE_LIST && return {};
    for prop_name in (all_props)
      if (tostr(prop_name):ends_with("_reaction"))
        reaction_props = {@reaction_props, prop_name};
      endif
    endfor
    if (grant_reads)
      grants = {};
      for prop_name in (reaction_props)
        grants = {@grants, {"property_read", target_obj, prop_name}};
      endfor
      set_task_perms(who, grants);
    endif
    for prop_name in (reaction_props)
      prop_value = target_obj.(prop_name);
      "Only include if it's actually a reaction flyweight";
      if (typeof(prop_value) == TYPE_FLYWEIGHT && prop_value.delegate == $reaction)
        result = {@result, {prop_name, prop_value}};
      endif
    endfor
    return result;
  endmethod
endobject
