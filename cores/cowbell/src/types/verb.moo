object VERB
  name: "Verb"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Delegate object for verb metadata flyweights. Provides access to verb information and operations. Slots: owner_obj, location, name, verb_owner, flags, dobj, prep, iobj";
  override import_export_hierarchy = {"types"};
  override import_export_id = "verb";

  verb owner (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the owner of the verb";
    return this.owner_obj;
  endverb

  verb location (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the object where verb is defined";
    return this.location;
  endverb

  verb name (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the verb name";
    return this.name;
  endverb

  verb verb_owner (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the owner of the verb (the user/wizard who created it)";
    return this.verb_owner;
  endverb

  verb flags (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the verb flags (rwxd)";
    return this.flags;
  endverb

  verb dobj (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the direct object specification";
    return this.dobj;
  endverb

  verb prep (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the preposition specification";
    return this.prep;
  endverb

  verb iobj (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the indirect object specification";
    return this.iobj;
  endverb

  verb index (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return the verb's index position in the object's verb list";
    return this.index;
  endverb

  verb args_spec (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return formatted args specification (dobj prep iobj)";
    return this:dobj() + " " + this:prep() + " " + this:iobj();
  endverb

  verb code (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get the verb's code as a list of lines";
    set_task_perms(caller_perms());
    code_lines = `verb_code(this:location(), this:index(), false, true) ! ANY => {}';
    if (typeof(code_lines) == TYPE_ERR)
      return {};
    endif
    return code_lines;
  endverb

  verb set_perms (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set verb permissions. Args: {new_owner, perms_string}";
    "Sets owner and permission flags (r, w, x, d)";
    set_task_perms(caller_perms());
    {new_owner, perms_string} = args;
    set_verb_info(this:location(), this:index(), {new_owner, perms_string, this:name()});
  endverb

  verb test_verb_metadata (this none this) owner: HACKER flags: "rxd"
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
  endverb
endobject