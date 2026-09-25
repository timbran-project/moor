object NOTE_EDITOR [
  import_export_id -> "note_editor"
]
  name: "Note Editor"
  parent: GENERIC_EDITOR
  owner: #96
  readable: true

  property objects (owner: #96, flags: "rc") = {};
  property strmode (owner: #96, flags: "r") = {};

  override aliases (owner: #96, flags: "rc") = {"Note Editor", "nedit"};
  override blessed_task (owner: #96, flags: "rc") = 2137271057;
  override change_msg (owner: #96, flags: "rc") = "There are changes.";
  override commands (owner: #96, flags: "rc") = {{"e*dit", "<note>"}, {"save", "[<note>]"}, {"mode", "[string|list]"}};
  override commands2 (owner: #96, flags: "rc") = {
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
    {"y*ank", "w*hat", "mode", "e*dit", "save", "abort", "q*uit,done,pause"}
  };
  override depart_msg (owner: #96, flags: "rc") = "A small swarm of 3x5 index cards arrives, engulfs %n, and carries %o away.";
  override entrances (owner: #96, flags: "c") = {#5750};
  override help (owner: #96, flags: "rc") = {};
  override no_change_msg (owner: #96, flags: "rc") = "Note has not been modified since the last save.";
  override no_littering_msg (owner: #96, flags: "rc") = {
    "Partially edited text will be here when you get back.",
    "To return, give the `@notedit' command with no arguments.",
    "Please come back and SAVE or ABORT if you don't intend to be working on this text in the immediate future.  Keep Our MOO Clean!  No Littering!"
  };
  override no_text_msg (owner: #96, flags: "rc") = "Note is devoid of text.";
  override nothing_loaded_msg (owner: #96, flags: "rc") = "Use the EDIT command to select a note.";
  override object_size (owner: HACKER, flags: "r") = {9901, 1084848672};
  override previous_session_msg (owner: #96, flags: "rc") = "You need to ABORT or SAVE this note before editing any other.";
  override return_msg (owner: #96, flags: "rc") = "A small swarm of 3x5 index cards blows in and disperses, revealing %n.";
  override stateprops (owner: #96, flags: "r") = {
    {"strmode", 0},
    {"objects", 0},
    {"texts", 0},
    {"changes", 0},
    {"inserting", 1},
    {"readable", 0}
  };
  override who_location_msg (owner: #96, flags: "rc") = "%L [editing notes]";

  verb "e*dit" (any none none) owner: #96 flags: "rd"
    "Usage: edit note or object.property. Refuse to replace unsaved edits.";
    let spec;
    const who = player in this.active;
    if (this:changed(who))
      player:tell("You are still editing ", this:working_on(who), ".  Please type ABORT or SAVE first.");
    else
      spec = this:parse_invoke(dobjstr, verb);
      if (spec)
        this:init_session(who, @spec);
      endif
    endif
  endverb

  verb save (any none none) owner: #96 flags: "rd"
    "Write the buffer to its target with current authority and preserve string mode.";
    let note;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (!dobjstr)
      note = this.objects[who];
    else
      note = this:note_match_failed(dobjstr);
      if (1 == note)
        return;
      else
        this.objects[who] = note;
      endif
    endif
    let text = this:text(who);
    const strmode = length(text) <= 1 && this.strmode[who];
    if (strmode)
      text = text ? text[1] | "";
    endif
    let result = this:set_note_text(note, text);
    if (TYPE_ERR == typeof(result))
      player:tell("Text not saved to ", this:working_on(who), ":  ", result);
      if (result == E_TYPE && typeof(note) == TYPE_OBJ)
        player:tell("Do `mode list' and try saving again.");
      elseif (!dobjstr)
        player:tell("Use `save' with an argument to save the text elsewhere.");
      endif
    else
      player:tell("Text written to ", this:working_on(who), strmode ? " as a single string." | ".");
      this:set_changed(who, 0);
    endif
  endverb

  method init_session owner: #96
    "Load a note or property into an authorized session and record its storage type.";
    let strmode;
    let text;
    const who = args[1];
    if (this:ok(who))
      this.strmode[who] = strmode = typeof(text = args[3]) == TYPE_STR;
      this:load(who, strmode ? text ? {text} | {} | text);
      this.objects[who] = args[2];
      player:tell("Now editing ", this:working_on(who), ".", strmode ? "  [string mode]" | "");
    endif
  endmethod

  method working_on owner: #96
    "Return the session's note or property name for display.";
    let object;
    let prop;
    const who = args[1];
    !who && return "????";
    const spec = this.objects[who];
    if (typeof(spec) == TYPE_LIST)
      object = spec[1];
      prop = spec[2];
    else
      object = spec;
      prop = 0;
    endif
    return valid(object) ? tostr("\"", object.name, "\"(", object, ")", prop ? "." + prop | "") | tostr(prop ? "." + prop + " on " | "", "invalid object (", object, ")");
  endmethod

  method parse_invoke owner: #96
    ":parse_invoke(string,verb)";
    " string is the actual commandline string indicating what we are to edit";
    " verb is the command verb that is attempting to invoke the editor";
    let string;
    let note;
    let text;
    caller != this && raise(E_PERM);
    string = args[1];
    if (!string)
      player:tell_lines({"Usage:  " + args[2] + " <note>   (where <note> is some note object)", "        " + args[2] + "          (continues editing an unsaved note)"});
    else
      note = this:note_match_failed(string);
      if (1 == note)
      else
        text = this:note_text(note);
        if (TYPE_ERR == typeof(text))
          player:tell("Couldn't retrieve text:  ", text);
        else
          return {note, text};
        endif
      endif
    endif
    return 0;
  endmethod

  method note_text owner: #2
    "WIZARDLY";
    let text;
    caller != $note_editor || caller_perms() != $note_editor.owner && return E_PERM;
    set_task_perms(player);
    const spec = args[1];
    if (typeof(spec) == TYPE_OBJ)
      text = spec:text();
    else
      text = `spec[1].(spec[2]) ! ANY';
    endif
    const tt = typeof(text);
    tt in {TYPE_ERR, TYPE_STR} || (tt == TYPE_LIST && (!text || typeof(text[1]) == TYPE_STR)) && return text;
    return E_TYPE;
  endmethod

  method set_note_text owner: #2
    "WIZARDLY";
    caller != $note_editor || caller_perms() != $note_editor.owner && return E_PERM;
    set_task_perms(player);
    let attempt = E_NONE;
    const spec = args[1];
    typeof(spec) == TYPE_OBJ && return spec:set_text(args[2]);
    if ($object_utils:has_callable_verb(spec[1], "set_" + spec[2]))
      attempt = spec[1]:("set_" + spec[2])(args[2]);
    endif
    typeof(attempt) == TYPE_ERR && return `spec[1].(spec[2]) = args[2] ! ANY';
    return attempt;
  endmethod

  method note_match_failed owner: #96
    "Resolve a note or property, report failure, and return the target or a failure sentinel.";
    let string;
    let object;
    let prop;
    const pp = $code_utils:parse_propref(string = args[1]);
    if (pp)
      object = pp[1];
      prop = pp[2];
    else
      object = string;
      prop = 0;
    endif
    let note = player:my_match_object(object, this:get_room(player));
    if ($command_utils:object_match_failed(note, object))
    elseif (prop)
      if (!$object_utils:has_property(note, prop))
        player:tell(object, " has no \".", prop, "\" property.");
      else
        return {note, prop};
      endif
    elseif (!$object_utils:has_callable_verb(note, "text") || !$object_utils:has_callable_verb(note, "set_text"))
      return {note, "description"};
      "... what we used to do.  but why barf?   that's no fun...";
      player:tell(object, "(", note, ") doesn't look like a note.");
    else
      return note;
    endif
    return 1;
  endmethod

  verb "w*hat" (none none none) owner: #96 flags: "rd"
    "Describe the current buffer and its string-storage mode.";
    pass(@args);
    const who = this:loaded(player);
    if (who && this.strmode[who])
      player:tell("Text will be stored as a single string instead of a list when possible.");
    endif
  endverb

  verb mode (any none none) owner: #96 flags: "rd"
    "mode [string|list]";
    let mode;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (dobjstr && index("string", dobjstr) == 1)
      this.strmode[who] = mode = 1;
      player:tell("Now in string mode:");
    elseif (dobjstr && index("list", dobjstr) == 1)
      this.strmode[who] = mode = 0;
      player:tell("Now in list mode:");
    elseif (dobjstr)
      player:tell("Unrecognized mode:  ", dobjstr);
      player:tell("Should be one of `string' or `list'");
      return;
    else
      player:tell("Currently in ", (mode = this.strmode[who]) ? "string " | "list ", "mode:");
    endif
    if (mode)
      player:tell("  store text as a single string instead of a list when possible.");
    else
      player:tell("  always store text as a list of strings.");
    endif
  endverb

  method local_editing_info owner: HACKER
    "Return {name, text, save_command} for client-side note editing.";
    const {what, text} = args;
    const cmd = typeof(text) == TYPE_STR ? "@set-note-string" | "@set-note-text";
    const name = typeof(what) == TYPE_OBJ ? what.name | tostr(what[1].name, ".", what[2]);
    const note = typeof(what) == TYPE_OBJ ? what | tostr(what[1], ".", what[2]);
    return {name, text, tostr(cmd, " ", note)};
  endmethod

  method "set_*" owner: #96
    "Permit inherited setters only for a caller that controls the editor.";
    $perm_utils:controls(caller_perms(), this) && return pass(@args);
    return E_PERM;
  endmethod
endobject
