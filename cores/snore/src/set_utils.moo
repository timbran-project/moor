object SET_UTILS [
  import_export_id -> "set_utils"
]
  name: "Set Utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  override aliases (owner: HACKER, flags: "rc") = {"Set Utilities", "set_utilities"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the Set Utilities utility package.  See `help $set_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "This object is useful for operations that treat lists as sets (i.e.,",
    "without concern about order and assuming no duplication).",
    "",
    " union(set, set, ...)        => union",
    " intersection(set, set, ...) => intersection",
    " intersection_preserve_case(base set, set, set, ...)",
    "        => intersection with the case of the base set's elements preserved",
    "",
    " diff*erence(set1, set2, ..., setn)",
    "        => result of removing all elements of sets 2..n from set 1.",
    "",
    " difference_suspended(set1, set2, ..., setn)",
    "        => same as above except it suspends as needed.",
    "",
    " exclusive_or(set, set, set, ...)",
    "        => all elements that are contained in exactly one of the sets",
    "",
    " contains(set1, set2, ..., setn)",
    "        => true if and only if all of sets 2..n are subsets of set 1",
    "",
    " equal(set1, set2)",
    "        => true if and only if set1 and set2 are equal"
  };
  override object_size (owner: HACKER, flags: "r") = {5574, 1084848672};

  method union owner: HACKER
    "Return the union of the argument lists. Preserve the first list's order and representatives.";
    !args && return {};
    let {result, @remaining} = args;
    for items in (remaining)
      for item in (items)
        result = setadd(result, item);
      endfor
    endfor
    return result;
  endmethod

  method intersection owner: HACKER
    "Intersect the lists using MOO equality; each step keeps representatives from its shorter input.";
    !args && return {};
    let {result, @remaining} = args;
    for items in (remaining)
      const shorter = length(result) < length(items) ? result | items;
      const longer = length(result) < length(items) ? items | result;
      result = { item for item in (shorter) if item in longer };
    endfor
    return result;
  endmethod

  method "diff*erence" owner: HACKER
    "Remove the subsequent sets' elements from the first set, preserving its remaining order.";
    let {result, @remaining} = args;
    for items in (remaining)
      for item in (items)
        result = setremove(result, item);
      endfor
    endfor
    return result;
  endmethod

  method contains owner: HACKER
    "Return whether the first list contains every element of all remaining lists. No arguments returns true.";
    const {?superset = {}, @remaining} = args;
    for items in (remaining)
      for item in (items)
        !(item in superset) && return false;
      endfor
    endfor
    return true;
  endmethod

  method "exclusive_or xor" owner: HACKER
    "Return elements present in exactly one input set, rather than odd-parity membership.";
    !args && return {};
    let {result, @remaining} = args;
    let seen = result;
    for items in (remaining)
      for item in (items)
        if (item in seen)
          result = setremove(result, item);
        else
          result = setadd(result, item);
        endif
      endfor
      seen = {@seen, @items};
    endfor
    return result;
  endmethod

  method "difference_suspended diff_suspended" owner: HACKER
    "Remove subsequent sets' elements from the first set. Budget checks between removals can commit.";
    let {result, @remaining} = args;
    for items in (remaining)
      for item in (items)
        result = setremove(result, item);
        $command_utils:suspend_if_needed(0);
      endfor
    endfor
    return result;
  endmethod

  method equal owner: HACKER
    "Return whether both lists contain the same elements, ignoring duplicates and string case.";
    const {first, second} = args;
    return this:contains(first, second) && this:contains(second, first);
  endmethod

  method intersection_preserve_case owner: HACKER
    "Intersect the argument sets, preserving representatives and order from the first list.";
    !args && return {};
    let {result, @remaining} = args;
    for items in (remaining)
      result = { item for item in (result) if item in items };
    endfor
    return result;
  endmethod
endobject
