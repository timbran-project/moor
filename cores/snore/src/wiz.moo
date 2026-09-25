object WIZ [
  import_export_id -> "wiz"
]
  name: "generic wizard"
  parent: PROG
  owner: #2
  readable: true

  property advertised (owner: #2, flags: "rc") = 1;
  property mail_identity (owner: #2, flags: "c") = #-1;
  property newt_msg (owner: #2, flags: "rc") = "%n @newts %d (%[#d])";
  property newt_victim_msg (owner: #2, flags: "rc") = "";
  property programmer_msg (owner: #2, flags: "rc") = "%d is now a programmer.";
  property programmer_victim_msg (owner: #2, flags: "rc") = "You are now a programmer.";
  property public_identity (owner: #2, flags: "rc") = #-1;
  property toad_msg (owner: #2, flags: "rc") = "%n @toads %d (%[#d])";
  property toad_victim_msg (owner: #2, flags: "rc") = "Have a nice life...";

  override aliases (owner: #2, flags: "rc") = {"player"};
  override description (owner: #2, flags: "rc") = "You see a wizard who chooses not to reveal its true appearance.";
  override features (owner: HACKER, flags: "r") = {
    PASTING_FEATURE,
    STAGE_TALK,
    UTILITY_FEATURE,
    BUILDER_FEATURE,
    PROGRAMMER_FEATURE,
    WIZARD_FEATURE
  };
  override help (owner: #2, flags: "rc") = WIZ_HELP;
  override mail_notify (owner: #2, flags: "rc");
  override object_size (owner: HACKER, flags: "r") = {56607, 1084848672};
  override password (owner: #2, flags: "") = "really impossible password to type";

  method moveto owner: #2
    "Move a wizard using the caller's authority, or owner authority for trusted editor transitions.";
    set_task_perms(caller in {this, $generic_editor, $verb_editor, $mail_editor, $note_editor} ? this.owner | caller_perms());
    return `move(this, args[1]) ! ANY';
  endmethod

  verb "@rn mail_catch_up check_mail_lists current_message set_current_message get_current_message make_current_message kill_current_message @nn" (none none none) owner: #2 flags: "rxd"
    "Delegate mail state to the configured mail identity when valid.";
    if (caller != this)
      set_task_perms(valid(caller_perms()) ? caller_perms() | player);
    endif
    const use = this.mail_identity;
    valid(use) && use != this && return use:(verb)(@args);
    return pass(@args);
  endverb

  method _mcd_start owner: #2
    "Record extraction selection and an explicit work list; require the selected numbered wizard.";
    const {variant, selection} = args;
    caller_perms().wizard && this == player && this.wizard || raise(E_PERM);
    !is_uuobjid(this) || raise(E_INVARG, "Extract as a numbered core wizard.");
    length(connected_players()) <= 1 || raise(E_INVARG, "Another player is connected.");
    !(`$wizard_feature.__mcd__state ! E_PROPNF => false') || raise(E_INVARG, "Extraction already recorded.");
    const {saved, references, skipped, originals, proxies} = selection;
    this in saved && $wiz in saved && $wizard_feature in saved || raise(E_INVARG, "The extracting wizard and its support must be selected.");
    for object in (saved)
      valid(object) || raise(E_INVARG, "Invalid core selection.");
    endfor
    const owners = [];
    for index in [1..length(originals)]
      if (is_player(originals[index]) && originals[index] != $no_one)
        valid(proxies[index]) && is_player(proxies[index]) || raise(E_INVARG, "A core owner needs a player proxy.");
        owners[originals[index]] = proxies[index];
      endif
    endfor
    for object in (saved)
      if (is_player(object) && object != $no_one)
        owners[object] = object;
      endif
    endfor
    const unwanted = { candidate for candidate in (objects()) if !(candidate in saved) };
    const state = ['wizard -> this, 'variant -> variant, 'saved -> saved, 'references -> references, 'skipped -> skipped, 'originals -> originals, 'proxies -> proxies, 'owners -> owners, 'unwanted -> unwanted, 'phase -> "prepare", 'index -> 1, 'task -> 0];
    add_property($wizard_feature, "__mcd__state", state, {this, ""});
    return true;
  endmethod

  method _mcd_check owner: #2
    "Return current extraction state after checking caller, wizard, connection, and task authority.";
    caller_perms().wizard && this == player && this.wizard || raise(E_PERM);
    const state = $wizard_feature.__mcd__state;
    state['wizard] == this || raise(E_PERM);
    length(connected_players()) <= 1 || raise(E_INVARG, "Another player connected; extraction stopped.");
    const worker = state['task];
    worker != task_id() && valid_task(worker) && raise(E_INVARG, "Extraction is already running.");
    return state;
  endmethod

  method mcd_2 owner: #2
    "Resume recorded extraction with budget checks between work units; shut down after success.";
    const state = this:_mcd_check();
    state['task] = task_id();
    $wizard_feature.__mcd__state = state;
    for task in (queued_tasks())
      task[1] != task_id() && kill_task(task[1]);
    endfor
    suspend(0);
    while (this:_mcd_step())
      $command_utils:suspend_if_needed(0);
    endwhile
    delete_property($wizard_feature, "__mcd__state");
    server_log("Core database extraction is complete.");
    notify(this, "Core database extraction is complete.");
    suspend(0);
    boot_player(this);
    shutdown();
  endmethod

  method _mcd_step owner: #2
    "Complete one recorded extraction unit; return false when done. Require extraction authority.";
    "Persist the cursor after each unit. Called helpers can commit internally; incomplete units must tolerate retry.";
    let state = this:_mcd_check();
    const phase = state['phase];
    const index = state['index];
    const saved = state['saved];
    const unwanted = state['unwanted];
    if (phase == "done")
      return false;
    endif
    if (phase == "prepare")
      for entry in (state['references])
        const {object, properties} = entry;
        for property in (properties)
          const proxy = object.(property) in state['originals];
          proxy && (object.(property) = state['proxies][proxy]);
        endfor
      endfor
      $player_class = $default_player;
      for number in [1..length(verbs(this))]
        delete_verb(this, 1);
      endfor
      for property in (properties(this))
        delete_property(this, property);
      endfor
      chparent(this, $wiz);
      for property in ($object_utils:all_properties(this))
        clear_property(this, property);
      endfor
      this.name = "Wizard";
      this.aliases = {"Wizard"};
      this.description = "";
      this.key = 0;
      this.ownership_quota = 100;
      this.password = 0;
      this.last_password_time = 0;
      $gender_utils:set(this, "neuter");
      state['phase] = "ownership";
    elseif (phase == "ownership")
      if (index > length(saved))
        state['phase] = "strip";
        state['index] = 1;
      else
        this:_mcd_owners(saved[index], state['owners]);
        state['index] = index + 1;
      endif
    elseif (phase == "strip")
      if (index > length(unwanted))
        state['phase] = "delete";
        state['index] = 1;
      else
        const object = unwanted[index];
        if (valid(object))
          for hook in ({"recycle", "exitfunc"})
            while ($object_utils:defines_verb(object, hook))
              delete_verb(object, hook);
            endwhile
          endfor
        endif
        state['index] = index + 1;
      endif
    elseif (phase == "delete")
      if (index > length(unwanted))
        state['phase] = "renumber";
        state['index] = 1;
      else
        const object = unwanted[index];
        if (valid(object))
          for content in (object.contents)
            move(content, $nothing);
          endfor
          is_player(object) && set_player_flag(object, 0);
          !(object in state['skipped]) && chparent(object, $nothing);
          recycle(object);
        endif
        state['index] = index + 1;
      endif
    elseif (phase == "renumber")
      if (index > length(saved))
        let ordered = {};
        for object in (saved)
          let chain = {};
          let ancestor = object;
          while (valid(ancestor) && !(ancestor in ordered))
            ancestor in saved || raise(E_INVARG, "Unselected ancestor survived extraction.");
            chain = {ancestor, @chain};
            ancestor = parent(ancestor);
          endwhile
          ordered = {@ordered, @chain};
        endfor
        state['saved] = ordered;
        state['phase] = "move";
        state['index] = 1;
      else
        const object = saved[index];
        if (is_uuobjid(object))
          state = this:_mcd_number(state, object);
        endif
        state['index] = index + 1;
      endif
    elseif (phase in {"move", "initialize", "measure"})
      if (index > length(saved))
        const next_phase = ["move" -> "initialize", "initialize" -> "measure", "measure" -> "finish"];
        state['phase] = next_phase[phase];
        state['index] = 1;
      else
        const object = saved[index];
        valid(object) || raise(E_INVARG, "A selected core object disappeared.");
        if (phase == "move")
          move(object, $nothing);
        elseif (phase == "initialize")
          if ($object_utils:has_callable_verb(object, "init_for_core"))
            object:init_for_core(state['variant]);
          endif
        else
          $byte_quota_utils:object_bytes(object);
        endif
        state['index] = index + 1;
      endif
    elseif (phase == "finish")
      const unexpected = { candidate for candidate in (objects()) if !(candidate in saved) };
      !unexpected || raise(E_INVARG, "Objects were created during extraction.", unexpected);
      $wiz_utils:initialize_owned();
      $byte_quota_utils:summarize_one_user(this);
      state['phase] = "done";
    else
      raise(E_INVARG, "Unknown extraction phase.", phase);
    endif
    $wizard_feature.__mcd__state = state;
    return state['phase] != "done";
  endmethod

  method _mcd_owners owner: #2
    "Normalize ownership on one saved object without a suspension; require extraction authority.";
    this:_mcd_check();
    const {object, owners} = args;
    fn core_owner(owner)
      const mapped = `owners[owner] ! E_RANGE => $nothing';
      if (valid(mapped))
        return mapped;
      endif
      return valid(owner) && owner.wizard ? this | $hacker;
    endfn
    object.owner = core_owner(object.owner);
    let obsolete = {};
    for number in [1..length(verbs(object))]
      let info = verb_info(object, number);
      info[1] = core_owner(info[1]);
      set_verb_info(object, number, info);
      index(info[3], "(old)") && (obsolete = {number, @obsolete});
    endfor
    for number in (obsolete)
      delete_verb(object, number);
    endfor
    for property in ($object_utils:all_properties(object))
      let info = property_info(object, property);
      info[1] = core_owner(info[1]);
      set_property_info(object, property, info);
    endfor
    return true;
  endmethod

  method _mcd_number owner: #2
    "Number one selected UUID object and repair declared links and owners in the same transaction.";
    this:_mcd_check();
    let {state, old} = args;
    "Keep metadata owners valid while the old ID disappears; protected setters reject invalid owners.";
    let verb_owners = {};
    let property_owners = {};
    for object in (state['saved])
      for number in [1..length(verbs(object))]
        let info = verb_info(object, number);
        if (info[1] == old)
          verb_owners = {@verb_owners, {object, number, info}};
          info[1] = this;
          set_verb_info(object, number, info);
        endif
      endfor
      for property in ($object_utils:all_properties(object))
        let info = property_info(object, property);
        if (info[1] == old)
          property_owners = {@property_owners, {object, property, info}};
          info[1] = this;
          set_property_info(object, property, info);
        endif
      endfor
    endfor
    const numbered = renumber(old, 0);
    state['saved] = { selected_object == old ? numbered | selected_object for selected_object in (state['saved]) };
    let references = {};
    for entry in (state['references])
      const {holder, properties} = entry;
      const object = holder == old ? numbered | holder;
      for property in (properties)
        if (!(property in {"owner", "location"}) && object.(property) == old)
          object.(property) = numbered;
        endif
      endfor
      references = {@references, {object, properties}};
    endfor
    state['references] = references;
    "Native renumber handles object ownership. Restore metadata ownership before this unit can commit.";
    for entry in (verb_owners)
      let {holder, number, info} = entry;
      info[1] = numbered;
      set_verb_info(holder == old ? numbered | holder, number, info);
    endfor
    for entry in (property_owners)
      let {holder, property, info} = entry;
      info[1] = numbered;
      set_property_info(holder == old ? numbered | holder, property, info);
    endfor
    return state;
  endmethod

  method kill_aux_wizard_parse owner: #2
    "Auxiliary verb for parsing @kill soon [#-of-seconds] [player | everyone]";
    "Args[1] is either # of seconds or player/everyone.";
    "Args[2], if it exists, is player/everyone, and forces args[1] to have been # of seconds.";
    "Return value: {# of seconds [default 60] , 1 for all, object for player.}";
    let everyone;
    set_task_perms(caller_perms());
    const nargs = length(args);
    const soon = toint(args[1]);
    if (nargs > 1)
      everyone = args[2];
    elseif (soon <= 0)
      everyone = args[1];
    else
      everyone = 0;
    endif
    if (everyone == "everyone")
      everyone = 1;
    elseif (typeof(everyone) == TYPE_STR)
      const result = $string_utils:match_player(everyone);
      if ($command_utils:player_match_failed(result, everyone))
        player:notify(tostr("Usage:  ", callers()[1][2], " soon [number of seconds] [\"everyone\" | player name]"));
        return {-1, -1};
      else
        return {soon ? soon | 60, result};
      endif
    endif
    return {soon ? soon | 60, everyone ? everyone | player};
  endmethod

  method "toad_msg toad_victim_msg programmer_msg programmer_victim_msg newt_msg newt_victim_msg" owner: #2
    "This is the canonical doing-something-to-somebody message.";
    "The corresponding property can either be";
    "   string             msg for all occasions";
    "   list of 2 strings  {we-are-there-msg,we-are-elsewhere-msg}";
    const m = this.(verb);
    typeof(m) != TYPE_LIST && return $string_utils:pronoun_sub(m);
    this.location == dobj.location || length(m) < 2 && return $string_utils:pronoun_sub(m[1]);
    return $string_utils:pronoun_sub(m[2]);
  endmethod

  method display_list owner: #2
    "Print a login policy list. Require the wizard class or a wizard caller.";
    caller != this && !caller_perms().wizard && return E_PERM;
    const which = args[1];
    let slist = {};
    let s = $login.(which)[1];
    if (s)
      slist = {@slist, "--- Subnets ---", @s};
    endif
    s = $login.(which)[2];
    if (s)
      slist = {@slist, "--- Domains ---", @s};
    endif
    s = $login.("temporary_" + which)[1];
    if (s)
      slist = {@slist, "--- Temporary Subnets ---"};
      for d in (s)
        slist = {@slist, tostr(d[1], " until ", $time_utils:time_sub("$1/$3 $H:$M", d[2] + d[3]))};
        $command_utils:suspend_if_needed(2);
      endfor
    endif
    s = $login.("temporary_" + which)[2];
    if (s)
      slist = {@slist, "--- Temporary Domains ---"};
      for d in (s)
        slist = {@slist, tostr(d[1], " until ", $time_utils:time_sub("$1/$3 $H:$M", d[2] + d[3]))};
        $command_utils:suspend_if_needed(2);
      endfor
    endif
    if (slist)
      player:notify_lines($string_utils:columnize(slist, 2));
    else
      player:notify(tostr("The ", which, " is empty."));
    endif
  endmethod

  method parse_templist_duration owner: HACKER
    "parses out the time interval at the beginning of the args[1], assumes rest is commentary.";
    let cont;
    const fw = $string_utils:first_word(args[1]);
    if (fw[1] == "for")
      const words = $string_utils:words(fw[2]);
      let try_ = {};
      let ind = cont = 1;
      while (cont)
        const word = words[ind];
        cont = ind;
        if (toint(word))
          try_ = {@try_, word};
          ind = ind + 1;
        else
          for set in ($time_utils.time_units)
            if (word in set)
              try_ = {@try_, word};
              ind = ind + 1;
            endif
          endfor
        endif
        if (cont == ind || ind > length(words))
          cont = 0;
        endif
      endwhile
      const dur = $time_utils:parse_english_time_interval(@try_);
      const rest = $string_utils:from_list(words[ind..$], " ");
      return {1, time(), dur, rest};
    else
      return {0, argstr};
    endif
  endmethod

  method check_site_entries owner: #2
    "Called by @[un]<color>list to check existence of the target site.";
    "=> {done okay, LIST of sites to remove}";
    let undo;
    let which;
    let target;
    let is_literal;
    let entrylist;
    let i;
    caller == this || (caller == $wizard_feature && player == this && caller_perms().wizard) || return E_PERM;
    {undo, which, target, is_literal, entrylist} = args;
    let rm = {};
    let confirm = 0;
    if (is_literal)
      for s in (entrylist)
        i = index(s, target + ".");
        if (i == 1)
          "... target is a prefix of s, s should probably go...";
          rm = {@rm, s};
        elseif (index(target + ".", s + ".") != 1)
          "... s is not a prefix of target...";
        elseif (undo)
          player:notify(tostr("You will need to un", which, " subnet ", s, " as well."));
        elseif (confirm)
          player:notify(tostr("...Subnet ", s, " already ", which, "ed..."));
        else
          player:notify(tostr("Subnet ", s, " already ", which, "ed."));
          confirm = $command_utils:yes_or_no(tostr(which, " ", target, " anyway?"));
          !confirm && return {0, {}};
        endif
      endfor
    else
      for s in (entrylist)
        i = rindex(s, "." + target);
        if (i && i == length(s) - length(target))
          "... target is a suffix of s, s should probably go...";
          rm = {@rm, s};
        else
          i = rindex("." + target, "." + s);
          if (!i || i < length(target) - length(s) + 1)
            "... s is not a suffix of target...";
          elseif (undo)
            player:notify(tostr("You will need to un", which, " domain `", s, "' as well."));
          elseif (confirm)
            player:notify(tostr("...Domain `", s, "' already ", which, "ed..."));
          else
            player:notify(tostr("Domain `", s, "' already ", which, "ed."));
            confirm = $command_utils:yes_or_no(tostr(which, " ", target, " anyway?"));
            !confirm && return {0, {}};
          endif
        endif
      endfor
    endif
    return {1, rm};
  endmethod

  method toad_cleanup owner: #2
    "Hook for site-specific cleanup before removing a player account.";
    player.wizard || raise(E_PERM);
    caller == this || (caller == $wizard_feature && player == this && caller_perms().wizard) || raise(E_PERM);
  endmethod
endobject
