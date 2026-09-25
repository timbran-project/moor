object ROOM [
  import_export_id -> "room"
]
  name: "generic room"
  parent: ROOT_CLASS
  owner: #2
  fertile: true
  readable: true

  property blessed_object (owner: #2, flags: "rc") = #-1;
  property blessed_task (owner: #2, flags: "rc") = 0;
  property ctype (owner: #2, flags: "rc") = 3;
  property dark (owner: #2, flags: "rc") = false;
  property ejection_msg (owner: #2, flags: "rc") = "You expel %d from %i.";
  property entrances (owner: #2, flags: "c") = {};
  property exits (owner: #2, flags: "c") = {};
  property free_entry (owner: #2, flags: "rc") = true;
  property free_home (owner: #2, flags: "rc") = false;
  property oejection_msg (owner: #2, flags: "rc") = "%N unceremoniously %{!expels} %d from %i.";
  property residents (owner: #2, flags: "rc") = {};
  property victim_ejection_msg (owner: #2, flags: "rc") = "You have been expelled from %i by %n.";
  property who_location_msg (owner: #2, flags: "rc") = "%T";

  override aliases (owner: #2, flags: "rc") = {"generic room"};
  override object_size (owner: HACKER, flags: "r") = {28944, 1084848672};

  method confunc owner: #2
    "Show the room and announce a connection for the player, a controller, or this room.";
    const principal = caller_perms();
    "The player check admits guests, who need not own themselves.";
    principal == player || $perm_utils:controls(principal, player) || caller == this || return;
    this:look_self(player.brief);
    this:announce($string_utils:pronoun_sub("%N %<has> connected.", player));
  endmethod

  method disfunc owner: #2
    "Announce disconnection and send non-guests home for an authorized session caller.";
    const principal = caller_perms();
    principal == player || $perm_utils:controls(principal, player) || caller == this || return;
    this:announce($string_utils:pronoun_sub("%N %<has> disconnected.", player));
    "Guests have their own disconnect cleanup.";
    !$object_utils:isa(player, $guest) && $housekeeper:move_players_home(player);
  endmethod

  verb say (any any any) owner: #2 flags: "rxd"
    "Say text to the room, reporting a broken output hook without aborting the command.";
    try
      player:tell("You say, \"", argstr, "\"");
      this:announce(player.name, " ", $gender_utils:get_conj("says", player), ", \"", argstr, "\"");
    except error (ANY)
      server_log(tostr("Room speech failed for ", player, ": ", error[1]));
    endtry
  endverb

  verb emote (any any any) owner: #2 flags: "rxd"
    "Announce an action; a leading colon joins the text directly to the player's name.";
    if (argstr != "" && argstr[1] == ":")
      this:announce_all(player.name, argstr[2..$]);
    else
      this:announce_all(player.name, " ", argstr);
    endif
  endverb

  method announce owner: #2
    "Broadcast to occupants except the command player; log and isolate broken recipient hooks.";
    for recipient in (setremove(this:contents(), player))
      try
        recipient:tell(@args);
      except error (ANY)
        server_log(tostr("Room broadcast to ", recipient, " failed: ", error[1]));
        continue recipient;
      endtry
    endfor
  endmethod

  method match_exit owner: #2
    "Match an exact exit name or alias; return nothing, failed-match, or ambiguous-match as needed.";
    const {name} = args;
    !name && return $nothing;
    let matched = $failed_match;
    for exit in (this.exits)
      if (valid(exit) && name in {exit.name, @exit.aliases})
        matched != $failed_match && matched != exit && return $ambiguous_match;
        matched = exit;
      endif
    endfor
    return matched;
  endmethod

  method add_exit owner: #2
    "Register an exit using caller authority; return false on a denied property write.";
    const {exit} = args;
    set_task_perms(caller_perms());
    return `this.exits = setadd(this.exits, exit) ! E_PERM' != E_PERM;
  endmethod

  method tell_contents owner: #2
    "Show supplied contents using layout 0..3, unless this room is dark.";
    const {contents, layout} = args;
    this.dark || contents == {} && return;
    if (layout == 0)
      player:tell("Contents:");
      for object in (contents)
        player:tell("  ", object:title());
      endfor
    elseif (layout == 1)
      for object in (contents)
        if (is_player(object))
          player:tell($string_utils:pronoun_sub(tostr("%N ", $gender_utils:get_conj("is", object), " here."), object));
        else
          player:tell("You see ", object:title(), " here.");
        endif
      endfor
    elseif (layout == 2)
      player:tell("You see ", $string_utils:title_list(contents), " here.");
    elseif (layout == 3)
      let players = {};
      let things = {};
      for object in (contents)
        if (is_player(object))
          players = {@players, object};
        else
          things = {@things, object};
        endif
      endfor
      things && player:tell("You see ", $string_utils:title_list(things), " here.");
      if (players)
        const conjugation = length(players) == 1 ? " " + $gender_utils:get_conj("is", players[1]) | " are";
        player:tell($string_utils:title_listc(players), conjugation, " here.");
      endif
    endif
  endmethod

  method look_self owner: #2
    "Show this room's title, optional description, and visible contents.";
    const {?brief = false} = args;
    player:tell(this:title());
    !brief && pass();
    this:tell_contents(setremove(this:contents(), player), this.ctype);
  endmethod

  method acceptable owner: #2
    "Require the room key plus free entry, a task blessing, ownership, or residency.";
    const {object, @options} = args;
    this:is_unlocked_for(object) || return false;
    this:free_entry(object, @options) && return true;
    object == this.blessed_object && task_id() == this.blessed_task && return true;
    object.owner == this.owner && return true;
    const residents = this.residents;
    return typeof(residents) == TYPE_LIST && (object in residents || object.owner in residents) != 0;
  endmethod

  method add_entrance owner: #2
    "Register an entrance using caller authority; return false on a denied property write.";
    const {entrance} = args;
    set_task_perms(caller_perms());
    return `this.entrances = setadd(this.entrances, entrance) ! E_PERM' != E_PERM;
  endmethod

  method bless_for_entry owner: #2
    "Authorize one object for entry in this task; only this room or a registered entrance may bless it.";
    const {object} = args;
    caller in {@this.entrances, this} || return;
    this.blessed_object = object;
    this.blessed_task = task_id();
  endmethod

  verb go (any any any) owner: #2 flags: "rxd"
    "Traverse one or more directions, committing between steps so arrival hooks can act.";
    const {?direction = "", @remaining} = args;
    if (!direction)
      player:tell("You need to specify a direction.");
      return E_INVARG;
    endif
    const exit = player.location:match_exit(direction);
    if (!valid(exit))
      if (exit == $failed_match)
        player:tell("You can't go that way (", direction, ").");
      else
        player:tell("I don't know which direction `", direction, "' you mean.");
      endif
      return;
    endif
    exit:invoke();
    !remaining && return;
    const arrived_room = player.location;
    "Commit the completed step before letting queued arrival behavior run.";
    suspend(0);
    "Read location again: another task or hook may have moved or recycled the player.";
    valid(player) && valid(arrived_room) || return;
    player.location == arrived_room && arrived_room:go(@remaining);
  endverb

  verb "l*ook" (any any any) owner: #2 flags: "rxd"
    "Look at the room, a nearby object, or an object inside a named container.";
    if (dobjstr == "" && !prepstr)
      this:look_self();
      return;
    endif
    if (prepstr != "in" && prepstr != "on")
      if (!dobjstr && prepstr == "at")
        dobjstr = iobjstr;
        iobjstr = "";
      else
        dobjstr = dobjstr + (prepstr && (dobjstr && " ") + prepstr);
        dobjstr = dobjstr + (iobjstr && (dobjstr && " ") + iobjstr);
      endif
      dobj = this:match_object(dobjstr);
      !$command_utils:object_match_failed(dobj, dobjstr) && dobj:look_self();
      return;
    endif
    !iobjstr && return player:tell(verb, " ", prepstr, " what?");
    iobj = this:match_object(iobjstr);
    $command_utils:object_match_failed(iobj, iobjstr) && return;
    if (dobjstr == "")
      iobj:look_self();
      return;
    endif
    const object = iobj:match(dobjstr);
    if (object == $failed_match)
      player:tell("I don't see any \"", dobjstr, "\" ", prepstr, " ", iobj.name, ".");
    elseif (object == $ambiguous_match)
      player:tell("There are several things ", prepstr, " ", iobj.name, " one might call \"", dobjstr, "\".");
    else
      object:look_self();
    endif
  endverb

  method announce_all owner: #2
    "Broadcast to all occupants; log and isolate broken recipient hooks.";
    for recipient in (this:contents())
      try
        recipient:tell(@args);
      except error (ANY)
        server_log(tostr("Room broadcast to ", recipient, " failed: ", error[1]));
        continue recipient;
      endtry
    endfor
  endmethod

  method announce_all_but owner: #2
    "Broadcast to occupants except an exclusion list; log and isolate broken recipient hooks.";
    const {excluded, @text} = args;
    let recipients = this:contents();
    for object in (excluded)
      recipients = setremove(recipients, object);
    endfor
    for recipient in (recipients)
      try
        recipient:tell(@text);
      except error (ANY)
        server_log(tostr("Room broadcast to ", recipient, " failed: ", error[1]));
        continue recipient;
      endtry
    endfor
  endmethod

  method enterfunc owner: #2
    "Show arriving players the room and consume any blessing for the arriving object.";
    const {object} = args;
    if (is_player(object) && object.location == this)
      player = object;
      this:look_self(player.brief);
    endif
    object == this.blessed_object && (this.blessed_object = $nothing);
  endmethod

  method exitfunc owner: #2
    "Default departure hook; subclasses can add behavior.";
    return;
  endmethod

  method remove_exit owner: #2
    "Remove an exit; allow that exit's cleanup hook or a caller with write authority.";
    const {exit} = args;
    caller != exit && set_task_perms(caller_perms());
    return `this.exits = setremove(this.exits, exit) ! E_PERM' != E_PERM;
  endmethod

  method remove_entrance owner: #2
    "Remove an entrance; allow that exit's cleanup hook or a caller with write authority.";
    const {exit} = args;
    caller != exit && set_task_perms(caller_perms());
    return `this.entrances = setremove(this.entrances, exit) ! E_PERM' != E_PERM;
  endmethod

  method recycle owner: #2
    "Evacuate contents before parent cleanup; require self or a controlling caller.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    "Try the enclosing room first, then reread the remaining contents.";
    if (valid(this.location))
      for object in (this.contents)
        try
          object:moveto(this.location);
        except error (ANY)
          server_log(tostr("Room evacuation failed for ", object, ": ", error[1]));
          continue object;
        endtry
      endfor
    endif
    for object in (this.contents)
      if (is_player(object))
        if (typeof(object.home) == TYPE_OBJ && valid(object.home))
          try
            object:moveto(object.home);
          except error (ANY)
            server_log(tostr("Room home evacuation failed for ", object, ": ", error[1]));
            continue object;
          endtry
        endif
        object.location == this && move(object, $player_start);
      elseif (valid(object.owner))
        try
          object:moveto(object.owner);
        except error (ANY)
          server_log(tostr("Room owner evacuation failed for ", object, ": ", error[1]));
          continue object;
        endtry
      endif
    endfor
    pass(@args);
  endmethod

  verb "e east w west s south n north ne northeast nw northwest se southeast sw southwest u up d down" (none none none) owner: #2 flags: "rxd"
    "Traverse the exact direction alias with caller authority, or command-player authority at the server entry point.";
    set_task_perms(caller_perms() == $nothing ? player | caller_perms());
    const exit = this:match_exit(verb);
    if (valid(exit))
      exit:invoke();
    elseif (exit == $failed_match)
      player:tell("You can't go that way.");
    else
      player:tell("I don't know which direction `", verb, "' you mean.");
    endif
  endverb

  method "ejection_msg oejection_msg victim_ejection_msg" owner: HACKER
    "Expand the named ejection message using command context.";
    return $gender_utils:pronoun_sub(this.(verb));
  endmethod

  method accept_for_abode owner: #2
    "Return whether residency policy and entry policy both permit this player's home.";
    const {resident} = args;
    return this:basic_accept_for_abode(resident) && this:acceptable(resident);
  endmethod

  method match owner: #2
    "Match a name against contents and exits using names and aliases.";
    const {name} = args;
    const candidates = {@this:contents(), @this:exits()};
    return $string_utils:match(name, candidates, "name", candidates, "aliases");
  endmethod

  method moveto owner: #2
    "Relocate this room only for itself, its owner object, or a controlling caller.";
    caller in {this, this.owner} || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return pass(@args);
  endmethod

  method who_location_msg owner: #2
    "Expand this room's location label for a player; inaccessible labels produce empty text.";
    const {object} = args;
    const message = `this.(verb) ! ANY';
    return message ? $string_utils:pronoun_sub(message, object) | "";
  endmethod

  method "exits entrances" owner: #2
    "Return the requested registration list only to this room or its controller.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return this.(verb);
  endmethod

  method "obvious_exits obvious_entrances" owner: #2
    "Return distinct registered exits whose visibility hook or property is true.";
    let visible = {};
    const exits = `verb == "obvious_exits" ? this.exits | this.entrances ! ANY => {}';
    for exit in (exits)
      `$code_utils:verb_or_property(exit, "obvious") ! ANY' && (visible = setadd(visible, exit));
    endfor
    return visible;
  endmethod

  method here_explain_syntax owner: #2
    "Decline room-specific syntax help so the command helper can explain verb syntax.";
    return false;
  endmethod

  method match_scope_for owner: #2
    "Return named objects visible to an actor; descendants can filter or extend this scope.";
    const {actor, ?context = []} = args;
    return {@this.contents, this};
  endmethod

  method here_huh owner: #2
    "Handle an argument-free command that names a registered exit; return whether handled.";
    const {command, command_args} = args;
    set_task_perms(caller_perms());
    command_args && return false;
    const exit = this:match_exit(command);
    exit == $failed_match && return false;
    if (valid(exit))
      exit:invoke();
    else
      player:tell("I don't know which direction `", command, "' you mean.");
    endif
    return true;
  endmethod

  method "room_announce*_all_but" owner: #2
    "Forward a room_announce alias to its matching broadcast method.";
    this:(verb[6..$])(@args);
  endmethod

  method examine_commands_ok owner: #2
    "Permit command inspection when the examiner is in this room.";
    const {examiner} = args;
    return this == examiner.location;
  endmethod

  method examine_key owner: #2
    "Describe the movement key to an authorized examiner during this object's examination.";
    const {examiner} = args;
    caller == this && $perm_utils:controls(examiner, this) && this.key != 0 || return 0;
    return {tostr(this:title(), " will accept only objects matching the following key:"), tostr("  ", $lock_utils:unparse_key(this.key))};
  endmethod

  method examine_contents owner: #2
    "Show contents only when called by this room's examination handler.";
    const {examiner} = args;
    caller == this && this:tell_contents(this.contents, this.ctype);
  endmethod

  method free_entry owner: HACKER
    "Return whether entry requires no resident or entrance blessing.";
    return !!this.free_entry;
  endmethod

  method init_for_core owner: #2
    "Run parent extraction initialization for wizards and place the extracting player in the starting room.";
    caller_perms().wizard || return;
    pass(@args);
    this == $player_start && move(player, this);
  endmethod

  method dark owner: #2
    "Return whether room contents are hidden.";
    return !!this.dark;
  endmethod

  method announce_lines_x owner: #2
    "Broadcast to occupants except the command player; log and isolate broken recipient hooks.";
    for recipient in (setremove(this:contents(), player))
      try
        recipient:tell_lines(@args);
      except error (ANY)
        server_log(tostr("Room broadcast to ", recipient, " failed: ", error[1]));
        continue recipient;
      endtry
    endfor
  endmethod

  method basic_accept_for_abode owner: #2
    "Return whether free-home policy, ownership, or residency permits this player to live here.";
    const {resident} = args;
    valid(resident) || return false;
    this.free_home || $perm_utils:controls(resident, this) && return true;
    const residents = this.residents;
    return typeof(residents) == TYPE_LIST ? resident in residents != 0 | resident == residents;
  endmethod
endobject
