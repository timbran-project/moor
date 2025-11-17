// Property metadata and operations
object PROPERTY
  name: "Property"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Delegate object for property metadata flyweights. Provides access to property information and operations. Slots: owner_obj, location, name, owner, perms, is_clear";
  override import_export_hierarchy = {"types"};
  override import_export_id = "property";

  verb owner (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the owner of the property (user who created it)";
    return this.owner;
  endverb

  verb location (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the object where property is defined";
    return this.location;
  endverb

  verb name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the property name";
    return this.name;
  endverb

  verb perms (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the property permissions (rwcd)";
    return this.perms;
  endverb

  verb is_clear (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return true if property is unset on this object";
    return this.is_clear;
  endverb

  verb value_string (this none this) owner: ARCH_WIZARD flags: "rxd"
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
  endverb

  verb set_perms (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set property permissions. Args: {new_owner, perms_string}";
    "Sets owner and permission flags (r, w, c)";
    set_task_perms(caller_perms());
    {new_owner, perms_string} = args;
    set_property_info(this:location(), this:name(), {new_owner, perms_string});
  endverb

  verb test_property_metadata (this none this) owner: HACKER flags: "rxd"
    "Test that property metadata flyweight returns expected values";
    "Get metadata for a known property";
    metadata = $prog_utils:get_property_metadata($root, 'import_export_id);
    typeof(metadata) == FLYWEIGHT || raise(E_ASSERT("Invalid metadata -- expected flyweight got " + toliteral(metadata)));
    metadata.location == $root || raise(E_ASSERT("location does not match"));
    metadata.name == 'import_export_id || raise(E_ASSERT("name does not match"));
    valid(metadata.owner) || raise(E_ASSERT("owner is not valid"));
    typeof(metadata.perms) == STR || raise(E_ASSERT("Perms is not a string"));
    "Check that is_clear is a boolean";
    if (typeof(metadata.is_clear) != OBJ && typeof(metadata.is_clear) != INT)
      "OBJ is false, INT is true in mooR's type system sometimes";
      if (metadata.is_clear != true && metadata.is_clear != false)
        raise(E_ASSERT("mismatching metadata"));
      endif
    endif
    return true;
  endverb

endobject
