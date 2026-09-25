object SEQ_UTILS [
  import_export_id -> "seq_utils"
]
  name: "sequence utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  override aliases (owner: HACKER, flags: "rc") = {"sequence utilities", "seq_utils", "squ"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the sequence utilities utility package.  See `help $seq_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "A sequence is a set of integers (*)",
    "This package supplies the following verbs:",
    "",
    "  :add      (seq,f,t)  => seq with [f..t] interval added",
    "  :remove   (seq,f,t)  => seq with [f..t] interval removed",
    "  :range    (f,t)      => sequence corresponding to [f..t]",
    "  {}                   => empty sequence",
    "  :contains (seq,n)    => n in seq",
    "  :size     (seq)      => number of elements in seq",
    "  :first    (seq)      => first integer in seq or E_NONE",
    "  :firstn   (seq,n)    => first n integers in seq (as a sequence)",
    "  :last     (seq)      => last integer in seq  or E_NONE",
    "  :lastn    (seq,n)    => last n integers in seq (as a sequence)",
    "",
    "  :complement   (seq)         => sequence consisting of integers not in seq",
    "  :union        (seq,seq,...) => union of all sequences",
    "  :intersection (seq,seq,...) => intersection of all sequences",
    "  :contract (seq,cseq)              (see `help $seq_utils:contract')",
    "  :expand   (seq,eseq[,include])    (see `help $seq_utils:expand')",
    "  ",
    "  :extract(seq,array)           => array[@seq]",
    "  :for([n,]seq,obj,verb,@args)  => for s in (seq) obj:verb(s,@args); endfor",
    "",
    "  :tolist(seq)            => list corresponding to seq",
    "  :tostr(seq)             => contents of seq as a string",
    "  :from_list(list)        => sequence corresponding to list",
    "  :from_sorted_list(list) => sequence corresponding to list (assumed sorted)",
    "  :from_string(string)    => sequence corresponding to string",
    "",
    "For boolean expressions, note that",
    "  the representation of the empty sequence is {} (boolean FALSE) and",
    "  all non-empty sequences are represented as nonempty lists (boolean TRUE).",
    "",
    "The representation used works better than the usual list implementation for sets consisting of long uninterrupted ranges of integers.  ",
    "For sparse sets of integers the representation is decidedly non-optimal (though it never takes more than double the space of the usual list representation).",
    "",
    "(*) Endpoints use the core limits $minint and $maxint. $minint marks an open lower bound; an open upper bound ends at $maxint. Counts use mooR integers and do not wrap at 32 bits.",
    ""
  };
  override object_size (owner: HACKER, flags: "r") = {17130, 1084848672};

  method "add remove" owner: HACKER
    "Add or remove an inclusive range. With no end, change membership through the upper limit.";
    "The endpoint representation uses integer parity, not boolean arithmetic.";
    const {sequence, start, ?finish = $nothing} = args;
    const removing = verb == "remove" ? 1 | 0;
    const first = start == $minint ? 1 | $list_utils:find_insert(sequence, start - 1);
    const prefix = {@sequence[1..first - 1], @(first + removing) % 2 ? {start} | {}};
    finish == $nothing && return prefix;
    const after = finish + 1;
    const last = $list_utils:find_insert(sequence, after);
    return {@prefix, @(last + removing) % 2 ? {after} | {}, @sequence[last..$]};
  endmethod

  method contains owner: HACKER
    "Return whether the integer is a member of the endpoint sequence.";
    const {sequence, item} = args;
    return $list_utils:find_insert(sequence, item) % 2 == 0;
  endmethod

  method complement owner: HACKER
    "Complement a sequence, optionally within inclusive lower/upper bounds. Input must fit those bounds.";
    let {sequence, ?lower = $minint, ?upper = $nothing} = args;
    if (upper != $nothing)
      const after = upper + 1;
      if (sequence && sequence[$] >= after)
        sequence[$..$] = {};
      else
        sequence = {@sequence, after};
      endif
    endif
    sequence && sequence[1] <= lower && return sequence[2..$];
    return {lower, @sequence};
  endmethod

  method union owner: HACKER
    "Return the union of the endpoint sequences; no arguments returns an empty sequence.";
    const sequences = { sequence for sequence in (args) if sequence };
    !sequences && return {};
    length(sequences) == 1 && return sequences[1];
    return this:_union(@sequences);
  endmethod

  method tostr owner: HACKER
    "Format a sequence as comma-separated integers and ranges; the range separator defaults to '..'.";
    const {sequence, ?separator = ".."} = args;
    !sequence && return "empty";
    let result = tostr(sequence[1] == $minint ? "" | sequence[1]);
    for position in [2..length(sequence)]
      if (position % 2)
        result = tostr(result, ", ", sequence[position]);
      elseif (sequence[position] != sequence[position - 1] + 1)
        result = tostr(result, separator, sequence[position] - 1);
      endif
    endfor
    return length(sequence) % 2 ? result + separator | result;
  endmethod

  method for owner: #2
    "for([position,] sequence, object, method, @arguments) calls the method for each member in order.";
    "Insert each member at position (default 1). Stop on a returned error; a lower-unbounded input returns E_RANGE.";
    "Use caller permissions. Called methods can suspend and commit. An upper-unbounded tail needs a stop result.";
    let position = 1;
    let call = args;
    if (typeof(call[1]) == TYPE_INT)
      position = call[1];
      call = call[2..$];
    endif
    const {sequence, object, method, @arguments} = call;
    set_task_perms(caller_perms());
    !sequence && return;
    sequence[1] == $minint && return E_RANGE;
    for range_index in [1..length(sequence) / 2]
      for item in [sequence[2 * range_index - 1]..sequence[2 * range_index] - 1]
        const result = object:(method)(@listinsert(arguments, item, position));
        typeof(result) == TYPE_ERR && return;
      endfor
    endfor
    if (length(sequence) % 2)
      let item = sequence[$];
      while (true)
        const result = object:(method)(@listinsert(arguments, item, position));
        typeof(result) == TYPE_ERR && return;
        item = item + 1;
      endwhile
    endif
  endmethod

  method extract owner: HACKER
    "Return array elements whose indexes belong to the sequence. Budget checks between ranges can commit.";
    let {sequence, array} = args;
    const count = length(array);
    !count && return {};
    const first = $list_utils:find_insert(sequence, 1);
    const last = $list_utils:find_insert(sequence, count);
    sequence = {@first % 2 ? {} | {1}, @sequence[first..last - 1], @last % 2 ? {} | {count + 1}};
    let result = {};
    for range_index in [1..length(sequence) / 2]
      $command_utils:suspend_if_needed(0);
      result = {@result, @array[sequence[2 * range_index - 1]..sequence[2 * range_index] - 1]};
    endfor
    return result;
  endmethod

  method tolist owner: HACKER
    "Expand an endpoint sequence into an integer list. An open upper endpoint ends at $maxint.";
    "Large ranges can exhaust the task budget; bound the sequence before materializing it.";
    let {sequence} = args;
    length(sequence) % 2 && (sequence = {@sequence, $maxint + 1});
    let result = {};
    for range_index in [1..length(sequence) / 2]
      for item in [sequence[2 * range_index - 1]..sequence[2 * range_index] - 1]
        result = {@result, item};
      endfor
    endfor
    return result;
  endmethod

  method from_list owner: HACKER
    "Return the endpoint sequence for an integer list; discard duplicates and sort the members.";
    const {items} = args;
    return this:from_sorted_list(sort(items));
  endmethod

  method from_sorted_list owner: HACKER
    "Return the endpoint sequence for sorted integers; repeated integers contribute only once.";
    const {items} = args;
    !items && return {};
    let previous = items[1];
    let sequence = {previous};
    for item in (items[2..$])
      if (item == previous)
        continue;
      endif
      item != previous + 1 && (sequence = {@sequence, previous + 1, item});
      previous = item;
    endfor
    return previous == $maxint ? sequence | {@sequence, previous + 1};
  endmethod

  method first owner: HACKER
    "Return the first sequence endpoint, or E_NONE for an empty sequence.";
    const {sequence} = args;
    return sequence ? sequence[1] | E_NONE;
  endmethod

  method last owner: HACKER
    "Return the last member, or E_NONE for an empty sequence. An open upper endpoint means $maxint.";
    const {sequence} = args;
    !sequence && return E_NONE;
    return length(sequence) % 2 ? $maxint | sequence[$] - 1;
  endmethod

  method size owner: HACKER
    "Count sequence members using mooR integers. An open upper endpoint ends at $maxint.";
    "The count does not wrap at the core's 32-bit sequence limits.";
    const {sequence} = args;
    let count = 0;
    for endpoint in (sequence)
      count = endpoint - count;
    endfor
    return length(sequence) % 2 ? $maxint + 1 - count | count;
  endmethod

  method from_string owner: HACKER
    "Parse comma-separated integers and inclusive a..b ranges; return E_INVARG for invalid text.";
    "Missing endpoints denote the sequence limits. Reversed finite ranges contribute no members.";
    const {text} = args;
    const words = $string_utils:explode($string_utils:strip_chars(text, " "), ",");
    let sequences = {};
    for word in (words)
      const separator = index(word, "..");
      if (!separator)
        !$string_utils:is_numeric(word) && return E_INVARG;
        const number = toint(word);
        sequences = {@sequences, this:range(number, number)};
        continue;
      endif
      const first_text = word[1..separator - 1];
      const last_text = word[separator + 2..$];
      first_text && !$string_utils:is_numeric(first_text) && return E_INVARG;
      last_text && !$string_utils:is_numeric(last_text) && return E_INVARG;
      const first = first_text ? toint(first_text) | $minint;
      if (!last_text)
        sequences = {@sequences, {first}};
      else
        sequences = {@sequences, this:range(first, toint(last_text))};
      endif
    endfor
    return this:union(@sequences);
  endmethod

  method firstn owner: HACKER
    "Return a sequence containing at most the first count members. A nonpositive count returns {}.";
    const {sequence, count} = args;
    count <= 0 && return {};
    let remaining = count;
    const count_endpoints = length(sequence);
    let position = 1;
    while (position <= count_endpoints)
      const after = remaining + sequence[position];
      if (position == count_endpoints)
        return after > $maxint ? sequence | {@sequence[1..position], after};
      endif
      after <= sequence[position + 1] && return {@sequence[1..position], after};
      remaining = after - sequence[position + 1];
      position = position + 2;
    endwhile
    return sequence;
  endmethod

  method lastn owner: HACKER
    "Return a sequence containing at most the last count members. A nonpositive count returns {}.";
    let {sequence, count} = args;
    count <= 0 && return {};
    const open_upper = length(sequence) % 2 != 0;
    open_upper && (sequence = {@sequence, $maxint + 1});
    let position = length(sequence);
    while (position)
      const first = sequence[position] - count;
      if (first >= sequence[position - 1])
        const suffix = open_upper ? sequence[position..$ - 1] | sequence[position..$];
        return {first, @suffix};
      endif
      count = sequence[position - 1] - first;
      position = position - 2;
    endwhile
    return open_upper ? sequence[1..$ - 1] | sequence;
  endmethod

  method range owner: HACKER
    "Return the endpoint sequence for an inclusive range, or {} when start exceeds finish.";
    const {start, finish} = args;
    start > finish && return {};
    return finish == $maxint ? {start} | {start, finish + 1};
  endmethod

  method expand owner: HACKER
    "Shift members to make room for finite insertion ranges. Optionally include the inserted members.";
    "Return E_TYPE for open-ended insertion ranges. Endpoint parity stays integer-valued.";
    const {old, insert, ?include = false} = args;
    const exclude = include ? 0 | 1;
    !insert && return old;
    length(insert) % 2 || insert[1] == $minint && return E_TYPE;
    const old_count = length(old);
    const insert_count = length(insert);
    let insert_index = 1;
    let first_inserted = insert[insert_index];
    let old_index = $list_utils:find_insert(old, first_inserted - 1);
    old_index > old_count && return old_count % 2 == exclude ? {@old, @insert} | old;
    let result = old[1..old_index - 1];
    let endpoint = old[old_index];
    let offset = 0;
    while (true)
      "The pending old endpoint is at least the current insertion start.";
      if (endpoint == first_inserted)
        const boundary = old_index % 2 == exclude ? 1 | 0;
        result = {@result, insert[insert_index + boundary]};
        old_index >= old_count && return old_count % 2 == exclude ? {@result, @insert[insert_index + 2..insert_count]} | result;
        old_index = old_index + 1;
      elseif (old_index % 2 != exclude)
        result = {@result, @insert[insert_index..insert_index + 1]};
      endif
      offset = offset + insert[insert_index + 1] - first_inserted;
      insert_index = insert_index + 2;
      if (insert_index > insert_count)
        return {@result, @{ tail + offset for tail in (old[old_index..old_count]) }};
      endif
      first_inserted = insert[insert_index];
      while (true)
        endpoint = old[old_index] + offset;
        if (endpoint >= first_inserted)
          break;
        endif
        result = {@result, endpoint};
        old_index >= old_count && return old_count % 2 == exclude ? {@result, @insert[insert_index..insert_count]} | result;
        old_index = old_index + 1;
      endwhile
    endwhile
  endmethod

  method contract owner: HACKER
    "Remove members in finite removal ranges and shift later members left by each removed range's size.";
    "Return E_TYPE for open-ended removal ranges. This reverses expand for finite inserted ranges.";
    const {old, removed} = args;
    !removed && return old;
    const removed_count = length(removed);
    removed_count % 2 || removed[1] == $minint && return E_TYPE;
    let first_removed = removed[1];
    let first_old = $list_utils:find_insert(old, first_removed - 1);
    let result = old[1..first_old - 1];
    let offset = 0;
    let removed_index = 2;
    let after_removed = removed[removed_index];
    const old_count = length(old);
    for old_index in [first_old..old_count]
      while (old[old_index] > after_removed)
        if ((old_index - first_old) % 2)
          result = {@result, first_removed - offset};
          first_old = old_index;
        endif
        offset = offset + after_removed - first_removed;
        if (removed_index >= removed_count)
          return {@result, @{ tail - offset for tail in (old[old_index..old_count]) }};
        endif
        first_removed = removed[removed_index + 1];
        removed_index = removed_index + 2;
        after_removed = removed[removed_index];
      endwhile
      if (old[old_index] < first_removed)
        result = {@result, old[old_index] - offset};
        first_old = old_index + 1;
      endif
    endfor
    return (old_count - first_old) % 2 ? result | {@result, first_removed - offset};
  endmethod

  method _union owner: HACKER
    "Merge nonempty endpoint sequences with a min-heap of their next interval starts.";
    "The heap holds at most one entry per input; intervals do not expand into individual integers.";
    const sequences = args;
    let heap = {};
    let positions = {};
    for sequence_index in [1..length(sequences)]
      positions = {@positions, 1};
      let slot = length(heap) + 1;
      heap = {@heap, sequence_index};
      while (slot > 1)
        const parent_slot = slot / 2;
        if (sequences[heap[parent_slot]][1] <= sequences[sequence_index][1])
          break;
        endif
        heap[slot] = heap[parent_slot];
        slot = parent_slot;
      endwhile
      heap[slot] = sequence_index;
    endfor
    let result = {};
    let have_interval = false;
    let current_start = 0;
    let current_end = 0;
    while (heap)
      const sequence_index = heap[1];
      const sequence = sequences[sequence_index];
      const position = positions[sequence_index];
      const start = sequence[position];
      const open_upper = position == length(sequence);
      const finish = open_upper ? $maxint + 1 | sequence[position + 1];
      if (!have_interval)
        current_start = start;
        current_end = finish;
        have_interval = true;
      elseif (start > current_end)
        result = {@result, current_start, current_end};
        current_start = start;
        current_end = finish;
      else
        current_end = max(current_end, finish);
      endif
      open_upper && return {@result, current_start};
      positions[sequence_index] = position + 2;
      if (position + 2 > length(sequence))
        heap[1] = heap[$];
        heap = heap[1..$ - 1];
      endif
      if (!heap)
        break;
      endif
      "Only the root key changed; restore heap order before reading the next interval.";
      const next_sequence = heap[1];
      const next_start = sequences[next_sequence][positions[next_sequence]];
      let slot = 1;
      while (slot * 2 <= length(heap))
        let child = slot * 2;
        if (child < length(heap))
          const left = heap[child];
          const right = heap[child + 1];
          if (sequences[right][positions[right]] < sequences[left][positions[left]])
            child = child + 1;
          endif
        endif
        const child_sequence = heap[child];
        if (next_start <= sequences[child_sequence][positions[child_sequence]])
          break;
        endif
        heap[slot] = child_sequence;
        slot = child;
      endwhile
      heap[slot] = next_sequence;
    endwhile
    return have_interval ? {@result, current_start, current_end} | {};
  endmethod

  method intersection owner: HACKER
    "Return the intersection of endpoint sequences. No arguments returns the whole sequence domain.";
    const universe = {$minint};
    const sequences = { sequence for sequence in (args) if sequence != universe };
    !sequences && return universe;
    length(sequences) == 1 && return sequences[1];
    const complements = { this:complement(selected) for selected in (sequences) };
    return this:complement(this:union(@complements));
  endmethod
endobject
