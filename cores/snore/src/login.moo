object LOGIN [
  import_export_id -> "login"
]
  name: "Login Commands"
  parent: ROOT_CLASS
  owner: #2
  readable: true

  property blacklist (owner: #2, flags: "") = {{}, {}};
  property blank_command (owner: #2, flags: "r") = "welcome";
  property bogus_command (owner: #2, flags: "r") = "?";
  property boot_process (owner: #2, flags: "rc") = 0;
  property checkpoint_in_progress (owner: #2, flags: "rc") = false;
  property connection_limit_msg (owner: HACKER, flags: "r") = "*** The MOO is too busy! The current lag is %l; there are %n connected.  WAIT FIVE MINUTES BEFORE TRYING AGAIN.";
  property create_enabled (owner: #2, flags: "rc") = true;
  property current_connections (owner: #2, flags: "rc") = {#-2};
  property current_lag (owner: #2, flags: "r") = 0;
  property current_numcommands (owner: #2, flags: "rc") = {1};
  property downtimes (owner: #2, flags: "rc") = {{1529543472, 0}, {1529444307, 0}};
  property goaway_message (owner: #2, flags: "rc") = {"Snore Core is not accepting connections right now. Please try again later."};
  property graylist (owner: #2, flags: "") = {{}, {}};
  property help_message (owner: #2, flags: "rc") = "# Getting started with Snore Core\n\n- `connect <name> <password>` - Sign in to an existing account\n- `create <name> <password>` - Create an account, if registration is open\n- `connect Guest` - Visit as a guest\n- `who` - See who is connected\n- `quit` - Disconnect\n\nOnce connected, type `help` for topics or `help introduction` for a short introduction.";
  property help_message_content_type (owner: #2, flags: "rc") = "text/djot";
  property ignored (owner: #2, flags: "rc") = {};
  property intercepted_actions (owner: HACKER, flags: "") = {};
  property intercepted_players (owner: HACKER, flags: "") = {};
  property lag_cutoff (owner: #2, flags: "rc") = 5;
  property lag_exemptions (owner: #2, flags: "rc") = {};
  property lag_sample_interval (owner: #2, flags: "rc") = 15;
  property lag_samples (owner: #2, flags: "rc") = {0, 0, 0, 0, 0};
  property last_lag_sample (owner: #2, flags: "rc") = 0;
  property max_connections (owner: HACKER, flags: "rc") = 99999;
  property max_numcommands (owner: #2, flags: "rc") = 20;
  property max_player_name (owner: #2, flags: "rc") = 40;
  property newt_registration_string (owner: #2, flags: "rc") = "Your character is temporarily hosed.";
  property newted (owner: #2, flags: "") = {};
  property oauth2_identity_version (owner: #2, flags: "") = 0;
  property print_lag (owner: #2, flags: "rc") = false;
  property redlist (owner: #2, flags: "") = {{}, {}};
  property registration_address (owner: #2, flags: "rc") = "";
  property registration_string (owner: #2, flags: "rc") = "Character creation is disabled.";
  property request_enabled (owner: #2, flags: "rc") = false;
  property spooflist (owner: #2, flags: "") = {{}, {}};
  property temporary_blacklist (owner: #2, flags: "") = {{}, {}};
  property temporary_graylist (owner: #2, flags: "") = {{}, {}};
  property temporary_newts (owner: #2, flags: "c") = {};
  property temporary_redlist (owner: #2, flags: "") = {{}, {}};
  property temporary_spooflist (owner: #2, flags: "") = {{}, {}};
  property welcome_message (owner: #2, flags: "rc") = "# Welcome to Snore Core\n\n*just boring enough*\n\nA LambdaCore fork for mooR, with familiar MOO commands and live programming.\n\nSign in with `connect <name> <password>`, create an account with `create <name> <password>`, or visit with `connect Guest`.\n\nType `help` for connection help. Once connected, type `help introduction` to get started.\n\nAdministrators can customize `$login.welcome_message` and `$login.help_message`.";
  property welcome_message_content_type (owner: #2, flags: "rc") = "text/djot";
  property who_masks_wizards (owner: #2, flags: "") = false;

  override aliases (owner: #2, flags: "rc") = {"Login Commands"};
  override description (owner: #2, flags: "rc") = "This provides everything needed by #0:do_login_command.  See `help $login' on $core_help for details.";
  override object_size (owner: HACKER, flags: "r") = {42064, 1084848672};

  verb "?" (any none any) owner: #2 flags: "rxd"
    "List executable login commands when the system login parser cannot match input.";
    caller == $sysobj || caller == this || return E_PERM;
    let commands = {};
    for object in ({this, @$object_utils:ancestors(this)})
      for position in [1..length(verbs(object))]
        const info = verb_info(object, position);
        if (verb_args(object, position) == {"any", "none", "any"} && index(info[2], "x"))
          const name = $string_utils:explode(info[3])[1];
          if (name in {"oauth2_check", "oauth2_create", "oauth2_connect"})
            continue;
          endif
          const star = index(name + "*", "*");
          commands = {@commands, $string_utils:uppercase(name[1..star - 1]) + strsub(name[star..$], "*", "")};
        endif
      endfor
    endfor
    notify(player, "I don't understand that. Valid commands at this point are");
    notify(player, "   " + $string_utils:english_list(setremove(commands, "?"), "", " or "));
    return 0;
  endverb

  verb "wel*come @wel*come" (any none any) owner: #2 flags: "rxd"
    "Show the welcome text and current connection notices to the login connection.";
    caller == $sysobj || caller == this || return E_PERM;
    const message = this.welcome_message;
    for line in (typeof(message) == TYPE_STR ? {message} | message)
      typeof(line) == TYPE_STR && notify(player, strsub(line, "%v", server_version()));
    endfor
    this:check_player_db();
    this:check_for_shutdown();
    this:check_for_checkpoint();
    this:maybe_print_lag();
    return 0;
  endverb

  verb "w*ho @w*ho" (any none any) owner: #2 flags: "rxd"
    "List connected players, retaining wizard masking and the 100-player query limit.";
    caller == $sysobj || caller == this || return E_PERM;
    const masked = this.who_masks_wizards ? $wiz_utils:connected_wizards() | {};
    const players = args ? $command_utils:player_match_result($string_utils:match_player(args), args)[2..$] | connected_players();
    if (length(players) > 100)
      this:notify("Please restrict this request to at most 100 players.");
      return 0;
    endif
    if (args)
      $code_utils:show_who_listing(players, $set_utils:intersection(players, masked));
    else
      $code_utils:show_who_listing($set_utils:difference(players, masked)) || this:notify("No one logged in.");
    endif
    return 0;
  endverb

  verb "co*nnect @co*nnect" (any none any) owner: #2 flags: "rxd"
    "Authenticate a password or guest login; return the player on success, or 0 on rejection.";
    "Password prompting installs a one-command interception. Automatic unnewting forks an audit message.";
    let name;
    let password;
    caller == #0 || caller == this || raise(E_PERM);
    try
      {name, ?password = 0} = args;
      name = strsub(name, " ", "_");
    except (E_ARGS)
      notify(player, tostr("Usage:  ", verb, " <existing-player-name> <password>"));
      return 0;
    endtry
    try
      let candidate = this:_match_player(name);
      const orig_candidate = candidate;
      valid(candidate) || raise(E_INVARG, tostr("`", name, "' matches no player name."));
      const connection = connection_name(player);
      const host = $string_utils:connection_hostname(connection);
      const denied = tostr("FAILED CONNECT: ", name, " (", candidate, ") on ", connection, host in candidate.all_connect_places ? "" | "******");
      if (`is_clear_property(candidate, "password") ! E_PROPNF' || !$object_utils:isa(candidate, $player))
        server_log(denied);
        raise(E_INVARG);
      endif
      const stored = candidate.password;
      if (typeof(stored) == TYPE_STR)
        if (!password)
          set_connection_option(player, "client-echo", false);
          notify(player, "Password: ", false, true);
          this:add_interception(player, "intercepted_password", candidate);
          return 0;
        endif
        if (!argon2_verify(stored, password))
          server_log(denied);
          raise(E_INVARG, "Invalid password.");
        endif
      elseif (stored != 0 || `candidate.oauth2_identities ! E_PROPNF => {}')
        raise(E_INVARG);
      endif
      if ($no_connect_message && !candidate.wizard)
        notify(player, $no_connect_message);
        server_log(tostr("REJECTED CONNECT: ", name, " (", candidate, ") on ", connection));
        return 0;
      endif
      if ($object_utils:isa(candidate, $guest))
        candidate = candidate:defer();
        if (!valid(candidate))
          if (candidate == $ambiguous_match)
            server_log(tostr("GUEST DENIED: ", connection));
            notify(player, "Sorry, guest characters are not allowed from your site at the current time.");
          else
            notify(player, "Sorry, all of our guest characters are in use right now.");
          endif
          return 0;
        endif
      endif
      if (candidate in this.newted)
        const entry = $list_utils:assoc(candidate, this.temporary_newts);
        if (!entry)
          notify(player, "");
          notify(player, this:newt_registration_string());
          boot_player(player);
          return 0;
        endif
        const uptime = this:uptime_since(entry[2]);
        if (uptime <= entry[3])
          notify(player, "");
          notify(player, this:temp_newt_registration_string(entry[3] - uptime));
          boot_player(player);
          return 0;
        endif
        this.temporary_newts = setremove(this.temporary_newts, entry);
        this.newted = setremove(this.newted, candidate);
        fork (0)
          player = this.owner;
          $mail_agent:send_message(player, $newt_log, tostr("automatic @unnewt ", candidate.name, " (", candidate, ")"), {"message sent from $login:connect"});
        endfork
        "The fork commits; repeat authentication and admission against current state.";
        return this:connect(name, password);
      endif
      const howmany = length(connected_players());
      const max = this:max_connections();
      if (!candidate.wizard && !(candidate in this.lag_exemptions) && howmany >= max && !$object_utils:connected(candidate))
        notify(player, $string_utils:subst(this.connection_limit_msg, {{"%n", tostr(howmany)}, {"%m", tostr(max)}, {"%l", tostr(this:current_lag())}, {"%t", candidate.last_connect_attempt ? ctime(candidate.last_connect_attempt) | "not recorded"}}));
        if ($object_utils:has_property($local, "mudlist"))
          notify(player, "You may wish to try another MUD while waiting for the MOO to unlag.  Here are a few that we know of:");
          for l in ($local.mudlist:choose(3))
            notify(player, l);
          endfor
        endif
        candidate.last_connect_attempt = time();
        server_log(tostr("CONNECTION LIMIT EXCEEDED: ", name, " (", candidate, ") on ", connection));
        boot_player(player);
        return 0;
      endif
      if (candidate != orig_candidate)
        notify(player, tostr("Okay,... ", name, " is in use.  Logging you in as `", candidate.name, "'"));
      endif
      this:record_connection(candidate);
      return candidate;
    except (E_INVARG)
      notify(player, "Either that player does not exist, or has a different password.");
      return 0;
    endtry
  endverb

  verb "cr*eate @cr*eate" (any none any) owner: #2 flags: "rxd"
    "Create a UUID player when registration is enabled; return the player or 0.";
    caller == $sysobj || caller == this || return E_PERM;
    if (!this:player_creation_enabled(player))
      notify(player, this:registration_string());
      return 0;
    endif
    if (length(args) != 2)
      notify(player, tostr("Usage:  ", verb, " <new-player-name> <new-password>"));
      return 0;
    endif
    if ($player_db.frozen)
      notify(player, "Sorry, can't create any new players right now. Try again in a few minutes.");
      return 0;
    endif
    const {name, password} = args;
    if (!name || name == "<>")
      notify(player, "You can't have a blank name!");
      return 0;
    endif
    if (name[1] == "<" && name[$] == ">")
      notify(player, tostr("Use create ", name[2..$ - 1], " <password>, without angle brackets."));
      return 0;
    endif
    if (index(name, " "))
      notify(player, "Sorry, no spaces are allowed in player names. Use dashes or underscores.");
      return 0;
    endif
    if (!$player_db:available(name) || this:_match_player(name) != $failed_match)
      notify(player, "Sorry, that name is not available. Please choose another.");
      return 0;
    endif
    if (!password)
      notify(player, "You must set a password for your player.");
      return 0;
    endif
    const account = $quota_utils:bi_create($player_class, $nothing);
    set_player_flag(account, 1);
    account.name = name;
    account.aliases = {name};
    account.programmer = $player_class.programmer;
    account.password = argon2(password, salt());
    account.last_password_time = time();
    account.last_connect_time = $maxint;
    account.last_disconnect_time = time();
    $quota_utils:initialize_quota(account);
    this:record_connection(account);
    $player_db:insert(name, account);
    `move(account, $player_start) ! ANY';
    return account;
  endverb

  verb "q*uit @q*uit" (any none any) owner: #2 flags: "rxd"
    "Disconnect this login connection.";
    caller == $sysobj || caller == this || return E_PERM;
    boot_player(player);
    return 0;
  endverb

  verb oauth2_check (any none any) owner: #2 flags: "rxd"
    "$login:oauth2_check(provider, external_id)";
    " => 0 (for not found)";
    " => objnum (for existing OAuth2 identity)";
    let provider;
    let external_id;
    caller == #0 && callers()[1][2] == "do_oauth_login" || raise(E_PERM);
    try
      {provider, external_id} = args;
    except (E_ARGS)
      notify(player, "OAuth2 check failed: invalid arguments");
      return 0;
    endtry
    const candidate = this:find_by_oauth2(provider, external_id);
    if (valid(candidate) && this:_oauth_admitted(candidate))
      server_log(tostr("OAUTH2 CHECK SUCCESS: ", provider, ":", external_id, " -> ", candidate));
      this:record_connection(candidate);
      return candidate;
    else
      server_log(tostr("OAUTH2 CHECK NOT FOUND: ", provider, ":", external_id));
      return 0;
    endif
  endverb

  verb oauth2_create (any none any) owner: #2 flags: "rxd"
    "$login:oauth2_create(provider, external_id, email, name, username, player_name)";
    " => 0 (for failed creation)";
    " => objnum (for successful creation)";
    let provider;
    let external_id;
    let email;
    let name;
    let username;
    let player_name;
    caller == #0 && callers()[1][2] == "do_oauth_login" || raise(E_PERM);
    if ($no_connect_message)
      notify(player, $no_connect_message);
      return 0;
    endif
    if (!this:player_creation_enabled(player))
      notify(player, this:registration_string());
      return 0;
    endif
    try
      {provider, external_id, email, name, username, player_name} = args;
    except (E_ARGS)
      notify(player, "OAuth2 create failed: invalid arguments");
      return 0;
    endtry
    if ($player_db.frozen)
      notify(player, "Sorry, can't create any new players right now.  Try again in a few minutes.");
      return 0;
    endif
    if (!player_name || player_name == "<>")
      notify(player, "You can't have a blank name!");
      return 0;
    elseif (player_name[1] == "<" && player_name[$] == ">")
      notify(player, "Don't use angle brackets in your player name.");
      return 0;
    elseif (index(player_name, " "))
      notify(player, "Sorry, no spaces are allowed in player names.  Use dashes or underscores.");
      return 0;
    elseif (!$player_db:available(player_name) || this:_match_player(player_name) != $failed_match)
      notify(player, "Sorry, that name is not available.  Please choose another.");
      return 0;
    endif
    valid(this:find_by_oauth2(provider, external_id)) && return 0;
    let new = $quota_utils:bi_create($player_class, $nothing);
    set_player_flag(new, 1);
    new.name = player_name;
    new.aliases = {player_name};
    new.programmer = $player_class.programmer;
    new.password = 0;
    new.email_address = email;
    this:_claim_oauth_identity(new, provider, external_id);
    new.last_connect_time = $maxint;
    new.last_disconnect_time = time();
    $quota_utils:initialize_quota(new);
    this:record_connection(new);
    $player_db:insert(player_name, new);
    `move(new, $player_start) ! ANY';
    server_log(tostr("OAUTH2 CREATE: ", player_name, " (", new, ") via ", provider, ":", external_id));
    return new;
  endverb

  verb oauth2_connect (any none any) owner: #2 flags: "rxd"
    "$login:oauth2_connect(provider, external_id, email, name, username, existing_name, existing_password)";
    " => 0 (for failed connection)";
    " => objnum (for successful link)";
    let provider;
    let external_id;
    let email;
    let name;
    let username;
    let existing_name;
    let existing_password;
    caller == #0 && callers()[1][2] == "do_oauth_login" || raise(E_PERM);
    try
      {provider, external_id, email, name, username, existing_name, existing_password} = args;
      server_log(tostr("OAUTH2 CONNECT ATTEMPT: provider=", provider, " external_id=", external_id, " existing_name=", existing_name, " args_count=", length(args)));
    except (E_ARGS)
      server_log(tostr("OAUTH2 CONNECT E_ARGS: received ", length(args), " args, expected 7"));
      notify(player, "OAuth2 connect failed: invalid arguments");
      return 0;
    endtry
    let candidate = this:_match_player(existing_name);
    if (!valid(candidate))
      server_log(tostr("OAUTH2 CONNECT FAILED: player not found: ", existing_name));
      notify(player, "That player does not exist.");
      return 0;
    endif
    server_log(tostr("OAUTH2 CONNECT: found candidate ", candidate, " password_type=", typeof(candidate.password)));
    const cp = candidate.password;
    if (typeof(cp) == TYPE_STR)
      "=== Candidate has a password, verify it";
      if (!argon2_verify(cp, existing_password))
        server_log(tostr("OAUTH2 CONNECT FAILED PASSWORD: ", existing_name, " (", candidate, ")"));
        notify(player, "Invalid password for existing account.");
        return 0;
      endif
      server_log(tostr("OAUTH2 CONNECT: password verified for ", existing_name));
    elseif (cp == 0)
      notify(player, "Set an account password before linking another login identity.");
      return 0;
    else
      "=== Candidate has nonstandard password";
      server_log(tostr("OAUTH2 CONNECT FAILED: nonstandard password type for ", existing_name, " (", candidate, ")"));
      notify(player, "Cannot link to that account.");
      return 0;
    endif
    this:_oauth_admitted(candidate) || return 0;
    this:_claim_oauth_identity(candidate, provider, external_id);
    "=== Set email address if one was provided and the candidate doesn't have one";
    if (email && (!$object_utils:has_property(candidate, "email_address") || !candidate.email_address))
      candidate.email_address = email;
      server_log(tostr("OAUTH2 CONNECT: set email address for ", existing_name, " to ", email));
    endif
    this:record_connection(candidate);
    server_log(tostr("OAUTH2 CONNECT: ", existing_name, " (", candidate, ") linked ", provider, ":", external_id));
    return candidate;
  endverb

  verb "up*time @up*time" (any none any) owner: #2 flags: "rxd"
    "Report elapsed time since the last server restart.";
    caller == $sysobj || caller == this || return E_PERM;
    notify(player, tostr("The server has been up for ", $time_utils:english_time(time() - $last_restart_time), "."));
    return 0;
  endverb

  verb "v*ersion @v*ersion" (any none any) owner: #2 flags: "rxd"
    "Report the core and runtime versions at the login prompt.";
    caller == $sysobj || caller == this || return E_PERM;
    notify(player, tostr("Snore Core uses mooR server version ", server_version(), "."));
    return 0;
  endverb

  method parse_command owner: #2
    "Return {verb, @arguments} for an executable login command or a pending password interception.";
    caller == $sysobj || caller == this || return E_PERM;
    const intercepted = this:interception(player);
    intercepted && return {@intercepted, @args};
    !args && return {this.blank_command};
    args[1] in {"oauth2_check", "oauth2_create", "oauth2_connect", "do_oauth_login"} && return {this.bogus_command, @args};
    const name = args[1];
    if (name && !$string_utils:is_numeric(name))
      for object in ({this, @$object_utils:ancestors(this)})
        const arguments = `verb_args(object, name) ! E_VERBNF, E_INVARG => {}';
        if (arguments == {"any", "none", "any"} && index(verb_info(object, name)[2], "x"))
          return args;
        endif
      endfor
    endif
    return {this.bogus_command, @args};
  endmethod

  method check_for_shutdown owner: #2
    "Print a pending shutdown notice without imposing server-side word wrapping.";
    const remaining = $shutdown_time - time();
    remaining < 0 && return 0;
    notify(player, tostr("WARNING: The server will shut down in ", $time_utils:english_time(remaining - remaining % 60), "."));
    const message = $shutdown_message;
    for line in (typeof(message) == TYPE_STR ? {message} | message)
      notify(player, line);
    endfor
  endmethod

  method check_player_db owner: #2
    "Explain a frozen name index; object identifiers still work for login.";
    $player_db.frozen || return 0;
    notify(player, "The player-name index is being reloaded. Please wait, or connect using your object identifier and password.");
    this:player_creation_enabled(player) && notify(player, "Character creation is unavailable during the reload.");
  endmethod

  method _match_player owner: #2
    "Return an exact player name or literal object identifier, or $failed_match.";
    const {name} = args;
    const literal = $string_utils:literal_object(name);
    valid(literal) && is_player(literal) && return literal;
    const candidate = $player_db:find_exact(name);
    return valid(candidate) && is_player(candidate) ? candidate | $failed_match;
  endmethod

  method find_by_oauth2 owner: #2
    ":find_by_oauth2(provider, external_id) => player or $failed_match";
    "Search all players for a matching oauth2_identities entry.";
    caller_perms().wizard || return E_PERM;
    const {provider, external_id} = args;
    let found = $failed_match;
    for candidate in (players())
      if (!$object_utils:has_property(candidate, "oauth2_identities"))
        continue;
      endif
      for identity in (candidate.oauth2_identities)
        if (typeof(identity) == TYPE_LIST && length(identity) == 2 && strcmp(identity[1], provider) == 0 && strcmp(identity[2], external_id) == 0)
          valid(found) && found != candidate && raise(E_INVARG, "OAuth identity is linked to multiple accounts.");
          found = candidate;
        endif
      endfor
    endfor
    return found;
  endmethod

  method "notify tell_current" owner: #2
    "Deliver login output using caller permissions; tell_current targets only the initiating connection.";
    const target = verb == "tell_current" ? connection() | player;
    const text = verb == "tell_current" ? tostr(@args) | args[1];
    set_task_perms(caller_perms());
    `notify(target, text) ! ANY';
  endmethod

  method tell owner: HACKER
    "Ignore room speech addressed to the login command object.";
    return 0;
  endmethod

  method player_creation_enabled owner: #2
    "Return whether creation is enabled for this connection's host; wizard-only.";
    caller_perms().wizard || return E_PERM;
    return !!this.create_enabled && !this:blacklisted($string_utils:connection_hostname(connection_name(args[1])));
  endmethod

  method "newt_registration_string registration_string" owner: #2
    "Substitute the configured registration address and literal percent signs.";
    return $string_utils:subst(this.(verb), {{"%e", this.registration_address}, {"%%", "%"}});
  endmethod

  method init_for_core owner: #2
    "Reset login configuration during wizard-controlled core extraction.";
    caller_perms().wizard || return E_PERM;
    this.current_lag = 0;
    this.lag_exemptions = {};
    this.max_connections = 99999;
    this.lag_samples = {0, 0, 0, 0, 0};
    this.print_lag = false;
    this.last_lag_sample = 0;
    this.bogus_command = "?";
    this.blank_command = "welcome";
    this.create_enabled = true;
    this.registration_address = "";
    this.registration_string = "Character creation is disabled.";
    this.newt_registration_string = "Your character is temporarily hosed.";
    this.welcome_message = "# Welcome to Snore Core\n\n*just boring enough*\n\nA LambdaCore fork for mooR, with familiar MOO commands and live programming.\n\nSign in with `connect <name> <password>`, create an account with `create <name> <password>`, or visit with `connect Guest`.\n\nType `help` for connection help. Once connected, type `help introduction` to get started.\n\nAdministrators can customize `$login.welcome_message` and `$login.help_message`.";
    this.welcome_message_content_type = "text/djot";
    this.help_message = "# Getting started with Snore Core\n\n- `connect <name> <password>` - Sign in to an existing account\n- `create <name> <password>` - Create an account, if registration is open\n- `connect Guest` - Visit as a guest\n- `who` - See who is connected\n- `quit` - Disconnect\n\nOnce connected, type `help` for topics or `help introduction` for a short introduction.";
    this.help_message_content_type = "text/djot";
    for name in ({"redlist", "blacklist", "graylist", "spooflist"})
      this.(name) = {{}, {}};
      this.("temporary_" + name) = {{}, {}};
    endfor
    this.who_masks_wizards = false;
    this.newted = {};
    this.temporary_newts = {};
    this.downtimes = {};
    if ("monitor" in properties(this))
      delete_property(this, "monitor");
    endif
    if ("monitor" in verbs(this))
      delete_verb(this, "monitor");
    endif
    if ("special_action" in verbs(this))
      set_verb_code(this, "special_action", {});
    endif
    pass(@args);
  endmethod

  method special_action owner: #2 flags: "xd"
    "Extension hook for site-specific login behavior.";
    return 0;
  endmethod

  method "blacklisted graylisted redlisted spooflisted" owner: #2
    "Return whether any matching site restriction is active; wizard-only.";
    caller_perms().wizard || return E_PERM;
    const {hostname} = args;
    const name = this:listname(verb);
    const lists = this.(name);
    for kind in [1..2]
      for entry in (lists[kind])
        const pattern = entry;
        if (this:_site_matches(hostname, pattern, kind))
          return true;
        endif
      endfor
    endfor
    return this:(verb + "_temp")(hostname);
  endmethod

  method "blacklist_add*_temp graylist_add*_temp redlist_add*_temp spooflist_add*_temp" owner: #2
    "Add a permanent host entry or a temporary {host, start, duration} entry; wizard-only.";
    caller_perms().wizard || return E_PERM;
    const {host, ?start = 0, ?duration = 0} = args;
    const temporary = index(verb, "temp") > 0;
    const name = (temporary ? "temporary_" | "") + this:listname(verb);
    const kind = $site_db:domain_literal(host) ? 1 | 2;
    this.(name)[kind] = setadd(this.(name)[kind], temporary ? {host, start, duration} | host);
    return true;
  endmethod

  method "blacklist_remove*_temp graylist_remove*_temp redlist_remove*_temp spooflist_remove*_temp" owner: #2
    "Remove a matching host entry; return true, or E_INVARG if absent. Wizard-only.";
    caller_perms().wizard || return E_PERM;
    const {host} = args;
    const temporary = index(verb, "temp") > 0;
    const name = (temporary ? "temporary_" | "") + this:listname(verb);
    const kind = $site_db:domain_literal(host) ? 1 | 2;
    if (temporary)
      const entry = $list_utils:assoc(host, this.(name)[kind]);
      !entry && return E_INVARG;
      this.(name)[kind] = setremove(this.(name)[kind], entry);
    else
      !(host in this.(name)[kind]) && return E_INVARG;
      this.(name)[kind] = setremove(this.(name)[kind], host);
    endif
    return true;
  endmethod

  method listname owner: #2
    "Map the first letter of a color-list operation to its property name; unknown operations give ???.";
    const {operation} = args;
    const position = operation ? index("bgrs", operation[1]) | 0;
    return {"???", "blacklist", "graylist", "redlist", "spooflist"}[position + 1];
  endmethod

  method "who(vanilla)" owner: #2
    "Unmasked connection listing for the system login hook.";
    caller == $sysobj || return E_PERM;
    if (!args)
      $code_utils:show_who_listing(connected_players()) || this:notify("No one logged in.");
    else
      const players = $command_utils:player_match_result($string_utils:match_player(args), args)[2..$];
      $code_utils:show_who_listing(players);
    endif
    return 0;
  endmethod

  method record_connection owner: #2
    "Update a player's connection history and host index immediately before login; wizard-only.";
    caller_perms().wizard || return E_PERM;
    const {who} = args;
    const now = time();
    who.first_connect_time = min(now, who.first_connect_time);
    who.previous_connection = {who.last_connect_time, $string_utils:connection_hostname(who.last_connect_place)};
    who.last_connect_time = now;
    const connection = connection_name(player);
    who.last_connect_place = connection;
    const host = $string_utils:connection_hostname(connection);
    const places = setremove(who.all_connect_places, host);
    who.all_connect_places = {host, @places[1..min($, 15)]};
    $object_utils:isa(who, $guest) || $site_db:add(who, host);
  endmethod

  method sample_lag owner: #2
    "Sample scheduler delay and schedule the next sample; wizard-only.";
    "The fork commits. Write the complete sample and timestamp before scheduling it.";
    caller_perms().wizard || return E_PERM;
    const interval = max(1, this.lag_sample_interval);
    const now = time();
    const delay = max(0, now - this.last_lag_sample - interval);
    this.lag_samples = {delay, @this.lag_samples[1..min($, 3)]};
    const samples = this.lag_samples;
    this.current_lag = delay > 3600 ? 0 | max(delay, samples[1], samples[2], $math_utils:mean(samples[2..$]));
    this.last_lag_sample = now;
    fork (interval)
      this:sample_lag();
    endfork
  endmethod

  method is_lagging owner: #2
    "Return whether the cached lag exceeds the configured cutoff.";
    return this:current_lag() > this.lag_cutoff;
  endmethod

  method max_connections owner: #2
    "Return a fixed limit or the lag-dependent element of {lagging, normal}.";
    const limit = this.max_connections;
    return typeof(limit) == TYPE_LIST ? limit[this:is_lagging() ? 1 | 2] | limit;
  endmethod

  method request_character owner: #2
    "Submit a character request after interactive confirmation; reads and mail delivery may commit.";
    "Recheck name, address, host, and caller authority after confirmation.";
    !caller_perms().wizard && return E_PERM;
    const {who, name, address} = args;
    const connection = $string_utils:connection_hostname(connection_name(who));
    let reason = $wiz_utils:check_player_request(name, address, connection);
    if (reason)
      let prefix = "";
      if (reason[1] == "-")
        reason = reason[2..$];
        prefix = "Please";
      else
        prefix = "Please try again, or, to register another way,";
      endif
      notify(who, reason);
      const msg = tostr(prefix, " send mail to ", $login.registration_address, ", with the character name you want.");
      notify(who, msg);
      return false;
    endif
    let lines = $no_one:eval_d("$local.help.(\"multiple-characters\")")[2];
    if (lines)
      notify(who, "Remember, in general, only one character per person is allowed.");
      notify(who, tostr("Do you already have a ", $mail_agent.moo_name, " character? [enter `yes' or `no']"));
      const answer = read(who);
      if (answer == "yes")
        notify(who, "Process terminated *without* creating a character.");
        return false;
      endif
      if (answer != "no")
        return notify(who, tostr("Please try again; when you get this question, answer `yes' or `no'. You answered `", answer, "'"));
      endif
      notify(who, "For future reference, do you want to see the full policy (from `help multiple-characters'?");
      notify(who, "[enter `yes' or `no']");
      if (read(who) == "yes")
        for line in (typeof(lines) == TYPE_STR ? {lines} | lines)
          notify(who, line);
        endfor
      endif
    endif
    notify(who, tostr("A request for a character named `", name, "' will be sent"));
    notify(who, tostr("to the registrar (", $login.registration_address, ")."));
    notify(who, "Is this OK? [enter `yes' or `no']");
    if (read(who) != "yes")
      notify(who, "Process terminated *without* creating a character.");
      return false;
    endif
    caller_perms().wizard || return E_PERM;
    const current_host = $string_utils:connection_hostname(connection_name(who));
    const current_reason = $wiz_utils:check_player_request(name, address, current_host);
    if (current_reason)
      notify(who, current_reason);
      return false;
    endif
    $mail_agent:send_message(this.owner, $registration_db.registrar, "Player request", {"Player request from " + current_host, ":", "", "@make-player " + name + " " + address});
    notify(who, tostr("Request for new character ", name, " email address '", address, "' accepted."));
    notify(who, tostr("Please be patient until the registrar gets around to it."));
    return true;
  endmethod

  verb "req*uest @req*uest" (any none any) owner: #2 flags: "rxd"
    "Accept a registration request when enabled; confirmation reads commit.";
    caller == $sysobj || caller == this || return E_PERM;
    if (!this.request_enabled)
      notify(player, this:registration_string());
    elseif (length(args) != 3 || args[2] != "for")
      notify(player, tostr("Usage:  ", verb, " <new-player-name> for <email-address>"));
    elseif (this:request_character(player, args[1], args[3]))
      boot_player(player);
    endif
  endverb

  verb "h*elp @h*elp" (any none any) owner: #2 flags: "rxd"
    "Show configured login help as text or a list of lines.";
    caller == $sysobj || caller == this || return E_PERM;
    const message = this.help_message;
    for line in (typeof(message) == TYPE_STR ? {message} | message)
      typeof(line) == TYPE_STR && notify(player, line);
    endfor
    return 0;
  endverb

  method maybe_print_lag owner: #2
    "Show cached lag when configured and requested by login or the connecting player.";
    caller == this || caller_perms() == player || return E_PERM;
    this.print_lag || return 0;
    const lag = this:current_lag();
    const description = lag > 0 ? tostr("approximately ", lag, lag == 1 ? " second" | " seconds") | "low";
    const count = length(connected_players());
    notify(player, tostr("The lag is ", description, "; there ", count == 1 ? "is " | "are ", count, " connected."));
  endmethod

  method current_lag owner: #2
    "Return the cached scheduler delay estimate.";
    return this.current_lag;
  endmethod

  method maybe_limit_commands owner: #2
    "Count commands per login connection; discard disconnected entries and boot over-budget clients.";
    caller_perms().wizard || return E_PERM;
    const position = player in this.current_connections;
    let count = 1;
    if (position)
      count = this.current_numcommands[position] + 1;
      this.current_numcommands[position] = count;
    else
      let connections = {};
      let counts = {};
      for row in [1..length(this.current_connections)]
        const connection = this.current_connections[row];
        if (typeof(`idle_seconds(connection) ! ANY') != TYPE_ERR)
          connections = {@connections, connection};
          counts = {@counts, this.current_numcommands[row]};
        endif
      endfor
      this.current_connections = {@connections, player};
      this.current_numcommands = {@counts, count};
    endif
    count <= this.max_numcommands && return false;
    notify(player, "Sorry, too many commands issued without connecting.");
    boot_player(player);
    return true;
  endmethod

  method server_started owner: #2
    "Reset connection interceptions and lag samples on restart; retain bounded downtime history.";
    caller_perms().wizard || return E_PERM;
    this.lag_samples = {0, 0, 0, 0, 0};
    this.downtimes = {{time(), this.last_lag_sample}, @this.downtimes[1..min($, 100)]};
    this.intercepted_players = {};
    this.intercepted_actions = {};
    this.current_connections = {};
    this.current_numcommands = {};
    this.checkpoint_in_progress = false;
  endmethod

  method uptime_since owner: #2
    "Subtract recorded downtime from elapsed seconds since the supplied timestamp.";
    const {since} = args;
    let elapsed = time() - since;
    for outage in (this.downtimes)
      outage[1] < since && return elapsed;
      elapsed = elapsed - (outage[1] - max(outage[2], since));
    endfor
    return elapsed;
  endmethod

  method count_bg_players owner: #2
    "Estimate background load from task delays; wizard-only, returning an integer player-equivalent count.";
    caller_perms().wizard || raise(E_PERM);
    const now = time();
    let hundredths = 0;
    for task in (queued_tasks())
      const delay = task[2] - now;
      const interval = delay <= 0 ? 1 | delay * 2;
      delay <= 300 && (hundredths = hundredths + 2000 / interval);
    endfor
    return hundredths / 100;
  endmethod

  method "blacklisted_temp graylisted_temp redlisted_temp spooflisted_temp" owner: #2
    "Return whether any matching site restriction is active; wizard-only.";
    caller_perms().wizard || return E_PERM;
    const {hostname} = args;
    const name = this:listname(verb);
    const lists = this.("temporary_" + name);
    for kind in [1..2]
      for entry in (lists[kind])
        const pattern = entry[1];
        if (this:_site_matches(hostname, pattern, kind))
          this:templist_expired(name, @entry) && return true;
        endif
      endfor
    endfor
    return false;
  endmethod

  method templist_expired owner: #2
    "Return whether a temporary site restriction remains active; remove it when its uptime duration expires.";
    caller_perms().wizard || return E_PERM;
    const {name, host, start, duration} = args;
    this:uptime_since(start) <= duration && return true;
    this:(name + "_remove_temp")(host);
    return false;
  endmethod

  method temp_newt_registration_string owner: #2
    "Describe the remaining temporary login restriction.";
    return "Your character is unavailable for another " + $time_utils:english_time(args[1]) + ".";
  endmethod

  method add_interception owner: HACKER
    "Install one pending login action per connection; calls from this login object only.";
    caller == this || raise(E_PERM);
    const {who, method, @arguments} = args;
    who in this.intercepted_players && raise(E_INVARG, "Player already has an interception set.");
    this.intercepted_players = {@this.intercepted_players, who};
    this.intercepted_actions = {@this.intercepted_actions, {method, @arguments}};
    return true;
  endmethod

  method delete_interception owner: HACKER
    "Remove a connection's pending login action; return whether one existed. Self calls only.";
    caller == this || raise(E_PERM);
    const {who} = args;
    const position = who in this.intercepted_players;
    !position && return false;
    this.intercepted_players = listdelete(this.intercepted_players, position);
    this.intercepted_actions = listdelete(this.intercepted_actions, position);
    return true;
  endmethod

  method interception owner: HACKER
    "Return a pending {method, @arguments} or 0; self calls only.";
    caller == this || raise(E_PERM);
    const {who} = args;
    const position = who in this.intercepted_players;
    return position ? this.intercepted_actions[position] | 0;
  endmethod

  method intercepted_password owner: #2
    "Restore client echo and authenticate the pending password response; system login hook only.";
    caller == $sysobj || raise(E_PERM);
    this:delete_interception(player);
    set_connection_option(player, "client-echo", 1);
    notify(player, "");
    !(length(args) in {1, 2}) && return 0;
    const {candidate, ?password = ""} = args;
    return this:connect(tostr(candidate), password);
  endmethod

  method "do_out_of_band_command doobc" owner: HACKER
    "Extension hook for out-of-band input before login; the default ignores it.";
    return 0;
  endmethod

  method check_for_checkpoint owner: #2
    "Show the configured checkpoint notice without wrapping or paging output.";
    this.checkpoint_in_progress || return 0;
    notify(player, "NOTICE: A database checkpoint is in progress.");
  endmethod

  method _site_matches owner: #2
    "Internal exact, numeric-prefix, or hostname suffix/wildcard match.";
    const {hostname, pattern, kind} = args;
    hostname == pattern && return true;
    const literal = $site_db:domain_literal(hostname);
    if (kind == 1)
      return !!literal && index(hostname, pattern) == 1 && (hostname + ".")[length(pattern) + 1] == ".";
    endif
    literal && return false;
    index(pattern, "*") && return !!$string_utils:match_string(hostname, pattern);
    const position = rindex(hostname, pattern);
    return position > 0 && ("." + hostname)[position] == "." && position - 1 + length(pattern) == length(hostname);
  endmethod

  method _oauth_admitted owner: #2
    "Apply account lockout and connection limits to a verified OAuth login without suspending.";
    "Expired temporary newts are eligible; the password path retains its cleanup and audit mail.";
    caller == this && caller_perms().wizard || raise(E_PERM);
    const {candidate} = args;
    is_player(candidate) && $object_utils:isa(candidate, $player) && !$object_utils:isa(candidate, $guest) || return false;
    is_clear_property(candidate, "password") && return false;
    if ($no_connect_message && !candidate.wizard)
      notify(player, $no_connect_message);
      return false;
    endif
    if (candidate in this.newted)
      const entry = $list_utils:assoc(candidate, this.temporary_newts);
      if (!entry || this:uptime_since(entry[2]) <= entry[3])
        notify(player, this:newt_registration_string());
        return false;
      endif
    endif
    const count = length(connected_players());
    if (!candidate.wizard && !(candidate in this.lag_exemptions) && count >= this:max_connections() && !$object_utils:connected(candidate))
      notify(player, "The connection limit has been reached. Please try again later.");
      return false;
    endif
    return true;
  endmethod

  method _claim_oauth_identity owner: #2
    "Bind one verified identity to one account; only wizard-owned login methods may call this.";
    "The shared revision makes concurrent claims conflict. This method does not suspend.";
    caller == this && caller_perms().wizard || raise(E_PERM);
    const {account, provider, external_id} = args;
    this.oauth2_identity_version = this.oauth2_identity_version + 1;
    const linked = this:find_by_oauth2(provider, external_id);
    valid(linked) && linked != account && raise(E_INVARG, "OAuth identity is already linked to another account.");
    linked == account && return false;
    const identities = `account.oauth2_identities ! E_PROPNF => {}';
    account.oauth2_identities = {@identities, {provider, external_id}};
    return true;
  endmethod
endobject
