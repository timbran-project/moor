object PLAYER [
  import_export_id -> "player"
]
  name: "generic player"
  parent: ROOT_CLASS
  owner: #2
  fertile: true
  readable: true

  property all_connect_places (owner: #2, flags: "") = {};
  property brief (owner: #2, flags: "rc") = 0;
  property connection_hook_epoch (owner: #2, flags: "r") = 0;
  property current_folder (owner: #2, flags: "c") = 1;
  property dict (owner: #2, flags: "rc") = {};
  property display_options (owner: #2, flags: "rc") = [];
  property edit_options (owner: #2, flags: "rc") = [];
  property email_address (owner: #2, flags: "") = "";
  property features (owner: HACKER, flags: "r") = {};
  property first_connect_time (owner: #2, flags: "r") = 2147483647;
  property gaglist (owner: #2, flags: "rc") = {};
  property gender (owner: #2, flags: "rc") = "neuter";
  property help (owner: #2, flags: "rc") = 0;
  property home (owner: #2, flags: "rc") = PLAYER_START;
  property last_connect_attempt (owner: #2, flags: "") = 0;
  property last_connect_place (owner: #2, flags: "") = "?";
  property last_connect_time (owner: #2, flags: "r") = 0;
  property last_disconnect_time (owner: #2, flags: "r") = 0;
  property last_password_time (owner: #2, flags: "") = 0;
  property oauth2_identities (owner: #2, flags: "") = {};
  property owned_objects (owner: #2, flags: "r") = {};
  property ownership_quota (owner: HACKER, flags: "") = 0;
  property page_absent_msg (owner: #2, flags: "rc") = "%N is not currently logged in.";
  property page_echo_msg (owner: #2, flags: "rc") = "Your message has been sent.";
  property page_origin_msg (owner: #2, flags: "rc") = "You sense that %n is looking for you in %l.";
  property paranoid (owner: #2, flags: "rc") = 0;
  property password (owner: #2, flags: "") = "impossible password to type";
  property po (owner: #2, flags: "rc") = "it";
  property poc (owner: #2, flags: "rc") = "It";
  property pp (owner: #2, flags: "rc") = "its";
  property ppc (owner: #2, flags: "rc") = "Its";
  property pq (owner: #2, flags: "rc") = "its";
  property pqc (owner: #2, flags: "rc") = "Its";
  property pr (owner: #2, flags: "rc") = "itself";
  property prc (owner: #2, flags: "rc") = "Itself";
  property previous_connection (owner: #2, flags: "") = 0;
  property profile_picture (owner: #2, flags: "rc") = false;
  property ps (owner: #2, flags: "rc") = "it";
  property psc (owner: #2, flags: "rc") = "It";
  property size_quota (owner: HACKER, flags: "") = {};
  property verb_subs (owner: #2, flags: "rc") = {};

  override aliases (owner: #2, flags: "rc") = {"generic player"};
  override description (owner: #2, flags: "rc") = "You see a player who should type '@describe me as ...'.";
  override object_size (owner: HACKER, flags: "r") = {97774, 1084848672};

  method init_for_core owner: #2
    "Reset player-class defaults and connection history; only a wizard may extract a core.";
    caller_perms().wizard || return;
    pass(@args);
    this.home = this in {$no_one, $hacker, $generic_editor.owner} ? $nothing | $player_start;
    const help_entry = $list_utils:assoc(this, {{$prog, {$prog_help, $builtin_function_help, $verb_help, $core_help}}, {$wiz, $wiz_help}, {$mail_recipient_class, $mail_help}, {$builder, $builder_help}, {$default_player, $default_player_help}});
    this.help = help_entry ? help_entry[2] | 0;
    this == $player && return;
    for prop in ({"last_connect_place", "all_connect_places", "previous_connection", "last_connect_time"})
      clear_property(this, prop);
    endfor
    !(this in {$default_player, $builder, $prog, $wiz, $guest}) && clear_property(this, "features");
    if (is_player(this))
      this.first_connect_time = $maxint;
      this.last_disconnect_time = $maxint;
    endif
  endmethod

  method confunc owner: #2
    "Report the last connection when utilities are installed; admit system, player, or controller calls.";
    const cp = caller_perms();
    if (valid(cp) && caller != this && !$perm_utils:controls(cp, this) && caller != #0)
      return E_PERM;
    endif
    $utility_feature in this.features && $utility_feature:("@last-connection")("confunc");
  endmethod

  method disfunc owner: #2
    "Clear caller history and invalid gag entries on authorized disconnection.";
    const cp = caller_perms();
    if (valid(cp) && caller != this && !$perm_utils:controls(cp, this) && caller != #0)
      return E_PERM;
    endif
    this:erase_paranoid_data();
    this:gc_gaglist();
    return;
  endmethod

  method initialize owner: #2
    "Initialize help state for this player or its controller, then run inherited initialization.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.help = 0;
    return pass(@args);
  endmethod

  method acceptable owner: #2
    "Return whether the proposed contained object is not a player.";
    return !is_player(args[1]);
  endmethod

  method my_explain_syntax owner: #2
    "Let the shared syntax helper explain unmatched commands.";
    return false;
  endmethod

  method match_environment owner: #2
    "Return objects visible to command matching; rooms may supply objects or custom alias entries.";
    const {command, ?options = []} = args;
    caller == #0 || caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    set_task_perms(this);
    let environment = {this, @this.contents};
    if (valid(this.location))
      const nearby = this.location:match_scope_for(this, options);
      typeof(nearby) == TYPE_LIST || raise(E_TYPE, "Room matching scope must be a list.");
      for entry in (nearby)
        environment = setadd(environment, entry);
      endfor
    endif
    return environment;
  endmethod

  method command_environment owner: #2
    "Return primary command providers in order: player, installed features, then location.";
    caller == #0 || caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    set_task_perms(this);
    let environment = {this};
    for feature in (this.features)
      valid(feature) && (environment = setadd(environment, feature));
    endfor
    valid(this.location) && (environment = setadd(environment, this.location));
    return environment;
  endmethod

  method my_huh owner: #2
    "Dispatch installed feature commands for this player. Only its controller can request dispatch.";
    const {command, command_args} = args;
    this == player || return false;
    caller_perms() == this || $perm_utils:controls(caller_perms(), this) || return false;
    const prepositions = {"any", prepstr ? $code_utils:full_prep(prepstr) | "none"};
    const direct_specs = dobjstr ? {"any"} | {"none", "any"};
    const indirect_specs = iobjstr ? {"any"} | {"none", "any"};
    let parsed = parse_command(tostr(command, " ", argstr), {});
    parsed['verb] = command;
    parsed['args] = command_args;
    parsed['dobj] = dobj;
    parsed['dobjstr] = dobjstr;
    parsed['iobj] = iobj;
    parsed['iobjstr] = iobjstr;
    parsed['prepstr] = prepstr;
    set_task_perms(this, {{"builtin_call", "dispatch_command_verb"}});
    for feature in (this.features)
      if (!$recycler:valid(feature))
        this:remove_feature(feature);
        continue;
      endif
      const feature_verb = feature:has_feature_verb(command, direct_specs, prepositions, indirect_specs);
      if (!feature_verb)
        continue;
      endif
      "The builtin preserves command arguments and root-command caller permissions, including rd verbs.";
      parsed['verb] = feature_verb;
      const matches = find_command_verb(parsed, {feature});
      if (matches && matches[1][1] == feature)
        dispatch_command_verb(feature, feature_verb, parsed);
      else
        "Custom feature hooks can redirect commands to public methods.";
        feature:(feature_verb)(@command_args);
      endif
      return true;
    endfor
    return false;
  endmethod

  method last_huh owner: #2
    "Try shared give/take/drop syntax with caller authority; return whether it was handled.";
    set_task_perms(caller_perms());
    const {command, command_args} = args;
    command in {"give", "hand", "get", "take", "drop", "throw"} || return false;
    $last_huh:(command)(@command_args);
    return true;
  endmethod

  method my_match_object owner: #2
    "Match a name near this player, with an optional alternate location.";
    ":my_match_object(string [,location])";
    return $string_utils:match_object(@{@args, this.location}[1..2], this);
  endmethod

  method tell_contents owner: #2
    "List complete carried-object titles, one per line.";
    const {contents} = args;
    !contents && return;
    player:tell("Carrying:");
    for thing in (contents)
      player:tell(" ", thing:title());
    endfor
  endmethod

  method titlec owner: #2
    "Return the capitalized title override, or the ordinary title when absent.";
    return `this.namec ! E_PROPNF => this:title()';
  endmethod

  method notify owner: #2
    "Deliver one line of output to this player. Returns 0 when disconnected.";
    this in connected_players() || return 0;
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    pass(args[1]);
  endmethod

  method notify_lines owner: #2
    "Deliver each line of a list (or one line) to this player.";
    caller == this || caller_perms() == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    set_task_perms(caller_perms());
    const lines = typeof(args[1]) == TYPE_LIST ? args[1] | {args[1]};
    for line in (lines)
      this:notify(tostr(line));
    endfor
  endmethod

  method tell owner: #2
    "Deliver output to this player, applying gagging and anti-spoofing.";
    if (this.gaglist || this.paranoid)
      this:gag_p() && return;
      if (this.paranoid == 1)
        $paranoid_db:add_data(this, {{@callers(), {player, "<cmd-line>", player}}, args});
      elseif (this.paranoid == 2)
        const source = this:whodunnit({@callers(), {player, "", player}}, {this, $no_one}, {})[3];
        args = {"(", source.name, " ", source, ") ", @args};
      endif
    endif
    pass(@args);
  endmethod

  method "tell_current tell_current_lines" owner: #2
    "Send text or lines only to this player's current connection; return false when none exists.";
    player == this || caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    const target = `connection() ! E_INVARG => $nothing';
    target == $nothing && return false;
    const delivery = verb == "tell_current_lines" ? "tell_connection_lines" | "tell_connection";
    return this:(delivery)(target, @args);
  endmethod

  method "tell_connection tell_connection_lines" owner: #2
    "Send text or lines to one of this player's connections, with gagging and caller attribution.";
    "Require player/controller authority. Raise E_INVARG for a foreign or closed connection.";
    const {target, @text} = args;
    player == this || caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    const multiline = verb == "tell_connection_lines";
    let lines;
    if (multiline)
      const {value} = text;
      lines = typeof(value) == TYPE_LIST ? value | {value};
    else
      lines = {tostr(@text)};
    endif
    if (this.gaglist || this.paranoid)
      this:gag_p() && return false;
      const frames = {@callers(), {player, "<cmd-line>", player}};
      if (this.paranoid == 1)
        $paranoid_db:add_data(this, {frames, multiline ? lines | text});
      elseif (this.paranoid == 2)
        const source = this:whodunnit(frames, {this, $no_one}, {})[3];
        if (multiline)
          lines = {tostr("[start text by ", source.name, " (", source, ")]"), @lines,
                   tostr("[end text by ", source.name, " (", source, ")]")};
        else
          lines = {tostr("(", source.name, " ", source, ") ", lines[1])};
        endif
      endif
    endif
    return this:_notify_connection(target, lines);
  endmethod

  method _notify_connection owner: #2
    "Validate the destination after output hooks, then send without suspension; self calls only.";
    const {target, lines} = args;
    caller == this || raise(E_PERM);
    typeof(target) == TYPE_OBJ || raise(E_INVARG, "Expected a connection object.");
    let attached = false;
    for entry in (connections(this))
      if (entry[1] == target)
        attached = true;
        break;
      endif
    endfor
    attached || raise(E_INVARG, "Connection is not attached to this player.");
    for line in (lines)
      notify(target, tostr(line));
    endfor
    return true;
  endmethod

  method gag_p owner: #2
    "Return whether the player or a defining object in the caller chain is gagged.";
    const gagged = this.gaglist;
    player in gagged && return true;
    gagged || return false;
    for frame in (callers())
      "Ignore frames for builtins, which have no object or owner.";
      if (frame[1] == $nothing && frame[3] == $nothing && frame[2] != "")
        continue;
      endif
      frame[1] in gagged || frame[4] in gagged && return true;
    endfor
    return false;
  endmethod

  method set_gaglist owner: #2
    ":set_gaglist(@newlist) => this.gaglist = newlist";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return this.gaglist = args;
  endmethod

  verb "@gag*!" (any any any) owner: #2 flags: "rd"
    "Usage: @gag <players or objects>. Use @gag! to include an object with descendants.";
    set_task_perms(player);
    player == this || return player:notify("Permission denied.");
    if (!args)
      player:notify(tostr("Usage:  ", verb, " <player or object> [<player or object>...]"));
      return;
    endif
    let changed = false;
    for p in ($string_utils:match_player_or_object(@args))
      if (p in player.gaglist)
        player:notify(tostr("You are already gagging ", p.name, "."));
      elseif (p == player)
        player:notify("Gagging yourself is a bad idea.");
      elseif (children(p) && verb != "@gag!")
        player:tell("If you really want to gag all descendents of ", $string_utils:nn(p), ", use `@gag! ", p, "' instead.");
      else
        changed = true;
        player:set_gaglist(@setadd(this.gaglist, p));
      endif
    endfor
    changed && this:("@listgag")();
  endverb

  verb "@listgag @gaglist @gagged" (any none none) owner: #2 flags: "rxd"
    "Usage: @listgag [search]. List gags; optionally scan public player gag lists.";
    set_task_perms(valid(caller_perms()) ? caller_perms() | player);
    const invoked_as_command = callers() != {};
    if (!this.gaglist)
      player:notify(tostr("You are ", invoked_as_command ? "no longer gagging anything." | "not gagging anything right now."));
    else
      player:notify(tostr("You are ", invoked_as_command ? "now" | "currently", " gagging ", $string_utils:nn(this.gaglist), "."));
    endif
    !args && return;
    player:notify("Searching for players who may be gagging you...");
    let gl = {};
    for p in (players())
      $command_utils:suspend_if_needed(0, "...searching gaglist...");
      if (!valid(p))
        continue;
      endif
      const gagged = `p.gaglist ! E_PERM => {}';
      typeof(gagged) == TYPE_LIST && this in gagged && (gl = {@gl, p});
    endfor
    gl = { who for who in (gl) if valid(who) };
    if (gl || !invoked_as_command)
      player:notify(tostr($string_utils:nn(gl, " ", "No one"), " appear", length(gl) <= 1 ? "s" | "", " to be gagging you."));
    endif
  endverb

  verb "@ungag" (any none none) owner: #2 flags: "rxd"
    "Usage: @ungag <name or identifier>, or @ungag everyone. Only the player may change its list.";
    if (player != this || (caller != this && !$perm_utils:controls(caller_perms(), this)))
      return player:notify("Permission denied.");
    endif
    !dobjstr && return player:notify(tostr("Usage:  ", verb, " <player>  or  ", verb, " everyone"));
    if (dobjstr == "everyone")
      this.gaglist = {};
      return player:notify("You are no longer gagging anyone or anything.");
    endif
    let match = dobj;
    if (!valid(match))
      match = toobj(dobjstr);
      if (match <= #0)
        match = $string_utils:match(dobjstr, this.gaglist, "name", this.gaglist, "aliases");
      endif
    endif
    if (match == $failed_match)
      player:notify(tostr("You don't seem to be gagging anything named ", dobjstr, "."));
    elseif (match == $ambiguous_match)
      player:notify(tostr("I don't know which \"", dobjstr, "\" you mean."));
    else
      this.gaglist = setremove(this.gaglist, match);
      player:notify(tostr(valid(match) ? match.name | match, " removed from gag list."));
    endif
    this:("@listgag")();
  endverb

  method whodunnit owner: #2
    "Return the first untrusted caller frame, or the final frame when all callers are trusted.";
    const {record, trust, mistrust} = args;
    let suspect = {this, "???", this};
    for frame in (record)
      "Explicit mistrust overrides owner trust; frames on the receiver itself remain trusted.";
      const trusted = !valid(suspect[3]) || suspect[3].wizard || suspect[3] in trust && !(suspect[3] in mistrust);
      trusted || suspect[1] == this || return suspect;
      suspect = frame;
    endfor
    return suspect;
  endmethod

  verb "wh*isper" (any at this) owner: #2 flags: "rxd"
    "Usage: whisper <message> to <player>";
    this:tell(player.name, " whispers, \"", dobjstr, "\"");
    player:tell("You whisper, \"", dobjstr, "\" to ", this.name, ".");
  endverb

  verb page (any any any) owner: #2 flags: "rxd"
    "Usage: page <player> [with <message>]";
    if (!args)
      player:notify(tostr("Usage: ", verb, " <player> [with <message>]"));
      return;
    endif
    const who = $string_utils:match_player(args[1]);
    $command_utils:player_match_result(who, args[1])[1] && return;
    if (who in this.gaglist)
      player:tell("You have ", who:title(), " @gagged.  If you paged ", $gender_utils:get_pronoun("o", who), ", ", $gender_utils:get_pronoun("s", who), " wouldn't be able to answer you.");
      return;
    endif
    "Message substitutions use these command-object bindings.";
    dobj = who;
    iobj = player;
    const header = player:page_origin_msg();
    let text = "";
    if (length(args) > 1)
      let message_start = 2;
      if (args[2] == "with" && length(args) > 2)
        message_start = 3;
      endif
      const msg = $string_utils:from_list(args[message_start..$], " ");
      text = tostr($string_utils:pronoun_sub(($string_utils:index_delimited(header, player.name) ? "%S" | "%N") + " %<pages>, \""), msg, "\"");
    endif
    const result = text ? who:receive_page(header, text) | who:receive_page(header);
    if (result == 2)
      const msg = who:page_absent_msg();
      player:tell(typeof(msg) == TYPE_STR ? msg | $string_utils:pronoun_sub("%n is not currently logged in.", who));
    else
      player:tell(who:page_echo_msg());
    endif
  endverb

  method receive_page owner: #2
    "Deliver preformatted private-page lines; return 1 if listening, or 2 if disconnected.";
    "Overrides may return 0 to refuse. Delivery still applies gagging and anti-spoofing.";
    this:is_listening() || return 2;
    this:tell_lines_suspended(args);
    return 1;
  endmethod

  method "page_origin_msg page_echo_msg page_absent_msg" owner: HACKER
    "Expand a configured private-page message, or return an empty string when unset.";
    const message = `this.(verb) ! E_PROPNF, E_PERM => ""';
    return message ? $string_utils:pronoun_sub(message, this) | "";
  endmethod

  verb "i inv*entory" (none none none) owner: #2 flags: "rd"
    "Usage: inventory. Display carried objects or the empty-handed message.";
    const c = player:contents();
    if (c)
      this:tell_contents(c);
    else
      player:tell("You are empty-handed.");
    endif
  endverb

  method look_self owner: #2
    "Display this player's description, connection state, and carried objects.";
    player:tell(this:titlec());
    pass();
    if (!(this in connected_players()))
      player:tell($gender_utils:pronoun_sub("%{:He} %{!is} sleeping.", this));
    else
      const idle = idle_seconds(this);
      if (idle < 60)
        player:tell($gender_utils:pronoun_sub("%{:He} %{!is} awake and %{!looks} alert.", this));
      else
        const elapsed = $string_utils:from_seconds(idle);
        player:tell($gender_utils:pronoun_sub("%{:He} %{!is} awake, but %{!has} been staring off into space for ", this), elapsed, ".");
      endif
    endif
    const contents = this:contents();
    contents && this:tell_contents(contents);
  endmethod

  verb "g*et take" (this none none) owner: #2 flags: "rxd"
    "Reject attempts to pick up a player, notifying both participants.";
    player:tell("This is not a pick-up joint!");
    this:tell(player.name, " tried to pick you up.");
  endverb

  verb "?* help info*rmation @help" (any any any) owner: #2 flags: "rxd"
    "Usage: help [topic] or ?topic. Resolve the player's help databases and deliver complete lines.";
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    let topic_name;
    if (index(verb, "?") != 1 || length(verb) <= 1)
      topic_name = $string_utils:trimr(argstr);
    elseif (argstr)
      topic_name = tostr(verb[2..$], " ", $string_utils:trimr(argstr));
    else
      topic_name = verb[2..$];
    endif
    const databases = $code_utils:help_db_list();
    const result = $code_utils:help_db_search(topic_name, databases);
    if (!result)
      $wiz_utils:missed_help(topic_name, result);
      return player:tell_current(tostr("Sorry, but no help is available on `", topic_name, "'."));
    endif
    if (result[1] == $ambiguous_match)
      $wiz_utils:missed_help(topic_name, result);
      player:tell_current_lines(tostr("Sorry, but the topic-name `", topic_name, "' is ambiguous.  I don't know which of the following topics you mean:"));
      for line in ($help:columnize(@$help:sort_topics(result[2])))
        player:tell_current(tostr("   ", line));
      endfor
      return;
    endif
    const {database, topic} = result;
    if (topic != topic_name)
      player:tell_current(tostr("Showing help on `", topic, "':"));
      player:tell_current("----");
    endif
    const remaining = databases[1 + (database in databases)..$];
    const text = database:get_topic(topic, remaining);
    text == 1 && return;
    if (!text)
      player:tell_current(tostr("Help DB ", database, " thinks it knows about `", topic_name, "' but something's messed up."));
      return player:tell_current(tostr("Tell ", database.owner.wizard ? "" | tostr(database.owner.name, " (", database.owner, ") or "), "a wizard."));
    endif
    for line in (typeof(text) == TYPE_LIST ? text | {text})
      player:tell_current(typeof(line) == TYPE_STR ? line | "Odd results from help -- complain to a wizard.");
      "Long help output may commit between complete lines; no world state is written here.";
      $command_utils:suspend_if_needed(0);
    endfor
  endverb

  method display_option owner: #2
    "Return a display option to this player or its controller, or E_PERM.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return $display_options:get(this.display_options, args[1]);
  endmethod

  method edit_option owner: #2
    "Return an edit option to this player, an editor, or its controller, or E_PERM.";
    caller == this || $object_utils:isa(caller, $generic_editor) || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return $edit_options:get(this.edit_options, args[1]);
  endmethod

  method "set_mail_option set_edit_option set_display_option" owner: #2
    "Set an option for this player or its controller; return 1 if changed, 0 if unchanged, or an error string.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return tostr(E_PERM);
    const property = verb[5..$] + "s";
    const updated = #0.(property):set(this.(property), @args);
    typeof(updated) == TYPE_STR && return updated;
    updated == this.(property) && return 0;
    this.(property) = updated;
    return 1;
  endmethod

  verb "@mailo*ptions @mail-o*ptions @edito*ptions @edit-o*ptions @displayo*ptions @display-o*ptions" (any any any) owner: #2 flags: "rd"
    "@<what>-option <option> [is] <value>   sets <option> to <value>";
    "@<what>-option <option>=<value>        sets <option> to <value>";
    "@<what>-option +<option>     sets <option>   (usually equiv. to <option>=1";
    "@<what>-option -<option>     resets <option> (equiv. to <option>=0)";
    "@<what>-option !<option>     resets <option> (equiv. to <option>=0)";
    "@<what>-option <option>      displays value of <option>";
    set_task_perms(player);
    const what = {"mail", "edit", "display"}[index("med", verb[2])];
    const options = what + "_options";
    const option_pkg = #0.(options);
    const set_option = "set_" + what + "_option";
    if (!args)
      player:notify_lines({"Current " + what + " options:", "", @option_pkg:show(this.(options), option_pkg.names)});
      return;
    endif
    const presult = option_pkg:parse(args);
    if (typeof(presult) == TYPE_STR)
      player:notify(presult);
      return;
    else
      if (length(presult) > 1)
        const sresult = this:(set_option)(@presult);
        if (typeof(sresult) == TYPE_STR)
          player:notify(sresult);
          return;
        endif
        if (!sresult)
          player:notify("No change.");
          return;
        endif
      endif
      player:notify_lines(option_pkg:show(this.(options), presult[1]));
    endif
  endverb

  method set_name owner: #2
    "Change a player's name and lookup index together; return 1 or a permission/validation error.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    if (!is_player(this))
      set_task_perms(caller_perms());
      return pass(@args);
    endif
    $player_db.frozen && return E_NACC;
    const name = args[1];
    length(name) > $login.max_player_name && return E_ARGS;
    $player_db:available(name, this) in {this, 1} || return E_INVARG;
    const old = this.name;
    this.name = name;
    name != old && !(old in this.aliases) && $player_db:delete(old);
    $player_db:insert(name, this);
    return 1;
  endmethod

  method set_aliases owner: #2
    "Set aliases and their player index entries atomically; return whether they changed or an error.";
    "Keep the name, omit conflicting aliases, and leave aliases with spaces out of the global index.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    !is_player(this) && return pass(@args);
    $player_db.frozen && return E_NACC;
    let aliases = args[1];
    typeof(aliases) == TYPE_LIST || return E_TYPE;
    aliases = setadd(aliases, this.name);
    const limit = $object_utils:has_property($local, "max_player_aliases") ? $local.max_player_aliases | $maxint;
    length(aliases) > limit && length(aliases) >= length(this.aliases) && return E_INVARG;
    for alias in (aliases)
      typeof(alias) == TYPE_STR || return E_INVARG;
      if (!(index(alias, " ") || index(alias, "\t")) && !($player_db:available(alias, this) in {this, 1}))
        aliases = setremove(aliases, alias);
      endif
    endfor
    const old = this.aliases;
    this.aliases = aliases;
    for alias in (old)
      !(alias in aliases) && $player_db:delete2(alias, this);
    endfor
    for alias in (aliases)
      !(index(alias, " ") || index(alias, "\t")) && $player_db:insert(alias, this);
    endfor
    return aliases != old;
  endmethod

  method set_gender owner: #2
    "Set gender and pronouns for this player or its controller; return the gender utility result.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const result = $gender_utils:set(this, args[1]);
    this.gender = typeof(result) == TYPE_STR ? result | args[1];
    return result;
  endmethod

  verb "@gender" (any none none) owner: #2 flags: "rd"
    "Usage: @gender [gender]. Display or set gender and pronouns.";
    set_task_perms(valid(caller_perms()) ? caller_perms() | player);
    if (!args)
      player:notify(tostr("Your gender is currently ", this.gender, "."));
      player:notify($string_utils:pronoun_sub("Your pronouns:  %s,%o,%p,%q,%r,%S,%O,%P,%Q,%R"));
      player:notify(tostr("Available genders:  ", $string_utils:english_list($gender_utils.genders, "", " or ")));
    else
      const result = this:set_gender(args[1]);
      const quote = result == E_NONE ? "\"" | "";
      player:notify(tostr("Gender set to ", quote, this.gender, quote, "."));
      if (typeof(result) != TYPE_ERR)
        player:notify($string_utils:pronoun_sub("Your pronouns:  %s,%o,%p,%q,%r,%S,%O,%P,%Q,%R"));
      elseif (result != E_NONE)
        player:notify(tostr("Couldn't set pronouns:  ", result));
      else
        player:notify("Pronouns unchanged.");
      endif
    endif
  endverb

  method set_brief owner: #2
    "Set the numeric brief counter, or add to it when a second argument is supplied.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.brief = length(args) == 1 ? args[1] | this.brief + args[1];
  endmethod

  verb "@mode" (any any any) owner: #2 flags: "rd"
    "@mode <mode>";
    "Current modes are brief and verbose.";
    "General verb for setting player `modes'.";
    if (caller != this)
      player:tell("You can't set someone else's modes.");
      return E_PERM;
    endif
    const modes = {"brief", "verbose"};
    const mode = `modes[$string_utils:find_prefix(dobjstr, modes)] ! E_TYPE, E_RANGE => 0';
    if (!mode)
      player:tell("Unknown mode \"", dobjstr, "\".  Known modes:");
      for choice in (modes)
        player:tell("  ", choice);
      endfor
      return 0;
    endif
    if (mode == "brief")
      this:set_brief(1);
    elseif (mode == "verbose")
      this:set_brief(0);
    endif
    player:tell($string_utils:capitalize(mode), " mode set.");
    return 1;
  endverb

  method add_feature owner: HACKER
    "Install an eligible feature; return true, E_INVARG for an invalid object, or E_PERM for denial.";
    "The player or its controller may install. The optional callback runs after the list update.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const {feature} = args;
    typeof(feature) == TYPE_OBJ && valid(feature) || return E_INVARG;
    $code_utils:verb_or_property(feature, "feature_ok", this) || return E_PERM;
    this.features = typeof(this.features) == TYPE_LIST ? setadd(this.features, feature) | {feature};
    try
      feature:feature_add(this);
    except (ANY)
      "An absent or failing callback does not undo installation.";
    endtry
    return true;
  endmethod

  method remove_feature owner: HACKER
    "Remove a feature; return true or E_PERM. The feature owner may also request removal.";
    "Notify the feature after the list update, including repeated removal requests.";
    const {feature} = args;
    caller == this || $perm_utils:controls(caller_perms(), this) || caller_perms() == feature.owner || return E_PERM;
    if (typeof(this.features) == TYPE_LIST)
      this.features = setremove(this.features, feature);
    endif
    try
      feature:feature_remove(this);
    except (ANY)
      "An absent or failing callback does not undo removal.";
    endtry
    return true;
  endmethod

  verb "@quit" (none none none) owner: #2 flags: "rd"
    "Usage: @quit. Disconnect only the connection issuing this command.";
    boot_player(connection());
  endverb

  method examine_commands_ok owner: #2
    "Return whether this player is the one requesting obvious commands.";
    return this == args[1];
  endmethod

  method is_listening owner: #2
    "return true if player is active.";
    return typeof(`idle_seconds(this) ! ANY') != TYPE_ERR;
  endmethod

  method moveto owner: #2
    "Move with caller authority; return E_INVARG for the void destination.";
    args[1] == $nothing && return E_INVARG;
    set_task_perms(caller_perms());
    pass(@args);
  endmethod

  method "announce*_all_but" owner: #2
    "Forward a room announcement, preserving the message and exclusion arguments.";
    return this.location:(verb)(@args);
  endmethod

  method verb_sub owner: #2
    "Return a player-specific verb substitution, or its gender-based conjugation.";
    const text = args[1];
    const entry = `$list_utils:assoc(text, this.verb_subs) ! ANY';
    return entry ? entry[2] | $gender_utils:get_conj(text, this);
  endmethod

  method ownership_quota owner: #2
    "Return the ownership quota to a controller of this player, or E_PERM.";
    $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return this.(verb);
  endmethod

  method tell_lines owner: #2
    "Deliver complete lines with gagging and recorded or immediate caller attribution.";
    let lines = typeof(args[1]) == TYPE_LIST ? args[1] | {args[1]};
    if (this.gaglist || this.paranoid)
      this:gag_p() && return;
      if (this.paranoid == 2)
        const source = this:whodunnit({@callers(), {player, "", player}}, {this, $no_one}, {})[3];
        lines = {tostr("[start text by ", source.name, " (", source, ")]"), @lines, tostr("[end text by ", source.name, " (", source, ")]")};
      elseif (this.paranoid == 1)
        $paranoid_db:add_data(this, {{@callers(), {player, "<cmd-line>", player}}, lines});
      endif
    endif
    this:notify_lines(lines);
  endmethod

  method set_home owner: #2
    "Set an accepting home for this player or its controller; return true or an error.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const home = args[1];
    $object_utils:has_callable_verb(home, "accept_for_abode") || return E_TYPE;
    home:accept_for_abode(this) || return E_INVARG;
    const result = `this.home = home ! ANY';
    return typeof(result) != TYPE_ERR ? true | result;
  endmethod

  verb "@registerme" (any any any) owner: #2 flags: "rd"
    "Usage: @registerme [as <address>]. Display registration or send a request to the registrar.";
    "A confirmation read commits; the request records the original connection and policy reason.";
    player != this && return player:notify(tostr(E_PERM));
    const who = this;
    if ($object_utils:isa(this, $guest))
      who:notify("Sorry, guests should use the '@request' command to request a character.");
      return;
    endif
    const connection = $string_utils:connection_hostname(connection_name(who));
    if (!argstr)
      if ($wiz_utils:get_email_address(who))
        player:tell("You are currently registered as:  ", $wiz_utils:get_email_address(who));
      else
        player:tell("You are not currently registered.");
      endif
      player:tell("Use @registerme as <address> to change this.");
      return;
    endif
    if (prepstr != "as" || !iobjstr || dobjstr)
      player:tell("Usage: @registerme as <address>");
      return;
    endif
    const email = iobjstr;
    if (email == $wiz_utils:get_email_address(this))
      who:notify("That is your current address.  Not changed.");
      return;
    endif
    const reason = $wiz_utils:check_reregistration(this, email, connection);
    if (reason)
      if (reason[1] == "-")
        if (!$command_utils:yes_or_no(reason[2..$] + ". Automatic registration not allowed. Ask to be registered at this address anyway?"))
          who:notify("Okay.");
          return;
        endif
      else
        return who:notify(tostr(reason, " Please try again."));
      endif
    endif
    who:notify("Your request will be forwarded to the registrar.");
    const curreg = $registration_db:find(email);
    let additional_info = {};
    if (typeof(curreg) == TYPE_LIST)
      additional_info = {"Current registration information for this email address:", @$registration_db:describe_registration(curreg)};
    else
      additional_info = {};
    endif
    $mail_agent:send_message(this, $registration_db.registrar, "Registration request", {"Reregistration request from " + $string_utils:nn(who) + " connected via " + connection + ":", "", "@register " + who.name + " " + email, "@new-password " + who.name + " is ", "", "Reason this request was forwarded:", reason, @additional_info});
  endverb

  method ctime owner: #2
    ":ctime([INT time]) => STR as the function.";
    "May be hacked by players and player-classes to reflect differences in time-zone.";
    return ctime(@args);
  endmethod

  verb news (any none none) owner: #2 flags: "rxd"
    "Usage: news [contents | new | all | archive | articles]. Read or list the selected edition.";
    set_task_perms(player);
    const current = this:get_current_message($news) || {0, 0};
    let archived = false;
    if (!args)
      const option = player:mail_option("news");
      option && option != "all" && (args = {option});
    elseif (args == {"all"})
      args = {};
    elseif (args == {"archive"})
      archived = true;
      args = {};
    endif
    const headers_only = args && args[1] == "contents";
    headers_only && (args[1..1] = {});
    let sequence;
    if (args)
      sequence = $news:_parse(args, @current);
      typeof(sequence) == TYPE_STR && return player:notify(sequence);
      sequence = $seq_utils:intersection(sequence, $news.current_news);
      if (!sequence)
        return player:notify(args == {"new"} ? "No new news." | "None of those are current articles.");
      endif
    else
      sequence = archived && $news.archive_news ? $news.archive_news | $news.current_news;
      sequence || return player:notify("No news");
    endif
    if (headers_only)
      $news:display_seq_headers(sequence, @current);
    else
      player:set_current_message($news, @$news:news_display_seq_full(sequence));
    endif
  endverb

  method erase_paranoid_data owner: #2
    "Erase recorded caller history for this player or its controller, or return E_PERM.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    $paranoid_db:erase_data(this);
  endmethod

  method notify_lines_suspended owner: #2
    "Deliver complete lines with caller authority, committing between lines only when the budget is low.";
    caller == this || caller_perms() == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    set_task_perms(caller_perms());
    const lines = typeof(args[1]) == TYPE_LIST ? args[1] | {args[1]};
    for line in (lines)
      $command_utils:suspend_if_needed(0);
      this:notify(tostr(line));
    endfor
  endmethod

  method _chparent owner: #2
    "Change ancestry with caller authority and return the builtin result.";
    set_task_perms(caller_perms());
    return chparent(@args);
  endmethod

  verb "@password" (any any any) owner: #2 flags: "rd"
    "Usage: @password [old-password] new-password. Validate and store a new password hash.";
    let new_password;
    if (typeof(player.password) != TYPE_STR)
      length(args) != 1 && return player:notify(tostr("Usage:  ", verb, " <new-password>"));
      new_password = args[1];
    elseif (length(args) != 2)
      player:notify(tostr("Usage:  ", verb, " <old-password> <new-password>"));
      return;
    elseif (!argon2_verify(player.password, tostr(args[1])))
      player:notify("That's not your old password.");
      return;
    elseif (is_clear_property(player, "password"))
      player:notify("Your password has a `clear' property.  Please refer to a wizard for assistance in changing it.");
      return;
    elseif (player in $wiz_utils.change_password_restricted)
      player:notify("You are not permitted to change your own password.");
      return;
    else
      new_password = args[2];
    endif
    const r = $password_verifier:reject_password(new_password, player);
    if (r)
      player:notify(r);
      return;
    endif
    const salt_str = salt();
    player.password = argon2(new_password, salt_str);
    player.last_password_time = time();
    player:notify("New password set.");
  endverb

  method recycle owner: #2
    "Run inherited cleanup and feature-removal callbacks for this player or its controller.";
    "This loop adds no commit boundary; an overriding hook can still suspend or fork.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return;
    pass(@args);
    for feature in (this.features)
      this.features = setremove(this.features, feature);
      if (!$object_utils:has_verb(feature, "feature_remove"))
        continue;
      endif
      try
        feature:feature_remove(this);
      except error (ANY)
        server_log(tostr("Feature removal for ", this, " on ", feature, " failed: ", error[1]));
        player:tell("Failure in ", feature, ":feature_remove for player ", $string_utils:nn(this));
      endtry
    endfor
  endmethod

  method gc_gaglist owner: #2
    "Remove invalid gag entries for this player or its controller; deny other callers.";
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    this.gaglist || return;
    this.gaglist = { object for object in (this.gaglist) if $recycler:valid(object) };
  endmethod

  method email_address owner: #2
    "Read the private email property with caller authority.";
    set_task_perms(caller_perms());
    return this.email_address;
  endmethod

  method set_email_address owner: #2
    "Write the private email property with caller authority.";
    set_task_perms(caller_perms());
    this.email_address = args[1];
  endmethod

  method reconfunc owner: #2
    "Run the connection hook again for an authorized reconnection.";
    const cp = caller_perms();
    if (valid(cp) && caller != this && !$perm_utils:controls(cp, this) && caller != $sysobj)
      return E_PERM;
    endif
    return this:confunc(@args);
  endmethod

  method profile_picture owner: #2
    "Return the configured picture tuple or false when unset.";
    return this.profile_picture;
  endmethod

  method set_profile_picture owner: #2
    "Store an image content type and binary picture for this player or its controller.";
    $perm_utils:controls(caller_perms(), this) || this == caller || return E_PERM;
    set_task_perms(this);
    const {content_type, picbin} = args;
    length(picbin) > 5 * (1 << 23) && raise(E_INVARG("Profile picture too large"));
    typeof(content_type) == TYPE_STR && $string_utils:find_prefix("image/", {content_type}) || raise(E_TYPE);
    typeof(picbin) == TYPE_BINARY || raise(E_TYPE);
    this.profile_picture = {content_type, picbin};
  endmethod
endobject
