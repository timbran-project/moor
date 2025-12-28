object AREA
  name: "Generic Area"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property passages_rel (owner: HACKER, flags: "r") = 0;

  override description = "Area container that manages passages between rooms using a relation.";
  override import_export_hierarchy = {"world"};
  override import_export_id = "area";

  verb initialize (this none this) owner: HACKER flags: "rxd"
    "Called after creation to set up the passages relation.";
    this:_ensure_passages_relation();
  endverb

  verb _ensure_passages_relation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Ensure this.passages_rel references a valid relation owned by the area's owner.";
    if (typeof(this.passages_rel) == OBJ && valid(this.passages_rel))
      return this.passages_rel;
    endif
    set_task_perms(valid(this.owner) ? this.owner | caller_perms());
    rel = create($relation);
    rel.name = "Passages Relation for Area " + tostr(this);
    this.passages_rel = rel;
    return this.passages_rel;
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

  verb set_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    this:require_caller(this);
    set_task_perms(this.owner);
    "Set or update the passage between two rooms.";
    {room_a, room_b, passage} = args;
    this:_ensure_passages_relation();
    "Remove existing passage if any";
    this:clear_passage(room_a, room_b);
    "Add new passage as canonical tuple";
    tuple = this:_canonical_tuple(room_a, room_b, passage);
    this.passages_rel:assert(tuple);
    return passage;
  endverb

  verb clear_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    this:require_caller(this);
    set_task_perms(this.owner);
    "Remove the passage between two rooms.";
    {room_a, room_b} = args;
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return false;
    endif
    "Find and retract the tuple";
    candidates = this.passages_rel:select_containing(room_a);
    for tuple in (candidates)
      if (room_b in tuple)
        return this.passages_rel:retract(tuple);
      endif
    endfor
    return false;
  endverb

  verb passages (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Return all passage objects.";
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return {};
    endif
    tuples = this.passages_rel:tuples();
    return { tuple[3] for tuple in (tuples) };
  endverb

  verb passages_from (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return all passages connected to a room.";
    {room} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return {};
    endif
    tuples = this.passages_rel:select_containing(room);
    return { tuple[3] for tuple in (tuples) };
  endverb

  verb handle_passage_command (this none this) owner: HACKER flags: "rxd"
    {parsed} = args;
    room = player.location;
    valid(room) || return false;
    passages = this:passages_from(room);
    passages || return false;
    verb_name = tostr(parsed["verb"]);
    `length(verb_name) ! ANY => false' || return false;
    dobj_name = parsed["dobjstr"];
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

  verb rooms_from (this none this) owner: HACKER flags: "rxd"
    "Find all rooms transitively reachable from the starting room.";
    "Optional second arg: only_open (default true) - skip closed passages.";
    {start_room, ?only_open = true} = args;
    typeof(start_room) == OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return {start_room};
    endif
    visited = [start_room -> true];
    frontier = {start_room};
    while (length(frontier) > 0)
      current = frontier[1];
      frontier = listdelete(frontier, 1);
      "Find passages from current room using datalog query";
      results = this.passages_rel:query({current, $dvar:mk_dest(), $dvar:mk_passage()});
      for binding in (results)
        dest = binding['dest];
        passage = binding['passage];
        if (only_open && !`passage.is_open ! ANY => true')
          continue;
        endif
        if (!maphaskey(visited, dest))
          visited[dest] = true;
          frontier = {@frontier, dest};
        endif
      endfor
      "Check reverse direction too (dest to current)";
      results = this.passages_rel:query({$dvar:mk_src(), current, $dvar:mk_passage()});
      for binding in (results)
        src = binding['src];
        passage = binding['passage];
        if (only_open && !`passage.is_open ! ANY => true')
          continue;
        endif
        if (!maphaskey(visited, src))
          visited[src] = true;
          frontier = {@frontier, src};
        endif
      endfor
    endwhile
    return mapkeys(visited);
  endverb

  verb connected (this none this) owner: HACKER flags: "rxd"
    "Check if two rooms are transitively connected via passages.";
    "Optional third arg: only_open (default true) - skip closed passages.";
    {room_a, room_b, ?only_open = true} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    reachable = this:rooms_from(room_a, only_open);
    return room_b in reachable;
  endverb

  verb find_path (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find a path from start_room to goal_room. Returns list of {room, passage} pairs, or false.";
    "Optional third arg: only_open (default true) - skip closed passages.";
    {start_room, goal_room, ?only_open = true} = args;
    typeof(start_room) == OBJ && typeof(goal_room) == OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return start_room == goal_room ? {{start_room, false}} | false;
    endif
    start_room == goal_room && return {{start_room, false}};
    visited = [start_room -> true];
    "Queue entries: {current_room, path_so_far}";
    queue = {{start_room, {}}};
    while (length(queue) > 0)
      "Suspend if ticks are getting low - use higher threshold for expensive queries";
      suspend_if_needed(50000);
      {current, path} = queue[1];
      queue = listdelete(queue, 1);
      "Try forward edges: current -> next";
      results = this.passages_rel:query({current, $dvar:mk_next(), $dvar:mk_passage()});
      for binding in (results)
        next = binding['next];
        passage = binding['passage];
        if (only_open && !`passage.is_open ! ANY => true')
          continue;
        endif
        if (next == goal_room)
          return {@path, {current, passage}, {goal_room, false}};
        endif
        if (!maphaskey(visited, next))
          visited[next] = true;
          queue = {@queue, {next, {@path, {current, passage}}}};
        endif
      endfor
      "Try reverse edges: next -> current";
      results = this.passages_rel:query({$dvar:mk_next(), current, $dvar:mk_passage()});
      for binding in (results)
        next = binding['next];
        passage = binding['passage];
        if (only_open && !`passage.is_open ! ANY => true')
          continue;
        endif
        if (next == goal_room)
          return {@path, {current, passage}, {goal_room, false}};
        endif
        if (!maphaskey(visited, next))
          visited[next] = true;
          queue = {@queue, {next, {@path, {current, passage}}}};
        endif
      endfor
    endwhile
    return false;
  endverb

  verb make_room_in (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a new room in this area. Requires 'add_room capability on area.";
    set_task_perms(caller_perms());
    {target, perms} = this:check_permissions('add_room);
    {parent_obj} = args;
    "Create room with caller's ownership";
    new_room = parent_obj:create();
    new_room:moveto(target);
    return new_room;
  endverb

  verb add_room (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Add a room to this area. Requires 'add_room capability on area.";
    {this, perms} = this:check_permissions('add_room);
    {room} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    room:moveto(this);
    return room;
  endverb

  verb create_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create passage between two rooms. Requires 'create_passage on area, 'dig_from on room_a, 'dig_into on room_b.";
    "For bidirectional passages, also requires 'dig_from on room_b and 'dig_into on room_a.";
    "room_a and room_b should be capability flyweights or raw room objects that caller has permission for.";
    {this, perms} = this:check_permissions('create_passage);
    {room_a, room_b, passage} = args;
    "Extract actual room objects from capabilities if needed";
    actual_room_a = typeof(room_a) == FLYWEIGHT ? room_a.delegate | room_a;
    actual_room_b = typeof(room_b) == FLYWEIGHT ? room_b.delegate | room_b;
    "Check room_a allows digging from it and room_b allows digging into it";
    try
      room_a:check_permissions('dig_from);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_from});
      raise(E_PERM, message);
    endtry
    try
      room_b:check_permissions('dig_into);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_b, 'room, {'dig_into});
      raise(E_PERM, message);
    endtry
    "If bidirectional (has side_b label or aliases), also check the reverse direction";
    is_bidirectional = passage.side_b_label != "" || length(passage.side_b_aliases) > 0;
    if (is_bidirectional)
      try
        room_b:check_permissions('dig_from);
      except (E_PERM)
        message = $grant_utils:format_denial(actual_room_b, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      try
        room_a:check_permissions('dig_into);
      except (E_PERM)
        message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_into});
        raise(E_PERM, message);
      endtry
    endif
    "Now create the passage with elevated area permissions";
    return this:_do_create_passage(actual_room_a, actual_room_b, passage, perms);
  endverb

  verb _do_create_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Actually create the passage with elevated permissions.";
    this:require_caller(this);
    {room_a, room_b, passage, perms} = args;
    set_task_perms(perms);
    this:set_passage(room_a, room_b, passage);
    return passage;
  endverb

  verb update_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Update an existing passage between two rooms. Requires 'dig_from permission on source room.";
    set_task_perms(caller_perms());
    {source_room, dest_room, new_passage} = args;
    typeof(source_room) == OBJ && typeof(dest_room) == OBJ || raise(E_TYPE);
    typeof(new_passage) == OBJ || typeof(new_passage) == FLYWEIGHT || raise(E_TYPE);
    "Extract actual room objects from capabilities if needed";
    actual_source = typeof(source_room) == FLYWEIGHT ? source_room.delegate | source_room;
    actual_dest = typeof(dest_room) == FLYWEIGHT ? dest_room.delegate | dest_room;
    "Check that source room allows digging from it";
    cap = caller_perms():find_capability_for(actual_source, 'room);
    room_target = typeof(cap) == FLYWEIGHT ? cap | actual_source;
    room_target:check_can_dig_from();
    "Update the passage";
    this:set_passage(actual_source, actual_dest, new_passage);
    return new_passage;
  endverb

  verb remove_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Remove passage between two rooms. Requires 'remove_passage on area and 'dig_from on source room.";
    {this, perms} = this:check_permissions('remove_passage);
    {room_a, room_b} = args;
    "Extract actual room objects from capabilities if needed";
    actual_room_a = typeof(room_a) == FLYWEIGHT ? room_a.delegate | room_a;
    actual_room_b = typeof(room_b) == FLYWEIGHT ? room_b.delegate | room_b;
    "Check that source room allows digging from it (implies permission to remove passages)";
    try
      room_a:check_permissions('dig_from);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_from});
      raise(E_PERM, message);
    endtry
    "Remove the passage with elevated permissions";
    return this:_do_remove_passage(actual_room_a, actual_room_b, perms);
  endverb

  verb _do_remove_passage (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Actually remove the passage with elevated permissions.";
    this:require_caller(this);
    {room_a, room_b, perms} = args;
    set_task_perms(perms);
    return this:clear_passage(room_a, room_b);
  endverb

  verb on_room_recycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Clean up all passages to/from a room that is being recycled.";
    set_task_perms(this.owner);
    {room} = args;
    typeof(room) == OBJ || return;
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return;
    endif
    tuples = this.passages_rel:select_containing(room);
    for tuple in (tuples)
      this.passages_rel:retract(tuple);
    endfor
  endverb

  verb find_passage_by_direction (this none this) owner: HACKER flags: "rxd"
    "Find a passage from a room matching a direction/label/alias. Returns passage or false.";
    {room, direction} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    typeof(direction) == STR || raise(E_TYPE);
    passages = this:passages_from(room);
    for p in (passages)
      if (p:matches_command(room, direction))
        return p;
      endif
    endfor
    return false;
  endverb

  verb get_exit_info (this none this) owner: HACKER flags: "rxd"
    "Get exit labels and ambient passage descriptions for a room. Returns {exits, ambient_passages}.";
    "ambient_passages is a list of {description, prose_style, label} tuples where prose_style is 'sentence or 'fragment.";
    {room} = args;
    typeof(room) == OBJ || raise(E_TYPE);
    passages = this:passages_from(room);
    exits = {};
    ambient_passages = {};
    for passage in (passages)
      is_open = `passage.is_open ! ANY => false';
      if (!is_open)
        continue;
      endif
      info = passage:side_info_for(room);
      if (length(info) == 0)
        continue;
      endif
      {label, description, ambient, ?prose_style = 'fragment} = info;
      if (label)
        if (ambient && description)
          "Ambient passages with descriptions integrate into room description";
          "Include label so it can be linkified";
          ambient_passages = {@ambient_passages, {description, prose_style, label}};
        else
          "Non-ambient or description-less passages show as simple exits";
          exits = {@exits, label};
        endif
      endif
    endfor
    return {exits, ambient_passages};
  endverb

  verb test_connectivity (this none this) owner: HACKER flags: "rxd"
    "Test connectivity checking between rooms";
    area = $area:create(true);
    r1 = $room:create(true);
    r2 = $room:create(true);
    r3 = $room:create(true);
    r4 = $room:create(true);
    "Create three rooms in a chain: r1 <-> r2 <-> r3";
    passage1 = <$passage, .side_a_room = r1, .side_b_room = r2, .is_open = true>;
    passage2 = <$passage, .side_a_room = r2, .side_b_room = r3, .is_open = true>;
    area:set_passage(r1, r2, passage1);
    area:set_passage(r2, r3, passage2);
    "r1 and r2 are directly connected";
    !area:connected(r1, r2) && raise(E_ASSERT, "r1 and r2 should be connected");
    "r1 and r3 are transitively connected";
    !area:connected(r1, r3) && raise(E_ASSERT, "r1 and r3 should be transitively connected");
    "r3 and r1 are connected (bidirectional)";
    !area:connected(r3, r1) && raise(E_ASSERT, "r3 and r1 should be connected");
    "r4 is not connected";
    area:connected(r1, r4) && raise(E_ASSERT, "r4 should not be connected");
  endverb

  verb test_rooms_from (this none this) owner: HACKER flags: "rxd"
    "Test finding all reachable rooms";
    area = $area:create(true);
    r1 = $room:create(true);
    r2 = $room:create(true);
    r3 = $room:create(true);
    r4 = $room:create(true);
    "Create a small network";
    area:set_passage(r1, r2, <$passage, .side_a_room = r1, .side_b_room = r2, .is_open = true>);
    area:set_passage(r2, r3, <$passage, .side_a_room = r2, .side_b_room = r3, .is_open = true>);
    area:set_passage(r1, r4, <$passage, .side_a_room = r1, .side_b_room = r4, .is_open = true>);
    reachable = area:rooms_from(r1);
    length(reachable) != 4 && raise(E_ASSERT, "Should find 4 reachable rooms from r1");
    r1 in reachable || raise(E_ASSERT, "Should include starting room");
    r2 in reachable || raise(E_ASSERT, "Should reach r2");
    r3 in reachable || raise(E_ASSERT, "Should reach r3");
    r4 in reachable || raise(E_ASSERT, "Should reach r4");
    "From r3 should reach all via bidirectional edges";
    reachable = area:rooms_from(r3);
    length(reachable) != 4 && raise(E_ASSERT, "Should find 4 reachable rooms from r3");
  endverb

  verb test_find_path (this none this) owner: HACKER flags: "rxd"
    "Test pathfinding between rooms";
    area = $area:create(true);
    r1 = $room:create(true);
    r2 = $room:create(true);
    r3 = $room:create(true);
    r_disconnected = $room:create(true);
    p1 = <$passage, .side_a_room = r1, .side_b_room = r2, .is_open = true>;
    p2 = <$passage, .side_a_room = r2, .side_b_room = r3, .is_open = true>;
    "Create chain: r1 <-> r2 <-> r3";
    area:set_passage(r1, r2, p1);
    area:set_passage(r2, r3, p2);
    "Direct path";
    path = area:find_path(r1, r2);
    path || raise(E_ASSERT, "Should find path from r1 to r2");
    length(path) != 2 && raise(E_ASSERT, "Path length should be 2");
    path[1][1] != r1 && raise(E_ASSERT, "Path should start at r1");
    path[2][1] != r2 && raise(E_ASSERT, "Path should end at r2");
    "Multi-hop path";
    path = area:find_path(r1, r3);
    path || raise(E_ASSERT, "Should find path from r1 to r3");
    length(path) != 3 && raise(E_ASSERT, "Path should have 3 nodes");
    path[1][1] != r1 && raise(E_ASSERT, "Path should start at r1");
    path[2][1] != r2 && raise(E_ASSERT, "Path should go through r2");
    path[3][1] != r3 && raise(E_ASSERT, "Path should end at r3");
    "No path to disconnected room";
    path = area:find_path(r1, r_disconnected);
    path && raise(E_ASSERT, "Should not find path to disconnected room");
    "Same room";
    path = area:find_path(r1, r1);
    path || raise(E_ASSERT, "Should find path from room to itself");
    length(path) != 1 && raise(E_ASSERT, "Same-room path should have 1 node");
  endverb

  verb test_closed_passages (this none this) owner: HACKER flags: "rxd"
    "Test that closed passages are respected by pathfinding";
    area = $area:create(true);
    r1 = $room:create(true);
    r2 = $room:create(true);
    r3 = $room:create(true);
    "Create chain with middle passage closed: r1 <-> r2 -X- r3";
    area:set_passage(r1, r2, <$passage, .side_a_room = r1, .side_b_room = r2, .is_open = true>);
    area:set_passage(r2, r3, <$passage, .side_a_room = r2, .side_b_room = r3, .is_open = false>);
    "r1 to r3 should fail with only_open=true (default)";
    path = area:find_path(r1, r3);
    path && raise(E_ASSERT, "Should not find path through closed passage");
    "r1 to r3 should succeed with only_open=false";
    path = area:find_path(r1, r3, false);
    path || raise(E_ASSERT, "Should find path when ignoring closed passages");
    length(path) != 3 && raise(E_ASSERT, "Path should have 3 nodes");
    "rooms_from should respect is_open";
    reachable = area:rooms_from(r1);
    length(reachable) != 2 && raise(E_ASSERT, "Should only reach 2 rooms with closed passage");
    reachable = area:rooms_from(r1, false);
    length(reachable) != 3 && raise(E_ASSERT, "Should reach all 3 rooms when ignoring closed");
  endverb
endobject
