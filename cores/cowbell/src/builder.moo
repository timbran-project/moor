object BUILDER
  name: "Generic Builder"
  parent: PLAYER
  location: FIRST_ROOM
  owner: HACKER
  programmer: true
  fertile: true
  readable: true

  override description = "Generic builder character prototype. Builders can create and modify basic objects and rooms. Inherits from player with building permissions.";
  override import_export_id = "builder";

  verb "@create" (any any any) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    spec = this:_parse_create_command(argstr);
    if (maphaskey(spec, 'error))
      this:_emit_create_error(spec['error]);
      return 0;
    endif
    parent_result = this:_resolve_create_parent(spec['parent]);
    if (maphaskey(parent_result, 'error))
      this:_emit_create_error(parent_result['error]);
      return 0;
    endif
    parent_obj = parent_result['parent];
    validation = this:_validate_create_parent(parent_obj);
    if (maphaskey(validation, 'error))
      this:_emit_create_error(validation['error]);
      return 0;
    endif
    name_info = this:_parse_create_names(spec['names]);
    if (maphaskey(name_info, 'error))
      this:_emit_create_error(name_info['error]);
      return 0;
    endif
    {primary_name, alias_list} = {name_info['primary], name_info['aliases]};
    new_obj = this:_create_child_object(parent_obj, primary_name, alias_list);
    this:_announce_create_success(new_obj, parent_obj, primary_name);
    return new_obj;
  endverb

  verb _parse_create_command (this none this) owner: HACKER flags: "rxd"
    "Parse raw @create argument string into parent token and name specification.";
    {raw_args} = args;
    trimmed = raw_args:trim();
    if (!trimmed)
      return ['error -> "Usage: @create <parent> named <name[:aliases]>"];
    endif
    {parent_token, names_clause} = this:_split_create_named_clause(trimmed);
    if (!parent_token)
      return ['error -> "You must specify the parent object to create from."];
    endif
    if (!names_clause)
      return ['error -> "You must provide a name using 'named'."];
    endif
    return ['parent -> parent_token, 'names -> names_clause];
  endverb

  verb _split_create_named_clause (this none this) owner: HACKER flags: "rxd"
    "Return {parent_part, names_part} while respecting quoted segments.";
    {input} = args;
    len = length(input);
    len >= 5 || return {input, ""};
    fn is_whitespace(ch)
      return index(" \t", ch) != 0;
    endfn
    in_quotes = false;
    named_start = 0;
    i = 1;
    while (i <= len)
      ch = input[i];
      if (ch == "\\")
        if (i < len)
          i = i + 2;
          continue;
        else
          break;
        endif
      elseif (ch == "\"")
        in_quotes = !in_quotes;
        i = i + 1;
        continue;
      endif
      if (!in_quotes && i + 4 <= len)
        candidate = input[i..i + 4];
        if (candidate:lowercase() == "named")
          before_ok = i == 1 || is_whitespace(input[i - 1]);
          after_pos = i + 5;
          after_ok = after_pos > len || is_whitespace(input[after_pos]);
          if (before_ok && after_ok)
            named_start = i;
            break;
          endif
        endif
      endif
      i = i + 1;
    endwhile
    if (!named_start)
      return {input:trim(), ""};
    endif
    parent_part = input[1..named_start - 1]:trim();
    remainder = input[named_start + 5..$];
    while (remainder && is_whitespace(remainder[1]))
      remainder = remainder[2..$];
    endwhile
    remainder = remainder:trim();
    return {parent_part, remainder};
  endverb

  verb _resolve_create_parent (this none this) owner: HACKER flags: "rxd"
    "Resolve parent token to an object using $match utilities.";
    {token} = args;
    result = $match:match_object(token, this);
    if (typeof(result) == ERR)
      return ['error -> toliteral(result)];
    endif
    return ['parent -> result];
  endverb

  verb _validate_create_parent (this none this) owner: HACKER flags: "rxd"
    {parent_obj} = args;
    typeof(parent_obj) != OBJ && return ['error -> "That parent reference is not an object."];
    !valid(parent_obj) && return ['error -> "That parent object no longer exists."];
    is_fertile = `parent_obj.fertile ! E_PROPNF => false';
    if (!is_fertile && !this.wizard && parent_obj.owner != this)
      return ['error -> "You do not have permission to create children of " + tostr(parent_obj) + "."];
    endif
    return ['ok -> true];
  endverb

  verb _parse_create_names (this none this) owner: HACKER flags: "rxd"
    "Parse name/alias specification into primary name and alias list.";
    {names_spec} = args;
    parsed = $str_proto:parse_name_aliases(names_spec);
    primary = parsed[1];
    aliases = parsed[2];
    if (!primary)
      return ['error -> "Primary object name cannot be blank."];
    endif
    return ['primary -> primary, 'aliases -> aliases];
  endverb

  verb _create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create the child object, apply naming, and move it into the builder's inventory.";
    caller == this || caller.wizard || raise(E_PERM);
    {parent_obj, primary_name, alias_list} = args;
    new_obj = create(parent_obj, this);
    new_obj.name = primary_name;
    new_obj.aliases = alias_list;
    move(new_obj, this);
    return new_obj;
  endverb

  verb _announce_create_success (this none this) owner: HACKER flags: "rxd"
    "Send a confirmation event for successful creation.";
    {new_obj, parent_obj, primary_name} = args;
    object_id = tostr(new_obj);
    parent_id = tostr(parent_obj);
    message = "Created " + primary_name + " (" + object_id + ") as a child of " + parent_id + ". It is now in your inventory.";
    this:inform_current($event:mk_info(this, message));
  endverb

  verb _emit_create_error (this none this) owner: HACKER flags: "rxd"
    {err_value} = args;
    message = this:_stringify_error(err_value);
    this:inform_current($event:mk_error(this, message));
  endverb

  verb _stringify_error (this none this) owner: HACKER flags: "rxd"
    {value} = args;
    if (typeof(value) == MAP && maphaskey(value, 'error))
      return this:_stringify_error(value['error]);
    endif
    if (typeof(value) == STR)
      return value;
    endif
    if (typeof(value) == LIST && length(value) >= 2 && typeof(value[2]) == STR)
      return value[2];
    endif
    typeof(value) == ERR && return toliteral(value);
    return toliteral(value);
  endverb

  verb test_parse_create_command (this none this) owner: HACKER flags: "rxd"
    spec = this:_parse_create_command("$thing named \"Sample Thing\"");
    maphaskey(spec, 'error) && raise(E_ASSERT("Parsing quoted name failed: " + toliteral(spec)));
    spec['parent] != "$thing" && raise(E_ASSERT("Parent token mismatch: " + toliteral(spec['parent])));
    spec['names] != "\"Sample Thing\"" && raise(E_ASSERT("Names clause mismatch: " + toliteral(spec['names])));
    spec = this:_parse_create_command("   ");
    !maphaskey(spec, 'error) && raise(E_ASSERT("Blank string should return error"));
    return true;
  endverb

  verb test_split_create_named_clause (this none this) owner: HACKER flags: "rxd"
    {parent_part, names_part} = this:_split_create_named_clause("$thing named \"The named one\"");
    parent_part != "$thing" && raise(E_ASSERT("Parent part parsing failed: " + toliteral(parent_part)));
    names_part != "\"The named one\"" && raise(E_ASSERT("Names part parsing failed: " + toliteral(names_part)));
    {parent_part, names_part} = this:_split_create_named_clause("$thing");
    parent_part != "$thing" && raise(E_ASSERT);
    names_part != "" && raise(E_ASSERT);
    {parent_part, names_part} = this:_split_create_named_clause("$thing named \"Alias with named keyword\"");
    parent_part != "$thing" && raise(E_ASSERT);
    names_part != "\"Alias with named keyword\"" && raise(E_ASSERT("Named keyword inside quotes should be ignored"));
    return true;
  endverb

  verb test_create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    new_obj = this:_create_child_object($thing, "Widget", {"gadget"});
    typeof(new_obj) == OBJ || raise(E_ASSERT("Returned value was not an object: " + toliteral(new_obj)));
    new_obj.owner != this && raise(E_ASSERT("Builder should own created object"));
    new_obj.location != this && raise(E_ASSERT("Created object should move into inventory"));
    new_obj.name != "Widget" && raise(E_ASSERT("Primary name was not applied: " + new_obj.name));
    new_obj.aliases != {"gadget"} && raise(E_ASSERT("Aliases not applied: " + toliteral(new_obj.aliases)));
    recycle(new_obj);
    return true;
  endverb
endobject