object ROOM
  name: "Generic Room"
  parent: ROOT
  location: FIRST_AREA
  owner: HACKER
  fertile: true
  readable: true

  override description = "Parent prototype for all rooms in the system, defining room behavior and event broadcasting.";
  override import_export_id = "room";

  verb emote (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_emote_event(argstr));
  endverb

  verb say (any any any) owner: HACKER flags: "rxd"
    this:announce(player:mk_say_event(argstr));
  endverb

  verb confunc (this none this) owner: HACKER flags: "rxd"
    arrival_event = player:mk_connected_event();
    for who in (this:contents())
      if (who == player)
        continue;
      endif
      `who:tell(arrival_event) ! E_VERBNF';
    endfor
    player:inform_current(player:mk_connected_event():with_audience('utility));
    look_d = this:look_self();
    player:inform_current(look_d:into_event():with_audience('utility));
  endverb

  verb enterfunc (this none this) owner: HACKER flags: "rxd"
    "Show room description to arriving players";
    {who} = args;
    valid(who) || return;
    if (is_player(who))
      look_d = this:look_self();
      who:inform_current(look_d:into_event():with_audience('utility));
    endif
  endverb

  verb exitfunc (this none this) owner: HACKER flags: "rxd"
    "Do nothing - movement verbs handle departure announcements directly";
    return;
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "TODO: support locking/unlocking etc";
    return true;
  endverb

  verb command_scope_for (this none this) owner: HACKER flags: "rxd"
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
endobject