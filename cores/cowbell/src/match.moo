object MATCH
  name: "Object Matching Utilities"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  override description = "Object matching system with support for numbered, UUID, and flyweight objects. Provides flexible matching with fuzzy search and enhanced error reporting.";
  override import_export_id = "match";

  verb parse_object_ref (this none this) owner: HACKER flags: "rxd"
    "Parse object reference string into components. Handles #123, #UUID-style, $system, @player formats.";
    "Returns {type, identifier, original} on success, or descriptive error on failure.";
    {ref_string} = args;
    !ref_string && return E_INVARG("Empty object reference");
    if (ref_string[1] == "#")
      if (ref_string:contains("-") && length(ref_string) > 10)
        return {'uuid, ref_string, ref_string};
      else
        let num_part = ref_string[2..$];
        num_part:is_numeric() || return E_INVARG("Invalid numeric object ID: " + ref_string);
        return {'numbered, toint(num_part), ref_string};
      endif
    elseif (ref_string[1] == "$")
      let prop_path = ref_string[2..$];
      prop_path || return E_INVARG("Empty system reference after $");
      return {'system, prop_path, ref_string};
    elseif (ref_string[1] == "@")
      let player_name = ref_string[2..$];
      player_name || return E_INVARG("Empty player reference after @");
      return {'player, player_name, ref_string};
    else
      return {'name, ref_string, ref_string};
    endif
  endverb

  verb resolve_object_ref (this none this) owner: HACKER flags: "rxd"
    "Resolve parsed object reference to actual object. Returns object or descriptive error.";
    {ref_info} = args;
    typeof(ref_info) != LIST && return E_TYPE("Expected parsed reference info");
    length(ref_info) < 2 && return E_INVARG("Malformed reference info");
    {ref_type, identifier, @rest} = ref_info;
    if (ref_type == 'numbered)
      let target_obj = toobj("#" + tostr(identifier));
      valid(target_obj) || return E_INVARG("Object #" + tostr(identifier) + " does not exist");
      return target_obj;
    elseif (ref_type == 'uuid)
      let target_obj = toobj(identifier);
      valid(target_obj) || return E_INVARG("UUID object " + identifier + " does not exist");
      return target_obj;
    elseif (ref_type == 'system)
      try
        let current_obj = #0;
        for prop_name in (identifier:split("."))
          current_obj = current_obj.(prop_name);
        endfor
        typeof(current_obj) == OBJ || return E_TYPE("System reference " + identifier + " is not an object");
        return current_obj;
      except (E_PROPNF)
        return E_PROPNF("System property $" + identifier + " does not exist");
      except (ANY)
        return E_INVARG("Invalid system reference $" + identifier);
      endtry
    elseif (ref_type == 'player)
      return this:match_player(identifier);
    elseif (ref_type == 'name)
      return this:match_by_name(identifier);
    else
      return E_INVARG("Unknown reference type: " + tostr(ref_type));
    endif
  endverb

  verb match_object (this none this) owner: HACKER flags: "rxd"
    "Main object matching interface. Returns the actual object.";
    "Usage: $match:match_object(ref_string [, context_object])";
    "The context_object (defaults to player) determines:";
    "  - What 'me' and 'player' resolve to (the context_object itself)";
    "  - What 'here' resolves to (context_object.location)";
    "  - Which objects to search for name matching (context_object.contents and context_object.location.contents)";
    {ref_string, ?context = player} = args;
    typeof(ref_string) != STR && return E_TYPE("Object reference must be a string");
    parse_result = this:parse_object_ref(ref_string);
    typeof(parse_result) == ERR && return parse_result;
    resolve_result = this:resolve_object_ref(parse_result);
    return resolve_result;
  endverb

  verb match_player (this none this) owner: HACKER flags: "rxd"
    "Match player by name using complex_match builtin.";
    {player_name} = args;
    players = players();
    result = complex_match(player_name, players);
    if (result == $failed_match)
      return E_INVARG("No player found matching '" + player_name + "'");
    endif
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
        return E_INVARG("No location to match 'here'");
      endif
    elseif (name_string:lowercase() == "me" || name_string:lowercase() == "player")
      if (valid(context))
        return context;
      else
        return E_INVARG("No context to match '" + name_string + "'");
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
    if (result == $failed_match)
      return E_INVARG("No object found matching '" + name_string + "'");
    endif
    return result;
  endverb

  verb test_match_object (this none this) owner: HACKER flags: "rxd"
    "Test object matching - returns actual objects.";
    result = this:match_object("#1");
    result != #1 && raise(E_ASSERT, "Should return actual object #1: " + toliteral(result));
    result = this:match_object("$root");
    result != $root && raise(E_ASSERT, "Should return actual $root object: " + toliteral(result));
    result = this:match_object("");
    typeof(result) != ERR && raise(E_ASSERT, "Empty string should return error: " + toliteral(result));
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
endobject