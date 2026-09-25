object REGISTRATION_DB [
  import_export_id -> "registration_db"
]
  name: "Registration Database"
  parent: ROOT_CLASS
  owner: HACKER

  property prune_progress (owner: HACKER, flags: "rc") = "";
  property prune_task (owner: HACKER, flags: "rc") = false;
  property registrar (owner: HACKER, flags: "rc") = #2;
  property registrations (owner: HACKER, flags: "rc") = [];
  property suspicious_userids (owner: #2, flags: "rc") = {
    "",
    "sysadmin",
    "root",
    "postmaster",
    "bin",
    "SYSTEM",
    "OPERATOR",
    "guest",
    "me",
    "mailer-daemon",
    "webmaster",
    "sysop",
    "info"
  };
  property total_pruned_characters (owner: HACKER, flags: "rc") = 0;
  property total_pruned_people (owner: HACKER, flags: "rc") = 0;

  override aliases (owner: HACKER, flags: "rc") = {"Registration Database"};
  override object_size (owner: HACKER, flags: "r") = {8549, 1084848672};

  method _key owner: HACKER
    "Normalize an email address for case-insensitive lookup.";
    return $string_utils:lowercase(args[1]);
  endmethod

  method find_exact owner: HACKER
    ":find_exact(email) => list of {who, comments} entries or $failed_match.";
    caller == this || caller_perms().wizard || return E_PERM;
    const key = this:_key(args[1]);
    !maphaskey(this.registrations, key) && return $failed_match;
    return this.registrations[key];
  endmethod

  method find_all_keys owner: HACKER
    ":find_all_keys(email) => keys whose addresses begin with email.";
    caller == this || caller_perms().wizard || return E_PERM;
    const key = this:_key(args[1]);
    let found = {};
    for candidate in (mapkeys(this.registrations))
      if (index(candidate, key) == 1)
        found = setadd(found, candidate);
      endif
    endfor
    return found;
  endmethod

  method insert owner: HACKER
    ":insert(email, list) => {old list} if the address was present, otherwise 0.";
    caller == this || caller_perms().wizard || return E_PERM;
    const {email, value} = args;
    typeof(email) == TYPE_STR || return E_INVARG;
    const key = this:_key(email);
    if (maphaskey(this.registrations, key))
      const old = this.registrations[key];
      this.registrations[key] = value;
      return {old};
    endif
    this.registrations[key] = value;
    return 0;
  endmethod

  method delete owner: HACKER
    ":delete(email) => {old list} if the address was present, otherwise 0.";
    caller == this || caller_perms().wizard || return E_PERM;
    const email = args[1];
    typeof(email) == TYPE_STR || return E_INVARG;
    const key = this:_key(email);
    !maphaskey(this.registrations, key) && return 0;
    const old = this.registrations[key];
    this.registrations = mapdelete(this.registrations, key);
    return {old};
  endmethod

  method clearall owner: HACKER
    ":clearall() => clears the registration index.";
    caller == this || caller_perms().wizard || return E_PERM;
    this.registrations = [];
  endmethod

  method add owner: HACKER
    ":add(player,email[,comment])";
    let i;
    !caller_perms().wizard && return E_PERM;
    const {who, email, @comment} = args;
    const l = this:find_exact(email);
    if (l == $failed_match)
      this:insert(email, {{who, @comment}});
    else
      i = $list_utils:iassoc(who, l);
      if (i)
        this:insert(email, listset(l, {who, @comment}, i));
      else
        this:insert(email, {@l, {who, @comment}});
      endif
    endif
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this:clearall();
      this.registrar = #2;
      this:prune_reset();
    endif
  endmethod

  method suspicious_address owner: #2
    "suspicious(address [,who])";
    "Determine whether an address appears to be another player in disguise.";
    "returns a list of similar addresses.";
    "If second argument given, then if all similar addresses are held by that";
    "person, let it pass---they're just switching departments at the same school";
    "or something.";
    let them;
    !caller_perms().wizard && return E_PERM;
    const {address, ?allowed = #-1} = args;
    let {userid, site} = $mail_agent:parse_address(address);
    const exact = !site && this:find_exact(address);
    if (!site)
      site = $mail_agent.site;
    endif
    site = $mail_agent:local_domain(site);
    const sitelen = length(site);
    let others = this:find_all_keys(userid + "@");
    for other in (others)
      if (other[max(1, $ - sitelen + 1)..$] != site)
        others = setremove(others, other);
      endif
    endfor
    if (exact)
      others = listinsert(others, address);
    endif
    for x in (others)
      let allzapped = 1;
      for y in (this:find_exact(x))
        let permitted = length(y) == 2 && y[2] in {"zapped due to inactivity", "toaded due to inactivity"} || y[1] == allowed;
        if (!permitted && $object_utils:has_property($local, "second_char_registry"))
          them = $local.second_char_registry:other_chars(y[1]);
          permitted = typeof(them) == TYPE_LIST && allowed in them;
        endif
        if (permitted)
          "let them change to the address if it is them, or if it is a registered char of theirs.";
        else
          allzapped = 0;
        endif
      endfor
      if (allzapped)
        others = setremove(others, x);
      endif
    endfor
    return others;
  endmethod

  method suspicious_userid owner: #2
    "suspicious_userid(userid)";
    "Return yes if userid is root or postmaster or something like that.";
    let extra;
    if ($object_utils:has_property(#0, "local") && $object_utils:has_property($local, "suspicious_userids"))
      extra = $local.suspicious_userids;
    else
      extra = {};
    endif
    return args[1] in {@this.suspicious_userids, @extra} || match(args[1], "^guest") || match(args[1], "^help") || index(args[1], "-owner") || index(args[1], "owner-");
  endmethod

  method describe_registration owner: #2
    "Returns a list of strings describing the registration data for an email address.  Args[1] should be the result of :find_exact.";
    set_task_perms(caller_perms());
    let result = {};
    for x in (args[1])
      const name = valid(x[1]) && is_player(x[1]) ? x[1].name | "<recycled>";
      const email = valid(x[1]) && is_player(x[1]) ? $wiz_utils:get_email_address(x[1]) | "<???>";
      result = {@result, tostr("  ", name, " (", x[1], ") current email: ", email, length(x) > 1 ? " [" + x[2] + "]" | "")};
    endfor
    return result;
  endmethod

  method prune owner: #2
    "Prune obsolete registrations by existing map keys; preserve records with administrative reasons.";
    "Wizard callers only. Each address is updated before a possible budget yield.";
    caller_perms().wizard || raise(E_PERM);
    this.prune_task = task_id();
    for address in (this:find_all_keys(""))
      caller_perms().wizard || raise(E_PERM);
      const original = this:find_exact(address);
      if (typeof(original) != TYPE_LIST)
        continue;
      endif
      let retained = {};
      for entry in (original)
        const {who, @reasons} = entry;
        let keep = valid(who) && is_player(who);
        for reason in (reasons)
          if (reason && !(reason in {"zapped due to inactivity", "toaded due to inactivity", "Additional email address"}))
            keep = true;
          endif
        endfor
        keep && (retained = {@retained, entry});
      endfor
      if (!retained)
        this:delete(address);
        this.total_pruned_people = this.total_pruned_people + 1;
      elseif (retained != original)
        this:insert(address, retained);
        this.total_pruned_characters = this.total_pruned_characters + length(original) - length(retained);
      endif
      this.prune_progress = address;
      $command_utils:suspend_if_needed(0);
    endfor
    this.prune_task = false;
    return true;
  endmethod

  method report_prune_progress owner: #2
    "Print the last completed address and pruning totals.";
    caller_perms().wizard || return E_PERM;
    player:tell("Last address: ", this.prune_progress || "none", ". Removed ", this.total_pruned_people, " addresses and ", this.total_pruned_characters, " individual entries.");
    player:tell("Pruning task active: ", $code_utils:task_valid(this.prune_task));
  endmethod

  method prune_reset owner: #2
    "Cancel the current pruning worker and reset its progress. Wizard callers only.";
    caller_perms().wizard || raise(E_PERM);
    if (this.prune_task != task_id() && $code_utils:task_valid(this.prune_task))
      kill_task(this.prune_task);
    endif
    this.prune_task = false;
    this.prune_progress = "";
    this.total_pruned_people = 0;
    this.total_pruned_characters = 0;
  endmethod

  verb search (this for any) owner: #2 flags: "rxd"
    "Search registration records for an authorized registrar or wizard.";
    const who = caller_perms();
    if (who != #-1 && !(who == player || caller == this) || !(who.wizard || who in $local.registrar_pet_core.members))
      raise(E_PERM);
    endif
    let total = 0;
    player:tell("Searching...");
    for k in ($registration_db:find_all_keys(""))
      $command_utils:suspend_if_needed(0);
      const line = k + " " + toliteral($registration_db:find_exact(k));
      if (index(line, iobjstr))
        player:tell(line);
        total = total + 1;
      endif
    endfor
    player:tell("Search over.  ", total, " matches found.");
  endverb
endobject
