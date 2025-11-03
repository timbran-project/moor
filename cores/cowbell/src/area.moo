object AREA
  name: "Generic Area"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  override description = "Area container that manages passages between rooms.";
  override import_export_id = "area";

  verb passage_key (this none this) owner: HACKER flags: "rxd"
    {room_a, room_b} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    key_a = toliteral(room_a);
    key_b = toliteral(room_b);
    if (key_a > key_b)
      temp = key_a;
      key_a = key_b;
      key_b = temp;
    endif
    return "passage_edge_" + key_a + "_" + key_b;
  endverb

  verb passage_for (this none this) owner: HACKER flags: "rxd"
    {room_a, room_b} = args;
    prop = this:passage_key(room_a, room_b);
    return `this.(prop) ! E_PROPNF => 0';
  endverb

  verb set_passage (this none this) owner: HACKER flags: "rxd"
    {room_a, room_b, passage} = args;
    typeof(passage) == OBJ || typeof(passage) == FLYWEIGHT || raise(E_TYPE);
    prop = this:passage_key(room_a, room_b);
    this.(prop) = passage;
    return passage;
  endverb

  verb clear_passage (this none this) owner: HACKER flags: "rxd"
    {room_a, room_b} = args;
    prop = this:passage_key(room_a, room_b);
    if (prop in properties(this))
      this.(prop) = 0;
    endif
    return true;
  endverb

  verb passages (this none this) owner: HACKER flags: "rxd"
    edges = {};
    for prop in (properties(this))
      if (!prop:starts_with("passage_edge_"))
        continue;
      endif
      passage = `this.(prop) ! E_PROPNF => 0';
      if (typeof(passage) == OBJ || typeof(passage) == FLYWEIGHT)
        edges = {@edges, passage};
      endif
    endfor
    return edges;
  endverb

  verb passages_from (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    connected = {};
    for passage in (this:passages())
      if (passage:includes(room))
        connected = {@connected, passage};
      endif
    endfor
    return connected;
  endverb

  verb scope_entries_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    entries = {};
    for passage in (this:passages_from(room))
      entry = passage:scope_entry_for(room);
      if (entry)
        entries = {@entries, entry};
      endif
    endfor
    return entries;
  endverb

  verb ambient_entries_for (this none this) owner: HACKER flags: "rxd"
    {room} = args;
    entries = {};
    for passage in (this:passages_from(room))
      entry = passage:ambient_entry_for(room);
      if (entry)
        entries = {@entries, entry};
      endif
    endfor
    return entries;
  endverb

  verb handle_passage_command (this none this) owner: HACKER flags: "rxd"
    {player, parsed} = args;
    typeof(player) == OBJ || return false;
    room = player.location;
    valid(room) || return false;
    passages = this:passages_from(room);
    passages || return false;
    verb_name = parsed["verb"];
    verb_name = typeof(verb_name) == STR ? verb_name:lowercase() | "";
    dobj_name = parsed["dobjstr"];
    dobj_name = typeof(dobj_name) == STR ? dobj_name:lowercase() | "";
    for passage in (passages)
      if (passage:matches_command(room, verb_name))
        return passage:travel_from(player, room, parsed);
      endif
      if (verb_name == "go" && dobj_name && passage:matches_command(room, dobj_name))
        return passage:travel_from(player, room, parsed);
      endif
    endfor
    return false;
  endverb
endobject
