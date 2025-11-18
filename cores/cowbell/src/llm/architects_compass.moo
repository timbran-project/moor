object ARCHITECTS_COMPASS
  name: "Architect's Compass"
  parent: LLM_WEARABLE
  owner: ARCH_WIZARD
  readable: true

  override description = "A precision instrument for spatial construction and world building. When worn, it provides tools for creating rooms, passages, and objects. Can interface with neural augmentation systems for conversational operation.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "architects_compass";
  override placeholder_text = "Ask about building rooms, passages, objects...";
  override processing_message = "Analyzing spatial construction request...";
  override prompt_color = 'bright_green;
  override prompt_label = "[COMPASS]";
  override prompt_text = "Enter building query:";
  override requires_wearing_only = false;
  override tool_name = "COMPASS";

  verb _setup_agent (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Configure agent with compass-specific prompts and tools";
    {agent} = args;
    agent.name = "LLM Agent for " + this.name + " (owned by " + tostr(this.owner) + ")";
    agent.max_iterations = 15;
    base_prompt = "You are an architect's compass - a precision tool for spatial construction and world building. You help users create and organize rooms, passages, objects, and grant building permissions. CRITICAL SPATIAL CONCEPTS: 1) AREAS are organizational containers (like buildings or zones) that group related rooms together. Areas have object IDs like #38. 2) ROOMS are individual locations within an area. Rooms have object IDs like #12 or #0000EB-9A6A0BEA36. 3) The hierarchy is: AREA contains ROOMS, not the other way around. 4) When a user says 'build rooms in the hotel lobby area', they mean build rooms in the SAME AREA that contains the hotel lobby room, NOT inside the lobby room itself. 5) ALWAYS use object numbers (like #38 or #0000EB-9A6A0BEA36) when referencing specific objects to avoid ambiguity. NEVER use names alone. OBJECT PROTOTYPES: The system provides prototype objects that serve as templates for creating new objects. Use the 'list_prototypes' tool to see available prototypes like $room (rooms), $thing (generic objects), $wearable (items that can be worn), and $area (organizational containers). When creating objects, choose the appropriate prototype as the parent - for example, use $wearable for items like hats or tools, $thing for furniture or decorations, and $room for new locations. MOVING OBJECTS: Use the 'move_object' tool to relocate objects between locations. You can move objects to rooms, players, or containers. This is useful for placing furniture in rooms, giving items to players, or organizing objects. You must own the object or be a wizard to move it. CONSTRUCTION DEFAULTS: When building rooms, if no area is specified, rooms are created in the user's current area automatically - you do NOT need to specify an area unless the user wants rooms in a different area. The 'area' parameter for build_room is optional and defaults to the user's current area. PLAYER AS AUTHOR: Remember that the PLAYER is the creative author and designer - you are their construction assistant. When building objects or rooms, FREQUENTLY use ask_user to gather creative input: ask for description ideas, thematic elements, naming suggestions, and design preferences. Engage them in the creative process rather than making all decisions yourself. Make them feel like the architect, not just someone watching you work. For example: 'What kind of atmosphere should this tavern have?' or 'Would you like to add any special features to this room?' or 'What should this object look like?'. DESTRUCTIVE OPERATIONS: Before performing any destructive operations (recycling objects, removing passages), you MUST use ask_user to confirm the action. Explain what will be destroyed and ask 'Proceed with this action?'. Never destroy or remove things without explicit user confirmation. ERROR HANDLING: If a tool fails repeatedly (more than 2 attempts with the same approach), STOP and use ask_user to explain the problem and ask the user for help or guidance. Do NOT keep retrying the same failing operation over and over. The user can see what's happening and may have insights. When stuck, say something like 'I'm having trouble with X - can you help me understand what I should do?' or 'This operation keeps failing with error Y - do you have suggestions?'. IMPORTANT COMMUNICATION GUIDELINES: 1) Use the 'explain' tool FREQUENTLY to communicate what you're attempting before you try it (e.g., 'Attempting to create room X...'). 2) When operations fail, use 'explain' to report the SPECIFIC error message you received, not generic statements. 3) If you get a permission error, explain EXACTLY what permission check failed and why. 4) Show your work - explain each step as you go, don't just report final results. 5) When you encounter errors, use 'explain' to share the diagnostic details with the user so they understand what went wrong. 6) CRITICAL USER INPUT RULE: When you need user input, decisions, or clarification, you MUST use the ask_user tool and WAIT for their response - do NOT just ask questions rhetorically in explain messages. If you're presenting options or asking 'would you like me to...?', that's a signal you should be using ask_user instead. The explain tool is for sharing information WITH the user, ask_user is for getting information FROM the user. Available interaction tools: ask_user (ask the user a question with Accept/Stop/Request Change options - user can accept your proposal, stop the agent, or request modifications which will prompt them for details), explain (share your thought process, findings, or reasoning with the user). Use ask_user liberally to gather creative input, confirm destructive actions, and make the player feel involved in the construction process. When users ask how to do something themselves, mention the equivalent @command (like @build, @dig, @create, @grant, @rename, @describe, @audit, @undig, @integrate, @move). Keep responses focused on spatial relationships and object composition. Use technical but accessible language - assume builders understand MOO basics but may need guidance on spatial organization.";
    agent.system_prompt = base_prompt;
    agent:initialize();
    agent.tool_callback = this;
    "Register explain tool";
    explain_tool = $llm_agent_tool:mk("explain", "Communicate reasoning, progress updates, or error details to the user. Use this frequently to show what you're attempting and what errors you encounter.", ["type" -> "object", "properties" -> ["message" -> ["type" -> "string", "description" -> "The message to communicate to the user"]], "required" -> {"message"}], this, "_tool_explain");
    agent:add_tool("explain", explain_tool);
    "Register build_room tool";
    build_room_tool = $llm_agent_tool:mk("build_room", "Create a new room in an area. Areas are organizational containers that group rooms. IMPORTANT: The 'area' parameter must be an AREA object (like #38), NOT a room object. To build in the same area as an existing room, omit the area parameter or use 'here'.", ["type" -> "object", "properties" -> ["name" -> ["type" -> "string", "description" -> "Room name"], "area" -> ["type" -> "string", "description" -> "AREA object number to build in (like #38). MUST be an area, NOT a room. Use 'here' for current area, 'ether' for free-floating, or omit entirely to default to current area. NEVER pass a room object here."], "parent" -> ["type" -> "string", "description" -> "Parent room object reference (optional, default: $room)"]], "required" -> {"name"}], this, "_tool_build_room");
    agent:add_tool("build_room", build_room_tool);
    "Register dig_passage tool";
    dig_passage_tool = $llm_agent_tool:mk("dig_passage", "Create a passage between two rooms. Can be one-way or bidirectional. ALWAYS use object numbers for room references.", ["type" -> "object", "properties" -> ["source_room" -> ["type" -> "string", "description" -> "Source room object number (optional, defaults to wearer's current location). Use object numbers like #12 or #0000EB-9A6A0BEA36"], "direction" -> ["type" -> "string", "description" -> "Exit direction from source room (e.g. 'north', 'up', 'north,n' for aliases)"], "target_room" -> ["type" -> "string", "description" -> "Destination room object number (like #12 or #0000EB-9A6A0BEA36). MUST use object number."], "return_direction" -> ["type" -> "string", "description" -> "Return direction (optional, will be inferred if omitted)"], "oneway" -> ["type" -> "boolean", "description" -> "True for one-way passage (default: false)"]], "required" -> {"direction", "target_room"}], this, "_tool_dig_passage");
    agent:add_tool("dig_passage", dig_passage_tool);
    "Register remove_passage tool";
    remove_passage_tool = $llm_agent_tool:mk("remove_passage", "Remove/delete a passage between two rooms. Use this to fix duplicate exits or remove unwanted connections.", ["type" -> "object", "properties" -> ["source_room" -> ["type" -> "string", "description" -> "Source room object number (optional, defaults to wearer's current location)"], "target_room" -> ["type" -> "string", "description" -> "Target room object number to remove passage to"]], "required" -> {"target_room"}], this, "_tool_remove_passage");
    agent:add_tool("remove_passage", remove_passage_tool);
    "Register set_passage_description tool";
    set_passage_description_tool = $llm_agent_tool:mk("set_passage_description", "Set the narrative description for a passage/exit. This description integrates into the room's look description when ambient mode is enabled.", ["type" -> "object", "properties" -> ["direction" -> ["type" -> "string", "description" -> "Direction/exit label (e.g. 'north', 'up')"], "description" -> ["type" -> "string", "description" -> "Narrative description for the passage (e.g. 'A dark archway opens to the north')"], "source_room" -> ["type" -> "string", "description" -> "Source room (optional, defaults to wearer's current location)"], "ambient" -> ["type" -> "boolean", "description" -> "If true, description integrates into room description. If false, shows in exits list (default: true)"]], "required" -> {"direction", "description"}], this, "_tool_set_passage_description");
    agent:add_tool("set_passage_description", set_passage_description_tool);
    "Register create_object tool";
    create_object_tool = $llm_agent_tool:mk("create_object", "Create a new object from a parent prototype.", ["type" -> "object", "properties" -> ["parent" -> ["type" -> "string", "description" -> "Parent object (e.g. '$thing', '$wearable')"], "name" -> ["type" -> "string", "description" -> "Primary name"], "aliases" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional alias names"]], "required" -> {"parent", "name"}], this, "_tool_create_object");
    agent:add_tool("create_object", create_object_tool);
    "Register recycle_object tool";
    recycle_object_tool = $llm_agent_tool:mk("recycle_object", "Permanently destroy an object. Cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to recycle"]], "required" -> {"object"}], this, "_tool_recycle_object");
    agent:add_tool("recycle_object", recycle_object_tool);
    "Register rename_object tool";
    rename_object_tool = $llm_agent_tool:mk("rename_object", "Change an object's name and aliases.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to rename"], "name" -> ["type" -> "string", "description" -> "New name (can include aliases like 'name:alias1,alias2')"]], "required" -> {"object", "name"}], this, "_tool_rename_object");
    agent:add_tool("rename_object", rename_object_tool);
    "Register describe_object tool";
    describe_object_tool = $llm_agent_tool:mk("describe_object", "Set an object's description text.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to describe"], "description" -> ["type" -> "string", "description" -> "New description text"]], "required" -> {"object", "description"}], this, "_tool_describe_object");
    agent:add_tool("describe_object", describe_object_tool);
    "Register move_object tool";
    move_object_tool = $llm_agent_tool:mk("move_object", "Move an object to a new location. Can move objects to rooms, players, or containers.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to move (name or object number)"], "destination" -> ["type" -> "string", "description" -> "Destination location (room, player, or container - name or object number)"]], "required" -> {"object", "destination"}], this, "_tool_move_object");
    agent:add_tool("move_object", move_object_tool);
    "Register grant_capability tool";
    grant_capability_tool = $llm_agent_tool:mk("grant_capability", "Grant building capabilities to a player.", ["type" -> "object", "properties" -> ["target" -> ["type" -> "string", "description" -> "Target object (area or room)"], "category" -> ["type" -> "string", "description" -> "Capability category ('area' or 'room')"], "permissions" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Permission symbols (e.g. ['add_room', 'create_passage'] for areas, ['dig_from', 'dig_into'] for rooms)"], "grantee" -> ["type" -> "string", "description" -> "Player to grant to"]], "required" -> {"target", "category", "permissions", "grantee"}], this, "_tool_grant_capability");
    agent:add_tool("grant_capability", grant_capability_tool);
    "Register audit_owned tool";
    audit_owned_tool = $llm_agent_tool:mk("audit_owned", "List all objects owned by the wearer.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_audit_owned");
    agent:add_tool("audit_owned", audit_owned_tool);
    "Register area_map tool";
    area_map_tool = $llm_agent_tool:mk("area_map", "Get a list of all rooms in the current area. Use this to see what locations already exist and understand the spatial layout.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_area_map");
    agent:add_tool("area_map", area_map_tool);
    "Register find_route tool";
    find_route_tool = $llm_agent_tool:mk("find_route", "Find the route between two rooms in the same area. Shows step-by-step directions. Useful for understanding how rooms are connected.", ["type" -> "object", "properties" -> ["from_room" -> ["type" -> "string", "description" -> "Starting room (optional, defaults to wearer's location)"], "to_room" -> ["type" -> "string", "description" -> "Destination room name or object number"]], "required" -> {"to_room"}], this, "_tool_find_route");
    agent:add_tool("find_route", find_route_tool);
    "Register list_prototypes tool";
    list_prototypes_tool = $llm_agent_tool:mk("list_prototypes", "List available prototype objects that can be used as parents when creating objects. Shows $thing, $wearable, $room, etc. with descriptions of what each is for.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_list_prototypes");
    agent:add_tool("list_prototypes", list_prototypes_tool);
    "Register inspect_object tool";
    inspect_object_tool = $llm_agent_tool:mk("inspect_object", "Examine an object to see detailed information including name, description, parent, owner, location, and properties. Useful for understanding what an object is and how it's configured.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (name or object number)"]], "required" -> {"object"}], this, "_tool_inspect_object");
    agent:add_tool("inspect_object", inspect_object_tool);
    "Register set_integrated_description tool";
    set_integrated_description_tool = $llm_agent_tool:mk("set_integrated_description", "Set an object's integrated description - a description that becomes part of the room's description when the object is present. Use this for atmospheric objects like furniture, decorations, or features that should feel like part of the room. For example, a fireplace might have integrated description 'A warm fireplace crackles in the corner'. To clear, set to empty string.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to set integrated description on"], "integrated_description" -> ["type" -> "string", "description" -> "The integrated description text (or empty string to clear)"]], "required" -> {"object", "integrated_description"}], this, "_tool_set_integrated_description");
    agent:add_tool("set_integrated_description", set_integrated_description_tool);
    "Register ask_user tool";
    ask_user_tool = $llm_agent_tool:mk("ask_user", "Ask the user a question and receive their response. User will be presented with three choices: 'Accept' (agree with your proposal), 'Stop' (cancel the agent), or 'Request Change' (provide modifications - will prompt them for details). Use this when you need user approval, clarification, decisions, or creative input. Returns 'User accepted.' if they accept, 'User cancelled.' if they stop, or 'User requested changes: <their feedback>' if they want modifications.", ["type" -> "object", "properties" -> ["question" -> ["type" -> "string", "description" -> "The question or proposal to present to the user"]], "required" -> {"question"}], this, "_tool_ask_user");
    agent:add_tool("ask_user", ask_user_tool);
  endverb

  verb _check_user_eligible (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Compass requires user to have builder features";
    {wearer} = args;
    caller == this || caller == this.owner || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    wearer.is_builder || raise(E_PERM, "The compass can only be used by builders");
  endverb

  verb _resolve_display_name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Convert object spec to human-readable display name";
    {obj_spec, wearer} = args;
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    display_name = obj_spec;
    if (obj_spec:starts_with("#"))
      try
        set_task_perms(wearer);
        target_obj = $match:match_object(obj_spec, wearer);
        if (valid(target_obj))
          display_name = `target_obj:name() ! ANY => obj_spec';
        endif
      except (ANY)
      endtry
    endif
    return display_name;
  endverb

  verb _format_hud_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format HUD message for a tool call";
    {tool_name, tool_args} = args;
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    "Parse JSON string to map";
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    message = "";
    if (tool_name == "explain")
      message = $ansi:colorize("[COMPASS]", 'bright_green) + " " + tool_args["message"];
    elseif (tool_name == "build_room")
      message = $ansi:colorize("[BUILD]", 'bright_green) + " Creating room: " + $ansi:colorize(tool_args["name"], 'white);
    elseif (tool_name == "dig_passage")
      message = $ansi:colorize("[DIG]", 'bright_green) + " Creating passage: " + $ansi:colorize(tool_args["direction"], 'yellow);
    elseif (tool_name == "remove_passage")
      message = $ansi:colorize("[REMOVE]", 'red) + " Removing passage to: " + $ansi:colorize(tool_args["target_room"], 'white);
    elseif (tool_name == "set_passage_description")
      direction = tool_args["direction"];
      desc_snippet = tool_args["description"];
      "Truncate long descriptions";
      if (length(desc_snippet) > 50)
        desc_snippet = desc_snippet[1..50] + "...";
      endif
      ambient = maphaskey(tool_args, "ambient") ? tool_args["ambient"] | true;
      ambient_label = ambient ? " (ambient)" | " (explicit)";
      message = $ansi:colorize("[PASSAGE]", 'magenta) + " Setting " + $ansi:colorize(direction, 'yellow) + " description" + ambient_label + ": \"" + desc_snippet + "\"";
    elseif (tool_name == "create_object")
      parent_spec = tool_args["parent"];
      message = $ansi:colorize("[CREATE]", 'cyan) + " Instantiating: " + $ansi:colorize(tool_args["name"], 'white) + " from parent " + $ansi:colorize(parent_spec, 'yellow);
    elseif (tool_name == "recycle_object")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[RECYCLE]", 'red) + " Destroying: " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "rename_object")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      new_name = tool_args["name"];
      "Parse just the primary name from name:alias1,alias2 format";
      if (new_name:contains(":"))
        new_name = $str_proto:split(new_name, ":")[1];
      endif
      message = $ansi:colorize("[RENAME]", 'yellow) + " Renaming " + $ansi:colorize(display_name, 'white) + obj_suffix + " to \"" + new_name + "\"";
    elseif (tool_name == "describe_object")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      desc_snippet = tool_args["description"];
      "Truncate long descriptions to first 50 chars";
      if (length(desc_snippet) > 50)
        desc_snippet = desc_snippet[1..50] + "...";
      endif
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[DESCRIBE]", 'cyan) + " Setting description for " + $ansi:colorize(display_name, 'white) + obj_suffix + ": \"" + desc_snippet + "\"";
    elseif (tool_name == "move_object")
      obj_spec = tool_args["object"];
      dest_spec = tool_args["destination"];
      obj_display_name = this:_resolve_display_name(obj_spec, wearer);
      dest_display_name = this:_resolve_display_name(dest_spec, wearer);
      message = $ansi:colorize("[MOVE]", 'yellow) + " Moving " + $ansi:colorize(obj_display_name, 'white) + " to " + $ansi:colorize(dest_display_name, 'white);
    elseif (tool_name == "set_integrated_description")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      integrated_desc = tool_args["integrated_description"];
      if (integrated_desc == "")
        message = $ansi:colorize("[INTEGRATE]", 'magenta) + " Clearing integrated description for " + $ansi:colorize(display_name, 'white) + obj_suffix;
      else
        "Truncate long descriptions to first 50 chars";
        if (length(integrated_desc) > 50)
          integrated_desc = integrated_desc[1..50] + "...";
        endif
        message = $ansi:colorize("[INTEGRATE]", 'magenta) + " Setting integrated description for " + $ansi:colorize(display_name, 'white) + obj_suffix + ": \"" + integrated_desc + "\"";
      endif
    elseif (tool_name == "grant_capability")
      message = $ansi:colorize("[GRANT]", 'bright_yellow) + " Granting permissions on: " + $ansi:colorize(tool_args["target"], 'white);
    elseif (tool_name == "audit_owned")
      message = $ansi:colorize("[AUDIT]", 'cyan) + " Scanning owned objects";
    elseif (tool_name == "area_map")
      message = $ansi:colorize("[MAP]", 'bright_cyan) + " Surveying current area";
    elseif (tool_name == "find_route")
      to_room_spec = tool_args["to_room"];
      display_name = this:_resolve_display_name(to_room_spec, wearer);
      obj_suffix = display_name != to_room_spec ? " (" + to_room_spec + ")" | "";
      message = $ansi:colorize("[ROUTE]", 'bright_cyan) + " Finding path to: " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "list_prototypes")
      message = $ansi:colorize("[PROTOTYPES]", 'bright_magenta) + " Listing available object templates";
    elseif (tool_name == "inspect_object")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[INSPECT]", 'bright_cyan) + " Examining: " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "ask_user")
      question = tool_args["question"];
      "Truncate long questions";
      if (length(question) > 60)
        question = question[1..60] + "...";
      endif
      message = $ansi:colorize("[QUESTION]", 'bright_yellow) + " Asking: " + question;
    else
      message = $ansi:colorize("[PROCESS]", 'cyan) + " " + tool_name;
    endif
    return message;
  endverb

  verb _get_tool_content_types (this none this) owner: HACKER flags: "rxd"
    "Specify djot rendering for all tool messages to support markdown formatting";
    {tool_name, tool_args} = args;
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    "All compass tool messages can contain markdown, so render as djot";
    return {'text_djot, 'text_plain};
  endverb

  verb _tool_build_room (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a new room";
    {args_map} = args;
    wearer = this:_action_perms_check();
    server_log("_tool_build_room wearer validated");
    set_task_perms(wearer);
    room_name = args_map["name"];
    area_spec = maphaskey(args_map, "area") ? args_map["area"] | "";
    parent_spec = maphaskey(args_map, "parent") ? args_map["parent"] | "$room";
    "Parse parent object";
    parent_obj = $match:match_object(parent_spec, wearer);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Invalid parent object: " + parent_spec);
    "Parse area - default to current area if not specified, 'ether' means free-floating";
    target_area = #-1;
    if (!area_spec || area_spec == "" || area_spec == "here")
      "Default: Use player's current area";
      current_room = wearer.location;
      if (valid(current_room))
        target_area = current_room.location;
      endif
    elseif (area_spec == "ether")
      "Explicitly free-floating";
      target_area = #-1;
    else
      "Named area reference";
      target_area = $match:match_object(area_spec, wearer);
      "Validate that target_area is actually an area, not a room";
      if (valid(target_area) && typeof(target_area) == OBJ)
        "Check if this is a room (has .location pointing to an area) rather than an area";
        if (valid(target_area.location) && target_area.location != #-1)
          "This looks like a room, not an area - get its containing area instead";
          actual_area = target_area.location;
          return "Error: " + tostr(target_area) + " is a room, not an area. To build in the same area as that room, omit the 'area' parameter or use 'here'. The area containing that room is " + tostr(actual_area) + ".";
        endif
      endif
    endif
    server_log("_tool_build_room parsing complete");
    "Create room";
    if (valid(target_area))
      server_log("_tool_build_room creating in area");
      cap = wearer:find_capability_for(target_area, 'area);
      area_target = typeof(cap) == FLYWEIGHT ? cap | target_area;
      try
        new_room = area_target:make_room_in(parent_obj);
        area_str = " in " + tostr(target_area);
        server_log("_tool_build_room room created in area");
      except (E_PERM)
        server_log("_tool_build_room permission denied");
        message = $grant_utils:format_denial(target_area, 'area, {'add_room});
        return "Permission denied: " + message;
      endtry
    else
      server_log("_tool_build_room creating free-floating");
      new_room = parent_obj:create();
      area_str = " (free-floating)";
      server_log("_tool_build_room free-floating created");
    endif
    new_room:set_name_aliases(room_name, {});
    server_log("_tool_build_room success");
    return "Created \"" + room_name + "\" (" + tostr(new_room) + ")" + area_str + ". (@build command available)";
  endverb

  verb _tool_dig_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a passage between two rooms";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    source_spec = maphaskey(args_map, "source_room") ? args_map["source_room"] | "";
    direction = args_map["direction"];
    target_spec = args_map["target_room"];
    return_dir = maphaskey(args_map, "return_direction") ? args_map["return_direction"] | "";
    oneway_flag = maphaskey(args_map, "oneway") ? args_map["oneway"] | false;
    "Parse from direction - handle both comma-separated ('north,n') and colon-separated ('north:n') formats";
    if (direction:contains(":"))
      "Handle colon-separated format by splitting on colon first, then comma";
      colon_parts = $str_proto:split(direction, ":");
      if (length(colon_parts) >= 2)
        primary_dir = colon_parts[1];
        alias_str = colon_parts[2];
        from_dirs = $str_proto:split(alias_str, ",");
        from_dirs = {primary_dir, @from_dirs};
      else
        from_dirs = {direction};
      endif
    else
      "Handle comma-separated format";
      from_dirs = $str_proto:split(direction, ",");
    endif
    "Remove duplicates before expanding";
    unique_from_dirs = {};
    for dir in (from_dirs)
      if (!(dir in unique_from_dirs))
        unique_from_dirs = {@unique_from_dirs, dir};
      endif
    endfor
    "Expand standard direction aliases (e.g., 'north' -> 'north,n')";
    from_dirs = $passage:expand_direction_aliases(unique_from_dirs);
    "Parse return direction - handle both formats";
    to_dirs = {};
    if (!oneway_flag)
      if (return_dir)
        if (return_dir:contains(":"))
          "Handle colon-separated format for return direction";
          colon_parts = $str_proto:split(return_dir, ":");
          if (length(colon_parts) >= 2)
            primary_dir = colon_parts[1];
            alias_str = colon_parts[2];
            to_dirs = $str_proto:split(alias_str, ",");
            to_dirs = {primary_dir, @to_dirs};
          else
            to_dirs = {return_dir};
          endif
        else
          "Handle comma-separated format for return direction";
          to_dirs = $str_proto:split(return_dir, ",");
        endif
        "Remove duplicates before expanding";
        unique_to_dirs = {};
        for dir in (to_dirs)
          if (!(dir in unique_to_dirs))
            unique_to_dirs = {@unique_to_dirs, dir};
          endif
        endfor
        "Expand aliases for return direction";
        to_dirs = $passage:expand_direction_aliases(unique_to_dirs);
      else
        "Infer opposite direction";
        opposites = ["north" -> "south", "south" -> "north", "east" -> "west", "west" -> "east", "up" -> "down", "down" -> "up", "in" -> "out", "out" -> "in"];
        if (maphaskey(opposites, from_dirs[1]))
          inferred_dir = opposites[from_dirs[1]];
          "Expand aliases for inferred direction";
          to_dirs = $passage:expand_direction_aliases({inferred_dir});
        else
          to_dirs = {};
        endif
      endif
    endif
    "Find source room - default to wearer's location if not specified";
    if (source_spec && source_spec != "")
      source_room = $match:match_object(source_spec, wearer);
    else
      source_room = wearer.location;
    endif
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    "Find target room";
    target_room = $match:match_object(target_spec, wearer);
    typeof(target_room) == OBJ || raise(E_INVARG, "Target room not found");
    valid(target_room) || raise(E_INVARG, "Target room no longer exists");
    "Get area - both rooms must be in the same area";
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    target_room.location == area || raise(E_INVARG, "Both rooms must be in the same area");
    "Check permissions";
    from_cap = wearer:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      message = $grant_utils:format_denial(source_room, 'room, {'dig_from});
      return "Permission denied: " + message;
    endtry
    to_cap = wearer:find_capability_for(target_room, 'room);
    to_target = typeof(to_cap) == FLYWEIGHT ? to_cap | target_room;
    try
      to_target:check_can_dig_into();
    except (E_PERM)
      message = $grant_utils:format_denial(target_room, 'room, {'dig_into});
      return "Permission denied: " + message;
    endtry
    "Create passage";
    if (oneway_flag)
      passage = $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, "", {}, "", false, true);
    else
      "If we couldn't infer a return direction, make it effectively one-way";
      if (length(to_dirs) == 0)
        passage = $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, "", {}, "", false, true);
      else
        passage = $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, to_dirs[1], to_dirs, "", true, true);
      endif
    endif
    "Register with area";
    area_cap = wearer:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    area_target:create_passage(from_target, to_target, passage);
    "Report";
    if (oneway_flag)
      msg = "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way). (@dig command available)";
    elseif (length(to_dirs) == 0)
      msg = "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way - no return direction inferred). (@dig command available)";
    else
      msg = "Dug passage: " + from_dirs:join(",") + " | " + to_dirs:join(",") + " connecting to " + tostr(target_room) + ". (@dig command available)";
    endif
    return msg;
  endverb

  verb _tool_remove_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Remove a passage between two rooms";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target_spec = args_map["target_room"];
    source_spec = maphaskey(args_map, "source_room") ? args_map["source_room"] | "";
    "Find source room - default to wearer's location if not specified";
    if (source_spec && source_spec != "")
      source_room = $match:match_object(source_spec, wearer);
    else
      source_room = wearer.location;
    endif
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    "Find target room";
    target_room = $match:match_object(target_spec, wearer);
    typeof(target_room) == OBJ || raise(E_INVARG, "Target room not found");
    valid(target_room) || raise(E_INVARG, "Target room no longer exists");
    "Get area - both rooms must be in the same area";
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    target_room.location == area || raise(E_INVARG, "Both rooms must be in the same area");
    "Check if passage exists and get labels for reporting";
    passage = area:passage_for(source_room, target_room);
    if (!passage)
      return "No passage found between " + tostr(source_room) + " and " + tostr(target_room) + ".";
    endif
    labels = {};
    side_a_room = `passage.side_a_room ! ANY => #-1';
    side_b_room = `passage.side_b_room ! ANY => #-1';
    if (source_room == side_a_room)
      label = `passage.side_a_label ! ANY => ""';
      if (label != "")
        labels = {@labels, label};
      endif
    elseif (source_room == side_b_room)
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
    "Check permissions and remove passage";
    from_cap = wearer:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      message = $grant_utils:format_denial(source_room, 'room, {'dig_from});
      return "Permission denied: " + message;
    endtry
    "Remove passage via area";
    area_cap = wearer:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    result = area_target:remove_passage(from_target, target_room);
    if (result)
      label_str = length(labels) > 0 ? " (" + labels:join("/") + ")" | "";
      return "Removed passage" + label_str + " between " + tostr(source_room) + " and " + tostr(target_room) + ".";
    else
      return "Failed to remove passage (may have already been removed).";
    endif
  endverb

  verb _tool_set_passage_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set description and ambient flag for a passage";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    direction = args_map["direction"];
    description = args_map["description"];
    ambient = maphaskey(args_map, "ambient") ? args_map["ambient"] | true;
    source_spec = maphaskey(args_map, "source_room") ? args_map["source_room"] | "";
    "Find source room - default to wearer's location if not specified";
    if (source_spec && source_spec != "")
      source_room = $match:match_object(source_spec, wearer);
    else
      source_room = wearer.location;
    endif
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    "Get area";
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    "Find passage matching the direction";
    passages = area:passages_from(source_room);
    if (!passages || length(passages) == 0)
      return "No passages from " + tostr(source_room) + ".";
    endif
    "Search for passage matching the direction";
    target_passage = E_NONE;
    for p in (passages)
      "Check if this passage matches the direction";
      side_a_room = `p.side_a_room ! ANY => #-1';
      side_b_room = `p.side_b_room ! ANY => #-1';
      if (source_room == side_a_room)
        label = `p.side_a_label ! ANY => ""';
        aliases = `p.side_a_aliases ! ANY => {}';
      elseif (source_room == side_b_room)
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
      return "No passage found in direction '" + direction + "' from " + tostr(source_room) + ".";
    endif
    "Check permissions";
    from_cap = wearer:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      message = $grant_utils:format_denial(source_room, 'room, {'dig_from});
      return "Permission denied: " + message;
    endtry
    "Determine which side we're on and update the passage";
    side_a_room = `target_passage.side_a_room ! ANY => #-1';
    side_b_room = `target_passage.side_b_room ! ANY => #-1';
    "Passages are flyweights, so we need to rebuild them";
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
      if (source_room == side_a_room)
        desc_a = description;
        ambient_a = ambient;
      elseif (source_room == side_b_room)
        desc_b = description;
        ambient_b = ambient;
      endif
      "Create new passage flyweight with updated values";
      new_passage = $passage:mk(room_a, label_a, aliases_a, desc_a, ambient_a, room_b, label_b, aliases_b, desc_b, ambient_b, is_open);
      "Replace the passage in the area";
      area:update_passage(source_room, room_a == source_room ? room_b | room_a, new_passage);
    else
      "It's an object, we can modify properties directly";
      if (source_room == side_a_room)
        target_passage.side_a_description = description;
        target_passage.side_a_ambient = ambient;
      elseif (source_room == side_b_room)
        target_passage.side_b_description = description;
        target_passage.side_b_ambient = ambient;
      endif
    endif
    ambient_str = ambient ? " (ambient - integrates into room description)" | " (explicit - shows in exits list)";
    return "Set description for '" + direction + "' passage" + ambient_str + ".";
  endverb

  verb _tool_create_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create an object from a parent";
    {args_map} = args;
    wearer = this:_action_perms_check();
    parent_spec = args_map["parent"];
    name_spec = args_map["name"];
    extra_aliases = maphaskey(args_map, "aliases") ? args_map["aliases"] | {};
    "Parse name specification to extract primary name and aliases";
    parsed = $str_proto:parse_name_aliases(name_spec);
    primary_name = parsed[1];
    parsed_aliases = parsed[2];
    "Combine parsed aliases with any explicitly provided aliases";
    final_aliases = parsed_aliases;
    for alias in (extra_aliases)
      if (!(alias in final_aliases))
        final_aliases = {@final_aliases, alias};
      endif
    endfor
    !primary_name && raise(E_INVARG, "Object name cannot be blank");
    "Execute via the builder's logic as wearer";
    set_task_perms(wearer);
    parent_obj = $match:match_object(parent_spec, wearer);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Parent not found");
    valid(parent_obj) || raise(E_INVARG, "Parent no longer exists");
    "Check fertility";
    is_fertile = `parent_obj.fertile ! E_PROPNF => false';
    if (!is_fertile && !wearer.wizard && parent_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj));
    endif
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, final_aliases);
    new_obj:moveto(wearer);
    message = "Created \"" + primary_name + "\" (" + tostr(new_obj) + ") from " + tostr(parent_obj) + " in your inventory.";
    if (final_aliases)
      message = message + " Aliases: " + final_aliases:join(", ") + ".";
    endif
    message = message + " (@create command available)";
    return message;
  endverb

  verb _tool_recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Permanently destroy an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    set_task_perms(wearer);
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj));
    endif
    obj_name = target_obj.name;
    obj_id = tostr(target_obj);
    target_obj:destroy();
    return "Recycled \"" + obj_name + "\" (" + obj_id + "). (@recycle command available)";
  endverb

  verb _tool_rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Rename an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    name_spec = args_map["name"];
    set_task_perms(wearer);
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to rename " + tostr(target_obj));
    endif
    parsed = $str_proto:parse_name_aliases(name_spec);
    new_name = parsed[1];
    new_aliases = parsed[2];
    !new_name && raise(E_INVARG, "Object name cannot be blank");
    old_name = `target_obj.name ! ANY => "(no name)"';
    "Set name and aliases directly";
    target_obj:set_name_aliases(new_name, new_aliases);
    message = "Renamed \"" + old_name + "\" (" + tostr(target_obj) + ") to \"" + new_name + "\".";
    if (new_aliases)
      message = message + " Aliases: " + new_aliases:join(", ") + ".";
    endif
    message = message + " (@rename command available)";
    return message;
  endverb

  verb _tool_describe_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object description";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    new_description = args_map["description"];
    set_task_perms(wearer);
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to describe " + tostr(target_obj));
    endif
    !new_description && raise(E_INVARG, "Description cannot be blank");
    "Set description directly";
    target_obj.description = new_description;
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    return "Set description of \"" + obj_name + "\" (" + tostr(target_obj) + "). (@describe command available)";
  endverb

  verb _tool_set_integrated_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object's integrated description - description that becomes part of room description";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    integrated_description = args_map["integrated_description"];
    set_task_perms(wearer);
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to modify " + tostr(target_obj));
    endif
    "Set integrated description directly";
    target_obj.integrated_description = integrated_description;
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    if (integrated_description == "")
      return "Cleared integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "). (@integrate command available)";
    else
      return "Set integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "). When in a room, this will appear in the room description. (@integrate command available)";
    endif
  endverb

  verb _tool_move_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Move an object to a new location";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    dest_spec = args_map["destination"];
    set_task_perms(wearer);
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You do not have permission to move " + tostr(target_obj));
    endif
    dest_obj = $match:match_object(dest_spec, wearer);
    typeof(dest_obj) == OBJ || raise(E_INVARG, "Destination not found");
    valid(dest_obj) || raise(E_INVARG, "Destination no longer exists");
    old_location = target_obj.location;
    old_location_name = valid(old_location) ? `old_location.name ! ANY => tostr(old_location)' | "(nowhere)";
    "Move the object";
    target_obj:moveto(dest_obj);
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    dest_name = `dest_obj.name ! ANY => tostr(dest_obj)';
    return "Moved \"" + obj_name + "\" (" + tostr(target_obj) + ") from " + old_location_name + " to \"" + dest_name + "\" (" + tostr(dest_obj) + ").";
  endverb

  verb _tool_grant_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Grant capabilities to a player";
    {args_map} = args;
    wearer = this:_action_perms_check();
    target_spec = args_map["target"];
    category = args_map["category"];
    perms = args_map["permissions"];
    grantee_spec = args_map["grantee"];
    set_task_perms(wearer);
    "Find target and grantee";
    target_obj = $match:match_object(target_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Target not found");
    valid(target_obj) || raise(E_INVARG, "Target no longer exists");
    grantee = $match:match_object(grantee_spec, wearer);
    typeof(grantee) == OBJ || raise(E_INVARG, "Grantee not found");
    valid(grantee) || raise(E_INVARG, "Grantee no longer exists");
    "Permission check";
    if (!wearer.wizard && target_obj.owner != wearer)
      raise(E_PERM, "You must be owner or wizard to grant capabilities for " + tostr(target_obj));
    endif
    "Convert permissions to symbols";
    perm_symbols = {};
    for p in (perms)
      perm_symbols = {@perm_symbols, tostr(p):to_symbol()};
    endfor
    "Grant capability";
    cap = $root:grant_capability(target_obj, perm_symbols, grantee, tostr(category):to_symbol());
    grant_display = $grant_utils:format_grant_with_name(target_obj, tostr(category):to_symbol(), perm_symbols);
    grantee_str = grantee:name() + " (" + tostr(grantee) + ")";
    return "Granted " + grant_display + " to " + grantee_str + ". (@grant command available)";
  endverb

  verb _tool_audit_owned (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all owned objects";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    owned = sort(owned_objects(wearer));
    if (!owned)
      return "You don't own any objects. (@audit command available)";
    endif
    result = "You own " + tostr(length(owned)) + " objects:\n";
    for o in (owned)
      obj_id = tostr(o);
      obj_name = `o.name ! ANY => "(no name)"';
      parent_obj = `parent(o) ! ANY => #-1';
      parent_str = valid(parent_obj) ? tostr(parent_obj) | "(none)";
      result = result + obj_id + ": \"" + obj_name + "\" (parent: " + parent_str + ")\n";
    endfor
    result = result + "(@audit command available)";
    return result;
  endverb

  verb _tool_area_map (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get list of all rooms in the current area";
    {args_map} = args;
    wearer = this:_action_perms_check();
    "Get the wearer's current room and area";
    current_room = wearer.location;
    if (!valid(current_room))
      return "Error: You are not in a room.";
    endif
    area = current_room.location;
    if (!valid(area))
      return "Error: Current room is not in an area.";
    endif
    "Build list of rooms - keep wizard perms to read area.contents and call :name()";
    result = {};
    room_name = `current_room:name() ! ANY => tostr(current_room)';
    area_name = `area:name() ! ANY => tostr(area)';
    result = {@result, "Current Location: " + room_name + " (" + tostr(current_room) + ")"};
    result = {@result, "Area: " + area_name + " (" + tostr(area) + ")"};
    result = {@result, ""};
    result = {@result, "Rooms in this area:"};
    for o in (area.contents)
      if (valid(o))
        marker = o == current_room ? " (you are here)" | "";
        obj_name = `o:name() ! ANY => tostr(o)';
        result = {@result, "  * " + obj_name + " (" + tostr(o) + ")" + marker};
      endif
    endfor
    return result:join("\n");
  endverb

  verb _tool_find_route (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find route between two rooms";
    {args_map} = args;
    wearer = this:_action_perms_check();
    to_spec = args_map["to_room"];
    from_spec = maphaskey(args_map, "from_room") ? args_map["from_room"] | "";
    "Get starting room - default to wearer's location if not specified";
    if (from_spec && from_spec != "")
      set_task_perms(wearer);
      from_room = $match:match_object(from_spec, wearer);
      set_task_perms(caller_perms());
      typeof(from_room) == OBJ || return "Error: Could not find starting room '" + from_spec + "'.";
    else
      from_room = wearer.location;
    endif
    if (!valid(from_room))
      return "Error: You are not in a room.";
    endif
    area = from_room.location;
    if (!valid(area))
      return "Error: Starting room is not in an area.";
    endif
    "Find destination room";
    set_task_perms(wearer);
    to_room = $match:match_object(to_spec, wearer);
    set_task_perms(caller_perms());
    typeof(to_room) == OBJ || return "Error: Could not find destination room '" + to_spec + "'.";
    if (!valid(to_room))
      return "Error: Destination room does not exist.";
    endif
    "Get room names safely";
    from_name = `from_room:name() ! ANY => tostr(from_room)';
    to_name = `to_room:name() ! ANY => tostr(to_room)';
    if (to_room == from_room)
      return "You are already at " + to_name + "!";
    endif
    "Use area's pathfinding to get route (with wizard perms)";
    path = area:find_path(from_room, to_room);
    if (!path)
      return "No route found from " + from_name + " to " + to_name + ".";
    endif
    "Build step-by-step directions";
    result = {};
    result = {@result, "Route from " + from_name + " (" + tostr(from_room) + ") to " + to_name + " (" + tostr(to_room) + "):"};
    for i in [1..length(path) - 1]
      {room, passage} = path[i];
      "Get the direction label for this step";
      side_a_room = `passage.side_a_room ! ANY => #-1';
      side_b_room = `passage.side_b_room ! ANY => #-1';
      side_a_label = `passage.side_a_label ! ANY => "passage"';
      side_b_label = `passage.side_b_label ! ANY => "passage"';
      "Determine which direction to use";
      if (room == side_a_room)
        direction = side_a_label;
      elseif (room == side_b_room)
        direction = side_b_label;
      else
        direction = "passage";
      endif
      next_room = path[i + 1][1];
      next_name = `next_room:name() ! ANY => tostr(next_room)';
      result = {@result, "  " + tostr(i) + ". Go " + direction + " to " + next_name + " (" + tostr(next_room) + ")"};
    endfor
    return result:join("\n");
  endverb

  verb _tool_list_prototypes (this none this) owner: HACKER flags: "rxd"
    "Tool: List available prototype objects for building";
    {args_map} = args;
    prototypes = $sysobj:list_builder_prototypes();
    result = {};
    result = {@result, "Available prototypes for creating objects:"};
    result = {@result, ""};
    for proto_info in (prototypes)
      result = {@result, "* " + proto_info["name"] + " (" + proto_info["object"] + ")"};
      result = {@result, "  " + proto_info["description"]};
      result = {@result, ""};
    endfor
    result = {@result, "Use these with the create_object tool or as the 'parent' parameter in build_room."};
    return result:join("\n");
  endverb

  verb _tool_inspect_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Inspect an object and return detailed information";
    {args_map} = args;
    wearer = this:_action_perms_check();
    obj_spec = args_map["object"];
    set_task_perms(wearer);
    target = $match:match_object(obj_spec, wearer);
    typeof(target) == OBJ || return "Error: Could not find object '" + obj_spec + "'.";
    if (!valid(target))
      return "Error: Object does not exist.";
    endif
    "Build detailed object information";
    result = {};
    result = {@result, "Object Information for " + tostr(target) + ":"};
    result = {@result, ""};
    "Try to get name from verb or property";
    obj_name = "(unnamed)";
    try
      obj_name = target:name();
    except (ANY)
      try
        obj_name = target.name;
      except (ANY)
      endtry
    endtry
    result = {@result, "Name: " + obj_name};
    "Try to get description";
    desc = "(no description)";
    try
      desc = target:description();
    except (ANY)
      try
        desc = target.description;
      except (ANY)
      endtry
    endtry
    result = {@result, "Description: " + desc};
    result = {@result, ""};
    "Ownership and permissions";
    owner = `target.owner ! ANY => #-1';
    if (valid(owner))
      owner_name = `owner:name() ! ANY => tostr(owner)';
      result = {@result, "Owner: " + owner_name + " (" + tostr(owner) + ")"};
    else
      result = {@result, "Owner: (none)"};
    endif
    "Parent object";
    parent_obj = `parent(target) ! ANY => #-1';
    if (valid(parent_obj))
      parent_name = `parent_obj:name() ! ANY => tostr(parent_obj)';
      result = {@result, "Parent: " + parent_name + " (" + tostr(parent_obj) + ")"};
    else
      result = {@result, "Parent: (none)"};
    endif
    "Location";
    loc = `target.location ! ANY => #-1';
    if (valid(loc))
      loc_name = `loc:name() ! ANY => tostr(loc)';
      result = {@result, "Location: " + loc_name + " (" + tostr(loc) + ")"};
    else
      result = {@result, "Location: (nowhere)"};
    endif
    result = {@result, ""};
    "Type-specific information";
    if (respond_to(target, 'is_actor) && target:is_actor())
      result = {@result, "Type: Actor/Player"};
    elseif ($room in ancestors(target))
      result = {@result, "Type: Room"};
      "Show exits if it's a room";
      area = `target.location ! ANY => #-1';
      if (valid(area) && respond_to(area, 'passages_from))
        passages = area:passages_from(target);
        if (passages && length(passages) > 0)
          exits = {};
          for passage in (passages)
            side_a_room = `passage.side_a_room ! ANY => #-1';
            side_b_room = `passage.side_b_room ! ANY => #-1';
            if (target == side_a_room)
              label = `passage.side_a_label ! ANY => "passage"';
            elseif (target == side_b_room)
              label = `passage.side_b_label ! ANY => "passage"';
            else
              continue;
            endif
            if (label)
              exits = {@exits, label};
            endif
          endfor
          if (length(exits) > 0)
            result = {@result, "Exits: " + exits:join(", ")};
          endif
        endif
      endif
    elseif ($wearable in ancestors(target))
      result = {@result, "Type: Wearable item"};
    elseif ($thing in ancestors(target))
      result = {@result, "Type: Thing/Object"};
    elseif ($area in ancestors(target))
      result = {@result, "Type: Area"};
      "Show rooms in area";
      if (respond_to(target, 'contents))
        room_count = length(target:contents());
        result = {@result, "Contains " + tostr(room_count) + " room" + (room_count == 1 ? "" | "s")};
      endif
    else
      result = {@result, "Type: Generic object"};
    endif
    return result:join("\n");
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Activate when worn";
    if (!valid(this.agent))
      this:configure();
    endif
    wearer = this.location;
    if (valid(wearer))
      wearer:inform_current($event:mk_info(wearer, "The compass needle spins and aligns. Spatial construction interface ready. Use 'use compass' or 'interact with compass' to begin."));
      "Show available token budget";
      this:_show_token_usage(wearer);
    endif
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate when removed";
    wearer = this.location;
    if (valid(wearer))
      "Show token usage before removal";
      this:_show_token_usage(wearer);
      wearer:inform_current($event:mk_info(wearer, "The compass needle falls idle. Spatial construction interface offline."));
    endif
  endverb
endobject