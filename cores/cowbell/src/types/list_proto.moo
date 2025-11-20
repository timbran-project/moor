object LIST_PROTO
  name: "List Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Prototype object for list utility methods and functional programming operations.";
  override import_export_hierarchy = {"types"};
  override import_export_id = "list_proto";

  verb append (this none this) owner: HACKER flags: "rxd"
    "append({a,b,c},{d,e},{},{f,g,h},...) =>  {a,b,c,d,e,f,g,h}";
    n = length(args);
    if (n > 50)
      return {@this:append(@args[1..n / 2]), @this:append(@args[n / 2 + 1..n])};
    endif
    l = {};
    for a in (args)
      l = {@l, @a};
    endfor
    return l;
  endverb

  verb assoc (this none this) owner: HACKER flags: "rx"
    "assoc(list, target[,index]) returns the first element of `list' whose own index-th element is target.  Index defaults to 1.";
    "returns {} if no such element is found";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (t[indx] == target)
        "... do this test first since it's the most likely to fail; this needs -d";
        if (typeof(t) == LIST && length(t) >= indx)
          return t;
        endif
      endif
    endfor
    return {};
  endverb

  verb assoc_prefix (this none this) owner: HACKER flags: "rxd"
    "assoc_prefix(list, target[,index]) returns the first element of `list' whose own index-th element has target as a prefix.  Index defaults to 1.";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (typeof(t) == LIST && (length(t) >= indx && index(t[indx], target) == 1))
        return t;
      endif
    endfor
    return {};
  endverb

  verb check_type (this none this) owner: HACKER flags: "rxd"
    "check_type(list, type)";
    "Make sure all elements of <list> are of a given <type>.";
    "<type> can be either one of LIST, STR, OBJ, NUM, ERR, or a list of same.";
    "return true if all elements check, otherwise 0.";
    typelist = typeof(args[2]) == LIST ? args[2] | {args[2]};
    for element in (args[1])
      if (!(typeof(element) in typelist))
        return false;
      endif
    endfor
    return true;
  endverb

  verb compress (this none this) owner: HACKER flags: "rxd"
    "compress(list) => list with consecutive repeated elements removed, e.g.,";
    "compress({a,b,b,c,b,b,b,d,d,e}) => {a,b,c,b,d,e}";
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
  endverb

  verb join (this none this) owner: HACKER flags: "rxd"
    "join(list[, separator]) => string with list elements joined by separator (default: space)";
    {l, ?separator = " "} = args;
    length(l) == 0 && return "";
    length(l) == 1 && typeof(l[1]) == STR && return l[1];
    length(l) == 1 && raise(E_TYPE("join() expects strings; got " + toliteral(l[1])));
    fn build_joined_string(items, sep)
      let result = "";
      for i in [1..length(items)]
        typeof(items[i]) == STR || raise(E_TYPE("join() expects strings; got " + toliteral(items[i])));
        result = result + items[i];
        if (i < length(items))
          typeof(sep) == STR || raise(E_TYPE("join() separator must be string; got " + toliteral(sep)));
          result = result + sep;
        endif
      endfor
      return result;
    endfn
    typeof(separator) == STR || raise(E_TYPE("join() separator must be string; got " + toliteral(separator)));
    return build_joined_string(l, separator);
  endverb

  verb test_join (this none this) owner: HACKER flags: "rxd"
    "Test the join method";
    {}:join() != "" && raise(E_ASSERT, "Empty list join failed");
    {"hello"}:join() != "hello" && raise(E_ASSERT, "Single element join failed");
    {"a", "b", "c"}:join() != "a b c" && raise(E_ASSERT, "Multi element join failed");
    {"a", "b", "c"}:join(", ") != "a, b, c" && raise(E_ASSERT, "Custom separator join failed");
    {1, 2, 3}:join("-") != "1-2-3" && raise(E_ASSERT, "Number join failed");
  endverb

  verb english_list (this none this) owner: #184 flags: "rxd"
    "Prints the argument (must be a list) as an english list, e.g. {1, 2, 3} is printed as \"1, 2, and 3\", and {1, 2} is printed as \"1 and 2\".";
    "Optional arguments are treated as follows:";
    "  Second argument is the string to use when the empty list is given.  The default is \"nothing\".";
    "  Third argument is the string to use in place of \" and \".  A typical application might be to use \" or \" instead.";
    "  Fourth argument is the string to use instead of a comma (and space).  Gary_Severn's deranged mind actually came up with an application for this.  You can ask him.";
    "  Fifth argument is a string to use after the penultimate element before the \" and \".  The default is to have a comma without a space.";
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
  endverb

  verb map (this none this) owner: HACKER flags: "rxd"
    "map(list, function) => apply function to each element and return new list";
    "Example: {1,2,3}:map({x} => x * 2) => {2,4,6}";
    {lst, func} = args;
    result = {};
    for item in (lst)
      result = {@result, func(item)};
    endfor
    return result;
  endverb

  verb filter (this none this) owner: HACKER flags: "rxd"
    "filter(list, predicate) => return new list with only elements matching predicate";
    "Example: {1,2,3,4,5}:filter({x} => x % 2 == 0) => {2,4}";
    {lst, pred} = args;
    result = {};
    for item in (lst)
      if (pred(item))
        result = {@result, item};
      endif
    endfor
    return result;
  endverb

  verb reduce (this none this) owner: HACKER flags: "rxd"
    "reduce(list, function, initial) => combine all elements using function";
    "Example: {1,2,3,4}:reduce({acc, x} => acc + x, 0) => 10";
    {lst, func, initial} = args;
    accumulator = initial;
    for item in (lst)
      accumulator = func(accumulator, item);
    endfor
    return accumulator;
  endverb

  verb find (this none this) owner: HACKER flags: "rxd"
    "find(list, predicate) => return first element matching predicate, or 0 if none";
    "Example: {\"apple\", \"banana\", \"cherry\"}:find({x} => \"a\" in x) => \"apple\"";
    {lst, pred} = args;
    for item in (lst)
      if (pred(item))
        return item;
      endif
    endfor
    return 0;
  endverb

  verb any (this none this) owner: HACKER flags: "rxd"
    "any(list, predicate) => return true if any element matches predicate";
    "Example: {1,2,3}:any({x} => x > 2) => true";
    {lst, pred} = args;
    for item in (lst)
      if (pred(item))
        return true;
      endif
    endfor
    return false;
  endverb

  verb all (this none this) owner: HACKER flags: "rxd"
    "all(list, predicate) => return true if all elements match predicate";
    "Example: {2,4,6}:all({x} => x % 2 == 0) => true";
    {lst, pred} = args;
    for item in (lst)
      if (!pred(item))
        return false;
      endif
    endfor
    return true;
  endverb

  verb unique (this none this) owner: HACKER flags: "rxd"
    "unique(list) => return list with duplicate elements removed";
    "Example: {1,2,2,3,1,4}:unique() => {1,2,3,4}";
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
  endverb

  verb group_by (this none this) owner: HACKER flags: "rxd"
    "group_by(list, key_function) => return map of key -> list of items with that key";
    "Example: {\"apple\", \"ant\", \"bee\", \"bear\"}:group_by({x} => x[1]) => [\"a\" -> {\"apple\", \"ant\"}, \"b\" -> {\"bee\", \"bear\"}]";
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
  endverb

  verb compose (this none this) owner: HACKER flags: "rxd"
    "Runs :compose on all elements in turn then joins them together into a result";
    results = {};
    for x in (args[1])
      results = {@results, x:compose(@args[2..$])};
    endfor
    return results:join("");
  endverb

  verb test_map (this none this) owner: HACKER flags: "rxd"
    "Test the map function";
    result = 0;
    result = {1, 2, 3}:map({x} => x * 2);
    result != {2, 4, 6} && raise(E_ASSERT, "Basic map failed, got " + toliteral(result));
    result = {}:map({y} => y + 1);
    result != {} && raise(E_ASSERT, "Empty list map failed, got " + toliteral(result));
    result = {"a", "b", "c"}:map({z} => z + "X");
    result != {"aX", "bX", "cX"} && raise(E_ASSERT, "String map failed, got " + toliteral(result));
    result = {42}:map({w} => w / 2);
    result != {21} && raise(E_ASSERT, "Single element map failed, got " + toliteral(result));
  endverb

  verb test_filter (this none this) owner: HACKER flags: "rxd"
    "Test the filter function";
    result = 0;
    result = {1, 2, 3, 4, 5}:filter({x} => x % 2 == 0);
    result != {2, 4} && raise(E_ASSERT, "Basic filter failed, got " + toliteral(result));
    result = {1, 3, 5}:filter({y} => y % 2 == 0);
    result != {} && raise(E_ASSERT, "Empty result filter failed, got " + toliteral(result));
    result = {2, 4, 6}:filter({z} => z % 2 == 0);
    result != {2, 4, 6} && raise(E_ASSERT, "All match filter failed, got " + toliteral(result));
    result = {"apple", "ant", "bee", "bear"}:filter({w} => w[1] == "b");
    result != {"bee", "bear"} && raise(E_ASSERT, "String filter failed, got " + toliteral(result));
    result = {}:filter({v} => v > 0);
    result != {} && raise(E_ASSERT, "Empty input filter failed, got " + toliteral(result));
  endverb

  verb test_reduce (this none this) owner: HACKER flags: "rxd"
    "Test the reduce function";
    result = 0;
    result = {1, 2, 3, 4}:reduce({acc0, val0} => acc0 + val0, 0);
    result != 10 && raise(E_ASSERT, "Basic sum reduce failed, got " + toliteral(result));
    result = {2, 3, 4}:reduce({acc1, val1} => acc1 * val1, 1);
    result != 24 && raise(E_ASSERT, "Product reduce failed, got " + toliteral(result));
    result = {3, 1, 4, 1, 5}:reduce({acc2, val2} => val2 > acc2 ? val2 | acc2, 0);
    result != 5 && raise(E_ASSERT, "Max reduce failed, got " + toliteral(result));
    result = {"a", "b", "c"}:reduce({acc3, val3} => acc3 + val3, "");
    result != "abc" && raise(E_ASSERT, "String concat reduce failed, got " + toliteral(result));
    result = {}:reduce({acc4, val4} => acc4 + val4, 42);
    result != 42 && raise(E_ASSERT, "Empty list reduce failed, got " + toliteral(result));
    result = {100}:reduce({acc5, val5} => acc5 + val5, 5);
    result != 105 && raise(E_ASSERT, "Single element reduce failed, got " + toliteral(result));
  endverb

  verb test_find (this none this) owner: HACKER flags: "rxd"
    "Test the find function";
    result = 0;
    result = {1, 2, 3, 4, 5}:find({x} => x > 3);
    result != 4 && raise(E_ASSERT, "Basic find failed, got " + toliteral(result));
    result = {1, 2, 3}:find({y} => y > 10);
    result != 0 && raise(E_ASSERT, "Not found case failed, got " + toliteral(result));
    result = {2, 4, 6, 8}:find({z} => z % 2 == 0);
    result != 2 && raise(E_ASSERT, "First match find failed, got " + toliteral(result));
    result = {"apple", "banana", "cherry"}:find({w} => "a" in w);
    result != "apple" && raise(E_ASSERT, "String find failed, got " + toliteral(result));
    result = {}:find({v} => v == 5);
    result != 0 && raise(E_ASSERT, "Empty list find failed, got " + toliteral(result));
  endverb

  verb test_any (this none this) owner: HACKER flags: "rxd"
    "Test the any function";
    result = 0;
    result = {1, 2, 3}:any({x} => x > 2);
    result != true && raise(E_ASSERT, "True any failed, got " + toliteral(result));
    result = {1, 2, 3}:any({y} => y > 5);
    result != false && raise(E_ASSERT, "False any failed, got " + toliteral(result));
    result = {2, 4, 6}:any({z} => z % 2 == 0);
    result != true && raise(E_ASSERT, "All match any failed, got " + toliteral(result));
    result = {}:any({w} => w > 0);
    result != false && raise(E_ASSERT, "Empty list any failed, got " + toliteral(result));
    result = {42}:any({v} => v == 42);
    result != true && raise(E_ASSERT, "Single element true any failed, got " + toliteral(result));
    result = {42}:any({u} => u == 99);
    result != false && raise(E_ASSERT, "Single element false any failed, got " + toliteral(result));
  endverb

  verb test_all (this none this) owner: HACKER flags: "rxd"
    "Test the all function";
    result = 0;
    result = {2, 4, 6}:all({x} => x % 2 == 0);
    result != true && raise(E_ASSERT, "True all failed, got " + toliteral(result));
    result = {1, 2, 3}:all({y} => y % 2 == 0);
    result != false && raise(E_ASSERT, "False all failed, got " + toliteral(result));
    result = {}:all({z} => z > 100);
    result != true && raise(E_ASSERT, "Empty list all failed, got " + toliteral(result));
    result = {42}:all({w} => w > 40);
    result != true && raise(E_ASSERT, "Single element true all failed, got " + toliteral(result));
    result = {42}:all({v} => v < 40);
    result != false && raise(E_ASSERT, "Single element false all failed, got " + toliteral(result));
    result = {"abc", "def", "ghi"}:all({u} => length(u) == 3);
    result != true && raise(E_ASSERT, "String all failed, got " + toliteral(result));
  endverb

  verb test_unique (this none this) owner: HACKER flags: "rxd"
    "Test the unique function";
    result = 0;
    result = {1, 2, 2, 3, 1, 4}:unique();
    result != {1, 2, 3, 4} && raise(E_ASSERT, "Basic unique failed, got " + toliteral(result));
    result = {1, 2, 3, 4}:unique();
    result != {1, 2, 3, 4} && raise(E_ASSERT, "No duplicates unique failed, got " + toliteral(result));
    result = {5, 5, 5, 5}:unique();
    result != {5} && raise(E_ASSERT, "All same unique failed, got " + toliteral(result));
    result = {}:unique();
    result != {} && raise(E_ASSERT, "Empty list unique failed, got " + toliteral(result));
    result = {"a", "b", "a", "c", "b"}:unique();
    result != {"a", "b", "c"} && raise(E_ASSERT, "String unique failed, got " + toliteral(result));
    result = {42}:unique();
    result != {42} && raise(E_ASSERT, "Single element unique failed, got " + toliteral(result));
  endverb

  verb test_group_by (this none this) owner: HACKER flags: "rxd"
    "Test the group_by function";
    result = 0;
    result = {"apple", "ant", "bee", "bear"}:group_by({x} => x[1]);
    expected = ["a" -> {"apple", "ant"}, "b" -> {"bee", "bear"}];
    result != expected && raise(E_ASSERT, "Basic group_by failed, got " + toliteral(result));
    result = {"a", "bb", "c", "dd", "eee"}:group_by({y} => length(y));
    expected = [1 -> {"a", "c"}, 2 -> {"bb", "dd"}, 3 -> {"eee"}];
    result != expected && raise(E_ASSERT, "Length group_by failed, got " + toliteral(result));
    result = {}:group_by({z} => z);
    result != [] && raise(E_ASSERT, "Empty list group_by failed, got " + toliteral(result));
    result = {"hello"}:group_by({w} => w[1]);
    expected = ["h" -> {"hello"}];
    result != expected && raise(E_ASSERT, "Single element group_by failed, got " + toliteral(result));
    result = {1, 2, 3, 4, 5, 6}:group_by({v} => v % 2);
    expected = [1 -> {1, 3, 5}, 0 -> {2, 4, 6}];
    result != expected && raise(E_ASSERT, "Numeric group_by failed, got " + toliteral(result));
  endverb

  verb test_compress (this none this) owner: HACKER flags: "rxd"
    "Test the modernized compress function";
    result = 0;
    result = {"a", "b", "b", "c", "b", "b", "b", "d", "d", "e"}:compress();
    result != {"a", "b", "c", "b", "d", "e"} && raise(E_ASSERT, "Basic compress failed, got " + toliteral(result));
    result = {"a", "b", "c", "d"}:compress();
    result != {"a", "b", "c", "d"} && raise(E_ASSERT, "No duplicates compress failed, got " + toliteral(result));
    result = {"x", "x", "x", "x"}:compress();
    result != {"x"} && raise(E_ASSERT, "All same compress failed, got " + toliteral(result));
    result = {}:compress();
    result != {} && raise(E_ASSERT, "Empty list compress failed, got " + toliteral(result));
    result = {"a"}:compress();
    result != {"a"} && raise(E_ASSERT, "Single element compress failed, got " + toliteral(result));
    result = {1, 1, 2, 3, 3, 3, 2, 2}:compress();
    result != {1, 2, 3, 2} && raise(E_ASSERT, "Numeric compress failed, got " + toliteral(result));
  endverb
endobject
