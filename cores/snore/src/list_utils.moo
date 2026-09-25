object LIST_UTILS [
  import_export_id -> "list_utils"
]
  name: "list utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property nonstring_tell_lines (owner: HACKER, flags: "r") = {};

  override aliases (owner: HACKER, flags: "rc") = {"list_utilities"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the list utilities utility package.  See `help $list_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "append            (list,list,..) => result of concatenating the given lists",
    "reverse           (list)         => reversed list",
    "remove_duplicates (list)         => list with all duplicates removed",
    "compress          (list)         => list with consecutive duplicates removed",
    "setremove_all     (list,elt)     => list with all occurrences of elt removed",
    "find_insert       (sortedlist,e) => index of first element > e in sortedlist",
    "sort              (list[,keys])  => sorted list",
    "count             (elt,list)     => count of elt found in list.",
    "flatten           (list)         => flatten all recursive lists into one list",
    "randomly_permute  (list)         => list with elements randomly permuted",
    "longest           (list)         => longest in list (consisting of str or list)",
    "shortest          (list)         => shortest in list (as above)",
    "",
    "make              (n[,e])        => list of n copies of e",
    "range             (m,n)          => {m,m+1,...,n}",
    "",
    "arrayset   (list,val,i[,j,k...]) => array modified so that list[i][j][k]==val",
    "",
    "-- Mapping functions (take a list and do something to each element):",
    "",
    "map_prop ({o...},prop)              => list of o.(prop)            for all o",
    "map_verb ({o...},verb[,args])        => list of o:(verb)(@args)     for all o",
    "map_arg  ([n,]obj,verb,{a...},args) => list of obj:(verb)(a,@args) for all a",
    "map_builtin (objectlist, function)  => applies function to all in objectlist",
    "",
    "-- Closure functions (mooR) --",
    "map(items, callback)        => callback(item) for each item",
    "filter(items, predicate)    => items whose predicate result is true",
    "reduce(items, callback, initial) => left fold with callback(accumulator, item)",
    "find_index(items, predicate) => first matching index, or 0",
    "any(items, predicate) / all(items, predicate) => boolean, with early stopping",
    "sort_by(items, key[, natural[, descending]]) => stable sort by key(item)",
    "",
    "Callbacks run with caller permissions, in input order. These helpers add no suspension.",
    "Callback errors propagate. A callback that suspends commits the current transaction.",
    "Capture target objects explicitly: callback this is the utility object.",
    "Example: $list_utils:map({1, 2, 3}, {x} => x * 2) returns {2, 4, 6}.",
    "For a simple one-off transformation, a list comprehension is often sufficient.",
    "",
    "-- Association list functions --",
    "",
    "An association list (alist) is a list of pairs (2-element lists), though the following functions have been generalized for lists of n-tuples (n-element lists).  In each case i defaults to 1.",
    "",
    "assoc        (targ,alist[,i]) => 1st tuple in alist whose i-th element is targ",
    "iassoc       (targ,alist[,i]) => index of same.",
    "assoc_prefix (targ,alist[,i]) => ... whose i-th element has targ as a prefix",
    "iassoc_prefix(targ,alist[,i]) => index of same.",
    "iassoc_sorted(targ,slist[,i]) => index of last element in sortedlist <= targ",
    "slice             (alist[,i]) => list of i-th elements",
    "sort_alist        (alist[,i]) => alist sorted on i-th elements.",
    "amerge  (alist,[tind,[dind]]) => merges tuples of alist with matching i-th elt",
    "build_alist          (list,N) => make an alist of N-intervals from list",
    "",
    "-- Functions that suspend --",
    "",
    "Budget checks can commit. Native sort checks once before sorting; native reverse does not suspend. See help $list_utils:<verb>.",
    "",
    "sort_suspended          iassoc_suspended          sort_alist_suspended",
    "reverse_suspended       randomly_permute_suspended"
  };
  override object_size (owner: HACKER, flags: "r") = {29031, 1084848672};

  method make owner: HACKER
    "Return n copies of a value, which defaults to 0; return E_INVARG for a negative n.";
    let {count, ?value = 0} = args;
    count < 0 && return E_INVARG;
    let result = {};
    let block = {value};
    while (count)
      count % 2 && (result = {@result, @block});
      count = count / 2;
      count && (block = {@block, @block});
    endwhile
    return result;
  endmethod

  method range owner: HACKER
    "Return the integers from start through end; start defaults to 1.";
    const {?start = 1, finish} = args;
    return { number for number in [start..finish] };
  endmethod

  method "map_prop*erty" owner: #2
    "Return each object's property value in input order, with caller permissions. No added suspension.";
    const {objects, property} = args;
    set_task_perms(caller_perms());
    return { object.(property) for object in (objects) };
  endmethod

  method map_verb owner: #2
    "Call each object's named verb with the remaining arguments; return results in input order.";
    "Use caller permissions. Called verbs can suspend and commit.";
    const {objects, method, @arguments} = args;
    set_task_perms(caller_perms());
    let results = {};
    for object in (objects)
      results = {@results, object:(method)(@arguments)};
    endfor
    return results;
  endmethod

  method "map_arg*s" owner: #2
    "map_args([position,] object, method, @arguments) maps the list at position, which defaults to 1.";
    "Return results in list order with caller permissions. Called verbs can suspend and commit.";
    let position = 1;
    let call = args;
    if (typeof(args[1]) == TYPE_INT)
      position = args[1];
      call = args[2..$];
    endif
    const {object, method, @arguments} = call;
    set_task_perms(caller_perms());
    let results = {};
    for item in (arguments[position])
      results = {@results, object:(method)(@listset(arguments, item, position))};
    endfor
    return results;
  endmethod

  method map_builtin owner: #2
    "Call a named builtin once per item with caller permissions; return E_INVARG for an unknown name.";
    "Return results in input order. A suspending builtin commits the current transaction.";
    const {items, builtin} = args;
    set_task_perms(caller_perms());
    !(`function_info(builtin) ! E_INVARG, E_ARGS => false') && return E_INVARG;
    let results = {};
    for item in (items)
      results = {@results, call_function(builtin, item)};
    endfor
    return results;
  endmethod

  method find_insert owner: HACKER
    "Return the first index whose value exceeds key, or length + 1. Input must be sorted.";
    const {items, key} = args;
    let lower = 1;
    let upper = length(items);
    while (lower <= upper)
      const middle = (lower + upper) / 2;
      if (key < items[middle])
        upper = middle - 1;
      else
        lower = middle + 1;
      endif
    endwhile
    return lower;
  endmethod

  method remove_duplicates owner: HACKER
    "Remove repeated elements, preserving the first occurrence and MOO equality semantics.";
    const {items} = args;
    let result = {};
    for item in (items)
      result = setadd(result, item);
    endfor
    return result;
  endmethod

  method arrayset owner: HACKER
    "Return a copy of a nested list with the value at the given indexes replaced.";
    const {items, value, position, @remaining} = args;
    !remaining && return listset(items, value, position);
    return listset(items, this:arrayset(items[position], value, @remaining), position);
  endmethod

  method setremove_all owner: HACKER
    "Remove every occurrence of a value, preserving the remaining order.";
    const {items, value} = args;
    return { item for item in (items) if item != value };
  endmethod

  method append owner: HACKER
    "Concatenate the argument lists in order.";
    let result = {};
    for items in (args)
      result = {@result, @items};
    endfor
    return result;
  endmethod

  method reverse owner: HACKER
    "Return the list in reverse order using the native builtin.";
    const {items} = args;
    return reverse(items);
  endmethod

  method compress owner: HACKER
    "Collapse consecutive equal elements, preserving each run's first value.";
    const {items} = args;
    !items && return {};
    let previous = items[1];
    let result = {previous};
    for item in (items[2..$])
      if (item != previous)
        result = {@result, item};
        previous = item;
      endif
    endfor
    return result;
  endmethod

  method sort owner: HACKER
    "sort(items[, keys[, natural[, reverse]]]) uses the native stable, case-insensitive sort.";
    "Parallel keys select the order. Natural ordering recognizes numbers within strings.";
    return sort(@args);
  endmethod

  method sort_suspended owner: #2
    "sort_suspended(interval, items[, keys]) checks the budget once, then uses native stable sort.";
    "The budget check can commit. The sort itself adds no suspension. Return E_ARGS for a noninteger interval.";
    const {interval, items, ?keys = {}} = args;
    typeof(interval) != TYPE_INT && return E_ARGS;
    set_task_perms(caller_perms());
    $command_utils:suspend_if_needed(interval);
    return sort(items, keys);
  endmethod

  method slice owner: HACKER
    "Extract a column from each row; the column defaults to 1 or can be a nonempty list of columns.";
    const {rows, ?column = 1} = args;
    if (typeof(column) == TYPE_LIST)
      "Keep the nonempty-column contract even for rows containing empty lists.";
      let result = {};
      for row in (rows)
        let selected = {row[column[1]]};
        for position in (column[2..$])
          selected = {@selected, row[position]};
        endfor
        result = {@result, selected};
      endfor
      return result;
    endif
    return { row[column] for row in (rows) };
  endmethod

  method assoc owner: HACKER
    "Return the first list row whose selected column equals target, or {}. Skip short and non-list rows.";
    const {target, rows, ?column = 1} = args;
    for row in (rows)
      typeof(row) == TYPE_LIST && `row[column] == target ! E_RANGE => false' && return row;
    endfor
    return {};
  endmethod

  method iassoc owner: HACKER
    "Return the first matching row's index, or 0. Skip short and non-list rows; column defaults to 1.";
    const {target, rows, ?column = 1} = args;
    for position in [1..length(rows)]
      const row = rows[position];
      typeof(row) == TYPE_LIST && `row[column] == target ! E_RANGE, E_TYPE => false' && return position;
    endfor
    return 0;
  endmethod

  method iassoc_suspended owner: #2
    "Return the first matching row's index, or 0; skip short and non-list rows.";
    "Optional column and suspension interval default to 1 and 0. Budget checks can commit.";
    const {target, rows, ?column = 1, ?interval = 0} = args;
    set_task_perms(caller_perms());
    for position in [1..length(rows)]
      const row = rows[position];
      typeof(row) == TYPE_LIST && `row[column] == target ! E_RANGE, E_TYPE => false' && return position;
      $command_utils:suspend_if_needed(interval);
    endfor
    return 0;
  endmethod

  method assoc_prefix owner: HACKER
    "Return the first list row with the target prefix in its selected column, or {}.";
    const {target, rows, ?column = 1} = args;
    for row in (rows)
      typeof(row) == TYPE_LIST && length(row) >= column && index(row[column], target) == 1 && return row;
    endfor
    return {};
  endmethod

  method iassoc_prefix owner: HACKER
    "Return the index of the first list row with the target prefix in its selected column, or 0.";
    const {target, rows, ?column = 1} = args;
    for position in [1..length(rows)]
      const row = rows[position];
      typeof(row) == TYPE_LIST && length(row) >= column && index(row[column], target) == 1 && return position;
    endfor
    return 0;
  endmethod

  method iassoc_sorted owner: HACKER
    "Return the last row index whose selected column is at most target, or 0. Rows must be sorted.";
    const {target, rows, ?column = 1} = args;
    let lower = 0;
    let upper = length(rows) + 1;
    while (upper - lower > 1)
      const middle = (lower + upper) / 2;
      if (target < rows[middle][column])
        upper = middle;
      else
        lower = middle;
      endif
    endwhile
    return lower;
  endmethod

  method sort_alist owner: HACKER
    "Stably sort rows by the selected column, which defaults to 1, using native sort.";
    const {rows, ?column = 1} = args;
    return sort(rows, this:slice(rows, column));
  endmethod

  method sort_alist_suspended owner: #2
    "Sort rows by a selected column after one budget check, which can commit. Column defaults to 1.";
    const {interval, rows, ?column = 1} = args;
    set_task_perms(caller_perms());
    $command_utils:suspend_if_needed(interval);
    return this:sort_alist(rows, column);
  endmethod

  method randomly_permute owner: HACKER
    "Return a uniformly random permutation of the input list.";
    const {items} = args;
    let result = {};
    for position in [1..length(items)]
      result = listinsert(result, items[position], random(position));
    endfor
    return result;
  endmethod

  method count owner: #2
    "Count occurrences of a value; return E_INVARG when the second argument is not a list.";
    const {value, items} = args;
    typeof(items) != TYPE_LIST && return E_INVARG;
    let count = 0;
    for item in (items)
      item == value && (count = count + 1);
    endfor
    return count;
  endmethod

  method flatten owner: HACKER
    "Return all non-list values from nested lists in left-to-right order.";
    const {items} = args;
    let result = {};
    for item in (items)
      if (typeof(item) == TYPE_LIST)
        result = {@result, @this:flatten(item)};
      else
        result = {@result, item};
      endif
    endfor
    return result;
  endmethod

  method "longest shortest" owner: HACKER
    "Return the first longest or shortest string/list. Return E_RANGE for no items, E_TYPE for other types.";
    const {items} = args;
    typeof(items) != TYPE_LIST && return E_TYPE;
    !items && return E_RANGE;
    let result = items[1];
    for item in (items)
      !(typeof(item) in {TYPE_LIST, TYPE_STR}) && return E_TYPE;
      const better = verb == "longest" ? length(item) > length(result) | length(item) < length(result);
      better && (result = item);
    endfor
    return result;
  endmethod

  method check_nonstring_tell_lines owner: HACKER
    "Record a wizard caller's stack when output contains a non-string. Other callers cannot update this log.";
    const {lines} = args;
    !caller_perms().wizard && return;
    for line in (lines)
      if (typeof(line) != TYPE_STR)
        this.nonstring_tell_lines = {@this.nonstring_tell_lines, callers()};
        return;
      endif
    endfor
  endmethod

  method reverse_suspended owner: #2
    "Return the reversed list using native reverse. This compatibility entry point does not suspend.";
    const {items} = args;
    return reverse(items);
  endmethod

  method randomly_permute_suspended owner: #2
    "Return a uniformly random permutation. Budget checks between insertions can commit.";
    const {items} = args;
    set_task_perms(caller_perms());
    let result = {};
    for position in [1..length(items)]
      result = listinsert(result, items[position], random(position));
      $command_utils:suspend_if_needed(0);
    endfor
    return result;
  endmethod

  method swap_elements owner: HACKER
    "Swap two list positions; return E_TYPE for wrong types or E_RANGE for an invalid position.";
    let {items, first, second} = args;
    !(typeof(items) == TYPE_LIST && typeof(first) == TYPE_INT && typeof(second) == TYPE_INT) && return E_TYPE;
    const count = length(items);
    !(first > 0 && first <= count && second > 0 && second <= count) && return E_RANGE;
    const previous = items[first];
    items[first] = items[second];
    items[second] = previous;
    return items;
  endmethod

  method "random_item random_element" owner: HACKER
    "Return a random list element, or E_ARGS/E_TYPE/E_RANGE for wrong arity, type, or an empty list.";
    length(args) != 1 && return E_ARGS;
    const {items} = args;
    typeof(items) != TYPE_LIST && return E_TYPE;
    !items && return E_RANGE;
    return items[random($)];
  endmethod

  method assoc_suspended owner: #2
    "Return the first matching list row, or {}; skip short and non-list rows.";
    "Optional column and suspension interval default to 1 and 0. Budget checks can commit.";
    const {target, rows, ?column = 1, ?interval = 0} = args;
    set_task_perms(caller_perms());
    for row in (rows)
      typeof(row) == TYPE_LIST && `row[column] == target ! E_RANGE, E_TYPE => false' && return row;
      $command_utils:suspend_if_needed(interval);
    endfor
    return {};
  endmethod

  method amerge owner: HACKER
    "Merge rows with equal keys. Key and output-key columns default to 1; groups use sorted key order.";
    const {rows, ?key_column = 1, ?output_column = 1} = args;
    !rows && return {};
    const ordered = this:sort_alist(rows, key_column);
    let key = ordered[1][key_column];
    let group = {key};
    let result = {};
    for row in (ordered)
      if (row[key_column] != key)
        result = {@result, this:swap_elements(group, 1, min(output_column, length(group)))};
        key = row[key_column];
        group = {key};
      endif
      group = {@group, @listdelete(row, key_column)};
    endfor
    return {@result, this:swap_elements(group, 1, min(output_column, length(group)))};
  endmethod

  method passoc owner: HACKER
    "Look up a key in parallel key/value lists. A missing key raises E_RANGE.";
    const {key, keys, values} = args;
    return values[key in keys];
  endmethod

  method setmove owner: HACKER
    "Move a list element from one position to another, preserving the order of other elements.";
    const {items, source, destination} = args;
    return listinsert(listdelete(items, source), items[source], destination);
  endmethod

  method iassoc_new owner: HACKER
    "Return the first matching row index, or 0. Return an indexing error value for malformed rows.";
    const {target, rows, ?column = 1} = args;
    try
      for position in [1..length(rows)]
        const row = rows[position];
        row[column] == target && typeof(row) == TYPE_LIST && return position;
      endfor
    except error (E_RANGE, E_TYPE, E_INVARG)
      return error[1];
    endtry
    return 0;
  endmethod

  method build_alist owner: HACKER
    "Split a list into equal-sized rows. Return E_INVARG for a nonpositive size, E_RANGE for a remainder.";
    const {items, width} = args;
    width <= 0 && return E_INVARG;
    length(items) % width && return E_RANGE;
    let result = {};
    for row in [1..length(items) / width]
      result = {@result, items[(row - 1) * width + 1..row * width]};
    endfor
    return result;
  endmethod

  method flatten_suspended owner: HACKER
    "Flatten nested lists in left-to-right order. Budget checks between elements can commit.";
    const {items} = args;
    let result = {};
    for item in (items)
      $command_utils:suspend_if_needed(0);
      if (typeof(item) == TYPE_LIST)
        result = {@result, @this:flatten_suspended(item)};
      else
        result = {@result, item};
      endif
    endfor
    return result;
  endmethod

  method map owner: #2
    "Return callback(item) for each item, in input order.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    let result = {};
    for item in (items)
      result = {@result, callback(item)};
    endfor
    return result;
  endmethod

  method filter owner: #2
    "Return items whose callback result is true, preserving order and duplicates.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    let result = {};
    for item in (items)
      callback(item) && (result = {@result, item});
    endfor
    return result;
  endmethod

  method reduce owner: #2
    "Fold left with callback(accumulator, item); return initial for an empty list.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback, initial} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    let result = initial;
    for item in (items)
      result = callback(result, item);
    endfor
    return result;
  endmethod

  method find_index owner: #2
    "Return the first index with a true callback result, or 0. Stop after the first match.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    for position in [1..length(items)]
      callback(items[position]) && return position;
    endfor
    return 0;
  endmethod

  method any owner: #2
    "Return whether any callback result is true; stop on the first match. Empty input returns false.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    for item in (items)
      callback(item) && return true;
    endfor
    return false;
  endmethod

  method all owner: #2
    "Return whether all callback results are true; stop on the first failure. Empty input returns true.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    for item in (items)
      !(callback(item)) && return false;
    endfor
    return true;
  endmethod

  method sort_by owner: #2
    "Stably sort by callback(item), evaluated once per item in input order, using native key ordering.";
    "Use caller permissions. Add no suspension; callback errors propagate and callback suspensions commit.";
    const {items, callback, ?natural = false, ?descending = false} = args;
    typeof(items) == TYPE_LIST && typeof(callback) == TYPE_LAMBDA || raise(E_TYPE);
    set_task_perms(caller_perms());
    let keys = {};
    for item in (items)
      keys = {@keys, callback(item)};
    endfor
    return sort(items, keys, natural, descending);
  endmethod
endobject
