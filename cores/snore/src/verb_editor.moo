object VERB_EDITOR [
  import_export_id -> "verb_editor"
]
  name: "Verb Editor"
  parent: GENERIC_EDITOR
  owner: #96
  readable: true

  property objects (owner: #96, flags: "") = {};
  property verbnames (owner: #96, flags: "") = {};

  override aliases (owner: #96, flags: "rc") = {"Verb Editor", "vedit", "verbedit", "verb edit"};
  override blessed_task (owner: #96, flags: "rc") = 665095404;
  override change_msg (owner: #96, flags: "rc") = "You have changed the verb since last successful compile.";
  override commands (owner: #96, flags: "rc") = {{"e*dit", "<obj>:<verb>"}, {"com*pile", "[as <obj>:<verb>]"}};
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
    {"y*ank", "w*hat", "e*dit", "com*pile", "abort", "q*uit,done,pause"}
  };
  override depart_msg (owner: #96, flags: "rc") = "You hear the bips of keyclick, the sliding of mice and the hum of computers in the distance as %n fades slowly out of view, heading towards them.";
  override entrances (owner: #96, flags: "c") = {#5749};
  override help (owner: #96, flags: "rc") = {};
  override no_change_msg (owner: #96, flags: "rc") = "The verb has no pending changes.";
  override no_littering_msg (owner: #96, flags: "rc") = {
    "Keeping your verb for later work.  ",
    "To return, give the `@edit' command with no arguments.",
    "Please come back and COMPILE or ABORT if you don't intend to be working on this verb in the immediate future.  Keep Our MOO Clean!  No Littering!"
  };
  override no_text_msg (owner: #96, flags: "rc") = "Verb body is empty.";
  override nothing_loaded_msg (owner: #96, flags: "rc") = "First, you have to select a verb to edit with the EDIT command.";
  override object_size (owner: HACKER, flags: "r") = {13962, 1084848672};
  override previous_session_msg (owner: #96, flags: "rc") = "You need to either COMPILE or ABORT this verb before you can start on another.";
  override return_msg (owner: #96, flags: "rc") = "There are the light bips of keyclick and the sliding of mice as %n fades into view, shoving %r away from the console, which promptly fades away.";
  override stateprops (owner: #96, flags: "r") = {
    {"objects", 0},
    {"verbnames", 0},
    {"texts", 0},
    {"changes", 0},
    {"inserting", 1},
    {"readable", 0}
  };
  override who_location_msg (owner: #96, flags: "rc") = "%L [editing verbs]";

  verb "e*dit" (any none none) owner: #96 flags: "rd"
    "Usage: edit object:verb. Invoke the editor on a verb definition.";
    if (!args)
      player:tell("edit what?");
    else
      this:invoke(argstr, verb);
    endif
  endverb

  verb "com*pile save" (none any any) owner: #96 flags: "rd"
    "Compile and save the current source with current target authorization.";
    let object;
    let vname;
    let vargs;
    let changeverb;
    let spec;
    let vnum;
    let objverbname;
    let verbcode;
    let pas = {{}, {}};
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (!args)
      object = this.objects[who];
      vname = this.verbnames[who];
      if (typeof(vname) == TYPE_LIST)
        vargs = listdelete(vname, 1);
        vname = vname[1];
      else
        vargs = {};
      endif
      changeverb = 0;
    else
      spec = args[1] == "as" && length(args) >= 2 ? $code_utils:parse_verbref(args[2]) | {};
      pas = spec ? $code_utils:parse_argspec(@args[3..$]) | {};
      if (!spec || typeof(pas) != TYPE_LIST || pas[2])
        if (typeof(pas) != TYPE_LIST)
          player:tell(pas);
        elseif (pas[2])
          player:tell("I don't understand \"", $string_utils:from_list(pas[2], " "), "\"");
        endif
        player:tell("Usage: ", verb, " [as <object>:<verb>]");
        return;
      else
        object = player:my_match_object(spec[1], this:get_room(player));
        if ($command_utils:object_match_failed(object, spec[1]))
          return;
        else
          vname = spec[2];
          vargs = pas[1] && {@pas[1], "none", "none"}[1..3];
          if (vargs)
            vargs[2] = $code_utils:full_prep(vargs[2]) || vargs[2];
          endif
          changeverb = 1;
        endif
      endif
    endif
    if (vargs)
      vnum = $code_utils:find_verb_named(object, vname);
      while (vnum && this:fetch_verb_args(object, vnum) != vargs)
        vnum = $code_utils:find_verb_named(object, vname, vnum + 1);
      endwhile
      if (!vnum)
        player:tell("There is no ", object, ":", vname, " verb with args (", $string_utils:from_list(vargs, " "), ").");
        if (!changeverb)
          player:tell("Use 'compile as ...' to write your code to another verb.");
        endif
        return;
      endif
      objverbname = tostr(object, ":", vname, " (", $string_utils:from_list(vargs, " "), ")");
    else
      vnum = 0;
      objverbname = tostr(object, ":", $code_utils:toint(vname) == E_TYPE ? vname | this:verb_name(object, vname));
    endif
    "...";
    "...perform eval_subs on verb code if necessary...";
    "...";
    if (player.eval_subs && player:edit_option("eval_subs"))
      verbcode = {};
      for x in (this:text(who))
        verbcode = {@verbcode, $code_utils:substitute(x, player.eval_subs)};
      endfor
    else
      verbcode = this:text(who);
    endif
    "...";
    "...write it out...";
    "...";
    let result = this:set_verb_code(object, vnum ? vnum | vname, verbcode);
    if (result)
      player:tell(objverbname, " not compiled because:");
      for x in (result)
        player:tell("  ", x);
      endfor
    elseif (typeof(result) == TYPE_ERR)
      player:tell({result, "You do not have write permission on " + objverbname + ".", "The verb " + objverbname + " does not exist (!?!)", "The object " + tostr(object) + " does not exist (!?!)"}[1 + (result in {E_PERM, E_VERBNF, E_INVARG})]);
      if (!changeverb)
        player:tell("Do 'compile as <object>:<verb>' to write your code to another verb.");
      endif
      changeverb = 0;
    else
      player:tell(objverbname, verbcode ? " successfully compiled." | " verbcode removed.");
      this:set_changed(who, 0);
    endif
    if (changeverb)
      this.objects[who] = object;
      this.verbnames[who] = vargs ? {vname, @vargs} | vname;
    endif
  endverb

  method working_on owner: #96
    "Describe an authorized session's object, verb name, and argument specification.";
    let who;
    const fuckup = this:ok(who = args[1]);
    !fuckup && return fuckup;
    const object = this.objects[who];
    const verbname = this.verbnames[who];
    typeof(verbname) == TYPE_LIST && return tostr(object, ":", verbname[1], " (", $string_utils:from_list(listdelete(verbname, 1), " "), ")");
    return tostr(object, ":", this:verb_name(object, verbname), " (", this:verb_args(object, verbname), ")");
    "return this:ok(who = args[1]) && tostr(this.objects[who]) + \":\" + this.verbnames[who];";
  endmethod

  method init_session owner: #96
    "Load verb source and target metadata into an authorized editing session.";
    const {who, object, vname, vcode} = args;
    if (this:ok(who))
      this:load(who, vcode);
      this.verbnames[who] = vname;
      this.objects[who] = object;
      this.active[who]:tell("Now editing ", this:working_on(who), ".");
      "this.active[who]:tell(\"Now editing \", object, \":\", vname, \".\");";
    endif
  endmethod

  method parse_invoke owner: #96
    ":parse_invoke(string,v,?code)";
    "  string is the commandline string to parse to obtain the obj:verb to edit";
    "  v is the actual command verb used to invoke the editor";
    " => {object, verbname, verb_code} or error";
    let vname;
    let code;
    if (caller != this)
      raise(E_PERM);
    endif
    const vref = $string_utils:words(args[1]);
    let spec = vref ? $code_utils:parse_verbref(vref[1]) | {};
    if (!spec)
      player:tell("Usage: ", args[2], " object:verb");
      return;
    endif
    let argspec = listdelete(vref, 1);
    if (argspec)
      const pas = $code_utils:parse_argspec(@argspec);
      if (typeof(pas) == TYPE_LIST)
        if (pas[2])
          player:tell("I don't understand \"", $string_utils:from_list(pas[2], " "), "\"");
          return;
        endif
        argspec = {@pas[1], "none", "none"}[1..3];
        argspec[2] = $code_utils:full_prep(argspec[2]) || argspec[2];
      else
        player:tell(pas);
        return;
      endif
    endif
    let object = player:my_match_object(spec[1], this:get_room(player));
    if (!$command_utils:object_match_failed(object, spec[1]))
      let vnum = $code_utils:find_verb_named(object, vname = spec[2]);
      if (argspec)
        while (vnum && this:fetch_verb_args(object, vnum) != argspec)
          vnum = $code_utils:find_verb_named(object, vname, vnum + 1);
        endwhile
      endif
      if (length(args) > 2)
        code = args[3];
      elseif (vnum)
        code = this:fetch_verb_code(object, vnum);
      else
        code = E_VERBNF;
      endif
      if (typeof(code) == TYPE_ERR)
        player:tell(code != E_VERBNF ? code | "That object does not define that verb", argspec ? " with those args." | ".");
        return code;
      else
        return {object, argspec ? {vname, @argspec} | vname, code};
      endif
    endif
    return 0;
  endmethod

  method fetch_verb_code owner: #2
    "WIZARDLY";
    caller != $verb_editor || caller_perms() != $verb_editor.owner && return E_PERM;
    set_task_perms(player);
    return `verb_code(args[1], args[2], !player:edit_option("no_parens")) ! ANY';
  endmethod

  method set_verb_code owner: #2
    "WIZARDLY";
    caller != $verb_editor || caller_perms() != $verb_editor.owner && return E_PERM;
    set_task_perms(player);
    return `set_verb_code(args[1], args[2], args[3]) ! ANY';
  endmethod

  method local_editing_info owner: #2
    "Return {name, source, save_command} for client-side verb editing.";
    let vargs;
    if (caller == $verb_editor)
      set_task_perms(player);
    endif
    let {object, vname, code} = args;
    if (typeof(vname) == TYPE_LIST)
      if (vname[3] != "none")
        vname[3] = $code_utils:short_prep(vname[3]);
      endif
      vargs = tostr(" ", vname[2], " ", vname[3], " ", vname[4]);
      vname = vname[1];
    else
      vargs = "";
    endif
    const name = tostr(object.name, ":", vname);
    "... so the next 2 lines are actually wrong, since verb_info won't";
    "... necessarily retrieve the correct verb if we have more than one";
    "... matching the given same name; anyway, if parse_invoke understood vname,";
    "... so will @program.  I suspect these were put here because in the";
    "... old scheme of things, vname was always a number.";
    "vname = strsub($string_utils:explode(verb_info(object, vname)[3])[1], \"*\", \"\")";
    "vargs = verb_args(object, vname)";
    "";
    return {name, code, tostr("@program ", object, ":", vname, vargs)};
  endmethod

  method verb_name owner: #2
    "verb_name(object, vname)";
    "Find vname on object and return its full name (quoted).";
    "This is useful for when we're working with verb numbers.";
    caller != $verb_editor || caller_perms() != $verb_editor.owner && return E_PERM;
    set_task_perms(player);
    const given = args[2];
    const info = `verb_info(args[1], given) ! ANY';
    typeof(info) == TYPE_ERR && return tostr(given, "[", info, "]");
    info[3] == given && return given;
    return tostr(given, "/\"", info[3], "\"");
  endmethod

  method verb_args owner: #2
    "verb_name(object, vname)";
    "Find vname on object and return its full name (quoted).";
    "This is useful for when we're working with verb numbers.";
    caller != $verb_editor || caller_perms() != $verb_editor.owner && return E_PERM;
    set_task_perms(player);
    return $string_utils:from_list(`verb_args(args[1], args[2]) ! ANY', " ");
  endmethod

  verb comment (any any any) owner: #96 flags: "rd"
    "Syntax: comment [<range>]";
    "";
    "Turns the specified range of lines, into comments.";
    let range;
    let from;
    let to;
    let crap;
    caller != player && caller_perms() != player && return E_PERM;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
    else
      range = this:parse_range(who, {"."}, @args);
      if (typeof(range) != TYPE_LIST)
        player:tell(tostr(range));
      elseif (range[3])
        player:tell_lines($code_utils:verb_documentation());
      else
        const text = this.texts[who];
        {from, to, crap} = range;
        let cut = $maxint;
        for line in [from..to]
          cut = min(cut, `match(text[line], "[^ ]")[1] ! E_RANGE => 1');
        endfor
        for line in [from..to]
          text[line] = toliteral(text[line][cut..$]) + ";";
        endfor
        this.texts[who] = text;
        player:tell(to == from ? "Line" | "Lines", " changed.");
        this.changes[who] = 1;
        this.times[who] = time();
      endif
    endif
  endverb

  verb uncomment (any any any) owner: #96 flags: "rd"
    "Syntax: uncomment [<range>]";
    "";
    "Turns the specified range of lines from comments to, uh, not comments.";
    let range;
    let from;
    let to;
    let crap;
    caller != player && caller_perms() != player && return E_PERM;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
    else
      range = this:parse_range(who, {"."}, @args);
      if (typeof(range) != TYPE_LIST)
        player:tell(tostr(range));
      elseif (range[3])
        player:tell_lines($code_utils:verb_documentation());
      else
        const text = this.texts[who];
        {from, to, crap} = range;
        let bogus = {};
        for line in [from..to]
          if (match(text[line], "^ *\"%([^\\\"]%|\\.%)*\";$"))
            "check from $code_utils:verb_documentation";
            if (!bogus)
              text[line] = $no_one:eval(text[line])[2];
            endif
          else
            bogus = setadd(bogus, line);
          endif
        endfor
        if (bogus)
          player:tell(length(bogus) == 1 ? "Line" | "Lines", " ", $string_utils:english_list(bogus), " ", length(bogus) == 1 ? "is" | "are", " not comments.");
          player:tell("No changes.");
          return;
        endif
        this.texts[who] = text;
        player:tell(to == from ? "Line" | "Lines", " changed.");
        this.changes[who] = 1;
        this.times[who] = time();
      endif
    endif
  endverb

  method fetch_verb_args owner: #2
    "WIZARDLY";
    caller != $verb_editor || caller_perms() != $verb_editor.owner && raise(E_PERM);
    set_task_perms(player);
    return `verb_args(args[1], args[2]) ! ANY';
  endmethod
endobject
