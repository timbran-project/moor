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
    "Approaches are tried in the order they were defined. `settings` holds values that conditions and steps read as `parameter.NAME`."
  };

  method define_goal owner: ARCH_WIZARD
    "Declare a goal with typed inputs. Every goal also receives actor, the NPC pursuing it.";
    const {playbook, name, inputs, ?description = ""} = args;
    const principal = caller_perms();
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    $behavior_schema:_name(name, "goal");
    $behavior_schema:_types(inputs, "goal inputs");
    !maphaskey(inputs, 'actor) || raise(E_INVARG, "Every goal already has actor, the NPC pursuing it.");
    typeof(description) == TYPE_STR || raise(E_TYPE);
    playbook.goals[name] = ['description -> description, 'inputs -> inputs];
    return true;
  endmethod

  method define_approach owner: ARCH_WIZARD
    "Add one way to achieve a goal, or replace the approach of that name. Validate it first.";
    const {playbook, goal, name, requires, steps} = args;
    const principal = caller_perms();
    isa(playbook, $playbook) || raise(E_INVARG, "Expected a playbook.");
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    $behavior_schema:_name(name, "approach");
    const approach = ['goal -> goal, 'name -> name, 'requires -> requires, 'steps -> steps];
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
    const principal = caller_perms();
    principal == playbook.owner || principal.wizard || raise(E_PERM);
    const kept = { approach for approach in (playbook.approaches) if !(approach['goal] == goal && approach['name] == name) };
    const removed = length(kept) < length(playbook.approaches);
    playbook.approaches = kept;
    return removed;
  endmethod

  method _compile owner: ARCH_WIZARD
    "Validate an approach against its goal, the actions, and the playbook's goals; return it with parsed condition and steps.";
    set_task_perms(caller_perms());
    const {playbook, approach} = args;
    $behavior_schema:_fields(approach, {'goal, 'name, 'requires, 'steps}, {}, "approach");
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
