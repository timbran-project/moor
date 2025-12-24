object AGENT_BUILDING_TOOLS
  name: "Agent Building Tools"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property guide (owner: ARCH_WIZARD, flags: "rc") = "SPATIAL CONCEPTS:\n\n1) AREAS are organizational containers (like buildings or zones) that group related rooms together. Areas have object IDs like #38.\n\n2) ROOMS are individual locations within an area. Rooms have object IDs like #12 or #0000EB-9A6A0BEA36.\n\n3) The hierarchy is: AREA contains ROOMS, not the other way around.\n\n4) When a user says 'build rooms in the hotel lobby area', they mean build rooms in the SAME AREA that contains the hotel lobby room, NOT inside the lobby room itself.\n\n5) ALWAYS use object numbers (like #38 or #0000EB-9A6A0BEA36) when referencing specific objects to avoid ambiguity. NEVER use names alone.\n\nOBJECT PROTOTYPES:\n\nThe system provides prototype objects that serve as templates for creating new objects. Use the 'list_prototypes' tool to see available prototypes like $room (rooms), $thing (generic objects), $wearable (items that can be worn), and $area (organizational containers). When creating objects, choose the appropriate prototype as the parent - for example, use $wearable for items like hats or tools, $thing for furniture or decorations, and $room for new locations.\n\nMOVING OBJECTS:\n\nUse the 'move_object' tool to relocate objects between locations. You can move objects to rooms, players, or containers. This is useful for placing furniture in rooms, giving items to players, or organizing objects. You must own the object or be a wizard to move it.\n\nRULE ENGINE FOR OBJECT BEHAVIOR:\n\nThe system provides a Datalog-style rule engine that lets builders configure object behavior WITHOUT writing MOO code. Rules are declarative logic expressions used for locks, puzzles, quest triggers, and conditional behaviors.\n\nExample: 'Key is(\"golden key\")?' finds an object matching \"golden key\" and binds it to variable Key.\n\nRules can chain relationships transitively: 'Child parent(Parent)? AND Parent parent(Grandparent)?' walks up a family tree.\n\nVariables (capitalized like Key, Item, Accessor) unify with values returned by fact predicates. The engine supports AND, OR, and bounded NOT operators.\n\nCommon use cases: container lock_rule/unlock_rule for key-based locks, puzzle objects with solution_rule checking conditions, doors with can_pass rules, quest items with requirements.\n\nUse list_rules to see existing rules on objects, set_rule to configure behavior, and doc_lookup(\"$rule_engine\") to read comprehensive documentation.\n\nCONSTRUCTION DEFAULTS:\n\nWhen building rooms, if no area is specified, rooms are created in the user's current area automatically - you do NOT need to specify an area unless the user wants rooms in a different area. The 'area' parameter for build_room is optional and defaults to the user's current area.\n\nSUBSTITUTION TEMPLATES:\n\nUse $sub/$sub_utils syntax for dynamic messages: {n/nc} actor, {d/dc} dobj, {i}, {t}, {l}; articles {a d}/{an d}/{the d} render article + noun; pronouns {s/o/p/q/r} with _dobj/_iobj variants; self alternation {you|they} auto-picks perspective; verbs conjugate with be/have/look.\n\nALWAYS use self-alternation for verbs that differ by person (e.g., {set|sets}, {place|places}) so the actor sees second-person grammar.\n\nBefore crafting templates, use doc_lookup(\"$sub_utils\") to recall article rules and binding variants.";

  override description = "Shared tool definitions and handlers for AI agents that build and manipulate the world. Used by both in-world wearables (like $architects_compass) and external MCP agents.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "agent_building_tools";

  verb get_tools (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return list of tool definitions for building/manipulation. All tools point to $agent_building_tools.";
    target_obj = this;
    tools = {};
    "Build/manipulation tools";
    tools = {@tools, $llm_agent_tool:mk("build_room", "Create a new room in an area. Areas are organizational containers that group rooms. IMPORTANT: The 'area' parameter must be an AREA object (like #38), NOT a room object. To build in the same area as an existing room, omit the area parameter or use 'here'.", ["type" -> "object", "properties" -> ["name" -> ["type" -> "string", "description" -> "Room name"], "area" -> ["type" -> "string", "description" -> "AREA object number to build in (like #38). MUST be an area, NOT a room. Use 'here' for current area, 'ether' for free-floating, or omit entirely to default to current area. NEVER pass a room object here."], "parent" -> ["type" -> "string", "description" -> "Parent room object reference (optional, default: $room)"]], "required" -> {"name"}], target_obj, "build_room")};
    tools = {@tools, $llm_agent_tool:mk("dig_passage", "Create a passage between two rooms. Can be one-way or bidirectional. ALWAYS use object numbers for room references.", ["type" -> "object", "properties" -> ["source_room" -> ["type" -> "string", "description" -> "Source room object number (optional, defaults to actor's current location). Use object numbers like #12 or #0000EB-9A6A0BEA36"], "direction" -> ["type" -> "string", "description" -> "Exit direction from source room (e.g. 'north', 'up', 'north,n' for aliases)"], "target_room" -> ["type" -> "string", "description" -> "Destination room object number (like #12 or #0000EB-9A6A0BEA36). MUST use object number."], "return_direction" -> ["type" -> "string", "description" -> "Return direction (optional, will be inferred if omitted)"], "oneway" -> ["type" -> "boolean", "description" -> "True for one-way passage (default: false)"]], "required" -> {"direction", "target_room"}], target_obj, "dig_passage")};
    tools = {@tools, $llm_agent_tool:mk("remove_passage", "Remove/delete a passage between two rooms. Use this to fix duplicate exits or remove unwanted connections.", ["type" -> "object", "properties" -> ["source_room" -> ["type" -> "string", "description" -> "Source room object number (optional, defaults to actor's current location)"], "target_room" -> ["type" -> "string", "description" -> "Target room object number to remove passage to"]], "required" -> {"target_room"}], target_obj, "remove_passage")};
    tools = {@tools, $llm_agent_tool:mk("set_passage_description", "Set the narrative description for a passage/exit. This description integrates into the room's look description when ambient mode is enabled.", ["type" -> "object", "properties" -> ["direction" -> ["type" -> "string", "description" -> "Direction/exit label (e.g. 'north', 'up')"], "description" -> ["type" -> "string", "description" -> "Narrative description for the passage (e.g. 'A dark archway opens to the north')"], "source_room" -> ["type" -> "string", "description" -> "Source room (optional, defaults to actor's current location)"], "ambient" -> ["type" -> "boolean", "description" -> "If true, description integrates into room description. If false, shows in exits list (default: true)"]], "required" -> {"direction", "description"}], target_obj, "set_passage_description")};
    tools = {@tools, $llm_agent_tool:mk("create_object", "Create a new object from a parent prototype.", ["type" -> "object", "properties" -> ["parent" -> ["type" -> "string", "description" -> "Parent object (e.g. '$thing', '$wearable')"], "name" -> ["type" -> "string", "description" -> "Primary name"], "aliases" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional alias names"]], "required" -> {"parent", "name"}], target_obj, "create_object")};
    tools = {@tools, $llm_agent_tool:mk("recycle_object", "Permanently destroy an object. Cannot be undone.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to recycle"]], "required" -> {"object"}], target_obj, "recycle_object")};
    tools = {@tools, $llm_agent_tool:mk("rename_object", "Change an object's name and aliases.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to rename"], "name" -> ["type" -> "string", "description" -> "New name (can include aliases like 'name:alias1,alias2')"]], "required" -> {"object", "name"}], target_obj, "rename_object")};
    tools = {@tools, $llm_agent_tool:mk("describe_object", "Set an object's description text.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to describe"], "description" -> ["type" -> "string", "description" -> "New description text"]], "required" -> {"object", "description"}], target_obj, "describe_object")};
    tools = {@tools, $llm_agent_tool:mk("move_object", "Move an object to a new location. Can move objects to rooms, players, or containers.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to move (name or object number)"], "destination" -> ["type" -> "string", "description" -> "Destination location (room, player, or container - name or object number)"]], "required" -> {"object", "destination"}], target_obj, "move_object")};
    tools = {@tools, $llm_agent_tool:mk("set_integrated_description", "Set an object's integrated description - a description that becomes part of the room's description when the object is present. Use this for atmospheric objects like furniture, decorations, or features that should feel like part of the room.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to set integrated description on"], "integrated_description" -> ["type" -> "string", "description" -> "The integrated description text (or empty string to clear)"]], "required" -> {"object", "integrated_description"}], target_obj, "set_integrated_description")};
    tools = {@tools, $llm_agent_tool:mk("grant_capability", "Grant building capabilities to a player.", ["type" -> "object", "properties" -> ["target" -> ["type" -> "string", "description" -> "Target object (area or room)"], "category" -> ["type" -> "string", "description" -> "Capability category ('area' or 'room')"], "permissions" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Permission symbols (e.g. ['add_room', 'create_passage'] for areas, ['dig_from', 'dig_into'] for rooms)"], "grantee" -> ["type" -> "string", "description" -> "Player to grant to"]], "required" -> {"target", "category", "permissions", "grantee"}], target_obj, "grant_capability")};
    "Analysis/inspection tools";
    tools = {@tools, $llm_agent_tool:mk("audit_owned", "List all objects owned by the actor.", ["type" -> "object", "properties" -> [], "required" -> {}], target_obj, "audit_owned")};
    tools = {@tools, $llm_agent_tool:mk("area_map", "Get a list of all rooms in the current area. Use this to see what locations already exist and understand the spatial layout.", ["type" -> "object", "properties" -> [], "required" -> {}], target_obj, "area_map")};
    tools = {@tools, $llm_agent_tool:mk("find_route", "Find the route between two rooms in the same area. Shows step-by-step directions. Useful for understanding how rooms are connected.", ["type" -> "object", "properties" -> ["from_room" -> ["type" -> "string", "description" -> "Starting room (optional, defaults to actor's location)"], "to_room" -> ["type" -> "string", "description" -> "Destination room name or object number"]], "required" -> {"to_room"}], target_obj, "find_route")};
    tools = {@tools, $llm_agent_tool:mk("list_prototypes", "List available prototype objects that can be used as parents when creating objects. Shows $thing, $wearable, $room, etc. with descriptions of what each is for.", ["type" -> "object", "properties" -> [], "required" -> {}], target_obj, "list_prototypes")};
    tools = {@tools, $llm_agent_tool:mk("inspect_object", "Examine an object to see detailed information including name, description, parent, owner, location, and properties.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (name or object number)"]], "required" -> {"object"}], target_obj, "inspect_object")};
    "Rule tools";
    tools = {@tools, $llm_agent_tool:mk("list_rules", "List all rule properties (*_rule) on an object and their current expressions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#10', '$container', 'chest')"]], "required" -> {"object"}], target_obj, "list_rules")};
    tools = {@tools, $llm_agent_tool:mk("set_rule", "Set an access control rule on an object property. Rules are logical expressions like 'Key is(\"golden key\")?' or 'NOT This is_locked()?'.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Rule property name (must end with _rule, e.g., 'lock_rule')"], "expression" -> ["type" -> "string", "description" -> "Rule expression using Datalog syntax"]], "required" -> {"object", "property", "expression"}], target_obj, "set_rule")};
    tools = {@tools, $llm_agent_tool:mk("show_rule", "Display the current expression for a specific rule property.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Rule property name (must end with _rule)"]], "required" -> {"object", "property"}], target_obj, "show_rule")};
    tools = {@tools, $llm_agent_tool:mk("test_rule", "Test a rule expression with specific variable bindings to see if it evaluates successfully.", ["type" -> "object", "properties" -> ["expression" -> ["type" -> "string", "description" -> "Rule expression to test (e.g., 'Key is(\"golden key\")?')"], "bindings" -> ["type" -> "object", "description" -> "Variable bindings as key-value pairs (e.g., {\"This\": \"#123\", \"Accessor\": \"#5\", \"Key\": \"#456\"})"]], "required" -> {"expression", "bindings"}], target_obj, "test_rule")};
    "Reaction tools";
    tools = {@tools, $llm_agent_tool:mk("list_reactions", "List all reactions on an object with detailed information including triggers, conditions, effects, and enabled status.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#12', 'here', 'cupboard')"]], "required" -> {"object"}], target_obj, "list_reactions")};
    tools = {@tools, $llm_agent_tool:mk("add_reaction", "Add a reaction to an object. Example: trigger=on_open, when=0, effects={{'announce, \"Door opens!\"}}", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Target object (name or #id)"], "property_name" -> ["type" -> "string", "description" -> "Must end with _reaction (e.g., on_open_reaction)"], "trigger" -> ["type" -> "string", "description" -> "Event name WITHOUT quotes: on_open, on_close, on_take, on_drop, on_pet, on_touch, on_use"], "when" -> ["type" -> "string", "description" -> "Use 0 for always. Or rule like: This is(\"locked\")?"], "effects" -> ["type" -> "string", "description" -> "List: {{'announce, \"msg\"}} or {{'set, 'prop, value}, {'announce, \"msg\"}}"]], "required" -> {"object", "property_name", "trigger", "when", "effects"}], target_obj, "add_reaction")};
    tools = {@tools, $llm_agent_tool:mk("set_reaction_enabled", "Enable or disable a reaction by property name.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object containing the reaction"], "property_name" -> ["type" -> "string", "description" -> "Reaction property name (must end with '_reaction')"], "enabled" -> ["type" -> "boolean", "description" -> "true to enable, false to disable"]], "required" -> {"object", "property_name", "enabled"}], target_obj, "set_reaction_enabled")};
    "Message template tools";
    tools = {@tools, $llm_agent_tool:mk("list_messages", "List message template properties (*_msg) and message bags (*_msg_bag/_msgs) on an object.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#62', '$room', 'here')"]], "required" -> {"object"}], target_obj, "list_messages")};
    tools = {@tools, $llm_agent_tool:mk("get_message_template", "Show a single message template or list the entries of a message bag.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msg, _msgs, or _msg_bag)"]], "required" -> {"object", "property"}], target_obj, "get_message_template")};
    tools = {@tools, $llm_agent_tool:mk("set_message_template", "Set a message template on an object property.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msg, _msgs, or _msg_bag)"], "template" -> ["type" -> "string", "description" -> "Template string using {sub} syntax"]], "required" -> {"object", "property", "template"}], target_obj, "set_message_template")};
    tools = {@tools, $llm_agent_tool:mk("add_message_template", "Append a message template to a message bag property (_msgs or _msg_bag).", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msgs or _msg_bag)"], "template" -> ["type" -> "string", "description" -> "Template string using {sub} syntax"]], "required" -> {"object", "property", "template"}], target_obj, "add_message_template")};
    tools = {@tools, $llm_agent_tool:mk("delete_message_template", "Remove a message entry by index from a message bag property.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msgs or _msg_bag)"], "index" -> ["type" -> "integer", "description" -> "1-based index to remove"]], "required" -> {"object", "property", "index"}], target_obj, "delete_message_template")};
    "Documentation tools";
    tools = {@tools, $llm_agent_tool:mk("doc_lookup", "Read developer documentation for an object, verb, or property. Use formats: obj, obj:verb, obj.property.", ["type" -> "object", "properties" -> ["target" -> ["type" -> "string", "description" -> "Object/verb/property reference, e.g., '$sub_utils', '#61:drop_msg', '#61.get_msg'"]], "required" -> {"target"}], target_obj, "doc_lookup")};
    tools = {@tools, $llm_agent_tool:mk("help_lookup", "Look up a help topic to get information about commands and features. Pass empty string to list all available topics.", ["type" -> "object", "properties" -> ["topic" -> ["type" -> "string", "description" -> "Help topic to look up (e.g., 'building', 'passages', '@build'). Pass empty string to list all."]], "required" -> {"topic"}], target_obj, "help_lookup")};
    return tools;
  endverb

  verb _parse_direction_spec (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse direction string into list (handles 'north:n' and 'north,n' formats)";
    {dir_spec} = args;
    !dir_spec:contains(":") && return $str_proto:split(dir_spec, ",");
    colon_parts = $str_proto:split(dir_spec, ":");
    length(colon_parts) < 2 && return {dir_spec};
    return {colon_parts[1], @$str_proto:split(colon_parts[2], ",")};
  endverb

  verb build_room (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a new room";
    {args_map, actor} = args;
    set_task_perms(actor);
    {room_name, area_spec, parent_spec} = {args_map["name"], maphaskey(args_map, "area") ? args_map["area"] | "", maphaskey(args_map, "parent") ? args_map["parent"] | "$room"};
    parent_obj = $match:match_object(parent_spec, actor);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Invalid parent object: " + parent_spec);
    "Parse area - default to current area if not specified, 'ether' means free-floating";
    target_area = #-1;
    if (!area_spec || area_spec == "" || area_spec == "here")
      current_room = actor.location;
      valid(current_room) && (target_area = current_room.location);
    elseif (area_spec != "ether")
      target_area = $match:match_object(area_spec, actor);
      "Validate that target_area is actually an area, not a room";
      if (valid(target_area) && typeof(target_area) == OBJ && valid(target_area.location) && target_area.location != #-1)
        actual_area = target_area.location;
        return "Error: " + tostr(target_area) + " is a room, not an area. To build in the same area as that room, omit the 'area' parameter or use 'here'. The area containing that room is " + tostr(actual_area) + ".";
      endif
    endif
    "Create room";
    if (!valid(target_area))
      new_room = parent_obj:create();
      area_str = " (free-floating)";
    else
      cap = actor:find_capability_for(target_area, 'area);
      area_target = typeof(cap) == FLYWEIGHT ? cap | target_area;
      try
        new_room = area_target:make_room_in(parent_obj);
        area_str = " in " + tostr(target_area);
      except (E_PERM)
        return "Permission denied: " + $grant_utils:format_denial(target_area, 'area, {'add_room});
      endtry
    endif
    new_room:set_name_aliases(room_name, {});
    return "Created \"" + room_name + "\" (" + tostr(new_room) + ")" + area_str + ".";
  endverb

  verb dig_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a passage between two rooms";
    {args_map, actor} = args;
    set_task_perms(actor);
    {source_spec, direction, target_spec, return_dir, oneway_flag} = {maphaskey(args_map, "source_room") ? args_map["source_room"] | "", args_map["direction"], args_map["target_room"], maphaskey(args_map, "return_direction") ? args_map["return_direction"] | "", maphaskey(args_map, "oneway") ? args_map["oneway"] | false};
    "Parse direction string into list";
    from_dirs = this:_parse_direction_spec(direction);
    from_dirs = $passage:expand_direction_aliases({@from_dirs});
    "Parse return direction";
    to_dirs = {};
    if (!oneway_flag)
      if (return_dir)
        to_dirs = this:_parse_direction_spec(return_dir);
        to_dirs = $passage:expand_direction_aliases({@to_dirs});
      else
        "Infer opposite direction";
        opposites = ["north" -> "south", "south" -> "north", "east" -> "west", "west" -> "east", "up" -> "down", "down" -> "up", "in" -> "out", "out" -> "in"];
        maphaskey(opposites, from_dirs[1]) && (to_dirs = $passage:expand_direction_aliases({opposites[from_dirs[1]]}));
      endif
    endif
    "Find source room - default to actor's location if not specified";
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, actor) | actor.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    target_room = $match:match_object(target_spec, actor);
    typeof(target_room) == OBJ || raise(E_INVARG, "Target room not found");
    valid(target_room) || raise(E_INVARG, "Target room no longer exists");
    "Get area - both rooms must be in the same area";
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    target_room.location == area || raise(E_INVARG, "Both rooms must be in the same area");
    "Check permissions";
    from_cap = actor:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(source_room, 'room, {'dig_from});
    endtry
    to_cap = actor:find_capability_for(target_room, 'room);
    to_target = typeof(to_cap) == FLYWEIGHT ? to_cap | target_room;
    try
      to_target:check_can_dig_into();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(target_room, 'room, {'dig_into});
    endtry
    "Create passage";
    passage = oneway_flag || !to_dirs ? $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, "", {}, "", false, true) | $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, to_dirs[1], to_dirs, "", true, true);
    "Register with area";
    area_cap = actor:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    area_target:create_passage(from_target, to_target, passage);
    "Report";
    msg = oneway_flag ? "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way)." | (!to_dirs ? "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way - no return direction inferred)." | "Dug passage: " + from_dirs:join(",") + " | " + to_dirs:join(",") + " connecting to " + tostr(target_room) + ".");
    return msg;
  endverb

  verb remove_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Remove a passage between two rooms";
    {args_map, actor} = args;
    set_task_perms(actor);
    {target_spec, source_spec} = {args_map["target_room"], maphaskey(args_map, "source_room") ? args_map["source_room"] | ""};
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, actor) | actor.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    target_room = $match:match_object(target_spec, actor);
    typeof(target_room) == OBJ || raise(E_INVARG, "Target room not found");
    valid(target_room) || raise(E_INVARG, "Target room no longer exists");
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    target_room.location == area || raise(E_INVARG, "Both rooms must be in the same area");
    passage = area:passage_for(source_room, target_room);
    typeof(passage) != FLYWEIGHT && return "No passage found between " + tostr(source_room) + " and " + tostr(target_room) + ".";
    "Collect labels for reporting";
    {side_a_room, side_b_room} = {`passage.side_a_room ! ANY => #-1', `passage.side_b_room ! ANY => #-1'};
    labels = {};
    source_room == side_a_room && `passage.side_a_label ! ANY => ""' != "" && (labels = {@labels, passage.side_a_label});
    source_room == side_b_room && `passage.side_b_label ! ANY => ""' != "" && (labels = {@labels, passage.side_b_label});
    target_room == side_a_room && `passage.side_a_label ! ANY => ""' != "" && !(passage.side_a_label in labels) && (labels = {@labels, passage.side_a_label});
    target_room == side_b_room && `passage.side_b_label ! ANY => ""' != "" && !(passage.side_b_label in labels) && (labels = {@labels, passage.side_b_label});
    "Check permissions";
    from_cap = actor:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(source_room, 'room, {'dig_from});
    endtry
    "Remove passage via area";
    area_cap = actor:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    result = area_target:remove_passage(from_target, target_room);
    label_str = labels ? " (" + labels:join("/") + ")" | "";
    return result ? "Removed passage" + label_str + " between " + tostr(source_room) + " and " + tostr(target_room) + "." | "Failed to remove passage (may have already been removed).";
  endverb

  verb set_passage_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set description and ambient flag for a passage";
    {args_map, actor} = args;
    set_task_perms(actor);
    {direction, description, ambient, source_spec} = {args_map["direction"], args_map["description"], maphaskey(args_map, "ambient") ? args_map["ambient"] | true, maphaskey(args_map, "source_room") ? args_map["source_room"] | ""};
    typeof(description) == STR && "{" in description && "}" in description && (description = `$sub_utils:compile(description) ! ANY => description');
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, actor) | actor.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    passages = area:passages_from(source_room);
    typeof(passages) != LIST && return "No passages from " + tostr(source_room) + ".";
    length(passages) == 0 && return "No passages from " + tostr(source_room) + ".";
    target_passage = area:find_passage_by_direction(source_room, direction);
    typeof(target_passage) != FLYWEIGHT && return "No passage found in direction '" + direction + "' from " + tostr(source_room) + ".";
    from_cap = actor:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(source_room, 'room, {'dig_from});
    endtry
    new_passage = target_passage:with_description_from(source_room, description):with_ambient_from(source_room, ambient);
    area:update_passage(source_room, target_passage:other_room(source_room), new_passage);
    return "Set description for '" + direction + "' passage" + (ambient ? " (ambient - integrates into room description)" | " (explicit - shows in exits list)") + ".";
  endverb

  verb create_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create an object from a parent";
    {args_map, actor} = args;
    {parent_spec, name_spec, extra_aliases} = {args_map["parent"], args_map["name"], maphaskey(args_map, "aliases") ? args_map["aliases"] | {}};
    {primary_name, parsed_aliases} = $str_proto:parse_name_aliases(name_spec);
    final_aliases = {@parsed_aliases, @extra_aliases};
    !primary_name && raise(E_INVARG, "Object name cannot be blank");
    set_task_perms(actor);
    parent_obj = $match:match_object(parent_spec, actor);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Parent not found");
    valid(parent_obj) || raise(E_INVARG, "Parent no longer exists");
    is_fertile = `parent_obj.fertile ! E_PROPNF => false';
    !is_fertile && !actor.wizard && parent_obj.owner != actor && raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj));
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, final_aliases);
    new_obj:moveto(actor);
    message = "Created \"" + primary_name + "\" (" + tostr(new_obj) + ") from " + tostr(parent_obj) + " in your inventory.";
    final_aliases && (message = message + " Aliases: " + final_aliases:join(", ") + ".");
    return message;
  endverb

  verb recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Permanently destroy an object";
    {args_map, actor} = args;
    set_task_perms(actor);
    target_obj = $match:match_object(args_map["object"], actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj));
    {obj_name, obj_id} = {target_obj.name, tostr(target_obj)};
    target_obj:destroy();
    return "Recycled \"" + obj_name + "\" (" + obj_id + ").";
  endverb

  verb rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Rename an object";
    {args_map, actor} = args;
    set_task_perms(actor);
    target_obj = $match:match_object(args_map["object"], actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You do not have permission to rename " + tostr(target_obj));
    {new_name, new_aliases} = $str_proto:parse_name_aliases(args_map["name"]);
    !new_name && raise(E_INVARG, "Object name cannot be blank");
    old_name = `target_obj.name ! ANY => "(no name)"';
    target_obj:set_name_aliases(new_name, new_aliases);
    message = "Renamed \"" + old_name + "\" (" + tostr(target_obj) + ") to \"" + new_name + "\".";
    new_aliases && (message = message + " Aliases: " + new_aliases:join(", ") + ".");
    return message;
  endverb

  verb describe_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object description";
    {args_map, actor} = args;
    set_task_perms(actor);
    target_obj = $match:match_object(args_map["object"], actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You do not have permission to describe " + tostr(target_obj));
    !args_map["description"] && raise(E_INVARG, "Description cannot be blank");
    target_obj.description = args_map["description"];
    return "Set description of \"" + `target_obj.name ! ANY => tostr(target_obj)' + "\" (" + tostr(target_obj) + ").";
  endverb

  verb move_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Move an object to a new location";
    {args_map, actor} = args;
    set_task_perms(actor);
    {obj_spec, dest_spec} = {args_map["object"], args_map["destination"]};
    target_obj = $match:match_object(obj_spec, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You do not have permission to move " + tostr(target_obj));
    dest_obj = $match:match_object(dest_spec, actor);
    typeof(dest_obj) == OBJ || raise(E_INVARG, "Destination not found");
    valid(dest_obj) || raise(E_INVARG, "Destination no longer exists");
    old_location_name = valid(target_obj.location) ? `target_obj.location.name ! ANY => tostr(target_obj.location)' | "(nowhere)";
    target_obj:moveto(dest_obj);
    return "Moved \"" + `target_obj.name ! ANY => tostr(target_obj)' + "\" (" + tostr(target_obj) + ") from " + old_location_name + " to \"" + `dest_obj.name ! ANY => tostr(dest_obj)' + "\" (" + tostr(dest_obj) + ").";
  endverb

  verb set_integrated_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object's integrated description";
    {args_map, actor} = args;
    set_task_perms(actor);
    target_obj = $match:match_object(args_map["object"], actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You do not have permission to modify " + tostr(target_obj));
    target_obj.integrated_description = args_map["integrated_description"];
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    return args_map["integrated_description"] == "" ? "Cleared integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + ")." | "Set integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "). When in a room, this will appear in the room description.";
  endverb

  verb grant_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Grant capabilities to a player";
    {args_map, actor} = args;
    {target_spec, category, perms, grantee_spec} = {args_map["target"], args_map["category"], args_map["permissions"], args_map["grantee"]};
    set_task_perms(actor);
    target_obj = $match:match_object(target_spec, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Target not found");
    valid(target_obj) || raise(E_INVARG, "Target no longer exists");
    grantee = $match:match_object(grantee_spec, actor);
    typeof(grantee) == OBJ || raise(E_INVARG, "Grantee not found");
    valid(grantee) || raise(E_INVARG, "Grantee no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You must be owner or wizard to grant capabilities for " + tostr(target_obj));
    perm_symbols = { tostr(p):to_symbol() for p in (perms) };
    $root:grant_capability(target_obj, perm_symbols, grantee, tostr(category):to_symbol());
    return "Granted " + $grant_utils:format_grant_with_name(target_obj, tostr(category):to_symbol(), perm_symbols) + " to " + grantee:name() + " (" + tostr(grantee) + ").";
  endverb

  verb audit_owned (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all owned objects";
    {args_map, actor} = args;
    set_task_perms(actor);
    owned = sort(owned_objects(actor));
    !owned && return "You don't own any objects.";
    result = "You own " + tostr(length(owned)) + " objects:\n";
    for o in (owned)
      result = result + tostr(o) + ": \"" + `o.name ! ANY => "(no name)"' + "\" (parent: " + (valid(`parent(o) ! ANY => #-1') ? tostr(parent(o)) | "(none)") + ")\n";
    endfor
    return result;
  endverb

  verb area_map (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get list of all rooms in the current area";
    {args_map, actor} = args;
    current_room = actor.location;
    !valid(current_room) && return "Error: You are not in a room.";
    area = current_room.location;
    !valid(area) && return "Error: Current room is not in an area.";
    result = {"Current Location: " + `current_room:name() ! ANY => tostr(current_room)' + " (" + tostr(current_room) + ")", "Area: " + `area:name() ! ANY => tostr(area)' + " (" + tostr(area) + ")", "", "Rooms in this area:"};
    for o in (area.contents)
      if (valid(o))
        result = {@result, "  * " + `o:name() ! ANY => tostr(o)' + " (" + tostr(o) + ")" + (o == current_room ? " (you are here)" | "")};
      endif
    endfor
    return result:join("\n");
  endverb

  verb find_route (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find route between two rooms";
    {args_map, actor} = args;
    {to_spec, from_spec} = {args_map["to_room"], maphaskey(args_map, "from_room") ? args_map["from_room"] | ""};
    set_task_perms(actor);
    from_room = from_spec && from_spec != "" ? $match:match_object(from_spec, actor) | actor.location;
    typeof(from_room) == OBJ || return "Error: Could not find starting room '" + from_spec + "'.";
    !valid(from_room) && return "Error: You are not in a room.";
    area = from_room.location;
    !valid(area) && return "Error: Starting room is not in an area.";
    to_room = $match:match_object(to_spec, actor);
    typeof(to_room) == OBJ || return "Error: Could not find destination room '" + to_spec + "'.";
    !valid(to_room) && return "Error: Destination room does not exist.";
    {from_name, to_name} = {`from_room:name() ! ANY => tostr(from_room)', `to_room:name() ! ANY => tostr(to_room)'};
    to_room == from_room && return "You are already at " + to_name + "!";
    path = area:find_path(from_room, to_room);
    !path && return "No route found from " + from_name + " to " + to_name + ".";
    result = {"Route from " + from_name + " (" + tostr(from_room) + ") to " + to_name + " (" + tostr(to_room) + "):"};
    for i in [1..length(path) - 1]
      {room, passage} = path[i];
      {side_a_room, side_b_room} = {`passage.side_a_room ! ANY => #-1', `passage.side_b_room ! ANY => #-1'};
      direction = room == side_a_room ? `passage.side_a_label ! ANY => "passage"' | (room == side_b_room ? `passage.side_b_label ! ANY => "passage"' | "passage");
      next_room = path[i + 1][1];
      result = {@result, "  " + tostr(i) + ". Go " + direction + " to " + `next_room:name() ! ANY => tostr(next_room)' + " (" + tostr(next_room) + ")"};
    endfor
    return result:join("\n");
  endverb

  verb list_prototypes (this none this) owner: HACKER flags: "rxd"
    "Tool: List available prototype objects for building";
    {args_map, actor} = args;
    prototypes = $sysobj:list_builder_prototypes();
    result = {"Available prototypes for creating objects:", ""};
    for proto_info in (prototypes)
      result = {@result, "* " + proto_info["name"] + " (" + proto_info["object"] + ")", "  " + proto_info["description"], ""};
    endfor
    return {@result, "Use these with the create_object tool or as the 'parent' parameter in build_room."}:join("\n");
  endverb

  verb inspect_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Inspect an object and return detailed information";
    {args_map, actor} = args;
    set_task_perms(actor);
    target = $match:match_object(args_map["object"], actor);
    typeof(target) == OBJ || return "Error: Could not find object '" + args_map["object"] + "'.";
    !valid(target) && return "Error: Object does not exist.";
    obj_name = `target:name() ! ANY => `target.name ! ANY => "(unnamed)"'';
    desc = `target:description() ! ANY => `target.description ! ANY => "(no description)"'';
    owner = `target.owner ! ANY => #-1';
    parent_obj = `parent(target) ! ANY => #-1';
    loc = `target.location ! ANY => #-1';
    result = {"Object Information for " + tostr(target) + ":", "", "Name: " + obj_name, "Description: " + desc, "", "Owner: " + (valid(owner) ? `owner:name() ! ANY => tostr(owner)' + " (" + tostr(owner) + ")" | "(none)"), "Parent: " + (valid(parent_obj) ? `parent_obj:name() ! ANY => tostr(parent_obj)' + " (" + tostr(parent_obj) + ")" | "(none)"), "Location: " + (valid(loc) ? `loc:name() ! ANY => tostr(loc)' + " (" + tostr(loc) + ")" | "(nowhere)"), ""};
    "Type-specific information";
    if (respond_to(target, 'is_actor) && target:is_actor())
      result = {@result, "Type: Actor/Player"};
    elseif ($room in ancestors(target))
      result = {@result, "Type: Room"};
      area = `target.location ! ANY => #-1';
      if (valid(area) && respond_to(area, 'passages_from))
        passages = area:passages_from(target);
        if (passages && length(passages) > 0)
          exits = {};
          for passage in (passages)
            {side_a_room, side_b_room} = {`passage.side_a_room ! ANY => #-1', `passage.side_b_room ! ANY => #-1'};
            if (target == side_a_room)
              label = `passage.side_a_label ! ANY => "passage"';
            elseif (target == side_b_room)
              label = `passage.side_b_label ! ANY => "passage"';
            else
              continue;
            endif
            label && (exits = {@exits, label});
          endfor
          exits && (result = {@result, "Exits: " + exits:join(", ")});
        endif
      endif
    elseif ($wearable in ancestors(target))
      result = {@result, "Type: Wearable item"};
    elseif ($thing in ancestors(target))
      result = {@result, "Type: Thing/Object"};
    elseif ($area in ancestors(target))
      result = {@result, "Type: Area"};
      respond_to(target, 'contents) && (result = {@result, "Contains " + tostr(length(target:contents())) + " room" + (length(target:contents()) == 1 ? "" | "s")});
    else
      result = {@result, "Type: Generic object"};
    endif
    return result:join("\n");
  endverb

  verb list_rules (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all rule properties on an object";
    {args_map, actor} = args;
    set_task_perms(actor);
    target_obj = $match:match_object(args_map["object"], actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    all_props = target_obj:all_properties();
    rule_props = {};
    for prop in (all_props)
      prop:ends_with("_rule") && (rule_props = {@rule_props, prop});
    endfor
    !rule_props && return "No rule properties found on " + tostr(target_obj) + ".";
    lines = {"Rules on " + tostr(target_obj) + ":"};
    for prop in (rule_props)
      value = `target_obj.(prop) ! ANY => 0';
      if (value == 0)
        lines = {@lines, "  " + prop + ": (no rule set)"};
      elseif (typeof(value) == FLYWEIGHT)
        rule_str = $rule_engine:decompile_rule(value);
        lines = {@lines, "  " + prop + ": " + rule_str};
      else
        lines = {@lines, "  " + prop + ": " + toliteral(value)};
      endif
    endfor
    return lines:join("\n");
  endverb

  verb set_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set a rule on an object property";
    {args_map, actor} = args;
    {obj_str, prop_name, expression} = {args_map["object"], args_map["property"], args_map["expression"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You must be owner or wizard to set rules on " + tostr(target_obj));
    prop_name:ends_with("_rule") || raise(E_INVARG, "Property name must end with '_rule'");
    compiled = $rule_engine:parse_expression(expression, prop_name, actor);
    validation = $rule_engine:validate_rule(compiled);
    !validation['valid] && raise(E_INVARG, "Rule validation failed: " + validation['warnings]:join("; "));
    if (prop_name in target_obj:all_properties())
      target_obj.(prop_name) = compiled;
    else
      add_property(target_obj, prop_name, compiled, {actor, "r"});
    endif
    return "Set " + tostr(target_obj) + "." + prop_name + " = " + expression;
  endverb

  verb show_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Show a specific rule property";
    {args_map, actor} = args;
    {obj_str, prop_name} = {args_map["object"], args_map["property"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name:ends_with("_rule") || raise(E_INVARG, "Property name must end with '_rule'");
    prop_name in target_obj:all_properties() || return tostr(target_obj) + "." + prop_name + " is not defined.";
    value = target_obj.(prop_name);
    if (value == 0)
      return tostr(target_obj) + "." + prop_name + ": (no rule set)";
    elseif (typeof(value) == FLYWEIGHT)
      rule_str = $rule_engine:decompile_rule(value);
      return tostr(target_obj) + "." + prop_name + ": " + rule_str;
    endif
    return tostr(target_obj) + "." + prop_name + ": " + toliteral(value);
  endverb

  verb test_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Test a rule expression with specific variable bindings";
    {args_map, actor} = args;
    {expression, bindings} = {args_map["expression"], args_map["bindings"]};
    typeof(expression) == STR || raise(E_TYPE, "expression must be string");
    typeof(bindings) == MAP || raise(E_TYPE, "bindings must be object/map");
    set_task_perms(actor);
    compiled = `$rule_engine:parse_expression(expression, 'test_rule, actor) ! ANY => E_INVARG';
    compiled == E_INVARG && return "ERROR: Rule parsing failed. Check syntax. Expression: " + expression;
    validation = $rule_engine:validate_rule(compiled);
    !validation['valid] && return "ERROR: Rule validation failed: " + validation['warnings]:join("; ") + ". Expression: " + expression;
    "Convert bindings map keys from strings to symbols";
    converted_bindings = [];
    for key in (mapkeys(bindings))
      converted_bindings[tosym(key)] = `$match:match_object(bindings[key], actor) ! ANY => bindings[key]';
    endfor
    result = $rule_engine:evaluate(compiled, converted_bindings);
    if (result['success])
      return "SUCCESS: Rule evaluated to true. Bindings: " + toliteral(converted_bindings);
    endif
    reason = maphaskey(result, 'reason) ? typeof(result['reason]) == STR ? result['reason] | toliteral(result['reason]) | "rule did not match";
    return "FAILED: Rule evaluated to false. Reason: " + reason + ". Bindings: " + toliteral(converted_bindings);
  endverb

  verb list_reactions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List reactions on an object with details";
    {args_map, actor} = args;
    set_task_perms(actor);
    obj_str = args_map["object"];
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    reaction_props = $obj_utils:reaction_properties(target_obj);
    if (!reaction_props || length(reaction_props) == 0)
      return "No reactions found on " + tostr(target_obj);
    endif
    lines = {"Reactions on " + tostr(target_obj) + " (" + tostr(length(reaction_props)) + " total):", ""};
    for prop_info in (reaction_props)
      {prop_name, reaction} = prop_info;
      lines = {@lines, prop_name + ":"};
      "Trigger";
      if (typeof(reaction.trigger) == SYM)
        lines = {@lines, "  Trigger: " + tostr(reaction.trigger)};
      elseif (typeof(reaction.trigger) == LIST)
        {kind, prop, op, value} = reaction.trigger;
        lines = {@lines, "  Trigger: threshold - " + tostr(prop) + " " + tostr(op) + " " + tostr(value)};
      else
        lines = {@lines, "  Trigger: (unknown)"};
      endif
      "When condition";
      if (reaction.when == 0)
        lines = {@lines, "  When: (no condition)"};
      else
        rule_str = $rule_engine:decompile_rule(reaction.when);
        lines = {@lines, "  When: " + rule_str};
      endif
      "Effects";
      lines = {@lines, "  Effects: " + tostr(length(reaction.effects)) + " items"};
      for effect in (reaction.effects)
        if (typeof(effect) == LIST && length(effect) > 0)
          lines = {@lines, "    - " + tostr(effect[1])};
        else
          lines = {@lines, "    - " + toliteral(effect)};
        endif
      endfor
      "Enabled";
      lines = {@lines, "  Enabled: " + (reaction.enabled ? "yes" | "no")};
      lines = {@lines, ""};
    endfor
    return lines:join("\n");
  endverb

  verb add_reaction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Add a reaction to an object";
    {args_map, actor} = args;
    set_task_perms(actor);
    obj_str = args_map["object"];
    prop_name = args_map["property_name"];
    trigger_str = args_map["trigger"];
    when_str = args_map["when"];
    effects_str = args_map["effects"];
    "Parse object";
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    "Validate property name";
    prop_name:ends_with("_reaction") || raise(E_INVARG, "Property name must end with '_reaction'");
    "Check permission";
    if (!actor.wizard && target_obj.owner != actor)
      return "Permission denied: You do not own " + tostr(target_obj) + " and are not a wizard.";
    endif
    "Parse trigger";
    if (pcre_match(trigger_str, "^[a-z_]+$"))
      trigger = tosym(trigger_str);
    else
      parsed_trigger = eval("return " + trigger_str + ";");
      if (!parsed_trigger[1])
        return "Error parsing trigger: " + tostr(parsed_trigger[2]);
      endif
      trigger = parsed_trigger[2];
    endif
    "Parse effects";
    parsed_effects = eval("return " + effects_str + ";");
    if (!parsed_effects[1])
      return "Error parsing effects: " + tostr(parsed_effects[2]);
    endif
    effects = parsed_effects[2];
    "When clause";
    if (when_str == "0")
      when_clause = 0;
    else
      when_clause = when_str;
    endif
    "Create reaction";
    try
      reaction = $reaction:mk(trigger, when_clause, effects);
    except e (ANY)
      return "Error creating reaction: " + (length(e) >= 2 ? tostr(e[2]) | toliteral(e));
    endtry
    "Add or update property";
    if (prop_name in target_obj:all_properties())
      target_obj.(prop_name) = reaction;
    else
      add_property(target_obj, prop_name, reaction, {actor, "r"});
    endif
    return "Set " + tostr(target_obj) + "." + prop_name;
  endverb

  verb set_reaction_enabled (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Enable or disable a reaction";
    {args_map, actor} = args;
    set_task_perms(actor);
    obj_str = args_map["object"];
    prop_name = args_map["property_name"];
    enabled = args_map["enabled"];
    "Parse object";
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    "Validate property name";
    prop_name:ends_with("_reaction") || raise(E_INVARG, "Property name must end with '_reaction'");
    "Check permission";
    if (!actor.wizard && target_obj.owner != actor)
      return "Permission denied: You do not own " + tostr(target_obj);
    endif
    "Check property exists and is a reaction";
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property not found: " + prop_name);
    reaction = target_obj.(prop_name);
    typeof(reaction) == FLYWEIGHT && reaction.delegate == $reaction || raise(E_INVARG, prop_name + " is not a reaction");
    "Reconstruct flyweight with new enabled state (flyweights are immutable)";
    new_reaction = <reaction.delegate, .when = reaction.when, .trigger = reaction.trigger, .effects = reaction.effects, .enabled = enabled, .fired_at = reaction.fired_at>;
    target_obj.(prop_name) = new_reaction;
    return (enabled ? "Enabled" | "Disabled") + " " + tostr(target_obj) + "." + prop_name;
  endverb

  verb list_messages (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List message template properties on an object";
    {args_map, actor} = args;
    set_task_perms(actor);
    obj_str = args_map["object"];
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    all_props = target_obj:all_properties();
    msg_props = {};
    for prop in (all_props)
      prop:ends_with("_msg") || prop:ends_with("_msgs") || prop:ends_with("_msg_bag") && (msg_props = {@msg_props, prop});
    endfor
    !msg_props && return "No message properties found on " + tostr(target_obj) + ".";
    lines = {"Messages on " + tostr(target_obj) + ":"};
    for prop in (msg_props)
      value = `target_obj.(prop) ! ANY => ""';
      if (typeof(value) == STR)
        lines = {@lines, "  " + prop + ": \"" + (length(value) > 50 ? value[1..50] + "..." | value) + "\""};
      elseif (typeof(value) == FLYWEIGHT)
        lines = {@lines, "  " + prop + ": (compiled template)"};
      elseif (typeof(value) == LIST)
        "Check if it's a compiled template (first item not a list) or a message bag (list of lists)";
        is_compiled = length(value) > 0 && typeof(value[1]) != LIST;
        is_bag = length(value) > 0 && typeof(value[1]) == LIST;
        if (is_compiled)
          lines = {@lines, "  " + prop + ": (compiled template)"};
        elseif (is_bag)
          lines = {@lines, "  " + prop + ": [" + tostr(length(value)) + " entries]"};
        else
          lines = {@lines, "  " + prop + ": (empty)"};
        endif
      else
        lines = {@lines, "  " + prop + ": " + toliteral(value)};
      endif
    endfor
    return lines:join("\n");
  endverb

  verb get_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get a message template value";
    {args_map, actor} = args;
    {obj_str, prop_name} = {args_map["object"], args_map["property"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name in target_obj:all_properties() || return tostr(target_obj) + "." + prop_name + " is not defined.";
    value = target_obj.(prop_name);
    "Helper to check if a list is a compiled template (contains strings/flyweights, not lists)";
    is_compiled = typeof(value) == LIST && length(value) > 0 && typeof(value[1]) != LIST;
    if (typeof(value) == LIST && is_compiled)
      "Single compiled template - decompile the whole thing";
      return tostr(target_obj) + "." + prop_name + ": " + $sub_utils:decompile(value);
    elseif (typeof(value) == LIST)
      "Message bag - list of compiled templates";
      lines = {tostr(target_obj) + "." + prop_name + " (" + tostr(length(value)) + " entries):"};
      for i in [1..length(value)]
        entry = value[i];
        if (typeof(entry) == LIST)
          lines = {@lines, "  " + tostr(i) + ": " + $sub_utils:decompile(entry)};
        else
          lines = {@lines, "  " + tostr(i) + ": " + toliteral(entry)};
        endif
      endfor
      return lines:join("\n");
    elseif (typeof(value) == FLYWEIGHT)
      return tostr(target_obj) + "." + prop_name + ": (flyweight - not a standard message format)";
    elseif (typeof(value) == STR)
      return tostr(target_obj) + "." + prop_name + ": \"" + value + "\"";
    endif
    return tostr(target_obj) + "." + prop_name + ": " + toliteral(value);
  endverb

  verb set_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set a message template on an object";
    {args_map, actor} = args;
    {obj_str, prop_name, template} = {args_map["object"], args_map["property"], args_map["template"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You must be owner or wizard to set messages on " + tostr(target_obj));
    "Compile the template";
    compiled = $sub_utils:compile(template);
    "Set or create property";
    if (prop_name in target_obj:all_properties())
      if (prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag"))
        target_obj.(prop_name) = {compiled};
      else
        target_obj.(prop_name) = compiled;
      endif
    else
      if (prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag"))
        add_property(target_obj, prop_name, {compiled}, {actor, "r"});
      else
        add_property(target_obj, prop_name, compiled, {actor, "r"});
      endif
    endif
    return "Set " + tostr(target_obj) + "." + prop_name;
  endverb

  verb add_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Add a message to a message bag";
    {args_map, actor} = args;
    {obj_str, prop_name, template} = {args_map["object"], args_map["property"], args_map["template"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You must be owner or wizard to set messages on " + tostr(target_obj));
    prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with _msgs or _msg_bag");
    compiled = $sub_utils:compile(template);
    if (prop_name in target_obj:all_properties())
      current = target_obj.(prop_name);
      typeof(current) == LIST || (current = {});
      target_obj.(prop_name) = {@current, compiled};
    else
      add_property(target_obj, prop_name, {compiled}, {actor, "r"});
    endif
    return "Added message to " + tostr(target_obj) + "." + prop_name;
  endverb

  verb delete_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Delete a message from a message bag by index";
    {args_map, actor} = args;
    {obj_str, prop_name, index} = {args_map["object"], args_map["property"], args_map["index"]};
    set_task_perms(actor);
    target_obj = $match:match_object(obj_str, actor);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !actor.wizard && target_obj.owner != actor && raise(E_PERM, "You must be owner or wizard to modify messages on " + tostr(target_obj));
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property not found: " + prop_name);
    current = target_obj.(prop_name);
    typeof(current) == LIST || raise(E_INVARG, prop_name + " is not a list");
    index >= 1 && index <= length(current) || raise(E_RANGE, "Index out of range");
    target_obj.(prop_name) = listdelete(current, index);
    return "Deleted message " + tostr(index) + " from " + tostr(target_obj) + "." + prop_name;
  endverb

  verb doc_lookup (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Fetch developer documentation for object/verb/property";
    {args_map, actor} = args;
    target_spec = args_map["target"];
    set_task_perms(actor);
    "Handle special alias cases";
    alias_obj = false;
    if (typeof(target_spec) == STR)
      alias_name = target_spec:starts_with("$") ? target_spec[2..$] | target_spec;
      alias_name == "sub_utils" && (alias_obj = $sub_utils);
      alias_name == "sub" && (alias_obj = $sub);
    endif
    if (alias_obj)
      type = 'object;
      target_obj = alias_obj;
      item_name = "";
    else
      parsed = $prog_utils:parse_target_spec(target_spec);
      parsed || raise(E_INVARG, "Invalid format. Use object, object:verb, or object.property");
      object_str = parsed['object_str];
      selectors = parsed['selectors];
      "Determine type and item_name from selectors";
      if (length(selectors) > 0)
        selector = selectors[1];
        type = selector['kind];
        item_name = selector['item_name];
      else
        type = 'object;
        item_name = "";
      endif
      target_obj = $match:match_object(object_str, actor);
      typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
      valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    endif
    "Fetch docs based on type";
    if (type == 'object)
      doc_text = $help_utils:get_object_documentation(target_obj);
      title = "Documentation for " + tostr(target_obj);
    elseif (type == 'verb)
      verb_location = target_obj:find_verb_definer(item_name);
      verb_location == #-1 && raise(E_INVARG, "Verb '" + tostr(item_name) + "' not found on " + tostr(target_obj));
      doc_text = $help_utils:extract_verb_documentation(verb_location, item_name);
      title = "Documentation for " + tostr(target_obj) + ":" + tostr(item_name);
    elseif (type == 'property)
      doc_text = $help_utils:property_documentation(target_obj, item_name);
      title = "Documentation for " + tostr(target_obj) + "." + tostr(item_name);
    else
      raise(E_INVARG, "Unknown target type");
    endif
    doc_body = typeof(doc_text) == LIST ? doc_text:join("\n") | doc_text;
    return title + "\n\n" + (doc_body ? doc_body | "(No documentation available)");
  endverb

  verb help_lookup (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Look up a help topic";
    {args_map, actor} = args;
    topic = args_map["topic"];
    typeof(topic) != STR && return "Error: topic must be a string.";
    "If empty topic, list available topics";
    if (topic == "")
      all_topics = actor:_collect_help_topics();
      result = {"Available help topics:"};
      for t in (all_topics)
        result = {@result, "  " + t.name + " - " + t.summary};
      endfor
      return result:join("\n");
    endif
    "Search for specific topic";
    found = actor:find_help_topic(topic);
    if (typeof(found) == INT)
      return "No help found for: " + topic;
    endif
    "Return structured help";
    return "Topic: " + found.name + "\n\n" + found.summary + "\n\n" + found.content + (found.see_also ? "\n\nSee also: " + found.see_also:join(", ") | "");
  endverb
endobject