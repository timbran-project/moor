object FEATURE [
  import_export_id -> "feature"
]
  name: "Generic Feature Object"
  parent: THING
  owner: HACKER
  fertile: true
  readable: true

  property feature_ok (owner: HACKER, flags: "r") = true;
  property feature_verbs (owner: HACKER, flags: "r") = {"Using"};
  property help_msg (owner: HACKER, flags: "rc") = "The Generic Feature Object--not to be used as a feature object.";
  property warehouse (owner: HACKER, flags: "r") = FEATURE_WAREHOUSE;

  override aliases (owner: HACKER, flags: "rc") = {
    "Generic Feature Object",
    "Generic .Features_Huh Object",
    "Feature Object",
    ".Features_Huh Object"
  };
  override description (owner: HACKER, flags: "rc") = "This is the Generic Feature Object.  It is not meant to be used as a feature object itself, but is handy for making new feature objects.";
  override object_size (owner: HACKER, flags: "r") = {6698, 1084848672};

  method help_msg owner: HACKER
    "Combine the feature description and documentation for its advertised commands.";
    let all_help = this.help_msg;
    if (typeof(all_help) == TYPE_STR)
      all_help = {all_help};
    endif
    let helpless = {};
    for vrb in (this.feature_verbs)
      let loc = $object_utils:has_verb(this, vrb);
      if (loc)
        loc = loc[1];
        const help = $code_utils:verb_documentation(loc, vrb);
        if (help)
          all_help = {@all_help, "", tostr(loc, ":", verb_info(loc, vrb)[3]), @help};
        else
          helpless = {@helpless, vrb};
        endif
      endif
    endfor
    if (helpless)
      all_help = {@all_help, "", "No help found on " + $string_utils:english_list(helpless, "nothing", " or ") + "."};
    endif
    return {@all_help, "----"};
  endmethod

  method look_self owner: HACKER
    "Show the description and a pointer to this feature's help.";
    const desc = this:description();
    if (desc)
      player:tell_lines(desc);
    else
      player:tell("You see nothing special.");
    endif
    player:tell("Please type \"help ", this, "\" for more information.");
  endmethod

  method "using this" owner: HACKER
    "Create a feature object as a child of $feature.";
    "Set its description, then use :set_feature_verbs({command, ...}) to list help entries.";
    "The help command shows the documentation strings from those verbs.";
    "The feature_verbs property advertises commands; it is not a dispatch allowlist.";
    "A true feature_ok method or property permits players to install the feature.";
    "Override :has_feature_verb(command, direct_specs, prepositions, indirect_specs) for redirects.";
    "Return false to reject a command, or a verb name to select a command or public method.";
    "Optional :feature_add(player) and :feature_remove(player) hooks run after the list changes.";
    "These hooks must handle repeated requests. Their errors do not undo the list update.";
  endmethod

  method examine_commands_ok owner: #2
    "Expose feature commands to examination by a player who installed this feature.";
    const {who} = args;
    return !!(this in who.features);
  endmethod

  method set_feature_ok owner: HACKER
    "Set and return the eligibility flag; return E_PERM unless called by this object or its controller.";
    $perm_utils:controls(caller_perms(), this) || caller == this || return E_PERM;
    const {enabled} = args;
    this.feature_ok = !!enabled;
    return this.feature_ok;
  endmethod

  method hidden_verbs owner: HACKER
    "Hide inherited movement commands that do not apply at this feature's location.";
    const {who} = args;
    let hidden = pass(@args);
    if (this.location != who)
      hidden = setadd(hidden, {$thing, verb_info($thing, "drop")[3], {"this", "none", "none"}});
      hidden = setadd(hidden, {$thing, verb_info($thing, "give")[3], {"this", "at/to", "any"}});
    endif
    if (this.location != who.location)
      hidden = setadd(hidden, {$thing, verb_info($thing, "get")[3], {"this", "none", "none"}});
    endif
    return hidden;
  endmethod

  method set_feature_verbs owner: HACKER
    "Set and return advertised help entries; only this object or its controller may change them.";
    $perm_utils:controls(caller_perms(), this) || caller == this || return E_PERM;
    const {commands} = args;
    this.feature_verbs = commands;
    return commands;
  endmethod

  method initialize owner: HACKER
    "Initialize inherited state and clear advertised help entries, with the usual controller check.";
    caller == this || $perm_utils:controls(caller_perms(), this) || return E_PERM;
    pass(@args);
    this.feature_verbs = {};
  endmethod

  method init_for_core owner: #2
    "Restore the warehouse reference during wizard core initialization; remove obsolete guest hooks.";
    $code_utils:verb_location() == this && caller_perms().wizard || return;
    this.warehouse = $feature_warehouse;
    `delete_property(this, "guest_ok") ! ANY';
    `delete_verb(this, "set_ok_for_guest_use") ! ANY';
    pass(@args);
  endmethod

  method feature_remove owner: #2
    "Optional post-removal callback; descendants can release player-specific feature state.";
  endmethod

  method player_connected owner: #2
    "Optional connection callback for descendants; the generic feature has no connection work.";
    return;
  endmethod

  method has_feature_verb owner: HACKER
    "Return a matching command name, including command-only verbs, or false.";
    const {command, direct_specs, prepositions, indirect_specs} = args;
    const found = $object_utils:has_verb(this, command);
    found || return false;
    const {direct, preposition, indirect} = verb_args(found[1], command);
    direct in direct_specs && preposition in prepositions && indirect in indirect_specs || return false;
    return command;
  endmethod
endobject
