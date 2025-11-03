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

  verb announce (this none this) owner: HACKER flags: "rxd"
    {event} = args;
    for who in (this:contents())
      `who:tell(event) ! E_VERBNF';
    endfor
  endverb
endobject