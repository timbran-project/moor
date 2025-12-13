object PROG_UTILS
  name: "Programmer Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  override description = "Core programmer utilities for verb and object manipulation. Provides common functionality used by both programmer features and development tools - verb/property management, code search, object inspection, etc.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "prog_utils";

  verb grep_verb_code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Search within a single verb's code for a pattern.";
    "Returns {line_number, truncated_line} if found, or 0 if no match.";
    "Args: {pattern, object, verb_num, casematters}";
    set_task_perms(caller_perms());
    {pattern, object, vnum, casematters} = args;
    "Try to get verb code - may fail due to permissions or non-existent verb";
    vc = `verb_code(object, vnum) ! ANY => false';
    if (typeof(vc) == ERR || !vc)
      return 0;
    endif
    "Quick check: does pattern exist anywhere in the verb code?";
    "This optimization from LambdaCore is much faster than checking line by line";
    suspend_if_needed();
    if (!index(tostr(@vc), pattern, casematters))
      return 0;
    endif
    suspend_if_needed();
    "Pattern exists somewhere, find which line";
    line_count = 0;
    for line in (vc)
      line_count = line_count + 1;
      if (line_count % 10 == 0)
        suspend_if_needed();
      endif
      if (match_pos = index(line, pattern, casematters))
        "Found the pattern - truncate and center around it";
        max_len = 50;
        line_len = length(line);
        if (line_len <= max_len)
          return {line_count, line};
        endif
        "Calculate window centered on the match";
        pattern_len = length(pattern);
        "Try to center the pattern in the window";
        start_pos = max(1, match_pos - (max_len - pattern_len) / 2);
        end_pos = min(line_len, start_pos + max_len - 1);
        "Adjust start if end hit the limit";
        if (end_pos == line_len && end_pos - start_pos < max_len - 1)
          start_pos = max(1, end_pos - max_len + 1);
        endif
        truncated = line[start_pos..end_pos];
        "Add ellipsis indicators";
        if (start_pos > 1)
          truncated = "..." + truncated;
        endif
        if (end_pos < line_len)
          truncated = truncated + "...";
        endif
        return {line_count, truncated};
      endif
    endfor
    return 0;
  endverb

  verb is_valid_prep (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Check if a string is a valid preposition spec";
    "Returns true if prep is 'none', 'any', or a valid preposition form";
    "Args: {prep_string}";
    set_task_perms(caller_perms());
    {prep_str} = args;
    typeof(prep_str) == STR || return false;
    "Check for special cases";
    if (prep_str == "none" || prep_str == "any")
      return true;
    endif
    "Check against actual prepositions from the runtime";
    preps = prepositions();
    for prep_entry in (preps)
      {prep_id, short_form, all_forms} = prep_entry;
      "Check short form match";
      if (prep_str == short_form)
        return true;
      endif
      "Check against all forms";
      for form in (all_forms)
        if (prep_str == form)
          return true;
        endif
      endfor
    endfor
    return false;
  endverb

  verb grep_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Search all verbs on an object for a pattern.";
    "Returns list of matches: {{obj, verb_name, line_num, matching_line}, ...}";
    "Args: {pattern, search_obj, casematters}";
    set_task_perms(caller_perms());
    {pattern, search_obj, casematters} = args;
    if (!valid(search_obj))
      return {};
    endif
    matches = {};
    verb_count = 0;
    "Get metadata for all verbs on this object";
    verbs_metadata = this:get_verbs_metadata(search_obj);
    "Search each verb using its metadata";
    for metadata in (verbs_metadata)
      verb_count = verb_count + 1;
      if (verb_count % 5 == 0)
        suspend_if_needed();
      endif
      verb_name = metadata:name();
      verb_index = metadata:index();
      match_result = this:grep_verb_code(pattern, search_obj, verb_index, casematters);
      if (typeof(match_result) == LIST)
        "Found a match - return just the essential data";
        {line_num, matching_line} = match_result;
        matches = {@matches, {search_obj, verb_name, line_num, matching_line}};
      endif
    endfor
    return matches;
  endverb

  verb format_line_numbers (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Format code lines with aligned line numbers.";
    "Returns list of strings with padded line numbers prepended.";
    "Args: {code_lines}";
    set_task_perms(caller_perms());
    {code_lines} = args;
    if (typeof(code_lines) != LIST || length(code_lines) == 0)
      return {};
    endif
    num_lines = length(code_lines);
    num_width = length(tostr(num_lines));
    numbered_lines = {};
    for i in [1..num_lines]
      line_num_str = tostr(i);
      padding = $str_proto:space(num_width - length(line_num_str), " ");
      numbered_lines = {@numbered_lines, padding + line_num_str + ":  " + code_lines[i]};
    endfor
    return numbered_lines;
  endverb

  verb get_verb_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get metadata for a verb as a flyweight with $verb delegate.";
    "Slots: owner_obj, location, name, verb_owner, flags, dobj, prep, iobj, index";
    "Args: {object, verb_name}";
    set_task_perms(caller_perms());
    {verb_obj, verb_name} = args;
    verb_info_data = verb_info(verb_obj, verb_name);
    {verb_owner, verb_flags, verb_names} = verb_info_data;
    verb_args_data = verb_args(verb_obj, verb_name);
    {dobj, prep, iobj} = verb_args_data;
    "Find the index of this verb in the object's verb list";
    verb_list = verbs(verb_obj);
    verb_index = verb_name in verb_list;
    "Return as flyweight with $verb delegate and slots for metadata";
    return < $verb, .owner_obj = verb_obj, .location = verb_obj, .name = verb_name, .verb_owner = verb_owner, .flags = verb_flags, .dobj = dobj, .prep = prep, .iobj = iobj, .index = verb_index >;
  endverb

  verb get_verbs_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get metadata for all verbs on an object as a list of flyweights.";
    "Returns list of $verb flyweights, one for each verb";
    "Args: {object}";
    set_task_perms(caller_perms());
    {verb_obj} = args;
    verb_list = verbs(verb_obj);
    metadata_list = {};
    for verb_index in [1..length(verb_list)]
      verb_name = verb_list[verb_index];
      verb_info_data = verb_info(verb_obj, verb_name);
      {verb_owner, verb_flags, verb_names} = verb_info_data;
      verb_args_data = verb_args(verb_obj, verb_name);
      {dobj, prep, iobj} = verb_args_data;
      metadata = < $verb, .owner_obj = verb_obj, .location = verb_obj, .name = verb_name, .verb_owner = verb_owner, .flags = verb_flags, .dobj = dobj, .prep = prep, .iobj = iobj, .index = verb_index >;
      metadata_list = {@metadata_list, metadata};
    endfor
    return metadata_list;
  endverb

  verb get_property_metadata (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get metadata for a property as a flyweight with $property delegate.";
    "Slots: owner_obj, location, name, owner, perms, is_clear";
    "Args: {object, property_name}";
    set_task_perms(caller_perms());
    {prop_obj, prop_name} = args;
    prop_info_data = property_info(prop_obj, prop_name);
    {prop_owner, prop_perms} = prop_info_data;
    is_clear = is_clear_property(prop_obj, prop_name);
    "Return as flyweight with $property delegate and slots for metadata";
    return < $property, .owner_obj = prop_obj, .location = prop_obj, .name = prop_name, .owner = prop_owner, .perms = prop_perms, .is_clear = is_clear >;
  endverb

  verb test_format_line_numbers (this none this) owner: HACKER flags: "rxd"
    "Test line number formatting";
    lines = {"line one", "line two", "line three"};
    numbered = this:format_line_numbers(lines);
    "Should return a list";
    if (typeof(numbered) != LIST)
      return E_ASSERT;
    endif
    "Should have same length";
    if (length(numbered) != length(lines))
      return E_ASSERT;
    endif
    "First line should start with '1: '";
    first = numbered[1];
    if (typeof(first) != STR || !index(first, "1:"))
      return E_ASSERT;
    endif
    "Last line should contain '3: '";
    last = numbered[3];
    if (typeof(last) != STR || !index(last, "3:"))
      return E_ASSERT;
    endif
    return true;
  endverb

  verb test_is_valid_prep (this none this) owner: HACKER flags: "rxd"
    "Test preposition validation";
    "Should accept 'none'";
    if (!this:is_valid_prep("none"))
      return E_ASSERT;
    endif
    "Should accept 'any'";
    if (!this:is_valid_prep("any"))
      return E_ASSERT;
    endif
    "Should accept 'with'";
    if (!this:is_valid_prep("with"))
      return E_ASSERT;
    endif
    "Should reject invalid prep";
    if (this:is_valid_prep("notaprep"))
      return E_ASSERT;
    endif
    return true;
  endverb

  verb parse_target_spec (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Parse a target specification (object, object.property, object:verb, object,inherited_prop, object;inherited_verb)";
    "Returns a map with keys: type, object_str, item_name, separator";
    "type is one of: 'object, 'property, 'verb, 'inherited_property, 'inherited_verb";
    "Returns 0 if invalid (multiple separators or malformed)";
    spec = args[1];
    spec = spec:trim();

    "Count number of separators to reject ambiguous specs";
    sep_count = 0;
    if ("." in spec) sep_count = sep_count + 1; endif
    if (":" in spec) sep_count = sep_count + 1; endif
    if ("," in spec) sep_count = sep_count + 1; endif
    if (";" in spec) sep_count = sep_count + 1; endif

    "If no separators, it's just an object reference";
    if (sep_count == 0)
      if (spec)
        return ['type -> 'object, 'object_str -> spec, 'item_name -> "", 'separator -> ""];
      endif
      return 0;
    endif

    "If multiple separators, it's invalid";
    if (sep_count > 1)
      return 0;
    endif

    "Exactly one separator - determine which type";
    if ("." in spec)
      parts = spec:split(".");
      if (length(parts) == 2 && parts[1] && parts[2])
        return ['type -> 'property, 'object_str -> parts[1]:trim(), 'item_name -> parts[2]:trim(), 'separator -> "."];
      endif
      return 0;
    elseif (":" in spec)
      parts = spec:split(":");
      if (length(parts) == 2 && parts[1] && parts[2])
        return ['type -> 'verb, 'object_str -> parts[1]:trim(), 'item_name -> parts[2]:trim(), 'separator -> ":"];
      endif
      return 0;
    elseif ("," in spec)
      parts = spec:split(",");
      if (length(parts) == 2 && parts[1] && parts[2])
        return ['type -> 'inherited_property, 'object_str -> parts[1]:trim(), 'item_name -> parts[2]:trim(), 'separator -> ","];
      endif
      return 0;
    elseif (";" in spec)
      parts = spec:split(";");
      if (length(parts) == 2 && parts[1] && parts[2])
        return ['type -> 'inherited_verb, 'object_str -> parts[1]:trim(), 'item_name -> parts[2]:trim(), 'separator -> ";"];
      endif
      return 0;
    endif

    "Should not reach here";
    return 0;
  endverb

  verb test_parse_target_spec (this none this) owner: HACKER flags: "rxd"
    "Test target spec parsing";

    "Test object reference";
    result = this:parse_target_spec("me");
    result['type] == 'object || raise(E_ASSERT, "me should parse as object");
    result['object_str] == "me" || raise(E_ASSERT, "object_str should be 'me'");

    "Test property reference";
    result = this:parse_target_spec("me.description");
    result['type] == 'property || raise(E_ASSERT, "me.description should parse as property");
    result['object_str] == "me" || raise(E_ASSERT, "object_str should be 'me'");
    result['item_name] == "description" || raise(E_ASSERT, "item_name should be 'description'");

    "Test verb reference";
    result = this:parse_target_spec("me:test");
    result['type] == 'verb || raise(E_ASSERT, "me:test should parse as verb");
    result['object_str] == "me" || raise(E_ASSERT, "object_str should be 'me'");
    result['item_name] == "test" || raise(E_ASSERT, "item_name should be 'test'");

    "Test inherited property reference";
    result = this:parse_target_spec("me,description");
    result['type] == 'inherited_property || raise(E_ASSERT, "me,description should parse as inherited_property");
    result['separator] == "," || raise(E_ASSERT, "separator should be ','");

    "Test inherited verb reference";
    result = this:parse_target_spec("me;test");
    result['type] == 'inherited_verb || raise(E_ASSERT, "me;test should parse as inherited_verb");
    result['separator] == ";" || raise(E_ASSERT, "separator should be ';'");

    "Test invalid reference (multiple separators)";
    result = this:parse_target_spec("me.desc:verb");
    result == 0 || raise(E_ASSERT, "multiple separators should return 0");

    "Test invalid reference (only separator, no item)";
    result = this:parse_target_spec("me.");
    result == 0 || raise(E_ASSERT, "missing item name should return 0");

    return true;
  endverb

  verb eval_literal (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Safely evaluate a MOO literal from a string, returning value and remaining text";
    "Returns {true, value, remaining_text} on success";
    "Returns {false, error_message, ''} on failure";
    "Accepts: numbers, strings, objects, lists, maps, symbols, errors";
    "If value starts with '(', parses until matching ')'; otherwise takes first whitespace token";
    "IMPORTANT: Runs with caller's permissions, not elevated";
    input_str = args[1]:trim();
    original_len = length(input_str);

    if (!input_str)
      return {false, "Empty input", ""};
    endif

    "Set permissions to caller to prevent privilege escalation";
    set_task_perms(caller_perms());

    "Determine where the literal ends";
    lit_end = 0;
    if (input_str[1] == "(")
      "Find matching closing paren";
      paren_depth = 0;
      for i in [1..original_len]
        char = input_str[i];
        if (char == "(")
          paren_depth = paren_depth + 1;
        elseif (char == ")")
          paren_depth = paren_depth - 1;
          if (paren_depth == 0)
            lit_end = i;
            break;
          endif
        endif
      endfor
      if (lit_end == 0)
        return {false, "Mismatched parentheses", ""};
      endif
    else
      "Find first whitespace for simple tokens";
      lit_end = index(input_str + " ", " ") - 1;
    endif

    "Extract the literal part";
    literal_part = input_str[1..lit_end];
    remaining = lit_end < original_len ? input_str[lit_end + 1..original_len]:trim() | "";

    "Try to evaluate the literal";
    eval_result = eval("return " + literal_part + ";", ['me -> player, 'here, player.location], 1, 2);
    if (!eval_result[1])
      return {false, tostr(eval_result[2]), ""};
    endif

    return {true, eval_result[2], remaining};
  endverb

  verb test_eval_literal (this none this) owner: HACKER flags: "rxd"
    "Test literal evaluation";

    "Test simple integer literal";
    result = this:eval_literal("42");
    result[1] && result[2] == 42 || raise(E_ASSERT, "42 should parse as integer 42");

    "Test integer with remaining text";
    result = this:eval_literal("42 rc");
    result[1] && result[2] == 42 && result[3] == "rc" || raise(E_ASSERT, "42 rc should parse 42 with remainder rc");

    "Test parenthesized expression";
    result = this:eval_literal("(123 / 2)");
    result[1] && result[2] == 61 || raise(E_ASSERT, "(123 / 2) should evaluate to 61");

    "Test parenthesized expression with remaining text";
    result = this:eval_literal("(123 / 2) rc");
    result[1] && result[2] == 61 && result[3] == "rc" || raise(E_ASSERT, "(123 / 2) rc should parse expr with remainder rc");

    "Test symbol";
    result = this:eval_literal("'atom");
    result[1] && result[2] == 'atom || raise(E_ASSERT, "'atom should parse as symbol");

    "Test object reference";
    result = this:eval_literal("$root");
    result[1] && result[2] == $root || raise(E_ASSERT, "$root should parse as object");

    return true;
  endverb

endobject
