object PASSWORD_VERIFIER [
  import_export_id -> "password_verifier"
]
  name: "password verifier"
  parent: THING
  owner: #2
  readable: true

  property check_against_dictionary (owner: #2, flags: "r") = 0;
  property check_against_email (owner: #2, flags: "r") = 0;
  property check_against_hosts (owner: #2, flags: "r") = 0;
  property check_against_moo (owner: #2, flags: "r") = 0;
  property check_against_name (owner: #2, flags: "r") = 0;
  property check_obscure_stuff (owner: #2, flags: "r") = 0;
  property help_msg (owner: HACKER, flags: "r") = {
    "Password Verifier",
    "==================",
    "",
    "To check for the validity of a password, use",
    "  :reject_password( password [, for-whom? ] )",
    "... If it returns a true value, that value will contain the string representing the reason why the password was rejected.  If it returns a false value, the password is OK.",
    "",
    "The toggle switches for this checking are:"
  };
  property minimum_password_length (owner: #2, flags: "r") = 0;
  property require_funky_characters (owner: #2, flags: "r") = 0;

  override aliases (owner: #2, flags: "rc") = {"password verifier", "password", "verifier", "pwd"};
  override description (owner: #2, flags: "rc") = "The password verifier verifies passwords.";
  override object_size (owner: HACKER, flags: "r") = {10921, 1084848672};

  method help_msg owner: HACKER
    "Return descriptions and current values of the configured password checks.";
    let x;
    let base = this.(verb);
    if (typeof(base) == TYPE_STR)
      base = {base};
    endif
    base = {@base, "", tostr(".minimum_password_length = ", toliteral(x = this.minimum_password_length)), x ? tostr("Passwords are required to be a minimum of ", $string_utils:english_number(x), " characters in length.") | "There is no minimum length requirement for passwords."};
    base = {@base, "", tostr(".check_against_moo = ", toliteral(x = this.check_against_moo)), tostr("Passwords ", x ? "may not" | "may", " be variants on the MOO's name (", $mail_agent.moo_name, ").")};
    base = {@base, "", tostr(".check_against_name = ", toliteral(x = this.check_against_name)), tostr("Passwords ", x ? "may not" | "may", " be variants on the player's MOO name and/or aliases.")};
    base = {@base, "", tostr(".check_against_email = ", toliteral(x = this.check_against_email)), x ? "Passwords may not be variants on the player's email address." | "Passwords are not checked against the player's email address."};
    base = {@base, "", tostr(".check_against_hosts = ", toliteral(x = this.check_against_hosts)), x ? "Passwords may not be variants on the player's hostname(s)." | "Passwords are not checked against the player's hostname(s)."};
    base = {@base, "", tostr(".check_against_dictionary = ", toliteral(x = this.check_against_dictionary)), tostr("Passwords ", typeof(x) == TYPE_OBJ ? "may not" | "may", " be dictionary words.")};
    base = {@base, "", tostr(".require_funky_characters = ", toliteral(x = this.require_funky_characters)), tostr("Non-alphabetic characters are ", x ? "" | "not ", "required in passwords.")};
    base = {@base, "", tostr(".check_obscure_stuff = ", toliteral(x = this.check_obscure_stuff)), x ? "Misc. obscure checks enabled" | "No obscure checks in use."};
    return base;
  endmethod

  method reject_password owner: #2
    ":reject_password ( STR password [ , OBJ for-whom ] );";
    "=> string value [if the password is rejected, why?]";
    "=> false value [if the password isn't rejected]";
    let trust;
    if (length(args) == 1)
      trust = 0;
    else
      if ($perm_utils:controls(caller_perms(), args[2]))
        trust = 1;
      else
        return "Permissions don't permit setting of that password.";
      endif
    endif
    "this is gonna be huge";
    return this:trivial_check(@args) || (this.minimum_password_length && this:check_length(@args)) || (this.check_against_name && trust && this:check_name(@args)) || (this.check_against_email && trust && this:check_email(@args)) || (this.check_against_hosts && trust && this:check_hosts(@args)) || (typeof(this.check_against_dictionary) in {TYPE_LIST, TYPE_OBJ} && this:check_dictionary(@args)) || (this.require_funky_characters && this:check_for_funky_characters(@args)) || (this.check_against_moo && this:check_against_moo(@args)) || (this.check_obscure_stuff && this:check_obscure_combinations(@args));
  endmethod

  method trivial_check owner: HACKER
    "Reject invalid password types, spaces, invalid players, guests, or unauthorized changes.";
    const pwd = args[1];
    typeof(pwd) != TYPE_STR && return "Passwords must be strings.";
    if (index(pwd, " "))
      return "Passwords may not contain spaces.";
    elseif (length(args) == 2)
      const who = args[2];
      typeof(who) != TYPE_OBJ || !valid(who) || !is_player(who) && return "That's not a player.";
      if (!$perm_utils:controls(caller_perms(), who))
        return "You can't set the password for that player.";
      elseif ($object_utils:isa(who, $guest))
        return "Sorry, but guest characters are not allowed to change their passwords.";
      endif
    endif
  endmethod

  method check_length owner: HACKER
    "Return a rejection reason when the password is shorter than the configured minimum.";
    const l = this.minimum_password_length;
    if (l && length(args[1]) < l)
      return tostr("Passwords must be a minimum of ", $string_utils:english_number(l), l == 1 ? " character " | " characters ", "long.");
    endif
  endmethod

  method check_name owner: HACKER
    "Reject passwords matching a player's name or its reverse.";
    const pwd = args[1];
    if (valid($player_db:find_exact(pwd)))
      return "Passwords may not be close to a player's name/alias pair.";
    endif
    if (valid($player_db:find($string_utils:reverse(pwd))))
      return "Passwords ought not be the reverse of a player's name/alias.";
    endif
  endmethod

  method check_email owner: #2
    "Reject passwords contained in a controlled player's registered address.";
    const {pwd, who} = args;
    !$perm_utils:controls(caller_perms(), who) && return "Permission denied.";
    const email = $wiz_utils:get_email_address(who);
    if (!email)
      "can't check";
      return;
    endif
    index(email, pwd) && return "Passwords can't match your registered email address.";
  endmethod

  method check_hosts owner: #2
    "Reject passwords contained in a controlled player's recorded hostnames.";
    const {pwd, who} = args;
    !$perm_utils:controls(caller_perms(), who) && return "Permission denied.";
    const hosts = who.all_connect_places;
    for x in (hosts)
      index(x, pwd) && return "Passwords may not match hostnames.";
    endfor
  endmethod

  method check_dictionary owner: HACKER
    "Reject ordinary dictionary words when the configured dictionary is available.";
    const pwd = args[1];
    const dict = this.check_against_dictionary;
    if (typeof(dict) == TYPE_OBJ)
      "assume we're checking mr spell";
      try
        if (dict:find_exact(pwd) && !this:_is_funky_case(pwd))
          return "Dictionary words are not permitted for passwords.";
        endif
      except (ANY)
        "in case this is messed up. Just let it go and return 0;";
      endtry
    endif
  endmethod

  method check_for_funky_characters owner: HACKER
    "Reject passwords without mixed case or nonalphabetic characters.";
    let pwd = args[1];
    if (this:_is_funky_case(pwd))
      return;
    endif
    const alphabet = $string_utils.alphabet;
    for i in [1..length(pwd)]
      !index(alphabet, pwd[i]) && return;
    endfor
    return "At least one unusual capitalization and/or numeric or punctuation character is required.";
  endmethod

  method check_against_moo owner: HACKER
    "Reject passwords matching the world name, except unusual case combinations.";
    const pwd = args[1];
    const moo = $mail_agent.moo_name;
    this:_is_funky_case(pwd) && return;
    pwd == moo && return "The MOO's name is not secure as a password.";
    if (moo[$ - 2..$] == "MOO")
      pwd == moo[1..$ - 3] && return "The MOO's name is not secure as a password.";
    endif
  endmethod

  method _is_funky_case owner: HACKER
    "Return whether a password uses case beyond lowercase, uppercase, or initial capitals.";
    const pwd = args[1];
    let u = $string_utils:uppercase(pwd);
    if (!strcmp(pwd, u))
      return false;
    endif
    let l = $string_utils:lowercase(pwd);
    if (!strcmp(pwd, l))
      return false;
    elseif (!strcmp(pwd, tostr(u[1], l[2..$])))
      return false;
    else
      return true;
    endif
  endmethod

  method check_obscure_combinations owner: HACKER
    "Reject password patterns resembling identification numbers or dates.";
    const pwd = args[1];
    if (match(pwd, "^[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]$"))
      return "Social security numbers are potentially insecure passwords.";
    endif
    if (match(pwd, "^[0-9]+/[0-9]+/[0-9]+$"))
      return "Passwords which look like dates are potentially insecure passwords.";
    endif
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.minimum_password_length = this.check_against_name = (this.check_against_email = (this.check_against_hosts = (this.check_against_dictionary = (this.require_funky_characters = (this.check_against_moo = (this.check_obscure_stuff = 0))))));
    endif
  endmethod
endobject
