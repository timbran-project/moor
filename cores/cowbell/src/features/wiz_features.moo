object WIZ_FEATURES
  name: "Wizard Features"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Provides wizard-only administrative verbs (@programmer, @builder, @llm-*, etc.) for wizards.";
  override import_export_hierarchy = {"features"};
  override import_export_id = "wiz_features";

  verb "@announce" (any none none) owner: ARCH_WIZARD flags: "rd"
    "Broadcast a message to all connected players.";
    this:_challenge_command_perms();
    set_task_perms(player);
    msg = argstr;
    if (!msg || msg == "")
      player:inform_current($event:mk_error(player, "Usage: @announce <message>"):with_audience('utility));
      return;
    endif
    msg = "“" + msg + "”";
    title = $format.title:mk("Announcement from " + player:name());
    content = $format.block:mk(title, msg);
    event = $event:mk_info(player, content):with_audience('utility):with_presentation_hint('inset);
    for p in (connected_players())
      `p:tell(event) ! E_VERBNF => p:tell(event)';
    endfor
    player:inform_current($event:mk_info(player, "Announcement sent to " + tostr(length(connected_players())) + " connection(s)."):with_audience('utility));
  endverb

  verb "@programmer" (any none none) owner: ARCH_WIZARD flags: "d"
    "Grant or upgrade a player to programmer status";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @programmer <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    "Check current status";
    if (dobj.authoring_features == $prog_features)
      player:inform_current($event:mk_error(player, dobj:name() + " is already a programmer."));
      return;
    endif
    is_upgrade = dobj.authoring_features == $builder_features;
    "Check if player has a description (skip for upgrades)";
    if (!is_upgrade)
      desc = `dobj:description() ! ANY => ""';
      if (!desc || desc == "")
        "Get pronouns for proper grammar";
        pronouns = `dobj:pronouns() ! E_VERBNF => $pronouns:mk('they, 'them, 'their, 'theirs, 'themself, false)';
        possessive = `pronouns.possessive ! ANY => "their"';
        question = "Grant " + dobj:name() + " programmer bit despite " + possessive + " lack of description?";
        "Use yes_no for confirmation";
        metadata = {{"input_type", "yes_no"}, {"prompt", question}};
        response = player:read_with_prompt(metadata);
        if (response != "yes")
          player:inform_current($event:mk_error(player, "Programmer bit not granted."));
          return;
        endif
      endif
    endif
    "Set features and flags";
    dobj.authoring_features = $prog_features;
    dobj.programmer = true;
    dobj.is_builder = true;
    "Handle tools";
    owner_name = dobj:name();
    if (is_upgrade)
      "Already has compass from builder, just add visor";
      visor = create($data_visor, dobj);
      visor.owner = dobj;
      visor.name = owner_name + "'s " + $data_visor.name;
      visor.aliases = $data_visor.aliases;
      visor:moveto(dobj);
      "Announce upgrade";
      if (valid(dobj.location))
        event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been upgraded to programmer privileges."):with_this(dobj.location);
        dobj.location:announce(event);
        tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted a Data Visor."):with_this(dobj.location);
        dobj.location:announce(tools_event);
      endif
      dobj:tell($event:mk_info(dobj, "You have been upgraded to programmer. A Data Visor has been added to your inventory for code editing and advanced features."));
      player:inform_current($event:mk_info(player, "You upgraded ", dobj:name(), " to programmer privileges."));
    else
      "Fresh grant - create both tools";
      compass = create($architects_compass, dobj);
      compass.owner = dobj;
      compass.name = owner_name + "'s " + $architects_compass.name;
      compass.aliases = $architects_compass.aliases;
      compass:moveto(dobj);
      visor = create($data_visor, dobj);
      visor.owner = dobj;
      visor.name = owner_name + "'s " + $data_visor.name;
      visor.aliases = $data_visor.aliases;
      visor:moveto(dobj);
      "Announce fresh grant";
      if (valid(dobj.location))
        event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted programmer and builder privileges."):with_this(dobj.location);
        dobj.location:announce(event);
        tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass and a Data Visor."):with_this(dobj.location);
        dobj.location:announce(tools_event);
      endif
      dobj:tell($event:mk_info(dobj, "In your inventory there are now an Architect's Compass and a Data Visor - powerful instruments bonded to you alone. Wear them to activate their capabilities: the Compass for building and spatial construction, the Visor for analyzing, writing code, creating objects, adding properties, and shaping the world's logic. Guard them carefully, as they grant significant power over the world."));
      player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " programmer and builder privileges."));
    endif
  endverb

  verb "@builder" (any none none) owner: ARCH_WIZARD flags: "d"
    "Grant builder status or downgrade from programmer";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @builder <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    "Check current status";
    if (dobj.authoring_features == $builder_features)
      player:inform_current($event:mk_error(player, dobj:name() + " is already a builder."));
      return;
    endif
    is_downgrade = dobj.authoring_features == $prog_features;
    "Confirm downgrade if necessary";
    if (is_downgrade)
      question = "Downgrade " + dobj:name() + " from programmer to builder? This will remove their Data Visor and programmer flag.";
      metadata = {{"input_type", "yes_no"}, {"prompt", question}};
      response = player:read_with_prompt(metadata);
      if (response != "yes")
        player:inform_current($event:mk_error(player, "Downgrade cancelled."));
        return;
      endif
    endif
    "Check if player has a description (skip for downgrades)";
    if (!is_downgrade)
      desc = `dobj:description() ! ANY => ""';
      if (!desc || desc == "")
        "Get pronouns for proper grammar";
        pronouns = `dobj:pronouns() ! E_VERBNF => $pronouns:mk('they, 'them, 'their, 'theirs, 'themself, false)';
        possessive = `pronouns.possessive ! ANY => "their"';
        question = "Grant " + dobj:name() + " builder status despite " + possessive + " lack of description?";
        "Use yes_no for confirmation";
        metadata = {{"input_type", "yes_no"}, {"prompt", question}};
        response = player:read_with_prompt(metadata);
        if (response != "yes")
          player:inform_current($event:mk_error(player, "Builder status not granted."));
          return;
        endif
      endif
    endif
    "Set features and flags";
    dobj.authoring_features = $builder_features;
    dobj.is_builder = true;
    "Handle tools and flags";
    owner_name = dobj:name();
    if (is_downgrade)
      "Remove programmer flag and visor";
      dobj.programmer = false;
      "Find and destroy visor";
      for item in (dobj.contents)
        if (valid(item) && isa(item, $data_visor))
          item:destroy();
          break;
        endif
      endfor
      "Announce downgrade";
      if (valid(dobj.location))
        event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been downgraded to builder privileges."):with_this(dobj.location);
        dobj.location:announce(event);
      endif
      dobj:tell($event:mk_info(dobj, "You have been downgraded to builder. Your Data Visor has been removed, but you retain your Architect's Compass."));
      player:inform_current($event:mk_info(player, "You downgraded ", dobj:name(), " to builder privileges."));
    else
      "Fresh grant - create compass";
      compass = create($architects_compass, dobj);
      compass.owner = dobj;
      compass.name = owner_name + "'s " + $architects_compass.name;
      compass.aliases = $architects_compass.aliases;
      compass:moveto(dobj);
      "Announce fresh grant";
      if (valid(dobj.location))
        event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted builder privileges."):with_this(dobj.location);
        dobj.location:announce(event);
        tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass."):with_this(dobj.location);
        dobj.location:announce(tools_event);
      endif
      dobj:tell($event:mk_info(dobj, "In your inventory there is now an Architect's Compass - a powerful instrument bonded to you alone. Wear it to activate its capabilities for building and spatial construction. Guard it carefully, as it grants significant power over the world."));
      player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " builder privileges."));
    endif
  endverb

  verb "@reconfigure-tools" (none none none) owner: ARCH_WIZARD flags: "d"
    "Reconfigure all Architect's Compasses and Data Visors in the database";
    this:_challenge_command_perms();
    set_task_perms(player);
    "Find all compasses and visors";
    compasses = {};
    visors = {};
    for o in (descendants($architects_compass))
      if (valid(o) && o != $architects_compass)
        compasses = {@compasses, o};
      endif
    endfor
    for obj in (descendants($data_visor))
      if (valid(o) && o != $data_visor)
        visors = {@visors, o};
      endif
    endfor
    total = length(compasses) + length(visors);
    if (total == 0)
      player:inform_current($event:mk_info(player, "No tool instances found to reconfigure."));
      return;
    endif
    "Confirm before proceeding";
    question = "Reconfigure " + tostr(length(compasses)) + " compass(es) and " + tostr(length(visors)) + " visor(s)?";
    metadata = {{"input_type", "yes_no"}, {"prompt", question}};
    response = player:read_with_prompt(metadata);
    if (response != "yes")
      player:inform_current($event:mk_error(player, "Reconfiguration cancelled."));
      return;
    endif
    "Reconfigure all compasses";
    compass_count = 0;
    for compass in (compasses)
      try
        compass:reconfigure();
        compass_count = compass_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to reconfigure " + tostr(compass) + ": " + toliteral(e)));
      endtry
    endfor
    "Reconfigure all visors";
    visor_count = 0;
    for visor in (visors)
      try
        visor:reconfigure();
        visor_count = visor_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to reconfigure " + tostr(visor) + ": " + toliteral(e)));
      endtry
    endfor
    "Report results";
    player:inform_current($event:mk_info(player, "Reconfigured " + tostr(compass_count) + " compass(es) and " + tostr(visor_count) + " visor(s)."));
  endverb

  verb "@shutdown" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Dump the database, announce, and shut down the server with countdown.";
    this:_challenge_command_perms();
    set_task_perms(player);
    msg = argstr;
    !msg && (msg = "Server is shutting down.");
    "Parse optional delay: \"in N <message>\" minutes; default 2 minutes";
    delay_minutes = 2;
    parts = msg:split(" ");
    if (length(parts) >= 2 && parts[1] == "in")
      possible_delay = `toint(parts[2]) ! ANY => -1';
      if (typeof(possible_delay) == INT && possible_delay > 0)
        delay_minutes = possible_delay;
        remaining = length(parts) >= 3 ? parts[3..$] | {};
        msg = remaining ? remaining:join(" ") | "Server is shutting down.";
      endif
    endif
    "Confirm shutdown";
    question = "Shut down the server in " + tostr(delay_minutes) + " minute(s)?";
    metadata = {{"input_type", "yes_no"}, {"prompt", question}};
    response = player:read_with_prompt(metadata);
    if (response != "yes")
      player:inform_current($event:mk_error(player, "Shutdown cancelled."):with_audience('utility));
      return;
    endif
    "Build countdown schedule (seconds)";
    announce_times = {};
    delay = delay_minutes;
    if (delay > 0)
      while (delay > 0)
        announce_times = {@announce_times, delay * 60};
        delay = delay / 2;
      endwhile
      announce_times = {@announce_times, 30, 10};
    else
      announce_times = {0};
    endif
    "Send announcements and countdown";
    for i in [1..length(announce_times)]
      seconds = announce_times[i];
      base_msg = $format.code:mk("** Server will shut down in " + tostr(seconds) + " second(s): " + msg + " **");
      event = $event:mk_info(player, $format.title:mk("Shutdown ..."), base_msg):with_audience('utility):with_presentation_hint('inset);
      for p in (connected_players())
        `p:tell(event) ! E_VERBNF => p:tell(event)';
      endfor
      next_delay = i < length(announce_times) ? announce_times[i] - announce_times[i + 1] | 0;
      next_delay > 0 && suspend(next_delay);
    endfor
    "Final message and boot everyone";
    final_msg = $format.code:mk("## Server shutdown: " + msg + " ##");
    final_event = $event:mk_info(player, final_msg):with_audience('utility):with_presentation_hint('inset);
    for p in (connected_players())
      `p:tell(final_event) ! E_VERBNF => p:tell(final_event)';
      `boot_player(p) ! ANY';
    endfor
    suspend(0);
    dump_database();
    shutdown(msg);
  endverb

  verb "@llm-budget" (any none none) owner: ARCH_WIZARD flags: "d"
    "View a player's LLM token budget and usage";
    this:_challenge_command_perms();
    set_task_perms(player);
    "Try to resolve target player";
    target = dobj;
    if (!valid(target) && dobjstr)
      target = $match:match_object(dobjstr, player);
    endif
    if (!valid(target))
      raise(E_INVARG, "Usage: @llm-budget <player>");
    endif
    if (!is_player(target))
      raise(E_INVARG, tostr(target) + " is not a player.");
    endif
    "Get budget and usage information";
    budget = `target.llm_token_budget ! ANY => 20000000';
    used = `target.llm_tokens_used ! ANY => 0';
    usage_log = `target.llm_usage_log ! ANY => {}';
    percent_used = used * 100 / budget;
    "Build budget info as table";
    title_obj = $format.title:mk("LLM Token Budget for " + target:name() + " (" + tostr(target) + ")");
    budget_rows = {{"Budget", tostr(budget) + " tokens"}, {"Used", tostr(used) + " tokens"}, {"Remaining", tostr(budget - used) + " tokens"}, {"Usage", tostr(percent_used) + "%"}};
    budget_table = $format.table:mk({"Property", "Value"}, budget_rows);
    "Build content blocks";
    content_blocks = {title_obj, budget_table};
    "Add usage log if available";
    if (length(usage_log) > 0)
      usage_rows = {};
      start_idx = length(usage_log) > 5 ? length(usage_log) - 4 | 1;
      for i in [start_idx..length(usage_log)]
        entry = usage_log[i];
        timestamp = `entry["timestamp"] ! ANY => 0';
        tokens = `entry["tokens"] ! ANY => 0';
        time_str = ctime(timestamp);
        usage_rows = {@usage_rows, {time_str, tostr(tokens) + " tokens"}};
      endfor
      usage_title = $format.title:mk("Recent usage (last 5 calls)");
      usage_table = $format.table:mk({"Time", "Tokens"}, usage_rows);
      content_blocks = {@content_blocks, usage_title, usage_table};
    endif
    "Send formatted output";
    content = $format.block:mk(@content_blocks);
    player:inform_current($event:mk_info(player, content):with_audience('utility));
  endverb

  verb "@llm-set-budget" (any at any) owner: ARCH_WIZARD flags: "d"
    "Set a player's LLM token budget";
    this:_challenge_command_perms();
    set_task_perms(player);
    "Try to resolve target player";
    target = dobj;
    if (!valid(target) && dobjstr)
      target = $match:match_object(dobjstr, player);
    endif
    if (!valid(target))
      raise(E_INVARG, "Usage: @llm-set-budget <player> to <budget>");
    endif
    if (!is_player(target))
      raise(E_INVARG, tostr(target) + " is not a player.");
    endif
    if (!iobjstr)
      raise(E_INVARG, "Usage: @llm-set-budget <player> to <budget>");
    endif
    "Parse budget value";
    new_budget = tonum(iobjstr);
    typeof(new_budget) == INT || raise(E_INVARG, "Budget must be a number.");
    new_budget > 0 || raise(E_INVARG, "Budget must be positive.");
    "Get current values for confirmation";
    old_budget = `target.llm_token_budget ! ANY => 20000000';
    used = `target.llm_tokens_used ! ANY => 0';
    "Confirm the change";
    question = "Set " + target:name() + "'s LLM token budget to " + tostr(new_budget) + " (currently " + tostr(old_budget) + ", " + tostr(used) + " used)?";
    metadata = {{"input_type", "yes_no"}, {"prompt", question}};
    response = player:read_with_prompt(metadata);
    if (response != "yes")
      player:inform_current($event:mk_error(player, "Budget change cancelled."));
      return;
    endif
    "Set the new budget";
    target.llm_token_budget = new_budget;
    player:inform_current($event:mk_info(player, "Set " + target:name() + "'s LLM token budget to " + tostr(new_budget) + " tokens."));
  endverb

  verb "@llm-reset-usage" (any none none) owner: ARCH_WIZARD flags: "d"
    "Reset a player's LLM token usage counter";
    this:_challenge_command_perms();
    set_task_perms(player);
    "Try to resolve target player";
    target = dobj;
    if (!valid(target) && dobjstr)
      target = $match:match_object(dobjstr, player);
    endif
    if (!valid(target))
      raise(E_INVARG, "Usage: @llm-reset-usage <player>");
    endif
    if (!is_player(target))
      raise(E_INVARG, tostr(target) + " is not a player.");
    endif
    "Get current usage for confirmation";
    used = `target.llm_tokens_used ! ANY => 0';
    budget = `target.llm_token_budget ! ANY => 20000000';
    "Confirm the reset";
    question = "Reset " + target:name() + "'s LLM token usage from " + tostr(used) + " to 0 (budget: " + tostr(budget) + ")?";
    metadata = {{"input_type", "yes_no"}, {"prompt", question}};
    response = player:read_with_prompt(metadata);
    if (response != "yes")
      player:inform_current($event:mk_error(player, "Usage reset cancelled."));
      return;
    endif
    "Reset usage and clear log";
    target.llm_tokens_used = 0;
    target.llm_usage_log = {};
    player:inform_current($event:mk_info(player, "Reset " + target:name() + "'s LLM token usage to 0 and cleared usage log."));
  endverb

  verb "@reissue-tools" (none none none) owner: ARCH_WIZARD flags: "rd"
    this:_challenge_command_perms();
    player.wizard || raise(E_PERM, "Only wizards can reissue tools.");
    "Destroy all existing visors and compasses, then reissue them to all programmers and builders";
    set_task_perms(player);
    "Find all existing compasses and visors";
    compasses = {};
    visors = {};
    for o in (descendants($architects_compass))
      if (valid(o) && o != $architects_compass)
        compasses = {@compasses, o};
      endif
    endfor
    for o in (descendants($data_visor))
      if (valid(o) && o != $data_visor)
        visors = {@visors, o};
      endif
    endfor
    "Find all players who need tools";
    "All players with is_builder flag get compass";
    compass_recipients = {};
    for p in (players())
      if (valid(p) && `p.is_builder ! ANY => false' && p != $hacker)
        compass_recipients = {@compass_recipients, p};
      endif
    endfor
    "All players with programmer flag get visor";
    visor_recipients = {};
    for p in (players())
      if (valid(p) && `p.programmer ! ANY => false' && p != $hacker)
        visor_recipients = {@visor_recipients, p};
      endif
    endfor
    total_destroy = length(compasses) + length(visors);
    total_issue = length(compass_recipients) + length(visor_recipients);
    "Confirm before proceeding";
    question = "Destroy " + tostr(length(compasses)) + " compass(es) and " + tostr(length(visors)) + " visor(s), then reissue " + tostr(length(compass_recipients)) + " compass(es) and " + tostr(length(visor_recipients)) + " visor(s)?";
    metadata = {{"input_type", "yes_no"}, {"prompt", question}};
    response = player:read_with_prompt(metadata);
    if (response != "yes")
      player:inform_current($event:mk_error(player, "Tool reissue cancelled."));
      return;
    endif
    "Destroy all existing tools";
    compass_count = 0;
    for compass in (compasses)
      try
        compass:destroy();
        compass_count = compass_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to destroy " + tostr(compass) + ": " + toliteral(e)));
      endtry
    endfor
    visor_count = 0;
    for visor in (visors)
      try
        visor:destroy();
        visor_count = visor_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to destroy " + tostr(visor) + ": " + toliteral(e)));
      endtry
    endfor
    player:inform_current($event:mk_info(player, "Destroyed " + tostr(compass_count) + " compass(es) and " + tostr(visor_count) + " visor(s)."));
    "Issue compasses to all builders/programmers/wizards";
    compass_count = 0;
    for recipient in (compass_recipients)
      try
        owner_name = recipient:name();
        compass = create($architects_compass, recipient);
        compass.owner = recipient;
        compass.name = owner_name + "'s " + $architects_compass.name;
        compass.aliases = $architects_compass.aliases;
        compass:moveto(recipient);
        compass_count = compass_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to issue compass to " + tostr(recipient) + ": " + toliteral(e)));
      endtry
    endfor
    "Issue visors to all programmers/wizards";
    visor_count = 0;
    for recipient in (visor_recipients)
      try
        owner_name = recipient:name();
        visor = create($data_visor, recipient);
        visor.owner = recipient;
        visor.name = owner_name + "'s " + $data_visor.name;
        visor.aliases = $data_visor.aliases;
        visor:moveto(recipient);
        visor_count = visor_count + 1;
      except e (ANY)
        player:inform_current($event:mk_error(player, "Failed to issue visor to " + tostr(recipient) + ": " + toliteral(e)));
      endtry
    endfor
    "Report results";
    player:inform_current($event:mk_info(player, "Issued " + tostr(compass_count) + " compass(es) and " + tostr(visor_count) + " visor(s)."));
  endverb

  verb "@chown" (any at any) owner: ARCH_WIZARD flags: "rd"
    "Change ownership of objects, properties, or verbs";
    "Usage: @chown <object> to <new_owner>";
    "Usage: @chown <object>.<property> to <new_owner>";
    "Usage: @chown <object>:<verb> to <new_owner>";
    this:_challenge_command_perms();
    set_task_perms(player);
    if (!dobjstr || !iobjstr)
      player:inform_current($event:mk_error(player, $format.code:mk("@chown TARGET to NEW_OWNER")));
      return;
    endif
    target_spec = dobjstr:trim();
    owner_str = iobjstr:trim();
    "Match the new owner";
    try
      new_owner = $match:match_object(owner_str, player);
      typeof(new_owner) != OBJ && raise(E_INVARG, "Owner must be an object.");
      !valid(new_owner) && raise(E_INVARG, "Owner object no longer exists.");
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find owner: " + e[2]));
      return;
    endtry
    "Parse the target specification";
    parsed = $prog_utils:parse_target_spec(target_spec);
    if (!parsed)
      player:inform_current($event:mk_error(player, "Invalid target reference. Use 'object', 'object.property', or 'object:verb'"));
      return;
    endif
    type = parsed['type];
    object_str = parsed['object_str];
    item_name = parsed['item_name];
    "Match the target object";
    try
      target_obj = $match:match_object(object_str, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "Could not find object: " + e[2]));
      return;
    endtry
    "Dispatch based on type";
    if (type == 'property)
      try
        metadata = $prog_utils:get_property_metadata(target_obj, item_name);
        current_perms = metadata:perms();
        metadata:set_perms(new_owner, current_perms);
        player:inform_current($event:mk_info(player, "Property ." + item_name + " on " + tostr(target_obj) + " now owned by " + tostr(new_owner) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error changing property owner: " + e[2]));
      endtry
    elseif (type == 'verb)
      try
        metadata = $prog_utils:get_verb_metadata(target_obj, item_name);
        current_perms = metadata:flags();
        metadata:set_perms(new_owner, current_perms);
        player:inform_current($event:mk_info(player, "Verb :" + item_name + " on " + tostr(target_obj) + " now owned by " + tostr(new_owner) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error changing verb owner: " + e[2]));
      endtry
    elseif (type == 'object)
      try
        target_obj.owner = new_owner;
        player:inform_current($event:mk_info(player, "Object " + tostr(target_obj) + " now owned by " + tostr(new_owner) + "."));
      except e (ANY)
        player:inform_current($event:mk_error(player, "Error changing object owner: " + e[2]));
      endtry
    else
      "Inherited references not supported for @chown";
      player:inform_current($event:mk_error(player, "@chown only works on direct object properties and verbs, not inherited ones."));
    endif
  endverb

  verb _challenge_command_perms (this none this) owner: HACKER flags: "xd"
    player.programmer && player.wizard || raise(E_PERM);
  endverb
endobject
