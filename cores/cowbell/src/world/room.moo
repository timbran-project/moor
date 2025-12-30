object ROOM
  name: "Generic Room"
  parent: ROOT
  location: FIRST_AREA
  owner: HACKER
  fertile: true
  readable: true

  override description = "Parent prototype for all rooms in the system, defining room behavior and event broadcasting.";
  override import_export_hierarchy = {"world"};
  override import_export_id = "room";

  verb initialize (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set sensible defaults for newly created rooms.";
    set_task_perms(caller_perms());
    this.description = "An empty room awaiting a description.";
  endverb

  verb emote (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_emote_event(argstr));
  endverb

  verb say (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_say_event(argstr));
  endverb

  verb "`*" (any any any) owner: HACKER flags: "rxd"
    "Directed say - say something to a specific person";
    "Usage: `target message";
    if (length(verb) < 2)
      player:inform_current($event:mk_error(player, "Usage: `target message"));
      return;
    endif
    target_name = verb[2..length(verb)];
    if (!argstr)
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
    this:announce(player:mk_directed_say_event(target, argstr));
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
    "Fire parent triggers for exit";
    pass(@args);
  endverb

  verb notify_pre_exit (this none this) owner: HACKER flags: "rxd"
    "Notify contents before a player leaves (called by passage before departure message).";
    {who} = args;
    if (valid(who) && is_player(who))
      for thing in (this.contents)
        if (thing != who)
          `thing:on_location_exit(who) ! E_VERBNF => 0';
        endif
      endfor
    endif
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "TODO: support locking/unlocking etc";
    return true;
  endverb

  verb match_scope_for (this none this) owner: HACKER flags: "rxd"
    "Expose the room and visible occupants to the command scope.";
    {actor, ?context = []} = args;
    "In case we have a parent that wants to establish initial occupancy, ask it first...";
    entries = `pass(@args) ! E_TYPE, E_VERBNF => {this}';
    "Add every visible occupant so they can be matched as direct objects.";
    visible = this:contents();
    for visible_obj in (visible)
      if (!valid(visible_obj))
        continue;
      endif
      entries = {@entries, visible_obj};
    endfor
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
    for who in (this:contents())
      `who:tell(event) ! E_VERBNF';
    endfor
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    "Override look_self to include exit information";
    "Get base look from parent";
    look_data = pass(@args);
    "Add exits if we're in an area with passages";
    area = this.location;
    if (!valid(area) || !respond_to(area, 'get_exit_info))
      return look_data;
    endif
    {exits, ambient_passages} = area:get_exit_info(this);
    "Set exits and ambient_passages slots on the flyweight if we have any";
    if (length(exits) > 0 || length(ambient_passages) > 0)
      contents_list = flycontents(look_data);
      return <look_data.delegate, .what = look_data.what, .title = look_data.title, .description = look_data.description, .exits = exits, .ambient_passages = ambient_passages, {@contents_list}>;
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
    set_task_perms(caller_perms());
    "Get exits from our area";
    area = this.location;
    if (!valid(area) || !respond_to(area, 'get_exit_info))
      player:inform_current($event:mk_error(player, "You don't see any obvious ways out."):with_audience('utility));
      return;
    endif
    {exit_lines, ambient_passages} = area:get_exit_info(this);
    if (length(exit_lines) == 0)
      player:inform_current($event:mk_error(player, "You don't see any obvious ways out."):with_audience('utility));
      return;
    endif
    "Format and display exits";
    exit_list = $format.list:mk(exit_lines);
    exit_title = $format.title:mk("Ways out");
    content = $format.block:mk(exit_title, exit_list);
    event = $event:mk_info(player, content):with_audience('utility):with_presentation_hint('inset):with_group('exits, this);
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
endobject