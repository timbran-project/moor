object VERB [
  import_export_id -> "verb",
  import_export_hierarchy -> {"types"}
]
  name: "Verb"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Delegate object for verb metadata flyweights. Provides access to verb information and operations. Slots: owner_obj, location, name, verb_owner, flags, dobj, prep, iobj";

  method owner owner: ARCH_WIZARD
    "Return the owner of the verb";
    return this.owner_obj;
  endmethod

  method location owner: ARCH_WIZARD
    "Return the object where verb is defined";
    return this.location;
  endmethod

  method name owner: ARCH_WIZARD
    "Return the verb name";
    return this.name;
  endmethod

  method verb_owner owner: ARCH_WIZARD
    "Return the owner of the verb (the user/wizard who created it)";
    return this.verb_owner;
  endmethod

  method flags owner: ARCH_WIZARD
    "Return the verb flags (rwxd)";
    return this.flags;
  endmethod

  method dobj owner: ARCH_WIZARD
    "Return the direct object specification";
    return this.dobj;
  endmethod

  method prep owner: ARCH_WIZARD
    "Return the preposition specification";
    return this.prep;
  endmethod

  method iobj owner: ARCH_WIZARD
    "Return the indirect object specification";
    return this.iobj;
  endmethod

  method index owner: ARCH_WIZARD
    "Return the verb's index position in the object's verb list";
    return this.index;
  endmethod

  method args_spec owner: ARCH_WIZARD
    "Return formatted args specification (dobj prep iobj)";
    return this:dobj() + " " + this:prep() + " " + this:iobj();
  endmethod

  method code owner: ARCH_WIZARD
    "Get the verb's code as a list of lines";
    set_task_perms(caller_perms());
    return verb_code(this:location(), this:index(), false, true);
  endmethod

  method set_perms owner: ARCH_WIZARD
    "Set verb permissions. Args: {new_owner, perms_string}";
    "Sets owner and permission flags (r, w, x, d)";
    set_task_perms(caller_perms());
    {new_owner, perms_string} = args;
    set_verb_info(this:location(), this:index(), {new_owner, perms_string, this:name()});
  endmethod

  method test_verb_metadata owner: HACKER
    "Test that verb metadata flyweight returns expected values";
    "Get metadata for a known verb";
    metadata = $prog_utils:get_verb_metadata($root, 'description);
    typeof(metadata) == TYPE_FLYWEIGHT || raise(E_ASSERT("Invalid metadata -- expected flyweight got " + toliteral(metadata)));
    metadata.location == $root || raise(E_ASSERT("location does not match"));
    metadata.name == 'description || raise(E_ASSERT("name does not match"));
    valid(metadata.verb_owner) || raise(E_ASSERT("verb_owner is not valid"));
    typeof(metadata.flags) == TYPE_STR || raise(E_ASSERT("flags is not a string"));
    "Check args_spec returns a string";
    args_spec = metadata:args_spec();
    typeof(args_spec) == TYPE_STR || raise(E_ASSERT("args_spec is not a string"));
    return true;
  endmethod
endobject
