object MAIL_RECIPIENT_CLASS [
  import_export_id -> "mail_recipient_class"
]
  name: "Generic Mail Receiving Player"
  parent: PLAYER
  owner: #2
  fertile: true
  readable: true

  property _mail_task (owner: #2, flags: "rc") = 0;
  property current_message (owner: #2, flags: "c") = {0, 0};
  property default_refusal_time (owner: HACKER, flags: "r") = 604800;
  property mail_forward (owner: #2, flags: "rc") = {};
  property mail_lists (owner: #2, flags: "rc") = {};
  property mail_notify (owner: #2, flags: "r") = {{}, {}};
  property mail_options (owner: #2, flags: "rc") = [];
  property mail_refused_msg (owner: HACKER, flags: "rc") = "%N refuses your mail.";
  property message_keep_date (owner: #2, flags: "rc") = 0;
  property messages (owner: #2, flags: "c") = {};
  property messages_going (owner: #2, flags: "c") = {};
  property messages_kept (owner: #2, flags: "rc") = {};
  property page_refused (owner: HACKER, flags: "r") = 0;
  property page_refused_msg (owner: HACKER, flags: "rc") = "%N refuses your page.";
  property refused_actions (owner: HACKER, flags: "r") = {};
  property refused_extra (owner: HACKER, flags: "r") = {};
  property refused_origins (owner: HACKER, flags: "r") = {};
  property refused_until (owner: HACKER, flags: "r") = {};
  property report_refusal (owner: HACKER, flags: "r") = false;
  property spurned_objects (owner: HACKER, flags: "r") = {};
  property whisper_refused_msg (owner: HACKER, flags: "rc") = "%N refuses your whisper.";

  override aliases (owner: #2, flags: "rc") = {"Generic Mail Receiving Player"};
  override help (owner: #2, flags: "rc") = MAIL_HELP;
  override object_size (owner: HACKER, flags: "r") = {71323, 1084848672};

  method mail_forward owner: #2
    "Return forwarding targets or a sender-specific refusal message.";
    const mf = this.(verb);
    typeof(mf) == TYPE_STR && return $string_utils:pronoun_sub(mf, @args);
    return mf;
  endmethod

  method receive_message owner: #2
    ":receive_message(msg,from) => the assigned message number, or 0 when dropped.";
    $perm_utils:controls(caller_perms(), this) || caller == this || return E_PERM;
    if (this:refuses_action(args[2], "mail"))
      return this:mail_refused_msg();
    endif
    if (this:mail_option("no_dupcc", args[1][1], args[1][2]))
      "pass the TEXT versions of who the message is from and to";
      const recipients = setremove($mail_agent:parse_address_field(args[1][3]), this);
      for x in (recipients)
        this:get_current_message(x) && return 0;
      endfor
    endif
    set_task_perms(this.owner);
    let new = this:new_message_num();
    const ncur = new <= 1 ? 0 | min(this:current_message(this), new);
    this:set_current_message(this, ncur);
    new = max(new, ncur + 1);
    this.messages = {@this.messages, {new, args[1]}};
    return new;
  endmethod

  method display_message owner: #2
    ":display_message(preamble,msg) --- prints msg to player.";
    const vb = this._mail_task == task_id() || caller == $mail_editor ? "notify_lines_suspended" | "tell_lines_suspended";
    const preamble = args[1];
    player:(vb)({@typeof(preamble) == TYPE_LIST ? preamble | {preamble}, @args[2], "--------------------------"});
  endmethod

  method "parse_message_seq from_msg_seq %from_msg_seq to_msg_seq %to_msg_seq subject_msg_seq body_msg_seq kept_msg_seq unkept_msg_seq display_seq_headers display_seq_full messages_in_seq list_rmm new_message_num length_num_le length_date_le length_date_gt length_all_msgs exists_num_eq msg_seq_to_msg_num_list msg_seq_to_msg_num_string rm_message_seq undo_rmm expunge_rmm renumber keep_message_seq set_message_body_by_index message_body_by_index" owner: #2
    "Message-sequence and folder operations delegate to $mail_agent when the caller is the";
    "mail agent itself or controls this player.  See the corresponding routines there.";
    if (caller == $mail_agent || $perm_utils:controls(caller_perms(), this))
      set_task_perms(this.owner);
      return $mail_agent:(verb)(@args);
    endif
    return E_PERM;
  endmethod

  method msg_summary_line owner: HACKER
    "Format a message summary through the mail agent.";
    return $mail_agent:msg_summary_line(@args);
  endmethod

  method msg_text owner: #2
    ":msg_text(@msg) => list of strings to display for this player.";
    return $mail_agent:to_text(@args);
  endmethod

  method notify_mail owner: #2
    ":notify_mail(from,recipients[,msgnums])";
    "Used by $mail_agent:raw_send to notify this player about mail sent from <from> to";
    "<recipients>.  <msgnums>, if given, gives the message numbers assigned.";
    $object_utils:connected(this) || return;
    caller in {this, $mail_agent} || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const {from, recipients, ?msgnums = {}} = args;
    const from_name = $mail_agent:name(from);
    const t = this in recipients;
    if (t && length(msgnums) >= t && msgnums[t])
      const namelist = $string_utils:english_list($list_utils:map_arg($mail_agent, "name", setremove(recipients, this)), "");
      this:notify(tostr("You have new mail (", msgnums[t], ") from ", from_name, namelist ? " which was also sent to " + namelist | "", "."));
      this:mail_option("expert") || this:notify(tostr("Type `help mail' for info on reading it."));
      return;
    endif
    const namelist = $string_utils:english_list({@t ? {"You"} | {}, @$list_utils:map_arg($mail_agent, "name", setremove(recipients, this))}, "");
    this:tell(tostr(namelist, length(recipients) == 1 ? " has" | " have", " just been sent new mail by ", from_name, "."));
  endmethod

  method current_message owner: #2
    ":current_message([recipient]) => current message number, or 0 when unknown.";
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    !args || args[1] == this && return this.current_message[1];
    const a = $list_utils:assoc(args[1], this.current_message);
    return a ? a[2] | 0;
  endmethod

  method get_current_message owner: #2
    ":get_current_message([recipient]) => {msg_num, last_read_date}, or 0 when unknown.";
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    if (!args || args[1] == this)
      if (length(this.current_message) < 2)
        "Whoops, this got trashed---fix it up!";
        this.current_message = {0, time(), @this.current_message};
      endif
      return this.current_message[1..2];
    endif
    const a = $list_utils:assoc(args[1], this.current_message);
    return a ? a[2..3] | 0;
  endmethod

  method set_current_message owner: #2
    ":set_current_message(recipient[,number[,date]]) => new {number,last-read-date} pair.";
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    const {recip, ?number = E_NONE, ?date = 0, ?force = 0} = args;
    const cm = this.current_message;
    if (recip == this)
      this.current_message[2] = max(date, cm[2]);
      number != E_NONE && (this.current_message[1] = number);
      return this.current_message[1..2];
    endif
    const i = $list_utils:iassoc(recip, cm);
    if (!i)
      const entry = {recip, number == E_NONE ? 0 | number, date};
      this.current_message = {@cm, entry};
      return entry[2..3];
    endif
    if (force)
      "`force' is assumed to come from `@unread'";
      this.current_message[i] = {recip, number, date};
    else
      this.current_message[i] = {recip, number == E_NONE ? cm[i][2] | number, max(date, cm[i][3])};
    endif
    return this.current_message[i][2..3];
  endmethod

  method make_current_message owner: #2
    ":make_current_message(recipient[,index]) -- start a current-message record.";
    const recip = args[1];
    const cm = this.current_message;
    const i = length(args) > 1 ? max(2, min(args[2], length(cm))) | 0;
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    recip == this && return;
    const j = $list_utils:iassoc(recip, cm);
    if (!j)
      this.current_message = listappend(cm, {recip, 0, 0}, @i ? {i} | {});
      return;
    endif
    if (i)
      if (j < i)
        this.current_message = {@cm[1..j - 1], @cm[j + 1..i], cm[j], @cm[i + 1..$]};
      elseif (j > i + 1)
        this.current_message = {@cm[1..i], cm[j], @cm[i + 1..j - 1], @cm[j + 1..$]};
      endif
    endif
  endmethod

  method kill_current_message owner: #2
    ":kill_current_message(recipient) => true iff the record was removed.";
    caller == this || $perm_utils:controls(caller_perms(), this) || raise(E_PERM);
    const recip = args[1];
    recip == this && return false;
    const cm = this.current_message;
    const i = $list_utils:iassoc(recip, cm);
    i || return false;
    this.current_message = listdelete(cm, i);
    return true;
  endmethod

  method current_folder owner: #2
    ":current_folder() => default folder to use, always an object, usually `this'";
    set_task_perms(caller_perms());
    !this:mail_option("sticky") && return this;
    const folder = this.current_folder;
    return typeof(folder) == TYPE_OBJ && valid(folder) ? folder | this;
  endmethod

  method set_current_folder owner: #2
    "Set the preferred folder with caller authority.";
    set_task_perms(caller_perms());
    return this.current_folder = args[1];
  endmethod

  method parse_folder_spec owner: #2
    ":parse_folder_spec(verb,args,expected_preposition[,allow_trailing_args_p])";
    " => {folder, msg_seq_args, trailing_args}";
    set_task_perms(caller_perms());
    const folder = this:current_folder();
    !prepstr && return {folder, args[2], {}};
    const vname = args[1];
    const words = args[2];
    const prep = args[3];
    const extra = {@args, 0}[4];
    const p = prepstr in words;
    if (prepstr != prep)
      extra && !index(prepstr, " ") && return {folder, words[1..p - 1], words[p..$]};
      player:tell("Usage:  ", vname, " [<message numbers>] [", prep, " <folder/list-name>]");
    elseif (!(p < length(words) && words[p + 1]))
      player:tell(vname, " ", $string_utils:from_list(words, " "), " WHAT?");
    else
      const fname = words[p + 1];
      const target = $mail_agent:match_recipient(fname, this);
      if ($mail_agent:match_failed(target, fname))
      else
        return {target, words[1..p - 1], words[p + 2..$]};
      endif
    endif
    return 0;
  endmethod

  method parse_mailread_cmd owner: #2
    ":parse_mailread_cmd(verb,args,default,prep[,trailer])";
    "  handles `VERB message_seq [PREP folder ...]'";
    "  returns {recipient object, message_seq, current_msg, \"...\"} or 0";
    set_task_perms(caller_perms());
    const pfs = this:parse_folder_spec(@listdelete(args, 3));
    !pfs && return 0;
    const default = args[3];
    const prep = args[4];
    const extra = {@args, 0}[5];
    const folder = pfs[1];
    const cur = this:get_current_message(folder) || {0};
    const snapshot = `folder:messages_in_seq({1, folder:length_all_msgs() + 1}) ! ANY => E_PERM';
    if (typeof(snapshot) != TYPE_LIST)
      player:tell($mail_agent:name(folder), " is not readable by you.");
      return 0;
    endif
    let pms = folder:parse_message_seq(pfs[2], @cur);
    !this:_mail_selection_unchanged(folder, snapshot) && return 0;
    if (typeof(pms) == TYPE_LIST)
      const rest = {@listdelete(pms, 1), @pfs[3]};
      if (!extra && rest)
        player:tell("I don't understand `", rest[1], "'");
        return 0;
      endif
      pms[1] && return {folder, pms[1], cur, rest};
      const used = length(pfs[2]) + 1 - length(pms);
      if (used)
        pms = "%f %<has> no `" + $string_utils:from_list(pfs[2][1..used], " ") + "' messages.";
      else
        pms = folder:parse_message_seq(default, @cur);
        !this:_mail_selection_unchanged(folder, snapshot) && return 0;
        typeof(pms) == TYPE_LIST && return {folder, pms[1], cur, rest};
      endif
    elseif (typeof(pms) == TYPE_ERR)
      player:tell($mail_agent:name(folder), " is not readable by you.");
      !$object_utils:isa(folder, $mail_recipient) && player:tell("Use * to indicate a non-player mail recipient.");
      return 0;
    endif
    let subst;
    if (folder == this)
      subst = {{"%f's", "Your"}, {"%f", "You"}, {"%<has>", "have"}};
    elseif (is_player(folder))
      subst = {{"%f", folder.name}, {"%<has>", $gender_utils:get_conj("has", folder)}};
    else
      subst = {{"%f", $mail_agent:name(folder)}, {"%<has>", "has"}};
    endif
    player:tell($string_utils:substitute(pms, {@subst, {"%%", "%"}}));
    return 0;
  endmethod

  verb "@mail" (any any any) owner: #2 flags: "rxd"
    "@mail <msg-sequence>                --- as in help @mail";
    "@mail <msg-sequence> on <recipient> --- shows mail on mailing list or player.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const p = this:parse_mailread_cmd("@mail", args, this:mail_option("@mail") || $mail_agent.("player_default_@mail"), "on");
    p || return;
    const folder = p[1];
    this:set_current_folder(folder);
    const msg_seq = p[2];
    const seq_size = $seq_utils:size(msg_seq);
    seq_size != 1 && player:notify(tostr(seq_size, " messages", folder == this ? "" | " on " + $mail_agent:name(folder), ":"));
    folder:display_seq_headers(msg_seq, @p[3]);
  endverb

  verb "@read @peek" (any any any) owner: #2 flags: "rxd"
    "@read <msg>...                  -- as in help @read";
    "@read <msg>... on *<recipient>  -- reads messages on recipient.";
    "@peek ...                       -- like @read, but don't set current message";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const p = this:parse_mailread_cmd("@read", args, "", "on");
    p || return;
    const folder = p[1];
    this:set_current_folder(folder);
    const msg_seq = p[2];
    const seq_size = $seq_utils:size(msg_seq);
    this._mail_task = task_id();
    const cur = folder:display_seq_full(msg_seq, tostr("Message %d", folder == this ? "" | " on " + $mail_agent:name(folder), ":"));
    if (cur && verb != "@peek")
      this:set_current_message(folder, @cur);
    endif
  endverb

  verb "@next @prev" (any any any) owner: #2 flags: "rd"
    "Read a relative message offset in the selected folder.";
    set_task_perms(player.owner);
    const n = toint(dobjstr);
    if (dobjstr && !n)
      player:notify(tostr("Usage:  ", verb, " [<number>] [on <recipient>]"));
      return;
    endif
    if (dobjstr)
      this:("@read")(tostr(verb[2..5], n), @listdelete(args, 1));
    else
      this:("@read")(verb[2..5], @args);
    endif
  endverb

  verb "@rmm*ail" (any any any) owner: #2 flags: "rd"
    "@rmm <message-sequence> [from <recipient>].   Use @unrmm if you screw up.";
    " Beware, though.  @unrmm can only undo the most recent @rmm.";
    set_task_perms(player);
    const p = this:parse_mailread_cmd("@rmm", args, "cur", "from");
    if (!p)
      return;
    endif
    const snapshot = p[1]:messages_in_seq({1, p[1]:length_all_msgs() + 1});
    if (!prepstr && p[1] != this && !$command_utils:yes_or_no("@rmmail from " + $mail_agent:name(p[1]) + ".  Continue?"))
      player:notify("@rmmail aborted.");
      return;
    endif
    !this:_mail_selection_unchanged(p[1], snapshot) && return;
    const folder = p[1];
    this:set_current_folder(folder);
    const e = folder:rm_message_seq(p[2]);
    if (typeof(e) == TYPE_ERR)
      player:notify(tostr($mail_agent:name(folder), ":  ", e));
      return;
    endif
    const n = $seq_utils:size(p[2]);
    const count = n == 1 ? "." | tostr(" (", n, " messages).");
    const fname = folder == this ? "" | " from " + $mail_agent:name(folder);
    player:notify(tostr("Deleted ", e, fname, count));
  endverb

  verb "@renumber" (any none none) owner: #2 flags: "rd"
    "Renumber an authorized mailbox and update this player's cursor.";
    set_task_perms(player);
    let folder;
    if (!dobjstr)
      folder = this:current_folder();
    else
      folder = $mail_agent:match_recipient(dobjstr);
      $mail_agent:match_failed(folder, dobjstr) && return;
    endif
    const cur = this:current_message(folder);
    const fname = $mail_agent:name(folder);
    const h = folder:renumber(cur);
    if (typeof(h) == TYPE_ERR)
      player:notify(tostr(h));
      return;
    endif
    if (!h[1])
      player:notify(tostr("No messages on ", fname, "."));
      return;
    endif
    player:notify(tostr("Messages on ", fname, " renumbered 1-", h[1], "."));
    this:set_current_folder(folder);
    if (h[2] && this:set_current_message(folder, h[2]))
      player:notify(tostr("Current message is now ", h[2], "."));
    endif
  endverb

  verb "@unrmm*ail" (any any any) owner: #2 flags: "rd"
    "@unrmm [on <recipient>]  -- undoes the previous @rmm on that recipient.";
    set_task_perms(player);
    const p = this:parse_folder_spec("@unrmm", args, "on");
    p || return;
    const what = $string_utils:from_list(p[2], " ");
    const keep = what && index("keep", what) == 1;
    let do;
    if (!what || keep)
      do = "undo_rmm";
    elseif (index("expunge", what) == 1)
      do = "expunge_rmm";
    elseif (index("list", what) == 1)
      do = "list_rmm";
    else
      player:notify(tostr("Usage:  ", verb, " [expunge|list] [on <recipient>]"));
      return;
    endif
    const folder = p[1];
    this:set_current_folder(folder);
    const msg_seq = folder:(do)(@keep ? {keep} | {});
    if (msg_seq)
      if (do == "undo_rmm")
        player:notify(tostr($seq_utils:size(msg_seq), " messages restored to ", $mail_agent:name(folder), "."));
        folder:display_seq_headers(msg_seq, 0);
      else
        player:notify(tostr(msg_seq, " zombie message", msg_seq == 1 ? " " | "s ", do == "expunge_rmm" ? "expunged from " | "on ", $mail_agent:name(folder), "."));
      endif
      return;
    endif
    if (typeof(msg_seq) == TYPE_ERR)
      player:notify(tostr($mail_agent:name(folder), ":  ", msg_seq));
      return;
    endif
    player:notify(tostr("No messages to ", do == "expunge_rmm" ? "expunge from " | "restore to ", $mail_agent:name(folder)));
  endverb

  verb "@send" (any any any) owner: #2 flags: "rxd"
    "Start or resume composition, with an optional inline subject.";
    let words = args;
    if (words && words[1] == "to")
      words = listdelete(words, 1);
    endif
    let subject = {};
    for a in (words)
      const i = index(a, "=");
      if (i > 3 && index("subject", a[1..i - 1]) == 1)
        words = setremove(words, a);
        a[1..i] = "";
        subject = {a};
      endif
    endfor
    $mail_editor:invoke(words, verb, @subject);
  endverb

  verb "@answer @repl*y" (any any any) owner: #2 flags: "rd"
    "@answer <msg> [on *<recipient>] [<flags>...]";
    set_task_perms(valid(caller_perms()) ? caller_perms() | player);
    const p = this:parse_mailread_cmd(verb, args, "cur", "on", 1);
    p || return;
    if ($seq_utils:size(p[2]) != 1)
      player:notify("You can only answer *one* message at a time.");
      return;
    endif
    const flags_replytos = $mail_editor:check_answer_flags(@p[4]);
    if (TYPE_LIST != typeof(flags_replytos))
      player:notify_lines({tostr("Usage:  ", verb, " [message-# [on <recipient>]] [flags...]"), "where flags include any of:", "  all        reply to everyone", "  sender     reply to sender only", "  include    include the original message in your reply", "  noinclude  don't include the original in your reply"});
      return;
    endif
    this:set_current_folder(p[1]);
    $mail_editor:invoke(2, verb, p[1]:messages_in_seq(p[2])[1][2], @flags_replytos);
  endverb

  verb "@forward" (any any any) owner: #2 flags: "rxd"
    "@forward <msg> [on *<recipient>] to <recipient> [<recipient>...]";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const p = this:parse_mailread_cmd(verb, args, "", "on", 1);
    if (!p)
      return;
    endif
    const sequence = p[2];
    if ($seq_utils:size(sequence) != 1)
      player:notify("You can only forward *one* message at a time.");
      return;
    endif
    if (length(p[4]) < 2 || p[4][1] != "to")
      player:notify(tostr("Usage:  ", verb, " [<message>] [on <folder>] to <recip>..."));
      return;
    endif
    let recips = {};
    for rs in (listdelete(p[4], 1))
      const r = $mail_agent:match_recipient(rs);
      $mail_agent:match_failed(r, rs) && return;
      recips = {@recips, r};
    endfor
    const folder = p[1];
    this:set_current_folder(folder);
    const m = folder:messages_in_seq(sequence)[1];
    const msgnum = m[1];
    const msgtxt = m[2];
    const from = msgtxt[2];
    let subject;
    if (msgtxt[4] != " ")
      subject = tostr("[", from, ":  ", msgtxt[4], "]");
    else
      const h = "" in msgtxt;
      if (h && h < length(msgtxt))
        subject = tostr("[", from, ":  `", msgtxt[h + 1][1..min(20, $)], "']");
      else
        subject = tostr("[", from, "]");
      endif
    endif
    const result = $mail_agent:send_message(player, recips, subject, $mail_agent:to_text(@msgtxt));
    if (!result)
      player:notify(tostr(result));
      return;
    endif
    if (result[1])
      player:notify(tostr("Message ", msgnum, @folder == this ? {} | {" on ", $mail_agent:name(folder)}, " @forwarded to ", $mail_agent:name_list(@listdelete(result, 1)), "."));
      return;
    endif
    player:notify("Message not sent.");
  endverb

  verb "@gripe" (any any any) owner: #2 flags: "rd"
    "Compose feedback to the configured gripe recipients.";
    $mail_editor:invoke($gripe_recipients, "@gripe", "@gripe: " + argstr);
  endverb

  verb "@typo @bug @suggest*ion @idea @comment" (any any any) owner: #2 flags: "rd"
    "Send room feedback to its owner, or start composition.";
    const loc = this.location;
    const subject = tostr($string_utils:capitalize(verb[2..$]), ":  ", loc.name, "(", loc, ")");
    this == player || return E_PERM;
    if (argstr)
      const result = $mail_agent:send_message(this, {loc.owner}, subject, argstr);
      if (result && result[1])
        player:notify(tostr("Your ", verb, " sent to ", $mail_agent:name_list(@listdelete(result, 1)), ".  Input is appreciated, as always."));
      else
        player:notify(tostr("Huh?  This room's owner (", loc.owner, ") is invalid?  Tell a wizard..."));
      endif
      return;
    endif
    if (!($object_utils:isa(loc, $room) && loc.free_entry))
      player:notify_lines({tostr("You need to make it a one-liner, i.e., `", verb, " something or other'."), "This room may not let you back in if you go to the Mail Room."});
    elseif ($object_utils:isa(loc, $generic_editor))
      player:notify_lines({tostr("You need to make it a one-liner, i.e., `", verb, " something or other'."), "Sending you to the Mail Room from an editor is usually a bad idea."});
    else
      $mail_editor:invoke({tostr(loc.owner)}, verb, subject);
    endif
    verb == "@bug" && player:notify("For a @bug report, be sure to mention exactly what it was you typed to trigger the error...");
  endverb

  verb "@skip" (any any any) owner: #2 flags: "rd"
    "@skip [*<folder/mailing_list>...]";
    "  Sets your last-read time for the given lists to now.";
    set_task_perms(player);
    const current = this:current_folder();
    for a in (args || {0})
      const folder = a ? $mail_agent:match_recipient(a) | this:current_folder();
      if (a ? $mail_agent:match_failed(folder, a) | 0)
        this:kill_current_message(this:my_match_object(a)) && player:notify("Invalid folder, but found it subscribed anyway.  Removed.");
        continue;
      endif
      const lseq = folder:length_all_msgs();
      const n = this:get_current_message(folder);
      const unread = n ? folder:length_date_gt(n[2]) | lseq;
      this:set_current_message(folder, lseq ? folder:messages_in_seq({lseq, lseq + 1})[1][1] | 0, time());
      player:notify(tostr(unread ? tostr("Ignoring ", unread) | "No", " unread message", unread != 1 ? "s" | "", " on ", $mail_agent:name(folder)));
      if (current == folder)
        this:set_current_folder(this);
      endif
    endfor
  endverb

  verb "@subscribe*-quick @unsubscribed*-quick" (any any any) owner: #2 flags: "rd"
    "@subscribe *<folder/mailing_list> [with notification] [before|after *<folder>]";
    "  causes you to be notified when new mail arrives on this list";
    "@subscribe";
    "  just lists available mailing lists.";
    "@unsubscribed";
    "  prints out available mailing lists you aren't already subscribed to.";
    "@subscribe-quick and @unsubscribed-quick";
    "  prints out same as above except without mail list descriptions, just names.";
    set_task_perms(player);
    let vname = verb;
    let quick = false;
    const qi = index(vname, "-q");
    if (qi)
      vname = vname[1..qi - 1];
      quick = true;
    endif
    const fname = {@args, 0}[1];
    if (!fname)
      const ml = $list_utils:slice(this.current_message[3..$]);
      const all_mlists = {@$mail_agent.contents, @this.mail_lists};
      for c in (all_mlists)
        if (!valid(c))
          continue;
        endif
        if (c:is_usable_by(this) || c:is_readable_by(this) && (vname != "@unsubscribed" || !(c in ml)))
          c:look_self(quick);
        endif
      endfor
      player:notify(tostr("-------- end of ", vname, " -------"));
      return;
    endif
    if (vname == "@unsubscribed")
      player:notify("@unsubscribed does not take arguments.");
      return;
    endif
    const folder = $mail_agent:match_recipient(fname);
    $mail_agent:match_failed(folder, fname) && return;
    if (folder == this)
      player:notify("You don't need to @subscribe to yourself");
      return;
    elseif ($object_utils:isa(folder, $mail_recipient) ? !folder:is_readable_by(this) | !$perm_utils:controls(this, folder))
      player:notify("That mailing list is not readable by you.");
      return;
    endif
    let notification = this in folder.mail_notify;
    let i = 0;
    let beforeafter = 0;
    let words = args;
    while (length(words) >= 2)
      if (length(words) < 3)
        player:notify(words[2] + " what?");
        return;
      endif
      if (words[2] in {"with", "without"})
        const wants = words[2] == "with";
        if (index("notification", words[3]) != 1)
          player:notify(tostr("with ", words[3], "?"));
          return;
        endif
        if (!$object_utils:isa(folder, $mail_recipient))
          player:notify(tostr("You cannot use ", verb, " to change mail notification from a non-$mail_recipient."));
        elseif (!wants == !notification)
        elseif (wants)
          if (this in folder:add_notify(this))
            notification = 1;
          else
            player:notify("This mail recipient does not allow immediate notification.");
          endif
        else
          folder:delete_notify(this);
          notification = 0;
        endif
      elseif (words[2] in {"before", "after"})
        if (beforeafter)
          player:notify(words[2] == beforeafter ? tostr("two `", beforeafter, "'s?") | "Only use one of `before' or `after'");
          return;
        endif
        const other = $mail_agent:match_recipient(words[3]);
        $mail_agent:match_failed(other, words[3]) && return;
        if (other == this)
          i = 2;
        else
          const idx = $list_utils:iassoc(other, this.current_message);
          if (!idx)
            player:notify(tostr("You aren't subscribed to ", $mail_agent:name(other), "."));
            return;
          endif
          i = idx;
        endif
        beforeafter = words[2];
        i = i - (beforeafter == "before" ? 1 | 0);
        if (this:mail_option("rn_order") != "fixed")
          player:notify("Warning:  Do `@mail-option rn_order=fixed' if you do not want your @rn listing reordered when you next login.");
        endif
      endif
      words = {@words[1], @words[4..$]};
    endwhile
    this:make_current_message(folder, @i ? {i} | {});
    const len = folder:length_all_msgs();
    player:notify(tostr($mail_agent:name(folder), " has ", len, " message", len == 1 ? "" | "s", ".", notification ? "  You will be notified immediately when new messages are posted." | "  Notification of new messages will be printed when you connect."));
    this:set_current_folder(folder);
  endverb

  method mail_catch_up owner: #2
    "Refresh readable subscriptions and order them without budget-driven commits.";
    set_task_perms(caller == this ? this.owner | caller_perms());
    this:set_current_folder(this);
    let dates = {};
    let new_cm = {};
    let head = {};
    const sort = this:mail_option("rn_order") || "read";
    for n in (this.current_message)
      if (typeof(n) != TYPE_LIST)
        head = {@head, n};
        continue;
      endif
      const folder = n[1];
      if (!($object_utils:isa(folder, $mail_recipient) && folder:is_readable_by(this)))
        continue;
      endif
      if (n[3] < folder.last_msg_date)
        const i = folder:length_date_le(n[3]);
        n[2] = i ? folder:messages_in_seq(i)[1] | 0;
      endif
      if (sort == "fixed")
        new_cm = {n, @new_cm};
      elseif (sort == "send")
        const j = $list_utils:find_insert(dates, folder.last_msg_date - 1);
        dates = listinsert(dates, folder.last_msg_date, j);
        new_cm = listinsert(new_cm, n, j);
      else
        new_cm = listappend(new_cm, n, $list_utils:iassoc_sorted(n[3] - 1, new_cm, 3));
      endif
    endfor
    this.current_message = {@head, @$list_utils:reverse(new_cm)};
  endmethod

  verb "@rn check_mail_lists @subscribed @rn-full" (none none none) owner: #2 flags: "rxd"
    "List subscriptions or unread activity with caller authority.";
    set_task_perms(caller == this ? this.owner | caller_perms());
    let which = {};
    const cm = this.current_message;
    const scan = verb == "@rn" || verb == "@rn-full" ? {{this, @cm[1..2]}, @cm[3..$]} | cm[3..$];
    const all = verb == "@subscribed";
    const fast = this:mail_option("fast_check") && verb != "@rn-full";
    for n in (scan)
      const rcpt = n[1];
      if (rcpt == $news)
      elseif ($mail_agent:is_recipient(rcpt))
        let nmsgs;
        if (fast)
          if (rcpt == this)
            const m = this.messages;
            nmsgs = m && m[length(m)][2][1] > n[3] ? $maxint | 0;
          else
            try
              nmsgs = n[1].last_msg_date > n[3] ? $maxint | 0;
            except (E_PERM, E_PROPNF)
              player:notify(tostr("Bogus recipient ", rcpt, " removed from .current_message."));
              this.current_message = setremove(this.current_message, n);
              nmsgs = 0;
            endtry
          endif
        else
          nmsgs = n[1]:length_date_gt(n[3]);
        endif
        if (nmsgs || all)
          which = {@which, {n[1], nmsgs}};
        endif
      else
        player:notify(tostr("Bogus recipient ", rcpt, " removed from .current_message."));
        this.current_message = setremove(this.current_message, n);
      endif
    endfor
    if (which)
      player:notify(tostr(verb == "@subscribed" ? "You are subscribed to the following" | "There is new activity on the following", length(which) > 1 ? " lists:" | " list:"));
      for w in (which)
        const name = w[1] == this ? " me" | $mail_agent:name(w[1]);
        player:notify(tostr($string_utils:left("    " + name, 40), " ", w[2] == $maxint ? "has" | w[2], " new message", w[2] == 1 ? "" | "s"));
      endfor
      if (verb != "check_mail_lists")
        player:notify("-- End of listing");
      endif
    elseif (verb == "@rn" || verb == "@rn-full")
      player:notify("No new activity on any of your lists.");
    elseif (verb == "@subscribed")
      player:notify("You aren't subscribed to any mailing lists.");
    endif
    return which;
  endverb

  method mail_option owner: #2
    ":mail_option(name) => the value of the specified mail option.";
    if (caller in {this, $mail_editor, $mail_agent} || $perm_utils:controls(caller_perms(), this))
      return $mail_options:get(this.mail_options, args[1]);
    endif
    return E_PERM;
  endmethod

  verb "@unsub*scribe" (any any any) owner: #2 flags: "rd"
    "@unsubscribe [*<folder/mailing_list> ...]";
    "entirely removes the record of your current message for the named folders,";
    "indicating your disinterest in anything that might appear there in the future.";
    set_task_perms(player);
    let unsubscribed = {};
    const current = this:current_folder();
    for a in (args || {0})
      let folder;
      if (a != 0)
        folder = $mail_agent:match_recipient(a);
        folder == $failed_match && (folder = this:my_match_object(a));
      else
        folder = current;
      endif
      if (!valid(folder))
        if (this:kill_current_message(folder))
          player:notify("Invalid folder, but found it subscribed anyway.  Removed.");
        else
          $mail_agent:match_failed(folder, a);
        endif
      elseif (folder == this)
        player:notify(tostr("You can't ", verb, " yourself."));
      elseif (!this:kill_current_message(folder))
        player:notify(tostr("You weren't subscribed to ", $mail_agent:name(folder)));
        if ($object_utils:isa(folder, $mail_recipient))
          const result = folder:delete_notify(this);
          typeof(result) == TYPE_LIST && result[1] == this && player:notify("Removed you from the mail notifications list.");
        endif
      else
        unsubscribed = {@unsubscribed, folder};
        $object_utils:isa(folder, $mail_recipient) && folder:delete_notify(this);
      endif
    endfor
    if (unsubscribed)
      player:notify(tostr("Forgetting about ", $string_utils:english_list($list_utils:map_arg($mail_agent, "name", unsubscribed))));
      current in unsubscribed && this:set_current_folder(this);
    endif
  endverb

  verb "@@sendmail" (any any any) owner: #2 flags: "rd"
    "Syntax: @@sendmail";
    "This is intended for use with client editors.  You probably don't want to try using this command manually.";
    "Reads a formatted mail message, extracts recipients, subject line and/or reply-to header and sends message without going to the mailroom.  Example:";
    "";
    "@@send";
    "To: Rog (#4292)";
    "Subject: random";
    "";
    "first line";
    "second line";
    ".";
    "";
    "Currently, header lines must have the same format as in an actual message.";
    set_task_perms(player);
    if (args)
      player:notify(tostr("The ", verb, " command takes no arguments."));
      $command_utils:read_lines();
      return;
    endif
    if (this != player)
      player:notify(tostr("You can't use ", this.pp, " ", verb, " verb."));
      $command_utils:read_lines();
      return;
    endif
    const msg = $command_utils:read_lines();
    const end_head = "" in msg || length(msg) + 1;
    let from = this;
    let subject = "";
    let replyto = "";
    let rcpts = {};
    const body = msg[end_head + 1..$];
    for i in [1..end_head - 1]
      const line = msg[i];
      if (index(line, "Subject:") == 1)
        subject = $string_utils:trim(line[9..$]);
      elseif (index(line, "To:") == 1)
        rcpts = $mail_agent:parse_address_field(line);
        if (!rcpts)
          player:notify("No recipients found in To: line");
          return;
        endif
      elseif (index(line, "Reply-to:") == 1)
        replyto = $mail_agent:parse_address_field(line);
        if (!replyto && $string_utils:trim(line[10..$]))
          player:notify("No address found in Reply-to: line");
          return;
        endif
      elseif (index(line, "From:") == 1)
        from = $mail_agent:parse_address_field(line);
        if (!from)
          player:notify("No sender found in From: line");
          return;
        endif
        if (length(from) > 1)
          player:notify("Multiple senders?");
          return;
        endif
        from = from[1];
      else
        const colon = index(line, ":");
        if (colon)
          player:notify(tostr("Unknown header \"", line[1..colon], "\""));
        else
          player:notify("Blank line must separate headers from body.");
        endif
        return;
      endif
    endfor
    if (!rcpts)
      player:notify("No To: line found.");
      return;
    endif
    if (!(subject || body))
      player:notify("Blank message not sent.");
      return;
    endif
    player:notify("Sending...");
    const result = $mail_agent:send_message(from, rcpts, replyto ? {subject, replyto} | subject, body);
    const e = typeof(result) == TYPE_LIST ? result[1] | result;
    if (e)
      if (length(result) == 1)
        player:notify("Mail actually went to no one.");
      else
        player:notify(tostr("Mail actually went to ", $mail_agent:name_list(@listdelete(result, 1)), "."));
      endif
      return;
    endif
    player:notify(tostr(typeof(e) == TYPE_ERR ? e | "Bogus recipients:  " + $string_utils:from_list(result[2])));
    player:notify("Mail not sent.");
  endverb

  verb "@keep-m*ail @keepm*ail" (any any any) owner: #2 flags: "rd"
    "@keep-mail [<msg-sequence>|none] [on <recipient>]";
    "marks the indicated messages as `kept'.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    if (!args)
      player:notify("Usage:  @keep-mail [<msg-sequence>|none] [on <recipient>]");
      return;
    endif
    if (args[1] == "none")
      const spec = this:parse_folder_spec(verb, listdelete(args, 1), "on", 0);
      !spec && return;
      if (spec[2])
        player:notify(tostr(verb, " <message-sequence> or `none', but not both."));
        return;
      endif
      const folder = spec[1];
      this:set_current_folder(folder);
      const cleared = folder:keep_message_seq({});
      if (cleared)
        player:notify(tostr("Messages on ", $mail_agent:name(folder), " are no longer marked as kept."));
      else
        player:notify(tostr(cleared));
      endif
      return;
    endif
    const p = this:parse_mailread_cmd(verb, args, "", "on");
    !p && return;
    if (p[1] != this)
      player:notify(tostr(verb, " can only be used on your own mail collection."));
      return;
    endif
    this:set_current_folder(p[1]);
    const msg_seq = p[2];
    const e = p[1]:keep_message_seq(msg_seq);
    if (e)
      player:notify(tostr("Message", match(e, "[.,]") ? "s " | " ", e, " now marked as kept."));
      return;
    endif
    if (typeof(e) == TYPE_ERR)
      player:notify(tostr(e));
      return;
    endif
    const seq_size = $seq_utils:size(msg_seq);
    player:notify(tostr(seq_size == 1 ? "That message is" | "Those messages are", " already marked as kept."));
  endverb

  method my_match_recipient owner: #2
    ":my_match_recipient(string) => matches string against player's private mailing lists.";
    let str = args[1];
    !str && return $nothing;
    if (str[1] == "*")
      str = str[2..$];
    endif
    return $string_utils:match(str, this.mail_lists, "aliases");
  endmethod

  method expire_old_messages owner: #2
    "Remove and expunge eligible old messages with owner authority.";
    set_task_perms(caller_perms());
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const seq = this:expirable_msg_seq();
    !seq && return 0;
    this:rm_message_seq(seq);
    return this:expunge_rmm();
  endmethod

  method msg_full_text owner: #2
    ":msg_full_text(@msg) => list of strings.";
    "msg is a mail message (in the usual transmission format).";
    "display_seq_full calls this to obtain the actual list of strings to display.";
    "The default is to leave it up to the player how it is displayed.";
    return player:msg_text(@args);
  endmethod

  verb "@resend" (any any any) owner: #2 flags: "rd"
    "@resend <msg> [on *<recipient>] to <recipient> [<recipient>...]";
    set_task_perms(valid(caller_perms()) ? caller_perms() | player);
    const p = this:parse_mailread_cmd(verb, args, "", "on", 1);
    if (!p)
      return;
    endif
    const sequence = p[2];
    if ($seq_utils:size(sequence) != 1)
      player:notify("You can only resend *one* message at a time.");
      return;
    endif
    if (length(p[4]) < 2 || p[4][1] != "to")
      player:notify(tostr("Usage:  ", verb, " [<message>] [on <folder>] to <recip>..."));
      return;
    endif
    let recips = {};
    for rs in (listdelete(p[4], 1))
      const r = $mail_agent:match_recipient(rs);
      $mail_agent:match_failed(r, rs) && return;
      recips = {@recips, r};
    endfor
    const folder = p[1];
    this:set_current_folder(folder);
    const m = folder:messages_in_seq(sequence)[1];
    const msgnum = m[1];
    const msgtxt = m[2];
    let from;
    let to;
    const forward_style = this:mail_option("resend_forw");
    let pmh;
    let orig_from;
    if (forward_style)
      pmh = $mail_agent:parse_misc_headers(msgtxt, "Reply-To", "Original-Date", "Original-From");
      orig_from = pmh[3][3] || msgtxt[2];
    else
      pmh = $mail_agent:parse_misc_headers(msgtxt, "Reply-To", "Original-Date", "Original-From", "Resent-By", "Resent-To");
      orig_from = pmh[3][3];
      from = $mail_agent:parse_address_field(msgtxt[2])[1];
      to = $mail_agent:parse_address_field(msgtxt[3]);
    endif
    const snapshot = folder:messages_in_seq({1, folder:length_all_msgs() + 1});
    const bogus = pmh[2];
    if (bogus)
      player:notify("Bogus headers stripped from original message:");
      for b in (bogus)
        player:notify("  " + b);
      endfor
      if (!$command_utils:yes_or_no("Continue?"))
        player:notify("Message not resent.");
        return;
      endif
    endif
    !this:_mail_selection_unchanged(folder, snapshot) && return;
    const hdrs = {msgtxt[4], pmh[3][1], {"Original-Date", pmh[3][2] || ctime(msgtxt[1])}, @orig_from ? {{"Original-From", orig_from}} | {}, @pmh[1]};
    let result;
    if (forward_style)
      result = $mail_agent:send_message(player, recips, hdrs, pmh[4]);
    else
      result = $mail_agent:resend_message(player, recips, from, to, hdrs, pmh[4]);
    endif
    if (!result)
      player:notify(tostr(result));
    elseif (result[1])
      player:notify(tostr("Message ", msgnum, @folder == this ? {} | {" on ", $mail_agent:name(folder)}, " @resent to ", $mail_agent:name_list(@listdelete(result, 1)), "."));
    else
      player:notify("Message not resent.");
    endif
  endverb

  method expirable_msg_seq owner: #2
    "Return a sequence indicating the expirable messages for this player.";
    set_task_perms(caller_perms());
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const curmsg = this:get_current_message(this);
    if (!curmsg)
      "No messages!  Don't even try.";
      return {};
    endif
    const period = this:mail_option("expire") || $mail_agent.player_expire_time;
    if (period <= 0)
      return {};
    endif
    return $seq_utils:remove(this:unkept_msg_seq(), 1 + this:length_date_le(min(time() - period, curmsg[2] - 86400)));
  endmethod

  verb "@nn" (none none none) owner: #2 flags: "rxd"
    "@nn  -- reads the first new message on the first mail_recipient (in .current_message) where new mail exists.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const cm = this.current_message;
    const scan = {{this, @cm[1..2]}, @cm[3..$]};
    for n in (scan)
      if ($mail_agent:is_recipient(n[1]))
        const newmsgs = n[1]:length_date_gt(n[3]);
        if (newmsgs)
          const next = n[1]:length_all_msgs() - newmsgs + 1;
          const folder = n[1];
          this:set_current_folder(folder);
          this._mail_task = task_id();
          const cur = folder:display_seq_full({next, next + 1}, tostr("Message %d", " on ", $mail_agent:name(folder), ":"));
          this:set_current_message(folder, @cur);
          return;
        endif
      else
        player:notify(tostr("Bogus recipient ", n[1], " removed from .current_message."));
        this.current_message = setremove(this.current_message, n);
      endif
    endfor
    player:tell("No News (is good news)");
  endverb

  verb "@unread" (any any any) owner: #2 flags: "rd"
    "@unread <msg> [on *<recipient>]  -- resets last-read-date for recipient to just before the first of the indicated messages.";
    set_task_perms(player);
    const p = this:parse_mailread_cmd("@unread", args, "cur", "on");
    !p && return;
    const folder = p[1];
    this:set_current_folder(folder);
    const msg_seq = p[2];
    const msg_ord = $seq_utils:first(msg_seq);
    const msgdate = folder:messages_in_seq(msg_ord)[2][1] - 1;
    const cm = this:get_current_message(folder);
    if (!cm || cm[2] < msgdate)
      player:notify("Already unread.");
      return;
    endif
    if (folder == this)
      this.current_message[2] = msgdate;
    else
      this:set_current_message(folder, cm[1], min(cm[2], msgdate), 1);
    endif
    folder:display_seq_headers({msg_ord, msg_ord + 1}, cm[1], msgdate);
  endverb

  verb "@refile @copym*ail" (any any any) owner: #2 flags: "rd"
    "@refile/@copym*ail <msg-sequence> [on <recipient>] to <recipient>";
    "@refile will delete the messages from the source folder.  @copym does not.";
    set_task_perms(player);
    const p = this:parse_mailread_cmd("@refile", args, "cur", "on", 1);
    if (!p)
      return;
    endif
    if (length(p[4]) != 2 || p[4][1] != "to")
      player:notify(tostr("Usage:  ", verb, " [<message numbers>] [on <folder>] to <folder>"));
      return;
    endif
    const dest = $mail_agent:match_recipient(p[4][2]);
    if ($mail_agent:match_failed(dest, p[4][2]))
      return;
    endif
    const source = p[1];
    const msg_seq = p[2];
    for m in (source:messages_in_seq(msg_seq))
      const e = dest:receive_message(m[2], source);
      if (typeof(e) != TYPE_INT || e <= 0)
        player:notify(tostr("Copying msg. ", m[1], ":  ", e));
        return;
      endif
    endfor
    const refile = verb == "@refile";
    if (refile)
      const e = source:rm_message_seq(msg_seq);
      typeof(e) == TYPE_ERR && return player:notify(tostr("Copied mail, but could not remove it from ", source, ":  ", e));
    endif
    const n = $seq_utils:size(msg_seq);
    const count = tostr(n, " message", n == 1 ? "" | "s");
    const fname = source == this ? "" | tostr(is_player(source) ? " from " | " from *", source.name, "(", source, ")");
    const suffix = tostr(is_player(dest) ? " to " | " to *", dest.name, "(", dest, ").");
    player:notify(tostr(refile ? "Refiled " | "Copied ", count, fname, suffix));
  endverb

  verb "@quickr*eply @qreply" (any any any) owner: #2 flags: "rd"
    "@qreply <msg> [on *<recipient>] [<flags>...]";
    "like @reply only, as in @qsend, we prompt for the message text using ";
    "$command_utils:read_lines() rather than invoking the $mail_editor.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const p = this:parse_mailread_cmd(verb, args, "cur", "on", 1);
    if (!p)
      return;
    endif
    if ($seq_utils:size(p[2]) != 1)
      player:notify("You can only answer *one* message at a time.");
      return;
    endif
    const flags_replytos = $mail_editor:check_answer_flags("noinclude", @p[4]);
    if (TYPE_LIST != typeof(flags_replytos))
      player:notify_lines({tostr("Usage:  ", verb, " [message-# [on <recipient>]] [flags...]"), "where flags include any of:", "  all        reply to everyone", "  sender     reply to sender only", tostr("  include    include the original message in reply (can't do this for ", verb, ")"), "  noinclude  don't include the original in your reply"});
      return;
    endif
    if ("include" in flags_replytos[1])
      player:notify(tostr("Can't include message on a ", verb));
      return;
    endif
    this:set_current_folder(p[1]);
    const snapshot = p[1]:messages_in_seq({1, p[1]:length_all_msgs() + 1});
    const to_subj = $mail_editor:parse_msg_headers(p[1]:messages_in_seq(p[2])[1][2], flags_replytos[1]);
    !to_subj && return;
    player:notify(tostr("To:       ", $mail_agent:name_list(@to_subj[1])));
    to_subj[2] && player:notify(tostr("Subject:  ", to_subj[2]));
    const replytos = flags_replytos[2];
    replytos && player:notify(tostr("Reply-to: ", $mail_agent:name_list(@replytos)));
    const hdrs = {to_subj[2], replytos || {}};
    player:notify("Enter lines of message:");
    const active = player in $mail_editor.active;
    const message = $command_utils:read_lines_escape(active ? {} | {"@edit"}, {tostr("You are composing mail to ", $mail_agent:name_list(@to_subj[1]), "."), @active ? {} | {"Type `@edit' to take this into the mail editor."}});
    if (typeof(message) == TYPE_ERR)
      player:notify(tostr(message));
      return;
    endif
    !this:_mail_selection_unchanged(p[1], snapshot) && return;
    if (message[1] == "@edit")
      $mail_editor:invoke(1, verb, to_subj[1], @hdrs, message[2]);
      return;
    endif
    if (!message[2])
      player:notify("Blank message not sent.");
      return;
    endif
    const result = $mail_agent:send_message(this, to_subj[1], hdrs, message[2]);
    if (result && result[1])
      player:notify(tostr("Message sent to ", $mail_agent:name_list(@listdelete(result, 1)), "."));
      return;
    endif
    player:notify("Message not sent.");
  endverb

  verb "@mail-all-new*-mail" (none none none) owner: #2 flags: "rxd"
    "@mail-all-new-mail";
    " Prints headers for all new mail on every mail-recipient mentioned in .current_message.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const cm = this.current_message;
    const scan = {{this, @cm[1..2]}, @cm[3..$]};
    this._mail_task = task_id();
    let nomail = true;
    for f in (scan)
      const folder = f[1];
      if (!($object_utils:isa(folder, $player) || $object_utils:isa(folder, $mail_recipient)))
        player:notify(tostr(folder, " is neither a $player nor a $mail_recipient"));
        continue;
      endif
      const flen = folder:length_all_msgs();
      if (typeof(flen) == TYPE_ERR)
        player:notify(tostr($mail_agent:name(folder), " ", flen));
        continue;
      endif
      const msg_seq = $seq_utils:range(folder:length_date_le(f[3]) + 1, flen);
      if (!msg_seq)
        continue;
      endif
      nomail = false;
      const s = $seq_utils:size(msg_seq);
      player:notify("===== " + $string_utils:left(tostr($mail_agent:name(folder), " (", s, " message", s == 1 ? ") " | "s) "), 40, "="));
      folder:display_seq_headers(msg_seq, @f[2..3]);
      player:notify("");
    endfor
    if (nomail)
      player:notify("You don't have any new mail anywhere.");
    else
      player:notify("===== " + $string_utils:left("End of new mail ", 40, "="));
    endif
  endverb

  verb "@read-all-new*-mail @ranm" (any none none) owner: #2 flags: "rxd"
    "@read-all-new-mail [yes]";
    " Prints all new mail on every mail-recipient mentioned in .current_message";
    " Generally this will spam you into next Tuesday.";
    " You will be queried for whether you want your last-read dates updated";
    "   but you can specify \"yes\" on the command line to suppress this.";
    "   If you do so, last-read dates will be updated after each folder read.";
    const cp = caller_perms();
    set_task_perms(valid(cp) ? cp | player);
    const noconfirm = length(args) ? args[1] | 0;
    if (noconfirm && noconfirm != "yes" && noconfirm != "no")
      player:notify("Unexpected argument(s): " + argstr);
      return;
    endif
    const cm = this.current_message;
    const scan = {{this, @cm[1..2]}, @cm[3..$]};
    this._mail_task = task_id();
    let nomail = true;
    let new_cms = {};
    for f in (scan)
      const folder = f[1];
      if (!($object_utils:isa(folder, $player) || $object_utils:isa(folder, $mail_recipient)))
        player:notify(tostr(folder, " is neither a $player nor a $mail_recipient"));
      else
        const flen = folder:length_all_msgs();
        if (typeof(flen) == TYPE_ERR)
          player:notify(tostr($mail_agent:name(folder), " ", flen));
        else
          const msg_seq = $seq_utils:range(folder:length_date_le(f[3]) + 1, flen);
          if (msg_seq)
            nomail = false;
            const s = $seq_utils:size(msg_seq);
            player:notify("===== " + $string_utils:left(tostr($mail_agent:name(folder), " (", s, " message", s == 1 ? ") " | "s) "), 40, "="));
            player:notify("");
            const cur = folder:display_seq_full(msg_seq, tostr("Message %d", folder == this ? "" | " on " + $mail_agent:name(folder), ":"));
            if (cur)
              if (noconfirm == "yes")
                this:set_current_message(folder, @cur);
                this:set_current_folder(folder);
              else
                new_cms = {@new_cms, {folder, @cur}};
              endif
              player:notify("");
            endif
          endif
        endif
      endif
      this._mail_task = task_id();
    endfor
    if (nomail)
      player:notify("You don't have any new mail anywhere.");
      return;
    endif
    player:notify("===== " + $string_utils:left("End of new mail ", 40, "="));
    if (noconfirm ? noconfirm == "yes" | $command_utils:yes_or_no("Mark these messages as read?"))
      for n in (new_cms)
        this:set_current_message(@n);
        this:set_current_folder(n[1]);
      endfor
      player:notify("Last-read-dates updated");
      return;
    endif
    player:notify("Last-read-dates not updated");
  endverb

  verb "@quick*send @qsend" (any any any) owner: #2 flags: "rd"
    "Syntax: @quicksend <recipients(s)> [subj=<text>] [<message>]";
    "Sends the recipients(s) a quick message, wit{out having to go to the mailroom. If there is more than one recipients, place them all in quotes. If the subj contains spaces, place it in quotes.";
    "To put line breaks in the message, use a caret (^).";
    "If no message is given, prompt for lines of message.";
    "Examples:";
    "@quicksend Alice subj=\"Wonderland is neat!\" Have you checked out the Wonderland scenario yet? I think you'd like it!";
    "@quicksend \"Ethel Fred\" Have you seen Lucy around?^--Ricky";
    set_task_perms($object_utils:isa(player, $guest) ? player.owner | player);
    if (!args)
      player:notify(tostr("Usage: ", verb, " <recipients(s)> [subj=<text>] [<message>]"));
      return E_INVARG;
    endif
    if (this != player)
      player:notify(tostr("You can't use ", this.pp, " @quicksend verb."));
      return E_PERM;
    endif
    const recipients = $mail_editor:parse_recipients({}, $string_utils:explode(args[1]));
    !recipients && return;
    let words = args;
    let rest = argstr;
    let subject;
    if (length(words) > 1)
      const eq = index(words[2], "=");
      if (eq && index("subject", words[2][1..eq - 1]) == 1)
        subject = $string_utils:trim(words[2][eq + 1..$]);
        const ws = $string_utils:word_start(rest);
        rest = rest[1..ws[1][2]] + rest[ws[2][2] + 1..$];
        words = listdelete(words, 2);
      else
        subject = "";
      endif
    else
      subject = "";
    endif
    let message;
    if (length(words) > 1)
      const first = rest[1] == "\"" ? length(words[1]) + 4 | length(words[1]) + 2;
      let unbroken = rest[first..$] + "^";
      message = {};
      while (unbroken)
        const i = index(unbroken, "^");
        if (i)
          message = {@message, unbroken[1..i - 1]};
        endif
        unbroken = unbroken[i + 1..$];
      endwhile
    else
      if (!(subject || player:mail_option("nosubject")))
        player:notify("Subject:");
        subject = $command_utils:read();
      endif
      player:notify("Enter lines of message:");
      const active = player in $mail_editor.active;
      message = $command_utils:read_lines_escape(active ? {} | {"@edit"}, {tostr("You are composing mail to ", $mail_agent:name_list(@recipients), "."), @active ? {} | {"Type `@edit' to take this into the mail editor."}});
      if (typeof(message) == TYPE_ERR)
        player:notify(tostr(message));
        return;
      endif
      if (message[1] == "@edit")
        $mail_editor:invoke(1, verb, recipients, subject, {}, message[2]);
        return;
      endif
      if (!(message[2] || subject))
        player:notify("Blank message not sent.");
        return;
      endif
      message = message[2];
    endif
    const result = $mail_agent:send_message(this, recipients, subject, message);
    if (result && result[1])
      player:notify(tostr("Message sent to ", $mail_agent:name_list(@listdelete(result, 1)), "."));
    else
      player:notify("Message not sent.");
    endif
  endverb

  method init_for_core owner: #2
    "Reset mail options during wizard-authorized core extraction.";
    if (caller_perms().wizard)
      pass(@args);
      this.mail_options = [];
    endif
  endmethod

  method confunc owner: #2
    "Check mail, news, and subscriptions during an authorized connection hook.";
    const cp = caller_perms();
    if (valid(cp) && caller != this && !$perm_utils:controls(cp, this) && caller != #0)
      return E_PERM;
    endif
    this:check_mail();
    $news:check();
    this:mail_catch_up();
    this:check_mail_lists();
    pass(@args);
  endmethod

  verb "@add-notify" (any at any) owner: #2 flags: "rd"
    "Ideally, in order for one person to be notified that another person has new mail, both the mail recipient and the notification recipient should agree that this is an OK transfer of information.";
    "Usage:  @add-notify me to player";
    "    Sends mail to player saying that I want to be added to their mail notification property.";
    "Usage:  @add-notify player to me";
    "    Makes sure that player wants to be notified, if so, adds them to my .mail_notify property.  (Deletes from temporary record.)";
    if (this == dobj)
      const target = $string_utils:match_player(iobjstr);
      $command_utils:player_match_failed(target, iobjstr) && return;
      if (this in target.mail_notify[1])
        player:tell("You already receive notifications when ", target.name, " receives mail.");
        return;
      endif
      if (this in target.mail_notify[2])
        player:tell("You already asked to be notified when ", target.name, " receives mail.");
        return;
      endif
      $mail_agent:send_message(player, {target}, "mail notification request", {tostr($string_utils:nn(this), " would like to receive mail notifications when you get mail."), "Please type:", tostr("  @add-notify ", this.name, " to me"), "if you wish to allow this action."});
      player:tell("Notifying ", $string_utils:nn(target), " that you would like to be notified when ", target.ps, " receives mail.");
      target.mail_notify[2] = setadd(target.mail_notify[2], this);
      return;
    endif
    if (this == iobj)
      const target = $string_utils:match_player(dobjstr);
      $command_utils:player_match_failed(target, dobjstr) && return;
      if (target in this.mail_notify[2])
        this.mail_notify[1] = setadd(this.mail_notify[1], target);
        this.mail_notify[2] = setremove(this.mail_notify[2], target);
        player:tell(target.name, " will be notified when you receive mail.");
        return;
      endif
      player:tell("It doesn't look like ", target.name, " wants to be notified when you receive mail.");
      return;
    endif
    player:tell("Usage:  @add-notify me to player");
    player:tell("        @add-notify player to me");
  endverb

  method mail_notify owner: #2
    "Return approved notification recipients, excluding pending requests.";
    if (length(this.mail_notify) > 0 && typeof(this.mail_notify[1]) == TYPE_LIST)
      return this.mail_notify[1];
    endif
    return this.mail_notify;
  endmethod

  verb "@unsend" (any from any) owner: #2 flags: "rd"
    "USAGE: @unsend [message-sequence] from <player>";
    "Attempts to unsend messages you sent to <player>. Per *B:Unsend, messages may not be unsent if they have been read, or if the player has set emself so that mail may not be unsent from em (@mail-option +no_unsend). In addition, mail sent to multiple players may not be unsent unless it can be unsent from each recipient.";
    "";
    "The following message sequences are the only ones allowed:";
    "";
    "  before:<date>    - Strictly before the given date.";
    "  after:<date>     - Strictly after the given date.";
    "  since:<date>     - On or after the given date.";
    "  until:<date>     - On or before the given date.";
    "  subject:<string> - The subject contains the given string.";
    "  body:<string>    - The message body contains the given string.";
    "  last:<number>    - The last <number> messages you sent.";
    "";
    "If you do not specify a sequence, the default sequence stored in @mail-option @unsend will be used.";
    const base = dobjstr || this:mail_option(verb) || $mail_agent.("player_default_@unsend");
    if (player != this)
      player:tell(E_PERM);
      return;
    endif
    let seq = typeof(base) == TYPE_STR ? $string_utils:words(base) | base;
    const who = $string_utils:match_player(iobjstr);
    const fail_msg = "Message(s) were not removed as expected. As per *B:Unsend, I cannot elaborate on why.";
    $command_utils:player_match_failed(who, iobjstr) && return;
    const options_parse = $mail_options:parse({verb, @seq});
    if (typeof(options_parse) == TYPE_STR)
      player:notify(options_parse);
      return;
    endif
    if (who:mail_option("no_unsend") || $object_utils:has_callable_verb(who, "do_unsend") != {$mail_recipient_class})
      player:notify(fail_msg);
      return;
    endif
    "The following loop weeds out `last:#' references, which need to be processed in a specific way.";
    let newseq = {};
    let lastnum = 0;
    for x in (seq)
      if (`x[1..5] == "last:" ! ANY')
        lastnum = toint(x[6..$]);
      else
        newseq = {@newseq, x};
      endif
    endfor
    seq = {"unkept:", tostr("from:", player), @newseq};
    let ok = this:_unsend_selection(who, seq, lastnum);
    if (typeof(ok) != TYPE_LIST)
      player:notify(fail_msg);
      return;
    endif
    const allmsgs = length($seq_utils:tolist(@ok));
    let count = 0;
    let missed = 0;
    let otherpeople = {};
    for position in ($list_utils:reverse($list_utils:range(allmsgs)))
      ok = position == allmsgs ? ok | this:_unsend_selection(who, seq, lastnum);
      if (typeof(ok) != TYPE_LIST || !ok[1])
        break;
      endif
      const x = $seq_utils:tolist(@ok)[$ - missed];
      ok = {x, x + 1};
      const whomail = who.messages;
      let bad = false;
      let possible = {};
      "Check if a message was sent to multiple people and set them up for @unsend, too.";
      const msg = whomail[x][2];
      const recips = $mail_agent:parse_address_field(msg[3]);
      if (recips == {who})
        who:do_unsend(ok);
        "Unsend deliberately clears the undo buffer so withdrawn copies cannot be restored.";
        who.messages_going = {};
        count = count + 1;
        continue;
      endif
      "Require an identical unread, unkept copy at every other recipient before removing any copy.";
      for y in (setremove(recips, who))
        let z;
        let ybad = !is_player(y) || y:mail_option("no_unsend") || $object_utils:has_callable_verb(y, "do_unsend") != {$mail_recipient_class};
        if (!ybad)
          z = this:_unsend_selection(y, {"unkept:"}, 0);
          ybad = typeof(z) != TYPE_LIST || !z[1];
        endif
        if (ybad)
          bad = true;
        else
          const ymail = y.messages;
          let numnum = 0;
          for post in ($seq_utils:tolist(@z))
            if (ymail[post][2] == msg)
              numnum = post;
              break;
            endif
          endfor
          if (!numnum)
            bad = true;
          else
            z = {numnum, numnum + 1};
          endif
        endif
        possible = bad ? {} | {@possible, {y, z}};
        if (bad)
          break;
        endif
      endfor
      if (bad)
        missed = missed + 1;
      else
        for foo in ({{who, ok}, @possible})
          const person = foo[1];
          const person_seq = foo[2];
          person:do_unsend(person_seq);
          "Unsend deliberately clears the undo buffer so withdrawn copies cannot be restored.";
          person.messages_going = {};
          person != who && (otherpeople = setadd(otherpeople, person));
        endfor
        count = count + 1;
      endif
    endfor
    if (!count || count != allmsgs)
      player:notify(fail_msg);
    endif
    count && player:notify(tostr(count, " message", count == 1 ? "" | "s", " unsent."));
    otherpeople && player:notify(tostr("Message(s) were also removed from ", $string_utils:nn(otherpeople), "."));
  endverb

  method _unsend_selection owner: #2
    "Select unkept, unread messages before applying a last-count limit; wizard callers only.";
    caller_perms().wizard || return E_PERM;
    const {recipient, filters, last_count} = args;
    const parsed = recipient:parse_message_seq(filters, @recipient:get_current_message());
    typeof(parsed) != TYPE_LIST && return parsed;
    const first_unread = recipient:length_date_le(recipient:get_current_message()[2]) + 1;
    let selected = $seq_utils:intersection(parsed[1], {first_unread, recipient:length_all_msgs() + 1});
    last_count > 0 && (selected = $seq_utils:lastn(selected, last_count));
    return {selected};
  endmethod

  method do_unsend owner: #2
    ":do_unsend(seq) -> Remove the specified messages. Used by @unsend. Cannot be overridden by players or player classes; @unsend won't bother to call the verb.";
    !caller_perms().wizard && return E_PERM;
    return $mail_agent:rm_message_seq(@args);
  endmethod

  verb "@annotate*mail" (any any any) owner: #2 flags: "rd"
    "@annotate <msg-sequence> [on <recipient>] with \"annotation\"";
    "prefix the specified messages with the given annotation.";
    set_task_perms(player);
    const p = this:parse_mailread_cmd("@annotate", args, "cur", "on", 1);
    if (!p)
      return;
    endif
    if (length(p[4]) != 2 || p[4][1] != "with")
      player:notify(tostr("Usage:  ", verb, " [<message numbers>] [on <folder>] with <annotation>"));
      return;
    endif
    const target = p[1];
    const message_sequence = p[2];
    let annotation = p[4][2..$];
    annotation[1] = tostr("[", player.name, " (", player, "):  ", annotation[1], "]");
    const e = target:annotate_message_seq(annotation, "prepend", message_sequence);
    if (typeof(e) in {TYPE_ERR, TYPE_STR})
      player:notify(tostr("Annotation Failed:  ", e));
      return;
    endif
    const count = $seq_utils:size(message_sequence);
    player:notify(tostr("Annotating ", count, " message", count == 1 ? "" | "s", " on ", $mail_agent:name(target), " with:"));
    player:notify_lines(annotation);
  endverb

  method annotate_message_seq owner: #2
    "Player mailboxes reject annotations.";
    return "Cannot annotate player messages.";
  endmethod

  method check_mail owner: #2
    "Notify the owner about unread mail with caller authority.";
    if (caller == this || $perm_utils:controls(caller_perms(), this))
      const nm = this:length_all_msgs() - this:length_date_le(this:get_current_message()[2]);
      if (nm)
        this:notify(tostr("You have new mail (", nm, " message", nm == 1 ? "" | "s", ").", this:mail_option("expert") ? "" | "  Type 'help mail' for info on reading it."));
      endif
    endif
  endmethod

  method disfunc owner: #2
    "Disconnect hook: clear deleted mail after the base player cleanup.";
    const result = pass(@args);
    typeof(result) == TYPE_ERR && return result;
    return this:expunge_rmm();
  endmethod

  method _mail_selection_unchanged owner: #2
    "Reject mailbox changes or lost read authority after a selector or confirmation commits.";
    const {folder, snapshot} = args;
    set_task_perms(caller_perms());
    const current = `folder:messages_in_seq({1, folder:length_all_msgs() + 1}) ! ANY => E_PERM';
    if (typeof(current) != TYPE_LIST || current != snapshot)
      player:notify("Mail selection changed or is no longer readable. Please repeat the command.");
      return false;
    endif
    return true;
  endmethod

  verb "@ref*use" (any any any) owner: HACKER flags: "rd"
    "Usage: @refuse <actions> [from <player|guests>] [for <duration>].";
    !argstr && return player:tell("@refuse <action(s)> [ from <player> ] [ for <time> ]");
    let parsed = this:parse_refuse_arguments(argstr);
    !parsed && return 0;
    const origin = parsed[1];
    if (typeof(origin) == TYPE_OBJ && origin != $nothing && !is_player(origin))
      return player:tell("You must give the name of some player.");
    endif
    const remaining = max(0, $maxint - time() - 2);
    if (parsed[3] < 0 || parsed[3] > remaining)
      parsed[3] = remaining;
      player:tell("That amount of time is too large. It has been capped at ", $time_utils:english_time(remaining), ".");
    endif
    this:add_refusal(@parsed);
    player:tell("Refusal of ", this:refusal_origin_to_name(origin), " for ", $time_utils:english_time(parsed[3]), " added.");
  endverb

  verb "@unref*use @allow" (any any any) owner: HACKER flags: "rd"
    "Remove selected refusals, or confirm removal of everything. Confirmation reads commit.";
    if (argstr == "everything")
      if ($command_utils:yes_or_no("Do you really want to erase all your refusals?"))
        this:clear_refusals();
        player:tell("OK, they are gone.");
      else
        player:tell("OK, no harm done.");
      endif
      return 0;
    endif
    const parsed = this:parse_refuse_arguments(argstr);
    !parsed && return 0;
    const origins = typeof(parsed[1]) == TYPE_LIST ? parsed[1] | {parsed[1]};
    let count = 0;
    for origin in (origins)
      count = count + this:remove_refusal(origin, parsed[2]);
    endfor
    const suffix = count == 1 && length(origins) == 1 ? "" | "s";
    player:tell(count ? "Refusal" | "You have no such refusal", suffix, count ? " removed." | ".");
  endverb

  verb "@refusals" (none any any) owner: HACKER flags: "rd"
    "List your refusals, or those of the player named after 'for'.";
    let who = player;
    if (iobjstr)
      who = $string_utils:match_player(iobjstr);
      $command_utils:player_match_failed(who, iobjstr) && return 0;
      !$object_utils:has_verb(who, "refusals_text") && return player:tell("That player does not have the refusal facility.");
    endif
    who:remove_expired_refusals();
    player:tell_lines(this:refusals_text(who));
  endverb

  verb "@refusal-r*eporting" (any any any) owner: HACKER flags: "rd"
    "Show or set whether refused actions produce a notification.";
    if (!argstr)
      return player:tell("Refusal reporting is ", this.report_refusal ? "on" | "off", ".");
    elseif (argstr in {"on", "yes", "y", "1"})
      this.report_refusal = true;
      return player:tell("Refusals will be reported to you as they happen.");
    elseif (argstr in {"off", "no", "n", "0"})
      this.report_refusal = false;
      return player:tell("Refusals will happen silently.");
    endif
    player:tell("@refusal-reporting on     - turn on refusal reporting");
    player:tell("@refusal-reporting off    - turn it off");
    player:tell("@refusal-reporting        - see if it's on or off");
  endverb

  method parse_refuse_arguments owner: HACKER
    "Parse action names, optional 'from' origin, and optional 'for' duration into a tuple.";
    "Return {origin, actions, seconds}; report malformed or ambiguous input and return 0.";
    const words = $string_utils:explode(args[1]);
    const possible = this:refusable_actions();
    let origin = $nothing;
    let actions = {};
    let duration = this.default_refusal_time;
    let errors = {};
    let position = 1;
    while (position <= length(words))
      const word = words[position];
      let matched = $string_utils:find_prefix(word, possible);
      if (!matched && word && word[$] == "s")
        matched = $string_utils:find_prefix(word[1..$ - 1], possible);
      endif
      if (typeof(matched) == TYPE_INT && matched > 0)
        actions = setadd(actions, possible[matched]);
      elseif (matched)
        errors = {@errors, word};
      elseif (word == "from" && position < length(words))
        position = position + 1;
        if (words[position] == "guests")
          origin = "all guests";
        else
          origin = $string_utils:match_player(words[position]);
          $command_utils:player_match_failed(origin, words[position]) && return 0;
        endif
      elseif (word == "for" && position < length(words))
        const count = this:parse_time_length(words[position + 1..$]);
        if (!count)
          errors = {@errors, word, words[position + 1]};
        else
          duration = this:parse_time(words[position + 1..position + count]);
          if (typeof(duration) != TYPE_INT || duration <= 0)
            player:tell("Please specify a positive refusal duration.");
            return 0;
          endif
          position = position + count;
        endif
      else
        const synonyms = this:translate_refusal_synonym(word);
        if (synonyms)
          actions = $set_utils:union(actions, synonyms);
        else
          errors = {@errors, word};
        endif
      endif
      position = position + 1;
    endwhile
    if (errors)
      player:tell(length(errors) > 1 ? "These parts of the command were not understood: " | "This part of the command was not understood: ", $string_utils:english_list(errors, 0, " ", " ", " "));
      return 0;
    endif
    if (!actions)
      player:tell("Please specify an action to refuse.");
      return 0;
    endif
    return {this:player_to_refusal_origin(origin), actions, duration};
  endmethod

  method time_word_to_seconds owner: HACKER
    "Return the fixed interval for one named unit, or zero for an unknown unit.";
    const seconds = $time_utils:parse_english_time_interval("1", args[1]);
    return typeof(seconds) == TYPE_INT ? seconds | 0;
  endmethod

  method parse_time_length owner: HACKER
    "Return the length (0, 1, or 2) of a positive integer/unit duration prefix.";
    const {words} = args;
    !words && return 0;
    this:time_word_to_seconds(words[1]) && return 1;
    !$string_utils:is_numeric(words[1]) || toint(words[1]) <= 0 && return 0;
    return length(words) > 1 && this:time_word_to_seconds(words[2]) ? 2 | 1;
  endmethod

  method parse_time owner: HACKER
    "Convert an integer/unit duration; a bare integer means days, and empty input uses the default.";
    const {words} = args;
    !words && return this.default_refusal_time;
    length(words) > 2 && return E_INVARG;
    if (length(words) == 1 && this:time_word_to_seconds(words[1]))
      return this:time_word_to_seconds(words[1]);
    endif
    return $time_utils:parse_english_time_interval(words[1], length(words) == 2 ? words[2] | "days");
  endmethod

  method clear_refusals owner: HACKER
    "Erase refusals for self calls or a caller who controls the player.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.refused_origins = {};
    this.refused_actions = {};
    this.refused_until = {};
    this.refused_extra = {};
  endmethod

  method set_default_refusal_time owner: HACKER
    "Set the default refusal duration for self calls or a controlling caller.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.default_refusal_time = toint(args[1]);
  endmethod

  method refusable_actions owner: HACKER
    "Return supported refusal actions; descendants may extend pass() to add actions.";
    return {"page", "whisper", "move", "join", "accept", "mail"};
  endmethod

  method translate_refusal_synonym owner: HACKER
    "Translate 'all' to every supported action; descendants may supply other synonyms.";
    const {word} = args;
    return word == "all" ? this:refusable_actions() | {};
  endmethod

  method default_refusals_text_filter owner: HACKER
    "Return the actions to include in a refusal listing; the default includes all supplied actions.";
    return args[2];
  endmethod

  method refusals_text owner: HACKER
    "Describe a player's refusals using the fixed overridable text filter, without arbitrary method dispatch.";
    const who = args[1];
    let lines = {};
    for position in [1..length(who.refused_origins)]
      const origin = who.refused_origins[position];
      const actions = this:default_refusals_text_filter(origin, who.refused_actions[position]);
      actions && (lines = {@lines, tostr(ctime(who.refused_until[position]), " ", this:refusal_origin_to_name(origin), ":  ", $string_utils:from_list(actions, " "))});
    endfor
    return lines || {"No refusals."};
  endmethod

  method player_to_refusal_origin owner: #2
    "Keep opaque player IDs; guests use a caller-specific host fingerprint. Origins pass through unchanged.";
    set_task_perms(caller_perms());
    const {who} = args;
    if (typeof(who) == TYPE_OBJ && valid(who))
      const guest_class = `$local.guest ! E_PROPNF, E_INVIND => $guest';
      $object_utils:isa(who, guest_class) && return who:connection_name_hash("xx");
    endif
    return who;
  endmethod

  method refusal_origin_to_name owner: HACKER
    "Describe a player, everybody sentinel, or anonymous guest fingerprint.";
    const {origin} = args;
    origin in {"all guests", "everybody"} && return origin;
    origin == "Permission denied" && return "an errorful origin";
    typeof(origin) != TYPE_OBJ && return "a certain guest";
    origin == $nothing && return "Everybody";
    return $string_utils:name_and_number(origin);
  endmethod

  method check_refusal_actions owner: HACKER
    "Return whether every supplied action is supported by this player.";
    const {actions} = args;
    const legal = this:refusable_actions();
    for action in (actions)
      !(action in legal) && return false;
    endfor
    return true;
  endmethod

  method add_refusal owner: HACKER
    "Add actions for one or more origins, with a duration and optional per-action metadata; self calls only.";
    "An origin has one shared expiration time. This method adds no suspension.";
    caller == this || return E_PERM;
    let {origins, actions, ?duration = this.default_refusal_time, ?extra = 0} = args;
    typeof(origins) != TYPE_LIST && (origins = {origins});
    typeof(actions) != TYPE_LIST && (actions = {actions});
    this:check_refusal_actions(actions) || return E_INVARG;
    const now = time();
    duration < 0 || duration > 9223372036854775807 - now && return E_INVARG;
    const until = now + duration;
    for supplied in (origins)
      const origin = this:player_to_refusal_origin(supplied);
      const position = origin in this.refused_origins;
      if (!position)
        this.refused_origins = {@this.refused_origins, origin};
        this.refused_actions = {@this.refused_actions, {}};
        this.refused_until = {@this.refused_until, until};
        this.refused_extra = {@this.refused_extra, {}};
      endif
      const row = position || length(this.refused_origins);
      this.refused_until[row] = until;
      for action in (actions)
        const column = action in this.refused_actions[row];
        if (column)
          this.refused_extra[row][column] = extra;
        else
          this.refused_actions[row] = {@this.refused_actions[row], action};
          this.refused_extra[row] = {@this.refused_extra[row], extra};
        endif
      endfor
    endfor
  endmethod

  method remove_refusal owner: HACKER
    "Remove selected actions for an origin; return the count removed. Self calls only.";
    caller == this || return E_PERM;
    let {origin, actions} = args;
    origin = this:player_to_refusal_origin(origin);
    typeof(actions) != TYPE_LIST && (actions = {actions});
    const row = origin in this.refused_origins;
    !row && return 0;
    let count = 0;
    for action in (actions)
      const column = action in this.refused_actions[row];
      if (column)
        this.refused_actions[row] = listdelete(this.refused_actions[row], column);
        this.refused_extra[row] = listdelete(this.refused_extra[row], column);
        count = count + 1;
      endif
    endfor
    if (!this.refused_actions[row])
      for name in ({"refused_origins", "refused_actions", "refused_until", "refused_extra"})
        this.(name) = listdelete(this.(name), row);
      endfor
    endif
    return count;
  endmethod

  method remove_expired_refusals owner: HACKER
    "Remove expired entries and deleted players; preserve the $nothing sentinel for everybody.";
    "Cleanup is synchronous and adds no transaction boundary.";
    const now = time();
    let rows = {};
    for position in [1..length(this.refused_origins)]
      const origin = this.refused_origins[position];
      const deleted = typeof(origin) == TYPE_OBJ && origin != $nothing && !valid(origin);
      now >= this.refused_until[position] || deleted && (rows = {position, @rows});
    endfor
    for row in (rows)
      for name in ({"refused_origins", "refused_actions", "refused_until", "refused_extra"})
        this.(name) = listdelete(this.(name), row);
      endfor
    endfor
  endmethod

  method refuses_action owner: HACKER
    "Check direct, owner, everybody, and guest-wide refusals, in that order.";
    "The default predicate does not commit. Descendant action hooks may have their own effects.";
    const {origin, action, @extra} = args;
    const key = this:player_to_refusal_origin(origin);
    let candidates = {key};
    if (typeof(key) == TYPE_OBJ && valid(key))
      candidates = {@candidates, key.owner};
    endif
    key != this && (candidates = {@candidates, $nothing});
    typeof(origin) == TYPE_OBJ && $object_utils:isa(origin, $guest) && (candidates = {@candidates, "all guests"});
    for candidate in (candidates)
      const row = candidate in this.refused_origins;
      if (row && action in this.refused_actions[row] && this:("refuses_action_" + action)(row, origin, @extra))
        return true;
      endif
    endfor
    return false;
  endmethod

  method "refuses_action_*" owner: HACKER
    "Return whether an indexed refusal remains active; cleanup occurs during explicit maintenance.";
    const {row, @context} = args;
    return time() < this.refused_until[row];
  endmethod

  method report_refusal owner: HACKER
    "Notify this player of a refused action only when reporting is enabled.";
    this.report_refusal && this:tell(@args[2..$]);
  endmethod

  verb "wh*isper" (any at this) owner: HACKER flags: "rxd"
    "Apply whisper refusals before inherited private delivery.";
    if (this:refuses_action(player, "whisper"))
      player:tell(this:whisper_refused_msg());
      this:report_refusal(player, "You just refused a whisper from ", player.name, ".");
      return 0;
    endif
    return pass(@args);
  endverb

  method receive_page owner: HACKER
    "Reject a refused page and mark its task for the sender's echo; otherwise use inherited delivery.";
    if (this:refuses_action(player, "page"))
      this.page_refused = task_id();
      return 0;
    endif
    this.page_refused = 0;
    return pass(@args);
  endmethod

  method page_echo_msg owner: HACKER
    "Return a refusal message only for the task whose page was refused.";
    if (task_id() == this.page_refused)
      this:report_refusal(player, "You just refused a page from ", player.name, ".");
      return this:page_refused_msg();
    endif
    return pass(@args);
  endmethod

  method "moveto acceptable" owner: HACKER
    "Apply player and caller-chain refusals before movement or acceptance; spurned ancestors also block acceptance.";
    const action = verb == "moveto" ? "move" | "accept";
    const item = args[1];
    player != this && this:refuses_action(player, action, item) && return false;
    let frames = callers();
    while (frames && frames[1][1] == this && frames[1][2] == verb)
      frames = frames[2..$];
    endwhile
    let previous = $nothing;
    for frame in (frames)
      const principal = frame[3];
      if (principal == $nothing && frame[1] == $nothing && frame[2] != "")
        continue;
      endif
      valid(principal) || return false;
      if (principal.wizard || principal == this || principal == previous)
        continue;
      endif
      this:refuses_action(principal, action, item) && return false;
      previous = principal;
    endfor
    if (action == "accept" && typeof(this.spurned_objects) == TYPE_LIST)
      for ancestor in (this.spurned_objects)
        $object_utils:isa(item, ancestor) && return false;
      endfor
    endif
    return pass(@args);
  endmethod

  method "whisper_refused_msg page_refused_msg mail_refused_msg" owner: HACKER
    "Expand the configured refusal message with this player as its subject.";
    return $string_utils:pronoun_sub(this.(verb), this);
  endmethod

  verb "@spurn" (any none none) owner: HACKER flags: "rd"
    "Usage: @spurn <object> to reject it and its descendants, or @spurn !<object> to remove the entry.";
    caller == this || return E_PERM;
    !argstr && return this:tell("Spurn what?");
    const removing = argstr[1] == "!";
    const text = removing ? argstr[2..$] | argstr;
    const item = this:my_match_object(text);
    $command_utils:object_match_failed(item, text) && return 0;
    const present = item in this.spurned_objects;
    if (removing)
      this.spurned_objects = $list_utils:setremove_all(this.spurned_objects, item);
      return this:tell(present ? "You are no longer spurning " | "You are not spurning ", $string_utils:nn(item), present ? " or any kids of it." | ".");
    endif
    this.spurned_objects = setadd(this.spurned_objects, item);
    this:tell(present ? "You are already spurning " | "You are now spurning ", $string_utils:nn(item), " plus any and all kids of it.");
  endverb

  verb "@spurned" (none none none) owner: HACKER flags: "rd"
    "List spurned objects, whose descendants are also rejected.";
    if (this.spurned_objects)
      return this:tell("You are spurning the following objects, including any and all descendents:  ", $string_utils:nn(this.spurned_objects));
    endif
    this:tell("You are not spurning any objects.");
  endverb

  method set_spurned_objects owner: HACKER
    "Replace the spurn list for a controlling caller; accept one object or a list of objects.";
    $perm_utils:controls(caller_perms(), this) || return E_PERM;
    const {objects} = args;
    const values = typeof(objects) == TYPE_LIST ? objects | {objects};
    for object in (values)
      typeof(object) == TYPE_OBJ || return E_TYPE;
    endfor
    this.spurned_objects = values;
  endmethod
endobject
