object CONTAINER [
  import_export_id -> "container"
]
  name: "generic container"
  parent: THING
  owner: #2
  fertile: true
  readable: true

  property close_msg (owner: #2, flags: "rc") = "You close %d.";
  property dark (owner: #2, flags: "r") = true;
  property empty_msg (owner: #2, flags: "rc") = "It is empty.";
  property oclose_msg (owner: #2, flags: "rc") = "closes %d.";
  property oopen_fail_msg (owner: #2, flags: "rc") = "";
  property oopen_msg (owner: #2, flags: "rc") = "opens %d.";
  property opaque (owner: #2, flags: "r") = 1;
  property open_fail_msg (owner: #2, flags: "rc") = "You can't open that.";
  property open_key (owner: #2, flags: "c") = 0;
  property open_msg (owner: #2, flags: "rc") = "You open %d.";
  property opened (owner: #2, flags: "r") = false;
  property oput_fail_msg (owner: #2, flags: "rc") = "";
  property oput_msg (owner: #2, flags: "rc") = "puts %d in %i.";
  property oremove_fail_msg (owner: #2, flags: "rc") = "";
  property oremove_msg (owner: #2, flags: "rc") = "removes %d from %i.";
  property put_fail_msg (owner: #2, flags: "rc") = "You can't put %d in that.";
  property put_msg (owner: #2, flags: "rc") = "You put %d in %i.";
  property remove_fail_msg (owner: #2, flags: "rc") = "You can't remove that.";
  property remove_msg (owner: #2, flags: "rc") = "You remove %d from %i.";

  override aliases (owner: #2, flags: "rc") = {"generic container"};
  override object_size (owner: HACKER, flags: "r") = {9415, 1084848672};

  verb "p*ut in*sert d*rop" (any in this) owner: #2 flags: "rxd"
    "Put a nearby object in this accessible, open container using caller authority.";
    !(this.location in {player, player.location}) && return player:tell("You can't get at ", this.name, ".");
    dobj == $nothing && return player:tell("What do you want to put ", prepstr, " ", this.name, "?");
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    !(dobj.location in {player, player.location}) && return player:tell("You don't have ", dobj.name, ".");
    !this.opened && return player:tell(this.name, " is closed.");
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    dobj:moveto(this);
    let message;
    if (dobj.location == this)
      player:tell(this:put_msg());
      message = this:oput_msg();
    else
      player:tell(this:put_fail_msg());
      message = this:oput_fail_msg();
    endif
    message && player.location:announce(player.name, " ", message);
  endverb

  verb "re*move ta*ke g*et" (any from this) owner: #2 flags: "rxd"
    "Remove an object from an accessible, visible container; try the floor if carrying fails.";
    !(this.location in {player, player.location}) && return player:tell("Sorry, you're too far away.");
    !this.opened && return player:tell(this.name, " is not open.");
    this.dark && return player:tell("You can't see into ", this.name, " to remove anything.");
    dobj = this:match_object(dobjstr);
    dobj == $nothing && return player:tell("What do you want to take from ", this.name, "?");
    $command_utils:object_match_failed(dobj, dobjstr) && return;
    !(dobj in this:contents()) && return player:tell(dobj.name, " isn't in ", this.name, ".");
    set_task_perms(caller_perms() != $nothing ? caller_perms() | player);
    dobj:moveto(player);
    if (dobj.location == player)
      player:tell(this:remove_msg());
      const message = this:oremove_msg();
      message && player.location:announce(player.name, " ", message);
      return;
    endif
    dobj:moveto(this.location);
    if (dobj.location == this.location)
      player:tell(this:remove_msg());
      const message = this:oremove_msg();
      message && player.location:announce(player.name, " ", message);
      player:tell("You can't pick up ", dobj.name, ", so it tumbles onto the floor.");
    else
      player:tell(this:remove_fail_msg());
      const message = this:oremove_fail_msg();
      message && player.location:announce(player.name, " ", message);
    endif
  endverb

  method look_self owner: #2
    "Describe this container and show its contents when visible.";
    pass();
    !this.dark && this:tell_contents();
  endmethod

  method acceptable owner: #2
    "Accept objects without a player flag; opening and visibility are command-level checks.";
    const {object} = args;
    return !is_player(object);
  endmethod

  verb open (this none none) owner: #2 flags: "rxd"
    "Open this container if its opening key accepts the effective command principal.";
    const principal = caller_perms() != $nothing && caller != this ? caller_perms() | player;
    this.opened && return player:tell("It's already open.");
    let message;
    if (this:is_openable_by(principal))
      this:set_opened(true);
      player:tell(this:open_msg());
      message = this:oopen_msg();
    else
      player:tell(this:open_fail_msg());
      message = this:oopen_fail_msg();
    endif
    message && player.location:announce(player.name, " ", message);
  endverb

  method is_openable_by owner: #2
    "Return whether the opening key permits this principal.";
    const {principal} = args;
    return this.open_key == 0 || $lock_utils:eval_key(this.open_key, principal);
  endmethod

  verb close (this none none) owner: #2 flags: "rxd"
    "Close this container and announce the result.";
    !this.opened && return player:tell("It's already closed.");
    this:set_opened(false);
    player:tell(this:close_msg());
    const message = this:oclose_msg();
    message && player.location:announce(player.name, " ", message);
  endverb

  method tell_contents owner: #2
    "List contents for the command player, or show the empty-container message.";
    if (this.contents)
      player:tell("Contents:");
      for item in (this:contents())
        player:tell("  ", item:title());
      endfor
      return;
    endif
    const message = this:empty_msg();
    message && player:tell(message);
  endmethod

  method set_opened owner: #2
    "Set boolean opening and visibility state atomically. The calling object's owner must control this container.";
    const {value} = args;
    $perm_utils:controls(caller.owner, this) || return E_PERM;
    const opened = !!value;
    this.opened = opened;
    this.dark = this.opaque > (opened ? 1 | 0);
    return opened;
  endmethod

  method set_opaque owner: #2
    "Clamp integer opacity to 0..2 and update visibility. The calling object's owner must control this container.";
    let {opacity} = args;
    $perm_utils:controls(caller.owner, this) || return E_PERM;
    typeof(opacity) == TYPE_INT || return E_INVARG;
    opacity = min(2, max(0, opacity));
    this.dark = opacity > (this.opened ? 1 | 0);
    this.opaque = opacity;
    return opacity;
  endmethod

  method "oclose_msg close_msg oopen_msg open_msg oput_fail_msg put_fail_msg oremove_fail_msg oremove_msg remove_fail_msg remove_msg oput_msg put_msg oopen_fail_msg open_fail_msg empty_msg" owner: HACKER
    "Expand the named message; inaccessible or missing messages produce empty text.";
    const message = `this.(verb) ! ANY';
    return message ? $string_utils:pronoun_sub(message) | "";
  endmethod

  method dark owner: #2
    "Return whether contents are hidden.";
    return !!this.dark;
  endmethod
endobject
