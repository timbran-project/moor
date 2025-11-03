object PASSAGE
  name: "Generic Passage"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property is_open (owner: HACKER, flags: "rc") = true;
  property side_a_aliases (owner: HACKER, flags: "rc") = {};
  property side_a_ambient (owner: HACKER, flags: "rc") = true;
  property side_a_description (owner: HACKER, flags: "rc") = "";
  property side_a_label (owner: HACKER, flags: "rc") = "";
  property side_a_room (owner: HACKER, flags: "rc") = #-1;
  property side_b_aliases (owner: HACKER, flags: "rc") = {};
  property side_b_ambient (owner: HACKER, flags: "rc") = true;
  property side_b_description (owner: HACKER, flags: "rc") = "";
  property side_b_label (owner: HACKER, flags: "rc") = "";
  property side_b_room (owner: HACKER, flags: "rc") = #-1;

  override description = "Bidirectional passage configuration.";
  override import_export_id = "passage";

  verb configure (this none this) owner: HACKER flags: "rxd"
    {room_a, label_a, aliases_a, description_a, ambient_a, room_b, label_b, aliases_b, description_b, ambient_b} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    this.side_a_room = room_a;
    this.side_a_label = typeof(label_a) == STR ? label_a | "";
    if (typeof(aliases_a) == LIST)
      this.side_a_aliases = aliases_a;
    elseif (typeof(aliases_a) == STR && aliases_a)
      this.side_a_aliases = {aliases_a};
    else
      this.side_a_aliases = {};
    endif
    this.side_a_description = typeof(description_a) == STR ? description_a | "";
    this.side_a_ambient = ambient_a ? true | false;
    this.side_b_room = room_b;
    this.side_b_label = typeof(label_b) == STR ? label_b | "";
    if (typeof(aliases_b) == LIST)
      this.side_b_aliases = aliases_b;
    elseif (typeof(aliases_b) == STR && aliases_b)
      this.side_b_aliases = {aliases_b};
    else
      this.side_b_aliases = {};
    endif
    this.side_b_description = typeof(description_b) == STR ? description_b | "";
    this.side_b_ambient = ambient_b ? true | false;
    return this;
  endverb

  verb includes (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    return room == this.side_a_room || room == this.side_b_room;
  endverb

  verb side_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    room == this.side_a_room && return 'a;
    room == this.side_b_room && return 'b;
    return 'none;
  endverb

  verb other_room (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this.side_a_room)
      return this.side_b_room;
    elseif (room == this.side_b_room)
      return this.side_a_room;
    else
      return #-1;
    endif
  endverb

  verb label_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this.side_a_room)
      return this.side_a_label;
    elseif (room == this.side_b_room)
      return this.side_b_label;
    else
      return "";
    endif
  endverb

  verb aliases_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    aliases = {};
    if (room == this.side_a_room)
      aliases = this.side_a_aliases;
    elseif (room == this.side_b_room)
      aliases = this.side_b_aliases;
    endif
    typeof(aliases) == LIST || (aliases = typeof(aliases) == STR ? {aliases} | {});
    return aliases;
  endverb

  verb description_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this.side_a_room)
      return this.side_a_description;
    elseif (room == this.side_b_room)
      return this.side_b_description;
    else
      return "";
    endif
  endverb

  verb ambient_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this.side_a_room)
      return this.side_a_ambient ? true | false;
    elseif (room == this.side_b_room)
      return this.side_b_ambient ? true | false;
    else
      return false;
    endif
  endverb

  verb scope_entry_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    aliases = this:aliases_for(room);
    if (!aliases)
      return this;
    endif
    return {this, @aliases};
  endverb

  verb ambient_entry_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    this:ambient_for(room) || return 0;
    return this:scope_entry_for(room);
  endverb

  verb matches_command (this none this) owner: HACKER flags: "rxd"
    {room, command} = args;
    typeof(command) == STR || return false;
    command = command:lowercase();
    for alias in (this:aliases_for(room))
      if (typeof(alias) != STR)
        continue;
      endif
      if (alias:lowercase() == command)
        return true;
      endif
    endfor
    label = this:label_for(room);
    if (typeof(label) == STR && label && label:lowercase() == command)
      return true;
    endif
    return false;
  endverb

  verb travel_from (this none this) owner: HACKER flags: "rxd"
    {player, from_room, parsed} = args;
    valid(player) || return false;
    valid(from_room) || return false;
    this.is_open || return this:_notify_blocked(player, from_room);
    to_room = this:other_room(from_room);
    valid(to_room) || return false;
    result = `player:moveto(to_room) ! ANY => ANY';
    result == ANY && return false;
    return true;
  endverb

  verb _notify_blocked (this none this) owner: HACKER flags: "rxd"
    {player, from_room} = args;
    message = "That way is blocked.";
    label = this:label_for(from_room);
    if (label)
      message = "The " + label + " passage is blocked.";
    endif
    player:inform_current($event:mk_error(player, message));
    return false;
  endverb
endobject