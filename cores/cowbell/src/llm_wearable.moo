object LLM_WEARABLE
  name: "LLM-Powered Wearable"
  parent: WEARABLE
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "r") = #-1;

  override description = "Base prototype for AI-powered wearable tools that use LLM agents for interactive assistance.";
  override import_export_id = "llm_wearable";

  verb configure (this none this) owner: HACKER flags: "rxd"
    "Override in child objects to configure agent with specific system prompt and tools";
    raise(E_VERBNF, "Child objects must override :configure to set up their agent");
  endverb

  verb _action_perms_check (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check tool is accessible and return wearer. Caller must set_task_perms(wearer).";
    wearer = this:wearer();
    if (!valid(wearer))
      "Check if tool is in player's inventory instead";
      wearer = player;
      valid(wearer) && is_member(this, wearer.contents) || raise(E_PERM, "Tool must be worn or in inventory to use");
    endif
    "Check user eligibility - override _check_user_eligible in children for custom requirements";
    this:_check_user_eligible(wearer);
    return wearer;
  endverb

  verb _check_user_eligible (this none this) owner: HACKER flags: "rxd"
    "Override in children to customize user eligibility requirements. Default: no restrictions";
    {wearer} = args;
    return true;
  endverb

  verb _send_with_continuation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Send message to agent with automatic continuation on max iterations";
    {message, ?tool_name = "TOOL", ?max_continuations = 3} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    response = this.agent:send_message(message);
    "If we hit max iterations, automatically continue";
    continuations = 0;
    while (response:starts_with("Error: Maximum iterations exceeded") && continuations < max_continuations)
      continuations = continuations + 1;
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[" + tool_name + "]", 'bright_yellow) + " Complex task detected - continuing automatically... (" + tostr(continuations) + "/" + tostr(max_continuations) + ")"):with_presentation_hint('inset));
      response = this.agent:send_message("Continue where you left off. Complete any remaining work from the previous request.");
    endwhile
    return response;
  endverb

  verb _tool_explain (this none this) owner: HACKER flags: "rxd"
    "Tool: Communicate reasoning, progress updates, or error details to user";
    {args_map} = args;
    message = args_map["message"];
    typeof(message) == STR || raise(E_TYPE("Expected message string"));
    "Message is displayed by on_tool_call callback, no need to display here";
    return "Message delivered to user.";
  endverb

  verb _tool_ask_user (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Ask the wearer a question and receive their response";
    {args_map} = args;
    wearer = this:_action_perms_check();
    question = args_map["question"];
    typeof(question) == STR || raise(E_TYPE("Expected question string"));
    set_task_perms(wearer);
    "Use player's prompt method to ask for input";
    response = wearer:prompt(question);
    if (typeof(response) != STR)
      return "User cancelled or provided no response.";
    endif
    return "User response: " + response;
  endverb

  verb on_tool_call (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback when agent uses a tool - children customize via _format_hud_message and _get_tool_content_types";
    {tool_name, tool_args} = args;
    wearer = this.location;
    if (!valid(wearer) || typeof(wearer) != OBJ)
      return;
    endif
    "Parse JSON string to map";
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    try
      "Let child format the message (handles all tools including explain/ask_user)";
      message = this:_format_hud_message(tool_name, tool_args);
      "Get content types from child (allows markdown rendering for specific tools)";
      content_types = this:_get_tool_content_types(tool_name, tool_args);
      "Build and send event";
      event = $event:mk_info(wearer, message):with_presentation_hint('inset);
      if (content_types && length(content_types) > 0)
        event = event:with_metadata('preferred_content_types, content_types);
      endif
      wearer:inform_current(event);
    except e (ANY)
      "Fall back to generic message if formatting fails";
      message = $ansi:colorize("[PROCESS]", 'cyan) + " Tool active: " + tool_name;
      wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset));
      server_log("LLM wearable callback error: " + toliteral(e));
    endtry
  endverb

  verb _format_hud_message (this none this) owner: HACKER flags: "rxd"
    "Override in child objects for tool-specific HUD message formatting";
    {tool_name, tool_args} = args;
    "Default formatting for common tools";
    if (tool_name == "explain")
      return $ansi:colorize("[INFO]", 'bright_green) + " " + tool_args["message"];
    elseif (tool_name == "ask_user")
      question = tool_args["question"];
      "Truncate long questions";
      if (length(question) > 60)
        question = question[1..60] + "...";
      endif
      return $ansi:colorize("[QUESTION]", 'bright_yellow) + " Asking: " + question;
    endif
    "Fallback for unknown tools";
    return $ansi:colorize("[PROCESS]", 'cyan) + " " + tool_name;
  endverb

  verb _get_tool_content_types (this none this) owner: HACKER flags: "rxd"
    "Override in children to specify content types for specific tools (e.g., markdown for explain)";
    {tool_name, tool_args} = args;
    "By default, no special content types - render as plain text";
    return {};
  endverb

  verb stop (this none none) owner: HACKER flags: "rd"
    "Stop the current agent operation and reset context";
    caller == player || raise(E_PERM);
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent is currently configured."));
      return;
    endif
    "Reset the agent's context to interrupt current operation";
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, "Agent operation stopped and context reset."));
  endverb
endobject