object WIZ
  name: "Generic Wizard"
  parent: PROG
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD

  property test (owner: WIZ, flags: "r") = {};

  override description = "You see a player who has has administrative powers but is too lazy to set their description.";
  override import_export_id = "wiz";

  verb "@programmer" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "Grant programmer bit to a player";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can grant programmer privileges.");
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @programmer <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    if (dobj.programmer)
      player:inform_current($event:mk_error(player, dobj:name() + " is already a programmer."));
      return;
    endif
    "Check if player has a description";
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
    "Grant programmer bit and reparent to $prog";
    dobj.programmer = true;
    chparent(dobj, $prog);
    "Create personal tools for the new programmer";
    owner_name = dobj:name();
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
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted programmer privileges and ", $sub:verb_have(), " been reparented to $prog."):with_this(dobj.location);
      dobj.location:announce(event);
      "Announce tools being granted";
      tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass and a Data Visor."):with_this(dobj.location);
      dobj.location:announce(tools_event);
    endif
    "Send private instructional message to new programmer";
    dobj:tell($event:mk_info(dobj, "In your inventory there are now an Architect's Compass and a Data Visor - powerful instruments bonded to you alone. Wear them to activate their capabilities: the Compass for building and spatial construction, the Visor for analyzing, writing code, creating objects, adding properties, and shaping the world's logic. Guard them carefully, as they grant significant power over the world."));
    "Confirm to wizard";
    player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " programmer privileges and reparented them to $prog."));
  endverb

  verb "@builder" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "Grant builder status to a player";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can grant builder status.");
    if (!valid(dobj))
      raise(E_INVARG, "Usage: @builder <player>");
    endif
    if (!is_player(dobj))
      raise(E_INVARG, tostr(dobj) + " is not a player.");
    endif
    if ($builder_features in dobj.wizard_granted_features)
      player:inform_current($event:mk_error(player, dobj:name() + " already has builder features."));
      return;
    endif
    "Check if player has a description";
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
    "Grant builder features";
    dobj.wizard_granted_features = {@dobj.wizard_granted_features, $builder_features};
    dobj.is_builder = true;
    "Create personal compass for the new builder";
    owner_name = dobj:name();
    compass = create($architects_compass, dobj);
    compass.owner = dobj;
    compass.name = owner_name + "'s " + $architects_compass.name;
    compass.aliases = $architects_compass.aliases;
    compass:moveto(dobj);
    "Announce to room";
    if (valid(dobj.location))
      event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted builder privileges."):with_this(dobj.location);
      dobj.location:announce(event);
      "Announce tool being granted";
      tools_event = $event:mk_info(dobj, $sub:nc(), " ", $sub:verb_have(), " been granted an Architect's Compass."):with_this(dobj.location);
      dobj.location:announce(tools_event);
    endif
    "Send private instructional message to new builder";
    dobj:tell($event:mk_info(dobj, "In your inventory there is now an Architect's Compass - a powerful instrument bonded to you alone. Wear it to activate its capabilities for building and spatial construction. Guard it carefully, as it grants significant power over the world."));
    "Confirm to wizard";
    player:inform_current($event:mk_info(player, "You granted ", dobj:name(), " builder privileges."));
  endverb

  verb "@reconfigure-tools" (none none none) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "Reconfigure all Architect's Compasses and Data Visors in the database";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can reconfigure tools.");
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

  verb "@llm-budget" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "View a player's LLM token budget and usage";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can view LLM budgets.");
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

  verb "@llm-set-budget" (any at any) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "Set a player's LLM token budget";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can set LLM budgets.");
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

  verb "@llm-reset-usage" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this && this.wizard || raise(E_PERM);
    "Reset a player's LLM token usage counter";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can reset LLM usage.");
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
    caller == this && this.wizard || raise(E_PERM);
    "Destroy all existing visors and compasses, then reissue them to all programmers and builders";
    set_task_perms(this);
    player.wizard || raise(E_PERM, "Only wizards can reissue tools.");
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
      if (valid(p) && `p.is_builder ! ANY => false')
        compass_recipients = {@compass_recipients, p};
      endif
    endfor
    "All players with programmer flag get visor";
    visor_recipients = {};
    for p in (players())
      if (valid(p) && `p.programmer ! ANY => false')
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
endobject