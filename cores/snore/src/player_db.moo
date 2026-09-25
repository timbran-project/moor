object PLAYER_DB [
  import_export_id -> "player_db"
]
  name: "Player Database"
  parent: ROOT_CLASS
  owner: HACKER
  readable: true

  property frozen (owner: HACKER, flags: "rc") = 0;
  property names (owner: HACKER, flags: "rc") = [
    "editor_owner" -> #96,
    "everyman" -> NO_ONE,
    "everyone" -> NO_ONE,
    "guest" -> DEFAULT_GUEST,
    "hacker" -> HACKER,
    "housekeeper" -> HOUSEKEEPER,
    "no_one" -> NO_ONE,
    "noone" -> NO_ONE,
    "wizard" -> #2
  ];
  property reserved (owner: HACKER, flags: "r") = {};
  property stupid_names (owner: HACKER, flags: "rc") = {
    "with",
    "using",
    "at",
    "to",
    "in",
    "into",
    "on",
    "onto",
    "upon",
    "out",
    "from",
    "inside",
    "over",
    "through",
    "under",
    "underneath",
    "beneath",
    "behind",
    "beside",
    "for",
    "about",
    "is",
    "as",
    "off",
    "of",
    "me",
    "you",
    "here"
  };

  override aliases (owner: HACKER, flags: "rc") = {"player_db", "plyrdb", "pdb"};
  override description (owner: HACKER, flags: "rc") = {
    "A database containing all player names and aliases.  ",
    "Names match case-insensitively; prefix lookups return a unique match or $ambiguous_match.",
    "See `help $player_db' for more information."
  };
  override object_size (owner: HACKER, flags: "r") = {8069, 1084848672};

  method load owner: HACKER
    ":load() -- reloads the player_db with the names of all existing players.";
    ".frozen is set to 1 while the load is in progress so that other routines are warned and don't try to do any updates.";
    caller != this && !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    this.frozen = 1;
    this:clearall();
    for p in (players())
      if (valid(p) && is_player(p))
        const key = this:_key(p.name);
        !maphaskey(this.names, key) && this:insert(p.name, p);
        for a in (p.aliases)
          if (index(a, " ") || index(a, "\t"))
            "don't bother, space or tab";
          elseif (!maphaskey(this.names, this:_key(a)))
            this:insert(a, p);
          endif
        endfor
      endif
    endfor
    this.frozen = 0;
  endmethod

  verb check (this none none) owner: HACKER flags: "rxd"
    ":check() -- checks for recycled and toaded players that managed not to get expunged from the db.";
    for key in (mapkeys(this.names))
      const who = this.names[key];
      if (!valid(who) || !is_player(who))
        player:tell("<- ", key, " ", who);
      elseif (this:_key(who.name) != key && !(key in { this:_key(a) for a in (who.aliases) }))
        player:tell(".", key, " <- ", who.name, " ", who);
      endif
    endfor
    player:tell("done.");
  endverb

  method init_for_core owner: HACKER
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.reserved = {};
      this:load();
    endif
  endmethod

  method available owner: HACKER
    ":available(name,who) => 1 if a name is available for use, or the object id of whoever is currently using it, or 0 if the name is otherwise forbidden.";
    "If $player_db is not .frozen and :available returns 1, then $player:set_name will succeed.";
    let who;
    const {name, ?target = valid(caller) ? caller | player} = args;
    name in this.stupid_names || name in this.reserved && return 0;
    if (target in $wiz_utils.rename_restricted)
      return 0;
    elseif (!name || index(name, " ") || index(name, "\\") || index(name, "\"") || index(name, "\t"))
      return 0;
    elseif (index("*#()", name[1]))
      return 0;
    elseif ($code_utils:match_objid(name))
      return 0;
    else
      who = this:find_exact(name);
      if (valid(who) && is_player(who))
        return who;
      elseif ($object_utils:has_callable_verb($local, "legal_name") && !$local:legal_name(name, target))
        return 0;
      else
        return 1;
      endif
    endif
  endmethod

  method _key owner: HACKER
    "Normalize a name or alias for case-insensitive lookup.";
    return $string_utils:lowercase(args[1]);
  endmethod

  method find_exact owner: HACKER
    ":find_exact(name) => object or $failed_match.";
    const name = args[1];
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    !maphaskey(this.names, key) && return $failed_match;
    return this.names[key];
  endmethod

  method find owner: HACKER
    ":find(name) => exact match first, otherwise a unique prefix match, $ambiguous_match, or $failed_match.";
    const name = args[1];
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    maphaskey(this.names, key) && return this.names[key];
    const matches = this:find_all(name);
    !matches && return $failed_match;
    length(matches) > 1 && return $ambiguous_match;
    return matches[1];
  endmethod

  method find_all owner: HACKER
    ":find_all(name) => list of distinct objects whose names or aliases begin with name.";
    const name = args[1];
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    let found = {};
    for candidate in (mapkeys(this.names))
      if (index(candidate, key) == 1)
        found = setadd(found, this.names[candidate]);
      endif
    endfor
    return found;
  endmethod

  method insert owner: HACKER
    ":insert(name, object) => {old object} if the name was present, otherwise 0.";
    !($perm_utils:controls(caller_perms(), this) || caller == this) && return E_PERM;
    const {name, who} = args;
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    if (maphaskey(this.names, key))
      const old = this.names[key];
      this.names[key] = who;
      return {old};
    endif
    this.names[key] = who;
    return 0;
  endmethod

  method delete owner: HACKER
    ":delete(name) => {old object} if the name was present, otherwise 0.";
    !($perm_utils:controls(caller_perms(), this) || caller == this) && return E_PERM;
    const name = args[1];
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    !maphaskey(this.names, key) && return 0;
    const old = this.names[key];
    this.names = mapdelete(this.names, key);
    return {old};
  endmethod

  method delete2 owner: HACKER
    ":delete2(name, object) deletes the name only if it maps to object. Returns {previous} or 0.";
    !($perm_utils:controls(caller_perms(), this) || caller == this) && return E_PERM;
    const {name, who} = args;
    typeof(name) == TYPE_STR || return E_INVARG;
    const key = this:_key(name);
    !maphaskey(this.names, key) && return 0;
    const old = this.names[key];
    old != who && return {old};
    this.names = mapdelete(this.names, key);
    return {old};
  endmethod

  method clearall owner: #2
    ":clearall() => clears the name index.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.names = [];
  endmethod

  method why_bad_name owner: #2
    ":why_bad_name(player, namespec) => Returns a message explaining why a player name change is invalid.";
    let i;
    let match;
    const who = args[1];
    const name = $building_utils:parse_names(args[2])[1];
    const si = index(name, " ");
    const qi = index(name, "\"");
    const bi = index(name, "\\");
    const ti = index(name, "\t");
    if (si || qi || bi || ti)
      return tostr("You may not use a name containing ", $string_utils:english_list({@si ? {"spaces"} | {}, @qi ? {"quotation marks"} | {}, @bi ? {"backslashes"} | {}, @ti ? {"tabs"} | {}}, "ERROR", " or "), ".  Try \"", strsub(strsub(strsub(strsub(name, " ", "_"), "\"", "'"), "\\", "/"), "\t", "___"), "\" instead.");
    endif
    name == "" && return tostr("You may not use a blank name.");
    i = index("*#()", name[1]);
    if (i)
      return tostr("You may not begin a name with the \"", "*#()"[i], "\" character.");
    elseif ($code_utils:match_objid(name))
      return tostr("A name can't contain a parenthesized object number.");
    elseif (name in $player_db.stupid_names)
      return tostr("The name \"", name, "\" would probably cause problems in command parsing or similar usage.");
    elseif (name in $player_db.reserved)
      return tostr("The name \"", name, "\" is reserved.");
    elseif (length(name) > $login.max_player_name)
      return tostr("The name \"", name, "\" is too long.  Maximum name length is ", $login.max_player_name, " characters.");
    else
      match = $player_db:find_exact(name);
      if (valid(match) && is_player(match) && who != match)
        return tostr("The name \"", name, "\" is already being used by ", match.name, "(", match, ").");
      elseif ($player_db.frozen)
        return tostr("$player_db is not accepting new changes at the moment.");
      elseif ($object_utils:has_callable_verb($local, "legal_name") && !$local:legal_name(name, who))
        return "That name is reserved.";
      elseif (who in $wiz_utils.rename_restricted)
        return "This player is not allowed to change names.";
      endif
    endif
  endmethod
endobject
