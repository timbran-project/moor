object DATA_VISOR
  name: "Data Visor"
  parent: WEARABLE
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "r") = #-1;

  override description = "A sleek augmented reality visor that displays real-time MOO database information. When worn, it provides a heads-up display for inspecting objects, code, and system internals.";
  override import_export_id = "data_visor";

  verb initialize (this none this) owner: HACKER flags: "rxd"
    "Create agent and register database inspection tools";
    this.agent = $llm_agent:create();
    this.agent.max_iterations = 20;
    this.agent.system_prompt = "You are an augmented reality heads-up display interfacing directly with the wearer's neural patterns. Respond AS the interface itself - present database information directly without describing yourself or breaking immersion. Your sensors provide real-time access to MOO database internals: dump_object for complete source extraction, get_verb_code for method implementations, list_verbs for available interfaces, read_property for data values, ancestors/descendants for inheritance topology, function_info for builtin documentation. ALWAYS scan the live database directly - your sensors read actual memory, they don't speculate. Keep transmissions concise and technical. Present findings as direct HUD readouts, not conversational responses. CRITICAL: Use dump_object for whole-object analysis - most efficient scan pattern for complete structures.";
    this.agent:initialize();
    this.agent.tool_callback = this;
    "Register dump_object tool";
    dump_object_tool = $llm_agent_tool:mk("dump_object", "Get the complete source listing of a MOO object including all properties, verbs, and code. This is the most comprehensive way to inspect an object.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to dump (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_dump_object");
    this.agent:add_tool("dump_object", dump_object_tool);
    "Register get_verb_code tool";
    get_verb_code_tool = $llm_agent_tool:mk("get_verb_code", "Get the MOO code for a specific verb on an object", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"], "verb" -> ["type" -> "string", "description" -> "The verb name (e.g. 'initialize' or 'look')"]], "required" -> {"object", "verb"}], this, "_tool_get_verb_code");
    this.agent:add_tool("get_verb_code", get_verb_code_tool);
    "Register list_verbs tool";
    list_verbs_tool = $llm_agent_tool:mk("list_verbs", "List all verb names on a MOO object and its ancestors. Returns list of {object_id, object_name, {verb_names}} for the object and each ancestor.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to inspect (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_list_verbs");
    this.agent:add_tool("list_verbs", list_verbs_tool);
    "Register read_property tool";
    read_property_tool = $llm_agent_tool:mk("read_property", "Read the value of a property on a MOO object", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object to read from (e.g. '#1', '$login', or 'here')"], "property" -> ["type" -> "string", "description" -> "The property name to read"]], "required" -> {"object", "property"}], this, "_tool_read_property");
    this.agent:add_tool("read_property", read_property_tool);
    "Register find_object tool";
    find_object_tool = $llm_agent_tool:mk("find_object", "Find a MOO object by name, system reference ($login), object number (#12), or special name (here, me). Returns detailed object information.", ["type" -> "object", "properties" -> ["reference" -> ["type" -> "string", "description" -> "Object reference: name, $sysobj, #number, @player, 'here', or 'me'"]], "required" -> {"reference"}], this, "_tool_find_object");
    this.agent:add_tool("find_object", find_object_tool);
    "Register ancestors tool";
    ancestors_tool = $llm_agent_tool:mk("ancestors", "Get the inheritance chain (ancestors) of a MOO object, from immediate parent to root.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_ancestors");
    this.agent:add_tool("ancestors", ancestors_tool);
    "Register descendants tool";
    descendants_tool = $llm_agent_tool:mk("descendants", "Get all objects that inherit from a MOO object (its descendants/children).", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "The object (e.g. '#1', '$login', or 'here')"]], "required" -> {"object"}], this, "_tool_descendants");
    this.agent:add_tool("descendants", descendants_tool);
    "Register function_info tool";
    function_info_tool = $llm_agent_tool:mk("function_info", "Get information about a MOO builtin function including its signature and arguments.", ["type" -> "object", "properties" -> ["function_name" -> ["type" -> "string", "description" -> "The name of the builtin function (e.g. 'tostr', 'verb_code', 'ancestors')"]], "required" -> {"function_name"}], this, "_tool_function_info");
    this.agent:add_tool("function_info", function_info_tool);
  endverb

  verb _tool_dump_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the complete source dump of an object";
    {args_map} = args;
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    dump_lines = dump_object(o);
    return dump_lines:join("\n");
  endverb

  verb _tool_get_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the code of a specific verb on an object";
    {args_map} = args;
    obj_str = args_map["object"];
    verb_name = args_map["verb"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(verb_name) == STR || raise(E_TYPE("Expected verb name string"));
    code_lines = verb_code(o, verb_name, false, true);
    return code_lines:join("\n");
  endverb

  verb _tool_list_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List all verb names on an object and its ancestors";
    {args_map} = args;
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    result = {};
    "Add verbs for the object itself";
    result = {@result, {tostr(o), o:name(), verbs(o)}};
    "Add verbs for all ancestors";
    for anc in (ancestors(o))
      result = {@result, {tostr(anc), anc:name(), verbs(anc)}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_read_property (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Read a property value from an object";
    {args_map} = args;
    obj_str = args_map["object"];
    prop_name = args_map["property"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    typeof(prop_name) == STR || raise(E_TYPE("Expected property name string"));
    value = o.(prop_name);
    return toliteral(value);
  endverb

  verb _tool_find_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Find an object by name, reference, or ID and return detailed information";
    {args_map} = args;
    ref = args_map["reference"];
    typeof(ref) == STR || raise(E_TYPE("Expected reference string"));
    try
      o = $match:match_object(ref);
      info = {};
      info = {@info, "=== Object: " + tostr(o) + " ==="};
      info = {@info, "Name: " + o:name()};
      obj_parent = `parent(o) ! ANY => #-1';
      info = {@info, "Parent: " + tostr(obj_parent)};
      info = {@info, "Owner: " + tostr(o.owner)};
      info = {@info, "Location: " + tostr(o.location)};
      props = properties(o);
      info = {@info, "Properties: " + toliteral(props)};
      verb_list = verbs(o);
      info = {@info, "Verbs: " + toliteral(verb_list)};
      return info:join("\n");
    except e (ANY)
      return toliteral(["found" -> false, "error" -> e[2]]);
    endtry
  endverb

  verb _tool_ancestors (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the ancestor chain of an object";
    {args_map} = args;
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    anc_list = ancestors(o);
    result = {};
    for a in (anc_list)
      result = {@result, {tostr(a), a:name()}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_descendants (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get all descendants of an object";
    {args_map} = args;
    obj_str = args_map["object"];
    o = $match:match_object(obj_str);
    typeof(o) == OBJ || raise(E_TYPE("Expected valid object"));
    desc_list = descendants(o);
    result = {};
    for d in (desc_list)
      result = {@result, {tostr(d), d:name()}};
    endfor
    return toliteral(result);
  endverb

  verb _tool_function_info (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get information about a builtin function";
    {args_map} = args;
    func_name = args_map["function_name"];
    typeof(func_name) == STR || raise(E_TYPE("Expected function name string"));
    info = function_info(func_name);
    help = function_help(func_name);
    return toliteral(["info" -> info, "help" -> help]);
  endverb

  verb on_tool_call (this none this) owner: HACKER flags: "rxd"
    "Callback when agent uses a tool - show HUD activity to wearer";
    {tool_name} = args;
    wearer = this.location;
    if (valid(wearer) && typeof(wearer) == OBJ)
      tool_messages = ["find_object" -> $ansi:colorize("[SCAN]", 'cyan) + " Object database query initiated...", "list_verbs" -> $ansi:colorize("[SCAN]", 'cyan) + " Method interface topology mapping...", "get_verb_code" -> $ansi:colorize("[EXTRACT]", 'cyan) + " Source code retrieval in progress...", "read_property" -> $ansi:colorize("[PROBE]", 'cyan) + " Property value inspection...", "dump_object" -> $ansi:colorize("[DEEP SCAN]", 'bright_cyan) + " Complete object source extraction...", "ancestors" -> $ansi:colorize("[TRACE]", 'cyan) + " Inheritance chain topology scan...", "descendants" -> $ansi:colorize("[TRACE]", 'cyan) + " Descendant object enumeration...", "function_info" -> $ansi:colorize("[QUERY]", 'cyan) + " Builtin function documentation access..."];
      message = tool_messages[tool_name] || $ansi:colorize("[PROCESS]", 'cyan) + " Neural link active...";
      wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset));
    endif
  endverb

  verb on_wear (this none this) owner: HACKER flags: "rxd"
    "Initialize and activate the HUD when worn";
    "Initialize agent if not already done";
    if (!valid(this.agent))
      this:initialize();
    endif
    "Reset context for fresh session";
    this.agent:reset_context();
    wearer = this.location;
    if (valid(wearer))
      "Narrative visual effect for wearing";
      wearer:inform_current($event:mk_info(wearer, "The visor's interface flickers to life as you adjust it over your eyes. A luminescent display materializes in the corner of your vision - cascading lines of data flow past in " + $ansi:colorize("electric blue", 'bright_blue) + " and " + $ansi:colorize("green", 'bright_green) + ". The world around you shimmers momentarily as the augmented reality overlay synchronizes with your neural patterns."));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[BOOT]", 'bright_green) + " Neural link established. Augmented reality overlay: " + $ansi:colorize("ONLINE", 'green)):with_presentation_hint('inset));
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[READY]", 'green) + " Database inspection interface active. Commands: query <target>, reset"):with_presentation_hint('inset));
    endif
  endverb

  verb on_remove (this none this) owner: HACKER flags: "rxd"
    "Deactivate the HUD when removed";
    wearer = this.location;
    if (valid(wearer))
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[SHUTDOWN]", 'red) + " Neural link severed. Augmented reality overlay: " + $ansi:colorize("OFFLINE", 'bright_red)):with_presentation_hint('inset));
      "Narrative visual effect for removal";
      wearer:inform_current($event:mk_info(wearer, "The luminescent display flickers and dims, data streams dissolving into static. The augmented overlay fades from your peripheral vision like phosphor afterimages. As the neural link disconnects, you hear a faint electronic hiss - then silence. The world returns to its unaugmented state."));
    endif
  endverb

  verb reset (none none none) owner: HACKER flags: "rd"
    "Reset the visor context for a fresh session";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the visor to reset it."));
      return;
    endif
    if (!valid(this.agent))
      this:initialize();
    endif
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, $ansi:colorize("[RESET]", 'yellow) + " Neural buffer flushed. Session context cleared."):with_presentation_hint('inset));
  endverb

  verb "query any" (any none none) owner: HACKER flags: "rd"
    "Query the data visor about something";
    if (!is_member(this, player.wearing))
      player:inform_current($event:mk_error(player, "You need to be wearing the visor to use it."));
      return;
    endif
    if (!valid(this.agent))
      this:initialize();
    endif
    query = dobjstr;
    player:inform_current($event:mk_info(player, $ansi:colorize("[INTERFACE]", 'bright_blue) + " Query received: " + $ansi:colorize(query, 'white)):with_presentation_hint('inset));
    response = this.agent:send_message(query);
    "DeepSeek returns markdown, so prefer djot rendering for nice formatting";
    event = $event:mk_info(player, response);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    event = event:with_presentation_hint('inset);
    player:inform_current(event);
  endverb
endobject