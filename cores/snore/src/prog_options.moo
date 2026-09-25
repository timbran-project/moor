object PROG_OPTIONS [
  import_export_id -> "prog_options"
]
  name: "Programmer Options"
  parent: GENERIC_OPTIONS
  owner: HACKER
  readable: true

  property show_copy_expert (owner: HACKER, flags: "rc") = {"@copy prints warning message.", "@copy omits warning message."};
  property show_eval_time (owner: HACKER, flags: "rc") = {
    "eval does not show ticks/seconds consumed.",
    "eval shows ticks/seconds consumed."
  };
  property show_list_all_parens (owner: HACKER, flags: "rc") = {
    "@list shows only necessary parentheses by default",
    "@list shows all parentheses by default"
  };
  property show_list_no_numbers (owner: HACKER, flags: "rc") = {"@list gives line numbers by default", "@list omits line numbers by default"};
  property show_list_show_permissions (owner: HACKER, flags: "rc") = {
    "@list does not display permissions in header",
    "@list displays permissions in header"
  };
  property show_rmverb_mail_backup (owner: HACKER, flags: "rc") = {
    "@rmverb does not email you a backup",
    "@rmverb emails you a backup before deleting the verb"
  };
  property "type_@prop_flags" (owner: HACKER, flags: "rc") = {2};

  override _namelist (owner: HACKER, flags: "r") = "!list_all_parens!list_no_numbers!list_show_permissions!eval_time!copy_expert!list_numbers!verb_args!@prop_flags!rmverb_mail_backup!";
  override aliases (owner: HACKER, flags: "rc") = {"Programmer Options"};
  override description (owner: HACKER, flags: "rc") = {"Option package for $prog commands.  See `help @prog-options'."};
  override extras (owner: HACKER, flags: "r") = {"list_numbers"};
  override names (owner: HACKER, flags: "r") = {
    "list_all_parens",
    "list_no_numbers",
    "eval_time",
    "copy_expert",
    "verb_args",
    "@prop_flags",
    "list_show_permissions",
    "rmverb_mail_backup"
  };
  override object_size (owner: HACKER, flags: "r") = {5196, 1084848672};

  method actual owner: HACKER
    "Expand list_numbers into the inverse list_no_numbers flag.";
    const {name, value} = args;
    name == "list_numbers" && return {{"list_no_numbers", !value}};
    return {{name, value}};
  endmethod

  method show owner: HACKER
    "Describe an option, including the list_numbers alias.";
    const {options, name} = args;
    name != "list_numbers" && return pass(@args);
    return {@pass(options, "list_no_numbers"), "(list_numbers is a synonym for -list_no_numbers)"};
  endmethod

  method show_verb_args owner: HACKER
    "Return {value, lines} describing the default argument specification for @verb.";
    const value = this:get(@args);
    !value && return {0, {"Default args for @verb:  none none none"}};
    return {value, {tostr("Default args for @verb:  ", $string_utils:from_list(value, " "))}};
  endmethod

  method check_verb_args owner: HACKER
    "Validate {dobj, prep, iobj} and normalize the preposition. Return {value} or an error string.";
    let value = args[1];
    typeof(value) != TYPE_LIST && return "List expected";
    length(value) != 3 && return "List of length 3 expected";
    !(value[1] in {"this", "none", "any"}) && return tostr("Invalid dobj specification:  ", value[1]);
    const prep = $code_utils:short_prep(value[2]);
    !(prep || value[2] in {"none", "any"}) && return tostr("Invalid preposition:  ", value[2]);
    !(value[3] in {"this", "none", "any"}) && return tostr("Invalid iobj specification:  ", value[3]);
    prep && (value[2] = prep);
    return {value};
  endmethod

  method parse_verb_args owner: HACKER
    "Parse verb arguments. A + switch selects this none this; zero selects the default.";
    let {name, raw, data} = args;
    if (typeof(raw) == TYPE_STR)
      raw = $string_utils:explode(raw, " ");
    elseif (typeof(raw) == TYPE_INT)
      return raw ? {name, {"this", "none", "this"}} | {name, 0};
    endif
    const parsed = $code_utils:parse_argspec(@raw);
    typeof(parsed) != TYPE_LIST && return tostr(parsed);
    parsed[2] && return tostr("I don't understand \"", $string_utils:from_list(parsed[2], " "), "\"");
    const value = {@parsed[1], "none", "none", "none"}[1..3];
    return {name, value == {"none", "none", "none"} ? 0 | value};
  endmethod

  method "show_@prop_flags" owner: HACKER
    "Return {value, lines} describing the default permissions for new properties.";
    const value = this:get(@args);
    !value && return {0, {"Default permissions for @property=`rc'."}};
    return {value, {tostr("Default permissions for @property=`", value, "'.")}};
  endmethod

  method "check_@prop_flags" owner: #2
    "Accept property permission letters r, w, and c. Return {flags} or a diagnostic string.";
    const {value} = args;
    typeof(value) != TYPE_STR || match(value, "[^rwc]") && return "Must be a string composed of the characters `rwc'.";
    return {value};
  endmethod

  method "parse_@prop_flags" owner: #2
    "Parse and validate default property permissions.";
    const {name, raw, data} = args;
    const checked = this:("check_@prop_flags")(raw);
    typeof(checked) == TYPE_STR && return checked;
    return {name, checked[1]};
  endmethod
endobject
