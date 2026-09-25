object EDIT_OPTIONS [
  import_export_id -> "edit_options"
]
  name: "Edit Options"
  parent: GENERIC_OPTIONS
  owner: HACKER
  readable: true

  property show_eval_subs (owner: HACKER, flags: "rc") = {
    "Ignore .eval_subs when compiling verbs.",
    "Use .eval_subs when compiling verbs."
  };
  property show_local (owner: HACKER, flags: "rc") = {"Use in-MOO text editors.", "Ship text to client for local editing."};
  property show_no_parens (owner: HACKER, flags: "rc") = {
    "include all parentheses when fetching verbs.",
    "includes only necessary parentheses when fetching verbs."
  };
  property show_quiet_insert (owner: HACKER, flags: "rc") = {"Report line numbers on insert or append.", "No echo on insert or append."};

  override _namelist (owner: HACKER, flags: "r") = "!quiet_insert!eval_subs!local!no_parens!parens!noisy_insert!";
  override aliases (owner: HACKER, flags: "rc") = {"Edit Options"};
  override extras (owner: HACKER, flags: "r") = {"parens", "noisy_insert"};
  override names (owner: HACKER, flags: "r") = {"quiet_insert", "eval_subs", "local", "no_parens"};
  override namewidth (owner: HACKER, flags: "rc") = 20;
  override object_size (owner: HACKER, flags: "r") = {1856, 1084848672};

  method actual owner: HACKER
    "Expand parens and noisy_insert into their inverse stored flags.";
    const {name, value} = args;
    const index = name in {"parens", "noisy_insert"};
    index && return {{{"no_parens", "quiet_insert"}[index], !value}};
    return {{name, value}};
  endmethod

  method show owner: HACKER
    "Describe an editor option and explain inverse aliases.";
    const {options, name} = args;
    const index = name in {"parens", "noisy_insert"};
    !index && return pass(@args);
    const actual = {"no_parens", "quiet_insert"}[index];
    return {@pass(options, actual), tostr("(", name, " is a synonym for -", actual, ")")};
  endmethod
endobject
