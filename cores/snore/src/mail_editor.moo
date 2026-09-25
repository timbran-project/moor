object MAIL_EDITOR [
  import_export_id -> "mail_editor"
]
  name: "Mail Room"
  parent: GENERIC_EDITOR
  owner: HACKER
  readable: true

  property recipients (owner: HACKER, flags: "") = {};
  property replytos (owner: HACKER, flags: "") = {};
  property sending (owner: HACKER, flags: "") = {};
  property subjects (owner: HACKER, flags: "") = {};

  override aliases (owner: HACKER, flags: "rc") = {"Mail Room"};
  override blessed_task (owner: HACKER, flags: "rc") = 2043059065;
  override commands (owner: HACKER, flags: "rc") = {
    {"subj*ect", "[<text>]"},
    {"to", "[<rcpt>..]"},
    {"also-to", "[<rcpt>..]"},
    {"reply-to", "[<rcpt>..]"},
    {"who", "[<rcpt>..]"},
    {"pri*nt", ""},
    {"send", ""},
    {"showlists,unsubscribe", ""}
  };
  override commands2 (owner: HACKER, flags: "rc") = {
    {
      "say",
      "emote",
      "lis*t",
      "ins*ert",
      "n*ext,p*rev",
      "enter",
      "del*ete",
      "f*ind",
      "s*ubst",
      "m*ove,c*opy",
      "join*l",
      "fill"
    },
    {
      "y*ank",
      "w*hat",
      "subj*ect",
      "to",
      "also-to",
      "reply-to",
      "showlists,unsubscribe",
      "who",
      "pri*nt",
      "send",
      "abort",
      "q*uit,done,pause"
    }
  };
  override depart_msg (owner: HACKER, flags: "rc") = "%N flattens out into a largish postage stamp and floats away.";
  override entrances (owner: HACKER, flags: "c") = {#16500};
  override exit_on_abort (owner: HACKER, flags: "rc") = true;
  override help (owner: HACKER, flags: "rc") = {};
  override no_littering_msg (owner: HACKER, flags: "rc") = {
    "Saving your message so that you can finish it later.",
    "To come back, give the `@send' command with no arguments.",
    "Please come back and SEND or ABORT if you don't intend to be working on this",
    "message in the immediate future.  Keep Our MOO Clean!  No Littering!"
  };
  override no_text_msg (owner: HACKER, flags: "rc") = "Message body is empty.";
  override nothing_loaded_msg (owner: HACKER, flags: "rc") = "You're not editing anything!";
  override object_size (owner: HACKER, flags: "r") = {22248, 1084848672};
  override previous_session_msg (owner: HACKER, flags: "rc") = "You need to either SEND it or ABORT it before you can start another message.";
  override return_msg (owner: HACKER, flags: "rc") = "A largish postage stamp floats into the room and fattens up into %n.";
  override stateprops (owner: #96, flags: "r") = {
    {"sending", false},
    {"replytos", {}},
    {"recipients", {}},
    {"subjects", ""},
    {"texts", {}},
    {"changes", 0},
    {"inserting", 1},
    {"readable", 0}
  };
  override who_location_msg (owner: HACKER, flags: "rc") = "%L [mailing]";

  method working_on owner: HACKER
    "Describe an authorized draft and whether it is being sent.";
    const who = args[1];
    const access = this:ok(who);
    typeof(access) == TYPE_ERR && return access;
    const subject = `this.subjects[who] ! ANY';
    return tostr("a letter ", typeof(this:sending(who)) == TYPE_INT ? "(in transit) " | "", "to ", this:recipient_names(who), subject && tostr(" entitled \"", subject, "\""));
  endmethod

  method parse_invoke owner: HACKER
    "invoke(rcptstrings,verb[,subject]) for a @send";
    "invoke(1,verb,rcpts,subject,replyto,body) if no parsing is needed";
    "invoke(2,verb,msg,flags,replytos) for an @answer";
    const which = args[1];
    if (!which)
      player:tell_lines({tostr("Usage:  ", args[2], " <list-of-recipients>"), tostr("        ", args[2], "                      to continue with a previous draft")});
      return 0;
    endif
    if (typeof(which) == TYPE_LIST)
      const rcpts = this:parse_recipients({}, which);
      rcpts || return 0;
      let replyto = player:mail_option("replyto");
      replyto && (replyto = this:parse_recipients({}, replyto, ".mail_options: "));
      let subject = {@args, 0}[3];
      if (0 == subject)
        if (player:mail_option("nosubject"))
          subject = "";
        else
          player:tell("Subject:");
          subject = $command_utils:read();
        endif
      endif
      return {rcpts, subject, replyto, {}};
    endif
    which == 1 && return args[3..6];
    const {msg, flags} = {args[3], args[4]};
    const to_subj = this:parse_msg_headers(msg, flags);
    to_subj || return 0;
    let include = {};
    if ("include" in flags)
      include = { "> " + line for line in ($mail_agent:to_text(@msg)) };
    endif
    return {@to_subj, args[5], include};
  endmethod

  method init_session owner: HACKER
    "Initialize a draft; optional automatic entry uses the validated editor input path.";
    const {who, recip, subj, replyto, msg} = args;
    this:ok(who) || return;
    this.sending[who] = false;
    this.recipients[who] = recip;
    this.subjects[who] = subj;
    this.replytos[who] = replyto || {};
    this:load(who, msg);
    this.active[who]:tell("Composing ", this:working_on(who));
    const p = this.active[who];
    p:mail_option("enter") && this:_read_into_buffer();
  endmethod

  verb "pri*nt" (any none none) owner: HACKER flags: "rd"
    "Display the current draft or another player's published draft.";
    let plyr;
    if (!dobjstr)
      plyr = player;
    else
      plyr = $string_utils:match_player(dobjstr);
      $command_utils:player_match_result(plyr, dobjstr)[1] && return;
    endif
    if (plyr != player && !this:readable(plyr in this.active))
      player:tell(plyr.name, "(", plyr, ") has not published anything here.");
      return;
    endif
    const msg = this:message_with_headers(plyr in this.active);
    if (typeof(msg) != TYPE_LIST)
      player:tell(msg);
    else
      player:display_message({(plyr == player ? "Your" | tostr(plyr.name, "(", plyr, ")'s")) + " message so far:", ""}, player:msg_text(@msg));
    endif
  endverb

  method message_with_headers owner: HACKER
    "Return a published or authorized private message with headers; preserve session access errors.";
    const {who} = args;
    if (!this:readable(who))
      const access = this:ok(who);
      !access && return access;
    endif
    return $mail_agent:make_message(this.active[who], this.recipients[who], {this.subjects[who], this.replytos[who]}, this:text(who));
  endmethod

  verb "subj*ect:" (any any any) owner: HACKER flags: "rd"
    "Show or change the current draft subject.";
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (!argstr)
      player:tell(this.subjects[who]);
      return;
    endif
    const subj = this:set_subject(who, argstr);
    if (TYPE_ERR == typeof(subj))
      player:tell(subj);
      return;
    endif
    player:tell(subj ? "Setting the subject line for your message to \"" + subj + "\"." | "Deleting the subject line for your message.");
  endverb

  method set_subject owner: HACKER
    "Change an authorized draft subject and mark it modified.";
    const who = args[1];
    const access = this:ok(who);
    typeof(access) == TYPE_ERR && return access;
    const subj = args[2];
    this.subjects[who] = subj;
    this:set_changed(who, true);
    return subj;
  endmethod

  method sending owner: HACKER
    "Return the live sending task ID, or false; clear a completed or crashed task.";
    const {who} = args;
    const access = this:ok(who);
    !access && return access;
    const task = this.sending[who];
    typeof(task) == TYPE_INT && $code_utils:task_valid(task) && return task;
    typeof(task) == TYPE_INT && this:set_changed(who, true);
    this.sending[who] = false;
    return false;
  endmethod

  verb "to*:" (any any any) owner: HACKER flags: "rd"
    "Replace the draft recipients with the successfully parsed addresses.";
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (!args)
      player:tell("Your message is currently to ", this:recipient_names(who), ".");
      return;
    endif
    this.recipients[who] = this:parse_recipients({}, args);
    this:set_changed(who, true);
    player:tell("Your message is now to ", this:recipient_names(who), ".");
  endverb

  verb "also*-to: cc*:" (any any any) owner: HACKER flags: "rd"
    "Add successfully parsed addresses to the draft.";
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    this.recipients[who] = this:parse_recipients(this.recipients[who], args);
    this:set_changed(who, true);
    player:tell("Your message is now to ", this:recipient_names(who), ".");
  endverb

  verb "not-to*: uncc*:" (any any any) owner: HACKER flags: "rd"
    "Remove matching recipients without changing the draft if any name fails.";
    const who = this:loaded(player);
    !who && return player:tell(this:nothing_loaded_msg());
    let recipients = this.recipients[who];
    for name in (args)
      !name && return player:tell("Empty recipient name.");
      let recipient = $mail_agent:match_recipient(name);
      if (!valid(recipient) || !(recipient in recipients))
        recipient = $string_utils:literal_object(name);
        if (recipient != $failed_match)
          !(recipient in recipients) && return player:tell(recipient, " was not a recipient.");
        else
          const lists = { item for item in (recipients) if valid(item) && $object_utils:isa(item, $mail_recipient) };
          const people = { person for person in (recipients) if valid(person) && !(person in lists) };
          recipient = name[1] == "*" ? $string_utils:match(name[2..$], lists, "aliases") | $string_utils:match(name, people, "aliases");
          !valid(recipient) && (recipient = $string_utils:match(name, { candidate for candidate in (recipients) if valid(candidate) }, "aliases"));
          !valid(recipient) && return player:tell("Couldn't find ", name, " in To: list.");
        endif
      endif
      recipients = setremove(recipients, recipient);
    endfor
    this.recipients[who] = recipients;
    this:set_changed(who, true);
    player:tell("Your message is now to ", this:recipient_names(who), ".");
  endverb

  method parse_recipients owner: HACKER
    "parse_recipients(prev_list,list_of_strings) -- parses list of strings and adds any resulting player objects to prev_list.  Optional 3rd arg is prefixed to any mismatch error messages";
    let {recips, l, ?cmd_id = ""} = args;
    cmd_id = cmd_id || "";
    for s in (typeof(l) == TYPE_LIST ? l | {l})
      if (typeof(s) != TYPE_STR)
        if ($mail_agent:is_recipient(s))
          recips = setadd(recips, s);
        else
          player:tell(cmd_id, s, " is not a valid mail recipient.");
        endif
      else
        const matched = $mail_agent:match_recipient(s);
        !$mail_agent:match_failed(matched, s, cmd_id) && (recips = setadd(recips, matched));
      endif
    endfor
    return recips;
  endmethod

  method recipient_names owner: HACKER
    "Return readable address names with session authority.";
    const who = args[1];
    return this:ok(who) && $mail_agent:name_list(@this.recipients[who]);
  endmethod

  method make_message owner: HACKER
    "Format mail through the distribution service.";
    return $mail_agent:make_message(@args);
  endmethod

  method name_list owner: HACKER
    "Format a list of recipients through the distribution service.";
    return $mail_agent:(verb)(@args[1]);
  endmethod

  method parse_msg_headers owner: HACKER
    "parse_msg_headers(msg,flags)";
    "  parses msg to extract reply recipients and construct a subject line";
    "  if the \"all\" flag is present, reply goes to all of the original recipients";
    "  returns a list {recipients, subjectline} or 0 in case of error.";
    const {msg, flags} = args;
    const replyall = "all" in flags;
    let objects = {};
    if ("followup" in flags)
      for o in ($mail_agent:parse_address_field(msg[3]))
        if (objects)
          break o;
        elseif ($object_utils:isa(o, $mail_recipient))
          objects = {o};
        endif
      endfor
    endif
    objects = objects || $mail_agent:parse_address_field(msg[2] + (replyall ? msg[3] | ""));
    for line in (msg[5..("" in {@msg, ""}) - 1])
      const rt = index(line, "Reply-to:") == 1;
      if (rt)
        objects = $mail_agent:parse_address_field(line);
      endif
    endfor
    let recips = {};
    for o in (objects)
      if (o == #0)
        player:tell("Sorry, but I can't parse the header of that message.");
        return 0;
      endif
      if (!valid(o) || !(is_player(o) || $mail_recipient in $object_utils:ancestors(o)))
        player:tell(o, " is no longer a valid player or maildrop; ignoring that recipient.");
      elseif (o != player)
        recips = setadd(recips, o);
      endif
    endfor
    let subject = msg[4];
    if (subject == " ")
      subject = "";
    elseif (subject && index(subject, "Re: ") != 1)
      subject = "Re: " + subject;
    endif
    return {recips, subject};
  endmethod

  method check_answer_flags owner: HACKER
    "Parse @answer/@reply flags and return {flags, reply_to}.";
    let flags = {};
    for o in ({"all", "include", "followup"})
      player:mail_option(o) && (flags = {@flags, o});
    endfor
    let reply_to = player:mail_option("replyto") || {};
    const flaglist = "+1#include -1#noinclude +2#all -2#sender 0#replyto +3#followup ";
    for arg in (args)
      let a = arg;
      let value = "";
      const eq = index(a, "=");
      if (eq)
        value = a[eq + 1..$];
        a = a[1..eq - 1];
      endif
      const i = index(flaglist, "#" + a);
      if (typeof(a) != TYPE_STR || i < 3)
        player:tell("Unrecognized answer/reply option:  ", a);
        return 0;
      endif
      if (i != rindex(flaglist, "#" + a))
        player:tell("Ambiguous answer/reply option:  ", a);
        return 0;
      endif
      const digit = index("0123456789", flaglist[i - 1]) - 1;
      if (digit)
        if (value)
          player:tell("Flag does not take a value:  ", a);
          return 0;
        endif
        const f = {"include", "all", "followup"}[digit];
        flags = flaglist[i - 2] == "+" ? setadd(flags, f) | setremove(flags, f);
        f == "all" && (flags = setremove(flags, "followup"));
      else
        const recipients = value ? this:parse_recipients({}, $string_utils:explode(value), "replyto flag:  ") | {};
        !value || recipients && (reply_to = recipients);
      endif
    endfor
    return {flags, reply_to};
  endmethod

  verb "reply-to*: replyto*:" (any any any) owner: HACKER flags: "rd"
    "Show or replace the draft Reply-to recipients.";
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    let rt;
    if (args)
      rt = this:parse_recipients({}, args);
      this.replytos[who] = rt;
      this:set_changed(who, true);
    else
      rt = this.replytos[who];
    endif
    player:tell(rt ? "Replies will go to " + $mail_agent:name_list(@this.replytos[who]) + "." | "Reply-to field is empty.");
  endverb

  verb send (none none none) owner: #2 flags: "rd"
    "Send the current draft; delivery commits before notification and session cleanup.";
    let who = this:loaded(player);
    !who && return player:notify(this:nothing_loaded_msg());
    const recipients = this.recipients[who];
    !recipients && return player:notify("Umm... your message isn't addressed to anyone.");
    typeof(this:sending(who)) == TYPE_INT && return player:notify("Again? ... relax... it'll get there eventually.");
    const message = this:message_with_headers(who);
    typeof(message) == TYPE_ERR && return player:notify(tostr(message));
    const version = this.input_versions[player];
    const sending_task = task_id();
    this.sending[who] = sending_task;
    this:set_changed(who, false);
    player:notify("Sending...");
    const result = $mail_agent:raw_send(message, recipients, player);
    who = this:loaded(player);
    const same_session = who && maphaskey(this.input_versions, player) && this.input_versions[player] == version;
    const same_send = same_session && this.sending[who] == sending_task;
    same_send && (this.sending[who] = false);
    const prefix = same_send ? "" | "(prior send) ";
    if (typeof(result) != TYPE_LIST || !result[1])
      player:notify(tostr(prefix, "Mail not sent: ", toliteral(result)));
      same_send && this:set_changed(who, true);
      return;
    endif
    if (length(result) == 1)
      player:notify(prefix + "Mail not actually sent to anyone.");
      same_send && this:set_changed(who, true);
      return;
    endif
    player:notify(tostr(prefix, "Mail actually sent to ", $mail_agent:name_list(@result[2..$])));
    who = this:loaded(player);
    !same_send || !who || !maphaskey(this.input_versions, player) && return;
    this.input_versions[player] != version || this:changed(who) && return;
    if (player.location == this)
      this:done();
    else
      this:kill_session(who);
    endif
  endverb

  verb who (any none none) owner: HACKER flags: "rxd"
    "Resolve recipients for the current draft or supplied address names.";
    let recips;
    if (dobjstr)
      recips = this:parse_recipients({}, args);
      if (!recips)
        return;
      endif
    elseif (caller != player)
      return E_PERM;
    else
      const who = this:loaded(player);
      if (!who)
        player:tell(this:nothing_loaded_msg());
        return;
      endif
      recips = this.recipients[who];
    endif
    const resolve = $mail_agent:resolve_addr(recips, player);
    if (resolve[1])
      player:tell("Bogus addresses:  ", $string_utils:english_list(resolve[1]));
    else
      player:tell(dobjstr ? "Mail to " + $mail_agent:name_list(@recips) + " actually goes to " | "Your mail will actually go to ", $mail_agent:name_list(@resolve[2]));
    endif
  endverb

  verb showlists (any none none) owner: HACKER flags: "rd"
    "Describe visible mailing lists without output pagination.";
    player:tell_lines({"Available aliases:", ""});
    for c in (dobjstr == "all" ? $object_utils:descendants($mail_recipient) | $mail_agent.contents)
      if (c:is_usable_by(player) || c:is_readable_by(player))
        c:look_self();
      endif
    endfor
  endverb

  verb "subsc*ribe" (any at any) owner: HACKER flags: "rd"
    "Direct players to the subscription command.";
    player:tell("This command is obsolete.  Use @subscribe instead.  See `help @subscribe'");
  endverb

  verb "unsubsc*ribe" (any from any) owner: HACKER flags: "rd"
    "Remove controlled recipients from a mailing list forwarding list.";
    if (!iobjstr)
      player:tell("Usage:  ", verb, " [<list-of-people/lists>] from <list>");
      return;
    endif
    const target = $mail_agent:match(iobjstr);
    $mail_agent:match_failed(target, iobjstr) && return;
    const rstrs = dobjstr ? $string_utils:explode(dobjstr) | {"me"};
    const recips = this:parse_recipients({}, rstrs);
    const outcomes = target:delete_forward(@recips);
    if (typeof(outcomes) != TYPE_LIST)
      player:tell(outcomes);
      return;
    endif
    let removed = {};
    for r in [1..length(recips)]
      const e = outcomes[r];
      if (typeof(e) == TYPE_ERR)
        player:tell(verb, " ", recips[r].name, " from ", target.name, ":  ", e == E_INVARG ? "Not on list." | e);
      else
        removed = setadd(removed, recips[r]);
      endif
    endfor
    if (removed)
      player:tell($string_utils:english_list($list_utils:map_arg(2, $string_utils, "pronoun_sub", "%(name) (%#)", removed)), " removed from ", target.name, " (", target, ")");
    endif
  endverb

  method retain_session_on_exit owner: HACKER
    "Retain an active send or an unsaved draft when leaving.";
    const who = args[1];
    return this:ok(who) && (typeof(this:sending(who)) == TYPE_INT || pass(@args));
  endmethod

  method no_littering_msg owner: HACKER
    "recall that this only gets called if :retain_session_on_exit returns true";
    const who = player in this.active;
    return this:ok(who) && !this:changed(who) ? {"Your message is in transit."} | this.(verb);
  endmethod

  method local_editing_info owner: HACKER
    "Return client editing headers and body without wrapping lines.";
    const toline = $mail_agent:name_list(@args[1]);
    const subject = args[2];
    let lines = {"To:       " + toline, "Subject:  " + $string_utils:trim(subject)};
    args[3] && (lines = {@lines, "Reply-to: " + $mail_agent:name_list(@args[3])});
    lines = {@lines, "", @args[4]};
    return {tostr("MOOMail", subject ? "(" + subject + ")" | "-to(" + toline + ")"), lines, "@@sendmail"};
  endmethod
endobject
