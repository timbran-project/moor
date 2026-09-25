object NOTE [
  import_export_id -> "note"
]
  name: "generic note"
  parent: THING
  owner: #2
  fertile: true
  readable: true

  property encryption_key (owner: #2, flags: "c") = 0;
  property text (owner: #2, flags: "c") = {};
  property writers (owner: #2, flags: "rc") = {};

  override aliases (owner: #2, flags: "rc") = {"generic note"};
  override description (owner: #2, flags: "rc") = "There appears to be some writing on the note ...";
  override object_size (owner: HACKER, flags: "r") = {6265, 1084848672};

  verb "r*ead" (this none none) owner: #2 flags: "rxd"
    "Usage: read note. Display the note when the caller may read it.";
    if (!this:is_readable_by(valid(caller_perms()) ? caller_perms() | player))
      player:tell("Sorry, but it seems to be written in some code that you can't read.");
    else
      this:look_self();
      player:tell();
      player:tell_lines_suspended(this:text());
      player:tell();
      player:tell("(You finish reading.)");
    endif
  endverb

  verb "er*ase" (this none none) owner: #2 flags: "rxd"
    "Usage: erase note. Clear text when the caller may write it.";
    if (this:is_writable_by(valid(caller_perms()) ? caller_perms() | player))
      this:set_text({});
      player:tell("Note erased.");
    else
      player:tell("You can't erase this note.");
    endif
  endverb

  verb "wr*ite" (any on this) owner: #2 flags: "rxd"
    "Usage: write text on note. Append one line when the caller may write it.";
    if (this:is_writable_by(valid(caller_perms()) ? caller_perms() | player))
      this:set_text({@this.text, dobjstr});
      player:tell("Line added to note.");
    else
      player:tell("You can't write on this note.");
    endif
  endverb

  verb "del*ete rem*ove" (any from this) owner: #2 flags: "rd"
    "Usage: delete line from note. Remove a numbered line when the player may write it.";
    if (!this:is_writable_by(player))
      player:tell("You can't modify this note.");
    elseif (!dobjstr)
      player:tell("You must tell me which line to delete.");
    else
      let line = toint(dobjstr);
      if (line < 0)
        line = line + length(this.text) + 1;
      endif
      if (line <= 0 || line > length(this.text))
        player:tell("Line out of range.");
      else
        this:set_text(listdelete(this.text, line));
        player:tell("Line deleted.");
      endif
    endif
  endverb

  verb encrypt (this with any) owner: #2 flags: "rd"
    "Usage: encrypt note with key. Set a parsed read lock with player authority.";
    set_task_perms(player);
    const key = $lock_utils:parse_keyexp(iobjstr, player);
    if (typeof(key) == TYPE_STR)
      player:tell("That key expression is malformed:");
      player:tell("  ", key);
    else
      try
        this.encryption_key = key;
        player:tell("Encrypted ", this.name, " with this key:");
        player:tell("  ", $lock_utils:unparse_key(key));
      except error (ANY)
        player:tell(error[2], ".");
      endtry
    endif
  endverb

  verb decrypt (this none none) owner: #2 flags: "rd"
    "Usage: decrypt note. Clear its read lock with player authority.";
    set_task_perms(player);
    try
      dobj.encryption_key = 0;
      player:tell("Decrypted ", dobj.name, ".");
    except error (ANY)
      player:tell(error[2], ".");
    endtry
  endverb

  method text owner: #2
    "Return note text to a controlling or authorized reader; otherwise return E_PERM.";
    const cp = caller_perms();
    $perm_utils:controls(cp, this) || this:is_readable_by(cp) && return this.text;
    return E_PERM;
  endmethod

  method is_readable_by owner: #2
    "Return whether a principal satisfies this note's read lock.";
    const key = this.encryption_key;
    return key == 0 || $lock_utils:eval_key(key, args[1]);
  endmethod

  method set_text owner: #2
    "Replace note text for a controlling or authorized writer; reject invalid text types.";
    const cp = caller_perms();
    const newtext = args[1];
    if ($perm_utils:controls(cp, this) || this:is_writable_by(cp))
      if (typeof(newtext) == TYPE_LIST)
        this.text = newtext;
      else
        return E_TYPE;
      endif
    else
      return E_PERM;
    endif
  endmethod

  method is_writable_by owner: #2
    "Return whether a principal controls this note or is an allowed writer.";
    const who = args[1];
    const wr = this.writers;
    $perm_utils:controls(who, this) && return true;
    typeof(wr) == TYPE_LIST && return who in wr > 0;
    return !!wr;
  endmethod
endobject
