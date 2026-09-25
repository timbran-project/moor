object CODE_UTILS [
  import_export_id -> "code_utils"
]
  name: "code utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property _all_preps (owner: HACKER, flags: "rc") = {
    "with",
    "using",
    "at",
    "to",
    "in front of",
    "in",
    "inside",
    "into",
    "on top of",
    "on",
    "onto",
    "upon",
    "out of",
    "from inside",
    "from",
    "over",
    "through",
    "under",
    "underneath",
    "beneath",
    "behind",
    "beside",
    "for",
    "about",
    "is",
    "as",
    "off",
    "off of",
    "named",
    "called",
    "known as"
  };
  property _multi_preps (owner: HACKER, flags: "rc") = {"off", "from", "out", "on", "on top", "in", "in front", "known"};
  property _other_preps (owner: HACKER, flags: "rc") = {
    "using",
    "at",
    "inside",
    "into",
    "on top of",
    "onto",
    "upon",
    "out of",
    "from inside",
    "underneath",
    "beneath",
    "about",
    "off of",
    "called",
    "known as"
  };
  property _other_preps_n (owner: HACKER, flags: "rc") = {1, 2, 4, 4, 5, 5, 5, 6, 6, 9, 9, 12, 15, 16, 16};
  property _short_preps (owner: HACKER, flags: "rc") = {
    "with",
    "to",
    "in front of",
    "in",
    "on",
    "from",
    "over",
    "through",
    "under",
    "behind",
    "beside",
    "for",
    "is",
    "as",
    "off",
    "named"
  };
  property _version (owner: HACKER, flags: "rc") = "1.8.4+toastsoft.51";
  property builtin_props (owner: #2, flags: "r") = {"name", "r", "w", "f", "programmer", "wizard", "owner", "location", "contents"};
  property error_list (owner: HACKER, flags: "rc") = {
    E_NONE,
    E_TYPE,
    E_DIV,
    E_PERM,
    E_PROPNF,
    E_VERBNF,
    E_VARNF,
    E_INVIND,
    E_RECMOVE,
    E_MAXREC,
    E_RANGE,
    E_ARGS,
    E_NACC,
    E_INVARG,
    E_QUOTA,
    E_FLOAT
  };
  property error_names (owner: HACKER, flags: "rc") = {
    "E_NONE",
    "E_TYPE",
    "E_DIV",
    "E_PERM",
    "E_PROPNF",
    "E_VERBNF",
    "E_VARNF",
    "E_INVIND",
    "E_RECMOVE",
    "E_MAXREC",
    "E_RANGE",
    "E_ARGS",
    "E_NACC",
    "E_INVARG",
    "E_QUOTA",
    "E_FLOAT"
  };
  property prepositions (owner: HACKER, flags: "rc") = {
    "with/using",
    "at/to",
    "in front of",
    "in/inside/into",
    "on top of/on/onto/upon",
    "out of/from inside/from",
    "over",
    "through",
    "under/underneath/beneath",
    "behind",
    "beside",
    "for/about",
    "is",
    "as",
    "off/off of",
    "named/called/known as"
  };

  override aliases (owner: HACKER, flags: "rc") = {"code", "utils"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the code utilities utility package.  See `help $code_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "parse_propref(\"foo.bar\")  => {\"foo\",\"bar\"} (or 0 if arg. isn't a property ref.)",
    "parse_verbref(\"foo:bar\")  => {\"foo\",\"bar\"} (or 0 if arg. isn't a verb ref.)",
    "parse_argspec(\"any\",\"in\",\"front\",\"of\",\"this\",\"baz\"...)",
    "                          => {{\"any\", \"in front of\", \"this\"},{\"baz\"...}} ",
    "                                           (or string if args don't parse)",
    "",
    "toint(string)           => integer (or E_TYPE if string is not a integer)",
    "toobj(string)           => object (or E_TYPE if string is not an object)",
    "toerr(number or string) => error value (or 1 if out of range or unrecognized)",
    "error_name(error value) => name of error (e.g., error_name(E_PERM) => \"E_PERM\")",
    "",
    "verb_perms()      => the current task_perms (as set by set_task_perms()).",
    "verb_location()   => the object where the current verb is defined.",
    "verb_frame()      => callers()-style frame for the current verb.",
    "verb_all_frames() => entire callers() stack including current verb.",
    "verb_usage([object,verbname]) => returns first line of verb doc, usually usage",
    "verb_documentation([object,verbname]) => documentation at beginning of",
    "           verb code, if any -- default is the calling verb",
    "set_verb_documentation(object,verbname,text) => sets text at beginning of verb",
    "",
    "   Preposition routines",
    "",
    "prepositions()     => full list of prepostions",
    "full_prep (\"in\")   => \"in/inside/into\"",
    "short_prep(\"into\") => \"in\"",
    "short_prep(\"in/inside/into\") => \"in\"",
    "get_prep  (\"off\", \"of\", \"the\", \"table\") => {\"off of\", \"the\", \"table\"}",
    "",
    "   Verb routines",
    "",
    "verbname_match (fullname,name) => can `name' be used to call `fullname'",
    "find_verb_named          (object,name[,n]) => verb number or 0 if not found",
    "find_last_verb_named     (object,name[,n]) => verb number of last verb match",
    "find_callable_verb_named (object,name[,n]) => verb number or 0 if not found",
    "find_verbs_containing (pattern[,object|objlist]) => does work for @grep",
    "find_verbs_matching (pattern[,object|objlist]) => does work for @egrep",
    "move_verb (from obj,name,to obj[,newname]) => move a verb from object to object",
    "",
    "move_prop (from obj,name,to obj[,newname]) => move a property to another object",
    "",
    "   Verbs that do the actual dirty work for command lines verbs:",
    "",
    "@show           => show_object  (object)",
    "                   show_property(object,propname)",
    "                   show_verbdef (object,verbname)",
    "explain_syntax  => explain_verb_syntax(thisname,verbname,@verbargs)",
    "eval*-d         => eval_d(code)",
    "help            => help_db_list([player])",
    "                   help_db_search(string topic, dblist)",
    "@who            => show_who_listing(players [,more_players])",
    "@check-full     => display_callers([callers() output])",
    "@dump           => dump_preamble(object)",
    "                => dump_properties(object, create_flag)",
    "                => dump_verbs(object, create_flag)",
    "",
    "   Random but useful verbs",
    "",
    "verb_or_property(object,name[,@args]) => result of verb or property call,",
    "                                         or E_PROPNF",
    "corify_object(object)     => if the object is corified, returns $<name>",
    "task_valid(INT task_id)   => returns true if task_id is currently running.",
    "task_owner(INT task_id)   => returns owner of task_id, if running",
    "owns_task(NUM task_id,OBJ who) => returns whether who owns task_id (if running)",
    "argstr(verb,args[,argstr] => returns a corrected argstr (see full verb help)",
    "substitute(string,subs)   => subs in form {{\"target\", \"sub\"}, {...}, ...}"
  };
  override object_size (owner: HACKER, flags: "r") = {59174, 1084848672};

  verb eval_d (any any any) owner: #2 flags: "rxd"
    ":eval_d(code...) => {compiled?,result}";
    "This works exactly like the builtin eval() except that the code is evaluated ";
    "as if the d flag were unset.";
    let svc;
    let n;
    let colon;
    const code = {"set_verb_code(this,\"eval_d_util\",{\"\\\"Do not remove this verb!  This is an auxiliary verb for :eval_d().\\\";\"});", "dobj=iobj=this=#-1;", "dobjstr=iobjstr=prepstr=argstr=verb=\"\";", tostr("caller=", caller, ";"), "set_task_perms(caller_perms());", @args};
    !caller_perms().programmer && return E_PERM;
    caller_perms() == $no_one && $no_one:bad_eval(tostr(@args)) && return E_PERM;
    svc = set_verb_code(this, "eval_d_util", code);
    if (svc)
      let lines = {};
      for line in (svc)
        n = 0;
        if (index(line, "Line ") == 1)
          colon = index(line + ":", ":");
          n = toint(line[6..colon - 1]);
        endif
        if (n)
          lines = {@lines, tostr("Line ", n - 5, line[colon..$])};
        else
          lines = {@lines, line};
        endif
      endfor
      return {0, lines};
    else
      set_task_perms(caller_perms());
      return {1, this:eval_d_util()};
    endif
  endverb

  method "toint tonum" owner: HACKER
    ":toint(STR)";
    "=> toint(s) if STR is numeric";
    "=> E_TYPE if it isn't";
    let s;
    return match(s = args[1], "^ *[-+]?[0-9]+ *$") ? toint(s) | E_TYPE;
  endmethod

  method toobj owner: HACKER
    ":toobj(objectid as string) => objectid";
    const s = args[1];
    "Handle both integer object IDs (#123) and UUID object IDs (#00004C-993A15FAC7)";
    "Try UUID pattern first";
    let pcre_result = pcre_match(s, "^#[0-9A-Fa-f]{6}-[0-9A-Fa-f]{10}$");
    if (pcre_result)
      "For UUID format, call built-in toobj directly - it should handle UUID parsing";
      return toobj(s);
    endif
    "Try integer pattern";
    pcre_result = pcre_match(s, "^#[-+]?[0-9]+$");
    pcre_result && return toobj(s);
    return E_TYPE;
  endmethod

  method match_objid owner: HACKER
    ":match_objid(string) => match result if string contains object ID pattern";
    "Returns match() result for object ID patterns (both integer and UUID), or {} if no match";
    "Uses pcre_match for reliable pattern matching";
    let match_text;
    let match_start;
    let match_end;
    const s = args[1];
    "Try UUID pattern first (more specific)";
    let pcre_result = pcre_match(s, "^(#[0-9A-Fa-f]{6}-[0-9A-Fa-f]{10}) *$");
    if (pcre_result)
      "Convert pcre_match result to match() format";
      match_text = pcre_result[1]["0"]["match"];
      match_start = pcre_result[1]["0"]["position"][1];
      match_end = pcre_result[1]["0"]["position"][2];
      return {match_start, match_end, {{0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}}, s};
    endif
    "Try integer pattern with pcre_match";
    pcre_result = pcre_match(s, "^(#[-+]?[0-9]+) *$");
    if (pcre_result)
      "Convert pcre_match result to match() format";
      match_text = pcre_result[1]["0"]["match"];
      match_start = pcre_result[1]["0"]["position"][1];
      match_end = pcre_result[1]["0"]["position"][2];
      return {match_start, match_end, {{0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}, {0, -1}}, s};
    endif
    return {};
  endmethod

  method toerr owner: HACKER
    "toerr(n), toerr(\"E_FOO\"), toerr(\"FOO\") => E_FOO.";
    let n;
    const s = args[1];
    if (typeof(s) != TYPE_STR)
      n = toint(s) + 1;
      n > length(this.error_list) && return 1;
    else
      n = s in this.error_names || "E_" + s in this.error_names;
      if (!n)
        return 1;
      endif
    endif
    return this.error_list[n];
  endmethod

  method error_name owner: HACKER
    "error_name(E_FOO) => \"E_FOO\"";
    return toliteral(@args);
    return this.error_names[toint(args[1]) + 1];
  endmethod

  method show_object owner: #2
    "Print object metadata and requested properties or verbs with caller authority; output may yield.";
    let val;
    let vs;
    let ps;
    let all_props;
    set_task_perms(caller_perms());
    const {object, ?what = {"props", "verbs"}} = args;
    player:notify(tostr("Object ID:  ", object));
    player:notify(tostr("Name:       ", object.name));
    const names = {"Parent", "Location", "Owner"};
    const vals = {parent(object), object.location, object.owner};
    for i in [1..length(vals)]
      if (!valid(vals[i]))
        val = "*** NONE ***";
      else
        val = vals[i].name + " (" + tostr(vals[i]) + ")";
      endif
      player:notify(tostr(names[i], ":      "[1..12 - length(names[i])], val));
    endfor
    let line = "Flags:     ";
    if (is_player(object))
      line = line + " player";
    endif
    for flag in ({"programmer", "wizard", "r", "w", "f"})
      if (object.(flag))
        line = line + " " + flag;
      endif
    endfor
    player:notify(line);
    if (player.programmer && (player.wizard || player == object.owner || object.r))
      vs = "verbs" in what ? verbs(object) | {};
      if (vs)
        player:notify("Verb definitions:");
        for v in (vs)
          $command_utils:suspend_if_needed(0);
          player:notify(tostr("    ", v));
        endfor
      endif
      if ("props" in what)
        ps = properties(object);
        if (ps)
          player:notify("Property definitions:");
          for p in (ps)
            $command_utils:suspend_if_needed(0);
            player:notify(tostr("    ", p));
          endfor
        endif
        all_props = $object_utils:all_properties(object);
        if (all_props != {})
          player:notify("Properties:");
          for p in (all_props)
            $command_utils:suspend_if_needed(0);
            const strng = `toliteral(object.(p)) ! E_PERM => "(Permission denied.)"';
            player:notify(tostr("    ", p, ": ", strng));
          endfor
        endif
      endif
    elseif (player.programmer)
      player:notify("** Can't list properties or verbs: permission denied.");
    endif
    if (object.contents)
      player:notify("Contents:");
      for o in (object.contents)
        $command_utils:suspend_if_needed(0);
        player:notify(tostr("    ", o.name, " (", o, ")"));
      endfor
    endif
  endmethod

  method show_property owner: #2
    "Print property ownership, permissions, and value with caller authority.";
    let owner;
    let perms;
    set_task_perms(caller_perms());
    const {object, pname} = args;
    if (pname in this.builtin_props)
      player:notify(tostr(object, ".", pname));
      player:notify("Built-in property.");
    else
      try
        {owner, perms} = property_info(object, pname);
      except error (ANY)
        player:notify(error[2]);
        return;
      endtry
      player:notify(tostr(object, ".", pname));
      player:notify(tostr("Owner:        ", valid(owner) ? tostr(owner.name, " (", owner, ")") | "*** NONE ***"));
      player:notify(tostr("Permissions:  ", perms));
    endif
    player:notify(tostr("Value:        ", $string_utils:print(object.(pname))));
  endmethod

  method show_verbdef owner: #2
    "Print a verb definition's owner, flags, aliases, and argument specification.";
    let owner;
    let perms;
    let names;
    set_task_perms(caller_perms());
    let {object, vname} = args;
    const hv = $object_utils:has_verb(object, vname);
    if (!hv)
      player:notify("That object does not define that verb.");
      return;
    endif
    if (hv[1] != object)
      player:notify(tostr("Object ", object, " does not define that verb, but its ancestor ", hv[1], " does."));
      object = hv[1];
    endif
    try
      {owner, perms, names} = verb_info(object, vname);
    except error (ANY)
      player:notify(error[2]);
      return;
    endtry
    const arg_specs = verb_args(object, vname);
    player:notify(tostr(object, ":", names));
    player:notify(tostr("Owner:            ", valid(owner) ? tostr(owner.name, " (", owner, ")") | "*** NONE ***"));
    player:notify(tostr("Permissions:      ", perms));
    player:notify(tostr("Direct Object:    ", arg_specs[1]));
    player:notify(tostr("Preposition:      ", arg_specs[2]));
    player:notify(tostr("Indirect Object:  ", arg_specs[3]));
  endmethod

  method explain_verb_syntax owner: #2
    "Return a command example for an argument specification, or zero for a method.";
    let thisobj;
    let adobj;
    let aprep;
    let aiobj;
    let dobj_part;
    let iobj_part;
    args[4..5] == {"none", "this"} && return 0;
    {thisobj, verb, adobj, aprep, aiobj} = args;
    const prep_part = aprep == "any" ? "to" | this:short_prep(aprep);
    ".........`any' => `to' (arbitrary),... `none' => empty string...";
    if (adobj == "this" && dobj == thisobj)
      dobj_part = dobjstr;
      iobj_part = !prep_part || aiobj == "none" ? "" | aiobj == "this" ? dobjstr | iobjstr;
    elseif (aiobj == "this" && iobj == thisobj)
      dobj_part = adobj == "any" ? dobjstr | adobj == "this" ? iobjstr | "";
      iobj_part = iobjstr;
    elseif (!("this" in args[3..5]))
      dobj_part = adobj == "any" ? dobjstr | "";
      iobj_part = prep_part && aiobj == "any" ? iobjstr | "";
    else
      return 0;
    endif
    return tostr(verb, dobj_part ? " " + dobj_part | "", prep_part ? " " + prep_part | "", iobj_part ? " " + iobj_part | "");
  endmethod

  method "verb_p*erms verb_permi*ssions" owner: #2
    "returns the permissions of the current verb (either the owner or the result of the most recent set_task_perms()).";
    return caller_perms();
  endmethod

  method "verb_loc*ation" owner: HACKER
    "returns the object where the current verb is defined.";
    return callers()[1][4];
  endmethod

  method verb_documentation owner: #2
    ":verb_documentation([object,verbname]) => documentation at beginning of verb code, if any";
    "default is the calling verb";
    let code;
    set_task_perms(caller_perms());
    const c = callers()[1];
    const {?object = c[4], ?vname = c[2]} = args;
    try
      code = verb_code(object, vname);
    except error (ANY)
      return error[2];
    endtry
    let doc = {};
    for line in (code)
      if (match(line, "^\"%([^\\\"]%|\\.%)*\";$"))
        "... now that we're sure `line' is just a string, eval() is safe...";
        doc = {@doc, $no_one:eval("; return " + line)[2]};
      else
        return doc;
      endif
    endfor
    return doc;
  endmethod

  method set_verb_documentation owner: #2
    ":set_verb_documentation(object,verbname,text)";
    "  changes documentation at beginning of verb code";
    "  text is either a string or a list of strings";
    "  returns a non-1 value if anything bad happens...";
    let svc;
    set_task_perms(caller_perms());
    const {object, vname, text} = args;
    const code = `verb_code(object, vname) ! ANY';
    typeof(code) == TYPE_ERR && return code;
    const vd = $code_utils:verb_documentation(object, vname);
    if (typeof(vd) == TYPE_ERR)
      return vd;
    elseif (!(typeof(text) in {TYPE_LIST, TYPE_STR}))
      return E_INVARG;
    else
      let newdoc = {};
      for l in (typeof(text) == TYPE_LIST ? text | {text})
        typeof(l) != TYPE_STR && return E_INVARG;
        newdoc = {@newdoc, $string_utils:print(l) + ";"};
      endfor
      svc = `set_verb_code(object, vname, {@newdoc, @code[length(vd) + 1..$]}) ! ANY';
      if (TYPE_ERR == typeof(svc))
        "... this shouldn't happen.  I'm not setting this code -d just yet...";
        return svc;
      else
        return 1;
      endif
    endif
  endmethod

  method parse_propref owner: #2
    "$code_utils:parse_propref(string)";
    "Parses string as a MOO-code property reference, returning {object-string, prop-name-string} for a successful parse and false otherwise.  It always returns the right object-string to pass to, for example, this-room:match_object.";
    let object;
    let prop;
    const s = args[1];
    const dot = index(s, ".");
    if (dot)
      object = s[1..dot - 1];
      prop = s[dot + 1..$];
      object == "" || prop == "" && return 0;
      if (object[1] == "$")
        object = `#0.(object[2..$]) ! ANY';
        typeof(object) != TYPE_OBJ && return 0;
        object = tostr(object);
      endif
    elseif (index(s, "$") == 1)
      object = "#0";
      prop = s[2..$];
    else
      return 0;
    endif
    return {object, prop};
  endmethod

  method parse_verbref owner: #2
    "$code_utils:parse_verbref(string)";
    "Parses string as a MOO-code verb reference, returning {object-string, verb-name-string} for a successful parse and false otherwise.  It always returns the right object-string to pass to, for example, this-room:match_object().";
    const s = args[1];
    const colon = index(s, ":");
    if (colon)
      let object = s[1..colon - 1];
      const verbname = s[colon + 1..$];
      !(object && verbname) && return 0;
      if (object[1] == "$")
        const pname = object[2..$];
        object = pname in properties(#0) ? #0.(pname) | E_PROPNF;
        if (typeof(object) != TYPE_OBJ)
          return 0;
        endif
        object = tostr(object);
      endif
      return {object, verbname};
    else
      return 0;
    endif
  endmethod

  method parse_argspec owner: HACKER
    ":parse_arg_spec(@args)";
    "  attempts to parse the given sequence of args into a verb_arg specification";
    "returns {verb_args,remaining_args} if successful.";
    "  e.g., :parse_arg_spec(\"this\",\"in\",\"front\",\"of\",\"any\",\"foo\"..)";
    "           => {{\"this\",\"in front of\",\"any\"},{\"foo\"..}}";
    "returns a string error message if parsing fails.";
    let verbargs;
    let rest;
    let gp;
    let nargs = length(args);
    nargs < 1 && return {{}, {}};
    const ds = args[1];
    if (ds == "tnt")
      return {{"this", "none", "this"}, listdelete(args, 1)};
    elseif (!(ds in {"this", "any", "none"}))
      return tostr("\"", ds, "\" is not a valid direct object specifier.");
    elseif (nargs < 2 || args[2] in {"none", "any"})
      verbargs = args[1..min(3, nargs)];
      rest = args[4..nargs];
    else
      gp = $code_utils:get_prep(@args[2..nargs]);
      !gp[1] && return tostr("\"", args[2], "\" is not a valid preposition.");
      verbargs = {ds, @gp[1..min(2, nargs = length(gp))]};
      rest = gp[3..nargs];
    endif
    if (length(verbargs) >= 3 && !(verbargs[3] in {"this", "any", "none"}))
      return tostr("\"", verbargs[3], "\" is not a valid indirect object specifier.");
    endif
    return {verbargs, rest};
  endmethod

  method prepositions owner: HACKER
    "Return the server's preposition names, refreshing the cached list when needed.";
    if (server_version() != this._version)
      this:_fix_preps();
    endif
    return this.prepositions;
  endmethod

  method short_prep owner: HACKER
    ":short_prep(p) => shortest preposition equivalent to p";
    "p may be a single word or one of the strings returned by verb_args().";
    if (server_version() != this._version)
      this:_fix_preps();
    endif
    let word = args[1];
    word = word[1..index(word + "/", "/") - 1];
    const p = word in this._other_preps;
    p && return this._short_preps[this._other_preps_n[p]];
    word in this._short_preps && return word;
    return "";
  endmethod

  method full_prep owner: HACKER
    "Expand a recognized preposition abbreviation, or return an empty string.";
    if (server_version() != this._version)
      this:_fix_preps();
    endif
    const prep = args[1];
    let p = prep in this._short_preps;
    p && return this.prepositions[p];
    p = prep in this._other_preps;
    p && return this.prepositions[this._other_preps_n[p]];
    return "";
  endmethod

  method get_prep owner: HACKER
    ":get_prep(@args) extracts the prepositional phrase from the front of args, returning a list consisting of the preposition (or \"\", if none) followed by the unused args.";
    ":get_prep(\"in\",\"front\",\"of\",...) => {\"in front of\",...}";
    ":get_prep(\"inside\",...)          => {\"inside\",...}";
    ":get_prep(\"frabulous\",...}       => {\"\", \"frabulous\",...}";
    let prep = "";
    const allpreps = {@this._short_preps, @this._other_preps};
    let rest = 1;
    for i in [1..length(args)]
      const accum = i == 1 ? args[1] | tostr(accum, " ", args[i]);
      if (accum in allpreps)
        prep = accum;
        rest = i + 1;
      endif
      !(accum in this._multi_preps) && return {prep, @args[rest..$]};
    endfor
    return {prep, @args[rest..$]};
  endmethod

  verb _fix_preps (this at this) owner: HACKER flags: "rxd"
    ":_fix_preps() updates the properties on this having to do with prepositions.";
    "_fix_preps should be called whenever we detect that a new server version has been installed.";
    let nothers;
    let others;
    let shorts;
    let longs;
    let all;
    const orig_args = verb_args(this, verb);
    let multis = nothers = (others = (shorts = (longs = {})));
    let i = 0;
    while (typeof(`set_verb_args(this, verb, {"this", tostr(i), "this"}) ! ANY') != TYPE_ERR)
      const l = verb_args(this, verb)[2];
      all = $string_utils:explode(l, "/");
      let s = all[1];
      for p in (listdelete(all, 1))
        if (length(p) <= length(s))
          s = p;
        endif
      endfor
      for p in (all)
        while (true)
          const j = rindex(p, " ");
          if (!j)
            break;
          endif
          multis = {p = p[1..j - 1], @multis};
        endwhile
      endfor
      longs = {@longs, l};
      shorts = {@shorts, s};
      others = {@others, @setremove(all, s)};
      nothers = {@nothers, @$list_utils:make(length(all) - 1, length(shorts))};
      i = i + 1;
    endwhile
    set_verb_args(this, verb, orig_args);
    this.prepositions = longs;
    this._short_preps = shorts;
    this._other_preps = others;
    this._other_preps_n = nothers;
    this._multi_preps = multis;
    this._version = server_version();
    return;
  endverb

  method find_verb_named owner: #2
    ":find_verb_named(object,name[,n])";
    "  returns the *number* of the first verb on object matching the given name.";
    "  optional argument n, if given, starts the search with verb n,";
    "  causing the first n verbs (1..n-1) to be ignored.";
    "  0 is returned if no verb is found.";
    "  This routine does not find inherited verbs.";
    let object;
    let name;
    let start;
    {object, name, ?start = 1} = args;
    for i in [start..length(verbs(object))]
      const verbinfo = verb_info(object, i);
      this:verbname_match(verbinfo[3], name) && return i;
    endfor
    return 0;
  endmethod

  method find_last_verb_named owner: #2
    ":find_last_verb_named(object,name[,n])";
    "  returns the *number* of the last verb on object matching the given name.";
    "  optional argument n, if given, starts the search with verb n-1,";
    "  causing verbs (n..length(verbs(object))) to be ignored.";
    "  -1 is returned if no verb is found.";
    "  This routine does not find inherited verbs.";
    let {object, name, ?last = -1} = args;
    if (last < 0)
      last = length(verbs(object));
    endif
    for i in [0..last - 1]
      const verbinfo = verb_info(object, last - i);
      this:verbname_match(verbinfo[3], name) && return last - i;
    endfor
    return -1;
  endmethod

  method find_callable_verb_named owner: #2
    ":find_callable_verb_named(object,name[,n])";
    "  returns the *number* of the first verb on object that matches the given";
    "  name and has the x flag set.";
    "  optional argument n, if given, starts the search with verb n,";
    "  causing the first n verbs (0..n-1) to be ignored.";
    "  0 is returned if no verb is found.";
    "  This routine does not find inherited verbs.";
    let object;
    let name;
    let start;
    {object, name, ?start = 1} = args;
    for i in [start..length(verbs(object))]
      const verbinfo = verb_info(object, i);
      index(verbinfo[2], "x") && this:verbname_match(verbinfo[3], name) && return i;
    endfor
    return 0;
  endmethod

  method "verbname_match(new)" owner: HACKER
    ":verbname_match(fullverbname,name) => TRUE iff `name' is a valid name for a verb with the given `fullname'";
    let v;
    let verblist = " " + args[1] + " ";
    let name = args[2];
    if (index(verblist, " " + name + " ") && !match(name, "[ *]"))
      "Note that if name has a * or a space in it, then it can only match one of the * verbnames";
      return 1;
    else
      const namelen = length(name);
      while (true)
        const m = match(verblist, "[^ *]*%(%*%)[^ ]*");
        if (!m)
          break;
        endif
        const vlast = m[2];
        v = strsub(verblist[m[1]..vlast], "*", "");
        if (namelen >= m[3][1][1] - m[1] && (!v || index(v, verblist[vlast] == "*" ? name[1..min(namelen, length(v))] | name) == 1))
          return 1;
        endif
        verblist = verblist[vlast + 1..$];
      endwhile
    endif
    return 0;
  endmethod

  method "find_verbs_containing find_verbs_matching find_verb_lines_containing find_verb_lines_matching" owner: #2
    "Search readable verb source and print matches and a total to player.";
    "Args: pattern, optional object/list or numbered lower bound (default 0), optional integer case flag.";
    "Global searches require objects() permission. A numbered bound never excludes UUID objects.";
    "Per-object helpers can suspend; enumeration is a snapshot and source reads retain caller authority.";
    const {pattern, ?where = 0, ?casematters = 0} = args;
    typeof(where) in {TYPE_INT, TYPE_OBJ, TYPE_LIST} || raise(E_TYPE);
    set_task_perms(caller_perms());
    const whole_database = typeof(where) == TYPE_INT;
    const candidates = whole_database ? objects() | typeof(where) == TYPE_LIST ? where | {where};
    const search = "_" + verb;
    let count = 0;
    for object in (candidates)
      if (whole_database && where != 0)
        if (!valid(object))
          continue;
        endif
        if (!is_uuobjid(object) && toint(object) < where)
          continue;
        endif
      endif
      count = count + this:(search)(pattern, object, casematters);
    endfor
    player:notify("");
    player:notify(tostr("Total: ", count, " verb", count != 1 ? "s." | "."));
  endmethod

  method "_find_verbs_containing _find_verbs_matching" owner: #2
    ":_find_verbs_containing(pattern,object[,casematters])";
    ":_find_verbs_matching(regexp,object[,casematters])";
    "number of verbs in object with code having a line containing pattern or matching regexp";
    "prints verbname and offending line to player";
    set_task_perms(caller_perms());
    const {pattern, o, ?casematters = 0} = args;
    if ($command_utils:running_out_of_time())
      player:notify(tostr("...", o));
      suspend(0);
    endif
    !valid(o) && return 0;
    let count = 0;
    const verbs = $object_utils:accessible_verbs(o);
    const _grep_verb_code = verb == "_find_verbs_matching" ? "_egrep_verb_code" | "_grep_verb_code";
    typeof(verbs) != TYPE_LIST && return player:notify(tostr("verbs(", o, ") => ", tostr(verbs)));
    for vnum in [1..length(verbs)]
      const l = this:(_grep_verb_code)(pattern, o, vnum, casematters);
      if (l)
        const owner = verb_info(o, vnum)[1];
        player:notify(tostr(o, ":", verbs[vnum], " [", valid(owner) ? owner.name | "Recycled Player", " (", owner, ")]:  ", l));
        count = count + 1;
      endif
      if ($command_utils:running_out_of_time())
        player:notify(tostr("...", o));
        suspend(0);
      endif
    endfor
    return count;
  endmethod

  method _grep_verb_code owner: #2
    ":_grep_verb_code(pattern,object,verbname[,casematters]) => line number or 0";
    "  returns line number on which pattern occurs in code for object:verbname";
    set_task_perms(caller_perms());
    const {pattern, object, vname, ?casematters = 0} = args;
    "The following gross kluge is due to Quade (#82589).  tostr is fast, and so we can check for nonexistence of a pattern very quickly this way rather than checking line by line.  MOO needs a compiler.  --Nosredna";
    let vc = `verb_code(object, vname) ! ANY';
    typeof(vc) == TYPE_ERR || !index(tostr(@vc), pattern, casematters) && return 0;
    for line in (vc)
      index(line, pattern, casematters) && return line;
    endfor
    return 0;
  endmethod

  method _egrep_verb_code owner: #2
    ":_egrep_verb_code(regexp,object,verbname[,casematters]) => 0 or line number";
    "  returns line number of first line matching regexp in object:verbname code";
    let vc;
    set_task_perms(caller_perms());
    const {pattern, object, vname, ?casematters = 0} = args;
    try
      for line in (vc = `verb_code(object, vname) ! ANY => {}')
        match(line, pattern, casematters) && return line;
      endfor
    except (E_INVARG)
      raise(E_INVARG, "Malformed regular expression.");
    endtry
    return 0;
  endmethod

  method _parse_audit_args owner: HACKER
    "Parse [from <start>] [to <end>] [for <name>].";
    "Takes a series of strings, most likely @args with dobjstr removed.";
    "Returns a list {INT start, INT end, STR name}, or {} if there is an error.";
    let fail = length(args) % 2;
    let start = 0;
    let end = toint(max_object());
    let match = "";
    while (args && !fail)
      const prep = args[1];
      if (prep == "from")
        start = `toint(player.location:match_object(args[2])) ! ANY';
        if (typeof(start) == TYPE_ERR)
          start = `toint(args[2]) ! ANY';
        endif
        if (typeof(start) == TYPE_ERR)
          fail = 1;
        endif
      elseif (prep == "to")
        end = `toint(player.location:match_object(args[2])) ! ANY';
        if (typeof(end) == TYPE_ERR)
          end = `toint(args[2]) ! ANY';
        endif
        if (typeof(end) == TYPE_ERR)
          fail = 1;
        endif
      elseif (prep == "for")
        match = args[2];
      else
        fail = 1;
      endif
      args = args[3..length(args)];
    endwhile
    return fail ? {} | {start, end, match};
  endmethod

  method help_db_list owner: #2
    ":help_db_list([player]) => list of help dbs";
    "in the order that they are consulted by player";
    let who;
    let h;
    {?who = player} = args;
    let olist = {who, @$object_utils:ancestors(who)};
    if (valid(who.location))
      olist = {@olist, who.location, @$object_utils:ancestors(who.location)};
    endif
    let dbs = {};
    for o in (olist)
      h = `o.help ! ANY => 0';
      if (typeof(h) == TYPE_OBJ)
        h = {h};
      endif
      if (typeof(h) == TYPE_LIST)
        for db in (h)
          if (typeof(db) == TYPE_OBJ && (valid(db) && !(db in dbs)))
            dbs = {@dbs, db};
          endif
        endfor
      endif
    endfor
    return setadd(dbs, $help);
  endmethod

  method help_db_search owner: HACKER
    ":help_db_search(string,dblist)";
    "  searches each of the help db's in dblist for a topic matching string.";
    "  Returns  {db,topic}  or  {$ambiguous_match,{topic...}}  or {}";
    let what;
    let dblist;
    let ts;
    {what, dblist} = args;
    let topics = {};
    let help = 1;
    for db in (dblist)
      $command_utils:suspend_if_needed(0);
      ts = `db:find_topics(what) ! ANY => 0';
      if ({what} == ts)
        return {db, ts[1]};
      endif
      if (ts && typeof(ts) == TYPE_LIST)
        if (help)
          help = db;
        endif
        for t in (ts)
          topics = setadd(topics, t);
        endfor
      endif
    endfor
    length(topics) > 1 && return {$ambiguous_match, topics};
    topics && return {help, topics[1]};
    return {};
  endmethod

  method corify_object owner: HACKER
    ":corify_object(object)  => string representing object";
    "  usually just returns tostr(object), but in the case of objects that have";
    "  corresponding #0 properties, return the appropriate $-string.";
    const object = args[1];
    "Just in case #0 is !r on some idiot core.";
    for p in (`properties(#0) ! ANY => {}')
      "And if for some reason, some #0 prop is !r.";
      `#0.(p) ! ANY' == object && return "$" + p;
    endfor
    return tostr(object);
  endmethod

  method inside_quotes owner: #2
    "See if the end of the string passed as args[1] ends 'inside' a doublequote.  Used by $code_utils:substitute.";
    let {string} = args;
    let quoted = 0;
    while (true)
      const i = index(string, "\"");
      if (!i)
        break;
      endif
      if (!quoted || (i == 1 || string[i - 1] != "\\"))
        quoted = !quoted;
      endif
      string = string[i + 1..$];
    endwhile
    return quoted;
  endmethod

  method verb_or_property owner: #2
    "verb_or_property(<obj>, <name> [, @<args>])";
    "Looks for a callable verb or property named <name> on <obj>.";
    "If <obj> has a callable verb named <name> then return <obj>:(<name>)(@<args>).";
    "If <obj> has a property named <name> then return <obj>.(<name>).";
    "Otherwise return E_PROPNF, or E_PERM if you don't have permission to read the property.";
    set_task_perms(caller_perms());
    const {object, name, @rest} = args;
    return `object:(name)(@rest) ! E_VERBNF, E_INVIND => `object.(name) ! ANY'';
  endmethod

  method task_valid owner: #2
    "Return whether an integer task ID identifies the current, queued, or running task.";
    const {id} = args;
    typeof(id) != TYPE_INT && return false;
    set_task_perms($no_one);
    return id == task_id() || id in $list_utils:slice(queued_tasks(), 1) > 0 || E_PERM == `kill_task(id) ! ANY';
  endmethod

  method task_owner owner: #2
    ":task_owner(INT task_id) => returns the owner of the task belonging to the id.";
    const a = $list_utils:assoc(args[1], queued_tasks());
    a && return a[5];
    return E_INVARG;
  endmethod

  method argstr owner: #2
    ":argstr(verb,args[,argstr]) => what argstr should have been.  ";
    "Recall that the command line is parsed into a sequence of words; `verb' is";
    "assigned the first word, `args' is assigned the remaining words, and argstr";
    "is assigned a substring of the command line, which *should* be the one";
    "starting first nonblank character after the verb, but is instead (because";
    "the parser is BROKEN!) the one starting with the first nonblank character";
    "after the first space in the line, which is not necessarily after the verb.";
    "Clearly, if the verb contains spaces --- which can happen if you use";
    "backslashes and quotes --- this loses, and argstr will then erroneously";
    "have extra junk at the beginning.  This verb, given verb, args, and the";
    "actual argstr, returns what argstr should have been.";
    verb = args[1];
    argstr = {@args, argstr}[3];
    const n = length(args = args[2]);
    !index(verb, " ") && return argstr;
    !args && return "";
    "space in verb => two possible cases:";
    "(1) first space was not in a quoted string.";
    "    first word of argstr == rest of verb unless verb ended on this space.";
    const nqargs = $string_utils:words(argstr);
    nqargs == args && return argstr;
    const nqn = length(nqargs);
    nqn == n + 1 && nqargs[2..nqn] == args && return argstr[$string_utils:word_start(argstr)[2][1]..length(argstr)];
    "(2) first space was in a quoted string.";
    "    argstr starts with rest of string";
    const qs = $string_utils:word_start("\"" + argstr);
    return argstr[qs[length(qs) - length(args) + 1][1] - 1..length(argstr)];
  endmethod

  method verbname_match owner: HACKER
    ":verbname_match(fullverbname,name) => TRUE iff `name' is a valid name for a verb with the given `fullname'";
    let v;
    let verblist = " " + args[1] + " ";
    let name = args[2];
    if (index(verblist, " " + name + " ") && !(index(name, "*") || index(name, " ")))
      "Note that if name has a * or a space in it, then it can only match one of the * verbnames";
      return 1;
    else
      const namelen = length(name);
      while (true)
        const star = index(verblist, "*");
        if (!star)
          break;
        endif
        const vstart = rindex(verblist[1..star], " ") + 1;
        const vlast = vstart + index(verblist[vstart..$], " ") - 2;
        v = strsub(verblist[vstart..vlast], "*", "");
        if (namelen >= star - vstart && (!v || index(v, verblist[vlast] == "*" ? name[1..min(namelen, length(v))] | name) == 1))
          return 1;
        endif
        verblist = verblist[vlast + 1..$];
      endwhile
    endif
    return 0;
  endmethod

  method substitute owner: HACKER
    "$code_utils:substitute(string,subs) => new line";
    "Subs are a list of lists, {{\"target\",\"sub\"},{...}...}";
    "Substitutes targets for subs in a delimited string fashion, avoiding substituting anything inside quotes, e.g. player:tell(\"don't sub here!\")";
    let s;
    let subs;
    let sub;
    {s, subs} = args;
    const lets = "abcdefghijklmnopqrstuvwxyz0123456789";
    for x in (subs)
      const len = length(sub = x[1]);
      const delimited = index(lets, sub[1]) && index(lets, sub[len]);
      let prefix = "";
      while (true)
        const i = index(s, sub);
        if (!i)
          break;
        endif
        prefix = prefix + s[1..i - 1];
        if (prefix == "" || (!delimited || !index(lets, prefix[$])) && (!delimited || (i + len > length(s) || !index(lets, s[i + len]))) && !this:inside_quotes(prefix))
          prefix = prefix + x[2];
        else
          prefix = prefix + s[i..i + len - 1];
        endif
        s = s[i + len..length(s)];
      endwhile
      s = prefix + s;
    endfor
    return s;
  endmethod

  method show_who_listing owner: #2
    ":show_who_listing(players[,more_players[,recipient]])";
    "Send the listing to recipient, defaulting to the caller for player and login hooks.";
    " prints a listing of the indicated players.";
    " For players in the first list, idle/connected times are shown if the player is logged in, otherwise the last_disconnect_time is shown.  For players in the second list, last_disconnect_time is shown, no matter whether the player is logged in.";
    let itimes;
    let offs;
    let otimes;
    let t;
    let i;
    let locations;
    let w1;
    let w2;
    let total;
    let ilen;
    let l;
    let active_str;
    const {plist, ?more_plist = {}, ?recipient = caller} = args;
    let idles = itimes = (offs = (otimes = {}));
    argstr = dobjstr = (iobjstr = (prepstr = ""));
    for p in (more_plist)
      if (!valid(p))
        recipient:notify(tostr(p, " <invalid>"));
      else
        t = `p.last_disconnect_time ! E_PROPNF';
        if (typeof(t) == TYPE_INT)
          if (!(p in offs))
            offs = {@offs, p};
            otimes = {@otimes, {-t, -t, p}};
          endif
        elseif (is_player(p))
          recipient:notify(tostr(p.name, " (", p, ") ", t == E_PROPNF ? "is not a $player." | "has a garbled .last_disconnect_time."));
        else
          recipient:notify(tostr(p.name, " (", p, ") is not a player."));
        endif
      endif
    endfor
    for p in (plist)
      if (p in offs)
      elseif (!valid(p))
        recipient:notify(tostr(p, " <invalid>"));
      else
        i = `idle_seconds(p) ! ANY';
        if (typeof(i) != TYPE_ERR)
          if (!(p in idles))
            idles = {@idles, p};
            itimes = {@itimes, {i, connected_seconds(p), p}};
          endif
        else
          t = `p.last_disconnect_time ! E_PROPNF';
          if (typeof(t) == TYPE_INT)
            offs = {@offs, p};
            otimes = {@otimes, {-t, -t, p}};
          elseif (is_player(p))
            recipient:notify(tostr(p.name, " (", p, ") not logged in.", t == E_PROPNF ? "  Not a $player." | "  Garbled .last_disconnect_time."));
          else
            recipient:notify(tostr(p.name, " (", p, ") is not a player."));
          endif
        endif
      endif
    endfor
    !(idles || offs) && return 0;
    idles = $list_utils:sort_alist(itimes);
    offs = $list_utils:sort_alist(otimes);
    "...";
    "... calculate widths...";
    "...";
    const headers = {"Player name", @idles ? {"Connected", "Idle time"} | {"Last disconnect time", ""}, "Location"};
    let name_width = length(headers[1]);
    let names = locations = {};
    for lst in ({@idles, @offs})
      $command_utils:suspend_if_needed(0);
      p = lst[3];
      const namestr = tostr(p.name, " (", p, ")");
      name_width = max(length(namestr), name_width);
      names = {@names, namestr};
      let wlm = `p.location:who_location_msg(p) ! ANY';
      if (typeof(wlm) != TYPE_STR)
        wlm = valid(p.location) ? p.location.name | tostr("** Nowhere ** (", p.location, ")");
      endif
      locations = {@locations, wlm};
    endfor
    const time_width = 3 + (offs ? 12 | length("59 minutes"));
    const before = {0, w1 = 3 + name_width, w2 = w1 + time_width, w2 + time_width};
    "...";
    "...print headers...";
    "...";
    const su = $string_utils;
    let tell1 = headers[1];
    let tell2 = su:space(tell1, "-");
    for j in [2..4]
      tell1 = su:left(tell1, before[j]) + headers[j];
      tell2 = su:left(tell2, before[j]) + su:space(headers[j], "-");
    endfor
    recipient:notify(tell1);
    recipient:notify(tell2);
    "...";
    "...print lines...";
    "...";
    let active = 0;
    for i in [1..total = (ilen = length(idles)) + length(offs)]
      if (i <= ilen)
        lst = idles[i];
        if (lst[1] < 5 * 60)
          active = active + 1;
        endif
        l = {names[i], su:from_seconds(lst[2]), su:from_seconds(lst[1]), locations[i]};
      else
        const lct = offs[i - ilen][3].last_connect_time;
        const ldt = offs[i - ilen][3].last_disconnect_time;
        const ctime = `recipient:ctime(ldt) ! ANY => 0' || ctime(ldt);
        l = {names[i], lct <= time() ? ctime | "Never", "", locations[i]};
        if (i == ilen + 1 && idles)
          recipient:notify(su:space(before[2]) + "------- Disconnected -------");
        endif
      endif
      tell1 = l[1];
      for j in [2..4]
        tell1 = su:left(tell1, before[j]) + l[j];
      endfor
      recipient:notify(tell1);
      if ($command_utils:running_out_of_time())
        if ($login:is_lagging())
          "Check lag two ways---global lag, but we might still fail due to individual lag of the queue this runs in, so check again later.";
          recipient:notify(tostr("Plus ", total - i, " other players (", total, " total; out of time and lag is high)."));
          return;
        endif
        const now = time();
        suspend(0);
        if (time() - now > 10)
          recipient:notify(tostr("Plus ", total - i, " other players (", total, " total; out of time and lag is high)."));
          return;
        endif
      endif
    endfor
    "...";
    "...epilogue...";
    "...";
    recipient:notify("");
    if (total == 1)
      active_str = ", who has" + (active == 1 ? "" | " not");
    else
      if (active == total)
        active_str = active == 2 ? "s, both" | "s, all";
      elseif (active == 0)
        active_str = "s, none";
      else
        active_str = tostr("s, ", active);
      endif
      active_str = tostr(active_str, " of whom ha", active == 1 ? "s" | "ve");
    endif
    recipient:notify(tostr("Total: ", total, " player", active_str, " been active recently."));
    return total;
  endmethod

  method _egrep_verb_code_all owner: #2
    ":_egrep_verb_code_all(regexp,object,verbname[,casematters]) => list of lines number";
    "  returns list of all lines matching regexp in object:verbname code";
    let vc;
    set_task_perms(caller_perms());
    const {pattern, object, vname, ?casematters = 0} = args;
    let lines = {};
    for line in (vc = `verb_code(object, vname, 1, 0) ! ANY => {}')
      if (match(line, pattern, casematters))
        lines = {@lines, line};
      endif
    endfor
    return lines;
  endmethod

  method _grep_verb_code_all owner: #2
    ":_grep_verb_code_all(pattern,object,verbname[,casematters]) => list of lines";
    "  returns list of lines on which pattern occurs in code for object:verbname";
    let vc;
    set_task_perms(caller_perms());
    const {pattern, object, vname, ?casematters = 0} = args;
    let lines = {};
    for line in (vc = `verb_code(object, vname) ! ANY => {}')
      if (index(line, pattern, casematters))
        lines = {@lines, line};
      endif
    endfor
    return lines;
  endmethod

  method verb_usage owner: #2
    ":verb_usage([object,verbname]) => usage string at beginning of verb code, if any";
    "default is the calling verb";
    let docverb;
    set_task_perms(caller_perms());
    const c = callers()[1];
    let {?object = c[4], ?vname = c[2]} = args;
    const code = `verb_code(object, vname) ! ANY';
    typeof(code) == TYPE_ERR && return code;
    let doc = {};
    let indent = "^$";
    for line in (code)
      if (match(line, "^\"%([^\\\"]%|\\.%)*\";$"))
        "... now that we're sure `line' is just a string, eval() is safe...";
        const e = $no_one:eval(line)[2];
        let subs = match(e, "^%(%(Usage%|Syntax%): +%)%([^ ]+%)%(.*$%)");
        if (subs)
          "Server is broken, hence the next three lines:";
          if (subs[3][4][1] > subs[3][4][2])
            subs[3][4] = {0, -1};
          endif
          indent = "^%(" + $string_utils:space(length(substitute("%1", subs))) + " *%)%([^ ]+%)%(.*$%)";
          docverb = substitute("%3", subs);
          if (match(vname, "^[0-9]+$"))
            vname = docverb;
          endif
          doc = {@doc, substitute("%1", subs) + vname + substitute("%4", subs)};
        else
          subs = match(e, indent);
          if (subs)
            if (substitute("%3", subs) == docverb)
              doc = {@doc, substitute("%1", subs) + vname + substitute("%4", subs)};
            else
              doc = {@doc, e};
            endif
          elseif (indent)
            return doc;
          endif
        endif
      else
        return doc;
      endif
    endfor
    return doc;
  endmethod

  method verb_frame owner: HACKER
    "returns the callers() frame for the current verb.";
    return callers()[1];
  endmethod

  method verb_all_frames owner: HACKER
    "returns {this:verb_frame(), @callers()}.";
    return callers();
  endmethod

  method move_verb owner: #2
    ":move_verb(OBJ from, STR verb name, OBJ to, [STR new verb name]) -> Moves the specified verb from one object to another. Returns {OBJ, Full verb name} where the verb now resides if successful, error if not. To succeed, caller_perms() must control both objects and own the verb, unless called with wizard perms. Supplying a fourth argument moves the verb to a new name.";
    "Should handle verbnames with aliases and wildcards correctly.";
    let vinfo;
    const who = caller_perms();
    let {from, origverb, to, ?destverb = origverb} = args;
    if (typeof(from) != TYPE_OBJ || typeof(to) != TYPE_OBJ || typeof(origverb) != TYPE_STR || typeof(destverb) != TYPE_STR)
      "check this first so we can parse out long verb names next";
      return E_TYPE;
    endif
    const origverb_first = strsub(origverb[1..index(origverb + " ", " ") - 1], "*", "") || "*";
    const destverb_first = strsub(destverb[1..index(destverb + " ", " ") - 1], "*", "") || "*";
    !valid(from) || !valid(to) && return E_INVARG;
    if (from == to && destverb == origverb)
      "Moving same origverb onto the same object puts the verbcode in the wrong one. Just not allow";
      return E_NACC;
    elseif (!$perm_utils:controls(who, from) && !from.w || (!$perm_utils:controls(who, to) && !to.w))
      "caller_perms() is not allowed to hack on either object in question";
      return E_PERM;
    elseif (!$object_utils:defines_verb(from, origverb_first))
      "verb is not defined on the from object";
      return E_VERBNF;
    else
      vinfo = verb_info(from, origverb_first);
      if (vinfo && !$perm_utils:controls(who, vinfo[1]))
        "caller_perms() is not permitted to add a verb with the existing verb owner";
        return E_PERM;
      elseif (!who.programmer)
        return E_PERM;
      else
        "we now know that the caller's perms control the objects or the objects are writable, and we know that the caller's perms control the prospective verb owner (by more traditional means)";
        const vcode = verb_code(from, origverb_first);
        const vargs = verb_args(from, origverb_first);
        vinfo[3] = destverb == origverb ? vinfo[3] | destverb;
        const res = `add_verb(to, vinfo, vargs) ! ANY';
        typeof(res) == TYPE_ERR && return res;
        set_verb_code(to, destverb_first, vcode);
        delete_verb(from, origverb_first);
        return {to, vinfo[3]};
      endif
    endif
  endmethod

  method "move_prop*erty" owner: #2
    ":move_prop(OBJ from, STR prop name, OBJ to, [STR new prop name]) -> Moves the specified property and its contents from one object to another. Returns {OBJ, property name} where the property now resides if successful, error if not. To succeed, caller_perms() must control both objects and own the property, unless called with wizard perms. Supplying a fourth argument gives the property a new name on the new object.";
    let pinfo;
    const who = caller_perms();
    let {from, origprop, to, ?destprop = origprop} = args;
    if (typeof(from) != TYPE_OBJ || typeof(to) != TYPE_OBJ || typeof(origprop) != TYPE_STR || typeof(destprop) != TYPE_STR)
      return E_TYPE;
    endif
    if (!valid(from) || !valid(to))
      return E_INVARG;
    elseif (from == to && destprop == origprop)
      "Moving same prop onto the same object puts the contents in the wrong one. Just not allow";
      return E_NACC;
    elseif (!$perm_utils:controls(who, from) && !from.w || (!$perm_utils:controls(who, to) && !to.w))
      "caller_perms() is not allowed to hack on either object in question";
      return E_PERM;
    elseif (!$object_utils:defines_property(from, origprop))
      "property is not defined on the from object";
      return E_PROPNF;
    else
      pinfo = property_info(from, origprop);
      if (pinfo && !$perm_utils:controls(who, pinfo[1]))
        "caller_perms() is not permitted to add a property with the existing property owner";
        return E_PERM;
      elseif (!who.programmer)
        return E_PERM;
      else
        "we now know that the caller's perms control the objects or the objects are writable, and we know that the caller's perms control the prospective property owner (by more traditional means)";
        const pdata = from.(origprop);
        const pname = destprop == origprop ? origprop | destprop;
        const res = `add_property(to, pname, pdata, pinfo) ! ANY';
        typeof(res) == TYPE_ERR && return res;
        delete_property(from, origprop);
        return {to, pname};
      endif
    endif
  endmethod

  method eval_d_util owner: #2
    "Do not remove this verb!  This is an auxiliary verb for :eval_d().";
  endmethod

  method display_callers owner: #2
    ":display_callers([callers() style list]) - displays the output of the given argument, assumed to be a callers() output. See `help callers()' for details. Will use callers() explicitly if no argument is passed.";
    const call = caller_perms() == player ? "notify_lines" | "tell_lines";
    player:(call)(this:callers_text(@args));
  endmethod

  method callers_text owner: #2
    "Format caller frames with complete values; derive column widths from the data.";
    const {?frames = callers()} = args;
    const headers = {"This", "Verb", "Permissions", "VerbLocation", "Player"};
    let rows = {};
    let widths = { length(header) for header in (headers) };
    for frame in (frames)
      let row = {};
      for position in [1..5]
        const value = frame[position];
        let text;
        if (position == 2)
          text = tostr(value, "(", `frame[6] ! E_RANGE => 0', ")");
        else
          text = tostr(value, "(", valid(value) ? value.name | "invalid", ")");
        endif
        row = {@row, text};
        widths[position] = max(widths[position], length(text));
      endfor
      rows = {@rows, row};
    endfor
    const separator = $string_utils:from_list({ $string_utils:space(width, "-") for width in (widths) }, " ");
    let output = {};
    for columns in ({headers, @rows})
      output = {@output, $string_utils:from_list({ $string_utils:left(columns[index], widths[index]) for index in [1..5] }, " ")};
      length(output) == 1 && (output = {@output, separator});
    endfor
    return {@output, separator};
  endmethod

  method "set_property_value set_verb_or_property" owner: #2
    ":set_property_value(object, property, value)";
    " set_verb_or_property(same) -- similar to `verb_or_property'";
    "  -- attempts to set <object>.<property> to <value>.  If there exists <object>:set_<property>, then it is called and its returned value is returned.  If not, we try to set the property directly; the result of this is returned.";
    let p;
    let v;
    set_task_perms(caller_perms());
    length(args) != 3 && return E_ARGS;
    const o = args[1];
    if (typeof(o) != TYPE_OBJ)
      return E_INVARG;
    elseif (!$recycler:valid(o))
      return E_INVIND;
    else
      p = args[2];
      typeof(p) != TYPE_STR && return E_INVARG;
      v = "set_" + p;
      $object_utils:has_callable_verb(o, v) && return o:(v)(args[3]);
      return o.(p) = args[3];
    endif
  endmethod

  method owns_task owner: #2
    "$code_utils:owns_task(task_id, who)";
    "The purpose of this is to be faster than $code_utils:task_owner(task_id) in those cases where you are interested in whether a certain person owns the task rather than in determining the owner of a task where you have no preconceived notion of the owner.";
    return $list_utils:assoc(args[1], $wiz_utils:queued_tasks(args[2]));
  endmethod

  method dflag_on owner: #2
    "Syntax:  $code_utils:dflag_on()   => 0|1";
    "";
    "Returns true if the verb calling the verb that called this verb has the `d' flag set true. Returns false if it is !d. If there aren't that many callers, or the calling verb was a builtin such as eval, assume the debug flag is on for traceback purposes and return true.";
    "This is useful for determining whether the calling verb should return or raise an error to the verb that called it.";
    let c;
    return length(c = callers()) >= 2 ? `index(verb_info(c[2][4], c[2][2])[2], "d") && 1 ! E_INVARG => 1' | 1;
  endmethod

  method type_str owner: HACKER
    "type_str -- returns a string describing the type of args[1]";
    const x = args[1];
    const type_data = {1, 3.14, "", #0, E_NONE, {}};
    const type_strs = {"INT", "FLOAT", "STR", "OBJ", "ERR", "LIST"};
    for i in [1..length(type_data)]
      typeof(type_data[i]) == typeof(x) && return type_strs[i];
    endfor
    return "NONE";
  endmethod

  method dump_properties owner: #2
    ":dump_properties (object, create_flag): returns the list of strings representing the property information for this object and its ancestor objects in @dump format.";
    let create;
    let targname;
    let pquoted;
    let info;
    let value;
    set_task_perms(caller_perms());
    {dobj, create, ?targname = tostr(dobj)} = args;
    let result = {};
    for p in (`properties(dobj) ! ANY => {}')
      pquoted = toliteral(p);
      try
        info = property_info(dobj, p);
        value = dobj.(p);
      except error (ANY)
        result = {@result, tostr("\"", targname, ".(", pquoted, ") => ", toliteral(error[1]), " (", error[2], ")")};
        continue p;
      endtry
      if (create)
        const uvalue = typeof(value) == TYPE_LIST ? "{}" | 0;
        result = {@result, tostr("@prop ", targname, ".", pquoted, " ", uvalue || toliteral(value), " ", info[2] || "\"\"", info[1] == dobj.owner ? "" | tostr(" ", info[1]))};
        if (uvalue && value)
          result = {@result, tostr(";;", targname, ".(", pquoted, ") = ", toliteral(value))};
        endif
      else
        if (info[2] != "rc")
          result = {@result, tostr("@chmod ", targname, ".", pquoted, " ", info[2])};
        endif
        if (info[1] != dobj.owner)
          result = {@result, tostr("@chown ", targname, ".", pquoted, " ", info[1])};
        endif
        result = {@result, tostr(";;", targname, ".(", pquoted, ") = ", toliteral(value))};
      endif
      $command_utils:suspend_if_needed(0);
    endfor
    for a in ($object_utils:ancestors(dobj))
      for p in (`properties(a) ! ANY => {}')
        $command_utils:suspend_if_needed(1);
        pquoted = toliteral(p);
        try
          value = dobj.(p);
        except error (ANY)
          result = {@result, tostr("\"", targname, ".(", pquoted, ") => ", toliteral(error[1]), " (", error[2], ")")};
          continue p;
        endtry
        const avalue = `a.(p) ! ANY';
        if (typeof(avalue) == TYPE_ERR || value != avalue)
          result = {@result, tostr(";;", targname, ".(", pquoted, ") = ", toliteral(value))};
        endif
      endfor
      $command_utils:suspend_if_needed(1);
    endfor
    return result;
  endmethod

  method dump_preamble owner: #2
    ":dump_preamble(object): produces the @create command necessary to dump this object.";
    dobj = args[1];
    const parent = parent(dobj);
    let pstring = tostr(parent);
    for p in (properties(#0))
      if (#0.(p) == parent)
        pstring = "$" + p;
      endif
    endfor
    return tostr("@create ", pstring, " named ", dobj.name, ":", $string_utils:from_list(dobj.aliases, ","));
  endmethod

  method dump_verbs owner: #2
    ":dump_verbs (object, create_flag): returns the list of strings representing the verb information for this object in @dump format.";
    let create;
    let targname;
    let vname;
    let tail;
    set_task_perms(caller_perms());
    {dobj, create, ?targname = tostr(dobj)} = args;
    let result = {};
    let v = 1;
    while (true)
      const info = `verb_info(dobj, v) ! ANY';
      if (!(info || info == E_PERM))
        break;
      endif
      if (`index(info[3], "(old)") ! ANY' && 0)
        "Thought about skipping (old) verbs...";
        player:tell("Skipping ", dobj, ":\"", info[3], "\"...");
      else
        if (typeof(info) == TYPE_ERR)
          result = {@result, tostr("\"", dobj, ":", v, " --- ", info, "\";")};
        else
          const i = index(vname = info[3], " ");
          if (i)
            vname = vname[1..i - 1];
          endif
          if (vname[1] != "*")
            vname = strsub(vname, "*", "");
          endif
          args = verb_args(dobj, v);
          const prep = args[2] in {"any", "none"} ? args[2] | $code_utils:short_prep(args[2]);
          const perms = info[2] != (args == {"this", "none", "this"} ? "rxd" | "rd") ? info[2] || "\"\"" | "";
          if (create)
            if (info[1] == dobj.owner)
              tail = perms ? tostr(" ", perms) | "";
            else
              tail = tostr(" ", perms || info[2], " ", info[1]);
            endif
            result = {@result, tostr("@verb ", targname, ":\"", info[3], "\" ", args[1], " ", prep, " ", args[3], tail)};
          else
            result = {@result, tostr("@args ", targname, ":\"", info[3], "\" ", args[1], " ", prep, " ", args[3])};
            if (info[1] != dobj.owner)
              result = {@result, tostr("@chown ", targname, ":", vname, " ", info[1])};
            endif
            if (perms)
              result = {@result, tostr("@chmod ", targname, ":", vname, " ", perms)};
            endif
          endif
          const code = verb_code(dobj, v, 1, 1);
          if (code)
            result = {@result, tostr("@program ", targname, ":", vname), @code, ".", ""};
          endif
        endif
      endif
      if (`index(tostr(" ", info[3], " "), " * ") ! ANY')
        "... we have a * verb.  may as well forget trying to list...";
        "... the rest; they're invisible.  set v to something nonstring.";
        v = E_TYPE;
      else
        v = v + 1;
      endif
      $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method "_find_verb_lines_containing _find_verb_lines_matching" owner: #2
    ":_find_verb_lines_containing(pattern,object[,casematters])";
    ":_find_verb_lines_matching(regexp,object[,casematters])";
    "number of verbs in object with code having a line containing pattern or matching regexp";
    "prints verbname and all offending lines to player";
    set_task_perms(caller_perms());
    const {pattern, o, ?casematters = 0} = args;
    if ($command_utils:running_out_of_time())
      player:notify(tostr("...", o));
      suspend(0);
    endif
    !valid(o) && return 0;
    let count = 0;
    const verbs = $object_utils:accessible_verbs(o);
    typeof(verbs) != TYPE_LIST && return player:notify(tostr("verbs(", o, ") => ", tostr(verbs)));
    const _grep_verb_code_all = verb == "_find_verb_lines_matching" ? "_egrep_verb_code_all" | "_grep_verb_code_all";
    for vnum in [1..length(verbs)]
      let found = 0;
      for l in (this:(_grep_verb_code_all)(pattern, o, vnum, casematters))
        const owner = verb_info(o, vnum)[1];
        player:notify(tostr(o, ":", verbs[vnum], " [", valid(owner) ? owner.name | "Recycled Player", " (", owner, ")]:  ", l));
        found = 1;
        $command_utils:suspend_if_needed(0);
      endfor
      if (found)
        count = count + 1;
      endif
      if ($command_utils:running_out_of_time())
        player:notify(tostr("...", o));
        suspend(0);
      endif
    endfor
    return count;
  endmethod
endobject
