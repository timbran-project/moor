object PLANNER [
  import_export_id -> "planner",
  import_export_hierarchy -> {"rules"}
]
  name: "Planner"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property tick_seconds (owner: ARCH_WIZARD, flags: "r") = 1.0;
  property failure_seconds (owner: ARCH_WIZARD, flags: "r") = 300;
  property max_depth (owner: ARCH_WIZARD, flags: "r") = 32;
  property max_expansions (owner: ARCH_WIZARD, flags: "r") = 32;

  override description (owner: ARCH_WIZARD, flags: "rc") = "Runs NPC plans: goals from a playbook, achieved one action per tick.";
  override object_documentation (owner: ARCH_WIZARD, flags: "rc") = {
    "# Planner",
    "",
    "`pursue(npc, playbook, goal, inputs)` has an owned NPC work towards a goal, replacing its current plan. `abandon(npc)` stops it. `why(npc)` describes the plan.",
    "",
    "Each tick the planner chooses approaches for open goals, in the order the playbook defines them, and runs at most one action. Before an action runs, its requirement is checked against the world as it is. A failed step marks its approach and matches as failed for a while, and the goal tries its next approach on the next tick. When no approach applies, the goal fails and its parent's approach fails in turn.",
    "",
    "Steps run with the NPC owner's permissions. A plan can use playbooks owned by the NPC's owner or by a wizard. Players do not run plans. The NPC hears `on_plan_done` or `on_plan_failed` when its plan ends."
  };

  method pursue owner: ARCH_WIZARD
    "Have an owned NPC pursue a goal from a playbook, replacing any current plan.";
    const {npc, playbook, goal, ?inputs = []} = args;
    const principal = caller_perms();
    typeof(npc) == TYPE_OBJ && valid(npc) && isa(npc, $actor) || raise(E_INVARG, "Only actors pursue goals.");
    !is_player(npc) || raise(E_INVARG, "Players do not run plans.");
    principal == npc.owner || principal.wizard || raise(E_PERM);
    $planner:_usable(npc, playbook) || raise(E_PERM, "A plan can use only its owner's playbooks or a wizard's.");
    maphaskey(playbook.goals, goal) || raise(E_INVARG, "Unknown goal: " + tostr(goal));
    $behavior_schema:bindings(inputs, playbook.goals[goal]['inputs], "goal inputs");
    $planner:_stop(npc);
    npc.plan = ['playbook -> playbook, 'owner -> npc.owner, 'status -> 'running, 'frames -> {$planner:_frame(goal, mapmerge(inputs, ['actor -> npc]))}, 'setback -> ""];
    npc.plan_schedule = schedule_at($planner, "_tick", ftime(), {npc}, ['pass_elapsed -> 0]);
    return true;
  endmethod

  method abandon owner: ARCH_WIZARD
    "Stop an NPC's plan.";
    const {npc} = args;
    const principal = caller_perms();
    principal == npc.owner || principal.wizard || raise(E_PERM);
    $planner:_stop(npc);
    npc.plan = 0;
    return true;
  endmethod

  method why owner: ARCH_WIZARD
    "Describe what an NPC is pursuing, how, and its latest setback.";
    const {npc} = args;
    const plan = npc.plan;
    typeof(plan) == TYPE_MAP || return {npc.name + " has no plan."};
    let lines = {};
    for frame in (plan['frames])
      let line = $planner:_call_text(frame['goal], mapdelete(frame['inputs], 'actor));
      if (frame['approach] != 0)
        line = line + " by " + tostr(frame['approach]);
        if (length(frame['bindings]) > 0)
          line = line + " with " + { tostr(name) + " = " + $planner:_value_text(frame['bindings][name]) for name in (mapkeys(frame['bindings])) }:join(", ");
        endif
        const approach = $planner:_approach(plan['playbook], frame);
        if (approach != 0 && frame['step] <= length(approach['steps]))
          line = line + "; step " + tostr(frame['step]) + " of " + tostr(length(approach['steps])) + ": " + approach['steps][frame['step]]['text];
        endif
      endif
      lines = {@lines, line};
    endfor
    plan['status] == 'running || (lines = {@lines, "The plan is " + tostr(plan['status]) + "."});
    plan['setback] && (lines = {@lines, "Latest setback: " + plan['setback]});
    return lines;
  endmethod

  method _tick owner: ARCH_WIZARD
    "Advance one NPC's plan by at most one action. Return the delay before the next tick, or 0 when the plan ends.";
    caller_perms().wizard || raise(E_PERM);
    const {npc} = args;
    valid(npc) && typeof(npc.plan) == TYPE_MAP && npc.plan['status] == 'running || return 0;
    let plan = npc.plan;
    if (npc.owner != plan['owner] || !$planner:_usable(npc, plan['playbook]))
      return $planner:_finish(npc, plan, 'failed, "The NPC's owner or its playbook changed.");
    endif
    for expansion in [1..$planner.max_expansions]
      if (length(plan['frames]) == 0)
        return $planner:_finish(npc, plan, 'done, plan['setback]);
      endif
      let frame = plan['frames][$];
      if (frame['approach] == 0)
        const choice = $planner:_choose(npc, plan, frame);
        if (choice == 0)
          plan = $planner:_fail_goal(npc, plan, "No approach to " + $planner:_call_text(frame['goal], mapdelete(frame['inputs], 'actor)) + " applies.");
          length(plan['frames]) > 0 || return $planner:_finish(npc, plan, 'failed, plan['setback]);
          continue;
        endif
        frame['approach] = choice[1];
        frame['bindings] = choice[2];
        frame['step] = 1;
        plan['frames][length(plan['frames])] = frame;
        continue;
      endif
      const approach = $planner:_approach(plan['playbook], frame);
      if (approach == 0)
        plan = $planner:_fail_approach(npc, plan, "The approach " + tostr(frame['approach]) + " is gone or no longer valid.");
        continue;
      endif
      if (frame['step] > length(approach['steps]))
        plan['frames] = plan['frames][1..$ - 1];
        if (length(plan['frames]) > 0)
          let parent = plan['frames][$];
          parent['step] = parent['step] + 1;
          plan['frames][length(plan['frames])] = parent;
        endif
        continue;
      endif
      const step = approach['steps][frame['step]];
      const environment = ['input -> frame['inputs], 'parameter -> plan['playbook].settings, 'state -> [], 'binding -> frame['bindings]];
      let values = [];
      for field in (mapkeys(step['arguments]))
        values[field] = $condition:resolve(step['arguments][field], environment);
      endfor
      if (step['kind] == 'goal)
        if (length(plan['frames]) >= $planner.max_depth)
          plan = $planner:_fail_approach(npc, plan, "Goals are nested too deeply.");
          continue;
        endif
        plan['frames] = {@plan['frames], $planner:_frame(step['name], values)};
        continue;
      endif
      const result = $planner:_act(npc, plan['owner], step['name], values);
      if (result['status] == 'applied)
        frame['step] = frame['step] + 1;
        plan['frames][length(plan['frames])] = frame;
      else
        plan = $planner:_fail_approach(npc, plan, step['text] + ": " + result['reason]);
      endif
      npc.plan = plan;
      return $planner.tick_seconds;
    endfor
    npc.plan = plan;
    return $planner.tick_seconds;
  endmethod

  method _choose owner: ARCH_WIZARD
    "Choose the first approach whose condition holds, with the first matches that have not recently failed.";
    callers()[1][4] == $planner || raise(E_PERM);
    const {npc, plan, frame} = args;
    const playbook = plan['playbook];
    for approach in ($playbook:compiled_for(playbook, frame['goal]))
      if (maphaskey(approach, 'error))
        continue;
      endif
      const name = approach['source]['name];
      for bindings in ($planner:_matches(plan['owner], approach['requires], frame['inputs], playbook.settings))
        if (!$plan_failures:member({npc, frame['goal], name, value_hash(bindings)}))
          return {name, bindings};
        endif
      endfor
    endfor
    return 0;
  endmethod

  method _matches owner: ARCH_WIZARD
    "Evaluate an approach's condition as the NPC's owner and return every match, best first.";
    callers()[1][4] == $planner || raise(E_PERM);
    const {owner, rule, inputs, settings} = args;
    rule == 0 && return {[]};
    set_task_perms(owner);
    try
      const result = $rule_engine:evaluate(rule, inputs, settings);
      return result['success] ? {result['bindings], @result['alternatives]} | {};
    except (E_INVARG, E_TYPE, E_PERM, E_PROPNF, E_QUOTA, E_INVIND)
      return {};
    endtry
  endmethod

  method _act owner: ARCH_WIZARD
    "Check an action's requirement against the world as it is, then perform it as the NPC's owner.";
    callers()[1][4] == $planner || raise(E_PERM);
    const {npc, owner, name, values} = args;
    set_task_perms(owner);
    const check = $reaction:check_action(name, values);
    check['ok] || return ['status -> 'denied, 'reason -> "it needs " + check['unmet]:join(", ")];
    const result = $reaction:perform_action(name, values);
    result['status] == 'applied && return result;
    if (result['status] == 'error)
      return ['status -> 'error, 'reason -> result['error][2]];
    endif
    const said = { part for part in (result['reason]) if typeof(part) == TYPE_STR };
    return ['status -> 'denied, 'reason -> length(said) > 0 ? said:join(" ") | "it was refused"];
  endmethod

  method _fail_approach owner: ARCH_WIZARD
    "Remember that the current approach and its matches failed, and let the goal choose again.";
    callers()[1][4] == $planner || raise(E_PERM);
    let {npc, plan, reason} = args;
    let frame = plan['frames][$];
    if (frame['approach] != 0)
      $plan_failures:assert({npc, frame['goal], frame['approach], value_hash(frame['bindings])}, $plan_failures, $planner.failure_seconds);
    endif
    frame['approach] = 0;
    frame['bindings] = [];
    frame['step] = 1;
    plan['frames][length(plan['frames])] = frame;
    plan['setback] = reason;
    return plan;
  endmethod

  method _fail_goal owner: ARCH_WIZARD
    "Drop a goal that no approach can achieve; its parent's approach fails in turn.";
    callers()[1][4] == $planner || raise(E_PERM);
    let {npc, plan, reason} = args;
    plan['frames] = plan['frames][1..$ - 1];
    plan['setback] = reason;
    if (length(plan['frames]) > 0)
      plan = $planner:_fail_approach(npc, plan, reason);
    endif
    return plan;
  endmethod

  method _finish owner: ARCH_WIZARD
    "End a plan, keep how it ended, and tell the NPC.";
    callers()[1][4] == $planner || raise(E_PERM);
    let {npc, plan, status, reason} = args;
    plan['status] = status;
    plan['setback] = reason;
    npc.plan = plan;
    npc.plan_schedule = 0;
    try
      npc:fire_trigger(status == 'done ? 'on_plan_done | 'on_plan_failed, ['Actor -> npc]);
    except error (ANY)
      server_log("Plan reaction on " + toliteral(npc) + " failed: " + error[2]);
    endtry
    return 0;
  endmethod

  method _stop owner: ARCH_WIZARD
    "Cancel an NPC's pending plan tick.";
    callers()[1][4] == $planner || raise(E_PERM);
    const {npc} = args;
    schedule_valid(npc.plan_schedule) && schedule_stop(npc.plan_schedule);
    npc.plan_schedule = 0;
  endmethod

  method _usable owner: ARCH_WIZARD
    "A plan can use playbooks owned by the NPC's owner or by a wizard.";
    const {npc, playbook} = args;
    return typeof(playbook) == TYPE_OBJ && valid(playbook) && isa(playbook, $playbook) && (playbook.owner == npc.owner || playbook.owner.wizard);
  endmethod

  method _approach owner: ARCH_WIZARD
    "Find a frame's chosen approach, parsed, or 0 if it is gone or invalid.";
    const {playbook, frame} = args;
    for approach in ($playbook:compiled_for(playbook, frame['goal]))
      if (approach['source]['name] == frame['approach])
        return maphaskey(approach, 'error) ? 0 | approach;
      endif
    endfor
    return 0;
  endmethod

  method _frame owner: HACKER
    "A new open goal on a plan's stack.";
    const {goal, inputs} = args;
    return ['goal -> goal, 'inputs -> inputs, 'approach -> 0, 'bindings -> [], 'step -> 1];
  endmethod

  method _call_text owner: HACKER
    "Show a goal with its inputs.";
    const {goal, inputs} = args;
    return tostr(goal) + "(" + { tostr(name) + ": " + $planner:_value_text(inputs[name]) for name in (mapkeys(inputs)) }:join(", ") + ")";
  endmethod

  method _value_text owner: HACKER
    "Show a value by name when it is an object.";
    const {value} = args;
    return typeof(value) == TYPE_OBJ && valid(value) ? value.name | toliteral(value);
  endmethod

  method test_playbook_validation owner: HACKER
    "Approaches are checked against their goal, the actions, and their own bindings when defined, and keep their order.";
    const book = $playbook:create(true);
    $playbook:define_goal(book, 'tidy, ['thing -> 'object], "Put a thing away.");
    $test_utils:assert_raises(E_INVARG, $playbook, "define_goal", {book, 'bad, ['actor -> 'object]}, "actor is every goal's own input");
    for steps in ({{{'action, 'juggle, []}}, {{'action, 'drop, ['target -> "binding.Nowhere"]}}, {{'action, 'drop, ['target -> "1"]}}, {{'action, 'drop, []}}, {{'goal, 'missing, []}}})
      $test_utils:assert_raises(E_INVARG, $playbook, "define_approach", {book, 'tidy, 'broken, "", steps}, "Invalid steps are refused: " + toliteral(steps));
    endfor
    $test_utils:assert_raises(E_INVARG, $playbook, "define_approach", {book, 'tidy, 'broken, "no_such_fact(object: input.thing)", {}}, "An invalid condition is refused");
    $playbook:define_approach(book, 'tidy, 'hold, "location_of(object: input.thing) -> (location: Where)", {{'action, 'drop, ['target -> "input.thing"]}});
    $playbook:define_approach(book, 'tidy, 'second, "", {});
    $playbook:define_approach(book, 'tidy, 'hold, "", {{'action, 'drop, ['target -> "input.thing"]}});
    const compiled = $playbook:compiled_for(book, 'tidy);
    $test_utils:assert_eq({ entry['source]['name] for entry in (compiled) }, {'hold, 'second}, "Redefining an approach keeps its place");
    $test_utils:assert_eq(compiled[1]['steps][1]['arguments]['actor], ['kind -> 'input, 'name -> 'actor], "A step's actor defaults to the NPC");
    return true;
  endmethod

  method test_errands_validate owner: HACKER
    "Every approach in the core errands playbook validates.";
    for goal in (mapkeys($errands.goals))
      for entry in ($playbook:compiled_for($errands, goal))
        !maphaskey(entry, 'error) || raise(E_ASSERT, tostr(goal) + " by " + tostr(entry['source]['name]) + ": " + entry['error]);
      endfor
    endfor
    return true;
  endmethod

  method test_only_owners_start_plans owner: HACKER
    "Players do not run plans, and only an NPC's owner starts one.";
    $test_utils:assert_raises(E_INVARG, $planner, "pursue", {player, $errands, 'go_to, ['place -> player.location]}, "Players do not run plans");
    const npc = $test_utils:anonymous($actor);
    $test_utils:assert_raises(E_INVARG, $planner, "pursue", {npc, $errands, 'juggle, []}, "Unknown goals are refused");
    $test_utils:assert_raises(E_INVARG, $planner, "pursue", {npc, $errands, 'go_to, ['place -> "home"]}, "Goal inputs are typed");
    $test_utils:assert_raises(E_PERM, $planner, "pursue", {$actor, $errands, 'go_to, ['place -> #-1]}, "Only an NPC's owner starts its plan");
    $test_utils:assert_raises(E_PERM, $planner, "_tick", {npc}, "Only the planner's schedule advances a plan");
    $test_utils:assert_eq($planner:why(npc), {npc.name + " has no plan."}, "An NPC without a plan says so");
    return true;
  endmethod
endobject
