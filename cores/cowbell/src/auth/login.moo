object LOGIN
  name: "Login Service"
  parent: ROOT
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property blank_command (owner: ARCH_WIZARD, flags: "r") = "welcome";
  property bogus_command (owner: ARCH_WIZARD, flags: "r") = "?";
  property default_player_class (owner: ARCH_WIZARD, flags: "r") = PLAYER;
  property moo_title (owner: ARCH_WIZARD, flags: "rc") = "Cowbell-Core";
  property player_creation_enabled (owner: ARCH_WIZARD, flags: "r") = true;
  property player_setup_capability (owner: LOGIN, flags: "") = <#5, .token = "v4.local.EIjSChEcQf8hjLCih4NGE-vKw_UZDTKRpWaYiZeQP615jQATzm-KoZTU_t7DfF8lVdOkzNqSRrItjVEZczaN6BIB-83GPs-xGAM4eg9J8sb3NJJr8z8sJPXh2uNurXg4vEbB5TMhj04AQsuski87Jmwe0r1kEq1cS5baIer5griqGFykpZBCHuieE382dS8XJdOzq0p9xViQ9-x_87dmbVdJPAP0tbxA-7KycBk72eldC-mGBTPjfD2qQWqhczzmB77RJ1azUhhOTZU4g6uEBEBfLgE8a-heeB_AIqK1zKl_t8lOf-vUq9rUEQChG5YJID6_NNZGNB8y68eciVHUD1lPnPOaeCc">;
  property registration_string (owner: ARCH_WIZARD, flags: "rc") = "Character creation is disabled.";
  property new_player_welcome_message (owner: ARCH_WIZARD, flags: "rc") = "#### Welcome to {TITLE}!\n\nTry entering `help` to see what you kind of things can do where you are.";
  property welcome_message (owner: ARCH_WIZARD, flags: "rc") = {
    "## Welcome to the _mooR_ *Cowbell* core.",
    "",
    "connect with `archwizard` `test` to log in.",
    "",
    "Server version: {VERSION}",
    "",
    "You will probably want to change this text which is stored in $login.welcome_message property."
  };
  property welcome_message_content_type (owner: ARCH_WIZARD, flags: "rc") = "text/djot";

  override description = "Login service handling player authentication, character creation, and OAuth2 integration.";
  override import_export_hierarchy = {"auth"};
  override import_export_id = "login";

  verb welcome (any none any) owner: ARCH_WIZARD flags: "rxd"
    "Present the welcome message property to the user.";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    message = this.welcome_message:join("\n");
    message = this:_apply_template(message);
    notify(player, message, false, false, this.welcome_message_content_type);
  endverb

  verb _apply_template (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Apply template substitutions (TITLE, VERSION) to a message string.";
    set_task_perms(caller_perms());
    {message} = args;
    message = message:replace_all("{TITLE}", this.moo_title);
    message = message:replace_all("{VERSION}", server_version());
    return message;
  endverb

  verb "co*nnect @co*nnect" (any none any) owner: ARCH_WIZARD flags: "rxd"
    "$login:connect(player-name [, password])";
    " => 0 (for failed connections)";
    " => objnum (for successful connections)";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
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
    {status, _} = this:_password_state(candidate, password);
    if (status == 'ok)
      "Password verified.";
    elseif (status == 'missing)
      "We assume the password is a $password frob; prompt for it interactively.";
      set_connection_option(player, "binary", 1);
      notify(player, "Password: ");
      set_connection_option(player, "binary", 0);
      set_connection_option(player, "client-echo", 0);
      this:add_interception(player, "intercepted_password", candidate);
      return 0;
    elseif (status == 'external_only)
      server_log(tostr("FAILED CONNECT (NO PASSWORD): ", name, " (", candidate, ") on ", connection_name(player)));
      raise(E_INVARG, "This account uses external authentication.");
    elseif (status == 'invalid_type)
      server_log(tostr("FAILED CONNECT (BAD PASSWORD TYPE): ", name, " (", candidate, ") on ", connection_name(player)));
      raise(E_INVARG, "Cannot authenticate this account.");
    else
      server_log(tostr("FAILED CONNECT: ", name, " (", candidate, ") on ", connection_name(player)));
      raise(E_INVARG, "Invalid password.");
    endif
    "TODO: block lists, guests, etc";
    "Log the player in!";
    return candidate;
  endverb

  verb oauth2_check (any none any) owner: ARCH_WIZARD flags: "rxd"
    "$login:oauth2_check(provider, external_id)";
    " => 0 (for not found)";
    " => objnum (for existing OAuth2 identity)";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    try
      {provider, external_id} = args;
    except (E_ARGS)
      notify(player, "OAuth2 check failed: invalid arguments");
      return 0;
    endtry
    candidate = this:find_by_oauth2(provider, external_id);
    server_log(tostr("OAUTH2 CHECK: candidate=", candidate, " valid=", valid(candidate), " typeof=", typeof(candidate)));
    if (valid(candidate))
      server_log(tostr("OAUTH2 CHECK SUCCESS: ", provider, ":", external_id, " -> ", candidate));
      return candidate;
    else
      server_log(tostr("OAUTH2 CHECK NOT FOUND: ", provider, ":", external_id, " returning 0"));
      ret = 0;
      server_log(tostr("OAUTH2 CHECK: about to return ", ret, " typeof=", typeof(ret)));
      return ret;
    endif
  endverb

  verb oauth2_create (any none any) owner: ARCH_WIZARD flags: "rxd"
    "$login:oauth2_create(provider, external_id, email, name, username, player_name)";
    " => 0 (for failed creation)";
    " => objnum (for successful creation)";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    if (!this.player_creation_enabled)
      notify(player, this.registration_string);
      return 0;
    endif
    try
      {provider, external_id, email, name, username, player_name} = args;
      player_name = strsub(player_name, " ", "_");
    except (E_ARGS)
      notify(player, "OAuth2 create failed: invalid arguments");
      return 0;
    endtry
    if (!player_name || player_name == "<>")
      notify(player, "You can't have a blank name!");
      return 0;
    elseif (player_name[1] == "<" && player_name[$] == ">")
      notify(player, "Don't use angle brackets in your player name.");
      return 0;
    elseif (index(player_name, " "))
      notify(player, "Sorry, no spaces are allowed in player names.  Use dashes or underscores.");
      return 0;
    elseif (this:_match_player(player_name) != $failed_match)
      notify(player, "Sorry, that name is not available.  Please choose another.");
      return 0;
    endif
    new = this:_create_player(player_name, 0, email || "", {{provider, external_id}});
    server_log(tostr("OAUTH2 CREATE: ", player_name, " (", new, ") via ", provider, ":", external_id));
    return new;
  endverb

  verb oauth2_connect (any none any) owner: ARCH_WIZARD flags: "rxd"
    "$login:oauth2_connect(provider, external_id, email, name, username, existing_name, existing_password)";
    " => 0 (for failed connection)";
    " => objnum (for successful link)";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    try
      {provider, external_id, email, name, username, existing_name, existing_password} = args;
      existing_name = strsub(existing_name, " ", "_");
    except (E_ARGS)
      notify(player, "OAuth2 connect failed: invalid arguments");
      return 0;
    endtry
    if (!valid(candidate = this:_match_player(existing_name)))
      notify(player, "That player does not exist.");
      return 0;
    endif
    {status, _} = this:_password_state(candidate, existing_password);
    if (status == 'ok)
      "Password verified for linking.";
    elseif (status == 'external_only)
      "Candidate has no password; allow linking without challenge.";
    elseif (status == 'missing)
      notify(player, "Invalid password for existing account.");
      return 0;
    elseif (status == 'invalid_type)
      notify(player, "Cannot link to that account.");
      return 0;
    else
      notify(player, "Invalid password for existing account.");
      return 0;
    endif
    try
      identities = candidate.oauth2_identities;
    except (E_PROPNF)
      identities = {};
    endtry
    if (length(identities) > 0)
      for identity in (identities)
        if (typeof(identity) == LIST && length(identity) == 2)
          if (identity[1] == provider && identity[2] == external_id)
            notify(player, "This OAuth2 identity is already linked to that account.");
            return candidate;
          endif
        endif
      endfor
      candidate.oauth2_identities = {@identities, {provider, external_id}};
    else
      candidate.oauth2_identities = {{provider, external_id}};
    endif
    if (email)
      try
        current_email = candidate.email_address;
      except (E_PROPNF)
        candidate.email_address = email;
        current_email = email;
      endtry
      if (typeof(current_email) != STR || length(current_email) == 0)
        candidate.email_address = email;
      endif
    endif
    server_log(tostr("OAUTH2 CONNECT: ", existing_name, " (", candidate, ") linked ", provider, ":", external_id));
    return candidate;
  endverb

  verb "cr*eate @cr*eate" (any none any) owner: ARCH_WIZARD flags: "rxd"
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
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
    return this:_create_player(name, password, "", {});
  endverb

  verb _match_player (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":_match_player(name)";
    "This is the matching routine used by @connect.";
    "returns either a valid player corresponding to name or $failed_match.";
    caller == this || caller.wizard || raise(E_PERM);
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
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    !args && return {this.blank_command, @args};
    if ((verb = args[1]) && !verb:is_numeric())
      for i in ({this, @ancestors(this)})
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

  verb find_by_oauth2 (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":find_by_oauth2(provider, external_id)";
    "Search all players for matching oauth2_identities entry";
    caller == #0 || caller == this || caller_perms().wizard || raise(E_PERM);
    {provider, external_id} = args;
    for candidate in (players())
      if (is_player(candidate))
        try
          identities = candidate.oauth2_identities;
        except (E_PROPNF)
          identities = {};
        endtry
        for identity in (identities)
          if (typeof(identity) == LIST && length(identity) == 2 && identity[1] == provider && identity[2] == external_id)
            return candidate;
          endif
        endfor
      endif
    endfor
    return $failed_match;
  endverb

  verb _create_player (this none this) owner: LOGIN flags: "rxd"
    ":_create_player(name, password, email, oauth2_identities)";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {player_name, password_value, email, oauth_entries} = args;
    cap = this.player_setup_capability;
    "cap:make_player() returns a setup capability for the new player";
    setup_cap = cap:make_player();
    "Grab the actual underlying object for other uses";
    new_player = setup_cap.delegate;
    setup_cap:set_player_flag(1);
    setup_cap:set_owner(new_player);
    setup_cap:set_name_aliases(player_name, {player_name});
    if (password_value)
      setup_cap:set_password(password_value);
    endif
    if (typeof(email) == STR)
      setup_cap:set_email_address(email);
    endif
    if (typeof(oauth_entries) == LIST)
      setup_cap:set_oauth2_identities(oauth_entries);
    endif
    `setup_cap:moveto($first_room) ! ANY';
    return new_player;
  endverb

  verb _password_state (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":_password_state(candidate, attempt) => {status, stored_password}";
    caller == this || caller_perms().wizard || raise(E_PERM);
    {candidate, attempt} = args;
    try
      stored = candidate.password;
    except (E_PROPNF)
      return {'invalid_type, 0};
    endtry
    stored == 0 && return {'external_only, stored};
    typeof(stored) == FLYWEIGHT || return {'invalid_type, stored};
    attempt || return {'missing, stored};
    stored:challenge(attempt) || return {'mismatch, stored};
    return {'ok, stored};
  endverb

  verb welcome_new_player (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Welcome a new player and show them available commands.";
    "Args: {player_obj}";
    {new_player} = args;
    !valid(new_player) && return;
    set_task_perms(new_player);
    "Welcome them to the MUD and show the what command";
    welcome_msg = this:_apply_template(this.new_player_welcome_message);
    "Add quick-start tips for profile basics";
    tips_list = $format.list:mk({"Set your description: @describe me as <text>", "Set your pronouns: @pronouns they/them (or she/her, he/him, etc.)"});
    content = $format.block:mk(welcome_msg, "Next steps:", tips_list);
    event = $event:mk_info(new_player, content):with_audience('utility);
    event = event:with_metadata('preferred_content_types, {'text_djot, 'text_plain});
    new_player:inform_current(event);
  endverb
endobject
