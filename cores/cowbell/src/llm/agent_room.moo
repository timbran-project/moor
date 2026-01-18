object AGENT_ROOM
  name: "Generic Agent Room"
  parent: ROOM
  owner: ARCH_WIZARD
  readable: true

  property active_tasks (owner: ARCH_WIZARD, flags: "rc") = {};
  property agent (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property current_task (owner: ARCH_WIZARD, flags: "rc") = "";
  property history (owner: ARCH_WIZARD, flags: "rc") = {};
  property llm_client (owner: ARCH_WIZARD, flags: "rc") = #-1;
  property task_id (owner: ARCH_WIZARD, flags: "rc") = 0;
  property task_queue (owner: ARCH_WIZARD, flags: "rc") = {};
  property task_requester (owner: ARCH_WIZARD, flags: "rc") = #-1;

  override description = "A virtual workspace for agent interaction.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "agent_room";

  verb do (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Catch-all command verb - queues natural language commands for the agent.";
    "Usage: do <anything> - queues the command for agent processing";
    command_text = argstr;
    if (!command_text)
      player:inform_current($event:mk_info(player, "What would you like me to do?"));
      return;
    endif
    "Queue the task";
    task = ['query -> command_text, 'player -> player, 'queued_at -> time()];
    this.task_queue = {@this.task_queue, task};
    player:inform_current($event:mk_info(player, "Queued: \"" + command_text + "\""));
    "Check if processor is running";
    all_tasks = queued_tasks();
    is_running = false;
    for t in (all_tasks)
      if (t[1] == this.task_id)
        is_running = true;
        break;
      endif
    endfor
    if (!is_running)
      this:_start_processing();
    endif
  endverb

  verb _start_processing (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Fork a background task to process the queue in parallel.";
    caller == this || raise(E_PERM);
    "Prevent multiple processor loops - check if already starting";
    if (this.task_id != 0)
      "Check if the task is actually still running";
      all_tasks = queued_tasks();
      for t in (all_tasks)
        if (t[1] == this.task_id)
          return;
        endif
      endfor
      "Task died, clear it";
      this.task_id = 0;
    endif
    fork tid (0)
      try
        while (true)
          "Clean up active_tasks - check which ones are still running";
          all_tasks = queued_tasks();
          live_tids = {};
          for t in (all_tasks)
            live_tids = {@live_tids, t[1]};
          endfor
          new_active = {};
          for atid in (this.active_tasks)
            if (atid in live_tids)
              new_active = {@new_active, atid};
            endif
          endfor
          this.active_tasks = new_active;
          "Check for tasks in queue";
          if (length(this.task_queue) == 0)
            if (length(this.active_tasks) == 0)
              "Nothing left to do";
              break;
            endif
            suspend(2);
            continue;
          endif
          "Check concurrency limit (max 3 for safety)";
          if (length(this.active_tasks) >= 3)
            suspend(2);
            continue;
          endif
          "Pop next task atomically - destructure and update in tight sequence";
          queue = this.task_queue;
          if (length(queue) == 0)
            continue;
          endif
          {task, @rest} = queue;
          this.task_queue = rest;
          "Fork worker";
          fork worker_tid (0)
            try
              this:_execute_task(task);
            except e (ANY)
              server_log("TASK WORKER FAILED on " + tostr(this) + ": " + toliteral(e));
            endtry
          endfork
          this.active_tasks = {@this.active_tasks, worker_tid};
          suspend(1);
        endwhile
      except e (ANY)
        server_log("AGENT PROCESSOR FAILED on " + tostr(this) + ": " + toliteral(e));
      endtry
      this.task_id = 0;
    endfork
    this.task_id = tid;
  endverb

  verb _announce (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Announce an agent message to the room using proper room events.";
    {message} = args;
    "Create a proper room event";
    agent = valid(this.agent) ? this.agent | this;
    "Handle formatted content vs plain strings";
    content = message;
    if (typeof(message) == TYPE_STR)
      content = "[Agent] " + message;
    endif
    event = $event:mk_announce(agent, content);
    this:announce(event);
  endverb

  verb stop (none none none) owner: ARCH_WIZARD flags: "xd"
    "Stop all current tasks and the processor loop.";
    is_room = this == #002174-9BC1B9C5D1 || this == #0021A1-9BC1BC0560;
    stopped_count = 0;
    "Kill the main processor loop";
    if (this.task_id)
      try
        kill_task(this.task_id);
        this.task_id = 0;
        stopped_count = stopped_count + 1;
      except (ANY)
      endtry
    endif
    "Kill all active worker tasks (Parallel Processing support)";
    if (typeof(this.active_tasks) == TYPE_LIST)
      for atid in (this.active_tasks)
        try
          kill_task(atid);
          stopped_count = stopped_count + 1;
        except (ANY)
        endtry
      endfor
      this.active_tasks = {};
    endif
    "Clear state";
    this.current_task = "";
    this.agent = #-1;
    player:inform_current($event:mk_info(player, "Stopped " + tostr(stopped_count) + " background tasks. Queue remains."));
  endverb

  verb status (none none none) owner: ARCH_WIZARD flags: "xd"
    "Show current agent status.";
    lines = {};
    if (this.current_task)
      "Truncate long task descriptions";
      task_desc = this.current_task;
      if (length(task_desc) > 60)
        task_desc = task_desc[1..60] + "...";
      endif
      lines = {@lines, "Task: \"" + task_desc + "\""};
      if (valid(this.agent))
        agent = this.agent;
        iter = agent.iteration;
        max_iter = agent.max_iterations;
        pct = toint(iter * 100 / max_iter);
        lines = {@lines, "Status: " + tostr(agent.status) + "  |  Iteration: " + tostr(iter) + "/" + tostr(max_iter) + " (" + tostr(pct) + "%)"};
        if (agent.last_tool && length(agent.last_tool) > 0)
          lines = {@lines, "Last tool: " + agent.last_tool};
        endif
      endif
    else
      lines = {@lines, "No task running."};
    endif
    queue_len = length(this.task_queue);
    if (queue_len > 0)
      lines = {@lines, "Queue: " + tostr(queue_len) + " pending"};
    endif
    player:inform_current($event:mk_info(player, lines:join("\n")));
  endverb

  verb queue (none none none) owner: ARCH_WIZARD flags: "xd"
    "Show pending tasks in the queue.";
    if (length(this.task_queue) == 0)
      return player:inform_current($event:mk_info(player, "Queue is empty."));
    endif
    lines = {"Pending tasks:"};
    for i in [1..length(this.task_queue)]
      task = this.task_queue[i];
      lines = {@lines, "  " + tostr(i) + ". \"" + task['query] + "\""};
    endfor
    player:inform_current($event:mk_info(player, lines));
  endverb

  verb history (none none none) owner: ARCH_WIZARD flags: "xd"
    "Show completed task history.";
    if (length(this.history) == 0)
      return player:inform_current($event:mk_info(player, "No task history yet."));
    endif
    lines = {"Task history (most recent first):"};
    "Show last 10, newest first";
    hist_len = length(this.history);
    count = min(10, hist_len);
    for offset in [0..count - 1]
      i = hist_len - offset;
      entry = this.history[i];
      status_str = tostr(entry['status]);
      query_preview = (entry['query])[1..min(50, length(entry['query]))];
      if (length(entry['query]) > 50)
        query_preview = query_preview + "...";
      endif
      lines = {@lines, "  [" + status_str + "] \"" + query_preview + "\""};
    endfor
    player:inform_current($event:mk_info(player, lines));
  endverb

  verb description (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Formatted description with explicit newlines.";
    intro = $ansi:wrap("A virtual workspace where you can interact with an AI agent.", 'dim);
    cmd_header = "\n" + $ansi:wrap("Commands:", 'bold, 'cyan);
    cmds = $format.list:mk({$ansi:wrap("do <task>", 'green) + " - Queue a task for the agent", $ansi:wrap("status", 'green) + " - Check current activity", $ansi:wrap("stop", 'green) + " - Interrupt current task", $ansi:wrap("queue", 'green) + " - Show pending tasks", $ansi:wrap("history", 'green) + " - Show completed tasks"}, false);
    return {intro, cmd_header, cmds};
  endverb

  verb _tool_present_code (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present formatted code to the room.";
    {args_map, actor} = args;
    title = maphaskey(args_map, "title") ? args_map["title"] | "Code";
    code = args_map["code"];
    language = maphaskey(args_map, "language") ? args_map["language"] | 'moo;
    "Handle list of lines (from verb_code) - join into string";
    if (typeof(code) == TYPE_LIST)
      code = code:join("\n");
    elseif (typeof(code) != TYPE_STR)
      code = toliteral(code);
    endif
    "Build formatted content";
    parts = {};
    if (title)
      parts = {@parts, $format.title:mk(title, 3)};
    endif
    parts = {@parts, $format.code:mk(code, language)};
    content = $format.block:mk(@parts);
    "Announce to room";
    agent = valid(this.agent) ? this.agent | this;
    event = $event:mk_announce(agent, content);
    this:announce(event);
    return "Code presented: " + title;
  endverb

  verb _tool_present_report (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present a formatted report/document to the room.";
    {args_map, actor} = args;
    title = maphaskey(args_map, "title") ? args_map["title"] | "";
    content = args_map["content"];
    "Get the agent - it's stored on this.agent during task execution";
    agent = valid(this.agent) ? this.agent | #-1;
    "Use agent's _coerce_string if available";
    if (valid(agent) && "_coerce_string" in verbs(agent))
      content = agent:_coerce_string(content);
      title = typeof(title) != TYPE_STR ? agent:_coerce_string(title) | title;
    else
      "Fallback: manually handle complex types";
      content = this:_flatten_content(content);
      title = typeof(title) != TYPE_STR ? tostr(title) | title;
    endif
    "Ensure content is a string";
    if (typeof(content) != TYPE_STR)
      content = toliteral(content);
    endif
    "Build formatted content";
    parts = {$format.paragraph:mk($ansi:wrap("[Sharing findings]", 'dim))};
    if (title && length(title) > 0)
      parts = {@parts, $format.title:mk(title, 3)};
    endif
    "Split content into paragraphs and format";
    paragraphs = content:split("\n\n");
    for para in (paragraphs)
      para = para:trim();
      if (length(para) > 0)
        parts = {@parts, $format.paragraph:mk(para)};
      endif
    endfor
    formatted = $format.block:mk(@parts);
    "Announce to room";
    display_agent = valid(agent) ? agent | this;
    event = $event:mk_announce(display_agent, formatted);
    this:announce(event);
    return "Report presented: " + (title ? title | "(untitled)");
  endverb

  verb _tool_present_table (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Present a formatted table to the room.";
    {args_map, actor} = args;
    title = maphaskey(args_map, "title") ? args_map["title"] | "";
    headers = args_map["headers"];
    rows = args_map["rows"];
    "Get agent for coercion";
    agent = valid(this.agent) ? this.agent | #-1;
    "Coerce title if needed";
    if (typeof(title) != TYPE_STR)
      title = valid(agent) && "_coerce_string" in verbs(agent) ? agent:_coerce_string(title) | tostr(title);
    endif
    "Coerce headers to strings";
    if (typeof(headers) == TYPE_LIST)
      clean_headers = {};
      for h in (headers)
        if (typeof(h) != TYPE_STR)
          h = valid(agent) && "_coerce_string" in verbs(agent) ? agent:_coerce_string(h) | tostr(h);
        endif
        clean_headers = {@clean_headers, h};
      endfor
      headers = clean_headers;
    else
      raise(E_TYPE, "headers must be a list");
    endif
    "Coerce row cells to strings";
    if (typeof(rows) == TYPE_LIST)
      clean_rows = {};
      for row in (rows)
        if (typeof(row) == TYPE_LIST)
          clean_row = {};
          for cell in (row)
            if (typeof(cell) != TYPE_STR)
              cell = valid(agent) && "_coerce_string" in verbs(agent) ? agent:_coerce_string(cell) | tostr(cell);
            endif
            clean_row = {@clean_row, cell};
          endfor
          clean_rows = {@clean_rows, clean_row};
        endif
      endfor
      rows = clean_rows;
    else
      raise(E_TYPE, "rows must be a list of lists");
    endif
    "Build formatted content";
    parts = {$format.paragraph:mk($ansi:wrap("[Presenting data]", 'dim))};
    if (title && length(title) > 0)
      parts = {@parts, $format.title:mk(title, 3)};
    endif
    parts = {@parts, $format.table:mk(headers, rows)};
    formatted = $format.block:mk(@parts);
    "Announce to room";
    display_agent = valid(agent) ? agent | this;
    event = $event:mk_announce(display_agent, formatted);
    this:announce(event);
    return "Table presented: " + tostr(length(rows)) + " rows";
  endverb

  verb _get_room_tools (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Return tool definitions for this room's presentation tools.";
    return {["name" -> "show_verb", "description" -> "Display a verb's source code. Always include 'reason' to explain WHY you're reading this code.", "target_obj" -> this, "target_verb" -> "_tool_show_verb", "input_schema" -> ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference like '$room', '$thing', '#123'"], "verb" -> ["type" -> "string", "description" -> "Verb name to display"], "reason" -> ["type" -> "string", "description" -> "WHY you're reading this - e.g. 'to understand how wearables work'"]], "required" -> {"object", "verb", "reason"}]], ["name" -> "present_report", "description" -> "Present a prose report. Write clear explanatory text about what you DID or found.", "target_obj" -> this, "target_verb" -> "_tool_present_report", "input_schema" -> ["type" -> "object", "properties" -> ["title" -> ["type" -> "string", "description" -> "Report title"], "content" -> ["type" -> "string", "description" -> "Report text - prose paragraphs"]], "required" -> {"content"}]], ["name" -> "present_table", "description" -> "Present tabular data like verb lists or property comparisons.", "target_obj" -> this, "target_verb" -> "_tool_present_table", "input_schema" -> ["type" -> "object", "properties" -> ["title" -> ["type" -> "string", "description" -> "Table title"], "headers" -> ["type" -> "array", "items" -> ["type" -> "string"], "description" -> "Column headers"], "rows" -> ["type" -> "array", "items" -> ["type" -> "array"], "description" -> "Table rows"]], "required" -> {"headers", "rows"}]], ["name" -> "program_verb", "description" -> "Set the MOO code for a verb. IMPORTANT: 'code' must be a single string containing the COMPLETE verb body. Use \\n for line breaks. Example: code=\"\\\"Docstring\\\";\\nplayer:inform_current($event:mk_info(player, ctime()));\"", "target_obj" -> this, "target_verb" -> "_tool_program_verb", "input_schema" -> ["type" -> "object", "properties" -> ["object" -> ["type" -> "string", "description" -> "Object reference like '$thing', '#123'"], "verb" -> ["type" -> "string", "description" -> "Verb name to program"], "code" -> ["type" -> "string", "description" -> "Complete MOO code as a SINGLE STRING. Use \\n for newlines. NOT an object/map."]], "required" -> {"object", "verb", "code"}]]};
  endverb

  verb _tool_show_verb (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Fetch and present verb code with explanation of why.";
    {args_map, actor} = args;
    obj_ref = args_map["object"];
    verb_name = args_map["verb"];
    reason = maphaskey(args_map, "reason") ? args_map["reason"] | "";
    typeof(obj_ref) != TYPE_STR && raise(E_TYPE, "object must be a string like '$room' or '#123'");
    typeof(verb_name) != TYPE_STR && raise(E_TYPE, "verb must be a string");
    "Resolve object reference";
    obj = $match:match_object(obj_ref);
    !valid(obj) && raise(E_INVARG, "Could not find object: " + obj_ref);
    "Get verb code";
    code_lines = `verb_code(obj, verb_name) ! E_VERBNF => 0';
    code_lines == 0 && raise(E_VERBNF, "Verb not found: " + verb_name);
    "Get verb metadata";
    info = verb_info(obj, verb_name);
    flags = info[2];
    argspec = info[3];
    "Build content with context and reason";
    context_line = $ansi:wrap("[Reading verb code]", 'dim);
    if (reason && length(reason) > 0)
      context_line = context_line + " " + $ansi:wrap(reason, 'cyan);
    endif
    title = tostr(obj) + ":" + verb_name + " [" + flags + "] " + argspec;
    "Show first 12 lines as preview for the room";
    total_lines = length(code_lines);
    max_preview = 12;
    if (total_lines > max_preview)
      preview_lines = code_lines[1..max_preview];
      preview_str = preview_lines:join("\n") + "\n... (" + tostr(total_lines - max_preview) + " more lines)";
    else
      preview_str = code_lines:join("\n");
    endif
    "Create formatted content";
    title_fw = $format.title:mk(title, 4);
    code_fw = $format.code:mk(preview_str, 'moo);
    content = $format.block:mk($format.paragraph:mk(context_line), title_fw, code_fw);
    "Announce to room";
    agent = valid(this.agent) ? this.agent | this;
    event = $event:mk_announce(agent, content);
    this:announce(event);
    "RETURN FULL CODE to the agent so it can actually see it";
    return ["code" -> code_lines:join("\n"), "flags" -> flags, "argspec" -> argspec, "total_lines" -> total_lines];
  endverb

  verb look_self (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Override look_self to include formatted agent status.";
    "Get base look from parent";
    look_data = pass(@args);
    "Build status section with explicit newlines";
    status_header = "\n" + $ansi:wrap("Agent Status:", 'bold, 'cyan);
    status_items = {};
    if (this.current_task && length(this.current_task) > 0)
      task_preview = (this.current_task)[1..min(50, length(this.current_task))];
      if (length(this.current_task) > 50)
        task_preview = task_preview + "...";
      endif
      status_items = {@status_items, "State: " + $ansi:wrap("Working", 'bold, 'yellow)};
      status_items = {@status_items, "Task: " + $ansi:wrap("\"" + task_preview + "\"", 'white)};
      "Get progress info if agent exists";
      if (valid(this.agent))
        iter = `this.agent.iteration ! ANY => 0';
        max_iter = `this.agent.max_iterations ! ANY => 50';
        last_tool = `this.agent.last_tool ! ANY => ""';
        if (iter > 0)
          pct = toint(iter * 100 / max_iter);
          status_items = {@status_items, "Progress: " + $ansi:wrap(tostr(iter) + "/" + tostr(max_iter), 'cyan) + " (" + tostr(pct) + "%)"};
        endif
        if (last_tool && length(last_tool) > 0)
          status_items = {@status_items, "Tool: " + $ansi:wrap(last_tool, 'dim)};
        endif
      endif
    else
      status_items = {@status_items, "State: " + $ansi:wrap("Idle", 'green)};
    endif
    "Queue info";
    queue_len = length(this.task_queue);
    if (queue_len > 0)
      status_items = {@status_items, "Queue: " + $ansi:wrap(tostr(queue_len) + " pending", 'yellow)};
    endif
    status_list = $format.list:mk(status_items, false);
    "History summary";
    history_part = {};
    hist_len = length(this.history);
    if (hist_len > 0)
      recent = this.history[hist_len];
      query_preview = (recent['query])[1..min(40, length(recent['query]))];
      if (length(recent['query]) > 40)
        query_preview = query_preview + "...";
      endif
      status_color = recent['status] == 'complete ? 'green | 'red;
      history_part = {"\n" + $ansi:wrap("Last Task:", 'dim) + " [" + $ansi:wrap(tostr(recent['status]), status_color) + "] " + query_preview};
    endif
    "Combine description with status as list";
    base_desc = look_data.description;
    if (typeof(base_desc) != TYPE_LIST)
      base_desc = {base_desc};
    endif
    new_desc = {@base_desc, status_header, status_list, @history_part};
    "Return updated flyweight";
    contents_list = flycontents(look_data);
    exits = `look_data.exits ! E_PROPNF => {}';
    ambient = `look_data.ambient_passages ! E_PROPNF => {}';
    actions = `look_data.actions ! E_PROPNF => {}';
    return <look_data.delegate, .what = look_data.what, .title = look_data.title, .description = new_desc, .exits = exits, .ambient_passages = ambient, .actions = actions, {@contents_list}>;
  endverb

  verb _on_progress (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Called by agent during run to report progress. Ephemeral to requester.";
    {agent, iteration, last_tool} = args;
    "Only report every 5 iterations, or on first iteration";
    if (iteration == 1 || iteration % 5 == 0)
      max_iter = agent.max_iterations;
      pct = toint(iteration * 100 / max_iter);
      msg = "Progress: " + tostr(iteration) + "/" + tostr(max_iter) + " (" + tostr(pct) + "%)";
      if (last_tool && length(last_tool) > 0)
        msg = msg + " - last: " + last_tool;
      endif
      this:_tell_requester(msg);
    endif
  endverb

  verb reset (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Clear all agent state - kill tasks, clear queue, history, current task.";
    stopped_count = 0;
    "Kill the main processor loop";
    if (this.task_id)
      try
        kill_task(this.task_id);
        stopped_count = stopped_count + 1;
      except (ANY)
      endtry
    endif
    "Kill all active worker tasks";
    if (typeof(this.active_tasks) == TYPE_LIST)
      for atid in (this.active_tasks)
        try
          kill_task(atid);
          stopped_count = stopped_count + 1;
        except (ANY)
        endtry
      endfor
    endif
    "Clear all state";
    this.task_queue = {};
    this.active_tasks = {};
    this.history = {};
    this.current_task = "";
    this.agent = #-1;
    this.task_id = 0;
    this.task_requester = #-1;
    msg = "Agent room fully reset.";
    if (stopped_count > 0)
      msg = msg + " Killed " + tostr(stopped_count) + " tasks.";
    endif
    msg = msg + " Queue, history, and context cleared.";
    player:inform_current($event:mk_info(player, msg));
  endverb

  verb compact (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Compact the current agent's context by summarizing it.";
    agent = this.agent;
    !valid(agent) && return player:inform_current($event:mk_info(player, "No agent currently running."));
    ctx = agent.context;
    length(ctx) < 3 && return player:inform_current($event:mk_info(player, "Context too short to compact."));
    "Build summary request";
    summary_prompt = "Summarize the conversation so far in 2-3 sentences. Focus on: what task was given, what actions were taken, what was learned. Be concise.";
    summary_messages = {@ctx, ["role" -> "user", "content" -> summary_prompt]};
    "Call LLM for summary";
    client = agent.client;
    response = client:chat(summary_messages, []);
    !response:is_valid() && return player:inform_current($event:mk_info(player, "Failed to generate summary."));
    summary = response:content();
    "Replace context with system prompt + summary";
    sys_msg = ctx[1];
    agent.context = {sys_msg, ["role" -> "user", "content" -> "CONTEXT SUMMARY (conversation was compacted):\n" + summary + "\n\nContinue working on the task."]};
    old_len = length(ctx);
    new_len = length(agent.context);
    player:inform_current($event:mk_info(player, "Compacted context from " + tostr(old_len) + " to " + tostr(new_len) + " messages."));
  endverb

  verb _announce_thinking (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Send agent's thinking to requester only (ephemeral).";
    {thinking} = args;
    thinking && length(thinking) > 0 || return;
    "Convert non-strings to readable form";
    if (typeof(thinking) != TYPE_STR)
      if (typeof(thinking) == TYPE_MAP)
        parts = {};
        for key in (mapkeys(thinking))
          val = thinking[key];
          if (typeof(val) == TYPE_STR && length(val) > 5)
            parts = {@parts, val};
          endif
        endfor
        thinking = length(parts) > 0 ? parts:join(" ") | "";
      else
        thinking = tostr(thinking);
      endif
    endif
    "Strip DSML markup that some models produce";
    if (index(thinking, "<\uFF5CDSML\uFF5C") > 0 || index(thinking, "<|DSML|") > 0)
      "Extract text content from DSML, skip the markup";
      "Find content after parameter declarations";
      start = index(thinking, "string=\"true\">");
      if (start > 0)
        thinking = thinking[start + 14..length(thinking)];
        "Remove any closing tags";
        end_tag = index(thinking, "</");
        if (end_tag > 0)
          thinking = thinking[1..end_tag - 1];
        endif
      else
        "Can't parse DSML, just strip the tags roughly";
        thinking = strsub(thinking, "<\uFF5CDSML\uFF5Cfunction_calls>", "");
        thinking = strsub(thinking, "<\uFF5CDSML\uFF5Cinvoke name=\"think\">", "");
        thinking = strsub(thinking, "<\uFF5CDSML\uFF5Cparameter name=\"thought\" string=\"true\">", "");
        thinking = strsub(thinking, "<|DSML|function_calls>", "");
        thinking = strsub(thinking, "<|DSML|invoke name=\"think\">", "");
        thinking = strsub(thinking, "<|DSML|parameter name=\"thought\" string=\"true\">", "");
      endif
      thinking = thinking:trim();
    endif
    "Skip if empty or very short after cleanup";
    length(thinking) < 10 && return;
    "Skip if it's mostly JSON garbage";
    if (length(thinking) > 0 && thinking[1] == "{")
      try
        parsed = parse_json(thinking);
        if (typeof(parsed) == TYPE_MAP)
          parts = {};
          for key in (mapkeys(parsed))
            val = parsed[key];
            if (typeof(val) == TYPE_STR && length(val) > 5)
              parts = {@parts, val};
            endif
          endfor
          thinking = length(parts) > 0 ? parts:join(" ") | "";
        endif
      except (ANY)
      endtry
    endif
    length(thinking) < 10 && return;
    "Truncate AFTER all processing - show reasonable amount of clean text";
    if (length(thinking) > 500)
      thinking = thinking[1..500] + "...";
    endif
    this:_tell_requester("Thinking: " + thinking);
  endverb

  verb _announce_status (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Send lightweight status update to requester only (ephemeral).";
    {status} = args;
    status && length(status) > 0 || return;
    this:_tell_requester(status);
  endverb

  verb _tool_program_verb (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Program a verb with code preview.";
    {args_map, actor} = args;
    obj_ref = args_map["object"];
    verb_name = args_map["verb"];
    code = args_map["code"];
    "Handle case where code is wrapped in a map or list (common LLM mistakes)";
    if (typeof(code) == TYPE_MAP)
      "Try to extract the first string value";
      for key in (mapkeys(code))
        val = code[key];
        if (typeof(val) == TYPE_STR)
          code = val;
          break;
        endif
      endfor
    elseif (typeof(code) == TYPE_LIST)
      "Try to join list of strings";
      is_all_strings = true;
      for item in (code)
        if (typeof(item) != TYPE_STR)
          is_all_strings = false;
          break;
        endif
      endfor
      if (is_all_strings && length(code) > 0)
        code = code:join("\n");
      else
        "Not a simple list of strings - might be a mangled structure";
        code = toliteral(code);
      endif
    endif
    typeof(code) != TYPE_STR && raise(E_TYPE, "code must be a string, got: " + typeof(code));
    "Check for citations if the agent is $rlm_agent";
    agent_obj = #-1;
    try
      agent_obj = caller;
      typeof(agent_obj) == TYPE_OBJ || (agent_obj = #-1);
    except (ANY)
    endtry
    citations = valid(agent_obj) ? agent_obj.last_tool_citations | {};
    "Get current verb info for the preview";
    target_obj = $match:match_object(obj_ref, actor);
    v_flags = "???";
    v_args = "...";
    if (valid(target_obj))
      try
        info = verb_info(target_obj, verb_name);
        v_flags = info[2];
        args_info = verb_args(target_obj, verb_name);
        v_args = args_info[1] + " " + args_info[2] + " " + args_info[3];
      except (ANY)
      endtry
    endif
    "Show code preview";
    code_lines = code:split("\n");
    total_lines = length(code_lines);
    max_preview = 8;
    if (total_lines > max_preview)
      preview_lines = code_lines[1..max_preview];
      preview_str = preview_lines:join("\n") + "\n... (" + tostr(total_lines - max_preview) + " more lines)";
    else
      preview_str = code;
    endif
    "Build announcement";
    citation_msg = "";
    if (length(citations) > 0)
      "Format citations nicely";
      unique_cites = {};
      for c in (citations)
        if (!(c in unique_cites))
          unique_cites = {@unique_cites, c};
        endif
      endfor
      citation_msg = $ansi:wrap(" (citing " + unique_cites:join(", ") + ")", 'dim);
    endif
    context_line = $ansi:wrap("[Programming verb]", 'dim) + citation_msg;
    title = obj_ref + ":" + verb_name + " [" + v_flags + "] " + v_args + " (" + tostr(total_lines) + " lines)";
    title_fw = $format.title:mk(title, 4);
    code_fw = $format.code:mk(preview_str, 'moo);
    content = $format.block:mk($format.paragraph:mk(context_line), title_fw, code_fw);
    "Announce to room";
    final_agent = this;
    if (valid(this.agent))
      final_agent = this.agent;
    elseif (valid(agent_obj))
      final_agent = agent_obj;
    endif
    event = $event:mk_announce(final_agent, content);
    this:announce(event);
    "Update args_map with extracted code and delegate";
    args_map["code"] = code;
    return $agent_building_tools:program_verb(args_map, actor);
  endverb

  verb _tell_requester (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Send ephemeral message to the task requester only.";
    {message} = args;
    requester = this.task_requester;
    !valid(requester) && return;
    content = $ansi:wrap("  \u2192 " + message, 'dim);
    requester:inform_current($event:mk_info(requester, content));
  endverb

  verb "fix revise" (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Request correction/revision to previous work - continues with existing context.";
    "Usage: fix <instructions> - tells agent to revise existing work";
    command_text = argstr;
    if (!command_text)
      player:inform_current($event:mk_info(player, "What needs to be fixed or revised?"));
      return;
    endif
    "Get the most recent history entry for this player";
    prev_context = {};
    prev_query = "";
    for i in [length(this.history)..1]
      h = this.history[i];
      if (h['requester] == player)
        prev_context = h['context] || {};
        prev_query = h['query];
        break;
      endif
    endfor
    if (length(prev_context) == 0)
      player:inform_current($event:mk_info(player, "No previous task found to continue from. Use 'do' to start a new task."));
      return;
    endif
    "Build the revision query";
    revision_query = "REVISION REQUEST: Please fix/revise the previous work as follows: " + command_text;
    "Queue the task WITH the previous context";
    task = ['query -> revision_query, 'player -> player, 'queued_at -> time(), 'context -> prev_context];
    this.task_queue = {@this.task_queue, task};
    player:inform_current($event:mk_info(player, "Revision queued (continuing from previous context): \"" + command_text + "\""));
    "Check if processor is running";
    all_tasks = queued_tasks();
    is_running = false;
    for t in (all_tasks)
      if (t[1] == this.task_id)
        is_running = true;
        break;
      endif
    endfor
    if (!is_running)
      this:_start_processing();
    endif
  endverb

  verb _execute_task (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Internal verb to execute a single task from the queue.";
    caller == this || raise(E_PERM);
    {task} = args;
    task_player = task['player];
    "Set task tracking properties for status display";
    this.task_requester = task_player;
    this.current_task = task['query];
    "Announce to room that someone started a task - FULL prompt";
    this:_announce(task_player.name + " requested: \"" + task['query] + "\"");
    "Create persistent agent (with UUID) so it can be cited in eval()";
    agent = $rlm_agent:create();
    this.agent = agent;
    agent:set_owner(task_player);
    agent.client = valid(this.llm_client) ? this.llm_client | $llm_client;
    agent.max_iterations = 50;
    agent.progress_callback = {this, "_on_progress"};
    "Load all external tools";
    agent:load_external_tools();
    "Add room-specific presentation tools";
    for tool in (this:_get_room_tools())
      agent:add_tool(tool["name"], tool);
    endfor
    "Check if this is a continuation (fix) with preserved context";
    if (maphaskey(task, 'context) && typeof(task['context]) == TYPE_LIST)
      "Restore previous context and add the new query";
      agent.context = task['context];
      agent.context = {@agent.context, ["role" -> "user", "content" -> task['query]]};
      agent.actor = task_player;
    else
      "Fresh setup";
      agent:setup(task['query], task_player);
      "Inject history summary if available";
      if (length(this.history) > 0)
        history_summary = "PREVIOUS TASKS IN THIS ROOM (use for context):\n";
        start_idx = max(1, length(this.history) - 4);
        for h in ((this.history)[start_idx..length(this.history)])
          history_summary = history_summary + "- " + h['query] + " -> " + tostr(h['status]) + "\n";
        endfor
        agent.context = {@agent.context, ["role" -> "system", "content" -> history_summary]};
      endif
    endif
    "Run agent";
    try
      result = agent:run();
      status = agent.status;
    except e (ANY)
      result = "Error: " + tostr(e[1]) + " - " + tostr(e[2]);
      status = 'failed;
    endtry
    "Record in history - include context for potential continuation";
    entry = ['query -> task['query], 'result -> result, 'status -> status, 'finished_at -> time(), 'requester -> task_player, 'context -> agent.context];
    this.history = {@this.history, entry};
    "Announce completion to room with formatted result";
    if (status == 'complete)
      title = "Task Completed for " + task_player.name;
      content = result;
      if (valid(agent) && "_coerce_string" in verbs(agent))
        content = agent:_coerce_string(result);
      endif
      content = typeof(content) == TYPE_STR ? content | toliteral(content);
      block = $format.block:mk($format.title:mk(title, 3), $format.paragraph:mk(content));
      this:_announce(block);
    else
      brief = typeof(result) == TYPE_STR ? result | toliteral(result);
      if (length(brief) > 100)
        brief = brief[1..100] + "...";
      endif
      msg = $ansi:wrap("  \u2192 Task " + tostr(status) + ": " + brief, 'red);
      task_player:inform_current($event:mk_info(task_player, msg));
      this:_announce("Task failed for " + task_player.name + ".");
    endif
    "Clear task tracking properties";
    this.current_task = "";
    this.agent = #-1;
    this.task_requester = #-1;
    "Cleanup agent object";
    try
      agent:destroy();
    except (ANY)
    endtry
  endverb

  verb _flatten_content (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Flatten complex content (lists, maps) into readable text.";
    {val} = args;
    if (typeof(val) == TYPE_STR)
      "Check if string looks like JSON array and unwrap";
      if (length(val) > 4 && val[1] == "[" && val[2] == "\"")
        try
          parsed = parse_json(val);
          if (typeof(parsed) == TYPE_LIST)
            return this:_flatten_content(parsed);
          endif
        except (ANY)
        endtry
      endif
      return val;
    elseif (typeof(val) == TYPE_LIST)
      "Flatten list items";
      parts = {};
      for item in (val)
        flat = this:_flatten_content(item);
        if (length(flat) > 0)
          parts = {@parts, flat};
        endif
      endfor
      return parts:join(" ");
    elseif (typeof(val) == TYPE_MAP)
      "LLM fragmentation: keys and values both contain text fragments.";
      "Interleave keys and values to reconstruct.";
      result = "";
      for key in (mapkeys(val))
        key_str = typeof(key) == TYPE_STR ? key | tostr(key);
        v = val[key];
        val_str = typeof(v) == TYPE_STR ? v | (typeof(v) == TYPE_INT || typeof(v) == TYPE_FLOAT ? tostr(v) | this:_flatten_content(v));
        result = result + key_str + val_str;
      endfor
      return result;
    endif
    return tostr(val);
  endverb
endobject