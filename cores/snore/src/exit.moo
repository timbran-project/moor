object EXIT [
  import_export_id -> "exit"
]
  name: "generic exit"
  parent: ROOT_CLASS
  owner: #2
  fertile: true
  readable: true

  property arrive_msg (owner: #2, flags: "rc") = 0;
  property dest (owner: #2, flags: "rc") = #-1;
  property leave_msg (owner: #2, flags: "rc") = 0;
  property nogo_msg (owner: #2, flags: "rc") = 0;
  property oarrive_msg (owner: #2, flags: "rc") = 0;
  property obvious (owner: #2, flags: "rc") = true;
  property oleave_msg (owner: #2, flags: "rc") = 0;
  property onogo_msg (owner: #2, flags: "rc") = 0;
  property source (owner: #2, flags: "rc") = #-1;

  override aliases (owner: #2, flags: "rc") = {"generic exit"};
  override object_size (owner: HACKER, flags: "r") = {7191, 1084848672};

  method invoke owner: #2
    "Traverse this exit as the command player using caller authority.";
    set_task_perms(caller_perms());
    this:move(player);
  endmethod

  method move owner: #2
    "Move an object through this exit if its key and destination permit entry.";
    const {object} = args;
    set_task_perms(caller_perms());
    const unlocked = this:is_unlocked_for(object);
    unlocked && this.dest:bless_for_entry(object);
    if (!unlocked || !this.dest:acceptable(object))
      const message = this:nogo_msg(object);
      if (message)
        object:tell_lines(message);
      else
        object:tell("You can't go that way.");
      endif
      const others_message = this:onogo_msg(object);
      others_message && this:announce_msg(object.location, object, others_message);
      return;
    endif
    const source = object.location;
    const leave_message = this:leave_msg(object);
    leave_message && object:tell_lines(leave_message);
    object:moveto(this.dest);
    if (object.location != source)
      this:announce_msg(source, object, this:oleave_msg(object) || this:defaulting_oleave_msg(object) || "has left.");
    endif
    object.location == this.dest || return;
    const arrive_message = this:arrive_msg(object);
    arrive_message && object:tell_lines(arrive_message);
    this:announce_msg(object.location, object, this:oarrive_msg(object) || "has arrived.");
  endmethod

  method recycle owner: #2
    "Remove this exit's registrations before parent cleanup; require self or controlling caller.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    try
      this.source:remove_exit(this);
      this.dest:remove_entrance(this);
    except error (ANY)
      server_log(tostr("Exit registration cleanup failed for ", this, ": ", error[1]));
    endtry
    return pass(@args);
  endmethod

  method "leave_msg oleave_msg arrive_msg oarrive_msg nogo_msg onogo_msg" owner: #2
    "Expand the named traversal message with the supplied substitution arguments.";
    const message = this.(verb);
    return message ? $string_utils:pronoun_sub(message, @args) | "";
  endmethod

  method set_name owner: #2
    "Set the exit name for its controller or source-room owner. Return true or an error.";
    const {name} = args;
    const principal = caller_perms();
    $perm_utils:controls(principal, this) || (valid(this.source) && this.source.owner == principal) || return E_PERM;
    const result = `this.name = name ! ANY';
    return typeof(result) == TYPE_ERR ? result | true;
  endmethod

  method set_aliases owner: #2
    "Set exit aliases for its controller or source-room owner. Return true or an error.";
    const {aliases} = args;
    const principal = caller_perms();
    $perm_utils:controls(principal, this) || (valid(this.source) && this.source.owner == principal) || return E_PERM;
    const result = `this.aliases = aliases ! ANY';
    return typeof(result) == TYPE_ERR ? result | true;
  endmethod

  method announce_all_but owner: #2
    "Broadcast in a room with exclusions; a final list supplies lines with any prefix on the first line.";
    const {room, excluded, @text} = args;
    !text && return;
    const last = text[$];
    if (typeof(last) != TYPE_LIST)
      room:announce_all_but(excluded, @text);
      return;
    endif
    !last && return;
    room:announce_all_but(excluded, @text[1..$ - 1], last[1]);
    for line in (last[2..$])
      room:announce_all_but(excluded, line);
    endfor
  endmethod

  method defaulting_oleave_msg owner: #2
    "Describe departure using the first direction alias, or the exit name.";
    for name in ({this.name, @this.aliases})
      if (name in {"east", "west", "south", "north", "northeast", "southeast", "southwest", "northwest", "out", "up", "down", "nw", "sw", "ne", "se", "in"})
        return "goes " + name + ".";
      endif
      name in {"leave", "out", "exit"} && return "leaves";
    endfor
    index(this.name, "an ") == 1 || index(this.name, "a ") == 1 && return "leaves for " + this.name + ".";
    return "leaves for the " + this.name + ".";
  endmethod

  method moveto owner: #2
    "Relocate the exit only for itself, its owner object, or a controlling caller.";
    caller in {this, this.owner} || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    return pass(@args);
  endmethod

  method examine_key owner: #2
    "Describe the movement key to an authorized examiner during this object's examination.";
    const {examiner} = args;
    caller == this && $perm_utils:controls(examiner, this) && this.key != 0 || return 0;
    return {tostr(this:title(), " will only transport objects matching this key:"), tostr("  ", $lock_utils:unparse_key(this.key))};
  endmethod

  method announce_msg owner: #2
    "Announce a traversal message to the room except the traveler, adding the traveler's title if absent.";
    let {room, object, message} = args;
    const title = object:titlec();
    !$string_utils:index_delimited(message, title) && (message = tostr(title, " ", message));
    room:announce_all_but({object}, message);
  endmethod
endobject
