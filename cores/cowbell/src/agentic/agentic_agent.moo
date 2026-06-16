object AGENTIC_AGENT
  name: "Agentic Agent"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property all_failed_iterations (owner: ARCH_WIZARD, flags: "rc") = 0;
  property cancel_requested (owner: ARCH_WIZARD, flags: "rc") = 0;
  property chat_opts (owner: ARCH_WIZARD, flags: "rc") = 0;
  property client (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property compaction_callback (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property compaction_threshold (owner: ARCH_WIZARD, flags: "rc") = 0.7;
  property consecutive_tool_failures (owner: ARCH_WIZARD, flags: "rc") = [];
  property context (owner: ARCH_WIZARD, flags: "rc") = {};
  property current_iteration (owner: ARCH_WIZARD, flags: "rc") = 0;
  property last_token_usage (owner: ARCH_WIZARD, flags: "rc") = [];
  property max_consecutive_failures (owner: ARCH_WIZARD, flags: "rc") = 3;
  property max_iterations (owner: ARCH_WIZARD, flags: "rc") = 50;
  property min_messages_to_keep (owner: ARCH_WIZARD, flags: "rc") = 15;
  property system_prompt (owner: ARCH_WIZARD, flags: "rc") = "";
  property token_limit (owner: ARCH_WIZARD, flags: "rc") = 128000;
  property token_owner (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property tool_callback (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property tools (owner: ARCH_WIZARD, flags: "rc") = [];
  property total_tokens_used (owner: ARCH_WIZARD, flags: "rc") = 0;

  override description = "Stateful agent prototype that composes $agentic.loop and registered $agentic.tool flyweights.";
  override import_export_hierarchy = {"agentic"};
  override import_export_id = "agentic_agent";

  method initialize owner: ARCH_WIZARD
    "Called on creation. Creates an anonymous LLM client.";
    pass();
    this.client = $llm_client:create(true);
    this.client.name = "Client for " + this.name;
  endmethod

  method _challenge_permissions owner: ARCH_WIZARD
    "Allow self, owner, same-owner objects, and wizards.";
    {who} = args;
    who == #-1 || who == this || who == this.owner && return who;
    caller_perms().wizard && return who;
    try
      who.owner == this.owner && return who;
    except (E_PERM)
    endtry
    try
      who.wizard && return who;
    except (E_PERM)
    endtry
    raise(E_PERM);
  endmethod

  method _log owner: ARCH_WIZARD
    "Internal server log helper.";
    caller == this || raise(E_PERM);
    {message} = args;
    set_task_perms(this.owner, {{"builtin_call", "server_log"}});
    server_log("[agentic] " + message);
  endmethod

  method log_tool_error owner: ARCH_WIZARD
    "Log tool execution errors.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {tool_name, tool_args, error_msg} = args;
    safe_args = typeof(tool_args) == TYPE_STR ? tool_args | toliteral(tool_args);
    set_task_perms(this.owner, {{"builtin_call", "server_log"}});
    server_log("[agentic] tool error [" + toliteral(tool_name) + "]: " + toliteral(error_msg) + " args=" + toliteral(safe_args));
    return 1;
  endmethod

  method add_tool owner: ARCH_WIZARD
    "Register a tool flyweight by name.";
    this:_challenge_permissions(caller);
    {tool_name, tool_flyweight} = args;
    typeof(tool_name) == TYPE_STR || raise(E_TYPE, "tool_name must be string");
    typeof(tool_flyweight) == TYPE_FLYWEIGHT || raise(E_TYPE, "tool_flyweight must be flyweight");
    tools = this.tools;
    tools[tool_name] = tool_flyweight;
    this.tools = tools;
  endmethod

  method remove_tool owner: ARCH_WIZARD
    "Unregister a tool by name.";
    this:_challenge_permissions(caller);
    {tool_name} = args;
    typeof(tool_name) == TYPE_STR || raise(E_TYPE, "tool_name must be string");
    this.tools = mapdelete(this.tools, tool_name);
  endmethod

  method add_message owner: ARCH_WIZARD
    "Append a role/content map to context.";
    this:_challenge_permissions(caller);
    {role, content} = args;
    this.context = {@this.context, ["role" -> role, "content" -> content]};
  endmethod

  method reset_context owner: ARCH_WIZARD
    "Clear context and seed with system prompt if present.";
    this:_challenge_permissions(caller);
    this.context = this.system_prompt ? {["role" -> "system", "content" -> this.system_prompt]} | {};
    this.total_tokens_used = 0;
    this.consecutive_tool_failures = [];
    this.all_failed_iterations = 0;
  endmethod

  method _get_tool_schemas owner: ARCH_WIZARD
    "Internal: return registered tool schemas.";
    caller == this || caller == $agentic.loop || raise(E_PERM);
    return { this.tools[k]:to_schema() for k in (mapkeys(this.tools)) };
  endmethod

  method _find_tool owner: ARCH_WIZARD
    "Internal: find tool by name.";
    caller == this || caller == $agentic.loop || raise(E_PERM);
    {tool_name} = args;
    maphaskey(this.tools, tool_name) && return this.tools[tool_name];
    return #-1;
  endmethod

  method _call_llm_with_retry owner: ARCH_WIZARD
    "Internal: call LLM API with retry logic.";
    caller == this || caller == $agentic.loop || raise(E_PERM);
    {tool_schemas, ?opts = false} = args;
    opts = opts || this.chat_opts;
    max_retries = 3;
    for retry_count in [0..max_retries]
      try
        response = this.client:chat(this.context, opts, false, false, tool_schemas);
        suspend(0);
        return $llm_response:mk(response);
      except e (ANY)
        this:_log("ERROR: " + toliteral(e));
        retry_count >= max_retries && raise(E_INVARG, "LLM API call failed after retries: " + toliteral(e));
        suspend(retry_count + 1);
      endtry
    endfor
  endmethod

  method _track_token_usage owner: ARCH_WIZARD
    "Internal: track token usage and trigger compaction if needed.";
    caller == this || caller == $agentic.loop || raise(E_PERM);
    {response} = args;
    usage = response:usage();
    typeof(usage) == TYPE_MAP || return;
    this.last_token_usage = usage;
    maphaskey(usage, "total_tokens") || return;
    tokens_this_call = usage["total_tokens"];
    this.total_tokens_used = this.total_tokens_used + tokens_this_call;
    this:_update_token_usage(this.token_owner, tokens_this_call);
    this:needs_compaction() && this:compact_context();
  endmethod

  method _execute_tool_call owner: ARCH_WIZARD
    "Internal: execute one tool call and return a tool response message map.";
    caller == this || caller == $agentic.loop || raise(E_PERM);
    {tool_call} = args;
    tool_name = tool_call["function"]["name"];
    tool_args = tool_call["function"]["arguments"];
    tool_call_id = tool_call["id"];
    failures = typeof(this.consecutive_tool_failures) == TYPE_MAP ? this.consecutive_tool_failures | [];
    tool_failure_count = maphaskey(failures, tool_name) ? failures[tool_name] | 0;
    if (tool_failure_count >= this.max_consecutive_failures)
      error_msg = "TOOL BLOCKED: This tool has failed " + tostr(tool_failure_count) + " times in a row. STOP trying to use it and move on. Do NOT retry.";
      this:log_tool_error(tool_name, tool_args, error_msg);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, error_msg) ! ANY';
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> error_msg];
    endif
    tool = this:_find_tool(tool_name);
    if (typeof(tool) != TYPE_FLYWEIGHT)
      this:log_tool_error(tool_name, tool_args, "Tool not found");
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, "Tool not found") ! ANY';
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> "ERROR: tool not found"];
    endif
    try
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_call) && this.tool_callback:on_tool_call(tool_name, tool_args);
      result = tool:execute(tool_args, this.token_owner);
      suspend(0);
      content_out = typeof(result) == TYPE_STR ? result | toliteral(result);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_complete) && `this.tool_callback:on_tool_complete(tool_name, tool_args, content_out) ! ANY';
      is_error_response = typeof(result) == TYPE_STR && (result:starts_with("ERROR:") || result:starts_with("TOOL BLOCKED:"));
      if (is_error_response)
        failures[tool_name] = tool_failure_count + 1;
        this.consecutive_tool_failures = failures;
      elseif (tool_failure_count > 0)
        this.consecutive_tool_failures = mapdelete(failures, tool_name);
      endif
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> content_out];
    except e (ANY)
      error_msg = "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
      length(e) > 2 && typeof(e[3]) == TYPE_LIST && (error_msg = error_msg + "\nTraceback: " + toliteral(e[3]));
      this:log_tool_error(tool_name, tool_args, error_msg);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, error_msg) ! ANY';
      failures[tool_name] = tool_failure_count + 1;
      this.consecutive_tool_failures = failures;
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> error_msg];
    endtry
  endmethod

  method _check_token_budget owner: ARCH_WIZARD
    "Internal: enforce player token budget when token_owner is a player.";
    caller == this || raise(E_PERM);
    {player_obj} = args;
    !valid(player_obj) || !is_player(player_obj) && return 1;
    budget = player_obj.llm_token_budget;
    used = player_obj.llm_tokens_used;
    used >= budget && return "Error: LLM token budget exceeded. You have used " + tostr(used) + " of " + tostr(budget) + " tokens. Contact a wizard to increase your budget.";
    return 1;
  endmethod

  method needs_compaction owner: ARCH_WIZARD
    "Check prompt token usage against compaction threshold.";
    this:_challenge_permissions(caller);
    typeof(this.last_token_usage) == TYPE_MAP || return 0;
    maphaskey(this.last_token_usage, "prompt_tokens") || return 0;
    return this.last_token_usage["prompt_tokens"] > this.token_limit * this.compaction_threshold;
  endmethod

  method _update_token_usage owner: ARCH_WIZARD
    "Internal: update token usage counters on the player.";
    caller == this || raise(E_PERM);
    {player_obj, tokens_used} = args;
    !valid(player_obj) || !is_player(player_obj) && return;
    typeof(tokens_used) == TYPE_INT || raise(E_INVARG, "tokens_used must be integer");
    tokens_used >= 0 || raise(E_INVARG, "tokens_used cannot be negative");
    tokens_used <= 1000000 || raise(E_INVARG, "tokens_used suspiciously large");
    player_obj.llm_tokens_used = player_obj.llm_tokens_used + tokens_used;
    player_obj.llm_usage_log = {@player_obj.llm_usage_log, ["timestamp" -> time(), "tokens" -> tokens_used, "usage" -> this.last_token_usage]};
  endmethod

  method compact_context owner: ARCH_WIZARD
    "Compact context by summarizing older messages and keeping recent ones.";
    this:_challenge_permissions(caller);
    length(this.context) <= this.min_messages_to_keep + 1 && return;
    valid(this.compaction_callback) && respond_to(this.compaction_callback, 'on_compaction_start) && `this.compaction_callback:on_compaction_start() ! ANY';
    system_msg = this.context[1];
    target_split = length(this.context) - this.min_messages_to_keep;
    split_point = target_split;
    for i in [target_split..2]
      msg = this.context[i];
      if (typeof(msg) == TYPE_MAP && maphaskey(msg, "role"))
        role = msg["role"];
        if (role == "user" || role == "system")
          split_point = i;
          break;
        elseif (role == "assistant" && !(maphaskey(msg, "tool_calls") && msg["tool_calls"]))
          split_point = i;
          break;
        endif
      endif
    endfor
    old_messages = this.context[2..split_point - 1];
    recent_messages = this.context[split_point..$];
    length(old_messages) == 0 && return;
    summary_prompt = "Summarize the following conversation history in 3-4 concise sentences, preserving the most important information:\n\n" + toliteral(old_messages);
    summary_context = {system_msg, ["role" -> "user", "content" -> summary_prompt]};
    raw_resp = `this.client:chat(summary_context) ! ANY => []';
    response = $llm_response:mk(raw_resp);
    if (response:is_valid())
      summary_text = response:content();
      this.context = {system_msg, ["role" -> "assistant", "content" -> "Previous conversation summary: " + summary_text], @recent_messages};
      this:_log("context compacted: " + tostr(length(old_messages)) + " summarized, " + tostr(length(recent_messages)) + " kept");
    else
      this.context = {system_msg, @recent_messages};
      this:_log("context compacted: summary failed, using sliding window");
    endif
    valid(this.compaction_callback) && respond_to(this.compaction_callback, 'on_compaction_end) && `this.compaction_callback:on_compaction_end() ! ANY';
  endmethod

  method send_message owner: ARCH_WIZARD
    "Main entry: send user input through agentic loop until completion, cancellation, or explicit failure.";
    {user_input, ?opts = false} = args;
    this:_challenge_permissions(caller);
    this:add_message("user", user_input);
    this.cancel_requested = 0;
    this.current_iteration = 0;
    iteration = 0;
    empty_completion_count = 0;
    toolish_completion_count = 0;
    while (1)
      iteration = iteration + 1;
      this.current_iteration = iteration;
      if (this.cancel_requested)
        this.cancel_requested = 0;
        this.current_iteration = 0;
        return "Operation cancelled.";
      endif
      budget_check = this:_check_token_budget(this.token_owner);
      typeof(budget_check) == TYPE_STR && (this.current_iteration = 0) && return budget_check;
      if (valid(this.tool_callback) && respond_to(this.tool_callback, 'on_model_wait_start))
        `this.tool_callback:on_model_wait_start() ! ANY';
      endif
      turn = $agentic.loop:run_turn(this, opts);
      if (valid(this.tool_callback) && respond_to(this.tool_callback, 'on_model_wait_end))
        `this.tool_callback:on_model_wait_end(turn) ! ANY';
      endif
      status = turn["status"];
      blocked_error = "";
      if (maphaskey(turn, "tool_results") && typeof(turn["tool_results"]) == TYPE_LIST)
        for tr in (turn["tool_results"])
          tc = `tr["content"] ! ANY => ""';
          if (typeof(tc) == TYPE_STR && tc:starts_with("TOOL BLOCKED:"))
            blocked_error = tc;
            break;
          endif
        endfor
      endif
      if (blocked_error)
        this.current_iteration = 0;
        return "Error: " + blocked_error;
      endif
      if (status == "invalid")
        this.current_iteration = 0;
        return tostr(turn["raw"]);
      elseif (status == "complete")
        content = `turn["content"] ! ANY => ""';
        if (typeof(content) == TYPE_STR)
          non_ws = strsub(content, "\n", "");
          non_ws = strsub(non_ws, "\r", "");
          non_ws = strsub(non_ws, "\t", "");
          non_ws = strsub(non_ws, " ", "");
          if (!length(non_ws))
            empty_completion_count = empty_completion_count + 1;
            if (empty_completion_count >= 3)
              this.current_iteration = 0;
              return "Error: Model returned an empty completion 3 times in a row.";
            endif
            guidance = ["role" -> "system", "content" -> "Your last response had no visible content and no tool calls. Provide a direct final response to the user now."];
            this.context = {@this.context, guidance};
            suspend(0);
            continue;
          endif
          probe = content:lowercase();
          looks_like_tool_text = 0;
          if ("{" in probe || "(" in probe)
            hints = {"add_verb", "program_verb", "create_object", "add_property", "set_property", "describe_object", "inspect_object", "list_verbs", "list_properties", "read_property", "get_verb_code", "doc_lookup", "moo_eval", "moo_command"};
            for hint in (hints)
              if (hint + "{" in probe || hint + "(" in probe)
                looks_like_tool_text = 1;
                break;
              endif
            endfor
          endif
          if (looks_like_tool_text)
            toolish_completion_count = toolish_completion_count + 1;
            if (toolish_completion_count >= 3)
              this.current_iteration = 0;
              return "Error: Model returned pseudo tool-call text 3 times instead of executing tools.";
            endif
            guidance = ["role" -> "system", "content" -> "You responded with raw tool-call text instead of executing tools. Execute the tools directly. Only provide final prose once all requested changes are actually done."];
            this.context = {@this.context, guidance};
            suspend(0);
            continue;
          endif
        endif
        this.current_iteration = 0;
        return content;
      elseif (status == "all_failed")
        all_failed_count = this.all_failed_iterations + 1;
        this.all_failed_iterations = all_failed_count;
        tool_results = turn["tool_results"];
        if (all_failed_count >= 3)
          this.current_iteration = 0;
          this.all_failed_iterations = 0;
          return "Error: Agent stopped after 3 consecutive turns where all tools failed. Last errors: " + tool_results[1]["content"];
        endif
        guidance = ["role" -> "system", "content" -> "All tool calls in the previous response failed. Review the error messages above and either: (1) try a different approach, (2) use an ask_user-style tool to request help, or (3) explain what is blocking progress."];
        this.context = {@this.context, guidance};
      else
        this.all_failed_iterations = 0;
        empty_completion_count = 0;
        toolish_completion_count = 0;
      endif
      suspend(0);
    endwhile
  endmethod
endobject
