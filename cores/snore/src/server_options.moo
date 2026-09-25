object SERVER_OPTIONS [
  import_export_id -> "server_options"
]
  name: "Server Options"
  parent: ROOT_CLASS
  owner: #2
  readable: true

  property bg_ticks (owner: #2, flags: "rc") = 500000;
  property boot_msg (owner: #2, flags: "rc") = "";
  property command_fuzzy_threshold (owner: #2, flags: "r") = 0.3;
  property connect_msg (owner: #2, flags: "rc") = "*** Connected ***";
  property db_commit_queue_timeout_seconds (owner: #2, flags: "rc") = 5.0;
  property db_commit_queue_warn_seconds (owner: #2, flags: "rc") = 1.0;
  property fg_ticks (owner: #2, flags: "rc") = 800000;
  property help_msg (owner: #2, flags: "rc") = {
    "Snore Core server options",
    "",
    "fg_ticks and bg_ticks set the foreground and background task budgets.",
    "mooR permits larger budgets than traditional LambdaMOO. A suspend commits the current transaction.",
    "bg_seconds, fg_seconds, max_stack_depth, and queued_task_limit can also be configured.",
    "Use load_server_options() after changing runtime options; consult the mooR book for details.",
    "command_fuzzy_threshold controls the core's fuzzy command matching (default 0.3).",
    "The core uses its #0 builtin wrappers for quota and metadata policy.",
    "Call those interfaces when editing objects programmatically; a property here is not a security boundary.",
    "Connection notices depend on the configured host. connect_msg is the successful-login notice.",
    "The client controls visual wrapping and long-output paging; there is no screen-width setting."
  };
  property permit_writable_verbs (owner: #2, flags: "rc") = 0;
  property protect_add_property (owner: #2, flags: "rc") = 1;
  property protect_add_verb (owner: #2, flags: "rc") = 1;
  property protect_chparent (owner: #2, flags: "rc") = 1;
  property protect_force_input (owner: #2, flags: "rc") = 1;
  property protect_recycle (owner: #2, flags: "rc") = 1;
  property protect_set_property_info (owner: #2, flags: "r") = 1;
  property protect_set_verb_info (owner: #2, flags: "rc") = 1;
  property queued_task_limit (owner: #2, flags: "rc") = 300;
  property support_numeric_verbname_strings (owner: HACKER, flags: "r") = 0;

  override aliases (owner: #2, flags: "rc") = {"Server Options"};
  override object_size (owner: HACKER, flags: "r") = {6853, 1084848672};

  method help_msg owner: HACKER
    "Describe configured server options and protected builtin wrappers.";
    const output = {"On $server_options, the following settings have been established by the wizards:", ""};
    let wizonly = {};
    let etc = {};
    let mentioned = {};
    for x in (setremove(properties(this), "help_msg"))
      if (index(x, "protect_") == 1)
        mentioned = {@mentioned, x[9..$]};
        wizonly = {@wizonly, tostr(x[9..$], "() is ", this.(x) ? "" | "not ", "wizonly.")};
      else
        etc = {@etc, tostr("$server_options.", x, " = ", $string_utils:print(this.(x)))};
      endif
    endfor
    if ("set_verb_code" in wizonly)
      wizonly = {@wizonly, "", "Note: since the 'set_verb_code' built-in function is wiz-only, then the '.program' built-in command is wiz-only too."};
    endif
    let bf = $set_utils:intersection(verbs(#0), mentioned);
    if (bf)
      bf = $list_utils:sort(bf);
      etc = {@etc, "", "In your code, #0:(built-in)(@args) should be called rather than built-in(@args) when you would use one of the following built-in functions:", $string_utils:english_list(bf) + ".", "Example: #0:" + bf[1] + "(@args) should be used instead of " + bf[1] + "(@args)"};
    endif
    return {@this.help_msg, @output, @wizonly, "", @etc};
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (!caller_perms().wizard)
      raise(E_PERM);
    endif
    this.support_numeric_verbname_strings = 0;
    pass(@args);
  endmethod
endobject
