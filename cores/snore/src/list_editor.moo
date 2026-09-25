object LIST_EDITOR [
  import_export_id -> "list_editor"
]
  name: "List Editor"
  parent: GENERIC_EDITOR
  owner: #96
  fertile: true
  readable: true

  property objects (owner: #96, flags: "r") = {};
  property properties (owner: #96, flags: "r") = {};

  override aliases (owner: #96, flags: "rc") = {"List Editor"};
  override blessed_task (owner: #96, flags: "rc") = 917349705;
  override commands (owner: #96, flags: "rc") = {
    {"e*dit", "<object>.<prop>"},
    {"save", "[<object>.<prop>]"},
    {"expl*ode", "[<range>]"}
  };
  override commands2 (owner: #96, flags: "rc") = {
    {
      "say",
      "emote",
      "lis*t",
      "ins*ert",
      "n*ext,p*rev",
      "del*ete",
      "f*ind",
      "s*ubst",
      "m*ove,c*opy",
      "expl*ode"
    },
    {"w*hat", "abort", "q*uit,done,pause"}
  };
  override depart_msg (owner: #96, flags: "rc") = "%N heads off to edit some properties.";
  override no_littering_msg (owner: #96, flags: "rc") = {
    "Partially edited list value will be here when you get back.",
    "To return, give the `@pedit' command with no arguments.",
    "Please come back and SAVE or ABORT if you don't intend to be working on this list value in the immediate future.  Keep Our MOO Clean!  No Littering!"
  };
  override object_size (owner: HACKER, flags: "r") = {11877, 1084848672};
  override return_msg (owner: #96, flags: "rc") = "%N comes back from editing properties.";
  override stateprops (owner: #96, flags: "r") = {
    {"properties", ""},
    {"objects", #-1},
    {"texts", 0},
    {"changes", 0},
    {"inserting", 1},
    {"readable", 0}
  };

  verb "e*dit" (any none none) owner: #96 flags: "rd"
    "Usage: edit object.property. Load a property unless the current buffer has unsaved edits.";
    let spec;
    const who = player in this.active;
    if (this:changed(who))
      player:tell("You are still editing ", this:working_on(who), ".  Please type ABORT or SAVE first.");
    else
      spec = this:parse_invoke(dobjstr, verb);
      if (spec)
        this:init_session(who, @spec);
      endif
    endif
  endverb

  verb save (any any any) owner: #96 flags: "rd"
    "Parse the buffer and write the property with current authorization.";
    let objprop;
    let result;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
      return;
    endif
    if (dobjstr)
      objprop = this:property_match_result(dobjstr);
      if (objprop)
        this.objects[who] = objprop[1];
        this.properties[who] = objprop[2];
      else
        return;
      endif
    else
      objprop = {this.objects[who], this.properties[who]};
    endif
    const value_list = this:to_value(@this:text(who));
    if (value_list[1])
      player:tell("Error on line ", value_list[1], ":  ", value_list[2]);
      player:tell("Value not saved to ", this:working_on(who));
    else
      result = this:set_property(@objprop, value_list[2]);
      if (result)
        player:tell("Value written to ", this:working_on(who), ".");
        this:set_changed(who, 0);
      else
        player:tell(result);
        player:tell("Value not saved to ", this:working_on(who));
      endif
    endif
  endverb

  verb "join* fill" (any any any) owner: #96 flags: "rd"
    "Reject text-only reflow commands in the structured list editor.";
    player:tell("I don't understand that.");
  endverb

  verb "expl*ode" (any any any) owner: #96 flags: "rd"
    "Usage: explode [range]. Expand nested values into separately editable lines.";
    let range;
    let ins;
    let i;
    let end;
    const who = this:loaded(player);
    if (!who)
      player:tell(this:nothing_loaded_msg());
    else
      range = this:parse_range(who, {"_", "1"}, @args);
      if (typeof(range) != TYPE_LIST)
        player:tell(range);
      elseif (range[3])
        player:tell("Junk at end of cmd:  ", range[3]);
      else
        const text = this.texts[who];
        let newins = ins = this.inserting[who];
        const start = range[1];
        let debris = this:explode_line("", text[start]);
        if (typeof(debris) == TYPE_STR)
          player:tell("Line ", start, ":  ", debris);
          return;
        endif
        if (!debris[1])
          debris = listdelete(debris, 1);
        endif
        let newlines = {};
        for line in (text[i = start + 1..end = range[2]])
          const dlen = length(debris);
          newlines = {@newlines, @debris[1..dlen - 1]};
          if (ins == i)
            newins = start + length(newlines) + 1;
          endif
          debris = this:explode_line(debris[dlen], line);
          if (typeof(debris) == TYPE_STR)
            player:tell("Line ", i, ":  ", debris);
            return;
          endif
          i = i + 1;
        endfor
        const explen = length(newlines) + length(debris);
        if (ins > end)
          newins = ins - (end - start + 1) + explen;
        endif
        this.texts[who] = {@text[1..start - 1], @newlines, @debris, @text[end + 1..length(text)]};
        this.inserting[who] = newins;
        player:tell("--> ", start, "..", start + explen - 1);
      endif
    endif
  endverb

  method value owner: #96
    "Return the readable buffer's parsed value, or report a parse error.";
    let who;
    const e = this:readable(who = args ? args[1] | player in this.active) || this:ok(who);
    !e && return e;
    const vlist = this:to_value(@this:text(who));
    if (vlist[1])
      player:tell("Error on line ", vlist[1], ":  ", vlist[2]);
      return E_INVARG;
    else
      return vlist[2];
    endif
  endmethod

  method working_on owner: #96
    "Return the session's object and property name for display.";
    const who = args[1];
    !who && return "????";
    const object = this.objects[who];
    const prop = this.properties[who] || "(???)";
    return valid(object) ? tostr("\"", object.name, "\"(", object, ")", "." + prop) | tostr(".", prop, " on an invalid object (", object, ")");
  endmethod

  method init_session owner: #96
    "Load a property value and record its target in an authorized session.";
    const who = args[1];
    if (this:ok(who))
      this:load(who, args[4]);
      this.objects[who] = args[2];
      this.properties[who] = args[3];
      player:tell("Now editing ", this:working_on(who), ".");
    endif
  endmethod

  method property_match_result owner: #96
    "Resolve object.property in the editor's matching scope; report failures and return zero.";
    let string;
    const pp = $code_utils:parse_propref(string = args[1]);
    if (!pp)
      player:tell("Property specification expected.");
      return 0;
    endif
    const objstr = pp[1];
    const prop = pp[2];
    let object = player:my_match_object(objstr, this:get_room(player));
    if ($command_utils:object_match_failed(object, objstr))
    elseif (!$object_utils:has_property(object, prop))
      player:tell(object.name, "(", object, ") has no \".", prop, "\" property.");
    else
      return {object, prop};
    endif
    return 0;
  endmethod

  method property owner: #2
    "WIZARDLY";
    const vl = $code_utils:verb_loc();
    caller != vl || caller_perms() != vl.owner && return E_PERM;
    set_task_perms(player);
    return args[1].(args[2]);
  endmethod

  method set_property owner: #2
    "WIZARDLY";
    let e;
    const vl = $code_utils:verb_loc();
    caller != vl || caller_perms() != vl.owner && return E_PERM;
    let {object, pname, value} = args;
    set_task_perms(player);
    if ($object_utils:has_callable_verb(object, "set_" + pname))
      const attempt = object:("set_" + pname)(value);
      typeof(attempt) != TYPE_ERR && return attempt;
    endif
    return typeof(e = (object.(pname) = value)) == TYPE_ERR ? e | 1;
  endmethod

  method explode_line owner: #96
    "Expand one value line while preserving its nesting and indentation.";
    let newlines;
    let v;
    const su = $string_utils;
    const prev = args[1];
    const line = su:triml(args[2]);
    const indent = length(args[2]) - length(line);
    if (line[1] == "@")
      const splicee = $no_one:eval("{" + line[2..length(line)] + "}");
      !splicee[1] && return "Can't eval what's after the @.";
      newlines = this:explode_list(indent + 1, splicee[2]);
      return {prev, @newlines};
    endif
    if (line[1] == "}")
      this:is_delimiter(prev) && !index(prev, "{") && return {tostr(args[2][1..indent], su:trim(prev), " ", line)};
      return args;
    elseif (line[1] != "{")
      return args;
    elseif (!rindex(line, "}"))
      this:is_delimiter(prev) && return {su:trimr(prev) + (rindex(prev, "{") ? " " | ", ") + line};
      return args;
    else
      v = $no_one:eval(line);
      !v[1] && return "Can't eval this line.";
      newlines = {@this:explode_list(indent + 2, v[2]), su:space(indent) + "}"};
      this:is_delimiter(prev) && return {su:trimr(prev) + (rindex(prev, "{") ? " {" | ", {"), @newlines};
      return {prev, su:space(indent) + "{", @newlines};
    endif
  endmethod

  method explode_list owner: #96
    ":explode_list(indent,list) => corresponding list of strings to use.";
    let lines = {};
    const indent = $string_utils:space(args[1]);
    for element in (args[2])
      if (typeof(element) == TYPE_STR)
        lines = {@lines, indent + "\"" + element};
      else
        lines = {@lines, indent + $string_utils:print(element)};
      endif
    endfor
    return lines;
  endmethod

  method is_delimiter owner: #96
    "Return whether a line opens or closes a multiline list.";
    const line = $string_utils:triml(args[1]);
    return line && (line[1] == "}" || (line[1] == "{" && !rindex(line, "}")));
  endmethod

  method to_value owner: #96
    ":to_value(@list_of_strings) => {line#, error_message} or {0,value}";
    "converts the given list of strings back into a value if possible";
    let char;
    let v;
    let stack = {};
    let curlist = {};
    let curstr = 0;
    let i = 0;
    for line in (args)
      i = i + 1;
      line = $string_utils:triml(line);
      if (!line)
        "skip blank lines";
      else
        char = line[1];
        if (char == "+")
          curstr == 0 && return {i, "previous line is not a string"};
          curstr = curstr + line[2..length(line)];
        else
          if (curstr != 0)
            curlist = {@curlist, curstr};
            curstr = 0;
          endif
          if (char == "}" || (char == "{" && !rindex(line, "}")))
            let comma = 0;
            for c in [1..length(line)]
              char = line[c];
              if (char == "}")
                comma && return {i, "unexpected `}'"};
                !stack && return {i, "too many }'s"};
                curlist = {@stack[1], curlist};
                stack = listdelete(stack, 1);
              elseif (char == "{")
                comma = 1;
                stack = {curlist, @stack};
                curlist = {};
              elseif (char == " ")
              elseif (!comma && char == ",")
                comma = 1;
              else
                return {i, tostr("unexpected `", char, "'")};
              endif
            endfor
          elseif (char == "\"")
            curstr = line[2..length(line)];
          elseif (char == "@")
            v = $no_one:eval("{" + line[2..length(line)] + "}");
            !v[1] && return {i, "Can't eval what's after the @"};
            curlist = {@curlist, @v[2]};
          else
            v = $no_one:eval(line);
            !v[1] && return {i, "Can't eval this line"};
            curlist = {@curlist, v[2]};
          endif
        endif
      endif
    endfor
    stack && return {i, "missing }"};
    curstr != 0 && return {0, {@curlist, curstr}};
    return {0, curlist};
  endmethod

  method parse_invoke owner: #96
    "Resolve and read a property for an internal editor invocation.";
    let string;
    let objprop;
    let value;
    caller != this && raise(E_PERM);
    string = args[1];
    if (!string)
      player:tell_lines({"Usage:  " + args[2] + " <object>.<property>", "        " + args[2] + "          (continues editing an unsaved property)"});
    else
      objprop = this:property_match_result(string);
      if (!objprop)
      else
        value = this:property(@objprop);
        if (TYPE_ERR == typeof(value))
          player:tell("Couldn't get property value:  ", value);
        elseif (typeof(value) != TYPE_LIST)
          player:tell("Sorry... expecting a list-valued property.");
          if (typeof(value) == TYPE_STR)
            player:tell("Use @notedit to edit string-valued properties");
          else
            player:tell("Anyway, you don't need an editor to edit `", value, "'.");
          endif
        else
          return {@objprop, this:explode_list(0, value)};
        endif
      endif
    endif
    return 0;
  endmethod
endobject
