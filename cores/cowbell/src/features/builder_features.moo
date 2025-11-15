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

  verb "@create" (any named any) owner: ARCH_WIZARD flags: "rd"
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @create <parent> named <name[:aliases]>");
    endif
    try
      parent_obj = $match:match_object(dobjstr, player);
      typeof(parent_obj) != OBJ && raise(E_INVARG, "That parent reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
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
    player.is_builder || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr)
      raise(E_INVARG, "Usage: @recycle <object>");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@grant" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Grant capabilities to a player. Usage: @grant <target>.<category>(<cap1,cap2>) to <player>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    try
      if (!dobjstr || !iobjstr)
        raise(E_INVARG, "Usage: @grant <target>.<category>(<cap1,cap2>) to <player>");
      endif
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
      if (typeof(grantee) != OBJ)
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@audit @owned" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Show objects owned by a player. Usage: @audit [<player>]";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    try
      "Determine which player to audit";
      if (dobjstr)
        target = $match:match_object(dobjstr, player);
        typeof(target) != OBJ && raise(E_INVARG, "That reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@build" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Create a new room. Usage: @build <name> [in <area>] [as <parent>]";
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!argstr)
      raise(E_INVARG, "Usage: @build <name> [in <area>] [as <parent>]");
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
        area_target = typeof(cap) == FLYWEIGHT ? cap | target_area;
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
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
        typeof(target_area) != OBJ && raise(E_INVARG, "That area reference is not an object.");
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
      typeof(parent_obj) != OBJ && raise(E_INVARG, "That parent reference is not an object.");
      !valid(parent_obj) && raise(E_INVARG, "That parent object no longer exists.");
    endif
    "Parse room name using same logic as @create";
    parsed = $str_proto:parse_name_aliases(name_part);
    room_name = parsed[1];
    !room_name && raise(E_INVARG, "Room name cannot be blank.");
    return ['name -> room_name, 'area -> target_area, 'parent -> parent_obj];
  endverb

  verb "@dig @tunnel" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Create a passage to an existing room. Usage: @dig [oneway] <dir>[|<returndir>] to <room>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @dig [oneway] <dir>[|<returndir>] to <room>");
    endif
    try
      "Parse the direction spec";
      result = this:_parse_dig_command(dobjstr);
      is_oneway = result['oneway];
      from_dir = result['from_dir];
      to_dir = result['to_dir];
      "Find the target room - use iobj if it matched, otherwise search area by name";
      if (typeof(iobj) == OBJ && valid(iobj))
        target_room = iobj;
      else
        "Parser didn't find it, search area's rooms by name";
        current_room = player.location;
        area = valid(current_room) ? current_room.location | #-1;
        if (!valid(area))
          raise(E_INVARG, "You must be in an area to search for rooms by name.");
        endif
        target_room = $match:match_object(iobjstr, area);
        typeof(target_room) != OBJ && raise(E_INVARG, "That room reference is not an object.");
      endif
      !valid(target_room) && raise(E_INVARG, "That room no longer exists.");
      "Get current room and its area";
      current_room = player.location;
      !valid(current_room) && raise(E_INVARG, "You must be in a room to dig passages.");
      area = current_room.location;
      !valid(area) && raise(E_INVARG, "Your current room is not in an area.");
      "Check target room is in same area";
      target_room.location != area && raise(E_INVARG, "Target room must be in the same area.");
      "Check permissions on both rooms using capabilities if we have them";
      from_room_cap = player:find_capability_for(current_room, 'room);
      from_room_target = typeof(from_room_cap) == FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      to_room_cap = player:find_capability_for(target_room, 'room);
      to_room_target = typeof(to_room_cap) == FLYWEIGHT ? to_room_cap | target_room;
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
      area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@undig @remove-exit @delete-passage" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Remove a passage from the current room to another. Usage: @undig <room>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @undig <room>");
    endif
    try
      "Find target room - use dobj if it matched, otherwise search by name";
      if (typeof(dobj) == OBJ && valid(dobj))
        target_room = dobj;
      else
        "Parser didn't find it, search area's rooms by name";
        current_room = player.location;
        area = valid(current_room) ? current_room.location | #-1;
        if (!valid(area))
          raise(E_INVARG, "You must be in an area to search for rooms by name.");
        endif
        target_room = $match:match_object(dobjstr, area);
        typeof(target_room) != OBJ && raise(E_INVARG, "That room reference is not an object.");
      endif
      !valid(target_room) && raise(E_INVARG, "That room no longer exists.");
      "Get current room and its area";
      current_room = player.location;
      !valid(current_room) && raise(E_INVARG, "You must be in a room to remove passages.");
      area = current_room.location;
      !valid(area) && raise(E_INVARG, "Your current room is not in an area.");
      "Check target room is in same area";
      target_room.location != area && raise(E_INVARG, "Target room must be in the same area.");
      "Check if passage exists and get labels for reporting";
      passage = area:passage_for(current_room, target_room);
      if (!passage)
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
      from_room_target = typeof(from_room_cap) == FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      "Remove passage via area using capability if we have one";
      area_cap = player:find_capability_for(area, 'area);
      area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
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

  verb "@rename" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Rename an object. Usage: @rename <object> to <name[:aliases]>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @rename <object> to <name[:aliases]>");
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

  verb _do_rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to rename object with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(player);
    {target_obj, new_name, new_aliases} = args;
    target_obj:set_name_aliases(new_name, new_aliases);
  endverb

  verb "@describe" (any as any) owner: ARCH_WIZARD flags: "rd"
    "Set object or passage description. Usage: @describe <object or direction> as <description>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @describe <object or direction> as <description>");
    endif
    try
      "Try to match as object first, but catch errors";
      target_obj = false;
      try
        target_obj = $match:match_object(dobjstr, player);
      except (ANY)
        "Not an object - will try as passage below";
      endtry
      if (typeof(target_obj) == OBJ && valid(target_obj))
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
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
    "Search for passage matching the direction";
    target_passage = E_NONE;
    for p in (passages)
      "Check if this passage matches the direction";
      side_a_room = `p.side_a_room ! ANY => #-1';
      side_b_room = `p.side_b_room ! ANY => #-1';
      if (current_room == side_a_room)
        label = `p.side_a_label ! ANY => ""';
        aliases = `p.side_a_aliases ! ANY => {}';
      elseif (current_room == side_b_room)
        label = `p.side_b_label ! ANY => ""';
        aliases = `p.side_b_aliases ! ANY => {}';
      else
        continue;
      endif
      "Check if direction matches label or any alias (MOO has case-insensitive comparisons)";
      if (label == direction)
        target_passage = p;
        break;
      endif
      for alias in (aliases)
        if (typeof(alias) == STR && alias == direction)
          target_passage = p;
          break;
        endif
      endfor
      if (typeof(target_passage) != ERR)
        break;
      endif
    endfor
    if (typeof(target_passage) == ERR)
      return false;
    endif
    "Check permissions";
    cap = player:find_capability_for(current_room, 'room);
    room_target = typeof(cap) == FLYWEIGHT ? cap | current_room;
    room_target:check_can_dig_from();
    "Update passage description (ambient=true by default)";
    side_a_room = `target_passage.side_a_room ! ANY => #-1';
    side_b_room = `target_passage.side_b_room ! ANY => #-1';
    if (typeof(target_passage) == FLYWEIGHT)
      "Get all current properties";
      room_a = `target_passage.side_a_room ! ANY => #-1';
      room_b = `target_passage.side_b_room ! ANY => #-1';
      label_a = `target_passage.side_a_label ! ANY => ""';
      label_b = `target_passage.side_b_label ! ANY => ""';
      aliases_a = `target_passage.side_a_aliases ! ANY => {}';
      aliases_b = `target_passage.side_b_aliases ! ANY => {}';
      desc_a = `target_passage.side_a_description ! ANY => ""';
      desc_b = `target_passage.side_b_description ! ANY => ""';
      ambient_a = `target_passage.side_a_ambient ! ANY => true';
      ambient_b = `target_passage.side_b_ambient ! ANY => true';
      is_open = `target_passage.is_open ! ANY => true';
      "Update the side we're on";
      if (current_room == side_a_room)
        desc_a = description;
        ambient_a = true;
      elseif (current_room == side_b_room)
        desc_b = description;
        ambient_b = true;
      endif
      "Create new passage flyweight with updated values";
      new_passage = $passage:mk(room_a, label_a, aliases_a, desc_a, ambient_a, room_b, label_b, aliases_b, desc_b, ambient_b, is_open);
      "Replace the passage in the area";
      area:update_passage(current_room, room_a == current_room ? room_b | room_a, new_passage);
    else
      "It's an object, we can modify properties directly";
      if (current_room == side_a_room)
        target_passage.side_a_description = description;
        target_passage.side_a_ambient = true;
      elseif (current_room == side_b_room)
        target_passage.side_b_description = description;
        target_passage.side_b_ambient = true;
      endif
    endif
    message = "Set ambient description for '" + direction + "' passage: \"" + description + "\"";
    player:inform_current($event:mk_info(player, message));
    return true;
  endverb

  verb "@par*ent" (this none this) owner: ARCH_WIZARD flags: "rd"
    "Show the parent of an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @parent <object>");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb "@chi*ildren" (this none this) owner: ARCH_WIZARD flags: "rd"
    "Show the children of an object.";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @children <object>");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      let children_list = children(target_obj);
      let obj_name = target_obj.name;
      if (!length(children_list))
        message = tostr(obj_name, " (", target_obj, ") has no children.");
        player:inform_current($event:mk_info(player, message));
        return {};
      else
        let child_count = length(children_list);
        let child_names = { child:display_name() for child in (children_list) };
        let title_text = tostr(obj_name, " (", target_obj, ") has ", child_count, " child", child_count == 1 ? "" | "ren", ":");
        let title_obj = $format.title:mk(title_text);
        let list_obj = $format.list:mk(child_names);
        let content = $format.block:mk(title_obj, list_obj);
        player:inform_current($event:mk_info(player, content));
        return children_list;
      endif
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return false;
    endtry
  endverb

  verb "@integrate" (any as any) owner: ARCH_WIZARD flags: "rd"
    "Set object integrated description. Usage: @integrate <object> as <description>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @integrate <object> as <description>");
    endif
    try
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
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

  verb "@move" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Move an object to a new location. Usage: @move <object> to <location>";
    caller != player && raise(E_PERM);
    player.is_builder || raise(E_PERM, "Builder features required.");
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @move <object> to <location>");
    endif
    try
      "Match the object to move";
      target_obj = $match:match_object(dobjstr, player);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That object reference is not valid.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      "Check permissions - must own the object or be a wizard";
      if (!player.wizard && target_obj.owner != player)
        raise(E_PERM, "You do not have permission to move " + tostr(target_obj) + ".");
      endif
      "Match the destination location";
      dest_loc = $match:match_object(iobjstr, player);
      typeof(dest_loc) != OBJ && raise(E_INVARG, "That destination reference is not valid.");
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
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      player:inform_current($event:mk_error(player, message));
      return 0;
    endtry
  endverb

  verb "@edit" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Edit a property on an object using the presentation system.";
    "Usage: @edit <object>.<property>";
    "Examples: @edit player.name, @edit me.description";
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
    object_curie = target_obj:to_curie_str();
    present(player, editor_id, "text/plain", "property-value-editor", "", {{"object", object_curie}, {"property", prop_name}, {"title", editor_title}});
  endverb
endobject