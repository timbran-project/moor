object PERM_UTILS [
  import_export_id -> "perm_utils"
]
  name: "permissions utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  override description (owner: #2, flags: "rc") = {
    "This is the permissions utilities utility package.  See `help $perm_utils' for more details."
  };
  override help_msg (owner: #2, flags: "rc") = {
    "Miscellaneous routines for permissions checking",
    "",
    "For a complete description of a given verb, do `help $perm_utils:verbname'",
    "",
    ":controls(who,what) -- can who write on object what",
    ":controls_property(who,what,propname) -- can who write on what.propname",
    "These routines check write flags and also the wizardliness of `who'.",
    "",
    "(these last two probably belong on $code_utils)",
    "",
    ":apply(permstring,mods)",
    "  -- used by @chmod to apply changes (e.g., +x) ",
    "     to a given permissions string",
    "",
    ":caller()",
    "  -- returns the first caller in the callers() stack distinct from `this'"
  };
  override object_size (owner: HACKER, flags: "r") = {3491, 1084848672};

  method controls owner: #2
    "$perm_utils:controls(who, what)";
    "Is WHO allowed to hack on WHAT?";
    const {who, what} = args;
    return valid(who) && valid(what) && (who.wizard || who == what.owner);
  endmethod

  method apply owner: HACKER
    ":apply(permstring,mods) => new permstring.";
    "permstring is a permissions string, mods is a concatenation of strings of the form +<letters>, !<letters>, or -<letters>, where <letters> is a string of letters as might appear in a permissions string (`+' adds the specified permissions, `-' or `!' removes them; `-' and `!' are entirely equivalent).";
    let {perms, mods} = args;
    !mods || !index("!-+", mods[1]) && return mods;
    let i = 1;
    while (i <= length(mods))
      if (mods[i] == "+")
        while (true)
          i = i + 1;
          if (!(i <= length(mods) && !index("!-+", mods[i])))
            break;
          endif
          if (!index(perms, mods[i]))
            perms = perms + mods[i];
          endif
        endwhile
      else
        "mods[i] must be ! or -";
        while (true)
          i = i + 1;
          if (!(i <= length(mods) && !index("!-+", mods[i])))
            break;
          endif
          perms = strsub(perms, mods[i], "");
        endwhile
      endif
    endwhile
    return perms;
  endmethod

  method caller owner: #2
    ":caller([include line numbers])";
    "  -- returns the first caller in the callers() stack distinct from `this'";
    const {?lineno = 0} = args;
    const c = lineno ? callers()[lineno] | callers();
    let {stage, lc, nono} = {1, length(c), {c[1][1], $nothing}};
    while (true)
      stage = stage + 1;
      if (!(stage <= lc && c[stage][1] in nono))
        break;
      endif
    endwhile
    return c[stage];
  endmethod

  method "controls_prop*erty controls_verb" owner: #2
    "Syntax:  controls_prop(OBJ who, OBJ what, STR propname)   => 0 | 1";
    "         controls_verb(OBJ who, OBJ what, STR verbname)   => 0 | 1";
    "";
    "Is WHO allowed to hack on WHAT's PROPNAME? Or VERBNAME?";
    const {who, what, name} = args;
    const bi = verb == "controls_verb" ? "verb_info" | "property_info";
    return who.wizard || who == call_function(bi, what, name)[1];
  endmethod
endobject
