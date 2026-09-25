object NO_ONE [
  import_export_id -> "no_one"
]
  name: "Everyman"
  parent: MAIL_RECIPIENT_CLASS
  owner: HACKER
  player: true
  programmer: true
  readable: true

  property queued_task_limit (owner: #2, flags: "r") = 0;

  override aliases (owner: #2, flags: "r") = {"Everyman", "everyone", "no_one", "noone"};
  override description (owner: HACKER, flags: "rc") = "The character used for \"safe\" evals.";
  override home (owner: HACKER, flags: "rc") = #-1;
  override last_disconnect_time (owner: #2, flags: "r") = 2147483647;
  override mail_forward (owner: HACKER, flags: "rc") = "Everyman ($no_one) can not receive mail.";
  override object_size (owner: HACKER, flags: "r") = {5625, 1084848672};
  override ownership_quota (owner: HACKER, flags: "") = -10000;
  override page_echo_msg (owner: HACKER, flags: "rc") = "... no one out there to see it.";
  override size_quota (owner: HACKER, flags: "") = {0, 0, 1084781037, 0};

  method eval owner: #2
    "eval(code)";
    "Evaluate code with $no_one's permissions (so you won't damage anything).";
    "If code does not begin with a semicolon, set this = caller (in the code to be evaluated) and return the value of the first `line' of code.  This means that subsequent lines will not be evaluated at all.";
    "If code begins with a semicolon, set this = caller and let the code decide for itself when to return a value.  This is how to do multi-line evals.";
    const exp = args[1];
    this:bad_eval(exp) && return E_PERM;
    set_task_perms(this);
    exp[1] != ";" && return eval(tostr("this=", caller, "; return ", exp, ";"));
    return eval(tostr("this=", caller, ";", exp, ";"));
  endmethod

  method moveto owner: HACKER
    "Keep the unprivileged evaluation principal outside the world.";
    return 0;
  endmethod

  method eval_d owner: #2
    ":eval_d(code)";
    "exactly like :eval except that the d flag is unset";
    "Evaluate code with $no_one's permissions (so you won't damage anything).";
    "If code does not begin with a semicolon, set this = caller (in the code to be evaluated) and return the value of the first `line' of code.  This means that subsequent lines will not be evaluated at all.";
    "If code begins with a semicolon, set this = caller and let the code decide for itself when to return a value.  This is how to do multi-line evals.";
    const exp = args[1];
    this:bad_eval(exp) && return E_PERM;
    set_task_perms(this);
    exp[1] != ";" && return $code_utils:eval_d(tostr("this=", caller, "; return ", exp, ";"));
    return $code_utils:eval_d(tostr("this=", caller, ";", exp, ";"));
  endmethod

  method call_verb owner: #2
    "call_verb(object, verb name, args)";
    "Call verb with $no_one's permissions (so you won't damage anything).";
    "One could do this with $no_one:eval, but ick.";
    set_task_perms(this);
    return args[1]:(args[2])(@args[3]);
  endmethod

  method bad_eval owner: #2
    ":bad_eval(exp)";
    "  Returns 1 if the `exp' is inappropriate for use by $no_one.  In particular, if `exp' contains calls to `eval', `fork', `suspend', or `call_function' it is bad.  Similarly, if `player' is a nonvalid object (or a child of $garbage) the expression is considered `bad' because it is likely an attempt to anonymously spoof.";
    "  At present, the checks for bad builtins are overzealous.  It should check for delimited uses of the above calls, in case someone has a variable called `prevalent'.";
    const {exp} = args;
    if (index(exp, "eval") || index(exp, "fork") || index(exp, "suspend") || index(exp, "call_function"))
      "Well, they had one of the evil words in here.  See if it was in a quoted string or not -- we want to permit player:tell(\"Gentlemen use forks.\")";
      for bad in ({"eval", "fork", "suspend", "call_function"})
        let tempindex = 1;
        while (true)
          const l = index(exp[tempindex..$], bad, 0);
          if (!l)
            break;
          endif
          if ($code_utils:inside_quotes(exp[1..tempindex + l - 1]))
            tempindex = tempindex + l;
          else
            "it's there, bad unquoted string";
            return 1;
          endif
        endwhile
      endfor
    endif
    !$recycler:valid(player) && player >= #0 && return 1;
    return 0;
  endmethod

  method "set_*" owner: HACKER
    "Permit inherited setters only for wizard callers.";
    !caller_perms().wizard && return E_PERM;
    return pass(@args);
  endmethod
endobject
