object BUILD_OPTIONS
  name: "Builder Options"
  parent: GENERIC_OPTIONS
  owner: HACKER
  readable: true

  property show_audit_bytes (owner: #2, flags: "r") = {"@audit/@prospectus shows `<1K'", "@audit/@prospectus shows bytes"};
  property show_audit_float (owner: #2, flags: "r") = {
    "@audit/@prospectus shows integer sizes (1K)",
    "@audit/@prospectus shows floating-point sizes (1.0K)"
  };
  property show_bi_create (owner: HACKER, flags: "rc") = {
    "@create/@recycle re-use object numbers.",
    "@create/@recycle call create()/recycle() directly."
  };
  property type_dig_exit (owner: HACKER, flags: "rc") = {1};
  property type_dig_room (owner: HACKER, flags: "rc") = {1};

  override _namelist = "!dig_room!dig_exit!create_flags!bi_create!audit_bytes!audit_float!";
  override aliases = {"Builder Options"};
  override description = {"Option package for $builder commands.  See `help @build-options'."};
  override import_export_id = "build_options";
  override names = {
    "dig_room",
    "dig_exit",
    "create_flags",
    "bi_create",
    "audit_bytes",
    "audit_float"
  };
  override namewidth = 20;
  override object_size = {3690, 1084848672};

  method check_create_flags owner: HACKER
    value = args[1];
    if (m = match(value, "[^rwf]"))
      return tostr("Unknown object flag:  ", value[m[1]]);
    else
      return {tostr(index(value, "r") ? "r" | "", index(value, "w") ? "w" | "", index(value, "f") ? "f" | "")};
    endif
  endmethod

  method show_create_flags owner: HACKER
    if (value = this:get(@args))
      return {value, {tostr("Object flags for @create:  ", value)}};
    else
      return {0, {tostr("@create leaves all object flags reset")}};
    endif
  endmethod

  method parse_create_flags owner: HACKER
    raw = args[2];
    if (raw == 1)
      "...+create_flags => create_flags=r";
      return {args[1], "r"};
    elseif (typeof(raw) == TYPE_STR)
      return args[1..2];
    elseif (typeof(raw) != TYPE_LIST)
      return "???";
    elseif (length(raw) > 1)
      return tostr("I don't understand \"", $string_utils:from_list(listdelete(raw, 1), " "), "\"");
    else
      return {args[1], raw[1]};
    endif
  endmethod

  method "show_dig_room show_dig_exit" owner: HACKER
    name = args[2];
    what = verb == "show_dig_room" ? "room" | "exit";
    if ((value = this:get(args[1], name)) == 0)
      return {0, {tostr("@dig ", what, "s are children of $", what, ".")}};
    else
      return {value, {tostr("@dig ", what, "s are children of ", value, " (", valid(value) ? value.name | "invalid", ").")}};
    endif
  endmethod

  method "parse_dig_room parse_dig_exit" owner: HACKER
    {oname, raw, data} = args;
    if (typeof(raw) == TYPE_LIST)
      if (length(raw) > 1)
        return tostr("I don't understand \"", $string_utils:from_list(listdelete(raw, 1), " "), "\".");
      endif
      raw = raw[1];
    endif
    if (typeof(raw) != TYPE_STR)
      return "You need to give an object id.";
    elseif ($command_utils:object_match_failed(value = player:my_match_object(raw), raw))
      return "Option unchanged.";
    endif
    what = verb == "parse_dig_room" ? "room" | "exit";
    generic = #0.(what);
    if (value == generic)
      return {oname, 0};
    else
      if (!$object_utils:isa(value, generic))
        player:tell("Warning: ", value, " is not a descendant of $", what, ".");
      endif
      return {oname, value};
    endif
  endmethod
endobject
