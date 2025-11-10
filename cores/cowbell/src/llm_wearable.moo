object LLM_WEARABLE
  name: "LLM-Powered Wearable"
  parent: WEARABLE
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "r") = #-1;
  property placeholder_text (owner: HACKER, flags: "rc") = "Ask a question...";
  property processing_message (owner: HACKER, flags: "rc") = "Processing request...";
  property prompt_color (owner: HACKER, flags: "rc") = 'bright_cyan;
  property prompt_label (owner: HACKER, flags: "rc") = "[TOOL]";
  property prompt_text (owner: HACKER, flags: "rc") = "Enter your query:";
  property requires_wearing_only (owner: HACKER, flags: "rc") = true;
  property tool_name (owner: HACKER, flags: "rc") = "TOOL";

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

  verb do_wear (this none this) owner: HACKER flags: "rxd"
    "Override parent to enforce owner-only usage";
    if (player != this.owner)
      "Announce the violation to the room";
      if (valid(player.location))
        event = $event:mk_info(player, this:name(), " emits a sharp warning tone as ", $sub:n(), " ", $sub:self_alt("attempt", "attempts"), " to wear it, rejecting the unauthorized user."):with_this(player.location);
        player.location:announce(event);
      else
        player:inform_current($event:mk_error(player, this:name(), " refuses to attune to you. The device is bonded to its rightful owner and will not respond to unauthorized use."));
      endif
      return;
    endif
    pass(@args);
  endverb

  verb _send_with_continuation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Send message to agent with automatic continuation on max iterations";
    {message, ?tool_name = "TOOL", ?max_continuations = 3} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    "Set token owner for budget tracking";
    this.agent.token_owner = wearer;
    response = this.agent:send_message(message);
    "If we hit max iterations, automatically continue";
    continuations = 0;
    while (response:starts_with("Error: Maximum iterations exceeded") && continuations < max_continuations)
      continuations = continuations + 1;
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[" + tool_name + "]", 'bright_yellow) + " Complex task detected - continuing automatically... (" + tostr(continuations) + "/" + tostr(max_continuations) + ")"):with_presentation_hint('inset));
      response = this.agent:send_message("Continue where you left off. Complete any remaining work from the previous request.");
    endwhile
    "Show token usage summary";
    this:_show_token_usage(wearer);
    return response;
  endverb

  verb _show_token_usage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display token usage information to the user";
    {wearer} = args;
    if (!valid(this.agent))
      return;
    endif
    set_task_perms(wearer);
    budget = `wearer.llm_token_budget ! ANY => 20000000';
    used = `wearer.llm_tokens_used ! ANY => 0';
    percent_used = used * 100 / budget;
    "Color code based on usage";
    if (percent_used >= 90)
      color = 'bright_red;
    elseif (percent_used >= 75)
      color = 'yellow;
    else
      color = 'dim;
    endif
    "Check if there's been a recent API call";
    last_usage = this.agent.last_token_usage;
    if (typeof(last_usage) == MAP && maphaskey(last_usage, "total_tokens"))
      last_tokens = last_usage["total_tokens"];
      usage_msg = $ansi:colorize("[TOKENS]", color) + " Last call: " + $ansi:colorize(tostr(last_tokens), 'white) + " | Total: " + tostr(used) + "/" + tostr(budget) + " (" + tostr(percent_used) + "% used)";
    else
      "No API calls yet, just show budget";
      usage_msg = $ansi:colorize("[TOKENS]", color) + " Budget: " + tostr(used) + "/" + tostr(budget) + " (" + tostr(percent_used) + "% used)";
    endif
    wearer:inform_current($event:mk_info(wearer, usage_msg):with_presentation_hint('inset));
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
    "Use direct read() with text input type - simple text field + cancel button";
    metadata = {{"input_type", "text"}, {"prompt", question}, {"placeholder", "Enter your response..."}};
    response = wearer:read_with_prompt(metadata);
    if (typeof(response) != STR || response == "")
      "User cancelled - stop the agent flow";
      this.agent.cancel_requested = true;
      return "User cancelled.";
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
    "Stop the current agent operation without clearing context";
    caller == player || raise(E_PERM);
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent is currently configured."));
      return;
    endif
    "Request cancellation of current operation";
    this.agent.cancel_requested = true;
    "Show token usage before stopping";
    this:_show_token_usage(player);
    player:inform_current($event:mk_info(player, "Cancellation requested. Agent will stop at next safe point."));
  endverb

  verb reset (this none none) owner: HACKER flags: "rd"
    "Reset agent context, clearing conversation history";
    caller == player || raise(E_PERM);
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent is currently configured."));
      return;
    endif
    "Show token usage before resetting";
    this:_show_token_usage(player);
    "Clear the agent's context";
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, "Agent context reset. Conversation history cleared."));
  endverb

  verb "use inter*act qu*ery" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Use/interact with the wearable - prompts for input";
    caller == player || raise(E_PERM);
    "Check if wearing (and optionally carrying)";
    wearing_check = is_member(this, player.wearing);
    carrying_check = !this.requires_wearing_only && is_member(this, player.contents);
    if (!wearing_check && !carrying_check)
      error_msg = this.requires_wearing_only ? "You have to wear " + this:name() + " first." | "You have to wear or carry " + this:name() + " first.";
      player:inform_current($event:mk_error(player, error_msg));
      return;
    endif
    "Configure agent if needed";
    if (!valid(this.agent))
      this:configure();
    endif
    "Prompt for query text using metadata-based read";
    metadata = {{"input_type", "text"}, {"prompt", $ansi:colorize(this.prompt_label, this.prompt_color) + " " + this.prompt_text}, {"placeholder", this.placeholder_text}};
    query = player:read_with_prompt(metadata):trim();
    set_task_perms(caller_perms());
    if (!query)
      player:inform_current($event:mk_error(player, "Query cancelled - no input provided."));
      return;
    endif
    "Show received and processing messages";
    player:inform_current($event:mk_info(player, $ansi:colorize(this.prompt_label, this.prompt_color) + " Query received: " + $ansi:colorize(query, 'white)):with_presentation_hint('inset));
    player:inform_current($event:mk_info(player, $ansi:colorize("[PROCESSING]", 'yellow) + " " + this.processing_message):with_presentation_hint('inset));
    "Send to agent with continuation support";
    response = this:_send_with_continuation(query, this.tool_name, 3);
    "Display final response with djot rendering";
    event = $event:mk_info(player, response);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    event = event:with_presentation_hint('inset);
    player:inform_current(event);
  endverb
endobject