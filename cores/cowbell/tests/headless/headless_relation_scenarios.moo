object HEADLESS_RELATION_SCENARIOS
  name: "Headless Relation Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Headless runtime scenarios for relation queries over runtime-created fixtures.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_relation_scenarios";

  verb test_headless_relation_graph_query (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: anonymous relations support indexed query and reachability over object fixtures.";
    rel = $relation:create(true);
    graph = $relation:create(true);
    room_a = $room:create(true);
    room_b = $room:create(true);
    room_c = $room:create(true);
    rel:assert({room_a, room_b, "north"});
    rel:assert({room_b, room_c, "east"});
    rel:assert({room_a, room_c, "shortcut"});
    $test_utils:assert_eq(rel:count(), 3, "relation should have three asserted tuples before query");
    $test_utils:assert_eq(length(rel:tuples()), 3, "relation should enumerate three asserted tuples before query");
    from_a = rel:query({room_a, {'var, 'dest}, {'var, 'label}});
    $test_utils:assert_eq(length(from_a), 2, "query should find two outgoing room_a tuples");
    $test_utils:assert_true(['dest -> room_b, 'label -> "north"] in from_a, "query should bind room_b north");
    $test_utils:assert_true(['dest -> room_c, 'label -> "shortcut"] in from_a, "query should bind room_c shortcut");
    graph:assert({room_a, room_b});
    graph:assert({room_b, room_c});
    reachable = graph:reachable_from(room_a);
    $test_utils:assert_true(room_a in reachable, "reachable set should include start room");
    $test_utils:assert_true(room_b in reachable, "reachable set should include room_b");
    $test_utils:assert_true(room_c in reachable, "reachable set should include room_c");
    rel:clear();
    graph:clear();
    $test_utils:assert_eq(rel:count(), 0, "clear should remove all relation tuples");
    $test_utils:assert_eq(graph:count(), 0, "clear should remove all graph tuples");
    return true;
  endverb

  verb test_headless_relation_retract_updates_indexes (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: retracting fixture tuples updates membership and indexed query results.";
    rel = $relation:create(true);
    actor = $thing:create(true);
    target_a = $thing:create(true);
    target_b = $thing:create(true);
    rel:assert({actor, target_a, "holds"});
    rel:assert({actor, target_b, "wears"});
    $test_utils:assert_eq(length(rel:tuples()), 2, "relation should enumerate two asserted tuples before retract");
    $test_utils:assert_true(rel:member({actor, target_a, "holds"}), "first tuple should be present");
    $test_utils:assert_true(rel:member({actor, target_b, "wears"}), "second tuple should be present");
    $test_utils:assert_true(rel:retract({actor, target_a, "holds"}), "retract should remove existing tuple");
    $test_utils:assert_false(rel:member({actor, target_a, "holds"}), "retracted tuple should be absent");
    remaining = rel:query({actor, {'var, 'target}, {'var, 'label}});
    $test_utils:assert_eq(length(remaining), 1, "query should return only the unretracted tuple");
    $test_utils:assert_true(['target -> target_b, 'label -> "wears"] in remaining, "query should retain indexed second tuple");
    $test_utils:assert_false(rel:retract({actor, target_a, "holds"}), "retracting a missing tuple should return false");
    return true;
  endverb
endobject
