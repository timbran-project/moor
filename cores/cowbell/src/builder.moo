object BUILDER
  name: "Generic Builder"
  parent: PLAYER
  location: FIRST_ROOM
  owner: HACKER
  programmer: true
  readable: true

  override description = "Generic builder character prototype. Builders can create and modify basic objects and rooms. Inherits from player with building permissions.";
  override import_export_id = "builder";

  verb "@create" (any named any) owner: ARCH_WIZARD flags: "rxd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr || !iobjstr)
      this:_emit_create_error("Usage: @create <parent> named <name[:aliases]>");
      return 0;
    endif
    parent_result = this:_resolve_create_parent(dobjstr);
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
    name_info = this:_parse_create_names(iobjstr);
    if (maphaskey(name_info, 'error))
      this:_emit_create_error(name_info['error]);
      return 0;
    endif
    {primary_name, alias_list} = {name_info['primary], name_info['aliases]};
    new_obj = this:_create_child_object(parent_obj, primary_name, alias_list);
    this:_announce_create_success(new_obj, parent_obj, primary_name, alias_list);
    return new_obj;
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
    set_task_perms(this);
    new_obj = parent_obj:create();
    new_obj:set_name_aliases(primary_name, alias_list);
    new_obj:moveto(this);
    return new_obj;
  endverb

  verb _announce_create_success (this none this) owner: HACKER flags: "rxd"
    "Send a confirmation event for successful creation.";
    {new_obj, parent_obj, primary_name, alias_list} = args;
    object_id = tostr(new_obj);
    parent_id = tostr(parent_obj);
    message = "Created \"" + primary_name + "\" (" + object_id + ") as a child of " + parent_id + ".";
    if (alias_list)
      alias_str = alias_list:join(", ");
      message = message + " Aliases: " + alias_str + ".";
    endif
    message = message + " It is now in your inventory.";
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

  verb test_create_child_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    new_obj = this:_create_child_object($thing, "Widget", {"gadget"});
    typeof(new_obj) == OBJ || raise(E_ASSERT("Returned value was not an object: " + toliteral(new_obj)));
    new_obj.owner != this && raise(E_ASSERT("Builder should own created object"));
    new_obj.location != this && raise(E_ASSERT("Created object should move into inventory"));
    new_obj.name != "Widget" && raise(E_ASSERT("Primary name was not applied: " + new_obj.name));
    new_obj.aliases != {"gadget"} && raise(E_ASSERT("Aliases not applied: " + toliteral(new_obj.aliases)));
    new_obj:destroy();
    return true;
  endverb
endobject