object LLM_AGENT
  name: "LLM Agent"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property cancel_requested (owner: HACKER, flags: "r") = false;
  property compaction_threshold (owner: ARCH_WIZARD, flags: "r") = 0.7;
  property context (owner: ARCH_WIZARD, flags: "") = {};
  property current_continuation (owner: ARCH_WIZARD, flags: "r") = 0;
  property current_iteration (owner: ARCH_WIZARD, flags: "r") = 0;
  property last_token_usage (owner: ARCH_WIZARD, flags: "") = [];
  property max_iterations (owner: ARCH_WIZARD, flags: "") = 10;
  property min_messages_to_keep (owner: ARCH_WIZARD, flags: "") = 15;
  property system_prompt (owner: ARCH_WIZARD, flags: "rc") = "";
  property token_limit (owner: ARCH_WIZARD, flags: "") = 4000;
  property token_owner (owner: ARCH_WIZARD, flags: "") = #-1;
  property tool_callback (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property tools (owner: ARCH_WIZARD, flags: "") = [];
  property total_tokens_used (owner: ARCH_WIZARD, flags: "") = 0;

  override description = "Prototype for LLM-powered agents. Maintains conversation context and executes tool calls.";
  override import_export_id = "llm_agent";

  verb initialize (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Initialize context with system prompt when agent is created";
    this:_challenge_permissions(caller);
    if (this.system_prompt)
      this.context = {["role" -> "system", "content" -> this.system_prompt]};
    endif
  endverb

  verb add_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register a tool for this agent to use";
    this:_challenge_permissions(caller);
    {tool_name, tool_flyweight} = args;
    typeof(tool_name) == STR || raise(E_TYPE);
    typeof(tool_flyweight) == FLYWEIGHT || raise(E_TYPE);
    new_tools = this.tools;
    new_tools[tool_name] = tool_flyweight;
    this.tools = new_tools;
  endverb

  verb remove_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Unregister a tool";
    {tool_name} = args;
    new_tools = this.tools;
    new_tools = mapdelete(new_tools, tool_name);
    this.tools = new_tools;
  endverb

  verb add_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Add a message to context";
    this:_challenge_permissions(caller);
    {role, content} = args;
    this.context = {@this.context, ["role" -> role, "content" -> content]};
  endverb

  verb _get_tool_schemas (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get OpenAI-format tool schemas from registered tools";
    this:_challenge_permissions(caller);
    schemas = {};
    for tool_name in (mapkeys(this.tools))
      tool_flyweight = this.tools[tool_name];
      schemas = {@schemas, tool_flyweight:to_schema()};
    endfor
    return schemas;
  endverb

  verb _find_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find a registered tool by name";
    this:_challenge_permissions(caller);
    {tool_name} = args;
    if (maphaskey(this.tools, tool_name))
      return this.tools[tool_name];
    endif
    return false;
  endverb

  verb send_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Main entry point: send a message and get response, executing tools as needed";
    {user_input} = args;
    this:_challenge_permissions(caller);
    this:add_message("user", user_input);
    "Clear any previous cancellation request at start of new message";
    this.cancel_requested = false;
    this.current_iteration = 0;
    for iteration in [1..this.max_iterations]
      "Track current iteration for visibility";
      this.current_iteration = iteration;
      "Check if cancellation was requested";
      if (this.cancel_requested)
        this.cancel_requested = false;
        this.current_iteration = 0;
        return "Operation cancelled by user.";
      endif
      "Check player token budget before API call";
      if (valid(this.token_owner) && is_player(this.token_owner))
        set_task_perms(caller_perms());
        budget = `this.token_owner.llm_token_budget ! ANY => 20000000';
        used = `this.token_owner.llm_tokens_used ! ANY => 0';
        if (used >= budget)
          return "Error: LLM token budget exceeded. You have used " + tostr(used) + " of " + tostr(budget) + " tokens. Contact a wizard to increase your budget.";
        endif
      endif
      tool_schemas = this:_get_tool_schemas();
      "Retry API calls on transient errors (network issues, rate limits, etc.)";
      max_retries = 3;
      retry_count = 0;
      response = false;
      while (retry_count <= max_retries)
        try
          response = $llm_client:chat(this.context, false, false, tool_schemas);
          "Yield execution after API call to avoid tick limit";
          suspend(0);
          break;
        except e (ANY)
          server_log("ERROR: " + toliteral(e));
          retry_count = retry_count + 1;
          if (retry_count > max_retries)
            "All retries exhausted, re-raise the error";
            raise(E_INVARG, "LLM API call failed after retries: " + toliteral(e));
          endif
          "Wait before retrying - exponential backoff";
          suspend(retry_count);
        endtry
      endwhile
      "Track token usage";
      if (typeof(response) == MAP && maphaskey(response, "usage"))
        this.last_token_usage = response["usage"];
        if (maphaskey(response["usage"], "total_tokens"))
          tokens_this_call = response["usage"]["total_tokens"];
          this.total_tokens_used = this.total_tokens_used + tokens_this_call;
          "Update player's token usage - needs owner perms to write to ARCH_WIZARD-owned properties";
          if (valid(this.token_owner) && is_player(this.token_owner))
            this.token_owner.llm_tokens_used = this.token_owner.llm_tokens_used + tokens_this_call;
            "Log usage with timestamp";
            usage_entry = ["timestamp" -> time(), "tokens" -> tokens_this_call, "usage" -> response["usage"]];
            this.token_owner.llm_usage_log = {@this.token_owner.llm_usage_log, usage_entry};
          endif
        endif
        "Check if we need to compact";
        if (this:needs_compaction())
          this:compact_context();
        endif
      endif
      "Check if response has tool calls";
      if (typeof(response) == MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
        choice = response["choices"][1];
        message = choice["message"];
        "Check for tool calls";
        if (maphaskey(message, "tool_calls") && message["tool_calls"])
          "Execute each tool call";
          tool_results = {};
          for tool_call in (message["tool_calls"])
            "Check if cancellation was requested before executing each tool";
            if (this.cancel_requested)
              this.cancel_requested = false;
              this.current_iteration = 0;
              "Save assistant message with tool calls to context";
              this.context = {@this.context, message};
              "Add partial tool results if any were completed";
              for tool_result in (tool_results)
                this.context = {@this.context, tool_result};
              endfor
              return "Operation cancelled by user. " + tostr(length(tool_results)) + " of " + tostr(length(message["tool_calls"])) + " tools completed before cancellation.";
            endif
            tool_name = tool_call["function"]["name"];
            tool_args = tool_call["function"]["arguments"];
            tool = this:_find_tool(tool_name);
            if (typeof(tool) == FLYWEIGHT)
              try
                "Notify callback if set";
                if (valid(this.tool_callback))
                  this.tool_callback:on_tool_call(tool_name, tool_args);
                endif
                result = tool:execute(tool_args);
                "Yield execution after tool call to avoid tick limit";
                suspend(0);
                tool_results = {@tool_results, ["tool_call_id" -> tool_call["id"], "role" -> "tool", "name" -> tool_name, "content" -> tostr(result)]};
              except e (ANY)
                error_msg = "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
                if (length(e) > 2 && typeof(e[3]) == LIST)
                  error_msg = error_msg + "\nTraceback: " + toliteral(e[3]);
                endif
                tool_results = {@tool_results, ["tool_call_id" -> tool_call["id"], "role" -> "tool", "name" -> tool_name, "content" -> error_msg]};
              endtry
            else
              tool_results = {@tool_results, ["tool_call_id" -> tool_call["id"], "role" -> "tool", "name" -> tool_name, "content" -> "Error: tool not found"]};
            endif
          endfor
          "Add assistant message with tool calls to context";
          this.context = {@this.context, message};
          "Add tool results to context";
          for tool_result in (tool_results)
            this.context = {@this.context, tool_result};
          endfor
          "Yield before making another API call with tool results";
          suspend(0);
        else
          "No tool calls, this is the final response";
          final_content = message["content"];
          this:add_message("assistant", final_content);
          this.current_iteration = 0;
          return final_content;
        endif
      else
        "Unexpected response format";
        this.current_iteration = 0;
        return tostr(response);
      endif
    endfor
    this.current_iteration = 0;
    return "Error: Maximum iterations exceeded";
  endverb

  verb reset_context (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clear context and reinitialize with system prompt";
    this:_challenge_permissions(caller);
    this:initialize();
    this.total_tokens_used = 0;
  endverb

  verb needs_compaction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if context needs compaction based on token usage";
    this:_challenge_permissions(caller);
    if (typeof(this.last_token_usage) != MAP)
      return false;
    endif
    if (!maphaskey(this.last_token_usage, "prompt_tokens"))
      return false;
    endif
    prompt_tokens = this.last_token_usage["prompt_tokens"];
    threshold = this.token_limit * this.compaction_threshold;
    return prompt_tokens > threshold;
  endverb

  verb compact_context (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Compact context by summarizing old messages and keeping recent ones";
    this:_challenge_permissions(caller);
    if (length(this.context) <= this.min_messages_to_keep + 1)
      "Not enough messages to compact";
      return;
    endif
    "Separate system prompt, old messages, and recent messages";
    system_msg = this.context[1];
    old_messages = (this.context)[2..$ - this.min_messages_to_keep];
    recent_messages = (this.context)[$ - this.min_messages_to_keep + 1..$];
    "Build summary request from old messages";
    summary_context = {system_msg, ["role" -> "user", "content" -> "Summarize the following conversation history in 3-4 concise sentences, preserving the most important information:\n\n" + toliteral(old_messages)]};
    "Get summary from LLM";
    try
      response = $llm_client:chat(summary_context, false, false, {});
      if (typeof(response) == MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
        summary = response["choices"][1]["message"]["content"];
        "Rebuild context with system prompt, summary, and recent messages";
        this.context = {system_msg, ["role" -> "assistant", "content" -> "Previous conversation summary: " + summary], @recent_messages};
        server_log("LLM agent context compacted: " + tostr(length(old_messages)) + " messages summarized, " + tostr(length(recent_messages)) + " kept");
      else
        "Compaction failed, fall back to sliding window";
        this.context = {system_msg, @recent_messages};
        server_log("LLM agent context compacted: summary failed, using sliding window");
      endif
    except e (ANY)
      "Compaction failed, fall back to sliding window";
      this.context = {system_msg, @recent_messages};
      server_log("LLM agent context compaction error: " + toliteral(e));
    endtry
  endverb

  verb _challenge_permissions (this none this) owner: ARCH_WIZARD flags: "rxd"
    {who} = args;
    who == #-1 || who == this || who.owner == this.owner || who == this.owner || who.wizard || raise(E_PERM);
    return who;
  endverb
endobject