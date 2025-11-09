object BUILDER
  name: "Generic Builder"
  parent: PLAYER
  location: FIRST_ROOM
  owner: HACKER
  programmer: true
  readable: true

  property direction_abbrevs (owner: HACKER, flags: "rc") = [
    "d" -> "down",
    "down" -> "d",
    "downstairs" -> "d",
    "e" -> "east",
    "east" -> "e",
    "i" -> "in",
    "in" -> "i",
    "n" -> "north",
    "ne" -> "northeast",
    "north" -> "n",
    "northeast" -> "ne",
    "northwest" -> "nw",
    "nw" -> "northwest",
    "o" -> "out",
    "out" -> "o",
    "s" -> "south",
    "se" -> "southeast",
    "south" -> "s",
    "southeast" -> "se",
    "southwest" -> "sw",
    "sw" -> "southwest",
    "u" -> "up",
    "up" -> "u",
    "upstairs" -> "u",
    "w" -> "west",
    "west" -> "w"
  ];
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
  property grants_area (owner: HACKER, flags: "") = [];
  property grants_room (owner: HACKER, flags: "") = [];

  override description = "Generic builder character prototype. Builders can create and modify basic objects and rooms. Inherits from player with building permissions.";
  override import_export_id = "builder";

  verb "@create" (any named any) owner: HACKER flags: "rd"
    caller == this || raise(E_PERM);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @create <parent> named <name[:aliases]>");
    endif
    try
      parent_obj = $match:match_object(dobjstr, this);
      typeof(parent_obj) != OBJ && raise(E_INVARG, "That parent reference is not an object.");
      !valid(parent_obj) && raise(E_INVARG, "That parent object no longer exists.");
      is_fertile = `parent_obj.fertile ! E_PROPNF => false';
      if (!is_fertile && !this.wizard && parent_obj.owner != this)
        raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj) + ".");
      endif
      parsed = $str_proto:parse_name_aliases(iobjstr);
      primary_name = parsed[1];
      alias_list = parsed[2];
      !primary_name && raise(E_INVARG, "Primary object name cannot be blank.");
      new_obj = this:_create_child_object(parent_obj, primary_name, alias_list);
      object_id = tostr(new_obj);
      parent_name = `parent_obj.name ! ANY => tostr(parent_obj)';
      parent_id = tostr(parent_obj);
      message = "Created \"" + primary_name + "\" (" + object_id + ") as a child of \"" + parent_name + "\" (" + parent_id + ").";
      if (alias_list)
        alias_str = alias_list:join(", ");
        message = message + " Aliases: " + alias_str + ".";
      endif
      message = message + " It is now in your inventory.";
      this:inform_current($event:mk_info(this, message));
      return new_obj;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb _create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create the child object, apply naming, and move it into the builder's inventory.";
    caller == this || caller.wizard || raise(E_PERM);
    {parent_obj, primary_name, alias_list} = args;
    set_task_perms(this);
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, alias_list);
    new_obj:moveto(this);
    return new_obj;
  endverb

  verb test_create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    new_obj = this:_create_child_object($thing, "Widget", {"gadget"});
    typeof(new_obj) == OBJ || raise(E_ASSERT("Returned value was not an object: " + toliteral(new_obj)));
    new_obj.owner != this && raise(E_ASSERT("Builder should own created object"));
    new_obj.location != this && raise(E_ASSERT("Created object should move into inventory"));
    new_obj.name != "Widget" && raise(E_ASSERT("Primary name was not applied: " + new_obj.name));
    new_obj.aliases != {"gadget"} && raise(E_ASSERT("Aliases not applied: " + toliteral(new_obj.aliases)));
    new_obj:destroy();
    return true;
  endverb

  verb "@recycle @destroy" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr)
      raise(E_INVARG, "Usage: @recycle <object>");
    endif
    try
      target_obj = $match:match_object(dobjstr, this);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!this.wizard && target_obj.owner != this)
        raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj) + ".");
      endif
      obj_name = target_obj.name;
      obj_id = tostr(target_obj);
      target_obj:destroy();
      this:inform_current($event:mk_info(this, "Recycled \"" + obj_name + "\" (" + obj_id + ")."));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb "@grant" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Grant capabilities to a player. Usage: @grant <target>.<category>(<cap1,cap2>) to <player>";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    try
      if (!dobjstr || !iobjstr)
        raise(E_INVARG, "Usage: @grant <target>.<category>(<cap1,cap2>) to <player>");
      endif
      "Parse grant specification using $grant_utils";
      {target_obj, category, cap_list} = $grant_utils:parse_grant(dobjstr);
      "Permission check - must be owner or wizard";
      !this.wizard && target_obj.owner != this && raise(E_PERM, "You must be owner or wizard to grant capabilities for " + tostr(target_obj) + ".");
      "Match grantee - use iobj from parser, or fall back to match_object if parser failed";
      if (iobj == $failed_match)
        grantee = $match:match_object(iobjstr, this);
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
      this:inform_current($event:mk_info(this, message));
      return cap;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb test_recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    test_obj = this:_create_child_object($thing, "TestWidget", {"testgadget"});
    typeof(test_obj) == OBJ || raise(E_ASSERT("Setup: Failed to create test object"));
    obj_name = test_obj.name;
    obj_id = tostr(test_obj);
    test_obj:destroy();
    valid(test_obj) && raise(E_ASSERT("Object should be invalid after destruction"));
    return true;
  endverb

  verb test_capability_building (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test building with granted capabilities";
    test_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
    "Create test objects - area, two rooms, and a builder";
    test_area = create($area);
    test_room1 = create($room);
    test_room2 = create($room);
    test_builder = create($builder);
    test_room1:moveto(test_area);
    test_room2:moveto(test_area);
    "Test 1: Grant area capabilities to builder";
    $root:grant_capability(test_area, {'add_room, 'create_passage}, test_builder, 'area, test_key);
    typeof(test_builder.grants_area) == MAP || raise(E_ASSERT("Builder should have grants_area map"));
    maphaskey(test_builder.grants_area, test_area) || raise(E_ASSERT("Builder should have grant for test_area"));
    "Test 2: Grant room capabilities";
    $root:grant_capability(test_room1, {'dig_from}, test_builder, 'room, test_key);
    $root:grant_capability(test_room2, {'dig_into}, test_builder, 'room, test_key);
    maphaskey(test_builder.grants_room, test_room1) || raise(E_ASSERT("Builder should have grant for room1"));
    maphaskey(test_builder.grants_room, test_room2) || raise(E_ASSERT("Builder should have grant for room2"));
    "Test 3: find_capability_for returns the grants";
    area_cap = test_builder:find_capability_for(test_area, 'area);
    typeof(area_cap) == FLYWEIGHT || raise(E_ASSERT("Should find area capability"));
    area_cap.delegate == test_area || raise(E_ASSERT("Area cap should be for test_area"));
    room1_cap = test_builder:find_capability_for(test_room1, 'room);
    typeof(room1_cap) == FLYWEIGHT || raise(E_ASSERT("Should find room1 capability"));
    room1_cap.delegate == test_room1 || raise(E_ASSERT("Room1 cap should be for test_room1"));
    "Test 4: Verify capabilities grant expected permissions";
    {target, perms} = area_cap:challenge_for_with_key({'add_room, 'create_passage}, test_key);
    target == test_area || raise(E_ASSERT("Area cap should grant add_room and create_passage"));
    {target2, perms2} = room1_cap:challenge_for_with_key({'dig_from}, test_key);
    target2 == test_room1 || raise(E_ASSERT("Room1 cap should grant dig_from"));
    "Test 5: Capability not found returns false";
    nonexistent_room = create($room);
    no_cap = test_builder:find_capability_for(nonexistent_room, 'room);
    no_cap == false || raise(E_ASSERT("Should return false for room without grant"));
    "Cleanup";
    test_area:destroy();
    test_room1:destroy();
    test_room2:destroy();
    test_builder:destroy();
    nonexistent_room:destroy();
    return true;
  endverb

  verb "@audit @owned" (none none none) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    try
      owned = sort(owned_objects(this));
      if (!owned)
        this:inform_current($event:mk_info(this, "You don't own any objects."));
        return 0;
      endif
      headers = {"Object", "Name", "Parent"};
      rows = {};
      for o in (owned)
        obj_id = tostr(o);
        obj_name = `o.name ! ANY => "(no name)"';
        parent_obj = `parent(o) ! ANY => #-1';
        parent_str = valid(parent_obj) ? tostr(parent_obj) | "(none)";
        rows = {@rows, {obj_id, obj_name, parent_str}};
      endfor
      table_result = $format.table:mk(headers, rows);
      this:inform_current($event:mk_info(this, table_result));
      return length(owned);
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb "@build" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Create a new room. Usage: @build <name> [in <area>] [as <parent>]";
    caller == this || raise(E_PERM);
    set_task_perms(this);
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
        cap = this:find_capability_for(target_area, 'area);
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
      this:inform_current($event:mk_info(this, message));
      return new_room;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb _parse_build_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse @build command arguments. Returns map with 'name, 'area, 'parent.";
    caller == this || raise(E_PERM);
    {command_str} = args;
    command_str = command_str:trim();
    "Defaults";
    current_room = this.location;
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
        target_area = $match:match_object(area_spec, this);
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
      parent_obj = $match:match_object(parent_spec, this);
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
    caller == this || raise(E_PERM);
    set_task_perms(this);
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
        current_room = this.location;
        area = valid(current_room) ? current_room.location | #-1;
        if (!valid(area))
          raise(E_INVARG, "You must be in an area to search for rooms by name.");
        endif
        target_room = $match:match_object(iobjstr, area);
        typeof(target_room) != OBJ && raise(E_INVARG, "That room reference is not an object.");
      endif
      !valid(target_room) && raise(E_INVARG, "That room no longer exists.");
      "Get current room and its area";
      current_room = this.location;
      !valid(current_room) && raise(E_INVARG, "You must be in a room to dig passages.");
      area = current_room.location;
      !valid(area) && raise(E_INVARG, "Your current room is not in an area.");
      "Check target room is in same area";
      target_room.location != area && raise(E_INVARG, "Target room must be in the same area.");
      "Check permissions on both rooms using capabilities if we have them";
      from_room_cap = this:find_capability_for(current_room, 'room);
      from_room_target = typeof(from_room_cap) == FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      to_room_cap = this:find_capability_for(target_room, 'room);
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
      area_cap = this:find_capability_for(area, 'area);
      area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
      area_target:create_passage(from_room_target, to_room_target, passage);
      "Report success";
      if (is_oneway)
        message = "Dug passage: " + from_dir:join(",") + " to " + tostr(target_room) + " (one-way).";
      else
        message = "Dug passage: " + from_dir:join(",") + " | " + to_dir:join(",") + " connecting to " + tostr(target_room) + ".";
      endif
      this:inform_current($event:mk_info(this, message));
      return passage;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb "@undig @remove-exit @delete-passage" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Remove a passage from the current room to another. Usage: @undig <room>";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    if (!dobjstr)
      raise(E_INVARG, "Usage: @undig <room>");
    endif
    try
      "Find target room - use dobj if it matched, otherwise search by name";
      if (typeof(dobj) == OBJ && valid(dobj))
        target_room = dobj;
      else
        "Parser didn't find it, search area's rooms by name";
        current_room = this.location;
        area = valid(current_room) ? current_room.location | #-1;
        if (!valid(area))
          raise(E_INVARG, "You must be in an area to search for rooms by name.");
        endif
        target_room = $match:match_object(dobjstr, area);
        typeof(target_room) != OBJ && raise(E_INVARG, "That room reference is not an object.");
      endif
      !valid(target_room) && raise(E_INVARG, "That room no longer exists.");
      "Get current room and its area";
      current_room = this.location;
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
      from_room_cap = this:find_capability_for(current_room, 'room);
      from_room_target = typeof(from_room_cap) == FLYWEIGHT ? from_room_cap | current_room;
      try
        from_room_target:check_can_dig_from();
      except (E_PERM)
        message = $grant_utils:format_denial(current_room, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      "Remove passage via area using capability if we have one";
      area_cap = this:find_capability_for(area, 'area);
      area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
      result = area_target:remove_passage(from_room_target, target_room);
      "Report success";
      if (result)
        label_str = length(labels) > 0 ? " (" + labels:join("/") + ")" | "";
        message = "Removed passage" + label_str + " to " + tostr(target_room) + ".";
        this:inform_current($event:mk_info(this, message));
        return true;
      else
        raise(E_INVARG, "Failed to remove passage (may have already been removed).");
      endif
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
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
      from_dirs = this:_expand_direction_aliases(from_dirs);
      to_dirs = this:_expand_direction_aliases(to_dirs);
      return ['oneway -> is_oneway, 'from_dir -> from_dirs, 'to_dir -> to_dirs];
    endif
    "Single direction - split on commas for aliases";
    from_dirs = dir_spec:split(",");
    "Infer opposite direction";
    to_dirs = this:_infer_opposite_directions(from_dirs);
    !to_dirs && raise(E_INVARG, "Can't infer opposite direction for '" + dir_spec + "'. Use 'dir|returndir' syntax.");
    "Expand standard aliases";
    from_dirs = this:_expand_direction_aliases(from_dirs);
    to_dirs = this:_expand_direction_aliases(to_dirs);
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

  verb _expand_direction_aliases (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Expand common directions to include standard aliases.";
    caller == this || raise(E_PERM);
    {directions} = args;
    result = {};
    for dir in (directions)
      result = {@result, dir};
      "Add abbreviation if it exists";
      if (maphaskey(this.direction_abbrevs, dir))
        abbrev = this.direction_abbrevs[dir];
        if (abbrev && !(abbrev in result))
          result = {@result, abbrev};
        endif
      endif
    endfor
    return result;
  endverb

  verb "@rename" (any at any) owner: HACKER flags: "rd"
    "Rename an object. Usage: @rename <object> to <name[:aliases]>";
    caller == this || raise(E_PERM);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @rename <object> to <name[:aliases]>");
    endif
    try
      target_obj = $match:match_object(dobjstr, this);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!this.wizard && target_obj.owner != this)
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
      this:inform_current($event:mk_info(this, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb _do_rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to rename object with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    {target_obj, new_name, new_aliases} = args;
    target_obj:set_name_aliases(new_name, new_aliases);
  endverb

  verb "@describe" (any as any) owner: HACKER flags: "rd"
    "Set object description. Usage: @describe <object> as <description>";
    caller == this || raise(E_PERM);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @describe <object> as <description>");
    endif
    try
      target_obj = $match:match_object(dobjstr, this);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!this.wizard && target_obj.owner != this)
        raise(E_PERM, "You do not have permission to describe " + tostr(target_obj) + ".");
      endif
      new_description = iobjstr:trim();
      !new_description && raise(E_INVARG, "Description cannot be blank.");
      this:_do_describe_object(target_obj, new_description);
      obj_name = `target_obj.name ! ANY => tostr(target_obj)';
      message = "Set description of \"" + obj_name + "\" (" + tostr(target_obj) + ").";
      this:inform_current($event:mk_info(this, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb _do_describe_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set object description with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    {target_obj, new_description} = args;
    target_obj.description = new_description;
  endverb

  verb "@integrate" (any as any) owner: HACKER flags: "rd"
    "Set object integrated description. Usage: @integrate <object> as <description>";
    caller == this || raise(E_PERM);
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @integrate <object> as <description>");
    endif
    try
      target_obj = $match:match_object(dobjstr, this);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!this.wizard && target_obj.owner != this)
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
      this:inform_current($event:mk_info(this, message));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb _do_set_integrated_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal helper to set object integrated description with elevated permissions";
    caller == this || raise(E_PERM);
    set_task_perms(this);
    {target_obj, new_description} = args;
    target_obj.integrated_description = new_description;
  endverb
endobject