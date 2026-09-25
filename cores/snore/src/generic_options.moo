object GENERIC_OPTIONS [
  import_export_id -> "generic_options"
]
  name: "Generic Option Package"
  parent: ROOT_CLASS
  owner: HACKER
  fertile: true
  readable: true

  property _namelist (owner: HACKER, flags: "r") = "!";
  property extras (owner: HACKER, flags: "r") = {};
  property names (owner: HACKER, flags: "r") = {};
  property namewidth (owner: HACKER, flags: "rc") = 15;

  override aliases (owner: HACKER, flags: "rc") = {"Generic Option Package"};
  override description (owner: HACKER, flags: "rc") = "An option package. See help $generic_options.";
  override object_size (owner: HACKER, flags: "r") = {12729, 1084848672};

  method get owner: HACKER
    "Return the named value from an option map, or zero when the value is absent.";
    const {options, name} = args;
    typeof(options) != TYPE_MAP && return 0;
    return maphaskey(options, name) ? options[name] | 0;
  endmethod

  method set owner: HACKER
    "Return an updated option map or a diagnostic string. This method does not store the map.";
    "Typed options use check_NAME, type_NAME, or choices_NAME. Other options store boolean flags.";
    "False values remove an option. Object values remain valid inputs despite their truth value.";
    "Extra names expand through actual(name, value) into a list of option/value pairs.";
    let {options, name, value} = args;
    !(name in this.names || name in this.extras) && return "Unknown option:  " + name;
    typeof(value) == TYPE_ERR && return "Error value";
    if (value || typeof(value) == TYPE_OBJ)
      const checker = "check_" + name;
      const type_property = "type_" + name;
      const choice_property = "choices_" + name;
      if ($object_utils:has_callable_verb(this, checker))
        const checked = this:(checker)(value);
        typeof(checked) == TYPE_STR && return checked;
        value = checked[1];
      elseif ($object_utils:has_property(this, type_property))
        const types = this.(type_property);
        !this:istype(value, types) && return $string_utils:capitalize(this:desc_type(types) + " value expected.");
      elseif ($object_utils:has_property(this, choice_property))
        const choices = this.(choice_property);
        !$list_utils:assoc(value, choices) && return tostr("Allowed values: ", $string_utils:english_list($list_utils:slice(choices, 1), "(??)", " or "));
      else
        typeof(value) == TYPE_OBJ && return "Non-object value expected.";
        value = true;
      endif
    endif
    const updates = name in this.names ? {{name, value}} | this:actual(name, value);
    typeof(updates) != TYPE_LIST || !updates && return updates || "Not implemented.";
    typeof(options) != TYPE_MAP && (options = []);
    for update in (updates)
      const {option_name, option_value} = update;
      if (!option_value && typeof(option_value) != TYPE_OBJ)
        options = mapdelete(options, option_name);
      else
        options[option_name] = option_value;
      endif
    endfor
    return options;
  endmethod

  method parse owner: HACKER
    "Parse command words into {name}, {name, value}, or a diagnostic string.";
    "Accept +name, -name, !name, name=value, name value, and name is value.";
    "Pass numeric 0/1 switch tokens to parse_NAME hooks; set() normalizes stored flags.";
    "Additional arguments become the data list supplied to a parse_NAME hook.";
    let words = args[1];
    !words && return "";
    let option = words[1];
    words = listdelete(words, 1);
    const flag = option ? index("-+!", option[1]) | 0;
    flag && (option = option[2..$]);
    const equals = index(option, "=");
    let raw_value = {};
    if (equals)
      equals == 1 && return "Blank option name?";
      flag && return "Don't give a value if you use +, -, or !";
      words && return $string_utils:from_list(words, " ") + "??";
      raw_value = option[equals + 1..$];
      option = option[1..equals - 1];
    else
      !option && return "Blank option name?";
      if (flag)
        words && return "Don't give a value if you use +, -, or !";
        raw_value = flag == 2 ? 1 | 0;
      else
        words && words[1] == "is" && (words = listdelete(words, 1));
        raw_value = words;
      endif
    endif
    const name = this:_name(strsub(option, "-", "_"));
    typeof(name) != TYPE_STR && return tostr(name == $failed_match ? "Unknown" | "Ambiguous", " option:  ", option);
    !raw_value && return raw_value == {} ? {name} | {name, 0};
    const parser = "parse_" + name;
    $object_utils:has_callable_verb(this, parser) && return this:(parser)(name, raw_value, args[2..$]);
    const choice_property = "choices_" + name;
    $object_utils:has_property(this, choice_property) && return this:parsechoice(name, raw_value, this.(choice_property));
    raw_value in {0, "0", {"0"}} && return {name, 0};
    raw_value in {1, "1", {"1"}} && return {name, 1};
    return tostr("Option is a flag, use `+", option, "' or `-", option, "' (or `!", option, "')");
  endmethod

  method _name owner: HACKER
    "Resolve an exact option name or unique prefix. Return a match sentinel on failure.";
    const {name} = args;
    name in this.names || name in this.extras && return name;
    const names = this._namelist;
    const delimiter = names[1];
    const start = index(names, delimiter + name);
    !start && return $failed_match;
    start != rindex(names, delimiter + name) && return $ambiguous_match;
    const finish = index(names[start + 1..$], delimiter);
    return names[start + 1..start + finish - 1];
  endmethod

  method add_name owner: HACKER
    "Add a name or change its extra-name status. Return whether the definition changed.";
    "Only a principal that controls this package can change names. Return E_PERM or E_INVARG.";
    const {name, ?is_extra = false} = args;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    !name || match(name, "[-!+= ]") && return E_INVARG;
    const exists = name in this.names || name in this.extras;
    if (is_extra)
      name in this.extras && return false;
      this.names = setremove(this.names, name);
      this.extras = setadd(this.extras, name);
    else
      name in this.names && return false;
      this.extras = setremove(this.extras, name);
      this.names = setadd(this.names, name);
    endif
    if (!exists)
      const delimiter = this._namelist[1];
      !index(this._namelist, delimiter + name + delimiter) && (this._namelist = tostr(this._namelist, name, delimiter));
    endif
    return true;
  endmethod

  method remove_name owner: HACKER
    "Remove an option definition. Return whether it existed, or E_PERM for an unauthorized caller.";
    const {name} = args;
    !$perm_utils:controls(caller_perms(), this) && return E_PERM;
    !(name in this.names || name in this.extras) && return false;
    const delimiter = this._namelist[1];
    this._namelist = strsub(this._namelist, delimiter + name + delimiter, delimiter);
    this.names = setremove(this.names, name);
    this.extras = setremove(this.extras, name);
    return true;
  endmethod

  method show owner: HACKER
    "Return lines describing one option or a list of options from the supplied map.";
    const {options, name} = args;
    if (typeof(name) == TYPE_LIST)
      let lines = {};
      for option in (name)
        lines = {@lines, @this:show(options, option)};
      endfor
      return lines;
    endif
    !(name in this.names || name in this.extras) && return {"Unknown option:  " + name};
    const formatter = "show_" + name;
    const choice_property = "choices_" + name;
    let value = this:get(options, name);
    let description = {};
    if ($object_utils:has_callable_verb(this, formatter))
      {value, description} = this:(formatter)(@args);
    elseif ($object_utils:has_property(this, formatter) && value in {false, true, 0, 1})
      description = this.(formatter)[value ? 2 | 1];
    elseif ($object_utils:has_property(this, choice_property))
      const choices = this.(choice_property);
      if (!value && typeof(value) != TYPE_OBJ)
        description = choices[1][2];
      else
        const choice = $list_utils:assoc(value, choices);
        !choice && return {name + " has unexpected value " + toliteral(value)};
        description = choice[2];
      endif
    else
      name in this.extras && return {name + " not documented (complain)"};
      description = {"not documented (complain)"};
      if (typeof(value) in {TYPE_LIST, TYPE_STR})
        description = {toliteral(value), @description};
        value = "";
      endif
    endif
    typeof(description) == TYPE_STR && (description = {description});
    let label = " " + name;
    if (value in {false, true, 0, 1})
      label = (value ? "+" | "-") + name;
    elseif (typeof(value) in {TYPE_OBJ, TYPE_STR, TYPE_INT} && value != "")
      label = tostr(" ", name, "=", value);
    endif
    let lines = {$string_utils:left(label + "  ", this.namewidth) + description[1]};
    for line in (description[2..$])
      lines = {@lines, $string_utils:space(this.namewidth) + line};
    endfor
    return lines;
  endmethod

  method actual owner: HACKER
    "Expand an extra name and value into option/value pairs. Descendants define the aliases.";
    return "Not implemented.";
  endmethod

  method istype owner: HACKER
    "Return whether a value matches a listed type or recursively described list element type.";
    const {value, types} = args;
    const value_type = typeof(value);
    value_type in types && return true;
    value_type != TYPE_LIST && return false;
    for type in (types)
      typeof(type) == TYPE_LIST && this:islistof(value, type) && return true;
    endfor
    return false;
  endmethod

  method islistof owner: HACKER
    "Return whether every element of a list matches one of the supplied type descriptions.";
    const {values, types} = args;
    for value in (values)
      !this:istype(value, types) && return false;
    endfor
    return true;
  endmethod

  method desc_type owner: HACKER
    "Describe option types, including recursively described lists. Return a diagnostic for unknown types.";
    const {types} = args;
    const names = [TYPE_INT -> "number", TYPE_OBJ -> "object", TYPE_STR -> "string", TYPE_LIST -> "list", TYPE_BOOL -> "boolean"];
    let descriptions = {};
    for type in (types)
      if (typeof(type) == TYPE_LIST)
        const inner = this:desc_type(type);
        descriptions = {@descriptions, length(type) > 1 ? "(" + inner + ")-list" | inner + "-list"};
      else
        !maphaskey(names, type) && return "Bad type list";
        descriptions = {@descriptions, names[type]};
      endif
    endfor
    return $string_utils:english_list(descriptions, "nothing", " or ");
  endmethod

  method parsechoice owner: HACKER
    "Resolve a unique choice prefix. Return {name, choice} or a diagnostic string.";
    let {name, raw_value, entries} = args;
    const choices = $list_utils:slice(entries, 1);
    const error = tostr("Allowed values for this flag: ", $string_utils:english_list(choices, "(??)", " or "));
    if (typeof(raw_value) == TYPE_LIST)
      length(raw_value) != 1 && return error;
      raw_value = raw_value[1];
    endif
    typeof(raw_value) != TYPE_STR && return error;
    const matches = { choice for choice in (choices) if index(choice, raw_value) == 1 };
    !matches && return error;
    length(matches) > 1 && return tostr(raw_value, " is ambiguous.");
    return {name, matches[1]};
  endmethod
endobject
