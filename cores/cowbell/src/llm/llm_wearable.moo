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
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_wearable";

  verb configure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create agent and apply configuration. Children override _setup_agent to customize.";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    "Create the agent";
    this.agent = $llm_agent:create();
    "Set agent owner to tool owner so they can write to agent properties";
    this.agent.owner = this.owner;
    "Let child class configure it";
    this:_setup_agent(this.agent);
  endverb

  verb _setup_agent (this none this) owner: HACKER flags: "rxd"
    "Override in child objects to configure agent with specific system prompt and tools";
    {agent} = args;
    raise(E_VERBNF, "Child objects must override :_setup_agent to configure their agent");
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
    this:_check_for_owner("wear");
    pass(@args);
  endverb

  verb _check_for_owner (this none this) owner: HACKER flags: "rxd"
    "Override parent to enforce owner-only usage";
    action = {args};
    if (player != this.owner && !player.wizard)
      "Announce the violation to the room";
      if (valid(player.location))
        event = $event:mk_info(player, this:name(), " emits a sharp warning tone as ", $sub:n(), " ", $sub:self_alt("attempt", "attempts"), " to ", action, " it, rejecting the unauthorized user."):with_this(player.location);
        player.location:announce(event);
      else
        player:inform_current($event:mk_error(player, this:name(), " refuses to attune to you. The device is bonded to its rightful owner and will not respond to unauthorized use."));
      endif
      return;
    endif
  endverb

  verb _send_with_continuation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Send message to agent with user-confirmed continuation on max iterations";
    {message, ?tool_name = "TOOL", ?max_continuations = 3} = args;
    wearer = this:_action_perms_check();
    set_task_perms(wearer);
    "Set token owner for budget tracking";
    this.agent.token_owner = wearer;
    this.agent.current_continuation = 0;
    response = this.agent:send_message(message);
    "If we hit max iterations, ask user if they want to continue";
    continuations = 0;
    while (response:starts_with("Error: Maximum iterations exceeded") && continuations < max_continuations)
      "Show iteration limit message";
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[" + tool_name + "]", 'bright_yellow) + " Agent hit iteration limit (" + tostr(this.agent.max_iterations) + " iterations)."):with_presentation_hint('inset));
      "Ask user if they want to continue";
      metadata = {{"input_type", "yes_no"}, {"prompt", "Continue agent execution?"}};
      user_choice = wearer:read_with_prompt(metadata);
      if (user_choice != "yes")
        "User chose not to continue";
        this.agent.current_continuation = 0;
        this:_show_token_usage(wearer);
        return "Agent stopped at user request after reaching iteration limit.";
      endif
      "User chose to continue";
      continuations = continuations + 1;
      this.agent.current_continuation = continuations;
      wearer:inform_current($event:mk_info(wearer, $ansi:colorize("[" + tool_name + "]", 'bright_yellow) + " Continuing... (continuation " + tostr(continuations) + "/" + tostr(max_continuations) + ")"):with_presentation_hint('inset));
      response = this.agent:send_message("Continue where you left off. Complete any remaining work from the previous request.");
    endwhile
    "Reset continuation counter";
    this.agent.current_continuation = 0;
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
    "Don't downgrade perms - need ARCH_WIZARD perms to read llm_token_budget and llm_tokens_used";
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
    "Show context size and compaction status if we have prompt token data";
    if (typeof(last_usage) == MAP && maphaskey(last_usage, "prompt_tokens"))
      prompt_tokens = last_usage["prompt_tokens"];
      token_limit = this.agent.token_limit;
      compaction_threshold = this.agent.compaction_threshold;
      threshold_tokens = token_limit * compaction_threshold;
      context_percent = prompt_tokens * 100 / token_limit;
      threshold_percent = prompt_tokens * 100 / threshold_tokens;
      "Color code context usage";
      if (threshold_percent >= 100)
        ctx_color = 'bright_red;
        status = "COMPACTING";
      elseif (threshold_percent >= 80)
        ctx_color = 'yellow;
        status = "NEAR LIMIT";
      else
        ctx_color = 'dim;
        status = "OK";
      endif
      context_msg = $ansi:colorize("[CONTEXT]", ctx_color) + " Size: " + $ansi:colorize(tostr(prompt_tokens), 'white) + "/" + tostr(token_limit) + " (" + tostr(context_percent) + "%) | Compaction at " + tostr(threshold_tokens) + " (" + tostr(toint(threshold_percent)) + "% full) - " + $ansi:colorize(status, ctx_color);
      wearer:inform_current($event:mk_info(wearer, context_msg):with_presentation_hint('inset));
    endif
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
    "Tool: Ask the wearer a question, supporting choices or free-text responses";
    {args_map} = args;
    wearer = this:_action_perms_check();
    question = args_map["question"];
    typeof(question) == STR || raise(E_TYPE("Expected question string"));
    placeholder = `args_map["placeholder"] ! ANY => "Describe your requested changes..."';
    "If explicit choices are provided, present them directly";
    if (maphaskey(args_map, "choices"))
      choices = args_map["choices"];
      typeof(choices) == LIST && length(choices) > 0 || raise(E_TYPE("choices must be a non-empty list when provided"));
      "Always include a stop option so user can end the flow";
      if (!("Stop" in choices) && !("stop" in choices))
        choices = {@choices, "Stop"};
      endif
      metadata = {{"input_type", "choice"}, {"prompt", question}, {"choices", choices}};
      response = wearer:read_with_prompt(metadata);
      if (typeof(response) != STR || response == "" || response == "Stop")
        this.agent.cancel_requested = true;
        return "User cancelled.";
      endif
      return "User chose: " + response;
    endif
    "Handle explicitly requested input types (text, text_area, yes_no, confirmation, etc.)";
    requested_type = `args_map["input_type"] ! ANY => ""';
    allowed_types = {"yes_no", "text", "text_area", "confirmation", "yes_no_alternative"};
    if (is_member(requested_type, allowed_types))
      metadata = {{"input_type", requested_type}, {"prompt", question}};
      if (typeof(placeholder) == STR && placeholder != "")
        metadata = {@metadata, {"placeholder", placeholder}};
      endif
      if (requested_type == "text_area")
        rows = `args_map["rows"] ! ANY => 4';
        typeof(rows) == INT && (metadata = {@metadata, {"rows", rows}});
      endif
      response = wearer:read_with_prompt(metadata);
      if (!response || response == "@abort")
        this.agent.cancel_requested = true;
        return "User cancelled.";
      endif
      if (requested_type == "yes_no")
        if (response == "yes")
          return "User accepted.";
        else
          this.agent.cancel_requested = true;
          return "User cancelled.";
        endif
      endif
      return "User response: " + response;
    endif
    "Default: Accept / Stop / Request Change flow";
    metadata = {{"input_type", "choice"}, {"prompt", question}, {"choices", {"Accept", "Stop", "Request Change"}}};
    response = wearer:read_with_prompt(metadata);
    if (response == "Stop" || typeof(response) != STR || response == "")
      this.agent.cancel_requested = true;
      return "User cancelled.";
    elseif (response == "Request Change")
      "Follow up with multiline text input for the requested change";
      change_metadata = {{"input_type", "text_area"}, {"prompt", "What changes would you like?"}, {"placeholder", placeholder}, {"rows", 4}};
      change_request = wearer:read_with_prompt(change_metadata);
      if (change_request == "@abort" || typeof(change_request) != STR || change_request:trim() == "")
        this.agent.cancel_requested = true;
        return "User cancelled.";
      endif
      return "User requested changes: " + change_request:trim();
    else
      return "User accepted.";
    endif
  endverb

  verb log_tool_error (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Log tool execution errors to server_log. Called by agent when a tool raises.";
    {tool_name, tool_args, error_msg} = args;
    caller == this.agent || caller_perms().wizard || raise(E_PERM);
    "Do not downgrade perms; server_log requires wizard perms.";
    safe_args = typeof(tool_args) == STR ? tool_args | toliteral(tool_args);
    server_log("LLM tool error [" + tostr(tool_name) + "]: " + tostr(error_msg) + " args=" + safe_args);
    return true;
  endverb

  verb on_tool_call (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback when agent uses a tool - children customize via _format_hud_message and _get_tool_content_types";
    caller == this || caller == this.agent || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    {tool_name, tool_args} = args;
    wearer = this:wearer();
    if (!valid(wearer))
      return;
    endif
    "Parse JSON string to map";
    if (typeof(tool_args) == STR)
      tool_args = parse_json(tool_args);
    endif
    "Send a quick in-progress ping to show activity";
    ping_msg = $ansi:colorize("[PROCESSING]", 'cyan) + " " + tool_name;
    wearer:inform_current($event:mk_info(wearer, ping_msg):with_presentation_hint('inset));
    try
      "Let child format the message (handles all tools including explain/ask_user)";
      message = this:_format_hud_message(tool_name, tool_args);
      "Prepend iteration info if agent is available";
      if (valid(this.agent))
        iter = this.agent.current_iteration;
        max_iter = this.agent.max_iterations;
        cont = this.agent.current_continuation;
        if (iter > 0)
          iter_info = $ansi:colorize("[" + tostr(iter) + "/" + tostr(max_iter), 'dim);
          if (cont > 0)
            iter_info = iter_info + " cont:" + tostr(cont);
          endif
          iter_info = iter_info + "] ";
          message = iter_info + message;
        endif
      endif
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
      suffix = "";
      if (maphaskey(tool_args, "choices") && typeof(tool_args["choices"]) == LIST && length(tool_args["choices"]) > 0)
        suffix = " [options]";
      elseif (maphaskey(tool_args, "input_type") && typeof(tool_args["input_type"]) == STR)
        suffix = " [" + tool_args["input_type"] + "]";
      endif
      return $ansi:colorize("[QUESTION]", 'bright_yellow) + " Asking: " + question + suffix;
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

  verb stop (this none none) owner: ARCH_WIZARD flags: "rd"
    "Stop the current agent operation without clearing context";
    caller == this || caller == this.owner || (valid(caller_perms()) && caller_perms().wizard) || raise(E_PERM);
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent is currently configured."));
      return;
    endif
    set_task_perms(this.owner);
    "Request cancellation of current operation";
    this.agent.cancel_requested = true;
    "Show token usage before stopping";
    this:_show_token_usage(player);
    player:inform_current($event:mk_info(player, "Cancellation requested. Agent will stop at next safe point."));
  endverb

  verb reset (this none none) owner: ARCH_WIZARD flags: "rd"
    "Reset agent context, clearing conversation history";
    caller == this || caller == this.owner || (valid(caller_perms()) && caller_perms().wizard) || raise(E_PERM);
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent is currently configured."));
      return;
    endif
    set_task_perms(this.owner);
    "Show token usage before resetting";
    this:_show_token_usage(player);
    "Clear the agent's context";
    this.agent:reset_context();
    player:inform_current($event:mk_info(player, "Agent context reset. Conversation history cleared."));
  endverb

  verb debug_status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Debug the status calculation to see what's happening";
    if (!valid(this.agent))
      return "No agent configured";
    endif
    last_usage = this.agent.last_token_usage;
    if (typeof(last_usage) != MAP || !maphaskey(last_usage, "prompt_tokens"))
      return "No prompt token data available";
    endif
    prompt_tokens = last_usage["prompt_tokens"];
    token_limit = this.agent.token_limit;
    compaction_threshold = this.agent.compaction_threshold;
    threshold_tokens = token_limit * compaction_threshold;
    context_percent = prompt_tokens * 100 / token_limit;
    threshold_percent = prompt_tokens * 100 / threshold_tokens;
    if (threshold_percent >= 100)
      status = "COMPACTING";
    elseif (threshold_percent >= 80)
      status = "NEAR LIMIT";
    else
      status = "OK";
    endif
    return ["prompt_tokens" -> prompt_tokens, "token_limit" -> token_limit, "compaction_threshold" -> compaction_threshold, "threshold_tokens" -> threshold_tokens, "context_percent" -> context_percent, "threshold_percent" -> threshold_percent, "test_gte_100" -> threshold_percent >= 100, "test_gte_80" -> threshold_percent >= 80, "status" -> status];
  endverb

  verb recycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clean up agent when object is destroyed";
    caller == this || caller_perms() == this.owner || (valid(caller_perms()) && caller_perms().wizard) || raise(E_PERM);
    if (valid(this.agent))
      this.agent = #-1;
    endif
  endverb

  verb reconfigure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Reconfigure by cleaning up old agent and creating a fresh one";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    "Recycle old agent if it exists";
    if (valid(this.agent))
      this.agent:destroy();
      this.agent = #-1;
    endif
    "Create fresh agent with current configuration";
    this:configure();
  endverb

  verb "use inter*act qu*ery" (this none none) owner: ARCH_WIZARD flags: "rd"
    "Use/interact with the wearable - prompts for input";
    this:_check_for_owner("use");
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
