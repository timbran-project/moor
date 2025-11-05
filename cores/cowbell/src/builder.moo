object BUILDER
  name: "Generic Builder"
  parent: PLAYER
  location: FIRST_ROOM
  owner: HACKER
  programmer: true
  readable: true

  override description = "Generic builder character prototype. Builders can create and modify basic objects and rooms. Inherits from player with building permissions.";
  override import_export_id = "builder";

  verb "@create" (any named any) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr || !iobjstr)
      raise(E_INVARG, "Usage: @create <parent> named <name[:aliases]>");
    endif
    try
      parent_obj = $match:match_object(dobjstr, this);
      typeof(parent_obj) != OBJ && raise(E_INVARG, "That parent reference is not an object.");
      !valid(parent_obj) && raise(E_INVARG, "That parent object no longer exists.");
      is_fertile = `parent_obj.fertile ! E_PROPNF => false';
      if (!is_fertile && !this.wizard && parent_obj.owner != this)
        raise(E_PERM, "You do not have permission to create children of " + tostr(parent_obj) + ".");
      endif
      parsed = $str_proto:parse_name_aliases(iobjstr);
      primary_name = parsed[1];
      alias_list = parsed[2];
      !primary_name && raise(E_INVARG, "Primary object name cannot be blank.");
      new_obj = this:_create_child_object(parent_obj, primary_name, alias_list);
      object_id = tostr(new_obj);
      parent_id = tostr(parent_obj);
      message = "Created \"" + primary_name + "\" (" + object_id + ") as a child of " + parent_id + ".";
      if (alias_list)
        alias_str = alias_list:join(", ");
        message = message + " Aliases: " + alias_str + ".";
      endif
      message = message + " It is now in your inventory.";
      this:inform_current($event:mk_info(this, message));
      return new_obj;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
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

  verb "@recycle @destroy" (any none none) owner: ARCH_WIZARD flags: "rd"
    caller == this || raise(E_PERM);
    set_task_perms(caller_perms());
    if (!dobjstr)
      raise(E_INVARG, "Usage: @recycle <object>");
    endif
    try
      target_obj = $match:match_object(dobjstr, this);
      typeof(target_obj) != OBJ && raise(E_INVARG, "That reference is not an object.");
      !valid(target_obj) && raise(E_INVARG, "That object no longer exists.");
      if (!this.wizard && target_obj.owner != this)
        raise(E_PERM, "You do not have permission to recycle " + tostr(target_obj) + ".");
      endif
      obj_name = target_obj.name;
      obj_id = tostr(target_obj);
      target_obj:destroy();
      this:inform_current($event:mk_info(this, "Recycled \"" + obj_name + "\" (" + obj_id + ")."));
      return 1;
    except e (ANY)
      message = length(e) >= 2 && typeof(e[2]) == STR ? e[2] | toliteral(e);
      this:inform_current($event:mk_error(this, message));
      return 0;
    endtry
  endverb

  verb test_recycle_object (this none this) owner: ARCH_WIZARD flags: "rxd"
    test_obj = this:_create_child_object($thing, "TestWidget", {"testgadget"});
    typeof(test_obj) == OBJ || raise(E_ASSERT("Setup: Failed to create test object"));
    obj_name = test_obj.name;
    obj_id = tostr(test_obj);
    test_obj:destroy();
    valid(test_obj) && raise(E_ASSERT("Object should be invalid after destruction"));
    return true;
  endverb
endobject