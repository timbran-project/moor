object MAIL_RECIPIENT [
  import_export_id -> "mail_recipient"
]
  name: "Generic Mail Recipient"
  parent: ROOT_CLASS
  owner: HACKER
  fertile: true
  readable: true

  property expire_period (owner: HACKER, flags: "r") = 2592000;
  property guests_can_send_here (owner: HACKER, flags: "rc") = false;
  property last_msg_date (owner: HACKER, flags: "r") = 0;
  property last_used_time (owner: HACKER, flags: "r") = 0;
  property mail_forward (owner: HACKER, flags: "r") = "%t (%[#t]) is a generic recipient.";
  property mail_notify (owner: HACKER, flags: "r") = {};
  property messages (owner: HACKER, flags: "") = {};
  property messages_going (owner: HACKER, flags: "") = {};
  property messages_kept (owner: HACKER, flags: "r") = {};
  property moderated (owner: HACKER, flags: "rc") = {};
  property moderator_forward (owner: HACKER, flags: "rc") = "%n (%#) can't send to moderated list %t (%[#t]) directly.";
  property moderator_notify (owner: HACKER, flags: "rc") = {};
  property readers (owner: HACKER, flags: "rc") = {};
  property registered_email (owner: HACKER, flags: "") = "";
  property rmm_own_msgs (owner: HACKER, flags: "rc") = true;
  property writers (owner: HACKER, flags: "rc") = {};

  override aliases (owner: HACKER, flags: "rc") = {"Generic Mail Recipient"};
  override description (owner: HACKER, flags: "rc") = "This can either be a mailing list or a mail folder, depending on what mood you're in...";
  override object_size (owner: HACKER, flags: "r") = {30900, 1084848672};

  method set_aliases owner: HACKER
    "Set aliases after checking address names; return false if any alias was rejected.";
    const {aliases} = args;
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.location != $mail_agent && return pass(@args);
    length(aliases) > $mail_agent.max_list_aliases && return E_QUOTA;
    let accepted = {};
    for alias in (aliases)
      if (index(alias, " ") || $mail_agent:check_names(this, alias))
        accepted = {@accepted, alias};
      endif
    endfor
    return pass(accepted) && accepted == aliases;
  endmethod

  method look_self owner: HACKER
    "Describe the list: full name, aliases, access status, and description unless brief.";
    const {?brief = false} = args;
    const names = this:mail_names();
    const namelist = "*" + (names ? $string_utils:from_list(names, ", *") | tostr(this));
    let fwd = this:mail_forward();
    if (typeof(fwd) != TYPE_LIST)
      fwd = {};
    endif
    let access;
    if (this:is_writable_by(player))
      access = player in fwd ? " [Writable/Subscribed]" | " [Writable]";
    elseif (this.readers == 1)
      access = tostr(" [Public", player in fwd ? "/Subscribed]" | "]");
    elseif (player in fwd)
      access = " [Subscribed]";
    elseif (this:is_readable_by(player))
      access = " [Readable]";
    else
      access = "";
    endif
    let moderation;
    if (this:is_usable_by($no_one))
      moderation = "";
    elseif (this:is_usable_by(player))
      moderation = " [Approved]";
    else
      moderation = " [Moderated]";
    endif
    player:tell(namelist, "  (", this, ")", access, moderation);
    brief && return;
    let desc = this:description();
    typeof(desc) == TYPE_STR && (desc = {desc});
    for l in (desc)
      player:tell("    ", l);
    endfor
  endmethod

  method "is_writable_by is_annotatable_by" owner: HACKER
    "Return whether the principal controls this folder or appears in its writers list.";
    const who = args[1];
    $perm_utils:controls(who, this) && return true;
    return `who in this.writers ! E_TYPE => 0' != 0;
  endmethod

  method is_readable_by owner: HACKER
    "Allow public readers, listed readers, writers, and recipients reached by forwarding.";
    const who = args[1];
    typeof(this.readers) != TYPE_LIST && return true;
    return who in this.readers != 0 || this:is_writable_by(who) || $mail_agent:sends_to(1, this, who);
  endmethod

  method is_usable_by owner: HACKER
    "Return whether a sender may post directly under moderation and guest rules.";
    const who = args[1];
    if (this.moderated)
      return `who in this.moderated ! E_TYPE => 0' != 0 || this:is_writable_by(who) || !!who.wizard;
    endif
    return !!this.guests_can_send_here || !$object_utils:isa(who, $guest);
  endmethod

  method mail_notify owner: HACKER
    "Return normal or moderator notification recipients for the supplied sender.";
    args && !this:is_usable_by(args[1]) && !args[1].wizard && return this:moderator_notify(@args);
    return this.(verb);
  endmethod

  method mail_forward owner: HACKER
    "Return normal or moderator forwarding targets, or an explanatory rejection string.";
    args && !this:is_usable_by(args[1]) && !args[1].wizard && return this:moderator_forward(@args);
    const mf = this.(verb);
    typeof(mf) == TYPE_STR && return $string_utils:pronoun_sub(mf, @args);
    return mf;
  endmethod

  method moderator_forward owner: HACKER
    "Return moderator forwarding targets or a sender-specific rejection string.";
    const mf = this.(verb);
    typeof(mf) == TYPE_STR && return $string_utils:pronoun_sub(mf, args ? args[1] | $player);
    return mf;
  endmethod

  method add_forward owner: HACKER
    ":add_forward(recip[,recip...]) adds new recipients to this list.  Returns a string error message or a list of results (recip => success, E_PERM => not allowed, E_INVARG => not a valid recipient, string => other kind of failure)";
    const perms = caller == $mail_editor ? player | caller_perms();
    const forward_self = !this.mail_forward || this in this.mail_forward != 0;
    let result = {};
    for recip in (args)
      let r;
      if (!valid(recip) || (!is_player(recip) && !($mail_recipient in $object_utils:ancestors(recip))))
        r = E_INVARG;
      elseif ($perm_utils:controls(perms, this) || (typeof(this.readers) != TYPE_LIST && $perm_utils:controls(perms, recip)))
        this.mail_forward = setadd(this.mail_forward, recip);
        r = recip;
      else
        r = E_PERM;
      endif
      result = listappend(result, r);
    endfor
    if (length(this.mail_forward) > 1 && $nothing in this.mail_forward)
      this.mail_forward = setremove(this.mail_forward, $nothing);
    endif
    forward_self && (this.mail_forward = setadd(this.mail_forward, this));
    return result;
  endmethod

  method delete_forward owner: HACKER
    ":delete_forward(recip[,recip...]) removes recipients to this list.  Returns a list of results (E_PERM => not allowed, E_INVARG => not on list)";
    const perms = caller == $mail_editor ? player | caller_perms();
    let forward_self = !this.mail_forward || this in this.mail_forward != 0;
    let result = {};
    for recip in (args)
      let r;
      if (!(recip in this.mail_forward))
        r = E_INVARG;
      elseif (!valid(recip) || $perm_utils:controls(perms, recip) || $perm_utils:controls(perms, this))
        if (recip == this)
          forward_self = false;
        endif
        this.mail_forward = setremove(this.mail_forward, recip);
        r = recip;
      else
        r = E_PERM;
      endif
      result = listappend(result, r);
    endfor
    if (!(forward_self || this.mail_forward))
      this.mail_forward = {$nothing};
    elseif (this.mail_forward == {this})
      this.mail_forward = {};
    endif
    return result;
  endmethod

  method add_notify owner: HACKER
    ":add_notify(recip[,recip...]) adds new notifiees to this list.  Returns a list of results (recip => success, E_PERM => not allowed, E_INVARG => not a valid recipient)";
    const perms = caller == $mail_editor ? player | caller_perms();
    let result = {};
    for recip in (args)
      let r;
      if (!valid(recip) || recip == this)
        r = E_INVARG;
      elseif ($perm_utils:controls(perms, this) || (this:is_readable_by(perms) && $perm_utils:controls(perms, recip)))
        this.mail_notify = setadd(this.mail_notify, recip);
        r = recip;
      else
        r = E_PERM;
      endif
      result = listappend(result, r);
    endfor
    return result;
  endmethod

  method delete_notify owner: HACKER
    ":delete_notify(recip[,recip...]) removes notifiees from this list.  Returns a list of results (E_PERM => not allowed, E_INVARG => not on list)";
    const perms = caller == $mail_editor ? player | caller_perms();
    let result = {};
    for recip in (args)
      let r;
      if (!(recip in this.mail_notify))
        r = E_INVARG;
      elseif (!valid(recip) || $perm_utils:controls(perms, recip) || $perm_utils:controls(perms, this))
        this.mail_notify = setremove(this.mail_notify, recip);
        r = recip;
      else
        r = E_PERM;
      endif
      result = listappend(result, r);
    endfor
    return result;
  endmethod

  method receive_message owner: HACKER
    ":receive_message(msg) appends a message record and returns its number.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const new = this:new_message_num();
    this.messages = {@this.messages, {new, args[1]}};
    this.last_msg_date = args[1][1];
    this.last_used_time = time();
    return new;
  endmethod

  method ok owner: HACKER
    ":ok(caller,callerperms) => true iff caller can do read operations";
    return args[1] in {this, $mail_agent} != 0 || args[2].wizard || this:is_readable_by(args[2]);
  endmethod

  method ok_write owner: HACKER
    ":ok_write(caller,callerperms) => true iff caller can do write operations";
    return args[1] in {this, $mail_agent} != 0 || args[2].wizard || this:is_writable_by(args[2]);
  endmethod

  method "parse_message_seq from_msg_seq %from_msg_seq to_msg_seq %to_msg_seq subject_msg_seq body_msg_seq kept_msg_seq unkept_msg_seq display_seq_headers display_seq_full messages_in_seq list_rmm new_message_num length_num_le length_date_le length_all_msgs exists_num_eq msg_seq_to_msg_num_list msg_seq_to_msg_num_string" owner: HACKER
    ":parse_message_seq(strings,cur) => {msg_seq,@unused_strings} or string error";
    "";
    ":from_msg_seq(olist)     => msg_seq of messages from those people";
    ":%from_msg_seq(strings)  => msg_seq of messages with strings in the From: line";
    ":to_msg_seq(olist)       => msg_seq of messages to those people";
    ":%to_msg_seq(strings)    => msg_seq of messages with strings in the To: line";
    ":subject_msg_seq(target) => msg_seq of messages with target in the Subject:";
    ":body_msg_seq(target)    => msg_seq of messages with target in the body";
    ":new_message_num()    => number that the next incoming message will receive.";
    ":length_num_le(num)   => number of messages in folder numbered <= num";
    ":length_date_le(date) => number of messages in folder dated <= date";
    ":length_all_msgs()    => number of messages in folder";
    ":exists_num_eq(num)   => index of message in folder numbered == num, or 0";
    "";
    ":display_seq_headers(msg_seq[,cur])   display message summary lines";
    ":display_seq_full(msg_seq[,preamble]) display entire messages";
    "            => number of final message displayed";
    ":list_rmm() displays contents of .messages_going.";
    "            => the number of messages in .messages_going.";
    "";
    ":messages_in_seq(msg_seq) => list of messages in msg_seq on folder";
    "";
    "See the corresponding routines on $mail_agent for more detail.";
    return this:ok(caller, caller_perms()) ? $mail_agent:(verb)(@args) | E_PERM;
  endmethod

  method length_date_gt owner: HACKER
    ":length_date_gt(date) => number of messages in folder dated > date";
    this:ok(caller, caller_perms()) || return E_PERM;
    const date = args[1];
    return this.last_msg_date <= date ? 0 | $mail_agent:(verb)(date);
  endmethod

  method rm_message_seq owner: HACKER
    ":rm_message_seq(msg_seq) removes the given sequence from the folder";
    "               => string giving msg numbers removed";
    "See the corresponding routine on $mail_agent.";
    this:ok_write(caller, caller_perms()) && return $mail_agent:(verb)(@args);
    if (this:ok(caller, caller_perms()))
      const seq = this:own_messages_filter(caller_perms(), @args);
      seq && return $mail_agent:(verb)(@listset(args, seq, 1));
    endif
    return E_PERM;
  endmethod

  method "undo_rmm expunge_rmm renumber keep_message_seq set_message_body_by_index message_body_by_index" owner: HACKER
    ":undo_rmm()    restores previously deleted messages from .messages_going.";
    "               => msg_seq of restored messages";
    ":expunge_rmm() destroys contents of .messages_going once and for all.";
    "               => number of messages in .messages_going.";
    ":renumber([cur])  renumbers all messages";
    "               => {number of messages,new cur}.";
    ":keep_message_seq(msg_seq) marks messages as kept.";
    ":set_message_body_by_index(i,newbody) changes the body of the i-th message.";
    ":message_body_by_index(i) returns the body of the i-th message.";
    "";
    "See the corresponding routines on $mail_agent.";
    return this:ok_write(caller, caller_perms()) ? $mail_agent:(verb)(@args) | E_PERM;
  endmethod

  method own_messages_filter owner: HACKER
    ":own_messages_filter(who,msg_seq) => subsequence of msg_seq consisting of those messages that <who> is actually allowed to remove (on the assumption that <who> is not one of the allowed writers of this folder.";
    this.rmm_own_msgs || return E_PERM;
    const seq = this:from_msg_seq({args[1]}, args[2]);
    return typeof(seq) != TYPE_LIST || seq != args[2] ? {} | seq;
  endmethod

  method messages owner: HACKER
    ":messages(num) => the message numbered num; :messages() => the entire list of messages.";
    this:ok(caller, caller_perms()) || return E_PERM;
    !args && return this:messages_in_seq({1, this:length_all_msgs() + 1});
    const n = this:exists_num_eq(args[1]);
    n || return E_RANGE;
    return this:messages_in_seq(n)[2];
  endmethod

  method date_sort owner: HACKER
    "Sort messages by date atomically, preserving kept marks and discarding removed-message undo.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    $mail_agent:_sort_messages();
    return 0;
  endmethod

  method _fix_last_msg_date owner: HACKER
    "Set last_msg_date from the newest stored message.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    const mlen = this:length_all_msgs();
    this.last_msg_date = mlen ? this:messages_in_seq(mlen)[2][1] | 0;
  endmethod

  method moderator_notify owner: HACKER
    "Return configured moderation notification recipients.";
    return this.(verb);
  endmethod

  method msg_summary_line owner: HACKER
    "Format a mail summary through the mail service.";
    return $mail_agent:msg_summary_line(@args);
  endmethod

  method __check owner: HACKER
    "Check message formats with read authority; do not change stored messages or suspend.";
    this:ok(caller, caller_perms()) || return E_PERM;
    for message in (this.messages)
      $mail_agent:__convert_new(@message[2]);
    endfor
  endmethod

  method __fix owner: #2
    "Convert stored message formats in one transaction with mailbox write authority.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    this.messages = { {message[1], $mail_agent:__convert_new(@message[2])} for message in (this.messages) };
    this:_fix_last_msg_date();
    return true;
  endmethod

  method init_for_core owner: #2
    "Reset a mail folder during wizard-authorized extraction.";
    caller_perms().wizard || return;
    pass(@args);
    this == $mail_recipient && return;
    move(this, $mail_agent);
    this:rm_message_seq($seq_utils:range(1, this:length_all_msgs()));
    this:expunge_rmm();
    this:_fix_last_msg_date();
    this.mail_forward = {};
    for p in ({"mail_notify", "moderator_forward", "moderator_notify", "writers", "readers", "expire_period", "last_used_time"})
      this.(p) = $mail_recipient.(p);
    endfor
  endmethod

  method initialize owner: #2
    "Initialize forwarding when called by the folder or its controller.";
    if (caller == this || $perm_utils:controls(caller_perms(), this))
      this.mail_forward = {};
      return pass(@args);
    endif
  endmethod

  method "mail_name_old mail_name short_mail_name" owner: HACKER
    "Return the first alias with the mailing-list address prefix.";
    return "*" + this.aliases[1];
  endmethod

  method mail_names owner: HACKER
    "Return address aliases, normalizing underscores to hyphens and excluding spaces.";
    let names = {};
    for a in (this.aliases)
      if (!index(a, " "))
        names = setadd(names, strsub(a, "_", "-"));
      endif
    endfor
    return names;
  endmethod

  method expire_old_messages owner: #2
    "Remove messages older than expire_period that are not marked kept.";
    this:ok_write(caller, caller_perms()) || return E_PERM;
    for x in (this.mail_notify)
      if (!$object_utils:has_verb(x, "notify_mail"))
        this.mail_notify = setremove(this.mail_notify, x);
      endif
    endfor
    const period = this.expire_period;
    period || return 0;
    const rmseq = $seq_utils:remove(this:unkept_msg_seq(), 1 + this:length_date_le(time() - period));
    rmseq || return 0;
    this:rm_message_seq(rmseq);
    return this:expunge_rmm();
  endmethod

  method moveto owner: HACKER
    "Move a folder only with writer authority.";
    this:is_writable_by(caller_perms()) || this:is_writable_by(caller) || return E_PERM;
    pass(@args);
  endmethod

  method msg_full_text owner: HACKER
    ":msg_full_text(@msg) => list of strings.";
    "msg is a mail message (in the usual transmission format).";
    "display_seq_full calls this to obtain the actual list of strings to display.";
    return player:msg_text(@args);
  endmethod

  verb "@set_expire" (this at any) owner: HACKER flags: "rxd"
    "Syntax:  @set_expire <recipient> to <time>";
    "         @set_expire <recipient> to";
    "";
    "Allows the list owner to set the expiration period of this mail recipient. This is the time messages will remain before they are removed from the list. The <time> given can be in english terms (e.g., 2 months, 45 days, etc.).";
    "Non-wizard mailing list owners are limited to a maximum expire period of 180 days. They are also prohibited from setting the list to non-expiring.";
    "Wizards may set the expire period to 0 for no expiration.";
    "The second form, leaving off the time specification, will tell you what the recipient's expire period is currently set to.";
    caller_perms() == #-1 || caller_perms() == player || return player:tell(E_PERM);
    this:is_writable_by(player) || return player:tell(E_PERM);
    !iobjstr && return player:tell(this.expire_period ? tostr("Messages will automatically expire from ", this:mail_name(), " after ", $time_utils:english_time(this.expire_period), ".") | tostr("Messages will not expire from ", this:mail_name()));
    const time = $time_utils:parse_english_time_interval(iobjstr);
    typeof(time) == TYPE_ERR && return player:tell(time);
    time < 0 && return player:tell("Expiration periods cannot be negative.");
    time == 0 && !player.wizard && return player:tell("Only wizards may set a mailing list to not expire.");
    time > 180 * 86400 && !player.wizard && return player:tell("Only a wizard may set the expiration period on a mailing list to greater than 180 days.");
    this.expire_period = time;
    player:tell("Messages will ", time != 0 ? tostr("automatically expire from ", this:mail_name(), " after ", $time_utils:english_time(time)) | tostr("not expire from ", this:mail_name()), ".");
  endverb

  verb "@register" (this at any) owner: #2 flags: "rxd"
    "Syntax:   @register <recipient> to <email-address>";
    "          @register <recipient> to";
    "";
    "The list owner may use this command to record an email address for the mail recipient. Network mail is not available, so the address is only reported. If you leave the email address off of the command, the current registration is reported.";
    caller_perms() == #-1 || caller_perms() == player || return player:tell(E_PERM);
    $perm_utils:controls(player, this) || return player:tell(E_PERM);
    if (!iobjstr)
      if (this.registered_email)
        player:tell(this:mail_name(), " is registered to ", this.registered_email, ".");
      else
        player:tell(this:mail_name(), " is not registered to any address.");
        player:tell("Usage:  @register <recipient> to <email-address>");
      endif
      return;
    endif
    const reason = $mail_agent:invalid_email_address(iobjstr);
    reason && return player:tell(reason, ".");
    iobjstr != $wiz_utils:get_email_address(player) && return player:tell("Mailing list registration is limited to your own registered email address; network mail is not available.");
    this.registered_email = iobjstr;
    player:tell(this:mail_name(), " is now registered to ", iobjstr, ".");
  endverb

  method set_name owner: HACKER
    "Rename the list, rejecting reserved patterns and names already used by another list.";
    const {name} = args;
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    this.location == $mail_agent || return pass(@args);
    index(name, " ") && return pass(name);
    const rp = $mail_agent:reserved_pattern(name);
    if (rp)
      player:tell("Mailing list name \"", name, "\" uses a reserved pattern: ", rp[1]);
      return 0;
    endif
    const other = $mail_agent:match(name, #-1);
    if (valid(other) && other != this && name in other.aliases)
      player:tell("Mailing list name \"", name, "\" in use on ", other.name, "(", other, ")");
      return 0;
    endif
    return pass(name);
  endmethod

  method ok_annotate owner: #2
    ":ok_annotate(caller,callerperms) => true iff caller can do annotations";
    return args[1] in {this, $mail_agent} != 0 || args[2].wizard || this:is_annotatable_by(args[2]);
  endmethod

  method annotate_message_seq owner: #2
    "Prepend or append (default is prepend) note (a list of strings) to each message in message_seq.";
    "Recipient must be annotatable (:is_annotatable_by() returns 1) by the caller for this to work.";
    const {note, appendprepend, message_seq} = args;
    this:ok_annotate(caller, caller_perms()) || return E_PERM;
    for i in ($seq_utils:tolist(message_seq))
      let body = this:message_body_by_index(i);
      body = appendprepend == "append" ? {@body, "", @note} | {@note, "", @body};
      this:set_message_body_by_index(i, body);
    endfor
    return 1;
  endmethod
endobject
