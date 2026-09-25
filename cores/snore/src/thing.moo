object THING [
  import_export_id -> "thing"
]
  name: "generic thing"
  parent: ROOT_CLASS
  owner: #2
  fertile: true
  readable: true

  property drop_failed_msg (owner: #2, flags: "rc") = "You can't seem to drop %t here.";
  property drop_succeeded_msg (owner: #2, flags: "rc") = "You drop %t.";
  property odrop_failed_msg (owner: #2, flags: "rc") = "tries to drop %t but fails!";
  property odrop_succeeded_msg (owner: #2, flags: "rc") = "drops %t.";
  property otake_failed_msg (owner: #2, flags: "rc") = "";
  property otake_succeeded_msg (owner: #2, flags: "rc") = "picks up %t.";
  property take_failed_msg (owner: #2, flags: "rc") = "You can't pick that up.";
  property take_succeeded_msg (owner: #2, flags: "rc") = "You take %t.";

  override aliases (owner: #2, flags: "rc") = {"generic thing"};
  override object_size (owner: HACKER, flags: "r") = {4787, 1084848672};

  verb "g*et t*ake" (this none none) owner: #2 flags: "rxd"
    "Take this nearby thing using caller authority, falling back to the command player.";
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    this.location == player && return player:tell("You already have that!");
    this.location != player.location && return player:tell("I don't see that here.");
    this:moveto(player);
    let message;
    if (this.location == player)
      player:tell(this:take_succeeded_msg() || "Taken.");
      message = this:otake_succeeded_msg();
    else
      player:tell(this:take_failed_msg() || "You can't pick that up.");
      message = this:otake_failed_msg();
    endif
    message && player.location:announce(player.name, " ", message);
  endverb

  verb "d*rop th*row" (this none none) owner: #2 flags: "rxd"
    "Drop this held thing into the current room if its entry policy permits it.";
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    this.location != player && return player:tell("You don't have that.");
    !player.location:acceptable(this) && return player:tell("You can't drop that here.");
    this:moveto(player.location);
    let message;
    if (this.location == player.location)
      player:tell_lines(this:drop_succeeded_msg() || "Dropped.");
      message = this:odrop_succeeded_msg();
    else
      player:tell_lines(this:drop_failed_msg() || "You can't seem to drop that here.");
      message = this:odrop_failed_msg();
    endif
    message && player.location:announce(player.name, " ", message);
  endverb

  method moveto owner: #2
    "Move only to a destination allowed by this thing's key; delegate movement to the parent hook.";
    const {destination} = args;
    this:is_unlocked_for(destination) && pass(destination);
  endmethod

  method "take_failed_msg take_succeeded_msg otake_failed_msg otake_succeeded_msg drop_failed_msg drop_succeeded_msg odrop_failed_msg odrop_succeeded_msg" owner: #2
    "Expand a movement message with the caller's permissions.";
    set_task_perms(caller_perms());
    return $string_utils:pronoun_sub(this.(verb));
  endmethod

  verb "gi*ve ha*nd" (this at any) owner: #2 flags: "rxd"
    "Give this held thing to a nearby recipient whose entry policy accepts it.";
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    this.location != player && return player:tell("You don't have that!");
    !valid(player.location) && return player:tell("I see no \"", iobjstr, "\" here.");
    const recipient = player.location:match_object(iobjstr);
    $command_utils:object_match_failed(recipient, iobjstr) && return;
    recipient.location != player.location && return player:tell("I see no \"", iobjstr, "\" here.");
    recipient == player && return player:tell("Give it to yourself?");
    this:moveto(recipient);
    if (this.location == recipient)
      player:tell("You hand ", this:title(), " to ", recipient:title(), ".");
      recipient:tell(player:titlec(), " ", $gender_utils:get_conj("hands/hand", player), " you ", this:title(), ".");
    else
      player:tell(recipient:titlec(), " ", $gender_utils:get_conj("does/do", recipient), " not want that item.");
    endif
  endverb

  method examine_key owner: #2
    "Describe the movement key to an authorized examiner during this object's examination.";
    const {examiner} = args;
    caller == this && $perm_utils:controls(examiner, this) && this.key != 0 || return 0;
    return {tostr(this:title(), " can only be moved to locations matching this key:"), tostr("  ", $lock_utils:unparse_key(this.key))};
  endmethod
endobject
