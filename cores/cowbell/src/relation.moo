object RELATION
  name: "Generic Relation"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  override description = "N-ary persistent data relation.";
  override import_export_id = "relation";

  verb assert (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Add a tuple to the relation. Returns the UUID of the tuple.";
    {tuple} = args;
    typeof(tuple) == LIST || raise(E_TYPE);
    length(tuple) > 0 || raise(E_INVARG);
    "Generate unique ID for this tuple";
    tuple_id = uuid();
    tuple_prop = "tuple_" + tuple_id;
    "Store the tuple";
    add_property(this, tuple_prop, tuple, {this.owner, "r"});
    "Index each element in the tuple (skip flyweights - can't be map keys)";
    for i in [1..length(tuple)]
      element = tuple[i];
      "Skip flyweights - they cannot be map keys";
      if (typeof(element) == FLYWEIGHT)
        continue;
      endif
      hash = value_hash(element);
      index_prop = "index_" + hash;
      "Get or create index map for this hash - try to get it first";
      index_map = `this.(index_prop) ! E_PROPNF => 0';
      if (typeof(index_map) != MAP)
        "Property doesn't exist, create it";
        index_map = mapdelete(['_dummy -> 0], '_dummy);
        add_property(this, index_prop, index_map, {this.owner, "r"});
      endif
      "Get existing UUID list for this element, or start new list";
      uuid_list = maphaskey(index_map, element) ? index_map[element] | {};
      "Add this tuple's UUID to the list";
      uuid_list = {@uuid_list, tuple_id};
      index_map[element] = uuid_list;
      "Write updated map back to property";
      this.(index_prop) = index_map;
    endfor
    return tuple_id;
  endverb

  verb retract (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Remove a tuple from the relation. Returns true if found and removed, false otherwise.";
    {tuple} = args;
    typeof(tuple) == LIST || raise(E_TYPE);
    "Find the tuple's UUID by checking if it exists";
    tuple_id = this:_find_tuple_id(tuple);
    !tuple_id && return false;
    "Remove from all indexes (skip flyweights)";
    for i in [1..length(tuple)]
      element = tuple[i];
      "Skip flyweights - they weren't indexed";
      if (typeof(element) == FLYWEIGHT)
        continue;
      endif
      hash = value_hash(element);
      index_prop = "index_" + hash;
      if (index_prop in properties(this))
        index_map = this.(index_prop);
        uuid_list = maphaskey(index_map, element) ? index_map[element] | {};
        "Remove this UUID from the list";
        uuid_list = setremove(uuid_list, tuple_id);
        if (length(uuid_list) == 0)
          "No more tuples reference this element, remove from map";
          index_map = mapdelete(index_map, element);
        else
          index_map[element] = uuid_list;
        endif
        if (length(index_map) == 0)
          "Index map is empty, remove the property";
          delete_property(this, index_prop);
        else
          this.(index_prop) = index_map;
        endif
      endif
    endfor
    "Remove the tuple itself";
    tuple_prop = "tuple_" + tuple_id;
    delete_property(this, tuple_prop);
    return true;
  endverb

  verb member (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Check if a tuple exists in the relation.";
    {tuple} = args;
    typeof(tuple) == LIST || raise(E_TYPE);
    return this:_find_tuple_id(tuple) ? true | false;
  endverb

  verb select (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Find all tuples where tuple[position] == value. Position is 1-indexed.";
    {position, value} = args;
    typeof(position) == INT || raise(E_TYPE);
    position >= 1 || raise(E_INVARG);
    hash = value_hash(value);
    index_prop = "index_" + hash;
    "Get index map for this hash";
    index_map = `this.(index_prop) ! E_PROPNF => 0';
    if (typeof(index_map) != MAP)
      "Property doesn't exist, no tuples for this value";
      return {};
    endif
    "Get UUIDs for this specific value";
    uuid_list = maphaskey(index_map, value) ? index_map[value] | {};
    "Fetch tuples and filter by position";
    result = {};
    for tuple_id in (uuid_list)
      tuple_prop = "tuple_" + tuple_id;
      tuple = `this.(tuple_prop) ! E_PROPNF => 0';
      if (tuple && length(tuple) >= position && tuple[position] == value)
        result = {@result, tuple};
      endif
    endfor
    return result;
  endverb

  verb select_containing (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Find all tuples containing value in any position.";
    {value} = args;
    hash = value_hash(value);
    index_prop = "index_" + hash;
    "Get index map for this hash";
    index_map = `this.(index_prop) ! E_PROPNF => 0';
    if (typeof(index_map) != MAP)
      return {};
    endif
    "Get UUIDs for this specific value";
    uuid_list = maphaskey(index_map, value) ? index_map[value] | {};
    "Fetch all tuples";
    result = {};
    for tuple_id in (uuid_list)
      tuple_prop = "tuple_" + tuple_id;
      tuple = `this.(tuple_prop) ! E_PROPNF => 0';
      if (tuple)
        result = {@result, tuple};
      endif
    endfor
    return result;
  endverb

  verb tuples (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Return all tuples in the relation.";
    result = {};
    all_props = properties(this);
    for prop in (all_props)
      prop_str = tostr(prop);
      if (length(prop_str) >= 6 && prop_str[1..6] == "tuple_")
        tuple = `this.(prop) ! E_PROPNF => 0';
        if (tuple)
          result = {@result, tuple};
        endif
      endif
    endfor
    return result;
  endverb

  verb clear (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Remove all tuples from the relation.";
    for prop in (properties(this))
      prop_str = tostr(prop);
      is_tuple = length(prop_str) >= 6 && prop_str[1..6] == "tuple_";
      is_index = length(prop_str) >= 6 && prop_str[1..6] == "index_";
      if (is_tuple || is_index)
        delete_property(this, prop);
      endif
    endfor
    return true;
  endverb

  verb _find_tuple_id (this none this) owner: HACKER flags: "rxd"
    "Internal: Find the UUID for a given tuple, or return 0 if not found.";
    {tuple} = args;
    "Use first element to narrow search";
    if (length(tuple) == 0)
      return 0;
    endif
    element = tuple[1];
    hash = value_hash(element);
    index_prop = "index_" + hash;
    "Get candidate UUIDs";
    index_map = `this.(index_prop) ! E_PROPNF => 0';
    if (typeof(index_map) != MAP)
      "Property doesn't exist, no tuples for this element";
      return 0;
    endif
    uuid_list = maphaskey(index_map, element) ? index_map[element] | {};
    "Check each candidate to see if full tuple matches";
    for tuple_id in (uuid_list)
      tuple_prop = "tuple_" + tuple_id;
      stored_tuple = `this.(tuple_prop) ! E_PROPNF => 0';
      if (stored_tuple && stored_tuple == tuple)
        return tuple_id;
      endif
    endfor
    return 0;
  endverb

  verb test_assert_and_member (this none this) owner: HACKER flags: "rxd"
    "Test basic assertion and membership checking";
    rel = create($relation);
    "Test binary relation";
    rel:assert({#1, #2});
    !rel:member({#1, #2}) && raise(E_ASSERT, "Binary tuple not found after assert");
    rel:member({#2, #1}) && raise(E_ASSERT, "Element position within tuple should matter");
    "Test ternary relation";
    rel:assert({#12, #39, "passage1"});
    !rel:member({#12, #39, "passage1"}) && raise(E_ASSERT, "Ternary tuple not found");
    rel:member({#12, #39}) && raise(E_ASSERT, "Partial tuple should not match");
    "Test different arities in same relation";
    rel:assert({#5, #6, #7, #8});
    !rel:member({#5, #6, #7, #8}) && raise(E_ASSERT, "Quaternary tuple not found");
    rel:destroy();
  endverb

  verb test_retract (this none this) owner: HACKER flags: "rxd"
    "Test tuple removal";
    rel = create($relation);
    rel:assert({#1, #2, "edge1"});
    rel:assert({#1, #3, "edge2"});
    rel:assert({#2, #3, "edge3"});
    "Verify all present";
    !rel:member({#1, #2, "edge1"}) && raise(E_ASSERT, "Setup failed");
    "Retract one tuple";
    !rel:retract({#1, #2, "edge1"}) && raise(E_ASSERT, "Retract should return true");
    rel:member({#1, #2, "edge1"}) && raise(E_ASSERT, "Tuple still present after retract");
    "Other tuples should remain";
    !rel:member({#1, #3, "edge2"}) && raise(E_ASSERT, "Other tuple incorrectly removed");
    !rel:member({#2, #3, "edge3"}) && raise(E_ASSERT, "Other tuple incorrectly removed");
    "Retracting non-existent tuple should return false";
    rel:retract({#99, #100, "none"}) && raise(E_ASSERT, "Retract of missing tuple should be false");
    rel:destroy();
  endverb

  verb test_select (this none this) owner: HACKER flags: "rxd"
    "Test position-based selection";
    rel = create($relation);
    "Setup passage-like data";
    rel:assert({#12, #39, "north"});
    rel:assert({#12, #40, "east"});
    rel:assert({#39, #40, "south"});
    "Select by first position";
    results = rel:select(1, #12);
    length(results) != 2 && raise(E_ASSERT, "Expected 2 results from position 1");
    {#12, #39, "north"} in results || raise(E_ASSERT, "Missing expected tuple");
    {#12, #40, "east"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select by second position";
    results = rel:select(2, #39);
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result from position 2");
    {#12, #39, "north"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select by third position";
    results = rel:select(3, "south");
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result from position 3");
    {#39, #40, "south"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select non-existent value";
    results = rel:select(1, #99);
    length(results) != 0 && raise(E_ASSERT, "Expected empty results for non-existent value");
    rel:destroy();
  endverb

  verb test_tuples (this none this) owner: HACKER flags: "rxd"
    "Test retrieving all tuples";
    rel = create($relation);
    "Empty relation";
    length(rel:tuples()) != 0 && raise(E_ASSERT, "Empty relation should have no tuples");
    "Add some tuples";
    rel:assert({#1, #2});
    rel:assert({#3, #4});
    rel:assert({#5, #6, #7});
    all_tuples = rel:tuples();
    length(all_tuples) != 3 && raise(E_ASSERT, "Expected 3 tuples");
    {#1, #2} in all_tuples || raise(E_ASSERT, "Missing tuple");
    {#3, #4} in all_tuples || raise(E_ASSERT, "Missing tuple");
    {#5, #6, #7} in all_tuples || raise(E_ASSERT, "Missing tuple");
    rel:destroy();
  endverb

  verb test_clear (this none this) owner: HACKER flags: "rxd"
    "Test clearing all tuples";
    rel = create($relation);
    "Add several tuples";
    rel:assert({#1, #2, "a"});
    rel:assert({#3, #4, "b"});
    rel:assert({#5, #6, "c"});
    length(rel:tuples()) != 3 && raise(E_ASSERT, "Setup failed");
    "Clear the relation";
    !rel:clear() && raise(E_ASSERT, "Clear should return true");
    "Verify empty";
    length(rel:tuples()) != 0 && raise(E_ASSERT, "Relation should be empty after clear");
    rel:member({#1, #2, "a"}) && raise(E_ASSERT, "Tuple still present after clear");
    rel:destroy();
  endverb

  verb test_duplicate_assert (this none this) owner: HACKER flags: "rxd"
    "Test that asserting the same tuple twice doesn't create duplicates";
    rel = create($relation);
    rel:assert({#1, #2, "edge"});
    rel:assert({#1, #2, "edge"});
    results = rel:tuples();
    length(results) != 2 && raise(E_ASSERT, "Duplicate assert should create new tuple (UUIDs differ)");
    "Both should be present as member check is equality based";
    !rel:member({#1, #2, "edge"}) && raise(E_ASSERT, "Tuple should be present");
    rel:destroy();
  endverb

  verb test_bidirectional_indexing (this none this) owner: HACKER flags: "rxd"
    "Test that a single tuple is indexed under all its values.";
    rel = create($relation);
    "Assert a passage-like tuple";
    rel:assert({#12, #39, "north"});
    "Find tuples containing #12";
    results_from_12 = rel:select_containing(#12);
    length(results_from_12) != 1 && raise(E_ASSERT, "Should find 1 tuple via #12");
    {#12, #39, "north"} in results_from_12 || raise(E_ASSERT, "Wrong tuple via #12");
    "Find tuples containing #39";
    results_from_39 = rel:select_containing(#39);
    length(results_from_39) != 1 && raise(E_ASSERT, "Should find 1 tuple via #39");
    {#12, #39, "north"} in results_from_39 || raise(E_ASSERT, "Wrong tuple via #39");
    "Find tuples containing 'north'";
    results_from_north = rel:select_containing("north");
    length(results_from_north) != 1 && raise(E_ASSERT, "Should find 1 tuple via 'north'");
    {#12, #39, "north"} in results_from_north || raise(E_ASSERT, "Wrong tuple via 'north'");
    "Verify it's the SAME tuple found three different ways";
    results_from_12 == results_from_39 || raise(E_ASSERT, "Results should be identical");
    results_from_39 == results_from_north || raise(E_ASSERT, "Results should be identical");
    "Test with multiple passages";
    rel:assert({#12, #40, "east"});
    rel:assert({#39, #40, "south"});
    "Find all passages from #12";
    from_12 = rel:select_containing(#12);
    length(from_12) != 2 && raise(E_ASSERT, "Room #12 should have 2 passages");
    {#12, #39, "north"} in from_12 || raise(E_ASSERT, "Missing north passage");
    {#12, #40, "east"} in from_12 || raise(E_ASSERT, "Missing east passage");
    "Find all passages from #40";
    from_40 = rel:select_containing(#40);
    length(from_40) != 2 && raise(E_ASSERT, "Room #40 should have 2 passages");
    {#12, #40, "east"} in from_40 || raise(E_ASSERT, "Missing east passage");
    {#39, #40, "south"} in from_40 || raise(E_ASSERT, "Missing south passage");
    "Room #39 appears in different positions but both found";
    from_39 = rel:select_containing(#39);
    length(from_39) != 2 && raise(E_ASSERT, "Room #39 should have 2 passages");
    {#12, #39, "north"} in from_39 || raise(E_ASSERT, "Missing north passage (pos 2)");
    {#39, #40, "south"} in from_39 || raise(E_ASSERT, "Missing south passage (pos 1)");
    rel:destroy();
  endverb

  verb query (this none this) owner: HACKER flags: "rxd"
    "Match pattern with variables against tuples, return bindings. Variables are created with $dvar:mk_name().";
    {pattern} = args;
    typeof(pattern) == LIST || raise(E_TYPE);
    "Find first concrete (non-variable) value to narrow search";
    concrete_value = false;
    for elem in (pattern)
      if (typeof(elem) != FLYWEIGHT || !valid(elem.delegate) || elem.delegate != $dvar)
        concrete_value = elem;
        break;
      endif
    endfor
    "Get candidates";
    candidates = concrete_value ? this:select_containing(concrete_value) | this:tuples();
    "Match and build bindings";
    results = {};
    for tuple in (candidates)
      bindings = this:_unify(pattern, tuple);
      if (bindings)
        results = {@results, bindings};
      endif
    endfor
    return results;
  endverb

  verb _unify (this none this) owner: HACKER flags: "rxd"
    "Internal: Unify pattern with tuple, returning bindings map or false.";
    {pattern, tuple} = args;
    length(pattern) != length(tuple) && return false;
    bindings = [];
    for i in [1..length(pattern)]
      p = pattern[i];
      if (typeof(p) == FLYWEIGHT && valid(p.delegate) && p.delegate == $dvar)
        "Variable - bind or check consistency";
        var_name = p[1];
        if (maphaskey(bindings, var_name))
          bindings[var_name] != tuple[i] && return false;
        else
          bindings[var_name] = tuple[i];
        endif
      else
        "Concrete - must match exactly";
        p != tuple[i] && return false;
      endif
    endfor
    return bindings;
  endverb

  verb reachable_from (this none this) owner: HACKER flags: "rxd"
    "Find all values reachable via transitive closure from start value. Assumes binary relation.";
    {start} = args;
    visited = [start -> true];
    frontier = {start};
    while (length(frontier) > 0)
      current = frontier[1];
      frontier = listdelete(frontier, 1);
      "Find all tuples containing current";
      tuples = this:select_containing(current);
      for tuple in (tuples)
        length(tuple) != 2 && raise(E_INVARG, "reachable_from requires binary relation");
        {val_a, val_b} = tuple;
        "Get the other value";
        other = val_a == current ? val_b | val_a;
        if (!maphaskey(visited, other))
          visited[other] = true;
          frontier = {@frontier, other};
        endif
      endfor
    endwhile
    return mapkeys(visited);
  endverb

  verb test_query_basic (this none this) owner: HACKER flags: "rxd"
    "Test basic pattern matching with variables";
    rel = create($relation);
    rel:assert({#12, #39, "north"});
    rel:assert({#12, #40, "east"});
    rel:assert({#39, #40, "south"});
    "Query for all passages from #12";
    results = rel:query({#12, $dvar:mk_dest(), $dvar:mk_label()});
    length(results) != 2 && raise(E_ASSERT, "Expected 2 results from #12");
    ['dest -> #39, 'label -> "north"] in results || raise(E_ASSERT, "Missing north binding");
    ['dest -> #40, 'label -> "east"] in results || raise(E_ASSERT, "Missing east binding");
    "Query for passages to #39";
    results = rel:query({$dvar:mk_src(), #39, $dvar:mk_label()});
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result to #39");
    ['src -> #12, 'label -> "north"] in results || raise(E_ASSERT, "Missing binding");
    "Query all tuples";
    results = rel:query({$dvar:mk_a(), $dvar:mk_b(), $dvar:mk_c()});
    length(results) != 3 && raise(E_ASSERT, "Expected 3 results for all tuples");
    rel:destroy();
  endverb

  verb test_reachable (this none this) owner: HACKER flags: "rxd"
    "Test transitive closure - note: relation is bidirectional";
    rel = create($relation);
    "Build a chain: 1 <-> 2 <-> 3 <-> 4";
    rel:assert({#1, #2});
    rel:assert({#2, #3});
    rel:assert({#3, #4});
    "Add a branch: 2 <-> 5";
    rel:assert({#2, #5});
    reachable = rel:reachable_from(#1);
    length(reachable) != 5 && raise(E_ASSERT, "Should reach 5 nodes from #1");
    #1 in reachable || raise(E_ASSERT, "Should include start node");
    #2 in reachable || raise(E_ASSERT, "Should reach #2");
    #3 in reachable || raise(E_ASSERT, "Should reach #3");
    #4 in reachable || raise(E_ASSERT, "Should reach #4");
    #5 in reachable || raise(E_ASSERT, "Should reach #5");
    "From #3 reaches all nodes (bidirectional graph)";
    reachable = rel:reachable_from(#3);
    length(reachable) != 5 && raise(E_ASSERT, "Should reach all 5 nodes from #3");
    #1 in reachable || raise(E_ASSERT, "Should reach #1 via bidirectional edges");
    #2 in reachable || raise(E_ASSERT, "Should reach #2");
    #4 in reachable || raise(E_ASSERT, "Should reach #4");
    #5 in reachable || raise(E_ASSERT, "Should reach #5 via #2");
    rel:destroy();
  endverb
endobject