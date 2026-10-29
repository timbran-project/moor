object RULE_ENGINE [
  import_export_id -> "rule_engine",
  import_export_hierarchy -> {"rules"}
]
  name: "Rule Engine"
  parent: ROOT
  owner: HACKER
  readable: true

  property predicate_providers (owner: ARCH_WIZARD, flags: "r") = [];
  property validation_key (owner: ARCH_WIZARD, flags: "") = "";

  override description (owner: HACKER, flags: "rc") = "Evaluate explicit condition trees over named, typed predicates.";
  override object_documentation (owner: HACKER, flags: "rc") = {
    "# Rules and conditions",
    "A rule is a condition tree with declared input, parameter, and state types.",
    "AND, OR, NOT, and parentheses compose conditions. Unknown predicates and evaluation errors remain errors.",
    "References identify their namespace: input.Actor, parameter.cat, state.counter, or binding.Item.",
    "Quoted strings are literal text. Object references are explicit, such as #65.",
    "Examples: owner_is(object: input.This, owner: input.Accessor)",
    "NOT (input.Actor == parameter.cat) AND state.counter >= 4",
    "occupants(location: input.Location) -> (object: Visitor)",
    "relation(#123, rock: input.This) -> (person: Visitor) queries an explicit relation object.",
    "A reaction can use parameter.visitors as its relation reference. Relations define their own fields.",
    "Predicate arguments use names from their schemas. Selected outputs require explicit binding names.",
    "Negation requires bound inputs and cannot introduce new bindings.",
    "Values can be computed: binding.Height - input.Level <= 2, abs(binding.X - input.X) < 8, min(a, b), max(a, b). Arithmetic needs all integers or all floats.",
    "count(occupants(location: input.Location) -> (object: Visitor)) < 3 counts matches; the search must be complete.",
    "exists(...) holds when its condition has a match, without exposing that match's bindings.",
    "best(occupants(location: input.Location) -> (object: Visitor), by: binding.Visitor, limit: 2) keeps the matches with the lowest values; negate the value for the highest.",
    "Use @set-rule, @show-rule, @clear-rule, and @rules for policy properties.",
    "Core programmers register additional predicates with explicit input and output types.",
    "Read the Cowbell behavior model for the complete data and execution contracts."
  };

  method scope owner: HACKER
    "Construct an explicit static scope. Selected bindings start empty.";
    const {?inputs = [], ?parameters = [], ?state = []} = args;
    return ['input -> inputs, 'parameter -> parameters, 'state -> state, 'binding -> []];
  endmethod

  method policy_scope owner: HACKER
    "Describe inputs supplied by existing policy operations. Unknown slots require an explicit schema.";
    const {property} = args;
    const name = tosym(property);
    let inputs = ['This -> 'object, 'Accessor -> 'object];
    if (name in {'lock_rule, 'unlock_rule})
      inputs['Key] = 'object;
    elseif (name in {'take_rule, 'put_rule})
      inputs['Dobj] = 'object;
    elseif (name == 'feed_rule)
      inputs['Food] = 'object;
    elseif (!(name in {'get_rule, 'drop_rule, 'open_rule, 'close_rule, 'view_rule, 'read_rule, 'write_rule, 'wear_rule, 'remove_rule, 'use_rule, 'consume_rule, 'pet_rule, 'sit_rule, 'stand_rule, 'pass_rule}))
      inputs = [];
    endif
    return this:scope(inputs);
  endmethod

  method passage_scope owner: HACKER
    "Name passage endpoints explicitly. Key is required only when the condition uses it.";
    return this:scope(['Accessor -> 'object, 'From -> 'object, 'To -> 'object, 'Passage -> 'any, 'Key -> 'object]);
  endmethod

  method trigger_scope owner: HACKER
    "Describe event inputs until operation schemas replace the existing trigger entries.";
    const {trigger, ?state_types = []} = args;
    let inputs = ['This -> 'object, 'Location -> 'object, 'Actor -> 'object];
    if (typeof(trigger) == TYPE_SYM)
      trigger in {'on_take, 'on_put, 'on_get, 'on_drop, 'on_wear, 'on_remove} && (inputs['Item] = 'object);
      trigger in {'on_lock, 'on_unlock} && (inputs['Key] = 'object);
      if (trigger in {'on_passage_open, 'on_passage_close, 'on_passage_lock, 'on_passage_unlock})
        inputs = mapmerge(inputs, ['From -> 'object, 'To -> 'object, 'Passage -> 'any, 'Connection -> 'string, 'Direction -> 'string, 'Key -> 'object]);
      endif
      trigger in {'on_enter, 'on_exit} && (inputs['Who] = 'object);
      trigger in {'on_consume, 'on_empty} && (inputs['Amount] = 'integer);
      trigger == 'on_fed && (inputs['Food] = 'object);
    endif
    return this:scope(inputs, [], state_types);
  endmethod

  method schemas owner: HACKER
    "Return pure predicate metadata, without provider identities or authority.";
    let schemas = $world_facts:schemas();
    for name in (mapkeys($rule_engine.predicate_providers))
      schemas[name] = $rule_engine.predicate_providers[name]['schema];
    endfor
    return schemas;
  endmethod

  method register_predicate owner: ARCH_WIZARD
    "Register a typed provider. Only wizards may select executable query implementations.";
    caller_perms().wizard || raise(E_PERM);
    const {name, schema, provider, method} = args;
    $behavior_schema:_name(name, "predicate");
    name != 'relation || raise(E_INVARG, "relation is reserved for explicit relation queries.");
    !(name in {'abs, 'min, 'max, 'count, 'exists, 'best}) || raise(E_INVARG, tostr(name) + " is reserved by the condition language.");
    !maphaskey($world_facts:schemas(), name) || raise(E_INVARG, "Cannot replace a core predicate");
    typeof(provider) == TYPE_OBJ && valid(provider) && typeof(method) == TYPE_STR || raise(E_INVARG, "Invalid predicate provider");
    $behavior_schema:_vocabulary(['triggers -> [], 'actions -> [], 'predicates -> [name -> schema]]);
    $rule_engine.predicate_providers[name] = ['schema -> schema, 'provider -> provider, 'method -> method];
    this:forget_validations();
  endmethod

  method unregister_predicate owner: ARCH_WIZARD
    "Remove a global query provider as a wizard. Relations are addressed directly.";
    caller_perms().wizard || raise(E_PERM);
    const {name} = args;
    if (maphaskey($rule_engine.predicate_providers, name))
      $rule_engine.predicate_providers = mapdelete($rule_engine.predicate_providers, name);
    endif
    this:forget_validations();
  endmethod

  method forget_validations owner: ARCH_WIZARD
    "Invalidate every rule's validation stamp, so each rule validates in full on its next use. Call this after changing the condition language or the core predicates.";
    caller_perms().wizard || raise(E_PERM);
    $rule_engine.validation_key = value_hash(random_bytes(32));
  endmethod

  method stamp_rule owner: ARCH_WIZARD
    "Validate a rule and return it carrying a stamp, so later uses skip validation while the predicates stay the same.";
    const {rule} = args;
    const validation = $rule_engine:validate_rule(rule);
    validation['valid] || raise(E_INVARG, validation['warnings]:join("; "));
    const bindings = validation['bindings];
    $rule_engine.validation_key || ($rule_engine.validation_key = value_hash(random_bytes(32)));
    const stamp = string_hmac(value_hash({rule.condition, rule.scope, bindings}), $rule_engine.validation_key);
    return <$rule, .name = rule.name, .condition = rule.condition, .scope = rule.scope, .bindings = bindings, .validation = stamp>;
  endmethod

  method _stamped_bindings owner: ARCH_WIZARD
    "The bindings recorded by a rule's stamp, or false if the rule carries no stamp that holds.";
    const {rule} = args;
    const slots = flyslots(rule);
    if (!(maphaskey(slots, 'validation) && maphaskey(slots, 'bindings) && $rule_engine.validation_key && typeof(slots['validation]) == TYPE_STR))
      return false;
    endif
    if (slots['validation] != string_hmac(value_hash({slots['condition], slots['scope], slots['bindings]}), $rule_engine.validation_key))
      return false;
    endif
    return slots['bindings];
  endmethod

  method parse_expression owner: ARCH_WIZARD
    "Parse and validate one complete condition using explicitly declared inputs.";
    set_task_perms(caller_perms());
    const {text, ?name = 'parsed_rule, ?scope = this:scope(), ?parameters = []} = args;
    return $rule:mk(name, this:conditions():parse(text), scope, parameters);
  endmethod

  method validate_rule owner: HACKER
    "Validate tree structure, registered predicates, input types, and definite output bindings.";
    const {rule, ?scope = rule.scope} = args;
    try
      typeof(rule) == TYPE_FLYWEIGHT && rule.delegate == $rule || raise(E_INVARG, "Expected a canonical rule");
      if (scope == rule.scope)
        const stamped = $rule_engine:_stamped_bindings(rule);
        if (typeof(stamped) == TYPE_MAP)
          return ['valid -> true, 'warnings -> {}, 'bindings -> stamped];
        endif
      endif
      $behavior_schema:_fields(scope, {'input, 'parameter, 'state, 'binding}, {}, "scope");
      for namespace in ({'input, 'parameter, 'state, 'binding})
        $behavior_schema:_types(scope[namespace], "scope." + tostr(namespace));
      endfor
      const checked = $behavior_schema:condition(rule.condition, scope, this:schemas());
      return ['valid -> true, 'warnings -> {}, 'bindings -> checked['bindings]];
    except error (E_INVARG, E_QUOTA)
      return ['valid -> false, 'warnings -> {error[2]}, 'bindings -> []];
    endtry
  endmethod

  method decompile_rule owner: HACKER
    "Print the same tree that validation and evaluation consume.";
    const {rule} = args;
    return this:conditions():print(rule.condition);
  endmethod

  method conditions owner: HACKER
    "The condition evaluator this engine uses. A subclass may answer with a subclass of it.";
    return $condition;
  endmethod

  method evaluate owner: ARCH_WIZARD
    "Evaluate a rule under the invoking principal; incomplete exhaustive results remain errors. With explain, the result carries an explanation of what held and what failed.";
    set_task_perms(caller_perms());
    const {rule, ?inputs = [], ?parameters = [], ?state = [], ?preview = false, ?explain = false} = args;
    const validation = this:validate_rule(rule);
    validation['valid] || raise(E_INVARG, validation['warnings]:join("; "));
    const environment = ['input -> inputs, 'parameter -> parameters, 'state -> state, 'binding -> []];
    const used = this:conditions():references(rule.condition);
    for namespace in ({'input, 'parameter, 'state})
      for name in (used[namespace])
        maphaskey(environment[namespace], name) || raise(E_INVARG, "Missing " + tostr(namespace) + " " + tostr(name));
        $behavior_schema:_type(environment[namespace][name], rule.scope[namespace][name], tostr(name));
      endfor
    endfor
    const engine = this;
    const query = {name, values, limit} => engine:query(name, values, limit, preview);
    const result = this:conditions():evaluate(rule.condition, environment, query, 256, explain);
    result['complete] || raise(E_QUOTA, "Condition search is incomplete");
    const rows = result['bindings];
    let answer = ['success -> length(rows) > 0, 'bindings -> length(rows) > 0 ? rows[1] | [], 'alternatives -> length(rows) > 1 ? rows[2..$] | {}, 'warnings -> {}, 'complete -> true];
    explain && (answer['explanation] = result['trace]);
    return answer;
  endmethod

  method query owner: ARCH_WIZARD
    "Call one registered provider with the caller's permissions and validate its complete row shape.";
    set_task_perms(caller_perms());
    const {name, values, limit, ?preview = false} = args;
    typeof(limit) == TYPE_INT && limit > 0 && limit <= 256 || raise(E_INVARG, "Query result limit must be between 1 and 256");
    const schemas = this:schemas();
    maphaskey(schemas, name) || raise(E_INVARG, "Unknown predicate: " + tostr(name));
    const schema = schemas[name];
    $behavior_schema:bindings(values, schema['inputs], "predicate inputs");
    let result;
    if (maphaskey($rule_engine.predicate_providers, name))
      const source = $rule_engine.predicate_providers[name];
      !preview || raise(E_INVARG, "Preview cannot call the extension condition " + tostr(name) + ".");
      result = source['provider]:(source['method])(name, values, limit);
    else
      result = $world_facts:query(name, values, limit);
    endif
    $behavior_schema:_fields(result, {'rows, 'complete}, {}, "predicate result");
    $behavior_schema:_type(result['rows], 'list, "predicate rows");
    $behavior_schema:_type(result['complete], 'boolean, "predicate completeness");
    length(result['rows]) <= limit || raise(E_QUOTA, "Predicate exceeded its row limit");
    for row in (result['rows])
      $behavior_schema:bindings(row, schema['outputs], "predicate outputs");
    endfor
    return result;
  endmethod

  method test_condition_words_are_reserved owner: ARCH_WIZARD
    "Predicates cannot take the names of the condition language's own functions.";
    const schema = ['description -> "A test predicate.", 'inputs -> [], 'outputs -> []];
    for name in ({'abs, 'min, 'max, 'count, 'exists, 'best})
      try
        this:register_predicate(name, schema, this, "query");
        raise(E_ASSERT, "Registered a predicate named " + tostr(name));
      except error (E_INVARG)
      endtry
    endfor
    return true;
  endmethod

  method test_rules_compute_and_explain owner: HACKER
    "Rules accept computed values, and an explained evaluation carries the condition's trace.";
    const rule = this:parse_expression("1 + 2 * 3 == 7 AND max(1, 4) > 9");
    const result = this:evaluate(rule, [], [], [], false, true);
    result['success] && raise(E_ASSERT, "A false rule succeeded");
    const parts = result['explanation]['children];
    {parts[1]['matches], parts[2]['matches]} == {1, 0} || raise(E_ASSERT, "Explanation: " + toliteral(result['explanation]));
    !maphaskey(this:evaluate(rule), 'explanation) || raise(E_ASSERT, "An unexplained evaluation carried an explanation");
    return true;
  endmethod

  method test_stamped_rules_skip_validation owner: ARCH_WIZARD
    "A built rule carries a stamp that holds only for its own condition, scope, and the current predicates.";
    const rule = this:parse_expression("1 + 2 == 3");
    typeof($rule_engine:_stamped_bindings(rule)) == TYPE_MAP || raise(E_ASSERT, "A built rule carried no stamp");
    const forged = <$rule, .name = rule.name, .condition = ['kind -> 'bogus], .scope = rule.scope, .bindings = rule.bindings, .validation = rule.validation>;
    $rule_engine:_stamped_bindings(forged) == false || raise(E_ASSERT, "A stamp held for another condition");
    $rule_engine:validate_rule(forged)['valid] && raise(E_ASSERT, "A forged rule passed validation");
    let scope = rule.scope;
    scope['input]['Extra] = 'integer;
    const checked = $rule_engine:validate_rule(rule, scope);
    checked['valid] || raise(E_ASSERT, "Another scope failed: " + toliteral(checked));
    const schema = ['description -> "A test predicate.", 'inputs -> [], 'outputs -> []];
    this:register_predicate('stamp_test, schema, this, "query");
    this:unregister_predicate('stamp_test);
    $rule_engine:_stamped_bindings(rule) == false || raise(E_ASSERT, "A predicate change kept the stamp");
    this:evaluate(rule)['success] || raise(E_ASSERT, "An unstamped rule failed to evaluate");
    const restamped = this:stamp_rule(rule);
    typeof($rule_engine:_stamped_bindings(restamped)) == TYPE_MAP || raise(E_ASSERT, "Restamping failed");
    this:forget_validations();
    $rule_engine:_stamped_bindings(restamped) == false || raise(E_ASSERT, "Forgetting validations kept the stamp");
    return true;
  endmethod
endobject
