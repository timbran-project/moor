object RULE_TEST [
  import_export_id -> "rule_test",
  import_export_hierarchy -> {"rules"}
]
  name: "Rule Test"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property father (owner: HACKER, flags: "") = SYSOBJ;
  property guild_name (owner: HACKER, flags: "") = "Test Guild";
  property mother (owner: HACKER, flags: "") = SYSOBJ;
  property reputation (owner: HACKER, flags: "") = 8;

  override description = "Test fixture providing sample fact predicates for testing the rule system.";

  method fact_reputation owner: HACKER
    "Fact: reputation(Guild, MinLevel) - does Guild have reputation >= MinLevel?";
    {guild, min_level} = args;
    typeof(min_level) == TYPE_INT || raise(E_TYPE, "min_level must be integer");
    if (guild != this)
      return false;
    endif
    return this.reputation >= min_level;
  endmethod

  method test_fact_reputation owner: HACKER
    "Test the fact_reputation predicate.";
    result = this:fact_reputation(this, 5);
    result == true || raise(E_ASSERT, "Reputation 8 >= 5");
    result = this:fact_reputation(this, 10);
    result == false || raise(E_ASSERT, "Reputation 8 < 10");
    return true;
  endmethod

  method fact_parent owner: HACKER
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
    if (typeof(parent) == TYPE_SYM)
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
  endmethod

  method test_unification_parent owner: HACKER
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
  endmethod
endobject
