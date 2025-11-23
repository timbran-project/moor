// $rule_engine - Datalog-style query engine
// Stateless evaluation of rules and goals against fact predicates

object RULE_ENGINE
  name: "Rule Engine"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Stateless Datalog-style query engine. Evaluates rules and goals by calling fact predicates on objects.";
  override import_export_hierarchy = {"rules"};
  override import_export_id = "rule_engine";

  verb evaluate (this none this) owner: HACKER flags: "rxd"
    "Evaluate a rule to find all satisfying variable bindings.";
    "Args: rule (flyweight with .head, .body, .variables)";
    "Returns: {success: bool, bindings: map, alternatives: list of maps, warnings: list}";
    "Body can be either: a flat goal list (AND) or a list of branches (OR)";
    {rule, ?initial_bindings = []} = args;
    typeof(rule) == FLYWEIGHT || raise(E_TYPE, "rule must be flyweight");

    body = rule.body;

    "Check for negation warnings before evaluation";
    warnings = this:_check_negation_warnings(body, initial_bindings);

    "Check if body is a list of branches (OR) or flat goals (AND)";
    "Branches: body[1] is a list AND body[1][1] is a list (nested structure)";
    "Goals: body[1] is a list AND body[1][1] is a symbol (flat structure)";
    is_branches = false;
    if (length(body) > 0 && typeof(body[1]) == LIST && length(body[1]) > 0)
      first_elem = body[1][1];
      if (typeof(first_elem) == LIST)
        "It's a list of branches (or operator was used)";
        is_branches = true;
      endif
    endif

    if (is_branches)
      result = this:_prove_alternatives(body, initial_bindings);
    else
      "It's flat goals - use _prove_goals";
      result = this:_prove_goals(body, initial_bindings, {});
    endif

    "Add warnings to the result";
    result['warnings] = warnings;

    return result;
  endverb

  verb _prove_alternatives (this none this) owner: HACKER flags: "rxd"
    "Prove a list of alternative goal branches (OR).";
    "Each branch is a list of goals to prove with AND.";
    "Returns: {success: bool, bindings: map, alternatives: list of maps}";
    {alternatives, bindings} = args;
    typeof(alternatives) == LIST || raise(E_TYPE, "alternatives must be list");

    all_solutions = {};
    for branch in (alternatives)
      typeof(branch) == LIST || raise(E_TYPE, "each branch must be list of goals");
      result = this:_prove_goals(branch, bindings, {});
      if (result['success])
        all_solutions = {@all_solutions, result['bindings]};
        "Add any alternatives from this branch";
        branch_alts = result['alternatives];
        if (typeof(branch_alts) == LIST)
          for alt in (branch_alts)
            all_solutions = {@all_solutions, alt};
          endfor
        endif
      endif
    endfor

    if (length(all_solutions) == 0)
      return ['success -> false, 'bindings -> [], 'alternatives -> {}];
    endif

    return [
      'success -> true,
      'bindings -> all_solutions[1],
      'alternatives -> all_solutions[2..$]
    ];
  endverb

  verb _prove_goals (this none this) owner: HACKER flags: "rxd"
    "Prove a list of goals with backtracking. Returns all solutions.";
    "Pure recursion: goals, bindings, choice_stack → success + bindings + alternatives";
    {goals, bindings, ?_choice_stack = {}} = args;
    typeof(goals) == LIST || raise(E_TYPE, "goals must be list");
    typeof(bindings) == MAP || raise(E_TYPE, "bindings must be map");

    "Base case: no more goals, we succeeded";
    if (length(goals) == 0)
      return ['success -> true, 'bindings -> bindings, 'alternatives -> {}];
    endif

    "Recursive case: prove first goal, then rest";
    first_goal = goals[1];
    rest_goals = listdelete(goals, 1);

    "Check if this is a negation (first element is 'not)";
    if (length(first_goal) > 0 && first_goal[1] == 'not)
      "Handle negation as failure";
      inner_goals = listdelete(first_goal, 1);
      "Try to prove the inner goals";
      inner_result = this:_prove_goals(inner_goals, bindings);
      if (inner_result['success])
        "Inner goal succeeded, so NOT fails";
        return ['success -> false, 'bindings -> [], 'alternatives -> {}];
      else
        "Inner goal failed, so NOT succeeds (with same bindings, no new variables)";
        rest_result = this:_prove_goals(rest_goals, bindings);
        return rest_result;
      endif
    endif

    "Get all solutions for the first goal";
    solutions = this:_solve_goal(first_goal, bindings);

    "Try to prove the rest with each solution";
    all_results = {};
    for solution_bindings in (solutions)
      rest_result = this:_prove_goals(rest_goals, solution_bindings);
      if (rest_result['success])
        all_results = {@all_results, rest_result['bindings]};
      endif
    endfor


    "Return all results, or failure if none";
    if (length(all_results) == 0)
      return ['success -> false, 'bindings -> [], 'alternatives -> {}];
    endif

    return [
      'success -> true,
      'bindings -> all_results[1],
      'alternatives -> all_results[2..$]
    ];
  endverb

  verb _solve_goal (this none this) owner: HACKER flags: "rxd"
    "Solve a single goal by calling fact predicates.";
    "Goal format: {predicate_name, arg1, arg2, ...}";
    "Returns list of variable bindings that satisfy the goal";
    {goal, bindings} = args;
    typeof(goal) == LIST || raise(E_TYPE, "goal must be list");
    length(goal) >= 1 || raise(E_INVARG, "goal must have predicate name");

    predicate_name = goal[1];
    goal_args = goal[2..$];
    typeof(predicate_name) == STR || typeof(predicate_name) == SYM ||
      raise(E_TYPE, "predicate name must be string or symbol");

    "Substitute any variables in the goal args";
    substituted_args = this:_substitute_args(goal_args, bindings);

    "Get the object to query (usually first argument)";
    if (length(substituted_args) == 0)
      raise(E_INVARG, "goal needs at least one argument (the object)");
    endif

    target_obj = substituted_args[1];
    typeof(target_obj) == OBJ || raise(E_TYPE, "first goal argument must be object");

    "Build fact verb name and try to call it";
    fact_verb = "fact_" + tostr(predicate_name);

    "Call the fact predicate on the target object";
    fact_results = `target_obj:(fact_verb)(@substituted_args) ! E_VERBNF => false';

    if (fact_results == false)
      return {};
    endif

    "Convert results to list if needed";
    if (typeof(fact_results) != LIST)
      fact_results = {fact_results};
    endif

    "Unify each result with the original goal to get bindings";
    unified_solutions = {};
    for result in (fact_results)
      new_bindings = this:_unify_goal(goal, result, bindings);
      if (new_bindings != false)
        unified_solutions = {@unified_solutions, new_bindings};
      endif
    endfor

    return unified_solutions;
  endverb

  verb _substitute_args (this none this) owner: HACKER flags: "rxd"
    "Replace variables in args with their bindings.";
    {args, bindings} = args;

    result = {};
    for arg in (args)
      substituted = this:_substitute_value(arg, bindings);
      result = {@result, substituted};
    endfor
    return result;
  endverb

  verb _substitute_value (this none this) owner: HACKER flags: "rxd"
    "Substitute a single value, resolving variables.";
    {value, bindings} = args;

    "If it's a symbol and bound, return the binding";
    if (typeof(value) == SYM && maphaskey(bindings, value))
      return bindings[value];
    endif

    "Otherwise return as-is";
    return value;
  endverb

  verb _unify_goal (this none this) owner: HACKER flags: "rxd"
    "Unify a goal with a result, returning new bindings or false.";
    "goal: original goal with variables, e.g. {member, 'X, guild_a}";
    "result: result from fact predicate, e.g. #alice";
    "bindings: current variable bindings";
    {goal, result, bindings} = args;

    "For now, simple unification: the result is what the variable binds to";
    "In a full system, this would handle structured unification";

    "If goal is ground (no variables), just check equality";
    goal_args = goal[2..$];
    has_vars = false;
    for arg in (goal_args)
      if (typeof(arg) == SYM && !maphaskey(bindings, arg))
        has_vars = true;
        break;
      endif
    endfor

    if (!has_vars)
      "No variables, just check if result matches";
      return bindings;
    endif

    "Find the first unbound variable and bind it to result";
    for i in [1..length(goal_args)]
      arg = goal_args[i];
      if (typeof(arg) == SYM && !maphaskey(bindings, arg))
        "Bind this variable";
        bindings[arg] = result;
        return bindings;
      endif
    endfor

    "No unbound variables found - shouldn't happen";
    return bindings;
  endverb

  verb parse_expression (this none this) owner: HACKER flags: "rxd"
    "Parse a builder-friendly expression into a rule flyweight.";
    "Expression syntax: 'Object predicate? AND Object predicate2? OR NOT Object predicate3?'";
    "Capitalized words are variables, lowercase are constants. ? marks a predicate.";
    {expression_string, ?rule_name = 'parsed_rule} = args;
    typeof(expression_string) == STR || raise(E_TYPE, "expression must be string");

    "Tokenize the expression";
    tokens = this:_tokenize(expression_string);

    "Parse tokens into goal list";
    goals = this:_parse_goals(tokens);

    "Extract variables from goals";
    variables = this:_extract_variables_from_goals(goals);

    "Return rule flyweight";
    return <#63,
      .name = rule_name,
      .head = rule_name,
      .body = goals,
      .variables = variables
    >;
  endverb

  verb _tokenize (this none this) owner: HACKER flags: "rxd"
    "Tokenize an expression string into a list of tokens.";
    "Returns: list of strings, each token is a word, operator, or complex term";
    "Complex terms like 'predicate(arg)?' are kept as single tokens";
    {expression_string} = args;

    tokens = {};
    current_token = "";
    i = 1;

    while (i <= length(expression_string))
      char = expression_string[i];

      "Check for whitespace";
      if (char == " " || char == "\t" || char == "\n")
        if (length(current_token) > 0)
          tokens = {@tokens, current_token};
          current_token = "";
        endif
        i = i + 1;
        continue;
      endif

      "Check for ( - start of predicate arguments or expression grouping";
      if (char == "(")
        if (length(current_token) > 0)
          "We have a predicate name - scan for matching )? pattern";
          "Look ahead to see if this is a predicate with arguments";
          paren_count = 1;
          j = i + 1;
          while (j <= length(expression_string) && paren_count > 0)
            if (expression_string[j] == "(")
              paren_count = paren_count + 1;
            elseif (expression_string[j] == ")")
              paren_count = paren_count - 1;
            endif
            j = j + 1;
          endwhile
          "j now points after the closing ), check for ?";
          if (j <= length(expression_string) && expression_string[j] == "?")
            "This is a predicate with args like 'parent(X)?'";
            "Include it all in current token";
            while (i <= j)
              current_token = current_token + expression_string[i];
              i = i + 1;
            endwhile
            tokens = {@tokens, current_token};
            current_token = "";
            continue;
          else
            "Regular parenthesis for grouping";
            tokens = {@tokens, current_token};
            current_token = "";
            tokens = {@tokens, char};
            i = i + 1;
            continue;
          endif
        else
          "Standalone ( for grouping";
          tokens = {@tokens, char};
          i = i + 1;
          continue;
        endif
      endif

      "Check for )";
      if (char == ")")
        if (length(current_token) > 0)
          tokens = {@tokens, current_token};
          current_token = "";
        endif
        tokens = {@tokens, char};
        i = i + 1;
        continue;
      endif

      "Accumulate into current token";
      current_token = current_token + char;
      i = i + 1;
    endwhile

    "Don't forget the last token";
    if (length(current_token) > 0)
      tokens = {@tokens, current_token};
    endif

    return tokens;
  endverb

  verb _parse_goals (this none this) owner: HACKER flags: "rxd"
    "Parse a token list into a goal structure.";
    "Handles AND, OR, NOT operators and parentheses.";
    "Returns either a flat goal list (no OR) or a list of branches (OR present)";
    {tokens} = args;

    "Parse starting from position 1, return (branches, next_position)";
    result = this:_parse_or_expression(tokens, 1);
    branches = result[1];

    "If only one branch, unwrap it to maintain backward compatibility";
    if (length(branches) == 1)
      return branches[1];
    else
      "Multiple branches (OR expressions) - return as list of branches";
      return branches;
    endif
  endverb

  verb _parse_or_expression (this none this) owner: HACKER flags: "rxd"
    "Parse OR expressions: term OR term OR term";
    "Returns: {branches_list, next_position}";
    "Each branch is a list of goals (AND'd together)";
    {tokens, pos} = args;

    "Parse first AND expression";
    result = this:_parse_and_expression(tokens, pos);
    branch = result[1];
    pos = result[2];
    branches = {branch};

    "Parse remaining OR terms";
    while (pos <= length(tokens) && tokens[pos]:lowercase() == "or")
      pos = pos + 1;
      "Parse next AND expression";
      result = this:_parse_and_expression(tokens, pos);
      or_branch = result[1];
      pos = result[2];
      branches = {@branches, or_branch};
    endwhile

    return {branches, pos};
  endverb

  verb _parse_and_expression (this none this) owner: HACKER flags: "rxd"
    "Parse AND expressions: term AND term AND term";
    "Returns: {goals_list, next_position}";
    {tokens, pos} = args;

    "Parse first term";
    result = this:_parse_term(tokens, pos);
    goals = result[1];
    pos = result[2];

    "Parse remaining AND terms";
    while (pos <= length(tokens) && tokens[pos]:lowercase() == "and")
      pos = pos + 1;
      "Parse next term";
      result = this:_parse_term(tokens, pos);
      term_goals = result[1];
      pos = result[2];
      goals = {@goals, @term_goals};
    endwhile

    return {goals, pos};
  endverb

  verb _parse_term (this none this) owner: HACKER flags: "rxd"
    "Parse a single term: either 'NOT term', '(expression)', or 'object predicate(args)?'";
    "Returns: {goals_list, next_position}";
    {tokens, pos} = args;

    pos <= length(tokens) || raise(E_INVARG, "Unexpected end of expression");

    current = tokens[pos];

    "Handle NOT - negation as failure";
    if (current:lowercase() == "not")
      pos = pos + 1;
      result = this:_parse_term(tokens, pos);
      inner_goals = result[1];
      pos = result[2];
      "Wrap goals in 'not' marker: {not, goal1, goal2, ...}";
      not_goal = {'not};
      for goal in (inner_goals)
        not_goal = {@not_goal, goal};
      endfor
      return {{not_goal}, pos};
    endif

    "Handle parentheses";
    if (current == "(")
      pos = pos + 1;
      result = this:_parse_or_expression(tokens, pos);
      goals = result[1];
      pos = result[2];
      pos <= length(tokens) || raise(E_INVARG, "Missing closing parenthesis");
      tokens[pos] == ")" || raise(E_INVARG, "Expected closing parenthesis");
      pos = pos + 1;
      return {goals, pos};
    endif

    "Handle object predicate(args)? syntax";
    object_name = current;
    pos = pos + 1;
    pos <= length(tokens) || raise(E_INVARG, "Expected predicate after object");

    predicate_spec = tokens[pos];
    pos = pos + 1;

    "Check if predicate has arguments: predicate(arg1, arg2)?";
    pred_args = {};
    if (index(predicate_spec, "(") > 0)
      "Parse predicate with arguments";
      result = this:_parse_predicate_with_args(predicate_spec);
      predicate_name = result[1];
      pred_args = result[2];
    else
      "Simple predicate without arguments";
      "Check that predicate ends with ?";
      predicate_spec[length(predicate_spec)] == "?" ||
        raise(E_INVARG, "Predicate must end with ?");

      "Strip the ?";
      predicate_name = predicate_spec[1..length(predicate_spec)-1];
    endif

    "Convert object name to symbol or object reference";
    object_arg = this:_resolve_name(object_name);

    "Build goal: {predicate_name, object_arg, ...pred_args}";
    goal = {tosym(predicate_name:lowercase()), object_arg};
    for arg in (pred_args)
      arg_ref = this:_resolve_name(arg);
      goal = {@goal, arg_ref};
    endfor

    return {{goal}, pos};
  endverb

  verb _parse_predicate_with_args (this none this) owner: HACKER flags: "rxd"
    "Parse a predicate with arguments: 'predicate(arg1, arg2)?'";
    "Returns: {predicate_name, args_list}";
    {predicate_spec} = args;

    "Find opening paren";
    paren_pos = index(predicate_spec, "(");
    paren_pos > 0 || raise(E_INVARG, "Expected ( in predicate");

    predicate_name = predicate_spec[1..paren_pos-1];

    "Find closing paren and ?";
    close_pos = index(predicate_spec, ")");
    close_pos > paren_pos || raise(E_INVARG, "Expected ) in predicate");
    close_pos < length(predicate_spec) ||
      raise(E_INVARG, "Expected ? after )");

    predicate_spec[length(predicate_spec)] == "?" ||
      raise(E_INVARG, "Predicate must end with ?");

    "Extract arguments between ( and )";
    args_str = predicate_spec[paren_pos+1..close_pos-1];

    "Split by comma";
    args = {};
    if (length(args_str) > 0)
      "Simple comma splitting (doesn't handle nested parens, but good enough for now)";
      current_arg = "";
      for i in [1..length(args_str)]
        char = args_str[i];
        if (char == ",")
          arg = current_arg:trim();
          length(arg) > 0 || raise(E_INVARG, "Empty argument in predicate");
          args = {@args, arg};
          current_arg = "";
        else
          current_arg = current_arg + char;
        endif
      endfor
      "Don't forget the last argument";
      if (length(current_arg) > 0)
        arg = current_arg:trim();
        args = {@args, arg};
      endif
    endif

    return {predicate_name, args};
  endverb

  verb _resolve_name (this none this) owner: HACKER flags: "rxd"
    "Resolve a name to either a variable or object reference.";
    "Capitalized names are variables (symbols).";
    "Lowercase names are object constants.";
    "Numeric strings become integers.";
    {name} = args;

    "Check if it's an integer literal";
    num_val = `toint(name) ! ANY => 0';
    if (num_val != 0 || name == "0")
      return num_val;
    endif

    "TODO: Support float literals (e.g., 3.14)";
    "TODO: Support object literals (e.g., #42, #0000-0000-0000)";

    "Check if first character is uppercase (variable)";
    first_char = name[1];
    if (first_char >= "A" && first_char <= "Z")
      "It's a variable - return as symbol";
      return tosym(name);
    endif

    "Lowercase - try to resolve as a constant";
    "For now, support: player, this, sender, location, sysobj";
    lower_name = name:lowercase();
    if (lower_name == "player")
      return 'player;
    elseif (lower_name == "this")
      return 'this;
    elseif (lower_name == "sender")
      return 'sender;
    elseif (lower_name == "location")
      return 'location;
    elseif (lower_name == "sysobj")
      return 'sysobj;
    else
      "Unknown constant";
      raise(E_INVARG, "Unknown object constant: " + name);
    endif
  endverb

  verb _extract_variables_from_goals (this none this) owner: HACKER flags: "rxd"
    "Extract all variables from a goal list.";
    {goals} = args;

    variables = {};
    for goal in (goals)
      if (typeof(goal) == LIST && length(goal) >= 2)
        "Check each argument after the predicate name";
        for i in [2..length(goal)]
          arg = goal[i];
          if (typeof(arg) == SYM)
            arg_str = tostr(arg);
            "Variables are symbols (should already be detected as SYM)";
            if (!(arg in variables))
              variables = {@variables, arg};
            endif
          endif
        endfor
      endif
    endfor

    return variables;
  endverb

  verb _check_negation_warnings (this none this) owner: HACKER flags: "rxd"
    "Check for problematic negation patterns and return warnings/errors.";
    "Bounded negation: 0-1 unbound variables OK, 2+ is an error.";
    "Returns: list of warning/error strings";
    {goals, current_bindings} = args;

    warnings = {};

    for goal in (goals)
      if (typeof(goal) == LIST && length(goal) > 0 && goal[1] == 'not)
        "This is a negated goal";
        inner_goals = listdelete(goal, 1);

        "Count unbound variables across all inner goals";
        unbound_vars = {};
        for inner_goal in (inner_goals)
          if (typeof(inner_goal) == LIST && length(inner_goal) >= 2)
            for i in [2..length(inner_goal)]
              arg = inner_goal[i];
              if (typeof(arg) == SYM && !maphaskey(current_bindings, arg))
                "Collect unbound variables (deduplicate)";
                if (!(arg in unbound_vars))
                  unbound_vars = {@unbound_vars, arg};
                endif
              endif
            endfor
          endif
        endfor

        "Check if we have 2+ unbound variables (not allowed)";
        if (length(unbound_vars) > 1)
          warnings = {@warnings,
            "ERROR: Negation has " + tostr(length(unbound_vars)) +
            " unbound variables: " + tostr(unbound_vars) +
            " in goal " + tostr(goal) +
            " - bounded negation allows at most 1 unbound variable"
          };
        elseif (length(unbound_vars) == 1)
          "Single unbound variable is OK (bounded negation)";
        endif
      endif
    endfor

    return warnings;
  endverb

  verb test_simple_goal (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test evaluating a simple goal.";
    "Create a test object with a fact predicate";
    test_obj = $root:create(true);
    test_obj.name = "Test Object";

    "Define a simple fact: fact_true() returns true";
    "info: {owner, perms, names}";
    "args: {dobj, prep, iobj}";
    add_verb(test_obj, {#2, "rxd", "fact_true"}, {"this", "none", "none"});
    set_verb_code(test_obj, "fact_true", {"return true;"});

    "Evaluate a goal";
    "Note: predicate name is 'true', not 'fact_true' - the fact_ prefix is added by _solve_goal";
    empty_bindings = [];
    goal = {'true, test_obj};
    result = this:_solve_goal(goal, empty_bindings);

    typeof(result) == LIST || raise(E_ASSERT, "Result should be list");
    length(result) > 0 || raise(E_ASSERT, "Should have at least one solution");
    return true;
  endverb

  verb test_conjunction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test proving multiple goals (conjunction).";
    "Two goals: reputation >= 5 AND reputation >= 3 (both should succeed)";
    test_guild = #64;
    goals = {{'reputation, test_guild, 5}, {'reputation, test_guild, 3}};
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Both goals should succeed");
    return true;
  endverb

  verb test_failed_goal (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test a goal that should fail.";
    "Reputation >= 10 should fail (#64 has reputation 8)";
    test_guild = #64;
    goal = {'reputation, test_guild, 10};
    empty_bindings = [];

    result = this:_solve_goal(goal, empty_bindings);

    typeof(result) == LIST || raise(E_ASSERT, "Result should be list");
    length(result) == 0 || raise(E_ASSERT, "Should have no solutions");
    return true;
  endverb

  verb test_variable_binding (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test variable unification in goals.";
    "Query: what X satisfies parent(test_obj, X)?";
    test_obj = #64;

    "Set up parent relationship";
    test_obj.father = $root;

    "Create goal with variable 'X in second position";
    goal = {'parent, test_obj, 'X};
    empty_bindings = [];

    result = this:_solve_goal(goal, empty_bindings);

    typeof(result) == LIST || raise(E_ASSERT, "Result should be list");
    length(result) > 0 || raise(E_ASSERT, "Should have at least one solution");
    "First solution should bind 'X to $root";
    first_solution = result[1];
    typeof(first_solution) == MAP || raise(E_ASSERT, "Solution should be map");
    first_solution['X] == $root || raise(E_ASSERT, "'X should be bound to $root");

    return true;
  endverb

  verb test_multiple_solutions (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test goals that have multiple solutions via alternatives.";
    "Create a test object with both father and mother";
    test_obj = #64;
    test_obj.father = $root;
    test_obj.mother = $arch_wizard;

    "Query: what X satisfies parent(test_obj, X)?";
    goal = {'parent, test_obj, 'X};
    empty_bindings = [];

    result = this:_prove_goals({goal}, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Goal should succeed");
    "Check that we have alternatives (multiple solutions)";
    alternatives = result['alternatives];
    typeof(alternatives) == LIST || raise(E_ASSERT, "Alternatives should be list");
    length(alternatives) > 0 || raise(E_ASSERT, "Should have alternative solutions");

    return true;
  endverb

  verb test_transitive_uncle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test transitive relationship: uncle = parent's parent.";
    "Set up family: test_obj has mother, mother has father";
    test_obj = #64;
    "Create mother object (inherit from RULE_TEST to get father/mother properties)";
    mother_obj = #64:create(true);
    test_obj.mother = mother_obj;
    "Set mother's father (test_obj's grandfather)";
    mother_obj.father = $arch_wizard;

    "Query: what X satisfies parent(test_obj, Y) AND parent(Y, X)?";
    "This should find test_obj's grandparents";
    goals = {
      {'parent, test_obj, 'Y},
      {'parent, 'Y, 'X}
    };
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should find grandparent");

    "Verify that X is bound to the grandfather";
    first_binding = result['bindings];
    typeof(first_binding) == MAP || raise(E_ASSERT, "Binding should be map");
    first_binding['X] == $arch_wizard || raise(E_ASSERT, "X should be $arch_wizard (grandfather)");
    first_binding['Y] == mother_obj || raise(E_ASSERT, "Y should be mother_obj");

    return true;
  endverb

  verb test_cousin_relationship (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test cousin relationship: verify cousin shares grandparent.";
    "Build family tree:";
    "  $arch_wizard (grandparent)";
    "    |";
    "    +-- mother_obj (parent)";
    "    |      |";
    "    |      +-- test_obj (ego)";
    "    |";
    "    +-- sibling_obj (parent's sibling)";
    "           |";
    "           +-- cousin_obj (cousin)";

    test_obj = #64;
    "Reset test_obj's family (clear from previous tests)";
    test_obj.father = #0;
    test_obj.mother = #0;

    "Create mother";
    mother_obj = #64:create(true);
    test_obj.mother = mother_obj;
    mother_obj.father = $arch_wizard;

    "Create sibling of mother";
    sibling_obj = #64:create(true);
    sibling_obj.father = $arch_wizard;

    "Create cousin (sibling's child)";
    cousin_obj = #64:create(true);
    cousin_obj.father = sibling_obj;

    "Query: cousin_obj and test_obj share a grandparent";
    "Find: does cousin_obj's grandparent equal test_obj's grandparent?";
    goals_test_obj = {
      {'parent, test_obj, 'P1},
      {'parent, 'P1, 'TestGrandparent}
    };
    result_test = this:_prove_goals(goals_test_obj, []);
    typeof(result_test) == MAP || raise(E_ASSERT, "Result should be map");
    result_test['success] || raise(E_ASSERT, "Should find test_obj's grandparent");
    test_grandparent = result_test['bindings]['TestGrandparent];

    "Now check cousin_obj's grandparent";
    goals_cousin = {
      {'parent, cousin_obj, 'P2},
      {'parent, 'P2, 'CousinGrandparent}
    };
    result_cousin = this:_prove_goals(goals_cousin, []);
    typeof(result_cousin) == MAP || raise(E_ASSERT, "Result should be map");
    result_cousin['success] || raise(E_ASSERT, "Should find cousin's grandparent");
    cousin_grandparent = result_cousin['bindings]['CousinGrandparent];

    "Verify they share the same grandparent";
    test_grandparent == cousin_grandparent ||
      raise(E_ASSERT, "Cousin and test_obj should share grandparent");

    return true;
  endverb

  verb test_parse_simple_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing a simple expression into a rule.";
    "Parse: 'player has_key?'";
    expression = "player has_key?";
    rule = this:parse_expression(expression, 'simple_parse_test);

    typeof(rule) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    rule.head == 'simple_parse_test || raise(E_ASSERT, "Rule head should match");
    typeof(rule.body) == LIST || raise(E_ASSERT, "Rule body should be list");
    length(rule.body) == 1 || raise(E_ASSERT, "Should have 1 goal");

    "Check the goal structure";
    goal = rule.body[1];
    typeof(goal) == LIST || raise(E_ASSERT, "Goal should be list");
    length(goal) == 2 || raise(E_ASSERT, "Goal should have 2 elements");
    goal[1] == 'has_key || raise(E_ASSERT, "Predicate should be has_key");

    return true;
  endverb

  verb test_parse_variable_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing expression with variables.";
    "Parse: 'Player has_key? AND Player is_trusted?'";
    expression = "Player has_key? AND Player is_trusted?";
    rule = this:parse_expression(expression, 'variable_test);

    typeof(rule.body) == LIST || raise(E_ASSERT, "Body should be list");
    length(rule.body) == 2 || raise(E_ASSERT, "Should have 2 goals");

    "Check variables were extracted";
    length(rule.variables) > 0 || raise(E_ASSERT, "Should have variables");
    'Player in rule.variables || raise(E_ASSERT, "Should have Player variable");

    "Check first goal";
    goal1 = rule.body[1];
    goal1[1] == 'has_key || raise(E_ASSERT, "First predicate should be has_key");
    goal1[2] == 'Player || raise(E_ASSERT, "First goal arg should be Player variable");

    "Check second goal";
    goal2 = rule.body[2];
    goal2[1] == 'is_trusted || raise(E_ASSERT, "Second predicate should be is_trusted");
    goal2[2] == 'Player || raise(E_ASSERT, "Second goal arg should be Player variable");

    return true;
  endverb

  verb test_parse_mixed_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing expression with both constants and variables.";
    "Parse: 'Player has_key? AND location is_open?'";
    expression = "Player has_key? AND location is_open?";
    rule = this:parse_expression(expression, 'mixed_test);

    length(rule.body) == 2 || raise(E_ASSERT, "Should have 2 goals");

    goal1 = rule.body[1];
    goal1[1] == 'has_key || raise(E_ASSERT, "First predicate should be has_key");
    goal1[2] == 'Player || raise(E_ASSERT, "First arg should be Player variable");

    goal2 = rule.body[2];
    goal2[1] == 'is_open || raise(E_ASSERT, "Second predicate should be is_open");
    goal2[2] == 'location || raise(E_ASSERT, "Second arg should be location constant");

    return true;
  endverb

  verb test_parse_and_evaluate_family (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing a family relationship expression and evaluating it.";
    "Parse: 'Child parent(Grandparent)? AND Grandparent parent(GreatGrandparent)?'";
    expression = "Child parent(Grandparent)? AND Grandparent parent(GreatGrandparent)?";
    rule = this:parse_expression(expression, 'find_ancestors);

    "Set up family: test_obj has mother, mother has father";
    test_obj = #64;
    test_obj.father = #0;
    test_obj.mother = #0;
    mother_obj = #64:create(true);
    test_obj.mother = mother_obj;
    mother_obj.father = $arch_wizard;

    "Now evaluate the rule with bindings: Child=test_obj";
    "This should find: Grandparent=mother_obj, GreatGrandparent=$arch_wizard";
    bindings = ['Child -> test_obj];
    result = this:evaluate(rule, bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should find ancestors");

    "Check bindings";
    result_bindings = result['bindings];
    result_bindings['Grandparent] == mother_obj ||
      raise(E_ASSERT, "Grandparent should be mother_obj");
    result_bindings['GreatGrandparent] == $arch_wizard ||
      raise(E_ASSERT, "GreatGrandparent should be $arch_wizard");

    return true;
  endverb

  verb test_parse_or_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing OR expressions from strings.";
    "Parse: 'Player has_key? OR Player has_lockpick?'";
    expression = "Player has_key? OR Player has_lockpick?";
    rule = this:parse_expression(expression, 'key_or_pick);

    typeof(rule) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    typeof(rule.body) == LIST || raise(E_ASSERT, "Body should be list");
    length(rule.body) == 2 || raise(E_ASSERT, "Should have 2 branches");

    "Check first branch";
    branch1 = rule.body[1];
    typeof(branch1) == LIST || raise(E_ASSERT, "Branch should be list");
    length(branch1) == 1 || raise(E_ASSERT, "First branch should have 1 goal");
    branch1[1][1] == 'has_key || raise(E_ASSERT, "First goal should be has_key");

    "Check second branch";
    branch2 = rule.body[2];
    typeof(branch2) == LIST || raise(E_ASSERT, "Branch should be list");
    length(branch2) == 1 || raise(E_ASSERT, "Second branch should have 1 goal");
    branch2[1][1] == 'has_lockpick || raise(E_ASSERT, "Second goal should be has_lockpick");

    return true;
  endverb

  verb test_parse_and_evaluate_or (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing and evaluating OR expressions.";
    "Parse: 'Player has_key? OR Player has_lockpick?'";
    expression = "Player has_key? OR Player has_lockpick?";
    rule = this:parse_expression(expression, 'key_or_pick);

    test_obj = #64;

    "Define fact_has_lockpick on test_obj (has_key will fail)";
    add_verb(test_obj, {#2, "rxd", "fact_has_lockpick"}, {"this", "none", "none"});
    set_verb_code(test_obj, "fact_has_lockpick", {"return true;"});

    "Evaluate rule with Player=test_obj";
    bindings = ['Player -> test_obj];
    result = this:evaluate(rule, bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should succeed (lockpick branch works)");

    return true;
  endverb

  verb test_or_alternatives (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test evaluating OR expressions with alternatives.";
    "Query: (Player has_key?) OR (Player has_lockpick?)";
    test_obj = #64;

    "Branch 1: Player has_key (will fail)";
    branch1 = {{'has_key, test_obj}};

    "Branch 2: Player has_lockpick (will succeed)";
    branch2 = {{'has_lockpick, test_obj}};

    "Define fact_has_lockpick on test_obj";
    add_verb(test_obj, {#2, "rxd", "fact_has_lockpick"}, {"this", "none", "none"});
    set_verb_code(test_obj, "fact_has_lockpick", {"return true;"});

    "Prove alternatives: branch1 OR branch2";
    alternatives = {branch1, branch2};
    result = this:_prove_alternatives(alternatives, []);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should succeed (second branch succeeds)");

    return true;
  endverb

  verb test_parse_and_evaluate_cousin (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing cousin relationship: find shared grandparents.";
    "Parse: 'Person1 parent(Parent1)? AND Parent1 parent(Grandparent)? AND Person2 parent(Parent2)? AND Parent2 parent(Grandparent)?'";
    expression = "Person1 parent(Parent1)? AND Parent1 parent(Grandparent)? AND Person2 parent(Parent2)? AND Parent2 parent(Grandparent)?";
    rule = this:parse_expression(expression, 'find_cousins);

    "Build family tree:";
    "  $arch_wizard (grandparent)";
    "    |";
    "    +-- mother1_obj (parent of person1)";
    "    |      |";
    "    |      +-- person1_obj (ego)";
    "    |";
    "    +-- mother2_obj (parent of person2)";
    "           |";
    "           +-- person2_obj (cousin)";

    person1_obj = #64;
    person1_obj.father = #0;
    person1_obj.mother = #0;

    mother1_obj = #64:create(true);
    person1_obj.mother = mother1_obj;
    mother1_obj.father = $arch_wizard;

    mother2_obj = #64:create(true);
    mother2_obj.father = $arch_wizard;

    person2_obj = #64:create(true);
    person2_obj.father = mother2_obj;

    "Evaluate with: Person1=person1_obj, Person2=person2_obj";
    "This should find: Parent1=mother1_obj, Parent2=mother2_obj, Grandparent=$arch_wizard";
    bindings = ['Person1 -> person1_obj, 'Person2 -> person2_obj];
    result = this:evaluate(rule, bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should find shared grandparent");

    result_bindings = result['bindings];
    result_bindings['Grandparent] == $arch_wizard ||
      raise(E_ASSERT, "Grandparent should be $arch_wizard");

    return true;
  endverb

  verb test_ancestor_chain (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test longer ancestor chain: 4-generation ancestor query.";
    "Build 5-generation family to test 4-step chain";
    test_obj = #64;
    "Reset test_obj's family (clear from previous tests)";
    test_obj.father = #0;
    test_obj.mother = #0;

    "Create mother (gen 2)";
    mother_obj = #64:create(true);
    test_obj.mother = mother_obj;

    "Create maternal grandmother (gen 3)";
    grandmother_obj = #64:create(true);
    mother_obj.mother = grandmother_obj;

    "Create maternal great-grandmother (gen 4)";
    great_grandmother_obj = #64:create(true);
    grandmother_obj.mother = great_grandmother_obj;

    "Create maternal great-great-grandmother (gen 5)";
    great_great_grandmother_obj = #64:create(true);
    great_grandmother_obj.mother = great_great_grandmother_obj;

    "Query: 4-goal chain to find great-great-grandmother";
    "This tests: test_obj -> gen2 -> gen3 -> gen4 -> gen5";
    goals = {
      {'parent, test_obj, 'P1},
      {'parent, 'P1, 'P2},
      {'parent, 'P2, 'P3},
      {'parent, 'P3, 'Result}
    };
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "Should find 4-generation ancestor chain");

    bindings = result['bindings];
    bindings['Result] == great_great_grandmother_obj ||
      raise(E_ASSERT, "Should find great-great-grandmother through 4-step chain");

    return true;
  endverb

  verb test_parse_negation (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing negation (NOT) operator.";
    "Expression: 'NOT Object predicate?'";
    expression = "NOT player has_magic?";
    rule = this:parse_expression(expression, 'test_not);

    typeof(rule) == FLYWEIGHT || raise(E_ASSERT, "Should return flyweight");
    rule.body != {} || raise(E_ASSERT, "Body should not be empty");

    "Body should contain a NOT goal: {{'not, {...}}}";
    body = rule.body;
    length(body) > 0 || raise(E_ASSERT, "Body should have at least one goal");
    first_goal = body[1];
    typeof(first_goal) == LIST || raise(E_ASSERT, "First goal should be list");
    length(first_goal) > 0 || raise(E_ASSERT, "First goal should have content");
    first_goal[1] == 'not || raise(E_ASSERT, "First goal should start with 'not marker");

    return true;
  endverb

  verb test_negation_succeeds (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test negation as failure: NOT succeeds when inner goal fails.";
    test_obj = #64;

    "Create a goal that will fail (reputation >= 100)";
    goal_that_fails = {'reputation, test_obj, 100};

    "Wrap it in NOT: {{'not, goal_that_fails}}";
    not_goal = {'not, goal_that_fails};
    goals = {not_goal};
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "NOT of failing goal should succeed");

    return true;
  endverb

  verb test_negation_fails (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test negation as failure: NOT fails when inner goal succeeds.";
    test_obj = #64;

    "Create a goal that will succeed (reputation >= 5)";
    goal_that_succeeds = {'reputation, test_obj, 5};

    "Wrap it in NOT: {{'not, goal_that_succeeds}}";
    not_goal = {'not, goal_that_succeeds};
    goals = {not_goal};
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    !result['success] || raise(E_ASSERT, "NOT of succeeding goal should fail");

    return true;
  endverb

  verb test_negation_with_conjunction (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test negation in conjunction: goal1 AND NOT goal2.";
    test_obj = #64;

    "Create: reputation(test_obj, 5) AND NOT reputation(test_obj, 100)";
    "Both should succeed: first because 8 >= 5, second because 8 < 100";
    goal1 = {'reputation, test_obj, 5};
    goal2_fails = {'reputation, test_obj, 100};
    not_goal = {'not, goal2_fails};
    goals = {goal1, not_goal};
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    result['success] || raise(E_ASSERT, "goal1 AND NOT goal2 should succeed");

    return true;
  endverb

  verb test_parse_and_evaluate_not (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing and evaluating a NOT expression.";
    "Instead of using 'player' constant, directly build goals from parsed rule";
    test_obj = #64;

    "Build goals directly: reputation(test_obj, 100) AND NOT reputation(test_obj, 50)";
    goal1 = {'reputation, test_obj, 100};
    goal2_fails = {'reputation, test_obj, 50};
    not_goal = {'not, goal2_fails};
    goals = {goal1, not_goal};
    empty_bindings = [];

    result = this:_prove_goals(goals, empty_bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    "First goal fails (8 < 100), so whole expression fails";
    !result['success] || raise(E_ASSERT, "Expression should fail because first goal fails");

    return true;
  endverb

  verb test_parse_not_failure_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test parsing and evaluating NOT expression from string.";
    "Expression: 'this reputation(5)? AND NOT this reputation(100)?'";
    test_obj = #64;

    expression = "this reputation(5)? AND NOT this reputation(100)?";
    rule = this:parse_expression(expression, 'test_not_parsed);

    typeof(rule) == FLYWEIGHT || raise(E_ASSERT, "Should parse to flyweight");
    rule.body != {} || raise(E_ASSERT, "Body should not be empty");

    "Evaluate with initial binding this -> test_obj";
    bindings = ['this -> test_obj];
    result = this:evaluate(rule, bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    "First goal succeeds (8 >= 5), NOT goal succeeds (8 < 100), so conjunction succeeds";
    result['success] || raise(E_ASSERT, "Expression should succeed");

    return true;
  endverb

  verb test_parse_complex_not_expression (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test complex NOT expression: 'this reputation(5)? AND NOT this reputation(100)? OR this reputation(3)?'";
    test_obj = #64;

    "This should parse to: (reputation(5) AND NOT reputation(100)) OR reputation(3)";
    expression = "this reputation(5)? AND NOT this reputation(100)? OR this reputation(3)?";
    rule = this:parse_expression(expression, 'test_not_complex);

    typeof(rule) == FLYWEIGHT || raise(E_ASSERT, "Should parse to flyweight");

    "Evaluate with initial binding this -> test_obj";
    bindings = ['this -> test_obj];
    result = this:evaluate(rule, bindings);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");
    "First branch: reputation(5) AND NOT reputation(100) should succeed (8 >= 5, 8 < 100)";
    result['success] || raise(E_ASSERT, "Expression should succeed");

    return true;
  endverb

  verb test_negation_bounded_one_unbound (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test that bounded negation (1 unbound var) is allowed.";
    test_obj = #64;

    "Create a rule: NOT parent(test_obj, Parent) where Parent is unbound";
    "This is bounded negation - one unbound variable is OK";
    "Set up test_obj to have a father";
    test_obj.father = $root;

    not_goal = {'not, {'parent, test_obj, 'Parent}};
    rule = <#63,
      .name = 'test_bounded_not,
      .head = 'test_bounded_not,
      .body = {not_goal},
      .variables = {'Parent}
    >;

    "Evaluate with no bindings - should NOT have errors";
    result = this:evaluate(rule, []);

    typeof(result) == MAP || raise(E_ASSERT, "Result should be map");

    "Check for ERROR messages (warnings are OK, but errors mean 2+ unbound)";
    has_error = false;
    for warning in (result['warnings])
      if (index(warning, "ERROR:") > 0)
        has_error = true;
        break;
      endif
    endfor
    has_error && raise(E_ASSERT, "Should NOT have ERROR for 1 unbound variable");

    "NOT parent(test_obj, Parent) checks if there exists any parent";
    "Since test_obj has father = $root, fact_parent will return solutions";
    "So NOT should fail";
    !result['success] || raise(E_ASSERT, "NOT parent should fail (object has parents)");

    return true;
  endverb

endobject

