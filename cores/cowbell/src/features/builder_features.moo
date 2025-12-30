object BUILDER_FEATURES
  name: "Builder Features"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  property direction_opposites (owner: HACKER, flags: "rc") = [
    "d" -> "u",
    "down" -> "up",
    "downstairs" -> "upstairs",
    "e" -> "w",
    "east" -> "west",
    "i" -> "o",
    "in" -> "out",
    "n" -> "s",
    "ne" -> "sw",
    "north" -> "south",
    "northeast" -> "southwest",
    "northwest" -> "southeast",
    "nw" -> "se",
    "o" -> "i",
    "out" -> "in",
    "s" -> "n",
    "se" -> "nw",
    "south" -> "north",
    "southeast" -> "northwest",
    "southwest" -> "northeast",
    "sw" -> "ne",
    "u" -> "d",
    "up" -> "down",
    "upstairs" -> "downstairs",
    "w" -> "e",
    "west" -> "east"
  ];

  override description = "Provides building commands (@create, @build, @dig, etc.) for builders.";
  override import_export_hierarchy = {"features"};
  override import_export_id = "builder_features";

  verb _challenge_command_perms (this none this) owner: HACKER flags: "xd"
    caller == player || raise(E_PERM);
  endverb

  verb "@add-message" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Add a compiled message template entry to a message bag property. Usage: @add-message <object>.<prop> <template>";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (length(args) < 2)
      player:inform_current($event:mk_error(player, "Usage: @add-message <object>.<prop> <template>"):with_audience('utility));
      return;
    endif
    prop_spec = args[1];
    prop_parts = $str_proto:split(prop_spec, ".");
    length(prop_parts) == 2 || raise(E_INVARG, "Property must be in the form object.property");
    target_name = prop_parts[1];
    prop_name = prop_parts[2];
    target = $match:match_object(target_name, player);
    valid(target) || raise(E_INVARG, "Object not found");
    prop_name:ends_with("_msg_bag") || prop_name:ends_with("_msgs") || raise(E_INVARG, "Property must end with _msg_bag or _msgs");
    text = args[2];
    {success, compiled} = $obj_utils:validate_and_compile_template(text);
    if (!success)
      player:inform_current($event:mk_error(player, "Template compilation failed: " + compiled):with_audience('utility));
      return;
    endif
    msg_bag = `target.(prop_name) ! E_PROPNF => #-1';
    if (!valid(msg_bag))
      msg_bag = $msg_bag:create(true);
      target.(prop_name) = msg_bag;
    endif
    msg_bag:add(compiled);
    player:inform_current($event:mk_info(player, "Added message to " + tostr(target) + "." + prop_name):with_audience('utility));
  endverb

  verb "@del-message" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Remove a message entry by index from a message bag property. Usage: @del-message <object>.<prop> <index>";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (length(args) < 2)
      player:inform_current($event:mk_error(player, "Usage: @del-message <object>.<prop> <index>"):with_audience('utility));
      return;
    endif
    prop_spec = args[1];
    idx = toint(args[2]);
    prop_parts = $str_proto:split(prop_spec, ".");
    length(prop_parts) == 2 || raise(E_INVARG, "Property must be in the form object.property");
    target_name = prop_parts[1];
    prop_name = prop_parts[2];
    target = $match:match_object(target_name, player);
    valid(target) || raise(E_INVARG, "Object not found");
    prop_name:ends_with("_msg_bag") || prop_name:ends_with("_msgs") || raise(E_INVARG, "Property must end with _msg_bag or _msgs");
    msg_bag = `target.(prop_name) ! E_PROPNF => #-1';
    valid(msg_bag) || raise(E_INVARG, "Message bag not found on " + tostr(target) + "." + prop_name);
    msg_bag:remove(idx);
    player:inform_current($event:mk_info(player, "Removed message #" + tostr(idx) + " from " + tostr(target) + "." + prop_name):with_audience('utility));
  endverb

  verb "@create" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <parent> named <name> -- Create a new object.";
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "named") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@create PARENT named NAME[:ALIASES]")));
      return;
    endif
    try
      parent_obj = $match:match_object(dobjstr, player);
      typeof(parent_obj) != TYPE_OBJ && raise(E_INVARG, "That parent reference is not an object.");
      !valid(parent_obj) && raise(E_INVARG, "That parent object no longer exists.");
      if (!parent_obj.f && !player.wizard && parent_obj.owner != player)
        raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj) + ".");
      endif
      parsed = $str_proto:parse_name_aliases(iobjstr);
      primary_name = parsed[1];
      alias_list = parsed[2];
      !primary_name && raise(E_INVARG, "Primary object name cannot be blank.");
      new_obj = this:_create_child_object(player, parent_obj, primary_name, alias_list);
      object_id = tostr(new_obj);
      parent_name = `parent_obj.name ! ANY => tostr(parent_obj)';
      parent_id = tostr(parent_obj);
      message = "Created \"" + primary_name + "\" (" + object_id + ") as a child of \"" + parent_name + "\" (" + parent_id + ").";
      if (alias_list)
        alias_str = alias_list:join(", ");
        message = message + " Aliases: " + alias_str + ".";
      endif
      message = message + " It is now in your inventory.";
      player:inform_current($event:mk_info(player, message));
      return new_obj;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb _create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create the child object, apply naming, and move it into the builder's inventory.";
    caller == this || caller.wizard || raise(E_PERM);
    {builder_player, parent_obj, primary_name, alias_list} = args;
    set_task_perms(builder_player);
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, alias_list);
    new_obj:moveto(builder_player);
    return new_obj;
  endverb

  verb "@recycle @destroy" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Destroy an object permanently.";
    player.is_builder || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr)
      raise(E_INVARG, "Usage: @recycle OBJECT");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj) + ".");
      endif
      obj_name = target_obj.name;
      obj_id = tostr(target_obj);
      target_obj:destroy();
      player:inform_current($event:mk_info(player, "Recycled \"" + obj_name + "\" (" + obj_id + ")."));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@grant" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<category>(<caps>) to <player> -- Grant capabilities.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "to") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@grant TARGET.CATEGORY(CAP1,CAP2) to PLAYER")));
      return;
    endif
    try
      "Parse grant specification using $grant_utils";
      {target_obj, category, cap_list} = $grant_utils:parse_grant(dobjstr);
      "Permission check - must be owner or wizard";
      !player.wizard && target_obj.owner != player && raise(E_PERM, "You must be owner or wizard to grant capabilities for " + tostr(target_obj) + ".");
      "Match grantee - use iobj from parser, or fall back to match_object if parser failed";
      if (iobj == $failed_match)
        grantee = $match:match_object(iobjstr, player);
      else
        grantee = iobj;
      endif
      if (typeof(grantee) != TYPE_OBJ)
        raise(E_INVARG, "Grantee must be an object.");
      endif
      if (grantee == #-1 || grantee == #-2 || grantee == #-3)
        raise(E_INVARG, "Could not find player");
      endif
      if (!valid(grantee))
        raise(E_INVARG, "Grantee no longer exists.");
      endif
      "Grant the capability";
      cap = $root:grant_capability(target_obj, cap_list, grantee, category);
      "Report success using formatted grant spec";
      grant_display = $grant_utils:format_grant_with_name(target_obj, category, cap_list);
      grantee_str = grantee:name() + " (" + tostr(grantee) + ")";
      message = "Granted " + grant_display + " to " + grantee_str + ".";
      player:inform_current($event:mk_info(player, message));
      return cap;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@audit @owned" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: [<player>] -- Show objects owned by a player.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    try
      "Determine which player to audit";
      if (dobjstr)
        target = $match:match_object(dobjstr, player);
        typeof(target) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
        !valid(target) && raise(E_INVARG, "That object no longer exists.");
      else
        target = player;
      endif
      "Get owned objects";
      owned = sort(owned_objects(target));
      if (!owned)
        target_name = `target.name ! ANY => tostr(target)';
        message = target == player ? "You don't own any objects." | target_name + " doesn't own any objects.";
        player:inform_current($event:mk_info(player, message));
        return 0;
      endif
      "Build header";
      target_name = `target.name ! ANY => tostr(target)';
      min_id = owned[1];
      max_id = owned[length(owned)];
      header = "Objects owned by " + target_name + " (from " + tostr(min_id) + " to " + tostr(max_id) + "):";
      "Build table rows";
      headers = {"Name", "Object", "Location", "Size"};
      rows = {};
      total_bytes = 0;
      total_known = 0;
      for o in (owned)
        "Get object size if available";
        obj_bytes = `o:estimated_size_bytes() ! ANY => false';
        "Format size";
        if (obj_bytes == false)
          size_str = "unknown";
        else
          total_bytes = total_bytes + obj_bytes;
          total_known = total_known + 1;
          size_str = obj_bytes:format_bytes();
        endif
        "Get object info";
        obj_id = tostr(o);
        obj_name = `o.name ! ANY => "(no name)"';
        loc = `o.location ! ANY => #-1';
        loc_name = valid(loc) ? `loc.name ! ANY => tostr(loc)' | "Nowhere";
        rows = {@rows, {obj_name, obj_id, "[" + loc_name + "]", size_str}};
      endfor
      "Build footer";
      count = length(owned);
      footer = tostr(count) + " object" + (count == 1 ? "" | "s") + ".";
      if (total_known > 0)
        footer = footer + "  Total bytes: " + tostr(total_bytes) + ".";
      endif
      "Output results";
      player:inform_current($event:mk_info(player, header));
      table_result = $format.table:mk(headers, rows);
      player:inform_current($event:mk_info(player, table_result));
      player:inform_current($event:mk_info(player, footer));
      return count;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@build" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <name> [in <area>] -- Create a new room.";
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @build NAME [in AREA] [as PARENT]");
    endif
    try
      "Parse the command string";
      result = this:_parse_build_command(argstr);
      room_name = result['name];
      target_area = result['area];
      parent_obj = result['parent];
      "TODO: Detect duplicate room names in target_area. Should we warn or prevent?";
      "Create and place the room";
      if (valid(target_area))
        "Use capability if we have one, otherwise use area directly";
        cap = player:find_capability_for(target_area, 'area);
        "Use capability if found, otherwise use area directly";
        area_target = typeof(cap) == TYPE_FLYWEIGHT ? cap | target_area;
        try
          new_room = area_target:make_room_in(parent_obj);
          area_str = " in " + tostr(target_area);
        except (E_PERM)
          message = $grant_utils:format_denial(target_area, 'area, {'add_room});
          raise(E_PERM, message);
        endtry
      else
        "Free-floating room - create directly";
        new_room = parent_obj:create();
        area_str = " (free-floating)";
      endif
      new_room:set_name_aliases(room_name, {});
      "Report success";
      message = "Created \"" + room_name + "\" (" + tostr(new_room) + ")" + area_str + ".";
      player:inform_current($event:mk_info(player, message));
      return new_room;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb _parse_build_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse @build command arguments. Returns map with 'name, 'area, 'parent.";
    caller == this || raise(E_PERM);
    {command_str} = args;
    command_str = command_str:trim();
    "Defaults";
    current_room = player.location;
    target_area = valid(current_room) ? current_room.location | #-1;
    parent_obj = $room;
    "Check for 'in <area>' clause first";
    in_match = match(command_str, "(.+)\\s+in\\s+(\\S+)");
    if (in_match)
      name_part = in_match[2]:trim();
      area_spec = in_match[3];
      if (area_spec == "ether")
        target_area = #-1;
      else
        target_area = $match:match_object(area_spec, player);
        typeof(target_area) != TYPE_OBJ && raise(E_INVARG, "That area reference is not an object.");
        !valid(target_area) && raise(E_INVARG, "That area no longer exists.");
      endif
    else
      name_part = command_str;
    endif
    "Check for 'as <parent>' clause";
    as_match = match(name_part, "(.+)\\s+as\\s+(\\S+)");
    if (as_match)
      name_part = as_match[2]:trim();
      parent_spec = as_match[3];
      parent_obj = $match:match_object(parent_spec, player);
      typeof(parent_obj) != TYPE_OBJ && raise(E_INVARG, "That parent reference is not an object.");
      !valid(parent_obj) && raise(E_INVARG, "That parent object no longer exists.");
    endif
    "Parse room name using same logic as @create";
    parsed = $str_proto:parse_name_aliases(name_part);
    room_name = parsed[1];
    !room_name && raise(E_INVARG, "Room name cannot be blank.");
    return ['name -> room_name, 'area -> target_area, 'parent -> parent_obj];
  endverb

  verb "@dig @tunnel" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <dir> to <room> -- Create a passage to an existing room.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "to") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@dig [oneway] DIR[|RETURNDIR] to ROOM")));
      return;
    endif
    try
      "Parse the direction spec";
      result = this:_parse_dig_command(dobjstr);
      is_oneway = result['oneway];
      from_dir = result['from_dir];
      to_dir = result['to_dir];
      "Get current room and area first for scoped matching";
      current_room = player.location;
      !valid(current_room) && raise(E_INVARG, "You must be in a room to dig passages.");
      area = current_room.location;
      !valid(area) && raise(E_INVARG, "Your current room is not in an area.");
      "Find target room - only accept iobj if it's actually in this area";
      if (typeof(iobj) == TYPE_OBJ && valid(iobj) && iobj in area.contents)
        target_room = iobj;
      else
        "Search only in area's rooms by name";
        target_room = $match:resolve_in_scope(iobjstr, area.contents);
        if (typeof(target_room) != TYPE_OBJ || !valid(target_room))
          raise(E_INVARG, "No room found matching '" + iobjstr + "' in this area.");
        endif
      endif
      "Check permissions on both rooms using capabilities if we have them";
      from_room_cap = player:find_capability_for(current_room, 'room);
      from_room_target = typeof(from_room_cap) == TYPE_FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      to_room_cap = player:find_capability_for(target_room, 'room);
      to_room_target = typeof(to_room_cap) == TYPE_FLYWEIGHT ? to_room_cap | target_room;
      try
        to_room_target:check_can_dig_into();
      except (E_PERM)
        message = $grant_utils:format_denial(target_room, 'room, {'dig_into});
        raise(E_PERM, message);
      endtry
      "TODO: Detect duplicate exit directions from current_room. Can't have two 'up' exits.";
      "TODO: Handle alias conflicts - e.g. 'upstairs' and 'up' both expand to include 'u'.";
      "TODO: Write heuristics for detecting and resolving direction conflicts.";
      "Create the passage flyweight";
      if (is_oneway)
        passage = $passage:mk(current_room, from_dir[1], from_dir, "", true, target_room, "", {}, "", false, true);
      else
        passage = $passage:mk(current_room, from_dir[1], from_dir, "", true, target_room, to_dir[1], to_dir, "", true, true);
      endif
      "Register with area using capability if we have one";
      area_cap = player:find_capability_for(area, 'area);
      area_target = typeof(area_cap) == TYPE_FLYWEIGHT ? area_cap | area;
      area_target:create_passage(from_room_target, to_room_target, passage);
      "Report success";
      if (is_oneway)
        message = "Dug passage: " + from_dir:join(",") + " to " + tostr(target_room) + " (one-way).";
      else
        message = "Dug passage: " + from_dir:join(",") + " | " + to_dir:join(",") + " connecting to " + tostr(target_room) + ".";
      endif
      player:inform_current($event:mk_info(player, message));
      return passage;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@undig @remove-exit @delete-passage" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <direction> -- Remove a passage from the current room.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @undig DIRECTION or @undig ROOM");
    endif
    try
      "Get current room and its area first";
      current_room = player.location;
      !valid(current_room) && raise(E_INVARG, "You must be in a room to remove passages.");
      area = current_room.location;
      !valid(area) && raise(E_INVARG, "Your current room is not in an area.");
      "First, check if dobjstr matches a passage direction from this room";
      target_room = #-1;
      found_by_direction = false;
      for p in (area:passages_from(current_room))
        side_a_room = `p.side_a_room ! ANY => #-1';
        side_b_room = `p.side_b_room ! ANY => #-1';
        if (current_room == side_a_room)
          aliases = `p.side_a_aliases ! ANY => {}';
          if (dobjstr in aliases)
            target_room = side_b_room;
            found_by_direction = true;
            break;
          endif
        elseif (current_room == side_b_room)
          aliases = `p.side_b_aliases ! ANY => {}';
          if (dobjstr in aliases)
            target_room = side_a_room;
            found_by_direction = true;
            break;
          endif
        endif
      endfor
      "If no direction match, try matching as room reference";
      if (!valid(target_room))
        if (typeof(dobj) == TYPE_OBJ && valid(dobj))
          target_room = dobj;
        else
          target_room = `$match:match_object(dobjstr, area) ! ANY => #-1';
          typeof(target_room) != TYPE_OBJ && raise(E_INVARG, "No passage or room found matching '" + dobjstr + "'.");
        endif
        !valid(target_room) && raise(E_INVARG, "That room no longer exists.");
        "Check target room is in same area";
        target_room.location != area && raise(E_INVARG, "Target room must be in the same area.");
      endif
      "Look up passage (can be flyweight or $passage object)";
      passage = area:passage_for(current_room, target_room);
      if (typeof(passage) != TYPE_FLYWEIGHT && (typeof(passage) != TYPE_OBJ || !valid(passage)))
        raise(E_INVARG, "No passage found between here and " + tostr(target_room) + ".");
      endif
      labels = {};
      side_a_room = `passage.side_a_room ! ANY => #-1';
      side_b_room = `passage.side_b_room ! ANY => #-1';
      if (current_room == side_a_room)
        label = `passage.side_a_label ! ANY => ""';
        if (label != "")
          labels = {@labels, label};
        endif
      elseif (current_room == side_b_room)
        label = `passage.side_b_label ! ANY => ""';
        if (label != "")
          labels = {@labels, label};
        endif
      endif
      if (target_room == side_a_room)
        label = `passage.side_a_label ! ANY => ""';
        if (label != "" && !(label in labels))
          labels = {@labels, label};
        endif
      elseif (target_room == side_b_room)
        label = `passage.side_b_label ! ANY => ""';
        if (label != "" && !(label in labels))
          labels = {@labels, label};
        endif
      endif
      "Check permissions - must have dig_from on current room";
      from_room_cap = player:find_capability_for(current_room, 'room);
      from_room_target = typeof(from_room_cap) == TYPE_FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      "Remove passage via area using capability if we have one";
      area_cap = player:find_capability_for(area, 'area);
      area_target = typeof(area_cap) == TYPE_FLYWEIGHT ? area_cap | area;
      result = area_target:remove_passage(from_room_target, target_room);
      "Report success";
      if (result)
        label_str = length(labels) > 0 ? " (" + labels:join("/") + ")" | "";
        message = "Removed passage" + label_str + " to " + tostr(target_room) + ".";
        player:inform_current($event:mk_info(player, message));
        return true;
      else
        raise(E_INVARG, "Failed to remove passage (may have already been removed).");
      endif
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb _parse_dig_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse @dig direction spec. Returns map with 'oneway, 'from_dir, 'to_dir.";
    caller == this || raise(E_PERM);
    {dir_spec} = args;
    dir_spec = dir_spec:trim();
    "Check for oneway flag";
    is_oneway = false;
    if (dir_spec:starts_with("oneway "))
      is_oneway = true;
      dir_spec = dir_spec[8..length(dir_spec)]:trim();
    endif
    "Check for explicit bidirectional spec (|)";
    if ("|" in dir_spec)
      parts = dir_spec:split("|");
      length(parts) == 2 || raise(E_INVARG, "Direction spec must be 'dir' or 'dir|returndir'.");
      from_dirs = parts[1]:split(",");
      to_dirs = parts[2]:split(",");
      "Expand standard aliases";
      from_dirs = $passage:expand_direction_aliases(from_dirs);
      to_dirs = $passage:expand_direction_aliases(to_dirs);
      return ['oneway -> is_oneway, 'from_dir -> from_dirs, 'to_dir -> to_dirs];
    endif
    "Single direction - split on commas for aliases";
    from_dirs = dir_spec:split(",");
    "Infer opposite direction";
    to_dirs = this:_infer_opposite_directions(from_dirs);
    !to_dirs && raise(E_INVARG, "Can't infer opposite direction for '" + dir_spec + "'. Use 'dir|returndir' syntax.");
    "Expand standard aliases";
    from_dirs = $passage:expand_direction_aliases(from_dirs);
    to_dirs = $passage:expand_direction_aliases(to_dirs);
    return ['oneway -> is_oneway, 'from_dir -> from_dirs, 'to_dir -> to_dirs];
  endverb

  verb _infer_opposite_directions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Infer opposite directions for common compass/spatial directions.";
    caller == this || raise(E_PERM);
    {directions} = args;
    result = {};
    for dir in (directions)
      if (!maphaskey(this.direction_opposites, dir))
        return false;
      endif
      opposite = this.direction_opposites[dir];
      result = {@result, opposite};
    endfor
    return result;
  endverb

  verb "@rename" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> to <name> -- Rename an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "to") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@rename OBJECT to NAME[:ALIASES]")));
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

  verb _do_rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to rename object with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, new_name, new_aliases} = args;
    target_obj:set_name_aliases(new_name, new_aliases);
  endverb

  verb "@describe" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> as <description> -- Set object description.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "as") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@describe OBJECT_OR_DIRECTION as DESCRIPTION")));
      return;
    endif
    try
      "Try to match as object first, but catch errors";
      target_obj = false;
      try
        target_obj = $match:match_object(dobjstr, player);
      except (ANY)
        "Not an object - will try as passage below";
      endtry
      if (typeof(target_obj) == TYPE_OBJ && valid(target_obj))
        "It's an object - use existing object description logic";
        if (!player.wizard && target_obj.owner != player)
          raise(E_PERM, "You do not have permission to describe " + tostr(target_obj) + ".");
        endif
        new_description = iobjstr:trim();
        !new_description && raise(E_INVARG, "Description cannot be blank.");
        this:_do_describe_object(target_obj, new_description);
        obj_name = `target_obj.name ! ANY => tostr(target_obj)';
        message = "Set description of \"" + obj_name + "\" (" + tostr(target_obj) + ").";
        player:inform_current($event:mk_info(player, message));
        return 1;
      else
        "Not an object - try to match as a passage direction";
        result = this:_do_describe_passage(dobjstr, iobjstr);
        if (result)
          return 1;
        else
          raise(E_INVARG, "Could not find object or passage matching '" + dobjstr + "'.");
        endif
      endif
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@edit-description @edit-d" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Open multi-line editor for object description.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@edit-description <object>")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      if (!valid(target_obj))
        raise(E_INVARG, "I don't see that here.");
      endif
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You don't own that.");
      endif
      current_desc = `target_obj.description ! E_PROPNF => ""';
      conn = connection();
      session_id = player:start_edit_session(target_obj, "set_description", {conn});
      editor_title = "Edit Description: " + target_obj.name;
      present(player, session_id, "text/djot", "text-editor", current_desc, {{"object", $url_utils:to_curie_str($builder_features)}, {"verb", "receive_description_edit"}, {"title", editor_title}, {"text_mode", "string"}, {"session_id", session_id}});
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
    endtry
  endverb

  verb receive_description_edit (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback for text-editor when editing descriptions.";
    {session_id, content} = args;
    if (content == 'close)
      player:end_edit_session(session_id);
      return;
    endif
    session = player:get_edit_session(session_id);
    target_obj = session['target];
    conn = session['args][1];
    target_obj:set_description(content);
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    player:inform_connection(conn, $event:mk_info(player, "Description updated for " + obj_name + "."));
  endverb

  verb _do_describe_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set object description with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, new_description} = args;
    target_obj.description = new_description;
  endverb

  verb _do_describe_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set passage description with elevated permissions. Returns false if passage not found.";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {direction, description_str} = args;
    direction = direction:trim();
    description = description_str:trim();
    !description && raise(E_INVARG, "Description cannot be blank.");
    "Get current room - this is the player";
    current_room = player.location;
    if (!valid(current_room))
      return false;
    endif
    "Get area";
    area = current_room.location;
    if (!valid(area))
      return false;
    endif
    "Find passage matching the direction";
    passages = area:passages_from(current_room);
    if (!passages || length(passages) == 0)
      return false;
    endif
    "Find passage matching the direction";
    target_passage = area:find_passage_by_direction(current_room, direction);
    if (!target_passage)
      return false;
    endif
    "Check permissions";
    cap = player:find_capability_for(current_room, 'room);
    room_target = typeof(cap) == TYPE_FLYWEIGHT ? cap | current_room;
    room_target:check_can_dig_from();
    "Update passage description and set ambient flag";
    new_passage = target_passage:with_description_from(current_room, description);
    new_passage = new_passage:with_ambient_from(current_room, true);
    other_room = target_passage:other_room(current_room);
    area:update_passage(current_room, other_room, new_passage);
    message = "Set ambient description for '" + direction + "' passage: \"" + description + "\"";
    player:inform_current($event:mk_info(player, message));
    return true;
  endverb

  verb "@par*ent" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Show the parent of an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@parent OBJECT")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      let parent = parent(target_obj);
      let obj_name = target_obj.name;
      if (!valid(parent))
        message = tostr(obj_name, " (#", target_obj, ") has no parent.");
      else
        let parent_name = parent.name;
        message = tostr(obj_name, " (#", target_obj, ") has parent: ", parent_name, " (#", parent, ")");
      endif
      player:inform_current($event:mk_info(player, message));
      return parent;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb "@chi*ldren" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Show the children and descendants of an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@children OBJECT")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      children_list = children(target_obj);
      descendants_list = descendants(target_obj);
      obj_display = tostr(target_obj.name, " (", target_obj, ")");
      "Format each object as 'name (#id)'";
      children_strs = { tostr(c.name, " (", c, ")") for c in (children_list) };
      descendants_strs = { tostr(d.name, " (", d, ")") for d in (descendants_list) };
      title = $format.title:mk(obj_display);
      children_title = $format.title:mk("Children:");
      children_code = $format.code:mk(children_strs:english_list("none"));
      descendants_title = $format.title:mk("Descendants:");
      descendants_code = $format.code:mk(descendants_strs:english_list("none"));
      content = $format.block:mk(title, children_title, children_code, descendants_title, descendants_code);
      player:inform_current($event:mk_info(player, content));
      return children_list;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb "@integrate" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> as <description> -- Set object integrated description.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "as") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@integrate OBJECT as DESCRIPTION")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to set integrated description on " + tostr(target_obj) + ".");
      endif
      new_description = iobjstr:trim();
      this:_do_set_integrated_description(target_obj, new_description);
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      if (new_description == "")
        message = "Cleared integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + ").";
      else
        message = "Set integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "): \"" + new_description + "\"";
      endif
      player:inform_current($event:mk_info(player, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb _do_set_integrated_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set object integrated description with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, new_description} = args;
    target_obj.integrated_description = new_description;
  endverb

  verb "@move" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> to <location> -- Move an object to a new location.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || !dobjstr || (prepstr && prepstr != "to") || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@move OBJECT to LOCATION")));
      return;
    endif
    try
      "Match the object to move";
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That object reference is not valid.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      "Check permissions - must own the object or be a wizard";
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to move " + tostr(target_obj) + ".");
      endif
      "Match the destination location";
      dest_loc = $match:match_object(iobjstr, player);
      typeof(dest_loc) != TYPE_OBJ && raise(E_INVARG, "That destination reference is not valid.");
      !valid(dest_loc) && raise(E_INVARG, "That destination no longer exists.");
      "Get current location for messaging";
      old_loc = target_obj.location;
      is_player = `target_obj.player ! ANY => false';
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      "If it's a player, notify the old location";
      if (is_player && valid(old_loc))
        old_loc:announce_all_but({target_obj}, obj_name + " disappears suddenly for parts unknown.");
      endif
      "Perform the move";
      target_obj:moveto(dest_loc);
      "If it's a player, notify the new location";
      if (is_player && valid(dest_loc))
        dest_loc:announce_all_but({target_obj}, obj_name + " materializes out of thin air.");
      endif
      "Report success to the builder";
      dest_name = `dest_loc.name ! ANY => tostr(dest_loc)';
      message = "Moved " + obj_name + " (" + tostr(target_obj) + ") to " + dest_name + " (" + tostr(dest_loc) + ").";
      player:inform_current($event:mk_info(player, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@edit" (any any any) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object>.<property> -- Edit a property on an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      player:inform_current($event:mk_error(player, "Usage: " + verb + " <object>.<property>"));
      return;
    endif
    target_string = argstr:trim();
    "Property reference - must use dot notation";
    if (!("." in target_string))
      player:inform_current($event:mk_error(player, "Invalid property reference format. Use 'object.property'"));
      return;
    endif
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
      player:inform_current($event:mk_error(player, "I don't see '" + object_str + "' here."));
      return;
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error matching object: " + e[2]));
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
  endverb

  verb present_property_editor (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    {target_obj, prop_name} = args;
    editor_id = "edit-" + tostr(target_obj) + "-" + prop_name;
    editor_title = "Edit " + prop_name + " on " + tostr(target_obj);
    object_curie = $url_utils:to_curie_str(target_obj);
    present(player, editor_id, "text/plain", "property-value-editor", "", {{"object", object_curie}, {"property", prop_name}, {"title", editor_title}});
  endverb

  verb "@set-m*essage @setm" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Set a custom message template on an object property.";
    "Usage: @set-message OBJECT.PROPERTY template string...";
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || length(args) < 2)
      raise(E_INVARG, "Usage: @set-message OBJECT.PROPERTY template string...");
    endif
    try
      target_spec = args[1];
      "Parse property reference";
      parsed = $prog_utils:parse_target_spec(target_spec);
      if (!parsed)
        player:inform_current($event:mk_error(player, "Usage: @set-message <object>.<prop-name> template..."));
        return;
      endif
      "Handle both old 'property type and new 'compound type";
      if (parsed['type] == 'property)
        object_str = parsed['object_str];
        prop_name = parsed['item_name];
      elseif (parsed['type] == 'compound && length(parsed['selectors]) > 0)
        sel = parsed['selectors][1];
        if (sel['kind] != 'property)
          player:inform_current($event:mk_error(player, "Usage: @set-message <object>.<prop-name> template..."));
          return;
        endif
        object_str = parsed['object_str];
        prop_name = sel['item_name];
      else
        player:inform_current($event:mk_error(player, "Usage: @set-message <object>.<prop-name> template..."));
        return;
      endif
      prop_name:ends_with("_msg") || prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with '_msg', '_msgs', or '_msg_bag'.");
      "Match the target object";
      try
        target_obj = $match:match_object(object_str, player);
      except e (ANY)
        player:inform_current($event:mk_error(player, "Could not find object: " + tostr(e[2])));
        return;
      endtry
      "Get remainder after target spec";
      offset = index(argstr, target_spec) + length(target_spec);
      template_string = argstr[offset..length(argstr)]:trim();
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object does not exist.");
      "Check if property is writable";
      {writable, error_msg} = $obj_utils:check_message_property_writable(target_obj, prop_name, player);
      if (!writable)
        raise(E_PERM, error_msg);
      endif
      "Compile and validate the template";
      {success, result} = $obj_utils:validate_and_compile_template(template_string);
      if (!success)
        raise(E_INVARG, "Template compilation failed: " + result);
      endif
      compiled_list = result;
      "Set the compiled message";
      existing = `target_obj.(prop_name) ! E_PROPNF => E_PROPNF';
      if (typeof(existing) == TYPE_OBJ && isa(existing, $msg_bag))
        existing.entries = {compiled_list};
      else
        $obj_utils:set_compiled_message(target_obj, prop_name, compiled_list, player);
      endif
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      message = "Set message template on " + obj_name + " (" + tostr(target_obj) + ")." + prop_name + ".";
      player:inform_current($event:mk_info(player, message));
      return true;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@get-m*essage @getm" (any none any) owner: ARCH_WIZARD flags: "rd"
    "Show a message template for a single property.";
    "Usage: @get-message OBJECT.PROPERTY";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @get-message OBJECT.PROPERTY");
    endif
    try
      target_spec = args[1];
      parsed = $prog_utils:parse_target_spec(target_spec);
      if (!parsed || parsed['type] != 'property)
        player:inform_current($event:mk_error(player, "Usage: @get-message OBJECT.PROPERTY"));
        return;
      endif
      object_str = parsed['object_str];
      prop_name = parsed['item_name];
      prop_name:ends_with("_msg") || prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with '_msg', '_msgs', or '_msg_bag'.");
      target_obj = $match:match_object(object_str, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object does not exist.");
      if (!(prop_name in target_obj:all_properties()))
        raise(E_INVARG, "Property '" + prop_name + "' not found on " + tostr(target_obj) + ".");
      endif
      value = target_obj.(prop_name);
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      if (typeof(value) == TYPE_OBJ && isa(value, $msg_bag))
        entries = value:entries();
        if (!entries)
          header = obj_name + " (" + tostr(target_obj) + ")." + prop_name + " = (empty message bag)";
          player:inform_current($event:mk_info(player, header));
        else
          header = obj_name + " (" + tostr(target_obj) + ")." + prop_name + " (message bag, " + tostr(length(entries)) + " entries):";
          rows = {};
          idx = 1;
          for entry in (entries)
            template_str = typeof(entry) == TYPE_LIST ? `$sub_utils:decompile(entry) ! ANY => toliteral(entry)' | toliteral(entry);
            rows = {@rows, {tostr(idx), template_str}};
            idx = idx + 1;
          endfor
          table = $format.table:mk({"#", "Template"}, rows);
          player:inform_current($event:mk_info(player, header));
          player:inform_current($event:mk_info(player, table));
        endif
      else
        "If compiled template list, decompile to readable string";
        display_value = typeof(value) == TYPE_LIST ? `$sub_utils:decompile(value) ! ANY => toliteral(value)' | toliteral(value);
        message = obj_name + " (" + tostr(target_obj) + ")." + prop_name + " = " + display_value;
        player:inform_current($event:mk_info(player, message));
      endif
      return value;
    except e (ANY)
      msg = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, msg));
      return 0;
    endtry
  endverb

  verb "@set-r*ule" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Set a rule property on an object. Usage: @set-rule <object>.<rule-property> <expression>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    if (!argstr)
      raise(E_INVARG, "Usage: @set-rule OBJECT.RULE_PROPERTY expression");
    endif
    if (!args[1])
      raise(E_INVARG, "Usage: @set-rule OBJECT.PROPERTY expression");
    endif
    "args[1] is the object.property part, rest of argstr is the rule expression";
    prop_spec = args[1];
    rule_expr = argstr[length(prop_spec) + 1..$]:trim();
    server_log("Parsing: " + rule_expr);
    if (!rule_expr || rule_expr == "")
      raise(E_INVARG, "Usage: @set-rule OBJECT.PROPERTY expression");
    endif
    "Parse property reference";
    prop_parts = $str_proto:split(prop_spec, ".");
    length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property");
    target_name = prop_parts[1];
    prop_name = prop_parts[2];
    "Match object";
    target = $match:match_object(target_name, player);
    valid(target) || raise(E_INVARG, "Object not found");
    "Property must end with _rule to prevent accidents";
    prop_name:ends_with("_rule") || raise(E_INVARG, "Rule properties must end with '_rule'");
    "Permission check";
    if (!player.wizard && target.owner != player)
      raise(E_PERM, "You don't own " + tostr(target) + ".");
    endif
    "Parse and validate rule";
    rule = $rule_engine:parse_expression(rule_expr, tosym(prop_name));
    "Validate for bounded negation violations without evaluating";
    validation = $rule_engine:validate_rule(rule);
    if (length(validation['warnings]) > 0)
      for warning in (validation['warnings])
        player:inform_current($event:mk_error(player, "Warning: " + warning));
      endfor
      if (!validation['valid])
        raise(E_INVARG, "Rule has errors - fix bounded negation issues.");
      endif
    endif
    target.(prop_name) = rule;
    message = "Set rule on " + tostr(target) + "." + prop_name + ": \"" + rule_expr + "\"";
    player:inform_current($event:mk_info(player, message));
    return rule;
  endverb

  verb "@clear-rule" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Clear a rule property. Usage: @clear-rule <object>.<rule-property>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @clear-rule OBJECT.RULE_PROPERTY");
    endif
    try
      prop_spec = argstr:trim();
      "Parse property reference";
      prop_parts = $str_proto:split(prop_spec, ".");
      length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property");
      target_name = prop_parts[1];
      prop_name = prop_parts[2];
      "Match object";
      target = $match:match_object(target_name, player);
      valid(target) || raise(E_INVARG, "Object not found");
      "Property must end with _rule";
      prop_name:ends_with("_rule") || raise(E_INVARG, "Rule properties must end with '_rule'");
      "Permission check";
      if (!player.wizard && target.owner != player)
        raise(E_PERM, "You don't own " + tostr(target) + ".");
      endif
      "Clear the rule";
      target.(prop_name) = 0;
      message = "Cleared rule on " + tostr(target) + "." + prop_name;
      player:inform_current($event:mk_info(player, message));
      return true;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@show-rule" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Show a rule property. Usage: @show-rule <object>.<rule-property>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @show-rule OBJECT.RULE_PROPERTY");
    endif
    prop_spec = argstr:trim();
    "Parse property reference";
    prop_parts = $str_proto:split(prop_spec, ".");
    length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property");
    target_name = prop_parts[1];
    prop_name = prop_parts[2];
    "Match object";
    target = $match:match_object(target_name, player);
    valid(target) || raise(E_INVARG, "Object not found");
    "Property must end with _rule";
    prop_name:ends_with("_rule") || raise(E_INVARG, "Rule properties must end with '_rule'");
    "Get the rule";
    rule = target.(prop_name);
    if (rule == 0)
      message = tostr(target) + "." + prop_name + " = (no rule set)";
    else
      rule_expr = $rule_engine:decompile_rule(rule);
      message = tostr(target) + "." + prop_name + " = \"" + rule_expr + "\"";
    endif
    player:inform_current($event:mk_info(player, message));
    return rule;
  endverb

  verb "@mes*sages @msg" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Show all customizable message properties.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @messages OBJECT");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      "Get message properties";
      msg_props = $obj_utils:message_properties(target_obj);
      if (!msg_props || length(msg_props) == 0)
        obj_name = `target_obj.name ! ANY => tostr(target_obj)';
        message = obj_name + " (" + tostr(target_obj) + ") has no message properties.";
        player:inform_current($event:mk_info(player, message));
        return 0;
      endif
      "Build table";
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      headers = {"Property Name", "Current Value"};
      rows = {};
      for prop_info in (msg_props)
        {prop_name, prop_value} = prop_info;
        "Summarize the value - decompile if it's a compiled template list";
        if (typeof(prop_value) == TYPE_OBJ && isa(prop_value, $msg_bag))
          value_summary = "message bag (" + tostr(length(prop_value:entries())) + " entries)";
        elseif (typeof(prop_value) == TYPE_LIST)
          value_summary = `$sub_utils:decompile(prop_value) ! ANY => toliteral(prop_value)';
        else
          value_summary = toliteral(prop_value);
        endif
        rows = {@rows, {prop_name, value_summary}};
      endfor
      "Output results";
      header = "Message properties for " + obj_name + " (" + tostr(target_obj) + "):";
      player:inform_current($event:mk_info(player, header));
      table_result = $format.table:mk(headers, rows);
      player:inform_current($event:mk_info(player, table_result));
      return length(msg_props);
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@rules" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Show all rule properties on an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @rules OBJECT");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
    "Get rule properties";
    rule_props = $obj_utils:rule_properties(target_obj);
    if (!rule_props || length(rule_props) == 0)
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      message = obj_name + " (" + tostr(target_obj) + ") has no rule properties.";
      player:inform_current($event:mk_info(player, message));
      return 0;
    endif
    "Build table";
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    headers = {"Property Name", "Rule Expression"};
    rows = {};
    for prop_info in (rule_props)
      {prop_name, prop_value} = prop_info;
      "Decompile the rule if it's set";
      if (prop_value == 0)
        rule_expr = "(not set)";
      else
        rule_expr = $rule_engine:decompile_rule(prop_value);
      endif
      rows = {@rows, {prop_name, rule_expr}};
    endfor
    "Output results";
    header = "Rule properties for " + obj_name + " (" + tostr(target_obj) + "):";
    player:inform_current($event:mk_info(player, header));
    table_result = $format.table:mk(headers, rows);
    player:inform_current($event:mk_info(player, table_result));
    return length(rule_props);
  endverb

  verb "@reactions" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Show all reactions on an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @reactions OBJECT");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
    reaction_props = $obj_utils:reaction_properties(target_obj);
    if (!reaction_props || length(reaction_props) == 0)
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      message = obj_name + " (" + tostr(target_obj) + ") has no reactions.";
      player:inform_current($event:mk_info(player, message));
      return 0;
    endif
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    header = "Reactions on " + obj_name + " (" + tostr(target_obj) + "):";
    player:inform_current($event:mk_info(player, header));
    headers = {"Property", "Trigger", "When", "Effects", "Enabled"};
    rows = {};
    for prop_info in (reaction_props)
      {prop_name, reaction} = prop_info;
      trigger_str = "??";
      if (typeof(reaction.trigger) == TYPE_SYM)
        trigger_str = tostr(reaction.trigger);
      elseif (typeof(reaction.trigger) == TYPE_LIST && length(reaction.trigger) >= 4 && reaction.trigger[1] == 'when)
        {_, prop, op, val} = reaction.trigger;
        trigger_str = tostr(prop) + " " + tostr(op) + " " + tostr(val);
      elseif (typeof(reaction.trigger) == TYPE_LIST)
        trigger_str = toliteral(reaction.trigger);
      endif
      if (reaction.when == 0)
        when_str = "-";
      else
        when_str = $rule_engine:decompile_rule(reaction.when);
      endif
      effects_parts = {};
      for effect in (reaction.effects)
        if (typeof(effect) == TYPE_FLYWEIGHT && effect.type)
          effects_parts = {@effects_parts, tostr(effect.type)};
        elseif (typeof(effect) == TYPE_LIST && length(effect) > 0)
          effects_parts = {@effects_parts, tostr(effect[1])};
        endif
      endfor
      effects_str = effects_parts:join(", ");
      if (effects_str == "")
        effects_str = "(none)";
      endif
      enabled_str = reaction.enabled ? "yes" | "no";
      rows = {@rows, {prop_name, trigger_str, when_str, effects_str, enabled_str}};
    endfor
    table_result = $format.table:mk(headers, rows);
    player:inform_current($event:mk_info(player, table_result));
    return length(reaction_props);
  endverb

  verb "@add-reaction @set-reaction" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Add a reaction to an object. Usage: @add-reaction <object>.<name>_reaction <trigger> <when> <effects>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr || length(args) < 4)
      raise(E_INVARG, "Usage: @add-reaction OBJECT.NAME_reaction TRIGGER WHEN EFFECTS");
    endif
    try
      prop_spec = args[1];
      "Parse property reference";
      prop_parts = $str_proto:split(prop_spec, ".");
      length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property_reaction");
      target_name = prop_parts[1];
      prop_name = prop_parts[2];
      "Match object";
      target_obj = $match:match_object(target_name, player);
      valid(target_obj) || raise(E_INVARG, "Object not found");
      "Property must end with _reaction";
      prop_name:ends_with("_reaction") || raise(E_INVARG, "Reaction properties must end with '_reaction'");
      "Permission check";
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You don't own " + tostr(target_obj) + ".");
      endif
      "Parse trigger - evaluate as MOO expression";
      trigger_str = args[2];
      trigger = eval("return " + trigger_str + ";")[2];
      "Parse when clause";
      when_str = args[3];
      when_clause = when_str == "0" ? 0 | when_str;
      "Parse effects - join args from 4 onwards and evaluate";
      effects_parts = args[4..length(args)];
      effects_str = $list_proto:join(effects_parts, " ");
      effects = eval("return " + effects_str + ";")[2];
      reaction = $reaction:mk(trigger, when_clause, effects);
      "Add or update property";
      if (prop_name in target_obj:all_properties())
        target_obj.(prop_name) = reaction;
      else
        add_property(target_obj, prop_name, reaction, {player, "r"});
      endif
      trigger_display = typeof(trigger) == TYPE_SYM ? tostr(trigger) | "threshold";
      message = "Set " + tostr(target_obj) + "." + prop_name + ": trigger=" + trigger_display + ", effects=" + tostr(length(effects));
      player:inform_current($event:mk_info(player, message));
      return reaction;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@enable-reaction" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Enable a reaction. Usage: @enable-reaction <object>.<property_reaction>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @enable-reaction OBJECT.PROPERTY_reaction");
    endif
    try
      prop_spec = argstr:trim();
      "Parse property reference";
      prop_parts = $str_proto:split(prop_spec, ".");
      length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property_reaction");
      target_name = prop_parts[1];
      prop_name = prop_parts[2];
      "Match object";
      target_obj = $match:match_object(target_name, player);
      valid(target_obj) || raise(E_INVARG, "Object not found");
      "Property must end with _reaction";
      prop_name:ends_with("_reaction") || raise(E_INVARG, "Reaction properties must end with '_reaction'");
      "Permission check";
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You don't own " + tostr(target_obj) + ".");
      endif
      "Check property exists and is a reaction";
      prop_name in target_obj:all_properties() || raise(E_INVARG, "Property not found: " + prop_name);
      reaction = target_obj.(prop_name);
      typeof(reaction) == TYPE_FLYWEIGHT && reaction.delegate == $reaction || raise(E_INVARG, prop_name + " is not a reaction");
      "Enable the reaction";
      reaction.enabled = true;
      target_obj.(prop_name) = reaction;
      player:inform_current($event:mk_info(player, "Enabled " + tostr(target_obj) + "." + prop_name));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@disable-reaction" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Disable a reaction. Usage: @disable-reaction <object>.<property_reaction>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @disable-reaction OBJECT.PROPERTY_reaction");
    endif
    try
      prop_spec = argstr:trim();
      "Parse property reference";
      prop_parts = $str_proto:split(prop_spec, ".");
      length(prop_parts) == 2 || raise(E_INVARG, "Property must be object.property_reaction");
      target_name = prop_parts[1];
      prop_name = prop_parts[2];
      "Match object";
      target_obj = $match:match_object(target_name, player);
      valid(target_obj) || raise(E_INVARG, "Object not found");
      "Property must end with _reaction";
      prop_name:ends_with("_reaction") || raise(E_INVARG, "Reaction properties must end with '_reaction'");
      "Permission check";
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You don't own " + tostr(target_obj) + ".");
      endif
      "Check property exists and is a reaction";
      prop_name in target_obj:all_properties() || raise(E_INVARG, "Property not found: " + prop_name);
      reaction = target_obj.(prop_name);
      typeof(reaction) == TYPE_FLYWEIGHT && reaction.delegate == $reaction || raise(E_INVARG, prop_name + " is not a reaction");
      "Disable the reaction";
      reaction.enabled = false;
      target_obj.(prop_name) = reaction;
      player:inform_current($event:mk_info(player, "Disabled " + tostr(target_obj) + "." + prop_name));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@par*ents" (any none none) owner: ARCH_WIZARD flags: "rxd"
    "HINT: <object> -- Show the parent chain of an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@parents OBJECT")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      ancestors_list = ancestors(target_obj);
      obj_display = tostr(target_obj.name, " (", target_obj, ")");
      "Format ancestors as 'name (#id)'";
      ancestors_strs = { tostr(a.name, " (", a, ")") for a in (ancestors_list) };
      title = $format.title:mk(obj_display);
      parents_title = $format.title:mk("Parents:");
      parents_code = $format.code:mk(ancestors_strs:english_list("none"));
      content = $format.block:mk(title, parents_title, parents_code);
      player:inform_current($event:mk_info(player, content));
      return ancestors_list;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb "@set-thumbnail @thumbnail" (any none none) owner: ARCH_WIZARD flags: "rd"
    "HINT: <object> -- Set a thumbnail image for an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@set-thumbnail OBJECT")));
      return;
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != TYPE_OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to set thumbnail on " + tostr(target_obj) + ".");
      endif
      "Prompt for image upload";
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      result = player:upload_image("Upload thumbnail image for " + obj_name + ":", 5 * (1 << 20));
      if (!result)
        player:inform_current($event:mk_info(player, "Thumbnail upload cancelled."):with_audience('utility));
        return 0;
      endif
      {content_type, picbin} = result;
      target_obj:set_thumbnail(content_type, picbin);
      player:inform_current($event:mk_info(player, "Set thumbnail for " + obj_name + " (" + tostr(target_obj) + ")."));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == TYPE_STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return help topics for builder commands.";
    {for_player, ?topic = ""} = args;
    "Main overview topic";
    overview = $help:mk("building", "Builder commands", "Commands for creating and organizing the world:\n\n`@create`, `@recycle`, `@dig`, `@undig`, `@rename`, `@describe`, `@edit-description`, `@parent`, `@children`, `@integrate`, `@move`, `@messages`, `@rules`, `@reactions`, `@parents`, `@set-thumbnail`, `@grant`, `@audit`, `@build`\n\nUse `help <command>` for details on each command.", {"build", "create", "world"}, 'building, {"programming"});
    "If asking for all topics, just return overview";
    topic == "" && return {overview};
    "Check if topic matches overview";
    overview:matches(topic) && return overview;
    "Try to generate help from verb HINT tags";
    verb_help = `$help_utils:verb_help_from_hint(this, topic, 'building) ! ANY => 0';
    typeof(verb_help) != TYPE_INT && return verb_help;
    return 0;
  endverb
endobject