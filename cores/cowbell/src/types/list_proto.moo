object LIST_PROTO [
  import_export_id -> "list_proto",
  import_export_hierarchy -> {"types"}
]
  name: "List Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Prototype object for list utility methods and functional programming operations.";

  method append owner: HACKER
    "Return a single list containing every element from each argument list, in order.";
    "Example: append({a, b, c}, {d, e}, {}, {f, g, h}) => {a, b, c, d, e, f, g, h}.";
    n = length(args);
    if (n > 50)
      return {@this:append(@args[1..n / 2]), @this:append(@args[n / 2 + 1..n])};
    endif
    l = {};
    for a in (args)
      l = {@l, @a};
    endfor
    return l;
  endmethod

  method assoc owner: HACKER
    "Return the first list element whose index-th value equals target; index defaults to 1.";
    "Returns {} when no matching nested list is found.";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (typeof(t) != TYPE_LIST || length(t) < indx)
        continue;
      endif
      if (t[indx] == target)
        return t;
      endif
    endfor
    return {};
  endmethod

  method assoc_prefix owner: HACKER
    "Return the first list element whose index-th string value starts with target; index defaults to 1.";
    "Returns {} when no matching nested list is found.";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (typeof(t) != TYPE_LIST || length(t) < indx)
        continue;
      endif
      if (typeof(t[indx]) == TYPE_STR && index(t[indx], target) == 1)
        return t;
      endif
    endfor
    return {};
  endmethod

  method check_type owner: HACKER
    "Return true if every list element has one of the requested MOO type constants.";
    "The type argument may be a single type constant or a list of type constants.";
    typelist = typeof(args[2]) == TYPE_LIST ? args[2] | {args[2]};
    for element in (args[1])
      if (!(typeof(element) in typelist))
        return false;
      endif
    endfor
    return true;
  endmethod

  method compress owner: HACKER
    "Return a list with consecutive repeated elements collapsed to one occurrence.";
    "Example: compress({a, b, b, c, b, b, b, d, d, e}) => {a, b, c, b, d, e}.";
    l = args[1];
    if (!l)
      return l;
    endif
    fn compress_consecutive(items)
      let out = {items[1]};
      let last = items[1];
      for x in (listdelete(items, 1))
        if (x != last)
          out = listappend(out, x);
          last = x;
        endif
      endfor
      return out;
    endfn
    return compress_consecutive(l);
  endmethod

  method join owner: HACKER
    "Return the list elements converted to strings and joined by separator, which defaults to a space.";
    {l, ?separator = " "} = args;
    typeof(separator) == TYPE_STR || raise(E_TYPE("join() separator must be string; got " + toliteral(separator)));
    length(l) == 0 && return "";
    length(l) == 1 && return tostr(l[1]);
    result = tostr(l[1]);
    for i in [2..length(l)]
      result = result + separator + tostr(l[i]);
    endfor
    return result;
  endmethod

  method english_list owner: #184
    "Return a human-readable English list such as \"a, b, and c\" or \"a and b\".";
    "Optional arguments customize the empty-list text, conjunction, comma separator, and final comma separator.";
    {things, ?nothingstr = "nothing", ?andstr = " and ", ?commastr = ", ", ?finalcommastr = ","} = args;
    nthings = length(things);
    nthings == 0 && return nothingstr;
    nthings == 1 && return tostr(things[1]);
    nthings == 2 && return tostr(things[1], andstr, things[2]);
    ret = "";
    for k in [1..nthings - 1]
      if (k == nthings - 1)
        commastr = finalcommastr;
      endif
      ret = tostr(ret, things[k], commastr);
    endfor
    return tostr(ret, andstr, things[nthings]);
  endmethod

  method map owner: ARCH_WIZARD
    "Return a new list containing func(item) for each item in the input list.";
    "Example: {1, 2, 3}:map({x} => x * 2) => {2, 4, 6}.";
    set_task_perms(caller_perms());
    {lst, func} = args;
    result = {};
    for item in (lst)
      result = {@result, func(item)};
    endfor
    return result;
  endmethod

  method filter owner: ARCH_WIZARD
    "Return a new list containing only items for which pred(item) is true.";
    "Example: {1, 2, 3, 4, 5}:filter({x} => x % 2 == 0) => {2, 4}.";
    set_task_perms(caller_perms());
    {lst, pred} = args;
    result = {};
    for item in (lst)
      if (pred(item))
        result = {@result, item};
      endif
    endfor
    return result;
  endmethod

  method reduce owner: ARCH_WIZARD
    "Fold the list from left to right by repeatedly calling func(accumulator, item).";
    "Returns initial when the input list is empty.";
    set_task_perms(caller_perms());
    {lst, func, initial} = args;
    accumulator = initial;
    for item in (lst)
      accumulator = func(accumulator, item);
    endfor
    return accumulator;
  endmethod

  method find owner: ARCH_WIZARD
    "Return the first item for which pred(item) is true, or 0 when no item matches.";
    set_task_perms(caller_perms());
    {lst, pred} = args;
    for item in (lst)
      if (pred(item))
        return item;
      endif
    endfor
    return 0;
  endmethod

  method any owner: ARCH_WIZARD
    "Return true if pred(item) is true for at least one item in the list.";
    set_task_perms(caller_perms());
    {lst, pred} = args;
    for item in (lst)
      if (pred(item))
        return true;
      endif
    endfor
    return false;
  endmethod

  method all owner: ARCH_WIZARD
    "Return true if pred(item) is true for every item in the list.";
    "The empty list returns true.";
    set_task_perms(caller_perms());
    {lst, pred} = args;
    for item in (lst)
      if (!(pred(item)))
        return false;
      endif
    endfor
    return true;
  endmethod

  method unique owner: HACKER
    "Return a list with duplicate elements removed while preserving first-seen order.";
    "Example: {1, 2, 2, 3, 1, 4}:unique() => {1, 2, 3, 4}.";
    lst = args[1];
    result = {};
    seen = [];
    for item in (lst)
      if (!maphaskey(seen, item))
        result = {@result, item};
        seen[item] = true;
      endif
    endfor
    return result;
  endmethod

  method group_by owner: ARCH_WIZARD
    "Return a map from key_func(item) to the list of items with that key.";
    "Each group preserves the original item order.";
    set_task_perms(caller_perms());
    {lst, key_func} = args;
    groups = [];
    for item in (lst)
      let key = key_func(item);
      if (maphaskey(groups, key))
        groups[key] = {@groups[key], item};
      else
        groups[key] = {item};
      endif
    endfor
    return groups;
  endmethod

  method compose owner: HACKER
    "Compose each list element for the requested content type and combine the results.";
    "HTML composition returns the composed list; text composition joins rendered text parts.";
    {lst, render_for, content_type, @rest} = args;
    results = {};
    for x in (lst)
      results = {@results, x:compose(render_for, content_type, @rest)};
    endfor
    "For HTML, return list of composed elements (caller wraps in container)";
    "For text formats, join strings";
    if (content_type == 'text_html)
      return results;
    endif
    "Join text results, handling any non-strings gracefully";
    text_parts = {};
    for r in (results)
      if (typeof(r) == TYPE_STR)
        text_parts = {@text_parts, r};
      elseif (typeof(r) == TYPE_FLYWEIGHT)
        text_parts = {@text_parts, r:render(content_type)};
      else
        text_parts = {@text_parts, tostr(r)};
      endif
    endfor
    return text_parts:join("");
  endmethod

  method test_core_list_helpers owner: HACKER
    "Cover append, assoc, assoc_prefix, check_type, join, and english_list.";
    $test_utils:assert_eq(this:append({"a", "b"}, {"c"}, {}, {"d", "e"}), {"a", "b", "c", "d", "e"}, "append concatenates argument lists");
    nested = {{"id", 1}, {"name", "cowbell"}, "skip", {"name", "moor"}};
    $test_utils:assert_eq(this:assoc(nested, "name"), {"name", "cowbell"}, "assoc finds first matching nested list");
    $test_utils:assert_eq(this:assoc(nested, "missing"), {}, "assoc returns empty list when missing");
    $test_utils:assert_eq(this:assoc(nested, "cowbell", 2), {"name", "cowbell"}, "assoc supports custom index");
    $test_utils:assert_eq(this:assoc_prefix({{"alpha", 1}, {"beta", 2}}, "al"), {"alpha", 1}, "assoc_prefix finds string prefix");
    $test_utils:assert_eq(this:assoc_prefix({{"alpha", 1}, {42, 2}}, "4"), {}, "assoc_prefix ignores non-string indexed values");
    $test_utils:assert_true({"a", "b"}:check_type(TYPE_STR), "check_type accepts a single type");
    $test_utils:assert_true({"a", 1}:check_type({TYPE_STR, TYPE_INT}), "check_type accepts multiple types");
    $test_utils:assert_false({"a", 1}:check_type(TYPE_STR), "check_type rejects unmatched types");
    $test_utils:assert_eq({}:join(), "", "join empty list");
    $test_utils:assert_eq({"a", "b", "c"}:join(", "), "a, b, c", "join custom separator");
    $test_utils:assert_eq({1, 2, 3}:join("-"), "1-2-3", "join coerces non-string items");
    $test_utils:assert_eq({}:english_list(), "nothing", "english_list empty list");
    $test_utils:assert_eq({"red"}:english_list(), "red", "english_list single item");
    $test_utils:assert_eq({"red", "blue"}:english_list(), "red and blue", "english_list two items");
    $test_utils:assert_eq({"red", "blue", "green"}:english_list(), "red, blue, and green", "english_list three items");
    $test_utils:assert_eq({"red", "blue", "green"}:english_list("nothing", " or ", "; ", ";"), "red; blue; or green", "english_list custom separators");
    return true;
  endmethod

  method test_functional_list_helpers owner: ARCH_WIZARD
    "Cover map, filter, reduce, find, any, and all.";
    $test_utils:assert_eq({1, 2, 3}:map({x} => x * 2), {2, 4, 6}, "map transforms every item");
    $test_utils:assert_eq({}:map({x} => x + 1), {}, "map preserves empty lists");
    $test_utils:assert_eq({"a", "b", "c"}:map({x} => x + "X"), {"aX", "bX", "cX"}, "map handles strings");
    $test_utils:assert_eq({1, 2, 3, 4, 5}:filter({x} => x % 2 == 0), {2, 4}, "filter keeps matching items");
    $test_utils:assert_eq({1, 3, 5}:filter({x} => x % 2 == 0), {}, "filter can return empty list");
    $test_utils:assert_eq({1, 2, 3, 4}:reduce({acc, x} => acc + x, 0), 10, "reduce sums values");
    $test_utils:assert_eq({}:reduce({acc, x} => acc + x, 42), 42, "reduce returns initial for empty lists");
    $test_utils:assert_eq({1, 2, 3, 4, 5}:find({x} => x > 3), 4, "find returns first match");
    $test_utils:assert_eq({1, 2, 3}:find({x} => x > 10), 0, "find returns 0 when missing");
    $test_utils:assert_true({1, 2, 3}:any({x} => x > 2), "any true case");
    $test_utils:assert_false({1, 2, 3}:any({x} => x > 5), "any false case");
    $test_utils:assert_true({2, 4, 6}:all({x} => x % 2 == 0), "all true case");
    $test_utils:assert_false({1, 2, 3}:all({x} => x % 2 == 0), "all false case");
    $test_utils:assert_true({}:all({x} => x > 100), "all empty list is true");
    expected = task_perms()[1];
    {1}:map({x} => caller_perms()) == {expected} || raise(E_ASSERT("map callback should run with caller perms"));
    {1}:filter({x} => caller_perms() == expected) == {1} || raise(E_ASSERT("filter callback should run with caller perms"));
    {1}:reduce({acc, x} => caller_perms(), 0) == expected || raise(E_ASSERT("reduce callback should run with caller perms"));
    {1}:find({x} => caller_perms() == expected) == 1 || raise(E_ASSERT("find callback should run with caller perms"));
    {1}:any({x} => caller_perms() == expected) || raise(E_ASSERT("any callback should run with caller perms"));
    {1}:all({x} => caller_perms() == expected) || raise(E_ASSERT("all callback should run with caller perms"));
    {"a"}:group_by({x} => caller_perms()) == [expected -> {"a"}] || raise(E_ASSERT("group_by callback should run with caller perms"));
    return true;
  endmethod

  method test_set_group_and_compose_helpers owner: HACKER
    "Cover unique, group_by, compress, and compose.";
    $test_utils:assert_eq({1, 2, 2, 3, 1, 4}:unique(), {1, 2, 3, 4}, "unique preserves first-seen order");
    $test_utils:assert_eq({}:unique(), {}, "unique preserves empty list");
    $test_utils:assert_eq({"a", "b", "b", "c", "b", "b", "d"}:compress(), {"a", "b", "c", "b", "d"}, "compress collapses consecutive duplicates");
    $test_utils:assert_eq({}:compress(), {}, "compress preserves empty list");
    result = {"apple", "ant", "bee", "bear"}:group_by({x} => x[1]);
    $test_utils:assert_eq(result, ["a" -> {"apple", "ant"}, "b" -> {"bee", "bear"}], "group_by groups by key function");
    result = {"a", "bb", "c", "dd", "eee"}:group_by({x} => length(x));
    $test_utils:assert_eq(result, [1 -> {"a", "c"}, 2 -> {"bb", "dd"}, 3 -> {"eee"}], "group_by preserves item order within groups");
    $test_utils:assert_eq({}:group_by({x} => x), [], "group_by empty list");
    $test_utils:assert_eq({"a", "b"}:compose(player, 'text), "ab", "compose joins text results");
    $test_utils:assert_eq({"a", "b"}:compose(player, 'text_html), {"a", "b"}, "compose preserves HTML result list");
    return true;
  endmethod
endobject
