object RLM_AGENT
  name: "RLM Agent"
  parent: ROOT
  owner: ARCH_WIZARD
  fertile: true
  readable: true

  property actor (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property child_agents (owner: ARCH_WIZARD, flags: "rc") = [];
  property client (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property context (owner: ARCH_WIZARD, flags: "rc") = [];
  property depth (owner: ARCH_WIZARD, flags: "rc") = 0;
  property findings (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property iteration (owner: ARCH_WIZARD, flags: "rc") = 0;
  property last_error (owner: ARCH_WIZARD, flags: "rc") = 0;
  property last_tool (owner: ARCH_WIZARD, flags: "rc") = "";
  property last_tool_citations (owner: ARCH_WIZARD, flags: "rc") = {};
  property max_depth (owner: ARCH_WIZARD, flags: "r") = 5;
  property max_iterations (owner: ARCH_WIZARD, flags: "r") = 100;
  property parent_agent (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property progress_callback (owner: ARCH_WIZARD, flags: "rc") = 0;
  property query (owner: ARCH_WIZARD, flags: "rc") = "";
  property result (owner: ARCH_WIZARD, flags: "rc") = 0;
  property status (owner: ARCH_WIZARD, flags: "rc") = "pending";
  property system_prompt (owner: ARCH_WIZARD, flags: "rc") = "";
  property tools (owner: ARCH_WIZARD, flags: "rc") = {};
  property workspace (owner: ARCH_WIZARD, flags: "rc") = {};

  override import_export_hierarchy = {"llm"};
  override import_export_id = "rlm_agent";

  verb add_tool (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Register a tool for this agent to use.";
    "Accepts both flyweight tools and external tool maps.";
    {tool_name, tool} = args;
    typeof(tool_name) != TYPE_STR && raise(E_TYPE, "tool_name must be string");
    "Accept flyweights or maps with input_schema";
    if (typeof(tool) != TYPE_FLYWEIGHT && typeof(tool) != TYPE_MAP)
      raise(E_TYPE, "tool must be flyweight or map");
    endif
    if (typeof(tool) == TYPE_MAP && !maphaskey(tool, "input_schema"))
      raise(E_TYPE, "tool map must have input_schema");
    endif
    this.tools[tool_name] = tool;
  endverb

  verb _find_tool (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Find a registered tool by name. Returns flyweight or #-1 if not found.";
    caller == this || raise(E_PERM);
    {tool_name} = args;
    maphaskey(this.tools, tool_name) && return this.tools[tool_name];
    return #-1;
  endverb

  verb _get_tool_schemas (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Get OpenAI-format tool schemas from registered tools.";
    caller == this || raise(E_PERM);
    schemas = {};
    for tool_name in (mapkeys(this.tools))
      tool = this.tools[tool_name];
      if (typeof(tool) == TYPE_FLYWEIGHT)
        "Flyweight tool - use its to_schema method";
        schemas = {@schemas, tool:to_schema()};
      elseif (typeof(tool) == TYPE_MAP && maphaskey(tool, "input_schema"))
        "External tool format - convert to OpenAI format";
        schema = ["type" -> "function", "function" -> ["name" -> tool["name"], "description" -> tool["description"], "parameters" -> tool["input_schema"]]];
        schemas = {@schemas, schema};
      endif
    endfor
    return schemas;
  endverb

  verb _call_llm (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Call LLM API with tool schemas. Returns $llm_response flyweight.";
    caller == this || raise(E_PERM);
    {tool_schemas} = args;
    max_retries = 3;
    for retry_count in [0..max_retries]
      try
        response = this.client:chat(this.context, 0, false, false, tool_schemas);
        suspend(0);
        return $llm_response:mk(response);
      except e (ANY)
        "Log full error details via progress callback";
        cb = this.progress_callback;
        if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
          err_str = toliteral(e);
          `cb[1]:_announce_status("LLM Error (attempt " + tostr(retry_count + 1) + "/" + tostr(max_retries + 1) + "): " + err_str) ! ANY';
          "If error message is long, show more of it";
          if (length(e) >= 2 && typeof(e[2]) == TYPE_STR && length(e[2]) > 100)
            `cb[1]:_announce_status("Full error: " + e[2]) ! ANY';
          endif
        endif
        "Store last error for debugging";
        this.last_error = e;
        retry_count >= max_retries && raise(E_INVARG, "LLM API call failed: " + toliteral(e));
        suspend(retry_count + 1);
      endtry
    endfor
  endverb

  verb _execute_tool_call (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Execute a single tool call. Returns result map for context.";
    caller == this || raise(E_PERM);
    {tool_call} = args;
    tool_name = tool_call["function"]["name"];
    raw_args = tool_call["function"]["arguments"];
    tool_call_id = tool_call["id"];
    "Parse JSON args if needed";
    tool_args = [];
    if (typeof(raw_args) == TYPE_STR)
      try
        tool_args = parse_json(raw_args);
      except (ANY)
        return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> "ERROR: Invalid JSON in arguments. Please pass a clean JSON object."];
      endtry
    else
      tool_args = raw_args;
    endif
    "Coerce parameters - apply aggressive cleaning to strings and maps";
    if (typeof(tool_args) == TYPE_MAP)
      for key in (mapkeys(tool_args))
        val = tool_args[key];
        if (typeof(val) == TYPE_STR)
          tool_args[key] = this:_coerce_string(val);
        elseif (typeof(val) == TYPE_MAP)
          tool_args[key] = this:_coerce_string(val);
        elseif (typeof(val) != TYPE_LIST && typeof(val) != TYPE_BOOL && typeof(val) != TYPE_INT && typeof(val) != TYPE_FLOAT)
          tool_args[key] = this:_coerce_string(val);
        endif
      endfor
    else
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> "ERROR: Tool arguments must be a JSON object."];
    endif
    "Handle built-in RLM tools first";
    if (tool_name == "moo_eval")
      result = this:_builtin_eval(tool_args);
    elseif (tool_name == "spawn_agent")
      result = this:_builtin_spawn(tool_args);
    elseif (tool_name == "report_finding")
      result = this:_builtin_report(tool_args);
    elseif (tool_name == "think")
      result = this:_builtin_think(tool_args);
    else
      "Try registered tools";
      tool = this:_find_tool(tool_name);
      if (tool == #-1)
        result = "ERROR: Unknown tool: " + tool_name;
      elseif (typeof(tool) == TYPE_FLYWEIGHT)
        try
          result = tool:execute(tool_args, this.actor);
        except e (ANY)
          result = "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
        endtry
      elseif (typeof(tool) == TYPE_MAP && maphaskey(tool, "target_verb"))
        try
          set_task_perms(this.actor);
          target = tool["target_obj"];
          verb = tool["target_verb"];
          result = target:(verb)(tool_args, this.actor);
        except e (ANY)
          result = "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
        endtry
      else
        result = "ERROR: Invalid tool format for: " + tool_name;
      endif
    endif
    "Truncate large results";
    content_out = typeof(result) == TYPE_STR ? result | toliteral(result);
    max_len = 4000;
    if (length(content_out) > max_len)
      content_out = content_out[1..max_len] + "\n... [TRUNCATED]";
    endif
    return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> content_out];
  endverb

  verb initialize (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Called automatically on creation. Sets defaults.";
    pass();
    this.status = 'pending;
    this.result = 0;
    this.child_agents = {};
    this.context = {};
    this.tools = [];
  endverb

  verb _builtin_eval (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Execute MOO code with access to workspace. Returns truncated output.";
    caller == this || raise(E_PERM);
    {tool_args} = args;
    "Parse JSON if needed";
    if (typeof(tool_args) == TYPE_STR)
      try
        tool_args = parse_json(tool_args);
      except (ANY)
        tool_args = [];
      endtry
    endif
    code = tool_args["code"];
    typeof(code) != TYPE_STR && return "ERROR: code must be a string, got " + typeof(code);
    "Unwrap JSON-like structures that LLMs sometimes produce";
    "Handle [\"code\"] array format";
    if (length(code) > 4 && code[1] == "[" && code[2] == "\"")
      try
        unwrapped = parse_json(code);
        if (typeof(unwrapped) == TYPE_LIST && length(unwrapped) == 1 && typeof(unwrapped[1]) == TYPE_STR)
          code = unwrapped[1];
        elseif (typeof(unwrapped) == TYPE_LIST)
          code = this:_coerce_string(unwrapped);
        endif
      except (ANY)
      endtry
    endif
    "Handle {\"key\": \"value\"} object format - extract string values";
    if (length(code) > 2 && code[1] == "{" && code[2] == "\"")
      try
        unwrapped = parse_json(code);
        if (typeof(unwrapped) == TYPE_MAP)
          code = this:_coerce_string(unwrapped);
        endif
      except (ANY)
      endtry
    endif
    "Strip trailing brackets from malformed output";
    code = code:trim();
    while (length(code) > 0 && code[length(code)] == "]")
      code = code[1..length(code) - 1]:trim();
    endwhile
    while (length(code) > 0 && code[length(code)] == "}")
      code = code[1..length(code) - 1]:trim();
    endwhile
    "Check if code has return - if not and it's a simple expression, add return";
    has_return = index(code, "return ") > 0 || index(code, "return(") > 0;
    if (!has_return)
      trimmed = code:trim();
      if (length(trimmed) > 0 && trimmed[length(trimmed)] == ";")
        trimmed = trimmed[1..length(trimmed) - 1]:trim();
      endif
      "If no internal semicolons, it's likely a simple expression - wrap in return";
      if (index(trimmed, ";") == 0 && length(trimmed) > 0)
        code = "return " + trimmed + ";";
      endif
    endif
    "Final sanity check - if code is empty or garbage, report it";
    if (length(code:trim()) == 0)
      return "ERROR: Empty code after cleanup. Original input was malformed.";
    endif
    "Inject agent reference and actor";
    injected_code = "agent = " + toliteral(this) + "; actor = " + toliteral(this.actor) + "; " + code;
    try
      set_task_perms(this.actor);
      if (this.actor.wizard)
        server_log("AGENT EVAL (WIZARD): " + code);
      endif
      result = eval(injected_code);
      if (!result[1])
        err = result[2];
        if (typeof(err) == TYPE_MAP && maphaskey(err, "message"))
          msg = "ERROR: " + err["message"] + (maphaskey(err, "line") ? " at line " + tostr(err["line"]) | "");
          if (index(msg, "expected an operator") || index(msg, "expected an expression"))
            msg = msg + " (HINT: Check syntax - MOO uses {1,2,3} for lists, not [1,2,3])";
          endif
          return msg;
        endif
        return "ERROR: " + toliteral(err);
      endif
      output = toliteral(result[2]);
      if (length(output) > 4000)
        output = output[1..4000] + "\n... [TRUNCATED]";
      endif
      return output;
    except e (ANY)
      return "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
    endtry
  endverb

  verb _builtin_spawn (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Spawn a child agent with a sub-query and workspace subset.";
    caller == this || raise(E_PERM);
    {tool_args} = args;
    "Parse JSON if needed";
    if (typeof(tool_args) == TYPE_STR)
      tool_args = parse_json(tool_args);
    endif
    sub_query = tool_args["query"];
    typeof(sub_query) != TYPE_STR && return "ERROR: query must be a string";
    "Check depth limit";
    if (this.depth >= this.max_depth)
      return "ERROR: Maximum recursion depth (" + tostr(this.max_depth) + ") reached. Cannot spawn more agents.";
    endif
    "Announce spawn via callback";
    cb = this.progress_callback;
    if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
      short_query = length(sub_query) > 60 ? sub_query[1..60] + "..." | sub_query;
      `cb[1]:_announce("Spawning child agent: \"" + short_query + "\"") ! ANY';
    endif
    "Get workspace for child - either explicit or empty";
    child_workspace = [];
    if (maphaskey(tool_args, "workspace"))
      ws = tool_args["workspace"];
      "Parse if it's a JSON string";
      if (typeof(ws) == TYPE_STR)
        child_workspace = `parse_json(ws) ! ANY => []';
      elseif (typeof(ws) == TYPE_MAP)
        child_workspace = ws;
      endif
    endif
    "Create anonymous child agent - garbage collected when parent completes";
    set_task_perms(this.actor);
    child = $rlm_agent:create(true);
    child:set_owner(this.actor);
    child.client = this.client;
    child.max_depth = this.max_depth;
    child.max_iterations = this.max_iterations;
    child.progress_callback = this.progress_callback;
    "Copy registered tools to child";
    for tool_name in (mapkeys(this.tools))
      child:add_tool(tool_name, this.tools[tool_name]);
    endfor
    "Setup and run child with workspace";
    child:setup(sub_query, this.actor, this, this.depth + 1, child_workspace);
    this.child_agents = {@this.child_agents, child};
    result = child:run();
    "Announce completion";
    if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
      `cb[1]:_announce("Child agent completed (depth " + tostr(this.depth + 1) + ")") ! ANY';
    endif
    "Return child's result";
    return "Child agent (depth " + tostr(this.depth + 1) + ") completed.\nResult: " + (typeof(result) == TYPE_STR ? result | toliteral(result));
  endverb

  verb _builtin_report (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Record a finding or report final answer.";
    caller == this || raise(E_PERM);
    {tool_args} = args;
    "Parse JSON if needed";
    if (typeof(tool_args) == TYPE_STR)
      try
        tool_args = parse_json(tool_args);
      except (ANY)
        tool_args = [];
      endtry
    endif
    subject = tool_args["subject"];
    content = tool_args["content"];
    is_final = maphaskey(tool_args, "final") && tool_args["final"];
    "Identify and resolve any mangled structures in content";
    content = this:_coerce_string(content);
    "Validate and coerce subject";
    if (typeof(subject) != TYPE_STR)
      subject = typeof(subject) == TYPE_MAP || typeof(subject) == TYPE_LIST ? toliteral(subject) | tostr(subject);
    endif
    "Store finding in shared knowledge base";
    if (valid(this.findings))
      this.findings:assert({this.depth, subject, content});
    endif
    "Notify actor's location if it has _announce (like $agent_room)";
    if (valid(this.actor) && valid(this.actor.location))
      loc = this.actor.location;
      has_announce = false;
      try
        verb_info(loc, "_announce");
        has_announce = true;
      except (ANY)
      endtry
      if (has_announce)
        "If it's final, we let the Room handle the wrap-up announcement";
        "unless we aren't being tracked by a specialized room.";
        if (!is_final)
          preview = content[1..min(1000, length(content))];
          if (length(content) > 1000)
            preview = preview + "...";
          endif
          loc:_announce("Finding [" + subject + "] " + preview);
        endif
      endif
    endif
    "If final answer, set result and mark complete";
    if (is_final)
      this.result = content;
      this.status = 'complete;
      return "Final answer recorded. Agent will terminate.";
    endif
    return "Finding recorded: " + subject;
  endverb

  verb _get_builtin_schemas (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Return OpenAI-format schemas for the builtin RLM tools.";
    caller == this || raise(E_PERM);
    eval_schema = ["type" -> "function", "function" -> ["name" -> "moo_eval", "description" -> "Execute a MOO program to query state or calculate values. IMPORTANT: You MUST use 'return <expression>;' if you want to see a result. This tool takes full statements, not just a single expression.", "parameters" -> ["type" -> "object", "properties" -> ["code" -> ["type" -> "string", "description" -> "MOO code block. Variable 'agent' refers to you. Access workspace via 'agent.workspace'. MUST include 'return' to get data back. Example: 'return ctime();' or 'return verbs(#123);'"], "rationale" -> ["type" -> "string", "description" -> "What you're trying to learn from this query."]], "required" -> {"code", "rationale"}]]];
    spawn_schema = ["type" -> "function", "function" -> ["name" -> "spawn_agent", "description" -> "Spawn a child agent with a focused sub-task and a subset of context. The child's workspace becomes its context to query. Child runs to completion and returns its result.", "parameters" -> ["type" -> "object", "properties" -> ["query" -> ["type" -> "string", "description" -> "The sub-task for the child. Be specific about what you need answered."], "workspace" -> ["type" -> "object", "description" -> "Context for the child - typically a partition or filtered subset."]], "required" -> {"query"}]]];
    report_schema = ["type" -> "function", "function" -> ["name" -> "report_finding", "description" -> "Record a finding or report your final answer. Findings persist in a shared knowledge base. Use final=true when done.", "parameters" -> ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "Category of finding (e.g., 'summary', 'issue', 'pattern')."], "content" -> ["type" -> "string", "description" -> "The finding or answer."], "final" -> ["type" -> "boolean", "description" -> "True if this is your complete answer. Agent terminates after."]], "required" -> {"subject", "content"}]]];
    think_schema = ["type" -> "function", "function" -> ["name" -> "think", "description" -> "Share your current thinking or status with the user. Use this to explain what you're doing, why, or what you've learned. Helps the user follow your progress.", "parameters" -> ["type" -> "object", "properties" -> ["thought" -> ["type" -> "string", "description" -> "Your current thinking, plan, or status update."]], "required" -> {"thought"}]]];
    return {eval_schema, spawn_schema, report_schema, think_schema};
  endverb

  verb run (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Main agent loop. Execute until complete or max iterations.";
    !valid(this.client) && raise(E_INVARG, "No LLM client configured");
    this.status = 'running;
    this.iteration = 0;
    this.last_tool = "";
    tool_schemas = {@this:_get_builtin_schemas(), @this:_get_tool_schemas()};
    wrap_up_at = toint(this.max_iterations * 0.8);
    for iteration in [1..this.max_iterations]
      this.iteration = iteration;
      if (this.status == 'complete)
        break;
      endif
      cb = this.progress_callback;
      if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
        `cb[1]:((cb[2]))(this, iteration, this.last_tool) ! ANY';
      endif
      if (iteration == wrap_up_at)
        reminder = ["role" -> "system", "content" -> "SYSTEM REMINDER: You are at iteration " + tostr(iteration) + " of " + tostr(this.max_iterations) + ". Please wrap up soon. Use report_finding with final=true when done."];
        this.context = {@this.context, reminder};
      endif
      if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
        `cb[1]:_announce_status("Thinking...") ! ANY';
      endif
      response = this:_call_llm(tool_schemas);
      if (!response:is_valid())
        this.status = 'failed;
        this.result = "LLM returned invalid response";
        return this.result;
      endif
      reasoning = response:reasoning();
      if (reasoning && length(reasoning) > 0 && typeof(cb) == TYPE_LIST && length(cb) >= 2)
        "Let _announce_thinking handle truncation after processing";
        `cb[1]:_announce_thinking(reasoning) ! ANY';
      elseif ((thinking = response:content()) && length(thinking) > 0 && typeof(cb) == TYPE_LIST && length(cb) >= 2)
        "Let _announce_thinking handle truncation after stripping DSML";
        `cb[1]:_announce_thinking(thinking) ! ANY';
      endif
      "Get tool calls - either from response or parsed from DSML in content";
      tool_calls_to_process = response:tool_calls();
      used_dsml = false;
      if (!response:has_tool_calls())
        "Check for DSML markup in content (DeepSeek compatibility)";
        content = response:content() || "";
        dsml_tool_calls = this:_parse_dsml_tool_calls(content);
        if (length(dsml_tool_calls) > 0)
          "Found DSML tool calls - use those instead";
          if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
            `cb[1]:_announce_status("Parsed " + tostr(length(dsml_tool_calls)) + " tool call(s) from DSML") ! ANY';
          endif
          tool_calls_to_process = dsml_tool_calls;
          used_dsml = true;
        else
          "No tool calls and no DSML - nudge the model";
          this.context = {@this.context, response:message()};
          nudge = ["role" -> "system", "content" -> "SYSTEM: You responded with text but didn't call any tools. If you're done, call report_finding with final=true. If not, continue using tools to complete the task."];
          this.context = {@this.context, nudge};
          suspend(0);
          continue;
        endif
      endif
      tool_results = {};
      for tool_call in (tool_calls_to_process)
        tool_name = tool_call["function"]["name"];
        this.last_tool = tool_name;
        tool_result_map = this:_execute_tool_call(tool_call);
        tool_results = {@tool_results, tool_result_map};
        cleaned_args = typeof(tool_call["function"]["arguments"]) == TYPE_STR ? `parse_json(tool_call["function"]["arguments"]) ! ANY => []' | tool_call["function"]["arguments"];
        if (typeof(cleaned_args) == TYPE_MAP)
          for key in (mapkeys(cleaned_args))
            cleaned_args[key] = this:_resolve_citations(cleaned_args[key])['content];
          endfor
        endif
        status_msg = tool_name;
        if (tool_name == "moo_eval" && typeof(cleaned_args) == TYPE_MAP && maphaskey(cleaned_args, "code"))
          expr = cleaned_args["code"];
          if (length(expr) > 60)
            expr = expr[1..60] + "...";
          endif
          status_msg = "moo_eval: " + expr;
        elseif (typeof(cleaned_args) == TYPE_MAP && maphaskey(cleaned_args, "object"))
          status_msg = tool_name + ": " + cleaned_args["object"];
        elseif (typeof(cleaned_args) == TYPE_MAP && maphaskey(cleaned_args, "target"))
          status_msg = tool_name + ": " + cleaned_args["target"];
        elseif (typeof(cleaned_args) == TYPE_MAP && maphaskey(cleaned_args, "topic"))
          status_msg = tool_name + ": " + cleaned_args["topic"];
        elseif (typeof(cleaned_args) == TYPE_MAP && maphaskey(cleaned_args, "name"))
          status_msg = tool_name + ": " + cleaned_args["name"];
        endif
        if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
          `cb[1]:_announce_status(status_msg) ! ANY';
        endif
        if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
          res_content = tool_result_map["content"];
          if (index(res_content, "ERROR") == 1)
            `cb[1]:_announce_status("  \u2192 " + res_content) ! ANY';
          elseif (tool_name == "moo_eval")
            "Special case for eval: show result preview";
            brief = res_content;
            if (length(brief) > 500)
              brief = brief[1..500] + "...";
            endif
            `cb[1]:_announce_status("  \u2192 " + brief) ! ANY';
          elseif (tool_name != "think" && tool_name != "report_finding" && tool_name != "show_verb" && tool_name != "program_verb" && length(res_content) > 0 && length(res_content) < 200)
            `cb[1]:_announce_status("  \u2192 " + res_content) ! ANY';
          endif
        endif
        if (this.status == 'complete)
          break;
        endif
      endfor
      "Build assistant message - synthetic if we parsed DSML";
      if (used_dsml)
        "Construct proper assistant message with tool_calls for API compatibility";
        assistant_msg = ["role" -> "assistant", "tool_calls" -> tool_calls_to_process];
      else
        assistant_msg = response:message();
      endif
      this.context = {@this.context, assistant_msg, @tool_results};
      suspend(0);
    endfor
    if (this.status != 'complete)
      this.status = 'failed;
      findings = valid(this.findings) ? this.findings:query({}) | {};
      if (length(findings) > 0)
        this.result = "Max iterations reached. Partial findings:\n";
        for f in (findings)
          this.result = this.result + "- " + tostr(f[2]) + ": " + tostr(f[3]) + "\n";
        endfor
      else
        this.result = "Max iterations (" + tostr(this.max_iterations) + ") reached without completing";
      endif
    endif
    return this.result;
  endverb

  verb ask (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Convenience: create an agent, run it, and return the result.";
    "Usage: $rlm_agent:ask(query, actor, client)";
    "Agent is anonymous - garbage collected after use.";
    {query, actor, client} = args;
    set_task_perms(actor);
    agent = $rlm_agent:create(true);
    agent:set_owner(actor);
    agent.client = client;
    agent:setup(query, actor);
    return agent:run();
  endverb

  verb get_findings (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Get all findings from this agent's knowledge base.";
    !valid(this.findings) && return {};
    return this.findings:tuples();
  endverb

  verb setup (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Set up an RLM agent instance with query, actor, and optional initial context.";
    {query, actor, ?parent = #-1, ?depth = 0, ?initial_workspace = []} = args;
    this.query = query;
    this.actor = actor;
    this.parent_agent = parent;
    this.depth = depth;
    this.status = 'pending;
    this.result = 0;
    this.child_agents = {};
    this.workspace = initial_workspace;
    "Create findings relation for this subtree (or inherit from parent)";
    "Uses anonymous object - garbage collected with the agent";
    if (valid(parent) && valid(parent.findings))
      this.findings = parent.findings;
    else
      set_task_perms(actor);
      this.findings = $relation:create(true);
    endif
    "Build system prompt";
    guide = this:_get_guide();
    prompt = "You are a MOO Building Agent. You create objects and write MOO code.\n\nTASK: " + query + "\n\n## \u26A0\uFE0F CRITICAL: TOOL ARGUMENTS\n- Pass 'object' and 'verb' as separate parameters.\n- DO NOT prefix arguments with colons or protocol tokens. Example: object=\"$room\" (Correct) vs object=\":$room\" or object=\"functions.help_lookup\" (Incorrect).\n- DO NOT leak internal thought tokens like <|thought|> or <|tool_call_begin|> into tool parameters.\n- All code and text parameters MUST be simple, clean strings.\n\n## \u26A0\uFE0F CRITICAL: moo_eval syntax\n- **moo_eval** executes a full program body.\n- You **MUST** use the `return` keyword to see any data. Example: `return ctime();` (Correct) vs `ctime();` (Incorrect).\n- Always end statements with semicolons.\n\n## 🛠\uFE0F Tool Usage\n- **create_object(parent, name)**: Creates a new object.\n- **program_verb(object, verb, code)**: Sets code. 'code' must be a SINGLE STRING with \\n for newlines.\n- **add_verb(object, verb, ...)**: Adds a new verb.\n\n## 💡 Strategy\n1. Share your plan via **think**.\n2. Research the world using **moo_eval** (with return!) and **doc_lookup**.\n3. ACTUALLY BUILD IT - don't just report what you would do.\n\n" + guide;
    this.system_prompt = prompt;
    this.context = {["role" -> "system", "content" -> this.system_prompt]};
    return this;
  endverb

  verb test_eval_this (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Test what 'this' refers to inside eval";
    direct_this = this;
    eval_result = eval("return this;");
    return ['direct_this -> direct_this, 'eval_this -> eval_result[2]];
  endverb

  verb load_external_tools (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Load tools from #0:external_agent_tools() into this agent.";
    "Optional filter list to load only specific tools.";
    {?filter = {}} = args;
    external_tools = $external_agent_tools();
    for tool in (external_tools)
      tool_name = tool["name"];
      "Skip if filter provided and tool not in filter";
      if (length(filter) > 0 && !(tool_name in filter))
        continue;
      endif
      "Store the tool map directly - execution will handle it";
      this.tools[tool_name] = tool;
    endfor
    return mapkeys(this.tools);
  endverb

  verb _builtin_think (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Share thinking/status with the user via progress callback.";
    {tool_args} = args;
    "Handle malformed args - LLM sometimes sends weird map structures";
    thought = "";
    if (typeof(tool_args) == TYPE_MAP)
      if (maphaskey(tool_args, "thought"))
        thought = tool_args["thought"];
      else
        "No 'thought' key - extract any string values";
        for key in (mapkeys(tool_args))
          val = tool_args[key];
          if (typeof(val) == TYPE_STR && length(val) > length(thought))
            thought = val;
          endif
        endfor
      endif
    elseif (typeof(tool_args) == TYPE_STR)
      thought = tool_args;
    endif
    "Ensure thought is a string";
    if (typeof(thought) != TYPE_STR)
      thought = tostr(thought);
    endif
    !thought || length(thought) == 0 && return "Please provide a thought to share.";
    "Announce via callback if available";
    cb = this.progress_callback;
    if (typeof(cb) == TYPE_LIST && length(cb) >= 2)
      `cb[1]:_announce_thinking(thought) ! ANY';
    endif
    return "Shared: " + thought[1..min(50, length(thought))] + (length(thought) > 50 ? "..." | "");
  endverb

  verb _get_guide (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Return MOO programming guide for agents.";
    return "## MOO Programming Guide\n\n### Syntax Basics\n- **1-indexed**: Lists and strings start at index 1, not 0\n- **Lists**: `{ 1, 2, 3 }` (curly braces, NOT square brackets)\n- **Maps**: `[ \"key\" -> value, \"other\" -> 123 ]` (square brackets with ->)\n- **Comments**: Use string literals: `\"This is a comment\";`\n\n### Verb Types and Argspecs (CRITICAL)\n\n**Command verbs** - typed by players (e.g., 'tap wristwatch')\n- Flags: `rd` (NO x flag - x is for methods only)\n- Argspec determines how command parses: `dobj prep iobj`\n\n**Method verbs** - called programmatically (e.g., `obj:method()`)\n- Flags: `rxd` (x = executable from code)\n- Argspec: `this none this`\n\n**Common command argspecs:**\n- `this none none` = 'verb <this object>' (tap wristwatch, wear hat)\n- `any none none` = 'verb <anything>' (look thing)\n- `none none none` = 'verb' with no object (look, inventory)\n- `this with/using any` = 'verb <this> with <something>' (unlock door with key)\n- `any in/inside this` = 'put <thing> in <this>' (put coin in box)\n\nExample: 'tap wristwatch' needs argspec `this none none`:\n- dobj=this (the wristwatch is the direct object)\n- prep=none (no preposition)\n- iobj=none (no indirect object)\n\n### Event System (CRITICAL)\n**Never call notify() directly.**\n\n1. **:inform_current(event)** - Command responses (ephemeral)\n   ```\n   player:inform_current($event:mk_info(player, \"The watch shows: \" + ctime()));\n   ```\n\n2. **:tell(event)** - World events (persistent, all connections)\n\n3. **Room announcements** - Use $event:mk_emote for third-person actions:\n   ```\n   event = $event:mk_emote(player, @this.tap_msg):with_dobj(this);\n   player.location:announce(event);\n   ```\n\n### Message Properties (IMPORTANT PATTERN)\nStore messages on `*_msg` properties, NOT inline in code.\n\n**Add the property with template:**\n```\nthis.tap_msg = $sub_utils:compile(\"{nc} {tap|taps} the watch face.\");\n```\n\n**In the verb - use the property:**\n```\nevent = $event:mk_emote(player, @this.tap_msg):with_dobj(this);\nplayer.location:announce(event);\n```\n\n### $sub_utils Tokens\n- `{n}/{nc}` - Actor name (cap)\n- `{d}/{dc}` - Direct object\n- `{the d}` - Article + dobj\n- `{tap|taps}` - Self-alternation (first for actor, second for others)\n- `{p}` - Possessive pronoun (his/her/their)\n\n### Complete Command Verb Example\nVerb 'tap' on a wristwatch - argspec: `this none none`, flags: `rd`\n```\n\"Tap the watch to check time.\";\nevent = $event:mk_emote(player, @this.tap_msg):with_dobj(this);\nplayer.location:announce(event);\nplayer:inform_current($event:mk_info(player, \"The display shows: \" + ctime()));\n```\n";
  endverb

  verb _coerce_string (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Aggressively convert mangled model output into a single string.";
    {val} = args;
    if (typeof(val) == TYPE_STR)
      "Clean up hallucinated internal protocol tokens common in some model outputs (Kimi 2.5, DeepSeek)";
      patterns = {"<|tool_call_begin|>", "<|tool_call_end|>", "<|tool_call_argument_begin|>", "<|tool_calls_section_begin|>", "<|tool_calls_section_end|>", "<|DSML|", "<\uFF5CDSML\uFF5C", "functions.", ">functions.", "</thought>", "<|thought|>", "_of_thought"};
      for p in (patterns)
        while (idx = index(val, p))
          if (p[1] == "<" || p[1] == ">")
            end_idx = index(val[idx..$], ">") || index(val[idx..$], " ");
            if (end_idx)
              val = val[1..idx - 1] + val[idx + end_idx..$];
            else
              val = val[1..idx - 1] + val[idx + length(p)..$];
            endif
          else
            val = val[1..idx - 1] + val[idx + length(p)..$];
          endif
        endwhile
      endfor
      "Strip remaining punctuation garbage at start";
      while (length(val) > 0 && index(" {\"\":>])}", val[1]))
        val = val[2..$];
      endwhile
      return val:trim();
    elseif (typeof(val) == TYPE_LIST)
      if (length(val) == 1)
        return this:_coerce_string(val[1]);
      endif
      parts = {};
      for item in (val)
        coerced = this:_coerce_string(item);
        if (length(coerced) > 0)
          parts = {@parts, coerced};
        endif
      endfor
      return parts:join(" ");
    elseif (typeof(val) == TYPE_MAP)
      result = "";
      for key in (mapkeys(val))
        key_str = typeof(key) == TYPE_STR ? key | tostr(key);
        key_str = this:_coerce_string(key_str);
        v = val[key];
        val_str = typeof(v) == TYPE_STR ? v | (typeof(v) == TYPE_INT || typeof(v) == TYPE_FLOAT ? tostr(v) | this:_coerce_string(v));
        result = result + key_str + val_str;
      endfor
      return result;
    endif
    return tostr(val);
  endverb

  verb _resolve_citations (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Resolve citation structures in LLM output to clean content.";
    "Returns map with 'content key containing the cleaned value.";
    {val} = args;
    "Simple types pass through";
    if (typeof(val) == TYPE_STR)
      return ['content -> val];
    elseif (typeof(val) == TYPE_INT || typeof(val) == TYPE_FLOAT)
      return ['content -> tostr(val)];
    elseif (typeof(val) == TYPE_OBJ)
      return ['content -> tostr(val)];
    endif
    "Use _coerce_string for complex types (maps, lists)";
    return ['content -> this:_coerce_string(val)];
  endverb

  verb _parse_dsml_tool_calls (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Parse DSML markup from DeepSeek and convert to tool_calls format.";
    "Returns list of tool call maps, or empty list if no DSML found.";
    {content} = args;
    !content && return {};
    "Check for DSML markers";
    dsml_marker = "<\uFF5CDSML\uFF5C";
    if (!index(content, dsml_marker))
      return {};
    endif
    tool_calls = {};
    "Find all invoke blocks";
    pos = 1;
    while (pos <= length(content))
      "Find next invoke";
      invoke_start = index(content[pos..length(content)], "<\uFF5CDSML\uFF5Cinvoke");
      if (!invoke_start)
        break;
      endif
      invoke_start = invoke_start + pos - 1;
      "Extract name attribute";
      name_start = index(content[invoke_start..length(content)], "name=\"");
      if (!name_start)
        break;
      endif
      name_start = name_start + invoke_start - 1 + 6;
      name_end = index(content[name_start..length(content)], "\"");
      if (!name_end)
        break;
      endif
      func_name = content[name_start..name_start + name_end - 2];
      "Find parameters for this invoke";
      params = [];
      "Find the end of this invoke block (next invoke or end of function_calls)";
      next_invoke = index(content[invoke_start + 10..length(content)], "<\uFF5CDSML\uFF5Cinvoke");
      end_calls = index(content[invoke_start..length(content)], "</\uFF5CDSML\uFF5Cfunction_calls>");
      if (next_invoke)
        block_end = invoke_start + 10 + next_invoke - 2;
      elseif (end_calls)
        block_end = invoke_start + end_calls - 2;
      else
        block_end = length(content);
      endif
      "Extract parameters within this invoke block";
      param_search_pos = invoke_start;
      while (param_search_pos < block_end)
        param_start = index(content[param_search_pos..block_end], "<\uFF5CDSML\uFF5Cparameter");
        if (!param_start)
          break;
        endif
        param_start = param_start + param_search_pos - 1;
        "Extract parameter name";
        pname_start = index(content[param_start..block_end], "name=\"");
        if (!pname_start)
          break;
        endif
        pname_start = pname_start + param_start - 1 + 6;
        pname_end = index(content[pname_start..block_end], "\"");
        if (!pname_end)
          break;
        endif
        param_name = content[pname_start..pname_start + pname_end - 2];
        "Find the end of this parameter tag";
        tag_close = index(content[pname_start..block_end], ">");
        if (!tag_close)
          break;
        endif
        value_start = pname_start + tag_close;
        "Find the end of parameter value (next parameter or end of block)";
        next_param = index(content[value_start..block_end], "<\uFF5CDSML\uFF5Cparameter");
        end_param = index(content[value_start..block_end], "</\uFF5CDSML\uFF5Cparameter>");
        if (end_param && (!next_param || end_param < next_param))
          value_end = value_start + end_param - 2;
        elseif (next_param)
          value_end = value_start + next_param - 2;
        else
          value_end = block_end;
        endif
        param_value = content[value_start..value_end];
        "Trim whitespace";
        while (length(param_value) > 0 && param_value[1] == " ")
          param_value = param_value[2..length(param_value)];
        endwhile
        while (length(param_value) > 0 && param_value[length(param_value)] == " ")
          param_value = param_value[1..length(param_value) - 1];
        endwhile
        params[param_name] = param_value;
        param_search_pos = value_end + 1;
      endwhile
      "Create tool call entry with STRING keys to match OpenAI format";
      tool_call = ["id" -> tostr(random()), "type" -> "function", "function" -> ["name" -> func_name, "arguments" -> generate_json(params)]];
      tool_calls = {@tool_calls, tool_call};
      pos = block_end + 1;
    endwhile
    return tool_calls;
  endverb
endobject