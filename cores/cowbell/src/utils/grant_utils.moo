object GRANT_UTILS
  name: "Grant Utilities"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Utilities for formatting and parsing capability grant specifications.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "grant_utils";

  verb format_grant (this none this) owner: HACKER flags: "rxd"
    "Format a grant specification as target.category(cap1,cap2,...).";
    {target, category, cap_list} = args;
    typeof(target) == OBJ || raise(E_TYPE);
    typeof(category) == SYM || raise(E_TYPE);
    typeof(cap_list) == LIST || raise(E_TYPE);
    target_str = tostr(target);
    category_str = tostr(category);
    cap_names = { tostr(c) for c in (cap_list) };
    caps_str = cap_names:join(",");
    return target_str + "." + category_str + "(" + caps_str + ")";
  endverb

  verb format_grant_with_name (this none this) owner: HACKER flags: "rxd"
    "Format a grant specification including the target object's name.";
    {target, category, cap_list} = args;
    typeof(target) == OBJ || raise(E_TYPE);
    typeof(category) == SYM || raise(E_TYPE);
    typeof(cap_list) == LIST || raise(E_TYPE);
    target_name = valid(target) ? target:name() | "invalid object";
    target_str = target_name + " (" + tostr(target) + ")";
    category_str = tostr(category);
    cap_names = { tostr(c) for c in (cap_list) };
    caps_str = cap_names:join(",");
    return target_str + "." + category_str + "(" + caps_str + ")";
  endverb

  verb parse_grant (this none this) owner: HACKER flags: "rxd"
    "Parse a grant specification like #38.area(add_room,create_passage) into components.";
    "Returns {target, category, cap_list} or raises E_INVARG on parse error.";
    {grant_str} = args;
    typeof(grant_str) == STR || raise(E_TYPE);
    "Find the dots separating target.category";
    dot_idx = "." in grant_str;
    if (dot_idx == 0)
      raise(E_INVARG, "Grant spec must contain '.' separator");
    endif
    target_str = grant_str[1..dot_idx - 1];
    rest = grant_str[dot_idx + 1..length(grant_str)];
    "Find the opening paren for caps list";
    paren_idx = "(" in rest;
    if (paren_idx == 0)
      raise(E_INVARG, "Grant spec must contain '(' for capabilities");
    endif
    category_str = rest[1..paren_idx - 1];
    caps_part = rest[paren_idx + 1..length(rest)];
    "Ensure closing paren";
    if (length(caps_part) == 0 || caps_part[length(caps_part)] != ")")
      raise(E_INVARG, "Grant spec must end with ')'");
    endif
    caps_str = caps_part[1..length(caps_part) - 1];
    "Parse target object - use match_object to handle $sysref, #id, etc.";
    try
      target = $match:match_object(target_str);
    except (ANY)
      raise(E_INVARG, "Invalid target object: " + target_str);
    endtry
    if (typeof(target) != OBJ || !valid(target))
      raise(E_INVARG, "Invalid target object: " + target_str);
    endif
    "Parse category";
    category = tosym(category_str);
    "Parse capability list - filter out empty strings";
    cap_list = {};
    if (length(caps_str) > 0)
      cap_strs = caps_str:split(",");
      for cap_str in (cap_strs)
        cap_str = cap_str:trim();
        if (length(cap_str) > 0)
          cap_list = {@cap_list, tosym(cap_str)};
        endif
      endfor
    endif
    return {target, category, cap_list};
  endverb

  verb format_denial (this none this) owner: HACKER flags: "rxd"
    "Format a permission denial message for missing capabilities.";
    {target, category, required_caps} = args;
    typeof(target) == OBJ || raise(E_TYPE);
    typeof(category) == SYM || raise(E_TYPE);
    typeof(required_caps) == LIST || raise(E_TYPE);
    target_name = valid(target) ? target:name() | "invalid object";
    target_str = "\"" + target_name + "\" (" + tostr(target) + ")";
    grant_spec = this:format_grant(target, category, required_caps);
    cap_names = { tostr(c) for c in (required_caps) };
    caps_str = cap_names:join(", ");
    message = "You don't have permission to perform this action on " + target_str + ".";
    message = message + " Required: " + grant_spec + " (or ownership/wizard status).";
    return message;
  endverb

  verb test_format_grant (this none this) owner: HACKER flags: "rxd"
    "Test basic grant formatting.";
    result = this:format_grant(#38, 'area, {'add_room, 'create_passage});
    result == "#38.area(add_room,create_passage)" || raise(E_ASSERT, "format_grant failed: " + result);
    "Test single capability";
    result = this:format_grant(#12, 'room, {'dig_from});
    result == "#12.room(dig_from)" || raise(E_ASSERT, "Single cap format failed: " + result);
    "Test empty capability list";
    result = this:format_grant(#1, 'test, {});
    result == "#1.test()" || raise(E_ASSERT, "Empty cap list failed: " + result);
  endverb

  verb test_format_grant_with_name (this none this) owner: HACKER flags: "rxd"
    "Test grant formatting with object names.";
    "Test with valid object";
    result = this:format_grant_with_name($first_area, 'area, {'add_room});
    "First Area" in result || raise(E_ASSERT, "Name not included: " + result);
    "#50" in result || raise(E_ASSERT, "Object ID not included: " + result);
    ".area(add_room)" in result || raise(E_ASSERT, "Grant spec malformed: " + result);
  endverb

  verb test_parse_grant (this none this) owner: HACKER flags: "rxd"
    "Test parsing valid grant specifications.";
    {target, category, cap_list} = this:parse_grant("#38.area(add_room,create_passage)");
    target == #38 || raise(E_ASSERT, "Wrong target: " + tostr(target));
    category == 'area || raise(E_ASSERT, "Wrong category: " + tostr(category));
    length(cap_list) == 2 || raise(E_ASSERT, "Wrong cap list length: " + tostr(length(cap_list)));
    'add_room in cap_list || raise(E_ASSERT, "'add_room not in cap_list");
    'create_passage in cap_list || raise(E_ASSERT, "'create_passage not in cap_list");
    "Test single capability with whitespace";
    {target, category, cap_list} = this:parse_grant("#12.room( dig_from )");
    target == #12 || raise(E_ASSERT, "Wrong target (whitespace test)");
    category == 'room || raise(E_ASSERT, "Wrong category (whitespace test)");
    length(cap_list) == 1 || raise(E_ASSERT, "Wrong cap list length (whitespace test)");
    'dig_from in cap_list || raise(E_ASSERT, "'dig_from not in cap_list (whitespace test)");
    "Test empty capability list";
    {target, category, cap_list} = this:parse_grant("#1.test()");
    target == #1 || raise(E_ASSERT, "Wrong target (empty caps)");
    category == 'test || raise(E_ASSERT, "Wrong category (empty caps)");
    length(cap_list) == 0 || raise(E_ASSERT, "Cap list should be empty");
  endverb

  verb test_parse_grant_errors (this none this) owner: HACKER flags: "rxd"
    "Test parse_grant error handling.";
    "Missing dot separator";
    caught = `this:parse_grant("#38area(test)") ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject missing dot");
    "Missing opening paren";
    caught = `this:parse_grant("#38.area") ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject missing paren");
    "Missing closing paren";
    caught = `this:parse_grant("#38.area(test") ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject missing close paren");
    "Invalid object ID";
    caught = `this:parse_grant("notanobject.area(test)") ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject invalid object");
    "Empty string";
    caught = `this:parse_grant("") ! E_INVARG => true';
    caught || raise(E_ASSERT, "Should reject empty string");
  endverb

  verb test_format_denial (this none this) owner: HACKER flags: "rxd"
    "Test denial message formatting.";
    message = this:format_denial($first_area, 'area, {'add_room, 'create_passage});
    "First Area" in message || raise(E_ASSERT, "Name not in denial: " + message);
    "#50" in message || raise(E_ASSERT, "Object ID not in denial: " + message);
    "#50.area(add_room,create_passage)" in message || raise(E_ASSERT, "Grant spec not in denial: " + message);
    "permission" in message || raise(E_ASSERT, "No permission text in denial: " + message);
  endverb

  verb test_round_trip (this none this) owner: HACKER flags: "rxd"
    "Test format->parse round trip.";
    original_target = #38;
    original_category = 'area;
    original_caps = {'add_room, 'create_passage, 'test_cap};
    formatted = this:format_grant(original_target, original_category, original_caps);
    {parsed_target, parsed_category, parsed_caps} = this:parse_grant(formatted);
    parsed_target == original_target || raise(E_ASSERT, "Round trip: target mismatch");
    parsed_category == original_category || raise(E_ASSERT, "Round trip: category mismatch");
    length(parsed_caps) == length(original_caps) || raise(E_ASSERT, "Round trip: cap count mismatch");
    for cap in (original_caps)
      cap in parsed_caps || raise(E_ASSERT, "Round trip: missing cap " + tostr(cap));
    endfor
  endverb
endobject