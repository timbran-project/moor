object RULE
  name: "Rule"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for Datalog-style rules. Rules consist of a head predicate and a body of goals.";
  override import_export_hierarchy = {"rules"};
  override import_export_id = "rule";

  verb mk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a new rule flyweight.";
    "Args: name, head_predicate, body_goals";
    "Example: $rule:mk('trusted, 'trusted, {{member, 'X, #guild}, {reputation, #guild, 5}})";
    {rule_name, head_predicate, body_goals} = args;
    typeof(head_predicate) == TYPE_SYM || typeof(head_predicate) == TYPE_STR || raise(E_TYPE, "head_predicate must be symbol or string");
    typeof(body_goals) == TYPE_LIST || raise(E_TYPE, "body_goals must be list");
    "Extract variables from body";
    variables = this:_extract_variables(body_goals);
    return <this, .name = rule_name, .head = tosym(head_predicate), .body = body_goals, .variables = variables>;
  endverb

  verb _extract_variables (this none this) owner: HACKER flags: "rxd"
    "Extract all variables (symbols starting with uppercase) from goals.";
    {goals} = args;
    variables = {};
    for goal in (goals)
      if (typeof(goal) == TYPE_LIST)
        for arg in (goal[2..$])
          if (typeof(arg) == TYPE_SYM)
            arg_str = tostr(arg);
            "Variables are symbols that don't map to objects";
            if (arg_str[1] == "'" && length(arg_str) > 1)
              "It's a symbol literal, extract the name";
              var_name = tosym(arg_str[2..$]);
              if (!(var_name in variables))
                variables = {@variables, var_name};
              endif
            endif
          endif
        endfor
      endif
    endfor
    return variables;
  endverb

  verb evaluate (this none this) owner: HACKER flags: "rxd"
    "Evaluate this rule with initial bindings.";
    "Returns: {success: bool, bindings: map, alternatives: list}";
    {?initial_bindings = []} = args;
    "Delegate to rule engine";
    return $rule_engine:evaluate(this, initial_bindings);
  endverb

  verb test_rule_creation (this none this) owner: HACKER flags: "rxd"
    "Test creating a simple rule.";
    guild_obj = this;
    goal = {'member, 'X, guild_obj};
    rule = this:mk('test_rule, 'test_rule, {goal});
    typeof(rule) == TYPE_FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    rule.head != 'test_rule && raise(E_ASSERT, "Head should be test_rule");
    length(rule.body) != 1 && raise(E_ASSERT, "Body should have 1 goal");
    return true;
  endverb
endobject