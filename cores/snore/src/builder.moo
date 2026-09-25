object BUILDER [
  import_export_id -> "builder"
]
  name: "generic builder"
  parent: DEFAULT_PLAYER
  owner: #2
  fertile: true
  readable: true

  property build_options (owner: #2, flags: "rc") = [];

  override aliases (owner: #2, flags: "rc") = {"generic builder"};
  override description (owner: #2, flags: "rc") = "You see a player who should type '@describe me as ...'.";
  override features (owner: HACKER, flags: "r") = {PASTING_FEATURE, STAGE_TALK, UTILITY_FEATURE, BUILDER_FEATURE};
  override help (owner: #2, flags: "rc") = BUILDER_HELP;
  override object_size (owner: HACKER, flags: "r") = {36256, 1084848672};

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    if (caller_perms().wizard)
      if (this == $builder)
        this.build_options = [];
      else
        clear_property(this, "build_options");
      endif
      return pass(@args);
    endif
  endmethod

  method _messagify owner: #2
    "Given any of several formats people are likely to use for a @message";
    "property, return the canonical form (\"foobar_msg\").";
    let name = args[1];
    if (name[1] == "@")
      name = name[2..$];
    endif
    if (length(name) < 4 || name[$ - 3..$] != "_msg")
      name = name + "_msg";
    endif
    return name;
  endmethod

  method classes_2 owner: #2
    "Print the selected class tree. Traversal can yield between descendants.";
    let {root, indent, members, printed} = args;
    if (root in members)
      player:tell(indent, root.name, " (", root, ")");
    else
      player:tell(indent, "<", root.name, " (", root, ")>");
    endif
    printed = setremove(printed, root);
    indent = indent + "  ";
    set_task_perms(caller_perms());
    for c in ($list_utils:sort_suspended(2, $set_utils:intersection(children(root), printed)))
      $command_utils:suspend_if_needed(10);
      this:classes_2(c, indent, members, printed);
    endfor
  endmethod

  method _create owner: #2
    "Create a UUID object through the recycler with the caller's permissions.";
    set_task_perms(caller_perms());
    return $recycler:_create(@args);
  endmethod

  method _recycle owner: #2
    "Recycle an object through the recycler with the caller's permissions.";
    set_task_perms(caller_perms());
    return $recycler:_recycle(@args);
  endmethod

  method build_option owner: #2
    ":build_option(name)";
    "Returns the value of the specified builder option";
    caller == this || $perm_utils:controls(caller_perms(), this) && return $build_options:get(this.build_options, args[1]);
    return E_PERM;
  endmethod

  method set_build_option owner: #2
    ":set_build_option(oname,value)";
    "Changes the value of the named option.";
    "Returns a string error if something goes wrong.";
    !(caller == this || $perm_utils:controls(caller_perms(), this)) && return tostr(E_PERM);
    "...this is kludgy, but it saves me from writing the same verb n times.";
    "...there's got to be a better way to do this...";
    verb[1..4] = "";
    const foo_options = verb + "s";
    "...";
    const s = #0.(foo_options):set(this.(foo_options), @args);
    typeof(s) == TYPE_STR && return s;
    s == this.(foo_options) && return 0;
    this.(foo_options) = s;
    return 1;
  endmethod
endobject
