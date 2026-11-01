object PLAYBOOK [
  import_export_id -> "playbook",
  import_export_hierarchy -> {"rules"}
]
  name: "Playbook"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property goals (owner: HACKER, flags: "rc") = [];
  property approaches (owner: HACKER, flags: "rc") = {};
  property settings (owner: HACKER, flags: "rc") = [];
  property compiled (owner: ARCH_WIZARD, flags: "r") = [];

  override description (owner: HACKER, flags: "rc") = "Goals an NPC can pursue, and the approaches that achieve them in steps.";
  override object_documentation (owner: HACKER, flags: "rc") = {
    "# Playbooks",
    "",
    "A playbook holds goals and the approaches that achieve them. `$planner:pursue(npc, playbook, goal, inputs)` has an owned NPC work towards a goal.",
    "",
    "`define_goal(playbook, name, inputs, description)` declares a goal with typed inputs. Every goal also receives `actor`, the NPC pursuing it.",
    "`define_approach(playbook, goal, name, requires, steps)` adds one way to achieve a goal, or replaces the approach of that name. `requires` is a condition over `input.NAME` and `parameter.NAME`; its bindings feed the steps. Each step is `{'action, name, arguments}` or `{'goal, name, arguments}`, with each argument written as a value, such as `\"binding.Where\"`. A step's `actor` defaults to the NPC.",
    "`document(playbook)` reads a playbook as an editor needs it, `check(playbook, draft)` tests an approach without storing it, and `vocabulary()` lists what approaches can be made of. `order_approaches(playbook, goal, names)` and `remove_goal(playbook, goal)` rearrange it. Called with no caller, as a client's host calls them, these act for the player.",
    "Approaches are tried in the order they were defined. `settings` holds values that conditions and steps read as `parameter.NAME`."
  };

  method define_goal owner: ARCH_WIZARD
    "Declare a goal with typed inputs. Every goal also receives actor, the NPC pursuing it.";
    const {playbook, name, inputs, ?description = "", ?label = ""} = args;
    const principal = callers() ? caller_perms() | player;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    $behavior_schema:_name(name, "goal");
    $behavior_schema:_types(inputs, "goal inputs");
    !maphaskey(inputs, 'actor) || raise(E_INVARG, "Every goal already has actor, the NPC pursuing it.");
    typeof(description) == TYPE_STR || raise(E_TYPE);
    let goal = ['description -> description, 'inputs -> inputs];
    if (label != "")
      $behavior_schema:_label(label, {@mapkeys(inputs), 'actor}, "goal label");
      goal['label] = label;
    endif
    playbook.goals[name] = goal;
    return true;
  endmethod

  method define_approach owner: ARCH_WIZARD
    "Add one way to achieve a goal, or replace the approach of that name. Validate it first.";
    const {playbook, goal, name, requires, steps, ?note = ""} = args;
    const principal = callers() ? caller_perms() | player;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    $behavior_schema:_name(name, "approach");
    let approach = ['goal -> goal, 'name -> name, 'requires -> requires, 'steps -> steps];
    note != "" && (approach['note] = note);
    $playbook:_compile(playbook, approach);
    let approaches = playbook.approaches;
    let replaced = false;
    for i in [1..length(approaches)]
      if (approaches[i]['goal] == goal && approaches[i]['name] == name)
        approaches[i] = approach;
        replaced = true;
      endif
    endfor
    replaced || (approaches = {@approaches, approach});
    playbook.approaches = approaches;
    return true;
  endmethod

  method remove_approach owner: ARCH_WIZARD
    "Remove one approach to a goal. Return whether it existed.";
    const {playbook, goal, name} = args;
    const principal = callers() ? caller_perms() | player;
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    const kept = { approach for approach in (playbook.approaches) if !(approach['goal] == goal && approach['name] == name) };
    const removed = length(kept) < length(playbook.approaches);
    playbook.approaches = kept;
    return removed;
  endmethod

  method order_approaches owner: ARCH_WIZARD
    "Put a goal's approaches in this order, which is the order they're tried in. Other goals' keep their places.";
    const {playbook, goal, names} = args;
    const principal = callers() ? caller_perms() | player;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    const current = { approach['name] for approach in (playbook.approaches) if approach['goal] == goal };
    typeof(names) == TYPE_LIST && length(names) == length(current) || raise(E_INVARG, "Name each of the goal's approaches once.");
    for name in (current)
      name in names || raise(E_INVARG, "Name each of the goal's approaches once.");
    endfor
    let next = 1;
    let approaches = playbook.approaches;
    for i in [1..length(approaches)]
      if (approaches[i]['goal] == goal)
        approaches[i] = { approach for approach in (playbook.approaches) if approach['goal] == goal && approach['name] == names[next] }[1];
        next = next + 1;
      endif
    endfor
    playbook.approaches = approaches;
    return true;
  endmethod

  method remove_goal owner: ARCH_WIZARD
    "Remove a goal and its approaches, unless another goal's approach still has it as a step.";
    const {playbook, goal} = args;
    const principal = callers() ? caller_perms() | player;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    maphaskey(playbook.goals, goal) || raise(E_INVARG, "Unknown goal: " + tostr(goal));
    for approach in (playbook.approaches)
      if (approach['goal] != goal)
        for step in (approach['steps])
          step[1] == 'goal && step[2] == goal && raise(E_INVARG, tostr(approach['goal]) + " by " + tostr(approach['name]) + " still has this goal as a step.");
        endfor
      endif
    endfor
    playbook.approaches = { approach for approach in (playbook.approaches) if approach['goal] != goal };
    playbook.goals = mapdelete(playbook.goals, goal);
    return true;
  endmethod

  method vocabulary owner: HACKER
    "What approaches can be made of, for authoring: the predicates and actions with their labels, descriptions and types. Pure metadata, without providers or authority.";
    return ['predicates -> $rule_engine:schemas(), 'actions -> $reaction:action_schemas()];
  endmethod

  method document owner: ARCH_WIZARD
    "A playbook as an editor needs it: its settings, and each goal with its approaches in the order they're tried, parsed and validated. An approach that doesn't validate carries its error.";
    const {playbook} = args;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    let goals = [];
    for name in (mapkeys(playbook.goals))
      const described = { $playbook:_described(entry) for entry in ($playbook:compiled_for(playbook, name)) };
      goals[name] = mapmerge(playbook.goals[name], ['approaches -> described]);
    endfor
    return ['object -> playbook, 'settings -> playbook.settings, 'goals -> goals];
  endmethod

  method check owner: ARCH_WIZARD
    "Check a draft approach against a playbook and store nothing. Its condition can be text or a condition tree. Returns it parsed with ok true, or ok false and a message saying what's wrong and where.";
    set_task_perms(callers() ? caller_perms() | player);
    const {playbook, draft} = args;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    try
      let approach = draft;
      if (typeof(approach) == TYPE_MAP && maphaskey(approach, 'requires) && typeof(approach['requires]) == TYPE_MAP)
        approach['requires] = $rule_engine:conditions():print(approach['requires]);
      endif
      return mapmerge($playbook:_described($playbook:_compile(playbook, approach)), ['ok -> true]);
    except error (E_INVARG, E_TYPE, E_QUOTA, E_PERM, E_PROPNF, E_RANGE)
      return ['ok -> false, 'message -> error[2]];
    endtry
  endmethod

  method _described owner: HACKER
    "One compiled approach as an editor reads it.";
    const {entry} = args;
    const source = entry['source];
    let described = source;
    if (maphaskey(entry, 'error))
      described['error] = entry['error];
      return described;
    endif
    const rule = entry['requires];
    described['condition] = rule == 0 ? 0 | rule.condition;
    described['bindings] = rule == 0 ? [] | rule.bindings;
    described['parsed_steps] = entry['steps];
    return described;
  endmethod

  method _compile owner: ARCH_WIZARD
    "Validate an approach against its goal, the actions, and the playbook's goals; return it with parsed condition and steps.";
    set_task_perms(caller_perms());
    const {playbook, approach} = args;
    $behavior_schema:_fields(approach, {'goal, 'name, 'requires, 'steps}, {'note}, "approach");
    !maphaskey(approach, 'note) || typeof(approach['note]) == TYPE_STR || raise(E_INVARG, "An approach's note is text.");
    maphaskey(playbook.goals, approach['goal]) || raise(E_INVARG, "Unknown goal: " + tostr(approach['goal]));
    typeof(approach['requires]) == TYPE_STR || raise(E_INVARG, "An approach's condition is text; use \"\" for none.");
    typeof(approach['steps]) == TYPE_LIST && length(approach['steps]) <= 16 || raise(E_INVARG, "An approach has a list of at most 16 steps.");
    const label = tostr(approach['goal]) + " by " + tostr(approach['name]);
    const goal = playbook.goals[approach['goal]];
    let parameter_types = [];
    for setting in (mapkeys(playbook.settings))
      parameter_types[setting] = $behavior_schema:type_of(playbook.settings[setting]);
    endfor
    let scope = $rule_engine:scope(mapmerge(goal['inputs], ['actor -> 'object]), parameter_types);
    const rule = approach['requires] == "" ? 0 | $rule_engine:parse_expression(approach['requires], approach['name], scope);
    rule != 0 && (scope['binding] = rule.bindings);
    let steps = {};
    for spec in (approach['steps])
      typeof(spec) == TYPE_LIST && length(spec) == 3 || raise(E_INVARG, label + ": a step is {'action or 'goal, name, arguments}.");
      const {kind, target, values} = spec;
      let inputs;
      if (kind == 'action)
        const schemas = $reaction:action_schemas();
        maphaskey(schemas, target) || raise(E_INVARG, label + ": unknown action " + tostr(target));
        inputs = schemas[target]['inputs];
      elseif (kind == 'goal)
        maphaskey(playbook.goals, target) || raise(E_INVARG, label + ": unknown goal " + tostr(target));
        inputs = mapmerge(playbook.goals[target]['inputs], ['actor -> 'object]);
      else
        raise(E_INVARG, label + ": a step is an action or a goal.");
      endif
      typeof(values) == TYPE_MAP || raise(E_INVARG, label + ": step arguments are a map.");
      let parsed = [];
      let parts = {};
      for field in (mapkeys(values))
        typeof(values[field]) == TYPE_STR || raise(E_INVARG, label + ": write step arguments as values, such as \"input.item\".");
        parsed[field] = $condition:parse_value(values[field]);
        parts = {@parts, tostr(field) + ": " + values[field]};
      endfor
      if (maphaskey(inputs, 'actor) && !maphaskey(parsed, 'actor))
        parsed['actor] = ['kind -> 'input, 'name -> 'actor];
      endif
      $behavior_schema:_arguments(parsed, inputs, scope, label + " step " + tostr(length(steps) + 1), 0);
      steps = {@steps, ['kind -> kind, 'name -> target, 'arguments -> parsed, 'text -> tostr(target) + "(" + parts:join(", ") + ")"]};
    endfor
    return ['source -> approach, 'requires -> rule, 'steps -> steps];
  endmethod

  method compiled_for owner: ARCH_WIZARD
    "Return a goal's approaches in order, parsed and validated, reusing earlier work while their text is unchanged. An approach that no longer validates carries its error.";
    const {playbook, goal} = args;
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    let result = {};
    for approach in (playbook.approaches)
      if (approach['goal] != goal)
        continue;
      endif
      const key = tostr(goal) + ":" + tostr(approach['name]);
      let entry = `playbook.compiled[key] ! E_RANGE => 0';
      if (typeof(entry) != TYPE_MAP || !equal(entry['source], approach))
        try
          entry = $playbook:_compile(playbook, approach);
        except error (E_INVARG, E_TYPE, E_QUOTA, E_PERM, E_PROPNF)
          entry = ['source -> approach, 'error -> error[2]];
        endtry
        playbook.compiled[key] = entry;
      endif
      result = {@result, entry};
    endfor
    return result;
  endmethod
endobject
