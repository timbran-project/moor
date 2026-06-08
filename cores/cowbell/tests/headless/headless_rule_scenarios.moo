object HEADLESS_RULE_SCENARIOS
  name: "Headless Rule Runtime Scenarios"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Headless runtime scenarios for rule evaluation over runtime-created fixtures.";
  override import_export_hierarchy = {"tests", "headless"};
  override import_export_id = "headless_rule_scenarios";

  verb test_headless_rule_engine_with_fixture (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: rule evaluation resolves facts against a runtime-created fixture object.";
    fixture = #64:create(true);
    fixture.father = $root;
    fixture.mother = $thing;
    rule = $rule:mk('fixture_parents, 'fixture_parents, {{'parent, fixture, 'Parent}});
    result = $rule_engine:evaluate(rule);
    $test_utils:assert_true(result['success], "parent rule should have solutions");
    parents = {result['bindings]['Parent]};
    for alt in (result['alternatives])
      parents = {@parents, alt['Parent]};
    endfor
    $test_utils:assert_eq(length(parents), 2, "parent rule should bind both fixture parents");
    $test_utils:assert_true($root in parents, "parent rule should include $root");
    $test_utils:assert_true($thing in parents, "parent rule should include $thing");
    return true;
  endverb

  verb test_headless_rule_engine_negative_fixture (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Runtime scenario: rule evaluation reports failure when a bound fact has no matching fixture value.";
    fixture = #64:create(true);
    fixture.father = $root;
    fixture.mother = $thing;
    rule = $rule:mk('fixture_missing_parent, 'fixture_missing_parent, {{'parent, fixture, $room}});
    result = $rule_engine:evaluate(rule);
    $test_utils:assert_false(result['success], "parent rule should fail for a non-parent object");
    $test_utils:assert_eq(result['bindings], [], "failed rule should not return bindings");
    $test_utils:assert_eq(result['alternatives], {}, "failed rule should not return alternatives");
    return true;
  endverb
endobject
