object MATCH [
  import_export_id -> "match",
  import_export_hierarchy -> {"utils"}
]
  name: "Object Matching Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description (owner: HACKER, flags: "rc") = "Object matching system with support for numbered, UUID, and flyweight objects. Provides flexible matching with fuzzy search and enhanced error reporting.";

  method match_object owner: HACKER
    "Match an object reference string to an actual object.";
    "Handles: #123, #UUID-style, $system.prop, @playername, or plain name matching.";
    "Usage: $match:match_object(ref_string [, context_object])";
    "The context_object (defaults to player) determines:";
    "  - What 'me' and 'player' resolve to (the context_object itself)";
    "  - What 'here' resolves to (context_object.location)";
    "  - Which objects to search for name matching (context_object.contents and context_object.location.contents)";
    const {ref_string, ?context = player} = args;
    typeof(ref_string) != TYPE_STR && raise(E_TYPE, "Object reference must be a string");
    !ref_string && raise(E_INVARG, "Empty object reference");
    if (ref_string[1] == "#")
      const result = toobj(ref_string);
      if (result == #0 && ref_string != "#0")
        raise(E_INVARG, "Invalid object reference: " + ref_string);
      endif
      valid(result) || raise(E_INVARG, "Object " + ref_string + " does not exist");
      return result;
    elseif (ref_string[1] == "$")
      let prop_path = ref_string[2..$];
      prop_path || raise(E_INVARG, "Empty system reference after $");
      try
        let current_obj = #0;
        for prop_name in (prop_path:split("."))
          current_obj = current_obj.(prop_name);
        endfor
        typeof(current_obj) == TYPE_OBJ || raise(E_TYPE, "System reference $" + prop_path + " is not an object");
        return current_obj;
      except e (E_PROPNF)
        raise(E_PROPNF, "System property $" + prop_path + " does not exist");
      except e (ANY)
        raise(E_INVARG, "Invalid system reference $" + prop_path);
      endtry
    elseif (ref_string[1] == "@")
      let player_name = ref_string[2..$];
      player_name || raise(E_INVARG, "Empty player reference after @");
      return this:match_player(player_name, context);
    else
      return this:match_by_name(ref_string, context);
    endif
  endmethod

  method match_player owner: HACKER
    "Match player by name or object number using complex_match builtin.";
    const {player_name, ?context = player} = args;
    "Handle 'me'/'myself' as special case";
    if (player_name in {"me", "myself"})
      valid(context) && is_player(context) && return context;
      raise(E_INVARG, "No player context for 'me'");
    endif
    "Handle object number references (e.g., '#2', '#000053-9A6FBE399A')";
    if (player_name[1] == "#")
      const obj = `toobj(player_name) ! E_RANGE => $nothing';
      !valid(obj) && raise(E_INVARG, "Invalid object reference: " + player_name);
      !is_player(obj) && raise(E_INVARG, tostr(obj) + " is not a player.");
      return obj;
    endif
    const all_players = players();
    const result = complex_match(player_name, all_players);
    result == $failed_match && raise(E_INVARG, "No player found matching '" + player_name + "'");
    return result;
  endmethod

  method match_by_name owner: HACKER
    "Match object by name in current context using complex_match builtin.";
    const {name_string, ?context = player} = args;
    if (name_string == "here")
      valid(context) && valid(context.location) && return context.location;
      raise(E_INVARG, "No location to match 'here'");
    elseif (name_string in {"me", "player"})
      valid(context) && return context;
      raise(E_INVARG, "No context to match '" + name_string + "'");
    endif
    "Build search objects: context.contents FIRST (for containers), then location.contents.";
    let search_objects = {};
    valid(context) && (search_objects = {@search_objects, @context.contents});
    valid(context) && valid(context.location) && (search_objects = {@search_objects, @context.location.contents});
    !length(search_objects) && raise(E_INVARG, "No objects to search");
    "Build keys list with name and aliases for each object.";
    "This ensures aliases are checked properly by complex_match.";
    let keys = {};
    for o in (search_objects)
      let obj_keys = {o.name};
      try
        const aliases = o.aliases;
        if (typeof(aliases) == TYPE_LIST)
          obj_keys = {@obj_keys, @aliases};
        endif
      except e (ANY)
      endtry
      keys = {@keys, obj_keys};
    endfor
    "Use 3-arg complex_match with explicit keys to get proper alias matching.";
    const result = complex_match(name_string, search_objects, keys);
    result == $failed_match && raise(E_INVARG, "No object found matching '" + name_string + "'");
    return result;
  endmethod

  method resolve_in_scope owner: HACKER
    "Resolve a token against a list of scope entries (objects or {obj, aliases...}).";
    "The optional third argument is a map of options (unusual for MOO, but keeps flags extensible):";
    "  'allow_literals (bool, default true) - skip straight to literal #obj/uuobjid lookups";
    "  'fuzzy_threshold (num/bool, default 0.5) - fuzzy matching tolerance passed to complex_match";
    let {token, scope, ?options = []} = args;
    typeof(token) == TYPE_STR || raise(E_TYPE, "Token must be a string");
    typeof(scope) == TYPE_LIST || raise(E_TYPE, "Scope must be a list");
    options = typeof(options) == TYPE_MAP ? options | [];
    const allow_literals = maphaskey(options, 'allow_literals) ? options['allow_literals] | true;
    let fuzzy_threshold = maphaskey(options, 'fuzzy_threshold) ? options['fuzzy_threshold] | 0.5;
    if (typeof(fuzzy_threshold) == TYPE_BOOL)
      fuzzy_threshold = fuzzy_threshold ? 0.5 | 0.0;
    elseif (typeof(fuzzy_threshold) == TYPE_INT)
      fuzzy_threshold = tofloat(fuzzy_threshold);
    endif
    const token_trimmed = token:trim();
    if (!token_trimmed)
      return #-3;
    endif
    if (allow_literals)
      const literal = $str_proto:match_objid(token_trimmed);
      if (literal && literal['start] == 1 && literal['end] == length(token_trimmed))
        try
          let candidate_obj = toobj(token_trimmed);
          if (typeof(candidate_obj) == TYPE_OBJ && valid(candidate_obj))
            return candidate_obj;
          endif
        except (E_RANGE)
        endtry
      endif
    endif
    let targets = {};
    let keys = {};
    let has_keys = false;
    for entry in (scope)
      if (typeof(entry) == TYPE_OBJ)
        targets = {@targets, entry};
        keys = {@keys, {}};
      elseif (typeof(entry) == TYPE_LIST && entry && typeof(entry[1]) == TYPE_OBJ)
        let entry_obj = entry[1];
        let alias_list = {};
        for alias in (entry[2..$])
          if (typeof(alias) == TYPE_STR && alias)
            alias_list = {@alias_list, alias};
          endif
        endfor
        targets = {@targets, entry_obj};
        keys = {@keys, alias_list};
        if (alias_list)
          has_keys = true;
        endif
      endif
    endfor
    targets || return #-3;
    const keys_arg = has_keys ? keys | false;
    const result = complex_match(token_trimmed, targets, keys_arg, fuzzy_threshold);
    return result;
  endmethod

  method test_match_object owner: HACKER
    "Test object matching - returns actual objects.";
    let result = this:match_object("#1");
    result != #1 && raise(E_ASSERT, "Should return actual object #1: " + toliteral(result));
    result = this:match_object("$root");
    result != $root && raise(E_ASSERT, "Should return actual $root object: " + toliteral(result));
    try
      result = this:match_object("");
      raise(E_ASSERT, "Empty string should raise error, got: " + toliteral(result));
    except e (E_INVARG)
    endtry
    "Test environmental references";
    result = this:match_object("here");
    result == player.location || raise(E_ASSERT, "Should return player location for 'here': " + toliteral(result));
    result = this:match_object("me");
    result == player || raise(E_ASSERT, "Should return player for 'me': " + toliteral(result));
    result = this:match_object("player");
    result == player || raise(E_ASSERT, "Should return player for 'player': " + toliteral(result));
    "=== Named objects ===";
    const test_players = players();
    if (length(test_players) > 0)
      const first_player = test_players[1];
      const player_name = first_player.name;
      result = complex_match(player_name, test_players);
      result == first_player || raise(E_ASSERT, "Should return player object: " + toliteral(result));
    endif
    result = this:match_object(player.name);
    result == player || raise(E_ASSERT, "Should match the task player by name: " + toliteral(result));
  endmethod

  method test_resolve_in_scope_literals owner: HACKER
    scope = {#49, #50};
    result = this:resolve_in_scope("#49", scope);
    result != #49 && raise(E_ASSERT, "Literal numeric ID should resolve to #49: " + toliteral(result));
    temp = create($root);
    try
      uuid_str = tostr(temp);
      result = this:resolve_in_scope(uuid_str, scope);
      result != temp && raise(E_ASSERT, "Literal uuobjid should resolve to created object: " + toliteral(result));
    finally
      temp:destroy();
    endtry
    result = this:resolve_in_scope("#999999", scope);
    result != #-3 && raise(E_ASSERT, "Unknown literal should fail: " + toliteral(result));
  endmethod

  method test_resolve_in_scope_aliases owner: HACKER
    scope = {{#49, "first room", "lobby"}, {#50, "first area"}};
    result = this:resolve_in_scope("lobby", scope);
    result != #49 && raise(E_ASSERT, "Alias should resolve to first room: " + toliteral(result));
    result = this:resolve_in_scope("first area", scope);
    result != #50 && raise(E_ASSERT, "Text alias should resolve to first area: " + toliteral(result));
  endmethod

  method test_resolve_in_scope_ordinals owner: HACKER
    scope = {{#49, "room"}, {#50, "room"}};
    result = this:resolve_in_scope("second room", scope);
    result != #50 && raise(E_ASSERT, "Ordinal should pick second entry: " + toliteral(result));
    result = this:resolve_in_scope("third room", scope);
    result != #-3 && raise(E_ASSERT, "Out-of-range ordinal should fail: " + toliteral(result));
  endmethod

  method test_resolve_in_scope_fuzzy owner: HACKER
    scope = {{#49, "lobby"}};
    result = this:resolve_in_scope("lobbi", scope, ['fuzzy_threshold -> 0.8]);
    result != #49 && raise(E_ASSERT, "Fuzzy match should succeed with threshold: " + toliteral(result));
    result = this:resolve_in_scope("lobbi", scope, ['fuzzy_threshold -> 0.0]);
    result != #-3 && raise(E_ASSERT, "Fuzzy disabled should fail: " + toliteral(result));
  endmethod

  method object_suggestions owner: ARCH_WIZARD
    "Build labelled object choices from a visible match scope, retaining scope aliases.";
    set_task_perms(caller_perms());
    const {scope} = args;
    let result = {};
    let seen = [];
    for entry in (scope)
      const obj = typeof(entry) == TYPE_LIST && entry ? entry[1] | entry;
      if (typeof(obj) != TYPE_OBJ || !valid(obj))
        continue;
      endif
      const aliases = typeof(entry) == TYPE_LIST ? entry[2..$] | {};
      if (maphaskey(seen, obj))
        const previous = seen[obj];
        result[previous]["keys"] = {@result[previous]["keys"], @aliases};
        continue;
      endif
      seen[obj] = length(result) + 1;
      result = {@result, ["id" -> tostr(obj), "label" -> obj:name(), "value" -> tostr(obj), "detail" -> tostr(obj), "objectKind" -> obj:reference_kind(), "keys" -> {@obj:aliases(), @aliases}]};
    endfor
    return result;
  endmethod

  method input_context owner: HACKER
    "Describe the active template slot and any already-bound arguments.";
    const {template, ?active = "input", ?bindings = []} = args;
    typeof(template) == TYPE_STR && length(template) <= 1024 && typeof(bindings) == TYPE_MAP || raise(E_INVARG);
    active in {"input", "dobj", "iobj"} || raise(E_INVARG);
    let slots = {};
    for name in ({"input", "dobj", "iobj"})
      const marker = "{" + name + "}";
      if (index(template, marker))
        index(template, marker) == rindex(template, marker) || raise(E_INVARG, "Repeated argument slot");
        slots = {@slots, name};
      endif
    endfor
    active in slots && length(slots) <= 2 || raise(E_INVARG, "Missing active argument slot");
    for name in (mapkeys(bindings))
      name in slots || raise(E_INVARG, "Unknown bound argument");
      const value = bindings[name];
      typeof(value) == TYPE_STR && length(value) <= 256 && !index(value, "\n") && !index(value, "\r") || raise(E_INVARG);
    endfor
    return ["template" -> template, "active" -> active, "bindings" -> bindings, "slots" -> slots];
  endmethod

  method normalize_input_context owner: HACKER
    "Validate incoming context once, deriving unresolved slots from the template.";
    const {context} = args;
    typeof(context) == TYPE_MAP || raise(E_TYPE);
    !length(context) && return [];
    return this:input_context(context["template"], context["active"], `context["bindings"] ! E_RANGE => []');
  endmethod

  method matching_suggestions owner: ARCH_WIZARD
    "Use the ordinary command matcher, with provisional signature checks for an unfilled second slot.";
    set_task_perms(caller_perms());
    const {candidates, context, match_env, command_env} = args;
    !length(context) && return candidates;
    let template = context["template"];
    for slot in (context["slots"])
      const value = slot == context["active"] ? "#-2" | `context["bindings"][slot] ! E_RANGE => "#-3"';
      template = strsub(template, "{" + slot + "}", value);
    endfor
    const parsed = parse_command(template, match_env, true, 0.3);
    const direct = parsed['dobjstr] == "#-2";
    direct || parsed['iobjstr] == "#-2" || raise(E_INVARG, "Input must fill an object argument");
    const active_key = direct ? 'dobj | 'iobj;
    const other_key = direct ? 'iobj | 'dobj;
    const other_string = direct ? 'iobjstr | 'dobjstr;
    const provisional = parsed[other_string] == "#-3";
    if (provisional)
      "Probe possible receivers once, with a nonempty active sentinel. This accepts only an 'any' active argspec.";
      "Receiver probes do not enumerate combinations of candidate arguments.";
      const receivers = this:object_suggestions({@command_env, @match_env});
      for receiver in (receivers)
        let probe = parsed;
        probe[active_key] = #-2;
        probe[other_key] = toobj(receiver["value"]);
        find_command_verb(probe, command_env) && return candidates;
      endfor
    endif
    const other_candidates = parsed[other_key] == $ambiguous_match ? parsed[direct ? 'ambiguous_iobj | 'ambiguous_dobj] | {parsed[other_key]};
    let result = {};
    for candidate in (candidates)
      const object = toobj(candidate["value"]);
      let command = parsed;
      command[active_key] = object;
      command[direct ? 'dobjstr | 'iobjstr] = candidate["value"];
      "An unfilled slot can be any object, or the same receiver for a 'this' constraint.";
      const others = provisional ? {#-3, object} | other_candidates;
      for other in (others)
        command[other_key] = other;
        if (find_command_verb(command, command_env))
          result = {@result, candidate};
          break;
        endif
      endfor
    endfor
    return result;
  endmethod

  method rank_suggestions owner: HACKER
    "Rank exact, prefix, word-prefix, then substring matches; bound returned rows and omit search keys.";
    const {candidates, query, limit} = args;
    const needle = query:trim():lowercase();
    let buckets = {{}, {}, {}, {}};
    let seen = [];
    let count = 0;
    for candidate in (candidates)
      const id = candidate["id"];
      if (maphaskey(seen, id))
        continue;
      endif
      const keys = {candidate["label"], candidate["value"], @`candidate["keys"] ! E_RANGE => {}'};
      let rank = 5;
      for key in (keys)
        if (typeof(key) != TYPE_STR)
          continue;
        endif
        const text = key:lowercase();
        if (!needle || text == needle)
          rank = 1;
          break;
        elseif (index(text, needle) == 1)
          rank = min(rank, 2);
        elseif (index(text, " " + needle))
          rank = min(rank, 3);
        elseif (index(text, needle))
          rank = min(rank, 4);
        endif
      endfor
      if (rank == 5)
        continue;
      endif
      seen[id] = true;
      count = count + 1;
      if (length(buckets[rank]) < limit)
        buckets[rank] = {@buckets[rank], ["id" -> id, "label" -> candidate["label"], "value" -> candidate["value"], "detail" -> `candidate["detail"] ! E_RANGE => ""', "objectKind" -> `candidate["objectKind"] ! E_RANGE => "object"']};
      endif
    endfor
    const ranked = {@buckets[1], @buckets[2], @buckets[3], @buckets[4]};
    return ["items" -> ranked[1..min(length(ranked), limit)], "more" -> count > limit];
  endmethod
endobject
