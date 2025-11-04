object AREA
  name: "Generic Area"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property passages_rel (owner: HACKER, flags: "r") = 0;

  override description = "Area container that manages passages between rooms using a relation.";
  override import_export_id = "area";

  verb initialize (this none this) owner: HACKER flags: "rx"
    "Called after creation to set up the passages relation.";
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      this.passages_rel = create($relation);
    endif
  endverb

  verb _canonical_tuple (this none this) owner: HACKER flags: "rxd"
    "Build canonical tuple {min_room, max_room, passage} for storage.";
    {room_a, room_b, passage} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    typeof(passage) == OBJ || typeof(passage) == FLYWEIGHT || raise(E_TYPE);
    if (room_a < room_b)
      return {room_a, room_b, passage};
    else
      return {room_b, room_a, passage};
    endif
  endverb

  verb passage_for (this none this) owner: HACKER flags: "rxd"
    "Find the passage between two rooms.";
    {room_a, room_b} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    this:initialize();
    "Find all tuples containing room_a, then filter for room_b";
    candidates = this.passages_rel:select_containing(room_a);
    for tuple in (candidates)
      if (room_b in tuple)
        return tuple[3];
      endif
    endfor
    return false;
  endverb

  verb set_passage (this none this) owner: HACKER flags: "rxd"
    "Set or update the passage between two rooms.";
    {room_a, room_b, passage} = args;
    this:initialize();
    "Remove existing passage if any";
    this:clear_passage(room_a, room_b);
    "Add new passage as canonical tuple";
    tuple = this:_canonical_tuple(room_a, room_b, passage);
    this.passages_rel:assert(tuple);
    return passage;
  endverb

  verb clear_passage (this none this) owner: HACKER flags: "rxd"
    "Remove the passage between two rooms.";
    {room_a, room_b} = args;
    this:initialize();
    "Find and retract the tuple";
    candidates = this.passages_rel:select_containing(room_a);
    for tuple in (candidates)
      if (room_b in tuple)
        return this.passages_rel:retract(tuple);
      endif
    endfor
    return false;
  endverb

  verb passages (this none this) owner: HACKER flags: "rxd"
    "Return all passage objects.";
    this:initialize();
    tuples = this.passages_rel:tuples();
    return { tuple[3] for tuple in (tuples) };
  endverb

  verb passages_from (this none this) owner: HACKER flags: "rxd"
    "Return all passages connected to a room.";
    {room} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    this:initialize();
    tuples = this.passages_rel:select_containing(room);
    return { tuple[3] for tuple in (tuples) };
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
