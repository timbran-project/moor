object PROG [
  import_export_id -> "prog"
]
  name: "generic programmer"
  parent: BUILDER
  owner: #2
  fertile: true
  readable: true

  property eval_env (owner: HACKER, flags: "r") = "here=player.location;me=player";
  property eval_subs (owner: HACKER, flags: "r") = {};
  property eval_ticks (owner: HACKER, flags: "r") = 3;
  property prog_options (owner: #2, flags: "rc") = [];

  override aliases (owner: #2, flags: "rc") = {"generic", "programmer"};
  override description (owner: #2, flags: "rc") = "You see a player who is too experienced to have any excuse for not having a description.";
  override features (owner: HACKER, flags: "r") = {
    PASTING_FEATURE,
    STAGE_TALK,
    UTILITY_FEATURE,
    BUILDER_FEATURE,
    PROGRAMMER_FEATURE
  };
  override help (owner: #2, flags: "rc") = {PROG_HELP, BUILTIN_FUNCTION_HELP, VERB_HELP, CORE_HELP};
  override mail_notify (owner: #2, flags: "rc");
  override object_size (owner: HACKER, flags: "r") = {59612, 1084848672};

  method _kill_task_message owner: #2
    "Print the identity and source location of a killed task.";
    set_task_perms(caller_perms());
    const task = args[1];
    player:notify(tostr("Killed: ", $string_utils:right(tostr("task ", task[1]), 17), ", verb ", task[6], ":", task[7], ", line ", task[8], task[9] != task[6] ? ", this==" + tostr(task[9]) | ""));
  endmethod

  method set_eval_env owner: HACKER
    "set_eval_env(string);";
    "Run <string> through eval.  If it doesn't compile, return E_INVARG.  If it crashes, well, it crashes.  If it works okay, set .eval_env to it and set .eval_ticks to the amount of time it took.";
    if (is_player(this) && $perm_utils:controls(caller_perms(), this))
      const program = args[1];
      const value = $no_one:eval_d(";ticks = ticks_left();" + program + ";return ticks - ticks_left() - 2;");
      !value[1] && return E_INVARG;
      typeof(value[2]) == TYPE_ERR && return value[2];
      try
        const ok = this.eval_env = program;
        this.eval_ticks = value[2];
        return 1;
      except error (ANY)
        return error[1];
      endtry
    endif
  endmethod

  method eval_cmd_string owner: #2
    ":eval_cmd_string(string[,debug])";
    "Evaluates the string the way this player would normally expect to see it evaluated if it were typed on the command line.  debug (defaults to 1) indicates how the debug flag should be set during the evaluation.";
    " => {@eval_result, ticks, seconds}";
    "where eval_result is the result of the actual eval() call.";
    "";
    "For the case where string is an expression, we need to prefix `return ' and append `;' to string before passing it to eval().  However this is not appropriate for statements, where it is assumed an explicit return will be provided somewhere or that the return value is irrelevant.  The code below assumes that string is an expression unless it either begins with a semicolon `;' or one of the MOO language statement keywords.";
    "Next, the substitutions described by this.eval_subs, which should be a list of pairs {string, sub}, are performed on string";
    "Finally, this.eval_env is prefixed to the beginning while this.eval_ticks is subtracted from the eventual tick count.  This allows string to refer to predefined variables like `here' and `me'.";
    set_task_perms(caller_perms());
    let {program, ?debug = 1} = args;
    program = program + ";";
    debug = debug ? 38 | 0;
    if (!match(program, "^ *%(;%|%(if%|fork?%|return%|while%|try%)[^a-z0-9A-Z_]%)"))
      program = "return " + program;
    endif
    program = tostr(this.eval_env, ";", $code_utils:substitute(program, this.eval_subs));
    let ticks = ticks_left() - 53 - this.eval_ticks + debug;
    let seconds = seconds_left();
    const value = debug ? eval(program) | $code_utils:eval_d(program);
    seconds = seconds - seconds_left();
    ticks = ticks - ticks_left();
    return {@value, ticks, seconds};
  endmethod

  method eval_value_to_string owner: #2
    "Format an evaluation result, including object names and sentinel descriptions.";
    let a;
    set_task_perms(caller_perms());
    const val = args[1];
    if (typeof(val) == TYPE_OBJ)
      return tostr("=> ", val, "  ", valid(val) ? "(" + val.name + ")" | (a = $list_utils:assoc(val, {{#-1, "<$nothing>"}, {#-2, "<$ambiguous_match>"}, {#-3, "<$failed_match>"}})) ? a[2] | "<invalid>");
    endif
    typeof(val) == TYPE_ERR && return tostr("=> ", toliteral(val), "  (", val, ")");
    return tostr("=> ", toliteral(val));
  endmethod

  method prog_option owner: #2
    ":prog_option(name)";
    "Returns the value of the specified prog option";
    caller == this || $perm_utils:controls(caller_perms(), this) && return $prog_options:get(this.prog_options, args[1]);
    return E_PERM;
  endmethod

  method set_prog_option owner: #2
    ":set_prog_option(oname,value)";
    "Changes the value of the named option.";
    "Returns a string error if something goes wrong.";
    !(caller == this || $perm_utils:controls(caller_perms(), this)) && return tostr(E_PERM);
    "...this is kludgy, but it saves me from writing the same verb 3 times.";
    "...there's got to be a better way to do this...";
    verb[1..4] = "";
    const foo_options = verb + "s";
    "...";
    const s = #0.(foo_options):set(this.(foo_options), @args);
    typeof(s) == TYPE_STR && return s;
    s == this.(foo_options) && return 0;
    this.(foo_options) = s;
    return 1;
  endmethod

  method set_eval_subs owner: #2
    "Copied from Player Class hacked with eval that does substitutions and assorted stuff (#8855):set_eval_subs by Geust (#24442) Fri Aug  5 13:18:59 1994 PDT";
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    const subs = args[1];
    typeof(subs) != TYPE_LIST && return E_TYPE;
    for pair in (subs)
      if (length(pair) != 2 || typeof(pair[1] != TYPE_STR) || typeof(pair[2] != TYPE_STR))
        return E_INVARG;
      endif
    endfor
    return `this.eval_subs = subs ! ANY';
  endmethod
endobject
