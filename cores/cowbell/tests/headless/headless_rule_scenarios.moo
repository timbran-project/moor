object HEADLESS_RULE_SCENARIOS [
  import_export_id -> "headless_rule_scenarios"
]
  name: "Headless Rule Runtime Scenarios"
  parent: core::ROOT
  owner: core::HACKER
  readable: true

  override description (owner: core::HACKER, flags: "rc") = "Rules select and join facts from runtime-created objects.";

  method query_parents owner: core::ARCH_WIZARD
    "Read the test object's parents with the invoking principal's permissions.";
    set_task_perms(caller_perms());
    const {name, inputs, limit} = args;
    const child = inputs['child];
    return ['rows -> {['parent -> child.father], ['parent -> child.mother]}, 'complete -> true];
  endmethod

  method test_headless_rule_engine_with_fixture owner: core::ARCH_WIZARD
    "Select parents, join a second generation, and reject a nonmatching parent.";
    const child = create($root, $hacker, 2);
    const parent = create($root, $hacker, 2);
    try
      for object in ({child, parent})
        add_property(object, "father", $root, {$hacker, "r"});
        add_property(object, "mother", $thing, {$hacker, "r"});
      endfor
      child.father = parent;
      $rule_engine:register_predicate('test_parents, ['description -> "Parents of the fixture.", 'inputs -> ['child -> 'object], 'outputs -> ['parent -> 'object]], this, "query_parents");
      const scope = $rule_engine:scope(['Child -> 'object, 'Other -> 'object]);
      const expression = "test_parents(child: input.Child) -> (parent: Parent)";
      const rule = $rule_engine:parse_expression(expression, 'parents, scope);
      const result = $rule_engine:evaluate(rule, ['Child -> child]);
      $test_utils:assert_true(result['success], "The fixture has parents");
      const parents = { row['Parent] for row in ({result['bindings], @result['alternatives]}) };
      $test_utils:assert_eq(length(parents), 2, "Both parents are selected");
      $test_utils:assert_true(parent in parents, "The father is selected");
      $test_utils:assert_true($thing in parents, "The mother is selected");
      const missing = $rule_engine:parse_expression(expression + " AND binding.Parent == input.Other", 'missing, scope);
      const absent = $rule_engine:evaluate(missing, ['Child -> child, 'Other -> $room]);
      $test_utils:assert_false(absent['success], "An unrelated object does not match");
      $test_utils:assert_eq(absent['bindings], [], "No binding on failure");
      $test_utils:assert_eq(absent['alternatives], {}, "No alternatives on failure");
      const joined = $rule_engine:parse_expression(expression + " AND binding.Parent == input.Other" + " AND test_parents(child: binding.Parent) -> (parent: Grandparent)", 'joined, scope);
      const ancestors = $rule_engine:evaluate(joined, ['Child -> child, 'Other -> parent]);
      $test_utils:assert_eq(1 + length(ancestors['alternatives]), 2, "A later query receives the earlier query's bound parent");
      $test_utils:assert_eq(ancestors['bindings]['Parent], parent, "The join preserves its input");
    finally
      $rule_engine:unregister_predicate('test_parents);
      recycle(child);
      recycle(parent);
    endtry
    return true;
  endmethod

  method _errand_world owner: core::ARCH_WIZARD
    "Three rooms in a row, an NPC in the first, and a closed cupboard holding wine in the last.";
    const area = create($area);
    const rooms = { area:make_room_in($room) for i in [1..3] };
    for i in [1..2]
      area:create_passage(rooms[i], rooms[i + 1], $passage:mk(rooms[i], "east", {"east"}, "", true, rooms[i + 1], "west", {"west"}, "", true, true));
    endfor
    const npc = create($actor);
    const cupboard = create($container);
    const wine = create($thing);
    move(npc, rooms[1]);
    move(cupboard, rooms[3]);
    cupboard.open = false;
    cupboard.locked = false;
    move(wine, cupboard);
    return ['area -> area, 'rooms -> rooms, 'npc -> npc, 'cupboard -> cupboard, 'wine -> wine];
  endmethod

  method _await_plan owner: core::ARCH_WIZARD
    "Wait for an NPC's plan to end and return how it ended.";
    const {npc} = args;
    for attempt in [1..400]
      if (npc.plan['status] != 'running)
        break;
      endif
      suspend(0.02);
    endfor
    return npc.plan['status];
  endmethod

  method _clear_errand_world owner: core::ARCH_WIZARD
    "Remove an errand world.";
    const {world} = args;
    for thing in ({world['wine], world['cupboard], world['npc], @world['rooms], world['area]})
      valid(thing) && thing:destroy();
    endfor
  endmethod

  method test_headless_npc_runs_an_errand owner: core::ARCH_WIZARD
    "An NPC walks two rooms to a closed cupboard, opens it, takes the wine, brings it back and drops it, one action per tick.";
    const tick = $planner.tick_seconds;
    $planner.tick_seconds = 0.01;
    const world = this:_errand_world();
    try
      const {npc, wine} = {world['npc], world['wine]};
      const home = world['rooms][1];
      $planner:pursue(npc, $errands, 'fetch, ['item -> wine, 'to -> home]);
      $test_utils:assert_eq(this:_await_plan(npc), 'done, "The errand finishes: " + toliteral($planner:why(npc)));
      $test_utils:assert_eq(wine.location, home, "The wine is home");
      $test_utils:assert_eq(npc.location, home, "The NPC came back");
      $test_utils:assert_true(world['cupboard].open, "The NPC opened the cupboard on the way");
    finally
      $planner.tick_seconds = tick;
      this:_clear_errand_world(world);
    endtry
    return true;
  endmethod

  method test_headless_npc_gives_up_and_says_why owner: core::ARCH_WIZARD
    "When the cupboard is locked, every approach fails in turn; the plan ends failed, with the reason, and the NPC hears it.";
    const tick = $planner.tick_seconds;
    $planner.tick_seconds = 0.01;
    const world = this:_errand_world();
    try
      const {npc, wine, cupboard} = {world['npc], world['wine], world['cupboard]};
      cupboard.locked = true;
      add_property(npc, "failures", 0, {npc.owner, "r"});
      $reaction:install(npc, "plan_failed_reaction", $reaction:mk('on_plan_failed, 0, {{'increment, 'failures}}));
      $planner:pursue(npc, $errands, 'fetch, ['item -> wine, 'to -> world['rooms][1]]);
      $test_utils:assert_eq(this:_await_plan(npc), 'failed, "A locked cupboard defeats the errand");
      $test_utils:assert_eq(wine.location, cupboard, "The wine stays put");
      $test_utils:assert_eq(npc.failures, 1, "The NPC hears that its plan failed");
      const why = $planner:why(npc);
      $test_utils:assert_true(index(why:join(" "), "No approach to fetch") > 0, "The plan says why: " + toliteral(why));
      $test_utils:assert_true($plan_failures:member({npc, 'open_up, 'open_it, value_hash([])}), "The failed approach is remembered");
    finally
      $planner.tick_seconds = tick;
      this:_clear_errand_world(world);
    endtry
    return true;
  endmethod
endobject
