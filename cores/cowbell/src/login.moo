object LOGIN
  name: "Login Service"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property blank_command (owner: ARCH_WIZARD, flags: "r") = "welcome";
  property bogus_command (owner: ARCH_WIZARD, flags: "r") = "?";
  property player_creation_enabled (owner: ARCH_WIZARD, flags: "r") = true;
  property registration_string (owner: ARCH_WIZARD, flags: "rc") = "Character creation is disabled.";
  property welcome_message (owner: ARCH_WIZARD, flags: "rc") = {"## Welcome to the _mooR_ *Cowbell* core.", "", "connect with `archwizard` `test` to log in.", "", "You will probably want to change this text which is stored in $login.welcome_message property."};

  verb welcome (any none any) owner: ARCH_WIZARD flags: "rxd"
    "Present the welcome message property to the user.";
    caller != #0 && caller != this && raise(E_PERM);
    { notify(player, line) for line in (this.welcome_message) };
  endverb

  verb "co*nnect @co*nnect" (any none any) owner: ARCH_WIZARD flags: "rxd"
    "$login:connect(player-name [, password])";
    " => 0 (for failed connections)";
    " => objnum (for successful connections)";
    caller == #0 || caller == this || raise(E_PERM);
    "Check arguments, print usage notice if necessary";
    try
      {name, ?password = 0} = args;
      name = strsub(name, " ", "_");
    except (E_ARGS)
      notify(player, tostr("Usage:  ", verb, " <existing-player-name> <password>"));
      return 0;
    endtry
    "Is our candidate name invalid?";
    if (!valid(candidate = orig_candidate = this:_match_player(name)))
      raise(E_INVARG, tostr("`", name, "' matches no player name."));
    endif
    "We have a valid candidate, so we can now attempt to challenge it.";
    "We assume the password is a $password frob and has a :challenge verb available...";
    p_obj = candidate.password;
    if (!p_obj:challenge(password))
      server_log(tostr("FAILED CONNECT: ", name, " (", candidate, ") on ", connection_name(player)));
      raise(E_INVARG, "Invalid password.");
    endif
    "TODO: block lists, guests, etc";
    "Log the player in!";
    return candidate;
  endverb

  verb "cr*eate @cr*eate" (any none any) owner: ARCH_WIZARD flags: "rxd"
    if (caller != #0 && caller != this)
      return E_PERM;
      "... caller isn't :do_login_command()...";
    endif
    if (!this.player_creation_enabled)
      notify(player, this.registration_string);
      return;
    endif
    if (length(args) != 2)
      notify(player, tostr("Usage:  ", verb, " <new-player-name> <new-password>"));
      return;
    endif
    if (!(name = args[1]) || name == "<>")
      notify(player, "You can't have a blank name!");
      if (name)
        notify(player, "Also, don't use angle brackets (<>).");
      endif
      return;
    endif
    if (name[1] == "<" && name[$] == ">")
      notify(player, "Try that again but without the angle brackets, e.g.,");
      notify(player, tostr(" ", verb, " ", name[2..$ - 1], " ", strsub(strsub(args[2], "<", ""), ">", "")));
      notify(player, "This goes for other commands as well.");
      return;
    endif
    if (index(name, " "))
      notify(player, "Sorry, no spaces are allowed in player names.  Use dashes or underscores.");
      "... lots of routines depend on there not being spaces in player names...";
      return;
    endif
    if (this:_match_player(name) != $failed_match)
      notify(player, "Sorry, that name is not available.  Please choose another.");
      "... note the :_match_player call is not strictly necessary...";
      "... it is merely there to handle the case that $player_db gets corrupted.";
      return;
    endif
    if (!(password = args[2]))
      notify(player, "You must set a password for your player.");
      return;
    endif
    new = create($prog, $nothing);
    set_player_flag(new, 1);
    new.name = name;
    new.aliases = {name};
    new.programmer = 1;
    new.password = $password:mk(password);
    `move(new, $first_room) ! ANY';
    return new;
  endverb

  verb _match_player (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":_match_player(name)";
    "This is the matching routine used by @connect.";
    "returns either a valid player corresponding to name or $failed_match.";
    name = args[1];
    if (valid(candidate = name:literal_object()) && is_player(candidate))
      return candidate;
    endif
    "Simple brute force player name scan without considering aliases. Other cores have a $player_db, we might do the same when we grow up.";
    for candidate in (players())
      if (candidate.name == name)
        return candidate;
      endif
    endfor
    return $failed_match;
  endverb

  verb parse_command (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":parse_command(@args) => {verb, args}";
    "Given the args from #0:do_login_command,";
    "  returns the actual $login verb to call and the args to use.";
    "Commands available to not-logged-in users should be located on this object and given the verb_args \"any none any\"";
    caller != #0 && caller != this && return E_PERM;
    !args && return {this.blank_command, @args};
    if ((verb = args[1]) && !verb:is_numeric())
      for i in ({this, @this:ancestors()})
        try
          if (verb_args(i, verb) == {"any", "none", "any"} && index(verb_info(i, verb)[2], "x"))
            return args;
          endif
        except (ANY)
          continue i;
        endtry
      endfor
    endif
    return {this.bogus_command, @args};
  endverb
endobject
