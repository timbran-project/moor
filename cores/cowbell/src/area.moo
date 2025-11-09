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
    this:_ensure_passages_relation();
  endverb

  verb _ensure_passages_relation (this none this) owner: HACKER flags: "rxd"
    "Ensure this.passages_rel references a valid relation owned by the area's owner.";
    if (typeof(this.passages_rel) == OBJ && valid(this.passages_rel))
      return this.passages_rel;
    endif
    prior_perms = caller_perms();
    target_perms = valid(this.owner) ? this.owner | prior_perms;
    perms_changed = target_perms && target_perms != prior_perms;
    if (perms_changed)
      set_task_perms(target_perms);
    endif
    try
      rel = create($relation);
      this.passages_rel = rel;
    finally
      if (perms_changed)
        set_task_perms(prior_perms);
      endif
    endtry
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
    set_task_perms(caller_perms());
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
    `length(verb) ! ANY => false' || return false;
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
    {start_room} = args;
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
        if (!maphaskey(visited, dest))
          visited[dest] = true;
          frontier = {@frontier, dest};
        endif
      endfor
      "Check reverse direction too (dest to current)";
      results = this.passages_rel:query({$dvar:mk_src(), current, $dvar:mk_passage()});
      for binding in (results)
        src = binding['src];
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
    {room_a, room_b} = args;
    typeof(room_a) == OBJ && typeof(room_b) == OBJ || raise(E_TYPE);
    reachable = this:rooms_from(room_a);
    return room_b in reachable;
  endverb

  verb find_path (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Find a path from start_room to goal_room. Returns list of {room, passage} pairs, or false.";
    {start_room, goal_room} = args;
    typeof(start_room) == OBJ && typeof(goal_room) == OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != OBJ || !valid(this.passages_rel))
      return start_room == goal_room ? {{start_room, false}} | false;
    endif
    start_room == goal_room && return {{start_room, false}};
    visited = [start_room -> true];
    "Queue entries: {current_room, path_so_far}";
    queue = {{start_room, {}}};
    while (length(queue) > 0)
      {current, path} = queue[1];
      queue = listdelete(queue, 1);
      "Try forward edges: current -> next";
      results = this.passages_rel:query({current, $dvar:mk_next(), $dvar:mk_passage()});
      for binding in (results)
        next = binding['next];
        passage = binding['passage];
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

  verb test_connectivity (this none this) owner: HACKER flags: "rxd"
    "Test connectivity checking between rooms";
    area = create($area);
    "Create three rooms in a chain: 1 <-> 2 <-> 3";
    passage1 = <$passage, .side_a_room = #1, .side_b_room = #2, .is_open = true>;
    passage2 = <$passage, .side_a_room = #2, .side_b_room = #3, .is_open = true>;
    area:set_passage(#1, #2, passage1);
    area:set_passage(#2, #3, passage2);
    "#1 and #2 are directly connected";
    !area:connected(#1, #2) && raise(E_ASSERT, "#1 and #2 should be connected");
    "#1 and #3 are transitively connected";
    !area:connected(#1, #3) && raise(E_ASSERT, "#1 and #3 should be transitively connected");
    "#3 and #1 are connected (bidirectional)";
    !area:connected(#3, #1) && raise(E_ASSERT, "#3 and #1 should be connected");
    "#4 is not connected";
    area:connected(#1, #4) && raise(E_ASSERT, "#4 should not be connected");
    area:destroy();
  endverb

  verb test_rooms_from (this none this) owner: HACKER flags: "rxd"
    "Test finding all reachable rooms";
    area = create($area);
    "Create a small network";
    area:set_passage(#1, #2, <$passage, .is_open = true>);
    area:set_passage(#2, #3, <$passage, .is_open = true>);
    area:set_passage(#1, #4, <$passage, .is_open = true>);
    reachable = area:rooms_from(#1);
    length(reachable) != 4 && raise(E_ASSERT, "Should find 4 reachable rooms from #1");
    #1 in reachable || raise(E_ASSERT, "Should include starting room");
    #2 in reachable || raise(E_ASSERT, "Should reach #2");
    #3 in reachable || raise(E_ASSERT, "Should reach #3");
    #4 in reachable || raise(E_ASSERT, "Should reach #4");
    "From #3 should reach all via bidirectional edges";
    reachable = area:rooms_from(#3);
    length(reachable) != 4 && raise(E_ASSERT, "Should find 4 reachable rooms from #3");
    area:destroy();
  endverb

  verb test_find_path (this none this) owner: HACKER flags: "rxd"
    "Test pathfinding between rooms";
    area = create($area);
    p1 = <$passage, .is_open = true>;
    p2 = <$passage, .is_open = true>;
    "Create chain: 1 <-> 2 <-> 3";
    area:set_passage(#1, #2, p1);
    area:set_passage(#2, #3, p2);
    "Direct path";
    path = area:find_path(#1, #2);
    path || raise(E_ASSERT, "Should find path from #1 to #2");
    length(path) != 2 && raise(E_ASSERT, "Path length should be 2");
    path[1][1] != #1 && raise(E_ASSERT, "Path should start at #1");
    path[2][1] != #2 && raise(E_ASSERT, "Path should end at #2");
    "Multi-hop path";
    path = area:find_path(#1, #3);
    path || raise(E_ASSERT, "Should find path from #1 to #3");
    length(path) != 3 && raise(E_ASSERT, "Path should have 3 nodes");
    path[1][1] != #1 && raise(E_ASSERT, "Path should start at #1");
    path[2][1] != #2 && raise(E_ASSERT, "Path should go through #2");
    path[3][1] != #3 && raise(E_ASSERT, "Path should end at #3");
    "No path to disconnected room";
    path = area:find_path(#1, #99);
    path && raise(E_ASSERT, "Should not find path to disconnected room");
    "Same room";
    path = area:find_path(#1, #1);
    path || raise(E_ASSERT, "Should find path from room to itself");
    length(path) != 1 && raise(E_ASSERT, "Same-room path should have 1 node");
    area:destroy();
  endverb
endobject