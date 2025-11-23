// $rule_test - Test fixture for rule system
// Simple test objects with fact predicates

object RULE_TEST
  name: "Rule Test"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Test fixture providing sample fact predicates for testing the rule system.";
  override import_export_hierarchy = {"rules"};
  override import_export_id = "rule_test";

  property reputation (owner: HACKER, flags: "") = 8;
  property guild_name (owner: HACKER, flags: "") = "Test Guild";

  verb fact_reputation (this none this) owner: HACKER flags: "rxd"
    "Fact: reputation(Guild, MinLevel) - does Guild have reputation >= MinLevel?";
    {guild, min_level} = args;
    typeof(min_level) == INT || raise(E_TYPE, "min_level must be integer");

    if (guild != this)
      return false;
    endif

    return this.reputation >= min_level;
  endverb

  verb test_fact_reputation (this none this) owner: HACKER flags: "rxd"
    "Test the fact_reputation predicate.";
    result = this:fact_reputation(this, 5);
    result == true || raise(E_ASSERT, "Reputation 8 >= 5");

    result = this:fact_reputation(this, 10);
    result == false || raise(E_ASSERT, "Reputation 8 < 10");

    return true;
  endverb

  property father (owner: HACKER, flags: "") = #0;
  property mother (owner: HACKER, flags: "") = #0;

  verb fact_parent (this none this) owner: HACKER flags: "rxd"
    "Fact: parent(Child, Parent) - return list of all valid (Child, Parent) bindings";
    {child, parent} = args;

    "If child is not this object, no solutions";
    if (child != this)
      return {};
    endif

    "Build list of all parents";
    parents = {};
    if (this.father != #0)
      parents = {@parents, this.father};
    endif
    if (this.mother != #0)
      parents = {@parents, this.mother};
    endif

    "If parent arg is unbound (a variable), return all parents";
    "If parent arg is bound, return parent only if it matches";
    if (typeof(parent) == SYM)
      "parent is a variable - return all valid bindings";
      return parents;
    else
      "parent is ground - check if it's in the list";
      if (parent in parents)
        return {parent};
      else
        return {};
      endif
    endif
  endverb

  verb test_unification_parent (this none this) owner: HACKER flags: "rxd"
    "Test unification in parent relationship.";
    "Set up a simple family: this has a father";
    this.father = $root;

    "Query: is $root a parent of this?";
    result = this:fact_parent(this, $root);
    length(result) > 0 || raise(E_ASSERT, "$root should be parent");
    $root in result || raise(E_ASSERT, "$root should be in result");

    "Query: is #0 a parent of this?";
    result = this:fact_parent(this, #0);
    length(result) == 0 || raise(E_ASSERT, "#0 should not be parent");

    return true;
  endverb

endobject
