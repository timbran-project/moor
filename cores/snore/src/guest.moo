object GUEST [
  import_export_id -> "guest"
]
  name: "Generic Guest"
  parent: DEFAULT_PLAYER
  owner: HACKER
  readable: true

  property default_description (owner: HACKER, flags: "r") = {"By definition, guests appear nondescript."};
  property default_gender (owner: HACKER, flags: "r") = "neuter";
  property extra_confunc_msg (owner: HACKER, flags: "rc") = "";
  property free_to_use (owner: HACKER, flags: "r") = true;
  property request (owner: #2, flags: "") = false;

  override aliases (owner: #2, flags: "r") = {"Generic Guest"};
  override description (owner: HACKER, flags: "rc") = {"By definition, guests appear nondescript."};
  override features (owner: HACKER, flags: "r") = {PASTING_FEATURE, STAGE_TALK, UTILITY_FEATURE};
  override mail_forward (owner: HACKER, flags: "rc") = "%t (%[#t]) is a guest character.";
  override mail_notify (owner: HACKER, flags: "rc");
  override object_size (owner: HACKER, flags: "r") = {12606, 1084848672};
  override paranoid (owner: HACKER, flags: "rc") = 1;
  override password (owner: #2, flags: "") = 0;
  override size_quota (owner: HACKER, flags: "") = {0, 0, 0, 0};

  method boot owner: #2
    "Tell a displaced guest why another visitor needs the character; wizard login code only.";
    caller_perms().wizard || return E_PERM;
    const alternative = $login:player_creation_enabled(this) ? " or create your own character." | " or type 'create' for registration information.";
    this:notify(tostr("Sorry, you've been connected for ", $string_utils:from_seconds(connected_seconds(this)), " and someone else wants to be a guest. Feel free to come back", alternative));
  endmethod

  method disfunc owner: #2
    "Reset an authorized guest disconnection; keep the character unavailable until cleanup succeeds.";
    "Movement and feature/editor hooks can commit. A failed reset leaves free_to_use false.";
    const principal = caller_perms();
    caller == this || caller == $sysobj || principal == this || $perm_utils:controls(principal, this) || return E_PERM;
    this.free_to_use = false;
    this:log_disconnect();
    this:erase_paranoid_data();
    try
      if (this.location != this.home)
        this:room_announce(tostr(this.name, " has disconnected."));
        this:room_announce($string_utils:pronoun_sub($housekeeper.take_away_msg, this, $housekeeper));
        move(this, this.home);
        this:room_announce($string_utils:pronoun_sub($housekeeper.drop_off_msg, this, $housekeeper));
      endif
    finally
      this:do_reset();
      this.free_to_use = true;
    endtry
  endmethod

  method defer owner: #2
    "Choose a free guest, or displace one connected for more than fifteen minutes.";
    "Return $nothing when none is available or $ambiguous_match for a blocked host; wizard login only.";
    caller_perms().wizard || return this;
    $login:blacklisted($string_utils:connection_hostname(connection_name(player))) && return $ambiguous_match;
    const connected = connected_players();
    !(this in connected) && this.free_to_use && return this;
    let longest = 900;
    let candidate = $nothing;
    let free = {};
    for guest in ($object_utils:leaves($guest))
      if (!is_player(guest))
        continue;
      endif
      if (!(guest in connected) && guest.free_to_use)
        free = {@free, guest};
      elseif (guest in connected)
        const elapsed = connected_seconds(guest);
        if (elapsed > longest)
          longest = elapsed;
          candidate = guest;
        endif
      endif
    endfor
    free && return free[random(length(free))];
    valid(candidate) && candidate:boot();
    return candidate;
  endmethod

  method mail_catch_up owner: #2
    "Guests do not keep a subscription reading position.";
    return 0;
  endmethod

  verb create (any any any) owner: HACKER flags: "rd"
    "Explain how a guest can request or create a permanent character.";
    if ($login:player_creation_enabled(player))
      player:tell("First @quit, then reconnect and use 'create <name> <password>'.");
    else
      player:tell($login:registration_string());
    endif
  endverb

  method eject owner: HACKER
    "Use inherited inventory ejection, including its permission checks.";
    return pass(@args);
  endmethod

  method log owner: HACKER
    "Prepend {is_login, timestamp, host} to this guest's bounded log; self calls only.";
    caller == this || return E_PERM;
    const limit = max(0, this.max_connect_log);
    this.connect_log = limit ? {args, @this.connect_log[1..min($, limit - 1)]} | {};
  endmethod

  method confunc owner: #2
    "Record an authorized guest connection and run inherited connection hooks.";
    const principal = caller_perms();
    caller == this || caller == $sysobj || principal == this || $perm_utils:controls(principal, this) || return E_PERM;
    $guest_log:enter(true, time(), $string_utils:connection_hostname(connection_name(this)));
    const result = pass(@args);
    this:tell_lines(this:extra_confunc_msg());
    return result;
  endmethod

  method log_disconnect owner: #2
    "Record a disconnection using the saved host if the live connection is already gone.";
    caller == this || return E_PERM;
    const connection = `connection_name(this) ! ANY => this.last_connect_place';
    $guest_log:enter(false, time(), $string_utils:connection_hostname(connection));
  endmethod

  verb "@last-c*onnection" (any none none) owner: #2 flags: "rxd"
    "Suppress previous visitors' connection details in the guest command.";
    !valid(caller_perms()) && player:tell("Sorry, that information is not available.");
  endverb

  method my_huh owner: #2
    "Allow only the guest's own command parser to invoke inherited fallback behavior.";
    caller_perms() == this || return E_PERM;
    return pass(@args);
  endmethod

  verb "@read @peek" (any any any) owner: HACKER flags: "rd"
    "Use inherited read-only mail commands for guest-accessible lists.";
    return pass(@args);
  endverb

  method set_current_folder owner: HACKER
    "Delegate folder access and assignment to the inherited permission checks.";
    return pass(@args);
  endmethod

  method init_for_core owner: #2
    "Reset the guest prototype's extra greeting during wizard-controlled extraction.";
    caller_perms().wizard || return E_PERM;
    pass(@args);
    this.extra_confunc_msg = "";
  endmethod

  method "set_name set_aliases" owner: #2
    "Delegate naming changes only when the caller controls this guest.";
    $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return pass(@args);
  endmethod

  method extra_confunc_msg owner: #2
    "Expand pronouns in the extra guest greeting.";
    return $string_utils:pronoun_sub(this.extra_confunc_msg);
  endmethod

  method do_reset owner: #2
    "Restore visitor state from the prototype; wizard authority only.";
    "Feature, movement, and editor hooks may commit. The disconnect hook controls guest availability.";
    caller_perms().wizard || return E_PERM;
    const ancestor = parent(this);
    const reset_properties = {"paranoid", "responsible", "brief", "gaglist", "rooms", "current_message", "current_folder", "messages", "messages_going", "messages_kept", "request", "mail_options", "edit_options", "home", "spurned_objects", "web_info", "refused_origins", "refused_actions", "refused_until", "refused_extra", "report_refusal", "default_refusal_time", "page_refused"};
    for name in (reset_properties)
      $object_utils:has_property(ancestor, name) && clear_property(this, name);
    endfor
    this:set_description(this.default_description);
    this:set_gender(this.default_gender);
    for item in (this.contents)
      this:eject(item);
    endfor
    for feature in (this.features)
      !(feature in $guest.features) && this:remove_feature(feature);
    endfor
    for feature in ($guest.features)
      !(feature in this.features) && this:add_feature(feature);
    endfor
    for editor in ($object_utils:descendants($generic_editor))
      const position = this in editor.active;
      position && editor:kill_session(position);
    endfor
  endmethod

  verb "@request" (any any any) owner: #2 flags: "rd"
    "Usage: @request <player-name> for <email-address>; each guest visit may submit one request.";
    player == this || return player:tell(E_PERM);
    this.request && return player:tell("Sorry, you appear to have already requested a character.");
    prepstr != "for" || !dobjstr || index(iobjstr, " ") && return player:notify_lines($code_utils:verb_usage());
    $login:request_character(player, dobjstr, iobjstr) && (this.request = true);
  endverb

  method connection_name_hash owner: #2
    "Return a caller-specific host fingerprint without converting opaque object IDs to integers.";
    "Optional crypt arguments retain the salted fingerprint interface; the format is not a stable ID.";
    const host = $string_utils:connection_hostname(this.last_connect_place);
    return crypt(string_hash(tostr(caller_perms(), ":", host), "sha256"), @args);
  endmethod

  verb "@subscribe*-quick @unsubscribed*-quick" (any any any) owner: #2 flags: "rd"
    "List readable mailing lists or explain the guest subscription restriction.";
    "Confirmation reads and budget yields commit; each list checks current guest access.";
    caller_perms() != $nothing && caller_perms() != player && return E_PERM;
    if (args)
      return player:tell("Sorry, Guests don't have full mailing privileges. Use @read and @peek, or @request a character.");
    endif
    const lists = {@$mail_agent.contents, @this.mail_lists};
    if (length(lists) > 50 && !$command_utils:yes_or_no(tostr("There are ", length(lists), " mailing lists. Are you sure you want the whole list?")))
      return player:tell("OK, aborting.");
    endif
    for list in (lists)
      $command_utils:suspend_if_needed(0);
      if (valid(list) && (list:is_usable_by(this) || list:is_readable_by(this)) && verb != "@unsubscribed")
        `list:look_self(1) ! ANY';
      endif
    endfor
    player:tell("--End of List--");
  endverb

  method current_folder owner: #2
    "Delegate folder lookup only for this guest or its owner.";
    caller_perms() in {this, this.owner} || return E_PERM;
    return pass(@args);
  endmethod

  method notify owner: #2
    "Delegate notification only for the guest, its owner, self calls, or a wizard.";
    caller_perms().wizard || caller_perms() in {this, this.owner} || caller == this || return E_PERM;
    return pass(@args);
  endmethod
endobject
