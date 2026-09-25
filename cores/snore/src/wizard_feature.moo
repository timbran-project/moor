object WIZARD_FEATURE [
  import_export_id -> "wizard_feature"
]
  name: "Wizard Feature"
  parent: FEATURE
  owner: #2
  readable: true

  override feature_verbs (owner: HACKER, flags: "r") = {
    "@chown*#",
    "@shout",
    "@grant",
    "@grants*",
    "@transfer",
    "@programmer",
    "make-core-database",
    "@shutdown",
    "@dump-d*atabase",
    "@who-calls",
    "@toad",
    "@toad!",
    "@toad!!",
    "@untoad",
    "@detoad",
    "@quota",
    "@players",
    "@grepcore",
    "@egrepcore",
    "@net-who",
    "@@who",
    "@make-player",
    "@abort-sh*utdown",
    "@newt",
    "@unnewt",
    "@denewt",
    "@get-better",
    "@register",
    "@new-password",
    "@newpassword",
    "@log",
    "@guests",
    "@blacklist",
    "@graylist",
    "@redlist",
    "@unblacklist",
    "@ungraylist",
    "@unredlist",
    "@spooflist",
    "@unspooflist",
    "@corify",
    "@make-guest",
    "@temp-newt",
    "@deprog*rammer",
    "@lock-login",
    "@unlock-login",
    "@lock-login!"
  };
  override help_msg (owner: #2, flags: "rc") = "Commands for $wiz descendants. Installing this feature does not grant server permissions.";

  verb "@chown*#" (any any any) owner: #2 flags: "rd"
    "Transfer ownership of an object, property, or verb. Requires wizard permission.";
    let spec;
    let object;
    let e;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Sorry.");
      return;
    endif
    set_task_perms(player);
    args = setremove(args, "to");
    if (length(args) != 2 || !args[2])
      player:notify(tostr("Usage:  ", verb, " <object-or-property-or-verb> <owner>"));
      return;
    endif
    const what = args[1];
    const owner = $string_utils:match_player(args[2]);
    const bynumber = verb == "@chown#";
    if ($command_utils:player_match_result(owner, args[2])[1])
    else
      spec = $code_utils:parse_verbref(what);
      if (spec)
        object = player:my_match_object(spec[1]);
        if (!$command_utils:object_match_failed(object, spec[1]))
          let vname = spec[2];
          if (bynumber)
            vname = $code_utils:toint(vname);
            vname == E_TYPE && return player:notify("Verb number expected.");
            if (vname < 1 || vname > length(verbs(object)))
              return player:notify("Verb number out of range.");
            endif
          endif
          const info = `verb_info(object, vname) ! ANY';
          if (info == E_VERBNF)
            player:notify("That object does not define that verb.");
          elseif (typeof(info) == TYPE_ERR)
            player:notify(tostr(info));
          else
            try
              const result = set_verb_info(object, vname, listset(info, owner, 1));
              player:notify("Verb owner set.");
            except e (ANY)
              player:notify(e[2]);
            endtry
          endif
        endif
      elseif (bynumber)
        player:notify("@chown# can only be used with verbs.");
      else
        spec = index(what, ".") ? $code_utils:parse_propref(what) | {};
        if (spec)
          object = player:my_match_object(spec[1]);
          if (!$command_utils:object_match_failed(object, spec[1]))
            const pname = spec[2];
            e = $wiz_utils:set_property_owner(object, pname, owner);
            if (e == E_NONE)
              player:notify("+c Property owner set.  Did you really want to do that?");
            else
              player:notify(tostr(e && "Property owner set."));
            endif
          endif
        else
          object = player:my_match_object(what);
          if (!$command_utils:object_match_failed(object, what))
            player:notify(tostr($wiz_utils:set_owner(object, owner) && "Object ownership changed."));
          endif
        endif
      endif
    endif
  endverb

  verb "@shout" (any any any) owner: #2 flags: "rd"
    "Send an announcement to every connected player. Requires wizard permission.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (caller != player)
      raise(E_PERM);
    endif
    set_task_perms(player);
    if (length(args) == 1 && argstr[1] == "\"")
      argstr = args[1];
    endif
    const shout = $gender_utils:get_conj("shouts", player);
    for person in (connected_players())
      if (person != player)
        person:notify(tostr(player.name, " ", shout, ", \"", argstr, "\""));
      endif
    endfor
    player:notify(tostr("You shout, \"", argstr, "\""));
  endverb

  verb "@grant @grants* @transfer" (any at any) owner: #2 flags: "rd"
    "@grant <object> to <player>";
    "@grants <object> to <player>   --- same as @grant but may suspend.";
    "@transfer <expression> to <player> -- like 'grant', but evalutes a possible list of objects to transfer, and modifies quota.";
    "Ownership of the object changes as in @chown and :set_owner (i.e., .owner and all c properties change).  In addition all verbs and !c properties owned by the original owner change ownership as well.  Finally, for !c properties, instances on descendant objects change ownership (as in :set_property_owner).";
    let objlist;
    let object;
    let info;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Sorry.");
      return;
    endif
    set_task_perms(player);
    if (!iobjstr || !dobjstr)
      return player:notify(tostr("Usage:  ", verb, " <object> to <player>"));
    endif
    let newowner = $string_utils:match_player(iobjstr);
    if ($command_utils:player_match_failed(newowner, iobjstr))
      "...newowner is bogus...";
      return;
    endif
    if (verb == "@transfer")
      objlist = player:eval_cmd_string(dobjstr, 0);
      if (!objlist[1])
        player:notify(tostr("Had trouble reading `", dobjstr, "': "));
        player:notify_lines(@objlist[2]);
        return;
      endif
      if (typeof(objlist[2]) == TYPE_OBJ)
        objlist = objlist[2..2];
      elseif (typeof(objlist[2]) != TYPE_LIST)
        player:notify(tostr("Value of `", dobjstr, "' is not an object or list:  ", toliteral(objlist[2])));
        return;
      else
        objlist = objlist[2];
      endif
    else
      object = player:my_match_object(dobjstr);
      if ($command_utils:object_match_failed(object, dobjstr))
        "...object is bogus...";
        return;
      else
        objlist = {object};
      endif
    endif
    "Used to check for quota of newowner, but doesn't anymore, cuz the quota check doesn't work";
    const suspendok = verb != "@grant";
    player:tell("Transferring ", toliteral(objlist), " to ", $string_utils:nn(newowner));
    for object in (objlist)
      $command_utils:suspend_if_needed(0);
      let same = object.owner == newowner;
      for vnum in [1..length(verbs(object))]
        info = verb_info(object, vnum);
        if (!(info[1] != object.owner && (valid(info[1]) && is_player(info[1]))))
          same = same && info[1] == newowner;
          set_verb_info(object, vnum, listset(info, newowner, 1));
        endif
      endfor
      for prop in (properties(object))
        if (suspendok && (ticks_left() < 5000 || seconds_left() < 2))
          suspend(0);
        endif
        info = property_info(object, prop);
        if (!(index(info[2], "c") || (info[1] != object.owner && valid(info[1]) && is_player(info[1]))))
          same = same && info[1] == newowner;
          $wiz_utils:set_property_owner(object, prop, newowner, suspendok);
        endif
      endfor
      if (suspendok)
        suspend(0);
      endif
      $wiz_utils:set_owner(object, newowner, suspendok);
      if (same)
        player:notify(tostr(newowner.name, " already owns everything ", newowner.ps, " is entitled to on ", object.name, "."));
      else
        player:notify(tostr("Ownership changed on ", $string_utils:nn(object), ", verb, properties and descendants' properties."));
      endif
    endfor
    player:notify(tostr(verb, " complete."));
  endverb

  verb "@programmer" (any none none) owner: #2 flags: "rd"
    "Promote a player into the programmer hierarchy and grant programmer permission.";
    let result;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    dobj = $string_utils:match_player(dobjstr);
    if (dobj == $nothing)
      player:notify(tostr("Usage:  ", verb, " <playername>"));
    elseif ($command_utils:player_match_result(dobj, dobjstr)[1])
    elseif ($wiz_utils:check_prog_restricted(dobj))
      return player:notify(tostr("Sorry, ", dobj.name, " is not allowed to be a programmer."));
    elseif (dobj.description == $player.description && !$command_utils:yes_or_no($string_utils:pronoun_sub("@Programmer %d despite %[dpp] lack of description?")))
      player:notify(tostr("Okay, leaving ", dobj.name, " !programmer."));
      return;
    else
      result = $wiz_utils:set_programmer(dobj);
      if (result)
        player:notify(tostr(dobj.name, " (", dobj, ") is now a programmer.  ", dobj.ppc, " quota is currently ", $quota_utils:get_quota(dobj), "."));
        player:notify(tostr(dobj.name, " and the other wizards have been notified."));
        let msg = player:programmer_victim_msg();
        if (msg)
          dobj:notify(msg);
        endif
        msg = $object_utils:isa(dobj.location, $room) ? player:programmer_msg() | "";
        if (msg)
          dobj.location:announce_all_but({dobj}, msg);
        endif
      elseif (result == E_NONE)
        player:notify(tostr(dobj.name, " (", dobj, ") is already a programmer..."));
      else
        player:notify(tostr(result));
      endif
    endif
  endverb

  verb "make-core-database" (any none none) owner: #2 flags: "rd"
    "Usage: make-core-database [variant | resume]. Extract only in a disposable, isolated world.";
    "Confirmation precedes destruction. Resume continues the recorded phase after a stopped task.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const {?variant_name = ""} = args;
    if (variant_name == "resume")
      return player:mcd_2();
    endif
    if (`this.__mcd__state ! E_PROPNF => false')
      return player:tell("An extraction is already recorded. Use make-core-database resume.");
    endif
    if (length(connected_players()) > 1)
      return player:tell("Disconnect everyone else and isolate this copy before extracting a core.");
    endif
    if (!$command_utils:yes_or_no("This destroys world data. Is this an isolated disposable copy?") || !$command_utils:yes_or_no("Really extract the core?"))
      return player:tell("Core database extraction aborted.");
    endif
    player.wizard || raise(E_PERM);
    length(connected_players()) <= 1 || raise(E_INVARG, "Another player connected.");
    const variant = {{"name", variant_name}};
    const selection = $core_object_info(variant, true);
    player:_mcd_start(variant, selection);
    return player:mcd_2();
  endverb

  verb "@shutdown" (any any any) owner: #2 flags: "rd"
    "Schedule a server shutdown and notify connected players. Requires wizard permission.";
    let delay;
    let msg;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Sorry.");
      return;
    endif
    if ($code_utils:task_valid($shutdown_task))
      player:notify(tostr("Shutdown already in progress.  The MOO will be shut down in ", $time_utils:english_time($shutdown_time - time()), ", by ", $shutdown_message));
      return;
    endif
    const s = match(argstr, "^in +%([0-9]+%)%( +%|$%)");
    if (s)
      const bounds = s[3][1];
      delay = toint(argstr[bounds[1]..bounds[2]]);
      argstr = argstr[s[2] + 1..$];
    else
      delay = 2;
    endif
    if (!$command_utils:yes_or_no(tostr("Do you really want to shut down the server in ", delay, " minutes?")))
      player:notify("Aborted.");
      return;
    endif
    let announce_times = {};
    if (delay > 0)
      while (delay > 0)
        announce_times = {@announce_times, delay * 60};
        delay = delay / 2;
      endwhile
      announce_times = {@announce_times, 30, 10};
      $shutdown_time = time() + announce_times[1];
    endif
    $shutdown_message = tostr(player.name, " (", player, "): ", argstr);
    $shutdown_task = task_id();
    for i in [1..length(announce_times)]
      const base_msg = tostr("*** The server will be shut down by ", player.name, " (", player, ") in ", $time_utils:english_time(announce_times[i]), ":");
      msg = {base_msg, @$generic_editor:fill_string("*** " + argstr, length(base_msg) - 4, "*** ")};
      "...use raw notify() since :notify() verb could be broken...";
      for p in (connected_players())
        for line in (msg)
          notify(p, line);
        endfor
        $command_utils:suspend_if_needed(0);
      endfor
      suspend(announce_times[i] - {@announce_times, 0}[i + 1]);
    endfor
    for p in (connected_players())
      notify(p, tostr("*** Server shutdown by ", $shutdown_message, " ***"));
      boot_player(p);
    endfor
    suspend(0);
    $shutdown_task = E_NONE;
    set_task_perms(player);
    shutdown(argstr);
  endverb

  verb "@dump-d*atabase" (none none none) owner: #2 flags: "rd"
    "Request a database checkpoint. Requires wizard permission.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    dump_database();
    player:notify("Dumping...");
  endverb

  verb "@who-calls" (any any any) owner: #2 flags: "rd"
    "Search verb source for calls to the specified verb.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (argstr[1] != ":")
      argstr = ":" + argstr;
    endif
    player:notify(tostr("Searching for verbs that appear to call ", argstr, " ..."));
    player:notify("");
    $code_utils:find_verbs_containing(argstr + "(");
  endverb

  verb "@toad @toad! @toad!!" (any any any) owner: #2 flags: "rd"
    "@toad[!][!] <player> [blacklist|redlist|graylist] [commentary]";
    let listname;
    let ln;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const whostr = args[1];
    let comment = $string_utils:first_word(argstr)[2];
    if (verb == "@toad!!")
      listname = "redlist";
    elseif (verb == "@toad!")
      listname = "blacklist";
    else
      ln = {@args, ""}[2];
      if (ln)
        listname = $login:listname(ln);
      endif
      if (ln && index(listname, ln) == 1)
        "...first word of coment is one of the magic words...";
        comment = $string_utils:first_word(comment)[2];
      else
        listname = "";
      endif
    endif
    if (!player.wizard)
      player:notify("Yeah, right... you wish.");
      return;
    endif
    let who = $string_utils:match_player(whostr);
    if ($command_utils:player_match_failed(who, whostr))
      return;
    elseif (whostr != who.name && !(whostr in who.aliases) && whostr != tostr(who))
      player:notify(tostr("Must be a full name or an object number:  ", who.name, "(", who, ")"));
      return;
    elseif (who == player)
      player:notify("If you want to toad yourself, you have to do it by hand.");
      return;
    endif
    dobj = who;
    let msg = player:toad_victim_msg();
    if (msg)
      notify(who, msg);
    endif
    if ($wiz_utils:rename_all_instances(who, "disfunc", "toad_disfunc"))
      player:notify(tostr(who, ":disfunc renamed."));
    endif
    if ($wiz_utils:rename_all_instances(who, "recycle", "toad_recycle"))
      player:notify(tostr(who, ":recycle renamed."));
    endif
    "MOO-specific cleanup while still a player object.";
    player:toad_cleanup(who);
    const e = $wiz_utils:unset_player(who, $hacker);
    player:notify(e ? tostr(who.name, "(", who, ") is now a toad.") | tostr(e));
    msg = e && $object_utils:isa(who.location, $room) ? player:toad_msg() | "";
    if (msg)
      who.location:announce_all_but({who}, msg);
    endif
    let cname = listname ? $string_utils:connection_hostname(who.last_connect_place) | "";
    if (listname && !$login:(listname + "ed")(cname))
      $login:(listname + "_add")(cname);
      player:notify(tostr("Site ", cname, " ", listname, "ed."));
    else
      cname = "";
    endif
    if (!comment)
      player:notify("So why is this person being toaded?");
      comment = $command_utils:read();
    endif
    $mail_agent:send_message(player, $toad_log, tostr("@toad ", who.name, " (", who, ")"), {$string_utils:from_list(who.all_connect_places, " "), @cname ? {$string_utils:capitalize(listname + "ed:  ") + cname} | {}, @comment ? {comment} | {}});
    player:notify(tostr("Mail sent to ", $mail_agent:name($toad_log), "."));
    `$local.waitlist:note_reapee(who, tostr("@toaded by ", player.name)) ! ANY';
  endverb

  verb "@untoad @detoad" (any any any) owner: #2 flags: "rd"
    "@untoad <object> [as namespec]";
    "Turns object into a player.  Anything that isn't a guest is chowned to itself.";
    let e;
    let g;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Yeah, right... you wish.");
    elseif (prepstr && prepstr != "as")
      player:notify(tostr("Usage:  ", verb, " <object> [as name,alias,alias...]"));
    elseif ($command_utils:object_match_failed(dobj, dobjstr))
    else
      e = prepstr ? $building_utils:set_names(dobj, iobjstr) | false;
      if (prepstr && !e)
        player:notify(tostr("Initial rename failed:  ", e));
      else
        e = $wiz_utils:set_player(dobj, g = $object_utils:isa(dobj, $guest));
        if (e)
          player:notify(tostr(dobj.name, "(", dobj, ") is now a ", g ? "usable guest." | "player."));
        elseif (e == E_INVARG)
          player:notify(tostr(dobj.name, "(", dobj, ") is not of an appropriate player class."));
          player:notify("@chparent it to $player or some descendant.");
        elseif (e == E_NONE)
          player:notify(tostr(dobj.name, "(", dobj, ") is already a player."));
        elseif (e == E_NACC)
          player:notify("Wait until $player_db is finished updating...");
        elseif (e == E_RECMOVE)
          player:notify(tostr("The name `", dobj.name, "' is currently unavailable."));
          player:notify(tostr("Try again with   ", verb, " ", dobj, " as <newname>"));
        else
          player:notify(tostr(e));
        endif
      endif
    endif
  endverb

  verb "@quota" (any is any) owner: #2 flags: "rd"
    "@quota <player> is [public] <number> [<reason>]";
    "  changes a player's quota.  sends mail to the wizards.";
    let recipients;
    let n;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    set_task_perms(player);
    dobj = $string_utils:match_player(dobjstr);
    $command_utils:player_match_result(dobj, dobjstr)[1] && return;
    if (!valid(dobj))
      player:notify("Set whose quota?");
      return;
    endif
    if (iobjstr[1..min(7, $)] == "public ")
      iobjstr[1..7] = "";
      if ($object_utils:has_property($local, "public_quota_log"))
        recipients = {$quota_log, $local.public_quota_log};
      else
        player:tell("No public quota log.");
        return E_INVARG;
      endif
    else
      recipients = {$quota_log};
    endif
    const old = $quota_utils:get_quota(dobj);
    const qstr = iobjstr[1..(n = index(iobjstr + " ", " ")) - 1];
    let new = $code_utils:toint(qstr[1] == "+" ? qstr[2..$] | qstr);
    const reason = iobjstr[n + 1..$] || "(none)";
    if (typeof(new) != TYPE_INT)
      player:notify(tostr("Set ", dobj.name, "'s quota to what?"));
      return;
    endif
    if (qstr[1] == "+")
      new = old + new;
    endif
    const result = $quota_utils:set_quota(dobj, new);
    if (typeof(result) == TYPE_ERR)
      player:notify(tostr(result));
    else
      player:notify(tostr(dobj.name, "'s quota set to ", new, "."));
    endif
    $mail_agent:send_message(player, recipients, tostr("@quota ", dobj.name, " (", dobj, ") ", new, " (from ", old, ")"), tostr("Reason for quota ", new - old < 0 ? "decrease: " | "increase: ", reason, index("?.!", reason[$]) ? "" | "."));
  endverb

  verb "@players" (any any any) owner: #2 flags: "rd"
    "Report player activity, optionally including numbered and UUID objects grouped by owner activity.";
    "Requires wizard permission. Membership is a snapshot; objects are rechecked after each suspension.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const start = 654768000;
    const now = time();
    const day = 24 * 60 * 60;
    const week = 7 * day;
    const month = 30 * day;
    let days_objects = {0, 0, 0, 0, 0, 0, 0};
    let days_players = days_objects;
    let weeks_objects = {0, 0, 0, 0};
    let weeks_players = weeks_objects;
    let months_objects = {};
    let months_players = {};
    let nonplayer_objects = 0;
    let invalid_objects = 0;
    let always_objects = 0;
    let always_players = 0;
    let never_objects = 0;
    let never_players = 0;
    let numo = 0;
    if (argstr && (dobjstr || prepstr != "with" || index("objects", iobjstr) != 1))
      player:notify(tostr("Usage:  ", verb, " [with objects]"));
      return;
    endif
    const with_objects = argstr != "";
    const candidates = with_objects ? objects() | players();
    for o in (candidates)
      if ($command_utils:running_out_of_time())
        player:notify(tostr("... ", o));
        suspend(0);
      endif
      if (valid(o))
        numo = numo + 1;
        const p = is_player(o) ? o | o.owner;
        if (!valid(p))
          invalid_objects = invalid_objects + 1;
        elseif (!$object_utils:isa(p, $player))
          nonplayer_objects = nonplayer_objects + 1;
        else
          const seconds = now - p.last_connect_time;
          const days = seconds / day;
          const weeks = seconds / week;
          const months = seconds / month;
          if (seconds < 0)
            if (is_player(o))
              always_players = always_players + 1;
            else
              always_objects = always_objects + 1;
            endif
          elseif (seconds > now - start)
            if (is_player(o))
              never_players = never_players + 1;
            else
              never_objects = never_objects + 1;
            endif
          elseif (months > 0)
            while (months > length(months_players))
              months_players = {@months_players, 0};
              months_objects = {@months_objects, 0};
            endwhile
            if (is_player(o))
              months_players[months] = months_players[months] + 1;
            endif
            months_objects[months] = months_objects[months] + 1;
          elseif (weeks > 0)
            if (is_player(o))
              weeks_players[weeks] = weeks_players[weeks] + 1;
            endif
            weeks_objects[weeks] = weeks_objects[weeks] + 1;
          else
            if (is_player(o))
              days_players[days + 1] = days_players[days + 1] + 1;
            endif
            days_objects[days + 1] = days_objects[days + 1] + 1;
          endif
        endif
      endif
    endfor
    player:notify("");
    player:notify(tostr("Last connected"));
    player:notify(tostr("at least this     Num.     Cumul.   Cumul. %", with_objects ? "     Num.     Cumul.   Cumul. %" | ""));
    player:notify(tostr("long ago        players   players   players ", with_objects ? "   objects   objects   objects" | ""));
    player:notify(tostr("---------------------------------------------", with_objects ? "--------------------------------" | ""));
    const su = $string_utils;
    const col1 = 14;
    const col2 = 7;
    const col3 = 10;
    const col4 = 9;
    const col5 = 11;
    const col6 = 11;
    const col7 = 10;
    const nump = length(players());
    let totalp = 0;
    let totalo = 0;
    for x in ({{days_players, days_objects, "day", 1}, {weeks_players, weeks_objects, "week", 0}, {months_players, months_objects, "month", 0}})
      const pcounts = x[1];
      const ocounts = x[2];
      const unit = x[3];
      const offset = x[4];
      for i in [1..length(pcounts)]
        $command_utils:suspend_if_needed(0);
        const j = i - offset;
        player:notify(tostr(su:left(tostr(j, " ", unit, j == 1 ? ":" | "s:"), col1), su:right(pcounts[i], col2), su:right(totalp = totalp + pcounts[i], col3), su:right(totalp * 100 / nump, col4), "%", with_objects ? tostr(su:right(ocounts[i], col5), su:right(totalo = totalo + ocounts[i], col6), su:right(totalo * 100 / numo, col7), "%") | ""));
      endfor
      player:notify("");
    endfor
    player:notify(tostr(su:left("Never:", col1), su:right(never_players, col2), su:right(totalp = totalp + never_players, col3), su:right(totalp * 100 / nump, col4), "%", with_objects ? tostr(su:right(never_objects, col5), su:right(totalo = totalo + never_objects, col6), su:right(totalo * 100 / numo, col7), "%") | ""));
    player:notify(tostr(su:left("Always:", col1), su:right(always_players, col2), su:right(totalp = totalp + always_players, col3), su:right(totalp * 100 / nump, col4), "%", with_objects ? tostr(su:right(always_objects, col5), su:right(totalo = totalo + always_objects, col6), su:right(totalo * 100 / numo, col7), "%") | ""));
    with_objects && player:notify(tostr(su:left("Non-player owner:", col1 + col2 + col3 + col4 + 1), su:right(nonplayer_objects, col5), su:right(totalo = totalo + nonplayer_objects, col6), su:right(totalo * 100 / numo, col7), "%"));
    with_objects && player:notify(tostr(su:left("Invalid owner:", col1 + col2 + col3 + col4 + 1), su:right(invalid_objects, col5), su:right(totalo = totalo + invalid_objects, col6), su:right(totalo * 100 / numo, col7), "%"));
    player:notify("");
  endverb

  verb "@grepcore @egrepcore" (any any any) owner: #2 flags: "rd"
    "Search core verb source for text or a regular expression.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!args)
      player:notify(tostr("Usage:  ", verb, " <pattern>"));
      return;
    endif
    const pattern = argstr;
    const regexp = verb == "@egrepcore";
    player:notify(tostr("Searching for core verbs ", regexp ? "matching the regular expression " | "containing the string ", toliteral(pattern), " ..."));
    player:notify("");
    $code_utils:(regexp ? "find_verbs_matching" | "find_verbs_containing")(pattern, $core_objects());
  endverb

  verb "@net-who @@who" (any any any) owner: #2 flags: "rd"
    "@net-who prints all connected users and hosts.";
    "@net-who player player player prints specified users and current or most recent connected host.";
    "@net-who from hoststring prints all players who have connected from that host or host substring.  Substring can include *'s, e.g. @net-who from *.foo.edu.";
    let unsorted;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const su = $string_utils;
    if (prepstr == "from" && dobjstr)
      player:notify(tostr("Usage:  ", verb, " from <host string>"));
    elseif (prepstr != "from" || dobjstr || !iobjstr)
      "Not parsing 'from' here...  Instead printing connected/recent users.";
      const pstrs = args;
      if (!pstrs)
        unsorted = connected_players();
      else
        unsorted = listdelete($command_utils:player_match_result(su:match_player(pstrs), pstrs), 1);
      endif
      !unsorted && return;
      $wiz_utils:show_netwho_listing(player, unsorted);
    else
      $wiz_utils:show_netwho_from_listing(player, iobjstr);
    endif
  endverb

  verb "@make-player" (any any any) owner: #2 flags: "rd"
    "Creates a player.";
    "Syntax:  @make-player name email-address comments....";
    "Generates a random password for the player.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    caller == player || return E_PERM;
    if (length(args) < 2)
      player:tell("Syntax:  @make-player name email-address comments....");
      return;
    elseif (args[2] == "for")
      "common mistake: @make-player <name> for <email-address> ...";
      args = listdelete(args, 2);
    endif
    return $wiz_utils:do_make_player(@args);
  endverb

  verb "@abort-sh*utdown" (any any any) owner: #2 flags: "rd"
    "Cancel a pending server shutdown. Requires wizard permission.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Sorry.");
    elseif (!$code_utils:task_valid($shutdown_task))
      player:notify("No server shutdown in progress.");
      $shutdown_task = E_NONE;
    else
      "... Reset time so that $login:check_for_shutdown shuts up...";
      kill_task($shutdown_task);
      $shutdown_task = E_NONE;
      $shutdown_time = time() - 1;
      for p in (connected_players())
        notify(p, tostr("*** Server shutdown ABORTED by ", player.name, " (", player, ")", argstr && ":  " + argstr, " ***"));
      endfor
    endif
  endverb

  verb "@newt" (any any any) owner: #2 flags: "rd"
    "@newt <player> [commentary]";
    "turns a player into a newt.  It can get better...";
    "adds player to $login.newted, they will not be allowed to log in.";
    "Sends mail to $newt_log giving .all_connect_places and commentary.";
    let who;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const whostr = args[1];
    const comment = $string_utils:first_word(argstr)[2];
    if (!player.wizard)
      player:notify("Yeah, right.");
    else
      who = $string_utils:match_player(whostr);
      if ($command_utils:player_match_failed(who, whostr))
        return;
      elseif (whostr != who.name && !(whostr in who.aliases) && whostr != tostr(who))
        player:notify(tostr("Must be a full name or an object number:  ", who.name, "(", who, ")"));
        return;
      elseif (who == player)
        player:notify("If you want to newt yourself, you have to do it by hand.");
        return;
      elseif (who in $login.newted)
        player:notify(tostr(who.name, " appears to already be a newt."));
        return;
      else
        $wiz_utils:newt_player(who, comment);
      endif
    endif
  endverb

  verb "@unnewt @denewt @get-better" (any any any) owner: #2 flags: "rd"
    "@denewt <player> [commentary]";
    "Remove the player from $Login.newted";
    "Sends mail to $newt_log with commentary.";
    let who;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const whostr = args[1];
    const comment = $string_utils:first_word(argstr)[2];
    if (!player.wizard)
      player:notify("Yeah, right.");
    else
      who = $string_utils:match_player(whostr);
      if ($command_utils:player_match_failed(who, whostr))
        return;
      else
        "Should parse email address and register user in some clever way.  Ick.";
        if (!(who in $login.newted))
          player:notify(tostr(who.name, " does not appear to be a newt."));
        else
          $login.newted = setremove($login.newted, who);
          const entry = $list_utils:assoc(who, $login.temporary_newts);
          if (entry)
            $login.temporary_newts = setremove($login.temporary_newts, entry);
          endif
          player:notify(tostr(who.name, " (", who, ") got better."));
          $mail_agent:send_message(player, $newt_log, tostr("@denewt ", who.name, " (", who, ")"), comment ? {comment} | {});
        endif
      endif
    endif
  endverb

  verb "@register" (any any any) owner: #2 flags: "rd"
    "Registers a player.";
    "Syntax:  @register name email-address [additional commentary]";
    "Email-address is stored in $registration_db and on the player object.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    !player.wizard && return player:tell(E_PERM);
    $wiz_utils:do_register(@args);
  endverb

  verb "@new-password @newpassword" (any is any) owner: #2 flags: "rd"
    "@newpassword player is [string]";
    "Set's a player's password; omit string to have one randomly generated.";
    "Offer to email the password.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    !player.wizard && return E_PERM;
    dobj = $string_utils:match_player(dobjstr);
    if ($command_utils:player_match_failed(dobj, dobjstr))
      return;
    elseif (!(dobjstr in {@dobj.aliases, tostr(dobj)}))
      player:notify(tostr("Must be a full name or an object number: ", dobj.name, " (", dobj, ")"));
    else
      $wiz_utils:do_new_password(dobj, iobjstr);
    endif
  endverb

  verb "@log" (any any any) owner: #2 flags: "rd"
    "@log [<string>]    enters a comment in the server log.";
    "If no string is given, you are prompted to enter one or more lines for an extended comment.";
    let lines;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const whostr = tostr("from ", player.name, " (", player, ")");
    if (!player.wizard || player != caller)
      player:notify("Yeah, right.");
    elseif (argstr)
      server_log(tostr("COMMENT: [", whostr, "]  ", argstr));
      player:notify("One-line comment logged.");
    else
      lines = $command_utils:read_lines();
      if (lines)
        server_log(tostr("COMMENT: [", whostr, "]"));
        for l in (lines)
          server_log(l);
        endfor
        server_log(tostr("END_COMMENT."));
        player:notify(tostr(length(lines), " lines logged as extended comment."));
      endif
    endif
  endverb

  verb "@guests" (any none none) owner: #2 flags: "rd"
    "Show guest connections and their recorded sites. Requires wizard permission.";
    let unsorted;
    let alist;
    let where;
    let w1;
    let w2;
    let w3;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    const n = dobjstr == "all" ? 0 | $code_utils:toint(dobjstr || "20");
    if (caller != player)
      player:notify("You lose.");
    elseif (n == E_TYPE && index("now", dobjstr) != 1)
      player:notify(tostr("Usage:  ", verb, " <number>  (where <number> indicates how many entries to look at in the guest log)"));
      player:notify(tostr("Usage:  ", verb, " now (to see information about currently connected guests only)"));
    elseif (!dobjstr || index("now", dobjstr) != 1)
      $guest_log:last(n);
    else
      "*way* too much copied code in here from @who...  Sorry.  --yduJ";
      const su = $string_utils;
      const conn = connected_players();
      unsorted = {};
      for g in ($object_utils:leaves($guest))
        if (g in conn)
          unsorted = {@unsorted, g};
        endif
      endfor
      if (!unsorted)
        player:tell("No guests found.");
        return;
      endif
      let footnotes = {};
      alist = {};
      let nwidth = length("Player name");
      for u in (unsorted)
        const pref = u.programmer ? "% " | "  ";
        u.programmer && (footnotes = setadd(footnotes, "prog"));
        const u3 = {tostr(pref, u.name, " (", u, ")"), su:from_seconds(connected_seconds(u)), su:from_seconds(idle_seconds(u)), where = $string_utils:connection_hostname(connection_name(u))};
        nwidth = max(length(u3[1]), nwidth);
        if ($login:blacklisted(where))
          where = "(*) " + where;
          footnotes = setadd(footnotes, "black");
        elseif ($login:graylisted(where))
          where = "(+) " + where;
          footnotes = setadd(footnotes, "gray");
        endif
        alist = {@alist, u3};
        $command_utils:suspend_if_needed(0);
      endfor
      alist = $list_utils:sort_alist_suspended(0, alist, 3);
      $command_utils:suspend_if_needed(0);
      const headers = {"Player name", "Connected", "Idle Time", "From Where"};
      const time_width = length("59 minutes") + 2;
      const before = {0, w1 = nwidth + 3, w2 = w1 + time_width, w3 = w2 + time_width};
      let tell1 = "  " + headers[1];
      let tell2 = "  " + su:space(headers[1], "-");
      for j in [2..4]
        tell1 = su:left(tell1, before[j]) + headers[j];
        tell2 = su:left(tell2, before[j]) + su:space(headers[j], "-");
      endfor
      player:notify(tell1);
      player:notify(tell2);
      const active = 0;
      for a in (alist)
        $command_utils:suspend_if_needed(0);
        tell1 = a[1];
        for j in [2..4]
          tell1 = su:left(tell1, before[j]) + tostr(a[j]);
        endfor
        player:notify(tell1[1..min($, 79)]);
      endfor
      if (footnotes)
        player:notify("");
        if ("prog" in footnotes)
          player:notify(" %  == programmer.");
        endif
        if ("black" in footnotes)
          player:notify("(*) == blacklisted site.");
        endif
        if ("gray" in footnotes)
          player:notify("(+) == graylisted site.");
        endif
      endif
      player:tell("@guests display complete.");
    endif
  endverb

  verb "@blacklist @graylist @redlist @unblacklist @ungraylist @unredlist @spooflist @unspooflist" (any any any) owner: #2 flags: "rd"
    "@[un]blacklist [<site or subnet>  [for <duration>] [commentary]]";
    "@[un]graylist  [<site or subnet>  [for <duration>] [commentary]]";
    "@[un]redlist   [<site or subnet>  [for <duration>] [commentary]]";
    "@[un]spooflist [<site of subnet>  [for <duration>] [commentary]]";
    "The `for <duration>' is for temporary colorlisting a site only. The duration should be in english time units:  for 1 hour, for 1 day 2 hours 15 minutes, etc. The commentary should be after all durations. Note, if you are -not- using a duration, do not start your commentary with the word `for'.";
    let start;
    let duration;
    let comment;
    let fullname;
    let ntries;
    let dg;
    let old;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (!player.wizard)
      player:notify("Ummm.  no.");
      return;
    endif
    const undo = verb[2..3] == "un";
    const which = $login:listname(verb[undo ? 4 | 2]);
    const downgrade = {"", "graylist", "blacklist"}[1 + index("br", which[1])];
    const fw = $string_utils:first_word(argstr);
    if (!fw)
      "... Just print the list...";
      player:display_list(which);
      return;
    endif
    let target = fw[1];
    let parse = fw[2] ? player:parse_templist_duration(fw[2]) | {false};
    if (parse[1])
      if (typeof(parse[3]) == TYPE_ERR || !parse[3])
        player:notify(tostr("Could not parse the duration for @", which, "ing site \"", target, "\""));
        return;
      endif
      start = parse[2];
      duration = parse[3];
      comment = parse[4] ? {parse[4]} | {};
      comment = {tostr("for ", $time_utils:english_time(duration)), @comment};
    elseif (fw[2])
      comment = {fw[2]};
    else
      "Get the right vars set up as though parse had been called";
      parse = {0, ""};
      comment = {};
    endif
    player:tell("comment is currently ", toliteral(comment));
    const is_literal = $site_db:domain_literal(target);
    if (is_literal)
      if (target[$] == ".")
        target = target[1..$ - 1];
      endif
      fullname = "subnet " + target;
    else
      if (target[1] == ".")
        target[1..1] = "";
      endif
      fullname = "domain `" + target + "'";
    endif
    let entrylist = $login.(which)[is_literal ? 1 | 2];
    if (!undo && target in entrylist)
      player:notify(tostr(fullname, " is already ", which, "ed."));
      return;
    endif
    entrylist = setremove(entrylist, target);
    let result = player:check_site_entries(undo, which, target, is_literal, entrylist);
    !result[1] && return;
    let rm = result[2];
    const namelist = $string_utils:english_list(rm);
    let downgraded = {};
    if (rm)
      ntries = length(rm) == 1 ? "ntry" | "ntries";
      if ($command_utils:yes_or_no(tostr("Remove e", ntries, " for ", namelist, "?")))
        dg = undo && (downgrade && $command_utils:yes_or_no(downgrade + " them?"));
        for s in (rm)
          $login:(which + "_remove")(s);
          dg && ($login:(downgrade + "_add")(s) && (downgraded = {@downgraded, s}));
        endfor
        player:notify(tostr("E", ntries, " removed", @dg ? {" and ", downgrade, "ed."} | {"."}));
      else
        player:notify(tostr(namelist, " will continue to be ", which, "ed."));
        rm = {};
      endif
    endif
    if (downgraded)
      comment[1..0] = {tostr(downgrade, "ed ", $string_utils:english_list(downgraded), ".")};
    endif
    let tempentrylist = $login.("temporary_" + which)[is_literal ? 1 | 2];
    if (!undo && target in $list_utils:slice(tempentrylist))
      player:notify(tostr(fullname, " is already temporarily ", which, "ed."));
      return;
    endif
    const en = $list_utils:assoc(target, tempentrylist);
    if (en)
      tempentrylist = setremove(tempentrylist, en);
    endif
    result = player:check_site_entries(undo, which, target, is_literal, $list_utils:slice(tempentrylist));
    !result[1] && return;
    let rmtemp = result[2];
    const tempnamelist = $string_utils:english_list(rmtemp);
    let tempdowngraded = {};
    if (rmtemp)
      ntries = length(rmtemp) == 1 ? "ntry" | "ntries";
      if ($command_utils:yes_or_no(tostr("Remove e", ntries, " for ", tempnamelist, "?")))
        dg = undo && (downgrade && $command_utils:yes_or_no(downgrade + " them?"));
        for s in (rmtemp)
          old = $list_utils:assoc(s, tempentrylist);
          $login:(which + "_remove_temp")(s);
          dg && ($login:(downgrade + "_add_temp")(s, old[2], old[3]) && (tempdowngraded = {@tempdowngraded, s}));
        endfor
        player:notify(tostr("E", ntries, " removed", @dg ? {" and ", downgrade, "ed with durations transferred."} | {"."}));
      else
        player:notify(tostr(tempnamelist, " will continue to be temporarily ", which, "ed."));
        rmtemp = {};
      endif
    endif
    if (tempdowngraded)
      comment[1..0] = {tostr(downgrade, "ed ", $string_utils:english_list(tempdowngraded), ".")};
    endif
    if (!undo)
      if (parse[1])
        $login:(which + "_add_temp")(target, start, duration);
        player:notify(tostr(fullname, " ", which, "ed for ", $time_utils:english_time(duration)));
      else
        $login:(which + "_add")(target);
        player:notify(tostr(fullname, " ", which, "ed."));
      endif
      if (rm)
        comment[1..0] = {tostr("Subsumes ", which, "ing for ", namelist, ".")};
      endif
      if (rmtemp)
        comment[1..0] = {tostr("Subsumes temporary ", which, "ing for ", tempnamelist, ".")};
      endif
    elseif ($login:(which + "_remove")(target))
      player:notify(tostr(fullname, " un", which, "ed."));
      if (!downgrade)
      elseif ($command_utils:yes_or_no(downgrade + " it?"))
        $login:(downgrade + "_add")(target) && (downgraded = {target, @downgraded});
        player:notify(tostr(fullname, " ", downgrade, "ed."));
      else
        player:notify(tostr(fullname, " not ", downgrade, "ed."));
      endif
      if (downgraded)
        player:tell("Comment currently: ", toliteral(comment), " ; downgrade = ", toliteral(downgrade), " ; downgraded = ", toliteral(downgraded));
        comment[1..0] = {tostr(downgrade, "ed ", $string_utils:english_list(downgraded), ".")};
      endif
      if (rm)
        comment[1..0] = {tostr("Also removed ", namelist, ".")};
      endif
    else
      old = $list_utils:assoc(target, $login.("temporary_" + which)[is_literal ? 1 | 2]);
      if (old && $login:(which + "_remove_temp")(target))
        player:notify(tostr(fullname, " un", which, "ed."));
        if (!downgrade)
        elseif ($command_utils:yes_or_no(downgrade + " it?"))
          $login:(downgrade + "_add_temp")(target, old[2], old[3]) && (tempdowngraded = {target, @tempdowngraded});
          player:notify(tostr(fullname, " ", downgrade, "ed, currently for ", $time_utils:english_time(old[3]), " from ", $time_utils:time_sub("$1/$3", old[2])));
        else
          player:notify(tostr(fullname, " not ", downgrade, "ed."));
        endif
        if (tempdowngraded)
          comment[1..0] = {tostr(downgrade, "ed ", $string_utils:english_list(tempdowngraded), "with durations transferred.")};
        endif
        if (rmtemp)
          comment[1..0] = {tostr("Also removed ", tempnamelist, ".")};
        endif
      elseif (rm || rmtemp)
        player:notify(tostr(fullname, " itself was never actually ", which, "ed."));
        comment[1..0] = {tostr("Removed ", namelist, " from regular and ", tempnamelist, " from temporary.")};
      else
        player:notify(tostr(fullname, " was not ", which, "ed before."));
        return;
      endif
    endif
    const subject = tostr(undo ? "@un" | "@", which, " ", fullname);
    $mail_agent:send_message(player, $site_log, subject, comment);
    "...";
    "... make sure we haven't screwed ourselves...";
    let uhoh = {};
    for site in (player.all_connect_places)
      if (index(site, target) && $login:(which + "ed")(site))
        uhoh = {@uhoh, site};
      endif
    endfor
    if (uhoh)
      player:notify(tostr("WARNING:  ", $string_utils:english_list(uhoh), " are now ", which, "ed!"));
    endif
  endverb

  verb "@corify" (any as any) owner: #2 flags: "rd"
    "Usage:  @corify <object> as <propname>";
    "Adds <object> to the core, as $<propname>";
    "Reminds the wizard to write an :init_for_core verb, if there isn't one already.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:tell("Sorry, the core is wizardly territory.");
      return;
    endif
    if (dobj == $failed_match)
      dobj = player:my_match_object(dobjstr);
    endif
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    if (!iobjstr)
      player:tell("Usage:  @corify <object> as <propname>");
      return;
    endif
    if (iobjstr[1] == "$")
      iobjstr = iobjstr[2..$];
    endif
    try
      add_property(#0, iobjstr, dobj, {player, "r"});
    except e (ANY)
      return player:tell(e[1], ":", e[2]);
    endtry
    if (!("init_for_core" in verbs(dobj)))
      player:tell(dobj:titlec(), " has no :init_for_core verb.  Strongly consider adding one before doing anything else.");
    else
      player:tell("Corified ", $string_utils:nn(dobj), " as $", iobjstr, ".");
    endif
  endverb

  verb "@make-guest" (any none none) owner: #2 flags: "rd"
    "Usage:  @make-guest <guestname>";
    "Creates a player called <guestname>_Guest owned by $hacker and a child of $guest. Or, if $local.guest exists, make a child of that, assuming that all other guests are children of it too.";
    let guestnum;
    let adj;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (!player.wizard)
      player:tell("If you think this MOO needs more guests, you should contact a wizard.");
      return E_PERM;
    endif
    if (length(args) != 1)
      player:tell("Usage: ", verb, " <guest name>");
      return;
    endif
    const guest_parent = $object_utils:has_property($local, "guest") && valid($local.guest) && $object_utils:isa($local.guest, $guest) ? $local.guest | $guest;
    let i = length(children(guest_parent));
    while (true)
      guestnum = tostr("Guest", i = i + 1);
      if (!!$player_db:available(guestnum))
        break;
      endif
    endwhile
    const guestname = args[1] + "_Guest";
    const guestaliases = {guestname, adj = args[1], guestnum};
    !player.wizard && return;
    if ($player_db.frozen)
      player:tell("Sorry, the player db is frozen, so no players can be made right now.  Please try again in a few minutes.");
      return;
    elseif (!$player_db:available(guestname))
      player:tell("\"", guestname, "\" is not an available name.");
      return;
    elseif (!$player_db:available(adj))
      player:Tell("\"", adj, "\" is not an available name.");
      return;
    else
      let new = $quota_utils:bi_create(guest_parent, $hacker);
      new:set_name(guestname);
      new:set_aliases(guestaliases);
      const e = $wiz_utils:set_player(new, 1);
      if (!e)
        player:Tell("Unable to make ", new.name, " (", new, ") a player.");
        player:Tell(tostr(e));
      else
        player:Tell("Guest: ", new.name, " (", new, ") made.");
        new.default_description = {"By definition, guests appear nondescript."};
        new.description = new.default_description;
        new.last_connect_time = $maxint;
        new.last_disconnect_time = time();
        new.password = 0;
        new.size_quota = new.size_quota;
        new:set_gender(new.default_gender);
        move(new, $player_start);
        player:tell("Now don't forget to @describe ", new, " as something.");
      endif
    endif
  endverb

  verb "@temp-newt" (any for any) owner: #2 flags: "rd"
    "Restrict a player for a specified duration and record the reason.";
    let howlong;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    !player.wizard && return player:tell("Permission denied.");
    const who = $string_utils:match_player(dobjstr);
    if (!valid(who))
      return $command_utils:player_match_failed(who, dobjstr);
    elseif (dobjstr != who.name && !(dobjstr in who.aliases) && dobjstr != tostr(who))
      return player:tell(tostr("Must be a full name or an object number:  ", who.name, "(", who, ")"));
    elseif (who == player)
      player:notify("If you want to newt yourself, you have to do it by hand.");
      return;
    else
      howlong = $time_utils:parse_english_time_interval(iobjstr);
      !howlong && return player:tell("Can't parse time: ", howlong);
      if (who in $login.newted)
        player:notify(tostr(who.name, " appears to already be a newt."));
      else
        $wiz_utils:newt_player(who, "", "For " + iobjstr + ".  ");
      endif
      const index = $list_utils:iassoc(who, $login.temporary_newts);
      if (index)
        $login.temporary_newts[index][2] = time();
        $login.temporary_newts[index][3] = howlong;
      else
        $login.temporary_newts = {@$login.temporary_newts, {who, time(), howlong}};
      endif
      player:tell(who.name, " (", who, ") will be a newt until ", ctime(time() + howlong));
    endif
  endverb

  verb "@deprog*rammer" (any any any) owner: #2 flags: "rd"
    "@deprogrammer victim [for <duration>] [reason]";
    "";
    "Removes the prog-bit from victim.  If a duration is specified (see help $time_utils:parse_english_time_interval), then the victim is put into the temporary list. He will be automatically removed the first time he asks for a progbit after the duration expires.  Either with or without the duration you can specify a reason, or you will be prompted for one. However, if you don't have a duration, don't start the reason with the word `For'.";
    let start;
    let duration;
    let reason;
    let result;
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (!player.wizard)
      player:notify("No go.");
      return;
    endif
    if (!args)
      player:notify(tostr("Usage:  ", verb, " <playername> [for <duration>] [reason]"));
    endif
    const fw = $string_utils:first_word(argstr);
    let parse = fw[2] ? player:parse_templist_duration(fw[2]) | {false};
    if (parse[1])
      if (typeof(parse[3]) == TYPE_ERR || !parse[3])
        player:notify(tostr("Could not parse the duration for restricting programming for ", fw[1], "."));
        return;
      endif
      start = parse[2];
      duration = parse[3];
      reason = parse[4] ? {parse[4]} | {};
    else
      start = duration = 0;
      reason = fw[2] ? {fw[2]} | {};
    endif
    if (!reason)
      reason = {$command_utils:read("reason for resetting programmer flag")};
    endif
    if (duration)
      reason = {tostr("for ", $time_utils:english_time(duration)), @reason};
    endif
    let victim = $string_utils:match_player(fw[1]);
    if ($command_utils:player_match_failed(victim, fw[1]))
      "...done...";
    else
      result = $wiz_utils:unset_programmer(victim, reason, @start ? {start, duration} | {});
      if (result)
        player:notify(tostr(victim.name, " (", victim, ") is no longer a programmer.", duration ? tostr("  This restriction will be lifted in ", $string_utils:from_seconds(duration), ".") | ""));
      elseif (result == E_NONE)
        player:notify(tostr(victim.name, " (", victim, ") was already a nonprogrammer..."));
      else
        player:notify(tostr(result));
      endif
    endif
  endverb

  verb "@lock-login @unlock-login @lock-login!" (any any any) owner: #2 flags: "rd"
    "Syntax:  @lock-login <message>";
    "         @lock-login! <message>";
    "         @unlock-login";
    "";
    "The @lock-login calls prevent all non-wizard users from logging in, displaying <message> to them when they try.  (The second syntax, with @lock-login!, additionally boots any nonwizards who are already connected.)  @unlock-login turns this off.";
    $wizard_feature in player.features || raise(E_PERM);
    player.wizard || return player:tell("Wizard permission required.");
    set_task_perms(player);
    if (caller != player)
      raise(E_PERM);
    elseif (verb[2] == "u")
      $no_connect_message = 0;
      player:notify("Login restrictions removed.");
    elseif (!argstr)
      player:notify("You must provide some message to display to users who attempt to login:  @lock-login <message>");
    else
      $no_connect_message = argstr;
      player:notify(tostr("Logins are now blocked for non-wizard players.  Message displayed when attempted:  ", $no_connect_message));
      if (verb == "@lock-login!")
        const wizards = $wiz_utils:all_wizards_unadvertised();
        for x in (connected_players())
          if (!(x in wizards))
            boot_player(x);
          endif
        endfor
        player:notify("All nonwizards have been booted.");
      endif
    endif
  endverb

  method feature_ok owner: #2
    "Require the player class that supplies this command pack's methods and state.";
    const {who} = args;
    return valid(who) && $object_utils:isa(who, $wiz);
  endmethod
endobject
