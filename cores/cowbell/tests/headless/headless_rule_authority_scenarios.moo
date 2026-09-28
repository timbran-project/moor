// Copyright (C) 2026 The mooR Authors
// SPDX-License-Identifier: GPL-3.0-or-later

object HEADLESS_RULE_AUTHORITY_SCENARIOS
  name: "Rule Authority Scenarios"
  parent: ROOT
  owner: RUNTIME_WIZARD
  readable: true
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_rule_authority_scenarios";

  method test_foreign_reaction_mutation_denied owner: RUNTIME_WIZARD
    "A direct generic effect must preserve the invoking programmer's principal.";
    const victim = create($root, $hacker, 2);
    try
      add_property(victim, "audit_value", 0, {$hacker, ""});
      try
        this:_invoke_as_programmer("direct", victim);
      except (E_PERM)
      endtry
      $test_utils:assert_eq(victim.audit_value, 0, "A generic effect must preserve another owner's protected data");
    finally
      recycle(victim);
    endtry
    return true;
  endmethod

  method test_owned_reaction_and_delay_preserve_caller owner: RUNTIME_WIZARD
    "Generic effects and their delayed continuations keep the owner's invoking principal.";
    const target = create($root, #90101, 2);
    try
      add_property(target, "audit_value", 0, {#90101, ""});
      this:_invoke_as_programmer("owned", target);
      $test_utils:assert_eq(target.audit_value, 3, "Own immediate effect must run");
      suspend(2);
      $test_utils:assert_eq(target.audit_value, 4, "Own delayed effect must retain invoking authority");
    finally
      recycle(target);
    endtry
    return true;
  endmethod

  method test_guest_runs_installed_owner_reaction owner: RUNTIME_WIZARD
    "A guest may trigger a configured owner effect without receiving that owner's authority.";
    const target = create($root, #90101, 2);
    try
      add_property(target, "audit_value", 0, {#90101, ""});
      add_property(target, "probe_reaction", $reaction:mk('probe, 0, {{'set, 'audit_value, 7}}), {#90101, "r"});
      this:_trigger_as_guest(target);
      $test_utils:assert_eq(target.audit_value, 7, "Configured owner effect must run for a guest trigger");
    finally
      recycle(target);
    endtry
    return true;
  endmethod

  method _trigger_as_guest owner: RUNTIME_PLAYER
    "Invoke an installed trigger with an ordinary guest principal.";
    caller == #90013 || raise(E_PERM);
    const {target} = args;
    return target:fire_trigger('probe, ['Actor -> #90102]);
  endmethod

  method test_rule_predicate_preserves_caller owner: RUNTIME_WIZARD
    "Nested engine and flyweight entries must pass the original caller to predicates.";
    const rule = $rule:mk('audit, 'audit, {{'audit_principal, this, {'var, 'Principal}}});
    for entry in ({"engine", "rule"})
      const result = this:_evaluate_as_programmer(entry, rule);
      $test_utils:assert_true(result['success], "Principal predicate must succeed");
      $test_utils:assert_eq(result['bindings]['Principal], #90101, "Predicate caller must be the invoking programmer");
    endfor
    return true;
  endmethod

  method test_rule_cartesian_alternatives owner: RUNTIME_WIZARD
    "Independent two-valued predicates retain all four conjunction bindings.";
    const rule = $rule:mk('audit, 'audit, {{'audit_numbers, this, {'var, 'N}}, {'audit_letters, this, {'var, 'L}}});
    const result = $rule_engine:evaluate(rule);
    $test_utils:assert_true(result['success], "A conjunction solution exists");
    $test_utils:assert_eq(1 + length(result['alternatives]), 4, "All conjunction combinations must remain available");
    return true;
  endmethod

  method _invoke_as_programmer owner: RUNTIME_PROGRAMMER
    "Invoke a reaction entry with a verified programmer principal.";
    caller == #90013 || raise(E_PERM);
    const {entry, target} = args;
    entry == "direct" && return $reaction:execute_effect({'set, 'audit_value, 7}, ['Actor -> #90101, 'This -> target], target);
    if (entry == "owned")
      const reaction = $reaction:mk('probe, 0, {{'set, 'audit_value, 3}, {'delay, 1, {'increment, 'audit_value, 1}}});
      return reaction:execute(['Actor -> #90101, 'This -> target]);
    endif
    raise(E_INVARG);
  endmethod

  method _evaluate_as_programmer owner: RUNTIME_PROGRAMMER
    "Evaluate through each public rule entry as the programmer fixture.";
    caller == #90013 || raise(E_PERM);
    const {entry, rule} = args;
    entry == "engine" && return $rule_engine:evaluate(rule);
    entry == "rule" && return rule:evaluate();
    raise(E_INVARG);
  endmethod

  method fact_audit_principal owner: RUNTIME_WIZARD
    "Observe the principal passed by the engine's predicate call.";
    return {caller_perms()};
  endmethod

  method fact_audit_numbers owner: RUNTIME_WIZARD
    "Enumerate two independent number bindings.";
    return {1, 2};
  endmethod

  method fact_audit_letters owner: RUNTIME_WIZARD
    "Enumerate two independent letter bindings.";
    return {"a", "b"};
  endmethod
endobject
