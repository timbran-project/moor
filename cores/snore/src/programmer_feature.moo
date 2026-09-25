object PROGRAMMER_FEATURE [
  import_export_id -> "programmer_feature"
]
  name: "Programmer Feature"
  parent: FEATURE
  owner: #2
  readable: true

  override feature_verbs (owner: HACKER, flags: "r") = {
    "@prop*erty",
    "@chmod*#",
    "@args*#",
    "eval*-d",
    "@rmprop*erty",
    "@verb",
    "@rmverb*#",
    "@forked*-verbose",
    "@kill",
    "@killq*uiet",
    "@copy",
    "@copy-x",
    "@copy-move",
    "@prog*ram",
    "@program#",
    "@setenv",
    "@pros*pectus",
    "pros*pectus",
    "@d*isplay",
    "@db*size",
    "@gethelp",
    "@grep*all",
    "@egrep*all",
    "@s*how",
    "@check-p*roperty",
    "@clearp*roperty",
    "@clprop*erty",
    "@disown",
    "@disinherit",
    "@dump",
    "#*",
    "@progo*ptions",
    "@prog-o*ptions",
    "@programmero*ptions",
    "@programmer-o*ptions",
    "@list*#",
    "@verbs*",
    "@old-forked-v*erbose",
    "@props",
    "@properties"
  };
  override help_msg (owner: #2, flags: "rc") = "Commands for $prog descendants. Installing this feature does not grant server permissions.";

  verb "@prop*erty" (any any any) owner: #2 flags: "rd"
    "Add a property with a value, permissions, and owner. Requires programmer permission.";
    let value;
    let owner;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (!player.programmer)
      player:notify("You need to be a programmer to do this.");
      player:notify("If you want to become a programmer, talk to a wizard.");
      return;
    endif
    if (!$quota_utils:property_addition_permitted(player))
      player:tell("Property addition not permitted because quota exceeded.");
      return;
    endif
    let nargs = length(args);
    const usage = tostr("Usage:  ", verb, " <object>.<prop-name> [<init_value> [<perms> [<owner>]]]");
    let spec = args ? $code_utils:parse_propref(args[1]) | {};
    if (!spec)
      player:notify(usage);
      return;
    endif
    const object = player:my_match_object(spec[1]);
    const name = spec[2];
    $command_utils:object_match_failed(object, spec[1]) && return;
    if (nargs < 2)
      value = 0;
    else
      const q = $string_utils:prefix_to_value(argstr[$string_utils:word_start(argstr)[2][1]..$]);
      if (q[1] == 0)
        player:notify(tostr("Syntax error in initial value:  ", q[2]));
        return;
      endif
      value = q[2];
      args = {args[1], value, @$string_utils:words(q[1])};
      nargs = length(args);
    endif
    let default = player:prog_option("@prop_flags");
    if (!default)
      default = "rc";
    endif
    const perms = nargs < 3 ? default | $perm_utils:apply(default, args[3]);
    if (nargs < 4)
      owner = player;
    else
      owner = $string_utils:match_player(args[4]);
      $command_utils:player_match_result(owner, args[4])[1] && return;
    endif
    if (nargs > 4)
      player:notify(usage);
      return;
    endif
    try
      add_property(object, name, value, {owner, perms});
      player:notify(tostr("Property added with value ", toliteral(object.(name)), "."));
    except (E_INVARG)
      if ($object_utils:has_property(object, name))
        player:notify(tostr("Property ", object, ".", name, " already exists."));
      else
        for i in [1..length(perms)]
          if (!index("rcw", perms[i]))
            player:notify(tostr("Unknown permission bit:  ", perms[i]));
            return;
          endif
        endfor
        "...the only other possibility...";
        player:notify("Property is already defined on one or more descendents.");
        player:notify(tostr("Try @check-prop ", args[1]));
      endif
    except e (ANY)
      player:notify(e[2]);
    endtry
  endverb

  verb "@chmod*#" (any any any) owner: #2 flags: "rd"
    "Change object, property, or verb permissions where your authority permits.";
    let object;
    let info;
    let result;
    let w;
    let f;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    const bynumber = verb == "@chmod#";
    if (length(args) != 2)
      player:notify(tostr("Usage:  ", verb, " <object-or-property-or-verb> <permissions>"));
      return;
    endif
    let {what, perms} = args;
    let spec = $code_utils:parse_verbref(what);
    if (spec)
      if (!player.programmer)
        player:notify("You need to be a programmer to do this.");
        player:notify("If you want to become a programmer, talk to a wizard.");
        return;
      endif
      object = player:my_match_object(spec[1]);
      if (valid(object))
        let vname = spec[2];
        if (bynumber)
          vname = $code_utils:toint(vname);
          vname == E_TYPE && return player:notify("Verb number expected.");
          if (vname < 1 || `vname > length(verbs(object)) ! E_PERM => 0')
            return player:notify("Verb number out of range.");
          endif
        endif
        try
          info = verb_info(object, vname);
          const owner = info[1];
          if (!valid(owner))
            player:notify(tostr("That verb is owned by an invalid object (", owner, "); it needs to be @chowned."));
          elseif (!is_player(owner))
            player:notify(tostr("That verb is owned by a non-player object (", owner.name, ", ", owner, "); it needs to be @chowned."));
          else
            info[2] = perms = $perm_utils:apply(info[2], perms);
            try
              result = set_verb_info(object, vname, info);
              player:notify(tostr("Verb permissions set to \"", perms, "\"."));
            except (E_INVARG)
              player:notify(tostr("\"", perms, "\" is not a valid permissions string for a verb."));
            except e (ANY)
              player:notify(e[2]);
            endtry
          endif
        except (E_VERBNF)
          player:notify("That object does not define that verb.");
        except error (ANY)
          player:notify(error[2]);
        endtry
        return;
      endif
    elseif (bynumber)
      return player:notify("@chmod# can only be used for verbs.");
    else
      spec = index(what, ".") ? $code_utils:parse_propref(what) | {};
      if (spec)
        object = player:my_match_object(spec[1]);
        if (valid(object))
          const pname = spec[2];
          try
            info = property_info(object, pname);
            info[2] = perms = $perm_utils:apply(info[2], perms);
            try
              result = set_property_info(object, pname, info);
              player:notify(tostr("Property permissions set to \"", perms, "\"."));
            except (E_INVARG)
              player:notify(tostr("\"", perms, "\" is not a valid permissions string for a property."));
            except error (ANY)
              player:notify(error[2]);
            endtry
          except (E_PROPNF)
            player:notify("That object does not have that property.");
          except error (ANY)
            player:notify(error[2]);
          endtry
          return;
        endif
      else
        object = player:my_match_object(what);
        if (valid(object))
          perms = $perm_utils:apply((object.r ? "r" | "") + (object.w ? "w" | "") + (object.f ? "f" | ""), perms);
          let r = w = (f = 0);
          for i in [1..length(perms)]
            if (perms[i] == "r")
              r = 1;
            elseif (perms[i] == "w")
              w = 1;
            elseif (perms[i] == "f")
              f = 1;
            else
              player:notify(tostr("\"", perms, "\" is not a valid permissions string for an object."));
              return;
            endif
          endfor
          try
            object.r = r;
            object.w = w;
            object.f = f;
            player:notify(tostr("Object permissions set to \"", perms, "\"."));
          except (E_PERM)
            player:notify("Permission denied.");
          endtry
          return;
        endif
      endif
    endif
    $command_utils:object_match_failed(object, what);
  endverb

  verb "@args*#" (any any any) owner: #2 flags: "rd"
    "Change the argument specification of a verb you control.";
    let object;
    let name;
    let newargs;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    player != caller && return;
    set_task_perms(player);
    if (!player.programmer)
      player:notify("You need to be a programmer to do this.");
      player:notify("If you want to become a programmer, talk to a wizard.");
      return;
    endif
    let spec = args ? $code_utils:parse_verbref(args[1]) | {};
    if (!spec)
      player:notify(tostr(args ? "\"" + args[1] + "\"?  " | "", "<object>:<verb>  expected."));
    else
      object = player:my_match_object(spec[1]);
      if ($command_utils:object_match_failed(object, spec[1]))
        "...can't find object...";
      else
        if (verb == "@args#")
          name = $code_utils:toint(spec[2]);
          name == E_TYPE && return player:notify("Verb number expected.");
          if (name < 1 || `name > length(verbs(object)) ! E_PERM => 0')
            return player:notify("Verb number out of range.");
          endif
        else
          name = spec[2];
        endif
        try
          let info = verb_args(object, name);
          const pas = $code_utils:parse_argspec(@listdelete(args, 1));
          if (typeof(pas) != TYPE_LIST)
            "...arg spec is bogus...";
            player:notify(tostr(pas));
          else
            newargs = pas[1];
            if (!newargs)
              player:notify($string_utils:from_list(info, " "));
            elseif (pas[2])
              player:notify(tostr("\"", pas[2][1], "\" unexpected."));
            else
              info[2] = info[2][1..index(info[2] + "/", "/") - 1];
              info = {@newargs, @info[length(newargs) + 1..$]};
              try
                const result = set_verb_args(object, name, info);
                player:notify("Verb arguments changed.");
              except (E_INVARG)
                player:notify(tostr("\"", info[2], "\" is not a valid preposition (?)"));
              except error (ANY)
                player:notify(error[2]);
              endtry
            endif
          endif
        except (E_VERBNF)
          player:notify("That object does not have a verb with that name.");
        except error (ANY)
          player:notify(error[2]);
        endtry
      endif
    endif
  endverb

  verb "eval*-d" (any any any) owner: #2 flags: "rd"
    "A MOO-code evaluator.  Type `;CODE' or `eval CODE'.";
    "Calls player:eval_cmd_string to first transform CODE in any way appropriate (e.g., prefixing .eval_env) and then do the actual evaluation.  See documentation for this:eval_cmd_string";
    "If you set your .eval_time property to 1, you find out how many ticks and seconds you used.";
    "If eval-d is used, the evaluation is performed as if the debug flag were unset.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (!player.programmer)
      player:tell("You need to be a programmer to eval code.");
      return;
    endif
    set_task_perms(player);
    const result = player:eval_cmd_string(argstr, verb != "eval-d");
    if (result[1])
      player:notify(player:eval_value_to_string(result[2]));
      if (player:prog_option("eval_time") && !(`output_delimiters(player)[2] ! ANY'))
        player:notify(tostr("[used ", result[3], " tick", result[3] != 1 ? "s, " | ", ", result[4], " second", result[4] != 1 ? "s" | "", ".]"));
      endif
    else
      player:notify_lines(result[2]);
      const nerrors = length(result[2]);
      player:notify(tostr(nerrors, " error", nerrors == 1 ? "." | "s."));
    endif
  endverb

  verb "@rmprop*erty" (any any any) owner: #2 flags: "rd"
    "Remove a property you control.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    let spec = length(args) == 1 ? $code_utils:parse_propref(args[1]) | {};
    if (!spec)
      player:notify(tostr("Usage:  ", verb, " <object>.<property>"));
      return;
    endif
    const object = player:my_match_object(spec[1]);
    const pname = spec[2];
    $command_utils:object_match_failed(object, spec[1]) && return;
    try
      const result = delete_property(object, pname);
      player:notify("Property removed.");
    except (E_PROPNF)
      player:notify("That object does not define that property.");
    except res (ANY)
      player:notify(res[2]);
    endtry
  endverb

  verb "@verb" (any any any) owner: #2 flags: "rd"
    "Add a verb with an argument specification. Requires programmer permission.";
    let perms;
    let owner;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (!player.programmer)
      player:notify("You need to be a programmer to do this.");
      player:notify("If you want to become a programmer, talk to a wizard.");
      return;
    endif
    if (!$quota_utils:verb_addition_permitted(player))
      player:tell("Verb addition not permitted because quota exceeded.");
      return;
    endif
    let spec = args ? $code_utils:parse_verbref(args[1]) | {};
    if (!spec)
      player:notify(tostr("Usage:  ", verb, " <object>:<verb-name(s)> [<dobj> [<prep> [<iobj> [<permissions> [<owner>]]]]]"));
      return;
    endif
    const object = player:my_match_object(spec[1]);
    if ($command_utils:object_match_failed(object, spec[1]))
      return;
    endif
    const name = spec[2];
    "...Adding another verb of the same name is often a mistake...";
    const namelist = $string_utils:explode(name);
    for n in (namelist)
      const i = index(n, "*");
      if (i)
        n = n[1..i - 1] + n[i + 1..$];
      endif
      const hv = $object_utils:has_verb(object, n);
      if (hv && hv[1] == object)
        player:notify(tostr("Warning:  Verb `", n, "' already defined on that object."));
      endif
    endfor
    const pas = $code_utils:parse_argspec(@listdelete(args, 1));
    if (typeof(pas) != TYPE_LIST)
      player:notify(tostr(pas));
      return;
    endif
    let verbargs = pas[1] || (player:prog_option("verb_args") || {});
    verbargs = {@verbargs, "none", "none", "none"}[1..3];
    const rest = pas[2];
    if (verbargs == {"this", "none", "this"})
      perms = "rxd";
    else
      perms = "rd";
    endif
    if (rest)
      perms = $perm_utils:apply(perms, rest[1]);
    endif
    if (length(rest) < 2)
      owner = player;
    elseif (length(rest) > 2)
      player:notify(tostr("\"", rest[3], "\" unexpected."));
      return;
    else
      owner = $string_utils:match_player(rest[2]);
      if ($command_utils:player_match_result(owner, rest[2])[1])
        return;
      elseif (owner == $nothing)
        player:notify("Verb can't be owned by no one!");
        return;
      endif
    endif
    try
      const x = add_verb(object, {owner, perms, name}, verbargs);
      player:notify(tostr("Verb added (", x > 0 ? x | length($object_utils:accessible_verbs(object)), ")."));
    except (E_INVARG)
      player:notify(tostr(rest ? tostr("\"", perms, "\" is not a valid set of permissions.") | tostr("\"", verbargs[2], "\" is not a valid preposition (?)")));
    except e (ANY)
      player:notify(e[2]);
    endtry
  endverb

  verb "@rmverb*#" (any none none) owner: #2 flags: "rd"
    "Remove a verb you control, by name or number.";
    let object;
    let argspec;
    let loc;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    let spec = args ? $code_utils:parse_verbref(args[1]) | {};
    if (!spec)
      player:notify(tostr("Usage:  ", verb, " <object>:<verb>"));
    else
      object = player:my_match_object(spec[1]);
      if ($command_utils:object_match_failed(object, spec[1]))
        "...bogus object...";
      else
        argspec = $code_utils:parse_argspec(@listdelete(args, 1));
        if (typeof(argspec) != TYPE_LIST)
          player:notify(tostr(argspec));
        elseif (argspec[2])
          player:notify($string_utils:from_list(argspec[2], " ") + "??");
        else
          argspec = argspec[1];
          if (length(argspec) in {1, 2})
            player:notify({"Missing preposition", "Missing iobj specification"}[length(argspec)]);
          else
            let verbname = spec[2];
            if (verb == "@rmverb#")
              loc = $code_utils:toint(verbname);
              loc == E_TYPE && return player:notify("Verb number expected.");
              if (loc < 1 || loc > `length(verbs(object)) ! E_PERM => 0')
                return player:notify("Verb number out of range.");
              endif
            else
              if (index(verbname, "*") > 1)
                verbname = strsub(verbname, "*", "");
              endif
              loc = $code_utils:find_last_verb_named(object, verbname);
              if (argspec)
                argspec[2] = $code_utils:full_prep(argspec[2]) || argspec[2];
                while (loc != -1 && `verb_args(object, loc) ! ANY' != argspec)
                  loc = $code_utils:find_last_verb_named(object, verbname, loc - 1);
                endwhile
              endif
              if (loc < 0)
                player:notify(tostr("That object does not define that verb", argspec ? " with those args." | "."));
                return;
              endif
            endif
            const info = `verb_info(object, loc) ! ANY';
            const vargs = `verb_args(object, loc) ! ANY';
            const vcode = `verb_code(object, loc, 1, 1) ! ANY';
            try
              delete_verb(object, loc);
              if (info)
                player:notify(tostr("Verb ", object, ":", info[3], " (", loc, ") {", $string_utils:from_list(vargs, " "), "} removed."));
                if (player:prog_option("rmverb_mail_backup"))
                  $mail_agent:send_message(player, player, tostr(object, ":", info[3], " (", loc, ") {", $string_utils:from_list(vargs, " "), "}"), vcode);
                endif
              else
                player:notify(tostr("Unreadable verb ", object, ":", loc, " removed."));
              endif
            except e (ANY)
              player:notify(e[2]);
            endtry
          endif
        endif
      endif
    endif
  endverb

  verb "@forked*-verbose" (any none none) owner: #2 flags: "rd"
    "Syntax:  @forked [player]";
    "         @forked all wizards";
    "";
    "For a normal player, shows all the tasks you have waiting in your queue, especially those forked or suspended. A wizard will see all the tasks of all the players unless the optional argument is provided. @forked-v*erbose will show the full callers() stack for each task that has suspended (not a fresh fork).";
    "The second form is only usable by wizards and provides an output of all tasks owned by characters who are .wizard=1. Useful to find a task that may get put in a random queue due to $wiz_utils:random_wizard. Or even finding verbs that run with wizard permissions that shouldn't be.";
    let tasks;
    let q_id;
    let start;
    let nu;
    let nu2;
    let owner;
    let vloc;
    let vname;
    let lineno;
    let size;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const verbose = $code_utils:verbname_match("@forked-v*erbose", verb);
    if (!dobjstr)
      tasks = queued_tasks();
    elseif (dobjstr == "all wizards" && player.wizard)
      tasks = {};
      for t in (queued_tasks())
        if (valid(t[5]) && t[5].wizard)
          tasks = {@tasks, t};
        endif
        $command_utils:suspend_if_needed(1);
      endfor
    else
      dobj = $string_utils:match_player(dobjstr);
      if ($command_utils:player_match_result(dobj, dobjstr)[1])
        return;
      else
        tasks = $wiz_utils:queued_tasks(dobj);
        if (typeof(tasks) != TYPE_LIST)
          player:notify(tostr(verb, " ", dobj.name, "(", dobj, "):  ", tasks));
          return;
        endif
      endif
    endif
    if (tasks)
      const su = $string_utils;
      player:notify("Queue ID    Start Time            Owner         {Size} Verb (Line) [This]");
      player:notify("--------    ----------            -----         -----------------");
      const now = time();
      for task in (tasks)
        $command_utils:suspend_if_needed(0);
        {q_id, start, nu, nu2, owner, vloc, vname, lineno, player, ?size = 0} = task;
        const time = start >= now ? ctime(start)[5..24] | su:left(start == -1 ? "Reading input ..." | tostr(now - start, " seconds ago..."), 20);
        const owner_name = valid(owner) ? owner.name | tostr("Dead ", owner);
        player:notify(tostr(su:left(tostr(q_id), 10), "  ", time, "  ", su:left(owner_name, 12), "  {", $building_utils:size_string(size), "} ", vloc, ":", vname, " (", lineno, ")", player != vloc ? tostr(" [", player, "]") | ""));
        if (verbose || (index(vname, "suspend") && vloc == $command_utils))
          "Display the first (or, if verbose, every) line of the callers() list, which is gotten by taking the second through last elements of task_stack().";
          const stack = `task_stack(q_id, 1) ! E_INVARG => {}';
          for frame in (stack[2..verbose ? $ | 2])
            const {sthis, svname, sprogger, svloc, splayer, slineno} = frame;
            player:notify(tostr("                    Called By...  ", su:left(valid(sprogger) ? sprogger.name | tostr("Dead ", sprogger), 19), "  ", svloc, ":", svname, sthis != svloc ? tostr(" [", sthis, "]") | "", " (", slineno, ")"));
          endfor
        endif
      endfor
      player:notify("-----------------------------------------------------------------");
    else
      player:notify("No tasks.");
    endif
  endverb

  verb "@kill @killq*uiet" (any none none) owner: #2 flags: "rd"
    "Kills one or more tasks.";
    "Arguments:";
    "   object:verb -- kills all tasks which were started from that object and verb.";
    "   all -- kills all tasks owned by invoker";
    "   all player-name -- wizard variant:  kills all tasks owned by player.";
    "   all everyone -- wizard variant:  really kills all tasks.";
    "   Integer taskid -- kills the specifically named task.";
    "   soon [integer] -- kills all tasks scheduled to run in the next [integer] seconds, which defaults to 60.";
    "   %integer -- kills all tasks which end in the digits contained in integer.";
    "   The @killquiet alias kills tasks without the pretty printout if more than one task is being killed.";
    let all;
    let everyone;
    let realplayer;
    let soon;
    let percent;
    let digits;
    let colon;
    let whatstr;
    let vrb;
    let what;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const quiet = index(verb, "q");
    if (length(args) == 0)
      player:notify_lines({tostr("Usage:  ", verb, " [object]:[verb]"), tostr("        ", verb, " task_id"), tostr("        ", verb, " soon [number-of-seconds]", player.wizard ? " [everyone|<player name>]" | ""), tostr("        ", verb, " all", player.wizard ? " [everyone|<player name>]" | "")});
      return;
    endif
    const taskid = toint(args[1]);
    if (taskid)
    else
      all = args[1] == "all";
      if (all)
        everyone = 0;
        realplayer = player;
        if (player.wizard && length(args) > 1)
          realplayer = $string_utils:match_player(args[2]);
          everyone = args[2] == "everyone";
          if (!valid(realplayer) && !everyone)
            $command_utils:player_match_result(realplayer, args[2]);
            return;
          endif
          if (!everyone)
            set_task_perms(realplayer);
          endif
        endif
      else
        soon = args[1] == "soon";
        if (soon)
          realplayer = player;
          if (length(args) > 1)
            soon = toint(args[2]);
            if (soon <= 0 && !player.wizard)
              player:notify(tostr("Usage:  ", verb, " soon [positive-number-of-seconds]"));
              return;
            endif
            if (player.wizard)
              const result = player:kill_aux_wizard_parse(@args[2..$]);
              soon = result[1];
              if (result[1] < 0)
                "already gave them an error message";
                return;
              endif
              if (result[2] == 1)
                everyone = 1;
              else
                everyone = 0;
                set_task_perms(result[2]);
                realplayer = result[2];
              endif
            endif
          else
            soon = 60;
            everyone = 0;
          endif
        else
          percent = args[1][1] == "%";
          if (percent)
            const l = length(args[1]);
            digits = toint(args[1][2..l]);
            percent = toint("1" + "0000000000"[1..l - 1]);
          else
            colon = index(argstr, ":");
            if (colon)
              whatstr = argstr[1..colon - 1];
              vrb = argstr[colon + 1..$];
              if (whatstr)
                what = player:my_match_object(whatstr);
              endif
            else
              player:notify_lines({tostr("Usage:  ", verb, " [object]:[verb]"), tostr("        ", verb, " task_id"), tostr("        ", verb, " soon [number-of-seconds]", player.wizard ? " [everyone|<player name>]" | ""), tostr("        ", verb, " all", player.wizard ? " [\"everyone\"|<player name>]" | "")});
              return;
            endif
          endif
        endif
      endif
    endif
    "OK, parsed the line, and punted them if it was bogus.  This verb could have been a bit shorter at the expense of readability.  I think it's getting towards unreadable as is.  At this point we've set_task_perms'd, and set up an enormous number of local variables.  Evaluate them in the order we set them, and we should never get var not found.";
    const queued_tasks = queued_tasks();
    let killed = 0;
    if (taskid)
      try
        kill_task(taskid);
        player:notify(tostr("Killed task ", taskid, "."));
        killed = 1;
      except error (ANY)
        player:notify(tostr("Can't kill task ", taskid, ": ", error[2]));
      endtry
    elseif (all)
      for task in (queued_tasks)
        if (everyone || realplayer == task[5])
          `kill_task(task[1]) ! ANY';
          killed = killed + 1;
          if (!quiet)
            player:_kill_task_message(task);
          endif
        endif
        $command_utils:suspend_if_needed(3, "... killing tasks");
      endfor
    elseif (soon)
      const now = time();
      for task in (queued_tasks)
        if (task[2] - now < soon && (!player.wizard || (everyone || realplayer == task[5])))
          `kill_task(task[1]) ! ANY';
          killed = killed + 1;
          if (!quiet)
            player:_kill_task_message(task);
          endif
        endif
        $command_utils:suspend_if_needed(3, "... killing tasks");
      endfor
    elseif (percent)
      for task in (queued_tasks)
        if (digits == task[1] % percent)
          `kill_task(task[1]) ! ANY';
          killed = killed + 1;
          if (!quiet)
            player:_kill_task_message(task);
          endif
        endif
        $command_utils:suspend_if_needed(3, "... killing tasks");
      endfor
    elseif (colon || vrb || whatstr)
      for task in (queued_tasks)
        if (whatstr == "" || (valid(task[6]) && index(task[6].name, whatstr) == 1) || (valid(task[9]) && index(task[9].name, whatstr) == 1) || task[9] == what || task[6] == what && (vrb == "" || index(" " + strsub(task[7], "*", ""), " " + vrb) == 1))
          `kill_task(task[1]) ! ANY';
          killed = killed + 1;
          if (!quiet)
            player:_kill_task_message(task);
          endif
        endif
        $command_utils:suspend_if_needed(3, "... killing tasks");
      endfor
    else
      player:notify("Something is funny; I didn't understand your @kill command.  You shouldn't have gotten here.  Please send yduJ mail saying you got this message from @kill, and what you had typed to @kill.");
    endif
    if (!killed)
      player:notify("No tasks killed.");
    elseif (quiet)
      player:notify(tostr("Killed ", killed, " tasks."));
    endif
  endverb

  verb "@copy @copy-x @copy-move" (any at any) owner: #2 flags: "rd"
    "Usage:  @copy source:verbname to target[:verbname]";
    "  the target verbname, if not given, defaults to that of the source.  If the target verb doesn't already exist, a new verb is installed with the same args, names, code, and permission flags as the source.  Otherwise, the existing target's verb code is overwritten and no other changes are made.";
    "This the poor man's version of multiple inheritance... the main problem is that someone may update the verb you're copying and you'd never know.";
    "  if @copy-x is used, makes an unusable copy (!x, this none this).  If @copy-move is used, deletes the source verb as well.";
    let from;
    let fobj;
    let to;
    let tobj;
    let vargs;
    let e;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (!player.programmer)
      player:notify("You need to be a programmer to do this.");
      player:notify("If you want to become a programmer, talk to a wizard.");
      return;
    endif
    if (verb != "@copy-move" && !$quota_utils:verb_addition_permitted(player))
      player:notify("Verb addition not permitted because quota exceeded.");
      return;
    else
      from = $code_utils:parse_verbref(dobjstr);
      if (!from || !iobjstr)
        player:notify(tostr("Usage:  ", verb, " obj:verb to obj:verb"));
        player:notify(tostr("        ", verb, " obj:verb to obj"));
        player:notify(tostr("        ", verb, " obj:verb to :verb"));
        return;
      else
        fobj = player:my_match_object(from[1]);
        if ($command_utils:object_match_failed(fobj, from[1]))
          return;
        elseif (iobjstr[1] == ":")
          to = {fobj, iobjstr[2..$]};
        else
          to = $code_utils:parse_verbref(iobjstr);
          if (!to)
            iobj = player:my_match_object(iobjstr);
            $command_utils:object_match_failed(iobj, iobjstr) && return;
            to = {iobj, from[2]};
          else
            tobj = player:my_match_object(to[1]);
            if ($command_utils:object_match_failed(tobj, to[1]))
              return;
            else
              to[1] = tobj;
            endif
          endif
        endif
      endif
    endif
    from[1] = fobj;
    if (verb == "@copy-move")
      if (!$perm_utils:controls(player, fobj) && !$quota_utils:verb_addition_permitted(player))
        player:notify("Won't be able to delete old verb.  Quota exceeded, so unable to continue.  Aborted.");
        return;
      endif
      if ($perm_utils:controls(player, fobj))
        "only try to move if the player controls the verb. Otherwise, skip and treat as regular @copy";
        const result = $code_utils:move_verb(@from, @to);
        if (typeof(result) == TYPE_ERR)
          player:notify(tostr("Unable to move verb from ", from[1], ":", from[2], " to ", to[1], ":", to[2], " --> ", result));
        else
          player:notify(tostr("Moved verb from ", from[1], ":", from[2], " to ", result[1], ":", result[2]));
        endif
        return;
      else
        player:notify("Won't be able to delete old verb.  Treating this as regular @copy.");
      endif
    endif
    const to_firstname = strsub(to[2][1..index(to[2] + " ", " ") - 1], "*", "") || "*";
    const hv = $object_utils:has_verb(to[1], to_firstname);
    if (!hv || hv[1] != to[1])
      let info = `verb_info(@from) ! ANY';
      vargs = info ? `verb_args(@from) ! ANY' | {};
      if (!info || !vargs)
        player:notify(tostr("Retrieving ", from[1], ":", from[2], " --> ", info && vargs));
        return;
      endif
      if (!player.wizard)
        info[1] = player;
      endif
      if (verb == "@copy-x")
        "... make sure this is an unusable copy...";
        info[2] = strsub(info[2], "x", "");
        vargs = {"this", "none", "this"};
      endif
      if (from[2] != to[2])
        info[3] = to[2];
      endif
      e = `add_verb(to[1], info, vargs) ! ANY';
      if (TYPE_ERR == typeof(e))
        player:notify(tostr("Adding ", to[1], ":", to[2], " --> ", e));
        return;
      endif
    endif
    let code = `verb_code(@from) ! ANY';
    const owner = `verb_info(@from)[1] ! ANY';
    if (typeof(code) == TYPE_ERR)
      player:notify(tostr("Couldn't retrieve code from ", from[1].name, " (", from[1], "):", from[2], " => ", code));
      return;
    endif
    if (owner != player)
      const comment = tostr("Copied from ", $string_utils:nn(from[1]), ":", from[2], from[1] == owner ? "" | tostr(" [verb author ", $string_utils:nn(owner), "]"), " at ", ctime());
      code = {$string_utils:print(comment) + ";", @code};
      if (!player:prog_option("copy_expert"))
        player:notify("Use of @copy is discouraged.  Please do not use @copy if you can use inheritance or features instead.  Use @copy carefully, and only when absolutely necessary, as it is wasteful of database space.");
      endif
    endif
    e = `set_verb_code(to[1], to_firstname, code) ! ANY';
    if (TYPE_ERR == typeof(e))
      player:notify(tostr("Copying ", from[1], ":", from[2], " to ", to[1], ":", to[2], " --> ", e));
    elseif (typeof(e) == TYPE_LIST && e)
      player:notify(tostr("Copying ", from[1], ":", from[2], " to ", to[1], ":", to[2], " -->"));
      player:notify_lines(e);
    else
      player:notify(tostr(to[1], ":", to[2], " code set."));
    endif
  endverb

  verb "@prog*ram @program#" (any any any) owner: #2 flags: "rd"
    "This version of @program deals with multiple verbs having the same name.";
    "... @program <object>:<verbname> <dobj> <prep> <iobj>  picks the right one.";
    let object;
    let argspec;
    let verbname;
    let loc;
    let aliases;
    let active;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    player != caller && return;
    set_task_perms(player);
    "...";
    "...catch usage errors first...";
    "...";
    let punt = "...set punt to 0 only if everything works out...";
    let spec = args ? $code_utils:parse_verbref(args[1]) | {};
    if (!spec)
      player:notify(tostr("Usage: ", verb, " <object>:<verb> [<dobj> <prep> <iobj>]"));
    else
      object = player:my_match_object(spec[1]);
      if ($command_utils:object_match_failed(object, spec[1]))
        "...bogus object...";
      else
        argspec = $code_utils:parse_argspec(@listdelete(args, 1));
        if (typeof(argspec) != TYPE_LIST)
          player:notify(tostr(argspec));
        elseif (verb == "@program#")
          verbname = $code_utils:toint(spec[2]);
          if (verbname == E_TYPE)
            player:notify("Verb number expected.");
          elseif (length(args) > 1)
            player:notify("Don't give args for @program#.");
          elseif (verbname < 1 || `verbname > length(verbs(object)) ! E_PERM')
            player:notify("Verb number out of range.");
          else
            argspec = 0;
            punt = 0;
          endif
        elseif (argspec[2])
          player:notify($string_utils:from_list(argspec[2], " ") + "??");
        else
          argspec = argspec[1];
          if (length(argspec) in {1, 2})
            player:notify({"Missing preposition", "Missing iobj specification"}[length(argspec)]);
          else
            punt = 0;
            verbname = spec[2];
            if (index(verbname, "*") > 1)
              verbname = strsub(verbname, "*", "");
            endif
          endif
        endif
      endif
    endif
    "...";
    "...if we have an argspec, we'll need to reset verbname...";
    "...";
    if (punt)
    elseif (argspec)
      if (!(argspec[2] in {"none", "any"}))
        argspec[2] = $code_utils:full_prep(argspec[2]);
      endif
      loc = $code_utils:find_verb_named(object, verbname);
      while (loc > 0 && `verb_args(object, loc) ! ANY' != argspec)
        loc = $code_utils:find_verb_named(object, verbname, loc + 1);
      endwhile
      if (!loc)
        punt = "...can't find it....";
        player:notify("That object has no verb matching that name + args.");
      else
        verbname = loc;
      endif
    else
      loc = 0;
    endif
    "...";
    "...get verb info...";
    "...";
    if (!punt)
      punt = true;
      try
        const info = verb_info(object, verbname);
        punt = 0;
        aliases = info[3];
        if (!loc)
          loc = aliases in (verbs(object) || {});
        endif
      except (E_VERBNF)
        player:notify("That object does not have that verb definition.");
      except error (ANY)
        player:notify(error[2]);
      endtry
    endif
    "...";
    "...read the code...";
    "...";
    if (punt)
      player:notify(tostr("Now ignoring code for ", args ? args[1] | "nothing in particular", "."));
      $command_utils:read_lines();
      player:notify("Verb code ignored.");
    else
      player:notify(tostr("Now programming ", object.name, ":", aliases, "(", !loc ? "??" | loc, ")."));
      const lines = $command_utils:read_lines_escape((active = player in $verb_editor.active) ? {} | {"@edit"}, {tostr("You are editing ", $string_utils:nn(object), ":", verbname, "."), @active ? {} | {"Type `@edit' to take this into the verb editor."}});
      if (lines[1] == "@edit")
        $verb_editor:invoke(args[1], "@program", lines[2]);
        return;
      endif
      try
        const result = set_verb_code(object, verbname, lines[2]);
        if (result)
          player:notify_lines(result);
          player:notify(tostr(length(result), " error(s)."));
          player:notify("Verb not programmed.");
        else
          player:notify("0 errors.");
          player:notify("Verb programmed.");
        endif
      except error (ANY)
        player:notify(error[2]);
        player:notify("Verb not programmed.");
      endtry
    endif
  endverb

  verb "@setenv" (any any any) owner: #2 flags: "rd"
    "Usage: @setenv <environment string>";
    "Set your .eval_env property.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (!argstr)
      player:notify(tostr("Usage:  ", verb, " <environment string>"));
      return;
    endif
    player:notify(tostr("Current eval environment is: ", player.eval_env));
    const result = player:set_eval_env(argstr);
    if (typeof(result) == TYPE_ERR)
      player:notify(tostr(result));
      return;
    endif
    player:notify(tostr(".eval_env set to \"", player.eval_env, "\" (", player.eval_ticks, " ticks)."));
  endverb

  verb "@pros*pectus pros*pectus" (any any any) owner: #2 flags: "rd"
    "Usage: @prospectus <player> [from <start>] [to <end>]";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(caller_perms() == $nothing ? player | caller_perms());
    dobj = dobjstr ? $string_utils:match_player(dobjstr) | player;
    $command_utils:player_match_result(dobj, dobjstr)[1] && return;
    const dobjwords = $string_utils:words(dobjstr);
    if (args[1..length(dobjwords)] == dobjwords)
      args = args[length(dobjwords) + 1..$];
    endif
    const parse_result = $code_utils:_parse_audit_args(@args);
    if (!parse_result)
      player:notify(tostr("Usage:  ", verb, " player [from <start>] [to <end>]"));
      return;
    endif
    return $building_utils:do_prospectus(dobj, @parse_result);
  endverb

  verb "@d*isplay" (any none none) owner: #2 flags: "rd"
    "@display <object>[.[property]]*[,[inherited_property]]*[:[verb]]*[;[inherited_verb]]*";
    "null names for properties and verbs are interpreted as meaning all of them.";
    let y;
    let prop;
    let what;
    let inh;
    let vrbs;
    let p;
    let inf;
    let i;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    let opivu = {{}, {}, {}, {}, {}};
    let string = "";
    let punc = 1;
    let literal = 0;
    set_task_perms(player);
    for jj in [1..length(argstr)]
      const j = argstr[jj];
      if (literal)
        string = string + j;
        literal = 0;
      elseif (j == "\\")
        literal = 1;
      else
        y = index(".,:;", j);
        if (y)
          opivu[punc] = {@opivu[punc], string};
          punc = 1 + y;
          string = "";
        else
          string = string + j;
        endif
      endif
    endfor
    opivu[punc] = {@opivu[punc], string};
    const objname = opivu[1][1];
    const it = player:my_match_object(objname);
    $command_utils:object_match_failed(it, objname) && return;
    const readable = it.owner == player || (it.r || player.wizard);
    let cant = {};
    if ("" in opivu[2])
      if (readable)
        prop = properties(it);
      else
        prop = {};
        cant = setadd(cant, it);
      endif
      if (!player:display_option("thisonly"))
        what = it;
        while (true)
          if (!prop)
            what = parent(what);
          endif
          if (!(!prop && valid(what)))
            break;
          endif
          if (what.owner == player || (what.r || player.wizard))
            prop = properties(what);
          else
            cant = setadd(cant, what);
          endif
        endwhile
      endif
    else
      prop = opivu[2];
    endif
    if ("" in opivu[3])
      inh = {};
      for what in ({it, @$object_utils:ancestors(it)})
        if (what.owner == player || what.r || player.wizard)
          inh = {@inh, @properties(what)};
        else
          cant = setadd(cant, what);
        endif
      endfor
    else
      inh = opivu[3];
    endif
    for q in (inh)
      if (q in `properties(it) ! ANY => {}')
        prop = setadd(prop, q);
        inh = setremove(inh, q);
      endif
    endfor
    let vrb = {};
    if ("" in opivu[4])
      if (readable)
        vrbs = verbs(it);
      else
        vrbs = $object_utils:accessible_verbs(it);
        cant = setadd(cant, it);
      endif
      what = it;
      if (!player:display_option("thisonly"))
        while (true)
          if (!vrbs)
            what = parent(what);
          endif
          if (!(!vrbs && valid(what)))
            break;
          endif
          if (what.owner == player || (what.r || player.wizard))
            vrbs = verbs(what);
          else
            cant = setadd(cant, what);
          endif
        endwhile
      endif
      for n in [1..length(vrbs)]
        vrb = setadd(vrb, {what, n});
      endfor
    else
      for w in (opivu[4])
        y = $object_utils:has_verb(it, w);
        if (y)
          vrb = setadd(vrb, {y[1], w});
        else
          player:notify(tostr("No such verb, \"", w, "\""));
        endif
      endfor
    endif
    if ("" in opivu[5])
      for z in ({it, @$object_utils:ancestors(it)})
        if (player == z.owner || z.r || player.wizard)
          for n in [1..length(verbs(z))]
            vrb = setadd(vrb, {z, n});
          endfor
        else
          cant = setadd(cant, z);
        endif
      endfor
    else
      for w in (opivu[5])
        y = $object_utils:has_verb(it, w);
        if (typeof(y) == TYPE_LIST)
          vrb = setadd(vrb, {y[1], w});
        else
          player:notify(tostr("No such verb, \"", w, "\""));
        endif
      endfor
    endif
    if ({""} in opivu || opivu[2..5] == {{}, {}, {}, {}})
      player:notify(tostr(it.name, " (", it, ") [ ", it.r ? "readable " | "", it.w ? "writeable " | "", it.f ? "fertile " | "", is_player(it) ? "(player) " | "", it.programmer ? "programmer " | "", it.wizard ? "wizard " | "", "]"));
      if (it.owner != (is_player(it) ? it | player))
        player:notify(tostr("  Owned by ", valid(p = it.owner) ? p.name | "** extinct **", " (", p, ")."));
      endif
      player:notify(tostr("  Child of ", valid(p = parent(it)) ? p.name | "** none **", " (", p, ")."));
      if (it.location != $nothing)
        player:notify(tostr("  Location ", valid(p = it.location) ? p.name | "** unplace (tell a wizard, fast!) **", " (", p, ")."));
      endif
      if ($quota_utils.byte_based && $object_utils:has_property(it, "object_size"))
        player:notify(tostr("  Size: ", $string_utils:group_number(it.object_size[1]), " bytes at ", player:ctime(it.object_size[2])));
      endif
    endif
    const blankargs = player:display_option("blank_tnt") ? {"this", "none", "this"} | #-1;
    for b in (vrb)
      $command_utils:suspend_if_needed(0);
      const where = b[1];
      q = b[2];
      const short = typeof(q) == TYPE_INT ? q | strsub(y = index(q, " ") ? q[1..y - 1] | q, "*", "");
      inf = `verb_info(where, short) ! ANY';
      if (typeof(inf) == TYPE_LIST || inf == E_PERM)
        const name = typeof(inf) == TYPE_LIST ? index(inf[3], " ") ? "\"" + inf[3] + "\"" | inf[3] | q;
        let line = $string_utils:left(tostr($string_utils:right(tostr(where), 6), ":", name, " "), 32);
        if (inf == E_PERM)
          line = line + "   ** unreadable **";
        else
          line = $string_utils:left(tostr(line, inf[1].name, " (", inf[1], ") "), 53) + ((i = inf[2] in {"x", "xd", "d", "rd"}) ? {" x", " xd", "  d", "r d"}[i] | inf[2]);
          const vargs = `verb_args(where, short) ! ANY';
          if (vargs != blankargs)
            if (player:display_option("shortprep") && !(vargs[2] in {"any", "none"}))
              vargs[2] = $code_utils:short_prep(vargs[2]);
            endif
            line = $string_utils:left(line + " ", 60) + $string_utils:from_list(vargs, " ");
          endif
        endif
        player:notify(line);
      elseif (inf == E_VERBNF)
        player:notify(tostr(inf));
        player:notify(tostr("  ** no such verb, \"", short, "\" **"));
      else
        player:notify("This shouldn't ever happen. @display is buggy.");
      endif
    endfor
    const all = {@prop, @inh};
    const truncate_owner_names = length(all) > 1;
    for q in (all)
      $command_utils:suspend_if_needed(0);
      inf = `property_info(it, q) ! ANY';
      if (inf == E_PROPNF)
        if (q in $code_utils.builtin_props)
          player:notify(tostr($string_utils:left("," + q, 25), "Built in property            ", toliteral(it.(q))));
        else
          player:notify(tostr("  ** property not found, \"", q, "\" **"));
        endif
      else
        const pname = $string_utils:left(tostr(q in `properties(it) ! ANY => {}' ? "." | `is_clear_property(it, q) ! ANY' ? " " | ",", q, " "), 25);
        if (inf == E_PERM)
          player:notify(pname + "   ** unreadable **");
        else
          let oname = inf[1].name;
          truncate_owner_names && (length(oname) > 12 && (oname = oname[1..12]));
          `inf[2][1] != "r" ! E_RANGE => 1' && (inf[2][1..0] = " ");
          `inf[2][2] != "w" ! E_RANGE => 1' && (inf[2][2..1] = " ");
          player:notify($string_utils:left(tostr($string_utils:left(tostr(pname, oname, " (", inf[1], ") "), 47), inf[2], " "), 54) + toliteral(it.(q)));
        endif
      endif
    endfor
    if (cant)
      let failed = {};
      for k in (cant)
        failed = listappend(failed, tostr(k.name, " (", k, ")"));
      endfor
      player:notify($string_utils:centre(tostr(" no permission to read ", $string_utils:english_list(failed, ", ", " or ", " or "), ". "), 75, "-"));
    else
      player:notify($string_utils:centre(" finished ", 75, "-"));
    endif
  endverb

  verb "@db*size" (none none none) owner: #2 flags: "rd"
    "Report the number of live objects, including UUID objects. Requires programmer permission.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    "Enumerate with the verb owner's authority, exposing only the aggregate count.";
    const count = length(objects());
    set_task_perms(player);
    player:notify(tostr("There are ", count, " valid objects (numbered and UUID)."));
  endverb

  verb "@gethelp" (any any any) owner: #2 flags: "rd"
    "@gethelp [<topic>] [from <db or dblist>]";
    "  Prints the raw text of topic from the appropriate help db.";
    "  With no argument, gets the blank (\"\") topic from wherever it lives";
    "  Text is printed as a script for changing this help topic ";
    "  (somewhat like @dump...)";
    let topic;
    let dblist;
    let e;
    let text;
    let db;
    let fulltopic;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (!prepstr)
      topic = argstr;
      dblist = $code_utils:help_db_list();
    elseif (prepstr != "from")
      player:notify("Usage:  ", verb, " [<topic>] [from <db>]");
      return;
    else
      e = $no_one:eval_d(iobjstr = argstr[$string_utils:word_start(argstr)[(prepstr in args) + 1][1]..$]);
      if (!e)
        player:notify(tostr(e));
        return;
      elseif (!e[1])
        player:notify_lines(e[2]);
        return;
      else
        dblist = e[2];
        if (!(typeof(dblist) in {TYPE_OBJ, TYPE_LIST}))
          player:notify(tostr(iobjstr, " => ", dblist, " -- not an object or a list"));
          return;
        else
          topic = dobjstr;
          if (typeof(dblist) == TYPE_OBJ)
            dblist = {dblist};
          endif
        endif
      endif
    endif
    const search = $code_utils:help_db_search(topic, dblist);
    if (!search)
      player:notify("Topic not found.");
    elseif (search[1] == $ambiguous_match)
      player:notify(tostr("Topic `", topic, "' ambiguous:  ", $string_utils:english_list(search[2], "none", " or ")));
    else
      text = (db = search[1]):dump_topic(fulltopic = search[2]);
      if (typeof(text) == TYPE_ERR)
        "...ok...shoot me.  This is a -d verb...";
        player:notify(tostr("Cannot retrieve `", fulltopic, "' on ", $code_utils:corify_object(db), ":  ", text));
      else
        player:notify_lines(text);
      endif
    endif
  endverb

  verb "@grep*all @egrep*all" (any any any) owner: #2 flags: "rd"
    "Search accessible verb source for text or a regular expression.";
    let pattern;
    let objlist;
    let n;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (prepstr == "in")
      pattern = dobjstr;
      objlist = player:eval_cmd_string(iobjstr, 0);
      if (!objlist[1])
        player:notify(tostr("Had trouble reading `", iobjstr, "':  "));
        player:notify_lines(@objlist[2]);
        return;
      endif
      if (typeof(objlist[2]) == TYPE_OBJ)
        objlist = {objlist[2..2]};
      elseif (typeof(objlist[2]) != TYPE_LIST)
        player:notify(tostr("Value of `", iobjstr, "' is not an object or list:  ", toliteral(objlist[2])));
        return;
      else
        objlist = objlist[2..2];
      endif
    else
      n = prepstr == "from" && player.wizard ? toint(toobj(iobjstr)) | 0;
      if (prepstr == "from" && player.wizard && n)
        pattern = dobjstr;
        objlist = {n};
      elseif (args && player.wizard)
        pattern = argstr;
        objlist = {};
      else
        player:notify(tostr("Usage:  ", verb, " <pattern> ", player.wizard ? "[in {<objectlist>} | from <number>]" | "in {<objectlist>}"));
        return;
      endif
    endif
    player:notify(tostr("Searching for verbs ", @prepstr ? {prepstr, " ", iobjstr, " "} | {}, verb == "@egrep" ? "matching the pattern " | "containing the string ", toliteral(pattern), " ..."));
    player:notify("");
    const egrep = verb[2] == "e";
    const all = index(verb, "a");
    $code_utils:(all ? egrep ? "find_verb_lines_matching" | "find_verb_lines_containing" | egrep ? "find_verbs_matching" | "find_verbs_containing")(pattern, @objlist);
  endverb

  verb "@s*how" (any any any) owner: #2 flags: "rd"
    "Show the value and permissions of an object or property.";
    let object;
    let pname;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (dobjstr == "")
      player:notify(tostr("Usage:  ", verb, " <object-or-property-or-verb>"));
      return;
    endif
    let spec = index(dobjstr, ".") ? $code_utils:parse_propref(dobjstr) | {};
    if (spec)
      object = player:my_match_object(spec[1]);
      valid(object) && return $code_utils:show_property(object, spec[2]);
    else
      spec = $code_utils:parse_verbref(dobjstr);
      if (spec)
        object = player:my_match_object(spec[1]);
        valid(object) && return $code_utils:show_verbdef(object, spec[2]);
      else
        pname = dobjstr[1] == "$" ? dobjstr[2..$] | "";
        if (dobjstr[1] == "$" && pname in properties(#0) && typeof(#0.(pname)) == TYPE_OBJ)
          object = #0.(pname);
          valid(object) && return $code_utils:show_object(object);
        else
          spec = dobjstr[1] == "$" ? $code_utils:parse_propref(dobjstr) | {};
          spec && return $code_utils:show_property(#0, spec[2]);
          object = player:my_match_object(dobjstr);
          valid(object) && return $code_utils:show_object(object);
        endif
      endif
    endif
    $command_utils:object_match_failed(object, dobjstr);
  endverb

  verb "@check-p*roperty" (any none none) owner: #2 flags: "rd"
    "@check-prop object.property";
    "  checks for descendents defining the given property.";
    let object;
    let prop;
    let olist;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const spec = $code_utils:parse_propref(dobjstr);
    if (!spec)
      player:notify(tostr("Usage:  ", verb, " <object>.<prop-name>"));
    else
      object = player:my_match_object(spec[1]);
      if ($command_utils:object_match_failed(object, spec[1]))
        "...bogus object...";
      elseif (!($perm_utils:controls(player, object) || object.w))
        player:notify("You can't create a property on that object anyway.");
      else
        prop = spec[2];
        if ($object_utils:has_property(object, prop))
          player:notify("That object already has that property.");
        else
          olist = $object_utils:descendants_with_property_suspended(object, prop);
          if (olist)
            player:notify("The following descendents have this property defined:");
            player:notify("  " + $string_utils:from_list(olist, " "));
          else
            player:notify("No property name conflicts found.");
          endif
        endif
      endif
    endif
  endverb

  verb "@clearp*roperty @clprop*erty" (any none none) owner: #2 flags: "rd"
    "@clearproperty <obj>.<prop>";
    "Set the value of <obj>.<prop> to `clear', making it appear to be the same as the property on its parent.";
    let prop;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const l = $code_utils:parse_propref(dobjstr);
    if (!l)
      player:notify(tostr("Usage:  ", verb, " <object>.<property>"));
    else
      dobj = player:my_match_object(l[1]);
      if ($command_utils:object_match_failed(dobj, l[1]))
        "... bogus object...";
      endif
    endif
    try
      prop = l[2];
      if (is_clear_property(dobj, prop))
        player:notify(tostr("Property ", dobj, ".", prop, " is already clear!"));
        return;
      endif
      clear_property(dobj, prop);
      player:notify(tostr("Property ", dobj, ".", prop, " cleared; value is now ", toliteral(dobj.(prop)), "."));
    except (E_INVARG)
      player:notify(tostr("You can't clear ", dobj, ".", prop, "; none of the ancestors define that property."));
    except error (ANY)
      player:notify(error[2]);
    endtry
  endverb

  verb "@disown @disinherit" (any any any) owner: #2 flags: "rd"
    "Syntax: @disown <object> [from <object>]";
    "This command is used to remove unwanted children of objects you control. If you control an object, and there is a child of that object you do not want, this command will chparent() the object to its grandparent.";
    let grandparent;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (prepstr)
      if (prepstr != "from")
        player:notify("Usage:  ", verb, " <object> [from <object>]");
        return;
      endif
      iobj = player:my_match_object(iobjstr);
      if ($command_utils:object_match_failed(iobj, iobjstr))
        "... from WHAT?..";
        return;
      else
        dobj = $string_utils:literal_object(dobjstr);
        if (valid(dobj))
          "... literal object number...";
          if (parent(dobj) != iobj)
            player:notify(tostr(dobj, " is not a child of ", iobj.name, " (", iobj, ")"));
            return;
          endif
        else
          dobj = $string_utils:match(dobjstr, children(iobj), "name", children(iobj), "aliases");
          if ($command_utils:object_match_failed(dobj, dobjstr))
            "... can't match dobjstr against any children of iobj";
            return;
          endif
        endif
      endif
    else
      dobj = player:my_match_object(dobjstr);
      if ($command_utils:object_match_failed(dobj, dobjstr))
        "... can't match dobjstr...";
        return;
      endif
    endif
    try
      if ($object_utils:disown(dobj))
        player:notify(tostr(dobj.name, " (", dobj, ")'s parent is now ", (grandparent = parent(dobj)).name, " (", grandparent, ")."));
      else
        "this should never happen";
      endif
    except e (E_PERM, E_INVARG)
      const {code, message, value, traceback} = e;
      player:notify(message);
    endtry
  endverb

  verb "@dump" (any any any) owner: #2 flags: "rd"
    "@dump something [with [id=...] [noprops] [noverbs] [create]]";
    "This spills out all properties and verbs on an object, calling suspend at appropriate intervals.";
    "   id=#nnn -- specifies an idnumber to use in place of the object's actual id (for porting to another MOO)";
    "   noprops -- don't show properties.";
    "   noverbs -- don't show verbs.";
    "   create  -- indicates that a @create command should be generated and all of the verbs be introduced with @verb rather than @args; the default assumption is that the object already exists and you're just doing this to have a look at it.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    dobj = player:my_match_object(dobjstr);
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    if (prepstr && prepstr != "with")
      player:notify(tostr("Usage:  ", verb, " something [with [id=...] [noprops] [noverbs] [create]]"));
      return;
    endif
    let targname = tostr(dobj);
    let options = {"props", "verbs"};
    let create = 0;
    if (iobjstr)
      for o in ($string_utils:explode(iobjstr))
        if (index(o, "id=") == 1)
          targname = o[4..$];
        elseif (o in {"noprops", "noverbs"})
          options = setremove(options, o[3..$]);
        elseif (o in {"create"})
          create = 1;
        else
          player:notify(tostr("`", o, "' not understood as valid option."));
          player:notify(tostr("Usage:  ", verb, " something [with [id=...] [noprops] [noverbs] [create]]"));
          return;
        endif
      endfor
    endif
    if (create)
      player:notify($code_utils:dump_preamble(dobj));
    endif
    if ("props" in options)
      player:notify_lines_suspended($code_utils:dump_properties(dobj, create, targname));
    endif
    if (!("verbs" in options))
      player:notify("\"***finished***");
      return;
    endif
    player:notify("");
    player:notify_lines_suspended($code_utils:dump_verbs(dobj, create, targname));
    player:notify("\"***finished***");
  endverb

  verb "#*" (any any any) owner: #2 flags: "rd"
    "Copied from Player Class hacked with eval that does substitutions and assorted stuff (#8855):# by Geust (#24442) Sun May  9 20:19:05 1993 PDT";
    "#<string>[.<property>|.parent] [exit|player|inventory] [for <code>] returns information about the object (we'll call it <thing>) named by string.  String is matched in the current room unless one of exit|player|inventory is given.";
    "If neither .<property>|.parent nor <code> is specified, just return <thing>.";
    "If .<property> is named, return <thing>.<property>.  .parent returns parent(<thing>).";
    "If <code> is given, it is evaluated, with the value returned by the first part being substituted for %# in <code>.";
    "For example, the command";
    "  #JoeFeedback.parent player for toint(%#)";
    "will return 26026 (unless Joe has chparented since writing this).";
    let dot;
    let what;
    let val;
    let value;
    let l;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const whatstr = verb[2..dot = min(index(verb + ".", "."), index(verb + ":", ":")) - 1];
    if (!whatstr)
      player:notify("Usage:  #string [exit|player|inventory]");
      return;
    endif
    if (!args)
      what = player:my_match_object(whatstr);
    elseif (index("exits", args[1]) == 1)
      what = player.location:match_exit(whatstr);
    elseif (index("inventory", args[1]) == 1)
      what = player:match(whatstr);
    elseif (index("players", args[1]) == 1)
      what = $string_utils:match_player(whatstr);
      $command_utils:player_match_failed(what, whatstr) && return;
    else
      what = player:my_match_object(whatstr);
    endif
    if (!valid(what) && $code_utils:match_objid("#" + whatstr))
      what = toobj(whatstr);
    endif
    $command_utils:object_match_failed(what, whatstr) && return;
    while (index(verb, ".parent") == dot + 1)
      what = parent(what);
      dot = dot + 7;
    endwhile
    if (dot >= length(verb))
      val = what;
    else
      value = $code_utils:eval_d(tostr("return ", what, verb[dot + 1..$], ";"));
      if (value[1])
        val = value[2];
      else
        player:notify_lines(value[2]);
        return;
      endif
    endif
    if (prepstr)
      let program = strsub(iobjstr + ";", "%#", toliteral(val));
      let end = 1;
      "while (\"A\" <= (l = argstr[end]) && l <= \"Z\")";
      while (true)
        l = program[end];
        if (!("A" <= l && l <= "Z"))
          break;
        endif
        end = end + 1;
      endwhile
      if (program[1] == ";" || program[1..end - 1] in {"if", "for", "fork", "return", "while", "try"})
        program = $code_utils:substitute(program, player.eval_subs);
      else
        program = $code_utils:substitute("return " + program, player.eval_subs);
      endif
      value = eval(program);
      if (value[1])
        player:notify(player:eval_value_to_string(value[2]));
      else
        player:notify_lines(value[2]);
        const nerrors = length(value[2]);
        player:notify(tostr(nerrors, " error", nerrors == 1 ? "." | "s."));
      endif
    else
      player:notify(player:eval_value_to_string(val));
    endif
  endverb

  verb "@progo*ptions @prog-o*ptions @programmero*ptions @programmer-o*ptions" (any any any) owner: #2 flags: "rd"
    "@<what>-option <option> [is] <value>   sets <option> to <value>";
    "@<what>-option <option>=<value>        sets <option> to <value>";
    "@<what>-option +<option>     sets <option>   (usually equiv. to <option>=1";
    "@<what>-option -<option>     resets <option> (equiv. to <option>=0)";
    "@<what>-option !<option>     resets <option> (equiv. to <option>=0)";
    "@<what>-option <option>      displays value of <option>";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const what = "prog";
    const options = what + "_options";
    const option_pkg = #0.(options);
    const set_option = "set_" + what + "_option";
    if (!args)
      player:notify_lines({"Current " + what + " options:", "", @option_pkg:show(player.(options), option_pkg.names)});
      return;
    endif
    const presult = option_pkg:parse(args);
    if (typeof(presult) == TYPE_STR)
      player:notify(presult);
      return;
    else
      if (length(presult) > 1)
        const sresult = player:(set_option)(@presult);
        if (typeof(sresult) == TYPE_STR)
          player:notify(sresult);
          return;
        endif
        if (!sresult)
          player:notify("No change.");
          return;
        endif
      endif
      player:notify_lines(option_pkg:show(player.(options), presult[1]));
    endif
  endverb

  verb "@list*#" (any any any) owner: #2 flags: "rd"
    "@list <obj>:<verb> [<dobj> <prep> <iobj>] [with[out] paren|num] [all] [ranges]";
    let s;
    let pas;
    let vname;
    let code;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const bynumber = verb == "@list#";
    let pflag = player:prog_option("list_all_parens");
    let nflag = !player:prog_option("list_no_numbers");
    const permflag = player:prog_option("list_show_permissions");
    let aflag = 0;
    let argspec = {};
    let range = {};
    const spec = args ? $code_utils:parse_verbref(args[1]) | E_INVARG;
    args = spec ? listdelete(args, 1) | E_INVARG;
    while (args)
      if (args[1] && (index("without", args[1]) == 1 || args[1] == "wo"))
        "...w,wi,wit,with => 1; wo,witho,withou,without => 0...";
        const fval = !index(args[1], "o");
        if (`index("parentheses", args[2]) ! ANY' == 1)
          pflag = fval;
          args[1..2] = {};
        elseif (`index("numbers", args[2]) ! ANY' == 1)
          nflag = fval;
          args[1..2] = {};
        else
          player:notify(tostr(args[1], " WHAT?"));
          args = E_INVARG;
        endif
      elseif (index("all", args[1]) == 1)
        if (bynumber)
          player:notify("Don't use `all' with @list#.");
          args = E_INVARG;
        else
          aflag = 1;
          args[1..1] = {};
        endif
      elseif (index("0123456789", args[1][1]) || index(args[1], "..") == 1)
        s = $seq_utils:from_string(args[1]);
        if (E_INVARG == s)
          player:notify(tostr("Garbled range:  ", args[1]));
          args = E_INVARG;
        else
          range = $seq_utils:union(range, s);
          args = listdelete(args, 1);
        endif
      elseif (bynumber)
        player:notify("Don't give args with @list#.");
        args = E_INVARG;
      elseif (argspec)
        "... second argspec?  Not likely ...";
        player:notify(tostr(args[1], " unexpected."));
        args = E_INVARG;
      else
        pas = $code_utils:parse_argspec(@args);
        if (typeof(pas) == TYPE_LIST)
          argspec = pas[1];
          if (length(argspec) < 2)
            player:notify(tostr("Argument `", @argspec, "' malformed."));
            args = E_INVARG;
          else
            argspec[2] = $code_utils:full_prep(argspec[2]) || argspec[2];
            args = pas[2];
          endif
        else
          "... argspec is bogus ...";
          player:notify(tostr(pas));
          args = E_INVARG;
        endif
      endif
    endwhile
    if (args == E_INVARG)
      if (bynumber)
        player:notify(tostr("Usage:  ", verb, " <object>:<verbnumber> [with|without parentheses|numbers] [ranges]"));
      else
        player:notify(tostr("Usage:  ", verb, " <object>:<verb> [<dobj> <prep> <iobj>] [with|without parentheses|numbers] [all] [ranges]"));
      endif
      return;
    endif
    let object = player:my_match_object(spec[1]);
    if ($command_utils:object_match_failed(object, spec[1]))
      return;
    endif
    let shown_one = 0;
    for what in ({object, @$object_utils:ancestors(object)})
      if (bynumber)
        vname = $code_utils:toint(spec[2]);
        vname == E_TYPE && return player:notify("Verb number expected.");
        if (vname < 1 || `vname > length(verbs(what)) ! E_PERM => 0')
          return player:notify("Verb number out of range.");
        endif
        code = `verb_code(what, vname, pflag) ! ANY';
      elseif (argspec)
        let vnum = $code_utils:find_verb_named(what, spec[2]);
        while (vnum && `verb_args(what, vnum) ! ANY' != argspec)
          vnum = $code_utils:find_verb_named(what, spec[2], vnum + 1);
        endwhile
        vname = vnum;
        code = !vnum ? E_VERBNF | `verb_code(what, vnum, pflag) ! ANY';
      else
        vname = spec[2];
        code = `verb_code(what, vname, pflag) ! ANY';
      endif
      if (code != E_VERBNF)
        if (shown_one)
          player:notify("");
        elseif (what != object)
          player:notify(tostr("Object ", object, " does not define that verb", argspec ? " with those args" | "", ", but its ancestor ", what, " does."));
        endif
        if (typeof(code) == TYPE_ERR)
          player:notify(tostr(what, ":", vname, " -- ", code));
        else
          const info = verb_info(what, vname);
          let vargs = verb_args(what, vname);
          let fullname = info[3];
          if (index(fullname, " "))
            fullname = toliteral(fullname);
          endif
          if (index(vargs[2], "/"))
            vargs[2] = tostr("(", vargs[2], ")");
          endif
          player:notify(tostr(what, ":", fullname, "   ", $string_utils:from_list(vargs, " "), permflag ? " " + info[2] | ""));
          if (code == {})
            player:notify("(That verb has not been programmed.)");
          else
            let lineseq = {1, length(code) + 1};
            range && (lineseq = $seq_utils:intersection(range, lineseq));
            if (!lineseq)
              player:notify("(No lines in that range.)");
            endif
            for k in [1..length(lineseq) / 2]
              for i in [lineseq[2 * k - 1]..lineseq[2 * k] - 1]
                if (nflag)
                  let end = 0;
                  if (i < 10)
                    end = 1;
                  endif
                  player:notify(tostr(" "[1..end], i, ":  ", code[i]));
                else
                  player:notify(code[i]);
                endif
                $command_utils:suspend_if_needed(0);
              endfor
            endfor
          endif
        endif
        shown_one = 1;
      endif
      shown_one && !aflag && return;
    endfor
    if (!shown_one)
      player:notify(tostr("That object does not define that verb", argspec ? " with those args." | "."));
    endif
  endverb

  verb "@verbs*" (any none none) owner: #2 flags: "rd"
    "List the verbs defined on an object.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    if (!dobjstr)
      try
        if (verb[7] != "(" && verb[$] != ")")
          player:tell("Usage:  @verbs <object>");
          return;
        else
          dobjstr = verb[8..$ - 1];
        endif
      except (E_RANGE)
        return player:tell("Usage:  @verbs <object>");
      endtry
    endif
    const thing = player:my_match_object(dobjstr);
    if (!$command_utils:object_match_failed(thing, dobjstr))
      const verbs = $object_utils:accessible_verbs(thing);
      player:tell(";verbs(", thing, ") => ", toliteral(verbs));
    endif
  endverb

  verb "@old-forked-v*erbose" (any none none) owner: #2 flags: "rd"
    "Syntax:  @forked-v*erbose [player]";
    "         @forked-v*erbose all wizards";
    "";
    "For a normal player, shows all the tasks you have waiting in your queue, especially those forked or suspended. A wizard will see all the tasks of all the players unless the optional argument is provided. For a task which has suspended, and not a fresh fork, shows the full callers() stack.";
    "The second form is only usable by wizards and provides an output of all tasks owned by characters who are .wizard=1. Useful to find a task that may get put in a random queue due to $wiz_utils:random_wizard. Or even finding verbs that run with wizard permissions that shouldn't be.";
    let tasks;
    let q_id;
    let start;
    let nu;
    let nu2;
    let owner;
    let vloc;
    let vname;
    let lineno;
    let size;
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    if (!dobjstr)
      tasks = queued_tasks();
    elseif (dobjstr == "all wizards" && player.wizard)
      tasks = {};
      for t in (queued_tasks())
        if (valid(t[5]) && t[5].wizard)
          tasks = {@tasks, t};
        endif
        $command_utils:suspend_if_needed(1);
      endfor
    else
      dobj = $string_utils:match_player(dobjstr);
      if ($command_utils:player_match_result(dobj, dobjstr)[1])
        return;
      else
        tasks = $wiz_utils:queued_tasks(dobj);
        if (typeof(tasks) != TYPE_LIST)
          player:notify(tostr(verb, " ", dobj.name, "(", dobj, "):  ", tasks));
          return;
        endif
      endif
    endif
    if (tasks)
      const su = $string_utils;
      player:notify("Queue ID    Start Time            Owner         Verb (Line) [This]");
      player:notify("--------    ----------            -----         -----------------");
      const now = time();
      for task in (tasks)
        $command_utils:suspend_if_needed(0);
        {q_id, start, nu, nu2, owner, vloc, vname, lineno, player, ?size = 0} = task;
        const time = start >= now ? ctime(start)[5..24] | su:left(start == -1 ? "Reading input ..." | tostr(now - start, " seconds ago..."), 20);
        const owner_name = valid(owner) ? owner.name | tostr("Dead ", owner);
        player:notify(tostr(su:left(tostr(q_id), 10), "  ", time, "  ", su:left(owner_name, 12), "  ", vloc, ":", vname, " (", lineno, ")", player != vloc ? tostr(" [", player, "]") | ""));
        const stack = `task_stack(q_id, 1) ! E_INVARG => 0';
        if (stack)
          for frame in (listdelete(stack, 1))
            const {sthis, svname, sprogger, svloc, splayer, slineno} = frame;
            player:notify(tostr("                    Called By...  ", su:left(valid(sprogger) ? sprogger.name | tostr("Dead ", sprogger), 12), "  ", svloc, ":", svname, sthis != svloc ? tostr(" [", sthis, "]") | "", " (", slineno, ")"));
          endfor
        endif
      endfor
      player:notify("-----------------------------------------------------------------");
    else
      player:notify("No tasks.");
    endif
  endverb

  verb "@props @properties" (any any any) owner: #2 flags: "rd"
    "Usage: @properties <object>";
    "Alias: @props";
    "Displays all properties defined on <object>. Properties unreadable by you display as `E_PERM'.";
    $programmer_feature in player.features || raise(E_PERM);
    player.programmer || return player:tell("Programmer permission required.");
    set_task_perms(player);
    set_task_perms(player);
    const ob = player:my_match_object(argstr);
    if (!$command_utils:object_match_failed(ob, argstr))
      player:notify(tostr(";properties(", $code_utils:corify_object(ob), ") => ", toliteral($object_utils:accessible_props(ob))));
    endif
    "Last modified Mon Nov 28 06:21:21 2005 PST, by Roebare (#109000).";
  endverb

  method feature_ok owner: #2
    "Require the player class that supplies this command pack's methods and state.";
    const {who} = args;
    return valid(who) && $object_utils:isa(who, $prog);
  endmethod
endobject
