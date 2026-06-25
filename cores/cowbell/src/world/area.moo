object AREA [
  import_export_id -> "area",
  import_export_hierarchy -> {"world"}
]
  name: "Generic Area"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property passages_rel (owner: HACKER, flags: "r") = 0;

  override description = "Area container that manages passages between rooms using a relation.";

  method acceptable owner: HACKER
    "Areas accept rooms as spatial contents.";
    {what} = args;
    return typeof(what) == TYPE_OBJ && valid(what) && isa(what, $room);
  endmethod

  method initialize owner: HACKER
    "Called after creation to set up the passages relation.";
    pass();
    this:_ensure_passages_relation();
  endmethod

  method _ensure_passages_relation owner: ARCH_WIZARD
    "Ensure this.passages_rel references a valid relation owned by the area's owner.";
    if (typeof(this.passages_rel) == TYPE_OBJ && valid(this.passages_rel))
      return this.passages_rel;
    endif
    set_task_perms(valid(this.owner) ? this.owner | caller_perms());
    rel = create($relation);
    rel.name = "Passages Relation for Area " + tostr(this);
    this.passages_rel = rel;
    return this.passages_rel;
  endmethod

  method _canonical_tuple owner: HACKER
    "Build canonical tuple {min_room, max_room, passage} for storage.";
    {room_a, room_b, passage} = args;
    typeof(room_a) == TYPE_OBJ && typeof(room_b) == TYPE_OBJ || raise(E_TYPE);
    typeof(passage) == TYPE_OBJ || typeof(passage) == TYPE_FLYWEIGHT || raise(E_TYPE);
    if (room_a < room_b)
      return {room_a, room_b, passage};
    else
      return {room_b, room_a, passage};
    endif
  endmethod

  method passage_for owner: HACKER
    "Find the passage between two rooms.";
    {room_a, room_b} = args;
    typeof(room_a) == TYPE_OBJ && typeof(room_b) == TYPE_OBJ || raise(E_TYPE);
    this:initialize();
    "Find all tuples containing room_a, then filter for room_b";
    candidates = this.passages_rel:select_containing(room_a);
    for tuple in (candidates)
      if (room_b in tuple)
        return tuple[3];
      endif
    endfor
    return false;
  endmethod

  method set_passage owner: ARCH_WIZARD
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
  endmethod

  method clear_passage owner: ARCH_WIZARD
    this:require_caller(this);
    set_task_perms(this.owner);
    "Remove the passage between two rooms.";
    {room_a, room_b} = args;
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
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
  endmethod

  method passages owner: ARCH_WIZARD
    set_task_perms(caller_perms());
    "Return all passage objects.";
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
      return {};
    endif
    tuples = this.passages_rel:tuples();
    return { tuple[3] for tuple in (tuples) };
  endmethod

  method passages_from owner: ARCH_WIZARD
    "Return all passages connected to a room.";
    {room} = args;
    typeof(room) == TYPE_OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
      return {};
    endif
    tuples = this.passages_rel:select_containing(room);
    if (length(tuples) == 0)
      tuples = {};
      for binding in (this.passages_rel:query({room, {'var, 'dest}, {'var, 'passage}}))
        tuples = {@tuples, {room, binding['dest], binding['passage]}};
      endfor
      for binding in (this.passages_rel:query({{'var, 'src}, room, {'var, 'passage}}))
        tuples = {@tuples, {binding['src], room, binding['passage]}};
      endfor
    endif
    passages = {};
    for tuple in (tuples)
      passage = tuple[3];
      if (!(passage in passages))
        passages = {@passages, passage};
      endif
    endfor
    return passages;
  endmethod

  method handle_passage_command owner: HACKER
    {parsed} = args;
    room = player.location;
    valid(room) || return false;
    passages = this:passages_from(room);
    passages || return false;
    verb_name = tostr(parsed['verb]);
    length(verb_name) || return false;
    dobj_name = parsed['dobjstr];
    for passage in (passages)
      if (passage:matches_command(room, verb_name))
        return passage:travel_from(player, room, parsed);
      endif
      if (verb_name == "go" && dobj_name && passage:matches_command(room, dobj_name))
        return passage:travel_from(player, room, parsed);
      endif
    endfor
    return false;
  endmethod

  method rooms_from owner: HACKER
    "Find all rooms transitively reachable from the starting room.";
    "Optional second arg: only_open (default true) - skip closed passages.";
    {start_room, ?only_open = true} = args;
    typeof(start_room) == TYPE_OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
      return {start_room};
    endif
    visited = [start_room -> true];
    frontier = {start_room};
    while (length(frontier) > 0)
      current = frontier[1];
      frontier = listdelete(frontier, 1);
      "Find passages from current room using datalog query";
      results = this.passages_rel:query({current, {'var, 'dest}, {'var, 'passage}});
      for binding in (results)
        dest = binding['dest];
        passage = binding['passage];
        if (only_open && !passage.is_open)
          continue;
        endif
        if (!maphaskey(visited, dest))
          visited[dest] = true;
          frontier = {@frontier, dest};
        endif
      endfor
      "Check reverse direction too (dest to current)";
      results = this.passages_rel:query({{'var, 'src}, current, {'var, 'passage}});
      for binding in (results)
        src = binding['src];
        passage = binding['passage];
        if (only_open && !passage.is_open)
          continue;
        endif
        if (!maphaskey(visited, src))
          visited[src] = true;
          frontier = {@frontier, src};
        endif
      endfor
    endwhile
    return mapkeys(visited);
  endmethod

  method connected owner: HACKER
    "Check if two rooms are transitively connected via passages.";
    "Optional third arg: only_open (default true) - skip closed passages.";
    {room_a, room_b, ?only_open = true} = args;
    typeof(room_a) == TYPE_OBJ && typeof(room_b) == TYPE_OBJ || raise(E_TYPE);
    reachable = this:rooms_from(room_a, only_open);
    return room_b in reachable;
  endmethod

  method find_path owner: ARCH_WIZARD
    "Find a path from start_room to goal_room. Returns list of {room, connector} pairs, or false.";
    "Connector is either a passage flyweight or {'transport, label, transport_obj} for transports.";
    "Optional third arg: only_open (default true) - skip closed passages.";
    "Optional fourth arg: include_transports (default true) - include transport connections.";
    {start_room, goal_room, ?only_open = true, ?include_transports = true} = args;
    typeof(start_room) == TYPE_OBJ && typeof(goal_room) == TYPE_OBJ || raise(E_TYPE);
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
      "No passage relation - still check for transport-only paths";
      if (start_room == goal_room)
        return {{start_room, false}};
      endif
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
      "Try passage forward edges: current -> next";
      if (typeof(this.passages_rel) == TYPE_OBJ && valid(this.passages_rel))
        results = this.passages_rel:query({current, {'var, 'next}, {'var, 'passage}});
        for binding in (results)
          next = binding['next];
          passage = binding['passage];
          if (only_open && !passage.is_open)
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
        "Try passage reverse edges: next -> current";
        results = this.passages_rel:query({{'var, 'next}, current, {'var, 'passage}});
        for binding in (results)
          next = binding['next];
          passage = binding['passage];
          if (only_open && !passage.is_open)
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
      endif
      "Try transport connections from this room";
      if (include_transports)
        transports = current:transport_destinations();
        if (typeof(transports) == TYPE_LIST)
          for conn in (transports)
            {next, label, transport_obj} = conn;
            if (!valid(next))
              continue;
            endif
            if (next == goal_room)
              return {@path, {current, {'transport, label, transport_obj}}, {goal_room, false}};
            endif
            if (!maphaskey(visited, next))
              visited[next] = true;
              queue = {@queue, {next, {@path, {current, {'transport, label, transport_obj}}}}};
            endif
          endfor
        endif
      endif
    endwhile
    return false;
  endmethod

  method _move_room_here owner: ARCH_WIZARD
    "Move a room into this area, raising if containment fails.";
    if (caller != this && !caller_perms().wizard)
      typeof(caller) == TYPE_FLYWEIGHT && caller.delegate == this || raise(E_PERM);
    endif
    {room, move_perms} = args;
    typeof(room) == TYPE_OBJ && valid(room) && isa(room, $room) || raise(E_TYPE);
    valid(move_perms) || raise(E_INVARG);
    set_task_perms(move_perms);
    result = room:moveto(this);
    if (typeof(result) == TYPE_ERR)
      raise(error_code(result), "Could not move room into area.");
    endif
    room.location == this || raise(E_INVARG, "Could not move room into area.");
    return room;
  endmethod

  method make_room_in owner: ARCH_WIZARD
    "Create a new room in this area. Requires 'add_room capability on area.";
    actor = caller_perms();
    set_task_perms(actor);
    {target, perms} = this:check_permissions_as(actor, 'add_room);
    {parent_obj} = args;
    typeof(parent_obj) == TYPE_OBJ && valid(parent_obj) && isa(parent_obj, $room) || raise(E_TYPE);
    "Create room with caller's ownership";
    new_room = parent_obj:create();
    try
      return target:_move_room_here(new_room, actor);
    except e (ANY)
      valid(new_room) && new_room:destroy();
      raise(e[1], length(e) >= 2 ? e[2] | "Could not create room in area.");
    endtry
  endmethod

  method add_room owner: ARCH_WIZARD
    "Add a room to this area. Requires 'add_room capability on area.";
    actor = caller_perms();
    {this, perms} = this:check_permissions_as(actor, 'add_room);
    {room} = args;
    typeof(room) == TYPE_OBJ || raise(E_TYPE);
    set_task_perms(perms);
    return this:_move_room_here(room, actor);
  endmethod

  method create_passage owner: ARCH_WIZARD
    "Create passage between two rooms. Requires 'create_passage on area, 'dig_from on room_a, 'dig_into on room_b.";
    "For bidirectional passages, also requires 'dig_from on room_b and 'dig_into on room_a.";
    "room_a and room_b should be capability flyweights or raw room objects that caller has permission for.";
    actor = caller_perms();
    {this, perms} = this:check_permissions_as(actor, 'create_passage);
    {room_a, room_b, passage} = args;
    "Extract actual room objects from capabilities if needed";
    actual_room_a = typeof(room_a) == TYPE_FLYWEIGHT ? room_a.delegate | room_a;
    actual_room_b = typeof(room_b) == TYPE_FLYWEIGHT ? room_b.delegate | room_b;
    "Check room_a allows digging from it and room_b allows digging into it";
    try
      room_a:check_permissions_as(actor, 'dig_from);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_from});
      raise(E_PERM, message);
    endtry
    try
      room_b:check_permissions_as(actor, 'dig_into);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_b, 'room, {'dig_into});
      raise(E_PERM, message);
    endtry
    "If bidirectional (has side_b label or aliases), also check the reverse direction";
    is_bidirectional = passage.side_b_label != "" || length(passage.side_b_aliases) > 0;
    if (is_bidirectional)
      try
        room_b:check_permissions_as(actor, 'dig_from);
      except (E_PERM)
        message = $grant_utils:format_denial(actual_room_b, 'room, {'dig_from});
        raise(E_PERM, message);
      endtry
      try
        room_a:check_permissions_as(actor, 'dig_into);
      except (E_PERM)
        message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_into});
        raise(E_PERM, message);
      endtry
    endif
    "Now create the passage with elevated area permissions";
    return this:_do_create_passage(actual_room_a, actual_room_b, passage, perms);
  endmethod

  method _do_create_passage owner: ARCH_WIZARD
    "Internal: Actually create the passage with elevated permissions.";
    this:require_caller(this);
    {room_a, room_b, passage, perms} = args;
    set_task_perms(perms);
    this:set_passage(room_a, room_b, passage);
    return passage;
  endmethod

  method update_passage owner: ARCH_WIZARD
    "Update an existing passage between two rooms.";
    "Requires 'dig_from on source room; does not create new links.";
    set_task_perms(caller_perms());
    {source_room, dest_room, new_passage} = args;
    typeof(source_room) == TYPE_OBJ || typeof(source_room) == TYPE_FLYWEIGHT || raise(E_TYPE);
    typeof(dest_room) == TYPE_OBJ || typeof(dest_room) == TYPE_FLYWEIGHT || raise(E_TYPE);
    typeof(new_passage) == TYPE_OBJ || typeof(new_passage) == TYPE_FLYWEIGHT || raise(E_TYPE);
    actual_source = typeof(source_room) == TYPE_FLYWEIGHT ? source_room.delegate | source_room;
    actual_dest = typeof(dest_room) == TYPE_FLYWEIGHT ? dest_room.delegate | dest_room;
    valid(actual_source) && valid(actual_dest) || raise(E_INVARG);
    existing = this:passage_for(actual_source, actual_dest);
    typeof(existing) != TYPE_FLYWEIGHT && (typeof(existing) != TYPE_OBJ || !valid(existing)) && raise(E_INVARG, "No existing passage between those rooms.");
    cap = caller_perms():find_capability_for(actual_source, 'room);
    room_target = typeof(cap) == TYPE_FLYWEIGHT ? cap | actual_source;
    room_target:check_can_dig_from();
    this:set_passage(actual_source, actual_dest, new_passage);
    return new_passage;
  endmethod

  method remove_passage owner: ARCH_WIZARD
    "Remove passage between two rooms. Requires 'remove_passage on area and 'dig_from on source room.";
    actor = caller_perms();
    {this, perms} = this:check_permissions_as(actor, 'remove_passage);
    {room_a, room_b} = args;
    "Extract actual room objects from capabilities if needed";
    actual_room_a = typeof(room_a) == TYPE_FLYWEIGHT ? room_a.delegate | room_a;
    actual_room_b = typeof(room_b) == TYPE_FLYWEIGHT ? room_b.delegate | room_b;
    "Check that source room allows digging from it (implies permission to remove passages)";
    try
      room_a:check_permissions_as(actor, 'dig_from);
    except (E_PERM)
      message = $grant_utils:format_denial(actual_room_a, 'room, {'dig_from});
      raise(E_PERM, message);
    endtry
    "Remove the passage with elevated permissions";
    return this:_do_remove_passage(actual_room_a, actual_room_b, perms);
  endmethod

  method _do_remove_passage owner: ARCH_WIZARD
    "Internal: Actually remove the passage with elevated permissions.";
    this:require_caller(this);
    {room_a, room_b, perms} = args;
    set_task_perms(perms);
    return this:clear_passage(room_a, room_b);
  endmethod

  method on_room_recycle owner: ARCH_WIZARD
    "Clean up all passages to/from a room that is being recycled.";
    set_task_perms(this.owner);
    {room} = args;
    typeof(room) == TYPE_OBJ || return;
    if (typeof(this.passages_rel) != TYPE_OBJ || !valid(this.passages_rel))
      return;
    endif
    tuples = this.passages_rel:select_containing(room);
    for tuple in (tuples)
      this.passages_rel:retract(tuple);
    endfor
  endmethod

  method find_passage_by_direction owner: HACKER
    "Find a passage from a room matching a direction/label/alias. Returns passage or false.";
    {room, direction} = args;
    typeof(room) == TYPE_OBJ || raise(E_TYPE);
    typeof(direction) == TYPE_STR || raise(E_TYPE);
    passages = this:passages_from(room);
    for p in (passages)
      if (p:matches_command(room, direction))
        return p;
      endif
    endfor
    return false;
  endmethod

  method get_exit_info owner: HACKER
    "Get exit labels and ambient passage descriptions for a room. Returns {exits, ambient_passages}.";
    "ambient_passages is a list of {description, prose_style, label} tuples where prose_style is 'sentence or 'fragment.";
    {room} = args;
    typeof(room) == TYPE_OBJ || raise(E_TYPE);
    passages = this:passages_from(room);
    exits = {};
    ambient_passages = {};
    for passage in (passages)
      is_open = passage.is_open;
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
  endmethod

  method test_connectivity owner: HACKER
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
  endmethod

  method test_rooms_from owner: HACKER
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
  endmethod

  method test_find_path owner: HACKER
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
  endmethod

  method test_closed_passages owner: HACKER
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
  endmethod

  method test_accepts_rooms owner: HACKER
    "Test that areas accept and add rooms as spatial contents, while rejecting non-rooms.";
    area = $area:create(true);
    room = $room:create(true);
    added = $room:create(true);
    made = #-1;
    thing = $thing:create(true);
    try
      move(room, area);
      $test_utils:assert_eq(room.location, area, "raw move should put rooms in area");
      $test_utils:assert_true(room in area:contents(), "raw move should add room to area contents");
      area:add_room(added);
      $test_utils:assert_eq(added.location, area, "add_room should put rooms in area");
      $test_utils:assert_true(added in area:contents(), "add_room should add room to area contents");
      made = area:make_room_in($room);
      $test_utils:assert_true(valid(made), "make_room_in should create a room");
      $test_utils:assert_eq(parent(made), $room, "make_room_in should use the requested room parent");
      $test_utils:assert_eq(made.location, area, "make_room_in should put created room in area");
      $test_utils:assert_true(made in area:contents(), "make_room_in should add created room to area contents");
      accepted_thing = true;
      try
        move(thing, area);
      except (E_NACC)
        accepted_thing = false;
      endtry
      $test_utils:assert_false(accepted_thing, "raw move should reject non-room contents");
      $test_utils:assert_raises(E_TYPE, area, "add_room", {thing}, "add_room should reject non-room contents");
      $test_utils:assert_raises(E_TYPE, area, "make_room_in", {$thing}, "make_room_in should reject non-room parents");
    finally
      $test_utils:destroy_if_valid(made);
      $test_utils:destroy_if_valid(thing);
      $test_utils:destroy_if_valid(added);
      $test_utils:destroy_if_valid(room);
      $test_utils:destroy_if_valid(area);
    endtry
  endmethod

  method destroy owner: ARCH_WIZARD
    "Destroy this area, cleaning up the passages relation first.";
    "Clean up passages relation if it exists";
    if (typeof(this.passages_rel) == TYPE_OBJ && valid(this.passages_rel))
      this.passages_rel:destroy();
    endif
    "Call parent destroy";
    pass();
  endmethod
endobject
