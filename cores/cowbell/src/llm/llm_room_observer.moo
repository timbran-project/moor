object LLM_ROOM_OBSERVER
  name: "LLM Room Observer"
  parent: ACTOR
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "rc") = #-1;
  property already_off_msg (owner: HACKER, flags: "rc") = {<SUB, .capitalize = true, .type = 'dobj>, " is already switched off."};
  property already_on_msg (owner: HACKER, flags: "rc") = {<SUB, .capitalize = true, .type = 'dobj>, " is already active."};
  property enabled (owner: HACKER, flags: "rc") = true;
  property event_buffer (owner: ARCH_WIZARD, flags: "rc") = {};
  property event_buffer_size (owner: ARCH_WIZARD, flags: "rc") = 5;
  property knowledge_base (owner: HACKER, flags: "rc") = #-1;
  property last_significant_event (owner: HACKER, flags: "rc") = 0.0;
  property last_spoke_at (owner: HACKER, flags: "rc") = 0.0;
  property loop_task (owner: ARCH_WIZARD, flags: "rc") = 0;
  property observation_mechanics_prompt (owner: HACKER, flags: "rc") = "You are observing events in a virtual room. Events are delivered to you as MOO flyweight structures in the form OBSERVATION: <delegate, .field1 = value, .field2 = value>. Extract the relevant information from these structured events and use them to understand what's happening.";
  property preferred_model (owner: HACKER, flags: "rc") = "";
  property responding (owner: ARCH_WIZARD, flags: "rc") = 0;
  property response_opts (owner: HACKER, flags: "rc") = false;
  property response_prompt (owner: HACKER, flags: "rc") = "Respond to what you've observed. CRITICAL: Do NOT output any text directly - only use tool calls. For physical actions, use the emote tool. For speech, use directed_say. You can make multiple tool calls in sequence. If you have nothing to say or do, output nothing at all. Never explain your reasoning or thought process in your response - just act.";
  property role_prompt (owner: HACKER, flags: "rc") = "When asked, provide witty or insightful commentary based on what you've seen.";
  property shut_off_msg (owner: HACKER, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "reach", .for_others = "reaches">,
    " behind ",
    <SUB, .capitalize = false, .type = 'dobj>,
    "'s head and ",
    <SUB, .type = 'self_alt, .for_self = "flip", .for_others = "flips">,
    " a small switch. ",
    <SUB, .capitalize = true, .type = 'dobj>,
    " freezes mid-motion, eyes going vacant."
  };
  property significant_events (owner: HACKER, flags: "rc") = {
    "arrival",
    "departure",
    "say",
    "directed_say",
    "emote",
    "social",
    "pasteline",
    "url_share",
    "paste",
    "connected",
    "disconnected",
    "stagetalk"
  };
  property speak_cooldown (owner: HACKER, flags: "rc") = 10;
  property speak_delay (owner: HACKER, flags: "rc") = 3;
  property thinking_delay (owner: HACKER, flags: "rc") = 8;
  property thinking_interval (owner: HACKER, flags: "rc") = 6;
  property thinking_messages (owner: HACKER, flags: "rc") = {"thinks...", "ponders...", "considers...", "mulls it over..."};
  property thinking_task (owner: HACKER, flags: "rc") = 0;
  property thinking_timeout (owner: HACKER, flags: "rc") = 60;
  property thinking_timeout_message (owner: HACKER, flags: "rc") = "looks confused and shakes head, seeming to have lost the thread.";
  property triage_model (owner: ARCH_WIZARD, flags: "rc") = "MiniMaxAI/MiniMax-M2.1";
  property triage_prompt (owner: ARCH_WIZARD, flags: "rc") = "You are a triage filter for an NPC named {name}. Decide if {name} should engage with the recent activity.\n\nEXAMPLES:\n\nActivity: Alice says, \"Hey {name}, can you help me find the restaurant?\"\nAnswer: ENGAGE (directly addressed by name, asking for help)\n\nActivity: Bob arrives from the north.\nAnswer: IGNORE (just someone arriving, wait to see if they need help)\n\nActivity: Carol says, \"I have a commit that might help with that bug\"\nAnswer: IGNORE (technical discussion between others, \"help\" not directed at {name})\n\nActivity: Dan says, \"where am I? how do I check in?\"\nAnswer: ENGAGE (newcomer seems confused and needs orientation)\n\nActivity: Eve [to Frank]: \"did you see the game last night?\"\nAnswer: IGNORE (conversation between two other people)\n\nActivity: Grace says, \"this websocket code is tricky\"\nAnswer: IGNORE (technical discussion, not asking {name} for anything)\n\nActivity: Henry says, \"{name}?\"\nAnswer: ENGAGE (directly addressed by name)\n\nActivity: Iris nods\nActivity: Jack waves to everyone\nAnswer: IGNORE (social gestures not requiring response)\n\nActivity: Kate says, \"excuse me, is there someone who works here?\"\nAnswer: ENGAGE (looking for staff assistance)\n\nNOW DECIDE for this activity:\n{events}\n\nAnswer with ONLY one word: ENGAGE or IGNORE";
  property turn_on_msg (owner: HACKER, flags: "rc") = {
    <SUB, .capitalize = true, .type = 'actor>,
    " ",
    <SUB, .type = 'self_alt, .for_self = "reach", .for_others = "reaches">,
    " behind ",
    <SUB, .capitalize = false, .type = 'dobj>,
    "'s head and ",
    <SUB, .type = 'self_alt, .for_self = "flip", .for_others = "flips">,
    " the switch back. ",
    <SUB, .capitalize = true, .type = 'dobj>,
    " blinks and looks around, reorienting."
  };

  override description = "Room-observing bot powered by an LLM agent. Watches room events and responds when poked.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_room_observer";

  verb configure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create agent and apply configuration. Children override _setup_agent to customize.";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    set_task_perms(this.owner);
    "Create anonymous agent - GC'd when no longer referenced";
    this.agent = $llm_agent:create(true);
    "Set agent owner to observer owner so they can write to agent properties";
    this.agent.owner = this.owner;
    "Set token_owner to the observer - tools execute on behalf of the NPC";
    this.agent.token_owner = this;
    "Set model if preferred_model is configured";
    if (this.preferred_model)
      this.agent.client.model = this.preferred_model;
    endif
    "Let child class configure it";
    this:_setup_agent(this.agent);
  endverb

  verb _setup_agent (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Configure agent with room observer prompts. Override in children to add tools.";
    {agent} = args;
    "Combine base observation mechanics with specific role";
    agent.system_prompt = this.observation_mechanics_prompt + " " + this.role_prompt;
    agent:reset_context();
    "Set default chat options: lower temperature for more consistent responses";
    agent.chat_opts = $llm_chat_opts:mk():with_temperature(0.5);
    "Response opts: no tools needed for simple speak/silent decisions";
    this.response_opts = $llm_chat_opts:mk():with_temperature(0.6):with_tool_choice('none);
    "Set compaction callback so we can inject memories after compaction";
    agent.compaction_callback = this;
  endverb

  verb reconfigure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Reconfigure by stopping loop, clearing agent, and creating fresh one";
    caller == this || caller == this.owner || caller_perms().wizard || raise(E_PERM);
    "Stop the event loop before reconfiguring";
    this:_stop_loop();
    "Clear ref - anonymous agent will be GC'd";
    this.agent = #-1;
    "Create fresh agent with current configuration";
    this:configure();
  endverb

  verb tell (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Receive events from room. Enqueues to event loop via task_send.";
    if (!this.enabled)
      return;
    endif
    if (!$llm_client:is_configured())
      return;
    endif
    {event} = args;
    "Skip own events";
    event_actor = `event.actor ! ANY => #-1';
    if (event_actor == this)
      return;
    endif
    "Skip events from other NPCs";
    if (typeof(event_actor) == TYPE_OBJ && valid(event_actor) && isa(event_actor, $llm_room_observer))
      return;
    endif
    "Check if significant event type";
    event_verb = `event.verb ! ANY => ""';
    if (!(event_verb in this.significant_events))
      return;
    endif
    "Check if addressed to us or to someone else (via iobj)";
    event_target = `event.iobj ! ANY => #-1';
    addressed_to_us = typeof(event_target) == TYPE_OBJ && valid(event_target) && event_target == this;
    addressed_to_other = typeof(event_target) == TYPE_OBJ && valid(event_target) && event_target != this;
    if (addressed_to_other)
      return;
    endif
    "Name-mention filter: if a say/emote mentions another observer by name but not us, skip.";
    "Prevents NPCs from butting in on conversations directed at a sibling NPC.";
    if (event_verb == "say" || event_verb == "directed_say" || event_verb == "emote")
      event_content = `event.content ! ANY => ""';
      if (typeof(event_content) == TYPE_STR && length(event_content) > 0)
        content_lower = event_content:lowercase();
        my_name_lower = this:name():lowercase();
        mentions_me = index(content_lower, my_name_lower) > 0;
        mentions_other_observer = false;
        if (valid(this.location))
          for obj in (this.location.contents)
            if (obj != this && valid(obj) && isa(obj, $llm_room_observer))
              other_name = `obj:name() ! ANY => ""':lowercase();
              if (length(other_name) > 0 && index(content_lower, other_name) > 0)
                mentions_other_observer = true;
              endif
            endif
          endfor
        endif
        "Skip if mentions another observer but not us";
        if (mentions_other_observer && !mentions_me)
          return;
        endif
        "If it mentions us by name, mark as addressed";
        if (mentions_me && !addressed_to_us)
          addressed_to_us = true;
        endif
      endif
    endif
    "Ensure event loop is running and enqueue";
    this:_ensure_loop();
    msg = ["type" -> "observation", "content" -> toliteral(event), "addressed" -> addressed_to_us];
    try
      task_send(this.loop_task, msg);
    except e (ANY)
      "Loop may have died - restart and retry once";
      this:_start_loop();
      `task_send(this.loop_task, msg) ! ANY';
    endtry
  endverb

  verb poke (this none none) owner: ARCH_WIZARD flags: "rd"
    "Trigger the observer to respond. Sends poke to event loop and waits for reply.";
    if (!this.enabled)
      player:inform_current($event:mk_info(player, this:name() + " is currently switched off."));
      return;
    endif
    if (!valid(this.agent))
      this:configure();
    endif
    if (length(this.agent.context) <= 1)
      player:inform_current($event:mk_error(player, "No observations to respond to yet."));
      return;
    endif
    "Announce the poke action to the room";
    if (valid(this.location))
      poke_event = $event:mk_emote(player, $sub:nc(), " ", $sub:self_alt("poke", "pokes"), " ", this:name(), ".");
      this.location:announce(poke_event);
    endif
    "Ensure event loop is running";
    this:_ensure_loop();
    "Fork to wait for the loop's reply asynchronously";
    fork (0)
      set_task_perms(this.owner);
      my_task = task_id();
      try
        task_send(this.loop_task, ["type" -> "poke", "player" -> player, "reply_to" -> my_task]);
      except e (ANY)
        "Loop may have died - restart and retry";
        this:_start_loop();
        try
          task_send(this.loop_task, ["type" -> "poke", "player" -> player, "reply_to" -> my_task]);
        except e2 (ANY)
          player:inform_current($event:mk_error(player, "Something went wrong - could not reach " + this:name() + "."));
          return;
        endtry
      endtry
      "Wait for reply from event loop (up to 90s for LLM + thinking time)";
      replies = task_recv(90);
      if (length(replies) == 0)
        player:inform_current($event:mk_info(player, this:name() + " seems lost in thought."));
      else
        reply = replies[1];
        if (typeof(reply) == TYPE_MAP && maphaskey(reply, "error"))
          error = reply["error"];
          player:inform_current($event:mk_error(player, "Something went wrong - " + tostr(error[1]) + ": " + tostr(error[2])));
        endif
      endif
    endfork
  endverb

  verb maybe_speak (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Send a nudge to the event loop suggesting it may want to speak.";
    if (!this.enabled)
      return;
    endif
    if (!$llm_client:is_configured())
      return;
    endif
    "Cooldown check - don't even bother nudging if we spoke recently";
    if (ftime() - this.last_spoke_at < this.speak_cooldown)
      return;
    endif
    this:_ensure_loop();
    try
      task_send(this.loop_task, ["type" -> "nudge"]);
    except e (ANY)
      "Loop may have died - restart and retry";
      this:_start_loop();
      `task_send(this.loop_task, ["type" -> "nudge"]) ! ANY';
    endtry
  endverb

  verb reset (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Fully reinitialize the agent - picks up any config changes";
    caller == this || caller == this.owner || caller_perms().wizard || raise(E_PERM);
    caller.location || return E_INVARG;
    "Stop existing loop";
    this:_stop_loop();
    "Reconfigure creates a fresh agent with current settings";
    this:configure();
    return E_NONE;
  endverb

  verb _show_token_usage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Display token usage information to the user";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    set_task_perms(caller_perms());
    {user} = args;
    if (!valid(this.agent))
      return;
    endif
    budget = `user.llm_token_budget ! ANY => 20000000';
    used = `user.llm_tokens_used ! ANY => 0';
    last_usage = this.agent.last_token_usage;
    if (typeof(last_usage) == TYPE_MAP && maphaskey(last_usage, "total_tokens"))
      last_tokens = last_usage["total_tokens"];
      remaining = budget - used;
      percent_used = used * 100 / budget;
      "Color code based on usage";
      if (percent_used >= 90)
        color = 'bright_red;
      elseif (percent_used >= 75)
        color = 'yellow;
      else
        color = 'dim;
      endif
      usage_msg = $ansi:colorize("[TOKENS]", color) + " Last call: " + $ansi:colorize(tostr(last_tokens), 'white) + " | Total: " + tostr(used) + "/" + tostr(budget) + " (" + tostr(percent_used) + "% used)";
      user:inform_current($event:mk_info(user, usage_msg):with_presentation_hint('inset):with_group('llm, this));
    endif
  endverb

  verb "@reset" (this none none) owner: ARCH_WIZARD flags: "rd"
    if (!player.wizard && player != this.owner)
      player:inform_current($event:mk_error(player, "You can't do that."));
      return;
    endif
    reset_event = $event:mk_emote(player, player:name(), " reaches behind ", this:name(), "'s head and flips a formerly unseen switch...");
    caller.location:announce(reset_event);
    this:reset();
  endverb

  verb shut (this off none) owner: ARCH_WIZARD flags: "rd"
    "Shut off the observer - stops listening to room events";
    if (!player.wizard && player != this.owner)
      player:inform_current($event:mk_error(player, "You can't do that."));
      return;
    endif
    if (!this.enabled)
      event = $event:mk_info(player, @this.already_off_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    this.enabled = false;
    "Stop the event loop";
    this:_stop_loop();
    if (valid(this.location))
      event = $event:mk_emote(player, @this.shut_off_msg):with_dobj(this);
      this.location:announce(event);
    endif
  endverb

  verb turn (this on none) owner: ARCH_WIZARD flags: "rd"
    "Turn on the observer - resumes listening to room events";
    if (!player.wizard && player != this.owner)
      player:inform_current($event:mk_error(player, "You can't do that."));
      return;
    endif
    if (this.enabled)
      event = $event:mk_info(player, @this.already_on_msg):with_dobj(this);
      player:inform_current(event);
      return;
    endif
    this.enabled = true;
    if (valid(this.location))
      event = $event:mk_emote(player, @this.turn_on_msg):with_dobj(this);
      this.location:announce(event);
    endif
    "Lazy start - loop will start on first tell event";
  endverb

  verb _handle_agent_error (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Handle and log errors from agent operations. Override in children to customize.";
    {context, error} = args;
    error_msg = tostr(error[1]) + ": " + tostr(error[2]);
    server_log("LLM observer error [" + tostr(this) + " " + context + "]: " + error_msg);
    "Announce error to room if configured to do so";
    if (valid(this.location) && respond_to(this, 'on_agent_error))
      `this:on_agent_error(context, error) ! ANY';
    endif
  endverb

  verb _start_thinking (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Start showing periodic thinking emotes. Called from event loop (single-threaded).";
    if (!valid(this.location))
      return 0;
    endif
    "If already thinking, just return existing task";
    if (this.thinking_task > 0)
      return this.thinking_task;
    endif
    "Fork a task that shows thinking emotes after initial delay, then periodically";
    fork task_id (this.thinking_delay)
      my_id = task_id;
      msg_idx = 1;
      start_time = ftime();
      "Only run while THIS task is the active thinking task";
      while (this.thinking_task == my_id)
        "Check for timeout";
        if (ftime() - start_time > this.thinking_timeout)
          if (valid(this.location))
            this.location:announce(this:mk_emote_event(this.thinking_timeout_message));
          endif
          this.thinking_task = 0;
          break;
        endif
        if (valid(this.location) && length(this.thinking_messages) > 0)
          this.location:announce(this:mk_emote_event(this.thinking_messages[msg_idx]));
          msg_idx = msg_idx % length(this.thinking_messages) + 1;
        endif
        suspend(this.thinking_interval);
      endwhile
    endfork
    this.thinking_task = task_id;
    commit();
    return task_id;
  endverb

  verb _stop_thinking (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Stop the thinking indicator task.";
    {?task_id = 0} = args;
    task_id = task_id || this.thinking_task;
    if (task_id > 0)
      `kill_task(task_id) ! ANY';
      this.thinking_task = 0;
      commit();
    endif
  endverb

  verb _ensure_knowledge_base (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Lazily create knowledge base relation if not already created.";
    "Uses anonymous object so it's garbage collected when observer is recycled.";
    perms = caller_perms();
    caller == this || (valid(perms) && perms.wizard) || raise(E_PERM);
    if (!valid(this.knowledge_base))
      set_task_perms(this.owner);
      this.knowledge_base = $relation:create(true);
    endif
    return this.knowledge_base;
  endverb

  verb _tool_remember_fact (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Store a fact about a subject for later recall.";
    {args_map, actor} = args;
    "Safely extract arguments with defaults";
    subject = `args_map["subject"] ! E_RANGE => ""';
    fact = `args_map["fact"] ! E_RANGE => ""';
    "Check for missing required fields";
    if (typeof(subject) != TYPE_STR || subject == "")
      return "ERROR: Missing 'subject' parameter. You must provide both 'subject' and 'fact'. Example: {\"subject\": \"Ryan\", \"fact\": \"is a wizard\"}";
    endif
    if (typeof(fact) != TYPE_STR || fact == "")
      return "ERROR: Missing 'fact' parameter. You must provide both 'subject' and 'fact'. Example: {\"subject\": \"Ryan\", \"fact\": \"is a wizard\"}";
    endif
    "Check for values starting with any kind of quote character (ASCII or Unicode curly quotes)";
    "This catches LLM errors where it puts escaped quotes in values";
    quote_chars = {"\"", "'", "\u201C", "\u201D", "\u2018", "\u2019"};
    for qc in (quote_chars)
      if (subject:starts_with(qc) || fact:starts_with(qc))
        return "ERROR: Values should not start with quote characters. Remove any quotes from the values. WRONG: {\"subject\": \"\\\"mooR\\\"\"} CORRECT: {\"subject\": \"mooR\"}";
      endif
    endfor
    "Validate non-empty and meaningful content";
    subject = subject:trim();
    fact = fact:trim();
    if (length(subject) < 2)
      return "ERROR: Subject '" + subject + "' is too short. Use a name or topic like 'Ryan' or 'mooR'.";
    endif
    if (length(fact) < 3)
      return "ERROR: Fact '" + fact + "' is too short. Use a complete statement like 'is a wizard' or 'was created in 1990'.";
    endif
    if (subject == fact)
      return "ERROR: Subject and fact are identical. Subject is WHO/WHAT, fact is WHAT YOU KNOW. Example: subject='Ryan', fact='is a wizard'.";
    endif
    kb = this:_ensure_knowledge_base();
    "Store as (subject, fact, timestamp) tuple";
    kb:assert({subject, fact, time()});
    return "Successfully remembered about " + subject + ": " + fact;
  endverb

  verb _tool_recall_facts (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Retrieve stored facts about a subject.";
    {args_map, actor} = args;
    subject = args_map["subject"];
    typeof(subject) != TYPE_STR && raise(E_TYPE, "subject must be a string");
    if (!valid(this.knowledge_base))
      return "No memories stored yet.";
    endif
    "Query for facts matching this subject";
    results = this.knowledge_base:select_containing(subject);
    !results && return "No facts remembered about " + subject + ".";
    "Format results with timestamps";
    lines = {"Facts about " + subject + ":"};
    for tuple in (results)
      if (length(tuple) >= 2 && tuple[1] == subject)
        fact = tuple[2];
        time_str = length(tuple) >= 3 ? " (" + this:_format_time_ago(tuple[3]) + ")" | "";
        lines = {@lines, " - " + fact + time_str};
      endif
    endfor
    return length(lines) > 1 ? lines:join("\n") | "No facts remembered about " + subject + ".";
  endverb

  verb _register_memory_tools (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register memory tools with the agent. Called by children in _setup_agent.";
    perms = caller_perms();
    caller == this || (valid(perms) && perms.wizard) || raise(E_PERM);
    {agent} = args;
    "Tool: remember a fact";
    remember_tool = $llm_agent_tool:mk("remember_fact", "Store a noteworthy fact about a person, place, or topic for later recall. Use this to remember important details that might be useful in future conversations.", ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "Who or what the fact is about (a name or topic)"], "fact" -> ["type" -> "string", "description" -> "The fact to remember - keep it brief and factual"]], "required" -> {"subject", "fact"}], this, "remember_fact");
    agent:add_tool("remember_fact", remember_tool);
    "Tool: recall facts";
    recall_tool = $llm_agent_tool:mk("recall_facts", "Recall stored facts about a person, place, or topic. Returns facts with when they were remembered.", ["type" -> "object", "properties" -> ["subject" -> ["type" -> "string", "description" -> "Who or what to recall facts about"]], "required" -> {"subject"}], this, "recall_facts");
    agent:add_tool("recall_facts", recall_tool);
    "Tool: get current time";
    time_tool = $llm_agent_tool:mk("current_time", "Get the current date and time.", ["type" -> "object", "properties" -> [], "required" -> {}], this, "current_time");
    agent:add_tool("current_time", time_tool);
  endverb

  verb get_memory_summary (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get a summary of all remembered facts for injection into compacted context.";
    perms = caller_perms();
    caller == this || (valid(perms) && perms.wizard) || raise(E_PERM);
    if (!valid(this.knowledge_base))
      return "";
    endif
    "Get all facts and organize by subject";
    all_tuples = this.knowledge_base:tuples();
    !all_tuples && return "";
    "Organize by subject";
    by_subject = [];
    for tuple in (all_tuples)
      if (length(tuple) >= 2)
        subj = tuple[1];
        fact = tuple[2];
        existing = maphaskey(by_subject, subj) ? by_subject[subj] | {};
        by_subject[subj] = {@existing, fact};
      endif
    endfor
    !mapkeys(by_subject) && return "";
    "Format summary";
    lines = {"REMEMBERED FACTS:"};
    for subj in (mapkeys(by_subject))
      facts = by_subject[subj];
      lines = {@lines, "- " + subj + ": " + facts:join("; ")};
    endfor
    return lines:join("\n");
  endverb

  verb on_compaction_start (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called when agent context is being compacted. Override in children.";
    "Default: announce if in a room";
    if (valid(this.location))
      this.location:announce(this:mk_emote_event("pauses to collect thoughts..."));
    endif
  endverb

  verb on_compaction_end (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Called after agent context compaction completes. Inject remembered facts.";
    "Children should call pass() then show their own completion message.";
    if (!valid(this.agent))
      return;
    endif
    memory_summary = this:get_memory_summary();
    if (memory_summary && memory_summary != "")
      "Inject remembered facts with clear context about their origin";
      intro = "PERSISTENT MEMORY: The following facts were stored using your remember_fact tool and have been preserved across context compaction. Refer to these when relevant:";
      this.agent:add_message("user", intro + "\n\n" + memory_summary);
    endif
  endverb

  verb mk_emote_event (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Helper to create an emote event for this observer.";
    {message} = args;
    return $event:mk_emote(this, this:name(), " ", message);
  endverb

  verb _format_time_ago (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format a timestamp as relative time (e.g., '5 minutes ago').";
    {timestamp} = args;
    now = time();
    diff = now - timestamp;
    if (diff < 60)
      return tostr(diff) + " seconds ago";
    elseif (diff < 3600)
      mins = diff / 60;
      return tostr(mins) + (mins == 1 ? " minute ago" | " minutes ago");
    elseif (diff < 86400)
      hours = diff / 3600;
      return tostr(hours) + (hours == 1 ? " hour ago" | " hours ago");
    else
      days = diff / 86400;
      return tostr(days) + (days == 1 ? " day ago" | " days ago");
    endif
  endverb

  verb _tool_current_time (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Tool: Get the current time.";
    {args_map, actor} = args;
    now = time();
    return ["current_time" -> ctime(), "timestamp" -> now];
  endverb

  verb "@facts" (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Display all remembered facts in a formatted table.";
    if (!valid(this.knowledge_base))
      player:inform_current($event:mk_info(player, "No facts stored yet."):with_audience('utility));
      return;
    endif
    tuples = this.knowledge_base:tuples();
    if (!tuples)
      player:inform_current($event:mk_info(player, "No facts stored yet."):with_audience('utility));
      return;
    endif
    "Build table rows: Subject, Fact, When";
    rows = {};
    for tuple in (tuples)
      subject = length(tuple) >= 1 ? tuple[1] | "?";
      fact = length(tuple) >= 2 ? tuple[2] | "?";
      when = length(tuple) >= 3 ? this:_format_time_ago(tuple[3]) | "?";
      rows = {@rows, {subject, fact, when}};
    endfor
    "Create formatted output";
    table_obj = $format.table:mk({"Subject", "Fact", "When"}, rows);
    title_obj = $format.title:mk("Facts for " + this:name());
    content = $format.block:mk(title_obj, table_obj);
    event = $event:mk_info(player, content):with_audience('utility);
    player:inform_current(event);
  endverb

  verb "@compact-facts" (this none none) owner: ARCH_WIZARD flags: "rxd"
    "Compact facts using LLM to consolidate, remove contradictions, and keep important ones.";
    if (!valid(this.knowledge_base))
      player:inform_current($event:mk_info(player, "No facts to compact."):with_audience('utility));
      return;
    endif
    tuples = this.knowledge_base:tuples();
    if (!tuples || length(tuples) < 2)
      player:inform_current($event:mk_info(player, "Not enough facts to compact (need at least 2)."):with_audience('utility));
      return;
    endif
    if (!valid(this.agent))
      player:inform_current($event:mk_error(player, "No agent configured."):with_audience('utility));
      return;
    endif
    "Format current facts for the LLM";
    fact_lines = {};
    for tuple in (tuples)
      subject = tuple[1];
      fact = tuple[2];
      fact_lines = {@fact_lines, subject + ": " + fact};
    endfor
    facts_text = fact_lines:join("\n");
    "Build the compaction prompt";
    prompt = "You are consolidating a knowledge base. Below are stored facts. Your job is to:\n";
    prompt = prompt + "1. Remove redundant or duplicate information\n";
    prompt = prompt + "2. Resolve contradictions (keep the most likely correct version)\n";
    prompt = prompt + "3. Merge related facts about the same subject\n";
    prompt = prompt + "4. Discard trivial or irrelevant details\n";
    prompt = prompt + "5. Keep important, useful facts\n\n";
    prompt = prompt + "CURRENT FACTS:\n" + facts_text + "\n\n";
    prompt = prompt + "Return ONLY a JSON array of consolidated facts in this format:\n";
    prompt = prompt + "[{\"subject\": \"name or topic\", \"fact\": \"the consolidated fact\"}, ...]\n";
    prompt = prompt + "Return valid JSON only, no other text.";
    player:inform_current($event:mk_info(player, "Compacting " + tostr(length(tuples)) + " facts..."):with_audience('utility));
    "Call LLM directly without adding to context";
    try
      opts = $llm_chat_opts:mk():with_temperature(0.2);
      response = this.agent.client:chat({["role" -> "user", "content" -> prompt]}, opts);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error calling LLM: " + toliteral(e)):with_audience('utility));
      return;
    endtry
    "Extract content from response - handle both string and map responses";
    if (typeof(response) == TYPE_MAP)
      "API response format - extract content from choices[1].message.content";
      try
        response = response["choices"][1]["message"]["content"];
      except e (ANY)
        player:inform_current($event:mk_error(player, "Could not extract content from API response: " + toliteral(e)):with_audience('utility));
        return;
      endtry
    endif
    "Check response type";
    if (typeof(response) != TYPE_STR)
      player:inform_current($event:mk_error(player, "LLM response was not a string: " + toliteral(response)):with_audience('utility));
      return;
    endif
    "Parse JSON response";
    start_idx = index(response, "[");
    end_idx = rindex(response, "]");
    if (start_idx == 0 || end_idx == 0 || end_idx < start_idx)
      player:inform_current($event:mk_error(player, "LLM response contained no valid JSON array: " + response):with_audience('utility));
      return;
    endif
    json_str = response[start_idx..end_idx];
    try
      new_facts = parse_json(json_str);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Error parsing JSON: " + toliteral(e)):with_audience('utility));
      player:inform_current($event:mk_info(player, "JSON was: " + json_str):with_audience('utility));
      return;
    endtry
    "Validate we got a list";
    if (typeof(new_facts) != TYPE_LIST)
      player:inform_current($event:mk_error(player, "LLM returned non-list: " + toliteral(new_facts)):with_audience('utility));
      return;
    endif
    "Don't clear if we got nothing back";
    if (length(new_facts) == 0)
      player:inform_current($event:mk_info(player, "LLM returned empty list - keeping original facts."):with_audience('utility));
      return;
    endif
    "Clear old facts and add new ones";
    old_count = length(tuples);
    this.knowledge_base:clear();
    new_count = 0;
    now = time();
    for fact_obj in (new_facts)
      if (typeof(fact_obj) == TYPE_MAP)
        subject = `fact_obj["subject"] ! E_RANGE => ""';
        fact = `fact_obj["fact"] ! E_RANGE => ""';
        if (typeof(subject) == TYPE_STR && typeof(fact) == TYPE_STR && length(subject) > 1 && length(fact) > 2)
          this.knowledge_base:assert({subject, fact, now});
          new_count = new_count + 1;
        endif
      endif
    endfor
    player:inform_current($event:mk_info(player, "Compacted " + tostr(old_count) + " facts down to " + tostr(new_count) + " facts."):with_audience('utility));
  endverb

  verb triage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Quick triage: should we engage with recent activity?";
    "Returns true for engage, false for ignore.";
    if (!$llm_client:is_configured())
      return false;
    endif
    if (!valid(this.agent))
      return false;
    endif
    "Get last few messages from context for triage";
    ctx = this.agent.context;
    if (length(ctx) <= 1)
      return false;
    endif
    "Extract recent observations";
    recent = {};
    for i in [max(1, length(ctx) - 5)..length(ctx)]
      msg = ctx[i];
      if (msg["role"] == "user" && msg["content"]:starts_with("OBSERVATION:"))
        recent = {@recent, msg["content"]};
      endif
    endfor
    if (length(recent) == 0)
      return false;
    endif
    "Build triage prompt";
    events_text = recent:join("\n");
    prompt = strsub(this.triage_prompt, "{name}", this:name());
    prompt = strsub(prompt, "{events}", events_text);
    "Quick API call - use triage_model if set, otherwise default";
    "High max_tokens to handle models that output lengthy thinking";
    opts = $llm_chat_opts:mk():with_max_tokens(2000);
    model = this.triage_model || false;
    try
      response = $llm_client:chat({["role" -> "user", "content" -> prompt]}, opts, model);
    except e (ANY)
      return false;
    endtry
    "Extract answer from response";
    "Standard models put answer in content, reasoning models may put it in reasoning_content";
    content = "";
    reasoning = "";
    if (typeof(response) == TYPE_MAP && maphaskey(response, "choices") && length(response["choices"]) > 0)
      message = response["choices"][1]["message"];
      if (typeof(message) == TYPE_MAP)
        if (maphaskey(message, "content") && typeof(message["content"]) == TYPE_STR)
          content = message["content"]:trim():uppercase();
        endif
        if (maphaskey(message, "reasoning_content") && typeof(message["reasoning_content"]) == TYPE_STR && message["reasoning_content"] != "null")
          reasoning = message["reasoning_content"]:uppercase();
        endif
      endif
    endif
    "Strip out <think>...</think> tags from content";
    while (index(content, "<THINK>") > 0)
      think_start = index(content, "<THINK>");
      think_end = index(content, "</THINK>");
      if (think_end > think_start)
        before = think_start > 1 ? content[1..think_start - 1] | "";
        after = think_end + 8 <= length(content) ? content[think_end + 8..$] | "";
        content = (before + after):trim();
      else
        "Unclosed <think> tag - just strip everything from <think> onwards";
        content = think_start > 1 ? content[1..think_start - 1]:trim() | "";
        break;
      endif
    endwhile
    "Check content first - if it's a clean ENGAGE/IGNORE answer, use it";
    if (content == "ENGAGE" || content:starts_with("ENGAGE"))
      return true;
    endif
    if (content == "IGNORE" || content:starts_with("IGNORE"))
      return false;
    endif
    "Search for ENGAGE/IGNORE anywhere in content";
    last_engage = rindex(content, "ENGAGE");
    last_ignore = rindex(content, "IGNORE");
    if (last_engage > 0 && last_engage > last_ignore)
      return true;
    endif
    if (last_ignore > 0 && last_ignore > last_engage)
      return false;
    endif
    "For reasoning models, find the LAST occurrence of ENGAGE or IGNORE in reasoning";
    "The final answer typically comes at the end of the reasoning chain";
    if (length(reasoning) > 0)
      last_engage = rindex(reasoning, "ENGAGE");
      last_ignore = rindex(reasoning, "IGNORE");
      "Return true if ENGAGE appears after IGNORE (or IGNORE not found)";
      if (last_engage > 0 && last_engage > last_ignore)
        return true;
      endif
    endif
    return false;
  endverb

  verb buffer_event (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Add an event to the rolling buffer, maintaining max size.";
    {event} = args;
    buf = this.event_buffer;
    buf = {@buf, event};
    "Trim to max size";
    max_size = this.event_buffer_size;
    if (length(buf) > max_size)
      buf = buf[length(buf) - max_size + 1..$];
    endif
    this.event_buffer = buf;
  endverb

  verb respond (none none none) owner: ARCH_WIZARD flags: "rxd"
    "Legacy wrapper - sends a nudge to the event loop to trigger a response.";
    "Response generation is now handled by _event_loop.";
    this:_ensure_loop();
    try
      task_send(this.loop_task, ["type" -> "nudge"]);
    except e (ANY)
      this:_start_loop();
      `task_send(this.loop_task, ["type" -> "nudge"]) ! ANY';
    endtry
  endverb

  verb _process_and_announce (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Process an LLM response: strip noise, detect skip conditions, announce to room.";
    "Returns true if something was announced, false if skipped.";
    {response} = args;
    if (typeof(response) != TYPE_STR)
      return false;
    endif
    response = response:trim();
    "Strip SPEAK: prefix if LLM included it";
    if (response:starts_with("SPEAK: "))
      response = response[8..$];
    endif
    "Strip <think>...</think> tags";
    response_upper = response:uppercase();
    while (index(response_upper, "<THINK>") > 0)
      think_start = index(response_upper, "<THINK>");
      think_end = index(response_upper, "</THINK>");
      if (think_end > think_start)
        before = think_start > 1 ? response[1..think_start - 1] | "";
        after = think_end + 8 <= length(response) ? response[think_end + 8..$] | "";
        response = (before + after):trim();
        response_upper = response:uppercase();
      else
        "Unclosed <think> tag - strip from <think> onwards";
        response = think_start > 1 ? response[1..think_start - 1]:trim() | "";
        break;
      endif
    endwhile
    "Strip leading/trailing quotes to prevent double-quoting";
    if (length(response) >= 2 && response[1] == "\"" && response[$] == "\"")
      response = response[2..$ - 1];
    endif
    "Check skip conditions";
    skip_prefixes = {"Operation cancelled", "I've used", "I used", "Done", "SILENT", "Said to", "I've served", "I have served", "I've delivered", "I have delivered", "I've prepared", "I have prepared", "The scene is", "Scene is", "I've acknowledged", "I have acknowledged", "I have responded", "I've responded", "I've put", "I have put", "I've played", "I have played", "No tool calls", "No tools", "I have already", "I've already", "I should wait", "I will wait", "I'll wait", "I have now", "I've now", "I should now", "I will now", "I have completed", "I've completed", "Let me analyze", "I should respond", "I need to"};
    should_skip = length(response) <= 3;
    for prefix in (skip_prefixes)
      if (response:starts_with(prefix))
        should_skip = true;
      endif
    endfor
    skip_patterns = {"remains silent", "stays silent", "stay silent", "remain silent", "waiting to be", "waits to be", "chooses not to", "decides not to", "doesn't interject", "does not interject", "quietly observes", "continues to observe", "listens quietly", "i notice", "i should remain", "should remain focused", "shouldn't interrupt", "should not interrupt", "won't interrupt", "will not interrupt", "not my place", "their conversation", "their discussion", "unless someone", "unless asked", "stay quiet", "staying quiet", "remain professional", "focused on hotel", "focused on my", "scene is complete", "fitting philosophical", "appropriately melancholic", "appropriate commentary", "fitting commentary", "treated this drink", "treated the drink", "existential choice", "properly served", "served the", "delivered appropriately", "delivered a fitting", "acknowledged the order", "acknowledged their", "in character", "maintains the", "maintaining the", "this fits", "now i wait", "wait for further", "wait for the user", "the user can now", "wait for interaction", "further interaction", "no tool calls", "tool calls necessary", "no tools needed", "no action needed", "no action required", "another tool call", "before making", "wait for reply", "waiting for reply", "await their", "awaiting their", "made my response", "already made my", "should wait for", "completed the interaction", "completed my", "now wait for", "inner thinking", "my analysis", "my reasoning", "as a ", "as an "};
    response_lower = response:lowercase();
    for pattern in (skip_patterns)
      if (index(response_lower, pattern) > 0)
        should_skip = true;
      endif
    endfor
    if (should_skip || !valid(this.location))
      return false;
    endif
    "Parse inline *actions* and emit as separate emotes";
    remaining = response;
    while (true)
      star_pos = index(remaining, "*");
      if (star_pos == 0)
        break;
      endif
      end_pos = index(remaining[star_pos + 1..$], "*");
      if (end_pos == 0)
        break;
      endif
      end_pos = star_pos + end_pos;
      action = remaining[star_pos + 1..end_pos - 1];
      "Filter out silence-related emotes";
      action_lower = action:lowercase();
      action_skip = false;
      for pattern in (skip_patterns)
        if (index(action_lower, pattern) > 0)
          action_skip = true;
        endif
      endfor
      if (length(action) > 0 && length(action) < 100 && !action_skip)
        this.location:announce(this:mk_emote_event(action));
      endif
      before = star_pos > 1 ? remaining[1..star_pos - 1] | "";
      after = end_pos < length(remaining) ? remaining[end_pos + 1..$] | "";
      remaining = before + after;
    endwhile
    remaining = remaining:trim();
    if (length(remaining) > 3)
      say_event = $event:mk_say(this, this:name(), " says, \"", remaining, "\"");
      this.location:announce(say_event);
      return true;
    endif
    return false;
  endverb

  verb _event_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Main event loop. Processes observations, pokes, and nudges via task_recv.";
    "Runs as a single long-lived task. Callers enqueue work via task_send.";
    while (this.enabled)
      "Wait for messages (up to 60s timeout)";
      messages = task_recv(60);
      if (length(messages) == 0)
        "Timeout, no messages - loop and wait again";
      else
        try
          "Categorize incoming messages";
          observations = {};
          pokes = {};
          has_nudge = false;
          for msg in (messages)
            if (typeof(msg) == TYPE_MAP)
              msg_type = `msg["type"] ! ANY => ""';
              if (msg_type == "observation")
                observations = {@observations, msg};
              elseif (msg_type == "poke")
                pokes = {@pokes, msg};
              elseif (msg_type == "nudge")
                has_nudge = true;
              endif
            endif
          endfor
          "Ensure agent is configured";
          if (typeof(this.agent) != TYPE_OBJ || !valid(this.agent))
            this:configure();
          endif
          "Add observations to agent context";
          for obs in (observations)
            content = `obs["content"] ! ANY => ""';
            if (length(content) > 0)
              this.agent:add_message("user", "OBSERVATION: " + content);
            endif
          endfor
          "Auto-compact if context is getting large";
          if (length(this.agent.context) > 100)
            `this.agent:compact_context() ! ANY';
          endif
          "Decide whether to respond";
          should_respond = false;
          if (length(pokes) > 0)
            "Pokes always trigger a response";
            should_respond = true;
          elseif (has_nudge)
            "Nudges respond if cooldown allows";
            if (ftime() - this.last_spoke_at >= this.speak_cooldown)
              should_respond = true;
            endif
          elseif (length(observations) > 0)
            "Check if any observation is addressed to us";
            addressed = false;
            for obs in (observations)
              if (`obs["addressed"] ! ANY => false')
                addressed = true;
              endif
            endfor
            if (addressed)
              should_respond = true;
            elseif (length(this.agent.context) > 1)
              "Triage to decide if we should engage";
              should_respond = `this:triage() ! ANY => false';
            endif
          endif
          if (should_respond)
            this.responding = true;
            commit();
            "Set token owner for budget tracking on pokes";
            if (length(pokes) > 0)
              poke_player = `pokes[1]["player"] ! ANY => #-1';
              if (valid(poke_player))
                this.agent.token_owner = poke_player;
              endif
            else
              this.agent.token_owner = this;
            endif
            this.last_spoke_at = ftime();
            `this:_start_thinking() ! ANY';
            try
              response = this.agent:send_message(this.response_prompt);
            except e (ANY)
              `this:_stop_thinking() ! ANY';
              this.responding = false;
              commit();
              this:_handle_agent_error("event_loop", e);
              "Notify poke callers of error";
              for poke in (pokes)
                reply_to = `poke["reply_to"] ! ANY => 0';
                if (reply_to > 0)
                  `task_send(reply_to, ["type" -> "error", "error" -> e]) ! ANY';
                  commit();
                endif
              endfor
              "Skip further processing for this batch";
              response = "";
            endtry
            if (this.responding)
              `this:_stop_thinking() ! ANY';
              "Process and announce the response";
              `this:_process_and_announce(response) ! ANY';
              "Reply to poke callers";
              for poke in (pokes)
                reply_to = `poke["reply_to"] ! ANY => 0';
                if (reply_to > 0)
                  `task_send(reply_to, ["type" -> "response", "response" -> response]) ! ANY';
                endif
              endfor
              "Show token usage to poke player";
              if (length(pokes) > 0)
                poke_player = `pokes[1]["player"] ! ANY => #-1';
                if (valid(poke_player))
                  `this:_show_token_usage(poke_player) ! ANY';
                endif
              endif
              "Clear observation messages from context";
              ctx = this.agent.context;
              new_ctx = {};
              for msg in (ctx)
                role = `msg["role"] ! ANY => ""';
                content = `msg["content"] ! ANY => ""';
                if (!(role == "user" && typeof(content) == TYPE_STR && content:starts_with("OBSERVATION:")))
                  new_ctx = {@new_ctx, msg};
                endif
              endfor
              this.agent.context = new_ctx;
              this.responding = false;
              commit();
            endif
          endif
        except loop_error (ANY)
          "Catch-all: ensure responding is cleared on any unexpected error";
          `this:_stop_thinking() ! ANY';
          this.responding = false;
          commit();
          this:_handle_agent_error("event_loop/outer", loop_error);
        endtry
      endif
    endwhile
    "Loop exiting - clean up";
    this.loop_task = 0;
    this.responding = false;
    commit();
  endverb

  verb _start_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Fork the event loop task and store its ID.";
    "Stop any existing loop first to prevent duplicates";
    lt = this.loop_task;
    this.loop_task = 0;
    this.responding = false;
    if (lt > 0)
      `kill_task(lt) ! ANY';
    endif
    fork task_id (0)
      set_task_perms(this.owner);
      this:_event_loop();
    endfork
    this.loop_task = task_id;
    commit();
  endverb

  verb _stop_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Kill the event loop task if running.";
    lt = this.loop_task;
    this.loop_task = 0;
    this.responding = false;
    if (lt > 0)
      `kill_task(lt) ! ANY';
    endif
  endverb

  verb _ensure_loop (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Start the event loop if not already running.";
    if (this.loop_task <= 0)
      this:_start_loop();
    endif
  endverb
endobject