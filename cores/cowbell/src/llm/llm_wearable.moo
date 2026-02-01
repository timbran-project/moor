object LLM_WEARABLE
  name: "LLM-Powered Wearable"
  parent: WEARABLE
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "r") = #-1;
  property auto_confirm (owner: ARCH_WIZARD, flags: "rc") = 0;
  property placeholder_text (owner: HACKER, flags: "rc") = "Ask a question...";
  property preferred_model (owner: HACKER, flags: "rc") = "";
  property processing_message (owner: HACKER, flags: "rc") = "Processing request...";
  property progress_connection (owner: ARCH_WIZARD, flags: "rc") = 0;
  property progress_max_visible (owner: ARCH_WIZARD, flags: "rc") = 5;
  property progress_rewrite_id (owner: ARCH_WIZARD, flags: "rc") = "";
  property progress_steps (owner: ARCH_WIZARD, flags: "rc") = {};
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
    "Reset auto_confirm mode on reconfigure";
    this.auto_confirm = false;
    "Create anonymous agent - GC'd when no longer referenced";
    this.agent = $llm_agent:create(true);
    "Set agent owner to tool owner so they can write to agent properties";
    this.agent.owner = this.owner;
    "Downgrade perms after wiz-level property writes are done";
    set_task_perms(this.owner);
    "Set model if preferred_model is configured";
    if (this.preferred_model)
      this.agent.client.model = this.preferred_model;
    endif
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

  verb _show_token_usage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display token usage information to the user";
    {wearer} = args;
    !valid(this.agent) && return;
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
    if (typeof(last_usage) == TYPE_MAP && maphaskey(last_usage, "total_tokens"))
      last_tokens = last_usage["total_tokens"];
      usage_msg = $ansi:colorize("[TOKENS]", color) + " Last call: " + $ansi:colorize(tostr(last_tokens), 'white) + " | Total: " + tostr(used) + "/" + tostr(budget) + " (" + tostr(percent_used) + "% used)";
      tts_msg = "Token usage: Last call used " + tostr(last_tokens) + " tokens. Total " + tostr(used) + " of " + tostr(budget) + ", " + tostr(percent_used) + " percent used.";
    else
      "No API calls yet, just show budget";
      usage_msg = $ansi:colorize("[TOKENS]", color) + " Budget: " + tostr(used) + "/" + tostr(budget) + " (" + tostr(percent_used) + "% used)";
      tts_msg = "Token budget: " + tostr(used) + " of " + tostr(budget) + " used, " + tostr(percent_used) + " percent.";
    endif
    wearer:inform_current($event:mk_info(wearer, usage_msg):with_presentation_hint('inset):with_group('llm, this):with_tts(tts_msg));
    "Show context status";
    token_limit = this.agent.token_limit;
    compaction_threshold = this.agent.compaction_threshold;
    threshold_tokens = toint(token_limit * compaction_threshold);
    if (typeof(last_usage) == TYPE_MAP && maphaskey(last_usage, "prompt_tokens"))
      "We have actual prompt token data from a previous call";
      prompt_tokens = last_usage["prompt_tokens"];
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
      context_msg = $ansi:colorize("[CONTEXT]", ctx_color) + " Size: " + $ansi:colorize(tostr(prompt_tokens), 'white) + "/" + tostr(token_limit) + " (" + tostr(context_percent) + "%) | Compaction at " + tostr(threshold_tokens) + " - " + $ansi:colorize(status, ctx_color);
      context_tts = "Context size: " + tostr(prompt_tokens) + " of " + tostr(token_limit) + " tokens, " + tostr(context_percent) + " percent. Status: " + status + ".";
    else
      "No API call yet - show context is fresh, estimate from message count";
      num_messages = length(this.agent.context);
      if (num_messages == 0)
        status = "FRESH";
        ctx_color = 'bright_green;
        context_msg = $ansi:colorize("[CONTEXT]", ctx_color) + " " + $ansi:colorize(status, ctx_color) + " | Limit: " + tostr(token_limit) + " | Compaction at " + tostr(threshold_tokens);
        context_tts = "Context is fresh. Token limit is " + tostr(token_limit) + ", compaction at " + tostr(threshold_tokens) + ".";
      else
        status = tostr(num_messages) + " messages";
        ctx_color = 'dim;
        context_msg = $ansi:colorize("[CONTEXT]", ctx_color) + " " + status + " | Limit: " + tostr(token_limit) + " | Compaction at " + tostr(threshold_tokens);
        context_tts = "Context has " + tostr(num_messages) + " messages. Token limit is " + tostr(token_limit) + ".";
      endif
    endif
    wearer:inform_current($event:mk_info(wearer, context_msg):with_presentation_hint('inset):with_group('llm, this):with_tts(context_tts));
  endverb

  verb _tool_explain (this none this) owner: HACKER flags: "rxd"
    "Tool: Communicate reasoning, progress updates, or error details to user";
    {args_map, actor} = args;
    message = args_map["message"];
    typeof(message) == TYPE_STR || raise(E_TYPE("Expected message string"));
    "Message is displayed by on_tool_call callback, no need to display here";
    return "Message delivered to user.";
  endverb

  verb _tool_ask_user (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Ask the wearer a question, supporting choices or free-text responses";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    question = args_map["question"];
    typeof(question) == TYPE_STR || raise(E_TYPE("Expected question string"));
    placeholder = `args_map["placeholder"] ! ANY => "Describe your requested changes..."';
    "If explicit choices are provided, present them directly";
    if (maphaskey(args_map, "choices"))
      choices = args_map["choices"];
      typeof(choices) == TYPE_LIST && length(choices) > 0 || raise(E_TYPE("choices must be a non-empty list when provided"));
      "Always include a stop option so user can end the flow";
      if (!("Stop" in choices) && !("stop" in choices))
        choices = {@choices, "Stop"};
      endif
      metadata = {{"input_type", "choice"}, {"prompt", question}, {"choices", choices}};
      response = wearer:read_with_prompt(metadata);
      if (typeof(response) != TYPE_STR || response == "" || response == "Stop")
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
      if (typeof(placeholder) == TYPE_STR && placeholder != "")
        metadata = {@metadata, {"placeholder", placeholder}};
      endif
      if (requested_type == "text_area")
        rows = `args_map["rows"] ! ANY => 4';
        typeof(rows) == TYPE_INT && (metadata = {@metadata, {"rows", rows}});
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
    if (response == "Stop" || typeof(response) != TYPE_STR || response == "")
      this.agent.cancel_requested = true;
      return "User cancelled.";
    elseif (response == "Request Change")
      "Follow up with multiline text input for the requested change";
      change_metadata = {{"input_type", "text_area"}, {"prompt", "What changes would you like?"}, {"placeholder", placeholder}, {"rows", 4}};
      change_request = wearer:read_with_prompt(change_metadata);
      if (change_request == "@abort" || typeof(change_request) != TYPE_STR || change_request:trim() == "")
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
    safe_args = typeof(tool_args) == TYPE_STR ? tool_args | toliteral(tool_args);
    server_log("LLM tool error [" + tostr(tool_name) + "]: " + tostr(error_msg) + " args=" + safe_args);
    return true;
  endverb

  verb on_tool_call (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback when agent uses a tool - per-tool rewritable placeholder.";
    caller == this || caller == this.agent || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    {tool_name, tool_args} = args;
    "Get user - prefer wearer, fall back to token_owner for carried-but-not-worn items";
    wearer = this:wearer();
    if (!valid(wearer) && valid(this.agent))
      wearer = `this.agent.token_owner ! ANY => #-1';
    endif
    if (!valid(wearer))
      return;
    endif
    "Parse JSON string to map";
    if (typeof(tool_args) == TYPE_STR)
      tool_args = parse_json(tool_args);
    endif
    "Explain is not rewritable; emit once";
    if (tool_name == "explain")
      message = this:_format_hud_message(tool_name, tool_args);
      wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset):with_group('llm, this));
      return;
    endif
    "Create per-tool rewritable placeholder on current connection";
    rewrite_id = uuid();
    message = this:_format_hud_message(tool_name, tool_args);
    placeholder = $event:mk_info(wearer, message):with_rewritable(rewrite_id, 300, message):with_presentation_hint('processing):with_group('llm, this);
    wearer:inform_current(placeholder);
    "Track rewrite id by tool name (FIFO queue)";
    steps = typeof(this.progress_steps) == TYPE_MAP ? this.progress_steps | [];
    queue = maphaskey(steps, tool_name) ? steps[tool_name] | {};
    queue = {@queue, rewrite_id};
    steps[tool_name] = queue;
    this.progress_steps = steps;
  endverb

  verb on_tool_complete (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Callback after tool execution - rewrite per-tool placeholder once.";
    caller == this || caller == this.agent || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    {tool_name, tool_args, result} = args;
    "Skip explain tool - the message IS the result";
    if (tool_name == "explain")
      return;
    endif
    "Get user - prefer wearer, fall back to token_owner";
    wearer = this:wearer();
    if (!valid(wearer) && valid(this.agent))
      wearer = `this.agent.token_owner ! ANY => #-1';
    endif
    if (!valid(wearer))
      return;
    endif
    "Prepare result text (truncated)";
    result_text = typeof(result) == TYPE_STR ? result | toliteral(result);
    if (length(result_text) > 100)
      result_text = result_text[1..100] + "...";
    endif
    "Check if error";
    is_error = typeof(result) == TYPE_STR && (result:starts_with("ERROR:") || result:starts_with("TOOL BLOCKED:"));
    "Parse tool_args if JSON string";
    if (typeof(tool_args) == TYPE_STR)
      tool_args = `parse_json(tool_args) ! ANY => []';
    endif
    "Special formatting for task-related tools";
    task_tools = {"create_task", "record_finding", "get_findings", "task_status"};
    is_task_tool = tool_name in task_tools;
    "For ask_user, include the question in the completion message";
    question_text = "";
    if (tool_name == "ask_user" && typeof(tool_args) == TYPE_MAP && maphaskey(tool_args, "question"))
      question_text = tool_args["question"];
      if (length(question_text) > 60)
        question_text = question_text[1..60] + "...";
      endif
    endif
    "For record_finding, show what was recorded";
    finding_text = "";
    if (tool_name == "record_finding" && typeof(tool_args) == TYPE_MAP)
      subject = `tool_args["subject"] ! ANY => ""';
      key = `tool_args["key"] ! ANY => ""';
      if (subject != "" && key != "")
        finding_text = subject + "/" + key;
      endif
    endif
    "Find rewrite target for this tool";
    steps = typeof(this.progress_steps) == TYPE_MAP ? this.progress_steps | [];
    if (maphaskey(steps, tool_name) && length(steps[tool_name]) > 0)
      rewrite_id = steps[tool_name][1];
      if (length(steps[tool_name]) > 1)
        steps[tool_name] = (steps[tool_name])[2..length(steps[tool_name])];
      else
        steps = mapdelete(steps, tool_name);
      endif
      this.progress_steps = steps;
      if (is_error)
        message = $ansi:colorize("[\u2717]", 'red) + " " + $ansi:colorize(tool_name, 'yellow) + ": " + result_text;
        tts_msg = "Error from " + tool_name + ": " + result_text;
      elseif (tool_name == "ask_user" && question_text != "")
        message = $ansi:colorize("[\u2713]", 'green) + " " + $ansi:colorize(tool_name, 'yellow) + " \"" + question_text + "\": " + result_text;
        tts_msg = "Response to question: " + question_text + ". " + result_text;
      elseif (tool_name == "record_finding" && finding_text != "")
        message = $ansi:colorize("[\u2713]", 'bright_blue) + " " + $ansi:colorize(tool_name, 'bright_blue) + " [" + finding_text + "]: " + result_text;
        tts_msg = "Recorded finding for " + finding_text + ": " + result_text;
      elseif (is_task_tool)
        message = $ansi:colorize("[\u2713]", 'bright_blue) + " " + $ansi:colorize(tool_name, 'bright_blue) + ": " + result_text;
        tts_msg = tool_name + " completed: " + result_text;
      else
        message = $ansi:colorize("[\u2713]", 'green) + " " + $ansi:colorize(tool_name, 'yellow) + ": " + result_text;
        tts_msg = tool_name + " completed: " + result_text;
      endif
      event = $event:mk_info(wearer, message):with_presentation_hint('inset):with_group('llm, this):with_tts(tts_msg):with_audience('utility);
      wearer:rewrite_event(rewrite_id, event);
      return;
    endif
    "Fallback: no rewrite target; emit normal event";
    if (is_error)
      message = $ansi:colorize("[\u2717]", 'red) + " " + $ansi:colorize(tool_name, 'yellow) + ": " + result_text;
      tts_msg = "Error from " + tool_name + ": " + result_text;
    elseif (tool_name == "ask_user" && question_text != "")
      message = $ansi:colorize("[\u2713]", 'green) + " " + $ansi:colorize(tool_name, 'yellow) + " \"" + question_text + "\": " + result_text;
      tts_msg = "Response to question: " + question_text + ". " + result_text;
    elseif (tool_name == "record_finding" && finding_text != "")
      message = $ansi:colorize("[\u2713]", 'bright_blue) + " " + $ansi:colorize(tool_name, 'bright_blue) + " [" + finding_text + "]: " + result_text;
      tts_msg = "Recorded finding for " + finding_text + ": " + result_text;
    elseif (is_task_tool)
      message = $ansi:colorize("[\u2713]", 'bright_blue) + " " + $ansi:colorize(tool_name, 'bright_blue) + ": " + result_text;
      tts_msg = tool_name + " completed: " + result_text;
    else
      message = $ansi:colorize("[\u2713]", 'green) + " " + $ansi:colorize(tool_name, 'yellow) + ": " + result_text;
      tts_msg = tool_name + " completed: " + result_text;
    endif
    wearer:inform_current($event:mk_info(wearer, message):with_presentation_hint('inset):with_group('llm, this):with_tts(tts_msg));
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
      if (maphaskey(tool_args, "choices") && typeof(tool_args["choices"]) == TYPE_LIST && length(tool_args["choices"]) > 0)
        suffix = " [options]";
      elseif (maphaskey(tool_args, "input_type") && typeof(tool_args["input_type"]) == TYPE_STR)
        suffix = " [" + tool_args["input_type"] + "]";
      endif
      return $ansi:colorize("[QUESTION]", 'bright_yellow) + " Asking: " + question + suffix;
    endif
    "Fallback for unknown tools";
    return $ansi:colorize("[PROCESS]", 'cyan) + " " + tool_name;
  endverb

  verb _format_tts_message (this none this) owner: HACKER flags: "rxd"
    "Override in child objects for tool-specific TTS message formatting";
    {tool_name, tool_args} = args;
    "Default TTS-friendly formatting for common tools";
    if (tool_name == "explain")
      return "Info: " + tool_args["message"];
    elseif (tool_name == "ask_user")
      question = tool_args["question"];
      if (length(question) > 100)
        question = question[1..100] + "...";
      endif
      suffix = "";
      if (maphaskey(tool_args, "choices") && typeof(tool_args["choices"]) == TYPE_LIST && length(tool_args["choices"]) > 0)
        suffix = " with options";
      elseif (maphaskey(tool_args, "input_type") && typeof(tool_args["input_type"]) == TYPE_STR)
        suffix = ", " + tool_args["input_type"] + " input";
      endif
      return "Question: " + question + suffix;
    endif
    "Fallback for unknown tools";
    return "Processing tool: " + tool_name;
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
    "Request cancellation of current operation";
    this.agent.cancel_requested = true;
    set_task_perms(this.owner);
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
    if (typeof(last_usage) != TYPE_MAP || !maphaskey(last_usage, "prompt_tokens"))
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
    "Reconfigure by clearing old agent ref and creating fresh one";
    caller == this || caller == this.owner || caller_perms().wizard || raise(E_PERM);
    "Clear ref - anonymous agent will be GC'd";
    this.agent = #-1;
    "Create fresh agent with current configuration";
    this:configure();
  endverb

  verb _register_common_tools (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register tools common to all LLM wearables. Called by child configure verbs.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {agent} = args;
    "Register explain tool";
    explain_tool = $llm_agent_tool:mk("explain", "Share your thought process, findings, or reasoning with the user. Use this frequently to narrate what you're investigating, explain what you discovered from tool results, or describe your plan before taking actions.", ["type" -> "object", "properties" -> ["message" -> ["type" -> "string", "description" -> "Your explanation, findings, or thought process to share with the user"]], "required" -> {"message"}], this, "_tool_explain");
    agent:add_tool("explain", explain_tool);
    "Register ask_user tool";
    ask_user_tool = $llm_agent_tool:mk("ask_user", "Ask the user a question and receive their response. Provide 'choices' for a multiple-choice prompt or set 'input_type' to 'text'/'text_area' with an optional 'placeholder' (and 'rows' for text_area) to gather free-form input. If no options are provided, the prompt defaults to Accept/Stop/Request Change with a follow-up text box for requested changes.", ["type" -> "object", "properties" -> ["question" -> ["type" -> "string", "description" -> "The question or proposal to present to the user"], "choices" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Optional list of explicit choices to show the user"], "input_type" -> ["type" -> "string", "description" -> "Optional input style: 'text', 'text_area', or 'yes_no'"], "placeholder" -> ["type" -> "string", "description" -> "Placeholder to show in free-form prompts"], "rows" -> ["type" -> "integer", "description" -> "Number of rows when using text_area prompts"]], "required" -> {"question"}], this, "_tool_ask_user");
    agent:add_tool("ask_user", ask_user_tool);
    "Register todo list tools";
    todo_write_tool = $llm_agent_tool:mk("todo_write", "Replace the entire todo list. Use this to track multi-step tasks. Each todo needs 'content' (what to do) and 'status' ('pending', 'in_progress', or 'completed'). Mark tasks in_progress when starting, completed when done.", ["type" -> "object", "properties" -> ["todos" -> ["type" -> "array", "items" -> ["type" -> "object", "properties" -> ["content" -> ["type" -> "string"], "status" -> ["type" -> "string", "enum" -> {"pending", "in_progress", "completed"}]], "required" -> {"content", "status"}], "description" -> "List of todo items"]], "required" -> {"todos"}], this, "_tool_todo_write");
    agent:add_tool("todo_write", todo_write_tool);
    get_todos_tool = $llm_agent_tool:mk("get_todos", "Get the current todo list to see what tasks are pending, in progress, or completed.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "_tool_get_todos");
    agent:add_tool("get_todos", get_todos_tool);
  endverb

  verb _tool_todo_write (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Replace the entire todo list to track multi-step tasks";
    {args_map, actor} = args;
    actor || this:_action_perms_check();
    todos_input = args_map["todos"];
    typeof(todos_input) != TYPE_LIST && raise(E_TYPE, "todos must be a list");
    todo_items = {};
    for item in (todos_input)
      content = item["content"];
      status_str = item["status"];
      status = status_str == "pending" ? 'pending | (status_str == "in_progress" ? 'in_progress | (status_str == "completed" ? 'completed | raise(E_INVARG, "Invalid status: " + status_str)));
      todo_items = {@todo_items, ["content" -> content, "status" -> status]};
    endfor
    this.agent:set_todos(todo_items);
    summary = {tostr(length(todo_items)) + " todos set:"};
    for todo in (this.agent:get_todos())
      prefix = todo["status"] == 'completed ? "[x]" | (todo["status"] == 'in_progress ? "[>]" | "[ ]");
      summary = {@summary, "  " + prefix + " " + todo["content"]};
    endfor
    return summary:join("\n");
  endverb

  verb _tool_get_todos (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the current todo list";
    {args_map, actor} = args;
    actor || this:_action_perms_check();
    return this.agent:format_todos();
  endverb

  verb _register_authoring_tools (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register doc/message/rule authoring tools. Called by child configure verbs.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {agent} = args;
    "Register doc_lookup tool";
    doc_tool = $llm_agent_tool:mk("doc_lookup", "Read developer documentation for an object, verb, or property. Use formats: obj, obj:verb, obj.property.", ["type" -> "object", "properties" -> ["target" -> ["type" -> "string", "description" -> "Object/verb/property reference, e.g., '$sub_utils', '#61:drop_msg', '#61.get_msg'"]], "required" -> {"target"}], this, "_tool_doc_lookup");
    agent:add_tool("doc_lookup", doc_tool);
    "Register message tools";
    list_messages_tool = $llm_agent_tool:mk("list_messages", "List message template properties (*_msg) and message bags (*_msg_bag/_msgs) on an object. Equivalent to @messages.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#62', '$room', 'here')"]], "required" -> {"object"}], this, "_tool_list_messages");
    agent:add_tool("list_messages", list_messages_tool);
    get_message_tool = $llm_agent_tool:mk("get_message_template", "Show a single message template or list the entries of a message bag. Equivalent to @getm.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msg, _msgs, or _msg_bag)"]], "required" -> {"object", "property"}], this, "_tool_get_message_template");
    agent:add_tool("get_message_template", get_message_tool);
    set_message_tool = $llm_agent_tool:mk("set_message_template", "Set a message template on an object property. For bags (_msgs/_msg_bag), replace all entries with a single template; use add_message_template to append instead.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msg, _msgs, or _msg_bag)"], "template" -> ["type" -> "string", "description" -> "Template string using {sub} syntax"]], "required" -> {"object", "property", "template"}], this, "_tool_set_message_template");
    agent:add_tool("set_message_template", set_message_tool);
    add_message_tool = $llm_agent_tool:mk("add_message_template", "Append a message template to a message bag property (_msgs or _msg_bag). Equivalent to @add-message.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msgs or _msg_bag)"], "template" -> ["type" -> "string", "description" -> "Template string using {sub} syntax"]], "required" -> {"object", "property", "template"}], this, "_tool_add_message_template");
    agent:add_tool("add_message_template", add_message_tool);
    del_message_tool = $llm_agent_tool:mk("delete_message_template", "Remove a message entry by index from a message bag property. Equivalent to @del-message.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Property name (must end with _msgs or _msg_bag)"], "index" -> ["type" -> "integer", "description" -> "1-based index to remove"]], "required" -> {"object", "property", "index"}], this, "_tool_delete_message_template");
    agent:add_tool("delete_message_template", del_message_tool);
    "Register rule tools";
    list_rules_tool = $llm_agent_tool:mk("list_rules", "List all rule properties (*_rule) on an object and their current expressions. Rules control access to object operations like locking containers. Equivalent to @rules.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object to inspect (e.g., '#10', '$container', 'chest')"]], "required" -> {"object"}], this, "_tool_list_rules");
    agent:add_tool("list_rules", list_rules_tool);
    set_rule_tool = $llm_agent_tool:mk("set_rule", "Set an access control rule on an object property. Rules are logical expressions like 'Key is(\"golden key\")?' or 'NOT This is_locked()?'. See $rule_engine docs for syntax. Equivalent to @set-rule.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Rule property name (must end with _rule, e.g., 'lock_rule')"], "expression" -> ["type" -> "string", "description" -> "Rule expression using Datalog syntax (see $rule_engine docs)"]], "required" -> {"object", "property", "expression"}], this, "_tool_set_rule");
    agent:add_tool("set_rule", set_rule_tool);
    show_rule_tool = $llm_agent_tool:mk("show_rule", "Display the current expression for a specific rule property. Equivalent to @show-rule.", ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference"], "property" -> ["type" -> "string", "description" -> "Rule property name (must end with _rule)"]], "required" -> {"object", "property"}], this, "_tool_show_rule");
    agent:add_tool("show_rule", show_rule_tool);
  endverb

  verb _tool_doc_lookup (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Fetch developer documentation for object/verb/property (like @doc)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    target_spec = args_map["target"];
    set_task_perms(wearer);
    "Handle special alias cases";
    alias_obj = false;
    if (typeof(target_spec) == TYPE_STR)
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
      target_obj = $match:match_object(object_str, wearer);
      typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
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
    doc_body = typeof(doc_text) == TYPE_LIST ? doc_text:join("\n") | doc_text;
    return title + "\n\n" + (doc_body ? doc_body | "(No documentation available)");
  endverb

  verb _tool_list_messages (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List *_msg properties and message bags on an object (like @messages)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    msg_props = $obj_utils:message_properties(target_obj);
    !msg_props && return tostr(target_obj) + " has no message properties. (@messages command available)";
    lines = {"Message properties for " + tostr(target_obj) + ":"};
    for prop_info in (msg_props)
      {prop_name, prop_value} = prop_info;
      value_summary = typeof(prop_value) == TYPE_OBJ && isa(prop_value, $msg_bag) ? "message bag (" + tostr(length(prop_value:entries())) + " entries)" | (typeof(prop_value) == TYPE_LIST ? `$sub_utils:decompile(prop_value) ! ANY => toliteral(prop_value)' | toliteral(prop_value));
      lines = {@lines, " - " + prop_name + ": " + value_summary};
    endfor
    return lines:join("\n");
  endverb

  verb _tool_get_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Read a single message template (like @getm)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    prop_name = args_map["property"];
    prop_name:ends_with("_msg") || prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with _msg/_msgs/_msg_bag");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property '" + prop_name + "' not found on " + tostr(target_obj));
    value = target_obj.(prop_name);
    if (typeof(value) == TYPE_OBJ && isa(value, $msg_bag))
      entries = value:entries();
      !entries && return tostr(target_obj) + "." + prop_name + " = (empty message bag)";
      lines = {tostr(target_obj) + "." + prop_name + " (message bag, " + tostr(length(entries)) + " entries):"};
      for i, entry in (entries)
        lines = {@lines, tostr(i) + ". " + (typeof(entry) == TYPE_LIST ? `$sub_utils:decompile(entry) ! ANY => toliteral(entry)' | toliteral(entry))};
      endfor
      return lines:join("\n");
    endif
    display_value = typeof(value) == TYPE_LIST ? `$sub_utils:decompile(value) ! ANY => toliteral(value)' | toliteral(value);
    return tostr(target_obj) + "." + prop_name + " = " + display_value + " (@getm command available)";
  endverb

  verb _tool_set_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set a message template (like @setm). Creates property if missing.";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    {prop_name, template} = {args_map["property"], args_map["template"]};
    prop_name:ends_with("_msg") || prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with _msg/_msgs/_msg_bag");
    template || raise(E_INVARG, "Template string required");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    {success, compiled} = $obj_utils:validate_and_compile_template(template);
    success || raise(E_INVARG, "Template compilation failed: " + compiled);
    obj_name = `target_obj.name ! ANY => tostr(target_obj)';
    prop_exists = prop_name in target_obj:all_properties();
    if (!prop_exists)
      "Property doesn't exist - try to create it";
      if (!wearer.wizard && target_obj.owner != wearer)
        raise(E_PERM, "Cannot add property to " + tostr(target_obj) + ": not owner");
      endif
      add_property(target_obj, prop_name, compiled, {wearer, "rc"});
      return "Created and set " + prop_name + " on \"" + obj_name + "\" (" + tostr(target_obj) + ").";
    endif
    "Property exists - check if writable";
    {writable, error_msg} = $obj_utils:check_message_property_writable(target_obj, prop_name, wearer);
    writable || raise(E_PERM, error_msg);
    existing = target_obj.(prop_name);
    if (typeof(existing) == TYPE_OBJ && isa(existing, $msg_bag))
      existing.entries = {compiled};
      return "Replaced bag " + prop_name + " on \"" + obj_name + "\" (" + tostr(target_obj) + ") with a single entry (@setm).";
    endif
    $obj_utils:set_compiled_message(target_obj, prop_name, compiled, wearer);
    return "Set " + prop_name + " on \"" + obj_name + "\" (" + tostr(target_obj) + "). (@setm command available)";
  endverb

  verb _tool_add_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Append a template to a message bag (like @add-message)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    {prop_name, template} = {args_map["property"], args_map["template"]};
    prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with _msgs/_msg_bag");
    template || raise(E_INVARG, "Template string required");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    bag = `target_obj.(prop_name) ! E_PROPNF => #-1';
    !valid(bag) && (bag = $msg_bag:create(true)) && (target_obj.(prop_name) = bag);
    bag:add($sub_utils:compile(template));
    return "Added entry to " + tostr(target_obj) + "." + prop_name + ".";
  endverb

  verb _tool_delete_message_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Delete a template by index from a message bag (like @del-message)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    {prop_name, idx} = {args_map["property"], args_map["index"]};
    prop_name:ends_with("_msgs") || prop_name:ends_with("_msg_bag") || raise(E_INVARG, "Property must end with _msgs/_msg_bag");
    typeof(idx) == TYPE_INT || raise(E_TYPE, "Index must be integer");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    bag = `target_obj.(prop_name) ! E_PROPNF => #-1';
    valid(bag) && isa(bag, $msg_bag) || raise(E_INVARG, "Message bag not found on " + tostr(target_obj) + "." + prop_name);
    bag:remove(idx);
    return "Removed entry #" + tostr(idx) + " from " + tostr(target_obj) + "." + prop_name + ".";
  endverb

  verb _tool_list_rules (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: List *_rule properties on an object (like @rules)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    rule_props = $obj_utils:rule_properties(target_obj);
    !rule_props && return tostr(target_obj) + " has no rule properties. (@rules command available)";
    lines = {"Rule properties for " + tostr(target_obj) + ":"};
    for prop_info in (rule_props)
      {prop_name, prop_value} = prop_info;
      lines = {@lines, " - " + prop_name + ": " + (prop_value == 0 ? "(not set)" | $rule_engine:decompile_rule(prop_value))};
    endfor
    return lines:join("\n");
  endverb

  verb _tool_set_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Set a rule on an object property (like @set-rule)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    {prop_name, expression} = {args_map["property"], args_map["expression"]};
    prop_name:ends_with("_rule") || raise(E_INVARG, "Property must end with _rule");
    expression || raise(E_INVARG, "Rule expression required");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property '" + prop_name + "' not found on " + tostr(target_obj) + ". Use add_property to create it first.");
    "Handle special cases";
    if (expression == "0" || expression == "none" || expression == "always" || expression == "true")
      target_obj.(prop_name) = 0;
      return "Cleared rule on " + tostr(target_obj) + "." + prop_name + " (always passes)";
    endif
    if (expression == "false" || expression == "never" || expression == "locked")
      "Create an always-false rule using a fact that can never match";
      rule = $rule_engine:parse_expression("This is(\"__never_matches__\")?", tosym(prop_name), wearer);
      target_obj.(prop_name) = rule;
      return "Set " + tostr(target_obj) + "." + prop_name + " to always fail (locked)";
    endif
    rule = $rule_engine:parse_expression(expression, tosym(prop_name), wearer);
    validation = $rule_engine:validate_rule(rule);
    validation['valid] || raise(E_INVARG, "Rule validation failed: " + validation['warnings]:join("; "));
    target_obj.(prop_name) = rule;
    return "Set " + tostr(target_obj) + "." + prop_name + " = " + expression;
  endverb

  verb _tool_show_rule (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Display a rule property expression (like @show-rule)";
    {args_map, actor} = args;
    wearer = actor || this:_action_perms_check();
    prop_name = args_map["property"];
    prop_name:ends_with("_rule") || raise(E_INVARG, "Property must end with _rule");
    set_task_perms(wearer);
    target_obj = $match:match_object(args_map["object"], wearer);
    typeof(target_obj) == TYPE_OBJ || raise(E_INVARG, "Object not found");
    valid(target_obj) || raise(E_INVARG, "Object no longer exists");
    prop_name in target_obj:all_properties() || raise(E_INVARG, "Property '" + prop_name + "' not found on " + tostr(target_obj));
    rule = target_obj.(prop_name);
    return tostr(target_obj) + "." + prop_name + " = " + (rule == 0 ? "(not set)" | $rule_engine:decompile_rule(rule));
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
    metadata = {{"input_type", "text"}, {"prompt", $ansi:colorize(this.prompt_label, this.prompt_color) + " " + this.prompt_text}, {"placeholder", this.placeholder_text}, {"tts_prompt", this.prompt_text}};
    query = player:read_with_prompt(metadata):trim();
    if (!query)
      player:inform_current($event:mk_error(player, "Query cancelled - no input provided."));
      return;
    endif
    "Show query received";
    player:inform_current($event:mk_info(player, $ansi:colorize(this.prompt_label, this.prompt_color) + " Query received: " + $ansi:colorize(query, 'white)):as_inset():with_group('llm, this):with_tts("Query received: " + query));
    "Start progress tracking (replaces the old [PROCESSING] message)";
    tracking_active = this:_start_progress_tracking(player);
    "Set token owner for budget tracking";
    this.agent.token_owner = player;
    "Send to agent with continuation support (max 3 continuations)";
    response = this.agent:send_message(query);
    continuations = 0;
    max_continuations = 3;
    while (typeof(response) == TYPE_ERR && error_code(response) == E_QUOTA && continuations < max_continuations)
      "Hit iteration limit - end current progress and ask user";
      if (tracking_active)
        this:_end_progress_tracking('complete);
      endif
      player:inform_current($event:mk_info(player, $ansi:colorize("[" + this.tool_name + "]", 'bright_yellow) + " Agent hit iteration limit (" + tostr(this.agent.max_iterations) + " iterations)."):as_inset():with_group('llm, this):with_tts(this.tool_name + " hit iteration limit after " + tostr(this.agent.max_iterations) + " iterations."));
      metadata = {{"input_type", "yes_no"}, {"prompt", "Continue agent execution?"}};
      user_choice = player:read_with_prompt(metadata);
      if (user_choice != "yes")
        this.agent.current_iteration = 0;
        this:_show_token_usage(player);
        player:inform_current($event:mk_info(player, "Agent stopped at user request after reaching iteration limit."):as_inset():with_group('llm, this));
        return;
      endif
      "User chose to continue - restart progress tracking";
      continuations = continuations + 1;
      player:inform_current($event:mk_info(player, $ansi:colorize("[" + this.tool_name + "]", 'bright_yellow) + " Continuing... (continuation " + tostr(continuations) + "/" + tostr(max_continuations) + ")"):as_inset():with_group('llm, this):with_tts("Continuing, continuation " + tostr(continuations) + " of " + tostr(max_continuations) + "."));
      tracking_active = this:_start_progress_tracking(player);
      response = this.agent:send_message("Continue where you left off. Complete any remaining work from the previous request.");
    endwhile
    "End progress tracking";
    if (tracking_active)
      final_status = typeof(response) == TYPE_ERR ? 'error | 'complete;
      this:_end_progress_tracking(final_status);
    endif
    "Reset iteration counter";
    this.agent.current_iteration = 0;
    "Show token usage summary";
    this:_show_token_usage(player);
    "Check if we exhausted all continuations";
    if (typeof(response) == TYPE_ERR && error_code(response) == E_QUOTA)
      player:inform_current($event:mk_error(player, "Agent reached maximum iterations even after " + tostr(max_continuations) + " continuations. Task may be too complex."));
      return;
    endif
    "If response is still an ERR but not E_QUOTA, display it as an error";
    if (typeof(response) == TYPE_ERR)
      player:inform_current($event:mk_error(player, "Error: `" + toliteral(response) + "`"):as_djot());
      return;
    endif
    "Display final response with djot rendering";
    event = $event:mk_info(player, response):as_djot():as_inset():with_group('llm, this);
    player:inform_current(event);
  endverb

  verb _start_progress_tracking (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Begin tracking progress.";
    {wearer} = args;
    caller == this || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    return false;
  endverb

  verb _format_progress_display (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format the current progress steps for display.";
    "Returns a formatted block showing recent steps with status indicators.";
    "Permission check";
    caller == this || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    steps = this.progress_steps;
    total = length(steps);
    if (total == 0)
      return $ansi:colorize("[" + this.tool_name + "]", 'yellow) + " Initializing...";
    endif
    "Count completed vs in-progress";
    completed = 0;
    in_progress = 0;
    errors = 0;
    for step in (steps)
      if (step[2] == 'complete)
        completed = completed + 1;
      elseif (step[2] == 'in_progress)
        in_progress = in_progress + 1;
      elseif (step[2] == 'error)
        errors = errors + 1;
      endif
    endfor
    "Build header with iteration info";
    iter_info = "";
    if (valid(this.agent))
      iter = `this.agent.current_iteration ! ANY => 0';
      max_iter = `this.agent.max_iterations ! ANY => 10';
      if (iter > 0)
        iter_info = " Step " + tostr(iter) + "/" + tostr(max_iter);
      endif
    endif
    header = $ansi:colorize("\u2500\u2500\u2500 " + this.tool_name + iter_info + " ", 'cyan);
    status_parts = {};
    if (completed > 0)
      status_parts = {@status_parts, tostr(completed) + " done"};
    endif
    if (in_progress > 0)
      status_parts = {@status_parts, tostr(in_progress) + " active"};
    endif
    if (errors > 0)
      status_parts = {@status_parts, $ansi:colorize(tostr(errors) + " errors", 'red)};
    endif
    if (length(status_parts) > 0)
      header = header + $ansi:colorize("(" + status_parts:join(", ") + ")", 'dim);
    endif
    "Build list of paragraph elements";
    visible_lines = {$format.paragraph:mk(header)};
    "Add task status line if there's an active investigation task";
    task_id = `this.current_investigation_task ! ANY => 0';
    if (task_id > 0 && valid(this.agent))
      tasks = `this.agent.current_tasks ! ANY => []';
      if (typeof(tasks) == TYPE_MAP && maphaskey(tasks, task_id))
        task = tasks[task_id];
        task_desc = `task.description ! ANY => "Unknown"';
        if (length(task_desc) > 50)
          task_desc = task_desc[1..50] + "...";
        endif
        findings_count = `length(task.findings) ! ANY => 0';
        task_status = `task.status ! ANY => 'unknown';
        "Format task line";
        task_line = $ansi:colorize("    \u25B6 Task #" + tostr(task_id) + ": ", 'bright_blue) + task_desc;
        if (findings_count > 0)
          task_line = task_line + $ansi:colorize(" [" + tostr(findings_count) + " findings]", 'green);
        endif
        visible_lines = {@visible_lines, $format.paragraph:mk(task_line)};
      endif
    endif
    max_visible = this.progress_max_visible;
    start_idx = max(1, total - max_visible + 1);
    "Add ellipsis if we truncated";
    if (start_idx > 1)
      visible_lines = {@visible_lines, $format.paragraph:mk($ansi:colorize("  ... (" + tostr(start_idx - 1) + " earlier)", 'dim))};
    endif
    for i in [start_idx..total]
      step = steps[i];
      {name, status, summary} = step;
      if (status == 'complete)
        line = $ansi:colorize("  \u2713 ", 'green) + summary;
      elseif (status == 'error)
        line = $ansi:colorize("  \u2717 ", 'red) + summary;
      else
        line = $ansi:colorize("  \u25BA ", 'yellow) + summary;
      endif
      visible_lines = {@visible_lines, $format.paragraph:mk(line)};
    endfor
    return $format.block:mk(@visible_lines);
  endverb

  verb _update_progress (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Update progress tracking with a new step or status change.";
    "Args: tool_name, status ('started, 'complete, 'error), ?summary";
    "For 'complete status, summary is optional - keeps original if not provided.";
    {tool_name, status, ?summary = ""} = args;
    "Permission check";
    caller == this || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    if (!this.progress_rewrite_id)
      return false;
    endif
    "Update steps list based on status";
    if (status == 'started)
      "Add new in-progress step";
      this.progress_steps = {@this.progress_steps, {tool_name, 'in_progress, summary}};
    elseif (status == 'complete || status == 'error)
      "Mark last matching in-progress step, preserving summary unless error with new message";
      found = false;
      new_steps = {};
      for i in [length(this.progress_steps)..1]
        step = this.progress_steps[i];
        if (!found && step[1] == tool_name && step[2] == 'in_progress)
          "Keep original summary for complete, use new summary only for errors with message";
          new_summary = status == 'error && summary ? summary | step[3];
          step = {tool_name, status, new_summary};
          found = true;
        endif
        new_steps = {step, @new_steps};
      endfor
      this.progress_steps = new_steps;
    endif
    return true;
  endverb

  verb _end_progress_tracking (this none this) owner: ARCH_WIZARD flags: "rxd"
    "End progress tracking with a final summary rewrite.";
    "Args: ?final_status ('complete or 'error, default 'complete)";
    {?final_status = 'complete} = args;
    "Permission check";
    caller == this || caller_perms() == this.owner || caller_perms().wizard || raise(E_PERM);
    wearer = this:wearer();
    if (valid(wearer) && this.progress_rewrite_id)
      "Build final summary";
      total = length(this.progress_steps);
      errors = 0;
      for step in (this.progress_steps)
        if (step[2] == 'error)
          errors = errors + 1;
        endif
      endfor
      if (final_status == 'error || errors > 0)
        summary = $ansi:colorize("\u2500\u2500\u2500 " + this.tool_name + " ", 'yellow);
        if (errors > 0)
          summary = summary + $ansi:colorize("Completed with " + tostr(errors) + " error(s)", 'red);
        else
          summary = summary + $ansi:colorize("Error", 'red);
        endif
      else
        summary = $ansi:colorize("\u2500\u2500\u2500 " + this.tool_name + " Complete ", 'bright_green);
      endif
      summary = summary + $ansi:colorize(" (" + tostr(total) + " operations)", 'dim);
      final_event = $event:mk_info(wearer, summary):with_presentation_hint('inset):with_group('llm, this);
      wearer:rewrite_event(this.progress_rewrite_id, final_event, this.progress_connection);
    endif
    "Clear tracking state";
    this.progress_rewrite_id = "";
    this.progress_connection = 0;
    this.progress_steps = {};
  endverb
endobject