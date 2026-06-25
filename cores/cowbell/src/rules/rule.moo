object RULE [
  import_export_id -> "rule",
  import_export_hierarchy -> {"rules"}
]
  name: "Rule"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Flyweight delegate for Datalog-style rules. Rules consist of a head predicate and a body of goals.";

  method mk owner: ARCH_WIZARD
    "Create a new rule flyweight.";
    "Args: name, head_predicate, body_goals";
    "Example: $rule:mk('trusted, 'trusted, {{member, 'X, #guild}, {reputation, #guild, 5}})";
    {rule_name, head_predicate, body_goals} = args;
    typeof(head_predicate) == TYPE_SYM || typeof(head_predicate) == TYPE_STR || raise(E_TYPE, "head_predicate must be symbol or string");
    typeof(body_goals) == TYPE_LIST || raise(E_TYPE, "body_goals must be list");
    "Extract variables from body";
    variables = this:_extract_variables(body_goals);
    return <this, .name = rule_name, .head = tosym(head_predicate), .body = body_goals, .variables = variables>;
  endmethod

  method _extract_variables owner: HACKER
    "Extract all normalized variable names from goals.";
    {goals} = args;
    variables = {};
    return this:_collect_variables(goals, variables);
  endmethod

  method _collect_variables owner: HACKER
    "Append normalized variable names found in value to variables.";
    {value, variables} = args;
    if (typeof(value) == TYPE_LIST && length(value) == 2 && value[1] == 'var && typeof(value[2]) == TYPE_SYM)
      !(value[2] in variables) && (variables = {@variables, value[2]});
      return variables;
    endif
    if (typeof(value) == TYPE_LIST)
      for item in (value)
        variables = this:_collect_variables(item, variables);
      endfor
    endif
    return variables;
  endmethod

  method evaluate owner: HACKER
    "Evaluate this rule with initial bindings.";
    "Returns: {success: bool, bindings: map, alternatives: list}";
    {?initial_bindings = []} = args;
    "Delegate to rule engine";
    return $rule_engine:evaluate(this, initial_bindings);
  endmethod

  method test_rule_creation owner: HACKER
    "Test creating a simple rule.";
    guild_obj = this;
    goal = {'member, {'var, 'X}, guild_obj};
    rule = this:mk('test_rule, 'test_rule, {goal});
    typeof(rule) == TYPE_FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    rule.head != 'test_rule && raise(E_ASSERT, "Head should be test_rule");
    length(rule.body) != 1 && raise(E_ASSERT, "Body should have 1 goal");
    return true;
  endmethod
endobject
