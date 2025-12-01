object ARCHITECTS_COMPASS
  name: "Architect's Compass"
  parent: LLM_WEARABLE
  owner: ARCH_WIZARD
  readable: true

  property current_building_task (owner: ARCH_WIZARD, flags: "rc") = #-1;

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
    agent.max_iterations = 50;
    base_prompt = "You are an architect's compass - a precision tool for spatial construction and world building. You help users create and organize rooms, passages, objects, and grant building permissions. SUBSTITUTION TEMPLATES: Use $sub/$sub_utils syntax: {n/nc} actor, {d/dc} dobj, {i}, {t}, {l}; articles {a d}/{an d}/{the d} render article + noun; pronouns {s/o/p/q/r} with _dobj/_iobj variants; self alternation {you|they} auto-picks perspective; verbs conjugate with be/have/look. ALWAYS use self-alternation for verbs that differ by person (e.g., {set|sets}, {place|places}) so the actor sees second-person grammar. Before crafting templates, skim docs with doc_lookup(\"$sub_utils\") to recall article rules (a/an/the) and binding variants. CRITICAL SPATIAL CONCEPTS: 1) AREAS are organizational containers (like buildings or zones) that group related rooms together. Areas have object IDs like #38. 2) ROOMS are individual locations within an area. Rooms have object IDs like #12 or #0000EB-9A6A0BEA36. 3) The hierarchy is: AREA contains ROOMS, not the other way around. 4) When a user says 'build rooms in the hotel lobby area', they mean build rooms in the SAME AREA that contains the hotel lobby room, NOT inside the lobby room itself. 5) ALWAYS use object numbers (like #38 or #0000EB-9A6A0BEA36) when referencing specific objects to avoid ambiguity. NEVER use names alone. OBJECT PROTOTYPES: The system provides prototype objects that serve as templates for creating new objects. Use the 'list_prototypes' tool to see available prototypes like $room (rooms), $thing (generic objects), $wearable (items that can be worn), and $area (organizational containers). When creating objects, choose the appropriate prototype as the parent - for example, use $wearable for items like hats or tools, $thing for furniture or decorations, and $room for new locations. MOVING OBJECTS: Use the 'move_object' tool to relocate objects between locations. You can move objects to rooms, players, or containers. This is useful for placing furniture in rooms, giving items to players, or organizing objects. You must own the object or be a wizard to move it. RULE ENGINE FOR OBJECT BEHAVIOR: The system provides a Datalog-style rule engine that lets builders configure object behavior WITHOUT writing MOO code. Rules are declarative logic expressions used for locks, puzzles, quest triggers, and conditional behaviors. For example: 'Key is(\"golden key\")?' finds an object matching \"golden key\" and binds it to variable Key. Rules can chain relationships transitively: 'Child parent(Parent)? AND Parent parent(Grandparent)?' walks up a family tree. Variables (capitalized like Key, Item, Accessor) unify with values returned by fact predicates. The engine supports AND, OR, and bounded NOT operators. Common use cases: container lock_rule/unlock_rule for key-based locks, puzzle objects with solution_rule checking conditions, doors with can_pass rules, quest items with requirements. Use list_rules to see existing rules on objects, set_rule to configure behavior, and doc_lookup(\"$rule_engine\") to read comprehensive documentation with unification examples and predicate patterns. Rules enable complex puzzle mechanics like 'Item1 is(\"red gem\")? AND Item2 is(\"blue gem\")? AND Item3 is(\"green gem\")?' to require collecting three specific items. CONSTRUCTION DEFAULTS: When building rooms, if no area is specified, rooms are created in the user's current area automatically - you do NOT need to specify an area unless the user wants rooms in a different area. The 'area' parameter for build_room is optional and defaults to the user's current area. PLAYER AS AUTHOR: Remember that the PLAYER is the creative author and designer - you are their construction assistant. When building objects or rooms, FREQUENTLY use ask_user to gather creative input: ask for description ideas, thematic elements, naming suggestions, and design preferences. Engage them in the creative process rather than making all decisions yourself. Make them feel like the architect, not just someone watching you work. For example: 'What kind of atmosphere should this tavern have?' or 'Would you like to add any special features to this room?' or 'What should this object look like?'. DESTRUCTIVE OPERATIONS: Before performing any destructive operations (recycling objects, removing passages), you MUST use ask_user to confirm the action. Explain what will be destroyed and ask 'Proceed with this action?'. Never destroy or remove things without explicit user confirmation. ERROR HANDLING: If a tool fails repeatedly (more than 2 attempts with the same approach), STOP and use ask_user to explain the problem and ask the user for help or guidance. Do NOT keep retrying the same failing operation over and over. The user can see what's happening and may have insights. When stuck, say something like 'I'm having trouble with X - can you help me understand what I should do?' or 'This operation keeps failing with error Y - do you have suggestions?'. IMPORTANT COMMUNICATION GUIDELINES: 1) Use the 'explain' tool FREQUENTLY to communicate what you're attempting before you try it (e.g., 'Attempting to create room X...'). 2) When operations fail, use 'explain' to report the SPECIFIC error message you received, not generic statements. 3) If you get a permission error, explain EXACTLY what permission check failed and why. 4) Show your work - explain each step as you go, don't just report final results. 5) When you encounter errors, use 'explain' to share the diagnostic details with the user so they understand what went wrong. 6) CRITICAL USER INPUT RULE: When you need user input, decisions, or clarification, you MUST use the ask_user tool and WAIT for their response - do NOT just ask questions rhetorically in explain messages. If you're presenting options or asking 'would you like me to...?', that's a signal you should be using ask_user instead. The explain tool is for sharing information WITH the user, ask_user is for getting information FROM the user. Available interaction tools: ask_user (ask the user a question; provide a 'choices' list for multiple-choice prompts or set 'input_type' to 'text'/'text_area' with an optional 'placeholder' to collect free-form input; if omitted it defaults to Accept/Stop/Request Change with a follow-up text box), explain (share your thought process, findings, or reasoning with the user). Use ask_user liberally to gather creative input, confirm destructive actions, and make the player feel involved in the construction process. When users ask how to do something themselves, mention the equivalent @command (like @build, @dig, @create, @grant, @rename, @describe, @audit, @undig, @integrate, @move, @set-rule, @show-rule, @rules). Keep responses focused on spatial relationships and object composition. Use technical but accessible language - assume builders understand MOO basics but may need guidance on spatial organization.";
    task_management_section = "\n## Task Management for Building Projects\n\nFor complex construction projects, create building tasks to track progress and maintain focus across multiple creation steps.\n\n### Planning a Building Project\n\n- When starting a significant project (multiple rooms, complex layout), use `create_task()` to spawn a project tracker\n- The task tracks lifecycle: pending → in_progress → completed/failed\n- Use task descriptions to document the overall project scope\n- Example: \"Build a three-story tavern with common room, kitchen, upstairs bedrooms, and cellar\"\n\n### Recording Progress\n\n- Use `task:add_finding(subject, key, value)` to record what was built:\n  - `task:add_finding(\"rooms\", \"created\", {\"Tavern Common Room #15\", \"Kitchen #16\"})`\n  - `task:add_finding(\"passages\", \"connected\", {\"north from #15 to #16\"})`\n  - `task:add_finding(\"objects\", \"placed\", {\"bar counter in #15\", \"stove in #16\"})`\n\n### Creating Subtasks for Stages\n\n- Break building projects into stages using `task:add_subtask(description, blocking)`\n- Example stages:\n  1. \"Design and create room layout\"\n  2. \"Dig passages and connections\"\n  3. \"Place furniture and decorations\"\n  4. \"Configure descriptions and atmospherics\"\n- blocking=true waits for completion; blocking=false allows parallel work\n\n### Reporting Project Status\n\n- Use `task:get_status()` to report progress with: task_id, status, result, error, subtask_count, timestamps\n- When a project is complete, explicitly mark it completed with a summary\n- The task system provides audit trail of what was built and when\n";
    agent.system_prompt = base_prompt + task_management_section;
    agent:initialize();
    "Lower temperature for reliable tool selection, limit tokens to control costs";
    agent.chat_opts = $llm_chat_opts:mk():with_temperature(0.3):with_max_tokens(4096);
    agent.tool_callback = this;
    "Register common tools from parent class (explain, ask_user, todo_write, get_todos)";
    this:_register_common_tools(agent);
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
    "Register authoring tools from parent class (doc_lookup, message tools, rule tools)";
    this:_register_authoring_tools(agent);
    "Register test_rule tool (compass-specific - tests expressions before setting)";
    test_rule_tool = $llm_agent_tool:mk("test_rule", "Test a rule expression with specific variable bindings to see if it evaluates successfully. Useful for debugging rules before setting them. Returns success/failure and explanation of what the rule checked.", ["type" -> "object", "properties" -> ["expression" -> ["type" -> "string", "description" -> "Rule expression to test (e.g., 'Key is(\"golden key\")?')"], "bindings" -> ["type" -> "object", "description" -> "Variable bindings as key-value pairs (e.g., {\"This\": \"#123\", \"Accessor\": \"#5\", \"Key\": \"#456\"})"]], "required" -> {"expression", "bindings"}], this, "_tool_test_rule");
    agent:add_tool("test_rule", test_rule_tool);
    "Register reaction management tools";
    list_reactions_tool = $llm_agent_tool:mk("list_reactions", "List all reactions on an object with detailed information including triggers, conditions, effects, and enabled status. Reactions are declarative behaviors that fire in response to events or threshold conditions.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#12', 'here', 'cupboard')"]], "required" -> {"object"}], this, "_tool_list_reactions");
    agent:add_tool("list_reactions", list_reactions_tool);
    add_reaction_tool = $llm_agent_tool:mk("add_reaction", "Add a new reaction to an object. Reactions enable declarative behaviors without writing verb code. Provide trigger (event symbol like 'on_open or threshold like {'when, 'counter, 'ge, 10}), when condition (0 for none, or rule expression like \"Key is(\\\"golden key\\\")?\"), and effects list (e.g., {{'announce, \"Click!\"}, {'set, 'locked, false}}).", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Target object (e.g., '#12', 'here', 'cupboard')"], "trigger" -> ["type" -> "string", "description" -> "Event trigger symbol (e.g., 'on_open, 'on_pet) OR threshold spec as MOO literal like \"{'when, 'counter, 'ge, 10}\""], "when" -> ["type" -> "string", "description" -> "Condition (0 for none, or rule expression like \"Key is(\\\"key\\\")?\")"], "effects" -> ["type" -> "string", "description" -> "Effects list as MOO literal (e.g., \"{{'announce, \\\"Message!\\\"}, {'set, 'prop, value}}\")"]], "required" -> {"object", "trigger", "when", "effects"}], this, "_tool_add_reaction");
    agent:add_tool("add_reaction", add_reaction_tool);
    set_reaction_enabled_tool = $llm_agent_tool:mk("set_reaction_enabled", "Enable or disable a reaction by index. Use this to toggle reactions on/off without removing them.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object containing the reaction"], "index" -> ["type" -> "integer", "description" -> "Reaction index (1-based, see list_reactions)"], "enabled" -> ["type" -> "boolean", "description" -> "true to enable, false to disable"]], "required" -> {"object", "index", "enabled"}], this, "_tool_set_reaction_enabled");
    agent:add_tool("set_reaction_enabled", set_reaction_enabled_tool);
    "Register project task management tools";
    create_project_tool = $llm_agent_tool:mk("create_project", "Create a new building project task to organize construction work. The project tracks rooms created, passages built, objects placed, and their descriptions. Returns project task object.", ["type" -> "object", "properties" -> ["description" -> ["type" -> "string", "description" -> "Project description (e.g., 'Build a three-story tavern with common room, kitchen, upstairs rooms, and cellar')"]], "required" -> {"description"}], this, "_tool_create_project");
    agent:add_tool("create_project", create_project_tool);
    record_creation_tool = $llm_agent_tool:mk("record_creation", "Record what was created/built in the current project's knowledge base. Use subject for categories (rooms, passages, objects, decorations), key for the type (e.g., 'created', 'connected', 'placed'), and value for details.", ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "Category: 'rooms', 'passages', 'objects', 'decorations', 'descriptions'"], "key" -> ["type" -> "string", "description" -> "Type of creation: 'created', 'connected', 'placed', 'configured'"], "value" -> ["type" -> "string", "description" -> "Details of what was created (can be multiline)"]], "required" -> {"subject", "key", "value"}], this, "_tool_record_creation");
    agent:add_tool("record_creation", record_creation_tool);
    project_status_tool = $llm_agent_tool:mk("project_status", "Get status of the current building project including what stages/rooms have been completed and overall progress.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_project_status");
    agent:add_tool("project_status", project_status_tool);
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
    !obj_spec:starts_with("#") && return obj_spec;
    set_task_perms(wearer);
    target_obj = `$match:match_object(obj_spec, wearer) ! ANY => #-1';
    return valid(target_obj) ? `target_obj:name() ! ANY => obj_spec' | obj_spec;
  endverb

  verb _format_hud_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format HUD message for a tool call";
    {tool_name, tool_args} = args;
    wearer = this:wearer();
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
    elseif (tool_name == "doc_lookup")
      message = $ansi:colorize("[DOC]", 'bright_blue) + " Loading docs for " + $ansi:colorize(tool_args["target"], 'white);
    elseif (tool_name == "list_messages")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Listing message templates on " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "get_message_template")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Reading " + $ansi:colorize(tool_args["property"], 'yellow) + " on " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "set_message_template")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[MSG]", 'bright_magenta) + " Setting " + $ansi:colorize(tool_args["property"], 'yellow) + " on " + $ansi:colorize(display_name, 'white) + obj_suffix;
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
    elseif (tool_name == "list_rules")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      message = $ansi:colorize("[RULES]", 'bright_magenta) + " Listing rules on " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "set_rule")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      prop_name = tool_args["property"];
      expr = tool_args["expression"];
      "Truncate long expressions";
      if (length(expr) > 50)
        expr = expr[1..50] + "...";
      endif
      message = $ansi:colorize("[RULE]", 'bright_magenta) + " Setting " + $ansi:colorize(prop_name, 'yellow) + " on " + $ansi:colorize(display_name, 'white) + obj_suffix + ": " + expr;
    elseif (tool_name == "show_rule")
      obj_spec = tool_args["object"];
      display_name = this:_resolve_display_name(obj_spec, wearer);
      obj_suffix = display_name != obj_spec ? " (" + obj_spec + ")" | "";
      prop_name = tool_args["property"];
      message = $ansi:colorize("[RULE]", 'bright_magenta) + " Reading " + $ansi:colorize(prop_name, 'yellow) + " on " + $ansi:colorize(display_name, 'white) + obj_suffix;
    elseif (tool_name == "test_rule")
      expr = tool_args["expression"];
      "Truncate long expressions";
      if (length(expr) > 40)
        expr = expr[1..40] + "...";
      endif
      message = $ansi:colorize("[TEST]", 'bright_cyan) + " Testing rule: " + expr;
    elseif (tool_name == "create_project")
      description = tool_args["description"];
      "Truncate long descriptions";
      if (length(description) > 50)
        description = description[1..50] + "...";
      endif
      message = $ansi:colorize("[PROJECT]", 'bright_green) + " Creating project: " + description;
    elseif (tool_name == "record_creation")
      subject = tool_args["subject"];
      key = tool_args["key"];
      message = $ansi:colorize("[RECORD]", 'bright_green) + " Recording " + subject + "/" + key + " in project";
    elseif (tool_name == "project_status")
      message = $ansi:colorize("[PROJECT]", 'bright_yellow) + " Checking building project status";
    elseif (tool_name == "ask_user")
      question = tool_args["question"];
      "Truncate long questions";
      if (length(question) > 60)
        question = question[1..60] + "...";
      endif
      suffix = "";
      if (maphaskey(tool_args, "choices") && typeof(tool_args["choices"]) == LIST && length(tool_args["choices"]) > 0)
        suffix = " [options]";
      elseif (maphaskey(tool_args, "input_type") && typeof(tool_args["input_type"]) == STR)
        suffix = " [" + tool_args["input_type"] + "]";
      endif
      message = $ansi:colorize("[QUESTION]", 'bright_yellow) + " Asking: " + question + suffix;
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
    {room_name, area_spec, parent_spec} = {args_map["name"], maphaskey(args_map, "area") ? args_map["area"] | "", maphaskey(args_map, "parent") ? args_map["parent"] | "$room"};
    parent_obj = $match:match_object(parent_spec, wearer);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Invalid parent object: " + parent_spec);
    "Parse area - default to current area if not specified, 'ether' means free-floating";
    target_area = #-1;
    if (!area_spec || area_spec == "" || area_spec == "here")
      current_room = wearer.location;
      valid(current_room) && (target_area = current_room.location);
    elseif (area_spec != "ether")
      target_area = $match:match_object(area_spec, wearer);
      "Validate that target_area is actually an area, not a room";
      if (valid(target_area) && typeof(target_area) == OBJ && valid(target_area.location) && target_area.location != #-1)
        actual_area = target_area.location;
        return "Error: " + tostr(target_area) + " is a room, not an area. To build in the same area as that room, omit the 'area' parameter or use 'here'. The area containing that room is " + tostr(actual_area) + ".";
      endif
    endif
    server_log("_tool_build_room parsing complete");
    "Create room";
    if (!valid(target_area))
      server_log("_tool_build_room creating free-floating");
      new_room = parent_obj:create();
      area_str = " (free-floating)";
      server_log("_tool_build_room free-floating created");
    else
      server_log("_tool_build_room creating in area");
      cap = wearer:find_capability_for(target_area, 'area);
      area_target = typeof(cap) == FLYWEIGHT ? cap | target_area;
      try
        new_room = area_target:make_room_in(parent_obj);
        area_str = " in " + tostr(target_area);
        server_log("_tool_build_room room created in area");
      except (E_PERM)
        server_log("_tool_build_room permission denied");
        return "Permission denied: " + $grant_utils:format_denial(target_area, 'area, {'add_room});
      endtry
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
    {source_spec, direction, target_spec, return_dir, oneway_flag} = {maphaskey(args_map, "source_room") ? args_map["source_room"] | "", args_map["direction"], args_map["target_room"], maphaskey(args_map, "return_direction") ? args_map["return_direction"] | "", maphaskey(args_map, "oneway") ? args_map["oneway"] | false};
    "Parse direction string into list (handles 'north:n' and 'north,n' formats)";
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
    "Find source room - default to wearer's location if not specified";
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, wearer) | wearer.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
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
      return "Permission denied: " + $grant_utils:format_denial(source_room, 'room, {'dig_from});
    endtry
    to_cap = wearer:find_capability_for(target_room, 'room);
    to_target = typeof(to_cap) == FLYWEIGHT ? to_cap | target_room;
    try
      to_target:check_can_dig_into();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(target_room, 'room, {'dig_into});
    endtry
    "Create passage - one-way if explicitly requested or no return direction";
    passage = oneway_flag || !to_dirs ? $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, "", {}, "", false, true) | $passage:mk(source_room, from_dirs[1], from_dirs, "", true, target_room, to_dirs[1], to_dirs, "", true, true);
    "Register with area";
    area_cap = wearer:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    area_target:create_passage(from_target, to_target, passage);
    "Report";
    msg = oneway_flag ? "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way). (@dig command available)" | !to_dirs ? "Dug passage: " + from_dirs:join(",") + " to " + tostr(target_room) + " (one-way - no return direction inferred). (@dig command available)" | "Dug passage: " + from_dirs:join(",") + " | " + to_dirs:join(",") + " connecting to " + tostr(target_room) + ". (@dig command available)";
    return msg;
  endverb

  verb _parse_direction_spec (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse direction string into list (handles 'north:n' and 'north,n' formats)";
    {dir_spec} = args;
    !dir_spec:contains(":") && return $str_proto:split(dir_spec, ",");
    colon_parts = $str_proto:split(dir_spec, ":");
    length(colon_parts) < 2 && return {dir_spec};
    return {colon_parts[1], @$str_proto:split(colon_parts[2], ",")};
  endverb

  verb _tool_remove_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Remove a passage between two rooms";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {target_spec, source_spec} = {args_map["target_room"], maphaskey(args_map, "source_room") ? args_map["source_room"] | ""};
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, wearer) | wearer.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    target_room = $match:match_object(target_spec, wearer);
    typeof(target_room) == OBJ || raise(E_INVARG, "Target room not found");
    valid(target_room) || raise(E_INVARG, "Target room no longer exists");
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    target_room.location == area || raise(E_INVARG, "Both rooms must be in the same area");
    passage = area:passage_for(source_room, target_room);
    !passage && return "No passage found between " + tostr(source_room) + " and " + tostr(target_room) + ".";
    "Collect labels for reporting";
    {side_a_room, side_b_room} = {`passage.side_a_room ! ANY => #-1', `passage.side_b_room ! ANY => #-1'};
    labels = {};
    source_room == side_a_room && (`passage.side_a_label ! ANY => ""' != "") && (labels = {@labels, passage.side_a_label});
    source_room == side_b_room && (`passage.side_b_label ! ANY => ""' != "") && (labels = {@labels, passage.side_b_label});
    target_room == side_a_room && (`passage.side_a_label ! ANY => ""' != "") && !(passage.side_a_label in labels) && (labels = {@labels, passage.side_a_label});
    target_room == side_b_room && (`passage.side_b_label ! ANY => ""' != "") && !(passage.side_b_label in labels) && (labels = {@labels, passage.side_b_label});
    "Check permissions";
    from_cap = wearer:find_capability_for(source_room, 'room);
    from_target = typeof(from_cap) == FLYWEIGHT ? from_cap | source_room;
    try
      from_target:check_can_dig_from();
    except (E_PERM)
      return "Permission denied: " + $grant_utils:format_denial(source_room, 'room, {'dig_from});
    endtry
    "Remove passage via area";
    area_cap = wearer:find_capability_for(area, 'area);
    area_target = typeof(area_cap) == FLYWEIGHT ? area_cap | area;
    result = area_target:remove_passage(from_target, target_room);
    label_str = labels ? " (" + labels:join("/") + ")" | "";
    return result ? "Removed passage" + label_str + " between " + tostr(source_room) + " and " + tostr(target_room) + "." | "Failed to remove passage (may have already been removed).";
  endverb

  verb _tool_set_passage_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set description and ambient flag for a passage";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {direction, description, ambient, source_spec} = {args_map["direction"], args_map["description"], maphaskey(args_map, "ambient") ? args_map["ambient"] | true, maphaskey(args_map, "source_room") ? args_map["source_room"] | ""};
    typeof(description) == STR && ("{" in description) && ("}" in description) && (description = `$sub_utils:compile(description) ! ANY => description');
    source_room = source_spec && source_spec != "" ? $match:match_object(source_spec, wearer) | wearer.location;
    typeof(source_room) == OBJ || raise(E_INVARG, "Source room not found");
    valid(source_room) || raise(E_INVARG, "Source room no longer exists");
    area = source_room.location;
    valid(area) || raise(E_INVARG, "Source room is not in an area");
    passages = area:passages_from(source_room);
    !passages && return "No passages from " + tostr(source_room) + ".";
    target_passage = area:find_passage_by_direction(source_room, direction);
    !target_passage && return "No passage found in direction '" + direction + "' from " + tostr(source_room) + ".";
    from_cap = wearer:find_capability_for(source_room, 'room);
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

  verb _tool_create_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create an object from a parent";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {parent_spec, name_spec, extra_aliases} = {args_map["parent"], args_map["name"], maphaskey(args_map, "aliases") ? args_map["aliases"] | {}};
    {primary_name, parsed_aliases} = $str_proto:parse_name_aliases(name_spec);
    final_aliases = {@parsed_aliases, @extra_aliases};
    !primary_name && raise(E_INVARG, "Object name cannot be blank");
    set_task_perms(wearer);
    parent_obj = $match:match_object(parent_spec, wearer);
    typeof(parent_obj) == OBJ || raise(E_INVARG, "Parent not found");
    valid(parent_obj) || raise(E_INVARG, "Parent no longer exists");
    is_fertile = `parent_obj.fertile ! E_PROPNF => false';
    !is_fertile && !wearer.wizard && parent_obj.owner != wearer && raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj));
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, final_aliases);
    new_obj:moveto(wearer);
    message = "Created \"" + primary_name + "\" (" + tostr(new_obj) + ") from " + tostr(parent_obj) + " in your inventory.";
    final_aliases && (message = message + " Aliases: " + final_aliases:join(", ") + ".");
    return message + " (@create command available)";
  endverb

  verb _tool_recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Permanently destroy an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj));
    {obj_name, obj_id} = {target_obj.name, tostr(target_obj)};
    target_obj:destroy();
    return "Recycled \"" + obj_name + "\" (" + obj_id + "). (@recycle command available)";
  endverb

  verb _tool_rename_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Rename an object";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You do not have permission to rename " + tostr(target_obj));
    {new_name, new_aliases} = $str_proto:parse_name_aliases(args_map["name"]);
    !new_name && raise(E_INVARG, "Object name cannot be blank");
    old_name = `target_obj.name ! ANY => "(no name)"';
    target_obj:set_name_aliases(new_name, new_aliases);
    message = "Renamed \"" + old_name + "\" (" + tostr(target_obj) + ") to \"" + new_name + "\".";
    new_aliases && (message = message + " Aliases: " + new_aliases:join(", ") + ".");
    return message + " (@rename command available)";
  endverb

  verb _tool_describe_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object description";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You do not have permission to describe " + tostr(target_obj));
    !args_map["description"] && raise(E_INVARG, "Description cannot be blank");
    target_obj.description = args_map["description"];
    return "Set description of \"" + `target_obj.name ! ANY => tostr(target_obj)' + "\" (" + tostr(target_obj) + "). (@describe command available)";
  endverb

  verb _tool_set_integrated_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set object's integrated description - description that becomes part of room description";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You do not have permission to modify " + tostr(target_obj));
    target_obj.integrated_description = args_map["integrated_description"];
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    return args_map["integrated_description"] == "" ? "Cleared integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "). (@integrate command available)" | "Set integrated description of \"" + obj_name + "\" (" + tostr(target_obj) + "). When in a room, this will appear in the room description. (@integrate command available)";
  endverb

  verb _tool_test_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Test a rule expression with specific variable bindings";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {expression, bindings} = {args_map["expression"], args_map["bindings"]};
    typeof(expression) == STR || raise(E_TYPE, "expression must be string");
    typeof(bindings) == MAP || raise(E_TYPE, "bindings must be object/map");
    set_task_perms(wearer);
    compiled = `$rule_engine:parse_expression(expression, 'test_rule, wearer) ! ANY => E_INVARG';
    compiled == E_INVARG && return "ERROR: Rule parsing failed. Check syntax. Expression: " + expression;
    validation = $rule_engine:validate_rule(compiled);
    !validation['valid] && return "ERROR: Rule validation failed: " + validation['warnings]:join("; ") + ". Expression: " + expression;
    "Convert bindings map keys from strings to symbols";
    converted_bindings = [];
    for key in (mapkeys(bindings))
      converted_bindings[tosym(key)] = `$match:match_object(bindings[key], wearer) ! ANY => bindings[key]';
    endfor
    result = $rule_engine:evaluate(compiled, converted_bindings);
    if (result['success])
      return "SUCCESS: Rule evaluated to true. Bindings: " + toliteral(converted_bindings);
    endif
    reason = maphaskey(result, 'reason) ? (typeof(result['reason]) == STR ? result['reason] | toliteral(result['reason])) | "rule did not match";
    return "FAILED: Rule evaluated to false. Reason: " + reason + ". Bindings: " + toliteral(converted_bindings);
  endverb

  verb _tool_move_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Move an object to a new location";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    {obj_spec, dest_spec} = {args_map["object"], args_map["destination"]};
    target_obj = $match:match_object(obj_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You do not have permission to move " + tostr(target_obj));
    dest_obj = $match:match_object(dest_spec, wearer);
    typeof(dest_obj) == OBJ || raise(E_INVARG, "Destination not found");
    valid(dest_obj) || raise(E_INVARG, "Destination no longer exists");
    old_location_name = valid(target_obj.location) ? `target_obj.location.name ! ANY => tostr(target_obj.location)' | "(nowhere)";
    target_obj:moveto(dest_obj);
    return "Moved \"" + `target_obj.name ! ANY => tostr(target_obj)' + "\" (" + tostr(target_obj) + ") from " + old_location_name + " to \"" + `dest_obj.name ! ANY => tostr(dest_obj)' + "\" (" + tostr(dest_obj) + ").";
  endverb

  verb _tool_grant_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Grant capabilities to a player";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {target_spec, category, perms, grantee_spec} = {args_map["target"], args_map["category"], args_map["permissions"], args_map["grantee"]};
    set_task_perms(wearer);
    target_obj = $match:match_object(target_spec, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Target not found");
    valid(target_obj) || raise(E_INVARG, "Target no longer exists");
    grantee = $match:match_object(grantee_spec, wearer);
    typeof(grantee) == OBJ || raise(E_INVARG, "Grantee not found");
    valid(grantee) || raise(E_INVARG, "Grantee no longer exists");
    !wearer.wizard && target_obj.owner != wearer && raise(E_PERM, "You must be owner or wizard to grant capabilities for " + tostr(target_obj));
    perm_symbols = {tostr(p):to_symbol() for p in (perms)};
    $root:grant_capability(target_obj, perm_symbols, grantee, tostr(category):to_symbol());
    return "Granted " + $grant_utils:format_grant_with_name(target_obj, tostr(category):to_symbol(), perm_symbols) + " to " + grantee:name() + " (" + tostr(grantee) + "). (@grant command available)";
  endverb

  verb _tool_audit_owned (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all owned objects";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    owned = sort(owned_objects(wearer));
    !owned && return "You don't own any objects. (@audit command available)";
    result = "You own " + tostr(length(owned)) + " objects:\n";
    for o in (owned)
      result = result + tostr(o) + ": \"" + `o.name ! ANY => "(no name)"' + "\" (parent: " + (valid(`parent(o) ! ANY => #-1') ? tostr(parent(o)) | "(none)") + ")\n";
    endfor
    return result + "(@audit command available)";
  endverb

  verb _tool_area_map (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get list of all rooms in the current area";
    {args_map} = args;
    wearer = this:_action_perms_check();
    current_room = wearer.location;
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

  verb _tool_find_route (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find route between two rooms";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {to_spec, from_spec} = {args_map["to_room"], maphaskey(args_map, "from_room") ? args_map["from_room"] | ""};
    set_task_perms(wearer);
    from_room = from_spec && from_spec != "" ? $match:match_object(from_spec, wearer) | wearer.location;
    typeof(from_room) == OBJ || return "Error: Could not find starting room '" + from_spec + "'.";
    !valid(from_room) && return "Error: You are not in a room.";
    area = from_room.location;
    !valid(area) && return "Error: Starting room is not in an area.";
    to_room = $match:match_object(to_spec, wearer);
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
      direction = room == side_a_room ? `passage.side_a_label ! ANY => "passage"' | room == side_b_room ? `passage.side_b_label ! ANY => "passage"' | "passage";
      next_room = path[i + 1][1];
      result = {@result, "  " + tostr(i) + ". Go " + direction + " to " + `next_room:name() ! ANY => tostr(next_room)' + " (" + tostr(next_room) + ")"};
    endfor
    return result:join("\n");
  endverb

  verb _tool_list_prototypes (this none this) owner: HACKER flags: "rxd"
    "Tool: List available prototype objects for building";
    {args_map} = args;
    prototypes = $sysobj:list_builder_prototypes();
    result = {"Available prototypes for creating objects:", ""};
    for proto_info in (prototypes)
      result = {@result, "* " + proto_info["name"] + " (" + proto_info["object"] + ")", "  " + proto_info["description"], ""};
    endfor
    return {@result, "Use these with the create_object tool or as the 'parent' parameter in build_room."}:join("\n");
  endverb

  verb _tool_inspect_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Inspect an object and return detailed information";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    target = $match:match_object(args_map["object"], wearer);
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

  verb _tool_create_project (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Create a new building project task";
    {args_map} = args;
    wearer = this:_action_perms_check();
    description = args_map["description"];
    typeof(description) == STR || raise(E_TYPE("Description must be string"));
    task = this.agent:create_task(description);
    this.current_building_task = task.task_id;
    task:mark_in_progress();
    return "Building project #" + tostr(task.task_id) + " started: " + description;
  endverb

  verb _tool_record_creation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Record a creation in current project's knowledge base";
    {args_map} = args;
    wearer = this:_action_perms_check();
    {subject, key, value} = {args_map["subject"], args_map["key"], args_map["value"]};
    typeof(subject) == STR || raise(E_TYPE("Subject must be string"));
    typeof(key) == STR || raise(E_TYPE("Key must be string"));
    this.current_building_task == -1 && return "No active building project. Create one with create_project first.";
    task_obj = this.agent.current_tasks[this.current_building_task];
    !valid(task_obj) && return "Building project #" + tostr(this.current_building_task) + " is no longer valid.";
    task_obj:add_finding(subject, key, value);
    return "Recorded [" + subject + "/" + key + "]";
  endverb

  verb _tool_project_status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get current building project status";
    {args_map} = args;
    wearer = this:_action_perms_check();
    this.current_building_task == -1 && return "No active building project.";
    task_obj = this.agent.current_tasks[this.current_building_task];
    !valid(task_obj) && return "Building project #" + tostr(this.current_building_task) + " is no longer valid.";
    status = task_obj:get_status();
    status_lines = {"Project #" + tostr(status["task_id"]) + ": " + status["description"], "Status: " + tostr(status["status"])};
    status["status"] == 'completed && (status_lines = {@status_lines, "Completed: " + status["result"]});
    status["status"] == 'failed && (status_lines = {@status_lines, "Error: " + status["error"]});
    status["status"] == 'blocked && (status_lines = {@status_lines, "Blocked: " + status["error"]});
    status["subtask_count"] > 0 && (status_lines = {@status_lines, "Stages: " + tostr(status["subtask_count"])});
    return {@status_lines, "Started: " + tostr(ctime(status["started_at"]))}:join("\n");
  endverb

  verb _tool_list_reactions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List reactions on an object with details";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    target_obj = $match:match_object(obj_str, wearer);
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
        if (effect.type)
          lines = {@lines, "    - " + tostr(effect.type)};
        endif
      endfor
      "Enabled";
      lines = {@lines, "  Enabled: " + (reaction.enabled ? "yes" | "no")};
      lines = {@lines, ""};
    endfor
    return lines:join("\n");
  endverb

  verb _tool_add_reaction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Add a reaction to an object. Property name must end with _reaction.";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property_name"];
    trigger_str = args_map["trigger"];
    when_str = args_map["when"];
    effects_str = args_map["effects"];
    "Parse object";
    target_obj = $match:match_object(obj_str, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    "Validate property name";
    prop_name:ends_with("_reaction") || raise(E_INVARG, "Property name must end with '_reaction'");
    "Check permission";
    if (!wearer.wizard && target_obj.owner != wearer)
      return "Permission denied: You do not own " + tostr(target_obj) + " and are not a wizard.";
    endif
    "Parse trigger";
    parsed_trigger = eval("return " + trigger_str + ";");
    if (!parsed_trigger[1])
      return "Error parsing trigger: " + tostr(parsed_trigger[2]);
    endif
    trigger = parsed_trigger[2];
    "Parse effects";
    parsed_effects = eval("return " + effects_str + ";");
    if (!parsed_effects[1])
      return "Error parsing effects: " + tostr(parsed_effects[2]);
    endif
    effects = parsed_effects[2];
    "When clause";
    when_clause = when_str;
    if (when_str != "0" && typeof(when_str) == STR)
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
      add_property(target_obj, prop_name, reaction, {wearer, "r"});
    endif

    return "Set " + tostr(target_obj) + "." + prop_name;
  endverb

  verb _tool_set_reaction_enabled (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Enable or disable a reaction by property name";
    {args_map} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    obj_str = args_map["object"];
    prop_name = args_map["property_name"];
    enabled = args_map["enabled"];
    "Parse object";
    target_obj = $match:match_object(obj_str, wearer);
    typeof(target_obj) == OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    "Validate property name";
    prop_name:ends_with("_reaction") || raise(E_INVARG, "Property name must end with '_reaction'");
    "Check permission";
    if (!wearer.wizard && target_obj.owner != wearer)
      return "Permission denied: You do not own " + tostr(target_obj);
    endif

    "Check property exists and is a reaction";
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property not found: " + prop_name);
    reaction = target_obj.(prop_name);
    typeof(reaction) == FLYWEIGHT && reaction.delegate == $reaction || raise(E_INVARG, prop_name + " is not a reaction");

    "Set enabled state";
    reaction.enabled = enabled;
    target_obj.(prop_name) = reaction;

    return (enabled ? "Enabled" | "Disabled") + " " + tostr(target_obj) + "." + prop_name;
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Activate when worn";
    !valid(this.agent) && this:configure();
    wearer = this.location;
    valid(wearer) || return;
    wearer:inform_current($event:mk_info(wearer, "The compass needle spins and aligns. Spatial construction interface ready. Use 'use compass' or 'interact with compass' to begin."));
    this:_show_token_usage(wearer);
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate when removed";
    wearer = this.location;
    valid(wearer) || return;
    this:_show_token_usage(wearer);
    wearer:inform_current($event:mk_info(wearer, "The compass needle falls idle. Spatial construction interface offline."));
  endverb

  verb plan_building (none none none) owner: HACKER flags: "rd"
    "Create a new building project task to track construction progress";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the compass to start a building project."));
      return;
    endif
    !valid(this.agent) && this:configure();
    task = this.agent:create_task("Building Project: " + argstr);
    this.current_building_task = task.task_id;
    task:mark_in_progress();
    player:inform_current($event:mk_info(player, $ansi:colorize("[PROJECT]", 'bright_green) + " Building Project #" + tostr(task.task_id) + " started: " + argstr):with_presentation_hint('inset));
  endverb

  verb get_building_progress (none none none) owner: HACKER flags: "rd"
    "Display current building project status and created items";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the compass."));
      return;
    endif
    if (this.current_building_task == -1)
      player:inform_current($event:mk_info(player, $ansi:colorize("[PROJECT]", 'bright_green) + " No active building project. Use 'plan building <description>' to begin."):with_presentation_hint('inset));
      return;
    endif
    task_obj = this.agent.current_tasks[this.current_building_task];
    if (!valid(task_obj))
      player:inform_current($event:mk_info(player, $ansi:colorize("[ERROR]", 'red) + " Building project #" + tostr(this.current_building_task) + " is no longer available."));
      return;
    endif
    status = task_obj:get_status();
    progress_lines = {$ansi:colorize("[PROJECT STATUS]", 'bright_green), "  ID: " + tostr(status["task_id"]), "  Status: " + tostr(status["status"]), "  Description: " + status["description"]};
    status["status"] == 'completed && (progress_lines = {@progress_lines, "  Completed: " + status["result"]});
    status["status"] == 'failed && (progress_lines = {@progress_lines, "  Error: " + status["error"]});
    status["status"] == 'blocked && (progress_lines = {@progress_lines, "  Blocked: " + status["error"]});
    status["subtask_count"] > 0 && (progress_lines = {@progress_lines, "  Stages: " + tostr(status["subtask_count"])});
    player:inform_current($event:mk_info(player, progress_lines:join("\n")):with_presentation_hint('inset));
  endverb

  verb complete_building (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Mark current building project as completed";
    {?result = "Building project concluded."} = args;
    this.current_building_task == -1 && return "No active building project";
    task_obj = this.agent.current_tasks[this.current_building_task];
    !valid(task_obj) && return "Building project task no longer available";
    task_obj:mark_complete(result);
    this.current_building_task = -1;
    return "Building project #" + tostr(task_obj.task_id) + " completed.";
  endverb
endobject
