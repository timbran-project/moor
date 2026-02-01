object ROOM
  name: "Generic Room"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property acoustic_neighbors (owner: ARCH_WIZARD, flags: "rc") = [];
  property engagements (owner: ARCH_WIZARD, flags: "rc") = [];

  override description = "Parent prototype for all rooms in the system, defining room behavior and event broadcasting.";
  override import_export_hierarchy = {"world"};
  override import_export_id = "room";

  verb initialize (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set sensible defaults for newly created rooms.";
    pass();
    set_task_perms(caller_perms());
    this.description = "An empty room awaiting a description.";
    this.import_export_hierarchy = {"rooms"};
  endverb

  verb emote (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_emote_event(argstr));
  endverb

  verb say (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_say_event(argstr));
  endverb

  verb "`* to" (any any any) owner: HACKER flags: "rd"
    "Directed say - say something to a specific person";
    "Usage: `target message  OR  to target message";
    if (verb[1] == "`")
      "Backtick syntax: target is in verb[2..]";
      if (length(verb) < 2)
        player:inform_current($event:mk_error(player, "Usage: `target message"));
        return;
      endif
      target_name = verb[2..length(verb)];
      message = argstr;
    else
      "to syntax: first word of argstr is target, rest is message";
      if (!argstr)
        player:inform_current($event:mk_error(player, "Usage: to <target> <message>"));
        return;
      endif
      space_idx = index(argstr, " ");
      if (space_idx > 0)
        target_name = argstr[1..space_idx - 1];
        message = argstr[space_idx + 1..$]:trim();
      else
        target_name = argstr;
        message = "";
      endif
    endif
    if (!message)
      player:inform_current($event:mk_error(player, "Say what to ", target_name, "?"));
      return;
    endif
    try
      target = $match:match_object(target_name, player);
    except e (ANY)
      player:inform_current($event:mk_error(player, "I don't see '", target_name, "' here."));
      return;
    endtry
    if (!valid(target) || typeof(target) != TYPE_OBJ)
      player:inform_current($event:mk_error(player, "I don't see '", target_name, "' here."));
      return;
    endif
    "Build the event with source/dest annotations";
    event = player:mk_stagetalk(target, message);
    event = event:with_metadata('source, player);
    event = event:with_metadata('target, target);
    event = event:with_metadata('message, message);
    "Announce to room";
    this:announce(event);
    "Notify target if it implements on_addressed protocol - fork so speech delivers first";
    if (respond_to(target, 'on_addressed))
      fork (0)
        `target:on_addressed(player, message, event) ! ANY';
      endfork
    endif
  endverb

  verb confunc (this none this) owner: HACKER flags: "rxd"
    "Called when a player connects in this room.";
    "Args: who, ?is_new_player, ?should_announce";
    {who, ?is_new_player = false, ?should_announce = true} = args;
    "Only announce if should_announce is true (not a quick reconnect)";
    if (should_announce)
      arrival_event = who:mk_connected_event(is_new_player):with_audience('utility);
      this:announce(arrival_event);
    endif
    "Always show the room to the connecting player";
    look_d = this:look_self();
    who:inform_current(look_d:into_event():with_audience('utility));
  endverb

  verb disfunc (this none this) owner: HACKER flags: "rxd"
    discon_event = player:mk_disconnected_event():with_audience('utility);
    this:announce(discon_event);
  endverb

  verb enterfunc (this none this) owner: HACKER flags: "rxd"
    "Show room description to arriving players";
    {who} = args;
    valid(who) || return;
    if (is_player(who))
      look_d = this:look_self();
      `who:tell(look_d:into_event():with_audience('utility)) ! ANY';
      "Notify objects in the room that a player arrived";
      for thing in (this.contents)
        if (thing != who)
          `thing:on_location_enter(who) ! E_VERBNF => 0';
        endif
      endfor
    endif
    pass(@args);
  endverb

  verb exitfunc (this none this) owner: HACKER flags: "rxd"
    "Notify room contents of departure, then fire parent triggers.";
    {who} = args;
    for item in (this.contents)
      respond_to(item, 'on_location_exit) && `item:on_location_exit(who) ! ANY';
    endfor
    pass(@args);
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "TODO: support locking/unlocking etc";
    return true;
  endverb

  verb match_scope_for (this none this) owner: HACKER flags: "rxd"
    "Expose the room and visible occupants to the command scope.";
    {actor, ?context = []} = args;
    "In case we have a parent that wants to establish initial occupancy, ask it first...";
    entries = `pass(@args) ! E_TYPE, E_VERBNF => {}';
    "Add every visible occupant so they can be matched as direct objects.";
    "Contents come BEFORE the room itself so items match before room name.";
    visible = this:contents();
    for visible_obj in (visible)
      if (!valid(visible_obj))
        continue;
      endif
      entries = {@entries, visible_obj};
    endfor
    "Add the room itself last.";
    entries = {@entries, this};
    return entries;
  endverb

  verb maybe_handle_passage (this none this) owner: HACKER flags: "rxd"
    "Let our location (area) potentially handle passage commands...";
    {parsed} = args;
    if (!valid(this.location) || !respond_to(this.location, 'handle_passage_command))
      return false;
    endif
    return this.location:handle_passage_command(parsed);
  endverb

  verb maybe_handle_command (this none this) owner: HACKER flags: "rxd"
    "Handle any potential commands that the command matcher didn't already handle on the player, for example for furniture or exits";
    {pc} = args;
    return this:maybe_handle_passage(pc);
  endverb

  verb announce (this none this) owner: HACKER flags: "rxd"
    {event} = args;
    "Local announcement";
    for who in (this:contents())
      suspend_if_needed();
      `who:tell(event) ! E_VERBNF';
    endfor
    "Check for acoustic propagation";
    if (typeof(event) != TYPE_FLYWEIGHT)
      return;
    endif
    slots = flyslots(event);
    loudness = maphaskey(slots, 'loudness) ? slots['loudness] | 0;
    propagates = maphaskey(slots, 'propagates) ? slots['propagates] | false;
    if (loudness == 0 && !propagates)
      return;
    endif
    "Propagate to acoustic neighbors";
    neighbors = this.acoustic_neighbors;
    if (typeof(neighbors) != TYPE_LIST || length(neighbors) == 0)
      return;
    endif
    for neighbor_spec in (neighbors)
      if (typeof(neighbor_spec) != TYPE_MAP)
        continue;
      endif
      room = `neighbor_spec['room] ! ANY => $nothing';
      if (!valid(room))
        continue;
      endif
      "Check loudness threshold if specified";
      threshold = `neighbor_spec['threshold] ! ANY => 1';
      if (loudness < threshold && !propagates)
        continue;
      endif
      "Transform the event";
      transformer = `neighbor_spec['transformer] ! ANY => ""';
      if (typeof(transformer) == TYPE_STR && length(transformer) > 0)
        "Custom transformer verb on this room";
        transformed = `this:(transformer)(event, room) ! ANY => 0';
      else
        "Default transformation: use prefix";
        prefix = `neighbor_spec['prefix] ! ANY => "From nearby"';
        transformed = this:_default_distant_transform(event, prefix);
      endif
      if (transformed != 0 && typeof(transformed) == TYPE_FLYWEIGHT)
        `room:announce_distant(transformed, this) ! ANY';
      endif
    endfor
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    "Override look_self to include exit information and actions";
    "Get base look from parent";
    look_data = pass(@args);
    "Add exits if we're in an area with passages";
    area = this.location;
    exits = {};
    ambient_passages = {};
    if (valid(area) && respond_to(area, 'get_exit_info))
      {exits, ambient_passages} = area:get_exit_info(this);
    endif
    "Collect actions from objects in the room";
    actions = {};
    for item in (this.contents)
      item_actions = `item:available_actions() ! E_VERBNF => {}';
      if (typeof(item_actions) == TYPE_LIST && length(item_actions) > 0)
        actions = {@actions, @item_actions};
      endif
    endfor
    "Build updated flyweight if we have exits, passages, or actions";
    if (length(exits) > 0 || length(ambient_passages) > 0 || length(actions) > 0)
      contents_list = flycontents(look_data);
      return <look_data.delegate, .what = look_data.what, .title = look_data.title, .description = look_data.description, .exits = exits, .ambient_passages = ambient_passages, .actions = actions, {@contents_list}>;
    endif
    return look_data;
  endverb

  verb check_can_dig_from (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if caller can dig passages from this room. Wizard, owner, or 'dig_from capability.";
    set_task_perms(caller_perms());
    {this, perms} = this:check_permissions('dig_from);
    return true;
  endverb

  verb check_can_dig_into (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if caller can dig passages into this room. Wizard, owner, or 'dig_into capability.";
    set_task_perms(caller_perms());
    {this, perms} = this:check_permissions('dig_into);
    return true;
  endverb

  verb "exits ways" (none none none) owner: ARCH_WIZARD flags: "rd"
    "List the ways out of this room.";
    "Note: removed set_task_perms(caller_perms()) - it breaks respond_to when caller_perms is #-1";
    "Get exits from our area";
    area = this.location;
    if (!valid(area) || !respond_to(area, 'get_exit_info))
      player:inform_current($event:mk_error(player, "You don't see any obvious ways out."):with_audience('utility));
      return;
    endif
    {exit_lines, ambient_passages} = area:get_exit_info(this);
    "Collect all exit directions - both regular exits and ambient passage labels";
    all_exits = {@exit_lines};
    for ap in (ambient_passages)
      "ambient_passages format: {description, prose_style, label}";
      if (typeof(ap) == TYPE_LIST && length(ap) >= 3)
        label = ap[3];
        if (label && typeof(label) == TYPE_STR)
          all_exits = {@all_exits, label};
        endif
      endif
    endfor
    if (length(all_exits) == 0)
      player:inform_current($event:mk_error(player, "You don't see any obvious ways out."):with_audience('utility));
      return;
    endif
    "Format and display exits with command links using 'go' prefix";
    exit_links = { $format.link:cmd("go " + exit_dir, exit_dir) for exit_dir in (all_exits) };
    exit_list = $format.list:mk(exit_links);
    exit_title = $format.title:mk("Ways out");
    content = $format.block:mk(exit_title, exit_list);
    event = $event:mk_info(player, content):with_audience('utility):with_metadata('preferred_content_types, {'text_html, 'text_plain}):with_presentation_hint('inset):with_group('exits, this);
    player:inform_current(event);
  endverb

  verb action_go (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Action handler: make actor go in a direction from this room.";
    set_task_perms(this.owner);
    {who, context, direction} = args;
    who.location != this && return false;
    "Get the area and find passage for this direction";
    area = this.location;
    !valid(area) && return false;
    !respond_to(area, 'find_passage_by_direction) && return false;
    passage = `area:find_passage_by_direction(this, direction) ! ANY => false';
    !passage && return false;
    "Traverse the passage";
    return `passage:travel_from(who, this, []) ! ANY => false';
  endverb

  verb help_topics (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Rooms don't add extra help topics - exits command handles that.";
    {for_player, ?topic = ""} = args;
    return topic == "" ? {} | 0;
  endverb

  verb recycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clean up passages when room is recycled.";
    area = this.location;
    if (valid(area) && respond_to(area, 'on_room_recycle))
      `area:on_room_recycle(this) ! ANY';
    endif
  endverb

  verb notify_pre_exit (this none this) owner: HACKER flags: "rxd"
    "Notify contents before a player leaves (called by passage before departure message).";
    {who} = args;
    if (valid(who) && is_player(who))
      "Clear any engagement record for this actor.";
      this:disengage_actor(who);
      "Notify contents (furniture, etc.) that someone is leaving.";
      for thing in (this.contents)
        if (thing != who)
          `thing:on_location_exit(who) ! E_VERBNF => 0';
        endif
      endfor
    endif
  endverb

  verb unlock (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Unlock a passage, or defer to an object's unlock verb.";
    "Usage: unlock <direction> [with <key>] OR unlock <object> OR unlock door";
    direction = dobjstr;
    if (!direction || direction == "")
      player:inform_current($event:mk_error(player, "Unlock what?"));
      return;
    endif
    "First check if this matches an object in scope with an unlock verb";
    scope = {@player.contents, @this.contents};
    target = $match:resolve_in_scope(direction, scope);
    if (valid(target) && respond_to(target, 'unlock))
      return target:unlock();
    endif
    "Get the area";
    area = this.location;
    if (!valid(area) || !isa(area, $area))
      player:inform_current($event:mk_error(player, "This room is not in an area."));
      return;
    endif
    "If 'door' was specified, find a door-type passage";
    passage = 0;
    if (direction == "door")
      passages = area:passages_from(this);
      for p in (passages)
        if (p:door_name_for(this) == "door")
          passage = p;
          break;
        endif
      endfor
      if (typeof(passage) != TYPE_FLYWEIGHT)
        player:inform_current($event:mk_error(player, "There's no door here."));
        return;
      endif
    else
      passage = area:find_passage_by_direction(this, direction);
    endif
    if (typeof(passage) != TYPE_FLYWEIGHT)
      player:inform_current($event:mk_error(player, "There's no exit in that direction."));
      return;
    endif
    "Check if it's locked";
    if (!passage:_value("is_locked", false))
      door_name = passage:door_name_for(this);
      msg = "The " + door_name + " is already unlocked.";
      player:inform_current($event:mk_info(player, msg));
      return;
    endif
    "Find a key - either specified or auto-detect from inventory";
    key = #-1;
    to_room = passage:other_room(this);
    if (iobjstr && iobjstr != "")
      key = $match:resolve_in_scope(iobjstr, scope);
      if (!valid(key))
        player:inform_current($event:mk_error(player, "You don't have that."));
        return;
      endif
    else
      "Auto-detect key";
      unlock_rule = passage:_value("unlock_rule", 0);
      if (typeof(unlock_rule) == TYPE_FLYWEIGHT)
        for item in (player.contents)
          bindings = ['Accessor -> player, 'This -> to_room, 'Key -> item, 'Passage -> passage];
          result = $rule_engine:evaluate(unlock_rule, bindings);
          if (typeof(result) == TYPE_MAP && result['success])
            key = item;
            break;
          endif
          bindings = ['Accessor -> player, 'This -> this, 'Key -> item, 'Passage -> passage];
          result = $rule_engine:evaluate(unlock_rule, bindings);
          if (typeof(result) == TYPE_MAP && result['success])
            key = item;
            break;
          endif
        endfor
      endif
    endif
    if (!valid(key))
      player:inform_current($event:mk_error(player, "You don't have a key that fits this lock."));
      return;
    endif
    "Verify the key works";
    unlock_rule = passage:_value("unlock_rule", 0);
    if (typeof(unlock_rule) == TYPE_FLYWEIGHT)
      bindings = ['Accessor -> player, 'This -> to_room, 'Key -> key, 'Passage -> passage];
      result = $rule_engine:evaluate(unlock_rule, bindings);
      if (typeof(result) != TYPE_MAP || !result['success])
        bindings = ['Accessor -> player, 'This -> this, 'Key -> key, 'Passage -> passage];
        result = $rule_engine:evaluate(unlock_rule, bindings);
        if (typeof(result) != TYPE_MAP || !result['success])
          player:inform_current($event:mk_error(player, "That key doesn't fit this lock."));
          return;
        endif
      endif
    endif
    "Unlock the passage";
    new_passage = passage:with_locked(false);
    area:update_passage(this, to_room, new_passage);
    door_name = passage:door_name_for(this);
    unlock_msg = new_passage:_value("unlock_msg", 0);
    if (unlock_msg)
      player:inform_current($event:mk_info(player, unlock_msg));
    else
      msg = "You unlock the " + door_name + ".";
      player:inform_current($event:mk_info(player, msg));
    endif
    "Announce to room";
    announce_msg = player.name + " unlocks the " + door_name + ".";
    event = $event:mk_narrative(player, announce_msg);
    this:announce(event);
  endverb

  verb lock (any any any) owner: ARCH_WIZARD flags: "rxd"
    "Lock a passage, or defer to an object's lock verb.";
    "Usage: lock <direction> [with <key>] OR lock <object> OR lock door";
    direction = dobjstr;
    if (!direction || direction == "")
      player:inform_current($event:mk_error(player, "Lock what?"));
      return;
    endif
    "First check if this matches an object in scope with a lock verb";
    scope = {@player.contents, @this.contents};
    target = $match:resolve_in_scope(direction, scope);
    if (valid(target) && respond_to(target, 'lock))
      return target:lock();
    endif
    "Get the area";
    area = this.location;
    if (!valid(area) || !isa(area, $area))
      player:inform_current($event:mk_error(player, "This room is not in an area."));
      return;
    endif
    "If 'door' was specified, find a door-type passage";
    passage = 0;
    if (direction == "door")
      passages = area:passages_from(this);
      for p in (passages)
        if (p:door_name_for(this) == "door")
          passage = p;
          break;
        endif
      endfor
      if (typeof(passage) != TYPE_FLYWEIGHT)
        player:inform_current($event:mk_error(player, "There's no door here."));
        return;
      endif
    else
      passage = area:find_passage_by_direction(this, direction);
    endif
    if (typeof(passage) != TYPE_FLYWEIGHT)
      player:inform_current($event:mk_error(player, "There's no exit in that direction."));
      return;
    endif
    "Check if it's already locked";
    if (passage:_value("is_locked", false))
      door_name = passage:door_name_for(this);
      msg = "The " + door_name + " is already locked.";
      player:inform_current($event:mk_info(player, msg));
      return;
    endif
    "Check if passage has a lock (unlock_rule)";
    unlock_rule = passage:_value("unlock_rule", 0);
    if (typeof(unlock_rule) != TYPE_FLYWEIGHT)
      player:inform_current($event:mk_error(player, "That doesn't have a lock."));
      return;
    endif
    "Find a key - either specified or auto-detect from inventory";
    key = #-1;
    to_room = passage:other_room(this);
    if (iobjstr && iobjstr != "")
      key = $match:resolve_in_scope(iobjstr, scope);
      if (!valid(key))
        player:inform_current($event:mk_error(player, "You don't have that."));
        return;
      endif
    else
      "Auto-detect key";
      for item in (player.contents)
        bindings = ['Accessor -> player, 'This -> to_room, 'Key -> item, 'Passage -> passage];
        result = $rule_engine:evaluate(unlock_rule, bindings);
        if (typeof(result) == TYPE_MAP && result['success])
          key = item;
          break;
        endif
        bindings = ['Accessor -> player, 'This -> this, 'Key -> item, 'Passage -> passage];
        result = $rule_engine:evaluate(unlock_rule, bindings);
        if (typeof(result) == TYPE_MAP && result['success])
          key = item;
          break;
        endif
      endfor
    endif
    if (!valid(key))
      player:inform_current($event:mk_error(player, "You don't have a key that fits this lock."));
      return;
    endif
    "Verify the key works";
    bindings = ['Accessor -> player, 'This -> to_room, 'Key -> key, 'Passage -> passage];
    result = $rule_engine:evaluate(unlock_rule, bindings);
    if (typeof(result) != TYPE_MAP || !result['success])
      bindings = ['Accessor -> player, 'This -> this, 'Key -> key, 'Passage -> passage];
      result = $rule_engine:evaluate(unlock_rule, bindings);
      if (typeof(result) != TYPE_MAP || !result['success])
        player:inform_current($event:mk_error(player, "That key doesn't fit this lock."));
        return;
      endif
    endif
    "Close the door first if it's open, then lock it";
    new_passage = passage;
    if (passage:_value("is_open", true))
      new_passage = new_passage:with_open(false);
    endif
    new_passage = new_passage:with_locked(true);
    area:update_passage(this, to_room, new_passage);
    door_name = passage:door_name_for(this);
    lock_msg = new_passage:_value("lock_msg", 0);
    if (lock_msg)
      player:inform_current($event:mk_info(player, lock_msg));
    else
      msg = "You lock the " + door_name + ".";
      player:inform_current($event:mk_info(player, msg));
    endif
    "Announce to room";
    announce_msg = player.name + " locks the " + door_name + ".";
    event = $event:mk_narrative(player, announce_msg);
    this:announce(event);
  endverb

  verb open (any none none) owner: ARCH_WIZARD flags: "rxd"
    "Open a closed door/passage, or defer to an object's open verb.";
    "Usage: open <direction> OR open <object> OR open door";
    direction = dobjstr;
    if (!direction || direction == "")
      player:inform_current($event:mk_error(player, "Open what?"));
      return;
    endif
    "First check if this matches an object in scope with an open verb";
    scope = {@player.contents, @this.contents};
    target = $match:resolve_in_scope(direction, scope);
    if (valid(target) && respond_to(target, 'open))
      return target:open();
    endif
    "Get the area";
    area = this.location;
    if (!valid(area) || !isa(area, $area))
      player:inform_current($event:mk_error(player, "This room is not in an area."));
      return;
    endif
    "If 'door' was specified, find a door-type passage";
    passage = 0;
    if (direction == "door")
      passages = area:passages_from(this);
      for p in (passages)
        if (p:door_name_for(this) == "door")
          passage = p;
          break;
        endif
      endfor
      if (typeof(passage) != TYPE_FLYWEIGHT)
        player:inform_current($event:mk_error(player, "There's no door here."));
        return;
      endif
    else
      passage = area:find_passage_by_direction(this, direction);
    endif
    if (typeof(passage) != TYPE_FLYWEIGHT)
      player:inform_current($event:mk_error(player, "There's no exit in that direction."));
      return;
    endif
    "Check if it's already open";
    if (passage:_value("is_open", true))
      door_name = passage:door_name_for(this);
      msg = "The " + door_name + " is already open.";
      player:inform_current($event:mk_info(player, msg));
      return;
    endif
    "Check if it's locked";
    to_room = passage:other_room(this);
    if (passage:_value("is_locked", false))
      "Try to unlock it first - find a key";
      key = #-1;
      unlock_rule = passage:_value("unlock_rule", 0);
      if (typeof(unlock_rule) == TYPE_FLYWEIGHT)
        for item in (player.contents)
          bindings = ['Accessor -> player, 'This -> to_room, 'Key -> item, 'Passage -> passage];
          result = $rule_engine:evaluate(unlock_rule, bindings);
          if (typeof(result) == TYPE_MAP && result['success])
            key = item;
            break;
          endif
          bindings = ['Accessor -> player, 'This -> this, 'Key -> item, 'Passage -> passage];
          result = $rule_engine:evaluate(unlock_rule, bindings);
          if (typeof(result) == TYPE_MAP && result['success])
            key = item;
            break;
          endif
        endfor
      endif
      if (!valid(key))
        door_name = passage:door_name_for(this);
        msg = "The " + door_name + " is locked.";
        player:inform_current($event:mk_error(player, msg));
        return;
      endif
      "Unlock it first";
      passage = passage:with_locked(false);
      door_name = passage:door_name_for(this);
      unlock_msg = passage:_value("unlock_msg", 0);
      if (unlock_msg)
        player:inform_current($event:mk_info(player, unlock_msg));
      else
        msg = "You unlock the " + door_name + " with your key.";
        player:inform_current($event:mk_info(player, msg));
      endif
    endif
    "Open the passage";
    new_passage = passage:with_open(true);
    area:update_passage(this, to_room, new_passage);
    door_name = passage:door_name_for(this);
    open_msg = new_passage:_value("open_msg", 0);
    if (open_msg)
      player:inform_current($event:mk_info(player, open_msg));
    else
      msg = "You open the " + door_name + ".";
      player:inform_current($event:mk_info(player, msg));
    endif
    "Announce to room";
    announce_msg = player.name + " opens the " + door_name + ".";
    event = $event:mk_narrative(player, announce_msg);
    this:announce(event);
  endverb

  verb close (any none none) owner: ARCH_WIZARD flags: "rxd"
    "Close an open door/passage, or defer to an object's close verb.";
    "Usage: close <direction> OR close <object> OR close door";
    direction = dobjstr;
    if (!direction || direction == "")
      player:inform_current($event:mk_error(player, "Close what?"));
      return;
    endif
    "First check if this matches an object in scope with a close verb";
    scope = {@player.contents, @this.contents};
    target = $match:resolve_in_scope(direction, scope);
    if (valid(target) && respond_to(target, 'close))
      return target:close();
    endif
    "Get the area";
    area = this.location;
    if (!valid(area) || !isa(area, $area))
      player:inform_current($event:mk_error(player, "This room is not in an area."));
      return;
    endif
    "If 'door' was specified, find a door-type passage";
    passage = 0;
    if (direction == "door")
      passages = area:passages_from(this);
      for p in (passages)
        if (p:door_name_for(this) == "door")
          passage = p;
          break;
        endif
      endfor
      if (typeof(passage) != TYPE_FLYWEIGHT)
        player:inform_current($event:mk_error(player, "There's no door here."));
        return;
      endif
    else
      passage = area:find_passage_by_direction(this, direction);
    endif
    if (typeof(passage) != TYPE_FLYWEIGHT)
      player:inform_current($event:mk_error(player, "There's no exit in that direction."));
      return;
    endif
    "Check if it's already closed";
    if (!passage:_value("is_open", true))
      door_name = passage:door_name_for(this);
      msg = "The " + door_name + " is already closed.";
      player:inform_current($event:mk_info(player, msg));
      return;
    endif
    "Close the passage";
    new_passage = passage:with_open(false);
    to_room = passage:other_room(this);
    area:update_passage(this, to_room, new_passage);
    door_name = passage:door_name_for(this);
    close_msg = new_passage:_value("close_msg", 0);
    if (close_msg)
      player:inform_current($event:mk_info(player, close_msg));
    else
      msg = "You close the " + door_name + ".";
      player:inform_current($event:mk_info(player, msg));
    endif
    "Announce to room";
    announce_msg = player.name + " closes the " + door_name + ".";
    event = $event:mk_narrative(player, announce_msg);
    this:announce(event);
  endverb

  verb command_hints (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return special commands available in this room for LLM suggestions.";
    "Returns list of maps: [{command -> 'press 1', description -> 'Go to floor 1'}, ...]";
    "Override in subclasses to expose room-specific commands handled by maybe_handle_command.";
    return {};
  endverb

  verb engage_actor (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Register an actor as engaged with an object (sitting, swimming, etc.).";
    "If actor is already engaged with something else, disengage them first.";
    {actor, object} = args;
    "Check if actor is already engaged with something in this room.";
    current = `this.engagements[actor] ! E_RANGE => #-1';
    if (valid(current) && current != object)
      "Disengage from current object first.";
      if (respond_to(current, 'remove_occupant))
        `current:remove_occupant(actor) ! ANY';
      endif
    endif
    "Record new engagement.";
    this.engagements[actor] = object;
  endverb

  verb disengage_actor (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove an actor's engagement record from this room.";
    "Does NOT call remove_occupant - use this after the object has already removed them.";
    {actor} = args;
    this.engagements = `mapdelete(this.engagements, actor) ! E_RANGE => this.engagements';
  endverb

  verb get_engagement (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return what object an actor is engaged with in this room, or #-1 if none.";
    {actor} = args;
    return `this.engagements[actor] ! E_RANGE => #-1';
  endverb

  verb transport_destinations (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return destinations reachable via transport objects in this room.";
    "Scans contents for objects implementing :transport_connections().";
    "Returns list of {destination_room, label, transport_object} tuples.";
    results = {};
    for item in (this.contents)
      if (!valid(item))
        continue;
      endif
      connections = `item:transport_connections() ! ANY => {}';
      if (typeof(connections) == TYPE_LIST)
        for conn in (connections)
          results = {@results, conn};
        endfor
      endif
    endfor
    return results;
  endverb

  verb _default_distant_transform (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Transform an event for distant announcement. Returns new event or 0 to suppress.";
    {event, prefix} = args;
    "Get event info safely";
    slots = flyslots(event);
    actor_name = `slots['actor_name] ! ANY => "someone"';
    verb = `slots['verb] ! ANY => "does something"';
    sound = `slots['sound] ! ANY => ""';
    content = `slots['content] ! ANY => ""';
    "Build a distant description based on event type or sound";
    if (sound == "splash" || verb == "splash" || verb == "dive")
      msg = prefix + ", you hear a splash.";
    elseif (verb == "shout" || verb == "yell")
      if (content)
        msg = prefix + ", you hear " + actor_name + " shout, \"" + content + "\"";
      else
        msg = prefix + ", you hear " + actor_name + " shout.";
      endif
    elseif (verb == "say" || verb == "directed_say")
      msg = prefix + ", you hear muffled voices.";
    elseif (verb == "music" || verb == "record")
      msg = prefix + ", you hear music playing.";
    elseif (verb == "emote")
      msg = prefix + ", you hear sounds of activity.";
    else
      msg = prefix + ", you hear something.";
    endif
    "Build event manually to avoid $nothing.name error";
    content = $ansi:wrap(msg, 'dim, 'italic);
    normalized = $event:normalize_content(content);
    return <$event, .actor = $nothing, .actor_name = "", .verb = "distant", .dobj = false, .iobj = false, .timestamp = time(), .this_obj = false, normalized>;
  endverb

  verb announce_distant (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Receive a distant event from another room and announce it locally.";
    {event, source_room} = args;
    "Tell everyone in this room about the distant event";
    for who in (this:contents())
      suspend_if_needed();
      `who:tell(event) ! E_VERBNF';
    endfor
  endverb

  verb "shout yell" (any any any) owner: ARCH_WIZARD flags: "rd"
    "Shout something loudly - propagates to acoustic neighbors.";
    !argstr && return player:inform_current($event:mk_error(player, "Shout what?"));
    this:announce(player:mk_shout_event(argstr));
  endverb

  verb rewrite_announced (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Rewrite a previously announced rewritable event for all players in this room.";
    "Args: rewrite_id, new_event";
    "Usage: room:rewrite_announced(rewrite_id, $event:mk_info(actor, new_content))";
    {rewrite_id, new_event} = args;
    for who in (this:contents())
      if (!valid(who) || !is_player(who))
        continue;
      endif
      "Get this player's connections - we have permission since we're the room";
      try
        conns = who:_connections();
        if (!conns || length(conns) == 0)
          continue;
        endif
        "Rewrite for each connection this player has";
        for conn_info in (conns)
          conn = conn_info[1];
          who:rewrite_event(rewrite_id, new_event, conn);
        endfor
      except e (ANY)
        "Skip players we can't reach";
      endtry
    endfor
  endverb

  verb input_placeholders (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return a list of placeholder strings for the input field, or false for default.";
    "Override on specific rooms to provide context-sensitive hints.";
    return false;
  endverb
endobject