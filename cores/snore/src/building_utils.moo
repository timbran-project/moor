object BUILDING_UTILS [
  import_export_id -> "building_utils"
]
  name: "building utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  property class_string (owner: #2, flags: "rc") = {"p", "R", "E", "N", "C", "T", "F", "M", "H", "D", "U", "O"};
  property classes (owner: #2, flags: "rc") = {
    PLAYER,
    ROOM,
    EXIT,
    NOTE,
    CONTAINER,
    THING,
    FEATURE,
    MAIL_RECIPIENT,
    GENERIC_HELP,
    GENERIC_UTILS,
    GENERIC_OPTIONS
  };

  override aliases (owner: #2, flags: "rc") = {"building", "utils"};
  override description (owner: #2, flags: "rc") = {
    "This is the building utilities utility package.  See `help $building_utils' for more details."
  };
  override help_msg (owner: #2, flags: "rc") = {
    "Verbs useful for building.  For a complete description of a given verb, do `help $building_utils:verbname'.",
    "",
    "make_exit(spec,source,dest[,kind]) => a new exit",
    "          spec is an exit-spec as described in `help @dig'",
    "",
    "set_names(object, spec) - sets name and aliases for an object",
    "parse_names(spec) => list of {name, aliases}",
    "          in both of these, spec is of the form",
    "            <name>[[,:]<alias>,<alias>,...]",
    "          (as described in `help @rename')",
    "",
    "recreate(object, newparent) - effectively recycle and recreate object",
    "          as a child of newparent"
  };
  override object_size (owner: HACKER, flags: "r") = {12705, 1084848672};

  method make_exit owner: #2
    "make_exit(spec, source, dest[, kind]) -- create an exit object.";
    "Optional 4th arg gives a parent for the object to be created (distinct from $exit).";
    "Returns the object number as a list if successful, 0 if not.";
    set_task_perms(caller_perms());
    const {spec, source, dest, ?exit_kind = $exit} = args;
    let exit = player:_create(exit_kind);
    if (typeof(exit) == TYPE_ERR)
      player:notify(tostr("Cannot create new exit as a child of ", $string_utils:nn(exit_kind), ": ", exit, ".  See `help @build-options' for information on how to specify the kind of exit this command tries to create."));
      return;
    endif
    for f in ($string_utils:char_list(player:build_option("create_flags") || ""))
      exit.(f) = 1;
    endfor
    $building_utils:set_names(exit, spec);
    exit.source = source;
    exit.dest = dest;
    const source_ok = source:add_exit(exit);
    const dest_ok = dest:add_entrance(exit);
    move(exit, $nothing);
    const via = $string_utils:from_value(setadd(exit.aliases, exit.name), 1);
    if (source_ok)
      player:tell("Exit from ", source.name, " (", source, ") to ", dest.name, " (", dest, ") via ", via, " created with id ", exit, ".");
      if (!dest_ok)
        player:tell("However, I couldn't add ", exit, " as a legal entrance to ", dest.name, ".  You may have to get its owner, ", dest.owner.name, " to add it for you.");
      endif
      return {exit};
    endif
    if (dest_ok)
      player:tell("Exit to ", dest.name, " (", dest, ") via ", via, " created with id ", exit, ".  However, I couldn't add ", exit, " as a legal exit from ", source.name, ".  Get its owner, ", source.owner.name, " to add it for you.");
      return {exit};
    else
      player:_recycle(exit);
      player:tell("I couldn't add a new exit as EITHER a legal exit from ", source.name, " OR as a legal entrance to ", dest.name, ".  Get their owners, ", source.owner.name, " and ", dest.owner.name, ", respectively, to add it for you.");
      return 0;
    endif
  endmethod

  method set_names owner: #2
    "$building_utils:set_names(object, spec)";
    set_task_perms(caller_perms());
    const object = args[1];
    const names = this:parse_names(args[2]);
    const name = names[1] || object.name;
    return object:set_name(name) && object:set_aliases(names[2]);
  endmethod

  method recreate owner: #2
    ":recreate(object,newparent) -- effectively recycle and recreate the specified object as a child of parent.  Returns true if successful.";
    let {object, parent} = args;
    const who = caller_perms();
    !(valid(object) && valid(parent)) && return E_INVARG;
    if (who.wizard)
      "no problemo";
    elseif (who != object.owner || (who != parent.owner && !parent.f))
      return E_PERM;
    endif
    "Chparent any children to their grandparent instead of orphaning them horribly.  Have to do the chparent with wizperms, in case the children are owned by others, so do this before set_task_perms.";
    "Because this is done before set_task_perms() -- thus with wizard perms -- we save ticks and use chparent() instead of #0:chparent().  This will save many more ticks, if this is an object with many children.";
    const grandpa = parent(object);
    for c in (children(object))
      chparent(c, grandpa);
    endfor
    for item in (object.contents)
      if (!is_player(item))
        move(item, #-1);
      else
        move(item, $player_start);
      endif
    endfor
    set_task_perms(who);
    if ($object_utils:has_callable_verb(object, "recycle"))
      object:recycle();
    endif
    chparent(object, #-1);
    for p in (properties(object))
      delete_property(object, p);
    endfor
    for v in (verbs(object))
      delete_verb(object, 1);
    endfor
    chparent(object, parent);
    object.name = "";
    object.r = 0;
    object.f = 0;
    object.w = 0;
    if ($object_utils:has_callable_verb(parent, "initialize"))
      object:initialize();
    endif
    return 1;
  endmethod

  method parse_names owner: #2
    "$building_utils:parse_names(spec)";
    "Return {name, {alias, alias, ...}} from name,alias,alias or name:alias,alias";
    let aliases;
    let name;
    const spec = args[1];
    const colon = index(spec, ":");
    if (!colon)
      aliases = $string_utils:explode(spec, ",");
      if (!aliases)
        aliases = {spec};
      endif
      name = aliases[1];
    else
      aliases = $string_utils:explode(spec[colon + 1..$], ",");
      name = spec[1..colon - 1];
    endif
    return {name, $list_utils:map_arg($string_utils, "trim", aliases)};
  endmethod

  method audit_object_category owner: #2
    "Return the configured audit category character for an object.";
    let what = args[1];
    is_player(what) && return "P";
    while (valid(what))
      const i = what in this.classes;
      i && return this.class_string[i];
      what = parent(what);
    endwhile
    return " ";
  endmethod

  method object_audit_string owner: #2
    ":object_audit_string(object [,prospectus-style])";
    let vstr;
    let r;
    let name_field_len;
    let loc;
    let source;
    let destin;
    const {o, ?prospectus = 0} = args;
    const olen = length(tostr(max_object()));
    if (!$recycler:valid(o))
      return tostr(prospectus ? "          " | "", $quota_utils.byte_based ? "    " | "", $string_utils:right(o, olen), " Invalid Object!");
    endif
    if (prospectus)
      let kids = 0;
      for k in (children(o))
        $command_utils:suspend_if_needed(0);
        if (k.owner != o.owner)
          kids = 2;
          break k;
        elseif (kids == 0)
          kids = 1;
        endif
      endfor
      "The verbs() call below might fail, but that's OK";
      "Well, actually it won't cuz we seem to be a wizard.  Since you can get the number of verbs information from @verbs anyway, it seems kind of pointless to hide it here.";
      const v = verbs(o);
      if (v)
        vstr = tostr("[", $string_utils:right(length(v), 3), "] ");
      else
        vstr = "      ";
      endif
      if (o.r && o.f)
        r = "f";
      elseif (o.r)
        r = "r";
      elseif (o.f)
        r = "F";
      else
        r = " ";
      endif
      vstr = tostr(" kK"[kids + 1], r, $building_utils:audit_object_category(o), vstr);
    else
      vstr = "";
    endif
    if ($quota_utils.byte_based)
      vstr = tostr(this:size_string(`o.object_size[1] ! ANY => 0'), " ", vstr);
      name_field_len = 26;
    else
      name_field_len = 30;
    endif
    if (valid(o.location))
      loc = (o.location.owner == o.owner ? " " | "*") + "[" + o.location.name + "]";
    elseif ($object_utils:has_property(o, "dest") && $object_utils:has_property(o, "source"))
      if (typeof(o.source) != TYPE_OBJ)
        source = " <non-object> ";
      elseif (!valid(o.source))
        source = "<invalid>";
      else
        source = o.source.name;
        if (o.source.owner != o.owner)
          source = "*" + source;
        endif
      endif
      if (typeof(o.dest) != TYPE_OBJ)
        destin = " <non-object> ";
      elseif (!valid(o.dest))
        destin = "<invalid>";
      else
        destin = o.dest.name;
        if (o.dest.owner != o.owner)
          destin = "*" + destin;
        endif
      endif
      const srclen = min(length(source), 19);
      const destlen = min(length(destin), 19);
      loc = " " + source[1..srclen] + "->" + destin[1..destlen];
    elseif ($object_utils:isa(o, $room))
      loc = "";
      try
        for x in (o.entrances)
          if (typeof(x) == TYPE_OBJ && valid(x) && x.owner != o.owner && $object_utils:has_property(x, "dest") && x.dest == o)
            loc = loc + (loc ? ", " | "") + "<-*" + x.name;
          endif
        endfor
      except (ANY)
        if ($perm_utils:controls(player, o))
          loc = " BROKEN PROPERTY: .entrances";
        endif
      endtry
    else
      loc = " [Nowhere]";
    endif
    if (length(loc) > 41)
      loc = loc[1..37] + "..]";
    endif
    const namelen = min(length(o.name), name_field_len - 1);
    return tostr(vstr, $string_utils:right(o, olen), " ", $string_utils:left(o.name[1..namelen], name_field_len), loc);
  endmethod

  method "do_audit do_prospectus" owner: #2
    ":do_audit(who, start, end, match)";
    "audit who, with objects from start to end that match 'match'";
    ":do_prospectus(...)";
    "same, but with verb counts";
    let bytes;
    let num;
    let didit;
    const {who, start, end, match} = args;
    const pros = verb == "do_prospectus";
    "the set_task_perms is to make the task owned by the player. There are no other security aspects";
    set_task_perms(caller_perms());
    if (start == 0 && end == toint(max_object()) && !match && typeof(who.owned_objects) == TYPE_LIST && length(who.owned_objects) > 100 && !$command_utils:yes_or_no(tostr(who.name, " has ", length(who.owned_objects), " objects.  This will be a very long list.  Do you wish to proceed?")))
      const v = pros ? "@prospectus" | "@audit";
      return player:tell(v, " aborted.  Usage:  ", v, " [player] [from <start>] [to <end>] [for <match>]");
    endif
    player:tell(tostr("Objects owned by ", who.name, " (from #", start, " to #", end, match ? " matching " + match | "", ")", ":"));
    let count = bytes = 0;
    if (typeof(who.owned_objects) == TYPE_LIST)
      for o in (who.owned_objects)
        $command_utils:suspend_if_needed(0);
        !player:is_listening() && return;
        "Ranges filter numbered objects; UUID objects cannot be ranged and are always included.";
        num = `toint(o) ! ANY';
        if (typeof(num) == TYPE_ERR || (num >= start && num <= end))
          didit = this:do_audit_item(o, match, pros);
          count = count + didit;
          if (didit && $quota_utils.byte_based && $object_utils:has_property(o, "object_size"))
            bytes = bytes + o.object_size[1];
          endif
        endif
      endfor
    else
      for o in (owned_objects(who))
        $command_utils:suspend_if_needed(0);
        !player:is_listening() && return;
        if (!$recycler:valid(o))
          continue;
        endif
        num = `toint(o) ! ANY';
        if (typeof(num) == TYPE_ERR || (num >= start && num <= end))
          didit = this:do_audit_item(o, match, pros);
          count = count + didit;
          if (didit && $quota_utils.byte_based && $object_utils:has_property(o, "object_size"))
            bytes = bytes + o.object_size[1];
          endif
        endif
      endfor
    endif
    player:tell(tostr("-- ", count, " object", count == 1 ? "." | "s.", $quota_utils.byte_based ? tostr("  Total bytes: ", $string_utils:group_number(bytes), ".") | ""));
  endmethod

  method do_audit_item owner: #2
    ":do_audit_item(object, match-name-string, prospectus-flag)";
    const {o, match, pros} = args;
    let found = match ? 0 | 1;
    let names = `{o.name, @o.aliases} ! ANY => {o.name}';
    "Above to get rid of screwed up aliases";
    while (names && !found)
      if (index(names[1], match) == 1)
        found = 1;
      endif
      names = listdelete(names, 1);
    endwhile
    if (found)
      const line = $building_utils:object_audit_string(o, pros);
      player:tell(line);
      return 1;
    endif
    return 0;
  endmethod

  method size_string owner: #2
    "Copied from Roebare (#109000):size_string at Sat Nov 26 18:41:12 2005 PST";
    let factor;
    let threshold;
    let i;
    let unit;
    let size = args[1];
    typeof(size) != TYPE_INT && return E_INVARG;
    if (`!player:build_option("audit_float") ! ANY')
      "...use integers to determine a four-char string...";
      factor = 1000;
      threshold = {{1000, "B"}, {1000000, "K"}, {1000000000, "M"}};
      !size && return " ???";
      if (size < 0 || size > threshold[$][1])
        size < 0 || size > $maxint && return " >2G";
        "...floats still required to factor over $maxint...";
        return tostr($string_utils:right(floatstr(tofloat(size) / 1000000000.0, 0), 3), "G");
      elseif (size < threshold[1][1] && `!player:build_option("audit_bytes") ! ANY')
        return " <1K";
      endif
      for entry in ($list_utils:slice(threshold, 1))
        $command_utils:suspend_if_needed(0);
        i = $list_utils:iassoc(entry, threshold);
        if (size == entry)
          size = "1";
          try
            unit = threshold[i + 1][2];
          except error (E_RANGE)
            unit = "G";
          endtry
          break;
        elseif (size < entry)
          size = tostr(size / (entry / factor));
          unit = threshold[i][2];
          break;
        endif
      endfor
      return tostr($string_utils:right(size, 3), unit);
    else
      "...use floats to determine a six-char string...";
      size = tofloat(size);
      factor = 1024.0;
      "...be precise, `((1024.00 * 1024.00) * 1024.00) * 1024.00'...";
      threshold = {{1048576.0, "K"}, {1073741824.0, "M"}, {1099511627776.0, "G"}};
      !size && return "   ???";
      if (size < 0.0 || size > threshold[$][1])
        "...special handling for bad conversions & big numbers...";
        size < 0.0 || size > tofloat($maxint) && return "   >2G";
        return tostr($string_utils:right(floatstr(size / 1000000000.0, 1), 3), "G");
      endif
      for entry in ($list_utils:slice(threshold, 1))
        $command_utils:suspend_if_needed(0);
        i = $list_utils:iassoc(entry, threshold);
        if (size == entry)
          size = "1";
          try
            unit = threshold[i + 1][2];
          except error (E_RANGE)
            "...in another decade, maybe...";
            unit = "T";
          endtry
          break;
        elseif (size < entry)
          size = floatstr(size / (entry / factor), 1);
          unit = threshold[i][2];
          break;
        endif
      endfor
      return tostr($string_utils:right(size, 5), unit);
    endif
    "Rewritten by Roebare (#109000), 051119-26";
    "With inspiration from Miral (#107983) and assistance from Diopter (#98842)";
    "Byte & float display optional, per Nosredna (#2487), 051120-24";
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      pass(@args);
      this.classes = {$player, $room, $exit, $note, $container, $thing, $feature, $mail_recipient, $generic_help, $generic_utils, $generic_options};
    endif
  endmethod
endobject
