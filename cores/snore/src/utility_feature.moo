object UTILITY_FEATURE [
  import_export_id -> "utility_feature"
]
  name: "Utility Feature"
  parent: FEATURE
  owner: HACKER
  fertile: true
  readable: true

  override aliases (owner: HACKER, flags: "rc") = {"Utility Feature"};
  override description (owner: HACKER, flags: "rc") = "Out-of-world player conveniences: teleporting, player listings, and account information.";
  override feature_verbs (owner: HACKER, flags: "r") = {
    "@who",
    "@wizards",
    "where*is",
    "@users",
    "@memory",
    "@version",
    "@uptime",
    "@lastlog",
    "@last-c*onnection",
    "@age",
    "@owner",
    "@move",
    "@teleport",
    "home",
    "@sethome",
    "@rooms",
    "@go",
    "@addr*oom",
    "@rmr*oom",
    "@join",
    "@find",
    "@ways",
    "@at"
  };
  override help_msg (owner: HACKER, flags: "rc") = "This feature provides out-of-world conveniences. Worlds that want immersive movement and information commands can leave it uninstalled.";

  verb "@who" (any any any) owner: #2 flags: "rd"
    "List connected players, or the players named in the arguments.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const plyrs = args ? listdelete($command_utils:player_match_result($string_utils:match_player(args), args), 1) | connected_players();
    !plyrs && return;
    if (length(plyrs) > 100)
      player:tell("You have requested a listing of ", length(plyrs), " players.  Please either specify individual players you are interested in, to reduce the number of players in any single request, or else use the `@users' command instead.  The lag thanks you.");
      return;
    endif
    $code_utils:show_who_listing(plyrs, {}, player);
  endverb

  verb "@wizards" (any none none) owner: #2 flags: "rd"
    "@wizards [all]";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    if (args)
      $code_utils:show_who_listing($wiz_utils:all_wizards(), {}, player);
    else
      $code_utils:show_who_listing($wiz_utils:connected_wizards(), {}, player) || player:tell("No wizards currently logged in.");
    endif
  endverb

  verb "where*is @where*is" (any any any) owner: #2 flags: "rd"
    "Show the locations of connected players or the players named in the arguments.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    let them = connected_players();
    if (args)
      const who = $command_utils:player_match_result($string_utils:match_player(args), args);
      if (length(who) <= 1)
        if (!who[1])
          player:tell("Where is who?");
        endif
        return;
      endif
      if (who[1])
        player:tell("");
      endif
      them = listdelete(who, 1);
    endif
    for p in (them)
      player:tell(tostr($string_utils:left($string_utils:nn(p), 25), " ", $string_utils:nn(p.location)));
    endfor
  endverb

  verb "@users" (none none none) owner: #2 flags: "rd"
    "List connected players by name, one complete name per line.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const cp = connected_players();
    player:tell("There are " + tostr(length(cp)) + " players connected:");
    let dudes = $list_utils:map_prop(cp, "name");
    dudes = $list_utils:sort_suspended($login.current_lag, dudes);
    player:tell_lines(dudes);
  endverb

  verb "@memory" (none none none) owner: #2 flags: "rd"
    "@memory: report resident and reserved process memory. Requires wizard permission.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    $utility_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const {page_size, resident_pages, remaining_pages} = memory_usage();
    player:tell("Resident memory: ", $string_utils:group_number(page_size * resident_pages), " bytes.");
    player:tell("Reserved address space: ", $string_utils:group_number(page_size * (resident_pages + remaining_pages)), " bytes.");
  endverb

  verb "@version" (none none none) owner: #2 flags: "rd"
    "Report the mooR server version and this core's name.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    player:tell("mooR server ", server_version());
    player:tell("The database uses Snore Core, a LambdaCore fork for mooR.");
  endverb

  verb "@uptime" (none none none) owner: #2 flags: "rd"
    "Show how long the server has been running.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    player:tell(tostr($mail_agent.moo_name, " has been up for ", $time_utils:english_time(time() - $last_restart_time, $last_restart_time), "."));
  endverb

  verb "@lastlog" (any none none) owner: #2 flags: "rd"
    "Group players by the time of their most recent connection.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    let folks = players();
    if (dobjstr != "")
      dobj = $string_utils:match_player(dobjstr);
      if (!valid(dobj))
        player:tell("Who?");
        return;
      endif
      folks = {dobj};
    endif
    if (length(folks) > 100)
      player:tell("You have requested a listing of ", length(folks), " players.  That is too long a list; specify individual players you are interested in.");
      return;
    endif
    let day = {};
    let week = {};
    let month = {};
    let ever = {};
    let never = {};
    const a_day = 24 * 60 * 60;
    const a_week = 7 * a_day;
    const a_month = 30 * a_day;
    const now = time();
    for x in (folks)
      const when = x.last_connect_time;
      const how_long = now - when;
      if (when == 0 || when > now)
        never = {@never, x};
      elseif (how_long < a_day)
        day = {@day, x};
      elseif (how_long < a_week)
        week = {@week, x};
      elseif (how_long < a_month)
        month = {@month, x};
      else
        ever = {@ever, x};
      endif
    endfor
    for entry in ({{day, "the last day"}, {week, "the last week"}, {month, "the last 30 days"}, {ever, "recorded history"}})
      if (entry[1])
        player:tell("Players who have connected within ", entry[2], ":");
        for x in (entry[1])
          player:tell("  ", x.name, " last connected ", ctime(x.last_connect_time), ".");
        endfor
      endif
    endfor
    if (never)
      player:tell("Players who have never connected:");
      player:tell("  ", $string_utils:english_list($list_utils:map_prop(never, "name")));
    endif
  endverb

  verb "@last-c*onnection" (any none none) owner: #2 flags: "rxd"
    "@last-c           reports when and from where you last connected.";
    "@last-c all       adds the 10 most recent places you connected from.";
    "@last-c confunc   is like `@last-c' but is silent on first login.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    "Read private connection records only after the caller guard; run output hooks as the player.";
    const prev = player.previous_connection;
    const places = player.all_connect_places;
    set_task_perms(player);
    const opts = {"all", "confunc"};
    let i = 0;
    if (length(args) > 1)
      player:tell(tostr("Usage: ", verb, " [all]"));
      return;
    endif
    i = args ? $string_utils:find_prefix(args[1], opts) | 0;
    if (args && !i)
      player:tell(tostr("Usage:  ", verb, " [all]"));
      return;
    endif
    const opt_all = i && opts[i] == "all";
    const opt_confunc = i && opts[i] == "confunc";
    if (!prev)
      player:tell("Something was broken when you logged in; tell a wizard.");
    elseif (prev[1] == 0)
      opt_confunc || player:tell("Your previous connection was before we started keeping track.");
    elseif (prev[1] > time())
      player:tell("This is your first time connected.");
    else
      player:tell(tostr("Last connected ", player:ctime(prev[1]), " from ", prev[2]));
      if (opt_all)
        player:tell("Previous connections have been from the following sites:");
        for l in (places)
          player:tell("   " + l);
        endfor
      endif
    endif
  endverb

  verb "@age" (any none none) owner: #2 flags: "rd"
    "Show when a player first connected and how long ago that was.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    if (dobjstr == "" || dobj == player)
      dobj = player;
    else
      dobj = $string_utils:match_player(dobjstr);
      if (!valid(dobj))
        $command_utils:player_match_failed(dobj, dobjstr);
        return;
      endif
    endif
    const first = dobj.first_connect_time;
    if (first == $maxint)
      const duration = time() - dobj.last_disconnect_time;
      const notice = duration < 86400 ? $string_utils:from_seconds(duration) | $time_utils:english_time(duration / 86400 * 86400);
      player:tell(tostr(dobj.name, " has never connected.  It was created ", notice, " ago."));
    elseif (first == 0)
      player:tell(tostr(dobj.name, " first connected before initial connections were being recorded."));
    else
      player:tell(tostr(dobj.name, " first connected on ", ctime(first)));
      const duration = time() - first;
      const notice = duration < 86400 ? $string_utils:from_seconds(duration) | $time_utils:english_time(duration / 86400 * 86400);
      player:tell(tostr($string_utils:pronoun_sub("%S %<is> ", dobj), notice, " old."));
    endif
  endverb

  verb "@owner" (any none none) owner: #2 flags: "rd"
    "Show the owner of an object.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    dobj = player:my_match_object(dobjstr);
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    player:tell($string_utils:nn(dobj), " is owned by ", $string_utils:nn(dobj.owner), ".");
  endverb

  verb home (none none none) owner: #2 flags: "rd"
    "Move to your home through the normal movement hooks.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const start = player.location;
    if (start == player.home)
      player:tell("You're already home!");
      return;
    endif
    if (typeof(player.home) != TYPE_OBJ)
      player:tell("You've got a weird home, pal.  I've reset it to the default one.");
      player.home = $player_start;
    elseif (!valid(player.home))
      player:tell("Oh no!  Your home's been recycled.  Time to look around for a new one.");
      player.home = $player_start;
    else
      player:tell("You click your heels three times.");
    endif
    player:moveto(player.home);
    if (!valid(start))
    elseif (start == player.location)
      start:announce(player.name, " ", $gender_utils:get_conj("learns", player), " that you can never go home...");
    else
      try
        start:announce(player.name, " ", $gender_utils:get_conj("goes", player), " home.");
      except e (E_VERBNF)
        "start did not support announce";
      endtry
    endif
    if (player.location == player.home)
      player.location:announce(player.name, " ", $gender_utils:get_conj("comes", player), " home.");
    elseif (player.location == start)
      player:tell("Either home doesn't want you, or you don't really want to go.");
    else
      player:tell("Wait a minute!  This isn't your home...");
      if (valid(player.location))
        player.location:announce(player.name, " ", $gender_utils:get_conj("arrives", player), ", looking quite bewildered.");
      endif
    endif
  endverb

  verb "@sethome" (none none none) owner: #2 flags: "rd"
    "Set your home to the current room if it accepts you as a resident.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const here = player.location;
    if (!$perm_utils:controls(player, player))
      player:tell("Players who do not own themselves may not modify their home.");
    elseif (!$object_utils:has_callable_verb(here, "accept_for_abode"))
      player:tell("This is a pretty odd place.  You should make your home in an actual room.");
    elseif (here:accept_for_abode(player))
      player.home = here;
      player:tell(tostr(here.name, " is your new home."));
    else
      player:tell(tostr("This place doesn't want to be your home.  Contact ", here.owner.name, " to be added to the residents list of this place, or choose another place as your home."));
    endif
  endverb

  verb "@rooms" (none none none) owner: #2 flags: "rd"
    "'@rooms' - List the rooms which are known by name.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    let line = "";
    for item in (player.rooms)
      line = line + item[1] + "(" + tostr(item[2]) + ")   ";
    endfor
    player:tell(line);
  endverb

  verb "@go" (any none none) owner: #2 flags: "rd"
    "'@go <place>' - Teleport yourself somewhere. Example: '@go liv' to go to the living room.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const dest = player:lookup_room(dobjstr);
    if (dest == $failed_match)
      player:tell("There's no such place known.");
      return;
    endif
    player:teleport(player, dest);
  endverb

  verb "@move @teleport" (any any any) owner: #2 flags: "rd"
    "'@move <object> to <place>' - Teleport an object. Example: '@move trash to #11' to move trash to the closet.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const here = player.location;
    if (prepstr != "to" || !iobjstr)
      player:tell("Usage: @move <object> to <location>");
      return;
    endif
    let thing;
    if (!dobjstr || dobjstr == "me")
      thing = player;
    else
      thing = `here:match_object(dobjstr) ! E_VERBNF, E_INVIND => $failed_match';
      if (thing == $failed_match)
        thing = player:my_match_object(dobjstr);
      endif
    endif
    $command_utils:object_match_failed(thing, dobjstr) && return;
    if (!player.programmer && (thing.owner != player && thing != player))
      player:tell("You can only move your own objects.");
      return;
    endif
    const dest = player:lookup_room(iobjstr);
    if (dest == #-1 || !$command_utils:object_match_failed(dest, iobjstr))
      player:teleport(thing, dest);
    endif
  endverb

  verb "@addr*oom" (any none none) owner: #2 flags: "rd"
    "'@addroom <name> <object>', '@addroom <object> <name>', '@addroom <name>', '@addroom <object>', '@addroom' - Add a room to your personal database of teleport destinations. Example: '@addroom Kitchen #24'. Reasonable <object>s are numbers (#17) and 'here'. If you leave out <object>, the object is the current room. If you leave out <name>, the name is the specified room's name. If you leave out both, you get the current room and its name.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    let object;
    let name;
    if (!dobjstr)
      object = player.location;
      name = valid(object) ? object.name | "Nowhere";
    else
      const command = player:parse_out_object(dobjstr);
      if (command)
        name = command[1];
        object = command[2];
      else
        name = dobjstr;
        object = player.location;
      endif
    endif
    if (!valid(object))
      player:tell("This is not a valid location.");
      return E_INVARG;
    endif
    player:tell("Adding ", name, "(", tostr(object), ") to your database of rooms.");
    player.rooms = {@player.rooms, {name, object}};
  endverb

  verb "@rmr*oom" (any none none) owner: #2 flags: "rd"
    "'@rmroom <roomname>' - Remove a room from your personal database of teleport destinations. Example: '@rmroom library'.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const index = player:index_room(dobjstr);
    if (index)
      player:tell("Removing ", player.rooms[index][1], "(", player.rooms[index][2], ").");
      player.rooms = listdelete(player.rooms, index);
      return;
    endif
    player:tell("That room is not in your database of rooms. Check '@rooms'.");
  endverb

  verb "@join" (any none none) owner: #2 flags: "rd"
    "'@join <player>' - Teleport yourself to the location of any player, whether connected or not.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    if (dobjstr == "")
      player:tell("Usage: @join <player>. For example, '@join frand'.");
      return;
    endif
    const target = $string_utils:match_player(dobjstr);
    $command_utils:player_match_result(target, dobjstr);
    !valid(target) && return;
    if (target == player)
      player:tell("You are already with yourself.");
      return;
    endif
    let dest = target.location;
    let msg = player:enlist(player:join_msg());
    const editing = $object_utils:isa(dest, $generic_editor);
    if (editing)
      dest = dest.original[target in dest.active];
      const editing_msg = "%N is editing at the moment. You can wait here until %s is done.";
      if (player.location == dest)
        msg = {editing_msg};
      else
        msg = {@msg, editing_msg};
      endif
    endif
    if (msg && (player.location != dest || editing))
      player:tell_lines($string_utils:pronoun_sub(msg, target));
    elseif (player.location == dest)
      player:tell("OK, you're there. You didn't actually need to move, though.");
      return;
    endif
    player:teleport(player, dest);
  endverb

  verb "@find" (any none none) owner: #2 flags: "rd"
    "'@find #<object>', '@find <player>', '@find :<verb>' '@find .<property>' - Attempt to locate things. Verbs and properties are found on any object in the player's vicinity, and some other places.  '@find ?<help>' looks for a help topic on any available help database.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage: '@find #<object>' or '@find <player>' or '@find :<verb>' or '@find .<property>' or '@find ?<help topic>'.");
      return;
    endif
    let target;
    if (dobjstr[1] == ":")
      const name = dobjstr[2..$];
      player:find_verb(name);
      return;
    endif
    if (dobjstr[1] == ".")
      const name = dobjstr[2..$];
      player:find_property(name);
      return;
    elseif (dobjstr[1] == "#")
      target = toobj(dobjstr);
      if (!valid(target))
        player:tell(target, " does not exist.");
      endif
    elseif (dobjstr[1] == "?")
      const name = dobjstr[2..$];
      player:find_help(name);
      return;
    else
      target = $string_utils:match_player(dobjstr);
      $command_utils:player_match_result(target, dobjstr);
    endif
    if (valid(target))
      player:tell(target.name, " (", target, ") is at ", valid(target.location) ? target.location.name | "Nowhere", " (", target.location, ").");
    endif
  endverb

  verb "@ways" (any none none) owner: #2 flags: "rd"
    "'@ways', '@ways <room>' - List any obvious exits from the given room (or this room, if none is given).";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    const room = dobjstr ? dobj | player.location;
    if (!valid(room) || !($room in $object_utils:ancestors(room)))
      player:tell("You can only pry into the exits of a room.");
      return;
    endif
    let exits = {};
    if ($object_utils:has_verb(room, "obvious_exits"))
      exits = room:obvious_exits();
    endif
    exits = player:checkexits(player:obvious_exits(), room, exits);
    exits = player:findexits(room, exits);
    player:tell_ways(exits, room);
  endverb

  verb "@at" (any any any) owner: #2 flags: "rd"
    "'@at' - Find out where everyone is. '@at <player>' - Find out where <player> is, and who else is there. '@at <obj>' - Find out who else is at the same place as <obj>. '@at <place>' - Find out who is at the place. The place can be given by number, or it can be a name from your @rooms list. '@at #-1' - Find out who is at #-1. '@at me' - Find out who is in the room with you. '@at home' - Find out who is at your home.";
    $utility_feature in player.features || raise(E_PERM);
    !valid(caller_perms()) || caller_perms() == player || $perm_utils:controls(caller_perms(), player) || raise(E_PERM);
    set_task_perms(player);
    player:internal_at(argstr);
  endverb
endobject
