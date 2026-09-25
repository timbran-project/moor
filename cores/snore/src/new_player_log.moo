object NEW_PLAYER_LOG [
  import_export_id -> "new_player_log"
]
  name: "Player-Creation-Log"
  parent: MAIL_RECIPIENT
  location: MAIL_AGENT
  owner: #2

  override aliases (owner: HACKER, flags: "r") = {"Player-Creation-Log", "PCL"};
  override description (owner: #2, flags: "rc") = "Log of player creations.";
  override mail_forward (owner: HACKER, flags: "r") = {};
  override mail_notify (owner: HACKER, flags: "r") = {#2};
  override moderated (owner: #2, flags: "rc") = {NEW_PLAYER_LOG};
  override object_size (owner: HACKER, flags: "r") = {3172, 1084848672};

  method display_seq_headers owner: #2
    ":display_seq_headers(msg_seq[,cur])";
    !this:ok(caller, caller_perms()) && return E_PERM;
    player:tell("       WHEN    BY        WHO                 EMAIL-ADDRESS");
    pass(@args);
  endmethod

  method msg_summary_line owner: #2
    "Format a player-creation log entry with creator, player, date, and email.";
    let open;
    const when = ctime(args[1])[5..10];
    const from = args[2];
    const by = $string_utils:left(from[1..index(from, " (") - 1], -9);
    const subject = args[4];
    let who = subject[1..(open = index(subject, " (")) - 1];
    const close = rindex(subject, ")");
    if (close > open)
      who = who[1..min(9, $)] + subject[open..close];
    endif
    who = $string_utils:left(who, 18);
    const line = args[("" in args) + 1];
    let email = line[1..index(line + " ", " ") - 1];
    if (!index(email, "@"))
      email = "??";
    endif
    return tostr(when, "  ", by, " ", who, "  ", email);
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.mail_notify = {player};
      player:set_current_message(this, 0, 0, 1);
      this.moderated = {this};
    else
      return E_PERM;
    endif
  endmethod

  method is_usable_by owner: #2
    "Copied from Generic Mail Recipient (#6419):is_usable_by by Rog (#4292) Tue Mar  2 10:02:32 1993 PST";
    let who;
    return !this.moderated || (this:is_writable_by(who = args[1]) || who in this.moderated || who.wizard);
  endmethod

  verb expire_old_messages (none none none) owner: #2 flags: "rxd"
    "Stop breaking the expire task completely with out of seconds/ticks.";
    if (this:ok_write(caller, caller_perms()))
      fork (0)
        pass(@args);
      endfork
    else
      return E_PERM;
    endif
  endverb
endobject
