object MATCH
  name: "Object Matching Utilities"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: HACKER
  readable: true

  override description = "Object matching system with support for numbered, UUID, and flyweight objects. Provides flexible matching with fuzzy search and enhanced error reporting.";
  override import_export_hierarchy = {"utils"};
  override import_export_id = "match";

  verb match_object (this none this) owner: HACKER flags: "rxd"
    "Match an object reference string to an actual object.";
    "Handles: #123, #UUID-style, $system.prop, @playername, or plain name matching.";
    "Usage: $match:match_object(ref_string [, context_object])";
    "The context_object (defaults to player) determines:";
    "  - What 'me' and 'player' resolve to (the context_object itself)";
    "  - What 'here' resolves to (context_object.location)";
    "  - Which objects to search for name matching (context_object.contents and context_object.location.contents)";
    {ref_string, ?context = player} = args;
    typeof(ref_string) != STR && raise(E_TYPE, "Object reference must be a string");
    !ref_string && raise(E_INVARG, "Empty object reference");
    if (ref_string[1] == "#")
      result = toobj(ref_string);
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
        typeof(current_obj) == OBJ || raise(E_TYPE, "System reference $" + prop_path + " is not an object");
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
  endverb

  verb match_player (this none this) owner: HACKER flags: "rxd"
    "Match player by name using complex_match builtin.";
    {player_name, ?context = player} = args;
    players = players();
    result = complex_match(player_name, players);
    result == $failed_match && raise(E_INVARG, "No player found matching '" + player_name + "'");
    return result;
  endverb

  verb match_by_name (this none this) owner: HACKER flags: "rxd"
    "Match object by name in current context using complex_match builtin.";
    {name_string, ?context = player} = args;
    "Special cases for common MOO references";
    if (name_string:lowercase() == "here")
      if (valid(context) && valid(context.location))
        return context.location;
      else
        raise(E_INVARG, "No location to match 'here'");
      endif
    elseif (name_string:lowercase() == "me" || name_string:lowercase() == "player")
      if (valid(context))
        return context;
      else
        raise(E_INVARG, "No context to match '" + name_string + "'");
      endif
    endif
    search_objects = {};
    if (valid(context) && valid(context.location))
      search_objects = {@search_objects, @context.location.contents};
    endif
    if (valid(context))
      search_objects = {@search_objects, @context.contents};
    endif
    "Let complex_match auto-detect object names";
    result = complex_match(name_string, search_objects);
    result == $failed_match && raise(E_INVARG, "No object found matching '" + name_string + "'");
    return result;
  endverb

  verb resolve_in_scope (this none this) owner: HACKER flags: "rxd"
    "Resolve a token against a list of scope entries (objects or {obj, aliases...}).";
    "The optional third argument is a map of options (unusual for MOO, but keeps flags extensible):";
    "  'allow_literals (bool, default true) - skip straight to literal #obj/uuobjid lookups";
    "  'fuzzy_threshold (num/bool, default 0.5) - fuzzy matching tolerance passed to complex_match";
    {token, scope, ?options = []} = args;
    typeof(token) == STR || raise(E_TYPE, "Token must be a string");
    typeof(scope) == LIST || raise(E_TYPE, "Scope must be a list");
    options = typeof(options) == MAP ? options | [];
    allow_literals = maphaskey(options, 'allow_literals) ? options['allow_literals] | true;
    fuzzy_threshold = maphaskey(options, 'fuzzy_threshold) ? options['fuzzy_threshold] | 0.5;
    if (typeof(fuzzy_threshold) == BOOL)
      fuzzy_threshold = fuzzy_threshold ? 0.5 | 0.0;
    elseif (typeof(fuzzy_threshold) == INT)
      fuzzy_threshold = fuzzy_threshold + 0.0;
    endif
    token_trimmed = token:trim();
    if (!token_trimmed)
      return #-3;
    endif
    if (allow_literals)
      literal = $str_proto:match_objid(token_trimmed);
      if (literal && literal['start] == 1 && literal['end] == length(token_trimmed))
        try
          let candidate_obj = toobj(token_trimmed);
          if (typeof(candidate_obj) == OBJ && valid(candidate_obj))
            return candidate_obj;
          endif
        except (ANY)
        endtry
      endif
    endif
    targets = {};
    keys = {};
    has_keys = false;
    for entry in (scope)
      if (typeof(entry) == OBJ)
        targets = {@targets, entry};
        keys = {@keys, {}};
      elseif (typeof(entry) == LIST && entry && typeof(entry[1]) == OBJ)
        let entry_obj = entry[1];
        alias_list = {};
        for alias in (entry[2..$])
          if (typeof(alias) == STR && alias)
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
    keys_arg = has_keys ? keys | false;
    result = complex_match(token_trimmed, targets, keys_arg, fuzzy_threshold);
    return result;
  endverb

  verb test_match_object (this none this) owner: HACKER flags: "rxd"
    "Test object matching - returns actual objects.";
    result = this:match_object("#1");
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
    test_players = players();
    if (length(test_players) > 0)
      let first_player = test_players[1];
      let player_name = first_player.name;
      result = complex_match(player_name, test_players);
      result == first_player || raise(E_ASSERT, "Should return player object: " + toliteral(result));
    endif
    result = this:match_object("archwizard");
    valid(result) || raise(E_ASSERT, "Should match 'archwizard' to ArchWizard object: " + toliteral(result));
  endverb

  verb test_resolve_in_scope_literals (this none this) owner: HACKER flags: "rxd"
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
  endverb

  verb test_resolve_in_scope_aliases (this none this) owner: HACKER flags: "rxd"
    scope = {{#49, "first room", "lobby"}, {#50, "first area"}};
    result = this:resolve_in_scope("lobby", scope);
    result != #49 && raise(E_ASSERT, "Alias should resolve to first room: " + toliteral(result));
    result = this:resolve_in_scope("first area", scope);
    result != #50 && raise(E_ASSERT, "Text alias should resolve to first area: " + toliteral(result));
  endverb

  verb test_resolve_in_scope_ordinals (this none this) owner: HACKER flags: "rxd"
    scope = {{#49, "room"}, {#50, "room"}};
    result = this:resolve_in_scope("second room", scope);
    result != #50 && raise(E_ASSERT, "Ordinal should pick second entry: " + toliteral(result));
    result = this:resolve_in_scope("third room", scope);
    result != #-3 && raise(E_ASSERT, "Out-of-range ordinal should fail: " + toliteral(result));
  endverb

  verb test_resolve_in_scope_fuzzy (this none this) owner: HACKER flags: "rxd"
    scope = {{#49, "lobby"}};
    result = this:resolve_in_scope("lobbi", scope, ['fuzzy_threshold -> 0.8]);
    result != #49 && raise(E_ASSERT, "Fuzzy match should succeed with threshold: " + toliteral(result));
    result = this:resolve_in_scope("lobbi", scope, ['fuzzy_threshold -> 0.0]);
    result != #-3 && raise(E_ASSERT, "Fuzzy disabled should fail: " + toliteral(result));
  endverb
endobject