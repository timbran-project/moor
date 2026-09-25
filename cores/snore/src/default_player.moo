object DEFAULT_PLAYER [
  import_export_id -> "default_player"
]
  name: "default player class"
  parent: MAIL_RECIPIENT_CLASS
  owner: HACKER
  fertile: true
  readable: true

  property at_number (owner: HACKER, flags: "rc") = false;
  property at_room_width (owner: HACKER, flags: "rc") = 30;
  property join_msg (owner: HACKER, flags: "rc") = "You join %n.";
  property object_port_msg (owner: HACKER, flags: "rc") = "teleports you.";
  property oplayer_port_msg (owner: HACKER, flags: "rc") = "%T teleports %n out.";
  property oself_port_msg (owner: HACKER, flags: "rc") = "%<teleports> out.";
  property othing_port_msg (owner: HACKER, flags: "rc") = "%T teleports %n out.";
  property player_arrive_msg (owner: HACKER, flags: "rc") = "%T teleports %n in.";
  property player_port_msg (owner: HACKER, flags: "rc") = "You teleport %n.";
  property rooms (owner: HACKER, flags: "r") = {};
  property self_arrive_msg (owner: HACKER, flags: "rc") = "%<teleports> in.";
  property self_port_msg (owner: HACKER, flags: "rc") = "";
  property thing_arrive_msg (owner: HACKER, flags: "rc") = "%T teleports %n in.";
  property thing_port_msg (owner: HACKER, flags: "rc") = "You teleport %n.";
  property victim_port_msg (owner: HACKER, flags: "rc") = "teleports you.";

  override aliases (owner: #2, flags: "r") = {"default player class", "player class"};
  override description (owner: HACKER, flags: "rc") = "You see a player who should type '@describe me as ...'.";
  override features (owner: HACKER, flags: "r") = {PASTING_FEATURE, STAGE_TALK, UTILITY_FEATURE};
  override help (owner: HACKER, flags: "rc") = DEFAULT_PLAYER_HELP;
  override mail_notify (owner: HACKER, flags: "rc");
  override object_size (owner: HACKER, flags: "r") = {69955, 1084848672};
  override size_quota (owner: HACKER, flags: "") = {50000, 0, 0, 1};

  method names_of owner: HACKER
    "Return a string of object names using the shared string utility.";
    return $string_utils:names_of(@args);
  endmethod

  method lookup_room owner: HACKER
    "Resolve home, me, here, or a personal room name, then try ordinary nearby-object matching.";
    const room = args[1];
    room == "home" && return player.home;
    room == "me" && return player;
    room == "here" && return player.location;
    room || return $failed_match;
    const index = this:index_room(room);
    return index ? this.rooms[index][2] | this:my_match_object(room);
  endmethod

  method teleport owner: #2
    "Teleport a player or object. For printing messages, there are three cases: (1) teleport self (2) teleport other player (3) teleport object. There's a spot of complexity for handling the invalid location #-1.";
    set_task_perms($perm_utils:controls(caller_perms(), this) ? this | $no_one);
    const {thing, dest} = args;
    const source = thing.location;
    const dest_name = valid(dest) ? dest.name | tostr(dest);
    if (source == dest)
      player:tell(thing.name, " is already at ", dest_name, ".");
      return;
    endif
    thing:moveto(dest);
    if (thing.location == dest)
      const tsd = {thing, source, dest};
      if (thing == player)
        this:teleport_messages(@tsd, this:self_port_msg(@tsd), this:oself_port_msg(@tsd), this:self_arrive_msg(@tsd), "");
      elseif (is_player(thing))
        this:teleport_messages(@tsd, this:player_port_msg(@tsd), this:oplayer_port_msg(@tsd), this:player_arrive_msg(@tsd), this:victim_port_msg(@tsd));
      else
        this:teleport_messages(@tsd, this:thing_port_msg(@tsd), this:othing_port_msg(@tsd), this:thing_arrive_msg(@tsd), this:object_port_msg(@tsd));
      endif
      return;
    endif
    if (thing.location == source)
      if ($object_utils:contains(thing, dest))
        player:tell("Ooh, it's all twisty. ", dest_name, " is inside ", thing.name, ".");
        return;
      endif
      const pronoun = $object_utils:has_property(thing, "po") ? thing.po | "it";
      player:tell("Either ", thing.name, " doesn't want to go, or ", dest_name, " didn't accept ", pronoun, ".");
      return;
    endif
    const thing_name = thing == player ? "you" | thing.name;
    player:tell("A strange force deflects ", thing_name, " from the destination.");
  endmethod

  method teleport_messages owner: HACKER
    "Send teleport messages. There's a slight complication in that the source and dest need not be valid objects.";
    const {thing, source, dest, pmsg, smsg, dmsg, tmsg} = args;
    pmsg && player:tell(pmsg);
    smsg && `source:room_announce_all_but({thing, player}, smsg) ! E_VERBNF, E_INVIND';
    dmsg && `dest:room_announce_all_but({thing, player}, dmsg) ! E_VERBNF, E_INVIND';
    tmsg && thing:tell(tmsg);
  endmethod

  method index_room owner: HACKER
    "Return the exact room-name index, the last prefix match, or 0 when absent.";
    const room = tostr(args[1]);
    const size = length(room);
    let index = 1;
    let match = 0;
    for item in (this.rooms)
      const item_name = item[1];
      room == item_name && return index;
      if (size && length(item_name) >= size && room == item_name[1..size])
        match = index;
      endif
      index = index + 1;
    endfor
    return match;
  endmethod

  method find_verb owner: HACKER
    "Report verb providers in lookup order, removing duplicate objects while preserving their first occurrence.";
    const name = args[1];
    let results = "";
    const objects = $list_utils:remove_duplicates(this:find_verbs_on());
    for thing in (objects)
      if (!valid(thing))
        continue;
      endif
      let mom = $object_utils:has_verb(thing, name);
      if (!mom)
        continue;
      endif
      results = results + "   " + thing.name + "(" + tostr(thing) + ")";
      mom = mom[1];
      if (thing != mom)
        results = results + "--" + mom.name + "(" + tostr(mom) + ")";
      endif
    endfor
    if (results)
      this:tell("The verb :", name, " is on", results);
      return;
    endif
    this:tell("The verb :", name, " is nowhere to be found.");
  endmethod

  method findexits owner: HACKER
    "Add to the 'exits' list any exits in the room which have a single-letter alias.";
    const room = args[1];
    let exits = args[2];
    const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
    for i in [1..length(alphabet)]
      const found = room:match_exit(alphabet[i]);
      if (valid(found) && !(found in exits))
        exits = {@exits, found};
      endif
    endfor
    return exits;
  endmethod

  method checkexits owner: HACKER
    "Check a list of exits to see if any of them are in the given room.";
    const to_check = args[1];
    const room = args[2];
    let exits = args[3];
    for word in (to_check)
      const found = room:match_exit(word);
      if (valid(found) && !(found in exits))
        exits = {@exits, found};
      endif
    endfor
    return exits;
  endmethod

  method "self_port_msg player_port_msg thing_port_msg join_msg" owner: HACKER
    "Expand a personal teleport message when source, destination, and moved object are supplied.";
    let msg = this.(verb);
    if (msg && length(args) >= 3)
      msg = this:msg_sub(msg, @args);
    endif
    return msg;
  endmethod

  method "oself_port_msg self_arrive_msg oplayer_port_msg player_arrive_msg victim_port_msg othing_port_msg thing_arrive_msg object_port_msg" owner: HACKER
    "Expand a public teleport message and prefix the player name when it is absent.";
    let msg = this.(verb);
    if (!msg)
      msg = $default_player.(verb);
    endif
    if (length(args) >= 3)
      msg = this:msg_sub(msg, @args);
    endif
    if (!$string_utils:index_delimited(msg, player.name))
      msg = player.name + " " + msg;
    endif
    return msg;
  endmethod

  method msg_sub owner: HACKER
    "Expand source/destination room names and pronouns in a teleport message.";
    const {original, thing, source, destination} = args;
    const rooms = $string_utils:pronoun_quote({{"%<from room>", valid(source) ? source.name | "Nowhere"}, {"%<to room>", valid(destination) ? destination.name | "Nowhere"}});
    return $string_utils:pronoun_sub($string_utils:substitute(original, rooms), thing);
  endmethod

  method obvious_exits owner: HACKER
    "'obvious_exits()' - Return a list of common exit names which are obviously worth looking for in a room.";
    return {"n", "ne", "e", "se", "s", "sw", "w", "nw", "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest", "u", "d", "up", "down", "out", "exit", "leave", "enter"};
  endmethod

  method tell_ways owner: HACKER
    "Display the supplied exits and their aliases for @ways.";
    const exits = args[1];
    const descriptions = { exit.name + " (" + $string_utils:english_list(exit.aliases) + ")" for exit in (exits) };
    player:tell("Obvious exits: ", $string_utils:english_list(descriptions), ".");
  endmethod

  method tell_obj owner: HACKER
    "Return the name and number of an object, e.g. 'Root Class (#1)'.";
    const o = args[1];
    return (valid(o) ? o.name | "Nothing") + " (" + tostr(o) + ")";
  endmethod

  method parse_out_object owner: HACKER
    "Parse a leading or trailing object identifier or 'here'; return {name, object}, or 0.";
    "The room-list interface treats #0 as $nothing and fills an omitted name from the object.";
    const words = $string_utils:words(args[1]);
    words || return 0;
    const first = words[1];
    const last = words[$];
    let remaining;
    let object;
    if (first[1] == "#" || first == "here")
      remaining = words[2..$];
      object = first == "here" ? this.location | toobj(first);
    elseif (last[1] == "#" || last == "here")
      remaining = words[1..$ - 1];
      object = last == "here" ? this.location | toobj(last);
    else
      return 0;
    endif
    object == #0 && (object = $nothing);
    let name = $string_utils:from_list(remaining, " ");
    !name && (name = valid(object) ? object.name | "Nowhere");
    return {name, object};
  endmethod

  method enlist owner: HACKER
    "Return an existing list, wrap a truthy scalar, or return an empty list for a false value.";
    const value = args[1];
    value || return {};
    return typeof(value) == TYPE_LIST ? value | {value};
  endmethod

  verb "@spellm*essages @spellp*roperties" (any any any) owner: #2 flags: "rd"
    "@spellproperties <object>";
    "@spellmessages <object>";
    "Spell checks the string properties of an object, or the subset of said properties which are suffixed _msg, respectively.";
    set_task_perms(player);
    if (!dobjstr)
      player:notify(tostr("Usage: ", verb, " <object>"));
      return;
    endif
    const target = player:my_match_object(dobjstr);
    $command_utils:object_match_failed(target, dobjstr) && return;
    const all_props = $object_utils:all_properties(target);
    if (typeof(all_props) == TYPE_ERR)
      player:notify("Permission denied to read properties on that object.");
      return;
    endif
    let props = setremove({ tostr(property) for property in (all_props) }, "messages");
    if (verb[1..7] == "@spellm")
      let spell = {};
      for prop in (props)
        if (index(prop, "_msg") == length(prop) - 3 && index(prop, "_msg"))
          spell = {@spell, prop};
        endif
      endfor
      props = spell;
    endif
    if (props == {})
      player:notify(tostr("No ", verb[1..7] == "@spellm" ? "messages" | "properties", " found to spellcheck on ", target, "."));
      return;
    endif
    for data in (props)
      const dd = `target.(data) ! ANY';
      const text = typeof(dd) == TYPE_LIST ? dd | typeof(dd) == TYPE_STR ? {dd} | {};
      let linenumber = 0;
      for thisline in (text)
        $command_utils:suspend_if_needed(0);
        linenumber = linenumber + 1;
        if (typeof(thisline) == TYPE_STR)
          let i = $string_utils:strip_chars(thisline, "!@#$%^&*()_+1234567890={}[]<>?:;,./|\"~'");
          if (i)
            i = $string_utils:words(i);
            for ii in [1..length(i)]
              $command_utils:suspend_if_needed(0);
              if (!$spell:valid(i[ii]))
                let msg;
                const stem = rindex(i[ii], "s") == length(i[ii]) && $spell:valid(i[ii][1..$ - 1]) || rindex(i[ii], "'s") == length(i[ii]) - 1 && $spell:valid(i[ii][1..$ - 2]);
                if (stem)
                  msg = "Possible match: " + i[ii];
                else
                  msg = "Unknown word: " + i[ii];
                endif
                const foo = length(text) == 1 ? ": " | " (line " + tostr(linenumber) + "): ";
                player:notify(tostr(target, ".", data, foo, msg));
              endif
            endfor
          endif
        endif
      endfor
    endfor
    player:notify(tostr("Done spellchecking ", target, "."));
  endverb

  method at_players owner: HACKER
    "'at_players ()' - Return a list of players to be displayed by @at.";
    return connected_players();
  endmethod

  method do_at_all owner: HACKER
    "'do_at_all ()' - List where everyone is, sorted by popularity of location. This is called when you type '@at'.";
    let locations = {};
    let parties = {};
    let counts = {};
    for who in (this:at_players())
      const loc = who.location;
      const i = loc in locations;
      if (i)
        parties[i] = setadd(parties[i], who);
        counts[i] = counts[i] - 1;
      else
        locations = {@locations, loc};
        parties = {@parties, {who}};
        counts = {@counts, 0};
      endif
    endfor
    locations = $list_utils:sort(locations, counts);
    parties = $list_utils:sort(parties, counts);
    this:print_at_items(locations, parties);
  endmethod

  method do_at owner: HACKER
    "Display the connected players at a specified location.";
    const location = args[1];
    const party = { who for who in (this:at_players()) if who.location == location };
    this:print_at_items({location}, {party});
  endmethod

  method print_at_items owner: HACKER
    "'print_at_items (<locations>, <parties>)' - Print a list of locations and people, for @at. Override this if you want to make a change to @at's output that you can't make in :at_item.";
    const {locations, parties} = args;
    for i in [1..length(locations)]
      $command_utils:suspend_if_needed(0);
      player:tell_lines(this:at_item(locations[i], parties[i]));
    endfor
  endmethod

  method at_item owner: HACKER
    "Return one complete location/party line, or a deserted-location string; clients handle wrapping.";
    const {location, party} = args;
    const number = this.at_number ? $string_utils:right(tostr(location), 7) + " " | "";
    let room = $string_utils:left(valid(location) ? location.name | "[Nowhere]", this.at_room_width);
    length(room) > this.at_room_width && (room = room[1..this.at_room_width]);
    const prefix = number + room + " ";
    party || return prefix + " [deserted]";
    const names = { valid(who) ? who.name | "[Nobody]" for who in (party) };
    return {prefix + " " + $string_utils:from_list(names, " ")};
  endmethod

  method internal_at owner: HACKER
    "'internal_at (<argument string>)' - Perform the function of @at. The argument string is whatever the user typed after @at. This is factored out so that other verbs can call it.";
    const where = $string_utils:trim(args[1]);
    if (!where)
      this:do_at_all();
      return;
    endif
    let result;
    if (where[1] == "#")
      result = toobj(where);
      if (!valid(result) && result != #-1)
        player:tell("That object does not exist.");
        return;
      endif
    else
      result = this:lookup_room(where);
      if (!valid(result))
        result = $string_utils:match_player(where);
        if (!valid(result))
          player:tell("That is neither a player nor a room name.");
          return;
        endif
      endif
    endif
    if (valid(result) && !$object_utils:isa(result, $room))
      result = result.location;
    endif
    this:do_at(result);
  endmethod

  method confunc owner: #2
    "Run inherited connection handling and installed-feature hooks for authorized callers.";
    "There is no extra commit between features; custom hooks can still suspend.";
    const principal = caller_perms();
    valid(principal) && caller != this && !$perm_utils:controls(principal, this) && return E_PERM;
    pass(@args);
    set_task_perms(this);
    for feature in (this.features)
      if (!valid(feature) || !(feature in this.features))
        continue;
      endif
      try
        feature:player_connected(player, @args);
      except (E_VERBNF)
        continue;
      except error (ANY)
        server_log(tostr("Feature connection hook for ", this, " on ", feature, " failed: ", error[1]));
        player:tell("Feature initialization failure for ", feature, ": ", error[2], ".");
      endtry
    endfor
  endmethod

  method disfunc owner: #2
    "Run inherited disconnect cleanup, then schedule installed-feature hooks with player authority.";
    "The fork commits completed cleanup before callbacks; the child reads current feature membership.";
    const principal = caller_perms();
    valid(principal) && caller != this && !$perm_utils:controls(principal, this) && return E_PERM;
    pass(@args);
    set_task_perms(this);
    fork (max(0, $login:current_lag()))
      valid(this) || return;
      for feature in (this.features)
        if (!valid(feature) || !(feature in this.features))
          continue;
        endif
        try
          feature:player_disconnected(player, @args);
        except (E_VERBNF)
          continue;
        except error (ANY)
          server_log(tostr("Feature disconnect hook for ", this, " on ", feature, " failed: ", error[1]));
        endtry
      endfor
    endfork
  endmethod

  verb "@addword @adddict" (any any any) owner: #2 flags: "rd"
    "Usage: @addword or @adddict <words, property, or verb>. Add personal words or submit dictionary changes.";
    set_task_perms(player);
    if (verb == "@adddict" && !(player in $spell.trusted || player.wizard))
      player:tell("You may not add to the master dictionary. The following words will instead by put in a list of words to be approved for later addition to the dictionary. Thanks for your contribution.");
    endif
    if (!argstr)
      player:notify(tostr("Usage: ", verb, " one or more words"));
      player:notify(tostr("       ", verb, " object:verb"));
      player:notify(tostr("       ", verb, " object.prop"));
      return;
    endif
    if (!$perm_utils:controls(player, player))
      player:notify("Cannot modify dictionary on players who do not own themselves.");
      return;
    endif
    const data = $spell:get_input(argstr);
    !data && return;
    let num_learned = 0;
    for i in [1..length(data)]
      const line = $string_utils:words(data[i]);
      for ii in [1..length(line)]
        $command_utils:suspend_if_needed(0);
        if (verb == "@adddict")
          const result = $spell:add_word(line[ii]);
          if (result == E_PERM)
            if ($spell:find_exact(line[ii]) == $failed_match)
              player:notify(tostr("Submitted for approval:  ", line[ii]));
              $spell:submit(line[ii]);
            else
              player:notify(tostr("Already in dictionary:  " + line[ii]));
            endif
          elseif (typeof(result) == TYPE_ERR)
            player:notify(tostr(result));
          elseif (result)
            player:notify(tostr("Word added:  ", line[ii]));
            num_learned = num_learned + 1;
          else
            player:notify(tostr("Already in dictionary:  " + line[ii]));
          endif
        elseif (!$spell:valid(line[ii]))
          player.dict = listappend(player.dict, line[ii]);
          player:notify(tostr("Word added:  ", line[ii]));
          num_learned = num_learned + 1;
        endif
      endfor
    endfor
    player:notify(tostr(num_learned ? num_learned | "No", " word", num_learned != 1 ? "s " | " ", "added to ", verb == "@adddict" ? "main " | "personal ", "dictionary."));
  endverb

  verb "@spell @cspell @complete" (any any any) owner: #2 flags: "rd"
    "Usage: @spell <input>, @cspell <input>, or @complete <prefix>. Check spelling or list completions.";
    set_task_perms(player);
    if (!argstr)
      if (verb == "@complete")
        player:notify(tostr("Usage: ", verb, " word-prefix"));
      else
        player:notify(tostr("Usage: ", verb, " object.property"));
        player:notify(tostr("       ", verb, " object:verb"));
        player:notify(tostr("       ", verb, " one or more words"));
      endif
      return;
    endif
    if (verb == "@complete")
      const foo = $string_utils:from_list($spell:sort($spell:find_all(argstr)), " ");
      if (foo == "")
        player:notify(tostr("No words found that begin with `", argstr, "'"));
      else
        player:notify(tostr(foo));
      endif
      return;
    endif
    let corrected_words = {};
    const data = $spell:get_input(argstr);
    if (data)
      let misspelling = 0;
      for i in [1..length(data)]
        const line = $string_utils:words(data[i]);
        for ii in [1..length(line)]
          $command_utils:suspend_if_needed(0);
          if (!$spell:valid(line[ii]))
            let msg;
            const stem = rindex(line[ii], "s") == length(line[ii]) && $spell:valid(line[ii][1..$ - 1]) || rindex(line[ii], "'s") == length(line[ii]) - 1 && $spell:valid(line[ii][1..$ - 2]);
            if (stem)
              msg = "Possible match: " + line[ii];
              msg = msg + " " + (length(data) != 1 ? "(line " + tostr(i) + ")  " | "  ");
            else
              misspelling = misspelling + 1;
              msg = "Unknown word: " + line[ii] + (length(data) != 1 ? " (line " + tostr(i) + ")  " | "  ");
              if (verb == "@cspell" && !(line[ii] in corrected_words))
                corrected_words = listappend(corrected_words, line[ii]);
                const guesses = $string_utils:from_list($spell:guess_words(line[ii]), " ");
                if (guesses == "")
                  msg = msg + "-No guesses";
                else
                  msg = msg + "-Possible correct spelling";
                  msg = msg + (index(guesses, " ") ? "s: " | ": ");
                  msg = msg + guesses;
                endif
              endif
            endif
            player:notify(tostr(msg));
          endif
        endfor
      endfor
      player:notify(tostr("Found ", misspelling ? misspelling | "no", " misspelled word", misspelling == 1 ? "." | "s."));
    elseif (data != $failed_match)
      player:notify(tostr("Nothing found to spellcheck!"));
    endif
  endverb

  verb "@rmword" (any any any) owner: #2 flags: "rd"
    "Usage: @rmword <word>. Remove a word from your personal dictionary.";
    set_task_perms(player);
    if (argstr in player.dict)
      player.dict = setremove(player.dict, argstr);
      player:notify(tostr("`", argstr, "' removed from personal dictionary."));
    else
      player:notify(tostr("`", argstr, "' not found in personal dictionary."));
    endif
  endverb

  verb "@rmdict" (any any any) owner: #2 flags: "rd"
    "Usage: @rmdict <word>. Remove a master word when the dictionary permits it.";
    set_task_perms(player);
    const result = $spell:remove_word(argstr);
    if (result == E_PERM)
      player:notify("You may not remove words from the main dictionary. Use `@rmword' to remove words from your personal dictionary.");
    elseif (typeof(result) == TYPE_ERR)
      player:notify(tostr(result));
    elseif (result)
      player:notify(tostr("`", argstr, "' removed."));
    else
      player:notify(tostr("`", argstr, "' not found in dictionary."));
    endif
  endverb

  method find_property owner: HACKER
    "Report property providers in lookup order, removing duplicate objects while preserving their first occurrence.";
    const name = args[1];
    let results = "";
    const objects = $list_utils:remove_duplicates(this:find_properties_on());
    for thing in (objects)
      if (!valid(thing))
        continue;
      endif
      if (!$object_utils:has_property(thing, name))
        continue;
      endif
      results = results + "   " + thing.name + "(" + tostr(thing) + ")";
      const mom = this:property_inherited_from(thing, name);
      if (thing != mom)
        if (valid(mom))
          results = results + "--" + mom.name + "(" + tostr(mom) + ")";
        else
          results = results + "--built-in";
        endif
      endif
    endfor
    if (results)
      this:tell("The property .", name, " is on", results);
      return;
    endif
    this:tell("The property .", name, " is nowhere to be found.");
  endmethod

  method find_verbs_on owner: HACKER
    "Return ordered verb-search objects: self, location, nearby objects, inventory, and features.";
    return {this, this.location, @valid(this.location) ? this.location:contents() | {}, @this:contents(), @this.features};
  endmethod

  method find_properties_on owner: HACKER
    "Return ordered property-search objects: self, location, nearby objects, and inventory.";
    return {this, this.location, @valid(this.location) ? this.location:contents() | {}, @this:contents()};
  endmethod

  method property_inherited_from owner: HACKER
    "Return the defining ancestor, $nothing for a builtin property, or 0 when absent.";
    const what = args[1];
    const prop = args[2];
    !$object_utils:has_property(what, prop) && return 0;
    prop in $code_utils.builtin_props && return $nothing;
    let ancestor = what;
    while ($object_utils:has_property(parent(ancestor), prop))
      ancestor = parent(ancestor);
    endwhile
    return ancestor;
  endmethod

  method last_huh owner: #2
    "Handle message-authoring shortcuts and explicit-object utility commands.";
    set_task_perms(caller_perms());
    if (args[1][1] == "@" && prepstr == "is")
      const {command, command_args} = args;
      set_task_perms(player);
      $last_huh:(command)(@command_args);
      return true;
    endif
    pass(@args) && return 1;
    const cmd_verb = args[1];
    const cmd_args = args[2];
    const dobjo = $string_utils:literal_object(dobjstr);
    if (valid(dobjo))
      const r = $match_utils:match_verb(cmd_verb, dobjo, cmd_args);
      r && return r;
    endif
    const iobjo = $string_utils:literal_object(iobjstr);
    valid(iobjo) && return $match_utils:match_verb(cmd_verb, iobjo, cmd_args);
    return 0;
  endmethod

  method ping_features owner: #2
    "Remove invalid feature references and return the remaining installed features.";
    return this.features = { feature for feature in (this.features) if $recycler:valid(feature) };
  endmethod

  method set_owned_objects owner: #2
    "Reorder this player's owned-object list without changing its members; require player/controller authority.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const reordered = args[1];
    let remaining = this.owned_objects;
    length(reordered) == length(remaining) || return E_INVARG;
    for object in (reordered)
      remaining = setremove(remaining, object);
    endfor
    remaining && return E_INVARG;
    return this.owned_objects = reordered;
  endmethod

  method init_for_core owner: #2
    "Reset personal room names during wizard-authorized core extraction.";
    caller_perms().wizard || return;
    pass(@args);
    if ($code_utils:verb_location() == this)
      this.rooms = {};
    else
      clear_property(this, "rooms");
    endif
  endmethod

  method find_help owner: HACKER
    "'find_help (<name>[, databases])'";
    "Search for a help topic with the given name. [<databases>] defaults to the ones returned by $code_utils:help_db_list().";
    const {name, ?databases = $code_utils:help_db_list()} = args;
    if (!name)
      this:tell_current("What topic do you want to search for?");
      return;
    endif
    const result = $code_utils:help_db_search(name, databases);
    if (!result)
      this:tell_current("The help topic \"", name, "\" could not be found.");
      return;
    endif
    const object = result[1];
    const realname = result[2];
    if (object == $ambiguous_match)
      this:tell_current("The help topic \"", name, "\" could refer to any of the following:  ", $string_utils:english_list(realname));
      return;
    endif
    if (object == $help && !$object_utils:has_property(object, realname))
      const o = $string_utils:match_object(name, player.location);
      if (valid(o))
        if ($object_utils:has_callable_verb(o, "help_msg"))
          this:tell_current("That help topic was returned by ", $string_utils:nn(o), ":help_msg().");
        elseif ($object_utils:has_property(o, "help_msg"))
          this:tell_current("That help topic is located in ", $string_utils:nn(o), ".help_msg.");
        else
          this:tell_current("That help topic was matched by $help but there doesn't seem to be any help available for it.");
        endif
        return;
      endif
    endif
    if (object == $verb_help)
      let what = $code_utils:parse_verbref(realname);
      if (what)
        what[1] = $string_utils:match_object(what[1], player.location);
      endif
      if (what && valid(what[1]) && $object_utils:has_verb(@what))
        this:tell_current("That help topic is located at the beginning of the verb ", $string_utils:nn(what[1]), ":", what[2], ".");
      else
        this:tell_current("That help topic was matched by $verb_help but there doesn't seem to be any help available for it.");
      endif
      return;
    endif
    let where = {};
    for x in (databases)
      if ({realname} == x:find_topics(realname))
        where = setadd(where, x);
      endif
    endfor
    const asname = name == realname ? "" | " as \"" + realname + "\"";
    if (where)
      this:tell_current("That help topic is located on ", $string_utils:nn(where), asname, ".");
      return;
    endif
    this:tell_current("That help topic appears to be located on ", $string_utils:nn(object), asname, ", although this command could not find it.");
  endmethod

  verb "@addsubmitted @rmsubmitted @submitted" (none none none) owner: HACKER flags: "rd"
    "Usage: @submitted, @addsubmitted, or @rmsubmitted. Review pending dictionary words as a trusted user.";
    "Each input read commits. Recheck authority after input and mutate only current, reviewed entries.";
    if (!(player in $spell.trusted || player.wizard))
      return player:tell("You may not process submissions to the master dictionary.");
    endif
    fn check_access()
      player in $spell.trusted || player.wizard || raise(E_PERM);
      return true;
    endfn
    fn remove_pending(word)
      player in $spell.trusted || player.wizard || raise(E_PERM);
      $spell.submitted = setremove($spell.submitted, word);
      return true;
    endfn
    $spell.submitted = $list_utils:remove_duplicates($spell.submitted);
    const pending = $spell.submitted;
    pending || return player:notify("No submissions to the global spelling dictionary are pending.");
    const operation = verb[2..index(verb, "submitted") - 1];
    if (!operation)
      player:notify(tostr("The following ", length(pending), " words have been submitted to the master dictionary and await approval:"));
      return player:notify_lines($list_utils:sort(pending));
    endif
    try
      if (operation == "rm")
        player:tell("Which word do you want removed from the submission list?");
        const word = $command_utils:read();
        check_access();
        if (word in $spell.submitted)
          remove_pending(word);
          player:notify(tostr("The word `", word, "' was rejected from the submission list."));
        else
          player:notify(tostr("The word `", word, "' was not found in the submission list."));
        endif
        return;
      endif
      operation == "add" || return;
      player:notify(tostr("A total of ", length(pending), " words have been submitted to the master dictionary and await approval."));
      const review = $command_utils:yes_or_no("Do you wish to review the list first?");
      check_access();
      if (review)
        return player:notify_lines($list_utils:sort(pending));
      endif
      let learned = 0;
      let skipped = 0;
      let errors = 0;
      let rejected = 0;
      const individually = $command_utils:yes_or_no("Do you wish to process each word individually? Recommended, but may take a couple minutes.");
      check_access();
      if (individually)
        for candidate in (pending)
          if (!(candidate in $spell.submitted))
            continue;
          endif
          const approved = $command_utils:yes_or_no(tostr("Submitted: `", candidate, "'. Add this word?"));
          check_access();
          if (!(candidate in $spell.submitted))
            player:notify(tostr("The word `", candidate, "' is no longer pending."));
            continue;
          endif
          if (!approved)
            skipped = skipped + 1;
            player:notify(tostr("The word `", candidate, "' was skipped."));
          else
            const result = $spell:add_word(candidate);
            result == E_PERM && raise(E_PERM);
            if (typeof(result) == TYPE_ERR)
              errors = errors + 1;
              player:notify(tostr(result));
            elseif (result)
              player:notify(tostr("Word added: ", candidate));
              learned = learned + 1;
              remove_pending(candidate);
            else
              player:notify(tostr("Already in dictionary: ", candidate));
              rejected = rejected + 1;
              remove_pending(candidate);
            endif
          endif
          const remove = $command_utils:yes_or_no(tostr("Remove `", candidate, "' from the submission list?"));
          check_access();
          if (remove)
            remove_pending(candidate);
            player:notify(tostr("The word `", candidate, "' has been removed."));
          endif
          const keep_going = $command_utils:yes_or_no("Continue on to the next word?");
          check_access();
          if (!keep_going)
            return player:notify_lines({"Command aborted.", tostr(" ", learned, " words added"), tostr(" ", skipped, " words skipped"), tostr(" ", errors, " words errored"), tostr(" ", rejected, " words rejected")});
          endif
        endfor
        return player:notify_lines({"End of submissions.", tostr(" ", learned, " words added"), tostr(" ", skipped, " words skipped"), tostr(" ", errors, " words errored"), tostr(" ", rejected, " words rejected")});
      endif
      const cancel = $command_utils:yes_or_no("Last chance. Do you wish to cancel?");
      check_access();
      if (cancel)
        return player:notify(tostr("Command cancelled. ", $mail_agent.moo_name, "'s lexicographers thank you."));
      endif
      for candidate in (pending)
        $command_utils:suspend_if_needed(0);
        check_access();
        if (!(candidate in $spell.submitted))
          continue;
        endif
        const result = $spell:add_word(candidate);
        result == E_PERM && raise(E_PERM);
        if (result)
          learned = learned + 1;
          player:notify(tostr("Word added: ", candidate));
        else
          errors = errors + 1;
          player:notify(tostr(result));
          player:notify(tostr("The word `", candidate, "' was not added."));
        endif
      endfor
      player:notify_lines({"End of submissions.", tostr(" ", learned, " words added"), tostr(" ", errors, " words errored"), ""});
      const clear = $command_utils:yes_or_no("Clear the reviewed submissions?");
      check_access();
      if (clear)
        for candidate in (pending)
          remove_pending(candidate);
        endfor
        player:notify("Reviewed submissions cleared.");
      else
        player:notify("List unchanged. Please review and prune the submission list manually.");
      endif
    except (E_PERM)
      player:notify("Permissions error. Command cancelled.");
    endtry
  endverb

  verb "@features" (any for any) owner: #2 flags: "rxd"
    "Usage: @features [<name>] for <player>. List matching installed features and remove stale entries.";
    if (!iobjstr)
      player:tell("Usage: @features [<name>] for <player>");
      return;
    endif
    const whose = $string_utils:match_player(iobjstr);
    $command_utils:player_match_failed(whose, iobjstr) && return;
    let features = {};
    for feature in (whose.features)
      if (!valid(feature))
        whose:remove_feature(feature);
        continue;
      endif
      if (!dobjstr || dobjstr in feature.aliases)
        features = {@features, feature};
        continue;
      endif
      const prefix = $string_utils:find_prefix(dobjstr, feature.aliases);
      if (prefix || prefix == $ambiguous_match)
        features = {@features, feature};
      endif
    endfor
    if (!features)
      if (dobjstr)
        player:tell("No features found on ", whose.name, " (", whose, ") matching \"", dobjstr, "\".");
      else
        player:tell("No features found on ", whose.name, " (", whose, ").");
      endif
      return;
    endif
    const width = max(length("Feature"), @{ length(tostr(item)) for item in (features) }) + 1;
    player:tell($string_utils:left("Feature", width), "Name");
    player:tell($string_utils:left("-------", width), "----");
    for feature in (features)
      player:tell($string_utils:left(tostr(feature), width), feature.name);
    endfor
    player:tell($string_utils:left("-------", width), "----");
    let summary = tostr(length(features), " feature", length(features) > 1 ? "s" | "", " found");
    if (whose != this)
      summary = summary + tostr(" on ", whose.name, " (", whose, ")");
    endif
    if (dobjstr)
      summary = summary + " matching \"" + dobjstr + "\"";
    endif
    player:tell(summary, ".");
  endverb

  verb "@features" (any none none) owner: #2 flags: "rd"
    "Usage:  @features [<name>]";
    "List the feature objects matching <name> used by player.";
    iobjstr = player.name;
    iobj = player;
    this:("@features")();
  endverb

  verb "@ch*eck-full" (any any any) owner: #2 flags: "rd"
    "Usage: @check [count] or @check-full <text or count>. Inspect recorded output attribution.";
    const responsible = $paranoid_db:get_data(this);
    if (length(verb) <= 6)
      let n = 5;
      let trust = {this, $no_one};
      let mistrust = {};
      for k in (args)
        const z = $code_utils:toint(k);
        if (z)
          n = z;
        elseif (k[1] == "!")
          mistrust = listappend(mistrust, $string_utils:match_player(k[2..$]));
        else
          trust = listappend(trust, $string_utils:match_player(k));
        endif
      endfor
      const count = length(responsible);
      for q in (n > count ? responsible | responsible[count - n + 1..count])
        let msg = tostr(@q[2]);
        const s = this:whodunnit(q[1], trust, mistrust);
        const text = valid(s[1]) ? s[1].name | "** NONE **";
        this:notify(tostr($string_utils:left(tostr(length(text) > 13 ? text[1..13] | text, " (", s[1], ")"), 20), $string_utils:left(s[2], 15), $string_utils:left(tostr(length(s[3].name) > 13 ? s[3].name[1..13] | s[3].name, " (", s[3], ")"), 20), msg));
      endfor
      this:notify("*** finished ***");
    else
      let matches = {};
      const match_text = argstr;
      if (length(match_text) == 0)
        player:notify(tostr("Usage: ", verb, " <string> --or-- ", verb, " <number>"));
        return;
      endif
      if (!responsible)
        player:notify("No text has been saved by the monitor.  (See `help @paranoid').");
      else
        const x = $code_utils:toint(argstr);
        if (typeof(x) == TYPE_ERR)
          for line in (responsible)
            if (index(tostr(@line[$]), argstr))
              matches = {@matches, line};
            endif
          endfor
        else
          matches = responsible[$ - min(x, $) + 1..$];
        endif
        if (matches)
          for match in (matches)
            $command_utils:suspend_if_needed(3);
            const text = tostr(@match[$]);
            player:notify("Traceback for:");
            player:notify(text);
            $code_utils:display_callers(listdelete(match[1], length(match[1])));
          endfor
          player:notify("**** finished ****");
        else
          player:notify(tostr("No matches for \"", argstr, "\" found."));
        endif
      endif
    endif
  endverb

  verb "@paranoid" (any any any) owner: #2 flags: "rd"
    "Usage: @paranoid [line-count | immediate | off]. Configure caller attribution for received output.";
    const mode = args ? args[1] | "";
    if (!mode)
      $paranoid_db:set_kept_lines(this, 10);
      this.paranoid = 1;
      return this:notify("Anti-spoofer on and keeping 10 lines.");
    endif
    if (index("immediate", mode))
      $paranoid_db:set_kept_lines(this, 0);
      this.paranoid = 2;
      return this:notify("Anti-spoofer now in immediate mode.");
    endif
    if (index("off", mode) || mode == "0")
      this.paranoid = 0;
      $paranoid_db:set_kept_lines(this, 0);
      return this:notify("Anti-spoofer off.");
    endif
    const count = toint(mode);
    if (tostr(count) != mode || count < 0)
      this:notify(tostr("Usage: ", verb, " <lines to be kept>     to turn on your anti-spoofer."));
      this:notify(tostr("       ", verb, " off                    to turn it off."));
      return this:notify(tostr("       ", verb, " immediate              to use immediate mode."));
    endif
    this.paranoid = 1;
    const kept = $paranoid_db:set_kept_lines(this, count);
    this:notify(tostr("Anti-spoofer on and keeping ", kept, " lines."));
  endverb

  verb "@sw*eep" (none none none) owner: #2 flags: "rd"
    "Usage: @sweep. Report listeners and non-wizard authors of room communication hooks.";
    let found_listener = false;
    const room = this.location;
    for thing in (setremove(room.contents, this))
      const tell_location = $object_utils:has_verb(thing, "tell");
      const notify_location = $object_utils:has_verb(thing, "notify");
      if (thing in connected_players())
        this:notify(tostr(thing.name, " (", thing, ") is listening."));
        found_listener = true;
        continue;
      endif
      if ($object_utils:has_callable_verb(thing, "sweep_msg"))
        const message = thing:sweep_msg();
        if (typeof(message) == TYPE_STR)
          this:notify(tostr(thing.name, " (", thing, ") ", message, "."));
          found_listener = true;
          continue;
        endif
      endif
      for definition in ({{tell_location, "tell"}, {notify_location, "notify"}})
        if (!definition[1])
          continue;
        endif
        const author = verb_info(definition[1][1], definition[2])[1];
        if (author != this && !author.wizard)
          this:notify(tostr(thing.name, " (", thing, ") has been taught to listen by ", author.name, " (", author, ")"));
          found_listener = true;
          break;
        endif
      endfor
    endfor
    let authors = {};
    for command in ({"announce", "announce_all", "announce_all_but", "say", "emote", "huh", "here_huh", "huh2", "whisper", "here_explain_syntax"})
      const definition = $object_utils:has_verb(room, command);
      if (definition)
        const author = verb_info(definition[1], command)[1];
        author != this && !author.wizard && (authors = setadd(authors, author));
      endif
    endfor
    if (!authors)
      !found_listener && this:notify("Communications look secure.");
      return;
    endif
    if ($object_utils:has_verb(room, "sweep_msg"))
      const message = room:sweep_msg();
      if (typeof(message) == TYPE_STR)
        return this:notify(tostr(room.name, " (", room, ") ", message, "."));
      endif
    endif
    this:notify(tostr(room.name, " (", room, ") may have been bugged by ", $string_utils:english_list($list_utils:map_prop(authors, "name")), "."));
  endverb

  verb "@eject @eject! @eject!!" (any from any) owner: #2 flags: "rd"
    "Usage: @eject <object> from <container>. Require container ownership and protect wizards.";
    set_task_perms(player);
    if (iobjstr == "here")
      iobj = player.location;
    elseif (iobjstr == "me")
      iobj = player;
    elseif ($command_utils:object_match_failed(iobj, iobjstr))
      return;
    endif
    if (!$perm_utils:controls(player, iobj))
      player:notify(tostr("You are not the owner of ", iobj.name, "."));
      return;
    endif
    if (dobjstr == "me")
      dobj = player;
    else
      dobj = $string_utils:literal_object(dobjstr);
      if (dobj == $failed_match)
        dobj = iobj:match(dobjstr);
        $command_utils:object_match_failed(dobj, dobjstr) && return;
      endif
    endif
    if (dobj.location != iobj)
      player:notify(tostr(dobj.name, "(", dobj, ") is not in ", iobj.name, "(", iobj, ")."));
      return;
    endif
    if (dobj.wizard)
      player:notify(tostr("Sorry, you can't ", verb, " a wizard."));
      dobj:tell(player.name, " tried to ", verb, " you.");
      return;
    endif
    iobj:(verb == "@eject" ? "eject" | "eject_basic")(dobj);
    player:notify($object_utils:has_callable_verb(iobj, "ejection_msg") ? iobj:ejection_msg() | $room:ejection_msg());
    if (verb != "@eject!!")
      dobj:tell($object_utils:has_callable_verb(iobj, "victim_ejection_msg") ? iobj:victim_ejection_msg() | $room:victim_ejection_msg());
    endif
    iobj:announce_all_but({player, dobj}, $object_utils:has_callable_verb(iobj, "oejection_msg") ? iobj:oejection_msg() | $room:oejection_msg());
  endverb

  verb "@rename*#" (any at any) owner: #2 flags: "rd"
    "Usage: @rename <object, property, or verb> to <name>. Apply changes with player authority.";
    player == caller && player == this || return;
    set_task_perms(player);
    const by_number = verb == "@rename#";
    const verb_spec = $code_utils:parse_verbref(dobjstr);
    if (verb_spec)
      player.programmer || return player:notify(tostr(E_PERM));
      const object = this:my_match_object(verb_spec[1]);
      $command_utils:object_match_failed(object, verb_spec[1]) && return;
      let name = verb_spec[2];
      if (by_number)
        name = $code_utils:toint(name);
        name == E_TYPE && return player:notify("Verb number expected.");
        if (name < 1 || `name > length(verbs(object)) ! E_PERM => false')
          return player:notify("Verb number out of range.");
        endif
      endif
      try
        const info = verb_info(object, name);
        try
          set_verb_info(object, name, listset(info, iobjstr, 3));
          player:notify("Verb name changed.");
        except error (ANY)
          player:notify(error[2]);
        endtry
      except (E_VERBNF)
        player:notify("That object does not define that verb.");
      except error (ANY)
        player:notify(error[2]);
      endtry
      return;
    endif
    by_number && return player:notify("@rename# can only be used with verbs.");
    const property_spec = $code_utils:parse_propref(dobjstr);
    if (property_spec)
      player.programmer || return player:notify(tostr(E_PERM));
      const object = this:my_match_object(property_spec[1]);
      $command_utils:object_match_failed(object, property_spec[1]) && return;
      const name = property_spec[2];
      try
        const info = property_info(object, name);
        try
          set_property_info(object, name, {@info, iobjstr});
          player:notify("Property name changed.");
        except error (ANY)
          player:notify(error[2]);
        endtry
      except (E_PROPNF)
        player:notify("That object does not define that property.");
      except error (ANY)
        player:notify(error[2]);
      endtry
      return;
    endif
    const object = this:my_match_object(dobjstr);
    $command_utils:object_match_failed(object, dobjstr) && return;
    const old_name = object.name;
    const old_aliases = object.aliases;
    const result = $building_utils:set_names(object, iobjstr);
    if (result)
      const name_message = strcmp(object.name, old_name) == 0 ? tostr("Name of ", object, " (", old_name, ") is unchanged") | tostr("Name of ", object, " changed to \"", object.name, "\"");
      const aliases = $string_utils:from_value(object.aliases, 1);
      const alias_message = object.aliases == old_aliases ? tostr(".  Aliases are unchanged (", aliases, ").") | tostr(", with aliases ", aliases, ".");
      return player:notify(name_message + alias_message);
    endif
    if (result == E_INVARG)
      player:notify("That particular name change not allowed (see help @rename).");
      object == player && player:notify($player_db:why_bad_name(player, iobjstr));
    elseif (result == E_NACC)
      player:notify("Oops.  You can't update that name right now; try again in a few minutes.");
    elseif (result == E_ARGS)
      player:notify(tostr("Sorry, name too long.  Maximum number of characters in a name:  ", $login.max_player_name));
    elseif (!result && typeof(result) != TYPE_ERR)
      player:notify("Name and aliases remain unchanged.");
    else
      player:notify(tostr(result));
    endif
  endverb

  verb "@addalias*# @add-alias*#" (any at any) owner: #2 flags: "rd"
    "Usage: @addalias <aliases> to <object or verb>. Add object aliases or programmer-owned verb names.";
    player == this || return;
    set_task_perms(player);
    const by_number = verb[$] == "#";
    const spec = $code_utils:parse_verbref(iobjstr);
    if (spec)
      player.programmer || return player:notify(tostr(E_PERM));
      const object = player:my_match_object(spec[1]);
      $command_utils:object_match_failed(object, spec[1]) && return;
      let name = spec[2];
      if (by_number)
        name = $code_utils:toint(name);
        name == E_TYPE && return player:notify("Verb number expected.");
        if (name < 1 || `name > length(verbs(object)) ! E_PERM => false')
          return player:notify("Verb number out of range.");
        endif
      endif
      try
        const info = verb_info(object, name);
        const old = $string_utils:explode(info[3]);
        const requested = $list_utils:remove_duplicates($string_utils:explode(strsub(dobjstr, ",", " ")));
        const used = { present_alias for present_alias in (requested) if present_alias in old };
        const added = { missing_alias for missing_alias in (requested) if !(missing_alias in old) };
        if (used)
          player:notify(tostr(object.name, "(", object, "):", name, " already has the alias", length(used) > 1 ? "es" | "", " ", $string_utils:english_list(used), "."));
        endif
        if (added)
          const aliases = $string_utils:from_list({@old, @added}, " ");
          try
            set_verb_info(object, name, listset(info, aliases, 3));
            player:notify(tostr("Alias", length(added) > 1 ? "es" | "", " ", $string_utils:english_list(added), " added to verb ", object.name, "(", object, "):", name));
            player:notify(tostr("Verbname is now ", object.name, "(", object, "):\"", aliases, "\""));
          except error (ANY)
            player:notify(error[2]);
          endtry
        elseif (!used)
          player:notify("Did not understand what aliases to add from value:  " + dobjstr);
        endif
      except (E_VERBNF)
        player:notify("That object does not define that verb.");
      except error (ANY)
        player:notify(error[2]);
      endtry
      return;
    endif
    by_number && return player:notify(tostr(verb, " can only be used with verbs."));
    const object = player:my_match_object(iobjstr);
    $command_utils:object_match_failed(object, iobjstr) && return;
    const old = object.aliases;
    let added = $list_utils:remove_duplicates($list_utils:map_arg($string_utils, "trim", $string_utils:explode(is_player(object) ? strsub(dobjstr, " ", ",") | dobjstr, ",")));
    let used = {};
    for alias in (added)
      if (alias in old)
        used = {@used, alias};
        added = setremove(added, alias);
      elseif (is_player(object))
        const someone = $player_db:find_exact(alias);
        if (valid(someone))
          player:notify(tostr(someone.name, "(", someone, ") is already using the alias ", alias, "."));
          added = setremove(added, alias);
        endif
      endif
    endfor
    if (used)
      player:notify(tostr(object.name, "(", object, ") already has the alias", length(used) > 1 ? "es" | "", " ", $string_utils:english_list(used), "."));
    endif
    added || return player:tell("No new aliases found to add.");
    const aliases = {@old, @added};
    const result = object:set_aliases(aliases);
    if (result && object.aliases == aliases)
      player:notify(tostr("Alias", length(added) > 1 ? "es" | "", " ", $string_utils:english_list(added), " added to ", object.name, "(", object, ")."));
      player:notify(tostr("Aliases for ", $string_utils:nn(object), " are now ", $string_utils:from_value(aliases, 1)));
    elseif (result)
      player:notify("That particular name change not allowed (see help @rename or help @addalias).");
    elseif (result == E_INVARG)
      if (!$object_utils:has_property(#0, "local"))
        player:notify("You are not allowed any more aliases.");
      elseif ($object_utils:has_property($local, "max_player_aliases"))
        player:notify("You are not allowed more than " + tostr($local.max_player_aliases) + " aliases.");
      endif
    elseif (result == E_NACC)
      player:notify("Oops.  You can't update that object's aliases right now; try again in a few minutes.");
    elseif (!result && typeof(result) != TYPE_ERR)
      player:notify("Aliases not changed as expected!");
      player:notify(tostr("Aliases for ", $string_utils:nn(object), " are now ", $string_utils:from_value(object.aliases, 1)));
    else
      player:notify(tostr(result));
    endif
  endverb

  verb "@rmalias*# @rm-alias*#" (any from any) owner: #2 flags: "rd"
    "Usage: @rmalias <aliases> from <object or verb>. Verb edits require a programmer and retain one name.";
    player == this || return;
    set_task_perms(player);
    const by_number = verb[$] == "#";
    const spec = $code_utils:parse_verbref(iobjstr);
    if (spec)
      player.programmer || return player:notify(tostr(E_PERM));
      const object = player:my_match_object(spec[1]);
      $command_utils:object_match_failed(object, spec[1]) && return;
      let name = spec[2];
      if (by_number)
        name = $code_utils:toint(name);
        name == E_TYPE && return player:notify("Verb number expected.");
        if (name < 1 || `name > length(verbs(object)) ! E_PERM => false')
          return player:notify("Verb number out of range.");
        endif
      endif
      try
        const info = verb_info(object, name);
        const old = $string_utils:explode(info[3]);
        const requested = $list_utils:remove_duplicates($string_utils:explode(strsub(dobjstr, ",", " ")));
        const absent = { missing_alias for missing_alias in (requested) if !(missing_alias in old) };
        const removed = { present_alias for present_alias in (requested) if present_alias in old };
        let remaining = old;
        for removed_alias in (removed)
          remaining = setremove(remaining, removed_alias);
        endfor
        if (absent)
          player:notify(tostr(object.name, "(", object, "):", name, " does not have the alias", length(absent) > 1 ? "es" | "", " ", $string_utils:english_list(absent), "."));
        endif
        if (removed && remaining)
          const aliases = $string_utils:from_list(remaining, " ");
          try
            set_verb_info(object, name, listset(info, aliases, 3));
            player:notify(tostr("Alias", length(removed) > 1 ? "es" | "", " ", $string_utils:english_list(removed), " removed from verb ", object.name, "(", object, "):", name));
            player:notify(tostr("Verbname is now ", object.name, "(", object, "):\"", aliases, "\""));
          except error (ANY)
            player:notify(error[2]);
          endtry
        elseif (!remaining)
          player:notify("You have to leave a verb with at least one alias.");
        else
          player:notify("No aliases removed.");
        endif
      except (E_VERBNF)
        player:notify("That object does not define that verb.");
      except error (ANY)
        player:notify(error[2]);
      endtry
      return;
    endif
    by_number && return player:notify(tostr(verb, " can only be used with verbs."));
    const object = player:my_match_object(iobjstr);
    $command_utils:object_match_failed(object, iobjstr) && return;
    const old = object.aliases;
    const requested = $list_utils:remove_duplicates($list_utils:map_arg($string_utils, "trim", $string_utils:explode(dobjstr, ",")));
    const absent = { missing_alias for missing_alias in (requested) if !(missing_alias in old) };
    const removed = { present_alias for present_alias in (requested) if present_alias in old };
    let remaining = old;
    for removed_alias in (removed)
      remaining = setremove(remaining, removed_alias);
    endfor
    if (absent)
      player:notify(tostr(object.name, "(", object, ") does not have the alias", length(absent) > 1 ? "es" | "", " ", $string_utils:english_list(absent), "."));
    endif
    removed || return player:notify("Aliases unchanged.");
    const result = object:set_aliases(remaining);
    if (result)
      player:notify(tostr("Alias", length(removed) > 1 ? "es" | "", " ", $string_utils:english_list(removed), " removed from ", object.name, "(", object, ")."));
      player:notify(tostr("Aliases for ", object.name, "(", object, ") are now ", $string_utils:from_value(remaining, 1)));
    elseif (result == E_INVARG)
      player:notify("That particular name change not allowed (see help @rename or help @rmalias).");
    elseif (result == E_NACC)
      player:notify("Oops.  You can't update that object's aliases right now; try again in a few minutes.");
    elseif (!result && typeof(result) != TYPE_ERR)
      player:notify("Aliases not changed as expected!");
      player:notify(tostr("Aliases for ", $string_utils:nn(object), " are ", $string_utils:from_value(object.aliases, 1)));
    else
      player:notify(tostr(result));
    endif
  endverb

  verb "@desc*ribe" (any as any) owner: #2 flags: "rd"
    "Usage: @describe <object> as <text>. Set a description with player authority.";
    set_task_perms(player);
    dobj = player:my_match_object(dobjstr);
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    const result = dobj:set_description(iobjstr);
    player:notify(result ? "Description set." | tostr(result));
  endverb

  verb "@mess*ages" (any none none) owner: #2 flags: "rd"
    "Usage: @messages <object>. List message properties and whether their values are readable.";
    set_task_perms(player);
    !dobjstr && return player:notify(tostr("Usage:  ", verb, " <object>"));
    dobj = player:my_match_object(dobjstr);
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    const properties = $object_utils:all_properties(dobj);
    typeof(properties) == TYPE_ERR && return player:notify("You can't read the messages on that.");
    let found = false;
    for property_name in (properties)
      const property = tostr(property_name);
      const size = length(property);
      if (size <= 4 || property[size - 3..$] != "_msg")
        continue;
      endif
      found = true;
      const message = `dobj.(property) ! ANY';
      let description;
      if (message == E_PERM)
        description = "isn't readable by you.";
      elseif (!message)
        description = "isn't set.";
      elseif (typeof(message) == TYPE_LIST)
        description = "is a list.";
      elseif (typeof(message) != TYPE_STR)
        description = "is corrupted! **";
      else
        description = "is " + $string_utils:print(message);
      endif
      player:notify(tostr("@", property[1..size - 4], " ", dobjstr, " ", description));
    endfor
    !found && player:notify("That object doesn't have any messages to set.");
  endverb

  verb "@notedit" (any none none) owner: #96 flags: "rd"
    "Usage: @notedit <note or property>. Invoke the note editor.";
    $note_editor:invoke(dobjstr, verb);
  endverb

  verb "@exam*ine" (any none none) owner: #2 flags: "rxd"
    "Usage: @examine <object>. Display ownership, description, contents, and obvious verb syntax.";
    if (dobjstr == "")
      player:notify(tostr("Usage:  ", verb, " <object>"));
      return;
    endif
    let what = $string_utils:match_object(dobjstr, player.location);
    $command_utils:object_match_failed(what, dobjstr) && return;
    player:notify(tostr(what.name, " (", what, ") is owned by ", valid(what.owner) ? what.owner.name | "a recycled player", " (", what.owner, ")."));
    player:notify(tostr("Aliases:  ", $string_utils:english_list(what.aliases)));
    const desc = what:description();
    if (desc)
      player:notify_lines(desc);
    else
      player:notify("(No description set.)");
    endif
    if ($perm_utils:controls(player, what))
      player:notify(tostr("Key:  ", $lock_utils:unparse_key(what.key)));
    endif
    const contents = what.contents;
    if (contents)
      player:notify("Contents:");
      for item in (contents)
        player:notify(tostr("  ", item.name, " (", item, ")"));
      endfor
    endif
    const name = dobjstr;
    let vrbs = {};
    const commands_ok = what in {player, player.location};
    const dull_classes = {$root_class, $room, $player, $prog};
    let printed_working_msg = false;
    "Each ancestor is scanned without a suspension between reading its verb count and its verbs.";
    while (valid(what))
      if ($command_utils:running_out_of_time())
        if (!printed_working_msg)
          player:notify("Working on list of obvious verbs...");
          printed_working_msg = true;
        endif
        suspend(0);
        if (!valid(what))
          break;
        endif
      endif
      if (!(what in dull_classes))
        for i in [1..length(verbs(what))]
          const info = verb_info(what, i);
          const syntax = verb_args(what, i);
          if (index(info[2], "r") && (syntax[2..3] != {"none", "this"} && (commands_ok || "this" in syntax)) && verb_code(what, i))
            let {direct, prep, indirect} = syntax;
            if (syntax == {"any", "any", "any"})
              prep = "none";
            endif
            if (prep != "none")
              for x in ($string_utils:explode(prep, "/"))
                if (length(x) <= length(prep))
                  prep = x;
                endif
              endfor
            endif
            let vname = info[3];
            while (true)
              const j = index(vname, "* ");
              if (!j)
                break;
              endif
              vname = tostr(vname[1..j - 1], "<anything>", vname[j + 1..$]);
            endwhile
            if (vname[$] == "*")
              vname = vname[1..$ - 1] + "<anything>";
            endif
            vname = strsub(vname, " ", "/");
            let rest = "";
            if (prep != "none")
              rest = " " + (prep == "any" ? "<anything>" | prep);
              if (indirect != "none")
                rest = tostr(rest, " ", indirect == "this" ? name | "<anything>");
              endif
            endif
            if (direct != "none")
              rest = tostr(" ", direct == "this" ? name | "<anything>", rest);
            endif
            vrbs = setadd(vrbs, "  " + vname + rest);
          endif
        endfor
      endif
      what = parent(what);
    endwhile
    if (vrbs)
      player:notify("Obvious Verbs:");
      player:notify_lines(vrbs);
      printed_working_msg && player:notify("(End of list.)");
    elseif (printed_working_msg)
      player:notify("No obvious verbs found.");
    endif
  endverb

  verb "@add-feature @addfeature" (any none none) owner: #2 flags: "rd"
    "Usage: @add-feature [<feature object>]. Install a feature, or list available warehouse features.";
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @add-feature <object>");
      const available = $feature.warehouse.contents;
      length(available) >= 20 && return;
      player:tell("Available features include:");
      player:tell("--------------------------");
      for feature in (available)
        const title = feature:title() + (feature in player.features ? " (*)" | "");
        player:tell("  " + title);
      endfor
      player:tell("--------------------------");
      player:tell("A * after the feature name means that you already have that feature.");
      return;
    endif
    if (dobj == $failed_match)
      dobj = $feature.warehouse:match_object(dobjstr);
    endif
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    if (dobj in player.features)
      player:tell(dobjstr, " is already one of your features.");
    elseif (player:add_feature(dobj))
      player:tell(dobj, " (", dobj.name, ") added as a feature.");
    else
      player:tell("You can't seem to add ", dobj, " (", dobj.name, ") to your features list.");
    endif
  endverb

  verb "@remove-feature @rmfeature" (any none none) owner: #2 flags: "rd"
    "Usage: @remove-feature <feature object>. Remove an installed feature, including remote features.";
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @remove-feature <object>");
      return;
    endif
    const features = player.features;
    if (!valid(dobj))
      dobj = $string_utils:match(dobjstr, features, "name", features, "aliases");
    endif
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    if (!(dobj in features))
      player:tell(dobjstr, " is not one of your features.");
      return;
    endif
    player:remove_feature(dobj);
    player:tell(dobj, " (", dobj.name, ") removed from your features list.");
  endverb

  verb "@set-note-string @set-note-text" (any none none) owner: #2 flags: "rd"
    "Usage: @set-note-{string | text} <object or property>, followed by lines and a final dot.";
    "Input commits before matching and writing the target with the player's current authority.";
    const active = player in $note_editor.active;
    const input = $command_utils:read_lines_escape(active ? {} | {"@edit"}, {tostr("Changing ", argstr, "."), @active ? {} | {"Type `@edit' to take this into the note editor."}});
    if (input && input[1] == "@edit")
      $note_editor:invoke(argstr, verb);
      const index = $note_editor:loaded(player);
      index && ($note_editor.texts[index] = input[2]);
      return;
    endif
    set_task_perms(player);
    let text = input[2];
    verb == "@set-note-string" && length(text) <= 1 && (text = text ? text[1] | "");
    const spec = $code_utils:parse_propref(argstr);
    if (spec)
      const object = player:my_match_object(spec[1]);
      const property = spec[2];
      const setter = "set_" + property;
      if ($object_utils:has_verb(object, setter))
        const result = object:(setter)(text);
        if (typeof(result) != TYPE_ERR)
          return player:tell("Set ", property, " property of ", object.name, " (", object, ") via :", setter, ".");
        endif
      endif
      const result = `object.(property) = text ! ANY';
      if (result != text)
        return player:tell("Error:  ", result);
      endif
      return player:tell("Set ", property, " property of ", object.name, " (", object, ").");
    endif
    const note = $code_utils:toobj(argstr);
    if (typeof(note) == TYPE_OBJ)
      const result = note:set_text(text);
      if (typeof(result) == TYPE_ERR)
        return player:tell("Error:  ", result);
      endif
      return player:tell("Set text of ", note.name, " (", note, ").");
    endif
    player:tell("Error:  Malformed argument to ", verb, ": ", argstr);
  endverb

  verb "@edit" (any any any) owner: HACKER flags: "rd"
    "Calls the verb editor on verbs, the note editor on properties, and on anything else assumes it's an object for which you want to edit the .description.";
    if (!args)
      (player in $note_editor.active ? $note_editor | $verb_editor):invoke(dobjstr, verb);
    elseif ($code_utils:parse_verbref(args[1]))
      if (player.programmer)
        $verb_editor:invoke(argstr, verb);
      else
        player:notify("You need to be a programmer to do this.");
        player:notify("If you want to become a programmer, talk to a wizard.");
        return;
      endif
    else
      $note_editor:invoke(dobjstr, verb);
    endif
  endverb

  verb "@move-new" (any any any) owner: #2 flags: "rd"
    "'@move <object> to <place>' - Teleport an object. Example: '@move trash to #11' to move trash to the closet.";
    let here;
    set_task_perms(caller == this ? this | $no_one);
    if (prepstr != "to" || !iobjstr)
      player:tell("Usage: @move <object> to <location>");
      return;
    endif
    if (!dobjstr || dobjstr == "me")
      dobj = this;
    else
      dobj = here:match_object(dobjstr);
      if (!valid(dobj))
        dobj = player:my_match_object(dobjstr);
      endif
    endif
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    iobj = this:lookup_room(iobjstr);
    iobj != $nothing && $command_utils:object_match_failed(iobj, iobjstr) && return;
    if (!player.programmer && !$perm_utils:controls(this, dobj) && this != dobj)
      player:tell("You may only @move your own things.");
      return;
    endif
    this:teleport(dobj, iobj);
  endverb

  verb "@exits" (none none none) owner: #2 flags: "rxd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!$perm_utils:controls(valid(caller_perms()) ? caller_perms() | player, room))
      player:tell("Sorry, only the owner of a room may list its exits.");
    elseif (room.exits == {})
      player:tell("This room has no conventional exits.");
    else
      try
        for exit in (room.exits)
          try
            player:tell(exit.name, " (", exit, ") leads to ", valid(exit.dest) ? exit.dest.name | "???", " (", exit.dest, ") via {", $string_utils:from_list(exit.aliases, ", "), "}.");
          except (ANY)
            player:tell("Bad exit or missing .dest property:  ", $string_utils:nn(exit));
            continue exit;
          endtry
        endfor
      except (E_TYPE)
        player:tell("Bad .exits property. This should be a list of exit objects. Please fix this.");
      endtry
    endif
  endverb

  verb "@entrances" (none none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!$perm_utils:controls(valid(caller_perms()) ? caller_perms() | player, room))
      player:tell("Sorry, only the owner of a room may list its entrances.");
    elseif (room.entrances == {})
      player:tell("This room has no conventional entrances.");
    else
      try
        for exit in (room.entrances)
          try
            player:tell(exit.name, " (", exit, ") comes from ", valid(exit.source) ? exit.source.name | "???", " (", exit.source, ") via {", $string_utils:from_list(exit.aliases, ", "), "}.");
          except (ANY)
            player:tell("Bad entrance object or missing .source property: ", $string_utils:nn(exit));
            continue exit;
          endtry
        endfor
      except (E_TYPE)
        player:tell("Bad .entrances property. This should be a list of exit objects. Please fix this.");
      endtry
    endif
  endverb

  verb "@add-exit" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @add-exit <exit-number>");
      return;
    endif
    const exit = room:match_object(dobjstr);
    $command_utils:object_match_failed(exit, dobjstr) && return;
    if (!($exit in $object_utils:ancestors(exit)))
      player:tell("That doesn't look like an exit object to me...");
      return;
    endif
    let dest;
    try
      dest = exit.dest;
    except (E_PERM)
      player:tell("You can't read the exit's destination to check that it's consistent!");
      return;
    endtry
    let source;
    try
      source = exit.source;
    except (E_PERM)
      player:tell("You can't read that exit's source to check that it's consistent!");
      return;
    endtry
    if (source == $nothing)
      player:tell("That exit's source has not yet been set; set it to be this room, then run @add-exit again.");
      return;
    endif
    if (source != room)
      player:tell("That exit wasn't made to be attached here; it was made as an exit from ", source.name, " (", source, ").");
      return;
    elseif (typeof(dest) != TYPE_OBJ || !valid(dest) || !($room in $object_utils:ancestors(dest)))
      player:tell("That exit doesn't lead to a room!");
      return;
    endif
    if (!room:add_exit(exit))
      player:tell("Sorry, but you must not have permission to add exits to this room.");
    else
      player:tell("You have added ", exit, " as an exit that goes to ", exit.dest.name, " (", exit.dest, ") via ", $string_utils:english_list(setadd(exit.aliases, exit.name)), ".");
    endif
  endverb

  verb "@add-entrance" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @add-entrance <exit-number>");
      return;
    endif
    const exit = room:match_object(dobjstr);
    $command_utils:object_match_failed(exit, dobjstr) && return;
    if (!($exit in $object_utils:ancestors(exit)))
      player:tell("That doesn't look like an exit object to me...");
      return;
    endif
    let dest;
    try
      dest = exit.dest;
    except (E_PERM)
      player:tell("You can't read the exit's destination to check that it's consistent!");
      return;
    endtry
    if (dest != room)
      player:tell("That exit doesn't lead here!");
      return;
    endif
    if (!room:add_entrance(exit))
      player:tell("Sorry, but you must not have permission to add entrances to this room.");
    else
      player:tell("You have added ", exit, " as an entrance that gets here via ", $string_utils:english_list(setadd(exit.aliases, exit.name)), ".");
    endif
  endverb

  verb "@eject @eject! @eject!!" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    if (dobj.location != room)
      const is = $gender_utils:get_conj("is", dobj);
      player:tell(dobj.name, "(", dobj, ") ", is, " not here.");
      return;
    elseif (!$perm_utils:controls(player, room))
      player:tell("You are not the owner of this room.");
      return;
    elseif (dobj.wizard)
      player:tell("Sorry, you can't ", verb, " a wizard.");
      dobj:tell(player.name, " tried to ", verb, " you.");
      return;
    endif
    iobj = room;
    player:tell(room:ejection_msg());
    room:(verb == "@eject" ? "eject" | "eject_basic")(dobj);
    if (verb != "@eject!!")
      dobj:tell(room:victim_ejection_msg());
    endif
    room:announce_all_but({player, dobj}, room:oejection_msg());
  endverb

  verb "@resident*s" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!$perm_utils:controls(player, room))
      player:tell("You must own this room to manipulate the legal residents list.  Try contacting ", room.owner.name, ".");
    else
      if (typeof(room.residents) != TYPE_LIST)
        room.residents = {room.residents};
      endif
      if (!dobjstr)
        "First, remove !valid objects from this room...";
        for x in (room.residents)
          if (typeof(x) != TYPE_OBJ || !$recycler:valid(x))
            player:tell("Warning: removing ", x, ", an invalid object, from the residents list.");
            room.residents = setremove(room.residents, x);
          endif
        endfor
        player:tell("Allowable residents in this room:  ", $string_utils:english_list($list_utils:map_prop(room.residents, "name"), "no one"), ".");
        return;
      endif
      const remove = dobjstr[1] == "!";
      remove && (dobjstr = dobjstr[2..$]);
      let result = $string_utils:match_player_or_object(dobjstr);
      if (!result)
        return;
      else
        "a one element list was returned to us if it won.";
        result = result[1];
        if (remove)
          if (!(result in room.residents))
            player:tell(result.name, " doesn't appear to be in the residents list of ", room.name, ".");
          else
            room.residents = setremove(room.residents, result);
            player:tell(result.name, " removed from the residents list of ", room.name, ".");
          endif
        else
          if (result in room.residents)
            const is = $gender_utils:get_conj("is", result);
            player:tell(result.name, " ", is, " already an allowed resident of ", room.name, ".");
          else
            room.residents = {@room.residents, result};
            player:tell(result.name, " added to the residents list of ", room.name, ".");
          endif
        endif
      endif
    endif
  endverb

  verb "@remove-exit" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @remove-exit <exit>");
      return;
    endif
    const exit = room:match_object(dobjstr);
    if (!(exit in room.exits))
      $command_utils:object_match_failed(exit, dobjstr) && return;
      player:tell("Couldn't find \"", dobjstr, "\" in the exits list of ", room.name, ".");
      return;
    endif
    if (!room:remove_exit(exit))
      player:tell("Sorry, but you do not have permission to remove exits from this room.");
    else
      const name = valid(exit) ? exit.name | "<recycled>";
      player:tell("Exit ", exit, " (", name, ") removed from exit list of ", room.name, " (", room, ").");
    endif
  endverb

  verb "@remove-entrance" (any none none) owner: #2 flags: "rd"
    "Apply this room-management command to the player's current room.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    const room = player.location;
    valid(room) && $object_utils:isa(room, $room) || return player:tell("You are not in a room.");
    set_task_perms(player);
    if (!dobjstr)
      player:tell("Usage:  @remove-entrance <entrance>");
      return;
    endif
    let entrance = $string_utils:match(dobjstr, room.entrances, "name", room.entrances, "aliases");
    if (!valid(entrance))
      "Try again to parse it.  Maybe they gave object number.  Don't complain if it's invalid though; maybe it's been recycled in some nefarious way.";
      entrance = room:match_object(dobjstr);
    endif
    if (!(entrance in room.entrances))
      player:tell("Couldn't find \"", dobjstr, "\" in the entrances list of ", room.name, ".");
      return;
    endif
    if (!room:remove_entrance(entrance))
      player:tell("Sorry, but you do not have permission to remove entrances from this room.");
    else
      const name = valid(entrance) ? entrance.name | "<recycled>";
      player:tell("Entrance ", entrance, " (", name, ") removed from entrance list of ", room.name, " (", room, ").");
    endif
  endverb

  verb "@lock_for_open @lock-for-open" (any with any) owner: #2 flags: "rd"
    "Apply this authoring command to the named container with player authority.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    const container = dobj;
    $object_utils:isa(container, $container) || return player:tell("That is not a container.");
    set_task_perms(player);
    const key = $lock_utils:parse_keyexp(iobjstr, player);
    if (typeof(key) == TYPE_STR)
      player:tell("That key expression is malformed:");
      player:tell("  ", key);
    else
      try
        container.open_key = key;
        player:tell("Locked opening of ", container.name, " with this key:");
        player:tell("  ", $lock_utils:unparse_key(key));
      except error (ANY)
        player:tell(error[2], ".");
      endtry
    endif
  endverb

  verb "@unlock_for_open @unlock-for-open" (any none none) owner: #2 flags: "rd"
    "Apply this authoring command to the named container with player authority.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    const container = dobj;
    $object_utils:isa(container, $container) || return player:tell("That is not a container.");
    set_task_perms(player);
    try
      dobj.open_key = 0;
      player:tell("Unlocked ", dobj.name, " for opening.");
    except error (ANY)
      player:tell(error[2], ".");
    endtry
  endverb

  verb "@opacity" (any is any) owner: #2 flags: "rd"
    "Apply this authoring command to the named container with player authority.";
    !valid(caller_perms()) || $perm_utils:controls(caller_perms(), player) || return E_PERM;
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    const container = dobj;
    $object_utils:isa(container, $container) || return player:tell("That is not a container.");
    set_task_perms(player);
    if (!$perm_utils:controls(player, container))
      player:tell("Can't set opacity of something you don't own.");
    elseif (iobjstr != "0" && !toint(iobjstr))
      player:tell("Opacity must be an integer (0, 1, 2).");
    else
      player:tell("Opacity changed:  Now " + {"transparent.", "opaque.", "a black hole."}[1 + container:set_opaque(toint(iobjstr))]);
    endif
  endverb

  verb "exam*ine" (any none none) owner: #2 flags: "rd"
    "Usage: examine <object>. Delegate structural examination with player authority.";
    set_task_perms(player);
    if (!dobjstr)
      player:notify(tostr("Usage:  ", verb, " <object>"));
      return E_INVARG;
    endif
    const what = player.location:match_object(dobjstr);
    $command_utils:object_match_failed(what, dobjstr) && return;
    what:do_examine(player);
  endverb
endobject
