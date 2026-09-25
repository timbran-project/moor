object PARANOID_DB [
  import_export_id -> "paranoid_db"
]
  name: "@paranoid database"
  parent: ROOT_CLASS
  owner: HACKER
  readable: true

  property max_lines (owner: #2, flags: "r") = 30;
  property paranoid_data (owner: HACKER, flags: "rc") = [];

  override aliases (owner: HACKER, flags: "rc") = {"@paranoid database", "paranoid"};
  override description (owner: HACKER, flags: "rc") = {
    "",
    "This object stores the @paranoid data from :tell.  Normally it is not necessary to access these things directly.  All verbs are controlled by a caller_perms() check.  Data is stored per player as a record of kept lines and captured text.",
    "",
    ":add_data(who,data) adds one line's worth of data to the collection, trimming from the front as necessary.",
    "",
    ":get_data(who) retrieves the entire batch of data.",
    "",
    ":erase_data(who) sets the data to {}",
    "",
    ":set_kept_lines(who,number) Changes the number of kept lines.  Maximum is 20.",
    "",
    "Core verbs that call the above are $player:tell, @check, @paranoid, and :erase_paranoid_data."
  };
  override object_size (owner: HACKER, flags: "r") = {5921, 1084848672};

  method _entry owner: HACKER
    "Return the stored record for a player, creating a default record when absent.";
    const who = args[1];
    !maphaskey(this.paranoid_data, who) && return ["lines" -> 5, "data" -> {}];
    return this.paranoid_data[who];
  endmethod

  method init_for_core owner: HACKER
    "Reset this object for an extracted core. Wizard callers only.";
    !caller_perms().wizard && return;
    this.paranoid_data = [];
    pass(@args);
  endmethod

  method add_data owner: HACKER
    "Append a bounded caller-history entry for a player. Wizard callers only.";
    const {who, newdata} = args;
    !(is_player(who) && caller_perms().wizard) && return E_PERM;
    const entry = this:_entry(who);
    let data = {@entry["data"], newdata};
    const lines = entry["lines"];
    if (length(data) * 2 > lines * 3)
      data = data[length(data) - lines + 1..$];
    endif
    this.paranoid_data[who] = ["lines" -> lines, "data" -> data];
  endmethod

  method get_data owner: HACKER
    "Return caller history for a player controlled by the caller.";
    const who = args[1];
    $perm_utils:controls(caller_perms(), who) || return E_PERM;
    return this:_entry(who)["data"];
  endmethod

  method erase_data owner: HACKER
    "Clear caller history for a player controlled by the caller.";
    const who = args[1];
    $perm_utils:controls(caller_perms(), who) || return E_PERM;
    const entry = this:_entry(who);
    this.paranoid_data[who] = ["lines" -> entry["lines"], "data" -> {}];
  endmethod

  method set_kept_lines owner: HACKER
    "Set the retained history length for a controlled player, capped by max_lines.";
    const who = args[1];
    $perm_utils:controls(caller_perms(), who) && is_player(who) || return E_PERM;
    const entry = this:_entry(who);
    const kept = min(args[2], this.max_lines);
    this.paranoid_data[who] = ["lines" -> kept, "data" -> entry["data"]];
    return kept;
  endmethod

  method gc owner: HACKER
    "Remove expired history entries under the administrative collection policy.";
    if (caller != this && caller_perms() != #-1 && caller_perms() != player || !player.wizard)
      $error:raise(E_PERM);
    endif
    const threshold = 60 * 60 * 24 * 3;
    for who in (mapkeys(this.paranoid_data))
      if (!valid(who) || !is_player(who) || !this:is_paranoid(who))
        this.paranoid_data = mapdelete(this.paranoid_data, who);
        continue;
      endif
      const entry = this.paranoid_data[who];
      const lines = typeof(entry["lines"]) == TYPE_INT ? entry["lines"] | 10;
      let data = typeof(entry["data"]) == TYPE_LIST ? entry["data"] | {};
      if (!$object_utils:connected(who) && who.last_disconnect_time < time() - threshold && who.last_connect_time < time() - threshold)
        data = {};
      endif
      this.paranoid_data[who] = ["lines" -> lines, "data" -> data];
    endfor
  endmethod

  method help_msg owner: #2
    "Return the caller-history service description.";
    return this:description();
  endmethod

  method semiweeklyish owner: #2
    "Schedule the next history collection and run this one. Wizard callers only.";
    !caller_perms().wizard && return E_PERM;
    const threedays = 3 * 24 * 3600;
    fork (7 * 60 * 60 + threedays - time() % threedays)
      this:(verb)();
    endfork
    this:gc();
  endmethod

  method is_paranoid owner: #2
    "Some people make their .paranoid !r.  Wizardly verb to retrieve value.";
    return `args[1].paranoid ! ANY';
  endmethod
endobject
