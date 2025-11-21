object PASSAGE
  name: "Generic Passage"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property direction_abbrevs (owner: HACKER, flags: "rc") = [
    "d" -> "down",
    "down" -> "d",
    "downstairs" -> "d",
    "e" -> "east",
    "east" -> "e",
    "i" -> "in",
    "in" -> "i",
    "n" -> "north",
    "ne" -> "northeast",
    "north" -> "n",
    "northeast" -> "ne",
    "northwest" -> "nw",
    "nw" -> "northwest",
    "o" -> "out",
    "out" -> "o",
    "s" -> "south",
    "se" -> "southeast",
    "south" -> "s",
    "southeast" -> "se",
    "southwest" -> "sw",
    "sw" -> "southwest",
    "u" -> "up",
    "up" -> "u",
    "upstairs" -> "u",
    "w" -> "west",
    "west" -> "w"
  ];
  property is_open (owner: HACKER, flags: "rc") = true;
  property side_a_aliases (owner: HACKER, flags: "rc") = {};
  property side_a_ambient (owner: HACKER, flags: "rc") = true;
  property side_a_arrive_msg (owner: HACKER, flags: "rc") = {};
  property side_a_description (owner: HACKER, flags: "rc") = "";
  property side_a_label (owner: HACKER, flags: "rc") = "";
  property side_a_leave_msg (owner: HACKER, flags: "rc") = {};
  property side_a_room (owner: HACKER, flags: "rc") = #-1;
  property side_b_aliases (owner: HACKER, flags: "rc") = {};
  property side_b_ambient (owner: HACKER, flags: "rc") = true;
  property side_b_arrive_msg (owner: HACKER, flags: "rc") = {};
  property side_b_description (owner: HACKER, flags: "rc") = "";
  property side_b_label (owner: HACKER, flags: "rc") = "";
  property side_b_leave_msg (owner: HACKER, flags: "rc") = {};
  property side_b_room (owner: HACKER, flags: "rc") = #-1;

  override description = "Bidirectional passage configuration.";
  override import_export_hierarchy = {"world"};
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
    return <this, .side_a_room = room_a, .side_a_label = label_a, .side_a_aliases = aliases_a, .side_a_description = description_a, .side_a_ambient = ambient_a, .side_a_leave_msg = {}, .side_a_arrive_msg = {}, .side_b_room = room_b, .side_b_label = label_b, .side_b_aliases = aliases_b, .side_b_description = description_b, .side_b_ambient = ambient_b, .side_b_leave_msg = {}, .side_b_arrive_msg = {}, .is_open = is_open>;
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
      elseif (attr == 'leave_msg)
        prop = "side_a_leave_msg";
        default = {};
      elseif (attr == 'arrive_msg)
        prop = "side_a_arrive_msg";
        default = {};
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
      elseif (attr == 'leave_msg)
        prop = "side_b_leave_msg";
        default = {};
      elseif (attr == 'arrive_msg)
        prop = "side_b_arrive_msg";
        default = {};
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
    "Handle passage traversal using movement context and passage messages";
    {player, from_room, parsed} = args;
    valid(player) || return false;
    valid(from_room) || return false;
    this:_value("is_open", true) || return this:_notify_blocked(player, from_room);
    to_room = this:other_room(from_room);
    valid(to_room) || return false;
    "Get passage metadata";
    from_label = this:label_for(from_room);
    to_label = this:label_for(to_room);
    "Create movement context for message rendering";
    move_context = this:mk_movement_context(player, from_room, to_room, from_label);
    "Render and announce departure event";
    from_side = from_room == this:_side_lookup('a, 'room) ? 'a | 'b;
    leave_msg = this:_side_lookup(from_side, 'leave_msg);
    if (typeof(leave_msg) == LIST && length(leave_msg) > 0)
      "Render custom message with movement context";
      departure_text = "";
      for component in (leave_msg)
        if (typeof(component) == FLYWEIGHT)
          try
            rendered = component:render_as(player, 'text_plain, move_context);
            departure_text = departure_text + rendered;
          except (ANY)
            departure_text = departure_text + tostr(component);
          endtry
        else
          departure_text = departure_text + tostr(component);
        endif
      endfor
      departure = $event:mk(player, #-1, from_room, #-1, #-1, {departure_text}, {});
    else
      "Fall back to default message generation";
      from_description = this:description_for(from_room);
      departure = `player:mk_departure_event(from_room, from_label, from_description, to_room) ! E_VERBNF => 0';
    endif
    if (departure)
      departure = departure:with_audience('narrative);
      from_room:announce(departure);
    endif
    "Actually move the player";
    player:moveto(to_room);
    "Render and announce arrival event";
    to_side = to_room == this:_side_lookup('a, 'room) ? 'a | 'b;
    arrive_msg = this:_side_lookup(to_side, 'arrive_msg);
    if (typeof(arrive_msg) == LIST && length(arrive_msg) > 0)
      "Render custom message with movement context";
      arrival_text = "";
      for component in (arrive_msg)
        if (typeof(component) == FLYWEIGHT)
          try
            rendered = component:render_as(player, 'text_plain, move_context);
            arrival_text = arrival_text + rendered;
          except (ANY)
            arrival_text = arrival_text + tostr(component);
          endtry
        else
          arrival_text = arrival_text + tostr(component);
        endif
      endfor
      arrival = $event:mk(player, #-1, to_room, #-1, #-1, {arrival_text}, {});
    else
      "Fall back to default message generation";
      to_description = this:description_for(to_room);
      arrival = `player:mk_arrival_event(to_room, to_label, to_description, from_room) ! E_VERBNF => 0';
    endif
    if (arrival)
      arrival = arrival:with_audience('narrative);
      to_room:announce(arrival);
    endif
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

  verb expand_direction_aliases (this none this) owner: HACKER flags: "rxd"
    "Expand common directions to include standard aliases.";
    {directions} = args;
    result = {};
    for dir in (directions)
      result = {@result, dir};
      "Add abbreviation if it exists";
      if (maphaskey(this.direction_abbrevs, dir))
        abbrev = this.direction_abbrevs[dir];
        if (abbrev && !(abbrev in result))
          result = {@result, abbrev};
        endif
      endif
    endfor
    return result;
  endverb

  verb side_info_for (this none this) owner: HACKER flags: "rxd"
    "Get label, description, and ambient flag for a given room side.";
    "Returns [label, description, ambient] or empty list if room not found.";
    {room} = args;
    label = this:label_for(room);
    description = this:description_for(room);
    side = this:side_for(room);
    if (side == 'none)
      return {};
    endif
    ambient = this:_side_lookup(side, 'ambient);
    return {label, description, ambient};
  endverb

  verb _extract_all (this none this) owner: HACKER flags: "rxd"
    "Extract all passage properties into a map. Internal helper for transformer verbs.";
    return [
      'room_a -> this:_side_lookup('a, 'room),
      'room_b -> this:_side_lookup('b, 'room),
      'label_a -> this:_side_lookup('a, 'label),
      'label_b -> this:_side_lookup('b, 'label),
      'aliases_a -> this:_side_lookup('a, 'aliases),
      'aliases_b -> this:_side_lookup('b, 'aliases),
      'desc_a -> this:_side_lookup('a, 'description),
      'desc_b -> this:_side_lookup('b, 'description),
      'ambient_a -> this:_side_lookup('a, 'ambient),
      'ambient_b -> this:_side_lookup('b, 'ambient),
      'leave_msg_a -> this:_side_lookup('a, 'leave_msg),
      'leave_msg_b -> this:_side_lookup('b, 'leave_msg),
      'arrive_msg_a -> this:_side_lookup('a, 'arrive_msg),
      'arrive_msg_b -> this:_side_lookup('b, 'arrive_msg),
      'is_open -> this:_value("is_open", true)
    ];
  endverb

  verb with_label_from (this none this) owner: HACKER flags: "rxd"
    "Update the label visible from a given room. Returns new passage flyweight.";
    {room, label} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    typeof(label) == STR || raise(E_TYPE);
    side = this:side_for(room);
    side == 'none && raise(E_INVARG, "Room not connected by this passage");
    props = this:_extract_all();
    if (side == 'a)
      props['label_a] = label;
    else
      props['label_b] = label;
    endif
    return <this, .side_a_room = props['room_a], .side_a_label = props['label_a], .side_a_aliases = props['aliases_a], .side_a_description = props['desc_a], .side_a_ambient = props['ambient_a], .side_a_leave_msg = props['leave_msg_a], .side_a_arrive_msg = props['arrive_msg_a], .side_b_room = props['room_b], .side_b_label = props['label_b], .side_b_aliases = props['aliases_b], .side_b_description = props['desc_b], .side_b_ambient = props['ambient_b], .side_b_leave_msg = props['leave_msg_b], .side_b_arrive_msg = props['arrive_msg_b], .is_open = props['is_open]>;
  endverb

  verb with_description_from (this none this) owner: HACKER flags: "rxd"
    "Update the description visible from a given room. Returns new passage flyweight.";
    {room, description} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    typeof(description) == STR || raise(E_TYPE);
    side = this:side_for(room);
    side == 'none && raise(E_INVARG, "Room not connected by this passage");
    props = this:_extract_all();
    if (side == 'a)
      props['desc_a] = description;
    else
      props['desc_b] = description;
    endif
    return <this, .side_a_room = props['room_a], .side_a_label = props['label_a], .side_a_aliases = props['aliases_a], .side_a_description = props['desc_a], .side_a_ambient = props['ambient_a], .side_a_leave_msg = props['leave_msg_a], .side_a_arrive_msg = props['arrive_msg_a], .side_b_room = props['room_b], .side_b_label = props['label_b], .side_b_aliases = props['aliases_b], .side_b_description = props['desc_b], .side_b_ambient = props['ambient_b], .side_b_leave_msg = props['leave_msg_b], .side_b_arrive_msg = props['arrive_msg_b], .is_open = props['is_open]>;
  endverb

  verb with_aliases_from (this none this) owner: HACKER flags: "rxd"
    "Update the aliases visible from a given room. Accepts string or list. Returns new passage flyweight.";
    {room, aliases} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    side = this:side_for(room);
    side == 'none && raise(E_INVARG, "Room not connected by this passage");
    "Normalize aliases (same as mk does)";
    if (typeof(aliases) == STR)
      aliases = aliases ? {aliases} | {};
    elseif (typeof(aliases) != LIST)
      aliases = {};
    endif
    props = this:_extract_all();
    if (side == 'a)
      props['aliases_a] = aliases;
    else
      props['aliases_b] = aliases;
    endif
    return <this, .side_a_room = props['room_a], .side_a_label = props['label_a], .side_a_aliases = props['aliases_a], .side_a_description = props['desc_a], .side_a_ambient = props['ambient_a], .side_a_leave_msg = props['leave_msg_a], .side_a_arrive_msg = props['arrive_msg_a], .side_b_room = props['room_b], .side_b_label = props['label_b], .side_b_aliases = props['aliases_b], .side_b_description = props['desc_b], .side_b_ambient = props['ambient_b], .side_b_leave_msg = props['leave_msg_b], .side_b_arrive_msg = props['arrive_msg_b], .is_open = props['is_open]>;
  endverb

  verb with_ambient_from (this none this) owner: HACKER flags: "rxd"
    "Update the ambient flag for the side visible from a given room. Returns new passage flyweight.";
    {room, is_ambient} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    side = this:side_for(room);
    side == 'none && raise(E_INVARG, "Room not connected by this passage");
    props = this:_extract_all();
    if (side == 'a)
      props['ambient_a] = is_ambient ? true | false;
    else
      props['ambient_b] = is_ambient ? true | false;
    endif
    return <this, .side_a_room = props['room_a], .side_a_label = props['label_a], .side_a_aliases = props['aliases_a], .side_a_description = props['desc_a], .side_a_ambient = props['ambient_a], .side_a_leave_msg = props['leave_msg_a], .side_a_arrive_msg = props['arrive_msg_a], .side_b_room = props['room_b], .side_b_label = props['label_b], .side_b_aliases = props['aliases_b], .side_b_description = props['desc_b], .side_b_ambient = props['ambient_b], .side_b_leave_msg = props['leave_msg_b], .side_b_arrive_msg = props['arrive_msg_b], .is_open = props['is_open]>;
  endverb

  verb with_open (this none this) owner: HACKER flags: "rxd"
    "Update whether the passage is open/traversable. Returns new passage flyweight.";
    {is_open} = args;
    props = this:_extract_all();
    return <this, .side_a_room = props['room_a], .side_a_label = props['label_a], .side_a_aliases = props['aliases_a], .side_a_description = props['desc_a], .side_a_ambient = props['ambient_a], .side_a_leave_msg = props['leave_msg_a], .side_a_arrive_msg = props['arrive_msg_a], .side_b_room = props['room_b], .side_b_label = props['label_b], .side_b_aliases = props['aliases_b], .side_b_description = props['desc_b], .side_b_ambient = props['ambient_b], .side_b_leave_msg = props['leave_msg_b], .side_b_arrive_msg = props['arrive_msg_b], .is_open = is_open ? true | false>;
  endverb

  verb mk_movement_context (this none this) owner: HACKER flags: "rxd"
    "Create a movement context flyweight with get_binding() support for message rendering.";
    {actor, from_room, to_room, direction_label} = args;
    typeof(actor) == OBJ || raise(E_TYPE);
    typeof(from_room) == OBJ || raise(E_TYPE);
    typeof(to_room) == OBJ || raise(E_TYPE);
    typeof(direction_label) == STR || raise(E_TYPE);
    return <$passage, .actor = actor, .from_room = from_room, .to_room = to_room, .passage = this, .direction_label = direction_label>;
  endverb

  verb get_binding (this none this) owner: HACKER flags: "rxd"
    "Implement the binding protocol for message substitution.";
    {name} = args;
    if (name == 'actor) return this.actor; endif
    if (name == 'direction) return this.direction_label; endif
    if (name == 'from_room) return this.from_room; endif
    if (name == 'to_room) return this.to_room; endif
    if (name == 'passage) return this.passage; endif
    return false;
  endverb
endobject