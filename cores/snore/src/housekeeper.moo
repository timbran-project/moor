object HOUSEKEEPER [
  import_export_id -> "housekeeper"
]
  name: "housekeeper"
  parent: PROG
  owner: HOUSEKEEPER
  player: true
  programmer: true
  readable: true

  property clean (owner: HOUSEKEEPER, flags: "r") = {};
  property cleaning (owner: HOUSEKEEPER, flags: "rc") = #-1;
  property cleaning_index (owner: HOUSEKEEPER, flags: "rc") = 0;
  property destination (owner: HOUSEKEEPER, flags: "rc") = {};
  property drop_off_msg (owner: HOUSEKEEPER, flags: "rc") = "%[tpsc] arrives to drop off %n, who is sound asleep.";
  property eschews (owner: HOUSEKEEPER, flags: "rc") = {};
  property litter (owner: HOUSEKEEPER, flags: "rc") = {};
  property move_player_task (owner: HOUSEKEEPER, flags: "r") = false;
  property moveto_task (owner: HOUSEKEEPER, flags: "rc") = false;
  property owners (owner: HOUSEKEEPER, flags: "rc") = {#2};
  property player_queue (owner: HOUSEKEEPER, flags: "r") = {};
  property public_places (owner: HOUSEKEEPER, flags: "rc") = {};
  property recycle_bins (owner: HOUSEKEEPER, flags: "rc") = {};
  property requestors (owner: HOUSEKEEPER, flags: "rc") = {};
  property take_away_msg (owner: HOUSEKEEPER, flags: "rc") = "%[tpsc] arrives to cart %n off to bed.";
  property task (owner: HOUSEKEEPER, flags: "rc") = false;
  property testing (owner: HOUSEKEEPER, flags: "rc") = 0;

  override aliases (owner: #2, flags: "r") = {"housekeeper"};
  override description (owner: HOUSEKEEPER, flags: "rc") = "A very clean, neat, tidy person who doesn't mind lugging players and their gear all over the place.";
  override features (owner: HACKER, flags: "r") = {PASTING_FEATURE, STAGE_TALK};
  override last_disconnect_time (owner: #2, flags: "r") = 2147483647;
  override mail_forward (owner: HOUSEKEEPER, flags: "rc") = {#2};
  override object_size (owner: HACKER, flags: "r") = {21397, 1084848672};
  override owned_objects (owner: #2, flags: "r") = {HOUSEKEEPER};
  override ownership_quota (owner: HACKER, flags: "") = -9993;
  override page_absent_msg (owner: HOUSEKEEPER, flags: "rc") = "The housekeeper is too busy putting away all of the junk around the MOO that there isn't time to listen to pages and stuff like that so your page isn't listened to, too bad.";
  override po (owner: HOUSEKEEPER, flags: "rc") = "the housekeeper";
  override poc (owner: HOUSEKEEPER, flags: "rc") = "The housekeeper";
  override pp (owner: HOUSEKEEPER, flags: "rc") = "the housekeeper's";
  override ppc (owner: HOUSEKEEPER, flags: "rc") = "The housekeeper's";
  override pq (owner: HOUSEKEEPER, flags: "rc") = "the housekeeper's";
  override pqc (owner: HOUSEKEEPER, flags: "rc") = "The housekeeper's";
  override pr (owner: HOUSEKEEPER, flags: "rc") = "'self";
  override prc (owner: HOUSEKEEPER, flags: "rc") = "'Self";
  override ps (owner: HOUSEKEEPER, flags: "rc") = "the housekeeper";
  override psc (owner: HOUSEKEEPER, flags: "rc") = "The housekeeper";
  override size_quota (owner: HACKER, flags: "") = {183000, 34096, 1084780981, 0};

  method look_self owner: HOUSEKEEPER
    "Describe the housekeeper and its cleaning role.";
    player:tell_lines(this:description());
    player:tell($string_utils:pronoun_sub("%S %<is> moving around from room to room, cleaning up.", this));
  endmethod

  method cleanup owner: HOUSEKEEPER
    "$housekeeper:cleanup([insist]) => clean up player's objects. Argument is 'up' or 'up!' for manually requested cleanups (notify player differently)";
    caller_perms() != this && return E_PERM;
    for object in (this.clean)
      const x = object in this.clean;
      if (x && this.requestors[x] == player)
        const result = this:replace(object, @args);
        if (result)
          player:tell(result, ".");
        endif
      endif
      $command_utils:suspend_if_needed(0);
    endfor
    player:tell("The housekeeper has finished cleaning up your objects.");
  endmethod

  method replace owner: HOUSEKEEPER
    "replace the object given to its proper spot (if there is one).";
    let loc;
    let tr;
    const {object, ?insist = 0} = args;
    const i = object in this.clean;
    !i && return tostr(object, " is not on the ", this.name, "'s cleanup list");
    const place = this.destination[i];
    const r = this.requestors[i];
    if (!($recycler:valid(object) && $recycler:valid(r) && is_player(r) && ($recycler:valid(place) || place == #-1) && !(object.location in this.recycle_bins)))
      "object no longer valid (recycled or something), remove it.";
      this.clean = listdelete(this.clean, i);
      this.requestors = listdelete(this.requestors, i);
      this.destination = listdelete(this.destination, i);
      return tostr(object) + " is no longer valid, removed from cleaning list";
    endif
    const oldloc = loc = object.location;
    if (object.location == place)
      "already in its place";
      return "";
    endif
    const requestor = $recycler:valid(tr = this.requestors[i]) ? tr | $no_one;
    if (insist != "up!")
      if ($code_utils:verb_or_property(object, "in_use"))
        return "Not returning " + object.name + " because it claims to be in use";
      endif
      for thing in (object.contents)
        if (thing:is_listening())
          return "Not returning " + object.name + " because " + thing.name + " is inside";
        endif
        $command_utils:suspend_if_needed(0);
      endfor
      if (valid(loc) && loc != $limbo)
        if (loc:is_listening())
          return "Not returning " + object.name + " because " + loc.name + " is holding it";
        endif
        for y in (loc:contents())
          if (y != object && y:is_listening())
            return "Not returning " + object.name + " because " + y.name + " is in " + loc.name;
          endif
          $command_utils:suspend_if_needed(0);
        endfor
      endif
    endif
    if (valid(place) && !place:acceptable(object))
      return place.name + " won't accept " + object.name;
    endif
    try
      requestor:tell("As you requested, the housekeeper tidies ", $string_utils:nn(object), " from ", $string_utils:nn(loc), " to ", $string_utils:nn(place), ".");
      if ($object_utils:has_verb(loc, "announce_all_but"))
        loc:announce_all_but({requestor, object}, "At ", requestor.name, "'s request, the ", this.name, " sneaks in, picks up ", object.name, " and hurries off to put ", $object_utils:has_property(object, "po") && typeof(object.po) == TYPE_STR ? object.po | "it", " away.");
      endif
    except (ANY)
      "Ignore errors";
    endtry
    fork (0)
      this:moveit(object, place, requestor);
      !valid(object) && return;
      loc = object.location;
      if (loc == oldloc)
        return object.name + " wouldn't go; " + (!place:acceptable(object) ? " perhaps " + $string_utils:nn(place) + " won't let it in" | " perhaps " + $string_utils:nn(loc) + " won't let go of it");
      endif
      try
        object:tell("The housekeeper puts you away.");
        if ($object_utils:isa(loc, $room))
          loc:announce_all_but({object}, "At ", requestor.name, "'s request, the housekeeper sneaks in, deposits ", object:title(), " and leaves.");
        else
          loc:tell("You notice the housekeeper sneak in, give you ", object:title(), " and leave.");
        endif
      except (ANY)
        "Ignore errors";
      endtry
    endfork
    return "";
  endmethod

  verb cleanup_list (any none none) owner: HOUSEKEEPER flags: "rxd"
    "Print all cleanup requests, or requests involving one player.";
    let who;
    let tr;
    if (args)
      who = args[1];
      !valid(who) && return;
      player:tell(who.name, "'s personal cleanup list:");
    else
      who = 0;
      player:tell("Housekeeper's complete cleanup list:");
    endif
    player:tell("------------------------------------------------------------------");
    let printed_anything = 0;
    const objs = this.clean;
    const reqs = this.requestors;
    const dest = this.destination;
    for i in [1..length(objs)]
      $command_utils:suspend_if_needed(2);
      const req = $recycler:valid(tr = reqs[i]) ? tr | $no_one;
      const ob = objs[i];
      const place = dest[i];
      if (who == 0 || req == who || (valid(ob) && ob.owner == who))
        if (!valid(ob))
          player:tell(ob, " ** recycled ** ", "(", req.name, ")");
        else
          player:tell(ob, " ", ob.name, " => ", place, " ", (valid(place) ? place.name | "nowhere") || "nowhere", " (", req.name, ")");
        endif
        printed_anything = 1;
      endif
    endfor
    if (!printed_anything)
      player:tell("** The housekeeper has nothing in the cleanup list.");
    endif
    player:tell("------------------------------------------------------------------");
  endverb

  verb add_cleanup (any any any) owner: HOUSEKEEPER flags: "rxd"
    "Add a cleanup request after checking caller control and the requested destination.";
    let what;
    let who;
    let where;
    let tr;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    {what, ?who = player, ?where = what.location} = args;
    !valid(what) || what == #0 && return "invalid object";
    $object_utils:isa(who, $guest) && return tostr("Guests can't use the ", this.name, ".");
    !is_player(who) && return tostr("Non-players can't use the ", this.name, ".");
    if (!valid(where))
      return tostr("The ", this.name, " doesn't know how to find ", where, " in order to put away ", what.name, ".");
    endif
    if (is_player(what))
      return "The " + this.name + " doesn't do players, except to cart them home when they fall asleep.";
    endif
    for x in (this.eschews)
      if ($object_utils:isa(what, x[1]))
        let ok = 0;
        for y in [3..length(x)]
          if ($object_utils:isa(what, x[y]))
            ok = 1;
          endif
        endfor
        !ok && return tostr("The ", this.name, " doesn't do ", x[2], "!");
      endif
    endfor
    if ($object_utils:has_callable_verb(where, "litterp") ? where:litterp(what) | where in this.public_places && !(what in where.residents))
      return tostr("The ", this.name, " won't litter ", where.name, "!");
    endif
    const i = what in this.clean;
    if (i)
      if (!this:controls(i, who) && valid(this.destination[i]))
        return tostr($recycler:valid(tr = this.requestors[i]) ? tr.name | "Someone", " already asked that ", what.name, " be kept at ", this.destination[i].name, "!");
      endif
      this.requestors[i] = who;
      this.destination[i] = where;
    else
      this.clean = {what, @this.clean};
      this.requestors = {who, @this.requestors};
      this.destination = {where, @this.destination};
    endif
    return tostr("The ", this.name, " will keep ", what.name, " (", what, ") at ", valid(where) ? where.name + " (" + tostr(where) + ")" | where, ".");
  endverb

  verb remove_cleanup (any none none) owner: HOUSEKEEPER flags: "rxd"
    "Remove a cleanup request when the supplied player controls that request.";
    let what;
    let who;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    {what, ?who = player} = args;
    const i = what in this.clean;
    if (i)
      if (!this:controls(i, who))
        return tostr("You may remove an object from ", this.name, " list only if you own the object, the place it is kept, or if you placed the original cleaning order.");
      endif
      this.clean = listdelete(this.clean, i);
      this.destination = listdelete(this.destination, i);
      this.requestors = listdelete(this.requestors, i);
      return tostr(what.name, " (", what, ") removed from cleanup list.");
    else
      return tostr(what.name, " not in cleanup list.");
    endif
  endverb

  method controls owner: HOUSEKEEPER
    "does player control entry I?";
    const {i, who} = args;
    who in {this.owner, @this.owners} || who.wizard && return "Yessir.";
    const cleanable = this.clean[i];
    if (this.requestors[i] == who)
      return "you asked for the previous result, you can change this one.";
    endif
    const dest = this.destination[i];
    who == cleanable.owner || !valid(dest) || who == dest.owner && return "you own the object or the place where it is being cleaned to, or the destination is no longer valid.";
    return "";
  endmethod

  method continuous owner: HOUSEKEEPER
    "start the housekeeper cleaning continuously. Kill any previous continuous";
    "task. Not meant to be called interactively.";
    let x;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    if ($code_utils:task_valid(this.task))
      taskn = this.task;
      this.task = false;
      kill_task(taskn);
    endif
    fork taskn (0)
      while (true)
        let index = 1;
        while (index <= length(this.clean))
          this.cleaning = x = this.clean[index];
          this.cleaning_index = index;
          index = index + 1;
          fork (0)
            `this:replace(x) ! ANY';
          endfork
          suspend(this.testing ? 2 | this:time());
        endwhile
        suspend(5);
        this:litterbug();
      endwhile
    endfork
    this.task = taskn;
  endmethod

  method litterbug owner: HOUSEKEEPER
    "Return unattended litter from configured rooms. Each delayed move rechecks the object.";
    for room in (this.public_places)
      for thingy in (room.contents)
        suspend(10);
        if (valid(thingy) && valid(room) && thingy.location == room && this:is_litter(thingy) && !this:is_watching(thingy, $nothing))
          "if it is litter and no-one is watching";
          fork (0)
            this:send_home(thingy);
          endfork
          suspend(0);
        endif
      endfor
    endfor
  endmethod

  method is_watching owner: HOUSEKEEPER
    "Return whether a valid object is listening.";
    let thing;
    return valid(thing = args[1]) && thing:is_listening();
  endmethod

  method send_home owner: HOUSEKEEPER
    "Return litter home and announce the move. Internal housekeeper calls only.";
    caller != this && return E_PERM;
    const litter = args[1];
    const littering = litter.location;
    this:ejectit(litter, littering);
    const home = litter.location;
    if ($object_utils:isa(home, $room))
      home:announce_all("The ", this.name, " sneaks in, deposits ", litter:title(), " and leaves.");
    else
      home:tell("You notice the ", this.name, " sneak in, give you ", litter:title(), " and leave.");
    endif
    if ($object_utils:has_callable_verb(littering, "announce_all_but"))
      littering:announce_all_but({litter}, "The ", this.name, " sneaks in, picks up ", litter:title(), " and rushes off to put it away.");
    endif
  endmethod

  method moveit owner: #2
    "Wizardly verb to move object with requestor's permission";
    caller != this && return E_PERM;
    set_task_perms(player = args[3]);
    return args[1]:moveto(args[2]);
  endmethod

  method ejectit owner: #2
    "this:ejectit(object,room): Eject args[1] from args[2].  Callable only by housekeeper's quarters verbs.";
    if (caller == this)
      args[2]:eject(args[1]);
    endif
  endmethod

  method is_object_cleaned owner: HOUSEKEEPER
    "Return {destination, requestor} for a cleanup request, or zero if absent.";
    const what = args[1];
    const where = what in this.clean;
    !where && return 0;
    return {this.destination[where], this.requestors[where]};
  endmethod

  method is_litter owner: HOUSEKEEPER
    "Return whether the object matches the configured litter classes.";
    const thingy = args[1];
    for x in (this.litter)
      $object_utils:isa(thingy, x[1]) && !$object_utils:isa(thingy, x[2]) && return true;
    endfor
    return false;
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      this.password = "Impossible password to type";
      this.last_password_time = 0;
      this.litter = {};
      this.public_places = {};
      this.requestors = {};
      this.destination = {};
      this.clean = {};
      this.eschews = {};
      this.recycle_bins = {};
      this.cleaning = #-1;
      this.task = false;
      this.owners = {#2};
      this.mail_forward = {#2};
      this.player_queue = {};
      this.move_player_task = false;
      this.moveto_task = false;
      pass(@args);
    endif
  endmethod

  method clean_status owner: HOUSEKEEPER
    "Print cleaning counts and restart the worker if the caller is authorized.";
    let count = 0;
    for i in (this.requestors)
      if (i == player)
        count = count + 1;
      endif
    endfor
    player:tell("Number of items in cleanup list: ", tostr(length(this.clean)));
    player:tell("Number of items you requested to be tidied: ", tostr(count));
    player:tell("Number of requestors: ", tostr(length($list_utils:remove_duplicates(this.requestors))));
    player:tell("Time to complete one cleaning circuit: ", $time_utils:english_time(length(this.clean) * this:time()));
    player:tell("The Housekeeper is in " + ($housekeeper.testing == 0 ? "normal, non-testing mode." | "testing mode. "));
    if (!$code_utils:task_valid($housekeeper.task))
      player:tell("The Housekeeper task has died. Restarting...");
      $housekeeper:continuous();
    else
      player:tell("The Housekeeper is actively cleaning.");
    endif
  endmethod

  method is_cleaning owner: HOUSEKEEPER
    "return a string status if the hosuekeeper is cleaning this object";
    const cleanable = args[1];
    const info = this:is_object_cleaned(cleanable);
    info == 0 && return tostr(cleanable.name, " is not cleaned by the ", this.name, ".");
    return tostr(cleanable.name, " is kept tidy at ", $string_utils:nn(info[1]), " at the request of ", $string_utils:nn(info[2]), ".");
  endmethod

  method time owner: HOUSEKEEPER
    "Returns the amount of time to suspend between objects while continuous cleaning.";
    "Currently set to try to complete cleaning circuit in one hour, but not exceed one object every 20 seconds.";
    return max(20 + $login:current_lag(), length(this.clean) ? 3600 / length(this.clean) | 0);
  endmethod

  method acceptable owner: #2
    "Accept movement only from the housekeeper itself.";
    return caller == this;
  endmethod

  method move_players_home owner: #2
    "Queue a disconnected player for a delayed trip home. Require housekeeper control.";
    if (!$perm_utils:controls(caller_perms(), this))
      "perms don't control the $housekeeper; probably not called by $room:disfunc then. Used to let args[1] call this. No longer.";
      return E_PERM;
    endif
    this.player_queue = {@this.player_queue, {args[1], time() + 300}};
    if ($code_utils:task_valid(this.move_player_task))
      "the move-players-home task is already running";
      return;
    endif
    fork tid (10)
      while (this.player_queue)
        const mtime = this.player_queue[1][2];
        if (mtime < time() + 10)
          const who = this.player_queue[1][1];
          "Remove from queue first so that if they do something malicious, like put a kill_task in a custom :accept_for_abode, they won't be in the queue when the task restarts with the next player disconnect. Ho_Yan 12/3/98";
          this.player_queue = listdelete(this.player_queue, 1);
          if (valid(who) && is_player(who) && !$object_utils:connected(who))
            const dest = `who.home:accept_for_abode(who) ! ANY => 0' ? who.home | $player_start;
            if (who.location != dest)
              player = who;
              this:move_em(who, dest);
            endif
          endif
        else
          suspend(mtime - time());
        endif
        $command_utils:suspend_if_needed(1);
      endwhile
    endfork
    this.move_player_task = tid;
  endmethod

  method move_em owner: #2
    "Move a queued player with its own authority; fork a fallback for failed movement.";
    if (caller == this)
      const {who, dest} = args;
      set_task_perms(who);
      fork (0)
        fork (0)
          "This is forked so that it's protected from aborts due to errors in the player's :moveto verb.";
          if (who.location != dest)
            "Unfortunately, if who is -already- at $player_start, move() won't call :enterfunc and the sleeping body never goes to $limbo. Have to call explicitly for that case. Ho_Yan 11/2/95";
            if (who.location == $player_start)
              $player_start:enterfunc(who);
            else
              "Nosredna, 5/4/01: but wait, why don't we just moved them straight to limbo?";
              move(who, $limbo);
            endif
          endif
        endfork
        const start = who.location;
        this:set_moveto_task();
        who:moveto(dest);
        if (who.location != start)
          start:announce(this:take_away_msg(who));
        endif
        if (who.location == dest)
          dest:announce(this:drop_off_msg(who));
        endif
      endfork
    else
      return E_PERM;
    endif
  endmethod

  method "take_away_msg drop_off_msg" owner: HOUSEKEEPER
    "Expand a housekeeper movement message for the supplied player.";
    return $string_utils:pronoun_sub(this.(verb), args[1], this);
  endmethod

  method set_moveto_task owner: HOUSEKEEPER
    "sets $housekeeper.moveto_task to the current task_id() so player:moveto's can check for validity.";
    caller != this && return E_PERM;
    this.moveto_task = task_id();
  endmethod
endobject
