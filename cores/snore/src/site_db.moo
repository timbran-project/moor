object SITE_DB [
  import_export_id -> "site_db"
]
  name: "Site DB"
  parent: ROOT_CLASS
  owner: HACKER

  property domain (owner: HACKER, flags: "r") = "localdomain";
  property prune_progress (owner: HACKER, flags: "c") = "";
  property prune_task (owner: HACKER, flags: "rc") = false;
  property scheduled_prune_task (owner: #2, flags: "r") = false;
  property sites (owner: HACKER, flags: "rc") = ["localhost.localdomain" -> {#2}];
  property total_pruned_people (owner: HACKER, flags: "rc") = 0;
  property total_pruned_sites (owner: HACKER, flags: "rc") = 0;

  override aliases (owner: HACKER, flags: "rc") = {"sitedb", "site", "db"};
  override description (owner: HACKER, flags: "rc") = {
    "This object holds a db of places from which players have connected (see `help $site_db').",
    "The site blacklist and the graylist live as well (see `help blacklist')."
  };
  override object_size (owner: HACKER, flags: "r") = {13167, 1084848672};

  method _key owner: HACKER
    "Normalize a site name for case-insensitive lookup.";
    return $string_utils:lowercase(args[1]);
  endmethod

  method find_exact owner: HACKER
    ":find_exact(site) => list of objects or $failed_match.";
    caller == this || caller_perms().wizard || return E_PERM;
    const key = this:_key(args[1]);
    !maphaskey(this.sites, key) && return $failed_match;
    return this.sites[key];
  endmethod

  method find_all_keys owner: HACKER
    ":find_all_keys(site) => keys whose names begin with site.";
    caller == this || caller_perms().wizard || return E_PERM;
    const key = this:_key(args[1]);
    let found = {};
    for candidate in (mapkeys(this.sites))
      if (index(candidate, key) == 1)
        found = setadd(found, candidate);
      endif
    endfor
    return found;
  endmethod

  method insert owner: HACKER
    ":insert(site, list) => {old list} if the site was present, otherwise 0.";
    caller == this || caller_perms().wizard || return E_PERM;
    const {site, value} = args;
    typeof(site) == TYPE_STR || return E_INVARG;
    const key = this:_key(site);
    if (maphaskey(this.sites, key))
      const old = this.sites[key];
      this.sites[key] = value;
      return {old};
    endif
    this.sites[key] = value;
    return 0;
  endmethod

  method delete owner: HACKER
    ":delete(site) => {old list} if the site was present, otherwise 0.";
    caller == this || caller_perms().wizard || return E_PERM;
    const site = args[1];
    typeof(site) == TYPE_STR || return E_INVARG;
    const key = this:_key(site);
    !maphaskey(this.sites, key) && return 0;
    const old = this.sites[key];
    this.sites = mapdelete(this.sites, key);
    return {old};
  endmethod

  method clearall owner: HACKER
    ":clearall() => clears the site index.";
    caller == this || caller_perms().wizard || return E_PERM;
    this.sites = [];
  endmethod

  method add owner: HACKER
    ":add(player,site)";
    let l;
    !caller_perms().wizard && return E_PERM;
    let {who, domain} = args;
    if (this:domain_literal(domain))
      "... just enter it...";
      l = this:find_exact(domain);
      if (l == $failed_match)
        this:insert(domain, {who});
      elseif (!(who in l))
        this:insert(domain, setadd(l, who));
      endif
    else
      "...an actual domain name; add player to list for that domain...";
      "...then add domain itself to list for the next larger domain; repeat...";
      let dot = index(domain, ".");
      if (!dot)
        dot = length(domain) + 1;
        domain = tostr(domain, ".", this.domain);
      endif
      let prev = who;
      while (true)
        l = this:find_exact(domain);
        if (!($failed_match == l))
          break;
        endif
        this:insert(domain, {prev});
        if (dot)
          prev = domain[1..dot - 1];
          domain = domain[dot + 1..$];
        else
          return;
        endif
        dot = index(domain, ".");
      endwhile
      if (!(prev in l))
        this:insert(domain, {@l, prev});
      endif
      return;
    endif
  endmethod

  method load owner: #2
    ":load([start]) -- reloads site_db with the connection places of all players.";
    "WIZARDLY";
    let i;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const plist = players();
    if (!args)
      this:clearall();
    else
      i = args[1] in plist;
      if (i)
        plist[1..i - 1] = {};
      else
        return E_INVARG;
      endif
    endif
    for p in (plist)
      if (valid(p) && (is_player(p) && !$object_utils:isa(p, $guest)))
        for c in (p.all_connect_places)
          this:add(p, c);
          if ($command_utils:running_out_of_time())
            player:tell("...", p);
            suspend(0);
          endif
        endfor
      endif
    endfor
  endmethod

  method domain_literal owner: HACKER
    ":domain_literal(string)";
    " => true iff string is a domain literal (i.e., numeric IP address).";
    let hnum;
    const len = length(hnum = strsub(args[1], ".", ""));
    10 <= len && return toint(hnum[1..9]) && toint(hnum[6..len]);
    return toint(hnum);
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this:clearall();
      this.domain = "localdomain";
      this:prune_reset();
    endif
  endmethod

  method prune_alpha owner: #2
    "Prune named site keys. Wizard callers only; commit between complete keys.";
    caller_perms().wizard || raise(E_PERM);
    return this:_prune_sites(false, @args);
  endmethod

  method report_prune_progress owner: #2
    "Print the last completed site and pruning totals.";
    caller_perms().wizard || return E_PERM;
    player:tell("Last site: ", this.prune_progress || "none", ". Removed ", this.total_pruned_sites, " sites and ", this.total_pruned_people, " player entries.");
    player:tell("Pruning task active: ", $code_utils:task_valid(this.prune_task));
  endmethod

  method prune_fixup owner: #2
    "Repair a site subtree without an intermediate commit. Wizard callers only.";
    if (!caller_perms().wizard)
      raise(E_PERM);
    endif
    if (!args)
      for x in (this:find_all_keys(""))
        !index(x, ".") && this:prune_fixup(x);
      endfor
      return;
    endif
    const root = args[1];
    let items = this:find_exact(root);
    items == $failed_match && return 1;
    const orig = items;
    $site_db.prune_progress = root;
    $site_db.prune_task = task_id();
    for item in (items)
      if (typeof(item) == TYPE_STR)
        if (this:prune_fixup(item + "." + root))
          items = setremove(items, item);
        endif
      endif
    endfor
    if (!items)
      this:delete(root);
      this.total_pruned_sites = this.total_pruned_sites + 1;
      return 1;
    endif
    if (orig != items)
      this:insert(root, items);
    endif
  endmethod

  method prune_numeric owner: #2
    "Prune numeric site keys. Wizard callers only; commit between complete keys.";
    caller_perms().wizard || raise(E_PERM);
    return this:_prune_sites(true, @args);
  endmethod

  method schedule_prune owner: #2
    "Schedule one daily site-pruning worker at 09:00 UTC. Wizard callers only.";
    caller_perms().wizard || return E_PERM;
    $code_utils:task_valid(this.scheduled_prune_task) && return this.scheduled_prune_task;
    let worker;
    fork worker ((9 * 3600 - time() % 86400 + 86400) % 86400 || 86400)
      while (this.scheduled_prune_task == task_id())
        if (!$code_utils:task_valid(this.prune_task))
          try
            this:prune_alpha();
            this:prune_numeric();
          except error (ANY)
            this.prune_task = false;
            server_log(tostr("Site pruning failed: ", error));
          endtry
        endif
        suspend(86400);
      endwhile
    endfork
    this.scheduled_prune_task = worker;
    return worker;
  endmethod

  method prune_reset owner: #2
    "Cancel active pruning and reset its counters. Wizard callers only.";
    caller_perms().wizard || raise(E_PERM);
    if (this.prune_task != task_id() && $code_utils:task_valid(this.prune_task))
      kill_task(this.prune_task);
    endif
    this.prune_task = false;
    this.prune_progress = "";
    this.total_pruned_sites = 0;
    this.total_pruned_people = 0;
  endmethod

  method _prune_sites owner: #2
    "Prune a snapshot of site names, reading current membership at each complete-key update.";
    caller_perms().wizard || raise(E_PERM);
    const {numeric, ?verbose = false} = args;
    this.prune_task = task_id();
    for name in (this:find_all_keys(""))
      caller_perms().wizard || raise(E_PERM);
      if (!!this:domain_literal(name) != numeric)
        continue;
      endif
      const original = this:find_exact(name);
      if (typeof(original) != TYPE_LIST)
        continue;
      endif
      let retained = {};
      let useful = numeric;
      for item in (original)
        if (typeof(item) != TYPE_OBJ)
          retained = {@retained, item};
          useful = true;
        elseif (valid(item) && is_player(item))
          const recorded = name in item.all_connect_places;
          if (numeric || !index(name, "dialup") || recorded)
            retained = {@retained, item};
          endif
          recorded && (useful = true);
        endif
      endfor
      !useful && (retained = {});
      if (!retained)
        this:delete(name);
        this.total_pruned_sites = this.total_pruned_sites + 1;
      elseif (retained != original)
        this:insert(name, retained);
        this.total_pruned_people = this.total_pruned_people + length(original) - length(retained);
      endif
      this.prune_progress = name;
      verbose && player:tell("Pruned ", name);
      $command_utils:suspend_if_needed(0);
    endfor
    this.prune_task = false;
    return true;
  endmethod
endobject
