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

  verb mk (this none this) owner: HACKER flags: "rxd"
    {room_a, label_a, aliases_a, description_a, ambient_a, room_b, label_b, aliases_b, description_b, ambient_b, ?is_open = true} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    label_a = typeof(label_a) == STR ? label_a | "";
    label_b = typeof(label_b) == STR ? label_b | "";
    if (typeof(aliases_a) == STR)
      aliases_a = aliases_a ? {aliases_a} | {};
    elseif (typeof(aliases_a) != LIST)
      aliases_a = {};
    endif
    if (typeof(aliases_b) == STR)
      aliases_b = aliases_b ? {aliases_b} | {};
    elseif (typeof(aliases_b) != LIST)
      aliases_b = {};
    endif
    description_a = typeof(description_a) == STR ? description_a | "";
    description_b = typeof(description_b) == STR ? description_b | "";
    ambient_a = ambient_a ? true | false;
    ambient_b = ambient_b ? true | false;
    is_open = is_open ? true | false;
    return <this, [side_a_room -> room_a, side_a_label -> label_a, side_a_aliases -> aliases_a, side_a_description -> description_a, side_a_ambient -> ambient_a, side_b_room -> room_b, side_b_label -> label_b, side_b_aliases -> aliases_b, side_b_description -> description_b, side_b_ambient -> ambient_b, is_open -> is_open]>;
  endverb

  verb _value (this none this) owner: HACKER flags: "rxd"
    {prop, default} = args;
    typeof(prop) == STR || raise(E_TYPE);
    if (typeof(this) == OBJ)
      try
        return this.(prop);
      except (E_PROPNF)
        return default;
      endtry
    endif
    if (typeof(this) == FLYWEIGHT)
      try
        return this.(prop);
      except (E_PROPNF)
        return default;
      endtry
    endif
    return default;
  endverb

  verb _side_lookup (this none this) owner: HACKER flags: "rxd"
    {side, attr} = args;
    prop = "";
    default = 0;
    if (side == 'a)
      if (attr == 'room)
        prop = "side_a_room";
        default = #-1;
      elseif (attr == 'label)
        prop = "side_a_label";
        default = "";
      elseif (attr == 'aliases)
        prop = "side_a_aliases";
        default = {};
      elseif (attr == 'description)
        prop = "side_a_description";
        default = "";
      elseif (attr == 'ambient)
        prop = "side_a_ambient";
        default = false;
      endif
    elseif (side == 'b)
      if (attr == 'room)
        prop = "side_b_room";
        default = #-1;
      elseif (attr == 'label)
        prop = "side_b_label";
        default = "";
      elseif (attr == 'aliases)
        prop = "side_b_aliases";
        default = {};
      elseif (attr == 'description)
        prop = "side_b_description";
        default = "";
      elseif (attr == 'ambient)
        prop = "side_b_ambient";
        default = false;
      endif
    endif
    if (!prop)
      return default;
    endif
    return this:_value(prop, default);
  endverb

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
    return room == this:_side_lookup('a, 'room) || room == this:_side_lookup('b, 'room);
  endverb

  verb side_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    room == this:_side_lookup('a, 'room) && return 'a;
    room == this:_side_lookup('b, 'room) && return 'b;
    return 'none;
  endverb

  verb other_room (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this:_side_lookup('a, 'room))
      return this:_side_lookup('b, 'room);
    elseif (room == this:_side_lookup('b, 'room))
      return this:_side_lookup('a, 'room);
    else
      return #-1;
    endif
  endverb

  verb label_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this:_side_lookup('a, 'room))
      return this:_side_lookup('a, 'label);
    elseif (room == this:_side_lookup('b, 'room))
      return this:_side_lookup('b, 'label);
    else
      return "";
    endif
  endverb

  verb aliases_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    aliases = {};
    if (room == this:_side_lookup('a, 'room))
      aliases = this:_side_lookup('a, 'aliases);
    elseif (room == this:_side_lookup('b, 'room))
      aliases = this:_side_lookup('b, 'aliases);
    endif
    typeof(aliases) == LIST || (aliases = typeof(aliases) == STR ? {aliases} | {});
    return aliases;
  endverb

  verb description_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    if (room == this:_side_lookup('a, 'room))
      return this:_side_lookup('a, 'description);
    elseif (room == this:_side_lookup('b, 'room))
      return this:_side_lookup('b, 'description);
    else
      return "";
    endif
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
    this:_value("is_open", true) || return this:_notify_blocked(player, from_room);
    to_room = this:other_room(from_room);
    valid(to_room) || return false;
    context = ["passage" -> this, "from" -> from_room, "to" -> to_room, "from_label" -> this:label_for(from_room), "to_label" -> this:label_for(to_room), "from_description" -> this:description_for(from_room), "to_description" -> this:description_for(to_room)];
    `player:_set_travel_context(context) ! E_VERBNF => 0';
    player:moveto(to_room);
    `player:_clear_travel_context() ! E_VERBNF => 0';
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