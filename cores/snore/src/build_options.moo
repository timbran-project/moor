object BUILD_OPTIONS [
  import_export_id -> "build_options"
]
  name: "Builder Options"
  parent: GENERIC_OPTIONS
  owner: HACKER
  readable: true

  property show_audit_bytes (owner: #2, flags: "r") = {"@audit/@prospectus shows '<1K'", "@audit/@prospectus shows bytes"};
  property show_audit_float (owner: #2, flags: "r") = {
    "@audit/@prospectus shows integer sizes (1K)",
    "@audit/@prospectus shows floating-point sizes (1.0K)"
  };
  property type_dig_exit (owner: HACKER, flags: "rc") = {1};
  property type_dig_room (owner: HACKER, flags: "rc") = {1};

  override _namelist (owner: HACKER, flags: "r") = "!dig_room!dig_exit!create_flags!audit_bytes!audit_float!";
  override aliases (owner: HACKER, flags: "rc") = {"Builder Options"};
  override description (owner: HACKER, flags: "rc") = {"Option package for builder commands. See help @build-options."};
  override names (owner: HACKER, flags: "r") = {"dig_room", "dig_exit", "create_flags", "audit_bytes", "audit_float"};
  override namewidth (owner: HACKER, flags: "rc") = 20;
  override object_size (owner: HACKER, flags: "r") = {3690, 1084848672};

  method check_create_flags owner: HACKER
    "Normalize object permissions to rwf order. Return {flags} or a diagnostic string.";
    const {value} = args;
    const invalid = match(value, "[^rwf]");
    invalid && return tostr("Unknown object flag:  ", value[invalid[1]]);
    return {tostr(index(value, "r") ? "r" | "", index(value, "w") ? "w" | "", index(value, "f") ? "f" | "")};
  endmethod

  method show_create_flags owner: HACKER
    "Return {value, lines} describing the permissions for newly created objects.";
    const value = this:get(@args);
    !value && return {0, {"@create leaves all object flags reset"}};
    return {value, {tostr("Object flags for @create:  ", value)}};
  endmethod

  method parse_create_flags owner: HACKER
    "Parse object permissions. The + switch selects r; validation occurs in check_create_flags.";
    const {name, raw, data} = args;
    raw == 1 && return {name, "r"};
    typeof(raw) == TYPE_STR && return {name, raw};
    typeof(raw) != TYPE_LIST && return "???";
    length(raw) > 1 && return tostr("I don't understand \"", $string_utils:from_list(listdelete(raw, 1), " "), "\"");
    return {name, raw ? raw[1] | ""};
  endmethod

  method "show_dig_room show_dig_exit" owner: HACKER
    "Return {value, lines} describing the parent used for rooms or exits created by @dig.";
    const {options, name} = args;
    const kind = verb == "show_dig_room" ? "room" | "exit";
    const value = this:get(options, name);
    value == 0 && return {0, {tostr("@dig ", kind, "s are children of $", kind, ".")}};
    return {value, {tostr("@dig ", kind, "s are children of ", value, " (", valid(value) ? value.name | "invalid", ").")}};
  endmethod

  method "parse_dig_room parse_dig_exit" owner: HACKER
    "Match a parent for @dig. Return {name, object}, zero for the default, or a diagnostic.";
    let {name, raw, data} = args;
    if (typeof(raw) == TYPE_LIST)
      length(raw) > 1 && return tostr("I don't understand \"", $string_utils:from_list(listdelete(raw, 1), " "), "\".");
      !raw && return "You need to give an object id.";
      raw = raw[1];
    endif
    typeof(raw) != TYPE_STR && return "You need to give an object id.";
    const value = player:my_match_object(raw);
    $command_utils:object_match_failed(value, raw) && return "Option unchanged.";
    const kind = verb == "parse_dig_room" ? "room" | "exit";
    const generic = $sysobj.(kind);
    value == generic && return {name, 0};
    !$object_utils:isa(value, generic) && player:tell("Warning: ", value, " is not a descendant of $", kind, ".");
    return {name, value};
  endmethod
endobject
