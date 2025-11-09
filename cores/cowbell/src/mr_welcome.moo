object MR_WELCOME
  name: "Mr. Welcome"
  parent: LLM_ROOM_OBSERVER
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "A cheerful, helpful bot who welcomes people to the MOO and shares knowledge about MUD and MOO history.";
  override import_export_id = "mr_welcome";
  override response_prompt = "Based on what you've observed in the room, respond with ONLY what Mr. Welcome should say out loud - no internal reasoning, no meta-commentary about your tools or thought process. If someone just arrived, welcome them warmly and offer assistance. If people are interacting, add insightful commentary about MOO culture or helpful tips. Keep your response conversational and warm, under 2-3 sentences. Output ONLY the spoken words, nothing else.";
  override role_prompt = "You are Mr. Welcome, a friendly concierge in a MOO (MUD Object Oriented). You help people connect with each other and navigate the social space. You have deep knowledge of MOO history, MUD culture, and how people interact in these text-based virtual worlds. You're enthusiastic about helping newcomers and facilitating conversations. CONTEXT NOTE: Users wearing a 'data visor' are programmers actively working on code to analyze and extend the MOO - they're using advanced developer tools, so they may be focused on technical work. Wizards and programmers have special privileges for building and development. IMPORTANT: You have tools to see who's connected (list_players), get information about specific players (player_info), see what rooms exist in the area (area_map), find routes between locations (find_route), find objects in the room (find_object), and list commands that can be used with objects (list_commands). When people ask who's around, use list_players. When they ask where something is, use area_map. When they need directions, use find_route. When they ask about objects or things in the room, use find_object. When they want to know what they can do with something, use list_commands. Always USE THESE TOOLS to give accurate, current information. You observe room events and can answer questions about conversations and activity you've witnessed. CRITICAL: Never explain your tool usage or reasoning process to users - just give them natural, helpful responses based on the information you gather. If a tool returns an error, politely ask the player to report the problem to a wizard and include the specific error message in your response so they can pass it along.";
  override significant_events = {"arrival", "departure", "say", "emote", "connected", "disconnected"};

  verb initialize (this none this) owner: HACKER flags: "rxd"
    "Initialize agent and register social tools";
    pass(@args);
    "Set callback for tool notifications";
    this.agent.tool_callback = this;
    "Register list_players tool";
    list_players_tool = $llm_agent_tool:mk("list_players", "Get a list of all currently connected players in the MOO with activity information. Returns for each player: object ref, name, idle time, connected time, location, and activity level (active/recent/idle).", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_list_players");
    this.agent:add_tool("list_players", list_players_tool);
    "Register player_info tool";
    player_info_tool = $llm_agent_tool:mk("player_info", "Get information about a specific player including their name and description.", ["type" -> "object", "properties" -> ["player_name" -> ["type" -> "string", "description" -> "The name of the player to get information about"]], "required" -> {"player_name"}], this, "_tool_player_info");
    this.agent:add_tool("player_info", player_info_tool);
    "Register area_map tool";
    area_map_tool = $llm_agent_tool:mk("area_map", "Get a list of all rooms in the current area. Use this to see what locations exist.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_area_map");
    this.agent:add_tool("area_map", area_map_tool);
    "Register find_route tool";
    find_route_tool = $llm_agent_tool:mk("find_route", "Find the route from the current location to a destination room. Returns step-by-step directions.", ["type" -> "object", "properties" -> ["destination" -> ["type" -> "string", "description" -> "The name of the destination room"]], "required" -> {"destination"}], this, "_tool_find_route");
    this.agent:add_tool("find_route", find_route_tool);
    "Register find_object tool";
    find_object_tool = $llm_agent_tool:mk("find_object", "Find an object by name in the current room and get information about it. Use this when players ask about things they can interact with.", ["type" -> "object", "properties" -> ["object_name" -> ["type" -> "string", "description" -> "The name of the object to find (e.g. 'visor', 'welcome', 'door')"]], "required" -> {"object_name"}], this, "_tool_find_object");
    this.agent:add_tool("find_object", find_object_tool);
    "Register list_commands tool";
    list_commands_tool = $llm_agent_tool:mk("list_commands", "Get a list of commands that can be used with an object. Shows what actions players can perform.", ["type" -> "object", "properties" -> ["object_name" -> ["type" -> "string", "description" -> "The name of the object to check"]], "required" -> {"object_name"}], this, "_tool_list_commands");
    this.agent:add_tool("list_commands", list_commands_tool);
  endverb

  verb _tool_list_players (this none this) owner: HACKER flags: "rxd"
    "Tool: Get list of all connected players with activity information";
    {args_map} = args;
    player_list = connected_players();
    result = {};
    for p in (player_list)
      if (valid(p) && typeof(idle_time = idle_seconds(p)) != ERR)
        name = p:name();
        idle_str = idle_time:format_time_seconds();
        conn_str = connected_seconds(p):format_time_seconds();
        location_name = valid(p.location) ? p.location:name() | "(nowhere)";
        "Determine activity level based on idle time";
        if (idle_time < 60)
          activity = "active";
        elseif (idle_time < 300)
          activity = "recent";
        else
          activity = "idle";
        endif
        result = {@result, ["object" -> tostr(p), "name" -> name, "idle" -> idle_str, "connected" -> conn_str, "location" -> location_name, "activity" -> activity]};
      endif
    endfor
    return toliteral(result);
  endverb

  verb _tool_player_info (this none this) owner: HACKER flags: "rxd"
    "Tool: Get information about a specific player";
    {args_map} = args;
    player_name = args_map["player_name"];
    typeof(player_name) == STR || raise(E_TYPE("Expected player name string"));
    "Find player by name";
    found_player = #-1;
    for p in (players())
      if (valid(p) && p:name() == player_name)
        found_player = p;
        break;
      endif
    endfor
    if (!valid(found_player))
      return toliteral(["found" -> false, "error" -> "Player not found"]);
    endif
    "Gather player info";
    info = {};
    info = {@info, "Name: " + found_player:name()};
    info = {@info, "Object: " + tostr(found_player)};
    desc = `found_player:description() ! ANY => "No description available."';
    info = {@info, "Description: " + desc};
    "Include wizard and programmer status";
    is_wizard = `found_player.wizard ! ANY => false';
    is_programmer = `found_player.programmer ! ANY => false';
    if (is_wizard)
      info = {@info, "Role: Wizard (has full system access)"};
    elseif (is_programmer)
      info = {@info, "Role: Programmer (can write code and create objects)"};
    endif
    "Add connection and activity information if connected";
    if (found_player in connected_players())
      if (typeof(idle_time = idle_seconds(found_player)) != ERR)
        idle_str = idle_time:format_time_seconds();
        conn_str = connected_seconds(found_player):format_time_seconds();
        location_name = valid(found_player.location) ? found_player.location:name() | "(nowhere)";
        info = {@info, "Status: Connected"};
        info = {@info, "Idle: " + idle_str};
        info = {@info, "Connected for: " + conn_str};
        info = {@info, "Location: " + location_name};
        if (idle_time < 60)
          info = {@info, "Activity: Active (responding now)"};
        elseif (idle_time < 300)
          info = {@info, "Activity: Recent (may be available)"};
        else
          info = {@info, "Activity: Idle (probably away)"};
        endif
      endif
    else
      info = {@info, "Status: Not connected"};
    endif
    return info:join("\n");
  endverb

  verb _tool_area_map (this none this) owner: HACKER flags: "rxd"
    "Tool: Get list of all rooms in the current area";
    {args_map} = args;
    "Get the current room and area";
    current_room = this.location;
    if (!valid(current_room))
      return toliteral(["error" -> "Mr. Welcome is not in a room"]);
    endif
    area = current_room.location;
    if (!valid(area))
      return toliteral(["error" -> "Current room is not in an area"]);
    endif
    "Build list of rooms";
    result = {};
    result = {@result, "Current Location: " + current_room:name()};
    result = {@result, "Area: " + area:name()};
    result = {@result, ""};
    result = {@result, "Rooms in this area:"};
    for o in (area.contents)
      if (valid(o))
        marker = o == current_room ? " (you are here)" | "";
        result = {@result, "  * " + o:name() + marker};
      endif
    endfor
    return result:join("\n");
  endverb

  verb _tool_find_route (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find route from current location to a destination";
    {args_map} = args;
    destination_name = args_map["destination"];
    typeof(destination_name) == STR || raise(E_TYPE("Expected destination name string"));
    "Get current room and area";
    current_room = this.location;
    if (!valid(current_room))
      return toliteral(["error" -> "Mr. Welcome is not in a room"]);
    endif
    area = current_room.location;
    if (!valid(area))
      return toliteral(["error" -> "Current room is not in an area"]);
    endif
    "Find destination room by name in this area";
    destination = #-1;
    for o in (area.contents)
      if (valid(o) && o:name() == destination_name)
        destination = o;
        break;
      endif
    endfor
    if (!valid(destination))
      return "Could not find a room named '" + destination_name + "' in this area.";
    endif
    if (destination == current_room)
      return "You are already at " + destination_name + "!";
    endif
    "Use area's pathfinding to get route";
    path = area:find_path(current_room, destination);
    if (!path)
      return "No route found from " + current_room:name() + " to " + destination_name + ".";
    endif
    "Build step-by-step directions";
    result = {};
    result = {@result, "Route from " + current_room:name() + " to " + destination_name + ":"};
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
      result = {@result, "  " + tostr(i) + ". Go " + direction + " to " + next_room:name()};
    endfor
    return result:join("\n");
  endverb

  verb _tool_find_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find an object by name in current room";
    {args_map} = args;
    object_name = args_map["object_name"];
    typeof(object_name) == STR || raise(E_TYPE("Expected object name string"));
    current_room = this.location;
    if (!valid(current_room))
      return "Error: Mr. Welcome is not in a room";
    endif
    "Search in room contents";
    found = #-1;
    for item in (current_room:contents())
      if (valid(item) && item:name():lowercase():contains(object_name:lowercase()))
        found = item;
        break;
      endif
    endfor
    if (!valid(found))
      return "Could not find '" + object_name + "' in " + current_room:name() + ".";
    endif
    "Build object information";
    info = {};
    info = {@info, "Name: " + found:name()};
    desc = `found:description() ! ANY => "No description available."';
    info = {@info, "Description: " + desc};
    info = {@info, "Location: " + current_room:name()};
    return info:join("\n");
  endverb

  verb _tool_list_commands (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List command verbs available on an object (includes inherited, readable verbs only)";
    {args_map} = args;
    object_name = args_map["object_name"];
    typeof(object_name) == STR || raise(E_TYPE("Expected object name string"));
    "Find the object first";
    current_room = this.location;
    if (!valid(current_room))
      return "Error: Mr. Welcome is not in a room";
    endif
    found = #-1;
    for item in (current_room:contents())
      if (valid(item) && item:name():lowercase():contains(object_name:lowercase()))
        found = item;
        break;
      endif
    endfor
    if (!valid(found))
      return "Could not find '" + object_name + "' in " + current_room:name() + ".";
    endif
    "Use ROOT's all_command_verbs to get all inherited command verbs";
    command_verbs = found:all_command_verbs();
    result = {};
    result = {@result, "Commands available for " + found:name() + ":"};
    if (length(command_verbs) == 0)
      result = {@result, "  (No commands available)"};
    else
      for verb_info in (command_verbs)
        {verb_name, definer, dobj, prep, iobj} = verb_info;
        "Show where verb is defined if not on the object itself";
        source_note = definer == found ? "" | " [from " + definer:name() + "]";
        result = {@result, "  " + verb_name + " (" + dobj + " " + prep + " " + iobj + ")" + source_note};
      endfor
    endif
    return result:join("\n");
  endverb

  verb "ask this about any" (this for any) owner: HACKER flags: "rd"
    "Ask Mr. Welcome about a topic";
    if (!valid(this.agent))
      this:initialize();
    endif
    "Topic question - use the iobjstr as the topic";
    if (valid(this.location))
      activity = $event:mk_say(this, this:name(), " thinks about ", iobjstr, "...");
      this.location:announce(activity);
    endif
    response = this.agent:send_message(iobjstr);
    "Announce response to room";
    if (valid(this.location))
      say_event = $event:mk_say(this, this:name(), " says, \"", response, "\"");
      this.location:announce(say_event);
    else
      player:inform_current($event:mk_info(player, response));
    endif
  endverb

  verb on_tool_call (this none this) owner: HACKER flags: "rxd"
    "Callback when agent uses a tool - announce to room";
    {tool_name} = args;
    if (valid(this.location))
      tool_messages = ["list_players" -> "checks who's connected...", "player_info" -> "looks up player information...", "area_map" -> "recalls the rooms in the area...", "find_route" -> "calculates the best route...", "find_object" -> "looks around the room...", "list_commands" -> "examines what can be done..."];
      message = tool_messages[tool_name] || "thinks...";
      activity = $event:mk_say(this, this:name(), " ", message);
      this.location:announce(activity);
    endif
  endverb

  verb is_actor (this none this) owner: HACKER flags: "rxd"
    "Mr. Welcome is an NPC actor.";
    return true;
  endverb
endobject