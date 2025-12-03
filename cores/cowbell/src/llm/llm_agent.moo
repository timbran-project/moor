object LLM_AGENT
  name: "LLM Agent"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property cancel_requested (owner: HACKER, flags: "rc") = false;
  property chat_opts (owner: ARCH_WIZARD, flags: "rc") = false;
  property client (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property compaction_callback (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property compaction_threshold (owner: ARCH_WIZARD, flags: "r") = 0.7;
  property consecutive_tool_failures (owner: ARCH_WIZARD, flags: "rc") = [];
  property all_failed_iterations (owner: ARCH_WIZARD, flags: "rc") = 0;
  property context (owner: ARCH_WIZARD, flags: "c") = {};
  property current_continuation (owner: ARCH_WIZARD, flags: "rc") = 0;
  property current_iteration (owner: ARCH_WIZARD, flags: "rc") = 0;
  property current_tasks (owner: ARCH_WIZARD, flags: "rc") = [];
  property knowledge_base (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property last_token_usage (owner: ARCH_WIZARD, flags: "c") = [];
  property max_consecutive_failures (owner: ARCH_WIZARD, flags: "r") = 3;
  property max_iterations (owner: ARCH_WIZARD, flags: "r") = 50;
  property min_messages_to_keep (owner: ARCH_WIZARD, flags: "c") = 15;
  property next_task_id (owner: ARCH_WIZARD, flags: "rc") = 1;
  property next_todo_id (owner: ARCH_WIZARD, flags: "rc") = 1;
  property system_prompt (owner: ARCH_WIZARD, flags: "rc") = "";
  property todos (owner: ARCH_WIZARD, flags: "rc") = {};
  property token_limit (owner: ARCH_WIZARD, flags: "r") = 128000;
  property token_owner (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property tool_callback (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property tools (owner: ARCH_WIZARD, flags: "c") = [];
  property total_tokens_used (owner: ARCH_WIZARD, flags: "rc") = 0;

  override description = "Prototype for LLM-powered agents. Maintains conversation context and executes tool calls.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_agent";

  verb initialize (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called automatically on creation. Creates anonymous client.";
    this.client = $llm_client:create(true);
  endverb

  verb log_tool_error (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Log tool execution errors to server_log. Accessible internally by agent calls.";
    {tool_name, tool_args, error_msg} = args;
    caller == this || caller_perms().wizard || raise(E_PERM);
    "Do not downgrade perms; server_log requires wizard perms.";
    safe_args = typeof(tool_args) == STR ? tool_args | toliteral(tool_args);
    server_log("LLM tool error [" + toliteral(tool_name) + "]: " + toliteral(error_msg) + " args=" + toliteral(safe_args));
    return true;
  endverb

  verb add_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register a tool for this agent to use";
    this:_challenge_permissions(caller);
    {tool_name, tool_flyweight} = args;
    typeof(tool_name) != STR && raise(E_TYPE);
    typeof(tool_flyweight) != FLYWEIGHT && raise(E_TYPE);
    tools = this.tools;
    tools[tool_name] = tool_flyweight;
    this.tools = tools;
  endverb

  verb remove_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Unregister a tool";
    this:_challenge_permissions(caller);
    {tool_name} = args;
    this.tools = mapdelete(this.tools, tool_name);
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
    return { this.tools[k]:to_schema() for k in (mapkeys(this.tools)) };
  endverb

  verb _find_tool (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find a registered tool by name. Returns flyweight or #-1 if not found.";
    this:_challenge_permissions(caller);
    {tool_name} = args;
    maphaskey(this.tools, tool_name) && return this.tools[tool_name];
    return #-1;
  endverb

  verb _call_llm_with_retry (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Call LLM API with retry logic. Returns response map.";
    "Optional second arg: opts flyweight to override this.chat_opts";
    caller == this || raise(E_PERM);
    {tool_schemas, ?opts = false} = args;
    opts = opts || this.chat_opts;
    max_retries = 3;
    for retry_count in [0..max_retries]
      try
        response = this.client:chat(this.context, opts, false, false, tool_schemas);
        suspend(0);
        return response;
      except e (ANY)
        this:_log("ERROR: " + toliteral(e));
        retry_count >= max_retries && raise(E_INVARG, "LLM API call failed after retries: " + toliteral(e));
        suspend(retry_count + 1);
      endtry
    endfor
  endverb

  verb _track_token_usage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Track token usage from response and trigger compaction if needed.";
    caller == this || raise(E_PERM);
    {response} = args;
    !(typeof(response) == MAP && maphaskey(response, "usage")) && return;
    this.last_token_usage = response["usage"];
    if (maphaskey(response["usage"], "total_tokens"))
      tokens_this_call = response["usage"]["total_tokens"];
      this.total_tokens_used = this.total_tokens_used + tokens_this_call;
      this:_update_token_usage(this.token_owner, tokens_this_call);
    endif
    this:needs_compaction() && this:compact_context();
  endverb

  verb _execute_tool_call (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Execute a single tool call. Returns result map for context.";
    caller == this || raise(E_PERM);
    {tool_call} = args;
    tool_name = tool_call["function"]["name"];
    tool_args = tool_call["function"]["arguments"];
    tool_call_id = tool_call["id"];
    "Check if this tool has failed too many times consecutively";
    failures = typeof(this.consecutive_tool_failures) == MAP ? this.consecutive_tool_failures | [];
    tool_failure_count = maphaskey(failures, tool_name) ? failures[tool_name] | 0;
    if (tool_failure_count >= this.max_consecutive_failures)
      error_msg = "TOOL BLOCKED: This tool has failed " + tostr(tool_failure_count) + " times in a row. STOP trying to use it and move on. Do NOT retry.";
      this:log_tool_error(tool_name, tool_args, error_msg);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, error_msg) ! ANY';
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> error_msg];
    endif
    tool = this:_find_tool(tool_name);
    if (typeof(tool) != FLYWEIGHT)
      this:log_tool_error(tool_name, tool_args, "Tool not found");
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, "Tool not found") ! ANY';
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> "Error: tool not found"];
    endif
    try
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_call) && this.tool_callback:on_tool_call(tool_name, tool_args);
      result = tool:execute(tool_args);
      suspend(0);
      content_out = typeof(result) == STR ? result | toliteral(result);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_complete) && `this.tool_callback:on_tool_complete(tool_name, tool_args, content_out) ! ANY';
      "Check if result indicates an error (starts with ERROR:)";
      is_error_response = typeof(result) == STR && (result:starts_with("ERROR:") || result:starts_with("TOOL BLOCKED:"));
      if (is_error_response)
        "Increment failure count for error responses";
        failures[tool_name] = tool_failure_count + 1;
        this.consecutive_tool_failures = failures;
      elseif (tool_failure_count > 0)
        "Success - reset failure count for this tool";
        this.consecutive_tool_failures = mapdelete(failures, tool_name);
      endif
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> content_out];
    except e (ANY)
      error_msg = "ERROR: " + tostr(e[1]) + " - " + tostr(e[2]);
      length(e) > 2 && typeof(e[3]) == LIST && (error_msg = error_msg + "\nTraceback: " + toliteral(e[3]));
      this:log_tool_error(tool_name, tool_args, error_msg);
      valid(this.tool_callback) && respond_to(this.tool_callback, 'on_tool_error) && `this.tool_callback:on_tool_error(tool_name, tool_args, error_msg) ! ANY';
      "Increment failure count for this tool";
      failures[tool_name] = tool_failure_count + 1;
      this.consecutive_tool_failures = failures;
      return ["tool_call_id" -> tool_call_id, "role" -> "tool", "name" -> tool_name, "content" -> error_msg];
    endtry
  endverb

  verb send_message (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Main entry point: send a message and get response, executing tools as needed";
    "Optional second arg: opts flyweight to override this.chat_opts for this call";
    {user_input, ?opts = false} = args;
    this:_challenge_permissions(caller);
    this:add_message("user", user_input);
    this.cancel_requested = false;
    this.current_iteration = 0;
    for iteration in [1..this.max_iterations]
      this.current_iteration = iteration;
      if (this.cancel_requested)
        this.cancel_requested = false;
        this.current_iteration = 0;
        return "Operation cancelled by user.";
      endif
      budget_check = this:_check_token_budget(this.token_owner);
      typeof(budget_check) == STR && return budget_check;
      response = this:_call_llm_with_retry(this:_get_tool_schemas(), opts);
      this:_track_token_usage(response);
      "Check if response has tool calls";
      if (!(typeof(response) == MAP && maphaskey(response, "choices") && length(response["choices"]) > 0))
        this.current_iteration = 0;
        return tostr(response);
      endif
      message = response["choices"][1]["message"];
      "No tool calls = final response";
      if (!(maphaskey(message, "tool_calls") && message["tool_calls"]))
        this:add_message("assistant", message["content"]);
        this.current_iteration = 0;
        return message["content"];
      endif
      "Execute each tool call and track failures";
      tool_results = {};
      all_blocked = true;
      for tool_call in (message["tool_calls"])
        if (this.cancel_requested)
          this.cancel_requested = false;
          this.current_iteration = 0;
          this.context = {@this.context, message, @tool_results};
          return "Operation cancelled by user. " + tostr(length(tool_results)) + " of " + tostr(length(message["tool_calls"])) + " tools completed before cancellation.";
        endif
        result = this:_execute_tool_call(tool_call);
        tool_results = {@tool_results, result};
        "Check if this result was not a blocked/error response";
        content = result["content"];
        if (!(content:starts_with("TOOL BLOCKED:") || content:starts_with("ERROR:")))
          all_blocked = false;
        endif
      endfor
      this.context = {@this.context, message, @tool_results};
      "If all tools failed, add guidance and continue so LLM can adapt";
      if (all_blocked && length(tool_results) > 0)
        "Check if we've had too many consecutive all-failed iterations";
        all_failed_count = this.all_failed_iterations + 1;
        this.all_failed_iterations = all_failed_count;
        if (all_failed_count >= 3)
          this.current_iteration = 0;
          this.all_failed_iterations = 0;
          return "Agent stopped after 3 consecutive iterations where all tools failed. Last errors: " + tool_results[1]["content"];
        endif
        "Add system guidance to help LLM adapt";
        guidance = ["role" -> "system", "content" -> "All tool calls in the previous response failed. Review the error messages above and either: (1) try a different approach, (2) use the ask_user tool to request help, or (3) use the explain tool to tell the user what's blocking you."];
        this.context = {@this.context, guidance};
      else
        "Reset counter on any success";
        this.all_failed_iterations = 0;
      endif
      suspend(0);
    endfor
    return E_QUOTA("Maximum iterations exceeded");
  endverb

  verb reset_context (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clear context and rebuild from system prompt";
    this:_challenge_permissions(caller);
    this.context = this.system_prompt ? {["role" -> "system", "content" -> this.system_prompt]} | {};
    this.total_tokens_used = 0;
    this.consecutive_tool_failures = [];
    this.all_failed_iterations = 0;
  endverb

  verb needs_compaction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if context needs compaction based on token usage";
    this:_challenge_permissions(caller);
    typeof(this.last_token_usage) != MAP && return false;
    !maphaskey(this.last_token_usage, "prompt_tokens") && return false;
    return this.last_token_usage["prompt_tokens"] > this.token_limit * this.compaction_threshold;
  endverb

  verb compact_context (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Compact context by summarizing old messages and keeping recent ones";
    this:_challenge_permissions(caller);
    length(this.context) <= this.min_messages_to_keep + 1 && return;
    valid(this.compaction_callback) && respond_to(this.compaction_callback, 'on_compaction_start) && `this.compaction_callback:on_compaction_start() ! ANY';
    system_msg = this.context[1];
    old_messages = (this.context)[2..$ - this.min_messages_to_keep];
    recent_messages = (this.context)[$ - this.min_messages_to_keep + 1..$];
    summary_context = {system_msg, ["role" -> "user", "content" -> "Summarize the following conversation history in 3-4 concise sentences, preserving the most important information:\n\n" + toliteral(old_messages)]};
    try
      response = this.client:chat(summary_context, false, false, {});
      if (typeof(response) == MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
        summary = response["choices"][1]["message"]["content"];
        this.context = {system_msg, ["role" -> "assistant", "content" -> "Previous conversation summary: " + summary], @recent_messages};
        this:_log("LLM agent context compacted: " + tostr(length(old_messages)) + " messages summarized, " + tostr(length(recent_messages)) + " kept");
      else
        this.context = {system_msg, @recent_messages};
        this:_log("LLM agent context compacted: summary failed, using sliding window");
      endif
    except e (ANY)
      this.context = {system_msg, @recent_messages};
      this:_log("LLM agent context compaction error: " + toliteral(e));
    endtry
    valid(this.compaction_callback) && respond_to(this.compaction_callback, 'on_compaction_end) && `this.compaction_callback:on_compaction_end() ! ANY';
  endverb

  verb _challenge_permissions (this none this) owner: ARCH_WIZARD flags: "rxd"
    {who} = args;
    who == #-1 || who == this || who.owner == this.owner || who == this.owner || who.wizard || caller_perms().wizard || raise(E_PERM);
    return who;
  endverb

  verb _log (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Log message to server log. Runs with wizard perms regardless of agent owner.";
    {message} = args;
    server_log(message);
  endverb

  verb _check_token_budget (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if token owner is within budget. Returns true if okay, error string if exceeded.";
    caller == this || caller.wizard || raise(E_PERM);
    {player_obj} = args;
    !valid(player_obj) || !is_player(player_obj) && return true;
    budget = `player_obj.llm_token_budget ! ANY => 20000000';
    used = `player_obj.llm_tokens_used ! ANY => 0';
    used >= budget && return "Error: LLM token budget exceeded. You have used " + tostr(used) + " of " + tostr(budget) + " tokens. Contact a wizard to increase your budget.";
    return true;
  endverb

  verb _update_token_usage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Update player's token usage. Runs with wizard perms to write ARCH_WIZARD-owned properties.";
    caller == this || caller.wizard || raise(E_PERM);
    {player_obj, tokens_used} = args;
    !valid(player_obj) || !is_player(player_obj) && return;
    typeof(tokens_used) == INT || raise(E_INVARG, "tokens_used must be an integer");
    tokens_used >= 0 || raise(E_INVARG, "tokens_used cannot be negative");
    tokens_used <= 1000000 || raise(E_INVARG, "tokens_used suspiciously large");
    player_obj.llm_tokens_used = player_obj.llm_tokens_used + tokens_used;
    player_obj.llm_usage_log = {@player_obj.llm_usage_log, ["timestamp" -> time(), "tokens" -> tokens_used, "usage" -> this.last_token_usage]};
  endverb

  verb _ensure_knowledge_base (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Lazily create knowledge base if not already created.";
    !valid(this.knowledge_base) && (this.knowledge_base = create($relation, this.owner));
    return this.knowledge_base;
  endverb

  verb add_todo (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Add a todo item. Returns the new todo's id.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {content} = args;
    typeof(content) != STR && raise(E_TYPE, "content must be string");
    todo_id = this.next_todo_id;
    this.next_todo_id = todo_id + 1;
    this.todos = {@this.todos, ["id" -> todo_id, "content" -> content, "status" -> 'pending]};
    return todo_id;
  endverb

  verb update_todo (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Update a todo's status. Status must be 'pending, 'in_progress, or 'completed.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {todo_id, new_status} = args;
    typeof(todo_id) != INT && raise(E_TYPE, "todo_id must be integer");
    !(new_status in {'pending, 'in_progress, 'completed}) && raise(E_INVARG, "status must be 'pending, 'in_progress, or 'completed");
    updated = false;
    new_todos = {};
    for todo in (this.todos)
      if (todo["id"] == todo_id)
        new_todos = {@new_todos, ["id" -> todo["id"], "content" -> todo["content"], "status" -> new_status]};
        updated = true;
      else
        new_todos = {@new_todos, todo};
      endif
    endfor
    !updated && raise(E_INVARG, "todo not found: " + tostr(todo_id));
    this.todos = new_todos;
    return true;
  endverb

  verb remove_todo (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove a specific todo by id.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {todo_id} = args;
    typeof(todo_id) != INT && raise(E_TYPE, "todo_id must be integer");
    new_todos = {};
    found = false;
    for todo in (this.todos)
      if (todo["id"] == todo_id)
        found = true;
      else
        new_todos = {@new_todos, todo};
      endif
    endfor
    !found && return false;
    this.todos = new_todos;
    return true;
  endverb

  verb get_todos (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get all todos, optionally filtered by status.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {?status_filter = false} = args;
    !status_filter && return this.todos;
    filtered = {};
    for todo in (this.todos)
      todo["status"] == status_filter && (filtered = {@filtered, todo});
    endfor
    return filtered;
  endverb

  verb clear_completed_todos (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove all completed todos.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    new_todos = {};
    for todo in (this.todos)
      todo["status"] != 'completed && (new_todos = {@new_todos, todo});
    endfor
    this.todos = new_todos;
    return true;
  endverb

  verb set_todos (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Replace entire todo list. Each item must have content and status.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    {todo_list} = args;
    typeof(todo_list) != LIST && raise(E_TYPE, "todo_list must be a list");
    new_todos = {};
    for item in (todo_list)
      typeof(item) != MAP && raise(E_TYPE, "each todo must be a map");
      !maphaskey(item, "content") && raise(E_INVARG, "todo missing content");
      !maphaskey(item, "status") && raise(E_INVARG, "todo missing status");
      !(item["status"] in {'pending, 'in_progress, 'completed}) && raise(E_INVARG, "invalid status");
      todo_id = maphaskey(item, "id") ? item["id"] | this.next_todo_id;
      todo_id >= this.next_todo_id && (this.next_todo_id = todo_id + 1);
      new_todos = {@new_todos, ["id" -> todo_id, "content" -> item["content"], "status" -> item["status"]]};
    endfor
    this.todos = new_todos;
    return true;
  endverb

  verb format_todos (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format todos as human-readable string for display.";
    caller == this || caller_perms().wizard || caller_perms() == this.owner || raise(E_PERM);
    !this.todos && return "No todos.";
    lines = {};
    for todo in (this.todos)
      status_str = todo["status"] == 'completed ? "[x]" | (todo["status"] == 'in_progress ? "[>]" | "[ ]");
      lines = {@lines, status_str + " " + todo["content"]};
    endfor
    return lines:join("\n");
  endverb

  verb create_task (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a new task. If task_id not provided, auto-generates one. Returns task object.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {description, ?parent_task_id = 0} = args;
    typeof(description) != STR && raise(E_TYPE);
    task_id = this.next_task_id;
    this.next_task_id = task_id + 1;
    kb = this:_ensure_knowledge_base();
    task = create($llm_task, this.owner);
    task:mk(task_id, description, this, kb, parent_task_id);
    this.current_tasks[task_id] = task;
    return task;
  endverb

  verb remove_task (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove a task from tracking. Task object will be garbage collected if anonymous.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {task_id} = args;
    typeof(task_id) != INT && raise(E_TYPE);
    !maphaskey(this.current_tasks, task_id) && return false;
    this.current_tasks = mapdelete(this.current_tasks, task_id);
    return true;
  endverb

  verb get_task_status (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get status of all current tasks as a list of maps. For external reporting.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    task_statuses = {};
    for task_id in (mapkeys(this.current_tasks))
      task_obj = this.current_tasks[task_id];
      valid(task_obj) && (task_statuses = {@task_statuses, task_obj:get_status()});
    endfor
    return task_statuses;
  endverb

  verb cleanup_tasks (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Destroy all task objects and knowledge base. Called on agent destruction.";
    caller == this || caller_perms().wizard || raise(E_PERM);
    valid(this.knowledge_base) && this.knowledge_base:destroy() && (this.knowledge_base = #-1);
    this.current_tasks = {};
  endverb

  verb test_todo_lifecycle (this none this) owner: HACKER flags: "rxd"
    "Test basic todo operations.";
    agent = create($llm_agent);
    agent.owner = $hacker;
    "Add todos";
    id1 = agent:add_todo("First task");
    id2 = agent:add_todo("Second task");
    todos = agent:get_todos();
    length(todos) != 2 && raise(E_ASSERT, "Should have 2 todos");
    todos[1]["status"] != 'pending && raise(E_ASSERT, "New todo should be pending");
    "Update status";
    agent:update_todo(id1, 'in_progress);
    todos = agent:get_todos();
    todos[1]["status"] != 'in_progress && raise(E_ASSERT, "Should be in_progress");
    "Complete and clear";
    agent:update_todo(id1, 'completed);
    agent:clear_completed_todos();
    todos = agent:get_todos();
    length(todos) != 1 && raise(E_ASSERT, "Should have 1 todo after clear");
    todos[1]["id"] != id2 && raise(E_ASSERT, "Remaining todo should be id2");
    "Remove";
    agent:remove_todo(id2);
    todos = agent:get_todos();
    length(todos) != 0 && raise(E_ASSERT, "Should have 0 todos");
    agent:destroy();
    return true;
  endverb

  verb test_todo_filter (this none this) owner: HACKER flags: "rxd"
    "Test todo filtering by status.";
    agent = create($llm_agent);
    agent.owner = $hacker;
    agent:add_todo("Pending 1");
    id2 = agent:add_todo("In progress");
    agent:add_todo("Pending 2");
    agent:update_todo(id2, 'in_progress);
    pending = agent:get_todos('pending);
    length(pending) != 2 && raise(E_ASSERT, "Should have 2 pending");
    in_prog = agent:get_todos('in_progress);
    length(in_prog) != 1 && raise(E_ASSERT, "Should have 1 in_progress");
    agent:destroy();
    return true;
  endverb

  verb test_set_todos (this none this) owner: HACKER flags: "rxd"
    "Test replacing entire todo list.";
    agent = create($llm_agent);
    agent.owner = $hacker;
    agent:set_todos({["content" -> "Task A", "status" -> 'pending], ["content" -> "Task B", "status" -> 'in_progress], ["content" -> "Task C", "status" -> 'completed]});
    todos = agent:get_todos();
    length(todos) != 3 && raise(E_ASSERT, "Should have 3 todos");
    todos[2]["status"] != 'in_progress && raise(E_ASSERT, "Second should be in_progress");
    agent:destroy();
    return true;
  endverb

  verb reset_tool_failures (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Reset consecutive failure counts, optionally for a specific tool.";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    {?tool_name = ""} = args;
    if (tool_name == "")
      this.consecutive_tool_failures = [];
    else
      failures = this.consecutive_tool_failures;
      if (maphaskey(failures, tool_name))
        this.consecutive_tool_failures = mapdelete(failures, tool_name);
      endif
    endif
  endverb
endobject