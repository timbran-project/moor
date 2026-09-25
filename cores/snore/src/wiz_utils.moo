object WIZ_UTILS [
  import_export_id -> "wiz_utils"
]
  name: "Wizard Utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  property boot_exceptions (owner: #2, flags: "rc") = {};
  property boot_task (owner: #2, flags: "rc") = 585440461;
  property change_password_restricted (owner: #2, flags: "") = {};
  property chparent_restricted (owner: #2, flags: "") = {};
  property default_player_quota (owner: #2, flags: "rc") = 7;
  property default_programmer_quota (owner: #2, flags: "rc") = 7;
  property expiration_progress (owner: #2, flags: "rc") = #-1;
  property expiration_recipient (owner: #2, flags: "rc") = {#2};
  property missed_help_counters (owner: #2, flags: "r") = {};
  property missed_help_strings (owner: #2, flags: "r") = {};
  property new_core_message (owner: #2, flags: "r") = {
    "Welcome to Snore Core",
    "just boring enough",
    "",
    "Snore Core is a LambdaCore fork for mooR. Familiar MOO commands, rooms, objects, mail, and live programming remain at its center.",
    "The goal is to fit most existing MOO tutorials while using more of mooR's language and database facilities.",
    "",
    "Getting started",
    "---------------",
    "Type help introduction for an introduction, help index for topics, and @version for the server and core names.",
    "Try look, say hello, and @who. Mail, news, private pages, gagging, and guests are available.",
    "",
    "For administrators",
    "------------------",
    "Customize $login.welcome_message and $login.help_message for your world.",
    "Set $mail_agent.moo_name to your world name. Set $login.create_enabled to control account creation.",
    "Set your password with @password. Use help @password for its syntax.",
    "$player_class selects the class for new accounts. It defaults to $default_player. Keep $player as the base class.",
    "The builder, programmer, and wizard classes install their command features by default. Feature membership does not grant authority.",
    "The @programmer command promotes a player to programmer. Wizard authority allows changes throughout the database.",
    "The supplied Guest account supports guest visits. See help @guests and help @make-guest for administration.",
    "The news is a mailing list: send mail to *News, then use @addnews $ to *News to publish the latest message.",
    "",
    "What differs from older cores",
    "-----------------------------",
    "Core objects use traditional object numbers. Newly created player and world objects use UUID identifiers.",
    "Clients handle long-output paging and word wrapping. The core has no FTP, HTTP, or Gopher services.",
    "The mooR book in book/src describes the language and database. The core README and style guide describe this fork.",
    "",
    "Forked from LambdaCore through lambda-moor. The original core is the work of Pavel Curtis and the LambdaMOO community."
  };
  property next_perm_index (owner: #2, flags: "rc") = 1;
  property old_task_perms_user (owner: #2, flags: "rc") = {#8060};
  property programmer_restricted (owner: #2, flags: "rc") = {};
  property programmer_restricted_temp (owner: #2, flags: "rc") = {};
  property record_missed_help (owner: #2, flags: "rc") = 0;
  property registration_domain_restricted (owner: #2, flags: "rc") = 0;
  property rename_restricted (owner: HACKER, flags: "") = {};
  property suicide_string (owner: #2, flags: "rc") = "You don't *really* want to commit suicide, do you?";
  property system_chars (owner: #2, flags: "rc") = {HACKER, NO_ONE, HOUSEKEEPER};
  property wizards (owner: #2, flags: "rc") = {#2};

  override aliases (owner: #2, flags: "rc") = {"Wizard Utilities"};
  override description (owner: #2, flags: "rc") = {
    "This is the Wizard Utilities utility package.  See `help $wiz_utils' for more details."
  };
  override help_msg (owner: #2, flags: "rc") = {
    "Wizard Utilities",
    "----------------",
    "The following functions are substitutes for various server builtins.",
    "Anytime one feel tempted to use one of the expressions on the right,",
    "use the corresponding one on the left instead.  This will take care",
    "of various things that the server (for whatever reason) does not handle.",
    "",
    ":set_programmer(object)             object.programmer = 1;",
    "    chparent object to $prog",
    "    send mail to $prog_log",
    "",
    ":set_player(object[,nochown])       set_player_flag(object,1);",
    "    set player flag, ",
    "    add name/aliases to $player_db,",
    "    and maybe do a self chown.",
    "",
    ":unset_player(object[,newowner])    set_player_flag(object,0);",
    "    unset player flag,",
    "    remove name/aliases from $player_db",
    "    chown to newowner if given",
    "",
    ":set_owner(object, newowner)        object.owner = newowner;",
    "    change ownership on object",
    "    change ownership on all +c properties",
    "    juggle .ownership_quotas",
    "",
    ":set_property_owner(object, property, newowner[, suspend-ok])",
    "    change owner on a given property",
    "    if this is a -c property, we change the owner on all descendants",
    "    for which this is also a -c property.",
    "    Polite protest if property is +c and newowner != object.owner.",
    "",
    ":set_property_flags(object, property, flags[, suspend-ok])",
    "    change the permissions on a given property and propagate these to ",
    "    *all descendants*.  property ownership is changed on descendants ",
    "    where necessary."
  };
  override object_size (owner: HACKER, flags: "r") = {55744, 1084848672};

  method set_programmer owner: #2
    "Promote a player into the programmer hierarchy and grant programmer authority. Return true or an error.";
    const actor = caller_perms();
    const {victim, ?mail_from = actor} = args;
    actor.wizard || return E_PERM;
    valid(victim) && is_player(victim) && $object_utils:isa(victim, $player) || return E_INVARG;
    victim.programmer && return E_NONE;
    this:check_prog_restricted(victim) && return E_INVARG;
    if (!$object_utils:isa(victim, $prog))
      try
        chparent(victim, $prog);
      except error (ANY)
        return error[1];
      endtry
    endif
    victim.programmer = true;
    victim.features = setadd(setadd(victim.features, $builder_feature), $programmer_feature);
    $quota_utils:adjust_quota_for_programmer(victim);
    const subject = tostr("@programmer ", victim.name, " (", victim, ")");
    const body = tostr("I just gave ", victim.name, " a programmer bit.");
    const delivered = $mail_agent:send_message(mail_from, {$new_prog_log, victim}, subject, body);
    delivered[1] || $mail_agent:send_message(mail_from, {$new_prog_log}, subject, body);
    return true;
  endmethod

  method set_player owner: #2
    ":set_player(victim[,nochown]) => 1 or error";
    "Set victim's player flag, (maybe) chown to itself, add name and aliases to $player_db.";
    " E_NONE == already a player,";
    " E_NACC == player_db is frozen,";
    " E_RECMOVE == name is unavailable";
    let name;
    let aliases;
    let {victim, ?nochown = 0} = args;
    !caller_perms().wizard && return E_PERM;
    if (!(valid(victim) && $object_utils:isa(victim, $player)))
      return E_INVARG;
    elseif (is_player(victim))
      return E_NONE;
    elseif ($player_db.frozen)
      return E_NACC;
    else
      name = victim.name;
      !$player_db:available(name) && return E_RECMOVE;
      set_player_flag(victim, 1);
      if ($object_utils:isa(victim, $prog))
        victim.programmer = 1;
      else
        victim.programmer = $player.programmer;
      endif
      if (!nochown)
        $wiz_utils:set_owner(victim, victim);
      endif
      $player_db:insert(name, victim);
      for a in (setremove(aliases = victim.aliases, name))
        if (index(a, " "))
          "..ignore ..";
        elseif ($player_db:available(a) in {this, 1})
          $player_db:insert(a, victim);
        else
          aliases = setremove(aliases, a);
        endif
      endfor
      victim.aliases = setadd(aliases, name);
      return 1;
    endif
  endmethod

  method set_owner owner: #2
    ":set_owner(object,newowner[,suspendok])  does object.owner=newowner, taking care of c properties as well.  This should be used anyplace one is contemplating doing object.owner=newowner, since the latter leaves ownership of c properties unchanged.  (--Rog thinks this is a server bug).";
    let {object, newowner, ?suspendok = 0} = args;
    !valid(object) && return E_INVIND;
    if (!caller_perms().wizard)
      return E_PERM;
    elseif (!(valid(newowner) && is_player(newowner)))
      return E_INVARG;
    endif
    "The ownership transfer below is one unit: the object, its c properties, quota, and the owned";
    "lists must change together. Commit any earlier work before starting it.";
    if (suspendok && (ticks_left() < 5000 || seconds_left() < 2))
      suspend(0);
    endif
    valid(object) && valid(newowner) && is_player(newowner) || return E_INVARG;
    caller_perms().wizard || return E_PERM;
    const oldowner = object.owner;
    object.owner = newowner;
    for pname in ($object_utils:all_properties(object))
      const perms = property_info(object, pname)[2];
      if (index(perms, "c"))
        set_property_info(object, pname, {newowner, perms});
      endif
    endfor
    if ($object_utils:isa(oldowner, $player))
      if (is_player(oldowner) && object != oldowner)
        $quota_utils:reimburse_quota(oldowner, object);
      endif
      if (typeof(oldowner.owned_objects) == TYPE_LIST)
        oldowner.owned_objects = setremove(oldowner.owned_objects, object);
      endif
    endif
    if ($object_utils:isa(newowner, $player))
      if (object != newowner)
        $quota_utils:charge_quota(newowner, object);
      endif
      if (typeof(newowner.owned_objects) == TYPE_LIST)
        newowner.owned_objects = setadd(newowner.owned_objects, object);
      endif
    endif
    return 1;
  endmethod

  method set_property_owner owner: #2
    ":set_property_owner(object,prop,newowner[,suspendok])  changes the ownership of object.prop to newowner.  If the property is !c, changes the ownership on all of the descendents as well.  Otherwise, we just chown the property on the object itself and give a warning if newowner!=object.owner (--Rog thinks this is a server bug that one is able to do this at all...).";
    let {object, pname, newowner, ?suspendok = 0} = args;
    !caller_perms().wizard && return E_PERM;
    if (suspendok % 2 && (ticks_left() < 10000 || seconds_left() < 2))
      suspend(0);
    endif
    caller_perms().wizard || return E_PERM;
    const info = `property_info(object, pname) ! ANY';
    if (!info)
      "... handles E_PROPNF and invalid object errors...";
      return info;
    elseif (!is_player(newowner))
      return E_INVARG;
    elseif (index(info[2], "c"))
      if (suspendok / 2)
        "...(recursive call)...";
        "...child property is +c while parent is -c??...RUN AWAY!!";
        return E_NONE;
      else
        set_property_info(object, pname, listset(info, newowner, 1));
        return newowner == object.owner || E_NONE;
      endif
    else
      "Commit earlier children before this unit; the current object's property transfer and its";
      "recursion bookkeeping belong to one unit.";
      set_property_info(object, pname, listset(info, newowner, 1));
      suspendok = 2 + suspendok;
      for c in (children(object))
        this:set_property_owner(c, pname, newowner, suspendok);
      endfor
      return 1;
    endif
  endmethod

  method unset_player owner: #2
    ":unset_player(victim[,newowner])  => 1 or error";
    "Reset victim's player flag, chown victim to newowner (if given), remove all of victim's names and aliases from $player_db.";
    let {victim, ?newowner = 0} = args;
    !caller_perms().wizard && return E_PERM;
    if (!valid(victim))
      return E_INVARG;
    elseif (!is_player(victim))
      return E_NONE;
    endif
    if (typeof(newowner) == TYPE_OBJ)
      $wiz_utils:set_owner(victim, newowner);
    endif
    victim.programmer = 0;
    victim.wizard = 0;
    set_player_flag(victim, 0);
    if ($object_utils:has_property($local, "second_char_registry"))
      $local.second_char_registry:delete_player(victim);
      `$local.second_char_registry:delete_shared(victim) ! ANY';
    endif
    if ($player_db.frozen)
      player:tell("Warning:  player_db is in the middle of a :load().");
    endif
    $player_db:delete2(victim.name, victim);
    for a in (victim.aliases)
      $player_db:delete2(a, victim);
      "I don't *think* this is bad---we've already toaded the guy.  And folks with lots of aliases screw us. --Nosredna";
      $command_utils:suspend_if_needed(0);
    endfor
    return 1;
    "Paragraph (#122534) - Sat Nov 5, 2005 - Remove any shared character registry listings for `victim'.";
  endmethod

  method set_property_flags owner: #2
    ":set_property_flags(object,prop,flags[,suspendok])  changes the permissions on object.prop to flags.  Unlike a mere set_property_info, this changes the flags on all descendant objects as well.  We also change the ownership on the descendent properties where necessary.";
    let pinfo;
    let c;
    let kflags;
    const {object, pname, flags, ?suspendok = 0} = args;
    const perms = caller_perms();
    const info = `property_info(object, pname) ! ANY';
    if (!info)
      "... handles E_PROPNF and invalid object errors...";
      return info;
    endif
    if ($set_utils:difference($string_utils:char_list(flags), {"r", "w", "c"}))
      "...not r, w, or c?...";
      return E_INVARG;
    else
      pinfo = `property_info(parent(object), pname) ! ANY';
      if (pinfo && flags != pinfo[2])
        "... property doesn't actually live here...";
        "... only allowed to correct so that this property matches parent...";
        return E_INVARG;
      elseif (!(perms.wizard || info[1] == perms))
        "... you have to own the property...";
        return E_PERM;
      else
        c = index(flags, "c");
        if (!(!c == !index(info[2], "c") || $perm_utils:controls(perms, object)))
          "... if you're changing the c flag, you have to own the object...";
          return E_PERM;
        else
          if (c)
            set_property_info(object, pname, {object.owner, kflags = flags});
          else
            set_property_info(object, pname, kflags = listset(info, flags, 2));
          endif
          for kid in (children(object))
            this:_set_property_flags(kid, pname, kflags, suspendok);
          endfor
          return 1;
        endif
      endif
    endif
  endmethod

  method _set_property_flags owner: #2
    "_set_property_flags(object, pname, {owner, flags} or something+\"c\", suspendok)";
    "auxiliary to :set_property_flags... don't call this directly.";
    caller != this && return E_PERM;
    if (args[4] && $command_utils:running_out_of_time(0))
      suspend(0);
    endif
    const object = args[1];
    if (typeof(args[3]) != TYPE_LIST)
      set_property_info(object, args[2], {object.owner, args[3]});
    else
      set_property_info(@args[1..3]);
    endif
    for kid in (children(object))
      this:_set_property_flags(@listset(args, kid, 1));
    endfor
  endmethod

  method random_password owner: #2
    "Generate a random password of length args[1].  Alternates vowels and consonants, for maximum pronounceability.  Uses its own list of consonants which exclude F and C and K to prevent generating obscene sounding passwords.";
    "Capital I and lowercase L are excluded on the basis of looking like each other.";
    const vowels = "aeiouyAEUY";
    const consonants = "bdghjmnpqrstvwxzBDGHJLMNPQRSTVWXZ";
    const len = toint(args[1]);
    if (len)
      let alt = random(2) - 1;
      let s = "";
      for i in [1..len]
        const newchar = alt ? vowels[random($)] | consonants[random($)];
        s = s + newchar;
        alt = !alt;
      endfor
      return s;
    else
      return E_INVARG;
    endif
  endmethod

  method queued_tasks owner: #2
    ":queued_tasks(player) => list of queued tasks for that player.";
    "shouldn't the server builtin should work this way?  oh well";
    let who;
    set_task_perms(caller_perms());
    const e = `set_task_perms(who = args[1]) ! ANY';
    typeof(e) == TYPE_ERR && return e;
    if (who.wizard)
      let tasks = {};
      for t in (queued_tasks())
        if (t[5] == who)
          tasks = {@tasks, t};
        endif
      endfor
      return tasks;
    else
      return queued_tasks();
    endif
  endmethod

  method isnewt owner: #2
    "Return 1 if args[1] is a newted player.";
    !caller_perms().wizard && return E_PERM;
    return args[1] in $login.newted;
  endmethod

  method initialize_owned owner: #2
    "Rebuild player-class ownership caches from the database index, including UUID objects. Wizard only.";
    "Each owner is repaired in one transaction; optional suspension occurs before reading that owner.";
    caller_perms().wizard || return E_PERM;
    set_task_perms(caller_perms());
    player:tell("Beginning initialize_owned:  ", ctime());
    for owner in ({$player, @descendants($player)})
      $command_utils:suspend_if_needed(0);
      if (!valid(owner) || !$object_utils:isa(owner, $player))
        continue;
      endif
      if (typeof(owner.owned_objects) != TYPE_LIST)
        continue;
      endif
      owner.owned_objects = owned_objects(owner);
    endfor
    player:tell("Finished rebuilding ownership lists:  ", ctime());
  endmethod

  method verify_owned_objects owner: #2
    "Repair recorded ownership lists for all players. Wizard callers only; scanning may yield.";
    !caller_perms().wizard && return E_PERM;
    for p in (players())
      if (typeof(p.owned_objects) == TYPE_LIST)
        for o in (p.owned_objects)
          if (typeof(o) != TYPE_OBJ || !valid(o) || o.owner != p)
            p.owned_objects = setremove(p.owned_objects, o);
            player:tell("Removed ", $string_utils:nn(o), " from ", $string_utils:nn(p), "'s .owned_objects list.");
            if (typeof(o) == TYPE_OBJ && valid(o) && typeof(o.owner.owned_objects) == TYPE_LIST)
              o.owner.owned_objects = setadd(o.owner.owned_objects, o);
            endif
          endif
          $command_utils:suspend_if_needed(0, p);
        endfor
      endif
    endfor
  endmethod

  method "connected_wizards connected_wizards_unadvertised" owner: HACKER
    ":connected_wizards() => list of currently connected wizards and players mentioned in .public_identity properties as being wizard counterparts.";
    const wizzes = $object_utils:leaves($wiz);
    let wlist = {};
    const everyone = verb == "connected_wizards_unadvertised";
    for w in (wizzes)
      if (w.wizard && (w.advertised || everyone))
        if (`connected_seconds(w) ! ANY => 0')
          wlist = setadd(wlist, w);
        endif
        if (`connected_seconds(w.public_identity) ! ANY => 0')
          wlist = setadd(wlist, w.public_identity);
        endif
      endif
    endfor
    return wlist;
  endmethod

  method "all_wizards_advertised all_wizards all_wizards_unadvertised" owner: HACKER
    ":all_wizards_advertised() => list of all wizards who have set .advertised true and players mentioned their .public_identity properties as being wizard counterparts";
    const wizzes = $object_utils:leaves($wiz);
    let wlist = {};
    const everyone = verb == "all_wizards_unadvertised";
    for w in (wizzes)
      if (w.wizard && (w.advertised || everyone))
        if (is_player(w))
          wlist = setadd(wlist, w);
        endif
        if (`is_player(w.public_identity) ! ANY')
          wlist = setadd(wlist, w.public_identity);
        endif
      endif
    endfor
    return wlist;
  endmethod

  method rename_all_instances owner: #2
    ":rename_all_instances(object,oldname,newname)";
    "Used to rename all instances of an unwanted verb (like recycle or disfunc)";
    "if said verb is actually defined on the object itself";
    if (caller_perms().wizard)
      let found = 0;
      const {object, oldname, newname} = args;
      while (true)
        const info = `verb_info(object, oldname) ! ANY';
        if (!info)
          break;
        endif
        `set_verb_info(object, oldname, listset(info, newname, 3)) ! ANY';
        found = 1;
      endwhile
      return found;
    else
      return E_PERM;
    endif
  endmethod

  method missed_help owner: #2
    "Record an unsuccessful player help lookup when collection is enabled.";
    if (this.record_missed_help && callers()[1][4] == $player)
      const miss = args[1];
      let index = miss in this.missed_help_strings;
      if (!index)
        this.missed_help_strings = {miss, @this.missed_help_strings};
        this.missed_help_counters = {{0, 0}, @this.missed_help_counters};
        index = 1;
      endif
      const which = args[2] ? 2 | 1;
      this.missed_help_counters[index][which] = this.missed_help_counters[index][which] + 1;
    endif
  endmethod

  method show_missing_help owner: #2
    "Print a snapshot of frequently missed help requests; output may yield.";
    const mhs = this.missed_help_strings;
    const cnt = this.missed_help_counters;
    "save values first, so subsequent changes during suspends wont affect it";
    const thresh = args ? args[1] | 5;
    let strs = {};
    for i in [1..length(mhs)]
      $command_utils:suspend_if_needed(0);
      if (cnt[i][1] + cnt[i][2] > thresh)
        strs = {@strs, $string_utils:right(tostr(cnt[i][1]), 5) + " " + $string_utils:right(tostr(cnt[i][2]), 5) + " " + mhs[i]};
      endif
    endfor
    const sorted = $list_utils:sort_suspended(0, strs);
    const len = length(sorted);
    player:tell(" miss ambig word");
    for x in [1..len]
      $command_utils:suspend_if_needed(0);
      player:tell(sorted[len - x + 1]);
    endfor
    player:tell(" - - - - - - - - -");
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      `delete_property(this, "guest_feature_restricted") ! ANY';
      this.boot_exceptions = {};
      this.programmer_restricted = {};
      this.programmer_restricted_temp = {};
      this.chparent_restricted = {};
      this.rename_restricted = {};
      this.change_password_restricted = {};
      this.record_missed_help = 0;
      this.missed_help_counters = this.missed_help_strings = {};
      this.suicide_string = "You don't *really* want to commit suicide, do you?";
      this.wizards = {#2};
      this.next_perm_index = 1;
      this.system_chars = {$hacker, $no_one, $housekeeper};
      this.expiration_progress = $nothing;
      this.expiration_recipient = {#2};
    endif
  endmethod

  method show_netwho_listing owner: #2
    ":show_netwho_listing(tell,player_list)";
    " prints a listing of the indicated players showing connect sites.";
    let who;
    let unsorted;
    let pref;
    let lctime;
    let where;
    {who, unsorted} = args;
    !caller_perms().wizard && return E_PERM;
    !unsorted && return;
    const su = $string_utils;
    let alist = {};
    let footnotes = {};
    let nwidth = length("Player name");
    for u in (unsorted)
      $command_utils:suspend_if_needed(0);
      if (u.programmer)
        pref = "% ";
        footnotes = setadd(footnotes, "prog");
      else
        pref = "  ";
      endif
      if (u in connected_players())
        lctime = ctime(time() - connected_seconds(u));
        where = connection_name(u);
      else
        lctime = ctime(u.last_connect_time);
        where = u.last_connect_place;
      endif
      let name = u.name;
      if (length(name) > 15)
        name = name[1..13] + "..";
      endif
      const u3 = {tostr(pref, u.name, " (", u, ")"), lctime[5..10] + lctime[20..24]};
      nwidth = max(length(u3[1]), nwidth);
      where = $string_utils:connection_hostname(where);
      if ($login:blacklisted(where))
        where = "(*) " + where;
        footnotes = setadd(footnotes, "black");
      elseif ($login:graylisted(where))
        where = "(+) " + where;
        footnotes = setadd(footnotes, "gray");
      endif
      alist = {@alist, {@u3, where}};
    endfor
    alist = $list_utils:sort_alist_suspended(0, alist, 3);
    $command_utils:suspend_if_needed(0);
    const headers = {"Player name", "Last Login", "From Where"};
    const before = {0, nwidth + 3, nwidth + length(ctime(0)) - 11};
    let tell1 = "  " + headers[1];
    let tell2 = "  " + su:space(headers[1], "-");
    for j in [2..3]
      tell1 = su:left(tell1, before[j]) + headers[j];
      tell2 = su:left(tell2, before[j]) + su:space(headers[j], "-");
    endfor
    who:notify(tell1);
    who:notify(tell2);
    for a in (alist)
      $command_utils:suspend_if_needed(0);
      tell1 = a[1];
      for j in [2..3]
        tell1 = su:left(tell1, before[j]) + a[j];
      endfor
      who:notify(tell1[1..min($, 79)]);
    endfor
    if (footnotes)
      who:notify("");
      if ("prog" in footnotes)
        who:notify(" %  == programmer.");
      endif
      if ("black" in footnotes)
        who:notify("(*) == blacklisted site.");
      endif
      if ("gray" in footnotes)
        who:notify("(+) == graylisted site.");
      endif
    endif
  endmethod

  method show_netwho_from_listing owner: #2
    ":show_netwho_from_listing(tell,site)";
    "@net-who from hoststring prints all players who have connected from that host or host substring.  Substring can include *'s, e.g. @net-who from *.foo.edu.";
    let bozos;
    let s;
    !caller_perms().wizard && return E_PERM;
    const {tellwho, where} = args;
    const su = $string_utils;
    if (!index(where, "*"))
      "Oh good... search for users from a site... the fast way.  No wild cards.";
      let nl = 0;
      bozos = {};
      let sites = $site_db:find_all_keys(where);
      while (sites)
        s = sites;
        sites = {};
        for domain in (s)
          "Temporary kluge until $site_db is repaired. --Nosredna";
          for b in ($site_db:find_exact(domain) || {})
            $command_utils:suspend_if_needed(0, "..netwho..");
            if (typeof(b) == TYPE_STR)
              sites = setadd(sites, b + "." + domain);
            else
              bozos = setadd(bozos, b);
              nl = max(length(tostr(b, valid(b) && is_player(b) ? b.name | "*** recreated ***")), nl);
            endif
          endfor
        endfor
      endwhile
      if (bozos)
        tellwho:notify(tostr(su:left("  Player", nl + 7), "From"));
        tellwho:notify(tostr(su:left("  ------", nl + 7), "----"));
        for who in (bozos)
          let st = su:left(tostr(valid(who) && is_player(who) ? (who.programmer ? "% " | "  ") + who.name | "", " (", who, ")"), nl + 7);
          let comma = 0;
          if ($object_utils:isa(who, $player) && is_player(who))
            for p in ({$wiz_utils:get_email_address(who) || "*Unregistered*", @who.all_connect_places})
              if (comma && length(p) >= 78 - length(st))
                tellwho:notify(tostr(st, ","));
                st = su:space(nl + 7) + p;
              else
                st = tostr(st, comma ? ", " | "", p);
              endif
              comma = 1;
              $command_utils:suspend_if_needed(0);
            endfor
          else
            st = st + (valid(who) ? "*** recreated ***" | "*** recycled ***");
          endif
          tellwho:notify(st);
        endfor
        tellwho:notify("");
        tellwho:notify(tostr(length(bozos), " player", length(bozos) == 1 ? "" | "s", " found."));
      else
        tellwho:notify(tostr("No sites matching `", where, "'"));
      endif
    else
      "User typed 'from'.  Go search for users from this site.  (SLOW!)";
      let howmany = 0;
      for who in (players())
        $command_utils:suspend_if_needed(0);
        let matches = {};
        for name in (who.all_connect_places)
          if (index(where, "*") && su:match_string(name, where) || (!index(where, "*") && index(name, where)))
            matches = {@matches, name};
          endif
        endfor
        if (matches)
          howmany = howmany + 1;
          tellwho:notify(tostr(who.name, " (", who, "): ", su:english_list(matches)));
        endif
      endfor
      tellwho:notify(tostr(howmany || "No", " matches found."));
    endif
  endmethod

  method "check_player_request check_reregistration" owner: #2
    ":check_player_request(name [,email [,connection]])";
    " check if the request for player and email address is valid;";
    " return empty string if it valid, or else a string saying why not.";
    " The result starts with - if this is a 'send email, don't try again' situation.";
    ":check_reregistration(who, email, connection)";
    "  Since name is ignored, only check the 'email' parts and use the first arg";
    "  for the re-registering player.";
    let a;
    let b;
    if (!caller_perms().wizard)
      return E_PERM;
      "accesses registration information -- wiz only";
    endif
    const name = args[1];
    if (verb == "check_reregistration")
      "don't check player name";
    elseif (!name)
      return "A blank name isn't allowed.";
    elseif (name == "<>")
      return "Names with angle brackets aren't allowed.";
    elseif (index(name, " "))
      return "Names with spaces are not allowed. Use dashes or underscores.";
    elseif (match(name, "^<.*>$"))
      return tostr("Try using ", name[2..$ - 1], " instead of ", name, ".");
    elseif ($player_db.frozen)
      return "New players cannot be created at the moment, try again later.";
    elseif (!$player_db:available(name))
      return "The name '" + name + "' is not available.";
    elseif ($login:_match_player(name) != $failed_match)
      return "The name '" + name + "' doesn't seem to be available.";
    endif
    if (length(args) == 1)
      "no email address supplied.";
      return "";
    endif
    const address = args[2];
    const addrargs = verb == "check_reregistration" ? {name} | {};
    if ($registration_db:suspicious_address(address, @addrargs))
      return "-There has already been a character with that or a similar email address.";
    endif
    const reason = $mail_agent:invalid_email_address(address);
    reason && return reason + ".";
    const parsed = $mail_agent:parse_address(address);
    if ($registration_db:suspicious_userid(parsed[1]))
      return tostr("-Automatic registration from an account named ", parsed[1], " is not allowed.");
    endif
    const connection = length(args) > 2 ? args[3] | parsed[2];
    const check_connection = $wiz_utils.registration_domain_restricted && verb == "check_player_request";
    if (connection[max($ - 2, 1)..$] == ".uk" && parsed[2][1..3] == "uk.")
      return tostr("Addresses must be in internet form. Try ", parsed[1], "@", $string_utils:from_list($list_utils:reverse($string_utils:explode(parsed[2], ".")), "."), ".");
    endif
    if (check_connection && match(connection, "^[0-9.]+$"))
      "Allow reregistration from various things we wouldn't allow registration from.  Let them register to their yahoo acct...";
      return "-The system cannot resolve the name of the system you're connected from.";
    else
      if (check_connection)
        a = $mail_agent:local_domain(connection);
        b = $mail_agent:local_domain(parsed[2]);
      endif
      if (check_connection && a != b)
        return tostr("-The connection is from '", a, "' but the mail address is '", b, "'; these don't seem to be the same place.");
      elseif (verb == "check_player_request" && $login:spooflisted(parsed[2]))
        return tostr("-Automatic registration is not allowed from ", parsed[2], ".");
      endif
    endif
    return "";
  endmethod

  method make_player owner: #2
    "create a player named NAME with email address ADDRESS; return {object, password}.  Optional third arg is comment to be put in registration db.";
    "assumes $wiz_utils:check_player_request() has been called and it passes.";
    let password;
    !caller_perms().wizard && return E_PERM;
    const {name, address, @rest} = args;
    let new = $quota_utils:bi_create($player_class, $nothing);
    new.name = name;
    new.aliases = {name};
    const salt_str = salt();
    new.password = argon2(password = $wiz_utils:random_password(5), salt_str);
    new.last_password_time = time();
    new.last_connect_time = $maxint;
    "Last disconnect time is creation time, until they login.";
    new.last_disconnect_time = time();
    $quota_utils:initialize_quota(new);
    const error = $wiz_utils:set_player(new);
    if (!error)
      return player:tell("An error, ", error, " occurred while trying to make ", new, " a player. The database is probably inconsistent.");
    endif
    $wiz_utils:set_email_address(new, address);
    $registration_db:add(new, address, @rest);
    move(new, $player_start);
    new.programmer = $player_class.programmer;
    return {new, password};
  endmethod

  verb do_make_player (any any any) owner: #2 flags: "rxd"
    "do_maker_player(name,email,[comment])";
    "Common code for @make-player";
    "If no password is given, generates a random password for the player.";
    "Email-address is stored in $registration_db and on the player object.";
    !caller_perms().wizard && return E_PERM;
    let {name, email, @comments} = args;
    comments = $string_utils:from_list(comments, " ");
    let reason = $wiz_utils:check_player_request(name, email);
    const others = $registration_db:find_exact(email);
    if (others)
      player:notify(email + " is the registered address of the following characters:");
      for x in (others)
        player:notify(tostr(valid(x[1]) ? x[1].name | "<recycled>", valid(x[1]) && !is_player(x[1]) ? " {nonplayer}" | "", " (", x[1], ") ", length(x) > 1 ? "[" + tostr(@x[2..$]) + "]" | ""));
      endfor
      if (!reason)
        reason = "Already registered.";
      endif
    endif
    if (reason)
      player:notify(reason);
      if (!$command_utils:yes_or_no("Create character anyway? "))
        player:notify("Character not created.");
        return;
      endif
    endif
    const new = $wiz_utils:make_player(name, email, comments);
    player:notify(tostr(name, " (", new[1], ") created with password `", new[2], "' for ", email, comments ? " [" + comments + "]" | ""));
    $mail_agent:send_message(player, $new_player_log, tostr(name, " (", new[1], ")"), tostr(email, comments ? " " + comments | ""));
  endverb

  method do_register owner: #2
    "do_register(name, email_address [,comments])";
    "change player's email address.";
    !caller_perms().wizard && return E_PERM;
    let {whostr, email, @comments} = args;
    comments = $string_utils:from_list(comments);
    const who = $string_utils:match_player(whostr);
    $command_utils:player_match_failed(who, whostr) && return;
    if (whostr != who.name && !(whostr in who.aliases) && whostr != tostr(who))
      player:notify(tostr("Must be a full name or an object number:  ", who.name, "(", who, ")"));
      return;
    endif
    const reason = $mail_agent:invalid_email_address(email);
    if (reason)
      player:notify(reason);
      if (!$command_utils:yes_or_no("Register anyway?"))
        return player:notify("re-registration aborted.");
      endif
    endif
    if (comments)
      $registration_db:add(who, email, comments);
    else
      $registration_db:add(who, email);
    endif
    const old = $wiz_utils:get_email_address(who);
    $wiz_utils:set_email_address(who, email);
    player:notify(tostr(who.name, " (", who, ") formerly ", old ? old | "unregistered", ", registered at ", email, ".", comments ? " [" + comments + "]" | ""));
  endmethod

  method do_new_password owner: #2
    "do_new_password(who, [password])";
    !caller_perms().wizard && return E_PERM;
    let {who, ?password = $wiz_utils:random_password(6)} = args;
    if (!password)
      password = $wiz_utils:random_password(6);
    endif
    const whostr = $string_utils:nn(who);
    player:notify(tostr("About to change password for ", whostr, ". Old encrypted password is \"", who.password, "\""));
    const salt_str = salt();
    who.password = argon2(password, salt_str);
    who.last_password_time = time();
    player:notify(tostr(whostr, " new password is `", password, "'."));
  endmethod

  method set_owner_new owner: #2
    ":set_owner(object,newowner[,suspendok]) does object.owner=newowner, taking care of c properties as well.  This should be used anyplace one is contemplating doing object.owner=newowner, since the latter leaves ownership of c properties unchanged.";
    !caller_perms().wizard && return E_PERM;
    return this:set_owner(@args);
  endmethod

  method boot_idlers owner: #2
    "Schedule idle-connection checks under wizard authority.";
    let pl;
    let min;
    let idle;
    !caller_perms().wizard && return E_PERM;
    "------- constants ---- ";
    "20 minutes idle for regular players";
    const mintime = 60 * 20;
    "10 minutes for guests";
    const minguest = 60 * 10;
    "wait 3 minutes before actually booting";
    const bootdelay = 3;
    "start booting when there are 20 less than max players";
    const threshold = 20;
    " ----------------------";
    if ($code_utils:task_valid(this.boot_task) && task_id() != this.boot_task)
      "starting a new one: kill the old one";
      kill_task(this.boot_task);
      this.boot_task = 0;
    endif
    fork taskn (bootdelay * 60 * 3)
      const maxplayers = $login:max_connections() - threshold;
      pl = connected_players();
      if (length(pl) > maxplayers)
        let pll = {};
        let plt = {};
        for x in (pl)
          suspend(0);
          min = $object_utils:isa(x, $guest) ? minguest | mintime;
          idle = `idle_seconds(x) ! ANY => 0';
          if (idle > min && !x.wizard && !(x in this.boot_exceptions))
            pll = {x, @pll};
            plt = {idle, @plt};
          endif
        endfor
        if (pll)
          "Sort by idle time, and choose person who has been idle longest.";
          pll = $list_utils:sort(pll, plt);
          const booted = pll[$];
          const guest = $object_utils:isa(booted, $guest);
          min = guest ? minguest | mintime;
          if (`idle_seconds(booted) ! ANY => 0' > min)
            notify(booted, tostr("*** You've been idle more than ", min / 60, " minutes, and there are more than ", maxplayers, " players connected. If you're still idle and the MOO is still busy in ", bootdelay, " minute", bootdelay == 1 ? "" | "s", ", you will be booted. ***"));
            fork (60 * bootdelay)
              idle = `idle_seconds(booted) ! ANY => 0';
              if (idle > min && length(connected_players()) > $login:max_connections() - threshold)
                notify(booted, "*** You've been idle too long and the MOO is still too busy ***");
                server_log(tostr("IDLE: ", booted.name, " (", booted, ") idle ", idle / 60));
                boot_player(booted);
              endif
            endfork
          endif
        endif
      endif
      this:(verb)(@args);
    endfork
    this.boot_task = taskn;
    "This is set up so that it forks the task first, and this.boot_task is the task_id of whatever is running the idle booter";
  endmethod

  method grant_object owner: #2
    ":grant_object(what, towhom);";
    "Ownership of the object changes as in @chown and :set_owner (i.e., .owner and all c properties change).  In addition all verbs and !c properties owned by the original owner change ownership as well.  Finally, for !c properties, instances on descendant objects change ownership (as in :set_property_owner).";
    let info;
    !caller_perms().wizard && return E_PERM;
    const {object, newowner} = args;
    !is_player(newowner) && return E_INVARG;
    let same = object.owner == newowner;
    for vnum in [1..length(verbs(object))]
      info = verb_info(object, vnum);
      if (!(info[1] != object.owner && (valid(info[1]) && is_player(info[1]))))
        same = same && info[1] == newowner;
        set_verb_info(object, vnum, listset(info, newowner, 1));
      endif
    endfor
    for prop in (properties(object))
      $command_utils:suspend_if_needed(0);
      info = property_info(object, prop);
      if (!(index(info[2], "c") || (info[1] != object.owner && valid(info[1]) && is_player(info[1]))))
        same = same && info[1] == newowner;
        $wiz_utils:set_property_owner(object, prop, newowner, 1);
      endif
    endfor
    suspend(0);
    $wiz_utils:set_owner(object, newowner, 1);
    return same ? "nothing changed" | "grant changed";
  endmethod

  method connection_hash owner: #2
    "connection_hash(forwhom, host [,seed])";
    "Compute an encrypted hash of the host for 'forwhom', using 'crypt'.";
    const {forwhom, host, @seed} = args;
    let hash = toint(forwhom);
    for i in [1..length(host)]
      hash = hash * 14 + index($string_utils.ascii, host[i]);
    endfor
    return crypt(tostr(hash), @seed);
  endmethod

  method newt_player owner: #2
    ":newt_player(who [ , commentary] [, temporary])";
    let {who, ?comment = "", ?temporary = 0} = args;
    if (!caller_perms().wizard)
      $error:raise(E_PERM);
    elseif (length(args) < 1)
      $error:raise(E_ARGS);
    else
      who = args[1];
      if (typeof(who) != TYPE_OBJ || !is_player(who))
        $error:raise(E_INVARG);
      else
        if (!comment)
          player:notify("So why has this player been newted?");
          comment = $command_utils:read();
        endif
        if (temporary)
          comment = temporary + comment;
        endif
        $login.newted = setadd($login.newted, who);
        let msg = player:newt_victim_msg();
        if (msg)
          notify(who, msg);
        endif
        notify(who, $login:newt_registration_string());
        boot_player(who);
        player:notify(tostr(who.name, " (", who, ") has been turned into a newt."));
        $mail_agent:send_message(player, $newt_log, tostr("@newt ", who.name, " (", who, ")"), {$string_utils:from_list(who.all_connect_places, " "), @comment ? {comment} | {}});
        msg = $object_utils:isa(who.location, $room) ? player:newt_msg() | "";
        if (msg)
          who.location:announce_all_but({who}, msg);
        endif
        player:notify(tostr("Mail sent to ", $mail_agent:name($newt_log), "."));
      endif
    endif
  endmethod

  method unset_programmer owner: #2
    ":unset_programmer(victim[,reason[,start time,duration]]) => 1 or error.";
    "Resets victim.programmer, adds victim to .programmer_restricted.";
    "Put into temporary list if 3rd and 4th arguments are given. Which restricts the victim for uptime duration since start time. Must give a reason, though it can be blank, in this case.";
    let {victim, ?reason = "", ?start = 0, ?duration = 0} = args;
    !caller_perms().wizard && return E_PERM;
    if (!valid(victim))
      return E_INVARG;
    elseif (!victim.programmer && this:check_prog_restricted(victim))
      return E_NONE;
    else
      victim.programmer = 0;
      if (is_player(victim) && $object_utils:isa(victim, $player))
        this.programmer_restricted = setadd(this.programmer_restricted, victim);
        if (start)
          this.programmer_restricted_temp = setadd(this.programmer_restricted_temp, {victim, start, duration});
        endif
      endif
      $mail_agent:send_message(caller_perms(), {$newt_log}, tostr("@deprogrammer ", victim.name, " (", victim, ")"), reason ? typeof(reason) == TYPE_STR ? {reason} | reason | {});
      return 1;
    endif
  endmethod

  method is_wizard owner: HACKER
    ":is_wizard(who) => whether `who' is a wizard or is the .public_identity of some wizard.";
    "This verb is used for permission checks on commands that should only be accessible to wizards or their ordinary-player counterparts.  It will return true for unadvertised wizards.";
    const who = args[1];
    who.wizard && return 1;
    for w in ($object_utils:leaves($wiz))
      w.wizard && is_player(w) && who == `w.public_identity ! ANY' && return 1;
    endfor
    return 0;
  endmethod

  verb expire_mail (none none none) owner: #2 flags: "rxd"
    "Expire old list and player mail under wizard authority.";
    !caller_perms().wizard && return E_PERM;
    this:expire_mail_lists();
    this:expire_mail_players();
  endverb

  method expire_mail_weekly owner: #2
    "Schedule the next weekly expiration and run this pass. Wizard callers only.";
    !caller_perms().wizard && return E_PERM;
    fork (7 * 24 * 60 * 60)
      this:(verb)();
    endfork
    this:expire_mail();
  endmethod

  method check_prog_restricted owner: #2
    "Checks to see if args[1] is restricted from programmer either permanently or temporarily. Removes from temporary list if time is up";
    caller != this && !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const who = args[1];
    if (who in this.programmer_restricted)
      "okay, who is restricted. Now check to see if it is temporary";
      const entry = $list_utils:assoc(who, this.programmer_restricted_temp);
      if (entry)
        if ($login:uptime_since(entry[2]) > entry[3])
          "It's temporary and the time is up, remove and return false";
          this.programmer_restricted_temp = setremove(this.programmer_restricted_temp, entry);
          this.programmer_restricted = setremove(this.programmer_restricted, who);
          return 0;
        else
          "time is not up";
          return 1;
        endif
      else
        return 1;
      endif
    else
      return 0;
    endif
  endmethod

  method expire_mail_players owner: #2
    "Expire each player's eligible messages and report the total; commit between players.";
    !caller_perms().wizard && return E_PERM;
    let s = 0;
    for p in (players())
      this.expiration_progress = p;
      if (p.owner == p && is_player(p))
        s = s + (p:expire_old_messages() || 0);
      endif
      if (ticks_left() < 10000)
        set_task_perms($wiz_utils:random_wizard());
        suspend(0);
      endif
    endfor
    $mail_agent:send_message(player, this.expiration_recipient, verb, tostr(s, " messages have been expired from players."));
    return s;
  endmethod

  method expire_mail_lists owner: #2
    "Expire each mailing list's eligible messages and report the total; commit between lists.";
    !caller_perms().wizard && return E_PERM;
    let sum = 0;
    for x in ($object_utils:leaves_suspended($mail_recipient))
      this.expiration_progress = x;
      const temp = x:expire_old_messages();
      if (typeof(temp) == TYPE_INT)
        sum = sum + temp;
      endif
      "just suspend for every fucker, I'm tired of losing.";
      set_task_perms($wiz_utils:random_wizard());
      suspend(0);
    endfor
    $mail_agent:send_message(player, this.expiration_recipient, verb, tostr(sum, " messages have been expired from mailing lists."));
    return sum;
  endmethod

  method flush_editors owner: #2
    "Schedule weekly flushing of inactive editor sessions. Wizard callers only.";
    !caller_perms().wizard && return E_PERM;
    fork (86400 * 7)
      this:(verb)();
    endfork
    player:tell("Flushing ancient editor sessions.");
    for x in ({$verb_editor, $note_editor, $mail_editor})
      x:do_flush(time() - 30 * 86400, 0);
      $command_utils:suspend_if_needed(0);
    endfor
  endmethod

  method random_wizard owner: #2
    "Put all your wizards in $wiz_utils.wizards.  Then various long-running tasks will cycle among the permissions, spreading out the scheduler-induced personal lag.";
    const w = this.wizards;
    let i = this.next_perm_index;
    if (i >= length(w))
      i = 1;
    else
      i = i + 1;
    endif
    this.next_perm_index = i;
    return w[i];
  endmethod

  method set_email_address owner: #2
    "Set a player's primary email address with caller authority.";
    set_task_perms(caller_perms());
    let {who, email} = args;
    if (typeof(who.email_address) == TYPE_LIST)
      who.email_address[1] = email;
    else
      who.email_address = email;
    endif
  endmethod

  method get_email_address owner: #2
    "Read a player's primary email address with caller authority.";
    set_task_perms(caller_perms());
    const {who} = args;
    typeof(who.email_address) == TYPE_LIST && return who.email_address[1];
    return who.email_address;
  endmethod
endobject
