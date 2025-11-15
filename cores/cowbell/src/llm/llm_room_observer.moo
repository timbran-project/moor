object LLM_ROOM_OBSERVER
  name: "LLM Room Observer"
  parent: ACTOR
  owner: HACKER
  fertile: true
  readable: true

  property agent (owner: HACKER, flags: "rc") = #-1;
  property observation_mechanics_prompt (owner: HACKER, flags: "rc") = "You are observing events in a virtual room. Events are delivered to you as MOO flyweight structures in the form OBSERVATION: <delegate, .field1 = value, .field2 = value>. Extract the relevant information from these structured events and use them to understand what's happening.";
  property response_prompt (owner: HACKER, flags: "rc") = "Based on what you've observed, say something witty or insightful to the room.";
  property role_prompt (owner: HACKER, flags: "rc") = "When asked, provide witty or insightful commentary based on what you've seen.";
  property significant_events (owner: HACKER, flags: "rc") = {};

  override description = "Room-observing bot powered by an LLM agent. Watches room events and responds when poked.";
  override import_export_hierarchy = {"llm"};
  override import_export_id = "llm_room_observer";

  verb configure (this none this) owner: HACKER flags: "rxd"
    "Create agent and apply configuration. Children override _setup_agent to customize.";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    "Create the agent";
    this.agent = $llm_agent:create();
    "Set agent owner to observer owner so they can write to agent properties";
    this.agent.owner = this.owner;
    "Let child class configure it";
    this:_setup_agent(this.agent);
  endverb

  verb _setup_agent (this none this) owner: HACKER flags: "rxd"
    "Configure agent with room observer prompts. Override in children to add tools.";
    {agent} = args;
    "Combine base observation mechanics with specific role";
    agent.system_prompt = this.observation_mechanics_prompt + " " + this.role_prompt;
    agent:initialize();
  endverb

  verb reconfigure (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Reconfigure by cleaning up old agent and creating a fresh one";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    set_task_perms(caller_perms());
    "Recycle old agent if it exists";
    if (valid(this.agent))
      recycle(this.agent);
      this.agent = #-1;
    endif
    "Create fresh agent with current configuration";
    this:configure();
  endverb

  verb tell (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Receive events from room and pass to agent as observations";
    set_task_perms(this.owner);
    if (typeof(this.agent) != OBJ || !valid(this.agent))
      this:configure();
    endif
    {event} = args;
    "Pass event structure as literal for LLM to parse";
    observation = toliteral(event);
    this.agent:add_message("user", "OBSERVATION: " + observation);
    "Trigger maybe_speak if this event type is significant";
    if (length(this.significant_events) > 0)
      event_verb = `event.verb ! ANY => ""';
      event_actor = `event.actor ! ANY => #-1';
      "Don't trigger on our own events to avoid feedback loop";
      if (event_verb in this.significant_events && event_actor != this)
        fork (1)
          this:maybe_speak();
        endfork
      endif
    endif
  endverb

  verb poke (this none none) owner: ARCH_WIZARD flags: "rd"
    "Trigger the observer to respond based on accumulated observations";
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
    "Set token owner for budget tracking";
    this.agent.token_owner = player;
    "Get LLM response";
    response = this.agent:send_message(this.response_prompt);
    "Show token usage to player";
    this:_show_token_usage(player);
    "Announce response to room";
    if (valid(this.location))
      say_event = $event:mk_say(this, this:name(), " says, \"", response, "\"");
      this.location:announce(say_event);
    else
      player:inform_current($event:mk_info(player, response));
    endif
  endverb

  verb maybe_speak (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Evaluate recent observations and speak only if something noteworthy happened";
    if (!valid(this.agent))
      this:configure();
    endif
    if (length(this.agent.context) <= 1)
      return;
    endif
    "Ask LLM to evaluate if it should speak";
    prompt = "Review recent observations. If something noteworthy happened (someone arrived, left, asked a question, or something unusual occurred), respond with 'SPEAK: ' followed by a brief, friendly comment (1-2 sentences). If nothing warrants comment, respond with only 'SILENT'.";
    response = this.agent:send_message(prompt);
    "Check if LLM decided to speak";
    if (typeof(response) == STR && response:starts_with("SPEAK: "))
      actual_response = response[8..$];
      if (valid(this.location))
        say_event = $event:mk_say(this, this:name(), " says, \"", actual_response, "\"");
        this.location:announce(say_event);
      endif
    endif
    "Otherwise stay silent";
  endverb

  verb reset (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clear the agent's observation history with descriptive narrative";
    caller == this || caller == this.owner || caller.wizard || raise(E_PERM);
    set_task_perms(caller_perms());
    !caller.location || return E_INVARG;
    if (valid(this.agent))
      this.agent:reset_context();
    endif
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
    set_task_perms(caller_perms());
    budget = `user.llm_token_budget ! ANY => 20000000';
    used = `user.llm_tokens_used ! ANY => 0';
    last_usage = this.agent.last_token_usage;
    if (typeof(last_usage) == MAP && maphaskey(last_usage, "total_tokens"))
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
      user:inform_current($event:mk_info(user, usage_msg):with_presentation_hint('inset));
    endif
  endverb

  verb "@reset" (this none none) owner: ARCH_WIZARD flags: "rx"
    if (!player.wizard && player != this.owner)
      player:inform_current($event:mk_error(player, "You can't do that."));
      return;
    endif
    reset_event = $event:mk_emote(player, player:name(), " reaches behind ", this:name(), "'s head and flips a formerly unseen switch...");
    caller.location:announce(reset_event);
    this:reset();
  endverb
endobject