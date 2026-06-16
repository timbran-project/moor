object PROPERTY
  name: "Property"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Delegate object for property metadata flyweights. Provides access to property information and operations. Slots: owner_obj, location, name, owner, perms, is_clear";
  override import_export_hierarchy = {"types"};
  override import_export_id = "property";

  method owner owner: ARCH_WIZARD
    "Return the owner of the property (user who created it)";
    return this.owner;
  endmethod

  method location owner: ARCH_WIZARD
    "Return the object where property is defined";
    return this.location;
  endmethod

  method name owner: ARCH_WIZARD
    "Return the property name";
    return this.name;
  endmethod

  method perms owner: ARCH_WIZARD
    "Return the property permissions (rwcd)";
    return this.perms;
  endmethod

  method is_clear owner: ARCH_WIZARD
    "Return true if property is unset on this object";
    return this.is_clear;
  endmethod

  method value_string owner: ARCH_WIZARD
    "Get a string representation of the property's value";
    set_task_perms(caller_perms());
    if (this:is_clear())
      return "(clear)";
    endif
    try
      val = this:location().(this:name());
      return toliteral(val);
    except (ANY)
      return "(error reading property)";
    endtry
  endmethod

  method set_perms owner: ARCH_WIZARD
    "Set property permissions. Args: {new_owner, perms_string}";
    "Sets owner and permission flags (r, w, c)";
    set_task_perms(caller_perms());
    {new_owner, perms_string} = args;
    set_property_info(this:location(), this:name(), {new_owner, perms_string});
  endmethod

  method test_property_metadata owner: HACKER
    "Test that property metadata flyweight returns expected values";
    "Get metadata for a known property";
    metadata = $prog_utils:get_property_metadata($root, 'import_export_id);
    typeof(metadata) == TYPE_FLYWEIGHT || raise(E_ASSERT("Invalid metadata -- expected flyweight got " + toliteral(metadata)));
    metadata.location == $root || raise(E_ASSERT("location does not match"));
    metadata.name == 'import_export_id || raise(E_ASSERT("name does not match"));
    valid(metadata.owner) || raise(E_ASSERT("owner is not valid"));
    typeof(metadata.perms) == TYPE_STR || raise(E_ASSERT("Perms is not a string"));
    "Check that is_clear is a boolean";
    if (typeof(metadata.is_clear) != TYPE_OBJ && typeof(metadata.is_clear) != TYPE_INT)
      "OBJ is false, INT is true in mooR's type system sometimes";
      if (metadata.is_clear != true && metadata.is_clear != false)
        raise(E_ASSERT("mismatching metadata"));
      endif
    endif
    return true;
  endmethod
endobject
